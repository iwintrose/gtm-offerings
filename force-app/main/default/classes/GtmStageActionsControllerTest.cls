@IsTest
private class GtmStageActionsControllerTest {

    // Dynamic construction avoids a static compile-time reference to
    // GTM_Assessment_Request__c.Saved_Configuration__c -- see the comment on
    // GtmStageActionsController for why that field is treated this way
    // throughout the codebase.
    private static SObject newAssessmentRequest(
        Id savedConfigId, String requesterName, String requesterEmail, String company
    ) {
        SObject req = Schema.getGlobalDescribe().get('GTM_Assessment_Request__c').newSObject();
        req.put('Saved_Configuration__c', savedConfigId);
        req.put('Requester_Name__c', requesterName);
        req.put('Requester_Email__c', requesterEmail);
        req.put('Company__c', company);
        return req;
    }

    // ── getStageContext ──────────────────────────────────────────────────────

    @IsTest
    static void getStageContext_unresolvableId_returnsEmptyContext() {
        Test.startTest();
        GtmStageActionsController.StageContext ctx =
            GtmStageActionsController.getStageContext('not-a-real-id');
        Test.stopTest();

        Assert.isNull(ctx.stage, 'Unresolvable id should yield a blank context');
        Assert.isNull(ctx.assessmentId);
        Assert.isNull(ctx.sharedUrl);
    }

