/**
 * Read-only list backend for the "All Assessments" table in gtmReadoutsOverview
 * (issue assessments-tab-filter). Contract: docs/architecture/gtm-assessments-table.md
 * (that file wins over any comment here).
 *
 * One row per GTM_Assessment_Request__c, the request's most recently created
 * readout joined on for the readout status. Every filter, preset, sort and
 * count definition lives in this class and nowhere else, so the tab, the
 * Overview tiles and a later GUS tool can all call getAssessmentPage and agree.
 *
 * Zero DML, zero callouts. `with sharing`, plus an explicit ownership backstop
 * (see scoping below). Two narrow `without sharing` reads live in the private
 * ElevatedReads inner class; nothing else in this class elevates.
 *
 * Scoping (one predicate for rows, count and offeringOptions):
 *  - A user holding viewAllRecords on GTM_Assessment_Request__c through ANY
 *    assigned permission set sees every request. This is a private copy of the
 *    generalized check from rep-data-scoping-owd-3; it is deliberately NOT the
 *    permission-set-name isAdmin() in GtmHomeSnapshotController.
 *  - Everyone else sees requests they own, plus the "queue orphan" arm: requests
 *    that have a readout owned by a queue the user belongs to (the
 *    GTM_Readout_Triage case, where the request itself is not rep-owned).
 *    UNVERIFIED without a live org: whether the workspace's own getRecord on
 *    such a request succeeds for a queue member under the Private OWD. The old
 *    readout-grain grid opened the same workspace for the same orphan, so this
 *    is parity, not a regression.
 */
