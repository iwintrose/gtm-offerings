# All Assessments Table (`gtmReadoutsOverview`, "All Assessments" mode)

Status: Implemented, pending QA (issue `assessments-tab-filter`, Architect addendum 2026-09-19). Developer deviations are marked **DEVIATION** below with the reason. Contract first: binding on Developer and QA; land this file before the code.

Depends on `shared-filter-bar` (`gtmFilterBar`, `gtmFilterUrlState`, `docs/architecture/gtm-filter-bar.md`), which must merge first. If its merged API differs from what is written here, its merged contract wins and this doc is updated in the same change.

## 1. Salesforce-native evaluation (standing rule)

Source caveat: live Salesforce docs could not be browsed from the Architect environment. The findings rest on the documented `lightning-datatable` API as known to the Architect and MUST be spot-checked by the Developer (section 7) before coding. A failed check stops work and returns to the Architect; nobody improvises a hand-built table.

### 1.1 `lightning-datatable`: DECISION = USE, no custom column types in v1

| Need | Native answer | Verdict |
|---|---|---|
| Sortable columns | `sortable: true`, `sorted-by`, `sorted-direction`, `onsort` | Native. The handler re-queries the server (3.5); the table never sorts loaded rows client-side, because with paging the loaded rows are not the whole set. |
| Infinite loading | `enable-infinite-loading`, `onloadmore`, `load-more-offset`; needs a fixed-height scroll container | Native. Page size 50. |
| Link columns | column `type: 'url'`, `typeAttributes: { label: { fieldName }, target: '_self' }` | Native. |
| Open the workspace | column `type: 'button'` (variant base), `onrowaction` | Native, with a constraint: see 1.3. |
| Tier / status as coloured text | `cellAttributes: { class: { fieldName }, iconName: { fieldName } }` with SLDS utility classes | Native, no custom type. |
| Score | `type: 'number'` | Native. |
| Submitted | `type: 'date'` with year/month/day `typeAttributes` (Datetime field) | Native. |
| Loading | `is-loading` | Native. Empty state is plain text (nothing native). |
| Accessibility | table semantics, keyboard, sort announcements | Owned by the base component. |

Custom column types (extending `LightningDatatable`) are NOT built in v1. They would only buy filled badge/pill styling for tier and status (the mockup). Decision: coloured text plus icon via `cellAttributes` is the accepted native equivalent. If the product owner rejects it after seeing the deployed table, the sanctioned follow-up is exactly one custom type `gtmBadgeCell` (a `LightningDatatable` subclass, one template, SLDS `slds-badge`), added as an amendment here. Not built speculatively.

### 1.2 Prospect column: two native `url` columns

The mockup's single "Prospect" cell with two links is not a native cell. v1 uses adjacent "Contact" and "Company" `url` columns. Neither may render blank for a row that has data:
- Contact: label = `Contact__r.Name`, else `Requester_Name__c`, else `Company__c`. Target = Contact record when `Contact__c` is set, else Account when `Account__c` is set, else the request record.
- Company: label = `Company__c`, else `Account__r.Name`. Target = Account when `Account__c` is set, else the request record.
- Targets are `/lightning/r/<ObjectApiName>/<Id>/view`, built by a pure function `buildRecordUrl` covered by Jest.

### 1.3 Row click: recorded deviation from the product-owner wording

Amendment 2 says "row click opens the workspace". `lightning-datatable` has no whole-row click; the native mechanisms are `onrowaction` (button/action column) and `onrowselection`, and attaching a handler inside the datatable's DOM is unsupported (shadow boundary / LWS). Decision: **the Assessment (`AR-####`) button cell is the row's open action**; the Contact and Company links navigate to their records and do not open the workspace. If the product owner requires whole-row click, that is a custom table and needs an explicit product-owner override recorded here; the Developer must not hand-build one silently.

The open behaviour is otherwise as scoped: set `selectedAssessmentRequestId`, `selectedReadoutId` (may be blank), `selectedOfferingKey`, call `writeSelectionToUrl()`, render the unchanged `c-gtm-readout-workspace`.

### 1.4 Standard list-view filtering: evaluated and rejected

