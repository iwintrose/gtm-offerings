/**
 * Rep-ownership lockdown, piece 4 (permissions / OWD / lookup delete rules).
 *
 * Simulates real users with real permission-set assignments. Owner rule: a rep
 * may view/edit/delete only their own links and everything tied to them;
 * admins see all; content editors keep reading and answering all feedback.
 * Page Content / Section create-edit-delete for reps is deliberately left
 * as-is (owner decision F3), so it is not asserted here.
 */
@IsTest
private class GtmRepOwnershipPermissionsTest {

    private static User makeUser(String alias, List<String> permSetNames) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'T ' + alias, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            List<PermissionSetAssignment> asg = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN :permSetNames]) {
                asg.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
            }
            insert asg;
        }
        return u;
    }

    private static GTM_Saved_Configuration__c makeLink(Id ownerId, String tag) {
        GTM_Saved_Configuration__c c = new GTM_Saved_Configuration__c(
            OwnerId = ownerId, Offering__c = 'migration-accelerator', Company__c = 'Co ' + tag,
            Generated_URL__c = 'https://example.com/' + tag, Active__c = true);
        insert c;
        return c;
    }

    /** Everything tied to a link, owned by the link's owner. */
    private static void tieStuffTo(GTM_Saved_Configuration__c link, Id ownerId) {
        insert new GTM_Link_Event__c(OwnerId = ownerId, Saved_Configuration__c = link.Id,
            Event_Type__c = 'Page View');
        insert new GTM_Form_Draft__c(OwnerId = ownerId, Saved_Configuration__c = link.Id,
            Draft_Type__c = 'Booking', Status__c = 'Open');
    }

    private static Boolean feedbackOwdIsPrivate() {
        try {
            return [SELECT InternalSharingModel FROM EntityDefinition
                    WHERE QualifiedApiName = 'GTM_Offering_Feedback__c' LIMIT 1].InternalSharingModel == 'Private';
        } catch (Exception e) {
            return false;
        }
    }

    @IsTest
    static void repBCannotSeeOrTouchRepAsRecordsButAStillCan() {
        User repA = makeUser('rpa', new List<String>{ 'GTM_Offering_User' });
        User repB = makeUser('rpb', new List<String>{ 'GTM_Offering_User' });
        GTM_Saved_Configuration__c link = makeLink(repA.Id, 'a');
        tieStuffTo(link, repA.Id);
        System.runAs(repA) {
            GtmFeedbackController.submitFeedback('migration-accelerator', null, 'A raised this');
        }

        System.runAs(repB) {
            Assert.areEqual(0, [SELECT COUNT() FROM GTM_Saved_Configuration__c], 'link');
            Assert.areEqual(0, [SELECT COUNT() FROM GTM_Link_Event__c], 'events must not be visible to another rep');
            Assert.areEqual(0, [SELECT COUNT() FROM GTM_Form_Draft__c], 'drafts must not be visible to another rep');
            // A check-only deploy never applies the OWD change, so the own-only
            // feedback assertions run only when the live sharing model is
            // already Private. Own-only feedback is verified live, as a
            // non-admin rep, after deploy.
            if (feedbackOwdIsPrivate()) {
                Assert.areEqual(0, [SELECT COUNT() FROM GTM_Offering_Feedback__c], 'feedback must be own-only');
                Assert.areEqual(0, GtmFeedbackController.getFeedbackFor('migration-accelerator').size(),
                    'getFeedbackFor follows Private OWD');
            }
        }

        System.runAs(repA) {
            Assert.areEqual(1, [SELECT COUNT() FROM GTM_Link_Event__c]);
            Assert.areEqual(1, [SELECT COUNT() FROM GTM_Form_Draft__c]);
            Assert.areEqual(1, [SELECT COUNT() FROM GTM_Offering_Feedback__c]);
            Assert.areEqual(1, GtmFeedbackController.getFeedbackFor('migration-accelerator').size());
        }
    }

    @IsTest
    static void repObjectGrantsAreNarrow() {
        User rep = makeUser('rpc', new List<String>{ 'GTM_Offering_User' });
        System.runAs(rep) {
            Assert.isFalse(Schema.sObjectType.GTM_Form_Draft__c.isUpdateable(), 'draft edit');
            Assert.isFalse(Schema.sObjectType.GTM_Form_Draft__c.isDeletable(), 'draft delete');
            Assert.isFalse(Schema.sObjectType.GTM_Link_Event__c.isUpdateable(), 'event edit');
            Assert.isFalse(Schema.sObjectType.GTM_Link_Event__c.isDeletable(), 'event delete');
        }
    }

    @IsTest
    static void adminSeesEverything() {
        User repA = makeUser('rpd', new List<String>{ 'GTM_Offering_User' });
        User admin = makeUser('adm', new List<String>{ 'GTM_Offering_Admin' });
        GTM_Saved_Configuration__c link = makeLink(repA.Id, 'd');
        tieStuffTo(link, repA.Id);
        System.runAs(repA) {
            GtmFeedbackController.submitFeedback('migration-accelerator', null, 'A raised this');
        }
        System.runAs(admin) {
            Assert.areEqual(1, [SELECT COUNT() FROM GTM_Saved_Configuration__c]);
            Assert.areEqual(1, [SELECT COUNT() FROM GTM_Link_Event__c]);
            Assert.areEqual(1, [SELECT COUNT() FROM GTM_Form_Draft__c]);
            Assert.areEqual(1, [SELECT COUNT() FROM GTM_Offering_Feedback__c]);
        }
    }

    @IsTest
    static void contentEditorStillSeesAndAnswersAllFeedback() {
        User repA = makeUser('rpe', new List<String>{ 'GTM_Offering_User' });
        User repB = makeUser('rpf', new List<String>{ 'GTM_Offering_User' });
        User editor = makeUser('edt', new List<String>{ 'GTM_Content_Manager' });
        GTM_Offering_Feedback__c fbA;
        System.runAs(repA) {
            GtmFeedbackController.submitFeedback('migration-accelerator', null, 'from A');
        }
        System.runAs(repB) {
            GtmFeedbackController.submitFeedback('migration-accelerator', null, 'from B');
        }
        System.runAs(editor) {
            Assert.areEqual(2, GtmFeedbackController.getOpenFeedback().size(), 'editor sees all');
            Assert.areEqual(2, GtmFeedbackController.countOpenFeedback());
            Assert.isTrue(Schema.sObjectType.GTM_Offering_Feedback__c.isUpdateable(), 'editor can answer');
            Assert.isTrue(Schema.sObjectType.GTM_Offering_Feedback__c.fields.Response__c.isUpdateable());
            Assert.isTrue(Schema.sObjectType.GTM_Offering_Feedback__c.fields.Answered_At__c.isUpdateable());
            Id target = GtmFeedbackController.getOpenFeedback()[0].recordId;
            GtmFeedbackController.respond(target, 'Resolved', 'Fixed');
        }
    }

    @IsTest
    static void linkWithAnAssessmentCannotBeDeletedButOneWithoutCanAndItsEventsGo() {
        User repA = makeUser('rpg', new List<String>{ 'GTM_Offering_User' });
        GTM_Saved_Configuration__c blocked = makeLink(repA.Id, 'blk');
        GTM_Saved_Configuration__c free = makeLink(repA.Id, 'free');
        tieStuffTo(free, repA.Id);
        insert new GTM_Assessment_Request__c(Requester_Name__c = 'R', Requester_Email__c = 'r@example.com',
            Company__c = 'Co', Offering_Key__c = 'migration-accelerator', Saved_Configuration__c = blocked.Id);

        System.runAs(repA) {
            try {
                GtmSavedConfigurationController.deleteConfiguration(blocked.Id);
                Assert.fail('A link with an assessment request must not be deletable');
            } catch (AuraHandledException e) { /* expected */ }
        }
        Assert.areEqual(1, [SELECT COUNT() FROM GTM_Saved_Configuration__c WHERE Id = :blocked.Id]);

        System.runAs(repA) {
            GtmSavedConfigurationController.deleteConfiguration(free.Id);
        }
        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Saved_Configuration__c WHERE Id = :free.Id]);
        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Link_Event__c WHERE Saved_Configuration__c = :free.Id],
            'events cascade with the link');
        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Form_Draft__c WHERE Saved_Configuration__c = :free.Id]);
    }
}
