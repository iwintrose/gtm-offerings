# `GtmLinkStageService` — Shared Funnel-Stage Definitions

Status: Accepted (issue `stage-filter-pages-tab`, phase 1 backend)

## Problem

The Overview funnel, the Pages-tab stage filter and the GUS chat tool
(`gus-stage-filter-tool`) must all agree on which links are "engaged",
"went quiet", "came back" and so on, and the count shown for a stage must equal
the length of the list shown for that stage. The definitions therefore live in
ONE server-side Apex class. Nothing else (LWC, GUS) re-implements them.

"Funnel stage" is UNRELATED to `GTM_Saved_Configuration__c.Presentation_Stage__c`
(the BD workflow stage: Assessment, In_Review, Draft, Sent, Rep_Direct). The URL
parameter is `c__stage` and always means funnel stage.

Native alternatives considered (list views, roll-up summaries, reports) cannot
express child-event aggregates, distinct sessions, a rolling 48h window or
"Form Submitted event OR linked request", and cannot hand the same id list to the
Pages tab and GUS. Row-level security stays native (`with sharing`, Private OWD).

## Class contract

`public with sharing class GtmLinkStageService` — no DML, no callouts, no
`without sharing`, no per-link queries.

```apex
public static final List<String> STAGE_KEYS =
    new List<String>{'sent','engaged','started','submitted','quiet','hot','not_opened'};

public class StageCounts {
    @AuraEnabled public Integer sent, engaged, started, submitted, quiet, hot, notOpened;
    @AuraEnabled public Boolean truncated;
}

// Non-Aura (GUS and tests). Unknown/blank key -> IllegalArgumentException listing valid keys.
public static StageCounts getStageCounts()
public static List<Id> getLinkIdsForStage(String stageKey)

// Aura entries for the UI. Never cacheable (time-dependent `hot`).
// Unknown/blank key -> AuraHandledException listing valid keys.
@AuraEnabled(cacheable=false) public static StageCounts getStageCountsAura()
@AuraEnabled(cacheable=false) public static List<Id> getLinkIdsForStageAura(String stageKey)
```

### Link stats (issue `pages-tab-table-view`)

Per-link facts for the Pages-tab table, projected from the SAME private
`Computation` as the counts (no new query, no new definition):

```apex
public class LinkStat {
    @AuraEnabled public Id linkId;
    @AuraEnabled public Integer visits;        // LinkFacts.visits() = sessionViews + nullSessionViews
    @AuraEnabled public Datetime lastVisitAt;  // null = never visited
    @AuraEnabled public String funnelStage;    // submitted | started | engaged | not_opened
}
public class LinkStatsResult {
    @AuraEnabled public Boolean viewAll = false; // value compute() got from hasViewAllRecords; no extra probe
    @AuraEnabled public Boolean truncated = false;
    @AuraEnabled public List<LinkStat> stats = new List<LinkStat>(); // universe order
}
public static LinkStatsResult getLinkStats()                                      // non-Aura, tests/GUS
@AuraEnabled(cacheable=false) public static LinkStatsResult getLinkStatsAura()    // errors -> AuraHandledException
```

- `visits()` is the one definition of "visit"; `isHot()` calls it.
- `funnelStage` is the highest of: `submitted` if `isSubmitted()`, else `started` if
  `isStarted()`, else `engaged` if `isEngaged()`, else `not_opened`. Built from the
  existing predicates only.
- Same universe and owner scoping as the counts; the query count of
  `getLinkStatsAura()` equals that of `getStageCountsAura()`.

### Pages table (all mode, `gtmRepLinkFinder`)

`c-gtm-link-datatable` (a thin `lightning-datatable` subclass, `key-field="recordId"`,
`hide-checkbox-column`) replaces the tile grid. Rows are `getMyConfigurations()` rows
flattened in JS, merged by `linkId == Id` with `getLinkStatsAura().stats` (a row without
a stat renders blank stat cells). `getMyConfigurations()` is unchanged.

| # | Column | Field | Type | Sort key |
|---|---|---|---|---|
| 1 | Page | `scNumber` | `button` (`name:'open'`, disabled/title from `openDisabled`/`openTitle`) | `scNumber`, case-insensitive |
| 2 | Account | `company` | `gtmLink` (`name:'openAccount'`, disabled/title from `accountDisabled`/`accountTitle`) | `company`, case-insensitive |
| 3 | Contact | `contactName` | `gtmLink` (`name:'openContact'`, disabled/title from `contactDisabled`/`contactTitle`) | case-insensitive |
| 4 | Offering | `offeringLabel` | text | case-insensitive |
| 5 | Opportunity | `opportunityName` | text | case-insensitive |
| 6 | Funnel stage | `funnelLabel` (class `funnelClass`) | text | `funnelRank` |
| 7 | Visits | `visits` | number | numeric |
| 8 | Last visit | `lastVisitAt` | date (raw ISO) | raw ISO |
| 9 | Status | `statusLabel` (class `statusClass`) | text | case-insensitive |
| 10 | Saved | `createdDate` | date | raw ISO |
| 11 | Owner | `ownerName` | text; ONLY when `viewAll` (stats result) or, if the stats call failed, inferred from any row `OwnerId !== @salesforce/user/Id` | case-insensitive |
| 12 | (action) | | `action`, row action `open` via `getRowActions(row, done)` | n/a |