- The list-view surfaces available to a custom LWC (Aura `lightning:listView`, `lightning/uiListApi` wires) bind to a fixed named list view; none accepts composite runtime filter state from our shared filter bar, our sort, or our paging contract.
- A standard list view on `GTM_Assessment_Request__c` can express status, tier, offering, date and owner. It cannot express: readout status (a property of the latest child readout), the "Ready to book" named preset shared with Overview and GUS, explicit tier-rank then score then coalesced-date sort (a list view sorts a picklist by definition order and a single column), or the true-count-plus-paging contract behind one Apex home.
- The admin may still add plain list views for ad-hoc use. They do not substitute for this surface.

### 1.5 What remains custom, and why (the whole list)

1. `GtmAssessmentListController` (Apex): request-grain query, readout join, filter/preset/date/sort definitions, true count. No native mechanism joins the latest readout, ranks a picklist explicitly, or expands a named preset.
2. `gtmReadoutsOverview` glue and a small pure model module: shared-filter-bar config, server-row to datatable-row mapping, column defs, event wiring, URL restore. No hand-drawn table, no hand-rolled filter UI, no hand-rolled URL writer.

## 2. Row grain and readout join

One row per `GTM_Assessment_Request__c`. The readout shown is the request's **most recently created** readout (`CreatedDate DESC`, `Id DESC` tiebreak), the same rule `getContactsWithRequests` and `getReadoutForRequest` already use, so the trail and the table agree. The readout column and the readout filter both use that one chosen readout, never "any readout of the request".

`readoutId` is blank when there is no readout. The workspace tolerates this (verified in code, not live): `@api readoutId = null`, `_currentReadoutId = this.readoutId || null`, a "Generate Readout" path exists for exactly this case, and the account trail already passes `detail.readoutId || ''`. Jest must still cover the blank-readoutId open action.

## 3. Apex contract: new class `GtmAssessmentListController`

New class, not more weight on the 2,400-line `GtmReadoutController`. `public with sharing`, zero DML, zero callout. Requires `classAccesses` in `GTM_Offering_User` and `GTM_Offering_Admin` in the same change (CLAUDE.md section 6). The content sets do not need it.

### 3.1 Signature

```apex
@AuraEnabled   // NOT cacheable: Refresh must reach the server (same reasoning as getReadoutsForReview)
public static AssessmentPage getAssessmentPage(AssessmentQuery query)

public class AssessmentQuery {
    @AuraEnabled public List<String> status;     // multi
    @AuraEnabled public List<String> tier;       // multi
    @AuraEnabled public List<String> readout;    // multi
    @AuraEnabled public List<String> offering;   // Offering_Key__c values, multi
    @AuraEnabled public String range;            // '7'|'30'|'90' or 'YYYY-MM-DD..YYYY-MM-DD'
    @AuraEnabled public String preset;           // 'ready-to-book'
    @AuraEnabled public String sortBy;           // 'best-fit' (default)|tier|score|status|readout|submitted|contact|company
    @AuraEnabled public String sortDir;          // 'asc'|'desc'
    @AuraEnabled public Integer offset;          // default 0
    @AuraEnabled public Integer pageSize;        // default 50, clamped 1..200
}
public class AssessmentPage {
    @AuraEnabled public List<AssessmentRow> rows;
    @AuraEnabled public Integer totalCount;      // TRUE total under filters + scoping
    @AuraEnabled public Boolean totalIsCapped;   // true only if the 3.6 safety ceiling was hit
    @AuraEnabled public List<String> offeringOptions; // distinct Offering_Key__c within the same scope
}
// AssessmentRow: recordId, name, contactId, contactName, accountId, company, requesterName,
// offeringKey, tier, tierRank, score, requestStatus, readoutId, readoutStatus (blank = none yet),
// readoutNotificationSent (Boolean), submittedAt (null falls back to createdDate), createdDate
```

One wrapper so Overview and the future GUS tool call the same method with the same shape (those are separate issues; GUS must obey the zero-DML/zero-callout tool contract). Unknown or invalid keys are dropped, never thrown. Null, empty and absent all mean "no filter on that dimension".

