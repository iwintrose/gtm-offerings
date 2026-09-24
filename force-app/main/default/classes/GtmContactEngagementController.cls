/**
 * Backing controller for two callers of the same "one row = one engagement
 * link" data (issue-102-1-engagement-links-landing):
 *
 *  1. The Contact record page widget (gtmContactEngagement mounted with
 *     recordId = a Contact Id) -- every link for that one contact.
 *  2. The "Engagement Links" landing tab (gtmContactEngagement mounted with
 *     no recordId) -- a BD's queue of links across contacts, scoped by
 *     [My links | My team | All] (stakeholder decision D6, default "My
 *     links"), ranked by who is blocking (D13), grouped for display by
 *     contact (D8).
 *
 * One method, getEngagementSummaries, serves both -- generalized rather than
 * forked, per the task-scope's own hard boundary. contactId/accountId (when
 * supplied by either the Contact record page or a drill-in from gtmOverview's
 * Account/Contact click-through) narrow the audience and scope is ignored;
 * with neither supplied, scope drives the WHERE clause.
 *
 * Ranking is computed here, not client-side (D13's own "Data implication" --
 * sorting and paging break if state is computed per-row in the client). The
 * six states below are exactly D8/D13's table; "state" is returned as a key,
 * "primaryAction" as an action key the LWC switches on, and
 * "primaryActionLabel" as the exact button copy so the client does not have
 * to duplicate the label mapping.
 *
 * "Sent to prospect" (row state 2, "Published but not sent") intentionally
 * renders disabled with a tooltip rather than routing anywhere real: 102-3
 * (the ticket that builds a standalone Send action) has not shipped, and
 * GtmReadoutController.publishReadout already fires the prospect
 * notification automatically as part of publishing
 * (sendPublishNotification) -- so this state is the narrow "auto-send
 * failed or is still in flight" case, not a routine manual step today. This
 * is intentionally the more conservative of the two options the task
 * description allowed ("route ... or show it disabled with a tooltip");
 * flagged back to the coordinator/Architect for confirmation once 102-3 is
 * scoped, per this ticket's own instruction to confirm which.
 *
 * `with sharing`, FLS-safe (WITH SECURITY_ENFORCED), scope-gated the same
 * way GtmAssessmentListController/GtmHomeSnapshotController already do: an
 * explicit OwnerId backstop on top of `with sharing`, "all" gated behind
 * viewAllRecords on the object (private copy of the established
 * hasViewAllRecords probe -- "a third private copy is accepted to keep this
 * issue small", same call GtmAssessmentListController's own comment makes).
 * "team" is the running user's role plus every role under it in the
 * standard Role Hierarchy (User.ManagerId is NOT used -- role hierarchy is
 * the native Salesforce "my team" concept behind reports' own "My team's"
 * filters, and needs no new field). No DML, no callouts.
 */
