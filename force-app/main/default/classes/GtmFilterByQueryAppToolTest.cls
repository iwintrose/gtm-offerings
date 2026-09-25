/**
 * ISSUE #10. Contract: docs/architecture/gus-filter-query-tool.md.
 * Mirrors GtmStageFilterAppToolTest's shape: security via `with sharing`
 * (account/contact search only sees what the running user's sharing grants),
 * zero DML/zero callouts, enum parity with the shared vocabulary sources,
 * and the four required account/contact paths (exact, single-fuzzy,
 * ambiguous, unrecognized).
 */
@IsTest
private class GtmFilterByQueryAppToolTest {

    // ---- helpers -------------------------------------------------------

    private static User createUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'FBQ ' + alias, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
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

    private static Map<String, Object> run(Map<String, Object> input, Map<String, Object> acc) {
        String out = new GtmFilterByQueryAppTool().execute(GtmFilterByQueryAppTool.TOOL_NAME, input, acc);
        return (Map<String, Object>) JSON.deserializeUntyped(out);
    }

    // ---- tab validation --------------------------------------------------

    @IsTest
    static void missingOrInvalidTabIsAnErrorWithNoEffect() {
        for (Object bad : new List<Object>{ null, '', 'GTM_Home', 42, true }) {
            Map<String, Object> acc = new Map<String, Object>();
            Map<String, Object> r = run(new Map<String, Object>{ 'tab' => bad }, acc);
            Assert.isTrue(r.containsKey('error'), 'error for tab ' + bad);
            Assert.isTrue(acc.isEmpty(), 'no pageEffect on invalid tab');
        }
        Map<String, Object> acc2 = new Map<String, Object>();
        Assert.isTrue(run(new Map<String, Object>(), acc2).containsKey('error'));
        String nullInput = new GtmFilterByQueryAppTool().execute(GtmFilterByQueryAppTool.TOOL_NAME, null, acc2);
        Assert.isTrue(nullInput.contains('error'));
        String wrongTool = new GtmFilterByQueryAppTool().execute('other_tool', new Map<String, Object>{ 'tab' => 'GTM_Pages' }, acc2);
        Assert.isTrue(wrongTool.contains('error'));
    }

    // ---- Pages / stage -----------------------------------------------------

    @IsTest
    static void pagesWithValidStageSetsExactlyOnePageEffect() {
        User rep = createUser('fbqp1');
        assignPermSet(rep, 'GTM_Offering_User');
        System.runAs(rep) {
            Map<String, Object> acc = new Map<String, Object>();
            Map<String, Object> r = run(new Map<String, Object>{ 'tab' => 'GTM_Pages', 'stage' => 'quiet' }, acc);
            Assert.areEqual('GTM_Pages', r.get('tab'));
            Assert.isFalse(r.containsKey('error'));
            Assert.areEqual(1, acc.size());
            Map<String, Object> effect = (Map<String, Object>) acc.get('pageEffect');
            Assert.areEqual('navigate', effect.get('type'));
            Assert.areEqual('Show these in Pages', effect.get('label'));
            Assert.areEqual('GTM_Pages', effect.get('apiName'));
            Map<String, Object> state = (Map<String, Object>) effect.get('state');
            Assert.areEqual(1, state.size());
            Assert.areEqual('quiet', state.get('c__stage'));
        }
    }

    @IsTest
    static void pagesWithMissingOrInvalidStageIsAnErrorWithNoEffect() {
        User rep = createUser('fbqp2');
        assignPermSet(rep, 'GTM_Offering_User');
        System.runAs(rep) {
            for (Object bad : new List<Object>{ null, '', 'nope', 'QUIET', 42 }) {
                Map<String, Object> acc = new Map<String, Object>();
                Map<String, Object> r = run(new Map<String, Object>{ 'tab' => 'GTM_Pages', 'stage' => bad }, acc);
                Assert.isTrue(r.containsKey('error'), 'error for stage ' + bad);
                Assert.isTrue(acc.isEmpty(), 'no pageEffect for stage ' + bad);
            }
        }
    }

