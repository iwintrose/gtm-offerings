/**
 * Read-only, cross-rep rollup backing the "Team" view toggle on the
 * Analytics tab (issue #139, v2 first pass -- rep leaderboard only;
 * instrument-version comparison and flagged-assessment drill-in were
 * originally scoped as separate follow-ups, see the scoping comment on
 * #139 -- instrument-version comparison shipped in issue #159 as
 * `getInstrumentVersionComparison`; flagged-assessment drill-in shipped
 * in issue #160 as `getFlaggedRequests`). Originally shipped as its own standalone tab,
 * folded into `gtmAnalytics` as a view toggle per issue #177 -- it's the
 * same Analytics concept at a wider data scope, not a distinct feature
 * deserving its own nav entry.
 *
 * `with sharing`, deliberately NOT `OwnerId`-scoped -- unlike v1's
 * GtmAnalyticsController, which is rep-scoped for every persona including
 * admin. This class relies on GTM_Offering_Admin's existing
 * `viewAllRecords=true` grants on GTM_Saved_Configuration__c /
 * GTM_Assessment_Request__c / GTM_Readout__c (see that permission set's
 * metadata) plus `hasTeamAccess()` gating the UI toggle itself, rather
 * than an explicit `without sharing` escalation. A user without those
 * grants simply sees their own records under standard sharing -- this
 * class never widens access itself.
 *
 * No DML anywhere. Uses the corrected issue #138 semantics from the start:
 * "submitted" (a request's existence), not the old, wrong "started"/
 * "completed" split.
 */
