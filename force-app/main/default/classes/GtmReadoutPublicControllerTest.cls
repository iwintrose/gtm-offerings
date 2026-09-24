@isTest
private class GtmReadoutPublicControllerTest {

    private static Id seedReadout(String status, String token) {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c   = 'Alex Rivera',
            Requester_Email__c  = 'alex.rivera@example.com',
            Company__c          = 'Northwind Retail',
            // 18 of 32, not the 42 this fixture used to carry: there are 8
            // scored dimensions worth 4 points each (GtmAssessmentScoring), so
            // 42 was unreachable on the real scale and on the 40-point one it
            // seems to have been written against.
            Assessment_Score__c = 18,
            Assessment_Tier__c  = 'Prep Required'
        );
        insert req;

        GTM_Readout__c readout = new GTM_Readout__c(
            Assessment_Request__c = req.Id,
            Offering_Key__c       = 'migration-accelerator',
            Status__c             = status,
            Draft_Content__c      = '<p>Draft</p>',
            Approved_Content__c   = status == 'Draft' ? null : '<p>Approved copy</p>',
            Public_Link_Token__c  = token
        );
        insert readout;
        return readout.Id;
    }

    /**
     * Moves a readout to Approved the way production does -- the
     * GTM_Readout_Approval process's final-approval field update writes exactly
     * this field, and GtmReadoutApprovalSync does the rest. There is no
     * GtmReadoutController.approveReadout any more.
     */
    private static void approve(Id readoutId) {
        update new GTM_Readout__c(Id = readoutId, Status__c = 'Approved');
    }

    @isTest
    static void publishedTokenReturnsContent() {
        seedReadout('Published', 'valid-token-123');

        Test.startTest();
        GtmReadoutPublicController.PublishedReadout result =
            GtmReadoutPublicController.getPublishedReadout('valid-token-123');
        Test.stopTest();

        Assert.isNotNull(result, 'A valid published token should resolve');
        Assert.areEqual('<p>Approved copy</p>', result.content);
        Assert.areEqual('migration-accelerator', result.offeringKey);
        Assert.areEqual(
            UserInfo.getName(),
            result.repName,
            'Rep contact info should come from the readout owner (the running/test user)'
        );
    }

    @isTest
    static void draftReadoutsTokenReturnsNothing() {
        // A Draft readout has no real Public_Link_Token__c yet in practice,
        // but even if one were somehow set, the query must not resolve it --
        // Status__c = 'Published' is required in the WHERE clause itself.
        seedReadout('Draft', 'draft-token-456');

        Test.startTest();
        GtmReadoutPublicController.PublishedReadout result =
            GtmReadoutPublicController.getPublishedReadout('draft-token-456');
        Test.stopTest();

        Assert.isNull(result, 'A Draft readout must never resolve via the public token path');
    }

    @isTest
    static void approvedReadoutsTokenReturnsNothing() {
        seedReadout('Approved', 'approved-token-789');

        Test.startTest();
        GtmReadoutPublicController.PublishedReadout result =
            GtmReadoutPublicController.getPublishedReadout('approved-token-789');
        Test.stopTest();

        Assert.isNull(result, 'An Approved-but-not-yet-published readout must not resolve');
    }

    @isTest
    static void unknownTokenReturnsNothingSameAsUnpublished() {
        seedReadout('Published', 'valid-token-abc');

        Test.startTest();
        GtmReadoutPublicController.PublishedReadout forUnpublished =
            GtmReadoutPublicController.getPublishedReadout('approved-token-does-not-exist');
        GtmReadoutPublicController.PublishedReadout forNeverIssued =
            GtmReadoutPublicController.getPublishedReadout('completely-made-up-token');
        Test.stopTest();

        // Both cases return null identically -- there is no way for a caller
        // to distinguish "exists but not published" from "never existed".
        Assert.isNull(forUnpublished);
        Assert.isNull(forNeverIssued);
    }

    @isTest
    static void blankOrNullTokenReturnsNothing() {
        Assert.isNull(GtmReadoutPublicController.getPublishedReadout(null));
        Assert.isNull(GtmReadoutPublicController.getPublishedReadout(''));
        Assert.isNull(GtmReadoutPublicController.getPublishedReadout('   '));
    }

    @isTest
    static void unpublishedTokenNoLongerResolvesAfterUnpublish() {
        Id readoutId = seedReadout('Published', 'about-to-be-revoked');
        Assert.isNotNull(
            GtmReadoutPublicController.getPublishedReadout('about-to-be-revoked'),
            'Sanity check: token resolves while published'
        );

        GtmReadoutController.unpublishReadout(readoutId);

        Test.startTest();
        GtmReadoutPublicController.PublishedReadout result =
            GtmReadoutPublicController.getPublishedReadout('about-to-be-revoked');
        Test.stopTest();

        Assert.isNull(result, 'A revoked token must stop resolving instantly');
    }

    @isTest
    static void revokedTokenStaysDeadAfterRepublish() {
        // Unpublish -> republish is the case a plain "revoked token returns
        // null" test misses: if publish ever reused the old token, an
        // already-distributed link would come back to life.
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c  = 'Alex Rivera',
            Requester_Email__c = 'alex.rivera@example.com',
            Company__c         = 'Northwind Retail'
        );
        insert req;

        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);
        GtmReadoutController.publishReadout(readoutId);
        String firstToken = [SELECT Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutId].Public_Link_Token__c;

        GtmReadoutController.unpublishReadout(readoutId);
        GtmReadoutController.publishReadout(readoutId);
        String secondToken = [SELECT Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutId].Public_Link_Token__c;

        Test.startTest();
        GtmReadoutPublicController.PublishedReadout viaOld =
            GtmReadoutPublicController.getPublishedReadout(firstToken);
        GtmReadoutPublicController.PublishedReadout viaNew =
            GtmReadoutPublicController.getPublishedReadout(secondToken);
        Test.stopTest();

        Assert.areNotEqual(firstToken, secondToken, 'Republishing must mint a new token');
        Assert.isNull(viaOld, 'The revoked token must not resolve again after republishing');
        Assert.isNotNull(viaNew, 'The freshly minted token must resolve');
    }

    @isTest
    static void publishedResponseNeverCarriesDraftContent() {
        // Approved_Content__c is the published snapshot. Draft_Content__c can
        // legitimately hold newer, unapproved rep notes -- it must never reach
        // an unauthenticated caller, including via a future refactor that
        // widens the SELECT.
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c  = 'Alex Rivera',
            Requester_Email__c = 'alex.rivera@example.com',
            Company__c         = 'Northwind Retail'
        );
        insert req;

        GTM_Readout__c readout = new GTM_Readout__c(
            Assessment_Request__c = req.Id,
            Offering_Key__c       = 'migration-accelerator',
            Status__c             = 'Published',
            Draft_Content__c      = '<p>INTERNAL-ONLY-NOTE</p>',
            Approved_Content__c   = '<p>Approved copy</p>',
            Public_Link_Token__c  = 'draft-leak-check-token'
        );
        insert readout;

        Test.startTest();
        GtmReadoutPublicController.PublishedReadout result =
            GtmReadoutPublicController.getPublishedReadout('draft-leak-check-token');
        Test.stopTest();

        Assert.isNotNull(result);
        Assert.areEqual('<p>Approved copy</p>', result.content);
        Assert.isFalse(
            JSON.serialize(result).contains('INTERNAL-ONLY-NOTE'),
            'No part of the guest response may carry the working draft'
        );
    }

    // ------------------------------------------------------ queue-owned readouts
    //
    // Orphan readouts -- a direct booking with no Engagement Link and no
    // Opportunity -- are now owned by the GTM_Readout_Triage queue rather than
    // not being created at all. A queue is not a person, so there is no rep
    // name, email or phone to show the prospect, and there must be no
    // invented stand-in either.

    /**
     * The deployed queue if the org has it (it is source metadata, so normally
     * yes), otherwise one created here. Looking first avoids
     * DUPLICATE_DEVELOPER_NAME; the runAs is because Group is a setup object
     * and inserting it alongside a regular sObject is a MIXED_DML_OPERATION.
     */
    private static Id ensureTriageQueue() {
        List<Group> existing = [
            SELECT Id FROM Group
            WHERE DeveloperName = 'GTM_Readout_Triage' AND Type = 'Queue'
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }
        Group q = new Group(
            Name          = 'Unassigned Readouts',
            DeveloperName = 'GTM_Readout_Triage',
            Type          = 'Queue'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert q;
            insert new QueueSobject(QueueId = q.Id, SobjectType = 'GTM_Readout__c');
        }
        return q.Id;
    }

    @isTest
    static void aQueueOwnedReadoutRendersWithNoContactBlockAtAll() {
        Id queueId = ensureTriageQueue();

        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c  = 'Alex Rivera',
            Requester_Email__c = 'alex.rivera@example.com',
            Company__c         = 'Northwind Retail'
        );
        insert req;

        GTM_Readout__c readout = new GTM_Readout__c(
            OwnerId               = queueId,
            Assessment_Request__c = req.Id,
            Offering_Key__c       = 'migration-accelerator',
            Status__c             = 'Published',
            Approved_Content__c   = '<p>Approved copy</p>',
            Public_Link_Token__c  = 'queue-owned-token'
        );
        insert readout;
        Assert.areEqual(
            queueId,
            [SELECT OwnerId FROM GTM_Readout__c WHERE Id = :readout.Id].OwnerId,
            'Sanity check: the readout really is queue-owned'
        );

        Test.startTest();
        GtmReadoutPublicController.PublishedReadout result =
            GtmReadoutPublicController.getPublishedReadout('queue-owned-token');
        Test.stopTest();

        // The content still publishes -- an unclaimed readout is not a broken
        // one, and the prospect should still see what was approved.
        Assert.isNotNull(result, 'A queue-owned readout still resolves and renders its content');
        Assert.areEqual('<p>Approved copy</p>', result.content);

        // But there is no person to name, so there is no contact block. Not a
        // placeholder, not the queue's own name or email, not the approver, not
        // the running user -- absent.
        Assert.isNull(result.repName, 'A Queue is not a rep -- no name may be shown');
        Assert.isNull(result.repEmail, 'A Queue is not a rep -- no email may be shown');
        Assert.isNull(result.repPhone, 'A Queue is not a rep -- no phone may be shown');

        // Stated against the whole serialized payload as well, so a future
        // field added to PublishedReadout cannot quietly reintroduce it.
        String payload = JSON.serialize(result);
        Assert.isFalse(
            payload.containsIgnoreCase('Unassigned Readouts'),
            'The queue name must never reach the prospect: ' + payload
        );
        Assert.isFalse(
            payload.contains(String.valueOf(queueId)),
            'Nor the queue Id: ' + payload
        );
    }

    @isTest
    static void claimingAQueueOwnedReadoutTurnsTheContactBlockOn() {
        // The other half of the queue design: no extra code makes this work,
        // because applyRepContact reads OwnerId. A rep claiming the record out
        // of the queue becomes the owner, and the prospect-facing contact block
        // starts working from that moment. Asserted rather than assumed.
        Id queueId = ensureTriageQueue();

        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c  = 'Alex Rivera',
            Requester_Email__c = 'alex.rivera@example.com',
            Company__c         = 'Northwind Retail'
        );
        insert req;

        GTM_Readout__c readout = new GTM_Readout__c(
            OwnerId               = queueId,
            Assessment_Request__c = req.Id,
            Offering_Key__c       = 'migration-accelerator',
            Status__c             = 'Published',
            Approved_Content__c   = '<p>Approved copy</p>',
            Public_Link_Token__c  = 'claimed-readout-token'
        );
        insert readout;
        Assert.isNull(
            GtmReadoutPublicController.getPublishedReadout('claimed-readout-token').repName,
            'Sanity check: no contact while it sits in the queue'
        );

        // The claim: exactly what a rep does from the record page.
        readout.OwnerId = UserInfo.getUserId();
        update readout;

        Test.startTest();
        GtmReadoutPublicController.PublishedReadout result =
            GtmReadoutPublicController.getPublishedReadout('claimed-readout-token');
        Test.stopTest();

        Assert.areEqual(
            UserInfo.getName(),
            result.repName,
            'Once a rep owns it, the contact block is the owning rep'
        );
    }

    @isTest
    static void aTokenRevokedByReturnToDraftStopsResolving() {
        // returnToDraft refuses a Published readout outright, so the supported
        // route back to editing is unpublish (which revokes the token) then
        // revert. What matters to this class is the end state: the link a
        // prospect already has must be dead, and indistinguishable from a
        // token that never existed.
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c  = 'Alex Rivera',
            Requester_Email__c = 'alex.rivera@example.com',
            Company__c         = 'Northwind Retail'
        );
        insert req;

        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);
        GtmReadoutController.publishReadout(readoutId);
        String liveToken = [SELECT Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutId].Public_Link_Token__c;
        Assert.isNotNull(
            GtmReadoutPublicController.getPublishedReadout(liveToken),
            'Sanity check: the token resolves while published'
        );

        GtmReadoutController.unpublishReadout(readoutId);
        GtmReadoutController.returnToDraft(readoutId);

        Test.startTest();
        GtmReadoutPublicController.PublishedReadout viaOldToken =
            GtmReadoutPublicController.getPublishedReadout(liveToken);
        Test.stopTest();

        Assert.areEqual(
            'Draft',
            [SELECT Status__c FROM GTM_Readout__c WHERE Id = :readoutId].Status__c,
            'Sanity check: it really did revert'
        );
        Assert.isNull(viaOldToken, 'The old link must be dead once the readout is back in draft');
        Assert.isNull(
            GtmReadoutPublicController.getPublishedReadout('never-issued-at-all'),
            'And must be indistinguishable from a token that never existed'
        );
    }
}
