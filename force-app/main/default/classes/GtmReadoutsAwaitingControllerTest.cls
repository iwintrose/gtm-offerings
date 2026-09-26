/**
 * Tests for GtmReadoutsAwaitingController (issue
 * overview-bd-heat-redesign-3-daily-widgets). Every test creates its own
 * data; nothing reads or seeds live records. COARSE PROXY ONLY -- these
 * tests assert on Status__c/Notification_Sent_Date__c boundaries, never on
 * any viewed/replied signal (there is none; see the class doc comment).
 */
@IsTest
private class GtmReadoutsAwaitingControllerTest {

    private static Integer seq = 0;

    private static User createUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'Readouts ' + alias, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    private static User createViewAllUser(String alias) {
        User u = createUser(alias);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet ps = new PermissionSet(Name = 'ReadoutsViewAll' + alias, Label = 'Readouts ViewAll ' + alias);
            insert ps;
            insert new ObjectPermissions(
                ParentId = ps.Id, SobjectType = 'GTM_Readout__c',
                PermissionsRead = true, PermissionsViewAllRecords = true
            );
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    private static Opportunity newOpp(Id accountId, String name) {
        return new Opportunity(
            AccountId = accountId, Name = name, StageName = 'Prospecting',
            CloseDate = Date.today().addMonths(1)
        );
    }

    private static GTM_Readout__c newReadout(Id ownerId, Id opportunityId, String status, Datetime sentDate) {
        return newReadout(ownerId, opportunityId, null, status, sentDate);
    }

    private static GTM_Readout__c newReadout(Id ownerId, Id opportunityId, Id assessmentRequestId, String status, Datetime sentDate) {
        seq++;
        return new GTM_Readout__c(
            OwnerId = ownerId, Opportunity__c = opportunityId, Assessment_Request__c = assessmentRequestId,
            Offering_Key__c = 'offer-a', Status__c = status, Notification_Sent_Date__c = sentDate
        );
    }

    @IsTest
    static void repSeesOnlyOwnPublishedReadoutsWithSentDate() {
        User repA = createUser('rawrepa');
        User repB = createUser('rawrepb');
        Account acct;
        Opportunity opp;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            acct = new Account(Name = 'Readout Co');
            insert acct;
            opp = newOpp(acct.Id, 'Readout Deal');
            insert opp;
        }
        Datetime sentThreeDaysAgo = Datetime.now().addDays(-3);
        List<GTM_Readout__c> readouts = new List<GTM_Readout__c>{
            newReadout(repA.Id, opp.Id, 'Published', sentThreeDaysAgo),          // included
            newReadout(repA.Id, opp.Id, 'Draft', sentThreeDaysAgo),              // excluded: not Published
            newReadout(repA.Id, opp.Id, 'Published', null),                      // excluded: no sent date
            newReadout(repB.Id, opp.Id, 'Published', sentThreeDaysAgo)           // excluded: other rep's readout
        };
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert readouts;
        }

        List<GtmReadoutsAwaitingController.ReadoutRow> rows;
        System.runAs(repA) {
            rows = GtmReadoutsAwaitingController.getReadoutsAwaiting();
        }
        System.assertEquals(1, rows.size(), 'only the Published readout with a sent date, owned by repA');
        System.assertEquals(3, rows[0].daysSinceSent, 'days-since-sent proxy computed from Notification_Sent_Date__c');
        System.assertEquals('Readout Co', rows[0].accountName);
        System.assertEquals('Readout Deal', rows[0].opportunityName);
        System.assertEquals('offer-a', rows[0].offeringKey, 'offeringKey must thread through for c/gtmNavigate openReadout');
        System.assertEquals(null, rows[0].assessmentRequestId, 'orphan readout (no AR) is a real supported state -- see Assessment_Request__c field comment');
    }

    /** A readout has no page of its own (docs/architecture/gtm-row-open-and-links.md):
     *  the LWC opens it via c/gtmNavigate's openReadout(host, readoutId,
     *  assessmentRequestId, offeringKey), so both ids must be on the row. */
    @IsTest
    static void rowCarriesAssessmentRequestIdAndOfferingKeyForNavigation() {
        User rep = createUser('rawrepnv');
        Account acct;
        Opportunity opp;
        GTM_Assessment_Request__c req;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            acct = new Account(Name = 'Readout Nav Co');
            insert acct;
            opp = newOpp(acct.Id, 'Readout Nav Deal');
            insert opp;
            req = new GTM_Assessment_Request__c(
                OwnerId = rep.Id, Requester_Name__c = 'Requester Nav', Requester_Email__c = 'navrep@example.com',
                Company__c = 'Readout Nav Co', Status__c = 'Submitted', Offering_Key__c = 'offer-a'
            );
            insert req;
            insert newReadout(rep.Id, opp.Id, req.Id, 'Published', Datetime.now().addDays(-2));
        }
        List<GtmReadoutsAwaitingController.ReadoutRow> rows;
        System.runAs(rep) {
            rows = GtmReadoutsAwaitingController.getReadoutsAwaiting();
        }
        System.assertEquals(1, rows.size());
        System.assertEquals(req.Id, rows[0].assessmentRequestId, 'AR id must thread through so the LWC can navigate to the parent assessment workspace');
        System.assertEquals('offer-a', rows[0].offeringKey);
    }

    @IsTest
    static void adminWithViewAllSeesEveryonesPublishedReadouts() {
        User repA = createUser('rawrepva');
        User admin = createViewAllUser('rawadmva');
        Account acct;
        Opportunity opp;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            acct = new Account(Name = 'Readout Co 2');
            insert acct;
            opp = newOpp(acct.Id, 'Readout Deal 2');
            insert opp;
            insert newReadout(repA.Id, opp.Id, 'Published', Datetime.now().addDays(-1));
            insert newReadout(admin.Id, opp.Id, 'Published', Datetime.now().addDays(-2));
        }
        List<GtmReadoutsAwaitingController.ReadoutRow> rows;
        System.runAs(admin) {
            rows = GtmReadoutsAwaitingController.getReadoutsAwaiting();
        }
        System.assertEquals(2, rows.size(), 'viewAll grant sees both reps\' Published readouts');
    }

    @IsTest
    static void daysSinceSentZeroWhenSentToday() {
        User rep = createUser('rawreptd');
        Account acct;
        Opportunity opp;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            acct = new Account(Name = 'Readout Co 3');
            insert acct;
            opp = newOpp(acct.Id, 'Readout Deal 3');
            insert opp;
            insert newReadout(rep.Id, opp.Id, 'Published', Datetime.now());
        }
        List<GtmReadoutsAwaitingController.ReadoutRow> rows;
        System.runAs(rep) {
            rows = GtmReadoutsAwaitingController.getReadoutsAwaiting();
        }
        System.assertEquals(1, rows.size());
        System.assertEquals(0, rows[0].daysSinceSent, 'sent today: zero days since');
    }

    @IsTest
    static void executesNoDml() {
        User rep = createUser('rawrepdm');
        Account acct;
        Opportunity opp;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            acct = new Account(Name = 'Readout Co 4');
            insert acct;
            opp = newOpp(acct.Id, 'Readout Deal 4');
            insert opp;
            insert newReadout(rep.Id, opp.Id, 'Published', Datetime.now());
        }
        Integer before;
        Integer after;
        System.runAs(rep) {
            before = Limits.getDmlStatements();
            GtmReadoutsAwaitingController.getReadoutsAwaiting();
            after = Limits.getDmlStatements();
        }
        System.assertEquals(before, after, 'read-only');
    }
}
