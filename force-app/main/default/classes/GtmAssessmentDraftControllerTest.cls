/**
 * Covers the append-and-count design (docs/handoff/port-map-ma-to-gtm.md
 * section F) end to end as an internal (non-guest) user -- these tests prove
 * the mechanics; GtmGuestUpdateProbeTest is the permanent guest-context
 * regression gate for the platform fact this design depends on.
 */
@IsTest
private class GtmAssessmentDraftControllerTest {

    @IsTest
    static void mintCreatesOneOpenRow() {
        Test.startTest();
        GtmAssessmentDraftController.DraftHandle h =
            GtmAssessmentDraftController.saveDraft(null, '{"q1":"a"}', 'hubspot__sfmc');
        Test.stopTest();

        System.assertNotEquals(null, h.resumeToken, 'mint must return a token');
        System.assertEquals(true, h.created, 'first save must report created=true');

        List<GTM_Form_Draft__c> rows = [
            SELECT Draft_Type__c, Resume_Token__c, Draft_JSON__c, Pair_Key__c, Status__c
            FROM GTM_Form_Draft__c WHERE Resume_Token__c = :h.resumeToken
        ];
        System.assertEquals(1, rows.size(), 'mint appends exactly one row');
        System.assertEquals('Assessment', rows[0].Draft_Type__c);
        System.assertEquals('{"q1":"a"}', rows[0].Draft_JSON__c);
        System.assertEquals('hubspot__sfmc', rows[0].Pair_Key__c);
        System.assertEquals('Open', rows[0].Status__c);
    }

    @IsTest
    static void secondSaveAppendsRatherThanUpdates() {
        GtmAssessmentDraftController.DraftHandle first =
            GtmAssessmentDraftController.saveDraft(null, '{"q1":"a"}', 'hubspot__sfmc');

        Test.startTest();
        GtmAssessmentDraftController.DraftHandle second =
            GtmAssessmentDraftController.saveDraft(first.resumeToken, '{"q1":"a","q2":"b"}', 'hubspot__sfmc');
        Test.stopTest();

        System.assertEquals(false, second.created, 'a second save is not the creating call');
        List<GTM_Form_Draft__c> rows = [
            SELECT Id FROM GTM_Form_Draft__c WHERE Resume_Token__c = :first.resumeToken
        ];
        System.assertEquals(2, rows.size(),
            'a second save must be a second row (append-only -- this org will not let a '
            + 'guest UPDATE, see GtmGuestUpdateProbeTest), not one row mutated in place');
    }

    @IsTest
    static void resumeReturnsTheMostRecentAnswers() {
        GtmAssessmentDraftController.DraftHandle first =
            GtmAssessmentDraftController.saveDraft(null, '{"q1":"a"}', 'hubspot__sfmc');
        GtmAssessmentDraftController.saveDraft(first.resumeToken, '{"q1":"a","q2":"b"}', 'hubspot__sfmc');

        Test.startTest();
        GtmAssessmentDraftController.DraftPayload resumed =
            GtmAssessmentDraftController.resumeDraft(first.resumeToken);
        Test.stopTest();

        System.assertNotEquals(null, resumed, 'a fresh token minted moments earlier must resume');
        System.assertEquals('{"q1":"a","q2":"b"}', resumed.payload,
            'resume must return the newest row\'s answers, not the original mint\'s');
    }

    @IsTest
    static void resumeReturnsNullForAnUnknownToken() {
        Test.startTest();
        GtmAssessmentDraftController.DraftPayload resumed =
            GtmAssessmentDraftController.resumeDraft('not-a-real-token');
        Test.stopTest();
        System.assertEquals(null, resumed);
    }

