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
}