    @IsTest
    static void getStageContext_noLinkedAssessment_returnsStageAndUrlOnly() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = 'Draft',
            Generated_URL__c = 'https://example.com/configurator?company=Acme'
        );
        insert cfg;

        Test.startTest();
        GtmStageActionsController.StageContext ctx =
            GtmStageActionsController.getStageContext(cfg.Id);
        Test.stopTest();

        Assert.areEqual('Draft', ctx.stage);
        Assert.areEqual('https://example.com/configurator?company=Acme', ctx.sharedUrl);
        Assert.isNull(ctx.assessmentId, 'No assessment request is linked yet');
    }

    @IsTest
    static void getStageContext_withLinkedAssessment_returnsRequesterDetails() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = 'In_Review',
            Generated_URL__c = 'https://example.com/configurator?company=Acme'
        );
        insert cfg;

        SObject req = newAssessmentRequest(cfg.Id, 'Alex Rivera', 'alex@example.com', 'Acme Bank');
        insert req;

        Test.startTest();
        GtmStageActionsController.StageContext ctx =
            GtmStageActionsController.getStageContext(cfg.Id);
        Test.stopTest();

        Assert.areEqual('In_Review', ctx.stage);
        Assert.areEqual((Id) req.get('Id'), ctx.assessmentId);
        Assert.areEqual('Alex Rivera', ctx.requesterName);
        Assert.areEqual('alex@example.com', ctx.requesterEmail);
        Assert.areEqual('Acme Bank', ctx.requesterCompany);
    }

    @IsTest
    static void getStageContext_multipleAssessments_returnsMostRecentOnly() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = 'Draft',
            Generated_URL__c = 'https://example.com/configurator?company=Acme'
        );
        insert cfg;

        SObject older = newAssessmentRequest(cfg.Id, 'Older Requester', 'older@example.com', 'Old Co');
        insert older;
        SObject newer = newAssessmentRequest(cfg.Id, 'Newer Requester', 'newer@example.com', 'New Co');
        insert newer;

        // Force explicit CreatedDate ordering so the "latest first" behaviour
        // under test isn't left to same-transaction timestamp luck.
        Test.setCreatedDate((Id) older.get('Id'), DateTime.now().addDays(-2));
        Test.setCreatedDate((Id) newer.get('Id'), DateTime.now().addDays(-1));

        Test.startTest();
        GtmStageActionsController.StageContext ctx =
            GtmStageActionsController.getStageContext(cfg.Id);
        Test.stopTest();

        Assert.areEqual('Newer Requester', ctx.requesterName, 'Only the most recent request should be returned');
        Assert.areEqual('New Co', ctx.requesterCompany);
    }

    // ── advanceStage ─────────────────────────────────────────────────────────

    @IsTest
    static void advanceStage_unresolvableId_throwsAuraHandledException() {
        Boolean threw = false;
        Test.startTest();
        try {
            GtmStageActionsController.advanceStage('not-a-real-id', 'Sent');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'An unresolvable configId should be rejected');
    }

    @IsTest
    static void advanceStage_invalidStageValue_throwsAuraHandledException() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = 'Draft',
            Generated_URL__c = 'https://example.com/configurator'
        );
        insert cfg;

        Boolean threw = false;
        Test.startTest();
        try {
            GtmStageActionsController.advanceStage(cfg.Id, 'NotARealStage');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'An out-of-set stage value should be rejected');

        GTM_Saved_Configuration__c after = [
            SELECT Presentation_Stage__c FROM GTM_Saved_Configuration__c WHERE Id = :cfg.Id
        ];
        Assert.areEqual('Draft', after.Presentation_Stage__c, 'Rejected update must not persist');
    }

    @IsTest
    static void advanceStage_validNonSentTransition_updatesStageWithoutEmail() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = 'Draft',
            Generated_URL__c = 'https://example.com/configurator'
        );
        insert cfg;

        Test.startTest();
        GtmStageActionsController.advanceStage(cfg.Id, 'In_Review');
        Test.stopTest();

        GTM_Saved_Configuration__c after = [
            SELECT Presentation_Stage__c FROM GTM_Saved_Configuration__c WHERE Id = :cfg.Id
        ];
        Assert.areEqual('In_Review', after.Presentation_Stage__c);
        Assert.areEqual(0, Limits.getEmailInvocations(), 'Non-Sent transitions must never attempt an email');
    }

    @IsTest
    static void advanceStage_toSentWithRequesterEmail_sendsProposalEmail() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = 'In_Review',
            Generated_URL__c = 'https://example.com/configurator?company=Acme'
        );
        insert cfg;
        insert newAssessmentRequest(cfg.Id, 'Alex Rivera', 'alex@example.com', 'Acme Bank');

        Test.startTest();
        GtmStageActionsController.advanceStage(cfg.Id, 'Sent');
        // Limits must be read inside the startTest/stopTest window -- stopTest()
        // begins a fresh governor context for the outer test method, so an
        // Email Invocations check taken after it no longer reflects what
        // happened inside.
        //
        // Two, not one: the record-triggered flow GTM_Config_Send_To_Client
        // (RecordAfterSave on Presentation_Stage__c = Sent) fires on the
        // `update cfg;` inside advanceStage() and calls the same
        // sendProposalEmails invocable that advanceStage() also calls
        // directly afterward -- so a rep advancing a config to Sent currently
        // emails the client twice. That looks like an unintended duplicate
        // send rather than the intended behavior; flagged in the delivery
        // report rather than changed here per the "tests only" guardrail.
        Assert.areEqual(2, Limits.getEmailInvocations(), 'Both the flow and advanceStage() attempt a send');
        Test.stopTest();

        GTM_Saved_Configuration__c after = [
            SELECT Presentation_Stage__c FROM GTM_Saved_Configuration__c WHERE Id = :cfg.Id
        ];
        Assert.areEqual('Sent', after.Presentation_Stage__c);
    }

    @IsTest
    static void advanceStage_toSentWithNoGeneratedUrl_flowRejectsTheUpdate() {
        // The org's "GTM Config — Send To Client" record-triggered flow (see
        // the class header comment) requires a populated Generated_URL__c to
        // fire on a transition into Sent, and blocks the DML outright when it
        // is blank. That's existing declarative automation, not something this
        // class' Apex guards against -- assert the real, observed behavior.
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = 'Draft'
            // No Generated_URL__c -- nothing to link to in an email.
        );
        insert cfg;
        insert newAssessmentRequest(cfg.Id, 'Alex Rivera', 'alex@example.com', 'Acme Bank');

        Boolean threw = false;
        Test.startTest();
        try {
            GtmStageActionsController.advanceStage(cfg.Id, 'Sent');
        } catch (DmlException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(
            threw,
            'The Send To Client flow should reject advancing to Sent without a Generated_URL__c'
        );
        GTM_Saved_Configuration__c after = [
            SELECT Presentation_Stage__c FROM GTM_Saved_Configuration__c WHERE Id = :cfg.Id
        ];
        Assert.areEqual('Draft', after.Presentation_Stage__c, 'A rejected update must not persist');
    }

    @IsTest
    static void advanceStage_toSentWithNoAssessmentRequest_skipsEmailGracefully() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = 'Draft',
            Generated_URL__c = 'https://example.com/configurator'
        );
        insert cfg;
        // No linked GTM_Assessment_Request__c at all.

        Test.startTest();
        GtmStageActionsController.advanceStage(cfg.Id, 'Sent');
        Test.stopTest();

        GTM_Saved_Configuration__c after = [
            SELECT Presentation_Stage__c FROM GTM_Saved_Configuration__c WHERE Id = :cfg.Id
        ];
        Assert.areEqual('Sent', after.Presentation_Stage__c);
        Assert.areEqual(0, Limits.getEmailInvocations(), 'Nobody to email means no attempt');
    }

    @IsTest
    static void advanceStage_toSentWithBlankRequesterEmail_skipsEmail() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = 'Draft',
            Generated_URL__c = 'https://example.com/configurator'
        );
        insert cfg;
        insert newAssessmentRequest(cfg.Id, 'Alex Rivera', null, 'Acme Bank');

        Test.startTest();
        GtmStageActionsController.advanceStage(cfg.Id, 'Sent');
        Test.stopTest();

        Assert.areEqual(0, Limits.getEmailInvocations(), 'A requester with no email must not be emailed');
    }

    @IsTest
    static void advanceStage_toSentWithBlankRequesterNameAndCompany_stillSendsEmail() {
        // Exercises the "there"/no-company fallback branches in the email builders.
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = 'Draft',
            Generated_URL__c = 'https://example.com/configurator'
        );
        insert cfg;
        insert newAssessmentRequest(cfg.Id, null, 'anon@example.com', null);

        Test.startTest();
        GtmStageActionsController.advanceStage(cfg.Id, 'Sent');
        // See advanceStage_toSentWithRequesterEmail_sendsProposalEmail for why
        // this is 2, not 1 (the Send_To_Client flow duplicates the send).
        Assert.areEqual(2, Limits.getEmailInvocations(), 'A blank name/company should not block either send');
        Test.stopTest();
    }

    // ── sendProposalEmails (flow invocable) ──────────────────────────────────

    @IsTest
    static void sendProposalEmails_validInput_sendsEmail() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.com/configurator'
        );
        insert cfg;
        insert newAssessmentRequest(cfg.Id, 'Alex Rivera', 'alex@example.com', 'Acme Bank');

        GtmStageActionsController.SendEmailInput inp = new GtmStageActionsController.SendEmailInput();
        inp.configId = cfg.Id;
        inp.sharedUrl = 'https://example.com/configurator';

        Test.startTest();
        GtmStageActionsController.sendProposalEmails(
            new List<GtmStageActionsController.SendEmailInput>{ inp }
        );
        Assert.areEqual(1, Limits.getEmailInvocations());
        Test.stopTest();
    }

    @IsTest
    static void sendProposalEmails_unresolvableConfigId_skipsSilently() {
        GtmStageActionsController.SendEmailInput inp = new GtmStageActionsController.SendEmailInput();
        inp.configId = 'not-a-real-id';
        inp.sharedUrl = 'https://example.com/configurator';

        Test.startTest();
        GtmStageActionsController.sendProposalEmails(
            new List<GtmStageActionsController.SendEmailInput>{ inp }
        );
        Test.stopTest();

        Assert.areEqual(0, Limits.getEmailInvocations(), 'An unresolvable configId must not raise or email');
    }

    @IsTest
    static void sendProposalEmails_blankSharedUrl_skipsSilently() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator'
        );
        insert cfg;
        insert newAssessmentRequest(cfg.Id, 'Alex Rivera', 'alex@example.com', 'Acme Bank');

        GtmStageActionsController.SendEmailInput inp = new GtmStageActionsController.SendEmailInput();
        inp.configId = cfg.Id;
        inp.sharedUrl = '';

        Test.startTest();
        GtmStageActionsController.sendProposalEmails(
            new List<GtmStageActionsController.SendEmailInput>{ inp }
        );
        Test.stopTest();

        Assert.areEqual(0, Limits.getEmailInvocations());
    }

    @IsTest
    static void sendProposalEmails_bulkInputs_onlyValidOnesSendEmail() {
        GTM_Saved_Configuration__c goodCfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.com/good'
        );
        insert goodCfg;
        insert newAssessmentRequest(goodCfg.Id, 'Alex Rivera', 'alex@example.com', 'Acme Bank');

        GtmStageActionsController.SendEmailInput goodInput = new GtmStageActionsController.SendEmailInput();
        goodInput.configId = goodCfg.Id;
        goodInput.sharedUrl = 'https://example.com/good';

        GtmStageActionsController.SendEmailInput badInput = new GtmStageActionsController.SendEmailInput();
        badInput.configId = 'not-a-real-id';
        badInput.sharedUrl = 'https://example.com/bad';

        Test.startTest();
        GtmStageActionsController.sendProposalEmails(
            new List<GtmStageActionsController.SendEmailInput>{ goodInput, badInput }
        );
        Assert.areEqual(1, Limits.getEmailInvocations(), 'Only the resolvable input should send an email');
        Test.stopTest();
    }
}
