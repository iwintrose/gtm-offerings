/**
 * Pure, side-effect-free classification of an engagement link's D8/D13
 * six-state precedence (issue-102-1-engagement-links-landing's original
 * design, carried forward by issue #31). Extracted out of
 * GtmContactEngagementController (issue #31, Architect decision #3): that
 * class's only @AuraEnabled method, getEngagementSummaries, is scoped to
 * the now-retiring "Engagement Links" tab, but classify()'s state machine
 * is the single source of truth several other classes need to call
 * Apex-to-Apex to decide when to fire/close the real Task issue #31 adds to
 * the Account/Contact Activity timeline
 * (GtmLifecycleNotificationService.syncEngagementStateTask).
 *
 * No `with sharing`/`without sharing` declaration: this class does no
 * SOQL/DML at all (issue #31 Architect decision #3) -- every signal it
 * needs is passed in by the caller, who is responsible for resolving it
 * under whatever sharing context that caller already runs in. Because of
 * that, this class also needs no `classAccesses` permission-set grant
 * (decision #3): classAccesses gates client/declarative entry points
 * (Aura/LWC @AuraEnabled calls, REST, invocable actions, scheduled jobs),
 * not internal same-transaction static-method calls, and nothing here is
 * any of those.
 */
public class GtmEngagementStateClassifier {

    // ---------------------------------------------------- D8 + D13 states
    public static final String STATE_SUBMITTED_DRAFT  = 'submitted_draft';
    public static final String STATE_PUBLISHED_UNSENT = 'published_unsent';
    public static final String STATE_STARTED          = 'started_not_submitted';
    public static final String STATE_OPENED           = 'opened_not_started';
    public static final String STATE_NEVER_OPENED     = 'never_opened';
    public static final String STATE_SENT_COMPLETE    = 'sent_complete';

    /** Highest priority first -- exactly D13's six-tier order. */
    public static final Map<String, Integer> STATE_RANK = new Map<String, Integer>{
        STATE_SUBMITTED_DRAFT  => 1,
        STATE_PUBLISHED_UNSENT => 2,
        STATE_STARTED          => 3,
        STATE_OPENED           => 4,
        STATE_NEVER_OPENED     => 5,
        STATE_SENT_COMPLETE    => 6
    };

    /** One primary action key per state -- callers switch on this, never
     *  re-derive state from raw fields (D13's own mandate). */
    public static final Map<String, String> STATE_ACTION = new Map<String, String>{
        STATE_SUBMITTED_DRAFT  => 'open_readout',
        STATE_PUBLISHED_UNSENT => 'send_disabled',
        STATE_STARTED          => 'follow_up',
        STATE_OPENED           => 'follow_up',
        STATE_NEVER_OPENED     => 'resend',
        STATE_SENT_COMPLETE    => 'none'
    };

    public static final Map<String, String> STATE_ACTION_LABEL = new Map<String, String>{
        STATE_SUBMITTED_DRAFT  => 'Open the readout',
        STATE_PUBLISHED_UNSENT => 'Send to prospect',
        STATE_STARTED          => 'Follow up',
        STATE_OPENED           => 'Follow up',
        STATE_NEVER_OPENED     => 'Resend',
        STATE_SENT_COMPLETE    => '—'
    };

    /**
     * Human-readable state labels -- names WHO is blocking / WHY the row is
     * ranked where it is, not just a friendlier name for the same opaque
     * code:
     *   - submitted_draft / published_unsent (D13 ranks 1-2): the BD is the
     *     blocker -- "Your turn -- ...".
     *   - started_not_submitted / opened_not_started (ranks 3-4): the
     *     prospect is mid-flow and a nudge is the right lever -- "Nudge-able
     *     -- ...".
     *   - never_opened (rank 5) / sent_complete (rank 6): no action is
     *     blocked on anyone right now.
     */
    public static final Map<String, String> STATE_LABEL = new Map<String, String>{
        STATE_SUBMITTED_DRAFT  => 'Your turn — open the readout',
        STATE_PUBLISHED_UNSENT => 'Your turn — send to prospect',
        STATE_STARTED          => 'Nudge-able — they started, haven\'t finished',
        STATE_OPENED           => 'Nudge-able — they opened, haven\'t started',
        STATE_NEVER_OPENED     => 'Not yet opened',
        STATE_SENT_COMPLETE    => 'Complete'
    };

    /**
     * D8 + D13's six states, in priority order. Every signal here already
     * exists somewhere in the schema (Submitted_At__c, GTM_Link_Event__c.
     * Event_Type__c, GTM_Readout__c.Status__c / Notification_Sent_Date__c);
     * this method just doesn't do the SOQL to fetch it -- that is entirely
     * the caller's job, so this stays a pure function callable from any
     * sharing context (with sharing, without sharing, guest) without this
     * class itself needing an opinion about any of them.
     *
     * Null-safe on every Boolean parameter (`== true`/`!= true` rather than
     * bare truthiness) -- a strict superset of the original inline
     * GtmContactEngagementController.classify()'s guarantees, not a
     * behavior change for any caller that (like that original) always
     * passes real, non-null booleans.
     *
     * Boundary case: a readout that exists but whose request has no
     * Submitted_At__c (e.g. stale/synthetic data) is NOT treated as
     * "submitted" just because a readout row exists -- it falls through to
     * the engagement-signal branches like any other not-yet-submitted link,
     * since a readout only really exists once a request is genuinely
     * submitted (D7).
     *
     * @param assessmentSubmitted The request's Submitted_At__c is set.
     * @param readoutStatus       The most recent readout's Status__c, or
     *                            null when no readout exists yet.
     * @param notificationSent    The most recent readout's
     *                            Notification_Sent_Date__c is set.
     * @param formOpened          Any GTM_Link_Event__c with
     *                            Event_Type__c = 'Form Opened' exists.
     * @param lastPageView        Non-null when any GTM_Link_Event__c with
     *                            Event_Type__c = 'Page View' exists (the
     *                            actual timestamp value is not consulted,
     *                            only null-ness).
     */
    public static String classify(
        Boolean assessmentSubmitted, String readoutStatus, Boolean notificationSent,
        Boolean formOpened, DateTime lastPageView
    ) {
        if (assessmentSubmitted == true && readoutStatus != 'Published') {
            return STATE_SUBMITTED_DRAFT;
        }
        if (readoutStatus == 'Published' && notificationSent != true) {
            return STATE_PUBLISHED_UNSENT;
        }
        if (readoutStatus == 'Published' && notificationSent == true) {
            return STATE_SENT_COMPLETE;
        }
        if (assessmentSubmitted != true && formOpened == true) {
            return STATE_STARTED;
        }
        if (assessmentSubmitted != true && lastPageView != null) {
            return STATE_OPENED;
        }
        return STATE_NEVER_OPENED;
    }
}
