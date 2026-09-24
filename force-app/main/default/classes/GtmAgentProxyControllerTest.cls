@IsTest
private class GtmAgentProxyControllerTest {

    // ── Mock HTTP callout support ───────────────────────────────────────────

    /**
     * Returns responses[0], responses[1], ... in order across successive
     * calls in the same test, repeating the last entry once the list is
     * exhausted (handy for a tool-loop that keeps calling the same tool).
     */
    private class SequencedMock implements HttpCalloutMock {
        List<HttpResponse> responses;
        List<HttpRequest> capturedRequests = new List<HttpRequest>();
        Integer callCount = 0;

        SequencedMock(List<HttpResponse> responses) {
            this.responses = responses;
        }

        public HttpResponse respond(HttpRequest req) {
            capturedRequests.add(req);
            Integer idx = Math.min(callCount, responses.size() - 1);
            callCount++;
            return responses[idx];
        }
    }

    private static HttpResponse jsonResponse(Integer statusCode, String body) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(body);
        return res;
    }

    private static HttpResponse endTurnResponse(String text) {
        return jsonResponse(200, JSON.serialize(new Map<String,Object>{
            'stop_reason' => 'end_turn',
            'content' => new List<Object>{
                new Map<String,Object>{ 'type' => 'text', 'text' => text }
            }
        }));
    }

    private static HttpResponse toolUseResponse(String toolId, String toolName, Map<String,Object> input) {
        return jsonResponse(200, JSON.serialize(new Map<String,Object>{
            'stop_reason' => 'tool_use',
            'content' => new List<Object>{
                new Map<String,Object>{
                    'type'  => 'tool_use',
                    'id'    => toolId,
                    'name'  => toolName,
                    'input' => input
                }
            }
        }));
    }

    private static void seedApiKey() {
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Claude_API_Key__c = 'test-api-key-123'
        );
    }

    private static void seedOpenAiApiKey() {
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Chat_Provider__c = 'OpenAI',
            OpenAI_API_Key__c = 'sk-test-openai-key-123'
        );
    }

    // ── OpenAI Chat Completions response builders ───────────────────────────

    private static HttpResponse openAiEndTurnResponse(String text) {
        return jsonResponse(200, JSON.serialize(new Map<String,Object>{
            'choices' => new List<Object>{
                new Map<String,Object>{
                    'finish_reason' => 'stop',
                    'message' => new Map<String,Object>{
                        'role'    => 'assistant',
                        'content' => text
                    }
                }
            }
        }));
    }

    private static HttpResponse openAiToolCallResponse(String toolCallId, String toolName, Map<String,Object> input) {
        return jsonResponse(200, JSON.serialize(new Map<String,Object>{
            'choices' => new List<Object>{
                new Map<String,Object>{
                    'finish_reason' => 'tool_calls',
                    'message' => new Map<String,Object>{
                        'role' => 'assistant',
                        'content' => null,
                        'tool_calls' => new List<Object>{
                            new Map<String,Object>{
                                'id'   => toolCallId,
                                'type' => 'function',
                                'function' => new Map<String,Object>{
                                    'name'      => toolName,
                                    'arguments' => JSON.serialize(input)
                                }
                            }
                        }
                    }
                }
            }
        }));
    }

    // ── API key gate ─────────────────────────────────────────────────────────

    @IsTest
    static void chat_noApiKeyConfigured_throwsAuraHandledException() {
        Boolean threw = false;
        Test.startTest();
        try {
            GtmAgentProxyController.chat('tok', '', 'Hi', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A missing Claude API key should be rejected before any callout');
    }

    // ── Simple end_turn round trip ──────────────────────────────────────────

    @IsTest
    static void chat_endTurnResponse_returnsAssistantTextAndEmptyChanges() {
        seedApiKey();
        Test.setMock(HttpCalloutMock.class, new SequencedMock(
            new List<HttpResponse>{ endTurnResponse('Hello! How can I help?') }
        ));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok1', '', 'Hi there', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('Hello! How can I help?', (String) parsed.get('text'));

        Map<String,Object> changes = (Map<String,Object>) parsed.get('changes');
        Assert.isTrue(changes.isEmpty(), 'No tool calls were made, so no changes should accumulate');

        List<Object> history = (List<Object>) JSON.deserializeUntyped((String) parsed.get('historyJson'));
        Assert.areEqual(2, history.size(), 'History should contain the user turn and the assistant turn');
    }

    @IsTest
    static void chat_malformedPriorHistory_startsFreshInsteadOfFailing() {
        seedApiKey();
        Test.setMock(HttpCalloutMock.class, new SequencedMock(
            new List<HttpResponse>{ endTurnResponse('OK') }
        ));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok1', '', 'Hi', 'not valid json {{');
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        List<Object> history = (List<Object>) JSON.deserializeUntyped((String) parsed.get('historyJson'));
        Assert.areEqual(2, history.size(), 'Malformed prior history should be discarded, not appended to');
    }

    @IsTest
    static void chat_usesConfiguredModelOverride() {
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Claude_API_Key__c = 'test-api-key-123',
            Claude_Model__c = 'claude-custom-model-9'
        );
        SequencedMock mock = new SequencedMock(new List<HttpResponse>{ endTurnResponse('Hi') });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GtmAgentProxyController.chat('tok1', '', 'Hi', null);
        Test.stopTest();

        Assert.areEqual(1, mock.capturedRequests.size());
        Map<String,Object> sentBody =
            (Map<String,Object>) JSON.deserializeUntyped(mock.capturedRequests[0].getBody());
        Assert.areEqual('claude-custom-model-9', (String) sentBody.get('model'),
            'The configured Claude_Model__c override should be sent, not the hardcoded default');
    }

    // ── get_gtm_config_state tool ────────────────────────────────────────────

    @IsTest
    static void chat_toolUseGetState_thenEndTurn_returnsPageStateAndFinalText() {
        seedApiKey();
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            toolUseResponse('toolu_1', 'get_gtm_config_state', new Map<String,Object>()),
            endTurnResponse('Config loaded.')
        }));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok2', '', 'What is my current config?', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('Config loaded.', (String) parsed.get('text'));

        List<Object> history = (List<Object>) JSON.deserializeUntyped((String) parsed.get('historyJson'));
        Assert.areEqual(4, history.size(),
            'user, assistant tool_use, user tool_result, assistant text');

        Map<String,Object> toolResultTurn = (Map<String,Object>) history[2];
        List<Object> toolResultContent = (List<Object>) toolResultTurn.get('content');
        Map<String,Object> toolResultBlock = (Map<String,Object>) toolResultContent[0];
        String toolResultJson = (String) toolResultBlock.get('content');
        Assert.isTrue(
            toolResultJson.contains('availableIndustries'),
            'The tool result should carry the page state payload back to Claude'
        );
    }

    @IsTest
    static void chat_toolUseGetState_toolProvidedConfigIdIsIgnored() {
        seedApiKey();
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Config_Payload__c = '{"company":"Acme","industry":"tech","accent":"#FF5733","objectsCount":800,"depsCount":120,"healthScore":72,"note":"Test note"}'
        );
        insert cfg;

        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            toolUseResponse('toolu_1', 'get_gtm_config_state', new Map<String,Object>{ 'config_id' => cfg.Id }),
            endTurnResponse('Got it.')
        }));

        Test.startTest();
        // The chat-level (session) configId is blank; the model supplies its
        // own config_id, which executeGetState must IGNORE (a model must not
        // be able to point the tool at another rep's link).
        String resultJson = GtmAgentProxyController.chat('tok3', '', 'Load Acme', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        List<Object> history = (List<Object>) JSON.deserializeUntyped((String) parsed.get('historyJson'));
        Map<String,Object> toolResultTurn = (Map<String,Object>) history[2];
        List<Object> toolResultContent = (List<Object>) toolResultTurn.get('content');
        Map<String,Object> toolResultBlock = (Map<String,Object>) toolResultContent[0];
        String toolResultJson = (String) toolResultBlock.get('content');

        Assert.isTrue(
            !toolResultJson.contains('Acme'),
            'A model-supplied config_id must be ignored; only the session configId is used'
        );
    }

    // ── apply_gtm_config_update tool ─────────────────────────────────────────

    @IsTest
    static void chat_toolUseApplyUpdate_validDelta_accumulatesChanges() {
        seedApiKey();
        Map<String,Object> input = new Map<String,Object>{
            'updates_json' => JSON.serialize(new Map<String,Object>{ 'company' => 'Acme Corp', 'healthScore' => 85 })
        };
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            toolUseResponse('toolu_2', 'apply_gtm_config_update', input),
            endTurnResponse('Updated the config.')
        }));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok4', '', 'Set company to Acme Corp', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('Updated the config.', (String) parsed.get('text'));

        Map<String,Object> changes = (Map<String,Object>) parsed.get('changes');
        Assert.areEqual('Acme Corp', (String) changes.get('company'));
        Assert.areEqual(85, (Integer) changes.get('healthScore'));
    }

    @IsTest
    static void chat_toolUseApplyUpdate_invalidField_returnsErrorAndAccumulatesNothing() {
        seedApiKey();
        Map<String,Object> input = new Map<String,Object>{
            'updates_json' => JSON.serialize(new Map<String,Object>{ 'accent' => 'not-a-hex-color' })
        };
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            toolUseResponse('toolu_3', 'apply_gtm_config_update', input),
            endTurnResponse('That accent value is invalid.')
        }));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok5', '', 'Set accent to bogus', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Map<String,Object> changes = (Map<String,Object>) parsed.get('changes');
        Assert.isTrue(changes.isEmpty(), 'An invalid field must not be accumulated into changes');

        List<Object> history = (List<Object>) JSON.deserializeUntyped((String) parsed.get('historyJson'));
        Map<String,Object> toolResultTurn = (Map<String,Object>) history[2];
        List<Object> toolResultContent = (List<Object>) toolResultTurn.get('content');
        Map<String,Object> toolResultBlock = (Map<String,Object>) toolResultContent[0];
        String toolResultJson = (String) toolResultBlock.get('content');
        Assert.isTrue(toolResultJson.contains('"success":false'), 'The tool result should report failure');
        Assert.isTrue(toolResultJson.contains('hex'), 'The error should explain the hex color requirement');
    }

    @IsTest
    static void chat_toolUseApplyUpdate_blankUpdatesJson_returnsRequiredError() {
        seedApiKey();
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            toolUseResponse('toolu_4', 'apply_gtm_config_update', new Map<String,Object>()),
            endTurnResponse('I need more detail.')
        }));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok6', '', 'Update something', null);
        Test.stopTest();

        List<Object> history =
            (List<Object>) JSON.deserializeUntyped((String) ((Map<String,Object>) JSON.deserializeUntyped(resultJson)).get('historyJson'));
        Map<String,Object> toolResultTurn = (Map<String,Object>) history[2];
        List<Object> toolResultContent = (List<Object>) toolResultTurn.get('content');
        Map<String,Object> toolResultBlock = (Map<String,Object>) toolResultContent[0];
        String toolResultJson = (String) toolResultBlock.get('content');
        Assert.isTrue(
            toolResultJson.contains('updates_json is required'),
            'A missing updates_json field should be rejected with a clear message'
        );
    }

    @IsTest
    static void chat_toolUseApplyUpdate_malformedJson_returnsParseError() {
        seedApiKey();
        Map<String,Object> input = new Map<String,Object>{ 'updates_json' => 'not { valid json' };
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            toolUseResponse('toolu_5', 'apply_gtm_config_update', input),
            endTurnResponse('That did not parse.')
        }));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok7', '', 'Update with garbage', null);
        Test.stopTest();

        List<Object> history =
            (List<Object>) JSON.deserializeUntyped((String) ((Map<String,Object>) JSON.deserializeUntyped(resultJson)).get('historyJson'));
        Map<String,Object> toolResultTurn = (Map<String,Object>) history[2];
        List<Object> toolResultContent = (List<Object>) toolResultTurn.get('content');
        Map<String,Object> toolResultBlock = (Map<String,Object>) toolResultContent[0];
        String toolResultJson = (String) toolResultBlock.get('content');
        Assert.isTrue(
            toolResultJson.contains('not valid JSON'),
            'Malformed updates_json should be reported as a JSON parse failure'
        );
    }

    @IsTest
    static void chat_toolUseApplyUpdate_allKeysUnrecognized_returnsNoRecognisedFieldsError() {
        seedApiKey();
        Map<String,Object> input = new Map<String,Object>{
            'updates_json' => JSON.serialize(new Map<String,Object>{ 'notARealField' => 'x' })
        };
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            toolUseResponse('toolu_6', 'apply_gtm_config_update', input),
            endTurnResponse('Nothing recognised.')
        }));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok8', '', 'Update notARealField', null);
        Test.stopTest();

        List<Object> history =
            (List<Object>) JSON.deserializeUntyped((String) ((Map<String,Object>) JSON.deserializeUntyped(resultJson)).get('historyJson'));
        Map<String,Object> toolResultTurn = (Map<String,Object>) history[2];
        List<Object> toolResultContent = (List<Object>) toolResultTurn.get('content');
        Map<String,Object> toolResultBlock = (Map<String,Object>) toolResultContent[0];
        String toolResultJson = (String) toolResultBlock.get('content');
        Assert.isTrue(
            toolResultJson.contains('No recognised or valid fields'),
            'Unknown-only keys should be reported distinctly from a validation failure'
        );
    }

    // ── Unknown tool / unexpected stop reason ────────────────────────────────

    @IsTest
    static void chat_unknownToolName_reportsErrorButConversationContinues() {
        seedApiKey();
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            toolUseResponse('toolu_7', 'bogus_tool', new Map<String,Object>()),
            endTurnResponse('Sorry, I cannot do that.')
        }));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok9', '', 'Do something unsupported', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('Sorry, I cannot do that.', (String) parsed.get('text'));

        List<Object> history = (List<Object>) JSON.deserializeUntyped((String) parsed.get('historyJson'));
        Map<String,Object> toolResultTurn = (Map<String,Object>) history[2];
        List<Object> toolResultContent = (List<Object>) toolResultTurn.get('content');
        Map<String,Object> toolResultBlock = (Map<String,Object>) toolResultContent[0];
        String toolResultJson = (String) toolResultBlock.get('content');
        Assert.isTrue(
            toolResultJson.contains('Unknown tool: bogus_tool'),
            'An unrecognised tool name should produce an explicit error, not a silent failure'
        );
    }

    @IsTest
    static void chat_unexpectedStopReason_returnsGenericFallbackMessage() {
        seedApiKey();
        HttpResponse weird = jsonResponse(200, JSON.serialize(new Map<String,Object>{
            'stop_reason' => 'max_tokens',
            'content' => new List<Object>()
        }));
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{ weird }));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok10', '', 'Hi', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual(
            'I received an unexpected response. Please try again.',
            (String) parsed.get('text')
        );
    }

    @IsTest
    static void chat_exceedsMaxToolRounds_returnsStepLimitMessage() {
        seedApiKey();
        // A single tool_use response is repeated for every round by
        // SequencedMock, so the loop never reaches end_turn and must fall
        // back to the step-limit message after MAX_TOOL_ROUNDS iterations.
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            toolUseResponse('toolu_8', 'get_gtm_config_state', new Map<String,Object>())
        }));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok11', '', 'Keep going', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual(
            'I reached my step limit. Please rephrase your request.',
            (String) parsed.get('text')
        );

        List<Object> history = (List<Object>) JSON.deserializeUntyped((String) parsed.get('historyJson'));
        // 1 initial user turn + 5 rounds * (assistant tool_use + user tool_result)
        Assert.areEqual(11, history.size());
    }

    // ── B8: GtmAgentTone.clause() hoisted out of the per-round path ──────────

    @IsTest
    static void toneClauseIsResolvedOnceRegardlessOfRoundCount_notOncePerRound() {
        seedApiKey();
        // Forces every one of the MAX_TOOL_ROUNDS (5) rounds down the
        // tool_use branch, which is exactly the path that used to call
        // GtmAgentTone.clause() -> GtmPageContentReader.getPageContent (one
        // SOQL query) fresh via systemPrompt() on every callClaude().
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            toolUseResponse('toolu_tone', 'get_gtm_config_state', new Map<String,Object>())
        }));

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        GtmAgentProxyController.chat('tok-tone', '', 'Keep going', null);
        Integer queriesAfter = Limits.getQueries();
        Test.stopTest();

        // Each of the 5 rounds also issues one query for the
        // get_gtm_config_state tool itself (GtmAgentGetConfigState.execute),
        // so 5 rounds cost 5 tool queries either way. What must NOT scale
        // with round count is the tone clause read: it should be resolved
        // exactly once per runLoop() turn (before the while loop), not once
        // per round. Assert the total stays at "5 tool queries + 1 tone
        // query", not "5 tool queries + 5 tone queries".
        Assert.isTrue(
            (queriesAfter - queriesBefore) <= 6,
            'GtmAgentTone.clause() must be resolved once per runLoop() turn, not once per tool-use ' +
            'round — expected at most 5 tool queries + 1 tone query, got ' +
            (queriesAfter - queriesBefore) + ' total queries across 5 rounds'
        );
    }

    // ── Zero-DML assertion on tool-surface executeTool ───────────────────────

    @IsTest
    static void applyUpdateToolLeavesZeroDml() {
        seedApiKey();
        // (a) Claude asks to call apply_gtm_config_update with a valid delta
        // (b) Claude then gives a final text reply — the loop must not issue DML
        //     between these two callouts, because callouts are forbidden after DML.
        Map<String,Object> toolInput = new Map<String,Object>{
            'updates_json' => JSON.serialize(new Map<String,Object>{ 'company' => 'Acme' })
        };
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            toolUseResponse('toolu_dml', 'apply_gtm_config_update', toolInput),
            endTurnResponse('Done — company is now Acme.')
        }));

        Test.startTest();
        GtmAgentProxyController.chat('tok-zero-dml', '', 'Set company to Acme', '[]');
        // Assert inside the startTest/stopTest window, on the fresh governor-limit
        // counter that window provides. Asserting after Test.stopTest() reads the
        // OUTER context's DML count instead, which already includes seedApiKey()'s
        // insert above — that pre-existing DML was being misattributed to chat().
        System.assertEquals(0, Limits.getDmlStatements(),
            'ConfigSurface.executeTool must not issue DML; changes must be returned as a JSON delta');
        Test.stopTest();
    }

    // ── Callout failure ──────────────────────────────────────────────────────

    @IsTest
    static void chat_calloutReturnsNon200Status_throwsCalloutException() {
        seedApiKey();
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            jsonResponse(500, 'Internal error')
        }));

        Boolean threw = false;
        String errorMessage;
        Test.startTest();
        try {
            GtmAgentProxyController.chat('tok12', '', 'Hi', null);
        } catch (CalloutException e) {
            threw = true;
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A non-200 Claude API response should surface as a CalloutException');
        Assert.isTrue(errorMessage.contains('500'), 'The status code should be included in the error');
    }

    // ── OpenAI provider path ─────────────────────────────────────────────────

    @IsTest
    static void chat_openAiProvider_noApiKeyConfigured_throwsAuraHandledException() {
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Chat_Provider__c = 'OpenAI'
            // OpenAI_API_Key__c intentionally left blank
        );

        Boolean threw = false;
        Test.startTest();
        try {
            GtmAgentProxyController.chat('tok', '', 'Hi', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A missing OpenAI API key should be rejected before any callout, same as Claude');
    }

    @IsTest
    static void chat_openAiProvider_endTurnResponse_returnsAssistantTextAndEmptyChanges() {
        seedOpenAiApiKey();
        SequencedMock mock = new SequencedMock(
            new List<HttpResponse>{ openAiEndTurnResponse('Hello from OpenAI!') }
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok1', '', 'Hi there', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('Hello from OpenAI!', (String) parsed.get('text'));

        Map<String,Object> changes = (Map<String,Object>) parsed.get('changes');
        Assert.isTrue(changes.isEmpty(), 'No tool calls were made, so no changes should accumulate');

        // Confirm the request actually hit OpenAI's endpoint, with an
        // Authorization bearer header rather than Anthropic's x-api-key shape.
        Assert.areEqual('https://api.openai.com/v1/chat/completions', mock.capturedRequests[0].getEndpoint());
        Assert.areEqual('Bearer sk-test-openai-key-123', mock.capturedRequests[0].getHeader('Authorization'));

        Map<String,Object> sentBody =
            (Map<String,Object>) JSON.deserializeUntyped(mock.capturedRequests[0].getBody());
        Assert.areEqual('gpt-4o', (String) sentBody.get('model'), 'Default OpenAI model should be used when unset');
        List<Object> sentMessages = (List<Object>) sentBody.get('messages');
        Map<String,Object> systemMsg = (Map<String,Object>) sentMessages[0];
        Assert.areEqual('system', (String) systemMsg.get('role'));
    }

    @IsTest
    static void chat_openAiProvider_usesConfiguredModelOverride() {
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Chat_Provider__c = 'OpenAI',
            OpenAI_API_Key__c = 'sk-test-openai-key-123',
            OpenAI_Model__c = 'gpt-4o-mini'
        );
        SequencedMock mock = new SequencedMock(new List<HttpResponse>{ openAiEndTurnResponse('Hi') });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GtmAgentProxyController.chat('tok1', '', 'Hi', null);
        Test.stopTest();

        Map<String,Object> sentBody =
            (Map<String,Object>) JSON.deserializeUntyped(mock.capturedRequests[0].getBody());
        Assert.areEqual('gpt-4o-mini', (String) sentBody.get('model'),
            'The configured OpenAI_Model__c override should be sent, not the hardcoded default');
    }

    @IsTest
    static void chat_openAiProvider_toolUse_thenEndTurn_executesToolAndReturnsFinalText() {
        seedOpenAiApiKey();
        SequencedMock mock = new SequencedMock(new List<HttpResponse>{
            openAiToolCallResponse('call_1', 'get_gtm_config_state', new Map<String,Object>()),
            openAiEndTurnResponse('Config loaded via OpenAI.')
        });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok2', '', 'What is my current config?', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('Config loaded via OpenAI.', (String) parsed.get('text'));

        // The tool result from round 1 must be translated back into a proper
        // OpenAI 'tool' role message (with tool_call_id) for round 2's request.
        Map<String,Object> secondRequestBody =
            (Map<String,Object>) JSON.deserializeUntyped(mock.capturedRequests[1].getBody());
        List<Object> messages = (List<Object>) secondRequestBody.get('messages');
        Boolean foundToolMessage = false;
        for (Object m : messages) {
            Map<String,Object> msg = (Map<String,Object>) m;
            if ('tool'.equals(msg.get('role'))) {
                foundToolMessage = true;
                Assert.areEqual('call_1', (String) msg.get('tool_call_id'));
                Assert.isTrue(((String) msg.get('content')).contains('availableIndustries'));
            }
        }
        Assert.isTrue(foundToolMessage, 'The tool_result must round-trip into OpenAI\'s tool-role message shape');
    }

    @IsTest
    static void chat_openAiProvider_toolUseApplyUpdate_validDelta_accumulatesChanges() {
        seedOpenAiApiKey();
        Map<String,Object> input = new Map<String,Object>{
            'updates_json' => JSON.serialize(new Map<String,Object>{ 'company' => 'Acme Corp', 'healthScore' => 85 })
        };
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            openAiToolCallResponse('call_2', 'apply_gtm_config_update', input),
            openAiEndTurnResponse('Updated the config.')
        }));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok4', '', 'Set company to Acme Corp', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('Updated the config.', (String) parsed.get('text'));

        Map<String,Object> changes = (Map<String,Object>) parsed.get('changes');
        Assert.areEqual('Acme Corp', (String) changes.get('company'));
        Assert.areEqual(85, (Integer) changes.get('healthScore'));
    }

    @IsTest
    static void chat_openAiProvider_multiToolCallsInOneRound_executesEachAndRoundTripsBoth() {
        seedOpenAiApiKey();
        HttpResponse multiToolResponse = jsonResponse(200, JSON.serialize(new Map<String,Object>{
            'choices' => new List<Object>{
                new Map<String,Object>{
                    'finish_reason' => 'tool_calls',
                    'message' => new Map<String,Object>{
                        'role' => 'assistant',
                        'content' => null,
                        'tool_calls' => new List<Object>{
                            new Map<String,Object>{
                                'id'   => 'call_a',
                                'type' => 'function',
                                'function' => new Map<String,Object>{
                                    'name'      => 'get_gtm_config_state',
                                    'arguments' => JSON.serialize(new Map<String,Object>())
                                }
                            },
                            new Map<String,Object>{
                                'id'   => 'call_b',
                                'type' => 'function',
                                'function' => new Map<String,Object>{
                                    'name'      => 'apply_gtm_config_update',
                                    'arguments' => JSON.serialize(new Map<String,Object>{
                                        'updates_json' => JSON.serialize(new Map<String,Object>{ 'company' => 'Multi Inc' })
                                    })
                                }
                            }
                        }
                    }
                }
            }
        }));
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            multiToolResponse,
            openAiEndTurnResponse('Both tools ran.')
        }));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok-multi', '', 'Do two things', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('Both tools ran.', (String) parsed.get('text'));
        Map<String,Object> changes = (Map<String,Object>) parsed.get('changes');
        Assert.areEqual('Multi Inc', (String) changes.get('company'),
            'Both tool calls in a single OpenAI round must be executed via the unchanged surface contract');
    }

    @IsTest
    static void chat_openAiProvider_malformedToolCallArguments_doesNotThrow() {
        seedOpenAiApiKey();
        HttpResponse malformedArgsResponse = jsonResponse(200, JSON.serialize(new Map<String,Object>{
            'choices' => new List<Object>{
                new Map<String,Object>{
                    'finish_reason' => 'tool_calls',
                    'message' => new Map<String,Object>{
                        'role' => 'assistant',
                        'content' => null,
                        'tool_calls' => new List<Object>{
                            new Map<String,Object>{
                                'id'   => 'call_bad',
                                'type' => 'function',
                                'function' => new Map<String,Object>{
                                    'name'      => 'apply_gtm_config_update',
                                    'arguments' => 'not { valid json'
                                }
                            }
                        }
                    }
                }
            }
        }));
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            malformedArgsResponse,
            openAiEndTurnResponse('Handled the malformed call.')
        }));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok-bad-args', '', 'Trigger malformed args', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('Handled the malformed call.', (String) parsed.get('text'),
            'Malformed function-call arguments from OpenAI must degrade to a tool error, not an exception');
    }

    @IsTest
    static void chat_openAiProvider_unsupportedFinishReason_returnsGenericFallbackMessage() {
        seedOpenAiApiKey();
        HttpResponse lengthCut = jsonResponse(200, JSON.serialize(new Map<String,Object>{
            'choices' => new List<Object>{
                new Map<String,Object>{
                    'finish_reason' => 'length',
                    'message' => new Map<String,Object>{ 'role' => 'assistant', 'content' => null }
                }
            }
        }));
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{ lengthCut }));

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok-length', '', 'Hi', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual(
            'I received an unexpected response. Please try again.',
            (String) parsed.get('text'),
            'A non-stop/non-tool_calls finish_reason must fall back the same way Anthropic\'s non-standard stop reasons do'
        );
    }

    @IsTest
    static void chat_openAiProvider_calloutReturnsNon200Status_throwsCalloutException() {
        seedOpenAiApiKey();
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            jsonResponse(500, 'Internal error')
        }));

        Boolean threw = false;
        String errorMessage;
        Test.startTest();
        try {
            GtmAgentProxyController.chat('tok12', '', 'Hi', null);
        } catch (CalloutException e) {
            threw = true;
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A non-200 OpenAI API response should surface as a CalloutException');
        Assert.isTrue(errorMessage.contains('500'), 'The status code should be included in the error');
    }

    // ── Zero-DML contract holds identically on the OpenAI path ──────────────

    @IsTest
    static void openAiApplyUpdateToolLeavesZeroDml() {
        seedOpenAiApiKey();
        Map<String,Object> toolInput = new Map<String,Object>{
            'updates_json' => JSON.serialize(new Map<String,Object>{ 'company' => 'Acme' })
        };
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            openAiToolCallResponse('call_dml', 'apply_gtm_config_update', toolInput),
            openAiEndTurnResponse('Done — company is now Acme.')
        }));

        Test.startTest();
        GtmAgentProxyController.chat('tok-zero-dml-openai', '', 'Set company to Acme', '[]');
        System.assertEquals(0, Limits.getDmlStatements(),
            'ConfigSurface.executeTool must not issue DML on the OpenAI path either — same zero-DML contract as Anthropic');
        Test.stopTest();
    }

    // ── Back-compat: default/blank Chat_Provider__c behaves exactly as before ─

    @IsTest
    static void chat_blankChatProviderField_stillUsesAnthropicPath() {
        // Chat_Provider__c is explicitly blank here (not even 'Anthropic'
        // literal) -- getProvider() must treat blank the same as unset.
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Claude_API_Key__c = 'test-api-key-123',
            Chat_Provider__c = null
        );
        SequencedMock mock = new SequencedMock(
            new List<HttpResponse>{ endTurnResponse('Still Claude.') }
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok-blank-provider', '', 'Hi', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('Still Claude.', (String) parsed.get('text'));
        Assert.areEqual('https://api.anthropic.com/v1/messages', mock.capturedRequests[0].getEndpoint());
    }

    // ── Gemini provider path ─────────────────────────────────────────────────

    private static void seedGemini() {
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Chat_Provider__c = 'Gemini',
            Gemini_API_Key__c = 'gm-test-key-123'
        );
    }

    private static HttpResponse geminiTextResponse(String text) {
        return jsonResponse(200, JSON.serialize(new Map<String,Object>{
            'candidates' => new List<Object>{
                new Map<String,Object>{
                    'finishReason' => 'STOP',
                    'content' => new Map<String,Object>{
                        'role'  => 'model',
                        'parts' => new List<Object>{ new Map<String,Object>{ 'text' => text } }
                    }
                }
            }
        }));
    }

    private static HttpResponse geminiFunctionCallResponse(String name, Map<String,Object> args) {
        return jsonResponse(200, JSON.serialize(new Map<String,Object>{
            'candidates' => new List<Object>{
                new Map<String,Object>{
                    'finishReason' => 'STOP',
                    'content' => new Map<String,Object>{
                        'role'  => 'model',
                        'parts' => new List<Object>{
                            new Map<String,Object>{ 'functionCall' => new Map<String,Object>{ 'name' => name, 'args' => args } }
                        }
                    }
                }
            }
        }));
    }

    @IsTest
    static void chat_geminiProvider_noApiKeyConfigured_throwsAuraHandledException() {
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Chat_Provider__c = 'Gemini'
        );
        Boolean threw = false;
        Test.startTest();
        try {
            GtmAgentProxyController.chat('tok', '', 'Hi', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw, 'A missing Gemini key must be rejected before any callout');
    }

    @IsTest
    static void chat_geminiProvider_textResponse_sendsCorrectRequest() {
        seedGemini();
        SequencedMock mock = new SequencedMock(new List<HttpResponse>{ geminiTextResponse('Hello from Gemini!') });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok', '', 'Hi there', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('Hello from Gemini!', (String) parsed.get('text'));

        HttpRequest req = mock.capturedRequests[0];
        Assert.areEqual(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
            req.getEndpoint(), 'Default model goes in the path');
        Assert.areEqual('gm-test-key-123', req.getHeader('x-goog-api-key'));
        Assert.isFalse(req.getEndpoint().contains('key='), 'The key must not be in the URL');
        Assert.isFalse(req.getBody().contains('gm-test-key-123'), 'The key must not be in the body');

        Map<String,Object> body = (Map<String,Object>) JSON.deserializeUntyped(req.getBody());
        Map<String,Object> sysInstr = (Map<String,Object>) body.get('systemInstruction');
        Assert.isNotNull(sysInstr.get('parts'));
        List<Object> contents = (List<Object>) body.get('contents');
        Map<String,Object> first = (Map<String,Object>) contents[0];
        Assert.areEqual('user', (String) first.get('role'));

        List<Object> tools = (List<Object>) body.get('tools');
        Map<String,Object> toolBlock = (Map<String,Object>) tools[0];
        List<Object> decls = (List<Object>) toolBlock.get('functionDeclarations');
        Assert.areEqual(2, decls.size());
        for (Object d : decls) {
            Map<String,Object> decl = (Map<String,Object>) d;
            if ('get_gtm_config_state'.equals(decl.get('name'))) {
                Map<String,Object> params = (Map<String,Object>) decl.get('parameters');
                Assert.isFalse(params.containsKey('required'), 'Empty required must be omitted for Gemini');
            }
        }
    }

    @IsTest
    static void chat_geminiProvider_usesConfiguredModelOverride() {
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Chat_Provider__c = 'Gemini',
            Gemini_API_Key__c = 'gm-test-key-123',
            Gemini_Model__c = 'gemini-2.5-pro'
        );
        SequencedMock mock = new SequencedMock(new List<HttpResponse>{ geminiTextResponse('Hi') });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GtmAgentProxyController.chat('tok', '', 'Hi', null);
        Test.stopTest();

        Assert.isTrue(mock.capturedRequests[0].getEndpoint().contains('/models/gemini-2.5-pro:generateContent'));
    }

    @IsTest
    static void chat_geminiProvider_functionCallRoundTrip_zeroDml() {
        seedGemini();
        Map<String,Object> args = new Map<String,Object>{
            'updates_json' => JSON.serialize(new Map<String,Object>{ 'company' => 'Acme Gemini' })
        };
        SequencedMock mock = new SequencedMock(new List<HttpResponse>{
            geminiFunctionCallResponse('apply_gtm_config_update', args),
            geminiTextResponse('Updated via Gemini.')
        });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok-gem', '', 'Set company to Acme Gemini', '[]');
        Integer dml = Limits.getDmlStatements();
        Test.stopTest();

        Assert.areEqual(0, dml, 'A Gemini tool round must issue no DML');
        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('Updated via Gemini.', (String) parsed.get('text'));
        Map<String,Object> changes = (Map<String,Object>) parsed.get('changes');
        Assert.areEqual('Acme Gemini', (String) changes.get('company'));

        // Round 2 request: model functionCall + user functionResponse with the
        // name resolved from the synthesised gemini_0 tool_use id.
        Map<String,Object> body2 = (Map<String,Object>) JSON.deserializeUntyped(mock.capturedRequests[1].getBody());
        List<Object> contents = (List<Object>) body2.get('contents');
        Assert.areEqual(3, contents.size());
        Map<String,Object> modelTurn = (Map<String,Object>) contents[1];
        Assert.areEqual('model', (String) modelTurn.get('role'));
        Map<String,Object> fcPart = (Map<String,Object>) ((List<Object>) modelTurn.get('parts'))[0];
        Assert.areEqual('apply_gtm_config_update', (String) ((Map<String,Object>) fcPart.get('functionCall')).get('name'));
        Map<String,Object> userTurn = (Map<String,Object>) contents[2];
        Assert.areEqual('user', (String) userTurn.get('role'));
        Map<String,Object> frPart = (Map<String,Object>) ((List<Object>) userTurn.get('parts'))[0];
        Map<String,Object> fr = (Map<String,Object>) frPart.get('functionResponse');
        Assert.areEqual('apply_gtm_config_update', (String) fr.get('name'));
        Assert.isNotNull(((Map<String,Object>) fr.get('response')).get('result'));

        // Stored history uses the synthesised id in Anthropic shape.
        Assert.isTrue(((String) parsed.get('historyJson')).contains('gemini_0'));
    }

    @IsTest
    static void chat_geminiProvider_noCandidates_doesNotThrow() {
        seedGemini();
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            jsonResponse(200, '{"promptFeedback":{"blockReason":"SAFETY"}}')
        }));
        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok', '', 'Hi', null);
        Test.stopTest();
        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('I received an unexpected response. Please try again.', (String) parsed.get('text'));
    }

    @IsTest
    static void chat_geminiProvider_maxTokensFinishReason_returnsGenericFallback() {
        seedGemini();
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            jsonResponse(200, '{"candidates":[{"finishReason":"MAX_TOKENS","content":{"role":"model","parts":[]}}]}')
        }));
        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok', '', 'Hi', null);
        Test.stopTest();
        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('I received an unexpected response. Please try again.', (String) parsed.get('text'));
    }

    @IsTest
    static void chat_geminiProvider_non200_throwsCalloutExceptionWithoutKey() {
        seedGemini();
        Test.setMock(HttpCalloutMock.class, new SequencedMock(new List<HttpResponse>{
            jsonResponse(400, 'Bad request')
        }));
        Boolean threw = false;
        String msg;
        Test.startTest();
        try {
            GtmAgentProxyController.chat('tok', '', 'Hi', null);
        } catch (CalloutException e) {
            threw = true;
            msg = e.getMessage();
        }
        Test.stopTest();
        Assert.isTrue(threw);
        Assert.isTrue(msg.contains('400'));
        Assert.isFalse(msg.contains('gm-test-key-123'), 'The key must never be echoed in an error');
    }

    // ── Agentforce selected: never called, stateless fallback ────────────────

    @IsTest
    static void chat_agentforceSelected_fallsBackToAnthropicWhenItHasAKey() {
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Chat_Provider__c = 'Agentforce',
            Claude_API_Key__c = 'test-api-key-123',
            OpenAI_API_Key__c = 'sk-x'
        );
        SequencedMock mock = new SequencedMock(new List<HttpResponse>{ endTurnResponse('Claude answered.') });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String resultJson = GtmAgentProxyController.chat('tok', '', 'Hi', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        Assert.areEqual('Claude answered.', (String) parsed.get('text'));
        Assert.areEqual('https://api.anthropic.com/v1/messages', mock.capturedRequests[0].getEndpoint());
    }

    @IsTest
    static void chat_agentforceSelected_fallsBackToOpenAiThenGemini() {
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Chat_Provider__c = 'Agentforce',
            OpenAI_API_Key__c = 'sk-x',
            Gemini_API_Key__c = 'gm-x'
        );
        SequencedMock mock = new SequencedMock(new List<HttpResponse>{ openAiEndTurnResponse('OpenAI answered.') });
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        GtmAgentProxyController.chat('tok', '', 'Hi', null);
        Test.stopTest();
        Assert.areEqual('https://api.openai.com/v1/chat/completions', mock.capturedRequests[0].getEndpoint());

        GTM_Agent_Settings__c s = GTM_Agent_Settings__c.getOrgDefaults();
        s.OpenAI_API_Key__c = null;
        update s;
        Assert.areEqual('Gemini', GtmAgentProxyController.resolveEffectiveProvider(s));
    }

    @IsTest
    static void chat_agentforceSelected_noKeysAnywhere_surfacesExistingMissingKeyError() {
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Chat_Provider__c = 'Agentforce'
        );
        Boolean threw = false;
        Test.startTest();
        try {
            GtmAgentProxyController.chat('tok', '', 'Hi', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw, 'No configured provider is the pre-existing missing-key error, not a provider-value failure');
    }
}
