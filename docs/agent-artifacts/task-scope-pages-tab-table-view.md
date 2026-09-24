# TASK SCOPE — ISSUE #pages-tab-table-view

## 1. Requirements Breakdown

- **Target Objective:** Product decision (owner, 2026-09-19): the app prefers a TABLE over tiles/cards. The Assessments tab is becoming a default table with narrowing filters (`assessments-tab-filter`) and "the All Pages view should be similar". Replace the `.rlf-tiles` button grid that `gtmRepLinkFinder` renders in `rlfMode='all'` (Pages tab, `GTM_Pages` -> `gtmPageBrowser` -> `gtmRepLinkFinder`) with a `lightning-datatable` as the default view. The funnel-stage filter delivered by `stage-filter-pages-tab` (via the `shared-filter-bar` config, `c__stage`) narrows the table. The grouped Account > Contact > Link Miller view (`rlfMode='account'`) is untouched.
- **System Component Impacted:** LWC (`gtmRepLinkFinder` html/js/css + its Jest spec(s)); Apex (one new read-only `@AuraEnabled` method on `GtmLinkStageService`, plus its test class). No Experience Cloud route, no YAML instrument, no custom metadata.

### 1.0 Verified findings (current code; some differ from the brief)

1. **All-mode today:** `gtmRepLinkFinder.html` "Your recent links" renders one `<button class="rlf-tile" data-id=...>` per `tileRows` entry (company, Active/Inactive pill via `.rlf-status[--off]`, "offering · contact", "Saved <date>"). `connectedCallback -> loadSavedLinks()` calls `getMyConfigurations()` imperatively into `savedLinks`. `handleSelectTile` finds the row by `dataset.id`, returns silently if the row has no `accountId`, sets `_restoredContactId`/`_restoredLinkId`, sets `rlfMode='account'`, calls `dispatchModeChange()` and `restoreDrillState(accountId)`. That is "today's tile-click behaviour" and the "Open" action must call exactly this path (not a new one).
2. **`getMyConfigurations()`** (`GtmSavedConfigurationController`, `@AuraEnabled`, deliberately NOT cacheable): base clause `Presentation_Stage__c != null AND != 'Draft' AND != 'Rep_Direct'`, plus `OwnerId = :currentUserId` unless `hasViewAllRecords('GTM_Saved_Configuration__c')`; `ORDER BY CreatedDate DESC LIMIT 200` (the `LIMIT 200` is removed by `stage-filter-pages-tab`, a hard dependency of this issue, so result count = true total). Fields returned: `Id, Name, Offering__c, Industry__c, Company__c, Account__c, Account__r.Name, Contact__c, Contact__r.Name, Contact__r.Email, Opportunity__c, Opportunity__r.Name, Opportunity__r.StageName, Generated_URL__c, Active__c, CreatedDate, OwnerId, Owner.Name, Presentation_Stage__c`. So Account, Contact, Offering, Opportunity, Active, Saved date and Owner are ALL already available with no new query. Visits / last visit / funnel stage are NOT on this object and need the new stats method.
3. **Second caller:** `gtmSavedLinksBar.loadConfigurations()` (Experience Cloud site bar) also calls `getMyConfigurations()` and groups the raw records. This issue must NOT change that method's signature, return type, fields or filter. The Owner column needs nothing new (`Owner.Name` is already selected). Any change to `getMyConfigurations()` is a defect against this scope.
4. **Owner-visibility signal for the LWC:** the LWC has no "am I a viewAll user" flag. Derive "view-all" from the data (any row whose `OwnerId` differs from the current user Id, using `@salesforce/user/Id`) OR have the new Apex method return it (see Fork F4). Do not hard-code a permission-set name (the pattern being phased out org-wide, owd-3).
5. **Datatable nested-field limitation:** `lightning-datatable` `fieldName` reads a flat property; it does not traverse `Account__r.Name`. Rows must be flattened in JS (the existing `tileRows` getter already does this for company/contact; extend it).
6. **Existing datatable usages (read):** `gtmRecycleBin` (checkbox selection, `date` column with `typeAttributes`, `type:'action'` with `rowActions:[{label:'Restore',name:'restore'}]`, `onrowaction`) and `gtmAssessmentSubmissionView` (`hide-checkbox-column`, a `url` column with `typeAttributes:{label:{fieldName:'name'},target:'_self'}`, `type:'action'` with `rowActions:[{label:'Open',name:'open'}]`, `onrowaction`). Neither currently uses `sortable`/`onsort`/`sortedBy`/`cellAttributes`; this issue is the first to. `COLUMNS` is a module-level const in both; follow that.
7. **Existing Jest coverage that constrains this change:** `gtmRepLinkFinder.test.js` describes "quick-access tile grid (product-owner feedback)" (renders a tile per link, empty message, hides the grid after a tile pick, tile click reaches the view step), "browse-mode toggle" (All Pages shows only the grid; By Account shows only search), and "URL state persistence" (`c__rlfMode`, account/contact/link ids). These tile assertions (`.rlf-tile` queries) are the specs that must be rewritten to the table; the toggle/URL specs must keep passing with the table standing in for the tile grid.
8. `Presentation_Stage__c` (Assessment/In_Review/Draft/Sent/Rep_Direct) is unrelated to the FUNNEL stage. The Funnel stage column is the server-computed `funnelStage`, never `Presentation_Stage__c`.

