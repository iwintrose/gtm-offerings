/**
 * The "Act today" strip on the Overview (issue
 * overview-sales-dashboard-2-act-today). Read-only: no DML, no callouts, no
 * standalone request/readout queries.
 *
 * The New requests and Readout waiting tiles DELEGATE to
 * GtmAssessmentListController.getAssessmentPage, so a tile count is the same
 * number, from the same code path and scoping (request owner / view-all), as
 * the list it opens. Came back / Went quiet contribute NAMES only, taken from
 * GtmLinkStageService.getLinkIdsForStage; their COUNTS come from the LWC's one
 * getStageCountsAura() call and are never re-derived here.
 *
 * Contract: docs/architecture/overview-sales-dashboard-2-act-today.md
 */
public with sharing class GtmActTodayController {

    public static final Integer MAX_NAMES = 3;
    /** Rows requested so account-level de-duplication still finds 3 names. */
    public static final Integer NAME_PAGE_SIZE = 25;
    /** Link ids resolved to names for hot/quiet (newest first). */
    public static final Integer LINK_ID_WINDOW = 50;

    public class TileData {
        @AuraEnabled public Integer count = 0;
        @AuraEnabled public Boolean capped = false;
        @AuraEnabled public List<String> names = new List<String>();
    }

    public class ActToday {
        @AuraEnabled public TileData newRequests = new TileData();
        @AuraEnabled public TileData readoutWaiting = new TileData();
        @AuraEnabled public List<String> cameBackNames = new List<String>();
        @AuraEnabled public List<String> wentQuietNames = new List<String>();
    }

    @AuraEnabled(cacheable=false)
    public static ActToday getActToday() {
        try {
            ActToday out = new ActToday();
            out.newRequests = assessmentTile(new List<String>{ 'new' }, null);
            out.readoutWaiting = assessmentTile(null, new List<String>{ 'pending', 'approved-unsent' });
            out.cameBackNames = stageNames('hot');
            out.wentQuietNames = stageNames('quiet');
            return out;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    private static TileData assessmentTile(List<String> statuses, List<String> readouts) {
        GtmAssessmentListController.AssessmentQuery q = new GtmAssessmentListController.AssessmentQuery();
        q.status = statuses;
        q.readout = readouts;
        q.sortBy = 'submitted';
        q.sortDir = 'desc';
        q.offset = 0;
        q.pageSize = NAME_PAGE_SIZE;
        GtmAssessmentListController.AssessmentPage page = GtmAssessmentListController.getAssessmentPage(q);

        TileData tile = new TileData();
        tile.count = page.totalCount;
        tile.capped = page.totalIsCapped == true;
        List<String> candidates = new List<String>();
        for (GtmAssessmentListController.AssessmentRow row : page.rows) {
            candidates.add(String.isNotBlank(row.company) ? row.company : row.requesterName);
        }
        tile.names = firstDistinct(candidates);
        return tile;
    }

    /** Names for the link ids of one stage, newest link first, de-duplicated. */
    private static List<String> stageNames(String stageKey) {
        List<Id> allIds = GtmLinkStageService.getLinkIdsForStage(stageKey);
        if (allIds.isEmpty()) { return new List<String>(); }
        List<Id> window = new List<Id>();
        for (Integer i = 0; i < allIds.size() && i < LINK_ID_WINDOW; i++) {
            window.add(allIds[i]);
        }
        Map<Id, GTM_Saved_Configuration__c> configs = new Map<Id, GTM_Saved_Configuration__c>([
            SELECT Id, Company__c, Account__r.Name
            FROM GTM_Saved_Configuration__c
            WHERE Id IN :window
        ]);
        List<String> candidates = new List<String>();
        for (Id linkId : window) {
            GTM_Saved_Configuration__c cfg = configs.get(linkId);
            if (cfg == null) { continue; }
            String accountName = cfg.Account__r == null ? null : cfg.Account__r.Name;
            candidates.add(String.isNotBlank(accountName) ? accountName : cfg.Company__c);
        }
        return firstDistinct(candidates);
    }

    /** Order-preserving, case-insensitive de-dup; blanks skipped; max 3. */
    @TestVisible
    private static List<String> firstDistinct(List<String> candidates) {
        List<String> out = new List<String>();
        Set<String> seen = new Set<String>();
        for (String name : candidates) {
            if (String.isBlank(name)) { continue; }
            String trimmed = name.trim();
            if (!seen.add(trimmed.toLowerCase())) { continue; }
            out.add(trimmed);
            if (out.size() >= MAX_NAMES) { break; }
        }
        return out;
    }
}