### 3.2 Vocabularies (server-owned; the LWC config carries only keys and labels)

Request status (verified against `Status__c`): New, Contacted, Scheduled, Completed, No Show; slugs `new`, `contacted`, `scheduled`, `completed`, `no-show`.

Tier, explicit rank map best-first. Verified against the `Assessment_Tier__c` description and `GtmAssessmentScoring` (bands 27-32, 21-26, 15-20, 8-14):

| Rank | Tier | Key | Score band |
|---|---|---|---|
| 4 | Fast-Track | `fast-track` | 27-32 |
| 3 | Accelerator-Ready | `accelerator-ready` | 21-26 |
| 2 | Prep Required | `prep-required` | 15-20 |
| 1 | Discovery First | `discovery-first` | 8-14 |
| 0 | null | none | tier suppressed (unsupported source/target pair) |

Rank is an explicit `Map<String, Integer>`; do not rely on picklist order. Tier is not derivable from score alone (a `source_access` answer of 1 caps the tier at Discovery First regardless of score), hence sort tier first, then score. Null tier: rows are shown, ranked last, displayed as an em dash.

Readout keys, evaluated against the chosen readout (section 2):

| Key | Meaning |
|---|---|
| `none` | request has no readout |
| `draft` | Status = Draft |
| `pending` | Status = Pending Approval |
| `approved-unsent` | Status = Approved AND `Notification_Sent_Date__c` = null |
| `published` | Status = Published |

Published rows appear only under the `published` key or with no readout filter ("any"). An Approved readout that already has a notification sent has no key of its own and is visible only with no readout filter. The readout column always shows the real `Status__c` (or "None yet"), independent of the keys.

Preset `ready-to-book`: expanded server-side to status New AND tier IN (Fast-Track, Accelerator-Ready), intersected (AND) with every other active dimension, not overriding them. The LWC never sends the expanded values. The expansion exists only in this class; Overview counts must call the same method.

Combination: OR within a dimension (multi-select, one comma-separated param per shared contract F3), AND across dimensions. `range` and `preset` are single-valued.

### 3.3 Date range

Field: `Submitted_At__c`, falling back to `CreatedDate` when null: `(Submitted_At__c >= :s AND Submitted_At__c < :e) OR (Submitted_At__c = null AND CreatedDate >= :s AND CreatedDate < :e)`.
Both boundary dates are inclusive, whole calendar days in the running user's time zone: `s = Datetime.newInstance(fromDate, Time.newInstance(0,0,0,0))`, `e` (exclusive) = start of the day after `toDate`. Use `Date.today()` and `Datetime.newInstance(Date, Time)` (user-timezone based); no `Datetime.now()` arithmetic, no GMT. Preset `N` = last N calendar days including today: `from = today - (N - 1)`, `to = today`. Custom `from..to`: reversed pair is swapped, unparseable value is dropped. Tests: day-N edge in, day-N+1 out, null `Submitted_At__c` falling back, boundary-midnight rows.

### 3.4 Ownership and scoping

One predicate, the request predicate, for every row, the count and `offeringOptions`:
- `hasViewAllRecords('GTM_Assessment_Request__c')`: `ObjectPermissions` (`PermissionsViewAllRecords = true`) joined to `PermissionSetAssignment` for `UserInfo.getUserId()`. True: no owner clause. False: `OwnerId = :me` (plus the orphan arm below).
- The new class carries its own private copy, equivalent to the one in `GtmReadoutController` (the generalized check from `rep-data-scoping-owd-3`). It must NOT use the permission-set-name check in `GtmHomeSnapshotController.isAdmin()` (`PermissionSet.Name = 'GTM_Offering_Admin'`). A third private copy is accepted to keep this issue small; one shared helper is a separate refactor issue.

**Queue-owned orphan readouts do NOT stay reachable through the bare request predicate. This is a real regression risk the Developer must close.** `Generator.resolveOwnerId` falls back to the `GTM_Readout_Triage` queue only when no rep can be named (a direct booking with no Engagement Link or Opportunity). `GtmAssessmentRequestController` stamps the request `OwnerId` only from a config owner, so in that case the request is not owned by a rep. A queue-member rep fails `OwnerId = me` and a bare owner filter would drop exactly the orphans the old list surfaced. Decision: for non-view-all users the visible request set is