### 1.1 Decision recorded: use `lightning-datatable` (standing rule: Salesforce-native first)

Confirmed against the two in-repo usages above and the datatable docs. Native provides: `sortable` columns + `sorted-by`/`sorted-direction`/`onsort`; `type:'action'` row actions (`onrowaction`, `event.detail.action.name` and `event.detail.row`); `date` (with `typeAttributes` and the `dateLocal`-style formatting), `url`, `number`, `text`, `boolean` cell types; `cellAttributes.class` for per-row CSS class via `{ fieldName: ... }`; `hide-checkbox-column`; `resize-column-disabled`/resizable columns; `show-row-number-column`; `wrap-text-max-lines`; keyboard and ARIA behaviour. Decisions:

- **Build the table with `lightning-datatable`; do NOT hand-build a `<table>`.**
- **Status = coloured text via `cellAttributes.class` (default), no custom cell type.** Each row carries a precomputed class string (e.g. `funnelClass`) and the column uses `cellAttributes: { class: { fieldName: 'funnelClass' } }`. Class names must exist in the component's CSS, and because datatable renders inside its own shadow boundary the class must be reachable: SLDS utility classes (`slds-text-color_success`, `slds-text-color_weak`, `slds-text-color_error`) work, component-scoped CSS does NOT pierce into the datatable. Use SLDS text-colour utilities only. A real pill (a custom `LightningDatatable` subclass with a template) is a supported platform mechanism but is NOT justified here; introduce it only if the owner explicitly rejects coloured text (Fork F2).
- **Whole-row click is not natively available. Decision: two entry points, one handler.** (a) Column 1 (Account / company) is a `button`-type cell (`type:'button'`, `typeAttributes:{label:{fieldName:'company'}, name:'open', variant:'base'}`) so the primary text is a keyboard-focusable link-style control, AND (b) the row-action menu carries "Open" (`rowActions:[{label:'Open', name:'open'}]`, the exact idiom `gtmAssessmentSubmissionView` uses). Both fire `onrowaction`/`onrowaction`-equivalent and route to ONE handler that resolves the row by `row.recordId` and runs the same logic as `handleSelectTile` (refactor `handleSelectTile` into `openLinkRow(recordId)` shared by both; keep the no-`accountId` silent return). Do not use `onrowselection` or attach click listeners to the datatable's internal DOM (fragile under shadow DOM, breaks a11y).
- **Row-level client sorting:** datatable does not sort by itself; the component sorts its own `data` array on `onsort` (fieldName + direction, with `sortedBy`/`sortedDirection` bound). Date columns must sort on the raw ISO/Date value, not a formatted label; text sort case-insensitive; nulls last.
- **Client filtering:** no native filter; the component filters its own array (already the model for the stage filter: intersect with `getLinkIdsForStageAura(stage)`), exactly as `stage-filter-pages-tab` specifies for tiles, now applied to table rows.

### 1.2 Columns (all from data that exists)

