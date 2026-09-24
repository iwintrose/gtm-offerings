/**
 * Single home of the funnel-stage definitions (issue stage-filter-pages-tab).
 * Contract: docs/architecture/gtm-link-stage-filter.md. Read-only: no DML, no
 * callouts, no `without sharing`. GUS and the Pages tab both call this class
 * and must NOT re-implement any definition.
 *
 * "Funnel stage" is unrelated to GTM_Saved_Configuration__c.Presentation_Stage__c.
 *
 * Universe: the Pages-tab set (Presentation_Stage__c not null / Draft /
 * Rep_Direct), owner-scoped unless the user holds viewAllRecords. Rep_Direct
 * and Draft links are in NO key. Inactive links and links without an
 * Opportunity are included.
 *
 * NOTE: this is the ONE stalled/quiet definition (the old
 * GtmHomeSnapshotController stalled count was retired by issue
 * overview-sales-dashboard-2-act-today); the getDeals() funnel remains a
 * separate per-row view.
 */
public with sharing class GtmLinkStageService {

    public static final List<String> STAGE_KEYS =
        new List<String>{ 'sent', 'engaged', 'started', 'submitted', 'quiet', 'hot', 'not_opened' };

    private static final Integer UNIVERSE_LIMIT = 50000;
    private static final Integer HOT_WINDOW_HOURS = 48;

    // Test seams only (no production caller sets these).
    @TestVisible private static Datetime nowOverride;
    @TestVisible private static Integer universeLimitOverride;

    public class StageCounts {
        @AuraEnabled public Integer sent = 0;
        @AuraEnabled public Integer engaged = 0;
        @AuraEnabled public Integer started = 0;
        @AuraEnabled public Integer submitted = 0;
        @AuraEnabled public Integer quiet = 0;
        @AuraEnabled public Integer hot = 0;
        @AuraEnabled public Integer notOpened = 0;
        @AuraEnabled public Boolean truncated = false;
    }

    public class LinkStat {
        @AuraEnabled public Id linkId;
        @AuraEnabled public Integer visits = 0;
        @AuraEnabled public Datetime lastVisitAt;
        @AuraEnabled public String funnelStage;
    }

    public class LinkStatsResult {
        @AuraEnabled public Boolean viewAll = false;
        @AuraEnabled public Boolean truncated = false;
        @AuraEnabled public List<LinkStat> stats = new List<LinkStat>();
    }

    private class LinkFacts {
        Id linkId;
        Integer pageViewRows = 0;
        Integer sessionViews = 0;      // distinct non-null sessions on Page View rows
        Integer nullSessionViews = 0;  // Page View rows with no session; each is its own visit
        Datetime lastVisitAt;
        Boolean hasFormOpened = false;
        Boolean hasSubmittedEvent = false;
        Boolean hasRequest = false;

        Boolean isSubmitted() { return hasSubmittedEvent || hasRequest; }
        Boolean isStarted() { return hasFormOpened || isSubmitted(); }
        Boolean isEngaged() { return pageViewRows > 0 || isStarted(); }
        Boolean isQuiet() { return isStarted() && !isSubmitted(); }
        Integer visits() { return sessionViews + nullSessionViews; }
        String funnelStage() {
            if (isSubmitted()) { return 'submitted'; }
            if (isStarted()) { return 'started'; }
            if (isEngaged()) { return 'engaged'; }
            return 'not_opened';
        }
        Boolean isHot(Datetime cutoff) {
            return visits() >= 2
                && lastVisitAt != null && lastVisitAt >= cutoff;
        }
    }

    private class Computation {
        List<LinkFacts> ordered = new List<LinkFacts>();
        Boolean truncated = false;
        Boolean viewAll = false;
        Datetime cutoff;
    }

    public static StageCounts getStageCounts() {
        Computation c = compute();
        StageCounts out = new StageCounts();
        out.truncated = c.truncated;
        for (LinkFacts f : c.ordered) {
            out.sent++;
            if (f.isEngaged()) { out.engaged++; } else { out.notOpened++; }
            if (f.isStarted()) { out.started++; }
            if (f.isSubmitted()) { out.submitted++; }
            if (f.isQuiet()) { out.quiet++; }
            if (f.isHot(c.cutoff)) { out.hot++; }
        }
        return out;
    }

    public static List<Id> getLinkIdsForStage(String stageKey) {
        if (String.isBlank(stageKey) || !STAGE_KEYS.contains(stageKey)) {
            throw new IllegalArgumentException(
                'Unknown funnel stage \'' + stageKey + '\'. Valid stages: '
                + String.join(STAGE_KEYS, ', ') + '.'
            );
        }
        Computation c = compute();
        List<Id> ids = new List<Id>();
        for (LinkFacts f : c.ordered) {
            Boolean match;
            switch on stageKey {
                when 'sent' { match = true; }
                when 'engaged' { match = f.isEngaged(); }
                when 'started' { match = f.isStarted(); }
                when 'submitted' { match = f.isSubmitted(); }
                when 'quiet' { match = f.isQuiet(); }
                when 'hot' { match = f.isHot(c.cutoff); }
                when else { match = !f.isEngaged(); } // not_opened
            }
            if (match) { ids.add(f.linkId); }
        }
        return ids;
    }

    public static LinkStatsResult getLinkStats() {
        Computation c = compute();
        LinkStatsResult out = new LinkStatsResult();
        out.truncated = c.truncated;
        out.viewAll = c.viewAll;
        for (LinkFacts f : c.ordered) {
            LinkStat s = new LinkStat();
            s.linkId = f.linkId;
            s.visits = f.visits();
            s.lastVisitAt = f.lastVisitAt;
            s.funnelStage = f.funnelStage();
            out.stats.add(s);
        }
        return out;
    }

    @AuraEnabled(cacheable=false)
    public static LinkStatsResult getLinkStatsAura() {
        try {
            return getLinkStats();
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static StageCounts getStageCountsAura() {
        try {
            return getStageCounts();
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Id> getLinkIdsForStageAura(String stageKey) {
        try {
            return getLinkIdsForStage(stageKey);
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    // ---- Heat grid (issue overview-bd-heat-redesign-2-heat-grid) ----------
    // Contract: docs/architecture/overview-bd-heat-redesign-2-heat-grid.md.
    // Per-Account/per-day tier aggregation over GTM_Link_Event__c for the
    // trailing 14 days, reusing this class's own tier vocabulary (Page View
    // -> engaged, Form Opened/Resumed -> started, Form Submitted or a linked
    // Assessment Request -> submitted). Read-only, no DML, no callouts, same
    // owner/view-all universe scoping as compute().

    private static final Integer HEAT_WINDOW_DAYS = 14;
    private static final List<String> HEAT_TIERS = new List<String>{ 'none', 'engaged', 'started', 'submitted' };
    private static final Map<String, Integer> TIER_WEIGHT = new Map<String, Integer>{
        'none' => 0, 'engaged' => 1, 'started' => 2, 'submitted' => 3
    };

    @TestVisible private static Date heatTodayOverride;

    public class HeatDay {
        @AuraEnabled public Date day;
        @AuraEnabled public String tier = 'none';
        @AuraEnabled public Integer intensity = 0;
    }

    public class HeatRow {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityStage;
        @AuraEnabled public List<HeatDay> days = new List<HeatDay>();
        @AuraEnabled public String latestSignal = '';
        @AuraEnabled public Datetime latestSignalAt;
        @AuraEnabled public String currentTier = 'none';
        @AuraEnabled public Decimal heatScore = 0;
        @AuraEnabled public String nextAction = 'call_now';
    }

    public class HeatGridResult {
        @AuraEnabled public Boolean truncated = false;
        @AuraEnabled public List<HeatRow> rows = new List<HeatRow>();
    }

    private class AccountFacts {
        Id accountId;
        String accountName;
        Id contactId;
        String contactName;
        Id opportunityId;
        String opportunityStage;
        Datetime latestConfigCreatedDate; // to pick the "most recent" config's contact/opp
        // day (yyyy-mm-dd string key) -> tier reached that day
        Map<String, String> dayTier = new Map<String, String>();
        Datetime latestSignalAt;
        String latestSignalTier;
    }

    public static HeatGridResult getHeatGrid() {
        HeatGridResult out = new HeatGridResult();
        Date today = heatTodayOverride != null ? heatTodayOverride : Date.today();
        Date windowStart = today.addDays(-(HEAT_WINDOW_DAYS - 1));

        Id currentUserId = UserInfo.getUserId();
        String universeWhere = 'Presentation_Stage__c != null'
            + ' AND Presentation_Stage__c != \'Draft\''
            + ' AND Presentation_Stage__c != \'Rep_Direct\''
            + ' AND Account__c != null';
        Boolean viewAll = hasViewAllRecords('GTM_Saved_Configuration__c');
        if (!viewAll) {
            universeWhere += ' AND OwnerId = :currentUserId';
        }

        List<GTM_Saved_Configuration__c> universe = Database.query(
            'SELECT Id, Account__c, Account__r.Name, Contact__c, Contact__r.Name, '
            + 'Opportunity__c, Opportunity__r.StageName, CreatedDate '
            + 'FROM GTM_Saved_Configuration__c WHERE ' + universeWhere
            + ' ORDER BY CreatedDate DESC LIMIT ' + UNIVERSE_LIMIT
        );
        out.truncated = universe.size() >= UNIVERSE_LIMIT;
        if (universe.isEmpty()) {
            return out;
        }

        Map<Id, Id> configToAccount = new Map<Id, Id>();
        Map<Id, AccountFacts> byAccount = new Map<Id, AccountFacts>();
        for (GTM_Saved_Configuration__c cfg : universe) {
            configToAccount.put(cfg.Id, cfg.Account__c);
            AccountFacts f = byAccount.get(cfg.Account__c);
            if (f == null) {
                f = new AccountFacts();
                f.accountId = cfg.Account__c;
                f.accountName = cfg.Account__r != null ? cfg.Account__r.Name : '';
                byAccount.put(cfg.Account__c, f);
            }
            // universe is ordered CreatedDate DESC, so the first config seen
            // per Account is already its most-recently-created config.
            if (f.latestConfigCreatedDate == null) {
                f.latestConfigCreatedDate = cfg.CreatedDate;
                f.contactId = cfg.Contact__c;
                f.contactName = cfg.Contact__r != null ? cfg.Contact__r.Name : '';
                f.opportunityId = cfg.Opportunity__c;
                f.opportunityStage = cfg.Opportunity__r != null ? cfg.Opportunity__r.StageName : '';
            }
        }

        Set<Id> configIds = configToAccount.keySet();
        Datetime windowStartDt = Datetime.newInstance(windowStart, Time.newInstance(0, 0, 0, 0));

        for (GTM_Link_Event__c evt : [
            SELECT Saved_Configuration__c, Event_Type__c, CreatedDate
            FROM GTM_Link_Event__c
            WHERE Saved_Configuration__c IN :configIds AND CreatedDate >= :windowStartDt
        ]) {
            applyEvent(byAccount, configToAccount, evt.Saved_Configuration__c, evt.Event_Type__c, evt.CreatedDate, today);
        }

        // Requests aggregate: a submitted Assessment Request also counts as
        // 'submitted' on its own CreatedDate, same as compute()'s hasRequest.
        for (GTM_Assessment_Request__c req : [
            SELECT Saved_Configuration__c, CreatedDate
            FROM GTM_Assessment_Request__c
            WHERE Saved_Configuration__c IN :configIds AND CreatedDate >= :windowStartDt
        ]) {
            applyEvent(byAccount, configToAccount, req.Saved_Configuration__c, 'Form Submitted', req.CreatedDate, today);
        }

        for (AccountFacts f : byAccount.values()) {
            out.rows.add(toHeatRow(f, windowStart, today));
        }
        out.rows.sort(new HeatRowComparator());
        return out;
    }

    private static void applyEvent(
        Map<Id, AccountFacts> byAccount, Map<Id, Id> configToAccount,
        Id configId, String eventType, Datetime createdAt, Date today
    ) {
        Id accountId = configToAccount.get(configId);
        if (accountId == null) { return; }
        AccountFacts f = byAccount.get(accountId);
        if (f == null) { return; }
        String tier = tierOf(eventType);
        if (tier == null) { return; }

        Date day = createdAt.date();
        String dayKey = String.valueOf(day);
        String existing = f.dayTier.get(dayKey);
        if (existing == null || TIER_WEIGHT.get(tier) > TIER_WEIGHT.get(existing)) {
            f.dayTier.put(dayKey, tier);
        }

        if (f.latestSignalAt == null || createdAt > f.latestSignalAt
            || (createdAt == f.latestSignalAt && TIER_WEIGHT.get(tier) > TIER_WEIGHT.get(f.latestSignalTier))
        ) {
            f.latestSignalAt = createdAt;
            f.latestSignalTier = tier;
        }
    }

    /** Same tier vocabulary as LinkFacts.funnelStage(): Page View -> engaged,
     *  Form Opened/Resumed -> started, Form Submitted -> submitted. Any other
     *  event type (or a request, passed in as 'Form Submitted' by the caller)
     *  is either mapped here or ignored (null). */
    private static String tierOf(String eventType) {
        if (eventType == 'Form Submitted') { return 'submitted'; }
        if (eventType == 'Form Opened' || eventType == 'Form Resumed') { return 'started'; }
        if (eventType == 'Page View') { return 'engaged'; }
        return null;
    }

    private static HeatRow toHeatRow(AccountFacts f, Date windowStart, Date today) {
        HeatRow row = new HeatRow();
        row.accountId = f.accountId;
        row.accountName = f.accountName;
        row.contactId = f.contactId;
        row.contactName = f.contactName;
        row.opportunityId = f.opportunityId;
        row.opportunityStage = f.opportunityStage;

        for (Integer i = 0; i < HEAT_WINDOW_DAYS; i++) {
            Date day = windowStart.addDays(i);
            HeatDay hd = new HeatDay();
            hd.day = day;
            hd.tier = f.dayTier.containsKey(String.valueOf(day)) ? f.dayTier.get(String.valueOf(day)) : 'none';
            hd.intensity = TIER_WEIGHT.get(hd.tier);
            row.days.add(hd);
        }

        row.latestSignalAt = f.latestSignalAt;
        row.currentTier = f.latestSignalTier != null ? f.latestSignalTier : 'none';
        row.latestSignal = latestSignalLabel(row.currentTier, f.latestSignalAt, today);
        Integer daysSince = f.latestSignalAt != null ? f.latestSignalAt.date().daysBetween(today) : HEAT_WINDOW_DAYS;
        row.heatScore = (TIER_WEIGHT.get(row.currentTier) * 100) - daysSince;
        row.nextAction = nextActionFor(row.currentTier);
        return row;
    }

    private static String latestSignalLabel(String tier, Datetime at, Date today) {
        if (at == null) { return 'No activity in the last 14 days'; }
        String verb;
        if (tier == 'submitted') { verb = 'Assessment submitted'; }
        else if (tier == 'started') { verb = 'Assessment started'; }
        else { verb = 'Page viewed'; }
        Integer daysAgo = at.date().daysBetween(today);
        String whenLabel = daysAgo <= 0 ? 'today' : daysAgo == 1 ? 'yesterday' : daysAgo + ' days ago';
        return verb + ' ' + whenLabel;
    }

    /** 'submitted'->'nudge' (OUT OF SCOPE, rendered disabled by the LWC),
     *  'started'->'follow_up' (real Task action), everything else (cold or
     *  merely 'engaged')->'call_now' (real Log-a-Call action). */
    private static String nextActionFor(String currentTier) {
        if (currentTier == 'submitted') { return 'nudge'; }
        if (currentTier == 'started') { return 'follow_up'; }
        return 'call_now';
    }

    private class HeatRowComparator implements Comparator<HeatRow> {
        public Integer compare(HeatRow a, HeatRow b) {
            if (a.heatScore != b.heatScore) {
                return a.heatScore > b.heatScore ? -1 : 1;
            }
            Datetime aAt = a.latestSignalAt;
            Datetime bAt = b.latestSignalAt;
            if (aAt != bAt) {
                if (aAt == null) { return 1; }
                if (bAt == null) { return -1; }
                return aAt > bAt ? -1 : 1;
            }
            return String.valueOf(a.accountName).compareTo(String.valueOf(b.accountName));
        }
    }

    @AuraEnabled(cacheable=false)
    public static HeatGridResult getHeatGridAura() {
        try {
            return getHeatGrid();
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    /**
     * The one computation: universe query, events aggregate, requests
     * aggregate (three data queries, plus the permission probe).
     */
    private static Computation compute() {
        Computation result = new Computation();
        Datetime now = nowOverride != null ? nowOverride : System.now();
        result.cutoff = now.addHours(-HOT_WINDOW_HOURS);
        Integer cap = universeLimitOverride != null ? universeLimitOverride : UNIVERSE_LIMIT;

        Id currentUserId = UserInfo.getUserId();
        String universeWhere = 'Presentation_Stage__c != null'
            + ' AND Presentation_Stage__c != \'Draft\''
            + ' AND Presentation_Stage__c != \'Rep_Direct\'';
        result.viewAll = hasViewAllRecords('GTM_Saved_Configuration__c');
        if (!result.viewAll) {
            universeWhere += ' AND OwnerId = :currentUserId';
        }

        // 1. Universe (Ids only).
        Map<Id, LinkFacts> byId = new Map<Id, LinkFacts>();
        List<GTM_Saved_Configuration__c> universe = Database.query(
            'SELECT Id FROM GTM_Saved_Configuration__c WHERE ' + universeWhere
            + ' ORDER BY CreatedDate DESC LIMIT ' + cap
        );
        for (GTM_Saved_Configuration__c link : universe) {
            LinkFacts f = new LinkFacts();
            f.linkId = link.Id;
            byId.put(link.Id, f);
            result.ordered.add(f);
        }
        result.truncated = universe.size() >= cap;
        if (byId.isEmpty()) {
            return result;
        }

        String semiJoin = 'Saved_Configuration__c IN (SELECT Id FROM GTM_Saved_Configuration__c WHERE '
            + universeWhere + ')';

        // 2. Events aggregate. Dynamic SOQL keeps Saved_Configuration__c out of
        // the compile-time dependency graph (repo convention).
        for (AggregateResult ar : Database.query(
            'SELECT Saved_Configuration__c cfg, Event_Type__c evt, COUNT(Id) n, '
            + 'COUNT(Session_Id__c) nSess, COUNT_DISTINCT(Session_Id__c) dSess, '
            + 'MAX(CreatedDate) lastAt '
            + 'FROM GTM_Link_Event__c WHERE ' + semiJoin
            + ' GROUP BY Saved_Configuration__c, Event_Type__c'
        )) {
            LinkFacts f = byId.get((Id) ar.get('cfg'));
            if (f == null) { continue; } // beyond a truncated universe
            String evt = (String) ar.get('evt');
            Integer n = (Integer) ar.get('n');
            Datetime lastAt = (Datetime) ar.get('lastAt');
            if (evt == 'Page View') {
                f.pageViewRows += n;
                f.sessionViews += (Integer) ar.get('dSess');
                f.nullSessionViews += n - (Integer) ar.get('nSess');
            }
            if (evt == 'Page View' || evt == 'Form Resumed') {
                if (f.lastVisitAt == null || lastAt > f.lastVisitAt) { f.lastVisitAt = lastAt; }
            }
            if (evt == 'Form Opened' || evt == 'Form Resumed') { f.hasFormOpened = true; }
            if (evt == 'Form Submitted') { f.hasSubmittedEvent = true; }
        }

        // 3. Requests aggregate.
        for (AggregateResult ar : Database.query(
            'SELECT Saved_Configuration__c cfg, COUNT(Id) n '
            + 'FROM GTM_Assessment_Request__c WHERE ' + semiJoin
            + ' GROUP BY Saved_Configuration__c'
        )) {
            LinkFacts f = byId.get((Id) ar.get('cfg'));
            if (f != null) { f.hasRequest = true; }
        }
        return result;
    }

    /**
     * PRIVATE COPY of the owd-2 helper in GtmSavedConfigurationController:
     * does the running user hold viewAllRecords on the object via ANY assigned
     * permission set. TODO: de-duplicate onto the shared helper when
     * rep-data-scoping-owd-3 lands. Deliberately NOT
     * GtmHomeSnapshotController.isAdmin() (permission-set-name check), so this
     * service and the Pages tile grid never disagree about who sees everything.
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
}
