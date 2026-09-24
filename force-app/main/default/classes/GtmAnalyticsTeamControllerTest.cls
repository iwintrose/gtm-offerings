/**
 * Coverage for GtmAnalyticsTeamController, issue #139. Seeds links owned by
 * two DIFFERENT users (not the running test user) to prove this controller
 * actually rolls up across reps -- the entire point of it existing
 * alongside v1's OwnerId-scoped GtmAnalyticsController.
 */
@IsTest
private class GtmAnalyticsTeamControllerTest {

    @TestSetup
    static void seed() {
        User repA = createRep('repa');
        User repB = createRep('repb');

        List<GTM_Saved_Configuration__c> configs = new List<GTM_Saved_Configuration__c>{
            new GTM_Saved_Configuration__c(
                OwnerId = repA.Id, Company__c = 'Globex',
                Offering__c = 'migration-accelerator', Link_Password__c = 'pw-1'
            ),
            new GTM_Saved_Configuration__c(
                OwnerId = repB.Id, Company__c = 'Initech',
                Offering__c = 'migration-accelerator', Link_Password__c = 'pw-2'
            )
        };
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert configs;
        }

        GTM_Assessment_Request__c reqA = new GTM_Assessment_Request__c(
            Saved_Configuration__c = configs[0].Id,
            Offering_Key__c = 'migration-accelerator',
            Company__c = 'Globex',
            Status__c = 'New',
            Assessment_Score__c = 27
        );
        insert reqA;