| # | Column | Field (flattened) | Type | Sortable | Source |
|---|---|---|---|---|---|
| 1 | Account / company | `company` (`Company__c` or `Account__r.Name`) | `button` (opens link) | yes | `getMyConfigurations` |
| 2 | Contact | `contactName` | text | yes | `getMyConfigurations` |
| 3 | Offering | `offeringLabel` (`formatLabel(Offering__c)`) | text | yes | `getMyConfigurations` |
| 4 | Opportunity | `opportunityName` (blank when none) | text | yes | `getMyConfigurations` (`Opportunity__r.Name`) |
| 5 | Funnel stage | `funnelLabel` (Not opened / Prospect engaged / Assessment started / Assessment submitted) | text with `cellAttributes.class` | yes (by funnel rank, not alphabetical) | `getLinkStatsAura().funnelStage` |
| 6 | Visits | `visits` | number | yes | `getLinkStatsAura().visits` |
| 7 | Last visit | `lastVisitAt` | `date` (`typeAttributes` as in `gtmRecycleBin`), blank when never | yes | `getLinkStatsAura().lastVisitAt` |
| 8 | Status | `statusLabel` Active / Inactive | text + `cellAttributes.class` | yes | `Active__c` (`false` = Inactive, as today) |
| 9 | Saved | `createdDate` | `date` | yes | `CreatedDate` |
| 10 | Owner | `ownerName` | text | yes | `Owner.Name`; column present ONLY for a view-all user (hidden for reps) |
| 11 | (action) | | `action`, row action "Open" | n/a | shared open handler |

Rows with no Opportunity, no Contact or no visits are valid rows and render blank cells (never dropped).

### 1.3 Behaviour

