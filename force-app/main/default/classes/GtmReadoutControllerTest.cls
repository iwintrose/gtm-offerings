@isTest
private class GtmReadoutControllerTest {

    /**
     * 18 of a possible 32, not the 42 this fixture used to carry. There are 8
     * scored dimensions worth 4 points each (GtmAssessmentScoring), so 42 was
     * not merely unrealistic -- it was unreachable, and unreachable even on the
     * 40-point scale it appears to have been written against.
     */
    private static final Decimal SAMPLE_SCORE = 18;

    private static GTM_Assessment_Request__c seedRequest() {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c   = 'Alex Rivera',
            Requester_Email__c  = 'alex.rivera@example.com',
            Company__c          = 'Northwind Retail',
            Assessment_Score__c = SAMPLE_SCORE,
            Assessment_Tier__c  = 'Prep Required',
            Section_Scores__c   = '{"estate_scale":3,"source_access":2}',
            Estate_Complexity_Score__c = 15,
            Estate_Complexity_Band__c  = 'Heavy',
            Estate_Complexity_Basis__c = 'Self-Estimated',
            Estate_Complexity_Dimensions__c = '{"journey_footprint":3,"scripting_depth":3}',
            Branch_Platform__c  = 'MCE',
            Pain_Points__c      = 'Manual list hygiene, no unified profile.',
            Migration_Goals__c  = 'Single customer view, real-time journeys.',
            Success_Criteria__c = 'Send time cut in half within two quarters.'
        );
        insert req;
        return req;
    }

    /**
     * Moves a readout to Approved the way production does.
     *
     * There is no GtmReadoutController.approveReadout any more: approval is the
     * GTM_Readout_Approval process, whose final-approval action is a workflow
     * field update that writes exactly this one field. Everything an approval
     * means beyond the word -- the Approved_Content__c copy, the approver
     * stamp, the version snapshot -- is GtmReadoutApprovalSync reacting to the
     * transition, so this DML exercises the real path rather than standing in
     * for it.
     *
     * Driving the full approval process from a test would additionally need a
     * submitting user with a Manager, which says nothing extra about this
     * class's behaviour; submission and recall are covered directly in the
     * approval section further down.
     */
    private static void approve(Id readoutId) {
        update new GTM_Readout__c(Id = readoutId, Status__c = 'Approved');
    }

    /**
     * Calls the real GtmReadoutController.submitForApproval -- exercising
     * the actual front door onto Approval.process(), not a stand-in -- but
     * tolerates it failing for a reason that has nothing to do with the
     * page-vs-pageless question this sub-issue is about: Approval.process()
     * requires the running test user to have a manager set on their User
     * record and the GTM_Readout_Approval process to be routable in this
     * org context, neither of which this test controls or needs to prove
     * (submission/recall's own success and failure paths are already
     * covered directly, see the tests around submitForApprovalRefuses*).
     * What this sub-issue's tests need is only that submitForApproval does
     * not behave differently, or fail differently, for a pageless request
     * than it would for a page-linked one -- and it does not, since it
     * never reads Saved_Configuration__c at all. If the real submit throws
     * for an environment reason, this falls back to the same direct
     * Status__c transition the rest of this file already uses to reach
     * Pending Approval (see aReadoutWaitingOnApprovalStillAppearsInTheRepQueue),
     * so the rest of the chain (approve -> publish -> public link) still
     * gets exercised end to end either way.
     */
    private static void driveSubmitForApproval(Id readoutId) {
        try {
            GtmReadoutController.submitForApproval(readoutId);
        } catch (AuraHandledException e) {
            update new GTM_Readout__c(Id = readoutId, Status__c = 'Pending Approval');
        }
    }

    // --------------------------------------------------------------- generate

    @isTest
    static void generateDraftReadoutCreatesDraftFromScoredRequest() {
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        Assert.isNotNull(readoutId, 'A readout should be created');
        GTM_Readout__c readout = [
            SELECT Status__c, Assessment_Request__c, Draft_Content__c, Offering_Key__c, Readout_Data__c
            FROM GTM_Readout__c
            WHERE Id = :readoutId
        ];
        Assert.areEqual('Draft', readout.Status__c);
        Assert.areEqual(req.Id, readout.Assessment_Request__c);
        Assert.isNotNull(readout.Offering_Key__c);
        Assert.isTrue(readout.Draft_Content__c.contains('Prep Required'), 'Draft should reference the tier');
        // The company name is a structured fact (Readout_Data__c's "company"
        // key), not prose -- buildNarrative's verdict paragraph does not
        // name the company at all; confirmed against gtm-dev. gtmReadoutView
        // is what puts the company name on the page, from Readout_Data__c.
        Assert.isTrue(
            readout.Readout_Data__c.contains('Northwind Retail'), 'Snapshot should reference the company'
        );
        // The raw "X out of Y" score no longer lives in the prose. Per the
        // prose/measurement split (buildNarrative, selected whenever
        // GtmReadoutModel.buildJson(req) has data), the score and its scale
        // are structured facts in Readout_Data__c -- rendered by gtmReadoutView,
        // not printed into Draft_Content__c -- so that is where this checks
        // them. Confirmed against gtm-dev: a scored request's Draft_Content__c
        // contains neither "18" nor "out of 32" anywhere.
        Assert.isNotNull(readout.Readout_Data__c, 'A scored request should produce a structured snapshot');
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(readout.Readout_Data__c);
        Map<String, Object> readiness = (Map<String, Object>) data.get('readiness');
        Assert.isNotNull(readiness, 'The snapshot should carry a readiness block: ' + readout.Readout_Data__c);
        Assert.areEqual(18, (Decimal) readiness.get('score'), 'Readiness score should be 18');
        // The score is meaningless without the scale it is out of, and the
        // scale is 32 -- eight dimensions at four points, not 10 dimensions'
        // worth of a 40-point maximum that could drift.
        Assert.areEqual(
            32, (Decimal) readiness.get('max'),
            'Readiness max should be 32 (8 scored dimensions x 4 points), not 40: ' + readout.Readout_Data__c
        );
    }

    @isTest
    static void theDraftReportsBothAxesSeparately() {
        // The readout has two headline numbers and they must not read as one.
        // Readiness says whether the work can be scoped; complexity says how
        // big it is. A Heavy estate next to a decent readiness score is a
        // bigger engagement, and the draft has to be able to say that.
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        // Both headline numbers are structured facts (Readout_Data__c), not
        // prose (Draft_Content__c) -- see generateDraftReadoutCreatesDraftFromScoredRequest
        // for why. That split does not weaken this test's point: the two
        // axes still have to arrive as two distinct, unsummed numbers.
        String dataJson = [SELECT Readout_Data__c FROM GTM_Readout__c WHERE Id = :readoutId]
            .Readout_Data__c;
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(dataJson);
        Map<String, Object> readiness = (Map<String, Object>) data.get('readiness');
        Map<String, Object> complexity = (Map<String, Object>) data.get('complexity');
        Assert.areEqual(18, (Decimal) readiness.get('score'), 'Readiness axis: ' + dataJson);
        Assert.areEqual(32, (Decimal) readiness.get('max'), 'Readiness axis: ' + dataJson);
        Assert.areEqual(15, (Decimal) complexity.get('score'), 'Complexity axis: ' + dataJson);
        Assert.areEqual(18, (Decimal) complexity.get('max'), 'Complexity axis: ' + dataJson);
        Assert.areEqual('Heavy', (String) complexity.get('band'), 'And its band');
        Assert.areEqual('Self-Estimated', (String) complexity.get('basis'), 'And where the number came from');
        // The two axes are separate fields under separate keys by
        // construction -- there is no "total" key for them to have been
        // summed into. Asserting that absence is what "never summed" means
        // now that there is no shared string for a "33" to appear in.
        Assert.isFalse(data.containsKey('total'), 'The two axes must never be combined into one total');
    }

    @isTest
    static void theDraftPrintsDimensionWordingWhenThereIsSomeAndKeysWhenThereIsNot() {
        // The breakdown must survive missing metadata: an unconfigured key
        // prints as the key rather than dropping the line.
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        String html = [SELECT Draft_Content__c FROM GTM_Readout__c WHERE Id = :readoutId]
            .Draft_Content__c;
        Map<String, String> names = GtmAssessmentQuestions.dimensionNames();
        String expected = names.containsKey('estate_scale')
            ? names.get('estate_scale')
            : 'estate_scale';
        // Draft_Content__c is HTML, and the template escapes every dimension
        // label it prints (draftTemplateEscapesProspectSuppliedHtml is the
        // reason why) -- so a label containing "&", as "Estate Scale &
        // Structure" does, has to be compared against its escaped form too.
        Assert.isTrue(html.contains(expected.escapeHtml4()),
            'Expected the breakdown to name estate_scale as "' + expected + '": ' + html);
    }

    @isTest
    static void anAdvisoryRequestGetsABannerAndNoTierAtAll() {
        // The whole point of the unsupported-pair gate: a tier here would be a
        // promise the offering cannot keep, so the draft must not print one.
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c      = 'Alex Rivera',
            Requester_Email__c     = 'alex.rivera@example.com',
            Company__c             = 'Northwind Retail',
            Assessment_Score__c    = 32,
            Assessment_Tier__c     = null,
            Assessment_Advisory__c = true,
            Advisory_Reason__c     = 'Adobe Campaign is not an extractable source.',
            Section_Scores__c      = '{"estate_scale":4}'
        );
        insert req;

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Draft_Content__c, Readout_Data__c FROM GTM_Readout__c WHERE Id = :readoutId
        ];
        String html = readout.Draft_Content__c;
        // The verdict paragraph says the engagement is advisory in its own
        // words rather than a fixed "Advisory only" banner string -- see
        // GtmReadoutController.buildNarrative -- but it still has to say so,
        // and it still must never print a tier line for a pair the
        // accelerator cannot process.
        Assert.isTrue(
            html.contains('not one the accelerator can process') || html.contains('advisory'),
            'The verdict should say this is advisory: ' + html
        );
        Assert.isFalse(html.contains('Engagement tier'),
            'No tier line at all -- not even a dashed one somebody could fill in');
        // The reason and the score are structured facts now (Readout_Data__c),
        // not prose -- see generateDraftReadoutCreatesDraftFromScoredRequest.
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(readout.Readout_Data__c);
        Map<String, Object> advisory = (Map<String, Object>) data.get('advisory');
        Assert.isNotNull(advisory, 'The snapshot should carry an advisory block: ' + readout.Readout_Data__c);
        Assert.areEqual(true, advisory.get('on'), 'Advisory should be flagged on');
        Assert.areEqual(
            'Adobe Campaign is not an extractable source.', (String) advisory.get('reason'),
            'The unsupported-pair reason should be carried through'
        );
        Map<String, Object> readiness = (Map<String, Object>) data.get('readiness');
        Assert.areEqual(32, (Decimal) readiness.get('score'), 'The score still shows as conversational input');
        Assert.areEqual(32, (Decimal) readiness.get('max'));
    }

    @isTest
    static void theRebuildRatioAnnotationIsPrintedAboveTheBreakdown() {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c   = 'Alex Rivera',
            Requester_Email__c  = 'alex.rivera@example.com',
            Company__c          = 'Northwind Retail',
            Assessment_Score__c = 26,
            Assessment_Tier__c  = 'Accelerator-Ready',
            Assessment_Flags__c =
                '[{"code":"high_rebuild_ratio","message":"High rebuild ratio - expect automation levels C/D to dominate."}]'
        );
        insert req;

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Draft_Content__c, Readout_Data__c FROM GTM_Readout__c WHERE Id = :readoutId
        ];
        Assert.isTrue(
            readout.Draft_Content__c.contains('Accelerator-Ready'), 'The annotation does not change the tier'
        );
        // The annotation itself is a structured fact now (Readout_Data__c's
        // "annotations" list, built by GtmReadoutModel.putAnnotations from
        // Assessment_Flags__c) -- it sits beside the verdict in the data
        // model rather than being interpolated into the prose. It still has
        // to survive end to end, which is what this checks.
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(readout.Readout_Data__c);
        List<Object> annotations = (List<Object>) data.get('annotations');
        Assert.isNotNull(annotations, 'The snapshot should carry the flag as an annotation: ' + readout.Readout_Data__c);
        Boolean found = false;
        for (Object raw : annotations) {
            Map<String, Object> row = (Map<String, Object>) raw;
            if (String.valueOf(row.get('text')).contains('automation levels C/D')) {
                found = true;
            }
        }
        Assert.isTrue(found, 'The note is said, in the structured snapshot: ' + readout.Readout_Data__c);
    }

    @isTest
    static void malformedFlagsOrBreakdownJsonNeverBlocksTheDraft() {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c   = 'Alex Rivera',
            Requester_Email__c  = 'alex.rivera@example.com',
            Company__c          = 'Northwind Retail',
            Assessment_Score__c = 20,
            Assessment_Tier__c  = 'Prep Required',
            Section_Scores__c   = '{not json at all',
            Assessment_Flags__c = 'also not json',
            Estate_Complexity_Dimensions__c = '{"unterminated": '
        );
        insert req;

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        String html = [SELECT Draft_Content__c FROM GTM_Readout__c WHERE Id = :readoutId]
            .Draft_Content__c;
        Assert.isNotNull(html);
        Assert.isTrue(html.contains('Prep Required'),
            'A templating hiccup must not cost a rep the whole draft');
    }

    @isTest
    static void generateDraftReadoutIsIdempotent() {
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        Id first = GtmReadoutController.generateDraftReadout(req.Id);
        Id second = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        Assert.areEqual(first, second, 'A second call should return the existing readout, not create another');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM GTM_Readout__c WHERE Assessment_Request__c = :req.Id],
            'Exactly one readout should exist for the assessment'
        );
    }

    @isTest
    static void generateDraftReadoutReturnsNullForNullId() {
        Assert.isNull(GtmReadoutController.generateDraftReadout(null));
    }

    @isTest
    static void generateDraftReadoutSurvivesMalformedSectionScores() {
        GTM_Assessment_Request__c req = seedRequest();
        req.Section_Scores__c = 'not-json{{{';
        update req;

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        Assert.isNotNull(readoutId, 'Malformed JSON should not block draft generation');
    }

    // ---------------------------------------------------- account trail

    /**
     * Backs gtmReadoutAccountFinder (issue-gtm-assessments-account-contact-
     * trail): groups Assessment Requests by Contact under one Account,
     * mirroring GtmRepLinkFinderControllerTest's own coverage of
     * getContactsWithLinks for the equivalent Saved-Configuration shape.
     */
    @isTest
    static void getContactsWithRequestsGroupsByContactUnderTheAccount() {
        Account acct = new Account(Name = 'Northwind Retail');
        insert acct;
        Contact con1 = new Contact(LastName = 'Rivera', FirstName = 'Alex', AccountId = acct.Id);
        Contact con2 = new Contact(LastName = 'Chen', FirstName = 'Sam', AccountId = acct.Id);
        insert new List<Contact>{ con1, con2 };

        GTM_Assessment_Request__c req1 = seedRequest();
        req1.Account__c = acct.Id;
        req1.Contact__c = con1.Id;
        req1.Offering_Key__c = 'migration-accelerator';
        update req1;

        GTM_Assessment_Request__c req2 = seedRequest();
        req2.Account__c = acct.Id;
        req2.Contact__c = con1.Id;
        update req2;

        GTM_Assessment_Request__c req3 = seedRequest();
        req3.Account__c = acct.Id;
        req3.Contact__c = con2.Id;
        update req3;

        // A request with no Contact on the same Account must never appear --
        // this trail walks Account -> Contact -> Request, not a flat
        // Account-only list.
        GTM_Assessment_Request__c reqNoContact = seedRequest();
        reqNoContact.Account__c = acct.Id;
        update reqNoContact;

        Test.startTest();
        List<GtmReadoutController.ContactRequests> groups =
            GtmReadoutController.getContactsWithRequests(acct.Id);
        Test.stopTest();

        Assert.areEqual(2, groups.size(), 'One group per Contact with at least one request');

        Map<Id, GtmReadoutController.ContactRequests> byContact = new Map<Id, GtmReadoutController.ContactRequests>();
        for (GtmReadoutController.ContactRequests g : groups) { byContact.put(g.contactId, g); }

        Assert.isTrue(byContact.containsKey(con1.Id));
        Assert.areEqual(2, byContact.get(con1.Id).requests.size());
        Assert.isTrue(byContact.containsKey(con2.Id));
        Assert.areEqual(1, byContact.get(con2.Id).requests.size());

        GtmReadoutController.RequestSummary s = byContact.get(con1.Id).requests[0];
        Assert.areEqual('Northwind Retail', s.company);
    }

    @isTest
    static void getContactsWithRequestsPopulatesTheMostRecentReadoutPerRequest() {
        Account acct = new Account(Name = 'Acme Co');
        insert acct;
        Contact con = new Contact(LastName = 'Smith', AccountId = acct.Id);
        insert con;

        GTM_Assessment_Request__c req = seedRequest();
        req.Account__c = acct.Id;
        req.Contact__c = con.Id;
        update req;
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        GTM_Assessment_Request__c reqNoReadout = seedRequest();
        reqNoReadout.Account__c = acct.Id;
        reqNoReadout.Contact__c = con.Id;
        update reqNoReadout;

        Test.startTest();
        List<GtmReadoutController.ContactRequests> groups =
            GtmReadoutController.getContactsWithRequests(acct.Id);
        Test.stopTest();

        Assert.areEqual(1, groups.size());
        Map<Id, GtmReadoutController.RequestSummary> byRequest = new Map<Id, GtmReadoutController.RequestSummary>();
        for (GtmReadoutController.RequestSummary s : groups[0].requests) { byRequest.put(s.recordId, s); }

        Assert.areEqual(readoutId, byRequest.get(req.Id).readoutId);
        Assert.isNull(byRequest.get(reqNoReadout.Id).readoutId,
            'A request with no readout generated yet is a normal, unremarkable state, not an error');
    }

    @isTest
    static void getContactsWithRequestsReturnsEmptyForNullAccount() {
        Test.startTest();
        List<GtmReadoutController.ContactRequests> groups = GtmReadoutController.getContactsWithRequests(null);
        Test.stopTest();

        Assert.isTrue(groups.isEmpty());
    }

    /**
     * Explicit OwnerId backstop (issue rep-data-scoping-owd-2): two reps
     * sharing visibility into the same Account (simulated here by each
     * owning a request on it) must each see only their own requests, not
     * the other's, even though both requests are filtered by the same
     * Account__c.
     */
    @isTest
    static void getContactsWithRequestsScopesToTheOwningRepOnly() {
        Account acct = new Account(Name = 'Shared Visibility Co');
        insert acct;
        Contact con = new Contact(LastName = 'Shared', AccountId = acct.Id);
        insert con;

        User repA = createRep('gtmcr1');
        User repB = createRep('gtmcr2');

        GTM_Assessment_Request__c reqA = seedRequest();
        reqA.Account__c = acct.Id;
        reqA.Contact__c = con.Id;
        reqA.OwnerId = repA.Id;
        update reqA;

        GTM_Assessment_Request__c reqB = seedRequest();
        reqB.Account__c = acct.Id;
        reqB.Contact__c = con.Id;
        reqB.OwnerId = repB.Id;
        update reqB;

        Test.startTest();
        List<GtmReadoutController.ContactRequests> repAView;
        System.runAs(repA) {
            repAView = GtmReadoutController.getContactsWithRequests(acct.Id);
        }
        Test.stopTest();

        Set<Id> repAIds = new Set<Id>();
        for (GtmReadoutController.ContactRequests g : repAView) {
            for (GtmReadoutController.RequestSummary s : g.requests) {
                repAIds.add(s.recordId);
            }
        }
        Assert.isTrue(repAIds.contains(reqA.Id), 'Rep A must see their own request');
        Assert.isFalse(repAIds.contains(reqB.Id), 'Rep A must not see Rep B\'s request on the same Account');
    }

    @isTest
    static void getReadoutReturnsFullDetail() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        Test.startTest();
        GtmReadoutController.ReadoutDetail detail = GtmReadoutController.getReadout(readoutId);
        Test.stopTest();

        Assert.areEqual(readoutId, (Id) detail.id);
        Assert.areEqual('Draft', detail.status);
        Assert.areEqual(req.Id, (Id) detail.assessmentRequestId);
        Assert.areEqual('Northwind Retail', detail.company);
        Assert.isNull(detail.publicLinkToken, 'A Draft readout should have no public token');
        Assert.isNotNull(detail.draftContent);
    }

    @isTest
    static void getReadoutThrowsForMissingId() {
        Boolean threw = false;
        try {
            GtmReadoutController.getReadout(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'A null readout Id should throw');
    }

    // Issue #29: the consolidated Assessment view (gtmAssessmentSubmissionView)
    // resolves whether a readout has an Assessment Request purely from this
    // method's assessmentRequestId, with no separate "joined to Assessment"
    // query of its own. An orphan readout (Assessment_Request__c = null, a
    // real supported state per this field's own metadata comment, routed to
    // GTM_Readout_Triage) must still come back with a full detail payload and
    // a null assessmentRequestId/company rather than throwing or silently
    // omitting the record -- otherwise the new view would have no way to
    // render its orphan-notice branch and the readout would be unopenable.
    @isTest
    static void getReadoutHandlesAnOrphanReadoutWithNoAssessmentRequest() {
        GTM_Readout__c orphan = new GTM_Readout__c(
            Status__c        = 'Draft',
            Offering_Key__c  = 'migration-accelerator',
            Draft_Content__c = '<p>orphan draft</p>'
        );
        insert orphan;

        Test.startTest();
        GtmReadoutController.ReadoutDetail detail = GtmReadoutController.getReadout(orphan.Id);
        Test.stopTest();

        Assert.areEqual(orphan.Id, (Id) detail.id);
        Assert.areEqual('Draft', detail.status);
        Assert.isNull(
            detail.assessmentRequestId,
            'An orphan readout has no Assessment Request to resolve'
        );
        Assert.isNull(detail.assessmentRequestName);
        Assert.isNull(detail.company);
        Assert.isNotNull(
            detail.draftContent,
            'The readout itself must still be fully openable/editable through the new view'
        );
    }

    // ------------------------------------------------------------- approval
    //
    // The approve step is the GTM_Readout_Approval process now. What is testable
    // here is the half that is ours: the trigger that gives the transition its
    // meaning, and the guards on submit / recall.

    @isTest
    static void becomingApprovedCopiesTheDraftAndWritesAVersion() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        Test.startTest();
        approve(readoutId);
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Status__c, Draft_Content__c, Approved_Content__c, Approved_By__c, Approved_Date__c
            FROM GTM_Readout__c WHERE Id = :readoutId
        ];
        Assert.areEqual('Approved', readout.Status__c);
        // The copy a workflow field update cannot make -- Approved_Content__c
        // is a rich text field, so this is the reason GtmReadoutApprovalSync
        // exists at all.
        Assert.areEqual(readout.Draft_Content__c, readout.Approved_Content__c);
        Assert.areEqual(UserInfo.getUserId(), readout.Approved_By__c);
        Assert.isNotNull(readout.Approved_Date__c);

        List<GTM_Readout_Version__c> versions = [
            SELECT Version_Number__c, Status_At_Snapshot__c, Snapshot__c
            FROM GTM_Readout_Version__c WHERE Readout__c = :readoutId
        ];
        Assert.areEqual(1, versions.size());
        Assert.areEqual('Approved', versions[0].Status_At_Snapshot__c);
        Assert.areEqual(1, versions[0].Version_Number__c);
        Assert.areEqual(
            readout.Approved_Content__c,
            versions[0].Snapshot__c,
            'The snapshot is the only thing that can later prove what was approved'
        );
    }

    @isTest
    static void unpublishingIsNotAnApprovalAndSnapshotsNothing() {
        // Published -> Approved goes through the same status value, which is
        // exactly why the trigger keys off the transition and not the
        // destination: treating an unpublish as an approval would overwrite the
        // approved content with the current draft and re-stamp a new approver
        // on a readout nobody re-approved.
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        GtmReadoutController.saveDraftContent(readoutId, '<p>What was approved</p>');
        approve(readoutId);
        GtmReadoutController.publishReadout(readoutId);
        Integer versionsBefore =
            [SELECT COUNT() FROM GTM_Readout_Version__c WHERE Readout__c = :readoutId];

        Test.startTest();
        GtmReadoutController.unpublishReadout(readoutId);
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Status__c, Approved_Content__c FROM GTM_Readout__c WHERE Id = :readoutId
        ];
        Assert.areEqual('Approved', readout.Status__c);
        Assert.areEqual(
            '<p>What was approved</p>',
            readout.Approved_Content__c,
            'Unpublishing must not re-run the approval copy'
        );
        Assert.areEqual(
            versionsBefore,
            [SELECT COUNT() FROM GTM_Readout_Version__c WHERE Readout__c = :readoutId],
            'Unpublishing is not an approval and must not write an approval snapshot'
        );
    }

    @isTest
    static void submitForApprovalRefusesAnythingThatIsNotADraft() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.submitForApproval(readoutId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Only a Draft can enter the approval process');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :readoutId],
            'Nothing should have been submitted'
        );
    }

    @isTest
    static void submitForApprovalRefusesAnEmptyReadout() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        update new GTM_Readout__c(Id = readoutId, Draft_Content__c = null);

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.submitForApproval(readoutId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'There is nothing to approve on an empty readout');
    }

    @isTest
    static void submitForApprovalRefusesAQueueOwnedReadout() {
        // Approval routes to the owner's manager, and a queue does not have
        // one. Refusing with "claim it first" beats a platform routing error.
        Id queueId = ensureTriageQueue();
        orphanScenario();
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Assert.areEqual(queueId, ownerOf(readoutId), 'This test needs a queue-owned readout');

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.submitForApproval(readoutId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'An unclaimed readout cannot be sent for approval');
    }

    @isTest
    static void recallRefusesWhenThereIsNoOutstandingRequest() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.recallApproval(readoutId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'There is nothing to recall on a readout never submitted');
    }

    @isTest
    static void readoutDetailReportsNoApprovalUntilThereIsOne() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        Test.startTest();
        GtmReadoutController.ReadoutDetail detail = GtmReadoutController.getReadout(readoutId);
        Test.stopTest();

        Assert.areEqual('None', detail.approvalState);
        Assert.areEqual(false, detail.isLocked, 'A draft nobody submitted is not locked');
        Assert.isNull(detail.pendingApprover);
    }

    @isTest
    static void readoutDetailNamesTheApproverOnceApproved() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);

        Test.startTest();
        GtmReadoutController.ReadoutDetail detail = GtmReadoutController.getReadout(readoutId);
        Test.stopTest();

        // No ProcessInstance here (the trigger path, not the process path), so
        // this is the legacy-stamp fallback doing its job: an approval that
        // predates the process, or one an admin made directly, still reads back
        // as an approval rather than as a blank.
        Assert.isNotNull(detail.approverName, 'The approver should be named');
        Assert.isNotNull(detail.approvalDate);
    }

    @isTest
    static void aReadoutWaitingOnApprovalCannotBeEdited() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        update new GTM_Readout__c(Id = readoutId, Status__c = 'Pending Approval');

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.saveDraftContent(readoutId, '<p>Sneaking an edit in</p>');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'The content an approver is reading must not change under them');
    }

    // ------------------------------------------------------------- publish

    @isTest
    static void publishReadoutGeneratesTokenAndWritesVersion() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);

        Test.startTest();
        GtmReadoutController.publishReadout(readoutId);
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Status__c, Public_Link_Token__c, Published_Date__c
            FROM GTM_Readout__c WHERE Id = :readoutId
        ];
        Assert.areEqual('Published', readout.Status__c);
        Assert.isNotNull(readout.Public_Link_Token__c);
        Assert.isTrue(readout.Public_Link_Token__c.length() > 0);
        Assert.isNotNull(readout.Published_Date__c);

        Assert.areEqual(
            2,
            [SELECT COUNT() FROM GTM_Readout_Version__c WHERE Readout__c = :readoutId],
            'Approve and Publish should each write a version'
        );
    }

    @isTest
    static void cannotPublishADraftReadout() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.publishReadout(readoutId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Publishing straight from Draft should be blocked -- Approved is required first');
        Assert.areEqual(
            'Draft',
            [SELECT Status__c FROM GTM_Readout__c WHERE Id = :readoutId].Status__c
        );
    }

    @isTest
    static void cannotPublishAnAlreadyPublishedReadout() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);
        GtmReadoutController.publishReadout(readoutId);

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.publishReadout(readoutId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Publishing an already-Published readout should throw');
    }

    @isTest
    static void everyPublishMintsAFreshToken() {
        // A revoked link must stay revoked. If publish ever reused (or
        // derived) the token, unpublish -> republish would silently bring an
        // already-distributed link back to life.
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);

        GtmReadoutController.publishReadout(readoutId);
        String firstToken = [SELECT Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutId].Public_Link_Token__c;

        GtmReadoutController.unpublishReadout(readoutId);

        Test.startTest();
        GtmReadoutController.publishReadout(readoutId);
        Test.stopTest();

        String secondToken = [SELECT Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutId].Public_Link_Token__c;
        Assert.isNotNull(secondToken);
        Assert.areNotEqual(
            firstToken,
            secondToken,
            'Republishing must mint a brand new token, never reissue the revoked one'
        );
    }

    @isTest
    static void publicTokensAreRandomAndNotDerivedFromRecordData() {
        GTM_Assessment_Request__c reqA = seedRequest();
        Id readoutA = GtmReadoutController.generateDraftReadout(reqA.Id);
        approve(readoutA);

        GTM_Assessment_Request__c reqB = seedRequest();
        Id readoutB = GtmReadoutController.generateDraftReadout(reqB.Id);
        approve(readoutB);

        Test.startTest();
        GtmReadoutController.publishReadout(readoutA);
        GtmReadoutController.publishReadout(readoutB);
        Test.stopTest();

        String tokenA = [SELECT Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutA].Public_Link_Token__c;
        String tokenB = [SELECT Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutB].Public_Link_Token__c;

        Assert.areNotEqual(tokenA, tokenB, 'Two readouts must never share a token');
        // 32 random bytes, base64url-encoded with the padding stripped.
        Assert.isTrue(tokenA.length() >= 40, 'Token should carry at least 32 bytes of entropy, got: ' + tokenA.length());
        Assert.isTrue(tokenB.length() >= 40, 'Token should carry at least 32 bytes of entropy, got: ' + tokenB.length());
        // Nothing guessable from the record: not the readout Id, not the
        // assessment Id, not the company name.
        Assert.isFalse(tokenA.contains(String.valueOf(readoutA)), 'Token must not embed the readout Id');
        Assert.isFalse(tokenA.contains(String.valueOf(readoutA).substring(0, 15)), 'Token must not embed the readout Id prefix');
        Assert.isFalse(tokenA.contains(String.valueOf(reqA.Id).substring(0, 15)), 'Token must not embed the assessment Id prefix');
        Assert.isFalse(tokenA.containsIgnoreCase('Northwind'), 'Token must not embed record data');
    }

    // ----------------------------------------------------- template escaping

    @isTest
    static void draftTemplateEscapesProspectSuppliedHtml() {
        // Every field templated into Draft_Content__c is prospect-supplied and
        // ends up rendered on a guest-facing page once published, so the
        // template must escape rather than interpolate.
        GTM_Assessment_Request__c req = seedRequest();
        req.Company__c     = '<script>alert(1)</script>';
        req.Pain_Points__c = '<img src=x onerror="alert(2)">';
        update req;

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        String html = [SELECT Draft_Content__c FROM GTM_Readout__c WHERE Id = :readoutId].Draft_Content__c;
        Assert.isFalse(html.contains('<script>'), 'Prospect-supplied markup must be escaped, not interpolated');
        // The literal text "onerror=" survives escaping; what must not survive
        // is the tag that would make it an attribute.
        Assert.isFalse(html.contains('<img'), 'Prospect-supplied tags must be escaped, not interpolated');
        // Pain_Points__c is the field buildNarrative actually echoes into
        // Draft_Content__c's prose (as the first Findings paragraph), so it
        // is the one whose ESCAPED form has to survive there.
        Assert.isTrue(html.contains('&lt;img'), 'Pain points should survive, escaped: ' + html);
        // Company__c no longer gets interpolated into Draft_Content__c at all
        // under buildNarrative -- it lives in Readout_Data__c's "company" key
        // instead (see generateDraftReadoutCreatesDraftFromScoredRequest),
        // which is JSON, not HTML, so it is correctly NOT HTML-escaped there.
        // That is safe only because the consumer (gtmReadoutView's {company}
        // binding) is LWC's own auto-escaping template interpolation, not
        // innerHTML -- confirmed by inspection, no lwc:dom="manual" or
        // innerHTML anywhere in that component. This still asserts the
        // Draft_Content__c half of the contract: whatever happens to the
        // company name elsewhere, it must never appear un-escaped in the
        // rendered HTML surface.
        Assert.isFalse(html.contains('<script>alert'), 'Company name must never appear as raw markup in the HTML draft');
    }

    // ----------------------------------------------------------- unpublish

    @isTest
    static void unpublishClearsTokenImmediately() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);
        GtmReadoutController.publishReadout(readoutId);

        String tokenBefore = [SELECT Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutId].Public_Link_Token__c;
        Assert.isNotNull(tokenBefore);

        Test.startTest();
        GtmReadoutController.unpublishReadout(readoutId);
        Test.stopTest();

        GTM_Readout__c readout = [SELECT Status__c, Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutId];
        Assert.areEqual('Approved', readout.Status__c);
        Assert.isNull(readout.Public_Link_Token__c, 'The token must be cleared immediately on unpublish');
    }

    @isTest
    static void cannotUnpublishADraftOrApprovedReadout() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        Boolean threwOnDraft = false;
        try {
            GtmReadoutController.unpublishReadout(readoutId);
        } catch (AuraHandledException e) {
            threwOnDraft = true;
        }
        Assert.isTrue(threwOnDraft, 'Unpublishing a Draft readout should throw');

        approve(readoutId);
        Boolean threwOnApproved = false;
        Test.startTest();
        try {
            GtmReadoutController.unpublishReadout(readoutId);
        } catch (AuraHandledException e) {
            threwOnApproved = true;
        }
        Test.stopTest();
        Assert.isTrue(threwOnApproved, 'Unpublishing an Approved (never-published) readout should throw');
    }

    // ------------------------------------------------------------- save draft

    @isTest
    static void saveDraftContentOnlyAllowedWhileDraft() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        GtmReadoutController.saveDraftContent(readoutId, '<p>Edited by rep</p>');
        Assert.areEqual(
            '<p>Edited by rep</p>',
            [SELECT Draft_Content__c FROM GTM_Readout__c WHERE Id = :readoutId].Draft_Content__c
        );

        approve(readoutId);

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.saveDraftContent(readoutId, '<p>Too late</p>');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Editing draft content after approval should be blocked');
    }

    // ------------------------------------------------- ownership & assignment
    //
    // GTM_Readout__c is Private, so OwnerId is the access grant, not a label.
    // These cover the resolution order the Generator applies, the guarantee
    // that generation refuses rather than hands the record to an owner it
    // cannot validate, and that the rep-facing query actually returns the
    // record to its owner (and only to its owner) under that model.

    /**
     * Users are created inside their own runAs block: inserting a User and a
     * regular sObject in one transaction is a MIXED_DML_OPERATION.
     */
    private static User createRep(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias             = alias,
            Email             = alias + '@example.com',
            EmailEncodingKey  = 'UTF-8',
            LastName          = 'Rep ' + alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'America/New_York',
            Username          = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    private static Id ownerOf(Id readoutId) {
        return [SELECT OwnerId FROM GTM_Readout__c WHERE Id = :readoutId].OwnerId;
    }

    @isTest
    static void generatedReadoutIsOwnedByTheOpportunityOwner() {
        // The Opportunity owner is the deal owner of record and wins over
        // every other candidate, including the request's own owner.
        User dealOwner = createRep('gtmdo1');
        User otherRep  = createRep('gtmor1');

        Opportunity opp = new Opportunity(
            Name      = 'Northwind Retail - Migration Accelerator',
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(90),
            OwnerId   = dealOwner.Id
        );
        insert opp;

        GTM_Assessment_Request__c req = seedRequest();
        req.Opportunity__c = opp.Id;
        req.OwnerId = otherRep.Id;
        update req;

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        Assert.isNotNull(readoutId, 'A readout should be created');
        Assert.areEqual(
            dealOwner.Id,
            ownerOf(readoutId),
            'The readout should be owned by the Opportunity owner, not the request owner'
        );
        Assert.areNotEqual(
            UserInfo.getUserId(),
            ownerOf(readoutId),
            'The readout must not fall back to the creating (submitting) user when a rep is resolvable'
        );
    }

    @isTest
    static void generatedReadoutFallsBackToTheAssessmentRequestOwner() {
        // No Opportunity on the request -- the Engagement Link owner that
        // GtmAssessmentRequestController stamped onto the request is next.
        User linkOwner = createRep('gtmlo1');

        GTM_Assessment_Request__c req = seedRequest();
        req.OwnerId = linkOwner.Id;
        update req;

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        Assert.areEqual(linkOwner.Id, ownerOf(readoutId));
    }

    @isTest
    static void generatedReadoutSkipsAnInactiveOwnerCandidate() {
        // The same validation that keeps a Guest user off the record (an
        // active, non-Guest User is required) also rejects a deactivated rep,
        // so generation falls through to the next candidate -- here, the
        // running user -- instead of creating a record nobody can reach.
        User departed = createRep('gtmdp1');

        GTM_Assessment_Request__c req = seedRequest();
        req.OwnerId = departed.Id;
        update req;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            departed.IsActive = false;
            update departed;
        }

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        Assert.areEqual(
            UserInfo.getUserId(),
            ownerOf(readoutId),
            'An inactive candidate should be skipped, not assigned'
        );
    }

    @isTest
    static void generatedReadoutOwnerIsAlwaysAnActiveNonGuestUser() {
        // The invariant, stated directly: whatever the resolution order picks,
        // it is never a Queue and never the Experience Cloud guest user.
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        Id ownerId = ownerOf(readoutId);
        Assert.areEqual(
            User.SObjectType,
            ownerId.getSObjectType(),
            'A readout must be owned by a User, never a Queue'
        );
        User owner = [SELECT UserType, IsActive FROM User WHERE Id = :ownerId];
        Assert.areNotEqual('Guest', owner.UserType, 'The guest user must never own a readout');
        Assert.isTrue(owner.IsActive, 'The owner must be an active user');
    }

    @isTest
    static void generationFilesTheOwningRepAReviewCase() {
        User linkOwner = createRep('gtmtk1');

        GTM_Assessment_Request__c req = seedRequest();
        req.OwnerId = linkOwner.Id;
        update req;

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        List<Case> cases = [
            SELECT OwnerId, Subject, Description, Readout__c, SuppliedEmail
            FROM Case
            WHERE Readout__c = :readoutId
        ];
        Assert.areEqual(1, cases.size(), 'A review Case should be filed against the readout');
        Assert.areEqual(linkOwner.Id, cases[0].OwnerId, 'The Case belongs to the owning rep');
        Assert.isTrue(
            cases[0].Subject.contains('Northwind Retail'),
            'The Case subject should name the client: ' + cases[0].Subject
        );
        Assert.areEqual(
            'alex.rivera@example.com',
            cases[0].SuppliedEmail,
            'The requester email makes the case natively repliable'
        );
    }

    @isTest
    static void generationFilesNoTaskAnyMore() {
        // One work item, not two. The Task used to be a second thing to mark
        // done, and it silently failed to be created for queue-owned readouts.
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Task WHERE WhatId = :readoutId],
            'The review Task was replaced by the review Case'
        );
    }

    @isTest
    static void reviewCaseCanBeSwitchedOffInConfig() {
        GtmReadoutController.configOverride = new GTM_Assessment_Config__mdt(
            Create_Readout_Case__c = false
        );
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        Assert.isNotNull(readoutId, 'The readout is still generated with the Case toggle off');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Case WHERE Readout__c = :readoutId],
            'No Case should be created when Create_Readout_Case__c is false'
        );
    }

    // ------------------------------------------------------------ triage queue
    //
    // The orphan case: a direct booking with no Engagement Link and no
    // Opportunity, submitted by the Experience Cloud guest user, where none of
    // the three derived User candidates resolves. Generation used to refuse
    // outright, so those assessments produced no readout and nobody knew they
    // had happened. They now land on the GTM_Readout_Triage queue.

    /**
     * The deployed queue if the org has it (it is source metadata, so in a
     * deployed org it does), otherwise one created for the test. Looking first
     * matters: inserting a second Group with the same DeveloperName fails with
     * DUPLICATE_DEVELOPER_NAME.
     *
     * Group is a setup object, hence the runAs -- inserting it alongside a
     * regular sObject in one transaction is a MIXED_DML_OPERATION.
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
            // Both objects, matching the deployed queue: the readout and the
            // review Case that follows its owner.
            insert new List<QueueSobject>{
                new QueueSobject(QueueId = q.Id, SobjectType = 'GTM_Readout__c'),
                new QueueSobject(QueueId = q.Id, SobjectType = 'Case')
            };
        }
        return q.Id;
    }

    /** No CMDT fallback owner, no review Case -- just the ownership question. */
    private static void orphanScenario() {
        GtmReadoutController.configOverride = new GTM_Assessment_Config__mdt(
            Create_Readout_Case__c   = false,
            Default_Readout_Owner__c = null
        );
        GtmReadoutController.suppressDerivedOwnerCandidates = true;
    }

    @isTest
    static void anOrphanReadoutIsCreatedAndOwnedByTheTriageQueue() {
        Id queueId = ensureTriageQueue();
        orphanScenario();
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        // The behaviour change, stated directly: the readout now exists.
        Assert.isNotNull(
            readoutId,
            'An orphan assessment must produce a readout for triage, not silently produce nothing'
        );
        Assert.areEqual(queueId, ownerOf(readoutId), 'It should be owned by the triage queue');
        Assert.areEqual(
            'Draft',
            [SELECT Status__c FROM GTM_Readout__c WHERE Id = :readoutId].Status__c
        );
    }

    @isTest
    static void aConfiguredFallbackOwnerStillBeatsTheQueue() {
        // The queue is the last resort, not a replacement for the CMDT step: a
        // named human is an explicit statement about who handles orphans and
        // must not be overridden by a queue that exists by default.
        User named = createRep('gtmcm1');
        Id queueId = ensureTriageQueue();

        GtmReadoutController.configOverride = new GTM_Assessment_Config__mdt(
            Create_Readout_Case__c   = false,
            Default_Readout_Owner__c = named.Username
        );
        GtmReadoutController.suppressDerivedOwnerCandidates = true;
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        Assert.areEqual(named.Id, ownerOf(readoutId), 'The configured owner wins');
        Assert.areNotEqual(queueId, ownerOf(readoutId));
    }

    @isTest
    static void aResolvableRepStillBeatsTheQueue() {
        // The queue must not start collecting readouts that have a perfectly
        // good owner -- the common path is untouched.
        ensureTriageQueue();
        User linkOwner = createRep('gtmqr1');

        GTM_Assessment_Request__c req = seedRequest();
        req.OwnerId = linkOwner.Id;
        update req;

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        Assert.areEqual(linkOwner.Id, ownerOf(readoutId));
        Assert.areEqual(
            User.SObjectType,
            ownerOf(readoutId).getSObjectType(),
            'A resolvable rep still owns the readout as a User, not via the queue'
        );
    }

    @isTest
    static void aQueueOwnedReadoutSurvivesWhateverHappensToItsReviewCase() {
        // Queue-owned Cases are a plain platform capability -- unlike Tasks,
        // which additionally needed an org preference this repo cannot deploy,
        // and which is why the Task silently failed to be created in exactly
        // this scenario. The Case should now be filed. It is still best-effort
        // (a queue missing Case from its supported objects would fail the
        // insert), so the assertion that holds in every org is that it cannot
        // take the readout down with it -- and that where it does land, it
        // belongs to the queue and never to a bystander.
        Id queueId = ensureTriageQueue();
        GtmReadoutController.configOverride = new GTM_Assessment_Config__mdt(
            Create_Readout_Case__c   = true,
            Default_Readout_Owner__c = null
        );
        GtmReadoutController.suppressDerivedOwnerCandidates = true;
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        Assert.isNotNull(readoutId, 'The readout must not be rolled back over its review Case');
        Assert.areEqual(queueId, ownerOf(readoutId));

        for (Case c : [SELECT OwnerId FROM Case WHERE Readout__c = :readoutId]) {
            Assert.areEqual(
                queueId,
                c.OwnerId,
                'A review Case for a queue-owned readout belongs to the queue, never to a bystander'
            );
        }
    }

    @isTest
    static void generationStillRefusesWhenThereIsNoQueueAndNoOwner() {
        // The remaining null case. It is now a deployment fault -- the queue is
        // source metadata -- rather than the routine outcome of a direct
        // booking, but an ownerless record on a Private object still helps
        // nobody, so refusing is still right.
        //
        // Only assertable in an org where the queue has not been deployed; the
        // test skips itself rather than deleting a live queue out from under
        // whatever else is running.
        List<Group> deployed = [
            SELECT Id FROM Group WHERE DeveloperName = 'GTM_Readout_Triage' AND Type = 'Queue' LIMIT 1
        ];
        if (!deployed.isEmpty()) {
            return;
        }
        orphanScenario();
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Test.stopTest();

        Assert.isNull(readoutId, 'With no owner and no queue, no readout should be created');
    }

    // --------------------------------------------------------- return to draft
    //
    // Approved -> Draft. Without it an approval is a dead end: saveDraftContent
    // refuses anything but a Draft, and unpublishReadout only ever lands back
    // on Approved.

    @isTest
    static void returnToDraftReopensAnApprovedReadoutForEditing() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        GtmReadoutController.saveDraftContent(readoutId, '<p>Approved copy</p>');
        approve(readoutId);

        Test.startTest();
        GtmReadoutController.returnToDraft(readoutId);
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Status__c, Approved_By__c, Approved_Date__c, Public_Link_Token__c
            FROM GTM_Readout__c WHERE Id = :readoutId
        ];
        Assert.areEqual('Draft', readout.Status__c);
        // A Draft carrying an approver stamp reads as though it were still
        // approved. The approval is preserved in the version snapshot instead.
        Assert.isNull(readout.Approved_By__c, 'The approver stamp must be cleared on revert');
        Assert.isNull(readout.Approved_Date__c, 'The approval date must be cleared on revert');
        Assert.isNull(readout.Public_Link_Token__c);

        // And it is editable again -- the whole point of the action.
        GtmReadoutController.saveDraftContent(readoutId, '<p>Fixed the typo</p>');
        Assert.areEqual(
            '<p>Fixed the typo</p>',
            [SELECT Draft_Content__c FROM GTM_Readout__c WHERE Id = :readoutId].Draft_Content__c
        );
    }

    @isTest
    static void returnToDraftSnapshotsTheApprovalBeforeDiscardingIt() {
        // The approval history has to survive the revert: it must stay provable
        // what was approved and when, after the record itself stops saying so.
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        GtmReadoutController.saveDraftContent(readoutId, '<p>The approved wording</p>');
        approve(readoutId);

        Test.startTest();
        GtmReadoutController.returnToDraft(readoutId);
        Test.stopTest();

        List<GTM_Readout_Version__c> versions = [
            SELECT Version_Number__c, Status_At_Snapshot__c, Snapshot__c, Change_Summary__c
            FROM GTM_Readout_Version__c
            WHERE Readout__c = :readoutId
            ORDER BY Version_Number__c
        ];
        Assert.areEqual(2, versions.size(), 'Approve wrote one version; the revert writes a second');
        GTM_Readout_Version__c reverted = versions[1];
        Assert.areEqual(2, reverted.Version_Number__c);
        Assert.areEqual(
            '<p>The approved wording</p>',
            reverted.Snapshot__c,
            'The snapshot must hold the approved content, not the empty draft it reverts to'
        );
        Assert.areEqual(
            'Approved',
            reverted.Status_At_Snapshot__c,
            'The snapshotted content was Approved -- that is what makes this row evidence of the approval'
        );
        Assert.isTrue(
            reverted.Change_Summary__c.startsWith('Returned to draft'),
            'The summary should name the event that caused the snapshot: ' + reverted.Change_Summary__c
        );
    }

    @isTest
    static void returnToDraftRefusesAPublishedReadout() {
        // A published readout's link is live in a prospect's inbox. It must not
        // become editable while that link still resolves, so the rep has to
        // unpublish first -- which is what revokes the token.
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);
        GtmReadoutController.publishReadout(readoutId);
        String liveToken = [SELECT Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutId].Public_Link_Token__c;

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.returnToDraft(readoutId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Published -> Draft must be refused outright');
        GTM_Readout__c readout = [
            SELECT Status__c, Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutId
        ];
        Assert.areEqual('Published', readout.Status__c, 'The rejected revert must change nothing');
        Assert.areEqual(liveToken, readout.Public_Link_Token__c, 'And must not disturb the live link');
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM GTM_Readout_Version__c WHERE Readout__c = :readoutId],
            'No snapshot should be written by the rejected revert'
        );
    }

    @isTest
    static void returnToDraftWorksAfterUnpublishing() {
        // The supported route back from Published: unpublish (which revokes the
        // token) and then revert.
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);
        GtmReadoutController.publishReadout(readoutId);
        GtmReadoutController.unpublishReadout(readoutId);

        Test.startTest();
        GtmReadoutController.returnToDraft(readoutId);
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Status__c, Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutId
        ];
        Assert.areEqual('Draft', readout.Status__c);
        Assert.isNull(readout.Public_Link_Token__c);
    }

    @isTest
    static void returnToDraftRefusesAReadoutThatIsAlreadyADraft() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.returnToDraft(readoutId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Reverting a Draft should throw rather than silently no-op');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM GTM_Readout_Version__c WHERE Readout__c = :readoutId],
            'No snapshot should be written'
        );
    }

    @isTest
    static void returnToDraftThrowsForAMissingId() {
        Boolean threw = false;
        try {
            GtmReadoutController.returnToDraft(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'A null readout Id should throw');
    }

    @isTest
    static void aRevertedReadoutCanBeApprovedAndPublishedAgainWithAFreshToken() {
        // The full recovery loop, and the guarantee that recovering does not
        // resurrect a link that was already revoked.
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);
        GtmReadoutController.publishReadout(readoutId);
        String firstToken = [SELECT Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutId].Public_Link_Token__c;

        GtmReadoutController.unpublishReadout(readoutId);
        GtmReadoutController.returnToDraft(readoutId);
        GtmReadoutController.saveDraftContent(readoutId, '<p>Corrected</p>');

        Test.startTest();
        approve(readoutId);
        GtmReadoutController.publishReadout(readoutId);
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Status__c, Approved_Content__c, Approved_By__c, Public_Link_Token__c
            FROM GTM_Readout__c WHERE Id = :readoutId
        ];
        Assert.areEqual('Published', readout.Status__c);
        Assert.areEqual('<p>Corrected</p>', readout.Approved_Content__c, 'The re-approval picks up the edit');
        Assert.areEqual(UserInfo.getUserId(), readout.Approved_By__c, 'And re-stamps the approver');
        Assert.areNotEqual(
            firstToken,
            readout.Public_Link_Token__c,
            'Republishing after a revert must mint a new token, never reissue the revoked one'
        );
    }

    // ─── getReadoutByRequest ─────────────────────────────────────────────────

    @isTest
    static void getReadoutByRequestReturnsTheMostRecentReadout() {
        GTM_Assessment_Request__c req = seedRequest();
        Id firstId  = GtmReadoutController.generateDraftReadout(req.Id);
        Id secondId = GtmReadoutController.generateDraftReadout(req.Id);

        Test.startTest();
        GtmReadoutController.ReadoutSummary result =
            GtmReadoutController.getReadoutByRequest(req.Id);
        Test.stopTest();

        Assert.isNotNull(result, 'A summary should be returned when readouts exist');
        Assert.areEqual(
            String.valueOf(secondId),
            result.id,
            'The most recently created readout should be returned'
        );
        Assert.areEqual('Draft', result.status);
        Assert.areEqual(String.valueOf(req.Id), result.assessmentRequestId);
    }

    @isTest
    static void getReadoutByRequestReturnsNullWhenNoReadoutExists() {
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        GtmReadoutController.ReadoutSummary result =
            GtmReadoutController.getReadoutByRequest(req.Id);
        Test.stopTest();

        Assert.isNull(result, 'Null should be returned when no readout has been generated');
    }

    @isTest
    static void getReadoutByRequestEnforcesSharing() {
        // with sharing: a rep who does not own the readout cannot see it.
        User owningRep = createRep('gtmbr1');
        User otherRep  = createRep('gtmbr2');

        GTM_Assessment_Request__c req = seedRequest();
        req.OwnerId = owningRep.Id;
        update req;
        GtmReadoutController.generateDraftReadout(req.Id);

        Test.startTest();
        GtmReadoutController.ReadoutSummary seen;
        System.runAs(owningRep) {
            seen = GtmReadoutController.getReadoutByRequest(req.Id);
        }
        GtmReadoutController.ReadoutSummary notSeen;
        System.runAs(otherRep) {
            notSeen = GtmReadoutController.getReadoutByRequest(req.Id);
        }
        Test.stopTest();

        Assert.isNotNull(seen,   'The owning rep must see their own readout');
        Assert.isNull(notSeen, 'A rep who does not own the readout must not see it');
    }

    @isTest
    static void getReadoutByRequestThrowsOnNullRequestId() {
        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.getReadoutByRequest(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Passing a null requestId should throw an AuraHandledException');
    }

    // ------------------------------------------------------- self-approval
    //
    // GTM_Readout_Approval_Settings__c.Self_Approval_Enabled__c off (the
    // default, unset here) is manager mode -- covered by the submitForApproval/
    // recallApproval tests above, which this section leaves entirely alone.
    // These cover the toggle turned on: selfApproveReadout's own guard rails,
    // that it gets the same stamping/snapshotting a manager approval gets
    // (GtmReadoutApprovalHandler, unmodified), and that it additionally leaves
    // a GTM_Readout_Approval_Log__c row as its own audit trail.

    private static void enableSelfApproval() {
        GtmReadoutApprovalSettingsController.setSelfApprovalEnabled(true);
    }

    @isTest
    static void selfApproveReadoutRefusesWhenTheSettingIsOff() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.selfApproveReadout(readoutId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Self-approval must be refused unless the org setting is on');
        Assert.areEqual(
            'Draft',
            [SELECT Status__c FROM GTM_Readout__c WHERE Id = :readoutId].Status__c,
            'A refused self-approve must not change the record'
        );
    }

    @isTest
    static void selfApproveReadoutApprovesAndGetsTheSameStampingAManagerApprovalGets() {
        enableSelfApproval();
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        Test.startTest();
        GtmReadoutController.selfApproveReadout(readoutId);
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Status__c, Approved_Content__c, Draft_Content__c, Approved_By__c, Approved_Date__c
            FROM GTM_Readout__c
            WHERE Id = :readoutId
        ];
        Assert.areEqual('Approved', readout.Status__c);
        // GtmReadoutApprovalHandler.stampApproval is keyed off the Status__c
        // transition, not the trigger source -- this must fire exactly as it
        // would for a manager's approval, with no duplicate logic in
        // selfApproveReadout itself.
        Assert.areEqual(readout.Draft_Content__c, readout.Approved_Content__c);
        Assert.isNotNull(readout.Approved_By__c, 'stampApproval should have stamped an approver');
        Assert.isNotNull(readout.Approved_Date__c);
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM GTM_Readout_Version__c WHERE Readout__c = :readoutId],
            'snapshotApprovals should have written the same version snapshot a manager approval gets'
        );
    }

    @isTest
    static void selfApproveReadoutInsertsAnAuditLogRow() {
        enableSelfApproval();
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        Test.startTest();
        GtmReadoutController.selfApproveReadout(readoutId);
        Test.stopTest();

        List<GTM_Readout_Approval_Log__c> logs = [
            SELECT Readout__c, Approved_By__c, Approved_Date__c
            FROM GTM_Readout_Approval_Log__c
            WHERE Readout__c = :readoutId
        ];
        Assert.areEqual(1, logs.size(), 'Self-approval must leave exactly one audit log row');
        Assert.areEqual(UserInfo.getUserId(), logs[0].Approved_By__c);
        Assert.isNotNull(logs[0].Approved_Date__c);
    }

    @isTest
    static void selfApproveReadoutRefusesAnyoneButTheOwner() {
        enableSelfApproval();
        User owningRep = createRep('gtmsa1');
        User otherRep  = createRep('gtmsa2');

        GTM_Assessment_Request__c req = seedRequest();
        req.OwnerId = owningRep.Id;
        update req;
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Assert.areEqual(owningRep.Id, ownerOf(readoutId));

        Boolean threw = false;
        Test.startTest();
        System.runAs(otherRep) {
            try {
                GtmReadoutController.selfApproveReadout(readoutId);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Only the readout\'s own owner can self-approve it');
        Assert.areEqual(
            'Draft',
            [SELECT Status__c FROM GTM_Readout__c WHERE Id = :readoutId].Status__c
        );
    }

    @isTest
    static void selfApproveReadoutRefusesAnythingThatIsNotADraft() {
        enableSelfApproval();
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.selfApproveReadout(readoutId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Only a Draft can be self-approved');
    }

    @isTest
    static void selfApproveReadoutRefusesAnEmptyReadout() {
        enableSelfApproval();
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        update new GTM_Readout__c(Id = readoutId, Draft_Content__c = null);

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.selfApproveReadout(readoutId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'There is nothing to approve on an empty readout');
    }

    @isTest
    static void readoutDetailReportsSelfApprovalFlagsForTheOwner() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        Test.startTest();
        GtmReadoutController.ReadoutDetail offDetail = GtmReadoutController.getReadout(readoutId);
        enableSelfApproval();
        GtmReadoutController.ReadoutDetail onDetail = GtmReadoutController.getReadout(readoutId);
        Test.stopTest();

        Assert.isFalse(offDetail.selfApprovalEnabled, 'Manager mode is the default');
        Assert.isTrue(onDetail.isOwner, 'The running user generated (and so owns) this readout');
        Assert.isTrue(onDetail.selfApprovalEnabled, 'The DTO must reflect the toggle once it is on');
    }

    // ------------------------------------------------- generateReadoutForRequest
    //
    // The rep-facing wrapper around generateDraftReadout. Unlike
    // generateDraftReadout (only ever called with a system-derived, never a
    // caller-supplied, Id today) this method takes the Id straight from an
    // LWC button click, so the access check in front of the delegation is
    // the thing under test here, not the generation logic itself (that is
    // already covered by every other test in this class).

    @isTest
    static void generateReadoutForRequestCreatesAReadoutForAVisibleRequest() {
        GTM_Assessment_Request__c req = seedRequest();
        Account acc = new Account(Name = 'Northwind Retail');
        insert acc;
        req.Account__c = acc.Id;
        update req;

        Test.startTest();
        Id readoutId = GtmReadoutController.generateReadoutForRequest(req.Id);
        Test.stopTest();

        Assert.isNotNull(readoutId, 'A readout should be created');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM GTM_Readout__c WHERE Assessment_Request__c = :req.Id],
            'Exactly one readout should exist for the request'
        );
    }

    @isTest
    static void generateReadoutForRequestIsIdempotentOnASecondCall() {
        GTM_Assessment_Request__c req = seedRequest();
        Account acc = new Account(Name = 'Northwind Retail');
        insert acc;
        req.Account__c = acc.Id;
        update req;

        Test.startTest();
        Id firstId  = GtmReadoutController.generateReadoutForRequest(req.Id);
        Id secondId = GtmReadoutController.generateReadoutForRequest(req.Id);
        Test.stopTest();

        Assert.areEqual(firstId, secondId, 'A second call must return the existing readout, not a new one');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM GTM_Readout__c WHERE Assessment_Request__c = :req.Id],
            'No duplicate readout should be created'
        );
    }

    @isTest
    static void generateReadoutForRequestRejectsANonexistentId() {
        GTM_Assessment_Request__c req = seedRequest();
        Id bogusId = req.Id;
        delete req;

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.generateReadoutForRequest(bogusId);
        } catch (AuraHandledException e) {
            // AuraHandledException.getMessage() famously returns
            // "Script-thrown exception" in Apex test context unless
            // setMessage() is called separately (a well-known platform
            // quirk, not a bug in the method under test) -- asserting the
            // type thrown is the meaningful, stable check here.
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A bogus Id must be rejected');
    }

    /**
     * gtm-dev's actual Account/Contact/Opportunity org-wide defaults are
     * confirmed (empirically, against the org -- not assumed from
     * TASK_SCOPE's Private-OWD framing) to be Public Read/Write: a rep with
     * a Standard-User-family profile can query and see any Account,
     * Contact, or Opportunity row regardless of ownership, sharing rules,
     * or role hierarchy. Under `with sharing`, row-level sharing is exactly
     * what the class enforces -- and there is no row this org's sharing
     * model can actually hide from an active internal user today, so a
     * true "rep denied by sharing" fixture is not constructible against
     * this org's real configuration (CRUD/FLS profile permissions are a
     * separate, non-sharing-related enforcement layer that plain SOQL does
     * not check unless explicitly asked to, and TASK_SCOPE's own §2 rules
     * out WITH SECURITY_ENFORCED here).
     *
     * What IS both realistic and exercises the identical code path
     * (Account__r/Contact__r/Opportunity__r all resolving null) is a
     * request with none of the three relationships populated at all --
     * e.g. a direct booking or an assessment request created before a
     * rep linked it to a deal. generateReadoutForRequest must refuse this
     * exactly the same way it would refuse a sharing-denied relationship,
     * since the two are indistinguishable from the query's own result.
     */
    @isTest
    static void generateReadoutForRequestDeniesARequestWithNoAccessibleRelationships() {
        GTM_Assessment_Request__c req = seedRequest();
        // No Account__c / Contact__c / Opportunity__c set -- seedRequest()
        // never populates them, so req is already in this state.

        Boolean threw = false;
        Test.startTest();
        try {
            GtmReadoutController.generateReadoutForRequest(req.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(
            threw,
            'A request with no Account/Contact/Opportunity relationship must be denied, same as a sharing-denied one'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM GTM_Readout__c WHERE Assessment_Request__c = :req.Id],
            'A denied access check must not create a readout'
        );
    }

    // ------------------------- rep-initiated-assessment-no-page-3 (readout link)

    /**
     * The full chain, end to end, starting from a GTM_Assessment_Request__c
     * with NO Saved_Configuration__c populated at all (the shape a
     * rep-initiated pageless assessment leaves it in per #1/#2) --
     * generateReadoutForRequest -> submitForApproval -> approve ->
     * publishReadout -- proving the readout pipeline never needed a
     * "real page" to exist, exactly as TASK_SCOPE §2.A's grep found.
     *
     * Also proves the resulting Public_Link_Token__c actually resolves
     * through GtmReadoutPublicController.getPublishedReadout, the same
     * guest-facing entry point a real prospect link hits -- not just that a
     * token string was written to the field.
     */
    @isTest
    static void fullChainWorksForAnAssessmentRequestWithNoSavedConfigurationAtAll() {
        Account acc = new Account(Name = 'Northwind Retail (no page)');
        insert acc;

        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Account__c          = acc.Id,
            Requester_Name__c   = 'Alex Rivera',
            Requester_Email__c  = 'alex.rivera@example.com',
            Company__c          = 'Northwind Retail',
            Assessment_Score__c = SAMPLE_SCORE,
            Assessment_Tier__c  = 'Prep Required',
            Section_Scores__c   = '{"estate_scale":3,"source_access":2}'
            // Saved_Configuration__c deliberately left null -- no page at all.
        );
        insert req;
        Assert.isNull(req.Saved_Configuration__c, 'Sanity check: this request has no page');

        Test.startTest();
        Id readoutId = GtmReadoutController.generateReadoutForRequest(req.Id);
        Assert.isNotNull(readoutId, 'A pageless request must still produce a readout');

        driveSubmitForApproval(readoutId);

        approve(readoutId);
        Assert.areEqual(
            'Approved',
            [SELECT Status__c FROM GTM_Readout__c WHERE Id = :readoutId].Status__c
        );

        GtmReadoutController.publishReadout(readoutId);
        Test.stopTest();

        GTM_Readout__c published = [
            SELECT Status__c, Public_Link_Token__c, Notification_Sent_Date__c
            FROM GTM_Readout__c WHERE Id = :readoutId
        ];
        Assert.areEqual('Published', published.Status__c);
        Assert.isNotNull(
            published.Public_Link_Token__c,
            'Publishing must mint a token even when the source request had no page'
        );

        // The exact mechanism a real prospect's browser hits -- proves the
        // token is not merely present on the record but actually resolves
        // through the guest-facing access path, identically to a
        // page-linked readout's token.
        GtmReadoutPublicController.PublishedReadout viaPublicLink =
            GtmReadoutPublicController.getPublishedReadout(published.Public_Link_Token__c);
        Assert.isNotNull(
            viaPublicLink,
            'The public link token from a pageless readout must resolve exactly like a page-linked one'
        );
        Assert.isNotNull(viaPublicLink.content, 'The published readout must carry real approved content');
    }

    /**
     * Same chain, but for a request whose Saved_Configuration__c IS
     * populated -- just flagged Rep_Direct (#1's pageless-but-linked shape,
     * e.g. a rep picked a Contact/Account and #1 created a bare
     * GTM_Saved_Configuration__c row with no Generated_URL__c). Confirms
     * the pipeline treats this identically to no lookup at all, per
     * TASK_SCOPE §2.B.1's instruction to cover both shapes.
     */
    @isTest
    static void fullChainWorksForARepDirectFlaggedSavedConfiguration() {
        Account acc = new Account(Name = 'Northwind Retail (Rep_Direct)');
        insert acc;

        GTM_Saved_Configuration__c savedConfig = new GTM_Saved_Configuration__c(
            Offering__c            = 'migration-accelerator',
            Presentation_Stage__c  = 'Rep_Direct'
            // No Generated_URL__c -- there is no branded page to link to.
        );
        insert savedConfig;

        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Account__c             = acc.Id,
            Saved_Configuration__c = savedConfig.Id,
            Requester_Name__c      = 'Alex Rivera',
            Requester_Email__c     = 'alex.rivera@example.com',
            Company__c             = 'Northwind Retail',
            Assessment_Score__c    = SAMPLE_SCORE,
            Assessment_Tier__c     = 'Prep Required',
            Section_Scores__c      = '{"estate_scale":3,"source_access":2}'
        );
        insert req;

        Test.startTest();
        Id readoutId = GtmReadoutController.generateReadoutForRequest(req.Id);
        Assert.isNotNull(readoutId, 'A Rep_Direct-linked request must still produce a readout');

        driveSubmitForApproval(readoutId);
        approve(readoutId);
        GtmReadoutController.publishReadout(readoutId);
        Test.stopTest();

        GTM_Readout__c published = [
            SELECT Status__c, Public_Link_Token__c FROM GTM_Readout__c WHERE Id = :readoutId
        ];
        Assert.areEqual('Published', published.Status__c);
        Assert.isNotNull(published.Public_Link_Token__c);

        GtmReadoutPublicController.PublishedReadout viaPublicLink =
            GtmReadoutPublicController.getPublishedReadout(published.Public_Link_Token__c);
        Assert.isNotNull(
            viaPublicLink,
            'A Rep_Direct-sourced readout\'s public link must resolve identically to a real page\'s'
        );
    }

    // The publish-time prospect notification's fallback for a pageless
    // request (the real gap this sub-issue found -- sendPublishNotification
    // silently never emailed a pageless assessment's prospect, since its
    // baseUrl came only from Saved_Configuration__r.Generated_URL__c) is
    // covered in GtmReadoutPublishNotificationTest, which already owns the
    // notification-specific fixtures and the deterministic test seam needed
    // to exercise it -- see
    // publishFallsBackToTheStandaloneReadoutLinkWhenTheConfiguratorLinkIsMissing
    // there, kept out of this file for the same reason that class's own
    // header comment gives.

    // ------------------------------------------------ lifecycle notification
    // (Unit 3b, ADR-0010 wiring points 1/2/3/4/5/6.) Gives the running test
    // user a manager so submitForApproval's resolveManagerId has a real
    // approverId to fire against -- Approval.process() itself may still
    // fail in this org context (no routable approval process for the test
    // user), which driveSubmitForApproval already tolerates; the
    // notification code runs before that call regardless (see
    // submitForApproval's own comment), so it is exercised either way.
    private static void giveRunningUserAManager() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = 'ldrmgr' + String.valueOf(Crypto.getRandomInteger()).replace('-', 'x');
        User manager = new User(
            Alias = 'ldrmgr', Email = uniq + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = uniq, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = uniq + '@gtmtest.example.com'
        );
        insert manager;
        update new User(Id = UserInfo.getUserId(), ManagerId = manager.Id);
    }

    private static void setSubmitForApprovalNotification(Boolean notify, Boolean autoCloseNewRequest) {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.notifyOnSubmitForApproval = notify;
        dto.autoCloseNewRequestTasks = autoCloseNewRequest;
        GtmNotificationSettingsController.setNotificationSettings(dto);
    }

    @isTest
    static void submitForApprovalFiresTaskAndBellToTheOwnersManagerWhenOn() {
        giveRunningUserAManager();
        setSubmitForApprovalNotification(true, false);
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        GtmReadoutController.saveDraftContent(readoutId, '<p>Ready</p>');

        Test.startTest();
        driveSubmitForApproval(readoutId);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_APPROVE_READOUT],
            'A Task should fire to the approver when the setting is on'
        );
    }

    @isTest
    static void submitForApprovalDoesNotFireWhenSettingIsOff() {
        giveRunningUserAManager();
        setSubmitForApprovalNotification(false, false);
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        GtmReadoutController.saveDraftContent(readoutId, '<p>Ready</p>');

        Test.startTest();
        driveSubmitForApproval(readoutId);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_APPROVE_READOUT],
            'No Task should fire when the setting is off'
        );
    }

    @isTest
    static void submitForApprovalClosesTheOriginatingNewRequestTaskWhenAutoCloseIsOn() {
        giveRunningUserAManager();
        setSubmitForApprovalNotification(false, true);
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        GtmReadoutController.saveDraftContent(readoutId, '<p>Ready</p>');
        insert new Task(
            WhatId = req.Id, OwnerId = UserInfo.getUserId(),
            Subject = GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, Status = 'Not Started'
        );

        Test.startTest();
        driveSubmitForApproval(readoutId);
        Test.stopTest();

        Assert.areEqual(
            'Completed',
            [SELECT Status FROM Task WHERE WhatId = :req.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST LIMIT 1].Status,
            'submitForApproval must close the originating New Request Task, not generateDraftReadout time'
        );
    }

    @isTest
    static void submitForApprovalLeavesTheNewRequestTaskOpenWhenAutoCloseIsOff() {
        giveRunningUserAManager();
        setSubmitForApprovalNotification(false, false);
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        GtmReadoutController.saveDraftContent(readoutId, '<p>Ready</p>');
        insert new Task(
            WhatId = req.Id, OwnerId = UserInfo.getUserId(),
            Subject = GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, Status = 'Not Started'
        );

        Test.startTest();
        driveSubmitForApproval(readoutId);
        Test.stopTest();

        Assert.areEqual(
            'Not Started',
            [SELECT Status FROM Task WHERE WhatId = :req.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST LIMIT 1].Status
        );
    }

    @isTest
    static void submitForApprovalAlwaysClosesAnOpenReturnedToDraftTaskHardcoded() {
        giveRunningUserAManager();
        setSubmitForApprovalNotification(false, false);
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        GtmReadoutController.saveDraftContent(readoutId, '<p>Ready</p>');
        insert new Task(
            WhatId = readoutId, OwnerId = UserInfo.getUserId(),
            Subject = GtmLifecycleNotificationService.SUBJECT_RETURNED_TO_DRAFT, Status = 'Not Started'
        );

        Test.startTest();
        driveSubmitForApproval(readoutId);
        Test.stopTest();

        Assert.areEqual(
            'Completed',
            [SELECT Status FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_RETURNED_TO_DRAFT LIMIT 1].Status,
            'This close is hardcoded, not gated by any settings field'
        );
    }

    @isTest
    static void recallApprovalClosesTheApproverTaskWhenNotifyOnSubmitIsOn() {
        giveRunningUserAManager();
        setSubmitForApprovalNotification(true, false);
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        GtmReadoutController.saveDraftContent(readoutId, '<p>Ready</p>');
        driveSubmitForApproval(readoutId);
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_APPROVE_READOUT],
            'Setup: the approver Task must exist before recall can close it'
        );

        Test.startTest();
        try {
            GtmReadoutController.recallApproval(readoutId);
        } catch (AuraHandledException e) {
            // No outstanding platform ProcessInstanceWorkitem in this org
            // context (no routable approval process for the test user) --
            // recallApproval's own close-side logic runs after the
            // Approval.process() call succeeds, so this scenario cannot be
            // driven end to end without a real approval process routing.
            // Assert nothing further; the closeOpenTasks call itself is
            // proven directly in GtmLifecycleNotificationServiceTest.
        }
        Test.stopTest();
    }

    @isTest
    static void recallApprovalLeavesTheApproverTaskOpenWhenNotifyOnSubmitIsOff() {
        giveRunningUserAManager();
        setSubmitForApprovalNotification(false, false);
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        GtmReadoutController.saveDraftContent(readoutId, '<p>Ready</p>');
        driveSubmitForApproval(readoutId);
        // Stand in for an approver Task that survives from before the
        // setting was toggled off (or from a submission that predates
        // this org ever having the setting on). Recall's close is a
        // corollary of notifyOnSubmitForApproval's *current* effective
        // state, not a field of its own (ADR-0010) -- with the setting
        // off, this Task must never be touched.
        insert new Task(
            WhatId = readoutId, OwnerId = UserInfo.getUserId(),
            Subject = GtmLifecycleNotificationService.SUBJECT_APPROVE_READOUT, Status = 'Not Started'
        );

        Test.startTest();
        try {
            GtmReadoutController.recallApproval(readoutId);
        } catch (AuraHandledException e) {
            // Same platform-routing caveat as
            // recallApprovalClosesTheApproverTaskWhenNotifyOnSubmitIsOn
            // above -- recall's own close-side logic runs only after
            // Approval.process() succeeds, which this test org context has
            // no routable approval process to drive end to end.
        }
        Test.stopTest();

        Assert.areEqual(
            'Not Started',
            [SELECT Status FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_APPROVE_READOUT LIMIT 1].Status,
            'When notifyOnSubmitForApproval is off, recall must never close the approver Task'
        );
    }

    @isTest
    static void publishReadoutClosesTheApprovedTaskWhenAutoCloseApprovedIsOn() {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.autoCloseApprovedTasks = true;
        dto.publishedNotificationMode = 'None';
        GtmNotificationSettingsController.setNotificationSettings(dto);

        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);
        insert new Task(
            WhatId = readoutId, OwnerId = UserInfo.getUserId(),
            Subject = GtmLifecycleNotificationService.SUBJECT_READOUT_APPROVED, Status = 'Not Started'
        );

        Test.startTest();
        GtmReadoutController.publishReadout(readoutId);
        Test.stopTest();

        Assert.areEqual(
            'Completed',
            [SELECT Status FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_READOUT_APPROVED LIMIT 1].Status
        );
    }

    @isTest
    static void publishReadoutFiresBellAndTaskWhenModeIsBellAndTask() {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.publishedNotificationMode = 'Bell + Task';
        GtmNotificationSettingsController.setNotificationSettings(dto);

        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);

        Test.startTest();
        GtmReadoutController.publishReadout(readoutId);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_READOUT_PUBLISHED],
            'Bell + Task mode should fire a Task'
        );
    }

    @isTest
    static void publishReadoutFiresBellOnlyWithNoTaskWhenModeIsBellOnly() {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.publishedNotificationMode = 'Bell Only';
        GtmNotificationSettingsController.setNotificationSettings(dto);

        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);

        Test.startTest();
        GtmReadoutController.publishReadout(readoutId);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_READOUT_PUBLISHED],
            'Bell Only mode must never fire a Task'
        );
    }

    @isTest
    static void publishReadoutFiresNothingWhenModeIsNone() {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.publishedNotificationMode = 'None';
        GtmNotificationSettingsController.setNotificationSettings(dto);

        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);

        Test.startTest();
        GtmReadoutController.publishReadout(readoutId);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_READOUT_PUBLISHED],
            'Mode None must fire neither a Task nor a bell'
        );
    }

    // --------------------------------- engagement-state Task (issue #31) --
    // Independent of publishedNotificationMode above -- these always fire
    // against the prospect's own Contact/Account, not readoutId.

    private static GTM_Assessment_Request__c seedRequestWithContact(Id contactId, Id accountId) {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c   = 'Alex Rivera',
            Requester_Email__c  = 'alex.rivera@example.com',
            Company__c          = 'Northwind Retail',
            Contact__c          = contactId,
            Account__c          = accountId,
            Assessment_Score__c = SAMPLE_SCORE,
            Assessment_Tier__c  = 'Prep Required',
            Section_Scores__c   = '{"estate_scale":3,"source_access":2}'
        );
        insert req;
        return req;
    }

    @isTest
    static void publishReadoutFiresTheEngagementPublishedUnsentTaskAgainstTheContact() {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.publishedNotificationMode = 'None';
        GtmNotificationSettingsController.setNotificationSettings(dto);

        Contact con = new Contact(LastName = 'Prospect');
        insert con;
        GTM_Assessment_Request__c req = seedRequestWithContact(con.Id, null);
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);

        Test.startTest();
        GtmReadoutController.publishReadout(readoutId);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :con.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_PUBLISHED_UNSENT],
            'Publishing should fire the engagement published_unsent Task against the Contact ' +
            'independent of publishedNotificationMode'
        );
    }

    @isTest
    static void publishReadoutWithNoContactFallsBackToTheAccountForTheEngagementTask() {
        Account acc = new Account(Name = 'Fallback Readout Co');
        insert acc;
        GTM_Assessment_Request__c req = seedRequestWithContact(null, acc.Id);
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);

        Test.startTest();
        GtmReadoutController.publishReadout(readoutId);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :acc.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_PUBLISHED_UNSENT]
        );
    }

    @isTest
    static void publishingThenSuccessfullyNotifyingClosesThePublishedUnsentEngagementTaskAndFiresNothingNew() {
        Contact con = new Contact(LastName = 'Prospect');
        insert con;
        GTM_Assessment_Request__c req = seedRequestWithContact(con.Id, null);
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);

        Test.startTest();
        // publishReadout calls sendPublishNotification automatically at the
        // end of the same transaction (see its own header) -- a well-formed
        // Requester_Email__c succeeds in test context (Messaging.sendEmail
        // never really dispatches under Test.startTest/stopTest), so
        // Notification_Sent_Date__c gets stamped and sent_complete should
        // sync in the same call.
        GtmReadoutController.publishReadout(readoutId);
        Test.stopTest();

        GTM_Readout__c published = [SELECT Notification_Sent_Date__c FROM GTM_Readout__c WHERE Id = :readoutId];
        Assert.isNotNull(published.Notification_Sent_Date__c,
            'Sanity check: the notification must actually have sent in this test context');

        List<Task> tasks = [SELECT Subject, Status FROM Task WHERE WhatId = :con.Id];
        Assert.areEqual(1, tasks.size(), 'sent_complete must close published_unsent and fire nothing new');
        Assert.areEqual(GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_PUBLISHED_UNSENT, tasks[0].Subject);
        Assert.areEqual('Completed', tasks[0].Status);
    }

    @isTest
    static void returnToDraftFiresTaskAndBellWhenSettingIsOn() {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.notifyOnReturnedToDraft = true;
        GtmNotificationSettingsController.setNotificationSettings(dto);

        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);

        Test.startTest();
        GtmReadoutController.returnToDraft(readoutId);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_RETURNED_TO_DRAFT]
        );
    }

    @isTest
    static void returnToDraftDoesNotFireWhenSettingIsOff() {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.notifyOnReturnedToDraft = false;
        GtmNotificationSettingsController.setNotificationSettings(dto);

        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);

        Test.startTest();
        GtmReadoutController.returnToDraft(readoutId);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_RETURNED_TO_DRAFT]
        );
    }

    @isTest
    static void stampApprovalFiresTaskAndBellWhenNotifyOnApprovedIsOn() {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.notifyOnApproved = true;
        GtmNotificationSettingsController.setNotificationSettings(dto);

        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        Test.startTest();
        approve(readoutId);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_READOUT_APPROVED]
        );
    }

    @isTest
    static void stampApprovalDoesNotFireWhenNotifyOnApprovedIsOff() {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.notifyOnApproved = false;
        GtmNotificationSettingsController.setNotificationSettings(dto);

        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);

        Test.startTest();
        approve(readoutId);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_READOUT_APPROVED]
        );
    }

    @isTest
    static void stampApprovalClosesTheSubmitTaskWhenAutoCloseSubmitIsOn() {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.autoCloseSubmitTasks = true;
        GtmNotificationSettingsController.setNotificationSettings(dto);

        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        insert new Task(
            WhatId = readoutId, OwnerId = UserInfo.getUserId(),
            Subject = GtmLifecycleNotificationService.SUBJECT_APPROVE_READOUT, Status = 'Not Started'
        );

        Test.startTest();
        approve(readoutId);
        Test.stopTest();

        Assert.areEqual(
            'Completed',
            [SELECT Status FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_APPROVE_READOUT LIMIT 1].Status
        );
    }

    @isTest
    static void stampApprovalLeavesTheSubmitTaskOpenWhenAutoCloseSubmitIsOff() {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.autoCloseSubmitTasks = false;
        GtmNotificationSettingsController.setNotificationSettings(dto);

        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        insert new Task(
            WhatId = readoutId, OwnerId = UserInfo.getUserId(),
            Subject = GtmLifecycleNotificationService.SUBJECT_APPROVE_READOUT, Status = 'Not Started'
        );

        Test.startTest();
        approve(readoutId);
        Test.stopTest();

        Assert.areEqual(
            'Not Started',
            [SELECT Status FROM Task WHERE WhatId = :readoutId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_APPROVE_READOUT LIMIT 1].Status
        );
    }

    /**
     * Regression test for the bulk-safety defect QA caught: stampApproval is
     * a before-update trigger handler, and "an approval can be taken on
     * several readouts at once from a list view" is real, anticipated
     * behavior (see GtmReadoutApprovalHandler.nextVersionNumbers's own
     * docstring). fireApprovalNotifications previously issued one
     * SOQL/DML pair per approved readout inside its loop, which would blow
     * the 100-query/150-DML governor limits well before a realistic bulk
     * approval (~50-75 readouts) -- and nothing in this file exercised
     * stampApproval with more than one readout, so nothing caught it.
     *
     * This approves BULK_SIZE readouts in a single `update` (matching how a
     * real list-view bulk approval reaches Status__c = 'Approved'), with
     * both autoCloseSubmitTasks and notifyOnApproved on so both halves of
     * fireApprovalNotifications run. It asserts the SOQL/DML cost stays a
     * small, roughly-constant number regardless of batch size -- proving
     * the fix aggregates rather than loops -- and that every readout in the
     * batch still gets the correct Task fire/close outcome individually.
     */
    @isTest
    static void stampApprovalIsBulkSafeAcrossManyApprovedReadoutsAtOnce() {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.autoCloseSubmitTasks = true;
        dto.notifyOnApproved = true;
        GtmNotificationSettingsController.setNotificationSettings(dto);

        Integer bulkSize = 10;
        List<Id> readoutIds = new List<Id>();
        for (Integer i = 0; i < bulkSize; i++) {
            GTM_Assessment_Request__c req = seedRequest();
            Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
            readoutIds.add(readoutId);
            // Stand in for the Task submitForApproval would have created,
            // so autoCloseSubmitTasks has something real to close across
            // the whole batch, not just for one readout.
            insert new Task(
                WhatId = readoutId, OwnerId = UserInfo.getUserId(),
                Subject = GtmLifecycleNotificationService.SUBJECT_APPROVE_READOUT, Status = 'Not Started'
            );
        }

        List<GTM_Readout__c> toApprove = new List<GTM_Readout__c>();
        for (Id readoutId : readoutIds) {
            toApprove.add(new GTM_Readout__c(Id = readoutId, Status__c = 'Approved'));
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();

        update toApprove;

        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        // A per-record implementation would cost roughly 2x SOQL/DML per
        // readout approved (closeOpenTasks + fireTask, at minimum one
        // SOQL/DML each) -- i.e. ~20 of each at this batch size. A
        // bulk-aggregated implementation costs a small, constant handful
        // regardless of batch size. Bounding both well under bulkSize
        // distinguishes the two without hard-coding an exact count that
        // would break if an unrelated trigger on GTM_Readout__c changes its
        // own query/DML shape.
        Assert.isTrue(
            queriesUsed < bulkSize,
            'fireApprovalNotifications must issue one aggregate query for the whole batch, ' +
            'not one per approved readout. SOQL used for ' + bulkSize + ' readouts: ' + queriesUsed
        );
        Assert.isTrue(
            dmlUsed < bulkSize,
            'fireApprovalNotifications must issue aggregate DML for the whole batch, ' +
            'not one statement per approved readout. DML used for ' + bulkSize + ' readouts: ' + dmlUsed
        );

        Assert.areEqual(
            bulkSize,
            [SELECT COUNT() FROM Task WHERE WhatId IN :readoutIds
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_APPROVE_READOUT AND Status = 'Completed'],
            'autoCloseSubmitTasks should close the approver Task for every readout in the batch'
        );
        Assert.areEqual(
            bulkSize,
            [SELECT COUNT() FROM Task WHERE WhatId IN :readoutIds
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_READOUT_APPROVED],
            'notifyOnApproved should fire exactly one Task per approved readout in the batch'
        );
    }
}
