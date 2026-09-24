/**
 * Aggregate KPIs for the GTM Offerings app's landing page.
 *
 * `GTM_Assessment_Request__c` and `GTM_Link_Event__c` are Private OWD
 * (rep-data-scoping-owd-1). `with sharing` alone means a non-admin rep's
 * queries here are already implicitly limited to records they own, but
 * every widget below also adds an explicit `WHERE OwnerId = :UserInfo
 * .getUserId()` as defense-in-depth, so the scoping is provable from the
 * query text and does not silently regress if the object's sharing model
 * is ever changed again. An admin (detected via the `GTM_Offering_Admin`
 * permission set, which already grants `viewAllRecords=true` on both
 * objects) bypasses the explicit filter and sees every rep's records, same
 * as `GtmAnalyticsTeamController`.
 */
public with sharing class GtmHomeSnapshotController {

    /**
     * Whether the running user should see org-wide data rather than just
     * their own -- checked directly against the permission set assignment
     * that grants `viewAllRecords=true` on `GTM_Assessment_Request__c` /
     * `GTM_Link_Event__c`, same pattern as
     * `GtmAnalyticsTeamController.hasTeamAccess()`.
     */
    private static Boolean isAdmin() {
        return ![
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND PermissionSet.Name = 'GTM_Offering_Admin'
            LIMIT 1
        ].isEmpty();
    }
    public class Snapshot {
        @AuraEnabled public Integer activeEngagementCount { get; set; }
        @AuraEnabled public Integer newAssessmentCount    { get; set; }
        @AuraEnabled public Integer recentViews          { get; set; }
    }

    @AuraEnabled(cacheable=false)
    public static Snapshot getSnapshot() {
        Snapshot snap = new Snapshot();
        Boolean admin = isAdmin();
        Id runningUserId = UserInfo.getUserId();

        snap.activeEngagementCount = [
            SELECT COUNT() FROM GTM_Saved_Configuration__c WHERE Active__c = true
        ];

        snap.newAssessmentCount = admin
            ? [SELECT COUNT() FROM GTM_Assessment_Request__c WHERE Status__c = 'New']
            : [
                SELECT COUNT() FROM GTM_Assessment_Request__c
                WHERE Status__c = 'New' AND OwnerId = :runningUserId
            ];

        snap.recentViews = admin
            ? [
                SELECT COUNT() FROM GTM_Link_Event__c
                WHERE Event_Type__c = 'Page View'
                AND CreatedDate = LAST_N_DAYS:7
            ]
            : [
                SELECT COUNT() FROM GTM_Link_Event__c
                WHERE Event_Type__c = 'Page View'
                AND CreatedDate = LAST_N_DAYS:7
                AND OwnerId = :runningUserId
            ];

        return snap;
    }

    public class RequestSummary {
        @AuraEnabled public Id      recordId      { get; set; }
        @AuraEnabled public String  name          { get; set; }
        @AuraEnabled public String  requesterName { get; set; }
        @AuraEnabled public String  company       { get; set; }
        @AuraEnabled public String  platform      { get; set; }
        @AuraEnabled public Datetime createdDate  { get; set; }
        // Added for issue overview-redesign-funnel-drilldown -- the panel's
        // "requested"-stage rows show a bit more than name/company/date. All
        // three already exist on GTM_Assessment_Request__c and are already
        // FLS-granted on the User/Admin permission sets, so no new field or
        // permission-set work was needed.
        @AuraEnabled public String  assessmentTier  { get; set; }
        @AuraEnabled public Decimal assessmentScore { get; set; }
        @AuraEnabled public String  offeringKey     { get; set; }
    }

    /**
     * The 5 newest requests still at Status = New, ordered newest first.
     *
     * Explicitly `OwnerId`-scoped (unless the running user is a
     * GTM_Offering_Admin) so requester/company PII from another rep's
     * submissions is never returned here, on top of the object's Private
     * OWD.
     */
    @AuraEnabled(cacheable=false)
    public static List<RequestSummary> getRecentNewAssessmentRequests() {
        List<RequestSummary> results = new List<RequestSummary>();
        Boolean admin = isAdmin();
        Id runningUserId = UserInfo.getUserId();
        List<GTM_Assessment_Request__c> requests = admin
            ? [
                SELECT Id, Name, Requester_Name__c, Company__c,
                       Current_Platform__c, CreatedDate,
                       Assessment_Tier__c, Assessment_Score__c, Offering_Key__c
                FROM GTM_Assessment_Request__c
                WHERE Status__c = 'New'
                ORDER BY CreatedDate DESC
                LIMIT 5
            ]
            : [
                SELECT Id, Name, Requester_Name__c, Company__c,
                       Current_Platform__c, CreatedDate,
                       Assessment_Tier__c, Assessment_Score__c, Offering_Key__c
                FROM GTM_Assessment_Request__c
                WHERE Status__c = 'New' AND OwnerId = :runningUserId
                ORDER BY CreatedDate DESC
                LIMIT 5
            ];
        for (GTM_Assessment_Request__c req : requests) {
            RequestSummary s = new RequestSummary();
            s.recordId        = req.Id;
            s.name            = req.Name;
            s.requesterName   = req.Requester_Name__c;
            s.company         = req.Company__c;
            s.platform        = req.Current_Platform__c;
            s.createdDate     = req.CreatedDate;
            s.assessmentTier  = req.Assessment_Tier__c;
            s.assessmentScore = req.Assessment_Score__c;
            s.offeringKey     = req.Offering_Key__c;
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
        @AuraEnabled public Id       accountId       { get; set; }
        @AuraEnabled public String   accountName     { get; set; }
        @AuraEnabled public Id       contactId       { get; set; }
        @AuraEnabled public String   contactName     { get; set; }
        @AuraEnabled public String   company         { get; set; }
        @AuraEnabled public String   industryLabel   { get; set; }
        // Issue opportunities-table-redesign-v2, Architect addendum
        // Resolution 3: Offering__c is a plain text key (no lookup to
        // GTM_Offering__mdt), resolved to a human-readable label the same
        // way GtmPageContentController.getOfferings()/getHomeSummary()
        // already do -- a supplemental GTM_Offering__mdt query, joined by
        // Offering_Key__c, falling back to the raw key when no metadata
        // record matches yet.
        @AuraEnabled public String   offeringLabel   { get; set; }
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
        @AuraEnabled public Datetime requestSubmittedAt { get; set; }
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

        // Resolution 3 (Architect addendum): the existing, established
        // convention for resolving an offering key to its human-readable
        // label -- GTM_Offering__mdt, keyed by Offering_Key__c, falling
        // back to the raw key when no metadata record matches yet. Built
        // once per call, exactly as GtmPageContentController.getOfferings()
        // does.
        Map<String, String> offeringLabels = new Map<String, String>();
        for (GTM_Offering__mdt off : [
            SELECT Offering_Key__c, Label__c FROM GTM_Offering__mdt
        ]) {
            offeringLabels.put(off.Offering_Key__c, off.Label__c);
        }

        for (GTM_Saved_Configuration__c cfg : [
            SELECT Id, Name, Active__c, Company__c, Industry_Label__c, Offering__c,
                   Opportunity__c, Opportunity__r.Name, Opportunity__r.StageName,
                   Opportunity__r.Amount, Opportunity__r.CloseDate,
                   Account__c, Account__r.Name, Contact__c, Contact__r.Name, CreatedDate
            FROM   GTM_Saved_Configuration__c
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
            d.accountId       = cfg.Account__c;
            d.accountName     = cfg.Account__r != null ? cfg.Account__r.Name : null;
            d.contactId       = cfg.Contact__c;
            d.contactName     = cfg.Contact__r != null ? cfg.Contact__r.Name : null;
            d.company         = cfg.Company__c;
            d.industryLabel   = cfg.Industry_Label__c;
            d.offeringLabel   = offeringLabels.containsKey(cfg.Offering__c)
                ? offeringLabels.get(cfg.Offering__c) : cfg.Offering__c;
            d.views           = 0;
            d.formOpened      = false;
            d.formSubmitted   = false;
            d.droppedOff      = false;
            byConfig.put(cfg.Id, d);
        }
        if (byConfig.isEmpty()) return new List<DealSummary>();

        Set<Id> configIds = byConfig.keySet();
        // Saved_Configuration__c is queried dynamically, not through typed
        // SOQL: a static reference to this Lookup blocks the delete-and-recreate
        // needed to repoint its referenceTo.
        for (AggregateResult ar : Database.query(
            'SELECT Saved_Configuration__c cfg, Event_Type__c evt, ' +
            '       COUNT(Id) n, MAX(CreatedDate) lastAt ' +
            'FROM   GTM_Link_Event__c ' +
            'WHERE  Saved_Configuration__c IN :configIds ' +
            'GROUP BY Saved_Configuration__c, Event_Type__c'
        )) {
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
        // you about the second one. Saved_Configuration__c queried
        // dynamically (a static reference blocks repointing the Lookup).
        for (SObject req : Database.query(
            'SELECT Id, Name, Status__c, Saved_Configuration__c, ' +
            '       Submitted_At__c, CreatedDate ' +
            'FROM   GTM_Assessment_Request__c ' +
            'WHERE  Saved_Configuration__c IN :configIds ' +
            'ORDER BY CreatedDate ASC'
        )) {
            DealSummary d = byConfig.get((Id) req.get('Saved_Configuration__c'));
            if (d == null) continue;
            d.requestId     = (Id) req.get('Id');
            d.requestName   = (String) req.get('Name');
            d.requestStatus = (String) req.get('Status__c');
            // Submitted_At__c is the correct field for "when this was
            // submitted" (Architect addendum, task-scope §1 Col 3) --
            // CreatedDate is only the request record's own creation time,
            // used here as a fallback for any submitted request where
            // Submitted_At__c is not yet populated.
            Datetime submittedAt = (Datetime) req.get('Submitted_At__c');
            d.requestSubmittedAt = submittedAt != null
                ? submittedAt : (Datetime) req.get('CreatedDate');
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

        List<GTM_Saved_Configuration__c> cfg = [
            SELECT Offering__c, Industry__c
            FROM GTM_Saved_Configuration__c WHERE Id = :configId LIMIT 1
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

        // Saved_Configuration__c is queried dynamically, not through typed
        // SOQL: a static reference to this Lookup blocks the delete-and-recreate
        // needed to repoint its referenceTo.
        for (AggregateResult ar : Database.query(
            'SELECT Step__c step, Event_Type__c evt, ' +
            '       COUNT_DISTINCT(Session_Id__c) sessions, COUNT(Id) hits, SUM(Dwell_Seconds__c) dwell ' +
            'FROM   GTM_Link_Event__c ' +
            'WHERE  Saved_Configuration__c = :configId AND Step__c != null ' +
            'GROUP BY Step__c, Event_Type__c'
        )) {
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
