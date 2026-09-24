/**
 * Read-only rollup controller for the Analytics tab (issue #110, v1).
 *
 * Scope, deliberately: this is a REPORTING surface, not a new source of
 * truth. It performs no DML anywhere, both public methods are
 * `cacheable=true`, and every query is scoped to the running user's own
 * GTM_Saved_Configuration__c records (OwnerId = UserInfo.getUserId()) --
 * v1 is rep-only by design (see TASK_SCOPE.md, phasing). A cross-rep/admin
 * view is v2 and would need its own method rather than a flag on these two,
 * since the sharing story is genuinely different (a rep is scoped by
 * ownership; an admin rollup would need to explicitly widen that).
 *
 * `with sharing` throughout: this reads records a rep already has access to
 * under the org's Private sharing model on GTM_Saved_Configuration__c /
 * GTM_Assessment_Request__c / GTM_Readout__c, and must never show a rep
 * data they could not otherwise see.
 *
 * Aggregation strategy: AggregateResult SOQL (COUNT/AVG/GROUP BY) rather
 * than pulling raw GTM_Link_Event__c rows into Apex heap -- flagged as a
 * governor-limit risk in the BA plan. If a rep's link volume ever makes
 * even these aggregate queries expensive, that is a signal for a scheduled
 * rollup object in v2, not a reason to loosen this to non-cacheable or to
 * paginate raw events here.
 *
 * ISSUE #138 FIX. GTM_Assessment_Request__c.Status__c ('New' / 'Contacted' /
 * 'Scheduled' / 'Completed' / 'No Show') is a REP FOLLOW-UP PIPELINE STATUS,
 * not a signal about whether the prospect finished the questionnaire --
 * confirmed in GtmAssessmentRequestController: score and tier are computed
 * and the record is inserted with Status__c = 'New' the instant a prospect
 * finishes the questionnaire. The original v1 "assessments completed" KPI
 * and tier mix were filtered on Status__c = 'Completed', which measures a
 * rep's own outreach progress, not assessment completion, and made the tier
 * mix silently empty until a rep manually advanced a lead's status. Fixed
 * by: (1) one funnel step, "submitted," standing in for what were two
 * conflated steps ("started"/"completed") -- a request's existence is the
 * only honest prospect-side completion signal this schema has; (2) tier mix
 * over every tiered request, not filtered by Status__c; (3) the rep
 * follow-up breakdown surfaced as its own field rather than discarded.
 */
