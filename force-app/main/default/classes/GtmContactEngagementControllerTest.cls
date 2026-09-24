@IsTest
private class GtmContactEngagementControllerTest {

    // ── helpers ──────────────────────────────────────────────────────────────

    private static Contact makeContact() {
        Contact c = new Contact(LastName = 'TestProspect');
        insert c;
        return c;
    }

    private static GTM_Saved_Configuration__c makeConfig(Id contactId, Boolean active) {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Contact__c  = contactId,
            Active__c   = active,
            Company__c  = 'Acme Corp',
            Offering__c = 'Cloud Modernization'
        );
        insert cfg;
        return cfg;
    }

    private static GTM_Saved_Configuration__c makeConfigFor(Id contactId, Id accountId, Id ownerId) {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Contact__c  = contactId,
            Account__c  = accountId,
            Active__c   = true,
            Company__c  = 'Acme Corp',
            Offering__c = 'Cloud Modernization'
        );
        if (ownerId != null) {
            cfg.OwnerId = ownerId;
        }
        insert cfg;
        return cfg;
    }

    private static GTM_Link_Event__c makeEvent(Id configId, String eventType) {
        GTM_Link_Event__c evt = new GTM_Link_Event__c(
            Saved_Configuration__c = configId,
            Event_Type__c          = eventType
        );
        insert evt;
        return evt;
    }

    private static GTM_Assessment_Request__c makeRequest(Id configId, DateTime submittedAt) {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Saved_Configuration__c = configId,
            Submitted_At__c        = submittedAt
        );
        insert req;
        return req;
    }

    private static GTM_Readout__c makeReadout(Id requestId, String status, Boolean notificationSent) {
        GTM_Readout__c ro = new GTM_Readout__c(
            Assessment_Request__c = requestId,
            Offering_Key__c       = 'migration-accelerator',
            Status__c             = status,
            Notification_Sent_Date__c = notificationSent ? DateTime.now() : null
        );
        insert ro;
        return ro;
    }

    /** Same pattern GtmAnalyticsTeamControllerTest.createRep uses -- alias
     *  capped at 8 chars (the Alias field's own limit). */
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

    private static void assignPermSet(Id userId, String permSetName) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :permSetName LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
        }
    }

    /** UserRole is a setup object like User/PermissionSet -- DML on it must
     *  stay isolated in its own System.runAs, same reason createRep/
     *  assignPermSet already wrap theirs (mixing setup and non-setup DML in
     *  one transaction throws MIXED_DML_OPERATION). devName is expected to
     *  be unique per test run (callers pass a timestamp-suffixed name) --
     *  UserRole is one of the standard objects visible to test methods
     *  regardless of SeeAllData, so a fixed literal could collide with real
     *  org data. */
    private static UserRole createRole(String devName, Id parentRoleId) {
        UserRole r = new UserRole(
            DeveloperName = devName,
            Name           = devName,
            ParentRoleId   = parentRoleId
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert r;
        }
        return r;
    }

    // ── contactId mode (Contact record page) — backward compatible ─────────

    @IsTest
    static void testContactScopedSubmittedDraftIsRanked1() {
        Contact c = makeContact();
        GTM_Saved_Configuration__c cfg = makeConfig(c.Id, true);
        makeEvent(cfg.Id, 'Page View');
        GTM_Assessment_Request__c req = makeRequest(cfg.Id, DateTime.now().addDays(-1));
        makeReadout(req.Id, 'Draft', false);

        Test.startTest();
        GtmContactEngagementController.EngagementQueueResult result =
            GtmContactEngagementController.getEngagementSummaries(c.Id, null, null, null, null);
        Test.stopTest();

        System.assertEquals(1, result.items.size(), 'Should return one summary');
        GtmContactEngagementController.LinkEngagementSummary s = result.items[0];
        System.assertEquals('Acme Corp', s.company);
        System.assertEquals('Cloud Modernization', s.offering);
        System.assert(s.active, 'Link should be active');
        System.assertNotEquals(null, s.lastPageView);
        System.assert(s.assessmentSubmitted, 'Assessment should be submitted');
        System.assertNotEquals(null, s.assessmentSubmittedAt);
        System.assertEquals(req.Id, s.recordId, 'recordId should be the assessment request id');
        System.assertEquals('submitted_draft', s.state);
        System.assertEquals('Your turn — open the readout', s.stateLabel);
        System.assertEquals(1, s.rank);
        System.assertEquals('open_readout', s.primaryAction);
        System.assertEquals(false, s.readoutSent, 'Draft readout is not Published yet');
    }

    @IsTest
    static void testContactScopedNoEventsNoAssessmentIsNeverOpened() {
        Contact c = makeContact();
        makeConfig(c.Id, false);

        Test.startTest();
        GtmContactEngagementController.EngagementQueueResult result =
            GtmContactEngagementController.getEngagementSummaries(c.Id, null, null, null, null);
        Test.stopTest();

        System.assertEquals(1, result.items.size());
        GtmContactEngagementController.LinkEngagementSummary s = result.items[0];
        System.assertEquals(null, s.lastPageView);
        System.assert(!s.assessmentSubmitted);
        System.assertEquals(null, s.assessmentSubmittedAt);
        System.assertEquals('never_opened', s.state);
        System.assertEquals('Not yet opened', s.stateLabel);
        System.assertEquals(5, s.rank);
        System.assertEquals('resend', s.primaryAction);
        System.assertEquals(null, s.recordId);
    }

    @IsTest
    static void testContactNoLinksReturnsEmptyResult() {
        Contact c = makeContact();

        Test.startTest();
        GtmContactEngagementController.EngagementQueueResult result =
            GtmContactEngagementController.getEngagementSummaries(c.Id, null, null, null, null);
        Test.stopTest();

        System.assert(result.items.isEmpty(), 'Should return empty list when contact has no links');
        System.assertEquals(0, result.totalCount);
        System.assertEquals(false, result.truncated);
    }

    // ── accountId mode (gtmOverview.handleAccountClick drill-in) ───────────

    @IsTest
    static void testAccountScopedIgnoresScopeParam() {
        Account acc = new Account(Name = 'Commercial Metals');
        insert acc;
        Contact c1 = makeContact();
        Contact c2 = makeContact();
        makeConfigFor(c1.Id, acc.Id, null);
        makeConfigFor(c2.Id, acc.Id, null);
        // A link on a different account must not show up.
        Account other = new Account(Name = 'Other Co');
        insert other;
        makeConfigFor(null, other.Id, null);

        Test.startTest();
        GtmContactEngagementController.EngagementQueueResult result =
            GtmContactEngagementController.getEngagementSummaries(null, acc.Id, 'all', null, null);
        Test.stopTest();

        System.assertEquals(2, result.items.size(), 'Only the two links on the requested account');
    }

    // ── scope: mine / team / all ────────────────────────────────────────────

    @IsTest
    static void testDefaultScopeIsMineWhenNoContactOrAccountOrScopeSupplied() {
        Contact c = makeContact();
        makeConfigFor(c.Id, null, UserInfo.getUserId());

        User other = createRep('ceoth1');
        assignPermSet(other.Id, 'GTM_Offering_User');
        // Insert as the elevated running-user context (same pattern
        // createRep/assignPermSet above already use for their own setup
        // DML), not System.runAs(other) -- `other` (Standard User profile,
        // no viewAllRecords) has no sharing access to Contact `c`, which
        // the running user owns, so a runAs(other) insert of a
        // GTM_Saved_Configuration__c referencing c.Id throws
        // INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY on the Contact
        // lookup. The scoping under test is driven entirely by the
        // OwnerId field value set below, not by who performs the insert.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            makeConfigFor(c.Id, null, other.Id);
        }

        Test.startTest();
        GtmContactEngagementController.EngagementQueueResult result =
            GtmContactEngagementController.getEngagementSummaries(null, null, null, null, null);
        Test.stopTest();

        System.assertEquals(1, result.items.size(), 'Default scope is My links -- only the running user\'s own link');
    }

    @IsTest
    static void testUnrecognizedScopeValueDefaultsToMine() {
        Contact c = makeContact();
        makeConfigFor(c.Id, null, UserInfo.getUserId());

        Test.startTest();
        GtmContactEngagementController.EngagementQueueResult result =
            GtmContactEngagementController.getEngagementSummaries(null, null, 'bogus-scope', null, null);
        Test.stopTest();

        System.assertEquals(1, result.items.size(), 'An unrecognized scope key falls back to mine, not an error');
    }

    @IsTest
    static void testAllScopeWithoutViewAllRecordsFallsBackToMine() {
        Contact c = makeContact();
        User rep = createRep('ceall1');
        assignPermSet(rep.Id, 'GTM_Offering_User');
        User other = createRep('ceall2');
        assignPermSet(other.Id, 'GTM_Offering_User');

        // Insert as the elevated running-user context, not
        // System.runAs(rep)/System.runAs(other) -- neither rep has sharing
        // access to Contact `c` (owned by the running user), which would
        // throw INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY on the
        // Contact lookup. The scoping under test is driven entirely by the
        // OwnerId field value, not by who performs the insert (see
        // GtmContactEngagementController's explicit `OwnerId = :me` WHERE
        // clause); only the actual read call below still needs to run as
        // `rep` -- that's what's under test.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            makeConfigFor(c.Id, null, rep.Id);
            makeConfigFor(c.Id, null, other.Id);
        }

        GtmContactEngagementController.EngagementQueueResult result;
        System.runAs(rep) {
            Test.startTest();
            result = GtmContactEngagementController.getEngagementSummaries(null, null, 'all', null, null);
            Test.stopTest();
        }

        System.assertEquals(1, result.items.size(),
            'A rep without viewAllRecords requesting "all" only sees their own link, not the other rep\'s');
    }

    @IsTest
    static void testAllScopeWithViewAllRecordsSeesOrgWide() {
        Contact c = makeContact();
        User admin = createRep('ceadmin');
        assignPermSet(admin.Id, 'GTM_Offering_Admin');
        User rep = createRep('cerep1');
        assignPermSet(rep.Id, 'GTM_Offering_User');

        // Insert as the elevated running-user context -- see the identical
        // comment in testAllScopeWithoutViewAllRecordsFallsBackToMine above
        // for why System.runAs(admin)/System.runAs(rep) around the insert
        // itself throws INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY here.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            makeConfigFor(c.Id, null, admin.Id);
            makeConfigFor(c.Id, null, rep.Id);
        }

        GtmContactEngagementController.EngagementQueueResult result;
        System.runAs(admin) {
            Test.startTest();
            result = GtmContactEngagementController.getEngagementSummaries(null, null, 'all', null, null);
            Test.stopTest();
        }

        System.assertEquals(2, result.items.size(), 'GTM_Offering_Admin holds viewAllRecords -- sees both links');
    }

    @IsTest
    static void testTeamScopeForRolelessUserCollapsesToSelf() {
        Contact c = makeContact();
        User rep = createRep('ceteam1');
        assignPermSet(rep.Id, 'GTM_Offering_User');
        User other = createRep('ceteam2');
        assignPermSet(other.Id, 'GTM_Offering_User');

        // Insert as the elevated running-user context -- see the identical
        // comment in testAllScopeWithoutViewAllRecordsFallsBackToMine above
        // for why System.runAs(rep)/System.runAs(other) around the insert
        // itself throws INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY here.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            makeConfigFor(c.Id, null, rep.Id);
            makeConfigFor(c.Id, null, other.Id);
        }

        GtmContactEngagementController.EngagementQueueResult result;
        System.runAs(rep) {
            Test.startTest();
            result = GtmContactEngagementController.getEngagementSummaries(null, null, 'team', null, null);
            Test.stopTest();
        }

        System.assertEquals(1, result.items.size(),
            'A user with no UserRoleId has no hierarchy to walk -- "team" collapses to just themself');
    }

    /**
     * Positive counterpart to testTeamScopeForRolelessUserCollapsesToSelf
     * (QA's own minor, non-blocking note on this ticket's first pass): a
     * manager whose role sits ABOVE a subordinate's role in a real Role
     * Hierarchy -- not User.ManagerId, which teamMemberIds() deliberately
     * does not use, see its own doc comment -- must see the subordinate's
     * link via the BFS role walk. A peer role entirely outside that branch
     * must not.
     */
    @IsTest
    static void testTeamScopeManagerSeesSubordinatesRecordViaRoleHierarchy() {
        String suffix = String.valueOf(Datetime.now().getTime());
        UserRole managerRole = createRole('CEMgr' + suffix, null);
        UserRole repRole     = createRole('CERep' + suffix, managerRole.Id);
        UserRole outsideRole = createRole('CEOut' + suffix, null);

        User manager  = createRep('cehm1');
        assignPermSet(manager.Id, 'GTM_Offering_User');
        User rep      = createRep('cehr1');
        assignPermSet(rep.Id, 'GTM_Offering_User');
        User outsider = createRep('ceho1');
        assignPermSet(outsider.Id, 'GTM_Offering_User');

        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = manager.Id, UserRoleId = managerRole.Id);
            update new User(Id = rep.Id, UserRoleId = repRole.Id);
            update new User(Id = outsider.Id, UserRoleId = outsideRole.Id);
        }

        Contact c = makeContact();
        // Insert as the elevated running-user context -- see the identical
        // comment in testAllScopeWithoutViewAllRecordsFallsBackToMine above
        // for why System.runAs(rep) around the insert itself throws
        // INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY here.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            makeConfigFor(c.Id, null, rep.Id);
        }

        GtmContactEngagementController.EngagementQueueResult managerResult;
        GtmContactEngagementController.EngagementQueueResult outsiderResult;
        Test.startTest();
        System.runAs(manager) {
            managerResult = GtmContactEngagementController.getEngagementSummaries(null, null, 'team', null, null);
        }
        System.runAs(outsider) {
            outsiderResult = GtmContactEngagementController.getEngagementSummaries(null, null, 'team', null, null);
        }
        Test.stopTest();

        System.assertEquals(1, managerResult.items.size(),
            'The manager\'s role sits above the rep\'s role in the hierarchy -- "team" must walk down to the ' +
            'subordinate role and include their link, not just the manager\'s own (which is empty here)');
        System.assertEquals(0, outsiderResult.items.size(),
            'A role entirely outside the manager\'s branch must not see the subordinate\'s link via "team"');
    }

    // ── D13 ranking: all six states, in one queue, re-sorted correctly ─────

    @IsTest
    static void testAllSixStatesRankInD13Order() {
        Contact c = makeContact();
        Id me = UserInfo.getUserId();

        // 1. Submitted, readout in Draft
        GTM_Saved_Configuration__c cfg1 = makeConfigFor(c.Id, null, me);
        GTM_Assessment_Request__c req1 = makeRequest(cfg1.Id, DateTime.now().addDays(-1));
        makeReadout(req1.Id, 'Draft', false);

        // 2. Readout published but not sent
        GTM_Saved_Configuration__c cfg2 = makeConfigFor(c.Id, null, me);
        GTM_Assessment_Request__c req2 = makeRequest(cfg2.Id, DateTime.now().addDays(-2));
        makeReadout(req2.Id, 'Published', false);

        // 3. Started but not submitted
        GTM_Saved_Configuration__c cfg3 = makeConfigFor(c.Id, null, me);
        makeEvent(cfg3.Id, 'Form Opened');

        // 4. Opened, not started
        GTM_Saved_Configuration__c cfg4 = makeConfigFor(c.Id, null, me);
        makeEvent(cfg4.Id, 'Page View');

        // 5. Never opened
        GTM_Saved_Configuration__c cfg5 = makeConfigFor(c.Id, null, me);

        // 6. Sent / complete
        GTM_Saved_Configuration__c cfg6 = makeConfigFor(c.Id, null, me);
        GTM_Assessment_Request__c req6 = makeRequest(cfg6.Id, DateTime.now().addDays(-3));
        makeReadout(req6.Id, 'Published', true);

        Test.startTest();
        GtmContactEngagementController.EngagementQueueResult result =
            GtmContactEngagementController.getEngagementSummaries(null, null, 'mine', null, null);
        Test.stopTest();

        System.assertEquals(6, result.items.size());
        List<String> expectedOrder = new List<String>{
            'submitted_draft', 'published_unsent', 'started_not_submitted',
            'opened_not_started', 'never_opened', 'sent_complete'
        };
        // Owner feedback on this ticket's first build: the raw enum
        // ("submitted_draft" etc.) was shown directly to the rep, hiding
        // the priority. stateLabel is the human-readable, "who's blocking"
        // fix -- assert it here for all six states, in D13 rank order, so
        // the label mapping never silently drifts from the state enum.
        Map<String, String> expectedLabel = new Map<String, String>{
            'submitted_draft'       => 'Your turn — open the readout',
            'published_unsent'      => 'Your turn — send to prospect',
            'started_not_submitted' => 'Nudge-able — they started, haven\'t finished',
            'opened_not_started'    => 'Nudge-able — they opened, haven\'t started',
            'never_opened'          => 'Not yet opened',
            'sent_complete'         => 'Complete'
        };
        for (Integer i = 0; i < expectedOrder.size(); i++) {
            System.assertEquals(expectedOrder[i], result.items[i].state,
                'Row ' + i + ' should be state ' + expectedOrder[i] + ' but was ' + result.items[i].state);
            System.assertEquals(i + 1, result.items[i].rank);
            System.assertEquals(expectedLabel.get(expectedOrder[i]), result.items[i].stateLabel,
                'Row ' + i + ' (' + expectedOrder[i] + ') should carry its human-readable stateLabel');
            System.assertNotEquals(result.items[i].state, result.items[i].stateLabel,
                'stateLabel must never equal the raw state enum -- that is exactly the bug this fixes');
        }
    }

    /**
     * Every state key in STATE_RANK/STATE_ACTION must also have a
     * stateLabel -- a state that silently falls through to a null label
     * would reproduce the raw-enum bug for that one state without any of
     * the six-state ranking test above catching it directly by name.
     */
    @IsTest
    static void testStateLabelIsNeverBlankForAnyClassifiedRow() {
        Contact c = makeContact();
        Id me = UserInfo.getUserId();
        makeConfigFor(c.Id, null, me); // never_opened -- the simplest case

        Test.startTest();
        GtmContactEngagementController.EngagementQueueResult result =
            GtmContactEngagementController.getEngagementSummaries(null, null, 'mine', null, null);
        Test.stopTest();

        System.assertEquals(1, result.items.size());
        GtmContactEngagementController.LinkEngagementSummary s = result.items[0];
        System.assertNotEquals(null, s.stateLabel, 'stateLabel must be populated for every classified row');
        System.assert(String.isNotBlank(s.stateLabel), 'stateLabel must not be blank');
    }

    /**
     * Same six links as above, but this time cfg5 ("Never opened") is given
     * a Page View AFTER the initial ranking would have placed it -- proving
     * a state change actually re-sorts the row to its new rank rather than
     * just showing a different badge on an unchanged position (per this
     * ticket's own acceptance criterion 1).
     */
    @IsTest
    static void testChangingOneLinkStateReSortsItToTheCorrectRank() {
        Contact c = makeContact();
        Id me = UserInfo.getUserId();

        GTM_Saved_Configuration__c neverOpened = makeConfigFor(c.Id, null, me);
        makeConfigFor(c.Id, null, me);

        Test.startTest();
        GtmContactEngagementController.EngagementQueueResult before =
            GtmContactEngagementController.getEngagementSummaries(null, null, 'mine', null, null);
        for (GtmContactEngagementController.LinkEngagementSummary s : before.items) {
            System.assertEquals('never_opened', s.state);
        }

        // Now one of the two links is opened -- still not started, still
        // ranked below "started"/"submitted", but strictly ABOVE the
        // remaining never-opened link (D13 rank 4 vs rank 5).
        makeEvent(neverOpened.Id, 'Page View');

        GtmContactEngagementController.EngagementQueueResult after =
            GtmContactEngagementController.getEngagementSummaries(null, null, 'mine', null, null);
        Test.stopTest();

        System.assertEquals('opened_not_started', after.items[0].state);
        System.assertEquals(4, after.items[0].rank);
        System.assertEquals('never_opened', after.items[1].state);
        System.assertEquals(5, after.items[1].rank);
    }

    // ── boundary case: readout exists but request has no Submitted_At__c ───

    @IsTest
    static void testReadoutWithoutSubmittedAtIsNotTreatedAsSubmitted() {
        Contact c = makeContact();
        GTM_Saved_Configuration__c cfg = makeConfigFor(c.Id, null, UserInfo.getUserId());
        GTM_Assessment_Request__c req = makeRequest(cfg.Id, null);
        makeReadout(req.Id, 'Draft', false);

        Test.startTest();
        GtmContactEngagementController.EngagementQueueResult result =
            GtmContactEngagementController.getEngagementSummaries(c.Id, null, null, null, null);
        Test.stopTest();

        System.assertEquals(1, result.items.size());
        GtmContactEngagementController.LinkEngagementSummary s = result.items[0];
        System.assert(!s.assessmentSubmitted, 'Submitted_At__c is null -- not submitted, even though a readout row exists');
        System.assertEquals('never_opened', s.state,
            'No engagement signals either -- falls through to never_opened, not submitted_draft');
    }

    // ── paging + truncated flag ─────────────────────────────────────────────

    @IsTest
    static void testPagingReturnsRequestedPageSize() {
        Contact c = makeContact();
        Id me = UserInfo.getUserId();
        for (Integer i = 0; i < 5; i++) {
            makeConfigFor(c.Id, null, me);
        }

        Test.startTest();
        GtmContactEngagementController.EngagementQueueResult page1 =
            GtmContactEngagementController.getEngagementSummaries(null, null, 'mine', 1, 2);
        GtmContactEngagementController.EngagementQueueResult page2 =
            GtmContactEngagementController.getEngagementSummaries(null, null, 'mine', 2, 2);
        GtmContactEngagementController.EngagementQueueResult page3 =
            GtmContactEngagementController.getEngagementSummaries(null, null, 'mine', 3, 2);
        Test.stopTest();

        System.assertEquals(2, page1.items.size());
        System.assertEquals(2, page2.items.size());
        System.assertEquals(1, page3.items.size(), 'Last page has the remainder');
        System.assertEquals(5, page1.totalCount);
        System.assertEquals(false, page1.truncated);
    }

    @IsTest
    static void testTruncatedFlagWhenCandidateCeilingIsHit() {
        GtmContactEngagementController.candidateCeiling = 2;
        Contact c = makeContact();
        Id me = UserInfo.getUserId();
        for (Integer i = 0; i < 3; i++) {
            makeConfigFor(c.Id, null, me);
        }

        Test.startTest();
        GtmContactEngagementController.EngagementQueueResult result =
            GtmContactEngagementController.getEngagementSummaries(null, null, 'mine', 1, 10);
        Test.stopTest();

        System.assertEquals(true, result.truncated, 'Hit the (test-lowered) candidate ceiling');
        System.assertEquals(2, result.items.size(), 'Only the candidates actually fetched are returned/ranked');
    }

    @IsTest
    static void testNullContactAccountAndScopeReturnsEmptyListWithoutException() {
        Test.startTest();
        GtmContactEngagementController.EngagementQueueResult result =
            GtmContactEngagementController.getEngagementSummaries(null, null, null, null, null);
        Test.stopTest();

        System.assert(result.items.isEmpty(), 'No links exist for the running user -- empty, not an exception');
    }
}
