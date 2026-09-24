/**
 * Simulates two reps with one link each and prospect activity arriving through
 * the real guest entry points. Proves activity is owned by the link owner and
 * that owner-scoped reads give each rep only their own truth, without relying
 * on viewAllRecords (the test permission set grants Read only).
 */
@IsTest
private class GtmRepOwnershipSimulationTest {

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

    private static User repA, repB, guestLike;
    private static GTM_Saved_Configuration__c linkA, linkB;

    private static void setup() {
        repA = makeUser('repa');
        repB = makeUser('repb');
        guestLike = makeUser('gst');
        insert new List<User>{ repA, repB, guestLike };

        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet ps = new PermissionSet(Name = 'SimReadOnly', Label = 'SimReadOnly');
            insert ps;
            List<ObjectPermissions> ops = new List<ObjectPermissions>();
            for (String o : new List<String>{
                    'GTM_Link_Event__c', 'GTM_Saved_Configuration__c', 'GTM_Assessment_Request__c'}) {
                ops.add(new ObjectPermissions(ParentId = ps.Id, SobjectType = o,
                    PermissionsRead = true, PermissionsViewAllRecords = false));
            }
            insert ops;
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = repA.Id, PermissionSetId = ps.Id),
                new PermissionSetAssignment(AssigneeId = repB.Id, PermissionSetId = ps.Id)
            };
        }

        linkA = link(repA.Id, 'Acme A', 'passA');
        linkB = link(repB.Id, 'Beta B', 'passB');
    }

    private static GTM_Saved_Configuration__c link(Id ownerId, String company, String pw) {
        GTM_Saved_Configuration__c c = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = company,
            Generated_URL__c = 'https://example.com/' + company.left(1), Active__c = true,
            Link_Password__c = pw, OwnerId = ownerId
        );
        insert c;
        return c;
    }

    private with sharing class ScopedReader {
        Integer eventsOn(Id linkId) {
            return [SELECT COUNT() FROM GTM_Link_Event__c WHERE Saved_Configuration__c = :linkId];
        }
    }

    private static void guestActivity() {
        System.runAs(guestLike) {
            GtmLinkEventController.logEvent(linkA.Id, 'Page View', 'sA', null, null);
            GtmLinkEventController.logEvent(linkA.Id, 'Page View', 'sA2', null, null);
            GtmLinkEventController.logEvent(linkB.Id, 'Page View', 'sB', null, null);
            GtmLinkEventController.logEvents(linkA.Id, 'sA', new List<GtmLinkEventController.EventInput>{
                ev('Section Viewed', 1), ev('Session End', 2) });
            GtmLinkEventController.logEvents(linkB.Id, 'sB', new List<GtmLinkEventController.EventInput>{
                ev('Section Viewed', 1) });
            GtmFormDraftController.saveDraft(linkA.Id, 'a1b2c3d4e5f60718293a', '{"n":"A"}', 'n', 'sA');
            GtmFormDraftController.clearDraft(linkA.Id, 'a1b2c3d4e5f60718293a');
            GtmFormDraftController.saveDraft(linkB.Id, 'ffffffffffffffffffff', '{"n":"B"}', 'n', 'sB');
            GtmAssessmentDraftController.saveDraft(null, '{"q":"a"}', null, linkA.Id, 'sA');
            GtmAssessmentDraftController.saveDraft(null, '{"q":"b"}', null, linkB.Id, 'sB');
            GtmLinkAuthController.verifyPassword(linkA.Id, 'passA');
            GtmLinkAuthController.verifyPassword(linkB.Id, 'passB');
        }
    }

    private static GtmLinkEventController.EventInput ev(String type, Integer seq) {
        GtmLinkEventController.EventInput e = new GtmLinkEventController.EventInput();
        e.eventType = type; e.sequence = seq;
        return e;
    }

    @IsTest
    static void activityIsOwnedByTheLinkOwnerNotTheGuest() {
        setup();
        guestActivity();

        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Link_Event__c WHERE OwnerId = :guestLike.Id],
            'No event may stay owned by the guest');
        Assert.areEqual(4, [SELECT COUNT() FROM GTM_Link_Event__c WHERE OwnerId = :repA.Id]);
        Assert.areEqual(2, [SELECT COUNT() FROM GTM_Link_Event__c WHERE OwnerId = :repB.Id]);
        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Link_Event__c
            WHERE Saved_Configuration__c = :linkA.Id AND OwnerId != :repA.Id]);

        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Form_Draft__c WHERE OwnerId = :guestLike.Id]);
        Assert.areEqual(3, [SELECT COUNT() FROM GTM_Form_Draft__c WHERE OwnerId = :repA.Id]);
        Assert.areEqual(2, [SELECT COUNT() FROM GTM_Form_Draft__c WHERE OwnerId = :repB.Id]);

        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :linkA.Id AND OwnerId = :repA.Id]);
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :linkB.Id AND OwnerId = :repB.Id]);
    }

    @IsTest
    static void eachRepReadsOnlyTheirOwnActivityWithoutViewAll() {
        setup();
        guestActivity();

        System.runAs(repA) {
            ScopedReader r = new ScopedReader();
            Assert.areEqual(4, r.eventsOn(linkA.Id), 'A sees own link events');
            Assert.areEqual(0, r.eventsOn(linkB.Id), 'A never sees B events');
            Assert.areEqual(2, GtmHomeSnapshotController.getSnapshot().recentViews,
                'A recentViews = A own Page Views');
        }
        System.runAs(repB) {
            ScopedReader r = new ScopedReader();
            Assert.areEqual(2, r.eventsOn(linkB.Id));
            Assert.areEqual(0, r.eventsOn(linkA.Id));
            Assert.areEqual(1, GtmHomeSnapshotController.getSnapshot().recentViews);
        }
    }

    @IsTest
    static void aMintedAssessmentDraftIsOwnedByTheLinkOwner() {
        setup();
        GtmAssessmentDraftController.DraftHandle h;
        System.runAs(guestLike) {
            h = GtmAssessmentDraftController.saveDraft(null, '{"q":"a"}', null, linkA.Id, 'sA');
        }
        GTM_Form_Draft__c minted = [SELECT OwnerId FROM GTM_Form_Draft__c WHERE Resume_Token__c = :h.resumeToken];
        Assert.areEqual(repA.Id, minted.OwnerId);
    }
}