public with sharing class GtmContactEngagementController {

    private static final Integer DEFAULT_PAGE_SIZE = 25;
    private static final Integer MAX_PAGE_SIZE = 100;
    /** Governor-safety ceiling on the candidate query -- paired with
     *  `truncated` on the result so this is never the silent, uncounted
     *  LIMIT 200/500 pattern getDeals()/getAllReadouts() have. */
    @TestVisible private static Integer candidateCeiling = 2000;
    /** Bound on the Role Hierarchy BFS below -- any real org's role tree is
     *  far shallower than this; it exists purely as a runaway-loop guard. */
    private static final Integer MAX_ROLE_DEPTH = 10;

    private static final String SCOPE_MINE = 'mine';
    private static final String SCOPE_TEAM = 'team';
    private static final String SCOPE_ALL  = 'all';

    // ---------------------------------------------------- D8 + D13 states
    @TestVisible private static final String STATE_SUBMITTED_DRAFT  = 'submitted_draft';
    @TestVisible private static final String STATE_PUBLISHED_UNSENT = 'published_unsent';
    @TestVisible private static final String STATE_STARTED          = 'started_not_submitted';
    @TestVisible private static final String STATE_OPENED           = 'opened_not_started';
    @TestVisible private static final String STATE_NEVER_OPENED     = 'never_opened';
    @TestVisible private static final String STATE_SENT_COMPLETE    = 'sent_complete';

    /** Highest priority first -- exactly D13's six-tier order. */
    private static final Map<String, Integer> STATE_RANK = new Map<String, Integer>{
        STATE_SUBMITTED_DRAFT  => 1,
        STATE_PUBLISHED_UNSENT => 2,
        STATE_STARTED          => 3,
        STATE_OPENED           => 4,
        STATE_NEVER_OPENED     => 5,
        STATE_SENT_COMPLETE    => 6
    };

    /** One primary action key per state -- the LWC switches on this, it
     *  never re-derives state from raw fields (D13's own mandate). */
    private static final Map<String, String> STATE_ACTION = new Map<String, String>{
        STATE_SUBMITTED_DRAFT  => 'open_readout',
        STATE_PUBLISHED_UNSENT => 'send_disabled',
        STATE_STARTED          => 'follow_up',
        STATE_OPENED           => 'follow_up',
        STATE_NEVER_OPENED     => 'resend',
        STATE_SENT_COMPLETE    => 'none'
    };

    private static final Map<String, String> STATE_ACTION_LABEL = new Map<String, String>{
        STATE_SUBMITTED_DRAFT  => 'Open the readout',
        STATE_PUBLISHED_UNSENT => 'Send to prospect',
        STATE_STARTED          => 'Follow up',
        STATE_OPENED           => 'Follow up',
        STATE_NEVER_OPENED     => 'Resend',
        STATE_SENT_COMPLETE    => '—'
    };

    /**
     * Human-readable state labels (owner feedback on this ticket's first
     * build: the raw enum strings -- "submitted_draft", "published_unsent",
     * etc. -- were rendered directly in the queue row, so "the priority is
     * hidden and unclear"). Each label names WHO is blocking / WHY the row
     * is ranked where it is, not just a friendlier name for the same opaque
     * code -- that's what makes D13's rank order legible instead of an
     * invisible sort:
     *   - submitted_draft / published_unsent (D13 ranks 1-2): the BD is the
     *     blocker -- "Your turn -- ...".
     *   - started_not_submitted / opened_not_started (ranks 3-4): the
     *     prospect is mid-flow and a nudge is the right lever -- "Nudge-able
     *     -- ...".
     *   - never_opened (rank 5) / sent_complete (rank 6): no action is
     *     blocked on anyone right now.
     * Additive only -- STATE_* enum values above are unchanged (tests/
     * ranking logic depend on them); this is purely a display label
     * alongside `state`, computed here since classify() already owns the
     * state logic (task-scope's own suggestion, confirmed the cleaner
     * option -- one source of truth for state -> copy, same as
     * STATE_ACTION_LABEL above).
     */
    private static final Map<String, String> STATE_LABEL = new Map<String, String>{
        STATE_SUBMITTED_DRAFT  => 'Your turn — open the readout',
        STATE_PUBLISHED_UNSENT => 'Your turn — send to prospect',
        STATE_STARTED          => 'Nudge-able — they started, haven\'t finished',
        STATE_OPENED           => 'Nudge-able — they opened, haven\'t started',
        STATE_NEVER_OPENED     => 'Not yet opened',
        STATE_SENT_COMPLETE    => 'Complete'
    };

    public class LinkEngagementSummary {
        /** GTM_Assessment_Request__c Id when one exists, else null -- what a
         *  row's link click navigates to (gtmAssessmentDetail). DTO-only
         *  addition, not a database field (task-scope §2). */
        @AuraEnabled public Id       recordId;
        /** GTM_Saved_Configuration__c Id -- every row has one (one row per
         *  link). Used to open the engagement link itself (Pages view) for
         *  states with no assessment request yet (follow_up/resend/never
         *  opened all precede request creation -- a request/readout is only
         *  created at submit time, see D7). */
        @AuraEnabled public Id       linkId;
        @AuraEnabled public String   linkName;
        @AuraEnabled public String   company;
        @AuraEnabled public String   offering;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public Boolean  active;
        @AuraEnabled public DateTime lastPageView;
        @AuraEnabled public Boolean  assessmentSubmitted;
        @AuraEnabled public DateTime assessmentSubmittedAt;
        /** Kept for backward compatibility with any existing caller: true
         *  once the readout is Published. Prefer readoutStatus/
         *  notificationSent/state for anything new -- this flag alone
         *  cannot distinguish "published, not yet sent" from "sent". */
        @AuraEnabled public Boolean  readoutSent;
        @AuraEnabled public Id       contactId;
        @AuraEnabled public String   contactName;
        @AuraEnabled public Id       accountId;
        @AuraEnabled public Id       readoutId;
        @AuraEnabled public String   readoutStatus;
        @AuraEnabled public Boolean  notificationSent;
        @AuraEnabled public Boolean  formOpened;
        @AuraEnabled public DateTime lastActivityAt;
        @AuraEnabled public String   state;
        /** Human-readable, "who's blocking" framing of `state` (see
         *  STATE_LABEL above) -- what the row actually renders; `state`
         *  itself stays the raw enum for tests/ranking/data-* hooks. DTO-only
         *  addition, additive, does not change `state`'s values. */
        @AuraEnabled public String   stateLabel;
        @AuraEnabled public Integer  rank;
        @AuraEnabled public String   primaryAction;
        @AuraEnabled public String   primaryActionLabel;
    }

    public class EngagementQueueResult {
        @AuraEnabled public List<LinkEngagementSummary> items = new List<LinkEngagementSummary>();
        @AuraEnabled public Integer totalCount = 0;
        @AuraEnabled public Boolean truncated = false;
    }

    /**
     * @param contactId  Optional. When set, every link for that one contact
     *                   (Contact record page mount, or a drill-in from
     *                   gtmOverview's handleContactClick); scopeKey ignored.
     * @param accountId  Optional. When contactId is null and this is set,
     *                   every link for that account (gtmOverview's
     *                   handleAccountClick drill-in); scopeKey ignored.
     * @param scopeKey   'mine' (default) | 'team' | 'all'. Only consulted
     *                   when both contactId and accountId are null (the
     *                   landing tab's own [My links | My team | All]
     *                   toggle, D6). An 'all' request from a user without
     *                   viewAllRecords on GTM_Saved_Configuration__c falls
     *                   back to 'mine' rather than throwing -- the same
     *                   fail-closed shape GtmAssessmentListController's
     *                   scope check uses.
     * @param pageNumber 1-based. Defaults to 1.
     * @param pageSize   Defaults to 25, capped at 100.
     */
    @AuraEnabled(cacheable=false)
    public static EngagementQueueResult getEngagementSummaries(
        Id contactId, Id accountId, String scopeKey, Integer pageNumber, Integer pageSize
    ) {
        EngagementQueueResult result = new EngagementQueueResult();

        Integer size = (pageSize == null || pageSize < 1) ? DEFAULT_PAGE_SIZE : Math.min(pageSize, MAX_PAGE_SIZE);
        Integer pageIdx = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
        Integer startIdx = (pageIdx - 1) * size;

        // Bind locals for the dynamic SOQL below -- Database.query resolves
        // ":name" against locals in THIS method, not in a helper, so every
        // name the WHERE clause can reference must be declared here even
        // when a given call ends up not using it.
        Id me = UserInfo.getUserId();
        Set<Id> teamUserIds = new Set<Id>();

        List<String> conds = new List<String>();
        if (contactId != null) {
            conds.add('Contact__c = :contactId');
        } else if (accountId != null) {
            conds.add('Account__c = :accountId');
        } else {
            String effectiveScope = normalizeScope(scopeKey);
            if (effectiveScope == SCOPE_ALL && hasViewAllRecords('GTM_Saved_Configuration__c')) {
                // No owner restriction -- org-wide.
            } else if (effectiveScope == SCOPE_TEAM) {
                teamUserIds = teamMemberIds(me);
                conds.add('OwnerId IN :teamUserIds');
            } else {
                conds.add('OwnerId = :me');
            }
        }

        String soql = 'SELECT Id, Name, Company__c, CreatedDate, Active__c, Offering__c, ' +
            'Contact__c, Contact__r.Name, Account__c, ' +
            '(SELECT Event_Type__c, CreatedDate FROM GTM_Link_Events__r ORDER BY CreatedDate DESC), ' +
            '(SELECT Id, Submitted_At__c FROM GTM_Assessment_Requests__r ORDER BY CreatedDate DESC LIMIT 1) ' +
            'FROM GTM_Saved_Configuration__c';
        if (!conds.isEmpty()) {
            soql += ' WHERE ' + String.join(conds, ' AND ');
        }
        soql += ' WITH SECURITY_ENFORCED ORDER BY CreatedDate DESC LIMIT ' + candidateCeiling;

        List<GTM_Saved_Configuration__c> configs = (List<GTM_Saved_Configuration__c>) Database.query(soql);
        if (configs.isEmpty()) {
            return result;
        }

        Set<Id> requestIds = new Set<Id>();
        for (GTM_Saved_Configuration__c cfg : configs) {
            for (GTM_Assessment_Request__c req : cfg.GTM_Assessment_Requests__r) {
                requestIds.add(req.Id);
            }
        }

        Map<Id, GTM_Readout__c> readoutByRequest = new Map<Id, GTM_Readout__c>();
        if (!requestIds.isEmpty()) {
            for (GTM_Readout__c ro : [
                SELECT Id, Status__c, Notification_Sent_Date__c, Assessment_Request__c
                FROM GTM_Readout__c
                WHERE Assessment_Request__c IN :requestIds
                WITH SECURITY_ENFORCED
            ]) {
                readoutByRequest.put(ro.Assessment_Request__c, ro);
            }
        }

        List<LinkEngagementSummary> all = new List<LinkEngagementSummary>();
        for (GTM_Saved_Configuration__c cfg : configs) {
            all.add(toSummary(cfg, readoutByRequest));
        }
        all.sort(new ByRankThenActivity());

        result.totalCount = all.size();
        result.truncated = configs.size() >= candidateCeiling;

        Integer fromIdx = Math.min(startIdx, all.size());
        Integer toIdx = Math.min(fromIdx + size, all.size());
        for (Integer i = fromIdx; i < toIdx; i++) {
            result.items.add(all[i]);
        }
        return result;
    }

    private static String normalizeScope(String raw) {
        if (raw == SCOPE_TEAM) { return SCOPE_TEAM; }
        if (raw == SCOPE_ALL)  { return SCOPE_ALL; }
        return SCOPE_MINE;
    }

    /**
     * Every user in the running user's Role Hierarchy branch: the running
     * user's own role plus every role under it, breadth-first, capped at
     * MAX_ROLE_DEPTH levels. A roleless running user's "team" collapses to
     * just themself -- there is no hierarchy to walk. This is the same
     * concept Salesforce's own standard report filters use for "My team's",
     * so it needs no new field or custom "team" object.
     */
    private static Set<Id> teamMemberIds(Id me) {
        Set<Id> ids = new Set<Id>{ me };
        List<User> runningUser = [SELECT UserRoleId FROM User WHERE Id = :me LIMIT 1];
        if (runningUser.isEmpty() || runningUser[0].UserRoleId == null) {
            return ids;
        }

        Set<Id> roleIds = new Set<Id>{ runningUser[0].UserRoleId };
        Set<Id> frontier = new Set<Id>{ runningUser[0].UserRoleId };
        Integer depth = 0;
        while (!frontier.isEmpty() && depth < MAX_ROLE_DEPTH) {
            Set<Id> next = new Set<Id>();
            for (UserRole r : [SELECT Id FROM UserRole WHERE ParentRoleId IN :frontier]) {
                if (roleIds.add(r.Id)) {
                    next.add(r.Id);
                }
            }
            frontier = next;
            depth++;
        }

        for (User u : [SELECT Id FROM User WHERE UserRoleId IN :roleIds AND IsActive = true]) {
            ids.add(u.Id);
        }
        return ids;
    }

    /**
     * Private copy of the generalized view-all check already established by
     * GtmAssessmentListController/GtmReadoutsAwaitingController: does the
     * running user hold viewAllRecords on the object via ANY assigned
     * permission set. "A third private copy is accepted to keep this issue
     * small" -- same call those classes' own comments make.
     */
    private static Boolean hasViewAllRecords(String sobjectApiName) {
        List<ObjectPermissions> perms = [
            SELECT PermissionsViewAllRecords
            FROM ObjectPermissions
            WHERE SobjectType = :sobjectApiName
              AND ParentId IN (
                  SELECT PermissionSetId FROM PermissionSetAssignment
                  WHERE AssigneeId = :UserInfo.getUserId()
              )
              AND PermissionsViewAllRecords = true
            LIMIT 1
        ];
        return !perms.isEmpty();
    }

    private static LinkEngagementSummary toSummary(
        GTM_Saved_Configuration__c cfg, Map<Id, GTM_Readout__c> readoutByRequest
    ) {
        LinkEngagementSummary s = new LinkEngagementSummary();
        s.linkId      = cfg.Id;
        s.linkName    = cfg.Name;
        s.company     = cfg.Company__c;
        s.offering    = cfg.Offering__c;
        s.createdDate = cfg.CreatedDate;
        s.active      = cfg.Active__c;
        s.contactId   = cfg.Contact__c;
        s.contactName = cfg.Contact__r != null ? cfg.Contact__r.Name : null;
        s.accountId   = cfg.Account__c;

        // Most recent Page View timestamp, and whether the form was ever
        // opened (events are ordered DESC, so the first Page View match is
        // already the latest -- formOpened just needs "does one exist").
        s.lastPageView = null;
        s.formOpened = false;
        for (GTM_Link_Event__c evt : cfg.GTM_Link_Events__r) {
            if (evt.Event_Type__c == 'Page View' && s.lastPageView == null) {
                s.lastPageView = evt.CreatedDate;
            }
            if (evt.Event_Type__c == 'Form Opened') {
                s.formOpened = true;
            }
        }

        GTM_Assessment_Request__c req = cfg.GTM_Assessment_Requests__r.isEmpty()
            ? null : cfg.GTM_Assessment_Requests__r[0];
        s.recordId              = req != null ? req.Id : null;
        s.assessmentSubmitted   = req != null && req.Submitted_At__c != null;
        s.assessmentSubmittedAt = req != null ? req.Submitted_At__c : null;

        GTM_Readout__c ro = req != null ? readoutByRequest.get(req.Id) : null;
        s.readoutId         = ro != null ? ro.Id : null;
        s.readoutStatus      = ro != null ? ro.Status__c : null;
        s.notificationSent   = ro != null && ro.Notification_Sent_Date__c != null;
        s.readoutSent         = ro != null && ro.Status__c == 'Published';

        String state = classify(s);
        s.state              = state;
        s.stateLabel          = STATE_LABEL.get(state);
        s.rank                = STATE_RANK.get(state);
        s.primaryAction       = STATE_ACTION.get(state);
        s.primaryActionLabel  = STATE_ACTION_LABEL.get(state);

        DateTime last = cfg.CreatedDate;
        if (s.lastPageView != null && s.lastPageView > last) { last = s.lastPageView; }
        if (s.assessmentSubmittedAt != null && s.assessmentSubmittedAt > last) { last = s.assessmentSubmittedAt; }
        if (ro != null && ro.Notification_Sent_Date__c != null && ro.Notification_Sent_Date__c > last) {
            last = ro.Notification_Sent_Date__c;
        }
        s.lastActivityAt = last;

        return s;
    }

    /**
     * D8 + D13's six states, in priority order. Not blocked on #277's
     * Status__c -- every signal here already exists (Submitted_At__c,
     * GTM_Link_Event__c.Event_Type__c, GTM_Readout__c.Status__c /
     * Notification_Sent_Date__c).
     *
     * Boundary case exercised in tests: a readout that exists but whose
     * request has no Submitted_At__c (e.g. stale/synthetic data) is NOT
     * treated as "submitted" just because a readout row exists -- it falls
     * through to the engagement-signal branches like any other
     * not-yet-submitted link, since a readout only really exists once a
     * request is genuinely submitted (D7).
     */
    @TestVisible
    private static String classify(LinkEngagementSummary s) {
        if (s.assessmentSubmitted && s.readoutStatus != 'Published') {
            return STATE_SUBMITTED_DRAFT;
        }
        if (s.readoutStatus == 'Published' && !s.notificationSent) {
            return STATE_PUBLISHED_UNSENT;
        }
        if (s.readoutStatus == 'Published' && s.notificationSent) {
            return STATE_SENT_COMPLETE;
        }
        if (!s.assessmentSubmitted && s.formOpened) {
            return STATE_STARTED;
        }
        if (!s.assessmentSubmitted && s.lastPageView != null) {
            return STATE_OPENED;
        }
        return STATE_NEVER_OPENED;
    }

    /** Rank ascending (1 = highest priority first); within a rank,
     *  most-recent-activity first (D13). */
    private class ByRankThenActivity implements Comparator<LinkEngagementSummary> {
        public Integer compare(LinkEngagementSummary a, LinkEngagementSummary b) {
            if (a.rank != b.rank) {
                return a.rank - b.rank;
            }
            Long at = 0;
            if (a.lastActivityAt != null) { at = a.lastActivityAt.getTime(); }
            Long bt = 0;
            if (b.lastActivityAt != null) { bt = b.lastActivityAt.getTime(); }
            if (at == bt) { return 0; }
            return at > bt ? -1 : 1;
        }
    }
}