    @IsTest
    static void pagesStageEnumIsBuiltFromTheSharedService() {
        GtmFilterByQueryAppTool tool = new GtmFilterByQueryAppTool();
        List<Object> defs = tool.definitions();
        Assert.areEqual(1, defs.size());
        Map<String, Object> def = (Map<String, Object>) defs[0];
        Assert.areEqual('filter_by_query', def.get('name'));
        Map<String, Object> props = (Map<String, Object>) ((Map<String, Object>) def.get('input_schema')).get('properties');
        Map<String, Object> stageProp = (Map<String, Object>) props.get('stage');
        Assert.areEqual(GtmLinkStageService.STAGE_KEYS, (List<String>) stageProp.get('enum'));
        Map<String, Object> statusProp = (Map<String, Object>) props.get('status');
        Assert.areEqual(GtmAssessmentListController.statusKeys().size(), ((List<String>) statusProp.get('enum')).size());
        Assert.isTrue(tool.handles('filter_by_query'));
        Assert.isFalse(tool.handles('find_links_by_stage'));
    }

    // ---- Assessments / status ----------------------------------------------

    @IsTest
    static void assessmentsWithValidStatusSetsExactlyOnePageEffect() {
        User rep = createUser('fbqa1');
        assignPermSet(rep, 'GTM_Offering_User');
        System.runAs(rep) {
            Map<String, Object> acc = new Map<String, Object>();
            Map<String, Object> r = run(new Map<String, Object>{ 'tab' => 'GTM_Assessments', 'status' => 'contacted' }, acc);
            Assert.areEqual('GTM_Assessments', r.get('tab'));
            Map<String, Object> effect = (Map<String, Object>) acc.get('pageEffect');
            Assert.areEqual('Show these in Assessments', effect.get('label'));
            Map<String, Object> state = (Map<String, Object>) effect.get('state');
            Assert.areEqual(1, state.size());
            Assert.areEqual('contacted', state.get('c__astatus'));
        }
    }

    @IsTest
    static void assessmentsWithInvalidStatusIsAnErrorWithNoEffect() {
        User rep = createUser('fbqa2');
        assignPermSet(rep, 'GTM_Offering_User');
        System.runAs(rep) {
            Map<String, Object> acc = new Map<String, Object>();
            Map<String, Object> r = run(new Map<String, Object>{ 'tab' => 'GTM_Assessments', 'status' => 'in-review' }, acc);
            Assert.isTrue(r.containsKey('error'));
            Assert.isTrue(acc.isEmpty());
        }
    }

    // ---- Assessments / date phrase -----------------------------------------

    @IsTest
    static void dateRangePhrasesMapToExpectedIsoRanges() {
        String todayRange = GtmFilterByQueryAppTool.rangeFor('today');
        List<String> todayParts = todayRange.split('\\.\\.');
        Assert.areEqual(todayParts[0], todayParts[1], 'today: from == to');

        String weekRange = GtmFilterByQueryAppTool.rangeFor('this_week');
        List<String> weekParts = weekRange.split('\\.\\.');
        Assert.isTrue(Date.valueOf(weekParts[0]) <= Date.today());
        Assert.areEqual(String.valueOf(Date.today()), weekParts[1]);
        Assert.areEqual(Date.today().toStartOfWeek(), Date.valueOf(weekParts[0]));

        String monthRange = GtmFilterByQueryAppTool.rangeFor('this_month');
        List<String> monthParts = monthRange.split('\\.\\.');
        Assert.areEqual(Date.today().toStartOfMonth(), Date.valueOf(monthParts[0]));
        Assert.areEqual(Date.today(), Date.valueOf(monthParts[1]));
    }

    @IsTest
    static void assessmentsWithValidDatePhraseSetsRangeState() {
        User rep = createUser('fbqa3');
        assignPermSet(rep, 'GTM_Offering_User');
        System.runAs(rep) {
            Map<String, Object> acc = new Map<String, Object>();
            Map<String, Object> r = run(new Map<String, Object>{ 'tab' => 'GTM_Assessments', 'date_phrase' => 'this_month' }, acc);
            Assert.isFalse(r.containsKey('error'));
            Map<String, Object> state = (Map<String, Object>) ((Map<String, Object>) acc.get('pageEffect')).get('state');
            Assert.isTrue(((String) state.get('c__arange')).contains('..'));
        }
    }

    @IsTest
    static void assessmentsWithUnrecognizedDatePhraseIsAnErrorWithNoEffect() {
        User rep = createUser('fbqa4');
        assignPermSet(rep, 'GTM_Offering_User');
        System.runAs(rep) {
            for (String bad : new List<String>{ 'last_month', 'last_30_days', 'yesterday', '' }) {
                Map<String, Object> acc = new Map<String, Object>();
                Map<String, Object> r = run(new Map<String, Object>{ 'tab' => 'GTM_Assessments', 'date_phrase' => bad }, acc);
                Assert.isTrue(r.containsKey('error'), 'error for date_phrase ' + bad);
                Assert.isTrue(acc.isEmpty());
            }
        }
    }

