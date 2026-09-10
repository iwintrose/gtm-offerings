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
    static void chat_toolUseGetState_toolProvidedConfigIdOverridesParam() {
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
        // The chat-level configId is blank; the tool call supplies its own,
        // which executeGetState must prefer.
        String resultJson = GtmAgentProxyController.chat('tok3', '', 'Load Acme', null);
        Test.stopTest();

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(resultJson);
        List<Object> history = (List<Object>) JSON.deserializeUntyped((String) parsed.get('historyJson'));
        Map<String,Object> toolResultTurn = (Map<String,Object>) history[2];
        List<Object> toolResultContent = (List<Object>) toolResultTurn.get('content');
        Map<String,Object> toolResultBlock = (Map<String,Object>) toolResultContent[0];
        String toolResultJson = (String) toolResultBlock.get('content');

        Assert.isTrue(
            toolResultJson.contains('"company":"Acme"'),
            'The tool-supplied config_id should be used over the (blank) chat-level configId'
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
}