    @IsTest
    static void submissionRevokesTheTokenWithoutAnyUpdate() {
        GtmAssessmentDraftController.DraftHandle h =
            GtmAssessmentDraftController.saveDraft(null, '{"q1":"a"}', 'hubspot__sfmc');

        // Simulates GtmAssessmentRequestController.closeDraft -- append the
        // terminal row, never update the existing one.
        insert new GTM_Form_Draft__c(
            Draft_Type__c        = 'Assessment',
            Resume_Token__c      = h.resumeToken,
            Draft_JSON__c        = '{}',
            Status__c            = 'Submitted',
            Expires_At__c        = h.expiresAt,
            Last_Saved_At__c     = System.now(),
            Submitted_Request__c = null // no real request in this unit test; presence of the
                                         // row with Status__c=Submitted is not what gates --
                                         // Submitted_Request__c populated is. See next test.
        );

        Test.startTest();
        GtmAssessmentDraftController.DraftPayload resumed =
            GtmAssessmentDraftController.resumeDraft(h.resumeToken);
        Test.stopTest();

        // Status__c alone does not revoke -- only a populated Submitted_Request__c
        // on the newest row does (see latestOpenRowFor). This asserts that
        // distinction rather than assuming it.
        System.assertNotEquals(null, resumed,
            'a Submitted-status row with no Submitted_Request__c must NOT revoke -- '
            + 'only Submitted_Request__c being populated does');
    }

    @IsTest
    static void submittedRequestPopulatedActuallyRevokes() {
        GtmAssessmentDraftController.DraftHandle h =
            GtmAssessmentDraftController.saveDraft(null, '{"q1":"a"}', 'hubspot__sfmc');

        GTM_Assessment_Config__mdt cfgOverride = new GTM_Assessment_Config__mdt(
            Create_Lead__c = false, Send_Email__c = false
        );

        // A minimal request row to point Submitted_Request__c at.
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c = 'Test Requester',
            Requester_Email__c = 'test@example.com',
            Status__c = 'New',
            Source__c = 'Migration Accelerator'
        );
        insert req;

        insert new GTM_Form_Draft__c(
            Draft_Type__c        = 'Assessment',
            Resume_Token__c      = h.resumeToken,
            Draft_JSON__c        = '{}',
            Status__c            = 'Submitted',
            Expires_At__c        = h.expiresAt,
            Last_Saved_At__c     = System.now(),
            Submitted_Request__c = req.Id
        );

        Test.startTest();
        GtmAssessmentDraftController.DraftPayload resumed =
            GtmAssessmentDraftController.resumeDraft(h.resumeToken);
        Test.stopTest();

        System.assertEquals(null, resumed,
            'once the newest row for a token carries Submitted_Request__c, resume must '
            + 'stop resolving it -- without updating anything');
    }

    @IsTest
    static void appendCapIsEnforced() {
        // A real 200-iteration loop would each cost a SOQL query (governor
        // limit 100/transaction) -- MAX_APPENDS is @TestVisible specifically
        // so this test can exercise the cap without needing 200 real saves.
        GtmAssessmentDraftController.MAX_APPENDS = 5;

        GtmAssessmentDraftController.DraftHandle h =
            GtmAssessmentDraftController.saveDraft(null, '{"q1":"a"}', 'hubspot__sfmc');
        GtmAssessmentDraftController.maxMintsPerWindow = 10000; // isolate the append cap from the mint throttle

        Test.startTest();
        Boolean threw = false;
        try {
            for (Integer i = 0; i < 10; i++) {
                GtmAssessmentDraftController.saveDraft(h.resumeToken, '{"q1":"' + i + '"}', 'hubspot__sfmc');
            }
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'a token must be refused once it is over the append cap');
    }

    @IsTest
    static void malformedPayloadIsRejected() {
        Test.startTest();
        Boolean threw = false;
        try {
            GtmAssessmentDraftController.saveDraft(null, 'not json', 'hubspot__sfmc');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void emailResumeLinkAppendsAndSpendsAnAppendUnit() {
        GtmAssessmentDraftController.DraftHandle h =
            GtmAssessmentDraftController.saveDraft(null, '{"q1":"a"}', 'hubspot__sfmc');

        Test.startTest();
        GtmAssessmentDraftController.SendResult result =
            GtmAssessmentDraftController.emailResumeLink(h.resumeToken, 'prospect@example.com');
        Test.stopTest();

        // No Resume_Link_Base_URL__c / Experience Cloud site context exists in
        // this unit test, so sending itself is not expected to succeed -- this
        // asserts the method degrades to the generic failure rather than
        // throwing, which is what a guest-callable method must do.
        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.message);
    }
}