        insert new GTM_Readout__c(
            Assessment_Request__c = reqA.Id,
            Offering_Key__c = 'migration-accelerator',
            Status__c = 'Published',
            Published_Date__c = DateTime.now()
        );
        // repB's link has a link but no assessment request at all -- proves
        // a rep with zero submissions still appears with submitted=0, not
        // omitted from the leaderboard.
    }

    @IsTest
    static void leaderboardIncludesBothRepsIndependentOfRunningUser() {
        Date rangeStart = Date.today().addDays(-1);
        Date rangeEnd = Date.today();

        Test.startTest();
        List<GtmAnalyticsTeamController.RepRow> rows =
            GtmAnalyticsTeamController.getRepLeaderboard(rangeStart, rangeEnd);
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'both reps links fall in range, regardless of who is running this test');

        Map<Id, GtmAnalyticsTeamController.RepRow> byRep = new Map<Id, GtmAnalyticsTeamController.RepRow>();
        for (GtmAnalyticsTeamController.RepRow r : rows) {
            byRep.put(r.repId, r);
        }

        GtmAnalyticsTeamController.RepRow first = rows[0];
        System.assertEquals(1, first.published, 'the rep with a published readout sorts first');
        System.assertEquals(1, first.submitted);
        System.assertEquals(27, first.avgScore);

        GtmAnalyticsTeamController.RepRow second = rows[1];
        System.assertEquals(0, second.published);
        System.assertEquals(0, second.submitted, 'a rep with a link but no assessment request still appears, at zero');
    }

    @IsTest
    static void leaderboardRejectsInvertedRange() {
        Test.startTest();
        Boolean threw = false;
        try {
            GtmAnalyticsTeamController.getRepLeaderboard(Date.today(), Date.today().addDays(-1));
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'a range end before its start must be rejected');
    }

    @IsTest
    static void leaderboardHandlesEmptyRangeWithoutError() {
        Date rangeStart = Date.today().addYears(-5);
        Date rangeEnd = rangeStart.addDays(1);

        Test.startTest();
        List<GtmAnalyticsTeamController.RepRow> rows =
            GtmAnalyticsTeamController.getRepLeaderboard(rangeStart, rangeEnd);
        Test.stopTest();

        System.assert(rows.isEmpty());
    }

    @IsTest
    static void hasTeamAccessIsTrueForAnAdminAssignedUser() {
        User admin = createRep('tmadmin');
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'GTM_Offering_Admin' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = admin.Id, PermissionSetId = ps.Id);
        }

        Boolean access;
        System.runAs(admin) {
            access = GtmAnalyticsTeamController.hasTeamAccess();
        }
        System.assertEquals(true, access, 'a user with GTM_Offering_Admin assigned sees the Team toggle');
    }

    @IsTest
    static void flaggedRequestsIncludesFlagOnlyAdvisoryOnlyAndBoth() {
        User repA = [SELECT Id FROM User WHERE Alias = 'repa' LIMIT 1];

        GTM_Assessment_Request__c flagOnly = new GTM_Assessment_Request__c(
            OwnerId = repA.Id,
            Offering_Key__c = 'migration-accelerator',
            Company__c = 'FlagOnlyCo',
            Status__c = 'New',
            Assessment_Flags__c = '[{"code":"high_rebuild_ratio","message":"High rebuild ratio."}]'
        );
        GTM_Assessment_Request__c advisoryOnly = new GTM_Assessment_Request__c(
            OwnerId = repA.Id,
            Offering_Key__c = 'migration-accelerator',
            Company__c = 'AdvisoryOnlyCo',
            Status__c = 'New',
            Assessment_Advisory__c = true,
            Advisory_Reason__c = 'Unsupported source/target pair.'
        );
        GTM_Assessment_Request__c both = new GTM_Assessment_Request__c(
            OwnerId = repA.Id,
            Offering_Key__c = 'migration-accelerator',
            Company__c = 'BothCo',
            Status__c = 'New',
            Assessment_Advisory__c = true,
            Advisory_Reason__c = 'Unsupported source/target pair.',
            Assessment_Flags__c = '[{"code":"high_rebuild_ratio","message":"High rebuild ratio."}]'
        );
        GTM_Assessment_Request__c neither = new GTM_Assessment_Request__c(
            OwnerId = repA.Id,
            Offering_Key__c = 'migration-accelerator',
            Company__c = 'NeitherCo',
            Status__c = 'New'
        );
        insert new List<GTM_Assessment_Request__c>{ flagOnly, advisoryOnly, both, neither };

        Date rangeStart = Date.today().addDays(-1);
        Date rangeEnd = Date.today();

        Test.startTest();
        GtmAnalyticsTeamController.FlaggedResult result =
            GtmAnalyticsTeamController.getFlaggedRequests(rangeStart, rangeEnd);
        Test.stopTest();

        System.assertEquals(3, result.rows.size(), 'flag-only, advisory-only, and both should be returned; neither excluded');
        System.assertEquals(3, result.returnedCount);
        System.assertEquals(false, result.hasMore);

        Map<Id, GtmAnalyticsTeamController.FlaggedRow> byId = new Map<Id, GtmAnalyticsTeamController.FlaggedRow>();
        for (GtmAnalyticsTeamController.FlaggedRow row : result.rows) {
            byId.put(row.requestId, row);
        }
        System.assert(!byId.containsKey(neither.Id), 'a request with neither signal must not appear');

        GtmAnalyticsTeamController.FlaggedRow flagOnlyRow = byId.get(flagOnly.Id);
        System.assertEquals(false, flagOnlyRow.advisory);
        System.assertEquals(1, flagOnlyRow.flagMessages.size());
        System.assertEquals('High rebuild ratio.', flagOnlyRow.flagMessages[0]);

        GtmAnalyticsTeamController.FlaggedRow advisoryOnlyRow = byId.get(advisoryOnly.Id);
        System.assertEquals(true, advisoryOnlyRow.advisory);
        System.assertEquals('Unsupported source/target pair.', advisoryOnlyRow.advisoryReason);
        System.assertEquals(0, advisoryOnlyRow.flagMessages.size());

        GtmAnalyticsTeamController.FlaggedRow bothRow = byId.get(both.Id);
        System.assertEquals(true, bothRow.advisory);
        System.assertEquals(1, bothRow.flagMessages.size());
    }

    @IsTest
    static void flaggedRequestsHandlesEmptyRangeWithoutError() {
        Date rangeStart = Date.today().addYears(-5);
        Date rangeEnd = rangeStart.addDays(1);

        Test.startTest();
        GtmAnalyticsTeamController.FlaggedResult result =
            GtmAnalyticsTeamController.getFlaggedRequests(rangeStart, rangeEnd);
        Test.stopTest();

        System.assert(result.rows.isEmpty());
        System.assertEquals(0, result.returnedCount);
        System.assertEquals(false, result.hasMore);
    }

    @IsTest
    static void flaggedRequestsRejectsInvertedRange() {
        Test.startTest();
        Boolean threw = false;
        try {
            GtmAnalyticsTeamController.getFlaggedRequests(Date.today(), Date.today().addDays(-1));
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'a range end before its start must be rejected');
    }

    @IsTest
    static void hasTeamAccessIsFalseForARepWithoutTheAdminPermissionSet() {
        User rep = createRep('tmrep');

        Boolean access;
        System.runAs(rep) {
            access = GtmAnalyticsTeamController.hasTeamAccess();
        }
        System.assertEquals(false, access, 'a rep with no GTM_Offering_Admin assignment never sees the Team toggle');
    }

    @IsTest
    static void instrumentVersionComparisonGroupsByPairAndVersionAndSortsNewestFirst() {
        User rep = createRep('ivcrep');
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            OwnerId = rep.Id, Company__c = 'Acme',
            Offering__c = 'migration-accelerator', Link_Password__c = 'pw-ivc'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert cfg;
        }

        List<GTM_Assessment_Request__c> requests = new List<GTM_Assessment_Request__c>{
            new GTM_Assessment_Request__c(
                Saved_Configuration__c = cfg.Id, Offering_Key__c = 'migration-accelerator',
                Company__c = 'Acme', Status__c = 'New',
                Instrument_Pair__c = 'hubspot__mcn', Instrument_Version__c = 'v1',
                Assessment_Score__c = 20, Assessment_Tier__c = 'Prep Required'
            ),
            new GTM_Assessment_Request__c(
                Saved_Configuration__c = cfg.Id, Offering_Key__c = 'migration-accelerator',
                Company__c = 'Acme', Status__c = 'New',
                Instrument_Pair__c = 'hubspot__mcn', Instrument_Version__c = 'v2',
                Assessment_Score__c = 28, Assessment_Tier__c = 'Fast-Track'
            ),
            new GTM_Assessment_Request__c(
                Saved_Configuration__c = cfg.Id, Offering_Key__c = 'migration-accelerator',
                Company__c = 'Acme', Status__c = 'New',
                Instrument_Pair__c = 'hubspot__mcn', Instrument_Version__c = 'v2'
                // unscored -- no Assessment_Score__c/Assessment_Tier__c, must not corrupt avgScore
            ),
            new GTM_Assessment_Request__c(
                Saved_Configuration__c = cfg.Id, Offering_Key__c = 'migration-accelerator',
                Company__c = 'Acme', Status__c = 'New'
                // legacy row, null pair/version -- must be bucketed as "(unset)", not dropped
            )
        };
        insert requests;

        insert new GTM_Readout__c(
            Assessment_Request__c = requests[1].Id,
            Offering_Key__c = 'migration-accelerator',
            Status__c = 'Published',
            Published_Date__c = DateTime.now()
        );

        Date rangeStart = Date.today().addDays(-1);
        Date rangeEnd = Date.today();

        Test.startTest();
        List<GtmAnalyticsTeamController.InstrumentVersionRow> rows =
            GtmAnalyticsTeamController.getInstrumentVersionComparison(rangeStart, rangeEnd);
        Test.stopTest();

        System.assertEquals(3, rows.size(), 'v1, v2, and the "(unset)" legacy bucket');

        // Sorted by pairKey asc, then version desc -- '(unset)' sorts before 'hubspot__mcn'
        // alphabetically, and within hubspot__mcn v2 (newest) comes before v1. The "(unset)"
        // bucket also picks up @TestSetup's reqA (also pair/version-less, score 27, published),
        // alongside this method's own unscored legacy row -- proving unset rows from different
        // sources still land in the one shared "(unset)" bucket rather than being dropped.
        System.assertEquals('(unset)', rows[0].pairKey, 'legacy rows missing pair/version are bucketed, not dropped');
        System.assertEquals('(unset)', rows[0].version);
        System.assertEquals(2, rows[0].submitted);
        System.assertEquals(27, rows[0].avgScore, 'avgScore averages only the scored row in the bucket, ignoring the unscored one');
        System.assertEquals(2, rows[0].tierCounts.get('Unscored'), 'both the scored-but-untiered and fully unscored rows fall into Unscored');
        System.assertEquals(1, rows[0].published);
        System.assertEquals(50.0, rows[0].publishRate);

        System.assertEquals('hubspot__mcn', rows[1].pairKey);
        System.assertEquals('v2', rows[1].version);
        System.assertEquals(2, rows[1].submitted);
        System.assertEquals(28, rows[1].avgScore, 'avgScore ignores the unscored row rather than treating it as 0');
        System.assertEquals(1, rows[1].tierCounts.get('Fast-Track'));
        System.assertEquals(1, rows[1].tierCounts.get('Unscored'), 'the unscored request lands in the Unscored bucket');
        System.assertEquals(1, rows[1].published);
        System.assertEquals(50.0, rows[1].publishRate);

        System.assertEquals('hubspot__mcn', rows[2].pairKey);
        System.assertEquals('v1', rows[2].version);
        System.assertEquals(1, rows[2].submitted);
        System.assertEquals(20, rows[2].avgScore);
        System.assertEquals(0, rows[2].published);
        System.assertEquals(0.0, rows[2].publishRate);
    }

    @IsTest
    static void instrumentVersionComparisonRejectsInvertedRange() {
        Test.startTest();
        Boolean threw = false;
        try {
            GtmAnalyticsTeamController.getInstrumentVersionComparison(Date.today(), Date.today().addDays(-1));
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'a range end before its start must be rejected');
    }

    @IsTest
    static void instrumentVersionComparisonHandlesEmptyRangeWithoutError() {
        Date rangeStart = Date.today().addYears(-5);
        Date rangeEnd = rangeStart.addDays(1);

        Test.startTest();
        List<GtmAnalyticsTeamController.InstrumentVersionRow> rows =
            GtmAnalyticsTeamController.getInstrumentVersionComparison(rangeStart, rangeEnd);
        Test.stopTest();

        System.assert(rows.isEmpty());
    }

    /**
     * Grants ObjectPermissions.PermissionsViewAllRecords=true on all three
     * objects GtmAnalyticsTeamController reads (GTM_Saved_Configuration__c,
     * GTM_Assessment_Request__c, GTM_Readout__c) via a brand-new,
     * NOT-GTM_Offering_Admin permission set, then assigns it to the given
     * user -- proves the generalized check honors any permission set with
     * the right grant, not a hardcoded name.
     */
    private static void grantOrgWideAnalyticsAccessViaCustomPermSet(Id userId, Set<String> objectApiNames) {
        PermissionSet ps = new PermissionSet(
            Label = 'Team Analytics View All (Test)',
            Name = 'Team_Analytics_View_All_Test_' + Math.abs(Crypto.getRandomInteger())
        );
        insert ps;

        List<ObjectPermissions> grants = new List<ObjectPermissions>();
        for (String objectApiName : objectApiNames) {
            grants.add(new ObjectPermissions(
                ParentId = ps.Id,
                SobjectType = objectApiName,
                PermissionsRead = true,
                PermissionsViewAllRecords = true
            ));
        }
        insert grants;

        insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
    }

    /**
     * Proves the generalized check is NOT hardcoded to 'GTM_Offering_Admin':
     * a brand-new, differently-named permission set granting
     * viewAllRecords=true on all three objects is honored on its own,
     * with no GTM_Offering_Admin assignment involved at all.
     */
    @IsTest
    static void hasTeamAccessIsTrueForADifferentlyNamedPermissionSetGrantingViewAllOnAllThreeObjects() {
        User rep = createRep('genrep');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            grantOrgWideAnalyticsAccessViaCustomPermSet(rep.Id, new Set<String>{
                'GTM_Saved_Configuration__c', 'GTM_Assessment_Request__c', 'GTM_Readout__c'
            });
        }

        Boolean access;
        System.runAs(rep) {
            access = GtmAnalyticsTeamController.hasTeamAccess();
        }
        System.assertEquals(true, access,
            'a differently-named permission set with viewAllRecords=true on all three objects must be honored, ' +
            'proving the check is not hardcoded to the GTM_Offering_Admin permission set name');
    }

    /**
     * The class-level doc comment (and the Architect's plan) require
     * viewAllRecords=true on ALL THREE objects, not just one -- a grant on
     * only two of the three must still be denied.
     */
    @IsTest
    static void hasTeamAccessIsFalseWhenOnlyTwoOfThreeObjectsAreGranted() {
        User rep = createRep('partrep');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            grantOrgWideAnalyticsAccessViaCustomPermSet(rep.Id, new Set<String>{
                'GTM_Saved_Configuration__c', 'GTM_Assessment_Request__c'
            });
        }

        Boolean access;
        System.runAs(rep) {
            access = GtmAnalyticsTeamController.hasTeamAccess();
        }
        System.assertEquals(false, access, 'a grant missing GTM_Readout__c must still be denied -- all three objects are required');
    }

    /**
     * Closes the gap this issue targets: today only the UI toggle
     * (hasTeamAccess()) was gated -- a rep calling the three data methods
     * directly (dev console/API) bypassed that entirely. Each method must
     * now reject a plain rep (GTM_Offering_User-equivalent, no org-wide
     * viewAllRecords grant) itself, server-side.
     */
    @IsTest
    static void dataMethodsRejectAPlainRepCallingDirectlyWithoutTheUiToggle() {
        User rep = createRep('dirrep');
        Date rangeStart = Date.today().addDays(-1);
        Date rangeEnd = Date.today();

        System.runAs(rep) {
            Boolean threwForLeaderboard = false;
            try {
                GtmAnalyticsTeamController.getRepLeaderboard(rangeStart, rangeEnd);
            } catch (AuraHandledException e) {
                threwForLeaderboard = true;
            }
            System.assert(threwForLeaderboard, 'getRepLeaderboard must reject a plain rep calling it directly');

            Boolean threwForInstrumentVersion = false;
            try {
                GtmAnalyticsTeamController.getInstrumentVersionComparison(rangeStart, rangeEnd);
            } catch (AuraHandledException e) {
                threwForInstrumentVersion = true;
            }
            System.assert(threwForInstrumentVersion, 'getInstrumentVersionComparison must reject a plain rep calling it directly');

            Boolean threwForFlagged = false;
            try {
                GtmAnalyticsTeamController.getFlaggedRequests(rangeStart, rangeEnd);
            } catch (AuraHandledException e) {
                threwForFlagged = true;
            }
            System.assert(threwForFlagged, 'getFlaggedRequests must reject a plain rep calling it directly');
        }
    }

    /**
     * The mirror of the previous test: a user holding the generalized
     * grant (via a differently-named permission set, not GTM_Offering_Admin)
     * on all three objects must pass the same server-side guard on all
     * three data methods, not just the hasTeamAccess() UI helper.
     */
    @IsTest
    static void dataMethodsAllowAUserWithTheGeneralizedGrantOnAllThreeObjects() {
        User rep = createRep('allowrep');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            grantOrgWideAnalyticsAccessViaCustomPermSet(rep.Id, new Set<String>{
                'GTM_Saved_Configuration__c', 'GTM_Assessment_Request__c', 'GTM_Readout__c'
            });
        }

        Date rangeStart = Date.today().addDays(-1);
        Date rangeEnd = Date.today();

        Test.startTest();
        System.runAs(rep) {
            List<GtmAnalyticsTeamController.RepRow> rows =
                GtmAnalyticsTeamController.getRepLeaderboard(rangeStart, rangeEnd);
            System.assertNotEquals(null, rows, 'a user with the generalized grant must be allowed through');

            List<GtmAnalyticsTeamController.InstrumentVersionRow> versionRows =
                GtmAnalyticsTeamController.getInstrumentVersionComparison(rangeStart, rangeEnd);
            System.assertNotEquals(null, versionRows);

            GtmAnalyticsTeamController.FlaggedResult flagged =
                GtmAnalyticsTeamController.getFlaggedRequests(rangeStart, rangeEnd);
            System.assertNotEquals(null, flagged);
        }
        Test.stopTest();
    }

    private static User createRep(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias             = alias,
            Email             = alias + '@example.com',
            EmailEncodingKey  = 'UTF-8',
            LastName          = 'Rep ' + alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'America/New_York',
            Username          = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }
}