```
OwnerId = :me
OR Id IN (SELECT Assessment_Request__c FROM GTM_Readout__c WHERE OwnerId IN :myQueueIds)
```

`myQueueIds` = the user's direct `GroupMember` queues (`Group.Type = 'Queue'`), the logic of the removed `myQueueIds()`. The readout read behind it runs under `with sharing`, so it matches only readouts the user can see.

**DEVIATION 1 (orphan arm mechanics).** As written above the arm cannot work: a `with sharing` read of the request still applies the Private OWD, so a queue member who does not own the request never sees it, whatever the WHERE clause says (there are no sharing rules on the object). Also, SOQL semi-joins are unreliable inside an OR. Implemented instead: (a) `with sharing` read of readouts owned by the user's queues gives a set of request ids; (b) the visible-request query is plain `OwnerId = :me` (or no owner clause for view-all); (c) the request rows for the orphan ids from (a), with the same filters, are fetched by the `without sharing` inner class and unioned by Id. Exposure is limited to requests behind readouts that the user's own queues already own (and can see), with the same light request columns as the main query, and is at parity with what the old readout grain showed those members. This widens the addendum's "readout join only" elevation by one read; the Architect should confirm.

UNVERIFIED and not testable without a live org (not authorised): whether the workspace's UI API `getRecord` on the request succeeds for a queue member who does not own the request under the Private OWD. The old card grid opened the same workspace for the same orphan, so this issue does not worsen it. Developer leaves a code comment; QA lists it as an open check for the first authorised deploy. Do not widen request sharing here.

Readout join visibility: a readout's owner is the Opportunity owner first, then the request owner, so it can differ from the rep who owns the request. A `with sharing` join would show "None yet" for a readout that exists and invite a duplicate Generate. So the join is a narrow private inner class `without sharing` (precedent: `Generator` in `GtmReadoutController`), restricted to `Assessment_Request__c IN :visibleRequestIds` (ids already scoped above) and returning only `Id`, `Status__c`, `Notification_Sent_Date__c`, `Assessment_Request__c`. No content fields. The workspace still enforces the user's real access when opened. Tests must include a rep who owns the request while another user owns the readout.

### 3.5 Sorting

Default `best-fit`: tier rank DESC, score DESC (null last), coalesce(submittedAt, createdDate) DESC, Id DESC (stable paging tiebreak). Column sorts (`tier`, `score`, `status`, `readout`, `submitted`, `contact`, `company`) apply the named key, then the default chain for ties. All in Apex. `onsort` re-queries from offset 0.

### 3.6 Algorithm, true count, paging

The readout dimension and tier-rank sort cannot be one SOQL. In order:
1. One SOQL for candidates using the natively filterable dimensions (owner arms, status, tier, offering, date, preset expansion), light columns only. Safety ceiling `LIMIT 10000`; if hit, `totalIsCapped = true` and the UI shows "10,000+".
2. One SOQL for the chosen readout per candidate (inner class, `ORDER BY Assessment_Request__c, CreatedDate DESC, Id DESC`, first per request wins).
3. Apply the readout filter in Apex, sort in Apex with the rank map. `totalCount` = size after this step (the TRUE total, not the page size, not any 200 cap). Slice `[offset, offset + pageSize)`.
4. **DEVIATION 2:** no separate hydration query. `Contact__r.Name` and `Account__r.Name` ride on the step 1 candidate query, because sorting by contact/company needs the names for every candidate, not just the page.

Three or four SOQL and at most 10,000 light rows: fine at expected volume. If volume ever pressures this, the sanctioned step is a roll-up/formula field, not client-side logic.

## 4. LWC contract (`gtmReadoutsOverview`)