Flattened row fields: `recordId, accountId, contactId, company, contactName,
offeringLabel, opportunityName, funnelStage, funnelLabel, funnelRank, funnelClass,
visits, lastVisitAt, statusLabel, statusClass, createdDate, ownerId, ownerName,
openDisabled, openTitle`. `company` prefers `Account__r.Name` over the free-typed
`Company__c` whenever both are populated (Company__c is only the display fallback for a
link with no Account lookup yet -- see "Account/Contact cell type" below).

#### Account/Contact cell type (`gtmLink`, issue pages-table-account-column-consistency)

Both the Account and Contact columns render through the shared `gtmLink` cell type,
NOT base `type: 'button'`. Base `lightning-datatable` has no supported way to plug in a
custom cell type without subclassing, so `c/gtmLinkDatatable`
(`force-app/main/default/lwc/gtmLinkDatatable`) extends `lightning/datatable` and
registers `static customTypes = { gtmLink: { template, standardCellLayout: true,
typeAttributes: [...] } }`; both `gtmRepLinkFinder.html` and `gtmReadoutsOverview.html`
mount `<c-gtm-link-datatable>` in place of `<lightning-datatable>` and otherwise pass the
exact same public API (sort, infinite loading, row actions all behave unchanged).

The cell itself is `c/gtmLinkCell` (`force-app/main/default/lwc/gtmLinkCell`), reused
by both the Pages and Assessments tables so they cannot drift into two different
Account/Contact renderings again (see `gtm-assessments-table.md`). Column
`typeAttributes` contract:

- `label` / `title` -- display text and tooltip (title ALWAYS renders, so
  `NO_ACCOUNT_TITLE`-style "no account on this link" messaging is never dropped, only
  its clickability changes).
- `disabled` -- true when the row has no real lookup for this cell; drives ONLY
  `gtmLinkCell`'s interactive-vs-static rendering, which is otherwise visually
  identical (same alignment, left-aligned block, link-styled text) whichever state it
  is in -- there is no more base-SLDS button-vs-disabled-button color/alignment split.
- `name` -- the row-action name (`openAccount` / `openContact`), unchanged.
- `targetId` / `idField` -- the id to open when clicked (`accountId` / `contactId`) and
  which row-object key to put it under. On click (or Enter/Space -- native
  `tabindex`/keyboard handling preserved), `gtmLinkCell` dispatches a `rowaction`
  CustomEvent shaped `{ action: { name }, row: { [idField]: targetId } }` that bubbles
  and composes up through `c-gtm-link-datatable` to the same `onrowaction={handleRowAction}`
  listener the base button type used to fire -- `openAccountRecord`/`openContactRecord`
  in `gtmRepLinkFinder.js` need no change. A disabled cell never dispatches.

- Funnel labels: not_opened "Not opened", engaged "Prospect engaged", started
  "Assessment started", submitted "Assessment submitted"; rank 0..3 in that order.
- Classes (SLDS utilities only): submitted -> `slds-text-color_success`;
  not_opened, Inactive -> `slds-text-color_weak`; otherwise none.
- Default sort `lastVisitAt` desc; never-visited (null) LAST in both directions; ties
  (and nulls) by `createdDate` desc then Id. Header starts `sortedBy='lastVisitAt'`,
  `sortedDirection='desc'`. Sort state is not in the URL.
