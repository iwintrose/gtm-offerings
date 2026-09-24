# Overview "Act today" tiles (ISSUE #overview-sales-dashboard-2-act-today)

Status: contract, pre-implementation. Piece B of the Overview split; rebases on piece A (`overview-sales-dashboard-1-layout-funnel.md`).

## 1. Apex

New class `GtmActTodayController` (`public with sharing`, read-only: SOQL/delegation only, zero DML, zero callout). Class access: `GTM_Offering_User` and `GTM_Offering_Admin` only.

```apex
@AuraEnabled(cacheable=false)
public static ActToday getActToday()

public class ActToday {
    @AuraEnabled public TileData newRequests;    // count = getAssessmentPage totalCount
    @AuraEnabled public TileData readoutWaiting; // count = getAssessmentPage totalCount
    @AuraEnabled public List<String> cameBackNames;  // names only, <=3
    @AuraEnabled public List<String> wentQuietNames; // names only, <=3
}
public class TileData {
    @AuraEnabled public Integer count;
    @AuraEnabled public Boolean capped;          // getAssessmentPage totalIsCapped
    @AuraEnabled public List<String> names;      // <=3, newest first, deduped by account
}
```

- newRequests: `GtmAssessmentListController.getAssessmentPage` with status=['new'], sortBy='submitted', sortDir='desc', pageSize=25; names from `rows[].company` (fall back `requesterName`), dedup case-insensitive, first 3.
- readoutWaiting: same with readout=['pending','approved-unsent'] (Approved AND Notification_Sent_Date__c null; Approved+notified is excluded, narrowing the owner's wording).
- hot/quiet names: `GtmLinkStageService.getLinkIdsForStage('hot'|'quiet')` (newest link first), query `GTM_Saved_Configuration__c` by Id set, name = `Account__r.Name` else `Company__c`, keep id order, dedup, first 3. NO counts returned for hot/quiet; the LWC takes them from piece A's single `getStageCountsAura()`.
- No standalone request/readout queries, no permission-set-name checks.

## 2. LWC (`gtmOverview`)

Row 1 "Act today", order: New requests, Came back, Went quiet, Readout waiting. Tile = count (with "+" when capped/truncated) + hint + up to 3 names; `role="button"`, `tabindex="0"`, click/Enter/Space navigate once. Zero: "0" + "All caught up", clickable. Counts: hot/quiet from `getStageCountsAura`, others from `getActToday`. `headerMeta` uses `newRequests.count`.

| Tile | Navigate (`standard__navItemPage`) |
|---|---|
| New requests | `GTM_Assessments`, `{c__astatus:'new'}` |
| Came back | `GTM_Pages`, `{c__stage:'hot'}` |
| Went quiet | `GTM_Pages`, `{c__stage:'quiet'}` |
| Readout waiting | `GTM_Assessments`, `{c__areadout:'pending,approved-unsent'}` |

## 3. Native evaluation
Standard report/dashboard tiles and list views cannot give names, stage definitions, view-all scoping or filtered custom-tab navigation; tiles stay custom (existing SLDS tokens, no new hex).

## 4. Retirement
Remove `Snapshot.stalledCount`, `countStalled`, related comments/tests (see task scope section 4). `grep -rn "stalledCount\|countStalled" force-app` must be empty.

## 5. Deploy-order dependency
Do not deploy to reps before `link-event-owner-fix` (guest-owned link events are invisible to reps; hot/quiet would read 0).