- `getAssessmentPage` is called imperatively, not `@wire`. First load and every filter/sort change reset `offset = 0` and replace rows. `onloadmore` appends the next page and is a no-op while loading or when `rows.length >= totalCount`.
- Filters via `c-gtm-filter-bar` + `gtmFilterUrlState`, params exactly `c__astatus` (chips, multi), `c__atier` (chips, multi), `c__areadout` (chips, multi), `c__arange` (date-range: 7/30/90 and custom), `c__aoffering` (multi chips, options from `offeringOptions`; any offering already in the URL is kept in the options so `readFilterState` does not drop it before the first response arrives), `c__apreset` (toggle "Ready to book"). Option keys/labels for status, tier, readout and preset are the 3.2 ones; the LWC contains no filter logic.
- URL writes for filters: shared `buildNavigateArgs` + `NavigationMixin.Navigate(pageReference, true)` (shared-filter-bar decision F1), with `currentState = mergeLocationState(wiredState)` so the `history.replaceState` writer `writeSelectionToUrl()` (`c__assessmentRequestId`, `c__readoutId`, `c__offeringKey`, `c__browseMode`, `c__repDirectId`) and the filter writer never clobber each other. Do not migrate `writeSelectionToUrl()` and do not use `history.replaceState` for filter params. Jest covers both directions.
- Filter writes build `currentState` from `mergeLocationState(wiredState)` and then overlay the component's own selection params from memory (set when truthy, deleted when blank). **DEVIATION 4:** without this, a param removed by `writeSelectionToUrl()`'s `replaceState` (e.g. Back from a deep-linked workspace) survives in the stale wired state and would be resurrected into the filter Navigate, reopening the workspace. Jest covers it.
- `capturePageRef` parses filters with `readFilterState` BEFORE the existing `if (!state.c__assessmentRequestId) return;`. A re-fired reference with unchanged filters must not refetch (idempotent).
- Account mode (`c__browseMode=account`): filter params preserved in the URL and ignored; no bar, no table, no fetch for them.
- Result line: "N assessments" from `totalCount`, shown by the shared bar's `resultCount`; **DEVIATION 3:** the bar renders a number only, so a capped total is not passed to it and the component renders its own "10,000+ assessments" line instead. Filtered-empty: "No assessments match these filters" with Clear all. True empty: "No assessment submissions yet."
- Pure, exported-for-test model module `gtmAssessmentsTableModel` (column defs, row mapping, `buildRecordUrl`, query builder from filter values).
- Datatable: fixed-height container, `key-field="recordId"`, `hide-checkbox-column`. Columns in order: Assessment (button), Contact (url), Company (url), Tier, Score, Request status, Readout, Submitted. Colours via `cellAttributes.class` with SLDS utilities.

## 5. `getReadoutsForReview`: REMOVE

Its only production caller is this component (verified: no other LWC, Aura or Apex caller; only `GtmReadoutControllerTest` references it). Removing it also removes the private `myQueueIds()` (logic moves to the new class). Keep `ReadoutSummary` (used by `getAllReadouts`, `getReadoutForRequest`) and `hasViewAllRecords` (used by `getContactsWithRequests`). Port, do not just delete, the tests that still guard behaviour: the rep-data-scoping-owd-2 two-rep OWD test (near `GtmReadoutControllerTest` line 1243) and queue-orphan visibility, into `GtmAssessmentListControllerTest`. Delete the "Draft and Approved only" tests (that behaviour is intentionally gone). Method-level removal needs no destructive-changes manifest.

## 6. Overview consistency

`GtmHomeSnapshotController` still uses the permission-set-name `isAdmin()`. The `overview-sales-dashboard` issue must move its tile counts onto `getAssessmentPage` so tile and tab share one predicate. Not done here; do not copy `isAdmin()`.

## 7. Developer first-hour checklist (native-API spot check, no org)

1. Current Lightning Component Reference: `lightning-datatable` `enable-infinite-loading`, `onloadmore`, `load-more-offset`, `sorted-by`, `sorted-direction`, `onsort`, `hide-checkbox-column`; column types `url`, `button`, `date`, `number`; `cellAttributes.class`/`iconName` with `fieldName`.
2. Apex Developer Guide: `Datetime.newInstance(Date, Time)` and `Date.today()` use the running user's time zone.
3. Any failure: stop and report to the Architect.

