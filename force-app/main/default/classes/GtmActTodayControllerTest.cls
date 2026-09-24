/**
 * Tests for GtmActTodayController (issue overview-sales-dashboard-2-act-today).
 * Every test creates its own data; nothing reads or seeds live records.
 */
@IsTest
private class GtmActTodayControllerTest {

    private static Integer seq = 0;

    private static User createUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'Act ' + alias, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    /** A user whose permission set grants viewAllRecords on the request object
     *  (NOT the shipped GTM_Offering_Admin, so the test proves the pattern). */
    private static User createViewAllUser(String alias) {
        User u = createUser(alias);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet ps = new PermissionSet(Name = 'ActTodayViewAll' + alias, Label = 'ActToday ViewAll ' + alias);
            insert ps;
            insert new ObjectPermissions(
                ParentId = ps.Id, SobjectType = 'GTM_Assessment_Request__c',
                PermissionsRead = true, PermissionsViewAllRecords = true
            );
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    private static GTM_Assessment_Request__c newRequest(Id ownerId, String status, String company, Datetime submitted) {
        seq++;
        return new GTM_Assessment_Request__c(
            OwnerId = ownerId,
            Requester_Name__c = 'Requester ' + seq,
            Requester_Email__c = 'act' + seq + '@example.com',
            Company__c = company,
            Status__c = status,
            Submitted_At__c = submitted,
            Offering_Key__c = 'offer-a'
        );
    }

    private static GTM_Readout__c newReadout(Id requestId, String status, Datetime notificationSent) {
        return new GTM_Readout__c(
            Assessment_Request__c = requestId, Offering_Key__c = 'offer-a',
            Status__c = status, Notification_Sent_Date__c = notificationSent
        );
    }

    private static GTM_Saved_Configuration__c newLink(Id ownerId, String company, Id accountId) {
        seq++;
        return new GTM_Saved_Configuration__c(
            OwnerId = ownerId, Offering__c = 'migration-accelerator', Company__c = company,
            Account__c = accountId, Generated_URL__c = 'https://example.com/act' + seq,
            Presentation_Stage__c = 'Sent', Active__c = true
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

    // ------------------------------------------------------------ names

    @IsTest
    static void firstDistinctDedupesCaseInsensitivelyAndCapsAtThree() {
        List<String> out = GtmActTodayController.firstDistinct(new List<String>{
            'Acme', null, ' acme ', '', 'Beta', 'BETA', 'Gamma', 'Delta'
        });
        Assert.areEqual(new List<String>{ 'Acme', 'Beta', 'Gamma' }, out);
    }

    // ------------------------------------------------- new requests / readouts

    @IsTest
    static void newRequestsCountNamesDedupeAndCap() {
        User rep = createUser('acttrep1');
        Datetime now = Datetime.now();
        List<GTM_Assessment_Request__c> reqs = new List<GTM_Assessment_Request__c>{
            newRequest(rep.Id, 'New', 'Oldest Co', now.addDays(-5)),
            newRequest(rep.Id, 'New', 'Acme', now.addDays(-4)),
            newRequest(rep.Id, 'New', 'ACME', now.addDays(-3)),
            newRequest(rep.Id, 'New', 'Beta', now.addDays(-2)),
            newRequest(rep.Id, 'New', 'Gamma', now.addDays(-1)),
            newRequest(rep.Id, 'Completed', 'Not New Co', now)
        };
        insert reqs;

        GtmActTodayController.ActToday result;
        System.runAs(rep) {
            result = GtmActTodayController.getActToday();
        }

        Assert.areEqual(5, result.newRequests.count, 'Completed is not a new request; the count is not the name count');
        Assert.areEqual(new List<String>{ 'Gamma', 'Beta', 'ACME' }, result.newRequests.names,
            'Newest first, the two Acme rows shown once, capped at 3');
        Assert.isFalse(result.newRequests.capped);
    }

    @IsTest
    static void newRequestNameFallsBackToRequesterWhenCompanyBlank() {
        User rep = createUser('acttrep2');
        GTM_Assessment_Request__c r = newRequest(rep.Id, 'New', null, Datetime.now());
        r.Requester_Name__c = 'Solo Requester';
        insert r;
        GtmActTodayController.ActToday result;
        System.runAs(rep) {
            result = GtmActTodayController.getActToday();
        }
        Assert.areEqual(1, result.newRequests.count);
        Assert.areEqual(new List<String>{ 'Solo Requester' }, result.newRequests.names);
    }

    @IsTest
    static void readoutWaitingIsPendingPlusApprovedUnsentOnly() {
        User rep = createUser('acttrep3');
        Datetime now = Datetime.now();
        List<GTM_Assessment_Request__c> reqs = new List<GTM_Assessment_Request__c>();
        for (String c : new List<String>{ 'Pending Co', 'Unsent Co', 'Notified Co', 'Draft Co', 'Published Co', 'None Co' }) {
            reqs.add(newRequest(rep.Id, 'Completed', c, now));
        }
        insert reqs;
        insert new List<GTM_Readout__c>{
            newReadout(reqs[0].Id, 'Pending Approval', null),
            newReadout(reqs[1].Id, 'Approved', null),
            newReadout(reqs[2].Id, 'Approved', now),
            newReadout(reqs[3].Id, 'Draft', null),
            newReadout(reqs[4].Id, 'Published', now)
        };

        GtmActTodayController.ActToday result;
        System.runAs(rep) {
            result = GtmActTodayController.getActToday();
        }

        Assert.areEqual(2, result.readoutWaiting.count,
            'Pending Approval and Approved-not-notified only; Approved+notified, Draft, Published and none are excluded');
        Assert.areEqual(new Set<String>{ 'Pending Co', 'Unsent Co' }, new Set<String>(result.readoutWaiting.names));
        Assert.areEqual(0, result.newRequests.count, 'These requests are Completed, not New');
    }

    // ------------------------------------------------------------ zero state

    @IsTest
    static void everythingIsZeroAndEmptyWhenNothingIsWaiting() {
        User rep = createUser('acttrep4');
        GtmActTodayController.ActToday result;
        System.runAs(rep) {
            result = GtmActTodayController.getActToday();
        }
        Assert.areEqual(0, result.newRequests.count);
        Assert.isTrue(result.newRequests.names.isEmpty());
        Assert.areEqual(0, result.readoutWaiting.count);
        Assert.isTrue(result.readoutWaiting.names.isEmpty());
        Assert.isTrue(result.cameBackNames.isEmpty());
        Assert.isTrue(result.wentQuietNames.isEmpty());
    }

    // -------------------------------------------------------------- scoping

    @IsTest
    static void twoRepsSeeOnlyTheirOwnAndViewAllSeesBoth() {
        User repA = createUser('acttrepa');
        User repB = createUser('acttrepb');
        User viewer = createViewAllUser('acttview');
        Datetime now = Datetime.now();
        GTM_Assessment_Request__c ra = newRequest(repA.Id, 'New', 'A Corp', now);
        GTM_Assessment_Request__c rb = newRequest(repB.Id, 'New', 'B Corp', now);
        GTM_Assessment_Request__c rc = newRequest(repB.Id, 'Completed', 'B Ready', now);
        insert new List<GTM_Assessment_Request__c>{ ra, rb, rc };
        insert newReadout(rc.Id, 'Pending Approval', null);

        GtmActTodayController.ActToday a;
        GtmActTodayController.ActToday b;
        GtmActTodayController.ActToday all;
        System.runAs(repA) { a = GtmActTodayController.getActToday(); }
        System.runAs(repB) { b = GtmActTodayController.getActToday(); }
        System.runAs(viewer) { all = GtmActTodayController.getActToday(); }

        Assert.areEqual(new List<String>{ 'A Corp' }, a.newRequests.names);
        Assert.areEqual(1, a.newRequests.count);
        Assert.areEqual(0, a.readoutWaiting.count, 'repA owns no waiting readout');
        Assert.areEqual(new List<String>{ 'B Corp' }, b.newRequests.names);
        Assert.areEqual(1, b.readoutWaiting.count);
        Assert.areEqual(2, all.newRequests.count, 'A view-all permission set sees every rep\'s requests');
        Assert.areEqual(1, all.readoutWaiting.count);
    }

    @IsTest
    static void hotAndQuietNamesAreScopedToTheRunningRep() {
        User repA = createUser('acttstga');
        User repB = createUser('acttstgb');
        GTM_Saved_Configuration__c la = newLink(repA.Id, 'A Link Co', null);
        GTM_Saved_Configuration__c lb = newLink(repB.Id, 'B Link Co', null);
        insert new List<GTM_Saved_Configuration__c>{ la, lb };
        insert new List<SObject>{
            newEvent(repA.Id, la.Id, 'Form Opened', 'a1'),
            newEvent(repB.Id, lb.Id, 'Form Opened', 'b1')
        };
        GtmActTodayController.ActToday a;
        System.runAs(repA) { a = GtmActTodayController.getActToday(); }
        Assert.areEqual(new List<String>{ 'A Link Co' }, a.wentQuietNames);
    }

    // -------------------------------------------------------- hot / quiet

    @IsTest
    static void hotAndQuietNamesPreferAccountNameDedupeAndMatchTheService() {
        User rep = createUser('acttstg1');
        Account acct = new Account(Name = 'Real Account Inc');
        insert acct;
        // Quiet: four links, two on the same account, one blank-account (Company__c fallback).
        List<GTM_Saved_Configuration__c> quiet = new List<GTM_Saved_Configuration__c>{
            newLink(rep.Id, 'Typed Co 1', acct.Id),
            newLink(rep.Id, 'Typed Co 2', acct.Id),
            newLink(rep.Id, 'Fallback Co', null),
            newLink(rep.Id, 'Third Co', null),
            newLink(rep.Id, 'Fourth Co', null)
        };
        GTM_Saved_Configuration__c hotLink = newLink(rep.Id, 'Hot Co', null);
        List<GTM_Saved_Configuration__c> all = new List<GTM_Saved_Configuration__c>(quiet);
        all.add(hotLink);
        insert all;

        List<SObject> events = new List<SObject>();
        for (GTM_Saved_Configuration__c l : quiet) {
            events.add(newEvent(rep.Id, l.Id, 'Form Opened', 'q' + l.Id));
        }
        events.add(newEvent(rep.Id, hotLink.Id, 'Page View', 'h1'));
        events.add(newEvent(rep.Id, hotLink.Id, 'Page View', 'h2'));
        insert events;

        GtmActTodayController.ActToday result;
        GtmLinkStageService.StageCounts counts;
        List<Id> quietIds;
        List<Id> hotIds;
        System.runAs(rep) {
            result = GtmActTodayController.getActToday();
            counts = GtmLinkStageService.getStageCounts();
            quietIds = GtmLinkStageService.getLinkIdsForStage('quiet');
            hotIds = GtmLinkStageService.getLinkIdsForStage('hot');
        }

        Assert.areEqual(5, counts.quiet);
        Assert.areEqual(counts.quiet, quietIds.size(), 'Service count equals its own id list');
        Assert.areEqual(1, counts.hot);
        Assert.areEqual(counts.hot, hotIds.size());
        Assert.areEqual(new List<String>{ 'Hot Co' }, result.cameBackNames);
        Assert.areEqual(3, result.wentQuietNames.size(), 'Capped at 3');
        Assert.isTrue(result.wentQuietNames.contains('Real Account Inc'),
            'Account__r.Name is preferred over Company__c');
        Assert.isFalse(result.wentQuietNames.contains('Typed Co 1') || result.wentQuietNames.contains('Typed Co 2'));
        Assert.areEqual(3, new Set<String>(result.wentQuietNames).size(),
            'The two links on one account are shown once');
    }

    // ------------------------------------------------------ delegation parity

    @IsTest
    static void tileCountsEqualGetAssessmentPageTotals() {
        User rep = createUser('acttpar1');
        Datetime now = Datetime.now();
        List<GTM_Assessment_Request__c> reqs = new List<GTM_Assessment_Request__c>();
        for (Integer i = 0; i < 4; i++) {
            reqs.add(newRequest(rep.Id, i < 3 ? 'New' : 'Completed', 'Parity ' + i, now.addHours(-i)));
        }
        insert reqs;
        insert newReadout(reqs[3].Id, 'Pending Approval', null);

        GtmAssessmentListController.AssessmentQuery qNew = new GtmAssessmentListController.AssessmentQuery();
        qNew.status = new List<String>{ 'new' };
        GtmAssessmentListController.AssessmentQuery qRo = new GtmAssessmentListController.AssessmentQuery();
        qRo.readout = new List<String>{ 'pending', 'approved-unsent' };

        GtmActTodayController.ActToday result;
        GtmAssessmentListController.AssessmentPage pageNew;
        GtmAssessmentListController.AssessmentPage pageRo;
        System.runAs(rep) {
            result = GtmActTodayController.getActToday();
            pageNew = GtmAssessmentListController.getAssessmentPage(qNew);
            pageRo = GtmAssessmentListController.getAssessmentPage(qRo);
        }

        Assert.areEqual(pageNew.totalCount, result.newRequests.count);
        Assert.areEqual(3, result.newRequests.count);
        Assert.areEqual(pageNew.totalIsCapped, result.newRequests.capped);
        Assert.areEqual(pageRo.totalCount, result.readoutWaiting.count);
        Assert.areEqual(1, result.readoutWaiting.count);
        Assert.areEqual(pageRo.totalIsCapped, result.readoutWaiting.capped);
    }
}
