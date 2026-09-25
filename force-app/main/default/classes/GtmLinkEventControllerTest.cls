/**
 * Owner stamp on guest-logged link events: each event belongs to the rep who
 * owns the link, one owner lookup per call, and an unresolvable owner never
 * breaks the prospect's page.
 */
@IsTest
private class GtmLinkEventControllerTest {

    private static User makeUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = tag + String.valueOf(Crypto.getRandomInteger()).replace('-', 'x');
        return new User(
            Alias = tag.left(5), Email = uniq + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = uniq, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = uniq + '@gtmtest.example.com'
        );
    }

    private static GTM_Saved_Configuration__c link(Id ownerId) {
        GTM_Saved_Configuration__c c = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/a', Active__c = true, OwnerId = ownerId
        );
        insert c;
        return c;
    }

    private static GtmLinkEventController.EventInput evt(Integer seq) {
        GtmLinkEventController.EventInput e = new GtmLinkEventController.EventInput();
        e.eventType = 'Section Viewed'; e.step = 'header'; e.sequence = seq;
        return e;
    }

    private static List<GtmLinkEventController.EventInput> batch(Integer n) {
        List<GtmLinkEventController.EventInput> out = new List<GtmLinkEventController.EventInput>();
        for (Integer i = 0; i < n; i++) out.add(evt(i));
        return out;
    }

    @IsTest
    static void aSingleEventIsOwnedByTheLinkOwner() {
        User rep = makeUser('repx');
        insert rep;
        GTM_Saved_Configuration__c c = link(rep.Id);

        Test.startTest();
        GtmLinkEventController.logEvent(c.Id, 'Page View', 'sess-1', null, null);
        Test.stopTest();
        Assert.isNull(GtmLinkOwnerStamp.lastError);

        List<GTM_Link_Event__c> rows = [SELECT OwnerId FROM GTM_Link_Event__c];
        Assert.areEqual(1, rows.size());
        Assert.areEqual(rep.Id, rows[0].OwnerId);
    }

    @IsTest
    static void aHundredEventsAcrossCallsAreAllStampedWithOneLookupPerCall() {
        User rep = makeUser('repy');
        insert rep;
        GTM_Saved_Configuration__c c = link(rep.Id);

        Integer q0 = Limits.getQueries();
        GtmLinkEventController.logEvents(c.Id, 's1', batch(1));
        Integer oneRowCost = Limits.getQueries() - q0;

        Integer q1 = Limits.getQueries();
        GtmLinkEventController.logEvents(c.Id, 's2', batch(60));
        Integer sixtyRowCost = Limits.getQueries() - q1;
        GtmLinkEventController.logEvents(c.Id, 's3', batch(40));
        GtmLinkEventController.logEvents(c.Id, 's4', batch(75));

        Assert.isNull(GtmLinkOwnerStamp.lastError, 'Lookup must not fail');
        Assert.areEqual(2, oneRowCost, 'Two owner-lookup queries per call');
        Assert.areEqual(oneRowCost, sixtyRowCost, 'No per-row queries');
        Assert.areEqual(1 + 60 + 40 + 60, [SELECT COUNT() FROM GTM_Link_Event__c]);
        Assert.areEqual(1 + 60 + 40 + 60,
            [SELECT COUNT() FROM GTM_Link_Event__c WHERE OwnerId = :rep.Id]);
    }

    @IsTest
    static void anInactiveOwnerLeavesTheEventUnstampedButLogged() {
        User rep = makeUser('repz');
        insert rep;
        GTM_Saved_Configuration__c c = link(rep.Id);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            rep.IsActive = false;
            update rep;
        }

        GtmLinkEventController.logEvents(c.Id, 's1', batch(2));

        List<GTM_Link_Event__c> rows = [SELECT OwnerId FROM GTM_Link_Event__c];
        Assert.areEqual(2, rows.size());
        for (GTM_Link_Event__c r : rows) {
            Assert.areNotEqual(rep.Id, r.OwnerId, 'Inactive owner must not be stamped');
        }
    }

    @IsTest
    static void aBadOrMissingConfigIdNeverThrows() {
        GtmLinkEventController.logEvent(null, 'Page View', 's', null, null);
        GtmLinkEventController.logEvent('not-an-id', 'Page View', 's', null, null);
        GtmLinkEventController.logEvents(UserInfo.getUserId(), 's', batch(3));
        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Link_Event__c]);
    }

    // ---------------------------- engagement-state Task sync (issue #31) --

    private static GTM_Saved_Configuration__c linkForContact(Id ownerId, Id contactId) {
        GTM_Saved_Configuration__c c = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/a', Active__c = true,
            OwnerId = ownerId, Contact__c = contactId
        );
        insert c;
        return c;
    }

    private static GTM_Saved_Configuration__c linkForAccount(Id ownerId, Id accountId) {
        GTM_Saved_Configuration__c c = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/a', Active__c = true,
            OwnerId = ownerId, Account__c = accountId
        );
        insert c;
        return c;
    }

    @IsTest
    static void aPageViewFiresTheOpenedTaskAgainstTheContact() {
        User rep = makeUser('repa');
        insert rep;
        Contact con = new Contact(LastName = 'Prospect');
        insert con;
        GTM_Saved_Configuration__c c = linkForContact(rep.Id, con.Id);

        Test.startTest();
        GtmLinkEventController.logEvent(c.Id, 'Page View', 'sess-1', null, null);
        Test.stopTest();

        List<Task> tasks = [
            SELECT WhatId, OwnerId, Subject FROM Task WHERE WhatId = :con.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_OPENED
        ];
        Assert.areEqual(1, tasks.size(), 'A Page View should fire the opened_not_started engagement Task');
        Assert.areEqual(rep.Id, tasks[0].OwnerId, 'The Task must be owned by the link owner');
    }

    @IsTest
    static void aPageViewOnAContactlessLinkFallsBackToTheAccount() {
        User rep = makeUser('repb');
        insert rep;
        Account acc = new Account(Name = 'Fallback Co');
        insert acc;
        GTM_Saved_Configuration__c c = linkForAccount(rep.Id, acc.Id);

        Test.startTest();
        GtmLinkEventController.logEvent(c.Id, 'Page View', 'sess-1', null, null);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :acc.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_OPENED],
            'With no Contact on the link, the Task must fall back to the Account'
        );
    }

    @IsTest
    static void aSecondPageViewDoesNotDuplicateTheOpenedTask() {
        User rep = makeUser('repc');
        insert rep;
        Contact con = new Contact(LastName = 'Prospect');
        insert con;
        GTM_Saved_Configuration__c c = linkForContact(rep.Id, con.Id);

        GtmLinkEventController.logEvent(c.Id, 'Page View', 'sess-1', null, null);

        Test.startTest();
        // A second visit generating another Page View must not spawn a
        // second open Task for the same state.
        GtmLinkEventController.logEvent(c.Id, 'Page View', 'sess-2', null, null);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :con.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_OPENED]
        );
    }

    @IsTest
    static void aFormOpenedEventAfterAPageViewClosesTheOpenedTaskAndFiresStarted() {
        User rep = makeUser('repd');
        insert rep;
        Contact con = new Contact(LastName = 'Prospect');
        insert con;
        GTM_Saved_Configuration__c c = linkForContact(rep.Id, con.Id);
        GtmLinkEventController.logEvent(c.Id, 'Page View', 'sess-1', null, null);

        Test.startTest();
        GtmLinkEventController.logEvent(c.Id, 'Form Opened', 'sess-1', null, null);
        Test.stopTest();

        Assert.areEqual(
            'Completed',
            [SELECT Status FROM Task WHERE WhatId = :con.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_OPENED LIMIT 1].Status
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :con.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_STARTED
                AND Status != 'Completed']
        );
    }

    @IsTest
    static void anIrrelevantEventTypeNeverFiresAnEngagementTask() {
        User rep = makeUser('repe');
        insert rep;
        Contact con = new Contact(LastName = 'Prospect');
        insert con;
        GTM_Saved_Configuration__c c = linkForContact(rep.Id, con.Id);

        Test.startTest();
        GtmLinkEventController.logEvent(c.Id, 'Section Viewed', 'sess-1', null, null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :con.Id]);
    }

    @IsTest
    static void aLinkWithNeitherContactNorAccountNeverFiresAnEngagementTask() {
        User rep = makeUser('repf');
        insert rep;
        GTM_Saved_Configuration__c c = link(rep.Id); // no Contact__c/Account__c set

        Test.startTest();
        GtmLinkEventController.logEvent(c.Id, 'Page View', 'sess-1', null, null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Task]);
    }

    @IsTest
    static void logEventsBatchFiresTheOpenedTaskOnceForTheWholeBatch() {
        User rep = makeUser('repg');
        insert rep;
        Contact con = new Contact(LastName = 'Prospect');
        insert con;
        GTM_Saved_Configuration__c c = linkForContact(rep.Id, con.Id);

        List<GtmLinkEventController.EventInput> events = batch(3);
        GtmLinkEventController.EventInput pv = new GtmLinkEventController.EventInput();
        pv.eventType = 'Page View';
        pv.sequence = 99;
        events.add(pv);

        Test.startTest();
        GtmLinkEventController.logEvents(c.Id, 'sess-1', events);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :con.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_OPENED],
            'One engagement Task per batch, even though the batch carried several event rows'
        );
    }

    @IsTest
    static void aBatchWithOnlyIrrelevantEventTypesDoesNotPayTheEngagementQueryCost() {
        // Mirrors aHundredEventsAcrossCallsAreAllStampedWithOneLookupPerCall's
        // own exact-query-count assertion style: batch()'s events are all
        // 'Section Viewed', so the engagement sync path must never run, and
        // the per-call query cost must stay exactly what it was before this
        // ticket's change.
        User rep = makeUser('reph');
        insert rep;
        Contact con = new Contact(LastName = 'Prospect');
        insert con;
        GTM_Saved_Configuration__c c = linkForContact(rep.Id, con.Id);

        Integer q0 = Limits.getQueries();
        GtmLinkEventController.logEvents(c.Id, 's1', batch(5));
        Integer cost = Limits.getQueries() - q0;

        Assert.areEqual(2, cost, 'No engagement-sync queries should run for a batch with no Page View/Form Opened');
        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :con.Id]);
    }
}
