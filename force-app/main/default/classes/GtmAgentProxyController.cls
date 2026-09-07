/**
 * Claude API proxy for the GTM Configurator AI assistant.
 *
 * Simulates what the Agentforce GTM_Configurator_Assistant agent will do once
 * Agentforce is provisioned: reads page state and applies config deltas via
 * tool use. When Agentforce is live, replace <c-ma-agent-chat> in
 * maConfigCustomize.html with <einstein-copilot-chat> and retire this class.
 *
 * Callout/DML ordering: all HTTP callouts happen before any DML. Config changes
 * are NOT published as GTM_Config_Update__e here — they are returned as a JSON
 * delta to the LWC, which dispatches them directly via _applyDelta(). The
 * Agentforce path uses the platform event (GtmAgentApplyConfigUpdate publishes it
 * and the empApi subscription in maConfigCustomize picks it up).
 *
 * TWO SCREENS, ONE LOOP. GUS now also sits on the readout editor
 * (gtmReadoutReview). That is a different job with different tools and a
 * different prompt, but it is NOT a second tool-use loop: runLoop() below is
 * the only one, and each screen supplies a GtmAgentToolSurface. chat() is the
 * configurator's entry point, chatOnReadout() the readout editor's.
 *
 * SHARING. This class stays `without sharing`, which is correct for the
 * configurator's page state and wrong for anything that reads or writes client
 * deal content. Apex resolves sharing per executing class, so the readout
 * surface (GtmReadoutAgentSurface) is `with sharing` and gets sharing back
 * despite being called from here — and it does not lean on that either: it
 * asserts the running user's record access on the readout explicitly, on every
 * call, before it reads or proposes anything. See its header.
 */
