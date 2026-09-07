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

    // --------------------------------------------------------------- listing

    @isTest
    static void getReadoutsForReviewReturnsDraftAndApprovedOnly() {
        GTM_Assessment_Request__c reqDraft = seedRequest();
        Id draftId = GtmReadoutController.generateDraftReadout(reqDraft.Id);

        GTM_Assessment_Request__c reqApproved = seedRequest();
        Id approvedId = GtmReadoutController.generateDraftReadout(reqApproved.Id);
        approve(approvedId);

        GTM_Assessment_Request__c reqPublished = seedRequest();
        Id publishedId = GtmReadoutController.generateDraftReadout(reqPublished.Id);
        approve(publishedId);
        GtmReadoutController.publishReadout(publishedId);

        Test.startTest();
        List<GtmReadoutController.ReadoutSummary> rows = GtmReadoutController.getReadoutsForReview();
        Test.stopTest();

        Set<String> ids = new Set<String>();
        for (GtmReadoutController.ReadoutSummary s : rows) { ids.add(s.id); }

        Assert.isTrue(ids.contains(draftId), 'Draft readouts should be listed');
        Assert.isTrue(ids.contains(approvedId), 'Approved readouts should be listed');
        Assert.isFalse(ids.contains(publishedId), 'Published readouts should drop off this list');
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
    static void aReadoutWaitingOnApprovalStillAppearsInTheRepQueue() {
        GTM_Assessment_Request__c req = seedRequest();
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        update new GTM_Readout__c(Id = readoutId, Status__c = 'Pending Approval');

        Test.startTest();
        List<GtmReadoutController.ReadoutSummary> rows = GtmReadoutController.getReadoutsForReview();
        Test.stopTest();

        Set<String> listed = new Set<String>();
        for (GtmReadoutController.ReadoutSummary s : rows) {
            listed.add(s.id);
        }
        Assert.isTrue(
            listed.contains(String.valueOf(readoutId)),
            'A readout waiting on an approver is still the rep\'s to chase, so it stays in the list'
        );
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

    @isTest
    static void repFacingQueryReturnsOnlyTheOwningRepsReadouts() {
        // The point of the Private model: getReadoutsForReview runs
        // `with sharing`, so a rep sees the readouts they own and nothing else.
        User owningRep = createRep('gtmow1');
        User otherRep  = createRep('gtmot1');

        GTM_Assessment_Request__c req = seedRequest();
        req.OwnerId = owningRep.Id;
        update req;
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        Assert.areEqual(owningRep.Id, ownerOf(readoutId));

        Test.startTest();
        List<GtmReadoutController.ReadoutSummary> mine;
        System.runAs(owningRep) {
            mine = GtmReadoutController.getReadoutsForReview();
        }
        List<GtmReadoutController.ReadoutSummary> theirs;
        System.runAs(otherRep) {
            theirs = GtmReadoutController.getReadoutsForReview();
        }
        Test.stopTest();

        Set<String> mineIds = new Set<String>();
        for (GtmReadoutController.ReadoutSummary s : mine) {
            mineIds.add(s.id);
        }
        Assert.isTrue(
            mineIds.contains(String.valueOf(readoutId)),
            'The owning rep must see their own readout for review'
        );

        for (GtmReadoutController.ReadoutSummary s : theirs) {
            Assert.areNotEqual(
                String.valueOf(readoutId),
                s.id,
                'A rep who does not own the readout must not see it'
            );
        }
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
}