- Open entry points (column-1 button and row action) both call
  `openLinkRow(recordId)` (today's tile-click path). A link with no `Account__c` has
  `openDisabled = true`, `openTitle = 'No account on this link; nothing to open'`; the
  row-action label becomes 'Open (no account on this link)' and is disabled.
- Stage filter narrows rows by `getLinkIdsForStageAura`; `filterResultCount` is the
  rendered row count always in all mode (label "links", or "links - <stage>" when
  filtered).
- Empty/error states (distinct): no links at all; filtered-empty (with Clear filter);
  load error. A stats-only failure still renders the table with em-dash stats and an
  inline notice. Table sits in a fixed-height scroll wrapper; no server paging.

### Computation

ONE private method builds a per-link facts map; `getStageCounts()` and
`getLinkIdsForStage()` are thin projections of it, so a count and its list cannot
diverge. Exactly three data SOQL statements per computation:

1. Universe: `SELECT Id FROM GTM_Saved_Configuration__c WHERE <universe clause>
   ORDER BY CreatedDate DESC LIMIT 50000`. `truncated = (rows == 50000)`.
2. Events aggregate over `GTM_Link_Event__c`, semi-joined on the same universe
   clause, grouped by (`Saved_Configuration__c`, `Event_Type__c`), selecting
   `COUNT(Id)`, `COUNT(Session_Id__c)`, `COUNT_DISTINCT(Session_Id__c)`,
   `MAX(CreatedDate)`.
3. Requests aggregate over `GTM_Assessment_Request__c`, same semi-join, grouped by
   `Saved_Configuration__c`, `COUNT(Id)`.

Aggregates are iterated with `for (AggregateResult ar : Database.query(...))`.
`Saved_Configuration__c` on events/requests is referenced via dynamic SOQL (repo
convention). The row-level permission probe (`hasViewAllRecords`) is a separate
permission query and is not a data query.

### Universe

`Presentation_Stage__c != null AND != 'Draft' AND != 'Rep_Direct'` (exactly the
Pages-tab base clause), plus `OwnerId = :UserInfo.getUserId()` unless the running
user holds `viewAllRecords` on `GTM_Saved_Configuration__c` via any assigned
permission set (private copy of `hasViewAllRecords`, same shape as
`GtmSavedConfigurationController`; de-duplicate onto the shared helper when
`rep-data-scoping-owd-3` lands; `GtmHomeSnapshotController.isAdmin()` is NOT used).

- No `Opportunity__c` requirement; links without an Opportunity are counted.
- Inactive links (`Active__c = false`) are included.
- Rep_Direct, Draft and null-stage links are excluded from EVERY key.
- Scoping is by LINK owner only; there is no `OwnerId` predicate on event/request rows.

### Per-link facts

| Fact | Source |
|---|---|
| `visits` (effective distinct visit sessions) | over `Page View` events: `COUNT_DISTINCT(Session_Id__c)` + (`COUNT(Id)` - `COUNT(Session_Id__c)`), i.e. each null-session view is its own visit |
| `hasPageView` | `Page View` `COUNT(Id) > 0` |
| `lastVisitAt` | `MAX(CreatedDate)` over `Page View` and `Form Resumed` |
| `hasFormOpened` | any `Form Opened` OR `Form Resumed` |
| `hasSubmittedEvent` | any `Form Submitted` |
| `hasRequest` | any linked `GTM_Assessment_Request__c` |

### Stage keys

| Key | Label | Link qualifies when |
|---|---|---|
| `sent` | Links sent | in the universe |
| `engaged` | Prospect engaged | `hasPageView` OR `hasFormOpened` OR `submitted` |
| `started` | Assessment started | `hasFormOpened` OR `submitted` |
| `submitted` | Assessment submitted | `hasSubmittedEvent` OR `hasRequest` |
| `quiet` | Went quiet | `started` AND NOT `submitted` (`Drop-off` neither adds nor removes) |
| `hot` | Came back | `visits >= 2` AND `lastVisitAt >= now - 48h` (exactly 48h old is included; Section Viewed / CTA Clicked / Form Field / Session End / Drop-off never count as a visit) |
| `not_opened` | Not opened yet | NOT `engaged` |

Invariants: `submitted <= started <= engaged <= sent`; `sent = engaged + not_opened`.
`quiet` and `hot` are cross-cutting and may overlap the funnel keys; a submitted link
can be `hot`. Unlike the legacy `countStalled()`, a link with a request but no
`Form Submitted` event is `submitted`, not `quiet`.

## URL contract

`this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: 'GTM_Pages' }, state: { c__stage: '<key>' } })`
where `<key>` is exactly one of the `STAGE_KEYS`. May be combined with
`c__rlfAccountId` / `c__rlfContactId`. Unknown values are ignored (no filter).

## Permissions

`classAccesses` for `GtmLinkStageService` on `GTM_Offering_User` and
`GTM_Offering_Admin` ONLY (never `GTM_Content_*` or `GTM_Guest`). No object/field
grants change.

## Related change

`GtmSavedConfigurationController.getMyConfigurations()` loses its `LIMIT 200` so the
Pages tile grid equals the universe (bounded by the SOQL row governor).

## Known open items

- Until `overview-sales-dashboard` adopts `getStageCounts()`, `countStalled()` and
  the `getDeals()` funnel remain a second, differing definition.
- QA gate: as a non-admin rep, a link with a prospect-generated event must be
  reflected in the counts (event/request ownership under Private OWD). If it is not,
  STOP and report; a `without sharing` aggregate inner class is not pre-approved.
