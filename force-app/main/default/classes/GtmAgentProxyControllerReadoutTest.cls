/**
 * The readout entry point end to end: access gate, tool round trip, delta out.
 *
 * NO LIVE CALLOUTS. Every Anthropic response is served by a HttpCalloutMock, so
 * these tests never reach api.anthropic.com and never need a real key.
 *
 * NOT RUN. No Salesforce CLI or org was available where this was written, so no
 * Apex in this change has been compiled or executed. Unverified.
 */
@isTest
private class GtmAgentProxyControllerReadoutTest {

    private static final String DRAFT =
        '<h2>Readout</h2><p><strong>Migration readiness:</strong> 18 out of 32</p>' +
        '<h3>What we found</h3><p>Original.</p>';

    /**
     * Replays a queued list of Anthropic responses, one per callout, so a
     * tool_use round followed by an end_turn round can be exercised as the two
     * HTTP calls it really is.
     */
    private class ScriptedClaude implements HttpCalloutMock {
        private final List<String> bodies;
        private Integer index = 0;
        public Integer calls = 0;
        ScriptedClaude(List<String> bodies) { this.bodies = bodies; }

        public HttpResponse respond(HttpRequest req) {
            calls++;
            System.assertEquals('https://api.anthropic.com/v1/messages', req.getEndpoint());
            System.assertNotEquals(null, req.getHeader('x-api-key'), 'the key must be sent server-side');
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(bodies[Math.min(index++, bodies.size() - 1)]);
            return res;
        }
    }

    private static String textTurn(String text) {
        return JSON.serialize(new Map<String, Object>{
            'stop_reason' => 'end_turn',
            'content' => new List<Object>{
                new Map<String, Object>{ 'type' => 'text', 'text' => text }
            }
        });
    }