## 8. Execution restrictions

No live deploy, no `sf apex run test`, no `deploy.sh` against `gtm-prod` (Production) for Developer or QA. Validation = `npx sfdx-lwc-jest -- gtmReadoutsOverview gtmAssessmentsTableModel`, full `npm test`, and the repo's local validation scripts. Apex tests are written and reviewed but executed only after the owner later authorises a deploy; they create their own data (`@TestSetup`, `System.runAs` for two reps, an admin with view-all, a queue member) and never touch live data.

---

# Addendum A: Account and Contact filters (issue `assessments-account-filters-apex`)

Source of truth for the full design: `docs/architecture/gtm-filter-bar.md` Addendum C.10.3 (the LWC half, `gtmReadoutsOverview` and `gtmAssessmentsTableModel`, is a later branch). This addendum records only the Apex contract change to `getAssessmentPage` and the new options method. It supersedes section 4's line "Account mode (`c__browseMode=account`): filter params preserved in the URL and ignored" once the LWC half ships (the "By Account or Contact" mode is folded into the filters).

## A.1 `AssessmentQuery`

Two new optional members: `List<String> accountIds`, `List<String> contactIds`. Normalisation: each value parsed with `Id.valueOf` in `try/catch`, kept only if its sObject type is Account (respectively Contact), de-duplicated, first 50 kept. `null` or empty means no filter. A NON-EMPTY list with NO valid id makes the query impossible (zero rows), unlike status and tier which drop unknown values: an "active" filter must never show an unfiltered list. SQL: `Account__c IN :accountVals`, `Contact__c IN :contactVals`, ANDed with every other condition and with each other (OR within a filter). `accountVals` and `contactVals` must exist as locals with those exact names in `queryVisible` and `ElevatedReads.queryOrphans`. Ownership, `with sharing`, the queue-orphan arm and the 10,000 candidate ceiling are unchanged; the new conditions live inside the same predicate.

## A.2 `getAssessmentFilterOptions(String kind, String searchTerm, List<String> includeIds)`

