/**
 * The loop that makes this feedback rather than a suggestion box: a note goes
 * in, a reply comes back, and the person who raised it can see where it stands.
 */
@IsTest
private class GtmFeedbackControllerTest {

    @IsTest
    static void aNoteIsRaisedAgainstAnOfferingAndCarriesWhoLeftIt() {
        Test.startTest();
        GtmFeedbackController.FeedbackItem it = GtmFeedbackController.submitFeedback(
            'migration-accelerator', 'story', 'The asset count reads as invented.');
        Test.stopTest();

        Assert.isNotNull(it.recordId);
        Assert.areEqual('New', it.status);
        Assert.areEqual('migration-accelerator', it.offeringKey);
        Assert.areEqual('story', it.templateType);
        Assert.isTrue(it.isMine, 'The person looking should see it as theirs');
        Assert.isNull(it.response, 'Nothing has been said back yet');
    }

    @IsTest
    static void emptyFeedbackIsRefusedRatherThanStored() {
        Test.startTest();
        try {
            GtmFeedbackController.submitFeedback('migration-accelerator', null, '   ');
            Assert.fail('Blank feedback should be refused');
        } catch (AuraHandledException e) { /* expected */ }
        try {
            GtmFeedbackController.submitFeedback('', null, 'Something');
            Assert.fail('Feedback about nothing should be refused');
        } catch (AuraHandledException e) { /* expected */ }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Offering_Feedback__c]);
    }

    /**
     * "Needs more information" is the state the loop exists for: the useful
     * answer to some feedback is a question back.
     */
    @IsTest
    static void askingSomethingBackKeepsItOpenAndStampsTheReply() {
        GtmFeedbackController.FeedbackItem raised = GtmFeedbackController.submitFeedback(
            'migration-accelerator', null, 'This claim will not survive a CFO.');

        Test.startTest();
        GtmFeedbackController.FeedbackItem asked = GtmFeedbackController.respond(
            raised.recordId, 'Needs More Info', 'Which claim, and which CFO said so?');
        Test.stopTest();

        Assert.areEqual('Needs More Info', asked.status);
        Assert.isNotNull(asked.answeredAt, 'A reply stamps when it was written');
        Assert.areEqual(1, GtmFeedbackController.countOpenFeedback(),
            'A question back is still open work');
    }

    @IsTest
    static void resolvingClosesItButKeepsWhatWasSaid() {
        GtmFeedbackController.FeedbackItem raised = GtmFeedbackController.submitFeedback(
            'migration-accelerator', null, 'The proof number is stale.');
        GtmFeedbackController.respond(raised.recordId, 'In Progress', 'Chasing the source.');

        Test.startTest();
        GtmFeedbackController.FeedbackItem done =
            GtmFeedbackController.respond(raised.recordId, 'Resolved', null);
        Test.stopTest();

        Assert.areEqual('Resolved', done.status);
        Assert.areEqual('Chasing the source.', done.response,
            'Changing the status must not wipe the reply');
        Assert.areEqual(0, GtmFeedbackController.countOpenFeedback());
        // Still visible to whoever raised it — that is how they learn it landed.
        Assert.areEqual(1, GtmFeedbackController.getFeedbackFor('migration-accelerator').size());
    }

    @IsTest
    static void theQueueHoldsOnlyOpenWorkAndTheOfferingViewHoldsEverything() {
        GtmFeedbackController.FeedbackItem a = GtmFeedbackController.submitFeedback('migration-accelerator', null, 'One.');
        GtmFeedbackController.submitFeedback('migration-accelerator', null, 'Two.');
        GtmFeedbackController.submitFeedback('other-offering', null, 'Three.');
        GtmFeedbackController.respond(a.recordId, 'Resolved', 'Fixed.');

        Test.startTest();
        List<GtmFeedbackController.FeedbackItem> queue = GtmFeedbackController.getOpenFeedback();
        List<GtmFeedbackController.FeedbackItem> mine  = GtmFeedbackController.getFeedbackFor('migration-accelerator');
        Test.stopTest();

        Assert.areEqual(2, queue.size(), 'Resolved work leaves the queue');
        Assert.areEqual(2, mine.size(), 'The offering keeps its whole history, resolved included');
        Assert.areEqual(0, GtmFeedbackController.getFeedbackFor('').size());
    }

    @IsTest
    static void aReplyToNothingIsRefused() {
        Test.startTest();
        try {
            GtmFeedbackController.respond('', 'Resolved', 'x');
            Assert.fail('A reply needs a record');
        } catch (AuraHandledException e) { /* expected */ }
        Test.stopTest();
    }
}
