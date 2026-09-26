/**
 * Claude/OpenAI/Gemini/Agentforce API proxy for the GTM Configurator AI
 * assistant.
 *
 * For Anthropic/OpenAI/Gemini: reads page state and applies config deltas via
 * tool use (the shared runLoop() below). For Agentforce (live as of issue
 * gus-live-agentforce-provider-runtime, configurator surface / chat() only —
 * see docs/architecture/gus-chat-provider-settings.md §5a and
 * docs/agent-artifacts/task-scope-gus-live-agentforce-provider-runtime.md §6
 * Fork 1/Fork 2): the same LWC (gtmAgentChat, unchanged) instead talks to a
 * real Agent API session server-side via runAgentforceLoop() — conversational
 * only, since the live "GTM Configurator Assistant" agent has zero
 * Topics/Actions wired and Agent API has no per-call tool-definition
 * parameter. `changes` is always empty on that path. chatOnReadout()/
 * chatOnApp() never route to Agentforce regardless of Chat_Provider__c.
 *
 * Callout/DML ordering: all HTTP callouts happen before any DML. Config changes
 * are NOT published as GTM_Config_Update__e here — they are returned as a JSON
 * delta to the LWC, which dispatches them directly via _applyDelta().
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

    // Named Credential set up in issue gus-live-agentforce-provider-auth
    // (force-app/main/default/namedCredentials/GTM_Agentforce_API.namedCredential-meta.xml).
    // Host/auth are handled entirely by the Named Credential; Apex only supplies
    // the path. Proven live against gtm-staging -- see
    // docs/architecture/gus-chat-provider-settings.md §5a "RESOLVED".
    static final String AGENTFORCE_API_BASE = 'callout:GTM_Agentforce_API/einstein/ai-agent/v1';

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
        // allowAgentforce=true: the configurator surface is the ONLY caller
        // permitted to resolve Chat_Provider__c='Agentforce' to the real Agent
        // API adapter -- see task-scope-gus-live-agentforce-provider-runtime.md
        // §6 Fork 2. chatOnReadout()/chatOnApp() below pass no 4th argument,
        // which defaults to false and keeps today's stateless fallback.
        return runLoop(new ConfigSurface(configId), userMessage, historyJson, true);
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
     *
     * `public`, not `private`: GtmAgentContentDraftController (Content
     * Manager's entry point, a separate class -- see its header and
     * docs/architecture/industry-variants-agentforce-draft.md §4) calls this
     * directly to reuse the one shared loop without needing Apex class
     * access to GtmAgentProxyController itself, which is what keeps
     * chat()/chatOnReadout()/chatOnApp() ungranted-and-unreachable from the
     * Content Manager app under decision F4. No other behavior change.
     *
     * 3-arg overload: allowAgentforce defaults to false, i.e. Chat_Provider__c
     * = 'Agentforce' is resolved through the existing stateless
     * Claude/OpenAI/Gemini fallback exactly as before. Every caller except
     * chat() uses this overload -- see the 4-arg overload's header for why.
     */
    public static String runLoop(GtmAgentToolSurface surface, String userMessage, String historyJson) {
        return runLoop(surface, userMessage, historyJson, false);
    }

    /**
     * @param allowAgentforce  true ONLY for chat()/ConfigSurface (the
     *        configurator surface) -- task-scope-gus-live-agentforce-provider-
     *        runtime.md §6 Fork 2 decides Agentforce goes live for that one
     *        caller only, since the live "GTM Configurator Assistant" agent's
     *        instructions are configurator-flavored and Agent API has no
     *        per-session system-prompt override that would make it safe to
     *        reuse for the readout editor or the app-wide utility bar.
     *        chatOnReadout()/chatOnApp() call the 3-arg overload above, which
     *        hardcodes false, so they always keep today's behavior regardless
     *        of Chat_Provider__c.
     *
     *        When true AND the org's Chat_Provider__c is literally
     *        'Agentforce', this method skips the Claude/OpenAI/Gemini
     *        tool-use loop entirely — no apiKey check, no surface.toolDefinitions(),
     *        no surface.executeTool() call — and hands off to
     *        runAgentforceLoop() instead. That is a hard constraint, not a
     *        preference: the live agent has zero Topics/Actions wired and
     *        Agent API's Start Session/Send Message bodies have no per-call
     *        tool-definition parameter the way Claude/OpenAI/Gemini accept
     *        (GtmAgentToolSurface.toolDefinitions()'s own doc comment calls
     *        these "Anthropic tool definitions" -- there is no Agent-API
     *        equivalent to send). `changes` returned on that path is always
     *        an empty map -- see task-scope §6 Fork 1.
     */
    public static String runLoop(GtmAgentToolSurface surface, String userMessage, String historyJson,
                                 Boolean allowAgentforce) {
        String provider = getProvider(allowAgentforce);

        if (allowAgentforce == true && PROVIDER_AGENTFORCE.equals(provider)) {
            return runAgentforceLoop(userMessage, historyJson);
        }

        String apiKey    = getApiKey(provider);
        if (String.isBlank(apiKey)) {
            String noKeyMessage;
            if (PROVIDER_GEMINI.equals(provider)) {
                noKeyMessage = 'Gemini API key not configured. Go to Setup → Custom Settings → GTM Agent Settings → Manage → New, and paste your Google Gemini API key into the Gemini API Key field.';
            } else if (PROVIDER_OPENAI.equals(provider)) {
                noKeyMessage = 'OpenAI API key not configured. Go to Setup → Custom Settings → GTM Agent Settings → Manage → New, and paste your OpenAI API key into the OpenAI API Key field.';
            } else {
                noKeyMessage = 'Claude API key not configured. Go to Setup → Custom Settings → GTM Agent Settings → Manage → New, and paste your Anthropic API key into the Claude API Key field.';
            }
            // AuraHandledException.getMessage() returns the generic
            // "Script-thrown exception" text unless setMessage() is called
            // explicitly, even though the constructor already took the real
            // message -- a documented Apex quirk. Every caller of runLoop()
            // (chat(), chatOnReadout(), GtmAgentContentDraftController.chat())
            // needs the real, matching configuration message to actually
            // reach both Apex callers/tests and the LWC client, so it must be
            // set here rather than relying on the constructor alone.
            AuraHandledException noKeyEx = new AuraHandledException(noKeyMessage);
            noKeyEx.setMessage(noKeyMessage);
            throw noKeyEx;
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
                // reaches here: the real-Agentforce case returned via
                // runAgentforceLoop() above, and every other case resolves
                // through getProvider()/resolveEffectiveProvider() to a real
                // provider before this loop starts.
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

    // ── Agentforce (Agent API) adapter — conversational-only, chat() only ──────
    //
    // Peer to callClaude/callOpenAi/callGemini, but structurally different: the
    // other three are single-callout, stateless-per-round functions plugged
    // into the shared tool-use `while` loop above. Agentforce cannot join that
    // loop at all -- it has no tool-definition parameter to send and the live
    // agent has zero Topics/Actions wired (task-scope-gus-live-agentforce-
    // provider-runtime.md §6 Fork 1) -- so it is a separate, self-contained
    // 1-2-callout path (Start Session only on a brand new conversation, then
    // always exactly one Send Message) that runLoop() delegates to entirely
    // instead of iterating it.
    //
    // Session continuity: real Agent API sessions are stateful server-side
    // objects. This class raises/returns no server-side session store of its
    // own (runLoop() is otherwise fully stateless across calls, by design), so
    // the session id is threaded back through the exact same opaque channel
    // gtmAgentChat.js already holds and resends verbatim every turn:
    // `historyJson`. On the Agentforce path that string stops being an
    // Anthropic-shaped turn array (there is nothing to replay -- Agent API
    // keeps the conversation server-side) and instead carries
    // `{"agentSessionId": "...", "turnCount": N}`. Because gtmAgentChat.js
    // never parses `historyJson`'s contents (see its handleSend()/_send()),
    // this needs zero LWC changes and mirrors historyJson's existing lifecycle
    // exactly, including reset()'s `this.historyJson = ''` clearing it. Do not
    // conflate this with `sessionToken` (LWC/empApi routing id, unrelated).

    /**
     * @param userMessage  the rep's latest typed turn.
     * @param historyJson  opaque state from the previous turn on THIS path
     *                     only -- see class-section header above. Blank/
     *                     unparseable/missing agentSessionId all mean "start a
     *                     new session," the same tolerant-parsing posture
     *                     parseHistory() already uses for the other providers.
     */
    private static String runAgentforceLoop(String userMessage, String historyJson) {
        GTM_Agent_Settings__c s = GTM_Agent_Settings__c.getOrgDefaults();
        assertAgentforceConfigured(s);

        Map<String,Object> state = parseAgentforceState(historyJson);
        String sessionId = (String) state.get('agentSessionId');
        // JSON.deserializeUntyped() returns a JSON number as Double, never
        // Integer, even though this class serialized it as an Integer --
        // Apex's own well-known untyped-JSON round-trip quirk (see the same
        // Integer/Decimal/Double handling in GtmPredicate.cls,
        // GtmAssessmentFrames.cls, ConduitMigrationController.cls). An
        // Integer-only check here would silently reset turnCount to 0 (and
        // therefore the Send Message sequenceId) on every turn after the
        // first -- checking both keeps the counter actually monotonic.
        Integer turnCount = agentforceStateInt(state.get('turnCount'));

        if (String.isBlank(sessionId)) {
            Map<String,Object> startResp = callAgentforceStartSession(
                s.Agentforce_Agent_Id__c, s.Agentforce_My_Domain_URL__c);
            sessionId = (String) startResp.get('sessionId');
            if (String.isBlank(sessionId)) {
                throw new CalloutException(
                    'Agentforce Agent API returned no sessionId from Start Session.');
            }
            // UNVERIFIED (flagged in this issue's handback -- official docs
            // 403'd on every fetch attempt, see task-scope-gus-live-
            // agentforce-provider-runtime.md §3.1): whether the rep's first
            // typed message can ride along with Start Session, or must always
            // be a separate, subsequent Send Message call. This always issues
            // a separate Send Message below, the more conservative reading --
            // Start Session's own confirmed body (§5a RESOLVED) has no
            // message-shaped field for it.
        }

        turnCount += 1;
        Map<String,Object> sendResp = callAgentforceSendMessage(sessionId, userMessage, turnCount);
        String replyText = extractAgentforceReplyText(sendResp);

        return JSON.serialize(new Map<String,Object>{
            'text'           => String.isNotBlank(replyText) ? replyText : 'The agent did not return a reply.',
            'historyJson'    => JSON.serialize(new Map<String,Object>{
                'agentSessionId' => sessionId,
                'turnCount'      => turnCount
            }),
            // Fork 1 (task-scope §6): always empty on this path -- there is no
            // tool result to feed back, since no tool was ever offered to the
            // model in the first place.
            'changes'        => new Map<String,Object>(),
            // Also surfaced as a top-level key (in addition to being embedded
            // in historyJson above) so a future LWC enhancement can read it
            // directly without parsing historyJson's contents -- purely
            // additive, ignored today by gtmAgentChat.js's JSON.parse(result).
            'agentSessionId' => sessionId
        });
    }

    /**
     * A clear, actionable config error -- mirroring the existing "<Provider>
     * API key not configured" pattern -- when Chat_Provider__c='Agentforce'
     * but the Agent ID / My Domain URL fields are not filled in yet.
     */
    private static void assertAgentforceConfigured(GTM_Agent_Settings__c s) {
        if (s == null || String.isBlank(s.Agentforce_Agent_Id__c) || String.isBlank(s.Agentforce_My_Domain_URL__c)) {
            String msg = 'Agentforce is not fully configured yet. Go to Setup → Custom Settings → '
                + 'GTM Agent Settings → Manage, and fill in the Agentforce Agent ID and My Domain URL fields.';
            AuraHandledException ex = new AuraHandledException(msg);
            ex.setMessage(msg);
            throw ex;
        }
    }

    /**
     * Tolerant parse of the Agentforce-shaped historyJson state described in
     * this section's header comment. Any parse failure (blank, garbage left
     * over from a provider switch, an Anthropic-shaped array from before
     * Agentforce was selected) is treated as "no existing session, start a
     * fresh one" -- never throws, matching parseHistory()'s own posture.
     */
    private static Map<String,Object> parseAgentforceState(String historyJson) {
        if (String.isBlank(historyJson)) return new Map<String,Object>();
        try {
            Object parsed = JSON.deserializeUntyped(historyJson);
            if (parsed instanceof Map<String,Object>) {
                return (Map<String,Object>) parsed;
            }
        } catch (Exception e) {
            // Not Agentforce-shaped -- fall through to "no existing session".
        }
        return new Map<String,Object>();
    }

    /**
     * Reads a JSON.deserializeUntyped() numeric value as an Integer, tolerant
     * of the fact that JSON numbers always come back as Double (see the
     * caller's comment) or, defensively, Integer/Decimal/null. Never throws;
     * anything unrecognized reads as 0.
     */
    private static Integer agentforceStateInt(Object raw) {
        if (raw instanceof Integer) return (Integer) raw;
        if (raw instanceof Decimal) return ((Decimal) raw).intValue();
        if (raw instanceof Double) return ((Double) raw).intValue();
        return 0;
    }

    /**
     * Builds the `instanceConfig.endpoint` value for a Start Session request
     * body. MUST end in a trailing slash -- see
     * docs/architecture/gus-chat-provider-settings.md §5a "RESOLVED
     * (2026-09-25, later same day)", item 2: a missing trailing slash on this
     * exact field produced a 404 byte-for-byte indistinguishable from an
     * anonymous/unauthenticated request, root-caused only after four live
     * debugging attempts. GtmAgentSettingsController.setAgentSettings() always
     * STRIPS any trailing slash before storing Agentforce_My_Domain_URL__c, so
     * this normalization is not optional / not "usually already there" -- it
     * must run on every call. Do not inline a raw concatenation at the call
     * site again.
     */
    @TestVisible
    private static String agentforceInstanceEndpoint(String myDomainUrl) {
        String domain = String.isBlank(myDomainUrl) ? '' : myDomainUrl.trim();
        if (String.isBlank(domain)) return domain;
        return domain.endsWith('/') ? domain : domain + '/';
    }

    /**
     * Agent API Start Session. Request shape is the exact one proven live
     * against gtm-staging with a real 200 + sessionId -- see
     * docs/architecture/gus-chat-provider-settings.md §5a "RESOLVED
     * (2026-09-25, later same day)". Auth is handled entirely by the
     * GTM_Agentforce_API Named Credential (generateAuthorizationHeader=true);
     * no Authorization header is set here, matching the proven smoke-test
     * Apex reproduced in that section. `bypassUser: true` is correct and
     * proven for this org's client-credentials setup (task-scope §3.3) --
     * do not add a per-caller variant.
     */
    private static Map<String,Object> callAgentforceStartSession(String agentId, String myDomainUrl) {
        String externalSessionKey = String.valueOf(Crypto.getRandomInteger()) + '-' + String.valueOf(Datetime.now().getTime());
        Map<String,Object> bodyMap = new Map<String,Object>{
            'externalSessionKey'    => externalSessionKey,
            // §5a RESOLVED item 2 (trailing slash) -- see agentforceInstanceEndpoint() above.
            'instanceConfig'        => new Map<String,Object>{ 'endpoint' => agentforceInstanceEndpoint(myDomainUrl) },
            'streamingCapabilities' => new Map<String,Object>{ 'chunkTypes' => new List<String>{ 'Text' } },
            'bypassUser'            => true
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(AGENTFORCE_API_BASE + '/agents/' + agentId + '/sessions');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(bodyMap));
        req.setTimeout(120000);

        HttpResponse resp = new Http().send(req);
        if (resp.getStatusCode() != 200) {
            throw new CalloutException(
                'Agentforce Agent API returned ' + resp.getStatusCode() + ': ' + resp.getBody()
            );
        }
        return (Map<String,Object>) JSON.deserializeUntyped(resp.getBody());
    }

    /**
     * Agent API Send Message.
     *
     * UNVERIFIED SHAPE -- flag for QA/coordinator to browser-verify live
     * before this ships (task-scope §3.1). Official docs 403'd on every fetch
     * attempt from this environment (both the BA's session and this one, same
     * bot-protection block), so this could not be pinned against a live 200
     * the way Start Session was. Built defensively, as close to the proven
     * Start Session pattern as reasonable: same Named Credential/base path,
     * same no-manual-Authorization-header posture, a `{sessionId}/messages`
     * path per the commonly documented Agent API convention (also unverified
     * this session), and a `sequenceId` per the `turnCount` this class already
     * threads through historyJson (see class-section header) in case message
     * ordering matters to the live API. If this shape is wrong, the failure
     * mode is a clean non-200 -> CalloutException (see below), not a silent
     * wrong answer or an uncaught exception -- same as every other provider.
     */
    private static Map<String,Object> callAgentforceSendMessage(String sessionId, String userMessage, Integer sequenceId) {
        Map<String,Object> bodyMap = new Map<String,Object>{
            'message' => new Map<String,Object>{
                'sequenceId' => sequenceId,
                'type'       => 'Text',
                'text'       => userMessage
            }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(AGENTFORCE_API_BASE + '/sessions/' + sessionId + '/messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(bodyMap));
        req.setTimeout(120000);

        HttpResponse resp = new Http().send(req);
        if (resp.getStatusCode() != 200) {
            throw new CalloutException(
                'Agentforce Agent API returned ' + resp.getStatusCode() + ': ' + resp.getBody()
            );
        }
        return (Map<String,Object>) JSON.deserializeUntyped(resp.getBody());
    }

    /**
     * Agent API End Session. UNVERIFIED SHAPE, same caveat as
     * callAgentforceSendMessage() above -- built on the commonly documented
     * `DELETE /sessions/{sessionId}` convention, unconfirmed against a live
     * response this session. `@TestVisible`/not currently called from any
     * runtime path: task-scope §3.2 explicitly leaves "when/whether to end a
     * session" (e.g. wiring gtmAgentChat.js's reset() to call it, vs. relying
     * on the Agent API's own idle-session timeout) as an open product
     * decision for the Architect, not settled by this issue's addendum.
     * Exists here, ready to be wired in once that decision is made -- flagged
     * explicitly in this issue's handback.
     */
    @TestVisible
    private static void callAgentforceEndSession(String sessionId) {
        if (String.isBlank(sessionId)) return;
        HttpRequest req = new HttpRequest();
        req.setEndpoint(AGENTFORCE_API_BASE + '/sessions/' + sessionId);
        req.setMethod('DELETE');
        req.setHeader('x-session-end-reason', 'UserRequest');
        req.setTimeout(120000);
        HttpResponse resp = new Http().send(req);
        if (resp.getStatusCode() >= 300) {
            throw new CalloutException(
                'Agentforce Agent API returned ' + resp.getStatusCode() + ': ' + resp.getBody()
            );
        }
    }

    /**
     * Send-Message response -> reply text. Defensive/tolerant: `messages` is
     * the one list-shaped field the confirmed Start Session response already
     * showed (§5a RESOLVED's live proof), so this assumes Send Message
     * returns the same shape, preferring a `type='Inform'` entry's `message`
     * text (matching that live proof's own welcome-message entry) and falling
     * back to the first non-blank `message` field of any type otherwise. If
     * the real shape differs, this returns null and runAgentforceLoop() above
     * surfaces a clear "did not return a reply" text rather than throwing.
     */
    private static String extractAgentforceReplyText(Map<String,Object> resp) {
        if (resp == null) return null;
        List<Object> messages = (List<Object>) resp.get('messages');
        if (messages == null || messages.isEmpty()) return null;

        String firstAny = null;
        for (Object mObj : messages) {
            if (!(mObj instanceof Map<String,Object>)) continue;
            Map<String,Object> m = (Map<String,Object>) mObj;
            Object text = m.get('message');
            if (!(text instanceof String) || String.isBlank((String) text)) continue;
            if (firstAny == null) firstAny = (String) text;
            if ('Inform'.equals(m.get('type'))) return (String) text;
        }
        return firstAny;
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

    /**
     * 0-arg overload: allowAgentforce=false, i.e. this can never return
     * 'Agentforce' -- every caller except the 4-arg runLoop() (from chat())
     * uses this one.
     */
    private static String getProvider() {
        return getProvider(false);
    }

    /**
     * @param allowAgentforce  see resolveEffectiveProvider(s, allowAgentforce)
     *        below -- true only for the configurator surface's chat() entry
     *        point, threaded down from runLoop()'s own allowAgentforce param.
     */
    private static String getProvider(Boolean allowAgentforce) {
        return resolveEffectiveProvider(GTM_Agent_Settings__c.getOrgDefaults(), allowAgentforce);
    }

    /**
     * 1-arg overload: allowAgentforce=false (today's original, still-correct
     * behavior for chatOnReadout()/chatOnApp()/anything else that doesn't know
     * about surfaces). Kept as its own @TestVisible entry point since existing
     * tests call it directly by this exact signature.
     */
    @TestVisible
    private static String resolveEffectiveProvider(GTM_Agent_Settings__c s) {
        return resolveEffectiveProvider(s, false);
    }

    /**
     * Surface-aware fork of the provider resolution -- see
     * task-scope-gus-live-agentforce-provider-runtime.md §6 Fork 2 ("DECIDED
     * -- configurator chat surface only"). `allowAgentforce=true` is passed
     * ONLY by chat()/ConfigSurface's path through runLoop(); every other
     * caller passes false and gets EXACTLY today's pre-runtime-issue
     * behavior, unchanged:
     *
     * Blank -> Anthropic. When allowAgentforce is false, 'Agentforce' resolves
     * statelessly to Anthropic if it has a key, else OpenAI if it has a key,
     * else Gemini if it has a key, else Anthropic (which then surfaces the
     * existing "Claude API key not configured" error) -- Agentforce is never
     * called on that path. When allowAgentforce is true, 'Agentforce' is
     * returned as-is (unresolved) so runLoop() can route to the real Agent API
     * adapter instead. Any other stored value passes through unchanged in
     * both cases. Never throws on the provider value.
     */
    @TestVisible
    private static String resolveEffectiveProvider(GTM_Agent_Settings__c s, Boolean allowAgentforce) {
        String p = s?.Chat_Provider__c;
        if (String.isBlank(p)) return PROVIDER_ANTHROPIC;
        if (!PROVIDER_AGENTFORCE.equals(p)) return p;
        if (allowAgentforce == true) return PROVIDER_AGENTFORCE;
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