public with sharing class GtmAssessmentListController {

    /** Safety ceiling on candidate rows. Shown as "10,000+" when reached. */
    @TestVisible private static Integer candidateCeiling = 10000;
    private static final Integer DEFAULT_PAGE_SIZE = 50;
    private static final Integer MAX_PAGE_SIZE = 200;
    private static final Integer OFFERING_OPTION_LIMIT = 200;
    private static final Integer FILTER_OPTION_LIMIT = 50;
    private static final Integer MAX_ID_FILTER_VALUES = 50;
    private static final Integer MAX_SEARCH_LENGTH = 80;
    /** Row scan bound for the options queries (deduplicated to parties in Apex). */
    private static final Integer PARTY_SCAN_LIMIT = 2000;
    private static final String KIND_ACCOUNT = 'account';
    private static final String KIND_CONTACT = 'contact';

    // --------------------------------------------------------- vocabularies

    private static final Map<String, String> STATUS_BY_KEY = new Map<String, String>{
        'new'       => 'New',
        'contacted' => 'Contacted',
        'scheduled' => 'Scheduled',
        'completed' => 'Completed',
        'no-show'   => 'No Show'
    };

    private static final Map<String, String> TIER_BY_KEY = new Map<String, String>{
        'fast-track'        => 'Fast-Track',
        'accelerator-ready' => 'Accelerator-Ready',
        'prep-required'     => 'Prep Required',
        'discovery-first'   => 'Discovery First'
    };

    /** Explicit best-first rank; never rely on picklist order. Absent = 0 (last). */
    private static final Map<String, Integer> TIER_RANK = new Map<String, Integer>{
        'Fast-Track'        => 4,
        'Accelerator-Ready' => 3,
        'Prep Required'     => 2,
        'Discovery First'   => 1
    };

    private static final Set<String> READOUT_KEYS = new Set<String>{
        'none', 'draft', 'pending', 'approved-unsent', 'approved-sent', 'published'
    };

    private static final String PRESET_READY_TO_BOOK = 'ready-to-book';
    private static final String SORT_BEST_FIT = 'best-fit';
    private static final Set<String> SORT_KEYS = new Set<String>{
        'best-fit', 'tier', 'score', 'status', 'readout', 'submitted', 'contact', 'company'
    };

    private static final String REQUEST_SELECT =
        'SELECT Id, Name, Status__c, Assessment_Tier__c, Assessment_Score__c, ' +
        '       Offering_Key__c, Submitted_At__c, CreatedDate, ' +
        '       Contact__c, Contact__r.Name, Account__c, Account__r.Name, ' +
        '       Company__c, Requester_Name__c ' +
        'FROM GTM_Assessment_Request__c';

    // --------------------------------------------------------------- contract

    public class AssessmentQuery {
        @AuraEnabled public List<String> status { get; set; }
        @AuraEnabled public List<String> tier { get; set; }
        @AuraEnabled public List<String> readout { get; set; }
        @AuraEnabled public List<String> offering { get; set; }
        /** Account / Contact record ids (assessments-account-filters-apex). Optional. */
        @AuraEnabled public List<String> accountIds { get; set; }
        @AuraEnabled public List<String> contactIds { get; set; }
        @AuraEnabled public String range { get; set; }
        @AuraEnabled public String preset { get; set; }
        @AuraEnabled public String sortBy { get; set; }
        @AuraEnabled public String sortDir { get; set; }
        @AuraEnabled public Integer offset { get; set; }
        @AuraEnabled public Integer pageSize { get; set; }
    }

    public class AssessmentRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String company;
        @AuraEnabled public String requesterName;
        @AuraEnabled public String offeringKey;
        @AuraEnabled public String tier;
        @AuraEnabled public Integer tierRank;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String requestStatus;
        @AuraEnabled public Id readoutId;
        @AuraEnabled public String readoutStatus;
        @AuraEnabled public Boolean readoutNotificationSent;
        /** The single readout filter key this row matches (see readoutKeyFor). */
        @AuraEnabled public String readoutKey;
        @AuraEnabled public Datetime submittedAt;
        @AuraEnabled public Datetime createdDate;
    }

    public class AssessmentPage {
        @AuraEnabled public List<AssessmentRow> rows = new List<AssessmentRow>();
        @AuraEnabled public Integer totalCount = 0;
        @AuraEnabled public Boolean totalIsCapped = false;
        @AuraEnabled public List<String> offeringOptions = new List<String>();
    }

    public class FilterOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String sublabel;
    }

    /** Who the running user is and which requests that lets them see. */
    private class Scope {
        public Boolean viewAll;
        public Id me;
        public Set<Id> orphanIds = new Set<Id>();
    }

    /** Validated, normalised form of AssessmentQuery. */
    private class Filters {
        public List<String> status = new List<String>();
        public List<String> tier = new List<String>();
        public List<String> readout = new List<String>();
        public List<String> offering = new List<String>();
        public Boolean statusActive = false;
        public Boolean tierActive = false;
        public Boolean readoutActive = false;
        public List<Id> accountIds = new List<Id>();
        public List<Id> contactIds = new List<Id>();
        public Boolean accountActive = false;
        public Boolean contactActive = false;
        public Datetime rangeStart;
        public Datetime rangeEnd;
        /** True when an intersection is empty (e.g. preset AND status=Completed). */
        public Boolean impossible = false;
    }

    // ------------------------------------------------------------ entry point

    /**
     * Deliberately NOT cacheable: the Refresh button and every filter change
     * must reach the server, and a cached page would show a pre-DML readout
     * status after an approve/publish (same reasoning the removed
     * getReadoutsForReview documented).
     */
    @AuraEnabled
    public static AssessmentPage getAssessmentPage(AssessmentQuery query) {
        AssessmentQuery q = query == null ? new AssessmentQuery() : query;
        Integer startIdx = (q.offset == null || q.offset < 0) ? 0 : q.offset;
        Integer pageSize = q.pageSize == null ? DEFAULT_PAGE_SIZE : q.pageSize;
        if (pageSize < 1) { pageSize = 1; }
        if (pageSize > MAX_PAGE_SIZE) { pageSize = MAX_PAGE_SIZE; }

        Filters f = normalise(q);
        Scope scope = currentScope();
        Id me = scope.me;
        Boolean viewAll = scope.viewAll;
        Set<Id> orphanRequestIds = scope.orphanIds;
        ElevatedReads elevated = new ElevatedReads();

        AssessmentPage page = new AssessmentPage();
        if (startIdx == 0) {
            page.offeringOptions = offeringOptions(viewAll, me, orphanRequestIds, elevated);
        }
        if (f.impossible) { return page; }

        Map<Id, GTM_Assessment_Request__c> candidates =
            new Map<Id, GTM_Assessment_Request__c>(queryVisible(f, viewAll, me));
        if (!orphanRequestIds.isEmpty()) {
            for (GTM_Assessment_Request__c r : elevated.queryOrphans(f, orphanRequestIds)) {
                if (!candidates.containsKey(r.Id)) { candidates.put(r.Id, r); }
            }
        }
        page.totalIsCapped = candidates.size() >= candidateCeiling;

        Map<Id, GTM_Readout__c> readouts = candidates.isEmpty()
            ? new Map<Id, GTM_Readout__c>()
            : elevated.latestReadouts(candidates.keySet());

        List<SortRow> kept = new List<SortRow>();
        for (GTM_Assessment_Request__c r : candidates.values()) {
            AssessmentRow row = toRow(r, readouts.get(r.Id));
            if (f.readoutActive && !f.readout.contains(readoutKey(row))) { continue; }
            kept.add(new SortRow(row));
        }

        sortKey = SORT_KEYS.contains(q.sortBy) ? q.sortBy : SORT_BEST_FIT;
        sortDescending = q.sortDir == 'desc';
        kept.sort();

        page.totalCount = kept.size();
        Integer endIdx = Math.min(kept.size(), startIdx + pageSize);
        for (Integer i = startIdx; i < endIdx; i++) {
            page.rows.add(kept[i].row);
        }
        return page;
    }

    /**
     * Options for the Account / Contact filters (assessments-account-filters-apex).
     * Lists ONLY parties with at least one request the user can see, using the
     * SAME scope as getAssessmentPage (currentScope). Deliberately NOT cacheable.
     * Zero DML, zero callouts. `kind` is a whitelist; anything else throws.
     */
    @AuraEnabled(cacheable=false)
    public static List<FilterOption> getAssessmentFilterOptions(
        String kind, String searchTerm, List<String> includeIds
    ) {
        if (kind != KIND_ACCOUNT && kind != KIND_CONTACT) {
            throw fail('Unsupported filter kind.');
        }
        Scope scope = currentScope();
        ElevatedReads elevated = new ElevatedReads();

        String term = searchTerm == null ? '' : searchTerm.trim();
        if (term.length() > MAX_SEARCH_LENGTH) { term = term.substring(0, MAX_SEARCH_LENGTH); }
        String likeTerm = String.isBlank(term) ? null : '%' + escapeLike(term) + '%';

        Map<Id, FilterOption> hits = collectParties(kind, likeTerm, null, scope, elevated);
        Map<Id, FilterOption> out = new Map<Id, FilterOption>();
        for (FilterOption o : sortedOptions(hits.values())) {
            if (out.size() >= FILTER_OPTION_LIMIT) { break; }
            out.put(Id.valueOf(o.value), o);
        }

        // Restored deep-link values: visible + correctly typed only.
        List<Id> restrict = parseIds(
            includeIds, kind == KIND_ACCOUNT ? Account.SObjectType : Contact.SObjectType
        );
        if (!restrict.isEmpty()) {
            Map<Id, FilterOption> included = collectParties(kind, null, restrict, scope, elevated);
            for (Id key : included.keySet()) {
                if (!out.containsKey(key)) { out.put(key, included.get(key)); }
            }
        }
        return sortedOptions(out.values());
    }

    private static AuraHandledException fail(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    /** Escape the escape character first, then % and _, so a term can never widen a LIKE. */
    private static String escapeLike(String raw) {
        return raw.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    /**
     * Distinct parties over the user's visible requests: the `with sharing` arm
     * (ownership backstop for reps) plus the queue-orphan arm through
     * ElevatedReads. Non-aggregate read, deduplicated in Apex: see the GROUP BY
     * note in docs/architecture/gtm-assessments-table.md Addendum A.
     */
    private static Map<Id, FilterOption> collectParties(
        String kind, String likeTerm, List<Id> restrictVals, Scope scope, ElevatedReads elevated
    ) {
        Id me = scope.me;
        String sql = partySql(
            kind, likeTerm != null, restrictVals != null, scope.viewAll ? '' : 'OwnerId = :me'
        );

        Map<Id, FilterOption> out = new Map<Id, FilterOption>();
        for (GTM_Assessment_Request__c r : (List<GTM_Assessment_Request__c>) Database.query(sql)) {
            addParty(out, kind, r);
        }
        if (!scope.viewAll && !scope.orphanIds.isEmpty()) {
            for (GTM_Assessment_Request__c r : elevated.queryOrphanParties(
                kind, likeTerm, restrictVals, scope.orphanIds
            )) {
                addParty(out, kind, r);
            }
        }
        return out;
    }

    /**
     * SOQL for party discovery. Bind locals that MUST exist in the calling
     * method: me (when scopeCond uses it), requestIds (orphan arm), likeTerm and
     * restrictVals (when the matching flag is true).
     */
    private static String partySql(String kind, Boolean withLike, Boolean withRestrict, String scopeCond) {
        Boolean isAccount = kind == KIND_ACCOUNT;
        String field = isAccount ? 'Account__c' : 'Contact__c';
        String nameField = isAccount ? 'Account__r.Name' : 'Contact__r.Name';
        List<String> c = new List<String>{ field + ' != null' };
        if (String.isNotBlank(scopeCond)) { c.add(scopeCond); }
        if (withLike) {
            c.add(isAccount
                ? '(Account__r.Name LIKE :likeTerm OR Company__c LIKE :likeTerm)'
                : '(Contact__r.Name LIKE :likeTerm OR Requester_Name__c LIKE :likeTerm OR Company__c LIKE :likeTerm)');
        }
        if (withRestrict) { c.add(field + ' IN :restrictVals'); }
        return REQUEST_SELECT + ' WHERE ' + String.join(c, ' AND ') +
            ' ORDER BY ' + nameField + ', Id LIMIT ' + PARTY_SCAN_LIMIT;
    }

    private static void addParty(Map<Id, FilterOption> out, String kind, GTM_Assessment_Request__c r) {
        Id key = kind == KIND_ACCOUNT ? r.Account__c : r.Contact__c;
        if (key == null || out.containsKey(key)) { return; }
        FilterOption o = new FilterOption();
        o.value = key;
        String accountName = r.Account__r != null ? r.Account__r.Name : null;
        if (kind == KIND_ACCOUNT) {
            o.label = String.isNotBlank(accountName) ? accountName : r.Company__c;
        } else {
            String contactName = r.Contact__r != null ? r.Contact__r.Name : null;
            o.label = String.isNotBlank(contactName) ? contactName : r.Requester_Name__c;
            String company = String.isNotBlank(accountName) ? accountName : r.Company__c;
            o.sublabel = company != o.label ? company : null;
        }
        if (String.isBlank(o.label)) { o.label = String.valueOf(key); }
        out.put(key, o);
    }

    private static List<FilterOption> sortedOptions(List<FilterOption> options) {
        Map<String, FilterOption> byKey = new Map<String, FilterOption>();
        for (FilterOption o : options) { byKey.put(o.label.toLowerCase() + '|' + o.value, o); }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<FilterOption> out = new List<FilterOption>();
        for (String k : keys) { out.add(byKey.get(k)); }
        return out;
    }

    /**
     * Keep only ids of the expected sObject type: parsed with Id.valueOf inside
     * try/catch, de-duplicated, first MAX_ID_FILTER_VALUES kept. Never used in
     * string concatenation; callers only bind the result.
     */
    private static List<Id> parseIds(List<String> raw, Schema.SObjectType expected) {
        List<Id> out = new List<Id>();
        if (raw == null) { return out; }
        Set<Id> seen = new Set<Id>();
        for (String s : raw) {
            if (out.size() >= MAX_ID_FILTER_VALUES) { break; }
            if (String.isBlank(s)) { continue; }
            try {
                Id candidate = Id.valueOf(s.trim());
                if (candidate.getSobjectType() == expected && seen.add(candidate)) {
                    out.add(candidate);
                }
            } catch (Exception e) {
                // Not an id: dropped.
            }
        }
        return out;
    }

    /** The one scope computation shared by getAssessmentPage and the options method. */
    private static Scope currentScope() {
        Scope s = new Scope();
        s.me = UserInfo.getUserId();
        s.viewAll = hasViewAllRecords('GTM_Assessment_Request__c');
        s.orphanIds = s.viewAll ? new Set<Id>() : queueOrphanRequestIds();
        return s;
    }

    // ------------------------------------------------------- normalisation

    private static Filters normalise(AssessmentQuery q) {
        Filters f = new Filters();

        Set<String> statuses = new Set<String>();
        for (String k : nz(q.status)) {
            if (STATUS_BY_KEY.containsKey(k)) { statuses.add(STATUS_BY_KEY.get(k)); }
        }
        Set<String> tiers = new Set<String>();
        for (String k : nz(q.tier)) {
            if (TIER_BY_KEY.containsKey(k)) { tiers.add(TIER_BY_KEY.get(k)); }
        }
        f.statusActive = !statuses.isEmpty();
        f.tierActive = !tiers.isEmpty();

        // Preset is intersected (AND) with the user's own choices, never a
        // replacement for them. It is expanded here and nowhere else.
        if (q.preset == PRESET_READY_TO_BOOK) {
            Set<String> presetStatus = new Set<String>{ 'New' };
            Set<String> presetTier = new Set<String>{ 'Fast-Track', 'Accelerator-Ready' };
            if (f.statusActive) { statuses.retainAll(presetStatus); } else { statuses = presetStatus; }
            if (f.tierActive) { tiers.retainAll(presetTier); } else { tiers = presetTier; }
            f.statusActive = true;
            f.tierActive = true;
            if (statuses.isEmpty() || tiers.isEmpty()) { f.impossible = true; }
        }
        f.status = new List<String>(statuses);
        f.tier = new List<String>(tiers);

        Set<String> readoutKeys = new Set<String>();
        for (String k : nz(q.readout)) {
            if (READOUT_KEYS.contains(k)) { readoutKeys.add(k); }
        }
        f.readout = new List<String>(readoutKeys);
        f.readoutActive = !readoutKeys.isEmpty();

        Set<String> offerings = new Set<String>();
        for (String k : nz(q.offering)) {
            if (String.isNotBlank(k)) { offerings.add(k); }
        }
        f.offering = new List<String>(offerings);

        // Unlike status/tier: a NON-EMPTY list with no valid id means zero rows,
        // so a corrupt deep link never shows an unfiltered list under an
        // active filter. Null or empty = no filter.
        if (q.accountIds != null && !q.accountIds.isEmpty()) {
            f.accountIds = parseIds(q.accountIds, Account.SObjectType);
            f.accountActive = true;
            if (f.accountIds.isEmpty()) { f.impossible = true; }
        }
        if (q.contactIds != null && !q.contactIds.isEmpty()) {
            f.contactIds = parseIds(q.contactIds, Contact.SObjectType);
            f.contactActive = true;
            if (f.contactIds.isEmpty()) { f.impossible = true; }
        }

        applyRange(f, q.range);
        return f;
    }

    private static List<String> nz(List<String> values) {
        return values == null ? new List<String>() : values;
    }

    /**
     * '7' | '30' | '90' (last N calendar days including today) or
     * 'YYYY-MM-DD..YYYY-MM-DD' (reversed pair swapped). Anything else is
     * dropped. Both boundary days are inclusive whole days in the RUNNING
     * USER'S time zone: Date.today() and Datetime.newInstance(Date, Time) are
     * both user-time-zone based; no Datetime.now() arithmetic, no GMT.
     */
    private static void applyRange(Filters f, String rangeText) {
        if (String.isBlank(rangeText)) { return; }
        Date fromDate;
        Date toDate;
        if (rangeText == '7' || rangeText == '30' || rangeText == '90') {
            toDate = Date.today();
            fromDate = toDate.addDays(-(Integer.valueOf(rangeText) - 1));
        } else {
            List<String> parts = rangeText.split('\\.\\.');
            if (parts.size() != 2) { return; }
            fromDate = parseIsoDate(parts[0]);
            toDate = parseIsoDate(parts[1]);
            if (fromDate == null || toDate == null) { return; }
            if (fromDate > toDate) {
                Date swap = fromDate;
                fromDate = toDate;
                toDate = swap;
            }
        }
        f.rangeStart = Datetime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0));
        f.rangeEnd = Datetime.newInstance(toDate.addDays(1), Time.newInstance(0, 0, 0, 0));
    }

    private static Date parseIsoDate(String raw) {
        if (raw == null || !Pattern.matches('\\d{4}-\\d{2}-\\d{2}', raw)) { return null; }
        try {
            Date d = Date.valueOf(raw);
            // Round-trip so '2026-02-31' cannot silently roll into March.
            return String.valueOf(d) == raw ? d : null;
        } catch (Exception e) {
            return null;
        }
    }

    // --------------------------------------------------------------- queries

    /**
     * Filter conditions on request columns (no owner clause). Bind variables
     * referenced here MUST exist as locals with these exact names in every
     * method that runs the resulting SOQL: statusVals, tierVals, offeringVals,
     * accountVals, contactVals, rangeStart, rangeEnd.
     */
    private static String filterSql(Filters f) {
        List<String> c = new List<String>();
        if (f.statusActive) { c.add('Status__c IN :statusVals'); }
        if (f.tierActive) { c.add('Assessment_Tier__c IN :tierVals'); }
        if (!f.offering.isEmpty()) { c.add('Offering_Key__c IN :offeringVals'); }
        if (f.accountActive) { c.add('Account__c IN :accountVals'); }
        if (f.contactActive) { c.add('Contact__c IN :contactVals'); }
        if (f.rangeStart != null) {
            c.add(
                '((Submitted_At__c >= :rangeStart AND Submitted_At__c < :rangeEnd) OR ' +
                '(Submitted_At__c = null AND CreatedDate >= :rangeStart AND CreatedDate < :rangeEnd))'
            );
        }
        return String.join(c, ' AND ');
    }

    /** The `with sharing` candidate read (own rows for a rep, all for view-all). */
    private static List<GTM_Assessment_Request__c> queryVisible(Filters f, Boolean viewAll, Id me) {
        List<String> statusVals = f.status;
        List<String> tierVals = f.tier;
        List<String> offeringVals = f.offering;
        List<Id> accountVals = f.accountIds;
        List<Id> contactVals = f.contactIds;
        Datetime rangeStart = f.rangeStart;
        Datetime rangeEnd = f.rangeEnd;

        List<String> conds = new List<String>();
        String fs = filterSql(f);
        if (String.isNotBlank(fs)) { conds.add(fs); }
        // Explicit ownership backstop on top of `with sharing` (defense in
        // depth, rep-data-scoping-owd-2): a rep sees the requests they own.
        if (!viewAll) { conds.add('OwnerId = :me'); }
        String sql = REQUEST_SELECT +
            (conds.isEmpty() ? '' : ' WHERE ' + String.join(conds, ' AND ')) +
            ' ORDER BY CreatedDate DESC, Id DESC LIMIT ' + candidateCeiling;
        return (List<GTM_Assessment_Request__c>) Database.query(sql);
    }

    /**
     * Request ids that have a readout owned by a queue the running user is a
     * direct member of (Group.Type = 'Queue'). The readout read is `with
     * sharing`, so only readouts the user can see (queue members can see
     * queue-owned records) contribute. Direct membership only, as the removed
     * getReadoutsForReview/myQueueIds did.
     */
    private static Set<Id> queueOrphanRequestIds() {
        Set<Id> queueIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT GroupId
            FROM GroupMember
            WHERE UserOrGroupId = :UserInfo.getUserId() AND Group.Type = 'Queue'
        ]) {
            queueIds.add(gm.GroupId);
        }
        Set<Id> out = new Set<Id>();
        if (queueIds.isEmpty()) { return out; }
        for (GTM_Readout__c r : [
            SELECT Assessment_Request__c
            FROM GTM_Readout__c
            WHERE OwnerId IN :queueIds AND Assessment_Request__c != null
            LIMIT 10000
        ]) {
            out.add(r.Assessment_Request__c);
        }
        return out;
    }

    /** Distinct Offering_Key__c within the SAME scope, ignoring the other filters. */
    private static List<String> offeringOptions(
        Boolean viewAll, Id me, Set<Id> orphanRequestIds, ElevatedReads elevated
    ) {
        Set<String> keys = new Set<String>();
        String sql = 'SELECT Offering_Key__c k FROM GTM_Assessment_Request__c ' +
            'WHERE Offering_Key__c != null' + (viewAll ? '' : ' AND OwnerId = :me') +
            ' GROUP BY Offering_Key__c ORDER BY Offering_Key__c LIMIT ' + OFFERING_OPTION_LIMIT;
        for (AggregateResult ar : Database.query(sql)) {
            keys.add((String) ar.get('k'));
        }
        if (!orphanRequestIds.isEmpty()) {
            for (GTM_Assessment_Request__c r : elevated.queryOrphans(new Filters(), orphanRequestIds)) {
                if (String.isNotBlank(r.Offering_Key__c)) { keys.add(r.Offering_Key__c); }
            }
        }
        List<String> out = new List<String>(keys);
        out.sort();
        return out;
    }

    /**
     * Local, private copy of the generalized view-all check: does the running
     * user hold viewAllRecords on the object via ANY assigned permission set.
     * Not the permission-set-name check in GtmHomeSnapshotController.isAdmin().
     * A third private copy is accepted to keep this issue small; one shared
     * helper is a separate refactor.
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

    // ------------------------------------------------------- elevated reads

    /**
     * The ONLY elevation in this class, two narrow reads:
     *
     *  1. latestReadouts: each already-visible request's most recently created
     *     readout, status fields only (Id, Status__c, Notification_Sent_Date__c,
     *     Assessment_Request__c). A readout's owner is the Opportunity owner
     *     first, then the request owner, so it can differ from the rep who owns
     *     the request; a `with sharing` join would show "None yet" for a readout
     *     that exists and invite a duplicate Generate. No content fields.
     *
     *  2. queryOrphans: the request rows for ids that came from readouts owned by
     *     a queue the user belongs to (queueOrphanRequestIds, itself `with
     *     sharing`). Under the Private OWD a queue member cannot otherwise see a
     *     request the queue's readout hangs off, which is exactly the orphan the
     *     old readout-grain list surfaced, so a `with sharing` read of the
     *     request would silently drop it. Same light request columns as the main
     *     query; no owner widening beyond "requests behind my own queues'
     *     readouts". Recorded as a deviation from the addendum's "readout join
     *     only" in docs/architecture/gtm-assessments-table.md section 3.4.
     */
    private without sharing class ElevatedReads {
        public Map<Id, GTM_Readout__c> latestReadouts(Set<Id> requestIds) {
            Map<Id, GTM_Readout__c> byRequest = new Map<Id, GTM_Readout__c>();
            for (GTM_Readout__c r : [
                SELECT Id, Status__c, Notification_Sent_Date__c, Assessment_Request__c
                FROM GTM_Readout__c
                WHERE Assessment_Request__c IN :requestIds
                ORDER BY Assessment_Request__c ASC, CreatedDate DESC, Id DESC
            ]) {
                // First seen per request is the most recent (ORDER BY above).
                if (!byRequest.containsKey(r.Assessment_Request__c)) {
                    byRequest.put(r.Assessment_Request__c, r);
                }
            }
            return byRequest;
        }

        /** Party discovery over orphan requests only (bounded by orphanIds). */
        public List<GTM_Assessment_Request__c> queryOrphanParties(
            String kind, String likeTerm, List<Id> restrictVals, Set<Id> orphanIds
        ) {
            Set<Id> requestIds = orphanIds;
            String sql = partySql(kind, likeTerm != null, restrictVals != null, 'Id IN :requestIds');
            return (List<GTM_Assessment_Request__c>) Database.query(sql);
        }

        public List<GTM_Assessment_Request__c> queryOrphans(Filters f, Set<Id> orphanIds) {
            List<String> statusVals = f.status;
            List<String> tierVals = f.tier;
            List<String> offeringVals = f.offering;
            List<Id> accountVals = f.accountIds;
            List<Id> contactVals = f.contactIds;
            Datetime rangeStart = f.rangeStart;
            Datetime rangeEnd = f.rangeEnd;
            Set<Id> requestIds = orphanIds;

            List<String> conds = new List<String>{ 'Id IN :requestIds' };
            String fs = filterSql(f);
            if (String.isNotBlank(fs)) { conds.add(fs); }
            String sql = REQUEST_SELECT + ' WHERE ' + String.join(conds, ' AND ') +
                ' ORDER BY CreatedDate DESC, Id DESC LIMIT ' + candidateCeiling;
            return (List<GTM_Assessment_Request__c>) Database.query(sql);
        }
    }

    // --------------------------------------------------------------- rows

    private static AssessmentRow toRow(GTM_Assessment_Request__c r, GTM_Readout__c ro) {
        AssessmentRow row = new AssessmentRow();
        row.recordId = r.Id;
        row.name = r.Name;
        row.contactId = r.Contact__c;
        row.contactName = r.Contact__r != null ? r.Contact__r.Name : null;
        row.accountId = r.Account__c;
        // Account__r.Name (a governed lookup) wins over the free-typed
        // Company__c fallback whenever both are populated -- Company__c only
        // fills in when there is no linked Account (issue
        // pages-table-account-column-consistency; same precedence flip as
        // gtmRepLinkTableModel.buildRows on the Pages table).
        row.company = (r.Account__r != null && String.isNotBlank(r.Account__r.Name))
            ? r.Account__r.Name
            : r.Company__c;
        row.requesterName = r.Requester_Name__c;
        row.offeringKey = r.Offering_Key__c;
        row.tier = r.Assessment_Tier__c;
        row.tierRank = TIER_RANK.containsKey(r.Assessment_Tier__c) ? TIER_RANK.get(r.Assessment_Tier__c) : 0;
        row.score = r.Assessment_Score__c;
        row.requestStatus = r.Status__c;
        row.readoutId = ro != null ? ro.Id : null;
        row.readoutStatus = ro != null ? ro.Status__c : null;
        row.readoutNotificationSent = ro != null && ro.Notification_Sent_Date__c != null;
        row.readoutKey = readoutKeyFor(row.readoutStatus, row.readoutNotificationSent);
        row.submittedAt = r.Submitted_At__c != null ? r.Submitted_At__c : r.CreatedDate;
        row.createdDate = r.CreatedDate;
        return row;
    }

    private static String readoutKey(AssessmentRow row) {
        return readoutKeyFor(row.readoutStatus, row.readoutNotificationSent);
    }

    /**
     * Total mapping: every readout state maps to exactly one key. A blank
     * status (no readout) is 'none'; Approved splits on whether the
     * notification was sent. Only a status outside the picklist yields ''.
     */
    @TestVisible
    private static String readoutKeyFor(String readoutStatus, Boolean notificationSent) {
        if (String.isBlank(readoutStatus)) { return 'none'; }
        if (readoutStatus == 'Draft') { return 'draft'; }
        if (readoutStatus == 'Pending Approval') { return 'pending'; }
        if (readoutStatus == 'Published') { return 'published'; }
        if (readoutStatus == 'Approved') {
            return notificationSent == true ? 'approved-sent' : 'approved-unsent';
        }
        return '';
    }

    // --------------------------------------------------------------- sorting

    private static String sortKey = SORT_BEST_FIT;
    private static Boolean sortDescending = true;

    /**
     * Comparable wrapper (Apex sort has no comparator argument, so the active
     * sort lives in the two statics above). Chain: the requested column (nulls
     * always last, whichever direction), then best-fit: tier rank DESC, score
     * DESC (null last), submitted DESC, Id DESC (stable paging tiebreak).
     */
    private class SortRow implements Comparable {
        public AssessmentRow row;
        public SortRow(AssessmentRow row) { this.row = row; }

        public Integer compareTo(Object other) {
            SortRow o = (SortRow) other;
            Integer c = 0;
            if (sortKey == 'tier') {
                c = cmpNum(rankOrNull(row), rankOrNull(o.row), sortDescending);
            } else if (sortKey == 'score') {
                c = cmpNum(row.score, o.row.score, sortDescending);
            } else if (sortKey == 'status') {
                c = cmpText(row.requestStatus, o.row.requestStatus, sortDescending);
            } else if (sortKey == 'readout') {
                c = cmpText(row.readoutStatus, o.row.readoutStatus, sortDescending);
            } else if (sortKey == 'submitted') {
                c = cmpNum(millis(row.submittedAt), millis(o.row.submittedAt), sortDescending);
            } else if (sortKey == 'contact') {
                c = cmpText(contactLabel(row), contactLabel(o.row), sortDescending);
            } else if (sortKey == 'company') {
                c = cmpText(row.company, o.row.company, sortDescending);
            }
            if (c != 0) { return c; }
            c = cmpNum(rankOrNull(row), rankOrNull(o.row), true);
            if (c != 0) { return c; }
            c = cmpNum(row.score, o.row.score, true);
            if (c != 0) { return c; }
            c = cmpNum(millis(row.submittedAt), millis(o.row.submittedAt), true);
            if (c != 0) { return c; }
            return cmpText(String.valueOf(row.recordId), String.valueOf(o.row.recordId), true);
        }
    }

    private static Decimal rankOrNull(AssessmentRow row) {
        return row.tierRank == null || row.tierRank == 0 ? null : Decimal.valueOf(row.tierRank);
    }

    private static Decimal millis(Datetime dt) {
        return dt == null ? null : Decimal.valueOf(dt.getTime());
    }

    private static String contactLabel(AssessmentRow row) {
        if (String.isNotBlank(row.contactName)) { return row.contactName; }
        if (String.isNotBlank(row.requesterName)) { return row.requesterName; }
        return row.company;
    }

    private static Integer cmpNum(Decimal a, Decimal b, Boolean descending) {
        if (a == null && b == null) { return 0; }
        if (a == null) { return 1; }
        if (b == null) { return -1; }
        if (a == b) { return 0; }
        Integer c = a < b ? -1 : 1;
        return descending ? -c : c;
    }

    private static Integer cmpText(String a, String b, Boolean descending) {
        Boolean aBlank = String.isBlank(a);
        Boolean bBlank = String.isBlank(b);
        if (aBlank && bBlank) { return 0; }
        if (aBlank) { return 1; }
        if (bBlank) { return -1; }
        Integer c = a.toLowerCase().compareTo(b.toLowerCase());
        if (c == 0) { return 0; }
        c = c < 0 ? -1 : 1;
        return descending ? -c : c;
    }
}