public without sharing class GtmAgentProxyController {

    static final String ANTHROPIC_URL    = 'https://api.anthropic.com/v1/messages';
    static final String DEFAULT_MODEL    = 'claude-sonnet-5';
    static final String ANTHROPIC_VER    = '2023-06-01';
    static final Integer MAX_TOKENS      = 1024;
    static final Integer MAX_TOOL_ROUNDS = 5;

    /**
     * Was a `static final String` constant. Now a method because the trailing
     * TONE line is sourced from GtmAgentTone.clause(), which reads
     * GTM_Page_Content__c via SOQL — not something a compile-time constant can
     * do. Everything above TONE is unchanged, fixed developer-authored text.
     */
    private static String configSystemPrompt() {
        return 'You are the GTM Configurator Assistant, embedded in a Publicis Sapient sales tool. ' +
        'You help PS sales reps personalize Migration Accelerator client presentations by reading ' +
        'the current page state and applying precise field updates based on what the rep tells you ' +
        'about their prospect.\n\n' +
        'TOOLS:\n' +
        '• get_gtm_config_state — reads current page values and the list of valid industry keys. ' +
        'Call this at the start of every conversation and again if the rep says the page changed.\n' +
        '• apply_gtm_config_update — updates one or more fields. Pass only the fields to change.\n\n' +
        'RULES:\n' +
        '1. Always call get_gtm_config_state before suggesting or applying any change.\n' +
        '2. The industry field must match one of the availableIndustries keys exactly. If the rep ' +
        'gives plain English, map to the closest key; if nothing is close, list options and ask.\n' +
        '3. After a successful apply, confirm which fields changed in plain English.\n' +
        '4. If apply returns success=false, quote the errorMessage and ask for a corrected value.\n' +
        '5. Stay in scope — only personalize the configurator page. Redirect other questions politely.\n\n' +
        'TONE: ' + GtmAgentTone.clause();
    }

    // ── Tool definitions ──────────────────────────────────────────────────────

    static final Map<String,Object> TOOL_GET_STATE = new Map<String,Object>{
        'name'        => 'get_gtm_config_state',
        'description' => 'Read the current GTM Configurator page state. Call before any change.',
        'input_schema' => new Map<String,Object>{
            'type'       => 'object',
            'properties' => new Map<String,Object>{
                'config_id' => new Map<String,Object>{
                    'type'        => 'string',
                    'description' => 'GTM_Saved_Configuration__c Id; omit or leave blank for unsaved sessions'
                }
            },
            'required' => new List<String>()
        }
    };

    static final Map<String,Object> TOOL_APPLY_UPDATE = new Map<String,Object>{
        'name'        => 'apply_gtm_config_update',
        'description' => 'Apply a partial config update. Include only the fields to change.',
        'input_schema' => new Map<String,Object>{
            'type'       => 'object',
            'properties' => new Map<String,Object>{
                'updates_json' => new Map<String,Object>{
                    'type'        => 'string',
                    'description' => 'JSON object. Valid keys: company (≤120 chars), industry (must match an availableIndustries key), accent (#RRGGBB hex), objectsCount (0-999999), depsCount (0-999999), healthScore (0-100), note (≤500 chars)'
                }
            },
            'required' => new List<String>{ 'updates_json' }
        }
    };

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Configurator entry point. Unchanged contract.
     *
     * @param sessionToken  LWC session token (routes empApi events; passed through for logging only in proxy mode)
     * @param configId      GTM_Saved_Configuration__c Id — blank for unsaved sessions
     * @param userMessage   Latest message from the rep
     * @param historyJson   JSON-serialised conversation history from prior turns
     * @return              JSON: { text, historyJson, changes }
     *                      changes: flat map of field→value for the LWC to apply directly
     */
    @AuraEnabled
    public static String chat(String sessionToken, String configId,
                              String userMessage, String historyJson) {
        return runLoop(new ConfigSurface(configId), userMessage, historyJson);
    }

    /**
     * Readout-editor entry point: GUS on gtmReadoutReview.
     *
     * The readout Id is a PARAMETER OF THE SESSION, not of any tool. The model
     * is never given a readout Id to pass, and no tool accepts one, so there is
     * no shape of tool call that can reach a different readout — the blast
     * radius of a confused or prompt-injected model is the one record the rep
     * already has open. Access to that record is asserted here, before the
     * first callout, and again inside every tool.
     *
     * workingDraft is the rep's unsaved editor content. Edits are computed
     * against it and returned as `changes.draftContent` for the LWC to drop
     * back into the editor — nothing is written to the record. The rep still
     * clicks Save Draft, and that save still goes through
     * GtmReadoutController.saveDraftContent with all its state checks. That is
     * both the human-in-the-loop gate and what keeps this transaction free of
     * DML between callouts.
     *
     * @return JSON: { text, historyJson, changes } where changes may contain
     *         draftContent (the proposed full readout HTML)
     */
    @AuraEnabled
    public static String chatOnReadout(String readoutId, String workingDraft,
                                       String userMessage, String historyJson) {
        if (String.isBlank(readoutId)) {
            throw new AuraHandledException('A readout Id is required.');
        }
        // Fail closed before we spend a callout on a record the rep cannot see.
        GtmReadoutAgentContext.assertReadable(readoutId);
        return runLoop(new GtmReadoutAgentSurface(readoutId, workingDraft), userMessage, historyJson);
    }

    // ── The loop (one, shared) ────────────────────────────────────────────────

    /**
     * The Claude tool-use loop. Callouts only; the surface's executeTool does
     * no DML, so every HTTP round trip in this method happens before the
     * transaction's first (client-side, later) write.
     */
    private static String runLoop(GtmAgentToolSurface surface, String userMessage, String historyJson) {
        String apiKey = getApiKey();
        if (String.isBlank(apiKey)) {
            throw new AuraHandledException(
                'Claude API key not configured. Go to Setup → Custom Settings → GTM Agent Settings → Manage → New, and paste your Anthropic API key into the Claude API Key field.'
            );
        }

        List<Object> history = parseHistory(historyJson);
        history.add(new Map<String,Object>{ 'role' => 'user', 'content' => userMessage });

        String model    = getModel();
        String finalText = '';
        Map<String,Object> accumulatedChanges = new Map<String,Object>();
        Integer rounds  = 0;

        while (rounds < MAX_TOOL_ROUNDS) {
            rounds++;
            Map<String,Object> response = callClaude(history, apiKey, model, surface);
            String stopReason           = (String) response.get('stop_reason');
            List<Object> content        = (List<Object>) response.get('content');

            history.add(new Map<String,Object>{ 'role' => 'assistant', 'content' => content });

            if (stopReason == 'end_turn') {
                for (Object c : content) {
                    Map<String,Object> block = (Map<String,Object>) c;
                    if ('text'.equals(block.get('type'))) {
                        finalText = (String) block.get('text');
                    }
                }
                break;
            }

            if (stopReason == 'tool_use') {
                List<Object> toolResults = new List<Object>();
                for (Object c : content) {
                    Map<String,Object> block = (Map<String,Object>) c;
                    if (!'tool_use'.equals(block.get('type'))) continue;

                    String toolName    = (String) block.get('name');
                    String toolId      = (String) block.get('id');
                    Map<String,Object> input = (Map<String,Object>) block.get('input');
                    String resultJson;
                    try {
                        resultJson = surface.executeTool(toolName, input, accumulatedChanges);
                    } catch (Exception e) {
                        // A surface is contracted not to throw. If one does, the
                        // conversation degrades to a tool error rather than a
                        // 500 the rep cannot act on.
                        resultJson = JSON.serialize(new Map<String,Object>{
                            'error' => 'Tool execution failed: ' + e.getMessage()
                        });
                    }

                    toolResults.add(new Map<String,Object>{
                        'type'        => 'tool_result',
                        'tool_use_id' => toolId,
                        'content'     => resultJson
                    });
                }
                history.add(new Map<String,Object>{ 'role' => 'user', 'content' => toolResults });
            } else {
                finalText = 'I received an unexpected response. Please try again.';
                break;
            }
        }

        if (String.isBlank(finalText)) {
            finalText = 'I reached my step limit. Please rephrase your request.';
        }

        return JSON.serialize(new Map<String,Object>{
            'text'        => finalText,
            'historyJson' => JSON.serialize(history),
            'changes'     => accumulatedChanges
        });
    }

    // ── The configurator surface ──────────────────────────────────────────────

    /**
     * The original two configurator tools, unchanged, now behind the surface
     * seam. `without sharing` is inherited from the enclosing class and is
     * deliberate here: configurator page state is not client deal content.
     */
    private class ConfigSurface implements GtmAgentToolSurface {
        private final String configId;
        ConfigSurface(String configId) { this.configId = configId; }

        public String systemPrompt()      { return configSystemPrompt(); }
        public Integer maxTokens()        { return MAX_TOKENS; }
        public List<Object> toolDefinitions() {
            return new List<Object>{ TOOL_GET_STATE, TOOL_APPLY_UPDATE };
        }

        public String executeTool(String toolName, Map<String,Object> input,
                                  Map<String,Object> accumulatedChanges) {
            return executeToolCall(toolName, input, configId, accumulatedChanges);
        }
    }

    // ── Tool execution ────────────────────────────────────────────────────────

    private static String executeToolCall(String toolName, Map<String,Object> input,
                                          String configId, Map<String,Object> accumulatedChanges) {
        try {
            if ('get_gtm_config_state'.equals(toolName)) {
                return executeGetState(input, configId);
            }
            if ('apply_gtm_config_update'.equals(toolName)) {
                return executeApplyUpdate(input, accumulatedChanges);
            }
            return '{"error":"Unknown tool: ' + toolName + '"}';
        } catch (Exception e) {
            return '{"error":"Tool execution failed: ' + e.getMessage().replace('"', '\\"') + '"}';
        }
    }

    private static String executeGetState(Map<String,Object> input, String configId) {
        String cfgId = (String) input.get('config_id');
        if (String.isBlank(cfgId)) cfgId = configId;

        GtmAgentGetConfigState.Input inp = new GtmAgentGetConfigState.Input();
        inp.configId = cfgId;
        GtmAgentGetConfigState.Output out =
            GtmAgentGetConfigState.execute(new List<GtmAgentGetConfigState.Input>{ inp })[0];

        return JSON.serialize(new Map<String,Object>{
            'company'             => out.company,
            'industry'            => out.industry,
            'accent'              => out.accent,
            'objectsCount'        => out.objectsCount,
            'depsCount'           => out.depsCount,
            'healthScore'         => out.healthScore,
            'note'                => out.note,
            'availableIndustries' => out.availableIndustries
        });
    }

    /**
     * Validates the delta without DML (no EventBus.publish). Valid changes are
     * merged into accumulatedChanges so the LWC can apply them after all
     * callouts complete, avoiding the Salesforce callout→DML restriction.
     */
    private static String executeApplyUpdate(Map<String,Object> input,
                                             Map<String,Object> accumulatedChanges) {
        String updatesJson = (String) input.get('updates_json');
        if (String.isBlank(updatesJson)) {
            return '{"success":false,"appliedJson":"","errorMessage":"updates_json is required."}';
        }

        Map<String,Object> raw;
        try {
            raw = (Map<String,Object>) JSON.deserializeUntyped(updatesJson);
        } catch (Exception e) {
            return '{"success":false,"appliedJson":"","errorMessage":"updates_json is not valid JSON."}';
        }

        Map<String,Object> clean  = new Map<String,Object>();
        List<String> errors       = new List<String>();
        for (String key : raw.keySet()) {
            if (!GtmAgentConfigActions.ALLOWED_DELTA_KEYS.contains(key)) continue;
            String err = GtmAgentConfigActions.validateDeltaField(key, raw.get(key));
            if (err != null) {
                errors.add(err);
            } else {
                clean.put(key, raw.get(key));
            }
        }

        if (!errors.isEmpty()) {
            return JSON.serialize(new Map<String,Object>{
                'success'      => false,
                'appliedJson'  => '',
                'errorMessage' => String.join(errors, ' ')
            });
        }
        if (clean.isEmpty()) {
            return '{"success":false,"appliedJson":"","errorMessage":"No recognised or valid fields in updates_json."}';
        }

        // Accumulate — the LWC applies these after all callouts are done
        accumulatedChanges.putAll(clean);

        return JSON.serialize(new Map<String,Object>{
            'success'      => true,
            'appliedJson'  => JSON.serialize(clean),
            'errorMessage' => ''
        });
    }

    // ── HTTP callout ──────────────────────────────────────────────────────────

    private static Map<String,Object> callClaude(List<Object> messages, String apiKey,
                                                String model, GtmAgentToolSurface surface) {
        String body = JSON.serialize(new Map<String,Object>{
            'model'      => model,
            'max_tokens' => surface.maxTokens(),
            'system'     => surface.systemPrompt(),
            'tools'      => surface.toolDefinitions(),
            'messages'   => messages
        });

        HttpRequest req = new HttpRequest();
        req.setEndpoint(ANTHROPIC_URL);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-api-key', apiKey);
        req.setHeader('anthropic-version', ANTHROPIC_VER);
        req.setBody(body);
        req.setTimeout(120000);

        HttpResponse resp = new Http().send(req);
        if (resp.getStatusCode() != 200) {
            throw new CalloutException(
                'Claude API returned ' + resp.getStatusCode() + ': ' + resp.getBody()
            );
        }
        return (Map<String,Object>) JSON.deserializeUntyped(resp.getBody());
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static List<Object> parseHistory(String historyJson) {
        if (String.isBlank(historyJson)) return new List<Object>();
        try {
            return (List<Object>) JSON.deserializeUntyped(historyJson);
        } catch (Exception e) {
            return new List<Object>();
        }
    }

    private static String getApiKey() {
        GTM_Agent_Settings__c s = GTM_Agent_Settings__c.getOrgDefaults();
        return s?.Claude_API_Key__c;
    }

    private static String getModel() {
        GTM_Agent_Settings__c s = GTM_Agent_Settings__c.getOrgDefaults();
        String m = s?.Claude_Model__c;
        return String.isBlank(m) ? DEFAULT_MODEL : m;
    }
}
