/**
 * Aggregate KPIs for the GTM Offerings app's landing page -- one cacheable
 * read, no per-record data, so it's safe to show org-wide regardless of
 * who's looking.
 */
public with sharing class GtmHomeSnapshotController {
    public class Snapshot {
        @AuraEnabled public Integer activeEngagementCount { get; set; }
        @AuraEnabled public Integer newAssessmentCount    { get; set; }
        @AuraEnabled public Integer recentViews          { get; set; }
        // Not "submissions": that is the same fact as newAssessmentCount, one
        // counted as an event and one as the record it produced, and two
        // tiles for one fact read as two facts. This is the number neither of
        // them can give you -- someone opened the form and did not finish --
        // which is the only one of the four that names work nobody is doing.
        @AuraEnabled public Integer stalledCount { get; set; }
    }

    @AuraEnabled(cacheable=false)
    public static Snapshot getSnapshot() {
        Snapshot snap = new Snapshot();

        snap.activeEngagementCount = [
            SELECT COUNT() FROM MA_Saved_Configuration__c WHERE Active__c = true
        ];

        snap.newAssessmentCount = [
            SELECT COUNT() FROM GTM_Assessment_Request__c WHERE Status__c = 'New'
        ];

        snap.recentViews = [
            SELECT COUNT() FROM GTM_Link_Event__c
            WHERE Event_Type__c = 'Page View'
            AND CreatedDate = LAST_N_DAYS:7
        ];

        snap.stalledCount = countStalled();

        return snap;
    }

    /**
     * Links where the form was opened and never submitted.
     *
     * Two aggregates rather than a semi-join, because a semi-join cannot ask
     * "has an event of this type and not one of that type" in one SOQL, and
     * the alternative -- a query per link -- is a governor limit waiting for
     * the tenth deal.
     */
    private static Integer countStalled() {
        Set<Id> opened = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Saved_Configuration__c cfg FROM GTM_Link_Event__c
            WHERE Event_Type__c = 'Form Opened' AND Saved_Configuration__c != null
            GROUP BY Saved_Configuration__c
        ]) {
            opened.add((Id) ar.get('cfg'));
        }
        if (opened.isEmpty()) return 0;

        for (AggregateResult ar : [
            SELECT Saved_Configuration__c cfg FROM GTM_Link_Event__c
            WHERE Event_Type__c = 'Form Submitted' AND Saved_Configuration__c IN :opened
            GROUP BY Saved_Configuration__c
        ]) {
            opened.remove((Id) ar.get('cfg'));
        }
        return opened.size();
    }

    public class RequestSummary {
        @AuraEnabled public Id      recordId      { get; set; }
        @AuraEnabled public String  name          { get; set; }
        @AuraEnabled public String  requesterName { get; set; }
        @AuraEnabled public String  company       { get; set; }
        @AuraEnabled public String  platform      { get; set; }
        @AuraEnabled public Datetime createdDate  { get; set; }
    }

    /** The 5 newest requests still at Status = New, ordered newest first. */
    @AuraEnabled(cacheable=false)
    public static List<RequestSummary> getRecentNewAssessmentRequests() {
        List<RequestSummary> results = new List<RequestSummary>();
        for (GTM_Assessment_Request__c req : [
            SELECT Id, Name, Requester_Name__c, Company__c,
                   Current_Platform__c, CreatedDate
            FROM GTM_Assessment_Request__c
            WHERE Status__c = 'New'
            ORDER BY CreatedDate DESC
            LIMIT 5
        ]) {
            RequestSummary s = new RequestSummary();
            s.recordId      = req.Id;
            s.name          = req.Name;
            s.requesterName = req.Requester_Name__c;
            s.company       = req.Company__c;
            s.platform      = req.Current_Platform__c;
            s.createdDate   = req.CreatedDate;
            results.add(s);
        }
        return results;
    }

    /**
     * One deal, with everything that has happened on the page sent for it.
     *
     * The overview used to show requests and a submissions count and nothing
     * that named the deal either belonged to, so a BD read "3 submissions" and
     * still had to go looking for whose. A deal is what they actually work, so
     * it is the row: the opportunity, the link sent for it, what the recipient
     * did with that link, and the request if one came back.
     */
    public class DealSummary {
        @AuraEnabled public Id       configId        { get; set; }
        @AuraEnabled public String   configName      { get; set; }
        @AuraEnabled public Boolean  linkActive      { get; set; }
        @AuraEnabled public Id       opportunityId   { get; set; }
        @AuraEnabled public String   opportunityName { get; set; }
        @AuraEnabled public String   stageName       { get; set; }
        @AuraEnabled public Decimal  amount          { get; set; }
        @AuraEnabled public Date     closeDate       { get; set; }
        @AuraEnabled public String   accountName     { get; set; }
        @AuraEnabled public String   company         { get; set; }
        @AuraEnabled public String   industryLabel   { get; set; }
        // The funnel, in the order it happens. Counted rather than flagged for
        // views because a second visit is the signal a first visit is not.
        @AuraEnabled public Integer  views           { get; set; }
        @AuraEnabled public Boolean  formOpened      { get; set; }
        @AuraEnabled public Boolean  formSubmitted   { get; set; }
        @AuraEnabled public Boolean  droppedOff      { get; set; }
        @AuraEnabled public Datetime lastActivity    { get; set; }
        @AuraEnabled public Id       requestId       { get; set; }
        @AuraEnabled public String   requestName     { get; set; }
        @AuraEnabled public String   requestStatus   { get; set; }
    }

    /**
     * Every deal a page has been prepared for, newest first.
     *
     * with sharing, and the opportunity fields come through the relationship,
     * so a user who cannot see a deal does not see it here either.
     */
    @AuraEnabled(cacheable=false)
    public static List<DealSummary> getDeals() {
        Map<Id, DealSummary> byConfig = new Map<Id, DealSummary>();

        for (MA_Saved_Configuration__c cfg : [
            SELECT Id, Name, Active__c, Company__c, Industry_Label__c,
                   Opportunity__c, Opportunity__r.Name, Opportunity__r.StageName,
                   Opportunity__r.Amount, Opportunity__r.CloseDate,
                   Account__r.Name, CreatedDate
            FROM   MA_Saved_Configuration__c
            WHERE  Opportunity__c != null
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]) {
            DealSummary d = new DealSummary();
            d.configId        = cfg.Id;
            d.configName      = cfg.Name;
            d.linkActive      = cfg.Active__c;
            d.opportunityId   = cfg.Opportunity__c;
            d.opportunityName = cfg.Opportunity__r.Name;
            d.stageName       = cfg.Opportunity__r.StageName;
            d.amount          = cfg.Opportunity__r.Amount;
            d.closeDate       = cfg.Opportunity__r.CloseDate;
            d.accountName     = cfg.Account__r != null ? cfg.Account__r.Name : null;
            d.company         = cfg.Company__c;
            d.industryLabel   = cfg.Industry_Label__c;
            d.views           = 0;
            d.formOpened      = false;
            d.formSubmitted   = false;
            d.droppedOff      = false;
            byConfig.put(cfg.Id, d);
        }
        if (byConfig.isEmpty()) return new List<DealSummary>();

        Set<Id> configIds = byConfig.keySet();
        for (AggregateResult ar : [
            SELECT Saved_Configuration__c cfg, Event_Type__c evt,
                   COUNT(Id) n, MAX(CreatedDate) lastAt
            FROM   GTM_Link_Event__c
            WHERE  Saved_Configuration__c IN :configIds
            GROUP BY Saved_Configuration__c, Event_Type__c
        ]) {
            DealSummary d = byConfig.get((Id) ar.get('cfg'));
            if (d == null) continue;
            String evt = (String) ar.get('evt');
            Integer n  = (Integer) ar.get('n');
            if (evt == 'Page View')           d.views = n;
            else if (evt == 'Form Opened')    d.formOpened = true;
            else if (evt == 'Form Submitted') d.formSubmitted = true;
            else if (evt == 'Drop-off')       d.droppedOff = true;

            Datetime lastAt = (Datetime) ar.get('lastAt');
            if (lastAt != null && (d.lastActivity == null || lastAt > d.lastActivity)) {
                d.lastActivity = lastAt;
            }
        }

        // Newest request wins: a prospect who filled the form twice is telling
        // you about the second one.
        for (GTM_Assessment_Request__c req : [
            SELECT Id, Name, Status__c, Saved_Configuration__c
            FROM   GTM_Assessment_Request__c
            WHERE  Saved_Configuration__c IN :configIds
            ORDER BY CreatedDate ASC
        ]) {
            DealSummary d = byConfig.get(req.Saved_Configuration__c);
            if (d == null) continue;
            d.requestId     = req.Id;
            d.requestName   = req.Name;
            d.requestStatus = req.Status__c;
        }

        return byConfig.values();
    }

    /** One chapter of a page, and what visitors did with it. */
    public class SitemapNode {
        @AuraEnabled public String  sectionKey  { get; set; }
        @AuraEnabled public String  label       { get; set; }
        @AuraEnabled public Decimal sortOrder   { get; set; }
        @AuraEnabled public Integer readers     { get; set; }
        @AuraEnabled public Decimal totalDwell  { get; set; }
        @AuraEnabled public Decimal avgDwell    { get; set; }
        @AuraEnabled public Integer clicks      { get; set; }
        @AuraEnabled public Boolean isLastSeen  { get; set; }
    }

    /**
     * The interaction sitemap for one engagement link.
     *
     * A page view says the link was opened. It does not say whether the proof
     * panel was reached or the closing ask was ever seen, which is the part a
     * BD can act on -- and "where did they stop reading" is a different and
     * better question than "did they convert".
     *
     * Marketing Cloud Personalization and Adobe both need a sitemap for this:
     * a hand-maintained map of URLs to named page types, kept in step with the
     * site by somebody. Here the page is already stored as ordered, named
     * sections, so the sitemap is the page's own structure and cannot drift
     * from it.
     */
    @AuraEnabled(cacheable=false)
    public static List<SitemapNode> getLinkSitemap(String configId) {
        List<SitemapNode> out = new List<SitemapNode>();
        if (String.isBlank(configId)) return out;

        List<MA_Saved_Configuration__c> cfg = [
            SELECT Offering__c, Industry__c
            FROM MA_Saved_Configuration__c WHERE Id = :configId LIMIT 1
        ];
        if (cfg.isEmpty()) return out;
        // The one industry section this link's reader is shown. The others are
        // structurally unreachable for this link, so listing them would be six
        // rows of zero that mean nothing went wrong.
        String ownIndustry = String.isBlank(cfg[0].Industry__c)
            ? null : 'industry-' + cfg[0].Industry__c;

        // The sections of the page this link points at, in the order it draws
        // them: the map has to include chapters nobody reached, because those
        // are the finding.
        Map<String, SitemapNode> byKey = new Map<String, SitemapNode>();
        for (GTM_Page_Section__c sec : [
            SELECT Section_Key__c, Label__c, Sort_Order__c, Layout_Type__c
            FROM   GTM_Page_Section__c
            WHERE  Offering_Key__c  = :cfg[0].Offering__c
            AND    Template_Type__c = 'configurator'
            AND    Active__c = true AND Status__c = 'Published'
            ORDER BY Sort_Order__c ASC NULLS LAST
            LIMIT  200
        ]) {
            // Only what a reader can actually land on. The assistant is a
            // control, the defaults are settings, and neither is a beat of the
            // page -- a map that lists them reports 0 readers on things that
            // have no readers by design.
            if (sec.Layout_Type__c == 'assistant'
                || sec.Layout_Type__c == 'offering-defaults') continue;
            if (sec.Layout_Type__c == 'industry-profile'
                && sec.Section_Key__c != ownIndustry) continue;

            SitemapNode n = new SitemapNode();
            n.sectionKey = sec.Section_Key__c;
            n.label      = sec.Layout_Type__c == 'industry-profile'
                ? sec.Label__c + ' (cover)' : sec.Label__c;
            n.sortOrder  = sec.Sort_Order__c;
            n.readers    = 0;
            n.clicks     = 0;
            n.totalDwell = 0;
            n.avgDwell   = 0;
            n.isLastSeen = false;
            byKey.put(sec.Section_Key__c, n);
            out.add(n);
        }
        if (out.isEmpty()) return out;

        for (AggregateResult ar : [
            SELECT Step__c step, Event_Type__c evt,
                   COUNT_DISTINCT(Session_Id__c) sessions, COUNT(Id) hits, SUM(Dwell_Seconds__c) dwell
            FROM   GTM_Link_Event__c
            WHERE  Saved_Configuration__c = :configId AND Step__c != null
            GROUP BY Step__c, Event_Type__c
        ]) {
            SitemapNode n = byKey.get((String) ar.get('step'));
            if (n == null) continue;
            String evt = (String) ar.get('evt');
            if (evt == 'Section Viewed') {
                n.readers    = (Integer) ar.get('sessions');
                Decimal d    = (Decimal) ar.get('dwell');
                n.totalDwell = d == null ? 0 : d.setScale(1);
                n.avgDwell   = n.readers > 0 ? (n.totalDwell / n.readers).setScale(1) : 0;
            } else if (evt == 'CTA Clicked') {
                n.clicks = (Integer) ar.get('hits');
            }
        }

        // Where reading stops is the finding, so it is marked rather than left
        // for someone to spot by comparing numbers down a column.
        Integer best = 0;
        for (SitemapNode n : out) if (n.readers > best) best = n.readers;
        SitemapNode lastReached = null;
        for (SitemapNode n : out) if (n.readers > 0) lastReached = n;
        if (lastReached != null && best > 0 && lastReached.sortOrder != null) {
            lastReached.isLastSeen = true;
        }
        return out;
    }
}