`@AuraEnabled`, not cacheable, `with sharing`, zero DML and callouts. Returns `List<FilterOption {value, label, sublabel}>`, at most 50 (plus visible `includeIds`, de-duplicated).
- `kind` whitelist `'account'` | `'contact'` (constant field names; Apex string comparison is case-insensitive); anything else throws a plain `AuraHandledException` (message `Unsupported filter kind.`, set with `setMessage`), by user decision, superseding the earlier "returns empty" wording.
- Scope: the same viewAll / `OwnerId = :me` / queue-orphan predicate as `getAssessmentPage`, from one shared private helper (orphan ids resolved through `ElevatedReads`, the only `without sharing` code).
- Only parties with at least one visible request (`Account__c != null` / `Contact__c != null`), ordered by name, `LIMIT 50`. GROUP BY note: `GROUP BY Account__r.Name` is unverified offline and the `GROUP BY Account__c` plus `SELECT ... FROM Account WHERE Id IN :ids` fallback would drop parties whose Account the rep cannot read under the Private OWD (labels would no longer match `toRow`). Implemented instead: a non-aggregate read of the request columns already used by `toRow` (`Account__r.Name`, `Contact__r.Name`, `Company__c`, `Requester_Name__c`), `ORDER BY <parent name>, Id`, `LIMIT 2000` rows (constant `PARTY_SCAN_LIMIT`), de-duplicated to parties in Apex and truncated to 50. Known limit: if the first 2,000 rows (alphabetical by party) hold fewer than 50 distinct parties, later parties are not listed; search narrows it. Contact `sublabel` is the request's account name (else company). Never an account or contact without a request. Labels as `toRow` (`Account__r.Name`, `Contact__r.Name`, fallbacks `Company__c` / `Requester_Name__c`); contact `sublabel` is the company.
- `searchTerm`: trimmed, at most 80 characters, bound as `:likeTerm = '%' + escaped + '%'` with `%`, `_`, `\` escaped; blank returns the first 50 alphabetically. Field names never come from user text.
- `includeIds`: at most 50; only visible, correctly typed ids are returned (for labelling restored deep links).

## A.3 Consumers and grants

`GtmActTodayController` calls `getAssessmentPage`; both new members are optional so it is unaffected (its test stays unmodified). No permission-set change: `GtmAssessmentListController` is already granted in `GTM_Offering_Admin` and `GTM_Offering_User`. No object, field, tab or metadata change. Tests: `GtmAssessmentListControllerTest` (hermetic: own data, zero offerings) and `GtmActTodayControllerTest` unmodified; then the full local suite on `gtm-staging` before any `gtm-prod` deploy.

---

# Addendum B: Contact/Account cell rendering, naming and precedence (issue `pages-table-account-column-consistency`)

Supersedes section 1.1's "no custom column types in v1" and the "Company" naming used
throughout sections 1-7 and Addendum A above (left as-is there since it documents
historical decisions; this addendum is the contract of record for the current shape).

## B.1 Column rename

The **Company** column (`companyLabel` field, `companyDisabled`/`companyTitle`
typeAttributes -- internal names unchanged) is now labelled **"Account"**, matching the
Pages table (`gtmRepLinkTableModel.js`, `docs/architecture/gtm-link-stage-filter.md`).
No "company" wording remains in either table's visible UI (headers, tooltips, empty
states). `COLUMNS` order is otherwise unchanged: Assessment, Contact, Account,
Readiness tier, Score, Request status, Readout, Submitted.

## B.2 Cell type: `gtmLink`, shared with the Pages table

Both `Contact` and `Account` columns now use the shared `gtmLink` custom
`lightning-datatable` cell type (`c/gtmLinkDatatable` + `c/gtmLinkCell`), replacing
`type: 'button'`. This is the exact same construct the Pages table uses -- see
`docs/architecture/gtm-link-stage-filter.md` ("Account/Contact cell type (`gtmLink`...)")
for the full typeAttributes contract (`label`, `title`, `disabled`, `name`, `targetId`,
`idField`) and the dispatched `rowaction` event shape. One shared component serves both
tables on purpose so they cannot drift into two different renderings again.

`gtmReadoutsOverview.html` mounts `<c-gtm-link-datatable>` in place of
`<lightning-datatable>`; all other props (`enable-infinite-loading`, `onloadmore`,
`load-more-offset`, `sorted-by`, `sorted-direction`, `onsort`, `hide-checkbox-column`)
are inherited unchanged from the base `lightning-datatable` API section 7 cited.
`handleRowAction` in `gtmReadoutsOverview.js` (`openContact`/`openAccount` via
`NavigationMixin`) needed no change: it only ever read `row.contactId`/`row.accountId`,
which `gtmLinkCell` still supplies on the dispatched event.

Both `Contact` and `Account` cells now render with identical alignment/color whether or
not the row has a real `contactId`/`accountId` -- the base-SLDS
button-vs-disabled-button visual split (blue/left vs. grey/centered) this issue fixed no
longer exists for either table. A row without a lookup keeps its
"No account/contact on this assessment" title (see `getRowActions`'
`ROW_ACTION_LABELS`/inline fallback labels, unchanged) surfaced via the cell's `title`
attribute; it is not link-styled and does not dispatch on click.

## B.3 `company` precedence flip (server-side)

`GtmAssessmentListController.toRow()` now prefers `Account__r.Name` over `Company__c`
whenever both are populated (previously the reverse -- the free-typed `Company__c`
silently masked a governed `Account__r.Name`). `Company__c` remains the display
fallback when there is no `Account__c` lookup at all. Mirrors the identical flip in
`gtmRepLinkTableModel.buildRows` on the Pages table (`docs/architecture/
gtm-link-stage-filter.md`). Covered by
`GtmAssessmentListControllerTest.companyPrefersAccountNameOverTypedCompanyWhenBothArePopulated`
(new) and `rowCarriesContactAccountAndCompanyFallbacks` (existing, still asserts the
no-Company__c fallback path). A request with a typed `Company__c` but no `Account__c`
is a data-quality signal (rep hasn't linked a real Account yet), not a bug; no new UI
flags it in this change (see `docs/backlog.md` for the follow-up note).
