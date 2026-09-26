/**
 * Pure unit tests for GtmEngagementStateClassifier.classify() and its
 * companion state maps -- extracted out of
 * GtmContactEngagementControllerTest (issue #31, Architect decision #3).
 * No SOQL/DML/Contact/GTM_Saved_Configuration__c fixtures needed at all:
 * classify() takes plain signal values and returns a state key, so every
 * test here calls it directly rather than round-tripping through
 * getEngagementSummaries. GtmContactEngagementControllerTest's own tests
 * (scope/pagination/role-hierarchy behavior classify() knows nothing about)
 * exercised only that now-deleted method -- once getEngagementSummaries and
 * its controller were deleted in issue #31's teardown phase, nothing in that
 * test class had a remaining reason to exist, so the whole class was deleted
 * alongside it rather than left behind as dead test code.
 */
@IsTest
private class GtmEngagementStateClassifierTest {

    // ── one test per state, the simplest signal combination that reaches it ──

    @IsTest
    static void submittedWithNoReadoutIsSubmittedDraft() {
        String state = GtmEngagementStateClassifier.classify(true, null, null, false, null);
        Assert.areEqual(GtmEngagementStateClassifier.STATE_SUBMITTED_DRAFT, state);
    }

    @IsTest
    static void submittedWithADraftReadoutIsStillSubmittedDraft() {
        String state = GtmEngagementStateClassifier.classify(true, 'Draft', false, false, null);
        Assert.areEqual(GtmEngagementStateClassifier.STATE_SUBMITTED_DRAFT, state);
    }

    @IsTest
    static void submittedWithAnApprovedReadoutIsStillSubmittedDraft() {
        String state = GtmEngagementStateClassifier.classify(true, 'Approved', false, false, null);
        Assert.areEqual(GtmEngagementStateClassifier.STATE_SUBMITTED_DRAFT, state,
            'submitted_draft covers everything up to (not including) Published, not just literal Draft');
    }

    @IsTest
    static void publishedAndNotYetNotifiedIsPublishedUnsent() {
        String state = GtmEngagementStateClassifier.classify(true, 'Published', false, false, null);
        Assert.areEqual(GtmEngagementStateClassifier.STATE_PUBLISHED_UNSENT, state);
    }

    @IsTest
    static void publishedAndNotifiedIsSentComplete() {
        String state = GtmEngagementStateClassifier.classify(true, 'Published', true, false, null);
        Assert.areEqual(GtmEngagementStateClassifier.STATE_SENT_COMPLETE, state);
    }

    @IsTest
    static void notSubmittedWithFormOpenedIsStartedNotSubmitted() {
        String state = GtmEngagementStateClassifier.classify(false, null, null, true, null);
        Assert.areEqual(GtmEngagementStateClassifier.STATE_STARTED, state);
    }

    @IsTest
    static void notSubmittedWithOnlyAPageViewIsOpenedNotStarted() {
        String state = GtmEngagementStateClassifier.classify(false, null, null, false, DateTime.now());
        Assert.areEqual(GtmEngagementStateClassifier.STATE_OPENED, state);
    }

    @IsTest
    static void noSignalsAtAllIsNeverOpened() {
        String state = GtmEngagementStateClassifier.classify(false, null, null, false, null);
        Assert.areEqual(GtmEngagementStateClassifier.STATE_NEVER_OPENED, state);
    }

    // ── boundary case: a readout row exists but the request was never really submitted ──

    @IsTest
    static void readoutWithoutSubmittedIsNotTreatedAsSubmitted() {
        // Stale/synthetic data: a readout with a real Status__c exists, but
        // assessmentSubmitted is false (Submitted_At__c was never actually
        // set) -- must fall through to the engagement-signal branches like
        // any other not-yet-submitted link, not be treated as submitted_draft
        // just because a readout row happens to exist (D7).
        String state = GtmEngagementStateClassifier.classify(false, 'Draft', false, false, null);
        Assert.areEqual(GtmEngagementStateClassifier.STATE_NEVER_OPENED, state);
    }

    // ── null-safety: a bare Boolean/String param never NPEs, never miscounts ──

    @IsTest
    static void nullAssessmentSubmittedIsTreatedAsNotSubmitted() {
        String state = GtmEngagementStateClassifier.classify(null, null, null, null, null);
        Assert.areEqual(GtmEngagementStateClassifier.STATE_NEVER_OPENED, state);
    }

    @IsTest
    static void nullNotificationSentOnAPublishedReadoutIsTreatedAsNotYetSent() {
        String state = GtmEngagementStateClassifier.classify(true, 'Published', null, false, null);
        Assert.areEqual(GtmEngagementStateClassifier.STATE_PUBLISHED_UNSENT, state);
    }

    // ── re-invocation with changed signals re-classifies, proving no hidden state ──

    @IsTest
    static void reclassifyingWithAFreshFormOpenedSignalMovesFromOpenedToStarted() {
        String before = GtmEngagementStateClassifier.classify(false, null, null, false, DateTime.now());
        Assert.areEqual(GtmEngagementStateClassifier.STATE_OPENED, before);

        String after = GtmEngagementStateClassifier.classify(false, null, null, true, DateTime.now());
        Assert.areEqual(GtmEngagementStateClassifier.STATE_STARTED, after,
            'classify() is a pure function -- an unrelated call with the earlier signals must not leak into this one');
    }

    // ── D13 rank order, and every state/action/label map is complete ──

    @IsTest
    static void allSixStatesRankInD13Order() {
        Map<String, Integer> expectedRank = new Map<String, Integer>{
            GtmEngagementStateClassifier.STATE_SUBMITTED_DRAFT  => 1,
            GtmEngagementStateClassifier.STATE_PUBLISHED_UNSENT => 2,
            GtmEngagementStateClassifier.STATE_STARTED          => 3,
            GtmEngagementStateClassifier.STATE_OPENED           => 4,
            GtmEngagementStateClassifier.STATE_NEVER_OPENED     => 5,
            GtmEngagementStateClassifier.STATE_SENT_COMPLETE    => 6
        };
        for (String state : expectedRank.keySet()) {
            Assert.areEqual(expectedRank.get(state), GtmEngagementStateClassifier.STATE_RANK.get(state),
                'Rank mismatch for ' + state);
        }
    }

    @IsTest
    static void stateLabelIsNeverBlankForAnyOfTheSixStates() {
        for (String state : GtmEngagementStateClassifier.STATE_RANK.keySet()) {
            String label = GtmEngagementStateClassifier.STATE_LABEL.get(state);
            Assert.isNotNull(label, 'stateLabel must be populated for ' + state);
            Assert.isTrue(String.isNotBlank(label), 'stateLabel must not be blank for ' + state);
            Assert.areNotEqual(state, label,
                'stateLabel must never equal the raw state enum -- that is exactly the bug this fixes');
        }
    }

    @IsTest
    static void primaryActionAndLabelAreNeverBlankForAnyOfTheSixStates() {
        for (String state : GtmEngagementStateClassifier.STATE_RANK.keySet()) {
            String action = GtmEngagementStateClassifier.STATE_ACTION.get(state);
            String actionLabel = GtmEngagementStateClassifier.STATE_ACTION_LABEL.get(state);
            Assert.isTrue(String.isNotBlank(action), 'primaryAction must not be blank for ' + state);
            Assert.isTrue(String.isNotBlank(actionLabel), 'primaryActionLabel must not be blank for ' + state);
        }
    }
}