    private static String toolTurn(String name, Map<String, Object> input) {
        return JSON.serialize(new Map<String, Object>{
            'stop_reason' => 'tool_use',
            'content' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'tool_use', 'id' => 'toolu_1', 'name' => name, 'input' => input
                }
            }
        });
    }

    private static void seedApiKey() {
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Claude_API_Key__c = 'sk-ant-test-key-not-real'
        );
    }

    private static GTM_Readout__c seedReadout() {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c  = 'Alex Rivera',
            Requester_Email__c = 'alex.rivera@example.com',
            Company__c         = 'Northwind Retail',
            Assessment_Score__c = 18,
            Assessment_Tier__c  = 'Prep Required'
        );
        insert req;
        GTM_Readout__c r = new GTM_Readout__c(
            Assessment_Request__c = req.Id, Offering_Key__c = 'migration-accelerator',
            Status__c = 'Draft', Draft_Content__c = DRAFT
        );
        insert r;
        return r;
    }

    @isTest
    static void aToolRoundTripReturnsTextHistoryAndTheProposedDraft() {
        seedApiKey();
        GTM_Readout__c r = seedReadout();

        ScriptedClaude mock = new ScriptedClaude(new List<String>{
            toolTurn('update_readout_draft', new Map<String, Object>{
                'mode' => 'replace_section',
                'section_heading' => 'What we found',
                'html' => '<p>Procurement is the real blocker.</p>'
            }),
            textTurn('Updated "What we found". Nothing is saved yet — click Save Draft.')
        });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String out = GtmAgentProxyController.chatOnReadout(
            r.Id, DRAFT, 'Fold in what I told you about procurement.', null
        );
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(out);
        Map<String, Object> changes = (Map<String, Object>) parsed.get('changes');

        System.assertEquals(2, mock.calls, 'one callout for the tool round, one for the reply');
        System.assert(String.valueOf(parsed.get('text')).contains('Save Draft'));
        System.assert(String.valueOf(changes.get('draftContent')).containsIgnoreCase('procurement'));
        System.assert(String.valueOf(changes.get('draftContent')).contains('18 out of 32'),
            'the scores must survive a section edit made through the loop');
        System.assertNotEquals(null, parsed.get('historyJson'));

        // The record itself is untouched: the rep saves, not the loop.
        System.assertEquals(DRAFT,
            [SELECT Draft_Content__c FROM GTM_Readout__c WHERE Id = :r.Id].Draft_Content__c);
    }

    @isTest
    static void aPlainAnswerCarriesNoDelta() {
        seedApiKey();
        GTM_Readout__c r = seedReadout();
        Test.setMock(HttpCalloutMock.class,
            new ScriptedClaude(new List<String>{ textTurn('Their tier is Prep Required.') }));

        Test.startTest();
        String out = GtmAgentProxyController.chatOnReadout(r.Id, DRAFT, 'What tier are they?', null);
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(out);
        System.assertEquals(0, ((Map<String, Object>) parsed.get('changes')).size());
    }

    @isTest
    static void aBlankReadoutIdIsRejectedBeforeAnyCallout() {
        seedApiKey();
        Test.setMock(HttpCalloutMock.class, new ScriptedClaude(new List<String>{ textTurn('x') }));
        Boolean threw = false;
        try {
            GtmAgentProxyController.chatOnReadout(null, DRAFT, 'hello', null);
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void aUserWithoutAccessIsRefusedBeforeAnyCallout() {
        seedApiKey();
        GTM_Readout__c r = seedReadout();

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User stranger = new User(
            Alias = 'gtmpx1', Email = 'gtmpx1@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'Stranger', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = 'gtmpx1' + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) { insert stranger; }

        ScriptedClaude mock = new ScriptedClaude(new List<String>{ textTurn('x') });
        Test.setMock(HttpCalloutMock.class, mock);

        Boolean threw = false;
        System.runAs(stranger) {
            try {
                GtmAgentProxyController.chatOnReadout(r.Id, DRAFT, 'show me the draft', null);
            } catch (Exception e) {
                threw = true;
            }
        }
        System.assertEquals(true, threw);
        System.assertEquals(0, mock.calls,
            'a readout the rep cannot see must not cost a callout, let alone return content');
    }

    /**
     * Calls GtmReadoutAgentSurface.executeTool directly — no mock, no callout
     * infrastructure — and asserts that the method neither issues a callout nor
     * touches DML. This proves the architectural constraint: all writes are
     * deferred to the LWC via the accumulatedChanges bag.
     *
     * get_readout_context is the cheapest tool: it takes no arguments and its
     * only side effects are SOQL queries (not callouts, not DML).
     */
    @isTest
    static void readoutSurfaceExecuteToolIssuesNoCallout() {
        GTM_Readout__c r = seedReadout();

        Test.startTest();
        GtmReadoutAgentSurface surf = new GtmReadoutAgentSurface(r.Id, DRAFT);
        surf.executeTool(
            'get_readout_context',
            new Map<String, Object>(),
            new Map<String, Object>()
        );

        System.assertEquals(0, Limits.getCallouts(),
            'GtmReadoutAgentSurface.executeTool must not perform callouts');
        System.assertEquals(0, Limits.getDmlStatements(),
            'GtmReadoutAgentSurface.executeTool must not perform DML');

        Test.stopTest();
    }

    @isTest
    static void aMissingApiKeyIsAnActionableError() {
        GTM_Readout__c r = seedReadout();
        Boolean threw = false;
        try {
            GtmAgentProxyController.chatOnReadout(r.Id, DRAFT, 'hello', null);
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void theConfiguratorEntryPointStillWorksThroughTheSharedLoop() {
        // The refactor moved the loop; the configurator contract must not move.
        seedApiKey();
        Test.setMock(HttpCalloutMock.class,
            new ScriptedClaude(new List<String>{ textTurn('Set the company to Northwind.') }));

        Test.startTest();
        String out = GtmAgentProxyController.chat('tok', null, 'Set company to Northwind', null);
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(out);
        System.assert(parsed.containsKey('text'));
        System.assert(parsed.containsKey('historyJson'));
        System.assert(parsed.containsKey('changes'));
    }

    /**
     * Fork 2 (task-scope-gus-live-agentforce-provider-runtime.md §6, "DECIDED
     * -- configurator chat surface only"): the readout editor must keep
     * routing through the existing stateless Claude/OpenAI/Gemini fallback
     * even when Chat_Provider__c='Agentforce' -- only chat()/ConfigSurface may
     * resolve to the real Agent API. ScriptedClaude.respond() itself asserts
     * the endpoint is api.anthropic.com/v1/messages, so this test would fail
     * outright (mock never invoked / wrong endpoint) if chatOnReadout() were
     * ever changed to attempt the Agentforce path instead.
     */
    @isTest
    static void chatOnReadout_agentforceSelected_stillFallsBackToClaude() {
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Chat_Provider__c = 'Agentforce',
            Claude_API_Key__c = 'sk-ant-test-key-not-real'
        );
        GTM_Readout__c r = seedReadout();
        ScriptedClaude mock = new ScriptedClaude(new List<String>{ textTurn('Their tier is Prep Required.') });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String out = GtmAgentProxyController.chatOnReadout(r.Id, DRAFT, 'What tier are they?', null);
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(out);
        System.assertEquals('Their tier is Prep Required.', (String) parsed.get('text'));
        System.assertEquals(1, mock.calls);
    }
}
