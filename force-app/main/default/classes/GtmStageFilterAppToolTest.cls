/**
 * ISSUE #gus-stage-filter-tool. Contract: docs/architecture/gus-stage-filter-tool.md.
 * Mandatory security coverage: two reps + admin under System.runAs proving the
 * tool never returns another rep's links even though GtmAgentProxyController is
 * `without sharing`.
 */
@IsTest
private class GtmStageFilterAppToolTest {

    // ---- helpers -------------------------------------------------------

    private static User createUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'Tool ' + alias, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    private static void assignPermSet(User u, String permSetName) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :permSetName LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
    }

    private static GTM_Saved_Configuration__c newLink(Id ownerId, String company) {
        return new GTM_Saved_Configuration__c(
            OwnerId = ownerId,
            Offering__c = 'migration-accelerator',
            Company__c = company,
            Generated_URL__c = 'https://secret.example.com/u/' + company.replace(' ', '-'),
            Link_Password__c = 'SECRET-PW-' + company.replace(' ', '-'),
            Presentation_Stage__c = 'Sent',
            Active__c = true
        );
    }

    private static SObject newEvent(Id ownerId, Id linkId, String type, String session) {
        SObject e = Schema.getGlobalDescribe().get('GTM_Link_Event__c').newSObject();
        e.put('OwnerId', ownerId);
        e.put('Saved_Configuration__c', linkId);
        e.put('Event_Type__c', type);
        e.put('Session_Id__c', session);
        return e;
    }

    /**
     * Seeds one owner's links across all seven stages. Returns name -> link.
     * none: not_opened. viewed: one page view (engaged). quiet: form opened.
     * done: form submitted. hot: two sessions now (hot).
     */
    private static Map<String, GTM_Saved_Configuration__c> seedFor(User owner, String tag) {
        Map<String, GTM_Saved_Configuration__c> links = new Map<String, GTM_Saved_Configuration__c>();
        for (String n : new List<String>{ 'none', 'viewed', 'quiet', 'done', 'hot' }) {
            links.put(n, newLink(owner.Id, tag + ' ' + n));
        }
        insert links.values();
        insert new List<SObject>{
            newEvent(owner.Id, links.get('viewed').Id, 'Page View', tag + 'v1'),
            newEvent(owner.Id, links.get('quiet').Id, 'Form Opened', tag + 'q1'),
            newEvent(owner.Id, links.get('done').Id, 'Form Submitted', tag + 'd1'),
            newEvent(owner.Id, links.get('hot').Id, 'Page View', tag + 'h1'),
            newEvent(owner.Id, links.get('hot').Id, 'Page View', tag + 'h2')
        };
        return links;
    }

    private static Map<String, Object> run(String stage, Map<String, Object> acc) {
        return run(new Map<String, Object>{ 'stage' => stage }, acc);
    }

    private static Map<String, Object> run(Map<String, Object> input, Map<String, Object> acc) {
        String out = new GtmStageFilterAppTool().execute(GtmStageFilterAppTool.TOOL_NAME, input, acc);
        return (Map<String, Object>) JSON.deserializeUntyped(out);
    }

    private static List<Id> rowIds(Map<String, Object> result) {
        List<Id> ids = new List<Id>();
        for (Object r : (List<Object>) result.get('rows')) {
            ids.add((Id) ((Map<String, Object>) r).get('id'));
        }
        return ids;
    }

    private static Set<String> companies(Map<String, Object> result) {
        Set<String> names = new Set<String>();
        for (Object r : (List<Object>) result.get('rows')) {
            names.add((String) ((Map<String, Object>) r).get('company'));
        }
        return names;
    }

    // ---- security: two reps + admin ------------------------------------

    @IsTest
    static void repNeverReceivesAnotherRepsLinksAndAdminSeesBoth() {
        User repA = createUser('gsfta');
        User repB = createUser('gsftb');
        User admin = createUser('gsftc');
        assignPermSet(repA, 'GTM_Offering_User');
        assignPermSet(repB, 'GTM_Offering_User');
        assignPermSet(admin, 'GTM_Offering_Admin');
        seedFor(repA, 'AAA');
        seedFor(repB, 'BBB');

        Map<String, Integer> expected = new Map<String, Integer>{
            'sent' => 5, 'not_opened' => 1, 'engaged' => 4, 'started' => 2,
            'submitted' => 1, 'quiet' => 1, 'hot' => 1
        };
        Assert.areEqual(GtmLinkStageService.STAGE_KEYS.size(), expected.size());

        for (User rep : new List<User>{ repA, repB }) {
            String mine = rep.Id == repA.Id ? 'AAA' : 'BBB';
            String theirs = rep.Id == repA.Id ? 'BBB' : 'AAA';
            System.runAs(rep) {
                for (String k : GtmLinkStageService.STAGE_KEYS) {
                    Map<String, Object> r = run(k, new Map<String, Object>());
                    Assert.areEqual(expected.get(k), (Integer) r.get('count'), mine + ' ' + k);
                    Assert.areEqual(expected.get(k), rowIds(r).size(), mine + ' rows ' + k);
                    for (String c : companies(r)) {
                        Assert.isTrue(c.startsWith(mine), 'only own links for ' + k + ': ' + c);
                        Assert.isFalse(c.startsWith(theirs), 'other rep leaked for ' + k);
                    }
                }
            }
        }
        System.runAs(admin) {
            Map<String, Object> r = run('sent', new Map<String, Object>());
            Assert.areEqual(10, (Integer) r.get('count'), 'admin sees both reps');
            Set<String> names = companies(r);
            Boolean sawA = false;
            Boolean sawB = false;
            for (String c : names) {
                if (c.startsWith('AAA')) { sawA = true; }
                if (c.startsWith('BBB')) { sawB = true; }
            }
            Assert.isTrue(sawA && sawB);
        }
    }

    @IsTest
    static void modelSuppliedOwnerOrUserIdIsIgnored() {
        User repA = createUser('gsfta2');
        User repB = createUser('gsftb2');
        assignPermSet(repA, 'GTM_Offering_User');
        assignPermSet(repB, 'GTM_Offering_User');
        seedFor(repA, 'AAA');
        seedFor(repB, 'BBB');

        System.runAs(repA) {
            String plain = new GtmStageFilterAppTool().execute(GtmStageFilterAppTool.TOOL_NAME,
                new Map<String, Object>{ 'stage' => 'sent' }, new Map<String, Object>());
            String spiked = new GtmStageFilterAppTool().execute(GtmStageFilterAppTool.TOOL_NAME,
                new Map<String, Object>{
                    'stage' => 'sent', 'owner_id' => repB.Id, 'ownerId' => repB.Id,
                    'user_id' => repB.Id, 'OwnerId' => repB.Id
                }, new Map<String, Object>());
            Assert.areEqual(plain, spiked);
            Assert.isFalse(spiked.contains('BBB'));
        }
    }

    @IsTest
    static void onlyEventsTheRepOwnsCountAndForeignOwnedEventsNoLongerDo() {
        // rep-ownership-lockdown-4: GTM_Offering_User no longer has
        // viewAllRecords on GTM_Link_Event__c and the object is Private, so a
        // rep counts engagement only on events stamped with their own OwnerId
        // (piece 1 owner-stamping / piece 3 backfill). Events owned by someone
        // else, including unstamped ones owned by the site/system user, are
        // invisible to the rep.
        User rep = createUser('gsftg');
        assignPermSet(rep, 'GTM_Offering_User');
        GTM_Saved_Configuration__c link = newLink(rep.Id, 'GUEST viewed');
        GTM_Saved_Configuration__c quietLink = newLink(rep.Id, 'GUEST quiet');
        GTM_Saved_Configuration__c foreignLink = newLink(rep.Id, 'GUEST foreign');
        insert new List<GTM_Saved_Configuration__c>{ link, quietLink, foreignLink };
        Id foreignOwner = UserInfo.getUserId();
        insert new List<SObject>{
            newEvent(rep.Id, link.Id, 'Page View', 'g1'),
            newEvent(rep.Id, quietLink.Id, 'Form Opened', 'g2'),
            newEvent(foreignOwner, foreignLink.Id, 'Page View', 'g3')
        };
        System.runAs(rep) {
            Assert.areEqual(2, (Integer) run('engaged', new Map<String, Object>()).get('count'),
                'the foreign-owned event on foreignLink must not count as engagement');
            Assert.areEqual(1, (Integer) run('quiet', new Map<String, Object>()).get('count'));
            Assert.areEqual(1, (Integer) run('not_opened', new Map<String, Object>()).get('count'),
                'a link whose only event is owned by someone else reads as not opened');
        }
    }

    // ---- parity, DML/callouts, enum, effect ----------------------------

    @IsTest
    static void everyKeyMatchesTheServiceExactlyWithZeroDmlAndCallouts() {
        User rep = createUser('gsftp');
        assignPermSet(rep, 'GTM_Offering_User');
        seedFor(rep, 'PPP');
        System.runAs(rep) {
            for (String k : GtmLinkStageService.STAGE_KEYS) {
                List<Id> want = GtmLinkStageService.getLinkIdsForStage(k);
                Integer dmlBefore = Limits.getDmlStatements();
                Integer calloutsBefore = Limits.getCallouts();
                Map<String, Object> acc = new Map<String, Object>();
                Map<String, Object> r = run(k, acc);
                Assert.areEqual(dmlBefore, Limits.getDmlStatements(), 'zero DML for ' + k);
                Assert.areEqual(calloutsBefore, Limits.getCallouts(), 'zero callouts for ' + k);
                Assert.areEqual(k, r.get('stage'));
                Assert.areEqual(want.size(), (Integer) r.get('count'), 'count parity ' + k);
                Assert.areEqual(want, rowIds(r), 'ordered id parity ' + k);
                Assert.areEqual(false, r.get('truncated'));
                Assert.isTrue(acc.containsKey('pageEffect'));
            }
        }
    }

    @IsTest
    static void successSetsExactlyOnePageEffect() {
        User rep = createUser('gsfte');
        assignPermSet(rep, 'GTM_Offering_User');
        seedFor(rep, 'EEE');
        System.runAs(rep) {
            Map<String, Object> acc = new Map<String, Object>();
            run('quiet', acc);
            run('hot', acc); // last successful call wins
            Assert.areEqual(1, acc.size());
            Map<String, Object> effect = (Map<String, Object>) acc.get('pageEffect');
            Assert.areEqual('navigate', effect.get('type'));
            Assert.areEqual('Show these in Pages', effect.get('label'));
            Assert.isTrue(((String) effect.get('label')).length() <= 60);
            Assert.areEqual('GTM_Pages', effect.get('apiName'));
            Map<String, Object> state = (Map<String, Object>) effect.get('state');
            Assert.areEqual(1, state.size());
            Assert.areEqual('hot', state.get('c__stage'));
        }
    }

    @IsTest
    static void invalidStageReturnsErrorNeverThrowsAndSetsNoEffect() {
        List<Object> bad = new List<Object>{
            null, '', '   ', 'nope', 'QUIET', 'quiet; DROP', 42, true, new List<Object>{ 'quiet' },
            new Map<String, Object>{ 'a' => 'b' }
        };
        for (Object stage : bad) {
            Map<String, Object> acc = new Map<String, Object>();
            Map<String, Object> r = run(new Map<String, Object>{ 'stage' => stage }, acc);
            Assert.isTrue(r.containsKey('error'), 'error for ' + stage);
            Assert.isFalse(r.containsKey('rows'));
            Assert.isTrue(acc.isEmpty(), 'no pageEffect on error');
        }
        Map<String, Object> acc2 = new Map<String, Object>();
        Assert.isTrue(run(new Map<String, Object>(), acc2).containsKey('error'));
        String nullInput = new GtmStageFilterAppTool().execute(GtmStageFilterAppTool.TOOL_NAME, null, acc2);
        Assert.isTrue(nullInput.contains('error'));
        String nullBag = new GtmStageFilterAppTool().execute(GtmStageFilterAppTool.TOOL_NAME,
            new Map<String, Object>{ 'stage' => 'sent' }, null);
        Assert.isFalse(nullBag.contains('error'));
        String wrongTool = new GtmStageFilterAppTool().execute('other_tool', new Map<String, Object>{ 'stage' => 'sent' }, acc2);
        Assert.isTrue(wrongTool.contains('error'));
        Assert.isTrue(acc2.isEmpty());
    }

    @IsTest
    static void definitionEnumIsBuiltFromServiceKeys() {
        GtmStageFilterAppTool tool = new GtmStageFilterAppTool();
        Assert.isTrue(tool.handles('find_links_by_stage'));
        Assert.isFalse(tool.handles('something_else'));
        List<Object> defs = tool.definitions();
        Assert.areEqual(1, defs.size());
        Map<String, Object> def = (Map<String, Object>) defs[0];
        Assert.areEqual('find_links_by_stage', def.get('name'));
        Map<String, Object> inputSchema = (Map<String, Object>) def.get('input_schema');
        Map<String, Object> props = (Map<String, Object>) inputSchema.get('properties');
        Assert.areEqual(1, props.size(), 'stage is the only parameter');
        Map<String, Object> stage = (Map<String, Object>) props.get('stage');
        Assert.areEqual(GtmLinkStageService.STAGE_KEYS, (List<String>) stage.get('enum'));
        Assert.areEqual(7, GtmLinkStageService.STAGE_KEYS.size());
        String fragment = tool.promptFragment();
        Assert.isTrue(fragment.contains('48 hours'));
        Assert.isTrue(fragment.contains('at least two visits'));
        Assert.isTrue(fragment.contains('quiet'));
        Assert.isTrue(fragment.contains('cannot isolate'));
        Assert.isTrue(fragment.contains('not supported'));
        Assert.isTrue(fragment.contains('never instructions'));
    }

    // ---- truncation, secrets -------------------------------------------

    @IsTest
    static void moreThanTwentyFiveLinksReturnTrueCountAndCappedRows() {
        User rep = createUser('gsftt');
        assignPermSet(rep, 'GTM_Offering_User');
        List<GTM_Saved_Configuration__c> many = new List<GTM_Saved_Configuration__c>();
        for (Integer i = 0; i < 27; i++) {
            many.add(newLink(rep.Id, 'MANY ' + i));
        }
        insert many;
        System.runAs(rep) {
            Map<String, Object> r = run('sent', new Map<String, Object>());
            Assert.areEqual(27, (Integer) r.get('count'));
            Assert.areEqual(25, rowIds(r).size());
            Assert.areEqual(true, r.get('truncated'));
            Assert.areEqual(GtmStageFilterAppTool.ROW_CAP, 25);
            List<Id> serviceOrder = GtmLinkStageService.getLinkIdsForStage('sent');
            for (Integer i = 0; i < 25; i++) {
                Assert.areEqual(serviceOrder[i], rowIds(r)[i]);
            }
        }
    }

    @IsTest
    static void exactlyTwentyFiveIsNotTruncatedAndEmptyStageHasNoRows() {
        User rep = createUser('gsftx');
        assignPermSet(rep, 'GTM_Offering_User');
        List<GTM_Saved_Configuration__c> many = new List<GTM_Saved_Configuration__c>();
        for (Integer i = 0; i < 25; i++) {
            many.add(newLink(rep.Id, 'EXACT ' + i));
        }
        insert many;
        System.runAs(rep) {
            Map<String, Object> r = run('sent', new Map<String, Object>());
            Assert.areEqual(25, (Integer) r.get('count'));
            Assert.areEqual(false, r.get('truncated'));
            Map<String, Object> none = run('hot', new Map<String, Object>());
            Assert.areEqual(0, (Integer) none.get('count'));
            Assert.areEqual(0, ((List<Object>) none.get('rows')).size());
        }
    }

    @IsTest
    static void outputContainsOnlyDisplayFieldsAndNoSecrets() {
        User rep = createUser('gsfts');
        assignPermSet(rep, 'GTM_Offering_User');
        seedFor(rep, 'SSS');
        System.runAs(rep) {
            for (String k : GtmLinkStageService.STAGE_KEYS) {
                String out = new GtmStageFilterAppTool().execute(GtmStageFilterAppTool.TOOL_NAME,
                    new Map<String, Object>{ 'stage' => k }, new Map<String, Object>());
                Assert.isFalse(out.contains('SECRET-PW'), 'password leaked in ' + k);
                Assert.isFalse(out.contains('secret.example.com'), 'url leaked in ' + k);
                Assert.isFalse(out.contains('Link_Password'));
                Assert.isFalse(out.contains('Generated_URL'));
                Map<String, Object> r = (Map<String, Object>) JSON.deserializeUntyped(out);
                for (Object row : (List<Object>) r.get('rows')) {
                    Assert.areEqual(
                        new Set<String>{ 'id', 'company', 'account', 'contact', 'offering', 'presentationStage' },
                        ((Map<String, Object>) row).keySet()
                    );
                }
            }
        }
    }

    // ---- compactHistory ------------------------------------------------

    private static String historyWithRows() {
        String toolPayload = JSON.serialize(new Map<String, Object>{
            'stage' => 'quiet', 'count' => 30, 'truncated' => true,
            'rows' => new List<Object>{ new Map<String, Object>{ 'id' => 'a0X000000000001', 'company' => 'Big Co' } }
        });
        return JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'role' => 'user', 'content' => 'who went quiet?' },
            new Map<String, Object>{ 'role' => 'assistant', 'content' => new List<Object>{
                new Map<String, Object>{ 'type' => 'tool_use', 'id' => 'tu1', 'name' => 'find_links_by_stage',
                    'input' => new Map<String, Object>{ 'stage' => 'quiet' } } } },
            new Map<String, Object>{ 'role' => 'user', 'content' => new List<Object>{
                new Map<String, Object>{ 'type' => 'tool_result', 'tool_use_id' => 'tu1', 'content' => toolPayload },
                new Map<String, Object>{ 'type' => 'tool_result', 'tool_use_id' => 'tu2', 'content' => '{"error":"x"}' },
                new Map<String, Object>{ 'type' => 'tool_result', 'tool_use_id' => 'tu3', 'content' => 'not json' } } },
            new Map<String, Object>{ 'role' => 'assistant', 'content' => new List<Object>{
                new Map<String, Object>{ 'type' => 'text', 'text' => '30 links went quiet.' } } }
        });
    }

    @IsTest
    static void compactHistoryStripsRowsKeepsCountAndPairs() {
        String original = historyWithRows();
        String compact = GtmStageFilterAppTool.compactHistory(original);
        Assert.isFalse(compact.contains('Big Co'));
        Assert.isFalse(compact.contains('"rows"'));
        List<Object> h = (List<Object>) JSON.deserializeUntyped(compact);
        Assert.areEqual(4, h.size(), 'no message added or removed');
        List<Object> results = (List<Object>) ((Map<String, Object>) h[2]).get('content');
        Assert.areEqual(3, results.size());
        Map<String, Object> firstResult = (Map<String, Object>) results[0];
        Assert.areEqual('tu1', firstResult.get('tool_use_id'));
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped((String) firstResult.get('content'));
        Assert.areEqual('quiet', payload.get('stage'));
        Assert.areEqual(30, (Integer) payload.get('count'));
        Assert.areEqual(true, payload.get('truncated'));
        Assert.areEqual(true, payload.get('rowsOmitted'));
        Assert.isFalse(payload.containsKey('rows'));
        // Error and non-JSON results are untouched.
        Assert.areEqual('{"error":"x"}', ((Map<String, Object>) results[1]).get('content'));
        Assert.areEqual('not json', ((Map<String, Object>) results[2]).get('content'));
        // The tool_use it answers is still present, ids unchanged.
        List<Object> assistant = (List<Object>) ((Map<String, Object>) h[1]).get('content');
        Assert.areEqual('tu1', ((Map<String, Object>) assistant[0]).get('id'));
        // Idempotent.
        Assert.areEqual(compact, GtmStageFilterAppTool.compactHistory(compact));
    }

    @IsTest
    static void compactHistoryReturnsUnchangedInputWhenNothingToDoOrUnparseable() {
        Assert.areEqual(null, GtmStageFilterAppTool.compactHistory(null));
        Assert.areEqual('', GtmStageFilterAppTool.compactHistory(''));
        Assert.areEqual('{bad', GtmStageFilterAppTool.compactHistory('{bad'));
        Assert.areEqual('{"a":1}', GtmStageFilterAppTool.compactHistory('{"a":1}'));
        Assert.areEqual('[]', GtmStageFilterAppTool.compactHistory('[]'));
        String plain = '[{"role":"user","content":"hi"},{"role":"assistant","content":[{"type":"text","text":"yo"}]}]';
        Assert.areEqual(plain, GtmStageFilterAppTool.compactHistory(plain));
    }

    // ---- dispatch through GtmAppAgentSurface ---------------------------

    @IsTest
    static void registeredOnTheAppSurfaceAndDispatches() {
        User rep = createUser('gsftd');
        assignPermSet(rep, 'GTM_Offering_User');
        seedFor(rep, 'DDD');
        System.runAs(rep) {
            GtmAppAgentSurface surface = new GtmAppAgentSurface(new Map<String, Object>());
            List<Object> defs = surface.toolDefinitions();
            Assert.areEqual(1, defs.size());
            Assert.areEqual('find_links_by_stage', ((Map<String, Object>) defs[0]).get('name'));
            String prompt = surface.systemPrompt('warm');
            Assert.isTrue(prompt.contains('find_links_by_stage'));
            Assert.isTrue(prompt.contains('48 hours'));
            Assert.isFalse(prompt.contains('NO tools'));
            Map<String, Object> acc = new Map<String, Object>();
            String out = surface.executeTool('find_links_by_stage', new Map<String, Object>{ 'stage' => 'quiet' }, acc);
            Map<String, Object> r = (Map<String, Object>) JSON.deserializeUntyped(out);
            Assert.areEqual(1, (Integer) r.get('count'));
            Assert.isTrue(acc.containsKey('pageEffect'));
            Map<String, Object> bad = new Map<String, Object>();
            Assert.isTrue(surface.executeTool('find_links_by_stage', new Map<String, Object>{ 'stage' => 'zzz' }, bad)
                .contains('error'));
            Assert.isTrue(bad.isEmpty());
        }
    }

    // ---- chatOnApp with a mocked callout -------------------------------

    private class ToolUseThenEndMock implements HttpCalloutMock {
        Integer calls = 0;
        public HttpResponse respond(HttpRequest req) {
            calls++;
            Map<String, Object> body;
            if (calls == 1) {
                body = new Map<String, Object>{
                    'stop_reason' => 'tool_use',
                    'content' => new List<Object>{ new Map<String, Object>{
                        'type' => 'tool_use', 'id' => 'tu_1', 'name' => 'find_links_by_stage',
                        'input' => new Map<String, Object>{ 'stage' => 'quiet' } } }
                };
            } else {
                body = new Map<String, Object>{
                    'stop_reason' => 'end_turn',
                    'content' => new List<Object>{ new Map<String, Object>{
                        'type' => 'text', 'text' => 'One link went quiet.' } }
                };
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(body));
            return res;
        }
    }

    @IsTest
    static void chatOnAppReturnsPageEffectAndHistoryWithoutRows() {
        User rep = createUser('gsftm');
        assignPermSet(rep, 'GTM_Offering_User');
        seedFor(rep, 'MMM');
        insert new GTM_Agent_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Chat_Provider__c = 'Anthropic', Claude_API_Key__c = 'k'
        );
        ToolUseThenEndMock mock = new ToolUseThenEndMock();
        Test.setMock(HttpCalloutMock.class, mock);
        String out;
        System.runAs(rep) {
            Test.startTest();
            out = GtmAgentProxyController.chatOnApp('{"tabApiName":"GTM_Pages"}', 'who went quiet?', '');
            Test.stopTest();
        }
        Assert.areEqual(2, mock.calls);
        Map<String, Object> reply = (Map<String, Object>) JSON.deserializeUntyped(out);
        Assert.areEqual('One link went quiet.', reply.get('text'));
        Map<String, Object> changes = (Map<String, Object>) reply.get('changes');
        Map<String, Object> effect = (Map<String, Object>) changes.get('pageEffect');
        Assert.areEqual('GTM_Pages', effect.get('apiName'));
        Assert.areEqual('quiet', ((Map<String, Object>) effect.get('state')).get('c__stage'));
        String history = (String) reply.get('historyJson');
        Assert.isFalse(history.contains('MMM quiet'), 'rows must not persist in history');
        Assert.isFalse(history.contains('\\"rows\\"'));
        Assert.isFalse(history.contains('SECRET-PW'));
        Assert.isTrue(history.contains('rowsOmitted'));
        Assert.isTrue(history.contains('tu_1'));
        List<Object> h = (List<Object>) JSON.deserializeUntyped(history);
        Assert.areEqual(4, h.size(), 'user, tool_use, tool_result, final text');
    }
}