public with sharing class GtmAnalyticsController {

    // Funnel/engagement event types that count as "opened" for a link --
    // either a guest actually viewed the page or opened the assessment
    // form. Kept as a private constant, not a bind var literal repeated
    // three times, so the funnel definition lives in exactly one place.
    private static final Set<String> OPEN_EVENT_TYPES = new Set<String>{ 'Page View', 'Form Opened' };

    /** Test seam: lets the test class pretend to be a different running user's data window. */
    @TestVisible
    private static Id ownerIdOverride;

    private static Id ownerId() {
        return ownerIdOverride != null ? ownerIdOverride : UserInfo.getUserId();
    }

    // --------------------------------------------------------------- summary

    /**
     * KPI row + funnel + tier mix + rep follow-up breakdown + weekly trend
     * for the given date range, optionally narrowed to one offering.
     * `offering` is matched against GTM_Saved_Configuration__c.Offering__c
     * (free text, per its own field description) -- null/blank means "all
     * offerings."
     *
     * Contract for lwc/gtmAnalytics -- see docs/architecture/gtm-analytics-v1.md.
     */
    @AuraEnabled(cacheable=true)
    public static AnalyticsSummary getSummary(Date rangeStart, Date rangeEnd, String offering) {
        return summaryForOwner(ownerId(), rangeStart, rangeEnd, offering);
    }

    /**
     * The actual rollup, parameterized by owner rather than always reading
     * `ownerId()` -- extracted (issue #140) so GtmAnalyticsDigestJob can
     * compute the exact same numbers for every rep it emails, rather than
     * maintaining a second, independent definition of these metrics.
     * `public`, not `private`: needs to be callable from that other class,
     * but is still plain Apex, not `@AuraEnabled` -- it is not a new
     * LWC-facing surface.
     */
    public static AnalyticsSummary summaryForOwner(Id ownerIdParam, Date rangeStart, Date rangeEnd, String offering) {
        validateRange(rangeStart, rangeEnd);
        String offeringFilter = String.isBlank(offering) ? null : offering;

        Integer periodDays = rangeStart.daysBetween(rangeEnd) + 1;
        Date priorEnd = rangeStart.addDays(-1);
        Date priorStart = priorEnd.addDays(-(periodDays - 1));

        AnalyticsSummary out = new AnalyticsSummary();

        Set<Id> configIds = configIdsInRange(ownerIdParam, rangeStart, rangeEnd, offeringFilter);
        Set<Id> priorConfigIds = configIdsInRange(ownerIdParam, priorStart, priorEnd, offeringFilter);

        out.linksCreated = configIds.size();
        out.linksCreatedPrior = priorConfigIds.size();

        out.linksOpened = countLinksWithEventType(configIds, OPEN_EVENT_TYPES);

        RequestRollup current = requestRollupFor(configIds);
        RequestRollup prior = requestRollupFor(priorConfigIds);

        out.assessmentsSubmitted = current.submitted;
        out.assessmentsSubmittedPrior = prior.submitted;
        out.followUpStatusCounts = statusCountsToList(current.statusCounts);

        ReadoutRollup readouts = readoutRollupFor(current.requestIds);
        out.readoutsPublished = readouts.published;
        out.avgDaysToPublish = readouts.avgDaysToPublish;

        ReadoutRollup priorReadouts = readoutRollupFor(prior.requestIds);
        out.readoutsPublishedPrior = priorReadouts.published;
        out.avgDaysToPublishPrior = priorReadouts.avgDaysToPublish;

        out.tierMix = tierMixFor(current.requestIds);
        out.trend = weeklyTrend(configIds, rangeStart, rangeEnd);

        return out;
    }

    /**
     * The by-offering table: one row per distinct Offering__c value among
     * the running user's links in range, sorted by readouts published
     * (most-converting first) -- matches the BA mockup's default sort.
     */
    @AuraEnabled(cacheable=true)
    public static List<OfferingRow> getOfferingBreakdown(Date rangeStart, Date rangeEnd) {
        validateRange(rangeStart, rangeEnd);
        Id uid = ownerId();
        DateTime windowStart = DateTime.newInstance(rangeStart, Time.newInstance(0, 0, 0, 0));
        DateTime windowEnd = DateTime.newInstance(rangeEnd.addDays(1), Time.newInstance(0, 0, 0, 0));

        Map<String, Set<Id>> configIdsByOffering = new Map<String, Set<Id>>();
        for (GTM_Saved_Configuration__c cfg : [
            SELECT Id, Offering__c
            FROM GTM_Saved_Configuration__c
            WHERE OwnerId = :uid
              AND CreatedDate >= :windowStart AND CreatedDate < :windowEnd
        ]) {
            String key = String.isBlank(cfg.Offering__c) ? '(none)' : cfg.Offering__c;
            if (!configIdsByOffering.containsKey(key)) {
                configIdsByOffering.put(key, new Set<Id>());
            }
            configIdsByOffering.get(key).add(cfg.Id);
        }

        List<OfferingRow> rows = new List<OfferingRow>();
        for (String offering : configIdsByOffering.keySet()) {
            Set<Id> configIds = configIdsByOffering.get(offering);
            RequestRollup req = requestRollupFor(configIds);
            ReadoutRollup readouts = readoutRollupFor(req.requestIds);

            OfferingRow row = new OfferingRow();
            row.offering = offering;
            row.links = configIds.size();
            row.submitted = req.submitted;
            row.avgScore = req.avgScore;
            row.published = readouts.published;
            row.topTier = req.topTier;
            rows.add(row);
        }

        rows.sort(new ByPublishedDesc());
        return rows;
    }

    private class ByPublishedDesc implements Comparator<OfferingRow> {
        public Integer compare(OfferingRow a, OfferingRow b) {
            return b.published - a.published;
        }
    }

    // --------------------------------------------------------------- helpers

    private static void validateRange(Date rangeStart, Date rangeEnd) {
        if (rangeStart == null || rangeEnd == null) {
            throw new AuraHandledException('A date range is required.');
        }
        if (rangeStart > rangeEnd) {
            throw new AuraHandledException('The range start must be on or before the range end.');
        }
    }

    /**
     * Ids of the running user's own links created in [rangeStart, rangeEnd],
     * optionally by offering. Static SOQL, not dynamic -- CreatedDate is a
     * DateTime field, so the range bounds are converted to DateTime here
     * rather than left as bare Date binds, which is what a dynamic
     * Database.query() string does implicitly and inconsistently.
     */
    private static Set<Id> configIdsInRange(Id uid, Date rangeStart, Date rangeEnd, String offeringFilter) {
        DateTime windowStart = DateTime.newInstance(rangeStart, Time.newInstance(0, 0, 0, 0));
        DateTime windowEnd = DateTime.newInstance(rangeEnd.addDays(1), Time.newInstance(0, 0, 0, 0));

        List<GTM_Saved_Configuration__c> matches = String.isBlank(offeringFilter)
            ? [
                SELECT Id FROM GTM_Saved_Configuration__c
                WHERE OwnerId = :uid AND CreatedDate >= :windowStart AND CreatedDate < :windowEnd
              ]
            : [
                SELECT Id FROM GTM_Saved_Configuration__c
                WHERE OwnerId = :uid AND CreatedDate >= :windowStart AND CreatedDate < :windowEnd
                  AND Offering__c = :offeringFilter
              ];
        Set<Id> ids = new Set<Id>();
        for (GTM_Saved_Configuration__c cfg : matches) {
            ids.add(cfg.Id);
        }
        return ids;
    }

    /** How many of these links have at least one event of one of the given types. */
    private static Integer countLinksWithEventType(Set<Id> configIds, Set<String> eventTypes) {
        if (configIds.isEmpty()) {
            return 0;
        }
        AggregateResult[] results = [
            SELECT COUNT_DISTINCT(Saved_Configuration__c) cnt
            FROM GTM_Link_Event__c
            WHERE Saved_Configuration__c IN :configIds
              AND Event_Type__c IN :eventTypes
        ];
        return results.isEmpty() ? 0 : (Integer) results[0].get('cnt');
    }

    private class RequestRollup {
        Integer submitted = 0;
        Decimal avgScore = 0;
        String topTier = null;
        Set<Id> requestIds = new Set<Id>();
        Map<String, Integer> statusCounts = new Map<String, Integer>();
    }

    /**
     * Submitted = any GTM_Assessment_Request__c exists for the link -- the
     * object is only ever created, with score and tier already computed,
     * the instant a prospect finishes the questionnaire (see class header,
     * issue #138). Score/tier averages and the tier-mix source set are
     * computed over EVERY request with a score/tier, not filtered by
     * Status__c -- that field is a rep follow-up pipeline stage, tracked
     * here separately in statusCounts, and says nothing about whether the
     * assessment itself is done.
     */
    private static RequestRollup requestRollupFor(Set<Id> configIds) {
        RequestRollup out = new RequestRollup();
        if (configIds.isEmpty()) {
            return out;
        }
        Decimal scoreTotal = 0;
        Integer scoredCount = 0;
        Map<String, Integer> tierCounts = new Map<String, Integer>();
        for (GTM_Assessment_Request__c req : [
            SELECT Id, Status__c, Assessment_Score__c, Assessment_Tier__c
            FROM GTM_Assessment_Request__c
            WHERE Saved_Configuration__c IN :configIds
        ]) {
            out.submitted++;
            out.requestIds.add(req.Id);

            if (String.isNotBlank(req.Status__c)) {
                Integer sn = out.statusCounts.containsKey(req.Status__c)
                    ? out.statusCounts.get(req.Status__c) : 0;
                out.statusCounts.put(req.Status__c, sn + 1);
            }
            if (req.Assessment_Score__c != null) {
                scoreTotal += req.Assessment_Score__c;
                scoredCount++;
            }
            if (String.isNotBlank(req.Assessment_Tier__c)) {
                Integer n = tierCounts.containsKey(req.Assessment_Tier__c)
                    ? tierCounts.get(req.Assessment_Tier__c) : 0;
                tierCounts.put(req.Assessment_Tier__c, n + 1);
            }
        }
        out.avgScore = scoredCount > 0 ? (scoreTotal / scoredCount).setScale(1) : 0;
        Integer best = 0;
        for (String tier : tierCounts.keySet()) {
            if (tierCounts.get(tier) > best) {
                best = tierCounts.get(tier);
                out.topTier = tier;
            }
        }
        return out;
    }

    private static List<StatusCount> statusCountsToList(Map<String, Integer> statusCounts) {
        List<StatusCount> out = new List<StatusCount>();
        for (String status : statusCounts.keySet()) {
            StatusCount sc = new StatusCount();
            sc.status = status;
            sc.count = statusCounts.get(status);
            out.add(sc);
        }
        return out;
    }

    private class ReadoutRollup {
        Integer published = 0;
        Decimal avgDaysToPublish = 0;
    }

    /** Published-readout count + average time-to-publish, for a set of source Assessment Requests. */
    private static ReadoutRollup readoutRollupFor(Set<Id> requestIds) {
        ReadoutRollup out = new ReadoutRollup();
        if (requestIds.isEmpty()) {
            return out;
        }
        Decimal totalDays = 0;
        Integer measured = 0;
        for (GTM_Readout__c r : [
            SELECT Id, Status__c, Published_Date__c,
                   Assessment_Request__r.Submitted_At__c
            FROM GTM_Readout__c
            WHERE Assessment_Request__c IN :requestIds
              AND Status__c = 'Published'
        ]) {
            out.published++;
            if (r.Published_Date__c != null && r.Assessment_Request__r.Submitted_At__c != null) {
                Long millis = r.Published_Date__c.getTime() - r.Assessment_Request__r.Submitted_At__c.getTime();
                totalDays += millis / (1000.0 * 60 * 60 * 24);
                measured++;
            }
        }
        out.avgDaysToPublish = measured > 0 ? (totalDays / measured).setScale(1) : 0;
        return out;
    }

    /**
     * Tier -> {count, pct}, over EVERY tiered request in the given id set --
     * issue #138: no longer filtered by Status__c, which is a rep follow-up
     * stage unrelated to whether the assessment produced a tier.
     */
    private static List<TierCount> tierMixFor(Set<Id> requestIds) {
        List<TierCount> mix = new List<TierCount>();
        if (requestIds.isEmpty()) {
            return mix;
        }
        Map<String, Integer> counts = new Map<String, Integer>();
        Integer total = 0;
        for (AggregateResult ar : [
            SELECT Assessment_Tier__c tier, COUNT(Id) cnt
            FROM GTM_Assessment_Request__c
            WHERE Id IN :requestIds AND Assessment_Tier__c != null
            GROUP BY Assessment_Tier__c
        ]) {
            String tier = (String) ar.get('tier');
            Integer cnt = (Integer) ar.get('cnt');
            counts.put(tier, cnt);
            total += cnt;
        }
        for (String tier : counts.keySet()) {
            TierCount tc = new TierCount();
            tc.tier = tier;
            tc.count = counts.get(tier);
            tc.pct = total > 0 ? (100.0 * counts.get(tier) / total).setScale(0) : 0;
            mix.add(tc);
        }
        return mix;
    }

    /**
     * Weekly link-opens vs. assessments-submitted, calendar-week bucketed
     * via SOQL date-function GROUP BY rather than iterating raw rows -- see
     * the class header on why this stays an aggregate query.
     */
    private static List<TrendPoint> weeklyTrend(Set<Id> configIds, Date rangeStart, Date rangeEnd) {
        Map<String, TrendPoint> byWeek = new Map<String, TrendPoint>();
        if (configIds.isEmpty()) {
            return new List<TrendPoint>();
        }
        DateTime windowStart = DateTime.newInstance(rangeStart, Time.newInstance(0, 0, 0, 0));
        DateTime windowEnd = DateTime.newInstance(rangeEnd.addDays(1), Time.newInstance(0, 0, 0, 0));

        for (AggregateResult ar : [
            SELECT CALENDAR_YEAR(CreatedDate) yr, WEEK_IN_YEAR(CreatedDate) wk, COUNT(Id) cnt
            FROM GTM_Link_Event__c
            WHERE Saved_Configuration__c IN :configIds
              AND Event_Type__c IN :OPEN_EVENT_TYPES
              AND CreatedDate >= :windowStart AND CreatedDate < :windowEnd
            GROUP BY CALENDAR_YEAR(CreatedDate), WEEK_IN_YEAR(CreatedDate)
            ORDER BY CALENDAR_YEAR(CreatedDate), WEEK_IN_YEAR(CreatedDate)
        ]) {
            String key = ar.get('yr') + '-W' + ar.get('wk');
            TrendPoint tp = weekPoint(byWeek, key, (Integer) ar.get('yr'), (Integer) ar.get('wk'));
            tp.opens = (Integer) ar.get('cnt');
        }

        for (AggregateResult ar : [
            SELECT CALENDAR_YEAR(CreatedDate) yr, WEEK_IN_YEAR(CreatedDate) wk, COUNT(Id) cnt
            FROM GTM_Assessment_Request__c
            WHERE Saved_Configuration__c IN :configIds
              AND CreatedDate >= :windowStart AND CreatedDate < :windowEnd
            GROUP BY CALENDAR_YEAR(CreatedDate), WEEK_IN_YEAR(CreatedDate)
            ORDER BY CALENDAR_YEAR(CreatedDate), WEEK_IN_YEAR(CreatedDate)
        ]) {
            String key = ar.get('yr') + '-W' + ar.get('wk');
            TrendPoint tp = weekPoint(byWeek, key, (Integer) ar.get('yr'), (Integer) ar.get('wk'));
            tp.submitted = (Integer) ar.get('cnt');
        }

        List<TrendPoint> points = byWeek.values();
        points.sort(new ByYearWeek());
        return points;
    }

    private static TrendPoint weekPoint(Map<String, TrendPoint> byWeek, String key, Integer yr, Integer wk) {
        if (!byWeek.containsKey(key)) {
            TrendPoint tp = new TrendPoint();
            tp.year = yr;
            tp.week = wk;
            tp.opens = 0;
            tp.submitted = 0;
            byWeek.put(key, tp);
        }
        return byWeek.get(key);
    }

    private class ByYearWeek implements Comparator<TrendPoint> {
        public Integer compare(TrendPoint a, TrendPoint b) {
            if (a.year != b.year) {
                return a.year - b.year;
            }
            return a.week - b.week;
        }
    }

    // ------------------------------------------------------------------ DTOs

    public class AnalyticsSummary {
        @AuraEnabled public Integer linksCreated = 0;
        @AuraEnabled public Integer linksCreatedPrior = 0;
        @AuraEnabled public Integer linksOpened = 0;
        @AuraEnabled public Integer assessmentsSubmitted = 0;
        @AuraEnabled public Integer assessmentsSubmittedPrior = 0;
        @AuraEnabled public Integer readoutsPublished = 0;
        @AuraEnabled public Integer readoutsPublishedPrior = 0;
        @AuraEnabled public Decimal avgDaysToPublish = 0;
        @AuraEnabled public Decimal avgDaysToPublishPrior = 0;
        @AuraEnabled public List<TierCount> tierMix = new List<TierCount>();
        @AuraEnabled public List<StatusCount> followUpStatusCounts = new List<StatusCount>();
        @AuraEnabled public List<TrendPoint> trend = new List<TrendPoint>();
    }

    public class TierCount {
        @AuraEnabled public String tier;
        @AuraEnabled public Integer count;
        @AuraEnabled public Decimal pct;
    }

    /** One row of the rep follow-up pipeline breakdown (Status__c on GTM_Assessment_Request__c). */
    public class StatusCount {
        @AuraEnabled public String status;
        @AuraEnabled public Integer count;
    }

    public class TrendPoint {
        @AuraEnabled public Integer year;
        @AuraEnabled public Integer week;
        @AuraEnabled public Integer opens;
        @AuraEnabled public Integer submitted;
    }

    public class OfferingRow {
        @AuraEnabled public String offering;
        @AuraEnabled public Integer links;
        @AuraEnabled public Integer submitted;
        @AuraEnabled public Decimal avgScore;
        @AuraEnabled public Integer published;
        @AuraEnabled public String topTier;
    }
}