public with sharing class GtmAnalyticsTeamController {

    /**
     * AuraHandledException has a well-known Apex quirk: passing a message to
     * its constructor does NOT populate what getMessage() returns to the
     * calling LWC unless setMessage() is also called explicitly afterward.
     * Every throw site in this class goes through this helper so callers
     * (and tests asserting on caught messages) actually receive the text
     * instead of the generic "Script-thrown exception" -- mirrors
     * GTM_RecycleBinController.handledException().
     */
    private static AuraHandledException handledException(String message) {
        AuraHandledException ahe = new AuraHandledException(message);
        ahe.setMessage(message);
        return ahe;
    }

    /**
     * The three objects this class reads org-wide, per its own class-level
     * doc comment -- a caller must hold `viewAllRecords=true` on ALL THREE
     * (via any permission set, not a hardcoded name) to see org-wide data
     * from any of the three data methods below.
     */
    private static final Set<String> ORG_WIDE_OBJECTS = new Set<String>{
        'GTM_Saved_Configuration__c', 'GTM_Assessment_Request__c', 'GTM_Readout__c'
    };

    /**
     * Whether the running user should see the "Team" toggle/org-wide data at
     * all -- generalized off any single hardcoded permission-set name.
     * Queries the standard `ObjectPermissions` object (joined through
     * `PermissionSetAssignment` for the running user) for
     * `PermissionsViewAllRecords = true` on each of the three objects this
     * class actually reads, so a future, differently-named permission set
     * granting the same escalation is honored automatically -- no code
     * change required. `ObjectPermissions` also reflects Profile-level
     * `viewAllRecords` grants, not just Permission Set ones.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean hasTeamAccess() {
        Map<String, Integer> grantedObjectCount = new Map<String, Integer>();
        for (ObjectPermissions op : [
            SELECT SobjectType FROM ObjectPermissions
            WHERE SobjectType IN :ORG_WIDE_OBJECTS
              AND PermissionsViewAllRecords = true
              AND ParentId IN (
                  SELECT PermissionSetId FROM PermissionSetAssignment
                  WHERE AssigneeId = :UserInfo.getUserId()
              )
        ]) {
            grantedObjectCount.put(op.SobjectType, 1);
        }
        return grantedObjectCount.keySet().containsAll(ORG_WIDE_OBJECTS);
    }

    /**
     * Server-side guard for the three data methods below -- `hasTeamAccess()`
     * alone only gates the client-facing UI toggle, so a caller invoking
     * these methods directly (dev console/API), bypassing the LWC, must
     * still be rejected here rather than silently getting org-wide rollups.
     */
    private static void assertTeamAccess() {
        if (!hasTeamAccess()) {
            throw handledException('You do not have access to view org-wide analytics.');
        }
    }

    /**
     * One row per rep who owns at least one GTM_Saved_Configuration__c
     * created in [rangeStart, rangeEnd], org-wide, sorted by readouts
     * published descending.
     */
    @AuraEnabled(cacheable=true)
    public static List<RepRow> getRepLeaderboard(Date rangeStart, Date rangeEnd) {
        assertTeamAccess();
        validateRange(rangeStart, rangeEnd);
        DateTime windowStart = DateTime.newInstance(rangeStart, Time.newInstance(0, 0, 0, 0));
        DateTime windowEnd = DateTime.newInstance(rangeEnd.addDays(1), Time.newInstance(0, 0, 0, 0));

        Map<Id, Set<Id>> configIdsByOwner = new Map<Id, Set<Id>>();
        for (GTM_Saved_Configuration__c cfg : [
            SELECT Id, OwnerId
            FROM GTM_Saved_Configuration__c
            WHERE CreatedDate >= :windowStart AND CreatedDate < :windowEnd
        ]) {
            if (!configIdsByOwner.containsKey(cfg.OwnerId)) {
                configIdsByOwner.put(cfg.OwnerId, new Set<Id>());
            }
            configIdsByOwner.get(cfg.OwnerId).add(cfg.Id);
        }
        if (configIdsByOwner.isEmpty()) {
            return new List<RepRow>();
        }

        Map<Id, String> repNames = new Map<Id, String>();
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :configIdsByOwner.keySet()]) {
            repNames.put(u.Id, u.Name);
        }

        List<RepRow> rows = new List<RepRow>();
        for (Id ownerId : configIdsByOwner.keySet()) {
            Set<Id> configIds = configIdsByOwner.get(ownerId);
            RequestRollup req = requestRollupFor(configIds);
            Integer published = publishedCountFor(req.requestIds);

            RepRow row = new RepRow();
            row.repId = ownerId;
            row.repName = repNames.containsKey(ownerId) ? repNames.get(ownerId) : String.valueOf(ownerId);
            row.links = configIds.size();
            row.submitted = req.submitted;
            row.avgScore = req.avgScore;
            row.published = published;
            rows.add(row);
        }

        rows.sort(new ByPublishedDesc());
        return rows;
    }

    private class ByPublishedDesc implements Comparator<RepRow> {
        public Integer compare(RepRow a, RepRow b) {
            return b.published - a.published;
        }
    }

    private static final String UNSET_SENTINEL = '(unset)';
    private static final String UNSCORED_TIER_BUCKET = 'Unscored';
    private static final List<String> TIER_LABELS = new List<String>{
        'Discovery First', 'Prep Required', 'Accelerator-Ready', 'Fast-Track'
    };

    /**
     * One row per distinct (Instrument_Pair__c, Instrument_Version__c)
     * combination seen on GTM_Assessment_Request__c records created in
     * [rangeStart, rangeEnd], org-wide -- the deferred "instrument-version
     * comparison" follow-up called out in this class's own doc comment
     * (issue #159). Null pair/version (legacy, pre-pack rows) are bucketed
     * under an explicit "(unset)" sentinel rather than dropped. avgScore is
     * left null (not defaulted to 0) when a group has no scored rows, per
     * Score's own doc comment distinguishing "not assessed" from "assessed
     * at the floor". Sorted by pairKey then version descending.
     */
    @AuraEnabled(cacheable=true)
    public static List<InstrumentVersionRow> getInstrumentVersionComparison(Date rangeStart, Date rangeEnd) {
        assertTeamAccess();
        validateRange(rangeStart, rangeEnd);
        DateTime windowStart = DateTime.newInstance(rangeStart, Time.newInstance(0, 0, 0, 0));
        DateTime windowEnd = DateTime.newInstance(rangeEnd.addDays(1), Time.newInstance(0, 0, 0, 0));

        Map<String, InstrumentVersionRow> rowsByKey = new Map<String, InstrumentVersionRow>();
        Map<String, Set<Id>> requestIdsByKey = new Map<String, Set<Id>>();

        for (GTM_Assessment_Request__c req : [
            SELECT Id, Instrument_Pair__c, Instrument_Version__c, Assessment_Score__c, Assessment_Tier__c
            FROM GTM_Assessment_Request__c
            WHERE CreatedDate >= :windowStart AND CreatedDate < :windowEnd
        ]) {
            String pairKey = String.isBlank(req.Instrument_Pair__c) ? UNSET_SENTINEL : req.Instrument_Pair__c;
            String version = String.isBlank(req.Instrument_Version__c) ? UNSET_SENTINEL : req.Instrument_Version__c;
            String groupKey = pairKey + ' ' + version;

            InstrumentVersionRow row = rowsByKey.get(groupKey);
            if (row == null) {
                row = new InstrumentVersionRow();
                row.pairKey = pairKey;
                row.version = version;
                row.tierCounts = newTierCounts();
                rowsByKey.put(groupKey, row);
                requestIdsByKey.put(groupKey, new Set<Id>());
            }

            row.submitted++;
            requestIdsByKey.get(groupKey).add(req.Id);

            if (req.Assessment_Score__c != null) {
                row.scoreTotal += req.Assessment_Score__c;
                row.scoredCount++;
            }

            String tierBucket = String.isBlank(req.Assessment_Tier__c) ? UNSCORED_TIER_BUCKET : req.Assessment_Tier__c;
            if (!row.tierCounts.containsKey(tierBucket)) {
                row.tierCounts.put(tierBucket, 0);
            }
            row.tierCounts.put(tierBucket, row.tierCounts.get(tierBucket) + 1);
        }

        List<InstrumentVersionRow> rows = new List<InstrumentVersionRow>();
        for (String groupKey : rowsByKey.keySet()) {
            InstrumentVersionRow row = rowsByKey.get(groupKey);
            row.avgScore = row.scoredCount > 0 ? (row.scoreTotal / row.scoredCount).setScale(1) : null;
            row.published = publishedCountFor(requestIdsByKey.get(groupKey));
            row.publishRate = row.submitted > 0
                ? ((Decimal) row.published / row.submitted * 100).setScale(1)
                : null;
            rows.add(row);
        }

        rows.sort(new ByPairThenVersionDesc());
        return rows;
    }

    private static Map<String, Integer> newTierCounts() {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (String label : TIER_LABELS) {
            counts.put(label, 0);
        }
        counts.put(UNSCORED_TIER_BUCKET, 0);
        return counts;
    }

    private class ByPairThenVersionDesc implements Comparator<InstrumentVersionRow> {
        public Integer compare(InstrumentVersionRow a, InstrumentVersionRow b) {
            Integer pairCompare = a.pairKey.compareTo(b.pairKey);
            if (pairCompare != 0) {
                return pairCompare;
            }
            return b.version.compareTo(a.version);
        }
    }

    /**
     * Hard row cap on the flagged/advisory drill-in query (issue #160).
     * `FlaggedResult.hasMore` tells the UI whether the range may contain
     * more than this many rows so it can prompt to narrow the date range,
     * rather than silently truncating.
     */
    private static final Integer FLAGGED_ROW_LIMIT = 500;

    /**
     * SOQL cannot filter on `Assessment_Flags__c` (a LongTextArea field --
     * "field 'Assessment_Flags__c' can not be filtered in a query call").
     * So the flagged/advisory predicate is applied in Apex after querying
     * every request in the date window; this cap on the *query itself*
     * bounds that in-memory scan/governor-limit exposure independent of
     * `FLAGGED_ROW_LIMIT`, which caps the (usually much smaller) filtered
     * result returned to the UI.
     */
    private static final Integer WINDOW_QUERY_LIMIT = 10000;

    /**
     * One row per `GTM_Assessment_Request__c` in [rangeStart, rangeEnd]
     * that was flagged during scoring (`Assessment_Flags__c` non-blank) or
     * hit the advisory gate (`Assessment_Advisory__c = true`) -- see
     * `GtmAssessmentScoring.cls` for how those fields are populated.
     */
    @AuraEnabled(cacheable=true)
    public static FlaggedResult getFlaggedRequests(Date rangeStart, Date rangeEnd) {
        assertTeamAccess();
        validateRange(rangeStart, rangeEnd);
        DateTime windowStart = DateTime.newInstance(rangeStart, Time.newInstance(0, 0, 0, 0));
        DateTime windowEnd = DateTime.newInstance(rangeEnd.addDays(1), Time.newInstance(0, 0, 0, 0));

        List<GTM_Assessment_Request__c> windowRequests = [
            SELECT Id, Name, OwnerId, CreatedDate, Assessment_Flags__c,
                   Assessment_Advisory__c, Advisory_Reason__c
            FROM GTM_Assessment_Request__c
            WHERE CreatedDate >= :windowStart AND CreatedDate < :windowEnd
            ORDER BY CreatedDate DESC
            LIMIT :WINDOW_QUERY_LIMIT
        ];

        List<GTM_Assessment_Request__c> requests = new List<GTM_Assessment_Request__c>();
        for (GTM_Assessment_Request__c req : windowRequests) {
            if (String.isNotBlank(req.Assessment_Flags__c) || req.Assessment_Advisory__c == true) {
                requests.add(req);
                if (requests.size() > FLAGGED_ROW_LIMIT) {
                    break;
                }
            }
        }

        Boolean hasMore = requests.size() > FLAGGED_ROW_LIMIT;
        if (hasMore) {
            requests.remove(requests.size() - 1);
        }

        Set<Id> ownerIds = new Set<Id>();
        for (GTM_Assessment_Request__c req : requests) {
            ownerIds.add(req.OwnerId);
        }
        Map<Id, String> repNames = new Map<Id, String>();
        if (!ownerIds.isEmpty()) {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :ownerIds]) {
                repNames.put(u.Id, u.Name);
            }
        }

        List<FlaggedRow> rows = new List<FlaggedRow>();
        for (GTM_Assessment_Request__c req : requests) {
            FlaggedRow row = new FlaggedRow();
            row.requestId = req.Id;
            row.requestName = req.Name;
            row.repId = req.OwnerId;
            row.repName = repNames.containsKey(req.OwnerId) ? repNames.get(req.OwnerId) : String.valueOf(req.OwnerId);
            row.createdDate = req.CreatedDate;
            row.advisory = req.Assessment_Advisory__c;
            row.advisoryReason = req.Advisory_Reason__c;
            row.flagMessages = parseFlagMessages(req.Assessment_Flags__c);
            rows.add(row);
        }

        FlaggedResult result = new FlaggedResult();
        result.rows = rows;
        result.returnedCount = rows.size();
        result.hasMore = hasMore;
        return result;
    }

    /**
     * `Assessment_Flags__c` is a JSON array of `{code, message}` objects
     * (see `GtmAssessmentScoring.cls`), open-ended for future annotation
     * codes -- only `message` is surfaced here since the drill-in UI has
     * no per-code behavior today.
     */
    private static List<String> parseFlagMessages(String flagsJson) {
        List<String> messages = new List<String>();
        if (String.isBlank(flagsJson)) {
            return messages;
        }
        try {
            List<Object> parsed = (List<Object>) JSON.deserializeUntyped(flagsJson);
            for (Object entry : parsed) {
                Map<String, Object> flag = (Map<String, Object>) entry;
                Object message = flag.get('message');
                messages.add(message != null ? String.valueOf(message) : String.valueOf(flag.get('code')));
            }
        } catch (Exception e) {
            // Malformed/unexpected JSON shape: surface the raw string rather
            // than failing the whole drill-in load.
            messages.add(flagsJson);
        }
        return messages;
    }

    private static void validateRange(Date rangeStart, Date rangeEnd) {
        if (rangeStart == null || rangeEnd == null) {
            throw handledException('A date range is required.');
        }
        if (rangeStart > rangeEnd) {
            throw handledException('The range start must be on or before the range end.');
        }
    }

    private class RequestRollup {
        Integer submitted = 0;
        Decimal avgScore = 0;
        Set<Id> requestIds = new Set<Id>();
    }

    /** Same "submitted = request exists" semantics as GtmAnalyticsController (issue #138). */
    private static RequestRollup requestRollupFor(Set<Id> configIds) {
        RequestRollup out = new RequestRollup();
        if (configIds.isEmpty()) {
            return out;
        }
        Decimal scoreTotal = 0;
        Integer scoredCount = 0;
        for (GTM_Assessment_Request__c req : [
            SELECT Id, Assessment_Score__c
            FROM GTM_Assessment_Request__c
            WHERE Saved_Configuration__c IN :configIds
        ]) {
            out.submitted++;
            out.requestIds.add(req.Id);
            if (req.Assessment_Score__c != null) {
                scoreTotal += req.Assessment_Score__c;
                scoredCount++;
            }
        }
        out.avgScore = scoredCount > 0 ? (scoreTotal / scoredCount).setScale(1) : 0;
        return out;
    }

    private static Integer publishedCountFor(Set<Id> requestIds) {
        if (requestIds.isEmpty()) {
            return 0;
        }
        AggregateResult[] results = [
            SELECT COUNT(Id) cnt
            FROM GTM_Readout__c
            WHERE Assessment_Request__c IN :requestIds AND Status__c = 'Published'
        ];
        return results.isEmpty() ? 0 : (Integer) results[0].get('cnt');
    }

    public class RepRow {
        @AuraEnabled public Id repId;
        @AuraEnabled public String repName;
        @AuraEnabled public Integer links;
        @AuraEnabled public Integer submitted;
        @AuraEnabled public Decimal avgScore;
        @AuraEnabled public Integer published;
    }

    public class InstrumentVersionRow {
        @AuraEnabled public String pairKey;
        @AuraEnabled public String version;
        @AuraEnabled public Integer submitted = 0;
        @AuraEnabled public Decimal avgScore;
        @AuraEnabled public Map<String, Integer> tierCounts;
        @AuraEnabled public Integer published = 0;
        @AuraEnabled public Decimal publishRate;

        // Accumulators, not exposed to the client.
        private Decimal scoreTotal = 0;
        private Integer scoredCount = 0;
    }

    public class FlaggedRow {
        @AuraEnabled public Id requestId;
        @AuraEnabled public String requestName;
        @AuraEnabled public Id repId;
        @AuraEnabled public String repName;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public Boolean advisory;
        @AuraEnabled public String advisoryReason;
        @AuraEnabled public List<String> flagMessages;
    }

    /**
     * `hasMore` is true when the range contains more than `FLAGGED_ROW_LIMIT`
     * matching requests -- the UI should show "showing N of possibly more,
     * narrow your date range" rather than assuming `rows` is exhaustive.
     */
    public class FlaggedResult {
        @AuraEnabled public List<FlaggedRow> rows;
        @AuraEnabled public Integer returnedCount;
        @AuraEnabled public Boolean hasMore;
    }
}