- **Default view:** the table is what All Pages mode shows; the tile markup, `.rlf-tiles`/`.rlf-tile*` CSS and tile-only getters are removed (no dead CSS). `rlfMode` toggle (All Pages / By Account or Contact), `dispatchModeChange`, header wiring in `gtmPageBrowser` are unchanged.
- **Default sort:** most recent activity first = `lastVisitAt` DESC, with links that have never been visited ordered after all visited links, newest `createdDate` first within that tail. (Fork F3: alternative "Saved date DESC" matches today's tile order; the brief asks "most recent activity first", so activity is the default.) The initial `sortedBy` for the header indicator is `lastVisitAt`/`desc`. User sorts override until reload; sort state is NOT persisted to the URL (Fork F5).
- **Stage filter:** when `c__stage` is active (owned and wired by `stage-filter-pages-tab`/`shared-filter-bar`), rows are narrowed to `recordId in getLinkIdsForStageAura(stage)`. The filter bar config, chip counts, `c__stage` URL read/write, unknown-key handling and error fallback are NOT redefined here; this issue only swaps the rendering target from tiles to the datatable and keeps every existing behaviour. Chip counts and the table are independent server calls; both fetched on mount and on `c__stage` change.
- **Result count:** shown via the shared bar's result-count slot/prop as the true total of the rows after all filters (so with no filter it equals the total number of links visible to the user; with a stage filter it equals the Overview count for that key). No "showing first N" wording since the 200 cap is gone.
- **Empty states (three, distinct):** (1) no links at all: "No saved links yet. Build one from the Overview tab's configurator wizard." (existing text, kept); (2) filtered-empty: "No links have reached <stage label> yet" with a Clear filter action (from `stage-filter-pages-tab`); (3) load error: message from Apex, and for a stats-only failure the table still renders from `getMyConfigurations()` with the stats columns blank/"—" and an inline notice, never a silently empty table. Datatable is rendered only when there is at least one row after filtering; spinner while loading.
- **Deep links unchanged:** `c__rlfMode`, `c__rlfAccountId`, `c__rlfContactId`, `c__rlfLinkId`, `c__rlfShowPreview|ShowWorkspace|PwRevealed`, and `c__stage` continue to be read and written exactly as today (`writeDrillStateToUrl` unchanged by this issue). A `c__rlfAccountId`/`c__rlfContactId` deep link still lands in account mode (the Overview navigates this way); a `c__stage` link with no account param lands in all mode showing the table.
- **Accessibility:** datatable supplies grid semantics and keyboard navigation; the column-1 button and the action menu are keyboard reachable; status is conveyed by text label, not colour alone.

### 1.4 New Apex (read-only, no extra query)

`GtmLinkStageService.getLinkStatsAura()`:

```
public class LinkStat {
    @AuraEnabled public Id       linkId;
    @AuraEnabled public Integer  visits;       // effective visit count (same value the hot rule uses)
    @AuraEnabled public Datetime lastVisitAt;  // MAX(CreatedDate) of Page View / Form Resumed; null = never
    @AuraEnabled public String   funnelStage;  // highest of submitted > started > engaged > not_opened
}
@AuraEnabled(cacheable=false)
public static List<LinkStat> getLinkStatsAura()
```

Built from the SAME private `Map<Id, LinkFacts>` the service already computes (3 SOQL statements per computation: universe Ids, events aggregate, requests aggregate); adds no query and no new definition. Same universe and owner scoping as `getMyConfigurations()` (base clause + owner-scoped unless `hasViewAllRecords`), so every table row has a stat entry and vice versa. Never `cacheable=true` (time-dependent facts; Aura caches cacheable actions). `public with sharing`, zero DML, zero callouts (AGENTS.md §1 zero-DML rule applies because the same class is GUS's read-only backend). The LWC merges stats into rows client-side by `linkId == Id`; a row without a stat entry renders blank stats (defensive).

### 1.5 Open forks (need Architect / owner; NOT settled here)

- **F1. Contract and ordering dependency.** `LinkStat` and `getLinkStatsAura()` were removed from `stage-filter-pages-tab` and assigned to this issue (Architect amendment). This issue merges AFTER `shared-filter-bar` and `stage-filter-pages-tab` (which also removes `LIMIT 200` and adds `GtmLinkStageService` + its `classAccesses` grants). The exact `getStageCountsAura` / bar prop names must be pinned to those merged contracts, not invented here. The Architect must confirm `LinkFacts` exposes the effective visit count and last-visit time for reuse (the stage scope defines `views` = effective distinct-session visits with null-session rows counted individually); if it does not on `main`, adding the two fields to `LinkFacts` is in scope, adding a query is not.
- **F2. Status rendering:** coloured text via `cellAttributes.class` (BA default, no custom code) versus a real pill via a custom datatable cell type. Coloured text limits styling to SLDS utility classes. Owner/Architect to confirm coloured text is acceptable.
- **F3. Default sort:** last visit DESC (BA default, from "most recent activity first") versus Saved date DESC (today's tile order). Confirm.
- **F4. View-all detection for the Owner column:** infer from data (`OwnerId !== current user Id` on any row) versus an explicit `Boolean viewAll` returned by the stats method (needs a wrapper return type instead of `List<LinkStat>`). Inference misjudges a view-all user who owns every visible link (column hidden, harmless); an explicit flag is exact. Architect to choose; if a wrapper is chosen, update §1.4.
- **F5. Sort persistence:** not persisted to the URL by default (no new URL params are introduced, keeping the `c__` contract closed). Confirm the owner does not want `c__rlfSort`.
- **F6. Row-open target for a link with no `Account__c`:** today `handleSelectTile` silently does nothing. A table row with an Open action that does nothing is worse UX than a tile that does nothing. Default kept as "same as today" for behavioural parity; Architect may prefer disabling the action for such rows.
- **F7. Owner scoping of stats:** rests on the stage-filter QA gate about guest-created event ownership (Architect addendum B.6). If that gate finds an undercount for non-admin reps, the Visits / Last visit / Funnel stage columns would be wrong for reps; this issue must not ship until that gate is closed. The `without sharing` contingency needs coordinator approval and is not pre-approved.
- **F8. Pagination/scale:** no server paging; datatable with a few thousand rows is acceptable per the stage-filter residual-risk note (Aura ~4 MB response). Revisit paging/infinite loading only if a rep nears ~3k links.
- No `gtm-dev` production data is touched: read-only methods, QA is read-only against `gtm-dev`; boundary data comes only from Apex test transactions.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO change to GUS. `GtmLinkStageService` is the read-only backend GUS uses, so the new `getLinkStatsAura()` must obey the zero-DML rule in AGENTS.md §1: no `insert/update/delete/upsert/Database.*` DML, no `without sharing`, no callouts; QA greps the class for DML keywords.
- [ ] Altering Custom Metadata? NO. No `GTM_Assessment_*` XML, no `migration-accelerator/` or `instrument/` YAML.
- [ ] Introducing database fields? NO. No new objects, fields, tabs or picklist values; all data derives from existing fields. Permission Sets: no field/object grants. `classAccesses` for `GtmLinkStageService` on `GTM_Offering_User` and `GTM_Offering_Admin` are added by `stage-filter-pages-tab`; NO new class is added by this issue (the method goes on the existing class), so no permission-set XML change is expected. If the Architect instead creates a new class (Fork F1), add its `classAccesses` to those same two sets only, never `GTM_Guest` / `GTM_Content_*`, in the same commit as the class so `scripts/check-references.py` passes.

Other dependencies: (a) merges AFTER `shared-filter-bar` and `stage-filter-pages-tab` (merge main in before Developer starts); (b) `gtmSavedLinksBar` must keep working: `getMyConfigurations()` is untouched and its Jest spec is re-run; (c) Contract First: Architect adds the `LinkStat`/`getLinkStatsAura` and table column/sort/row-action contract to `docs/architecture/gtm-link-stage-filter.md` (or a Pages-table doc) before code; (d) no `experiences/` change, so no `sf community publish`; ships to `gtm-dev` (treated as Production): validate with `--dry-run --run-tests` first and hold behind any open unexplained regression per the deploy-sequencing memory; (e) `python3 scripts/check-references.py` and `scripts/check-all.sh` before hand-off (the LWC import must name an existing method: `@salesforce/apex/GtmLinkStageService.getLinkStatsAura`); (f) CI header `ISSUE #pages-tab-table-view` must be on this scope file and in the PR.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. All Pages mode renders a `lightning-datatable` by default and no `.rlf-tile` markup or CSS remains; By Account or Contact mode, the mode toggle, `dispatchModeChange`, and the `gtmPageBrowser` header behaviour are unchanged.
  2. Columns per §1.2 render from the flattened rows; the Owner column appears only for a view-all user; rows without Opportunity/Contact/visits render blank cells and are not dropped.
  3. Default order is last visit DESC (never-visited last, newest Saved first within them); `onsort` on each sortable column reorders correctly in both directions (dates on raw values, Funnel stage by rank, nulls last) and updates `sortedBy`/`sortedDirection`.
  4. "Open" (column-1 button AND the row action) performs exactly today's tile-click behaviour: seeds `_restoredContactId` / `_restoredLinkId`, sets `rlfMode='account'`, dispatches `modechange`, and reaches the same view step; a row with no `Account__c` does nothing (parity).
  5. With `c__stage=<key>` active the table shows only rows whose id is in `getLinkIdsForStageAura(key)`; the result count equals the number of rendered rows and (unfiltered) the full link count; clearing the filter restores all rows. Filtered-empty, no-links, and load-error states are distinct and never silently empty; a stats-call failure still shows the table with blank stats and a notice.
  6. `c__rlfMode`, `c__rlfAccountId`, `c__rlfContactId`, `c__rlfLinkId`, preview/workspace/password params and `c__stage` deep links behave exactly as before (existing URL-state specs pass unchanged; `c__stage` survives `writeDrillStateToUrl`).
  7. `getLinkStatsAura()` returns exactly one `LinkStat` per link in the same universe as `getMyConfigurations()`, with `visits`, `lastVisitAt` and `funnelStage` matching `getStageCounts()`/`getLinkIdsForStage()` semantics (every link with `funnelStage='submitted'` is in the `submitted` id set, etc.); it issues no SOQL beyond the service's existing three (assert `Limits.getQueries()`); scoping: rep A sees only own links' stats, rep B only own, admin (`viewAllRecords`) sees all; `GTM_Guest` has no class access.
  8. `gtmSavedLinksBar` Jest spec and `GtmSavedConfigurationControllerTest` pass unchanged (proving `getMyConfigurations()` was not altered by this issue).
  9. QA validates live in the browser (per QA-browser-validation memory), read-only against `gtm-dev` (Production): open GTM_Pages as a rep and as an admin; verify the table, sorting, each stage filter's count vs. row count, Open from column 1 and the row action, filtered-empty and empty states, account-mode deep links from the Overview, the By Account or Contact toggle, and the Experience Cloud `gtmSavedLinksBar` surface. QA creates/edits/deletes no records on `gtm-dev`.
- **Target Test Target:** Jest: `force-app/main/default/lwc/gtmRepLinkFinder/__tests__/gtmRepLinkFinder.test.js` (rewrite the tile-grid describe block to table assertions; a sibling `gtmRepLinkFinder.table.test.js` following the `gtmOverview.repDirect.test.js` precedent is acceptable) covering columns (incl. Owner shown/hidden), default sort and `onsort`, stage filter narrows the table, row action and column-1 button both route to the open handler, three empty/error states, and deep links; run with `npm test -- gtmRepLinkFinder gtmSavedLinksBar`, then full `npm test`. Apex: `GtmLinkStageServiceTest` (extend with `getLinkStatsAura` cases: two reps via `System.runAs` plus an admin with viewAll, each `funnelStage`, visits/lastVisit values, no-query-beyond-three, consistency with the id lists) and re-run `GtmSavedConfigurationControllerTest` and `GtmRepLinkFinderControllerTest` for regressions.


---

# ARCHITECT ADDENDUM (2026-09-19) — resolves BA forks F1-F8; supersedes conflicting text in section 1

Reviewed against main at `6df0e3c` (`shared-filter-bar` #224 and `stage-filter-pages-tab` #226 merged). No bracket placeholders in the scope. Checklist confirmed: no GUS-surface change beyond one read-only method on `GtmLinkStageService` (zero DML, zero callouts, `with sharing`); no custom metadata; no fields/objects; no permission-set change (`classAccesses` for `GtmLinkStageService` already on `GTM_Offering_User` and `GTM_Offering_Admin`; NO new class is created). Worktree: `/Users/isiwintr/Documents/Workbench/worktrees/issue-pages-tab-table-view`, branch `agent/issue-pages-tab-table-view`.

## A. Standing rule: Salesforce-native evaluation

Decision: `lightning-datatable` is the base; no hand-built table. Sorting, action column, `button`/`date`/`number`/`text` cell types, `cellAttributes.class`, `hide-checkbox-column`, keyboard/ARIA are all native. Custom parts (unavoidable, no native equivalent): the per-link funnel facts (child-event aggregates; already in `GtmLinkStageService`), client-side sort/filter of the loaded array (datatable does not sort or filter itself), and row flattening.

Docs spot-checks I could NOT verify (no live doc access from the Architect environment). Developer verifies against the Lightning Component Reference in the first hour; ANY failure = stop and return to the Architect, do not improvise:
1. Column `type:'button'` supports `typeAttributes` `label` (fieldName), `name`, `variant:'base'`, `disabled` (fieldName) and `title` (fieldName); and a `button`-type column may be `sortable:true` with a `fieldName` (sort event reports that fieldName).
2. `type:'action'` `typeAttributes.rowActions` accepts a FUNCTION `(row, doneCallback)` and each action supports `disabled: true` and `label`. (Native action items have no tooltip; the reason is put in the label text.)
3. `cellAttributes: { class: { fieldName } }` accepts SLDS utility classes (`slds-text-color_success`, `slds-text-color_weak`, `slds-text-color_error`) and they render inside the datatable shadow boundary. Component CSS does not pierce; use utilities only.
4. `date` type `typeAttributes` (`year`, `month`, `day`, `hour`, `minute`) accept an ISO string/timestamp and render blank for null.
5. `sorted-by`, `sorted-direction`, `onsort` (`event.detail.fieldName` / `sortDirection`), `key-field`, `hide-checkbox-column`, `resize-column-disabled`.

## B. Fork resolutions (final)

- **F1 (LinkFacts).** Confirmed on main: `LinkFacts` already carries `lastVisitAt` (MAX CreatedDate of Page View / Form Resumed) and the effective visit count as `sessionViews + nullSessionViews` (exactly what `isHot()` uses). No new SOQL and no new aggregate. Permitted change: add a tiny `Integer visits() { return sessionViews + nullSessionViews; }` and make `isHot()` call it (one definition of "visit"; existing tests must stay green). `funnelStage` (highest of): `submitted` if `isSubmitted()`, else `started` if `isStarted()`, else `engaged` if `isEngaged()`, else `not_opened`. Must use the existing predicates, never re-derived. Adding a query is out of scope and a defect.
- **F2 (status rendering).** Coloured text via `cellAttributes.class` for Funnel stage and Status, SLDS utilities only. NO custom pill cell in this issue. Reasons: `gtmBadgeCell` does not exist on main; the sibling `assessments-tab-filter` design (`docs/architecture/gtm-assessments-table.md`, in worktree `issue-assessments-tab-filter`) also chose coloured text and only sanctions ONE follow-up custom type named `gtmBadgeCell` (a `LightningDatatable` subclass, one template, SLDS `slds-badge`) if the owner rejects it after seeing the deployed table; it cannot be verified without a browser. RECOMMENDATION to the coordinator: if the owner wants pills, build `gtmBadgeCell` ONCE as a single small follow-up issue and adopt it in both `gtmReadoutsOverview` and `gtmRepLinkFinder` in the same change; do not build it here or in the Assessments issue. Text labels always carry the meaning (colour is never the only signal). Class map: submitted -> `slds-text-color_success`; started/engaged -> default; not_opened -> `slds-text-color_weak`; Inactive -> `slds-text-color_weak`; Active -> default. (No error colour needed.)
- **F3 (default sort).** `lastVisitAt` DESC, never-visited last, ties (and the never-visited tail) by `createdDate` DESC then Id. Nulls are last in BOTH directions. Header indicator starts `sortedBy='lastVisitAt'`, `sortedDirection='desc'`.
- **F4 (view-all flag).** Explicit, from Apex. `getLinkStatsAura()` returns a wrapper, superseding the `List<LinkStat>` in section 1.4:
  ```apex
  public class LinkStat {
      @AuraEnabled public Id linkId;
      @AuraEnabled public Integer visits;        // LinkFacts.visits()
      @AuraEnabled public Datetime lastVisitAt;  // null = never visited
      @AuraEnabled public String funnelStage;    // submitted | started | engaged | not_opened
  }
  public class LinkStatsResult {
      @AuraEnabled public Boolean viewAll = false; // the value compute() already got from hasViewAllRecords(); NO extra probe
      @AuraEnabled public Boolean truncated = false;
      @AuraEnabled public List<LinkStat> stats = new List<LinkStat>();
  }
  public static LinkStatsResult getLinkStats()                       // non-Aura, for tests/GUS
  @AuraEnabled(cacheable=false) public static LinkStatsResult getLinkStatsAura()  // try/catch -> auraError(...)
  ```
  Implement by adding `Boolean viewAll` to the private `Computation`, set inside `compute()` from the existing `hasViewAllRecords` call (the permission probe is not a data query and must still run once per computation). Stats order = universe order. If the stats call fails, the LWC falls back to inference (any row `OwnerId !== @salesforce/user/Id`) so the Owner column is still correct for an admin viewing others' links. Never hard-code a permission-set name.
- **F5.** No sort state in the URL. No new `c__` params.
- **F6.** A link with no `Account__c`: Open is DISABLED, not a silent no-op. Column-1 button: `disabled: {fieldName:'openDisabled'}` and `title: {fieldName:'openTitle'}` (title text: "No account on this link; nothing to open"). Row-action menu: a module-level `getRowActions(row, doneCallback)` returning `[{label: row.openDisabled ? 'Open (no account on this link)' : 'Open', name:'open', disabled: row.openDisabled}]` (native menu items have no tooltip, so the reason is in the label). The shared `openLinkRow(recordId)` keeps its defensive silent return for a missing `accountId` (belt and braces), and Jest covers that a disabled row never calls it. This supersedes the "parity/silent" wording in success metric 4 for rows without an account; every row with an account behaves exactly as today's tile click.
- **F7 (DEPENDENCY, for the coordinator).** The guest-created-event ownership QA gate on `stage-filter-pages-tab` (task-scope-stage-filter-pages-tab.md B.6 / `gtm-link-stage-filter.md` "Known open items") is STILL OWED and unresolved. Visits / Last visit / Funnel stage for non-admin reps depend on it. THIS ISSUE MUST NOT MERGE OR DEPLOY until that gate is closed. Development and local Jest/validate-only work may proceed. If the gate finds an undercount, STOP and report to the coordinator: the `without sharing` contingency is NOT pre-approved and is NOT part of this issue.
- **F8.** No server paging. Datatable inside a fixed-height scroll container (`max-height` on a wrapper div styled in the component CSS; the wrapper is outside the datatable so component CSS applies). Accepted until a rep nears ~3k links (Aura ~4 MB response is the ceiling; `getMyConfigurations` rows are the heavier payload). Note it in the PR.

## C. Contract (Developer lands this FIRST, before code — Contract First)

Edit `docs/architecture/gtm-link-stage-filter.md`: delete the sentence "`LinkStat` / `getLinkStatsAura()` are NOT part of this contract...", add the Apex block from F4, the `visits()`/`funnelStage` definitions from F1, and a "Pages table (all mode)" section recording: the column table (section 1.2, with Owner shown only when `viewAll` (or inferred)), field names of the flattened row (`recordId, accountId, contactId, company, contactName, offeringLabel, opportunityName, funnelStage, funnelLabel, funnelRank, funnelClass, visits, lastVisitAt, statusLabel, statusClass, createdDate, ownerId, ownerName, openDisabled, openTitle`), sort keys (`funnelLabel` column sorts on `funnelRank`; date columns on raw ISO; text case-insensitive; numbers numeric; nulls last both directions; stable tie-break createdDate DESC), the two open entry points routed to one `openLinkRow(recordId)`, F6 disabled behaviour, and the three empty/error states.

## D. Implementation guardrails

1. `getMyConfigurations()`, `gtmSavedLinksBar`, `writeDrillStateToUrl`, `c__` params, `dispatchModeChange`, `gtmPageBrowser` are NOT modified. `GtmSavedConfigurationControllerTest` and the `gtmSavedLinksBar` spec must pass unchanged.
2. Chip counts, id set (`getLinkIdsForStageAura`) and stats are independent Aura calls; a stats failure renders the table with blank stats cells (em dash) and an inline notice; an id-set failure keeps the existing "Showing all links" behaviour. Each new async call uses the same sequence-guard pattern as `_countsSeq` / `_idsSeq` (a stale response never overwrites a newer one).
3. `filterResultCount` today returns `undefined` when no stage filter is active. For the table it must return the rendered row count ALWAYS in all mode (unfiltered = total links; label "links"), and the "links · <stage>" label only when filtered. Keep the account-mode branch as is.
4. `showStageEmpty` / `showNoSavedLinks` / `hasTileRows` / `tileRows` are renamed to table equivalents; the three empty states stay distinct; datatable is rendered only when rows exist and not loading. Remove `.rlf-tiles`, `.rlf-tile*`, `.rlf-status*` CSS and tile-only getters (no dead CSS).
5. Datatable attributes: `key-field="recordId"`, `hide-checkbox-column`, `columns`, `data`, `sorted-by`, `sorted-direction`, `onsort`, `onrowaction`. `COLUMNS` module-level const (Owner column added by a getter that concatenates), following `gtmRecycleBin` / `gtmAssessmentSubmissionView`. Put pure functions (flatten/merge stats, comparator, column builder, row actions) in a small exported module such as `gtmRepLinkTableModel.js` in the same LWC folder, Jest-covered directly.
6. Apex: identifiers must NOT be Apex reserved words or SOQL keywords (`limit`, `group`, `order`, `select`, `from`, `where`, `count`, `first`, `last`, `end`, `by`, `in`, `on`, `all`, `desc`, `asc`, `type`, `rows`-style safe names are fine). Use names such as `linkStats`, `stageName`, `visitCount`. No DML, no `without sharing`, no callouts, and `Limits.getQueries()` delta for `getLinkStatsAura()` equals that of `getStageCountsAura()` (assert equality, no extra query).
7. Apex test additions in `GtmLinkStageServiceTest` per the scope's Target Test Target, plus: `viewAll` true for the admin/viewAll user and false for a rep; `truncated` via the existing `universeLimitOverride` seam; `visits`/`funnelStage` agree with `getLinkIdsForStage` sets for every link; `isHot()` refactor leaves the existing hot tests green.

## E. Execution restrictions (coordinator, binding on Developer and QA)

- NO live deploy, NO `sf apex run`, NO `deploy.sh` against `gtm-dev` (Production) and no data reads/writes there.
- The ONE permitted org command is the validate-only check-only deploy WITH specified tests, which executes the tests and rolls back:
  `sf project deploy start --dry-run --source-dir force-app --test-level RunSpecifiedTests --tests GtmLinkStageServiceTest --tests GtmSavedConfigurationControllerTest --tests GtmRepLinkFinderControllerTest --target-org gtm-dev`
  (spell out `--dry-run`; `-c` is `--ignore-conflicts`, NOT a dry run.) Allowed and encouraged after the local checks pass; attach the result to the PR.
- Local gates: `npm test -- gtmRepLinkFinder gtmSavedLinksBar`, full `npm test`, `python3 scripts/check-references.py`, `scripts/check-all.sh`.
- Browser QA against `gtm-dev` remains blocked until (a) F7 is closed and (b) the owner authorises a deploy; until then QA is Jest + validate-only + code review. Deploy-sequencing memory applies (hold behind any open unexplained regression).