    // ---- Assessments / account+contact resolution --------------------------

    @IsTest
    static void exactAccountMatchResolvesAndSetsAcctState() {
        Account acc1 = new Account(Name = 'TD Bank');
        insert acc1;
        User rep = createUser('fbqa5');
        assignPermSet(rep, 'GTM_Offering_User');
        Test.setFixedSearchResults(new List<Id>{ acc1.Id });
        System.runAs(rep) {
            Map<String, Object> acc = new Map<String, Object>();
            Test.startTest();
            Map<String, Object> r = run(new Map<String, Object>{ 'tab' => 'GTM_Assessments', 'account_or_contact' => 'TD Bank' }, acc);
            Test.stopTest();
            Assert.isFalse(r.containsKey('error'), 'exact match should not error: ' + r);
            Map<String, Object> state = (Map<String, Object>) ((Map<String, Object>) acc.get('pageEffect')).get('state');
            Assert.areEqual(acc1.Id, (Id) state.get('c__aacct'));
        }
    }

    @IsTest
    static void singleFuzzyMatchResolvesWhenNoExactMatchExists() {
        Account acc1 = new Account(Name = 'TD Bank Financial Group');
        insert acc1;
        User rep = createUser('fbqa6');
        assignPermSet(rep, 'GTM_Offering_User');
        Test.setFixedSearchResults(new List<Id>{ acc1.Id });
        System.runAs(rep) {
            Map<String, Object> acc = new Map<String, Object>();
            Test.startTest();
            Map<String, Object> r = run(new Map<String, Object>{ 'tab' => 'GTM_Assessments', 'account_or_contact' => 'TD Bank' }, acc);
            Test.stopTest();
            Assert.isFalse(r.containsKey('error'), 'single fuzzy match should not error: ' + r);
            Map<String, Object> state = (Map<String, Object>) ((Map<String, Object>) acc.get('pageEffect')).get('state');
            Assert.areEqual(acc1.Id, (Id) state.get('c__aacct'));
        }
    }

    @IsTest
    static void multipleFuzzyMatchesAreAmbiguousAndSetNoEffect() {
        Account acc1 = new Account(Name = 'TD Bank Canada');
        Account acc2 = new Account(Name = 'TD Bank US');
        insert new List<Account>{ acc1, acc2 };
        User rep = createUser('fbqa7');
        assignPermSet(rep, 'GTM_Offering_User');
        Test.setFixedSearchResults(new List<Id>{ acc1.Id, acc2.Id });
        System.runAs(rep) {
            Map<String, Object> acc = new Map<String, Object>();
            Test.startTest();
            Map<String, Object> r = run(new Map<String, Object>{ 'tab' => 'GTM_Assessments', 'account_or_contact' => 'TD Bank' }, acc);
            Test.stopTest();
            Assert.isTrue(r.containsKey('error'), 'ambiguous match must be a text-only error');
            Assert.isTrue(acc.isEmpty(), 'no pageEffect on ambiguous match');
            List<Object> candidates = (List<Object>) r.get('candidates');
            Assert.areEqual(2, candidates.size());
            Assert.isTrue(candidates.contains('TD Bank Canada'));
            Assert.isTrue(candidates.contains('TD Bank US'));
        }
    }

    @IsTest
    static void unrecognizedQueryWithNoMatchAndNoOtherFieldIsAnErrorWithNoEffect() {
        User rep = createUser('fbqa8');
        assignPermSet(rep, 'GTM_Offering_User');
        Test.setFixedSearchResults(new List<Id>());
        System.runAs(rep) {
            Map<String, Object> acc = new Map<String, Object>();
            Test.startTest();
            Map<String, Object> r = run(new Map<String, Object>{ 'tab' => 'GTM_Assessments', 'account_or_contact' => 'Nobody Inc' }, acc);
            Test.stopTest();
            Assert.isTrue(r.containsKey('error'));
            Assert.isTrue(acc.isEmpty());
        }
    }

