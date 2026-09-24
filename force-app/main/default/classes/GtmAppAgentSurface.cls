/**
 * GUS surface for the app-wide utility bar item (chatOnApp). Contract:
 * docs/architecture/gus-utility-bar-host.md.
 *
 * `with sharing` from the start so every tool added later inherits sharing,
 * exactly like GtmReadoutAgentSurface. It is called only from
 * GtmAgentProxyController, so it has no permission-set entry.
 *
 * No DML, no callouts, never throws. With no registered tools the model is
 * told it has none and must not claim any action. Tools attach through the
 * GtmAppTool interface and one line in registeredTools().
 */
public with sharing class GtmAppAgentSurface implements GtmAgentToolSurface {

    static final Integer MAX_TOKENS = 1024;
    static final String  NO_TOOLS_ERROR = '{"error":"no tools available"}';
    static final Pattern NAME_PATTERN = Pattern.compile('^[A-Za-z0-9_]{1,80}$');
    static final Pattern RECORD_ID_PATTERN = Pattern.compile('^[A-Za-z0-9]{15}$|^[A-Za-z0-9]{18}$');

    /** Test hook: when non-null, returned by registeredTools() instead. */
    @TestVisible
    private static List<GtmAppTool> testTools;

    private final Map<String, Object> ctx;
    private final List<GtmAppTool> tools;

    public GtmAppAgentSurface(Map<String, Object> ctx) {
        this(ctx, registeredTools());
    }

    @TestVisible
    private GtmAppAgentSurface(Map<String, Object> ctx, List<GtmAppTool> tools) {
        this.ctx = ctx == null ? new Map<String, Object>() : ctx;
        this.tools = tools == null ? new List<GtmAppTool>() : tools;
    }

    /** Follow-up tool issues add one line each here. */
    private static List<GtmAppTool> registeredTools() {
        if (testTools != null) return testTools;
        List<GtmAppTool> registered = new List<GtmAppTool>();
        registered.add(new GtmStageFilterAppTool());
        return registered;
    }

    // ── GtmAgentToolSurface ──────────────────────────────────────────────────

    public Integer maxTokens() { return MAX_TOKENS; }

    public List<Object> toolDefinitions() {
        List<Object> defs = new List<Object>();
        Set<String> seen = new Set<String>();
        for (GtmAppTool t : tools) {
            List<Object> toolDefs = t.definitions();
            if (toolDefs == null) continue;
            for (Object d : toolDefs) {
                Map<String, Object> def = (Map<String, Object>) d;
                String name = (String) def.get('name');
                if (name == null || seen.contains(name)) continue;
                seen.add(name);
                defs.add(def);
            }
        }
        return defs;
    }

    public String executeTool(String toolName, Map<String, Object> input,
                              Map<String, Object> accumulatedChanges) {
        try {
            if (tools.isEmpty()) return NO_TOOLS_ERROR;
            Map<String, Object> safeInput = input == null ? new Map<String, Object>() : input;
            Map<String, Object> bag = accumulatedChanges == null ? new Map<String, Object>() : accumulatedChanges;
            for (GtmAppTool t : tools) {
                if (t.handles(toolName)) {
                    return t.execute(toolName, safeInput, bag);
                }
            }
            return '{"error":"unknown tool"}';
        } catch (Exception e) {
            return JSON.serialize(new Map<String, Object>{
                'error' => 'Tool execution failed: ' + e.getMessage()
            });
        }
    }

    public String systemPrompt(String toneClause) {
        String prompt = 'You are GUS, the Go-To-Market Utility Sidekick for the Publicis Sapient GTM Offerings ' +
            'Salesforce app, used by internal reps. Answer questions about how to use the app and about the ' +
            'page the rep is on. Be concise. If asked to do something you cannot, say so plainly and suggest ' +
            'the manual path.\n\n' +
            pageLine() + '\n\n';
        if (toolDefinitions().isEmpty()) {
            prompt += 'You currently have NO tools: you cannot read data, change anything, or take any action, ' +
                'and must not claim to.\n\n';
        } else {
            prompt += 'You may only take the actions your tools provide.\n';
            for (GtmAppTool t : tools) {
                String fragment = t.promptFragment();
                if (String.isNotBlank(fragment)) prompt += fragment + '\n';
            }
            prompt += '\n';
        }
        return prompt + 'TONE: ' + toneClause;
    }

    private String pageLine() {
        List<String> parts = new List<String>();
        addPart(parts, 'type', 'pageType');
        addPart(parts, 'tab', 'tabApiName');
        addPart(parts, 'object', 'objectApiName');
        addPart(parts, 'record', 'recordId');
        return parts.isEmpty() ? 'Current page: unknown' : 'Current page: ' + String.join(parts, ', ');
    }

    private void addPart(List<String> parts, String label, String key) {
        Object v = ctx.get(key);
        if (v instanceof String) parts.add(label + '=' + (String) v);
    }

    // ── Page context ─────────────────────────────────────────────────────────

    /**
     * Parses the client-supplied page context defensively and keeps only the
     * four allow-listed keys whose values match a strict pattern. Anything
     * else is dropped silently. Never throws.
     */
    @TestVisible
    public static Map<String, Object> sanitizeContext(String pageContextJson) {
        Map<String, Object> clean = new Map<String, Object>();
        if (String.isBlank(pageContextJson)) return clean;
        Map<String, Object> raw;
        try {
            Object parsed = JSON.deserializeUntyped(pageContextJson);
            if (!(parsed instanceof Map<String, Object>)) return clean;
            raw = (Map<String, Object>) parsed;
        } catch (Exception e) {
            return clean;
        }
        for (String key : new List<String>{ 'pageType', 'tabApiName', 'objectApiName' }) {
            Object v = raw.get(key);
            if (v instanceof String && NAME_PATTERN.matcher((String) v).matches()) {
                clean.put(key, v);
            }
        }
        Object rid = raw.get('recordId');
        if (rid instanceof String && RECORD_ID_PATTERN.matcher((String) rid).matches()) {
            clean.put('recordId', rid);
        }
        return clean;
    }

    // ── History bound ────────────────────────────────────────────────────────

    /**
     * Keeps the last `maxTurns` turns. A turn starts at a role='user' message
     * whose content is a String (rep text, not a tool_result list), so cutting
     * only there never separates a tool_use from its tool_result. Blank or
     * unparseable input, or nothing to trim, is returned unchanged. Never
     * throws.
     */
    public static String trimHistory(String historyJson, Integer maxTurns) {
        if (String.isBlank(historyJson) || maxTurns == null || maxTurns < 1) return historyJson;
        try {
            Object parsed = JSON.deserializeUntyped(historyJson);
            if (!(parsed instanceof List<Object>)) return historyJson;
            List<Object> history = (List<Object>) parsed;
            List<Integer> starts = new List<Integer>();
            for (Integer i = 0; i < history.size(); i++) {
                if (!(history[i] instanceof Map<String, Object>)) continue;
                Map<String, Object> turn = (Map<String, Object>) history[i];
                if ('user'.equals(turn.get('role')) && turn.get('content') instanceof String) {
                    starts.add(i);
                }
            }
            if (starts.size() <= maxTurns) return historyJson;
            Integer cut = starts[starts.size() - maxTurns];
            List<Object> kept = new List<Object>();
            for (Integer i = cut; i < history.size(); i++) kept.add(history[i]);
            return JSON.serialize(kept);
        } catch (Exception e) {
            return historyJson;
        }
    }
}
