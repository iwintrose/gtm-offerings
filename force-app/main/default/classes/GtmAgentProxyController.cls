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

    static final String ANTHROPIC_URL      = 'https://api.anthropic.com/v1/messages';
    static final String DEFAULT_MODEL      = 'claude-sonnet-5';
    static final String ANTHROPIC_VER      = '2023-06-01';
    static final String OPENAI_URL         = 'https://api.openai.com/v1/chat/completions';
    static final String DEFAULT_OPENAI_MODEL = 'gpt-4o';
    static final String GEMINI_BASE_URL    = 'https://generativelanguage.googleapis.com';
    // Convenience default only -- Gemini model ids change often. Admins can
    // override via GTM_Agent_Settings__c.Gemini_Model__c; this may go stale.
    static final String DEFAULT_GEMINI_MODEL = 'gemini-2.5-flash';
    static final String PROVIDER_ANTHROPIC = 'Anthropic';
    static final String PROVIDER_GEMINI    = 'Gemini';
    static final String PROVIDER_AGENTFORCE = 'Agentforce';
    static final String PROVIDER_OPENAI    = 'OpenAI';
    static final Integer MAX_TOKENS      = 1024;
    static final Integer MAX_TOOL_ROUNDS = 5;
    static final Integer APP_HISTORY_TURNS = 20;

    /**
     * Was a `static final String` constant. Now a method because the trailing
     * TONE line is sourced from GtmAgentTone.clause(), which reads
     * GTM_Page_Content__c via SOQL — not something a compile-time constant can
     * do. Everything above TONE is unchanged, fixed developer-authored text.
     *
     * @param toneClause  the already-resolved GtmAgentTone.clause() value for
     *                    this runLoop() turn — resolved once in runLoop(),
     *                    never re-queried here.
     */
    private static String configSystemPrompt(String toneClause) {
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
        'TONE: ' + toneClause;
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

    /**
     * App-wide entry point: GUS in the utility bar. No record is read here;
     * pageContextJson is untrusted client text and is reduced to an allow-listed
     * map by GtmAppAgentSurface.sanitizeContext. Never throws for blank/invalid
     * context, a blank message, or a missing provider key (a normal reply is
     * returned, with no callout). runLoop and its messages are unchanged.
     *
     * @return JSON: { text, historyJson, changes }
     */
    @AuraEnabled
    public static String chatOnApp(String pageContextJson, String userMessage, String historyJson) {
        Map<String,Object> ctx = GtmAppAgentSurface.sanitizeContext(pageContextJson);
        String priorHistory = historyJson == null ? '' : historyJson;
        if (String.isBlank(userMessage)) {
            return appReply('Please type a message.', priorHistory);
        }
        // Key check FIRST: same provider/key lookup runLoop uses.
        if (String.isBlank(getApiKey(getProvider()))) {
            return appReply('GUS is not set up yet. Ask an admin to add an API key on the GTM Offerings Settings tab.',
                            priorHistory);
        }
        String trimmed = GtmAppAgentSurface.trimHistory(historyJson, APP_HISTORY_TURNS);
        Map<String,Object> reply = (Map<String,Object>) JSON.deserializeUntyped(
            runLoop(new GtmAppAgentSurface(ctx), userMessage, trimmed));
        // Rows returned by tools are for the current turn only (gus-stage-filter-tool).
        reply.put('historyJson', GtmStageFilterAppTool.compactHistory((String) reply.get('historyJson')));
        return JSON.serialize(reply);
    }

    private static String appReply(String text, String historyJson) {
        return JSON.serialize(new Map<String,Object>{
            'text'        => text,
            'historyJson' => historyJson,
            'changes'     => new Map<String,Object>()
        });
    }

    // ── The loop (one, shared) ────────────────────────────────────────────────

    /**
     * The Claude tool-use loop. Callouts only; the surface's executeTool does
     * no DML, so every HTTP round trip in this method happens before the
     * transaction's first (client-side, later) write.
     */
    private static String runLoop(GtmAgentToolSurface surface, String userMessage, String historyJson) {
        String provider = getProvider();
        String apiKey    = getApiKey(provider);
        if (String.isBlank(apiKey)) {
            if (PROVIDER_GEMINI.equals(provider)) {
                throw new AuraHandledException(
                    'Gemini API key not configured. Go to Setup → Custom Settings → GTM Agent Settings → Manage → New, and paste your Google Gemini API key into the Gemini API Key field.'
                );
            }
            if (PROVIDER_OPENAI.equals(provider)) {
                throw new AuraHandledException(
                    'OpenAI API key not configured. Go to Setup → Custom Settings → GTM Agent Settings → Manage → New, and paste your OpenAI API key into the OpenAI API Key field.'
                );
            }
            throw new AuraHandledException(
                'Claude API key not configured. Go to Setup → Custom Settings → GTM Agent Settings → Manage → New, and paste your Anthropic API key into the Claude API Key field.'
            );
        }

        List<Object> history = parseHistory(historyJson);
        history.add(new Map<String,Object>{ 'role' => 'user', 'content' => userMessage });

        String model    = getModel(provider);
        String finalText = '';
        Map<String,Object> accumulatedChanges = new Map<String,Object>();
        Integer rounds  = 0;

        // Resolved ONCE per turn, before the loop's first callout. clause() is
        // a pure SOQL read keyed on fixed constants — deterministic for the
        // life of this transaction — so every round below reuses this value
        // instead of re-querying it (was up to MAX_TOOL_ROUNDS reads).
        String toneClause = GtmAgentTone.clause();

        while (rounds < MAX_TOOL_ROUNDS) {
            rounds++;
            Map<String,Object> response;
            if (PROVIDER_OPENAI.equals(provider)) {
                response = callOpenAi(history, apiKey, model, surface, toneClause);
            } else if (PROVIDER_GEMINI.equals(provider)) {
                response = callGemini(history, apiKey, model, surface, toneClause);
            } else {
                // Anthropic, and anything unrecognised. 'Agentforce' never
                // reaches here: getProvider() resolves it to a real provider.
                response = callClaude(history, apiKey, model, surface, toneClause);
            }
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

        public String systemPrompt(String toneClause) { return configSystemPrompt(toneClause); }
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
        // Always the session's configId: a model-supplied config_id is ignored
        // so a confused or prompt-injected model cannot aim the tool at
        // another link.
        String cfgId = configId;

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
                                                String model, GtmAgentToolSurface surface,
                                                String toneClause) {
        Map<String,Object> bodyMap = new Map<String,Object>{
            'model'      => model,
            'max_tokens' => surface.maxTokens(),
            'system'     => surface.systemPrompt(toneClause),
            'messages'   => messages
        };
        // Anthropic rejects an empty tools array, so a surface with no tools
        // (the app-wide GUS surface today) must omit the key entirely.
        List<Object> toolDefs = surface.toolDefinitions();
        if (toolDefs != null && !toolDefs.isEmpty()) {
            bodyMap.put('tools', toolDefs);
        }
        String body = JSON.serialize(bodyMap);

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

    // ── OpenAI HTTP callout (provider-strategy peer to callClaude) ─────────────

    /**
     * OpenAI Chat Completions counterpart to callClaude(). Translates the
     * canonical Anthropic-shaped `history` + surface.toolDefinitions() into
     * OpenAI's Chat Completions request shape, then normalizes the response
     * straight back into the same {stop_reason, content} shape callClaude()
     * returns — `content` blocks of type 'text' / 'tool_use' and stop_reason
     * of 'end_turn' / 'tool_use' — so runLoop() above needs no provider
     * branching beyond choosing which of these two methods to call. `history`
     * itself is NEVER stored in OpenAI's shape; only this method's request
     * body is. What runLoop() appends back into `history` after this call is
     * the same normalized Anthropic-shaped `content` list every other branch
     * of the loop already expects — so a conversation can, in principle,
     * switch providers between turns without a shape mismatch.
     */
    private static Map<String,Object> callOpenAi(List<Object> history, String apiKey,
                                                 String model, GtmAgentToolSurface surface,
                                                 String toneClause) {
        List<Object> messages = new List<Object>();
        messages.add(new Map<String,Object>{ 'role' => 'system', 'content' => surface.systemPrompt(toneClause) });
        messages.addAll(openAiMessagesFromHistory(history));

        Map<String,Object> bodyMap = new Map<String,Object>{
            'model'      => model,
            'max_tokens' => surface.maxTokens(),
            'messages'   => messages
        };
        List<Object> tools = openAiToolsFromToolDefinitions(surface.toolDefinitions());
        if (!tools.isEmpty()) {
            bodyMap.put('tools', tools);
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(OPENAI_URL);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + apiKey);
        req.setBody(JSON.serialize(bodyMap));
        req.setTimeout(120000);

        HttpResponse resp = new Http().send(req);
        if (resp.getStatusCode() != 200) {
            throw new CalloutException(
                'OpenAI API returned ' + resp.getStatusCode() + ': ' + resp.getBody()
            );
        }
        Map<String,Object> raw = (Map<String,Object>) JSON.deserializeUntyped(resp.getBody());
        return normalizeOpenAiResponse(raw);
    }

    /**
     * Translates a single OpenAI Chat Completions response envelope into the
     * {stop_reason, content} shape runLoop() already understands from
     * Anthropic. This is the highest-risk seam in the whole change — see
     * class header and the Architect addendum for why.
     *
     * - Any tool_calls on choices[0].message ⇒ stop_reason 'tool_use', one
     *   'tool_use' content block per call (arguments JSON-parsed into the
     *   `input` map exactly like Anthropic's tool_use.input).
     * - No tool_calls, finish_reason 'stop' ⇒ stop_reason 'end_turn', a single
     *   'text' content block if message.content is non-blank (an empty/blank
     *   assistant text with no tool call is treated as an end_turn with no
     *   text block, same as Anthropic could in principle return).
     * - Anything else (finish_reason 'length', 'content_filter', a missing
     *   choices array, malformed tool_call arguments, ...) normalizes to a
     *   stop_reason that is neither 'end_turn' nor 'tool_use', which is
     *   exactly the fallback branch runLoop() already has for Anthropic's own
     *   non-standard stop reasons (e.g. 'max_tokens') — no new branch needed
     *   in runLoop() itself.
     */
    private static Map<String,Object> normalizeOpenAiResponse(Map<String,Object> raw) {
        List<Object> choices = raw != null ? (List<Object>) raw.get('choices') : null;
        if (choices == null || choices.isEmpty()) {
            return new Map<String,Object>{ 'stop_reason' => 'no_choices', 'content' => new List<Object>() };
        }

        Map<String,Object> choice      = (Map<String,Object>) choices[0];
        String finishReason            = (String) choice.get('finish_reason');
        Map<String,Object> message     = (Map<String,Object>) choice.get('message');
        List<Object> toolCalls         = message != null ? (List<Object>) message.get('tool_calls') : null;

        if (toolCalls != null && !toolCalls.isEmpty()) {
            List<Object> content = new List<Object>();
            for (Object tc : toolCalls) {
                Map<String,Object> toolCall = (Map<String,Object>) tc;
                Map<String,Object> fn       = (Map<String,Object>) toolCall.get('function');
                String argsJson             = fn != null ? (String) fn.get('arguments') : null;
                Map<String,Object> input;
                try {
                    input = String.isNotBlank(argsJson)
                        ? (Map<String,Object>) JSON.deserializeUntyped(argsJson)
                        : new Map<String,Object>();
                } catch (Exception e) {
                    // Malformed function-call arguments from the model. Fed back
                    // to the surface as an empty input rather than throwing —
                    // executeTool's own validation reports the resulting error
                    // to the model, same recovery path Anthropic tool errors use.
                    input = new Map<String,Object>();
                }
                content.add(new Map<String,Object>{
                    'type'  => 'tool_use',
                    'id'    => toolCall.get('id'),
                    'name'  => fn != null ? fn.get('name') : null,
                    'input' => input
                });
            }
            return new Map<String,Object>{ 'stop_reason' => 'tool_use', 'content' => content };
        }

        List<Object> content = new List<Object>();
        String text = message != null ? (String) message.get('content') : null;
        if (String.isNotBlank(text)) {
            content.add(new Map<String,Object>{ 'type' => 'text', 'text' => text });
        }
        String stopReason = 'stop'.equals(finishReason) ? 'end_turn' : ('openai_' + finishReason);
        return new Map<String,Object>{ 'stop_reason' => stopReason, 'content' => content };
    }

    /**
     * Anthropic tool_use → OpenAI function-calling schema translation.
     * Anthropic: {name, description, input_schema}.
     * OpenAI:    {type:'function', function:{name, description, parameters}}.
     */
    private static List<Object> openAiToolsFromToolDefinitions(List<Object> anthropicToolDefs) {
        List<Object> result = new List<Object>();
        if (anthropicToolDefs == null) return result;
        for (Object t : anthropicToolDefs) {
            Map<String,Object> tool = (Map<String,Object>) t;
            result.add(new Map<String,Object>{
                'type'     => 'function',
                'function' => new Map<String,Object>{
                    'name'        => tool.get('name'),
                    'description' => tool.get('description'),
                    'parameters'  => tool.get('input_schema')
                }
            });
        }
        return result;
    }

    /**
     * Translates `history` — which is always stored in the canonical
     * Anthropic shape, regardless of which provider produced any given turn
     * — into OpenAI's flat messages array for a single outbound request.
     *
     * Anthropic 'user' turns are either a plain String (the rep's typed
     * message) or a List of tool_result blocks (the loop's reply to a
     * tool_use round); Anthropic 'assistant' turns are a List of text/
     * tool_use blocks (always list-shaped once normalized, on both
     * provider paths). OpenAI wants: {role:'user', content:string},
     * {role:'assistant', content:string|null, tool_calls:[...]}, and one
     * {role:'tool', tool_call_id, content} message PER tool_result block
     * (OpenAI has no single-message container for multiple tool results the
     * way Anthropic's tool_result content array does).
     */
    private static List<Object> openAiMessagesFromHistory(List<Object> history) {
        List<Object> messages = new List<Object>();
        for (Object turnObj : history) {
            Map<String,Object> turn = (Map<String,Object>) turnObj;
            String role       = (String) turn.get('role');
            Object contentObj = turn.get('content');

            if (contentObj instanceof String) {
                messages.add(new Map<String,Object>{ 'role' => role, 'content' => (String) contentObj });
                continue;
            }

            List<Object> blocks = (List<Object>) contentObj;
            if ('assistant'.equals(role)) {
                String text = null;
                List<Object> toolCalls = new List<Object>();
                for (Object b : blocks) {
                    Map<String,Object> block = (Map<String,Object>) b;
                    String type = (String) block.get('type');
                    if ('text'.equals(type)) {
                        text = (String) block.get('text');
                    } else if ('tool_use'.equals(type)) {
                        toolCalls.add(new Map<String,Object>{
                            'id'       => block.get('id'),
                            'type'     => 'function',
                            'function' => new Map<String,Object>{
                                'name'      => block.get('name'),
                                'arguments' => JSON.serialize(block.get('input'))
                            }
                        });
                    }
                }
                Map<String,Object> assistantMsg = new Map<String,Object>{ 'role' => 'assistant', 'content' => text };
                if (!toolCalls.isEmpty()) {
                    assistantMsg.put('tool_calls', toolCalls);
                }
                messages.add(assistantMsg);
            } else {
                // 'user' turn carrying tool_result blocks — one OpenAI 'tool'
                // message per block, in order.
                for (Object b : blocks) {
                    Map<String,Object> block = (Map<String,Object>) b;
                    if ('tool_result'.equals(block.get('type'))) {
                        messages.add(new Map<String,Object>{
                            'role'         => 'tool',
                            'tool_call_id' => block.get('tool_use_id'),
                            'content'      => block.get('content')
                        });
                    }
                }
            }
        }
        return messages;
    }

    // ── Gemini HTTP callout (provider-strategy peer to callOpenAi) ─────────────

    /**
     * Gemini generateContent counterpart to callOpenAi(). Same approach:
     * history stays Anthropic-shaped; only this request body is Gemini-shaped,
     * and the response is normalized back to {stop_reason, content}. Contract:
     * docs/architecture/gus-chat-provider-settings.md. The API key travels in
     * the x-goog-api-key header only (never the URL or body) and is never
     * included in an exception message.
     */
    private static Map<String,Object> callGemini(List<Object> history, String apiKey,
                                                 String model, GtmAgentToolSurface surface,
                                                 String toneClause) {
        Map<String,Object> bodyMap = new Map<String,Object>{
            'systemInstruction' => new Map<String,Object>{
                'parts' => new List<Object>{
                    new Map<String,Object>{ 'text' => surface.systemPrompt(toneClause) }
                }
            },
            'contents'         => geminiContentsFromHistory(history),
            'generationConfig' => new Map<String,Object>{ 'maxOutputTokens' => surface.maxTokens() }
        };
        List<Object> declarations = geminiToolsFromToolDefinitions(surface.toolDefinitions());
        if (!declarations.isEmpty()) {
            bodyMap.put('tools', new List<Object>{
                new Map<String,Object>{ 'functionDeclarations' => declarations }
            });
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(GEMINI_BASE_URL + '/v1beta/models/' + model + ':generateContent');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-goog-api-key', apiKey);
        req.setBody(JSON.serialize(bodyMap));
        req.setTimeout(120000);

        HttpResponse resp = new Http().send(req);
        if (resp.getStatusCode() != 200) {
            throw new CalloutException(
                'Gemini API returned ' + resp.getStatusCode() + ': ' + resp.getBody()
            );
        }
        Map<String,Object> raw = (Map<String,Object>) JSON.deserializeUntyped(resp.getBody());
        return normalizeGeminiResponse(raw);
    }

    /**
     * Gemini response -> {stop_reason, content}.
     * - any functionCall part => 'tool_use', one tool_use block per call with a
     *   synthesised id 'gemini_<n>' (Gemini supplies no call ids).
     * - finishReason STOP => 'end_turn' (text parts joined into one block).
     * - anything else, including no candidates (e.g. a promptFeedback block)
     *   => 'gemini_<reason>' / 'gemini_no_candidates', which runLoop() handles
     *   through its existing non-standard-stop-reason branch. Never throws.
     */
    private static Map<String,Object> normalizeGeminiResponse(Map<String,Object> raw) {
        List<Object> candidates = raw != null ? (List<Object>) raw.get('candidates') : null;
        if (candidates == null || candidates.isEmpty()) {
            return new Map<String,Object>{ 'stop_reason' => 'gemini_no_candidates', 'content' => new List<Object>() };
        }
        Map<String,Object> candidate = (Map<String,Object>) candidates[0];
        String finishReason = (String) candidate.get('finishReason');
        Map<String,Object> candContent = (Map<String,Object>) candidate.get('content');
        List<Object> parts = candContent != null ? (List<Object>) candContent.get('parts') : null;

        List<Object> toolUses = new List<Object>();
        String text = '';
        if (parts != null) {
            Integer n = 0;
            for (Object po : parts) {
                Map<String,Object> part = (Map<String,Object>) po;
                Map<String,Object> fc = (Map<String,Object>) part.get('functionCall');
                if (fc != null) {
                    Map<String,Object> args = (Map<String,Object>) fc.get('args');
                    toolUses.add(new Map<String,Object>{
                        'type'  => 'tool_use',
                        'id'    => 'gemini_' + n,
                        'name'  => fc.get('name'),
                        'input' => args != null ? args : new Map<String,Object>()
                    });
                    n++;
                } else if (part.get('text') instanceof String) {
                    text += (String) part.get('text');
                }
            }
        }

        List<Object> content = new List<Object>();
        if (String.isNotBlank(text)) {
            content.add(new Map<String,Object>{ 'type' => 'text', 'text' => text });
        }
        if (!toolUses.isEmpty()) {
            content.addAll(toolUses);
            return new Map<String,Object>{ 'stop_reason' => 'tool_use', 'content' => content };
        }
        String stopReason = 'STOP'.equals(finishReason) ? 'end_turn' : ('gemini_' + finishReason);
        return new Map<String,Object>{ 'stop_reason' => stopReason, 'content' => content };
    }

    /**
     * Anthropic tool defs -> Gemini functionDeclarations. Gemini accepts an
     * OpenAPI subset: strips additionalProperties, omits an empty `required`,
     * and omits `parameters` entirely when the schema has no properties.
     */
    private static List<Object> geminiToolsFromToolDefinitions(List<Object> anthropicToolDefs) {
        List<Object> result = new List<Object>();
        if (anthropicToolDefs == null) return result;
        for (Object t : anthropicToolDefs) {
            Map<String,Object> tool = (Map<String,Object>) t;
            Map<String,Object> decl = new Map<String,Object>{
                'name'        => tool.get('name'),
                'description' => tool.get('description')
            };
            Map<String,Object> schema = (Map<String,Object>) tool.get('input_schema');
            Map<String,Object> cleaned = cleanGeminiSchema(schema);
            Map<String,Object> props = cleaned != null ? (Map<String,Object>) cleaned.get('properties') : null;
            if (props != null && !props.isEmpty()) {
                decl.put('parameters', cleaned);
            }
            result.add(decl);
        }
        return result;
    }

    private static Map<String,Object> cleanGeminiSchema(Map<String,Object> schema) {
        if (schema == null) return null;
        Map<String,Object> out = new Map<String,Object>();
        for (String k : schema.keySet()) {
            if ('additionalProperties'.equals(k)) continue;
            Object v = schema.get(k);
            if ('required'.equals(k)) {
                List<Object> req = (List<Object>) v;
                if (req == null || req.isEmpty()) continue;
                out.put(k, req);
            } else if ('properties'.equals(k)) {
                Map<String,Object> props = (Map<String,Object>) v;
                Map<String,Object> cleanProps = new Map<String,Object>();
                if (props != null) {
                    for (String pk : props.keySet()) {
                        Object pv = props.get(pk);
                        cleanProps.put(pk, pv instanceof Map<String,Object>
                            ? (Object) cleanGeminiSchema((Map<String,Object>) pv) : pv);
                    }
                }
                out.put(k, cleanProps);
            } else if ('items'.equals(k) && v instanceof Map<String,Object>) {
                out.put(k, cleanGeminiSchema((Map<String,Object>) v));
            } else {
                out.put(k, v);
            }
        }
        return out;
    }

    /**
     * Anthropic-shaped history -> Gemini `contents`. Assistant turns become
     * role 'model' (text / functionCall parts); user turns are role 'user'
     * (text, or functionResponse parts for tool_result blocks). Because
     * Gemini's functionResponse needs the function NAME (Anthropic's
     * tool_result carries only the id), names are resolved from the earlier
     * tool_use block with the matching id.
     */
    private static List<Object> geminiContentsFromHistory(List<Object> history) {
        Map<String,String> nameById = new Map<String,String>();
        List<Object> contents = new List<Object>();
        for (Object turnObj : history) {
            Map<String,Object> turn = (Map<String,Object>) turnObj;
            String role       = (String) turn.get('role');
            Object contentObj = turn.get('content');
            String geminiRole = 'assistant'.equals(role) ? 'model' : 'user';

            if (contentObj instanceof String) {
                contents.add(new Map<String,Object>{
                    'role'  => geminiRole,
                    'parts' => new List<Object>{ new Map<String,Object>{ 'text' => (String) contentObj } }
                });
                continue;
            }

            List<Object> parts = new List<Object>();
            List<Object> blocks = (List<Object>) contentObj;
            if (blocks != null) {
                for (Object b : blocks) {
                    Map<String,Object> block = (Map<String,Object>) b;
                    String type = (String) block.get('type');
                    if ('text'.equals(type)) {
                        parts.add(new Map<String,Object>{ 'text' => block.get('text') });
                    } else if ('tool_use'.equals(type)) {
                        nameById.put((String) block.get('id'), (String) block.get('name'));
                        Object input = block.get('input');
                        parts.add(new Map<String,Object>{
                            'functionCall' => new Map<String,Object>{
                                'name' => block.get('name'),
                                'args' => input != null ? input : new Map<String,Object>()
                            }
                        });
                    } else if ('tool_result'.equals(type)) {
                        String fnName = nameById.get((String) block.get('tool_use_id'));
                        parts.add(new Map<String,Object>{
                            'functionResponse' => new Map<String,Object>{
                                'name'     => fnName,
                                'response' => new Map<String,Object>{ 'result' => block.get('content') }
                            }
                        });
                    }
                }
            }
            if (!parts.isEmpty()) {
                contents.add(new Map<String,Object>{ 'role' => geminiRole, 'parts' => parts });
            }
        }
        return contents;
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

    /** The provider runLoop() will actually call (never 'Agentforce'). */
    private static String getProvider() {
        return resolveEffectiveProvider(GTM_Agent_Settings__c.getOrgDefaults());
    }

    /**
     * Blank -> Anthropic. 'Agentforce' is saved-but-inactive (never called),
     * so it resolves statelessly to Anthropic if it has a key, else OpenAI if
     * it has a key, else Gemini if it has a key, else Anthropic (which then
     * surfaces the existing "Claude API key not configured" error). Never
     * throws on the provider value.
     */
    @TestVisible
    private static String resolveEffectiveProvider(GTM_Agent_Settings__c s) {
        String p = s?.Chat_Provider__c;
        if (String.isBlank(p)) return PROVIDER_ANTHROPIC;
        if (!PROVIDER_AGENTFORCE.equals(p)) return p;
        if (String.isNotBlank(s.Claude_API_Key__c)) return PROVIDER_ANTHROPIC;
        if (String.isNotBlank(s.OpenAI_API_Key__c)) return PROVIDER_OPENAI;
        if (String.isNotBlank(s.Gemini_API_Key__c)) return PROVIDER_GEMINI;
        return PROVIDER_ANTHROPIC;
    }

    private static String getApiKey(String provider) {
        GTM_Agent_Settings__c s = GTM_Agent_Settings__c.getOrgDefaults();
        String effective = PROVIDER_AGENTFORCE.equals(provider) ? resolveEffectiveProvider(s) : provider;
        if (PROVIDER_OPENAI.equals(effective)) {
            return s?.OpenAI_API_Key__c;
        }
        if (PROVIDER_GEMINI.equals(effective)) {
            return s?.Gemini_API_Key__c;
        }
        return s?.Claude_API_Key__c;
    }

    private static String getModel(String provider) {
        GTM_Agent_Settings__c s = GTM_Agent_Settings__c.getOrgDefaults();
        String effective = PROVIDER_AGENTFORCE.equals(provider) ? resolveEffectiveProvider(s) : provider;
        if (PROVIDER_OPENAI.equals(effective)) {
            String om = s?.OpenAI_Model__c;
            return String.isBlank(om) ? DEFAULT_OPENAI_MODEL : om;
        }
        if (PROVIDER_GEMINI.equals(effective)) {
            String gm = s?.Gemini_Model__c;
            return String.isBlank(gm) ? DEFAULT_GEMINI_MODEL : gm;
        }
        String m = s?.Claude_Model__c;
        return String.isBlank(m) ? DEFAULT_MODEL : m;
    }
}