    @IsTest
    static void completelyUnrecognizedAssessmentsQuerySetsNoStateAndIsAnError() {
        User rep = createUser('fbqa9');
        assignPermSet(rep, 'GTM_Offering_User');
        System.runAs(rep) {
            Map<String, Object> acc = new Map<String, Object>();
            Map<String, Object> r = run(new Map<String, Object>{ 'tab' => 'GTM_Assessments' }, acc);
            Assert.isTrue(r.containsKey('error'));
            Assert.isTrue(acc.isEmpty());
        }
    }

    @IsTest
    static void tooShortAccountTermIsAnErrorWithNoEffect() {
        User rep = createUser('fbqa10');
        assignPermSet(rep, 'GTM_Offering_User');
        System.runAs(rep) {
            Map<String, Object> acc = new Map<String, Object>();
            Map<String, Object> r = run(new Map<String, Object>{ 'tab' => 'GTM_Assessments', 'account_or_contact' => 'A' }, acc);
            Assert.isTrue(r.containsKey('error'));
            Assert.isTrue(acc.isEmpty());
        }
    }

    @IsTest
    static void statusAndDateAndAccountCombineIntoOnePageEffect() {
        Account acc1 = new Account(Name = 'TD Bank');
        insert acc1;
        User rep = createUser('fbqa11');
        assignPermSet(rep, 'GTM_Offering_User');
        Test.setFixedSearchResults(new List<Id>{ acc1.Id });
        System.runAs(rep) {
            Map<String, Object> acc = new Map<String, Object>();
            Test.startTest();
            Map<String, Object> r = run(new Map<String, Object>{
                'tab' => 'GTM_Assessments', 'status' => 'contacted',
                'date_phrase' => 'this_month', 'account_or_contact' => 'TD Bank'
            }, acc);
            Test.stopTest();
            Assert.isFalse(r.containsKey('error'));
            Map<String, Object> state = (Map<String, Object>) ((Map<String, Object>) acc.get('pageEffect')).get('state');
            Assert.areEqual(3, state.size());
            Assert.areEqual('contacted', state.get('c__astatus'));
            Assert.areEqual(acc1.Id, (Id) state.get('c__aacct'));
            Assert.isTrue(((String) state.get('c__arange')).contains('..'));
        }
    }

    // ---- zero DML / zero callouts ------------------------------------------

    @IsTest
    static void neverExecutesDmlOrCallouts() {
        Account acc1 = new Account(Name = 'TD Bank');
        insert acc1;
        User rep = createUser('fbqz1');
        assignPermSet(rep, 'GTM_Offering_User');
        Test.setFixedSearchResults(new List<Id>{ acc1.Id });
        System.runAs(rep) {
            Integer dmlBefore = Limits.getDmlStatements();
            Integer calloutsBefore = Limits.getCallouts();
            Map<String, Object> acc = new Map<String, Object>();
            Test.startTest();
            run(new Map<String, Object>{ 'tab' => 'GTM_Assessments', 'status' => 'contacted', 'account_or_contact' => 'TD Bank' }, acc);
            run(new Map<String, Object>{ 'tab' => 'GTM_Pages', 'stage' => 'quiet' }, acc);
            Test.stopTest();
            Assert.areEqual(dmlBefore, Limits.getDmlStatements());
            Assert.areEqual(calloutsBefore, Limits.getCallouts());
        }
    }

    // ---- dispatch through GtmAppAgentSurface -------------------------------

    @IsTest
    static void registeredOnTheAppSurfaceAlongsideTheStageTool() {
        User rep = createUser('fbqs1');
        assignPermSet(rep, 'GTM_Offering_User');
        System.runAs(rep) {
            GtmAppAgentSurface surface = new GtmAppAgentSurface(new Map<String, Object>());
            List<Object> defs = surface.toolDefinitions();
            Set<String> names = new Set<String>();
            for (Object d : defs) names.add((String) ((Map<String, Object>) d).get('name'));
            Assert.isTrue(names.contains('find_links_by_stage'));
            Assert.isTrue(names.contains('filter_by_query'));
            String prompt = surface.systemPrompt('warm');
            Assert.isTrue(prompt.contains('filter_by_query'));
            Map<String, Object> acc = new Map<String, Object>();
            String out = surface.executeTool('filter_by_query', new Map<String, Object>{ 'tab' => 'GTM_Pages', 'stage' => 'quiet' }, acc);
            Map<String, Object> r = (Map<String, Object>) JSON.deserializeUntyped(out);
            Assert.areEqual('GTM_Pages', r.get('tab'));
            Assert.isTrue(acc.containsKey('pageEffect'));
        }
    }
}
