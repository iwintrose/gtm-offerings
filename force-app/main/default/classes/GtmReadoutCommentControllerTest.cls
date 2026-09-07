/**
 * The recipient comment write path. The assertions that matter most here are
 * the negative ones: every server-state failure has to be indistinguishable
 * from every other, because the alternative is a comment box an attacker can
 * use to ask "is a readout being prepared for this deal".
 */
@isTest
private class GtmReadoutCommentControllerTest {

    private static final String TOKEN = 'valid-token-for-comments';

    /**
     * A published readout with a review case on it -- the shape production
     * produces, since GtmReadoutController.Generator files the case at
     * generation time and publishReadout mints the token.
     */
    private static Id seedPublishedReadoutWithCase(String token) {
        Id readoutId = seedReadout('Published', token);
        insert new Case(
            Readout__c = readoutId,
            Subject    = 'Review and approve readout — Northwind Retail'
        );
        return readoutId;
    }

    private static Id seedReadout(String status, String token) {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c   = 'Alex Rivera',
            Requester_Email__c  = 'alex.rivera@example.com',
            Company__c          = 'Northwind Retail',
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

    private static List<CaseComment> commentsOn(Id readoutId) {
        Set<Id> caseIds = new Set<Id>();
        for (Case c : [SELECT Id FROM Case WHERE Readout__c = :readoutId]) {
            caseIds.add(c.Id);
        }
        return [SELECT CommentBody, IsPublished, ParentId FROM CaseComment WHERE ParentId IN :caseIds];
    }

    // ------------------------------------------------------------- sections

    @isTest
    static void theSectionListIsTheOneTheServerValidatesAgainst() {
        Test.startTest();
        List<String> sections = GtmReadoutCommentController.getCommentSections();
        Test.stopTest();

        Assert.areEqual(7, sections.size(), 'The readout has seven sections');
        Assert.isTrue(sections.contains('Verdict'));
        Assert.isTrue(sections.contains('Scorecard'));
        Assert.isTrue(sections.contains('Capability gaps'));
        Assert.isTrue(sections.contains('Next steps'));
    }

    // -------------------------------------------------------- the happy path

    @isTest
    static void aValidTokenAppendsACommentToTheReviewCase() {
        Id readoutId = seedPublishedReadoutWithCase(TOKEN);

        Test.startTest();
        GtmReadoutCommentController.CommentResult result =
            GtmReadoutCommentController.submitComment(TOKEN, 'Scorecard', 'The integration score looks generous.');
        Test.stopTest();

        Assert.isTrue(result.accepted, 'A published token with a review case should accept a comment');
        List<CaseComment> comments = commentsOn(readoutId);
        Assert.areEqual(1, comments.size());
        Assert.isTrue(
            comments[0].CommentBody.contains('The integration score looks generous.'),
            'The comment text should be stored: ' + comments[0].CommentBody
        );
        Assert.isTrue(
            comments[0].CommentBody.startsWith('[Recipient comment — Scorecard]'),
            'The section travels as a prefix, which is what makes it readable in the related list: ' +
            comments[0].CommentBody
        );
        Assert.areEqual(
            false,
            comments[0].IsPublished,
            'The thread is internal -- the recipient posts to it and never reads it back'
        );
    }

    @isTest
    static void theSectionIsStoredInOurSpellingNotTheCallers() {
        Id readoutId = seedPublishedReadoutWithCase(TOKEN);

        Test.startTest();
        GtmReadoutCommentController.submitComment(TOKEN, 'cApAbIlItY GaPs', 'Fine by me.');
        Test.stopTest();

        List<CaseComment> comments = commentsOn(readoutId);
        Assert.areEqual(1, comments.size());
        Assert.isTrue(
            comments[0].CommentBody.startsWith('[Recipient comment — Capability gaps]'),
            'Only one of seven known strings may ever be stored: ' + comments[0].CommentBody
        );
    }

    // ------------------------------------------------------ no existence leak

    @isTest
    static void everyServerStateFailureLooksIdentical() {
        // The property the whole class is built around. A caller must not be
        // able to tell a token that never existed from one belonging to a
        // readout still in draft, from one that was revoked.
        seedReadout('Draft', 'draft-token');
        Id approvedId = seedReadout('Approved', 'approved-token');
        insert new Case(Readout__c = approvedId, Subject = 'Review');
        Id publishedNoCase = seedReadout('Published', 'published-but-no-case');

        Test.startTest();
        GtmReadoutCommentController.CommentResult neverExisted =
            GtmReadoutCommentController.submitComment('no-such-token', 'Verdict', 'Hello.');
        GtmReadoutCommentController.CommentResult stillDraft =
            GtmReadoutCommentController.submitComment('draft-token', 'Verdict', 'Hello.');
        GtmReadoutCommentController.CommentResult approvedNotPublished =
            GtmReadoutCommentController.submitComment('approved-token', 'Verdict', 'Hello.');
        GtmReadoutCommentController.CommentResult noThread =
            GtmReadoutCommentController.submitComment('published-but-no-case', 'Verdict', 'Hello.');
        GtmReadoutCommentController.CommentResult blankToken =
            GtmReadoutCommentController.submitComment('', 'Verdict', 'Hello.');
        Test.stopTest();

        for (GtmReadoutCommentController.CommentResult result : new List<GtmReadoutCommentController.CommentResult>{
            neverExisted, stillDraft, approvedNotPublished, noThread, blankToken
        }) {
            Assert.isFalse(result.accepted, 'None of these may be accepted');
            Assert.areEqual(
                neverExisted.message,
                result.message,
                'Every server-state refusal must be byte-identical to every other'
            );
        }
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM CaseComment],
            'Nothing may be written on any of those paths'
        );
        Assert.areEqual(0, commentsOn(publishedNoCase).size());
    }

    @isTest
    static void anUnpublishedReadoutStopsAcceptingCommentsImmediately() {
        Id readoutId = seedPublishedReadoutWithCase(TOKEN);
        GtmReadoutController.unpublishReadout(readoutId);

        Test.startTest();
        GtmReadoutCommentController.CommentResult result =
            GtmReadoutCommentController.submitComment(TOKEN, 'Verdict', 'Still there?');
        Test.stopTest();

        Assert.isFalse(result.accepted, 'A revoked token must stop accepting writes the moment it is revoked');
        Assert.areEqual(0, commentsOn(readoutId).size());
    }

    // ---------------------------------------------------- input-shape refusals
    //
    // These are the only refusals allowed to be specific, because they are
    // decided from the caller's own arguments before the token is looked at.

    @isTest
    static void anUnknownSectionIsRefusedWithoutTouchingAnything() {
        Id readoutId = seedPublishedReadoutWithCase(TOKEN);

        Test.startTest();
        GtmReadoutCommentController.CommentResult result =
            GtmReadoutCommentController.submitComment(TOKEN, 'Pricing', 'Not a section.');
        Test.stopTest();

        Assert.isFalse(result.accepted);
        Assert.areEqual(0, commentsOn(readoutId).size());
    }

    @isTest
    static void anEmptyCommentIsRefused() {
        Id readoutId = seedPublishedReadoutWithCase(TOKEN);

        Test.startTest();
        GtmReadoutCommentController.CommentResult blank =
            GtmReadoutCommentController.submitComment(TOKEN, 'Verdict', '   ');
        GtmReadoutCommentController.CommentResult markupOnly =
            GtmReadoutCommentController.submitComment(TOKEN, 'Verdict', '<b></b>');
        Test.stopTest();

        Assert.isFalse(blank.accepted);
        Assert.isFalse(markupOnly.accepted, 'Markup that sanitises down to nothing is nothing');
        Assert.areEqual(0, commentsOn(readoutId).size());
    }

    @isTest
    static void anOverlongCommentIsRefusedRatherThanTruncatedSilently() {
        Id readoutId = seedPublishedReadoutWithCase(TOKEN);
        String tooLong = 'x'.repeat(3001);

        Test.startTest();
        GtmReadoutCommentController.CommentResult result =
            GtmReadoutCommentController.submitComment(TOKEN, 'Findings', tooLong);
        Test.stopTest();

        Assert.isFalse(result.accepted);
        Assert.isTrue(
            result.message.contains('long'),
            'This one is safe to be specific about -- it is decided from the input alone'
        );
        Assert.areEqual(0, commentsOn(readoutId).size());
    }

    // ------------------------------------------------------------ sanitising

    @isTest
    static void htmlIsStrippedFromRecipientText() {
        // It is rendered back to reps inside Salesforce, and turns up in report
        // exports and email templates, so it is treated as hostile.
        Id readoutId = seedPublishedReadoutWithCase(TOKEN);

        Test.startTest();
        GtmReadoutCommentController.submitComment(
            TOKEN, 'Context', 'Nice <script>alert(1)</script> readout <img src=x onerror=y>'
        );
        Test.stopTest();

        List<CaseComment> comments = commentsOn(readoutId);
        Assert.areEqual(1, comments.size());
        Assert.isFalse(
            comments[0].CommentBody.contains('<script'),
            'No markup may survive: ' + comments[0].CommentBody
        );
        Assert.isFalse(comments[0].CommentBody.contains('onerror'));
        Assert.isTrue(comments[0].CommentBody.contains('Nice'));
    }

    @isTest
    static void aLeadingFormulaCharacterIsDefused() {
        // A case exported to CSV and opened in a spreadsheet is a real path for
        // this text, and =/+/@ start a formula there.
        Id readoutId = seedPublishedReadoutWithCase(TOKEN);

        Test.startTest();
        GtmReadoutCommentController.submitComment(TOKEN, 'The path', '=HYPERLINK("http://evil","click")');
        Test.stopTest();

        List<CaseComment> comments = commentsOn(readoutId);
        Assert.areEqual(1, comments.size());
        Assert.isTrue(
            comments[0].CommentBody.contains('\'=HYPERLINK'),
            'The formula should be quoted out: ' + comments[0].CommentBody
        );
    }

    // ---------------------------------------------------------- rate limiting

    @isTest
    static void theThreadIsThrottledAndSaysNothingAboutIt() {
        Id readoutId = seedPublishedReadoutWithCase(TOKEN);

        Test.startTest();
        for (Integer i = 0; i < 5; i++) {
            GtmReadoutCommentController.CommentResult ok =
                GtmReadoutCommentController.submitComment(TOKEN, 'Verdict', 'Comment number ' + i);
            Assert.isTrue(ok.accepted, 'The first five in the window are accepted');
        }
        GtmReadoutCommentController.CommentResult throttled =
            GtmReadoutCommentController.submitComment(TOKEN, 'Verdict', 'One too many');
        GtmReadoutCommentController.CommentResult unknownToken =
            GtmReadoutCommentController.submitComment('no-such-token', 'Verdict', 'Hello.');
        Test.stopTest();

        Assert.isFalse(throttled.accepted, 'The sixth in the window is refused');
        Assert.areEqual(
            unknownToken.message,
            throttled.message,
            'A throttle message is only reachable with a valid token, so it must not be distinguishable'
        );
        Assert.areEqual(5, commentsOn(readoutId).size());
    }

    // -------------------------------------------------- the oldest case wins

    @isTest
    static void commentsLandOnTheOriginalReviewCaseNotALaterOne() {
        // A rep can raise more cases against a readout from its Cases related
        // list. The recipient's thread must not migrate to whichever is newest,
        // or the conversation would split in two.
        Id readoutId = seedPublishedReadoutWithCase(TOKEN);
        Id firstCaseId = [SELECT Id FROM Case WHERE Readout__c = :readoutId LIMIT 1].Id;
        insert new Case(Readout__c = readoutId, Subject = 'Something else entirely');

        Test.startTest();
        GtmReadoutCommentController.submitComment(TOKEN, 'Next steps', 'When can we start?');
        Test.stopTest();

        List<CaseComment> comments = commentsOn(readoutId);
        Assert.areEqual(1, comments.size());
        Assert.areEqual(
            firstCaseId,
            comments[0].ParentId,
            'The thread stays on the review case the rep has been reading'
        );
    }
}
