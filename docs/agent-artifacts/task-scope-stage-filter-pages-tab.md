# TASK SCOPE — ISSUE #stage-filter-pages-tab

## 1. Requirements Breakdown

- **Target Objective:** Make the Overview funnel actionable. A rep clicks a funnel stage (or a "Came back" / "Went quiet" tile) and lands on the Pages tab (`GTM_Pages` -> `gtmPageBrowser` -> `gtmRepLinkFinder`) filtered to exactly the links in that stage, across all their pages. The same definitions must be callable by GUS chat (issue `gus-stage-filter-tool`) so "show me links that went quiet" returns the identical list, and the Overview counts (issue `overview-sales-dashboard`) must equal the filtered list length. Stage definitions therefore live in ONE server-side Apex class. This issue owns that shared contract, the Apex class, and the Pages-tab filter UX. It does NOT change `gtmOverview` and does NOT build the GUS tool.
- **System Component Impacted:** Apex (new `GtmLinkStageService` + `GtmLinkStageServiceTest`), LWC (`gtmRepLinkFinder` + its Jest spec). Possibly a one-line pass-through in `gtmPageBrowser` only if it does not already forward URL state (it does not need to — `gtmRepLinkFinder` reads `@wire(CurrentPageReference)` itself). Permission sets: class-access grants only (see §2). No Experience Cloud route, no YAML.

### 1.0 Findings from the current code (verified, some contradict the brief's wording)

1. `getDeals()` lives in **`GtmHomeSnapshotController`**, not `GtmSavedConfigurationController`. It selects `GTM_Saved_Configuration__c WHERE Opportunity__c != null ORDER BY CreatedDate DESC LIMIT 200`, no `OwnerId` filter (relies on `with sharing` + Private OWD only), then aggregates `GTM_Link_Event__c` by (config, Event_Type__c) and builds `views` (Page View count), `formOpened`, `formSubmitted`, `droppedOff`, `lastActivity` (MAX CreatedDate across ALL event types, including Section Viewed / Session End / Form Field), and newest `requestId`.
2. `gtmOverview.get funnel()` derives (client-side, from `getDeals()` rows): `sent` = every deal; `opened` = `views > 0`; `started` = `formOpened === true`; `converted` ("requested") = `!!requestId || formSubmitted === true`. The stages are NOT enforced cumulative: a link can have `formOpened` with zero Page Views (e.g. Form Opened logged by the resume path), so today's funnel can be non-monotonic.
3. `GtmHomeSnapshotController.countStalled()` (tile `stalledCount`) = distinct configs with a `Form Opened` event minus those with a `Form Submitted` event. It (a) ignores `GTM_Assessment_Request__c` (the funnel's "converted" counts a request even with no Form Submitted event), (b) has no Opportunity requirement and no LIMIT, and (c) uses an explicit `OwnerId = :runningUserId` on the EVENT rows plus `isAdmin()` (checks `PermissionSetAssignment` name `GTM_Offering_Admin`). So the Overview's stalled tile and its funnel are already computed from different universes and can disagree. This is a pre-existing inconsistency the shared class must resolve.
4. `GTM_Link_Event__c.Event_Type__c` (restricted picklist): Page View, Form Opened, Form Submitted, Drop-off, Section Viewed, CTA Clicked, Form Field, Form Resumed, Session End. `Saved_Configuration__c` on events/requests must be referenced via **dynamic SOQL** (`Database.query`) — established repo convention (comment in `countStalled()`), so the Lookup can be repointed later.
5. `GTM_Link_Event__c` and `GTM_Assessment_Request__c` are Private OWD (rep-data-scoping-owd-1). `GtmSavedConfigurationController.getMyConfigurations()` and `GtmRepLinkFinderController.getContactsWithLinks()` both scope by `OwnerId = :currentUserId` unless the user holds `viewAllRecords` via ANY assigned permission set (`hasViewAllRecords('GTM_Saved_Configuration__c')`, the owd-2 pattern, moving toward the owd-3 generalized check). `GtmHomeSnapshotController` still uses the older `isAdmin()` permission-set-NAME check.
6. `gtmRepLinkFinder` today: two modes. `rlfMode='all'` (default) = quick-access tile grid from `getMyConfigurations()` (base clause `Presentation_Stage__c != null AND != 'Draft' AND != 'Rep_Direct'`, owner-scoped, NO Opportunity requirement, NO row limit). `rlfMode='account'` = Account -> Contact -> Link Miller columns from `getContactsWithLinks(accountId)` (requires `Contact__c != null`). URL idiom: `@wire(CurrentPageReference) captureLinkFinderState(ref)` reads `c__rlfMode`, `c__rlfAccountId`, `c__rlfContactId`, `c__rlfLinkId`, `c__rlfShowPreview|ShowWorkspace|PwRevealed`; `writeDrillStateToUrl()` mirrors state with `history.replaceState` writing only non-default values. The finder has NO stage/status filter today. `gtmOverview` already deep-links to `GTM_Pages` with `{c__rlfAccountId}` / `{c__rlfContactId}`.
7. `Presentation_Stage__c` (Assessment, In_Review, Draft, Sent, Rep_Direct) is the BD workflow stage on the link. It is UNRELATED to the funnel stage keys below. The URL param must not be named or confused with it (hence `c__stage` = funnel stage; docs and code comments must say "funnel stage").

### 1.1 Filter-key definition table (the shared contract)

Unit of counting: one **link = one `GTM_Saved_Configuration__c` row**. "Reached" is cumulative and normalised so the funnel is monotonic (`submitted <= started <= engaged <= sent`). Per-link facts computed once:

| Fact | Exact source |
|---|---|
| `views` | COUNT of `GTM_Link_Event__c` where `Event_Type__c = 'Page View'` for the config |
| `lastVisitAt` | MAX(`CreatedDate`) of events with `Event_Type__c IN ('Page View','Form Resumed')` for the config |
| `hasFormOpened` | any event `Form Opened` OR `Form Resumed` (a resume is an open) |
| `hasSubmittedEvent` | any event `Form Submitted` |
| `hasRequest` | any `GTM_Assessment_Request__c` with `Saved_Configuration__c` = the config |

| Key | Label (UI) | Definition (link qualifies when…) |
|---|---|---|
| `sent` | Links sent | In the universe (below). Every link. |
| `engaged` | Prospect engaged | `views > 0` OR `hasFormOpened` OR `submitted` (normalised up: anyone who opened the form or submitted obviously opened the link). |
| `started` | Assessment started | `hasFormOpened` OR `submitted` (normalised up). |
| `submitted` | Assessment submitted | `hasSubmittedEvent` OR `hasRequest` (matches `gtmOverview`'s `converted` today: `!!requestId || formSubmitted`). |
| `quiet` | Went quiet | `started` AND NOT `submitted`. This is today's `stalledCount` ("opened the form and did not finish") **with one deliberate change**: a link with a request but no `Form Submitted` event is now correctly NOT quiet (today `countStalled()` would count it). Boundary: `Drop-off` events neither add nor remove membership — `quiet` is purely opened-and-not-submitted. |
| `hot` | Came back | `views >= 2` AND `lastVisitAt >= now - 48 hours` (a RETURN visit, i.e. it has been viewed more than once, and the latest visit is recent). Boundary: exactly 48h old is INCLUDED (`>=`); one Page View only is NOT hot; Section Viewed / CTA Clicked / Form Field / Session End / Drop-off never count as a visit (they are in-session noise and would falsely refresh "recent"). Cutoff uses `System.now()` server time — always evaluated at call time, never cached (`cacheable=false`). A submitted link CAN be hot (hot is orthogonal to the funnel; it is a recency signal). |
| `not_opened` | Not opened yet | NOT `engaged`, i.e. `sent` minus `engaged`. (Optional; include — it is the natural complement and costs nothing since `sent`/`engaged` are already computed.) |

Overlap is allowed by design: `quiet` and `hot` are cross-cutting filters, not funnel stages. Only the four cumulative keys plus `not_opened` are mutually consistent as counts (`sent = engaged + not_opened`).

### 1.2 Universe: which links are counted (DECISION NEEDED — flagged for Architect)

Constraint from the brief: the funnel/list must not silently drop links, and Overview count must equal Pages list length. Today's `getDeals()` (Opportunity != null, LIMIT 200) silently drops (a) links with no Opportunity and (b) everything past 200 newest; `getMyConfigurations()` (what the Pages tile grid shows) does neither but also excludes Draft / null-stage / Rep_Direct.

**Recommended universe (Option A, BA recommendation):** exactly the `getMyConfigurations()` base clause — `Presentation_Stage__c != null AND != 'Draft' AND != 'Rep_Direct'` — plus the same owner scoping: `OwnerId = :UserInfo.getUserId()` unless `hasViewAllRecords('GTM_Saved_Configuration__c')`. No `Opportunity__c` requirement, no 200 cap. Rationale: this is precisely the set the Pages tab can already render, so "count == list length" holds by construction, and nothing a rep has sent is dropped. Handle scale by not selecting wide fields in the universe query (Id only) and by aggregating events, with SOQL's 50k-row governor as the honest ceiling; if the universe query ever hits it, the class must surface a `truncated=true` flag rather than silently under-count (Architect to decide flag placement in `StageCounts`).

Consequences the Architect must confirm:
- **Link with no Opportunity:** INCLUDED in every key (they appear on the Pages tab today; the Overview list simply cannot show an opportunity name for them). The Overview issue must therefore either switch its funnel numbers to `getStageCounts()` (recommended) or accept that its deals table (Opportunity-only, LIMIT 200) is a subset of the funnel. This must be called out to the `overview-sales-dashboard` BA as a hard dependency.
- **Rep_Direct link (pageless rep-initiated assessment):** EXCLUDED from all keys, including `submitted`. It was never "sent" as a page, is not in the Pages tab's list, and including it would break count == list. Fork for the human: Rep_Direct assessments that a prospect completes are real submissions the Overview `Requests` panel already shows via `GTM_Assessment_Request__c`; if the human wants them in the funnel, the Pages tab needs a row type for them first (out of scope). Default = excluded; document it in the class header and the key table so GUS explains it accurately.
- **Draft / null Presentation_Stage__c:** EXCLUDED (never finished), same as Pages tab.
- **Inactive links (`Active__c = false`):** INCLUDED (they are in the Pages tile grid, shown "Inactive"; a link that went quiet and was then deactivated is still a link that went quiet). Flag to Architect as a low-stakes confirm.
- **Owner scoping (OWD rules preserved):** scope the UNIVERSE by link `OwnerId` (rep sees only own; `viewAllRecords` holder sees all). Query events/requests by `Saved_Configuration__c IN :universeIds` under `with sharing` and do NOT add an `OwnerId = :runningUserId` predicate on the event/request rows: an event's owner is not guaranteed to equal the link owner (guest-created), and adding it would make a rep's counts silently drop events. Architect to verify event ownership on `gtm-dev` READ-ONLY before deciding (do not run anything that writes to `gtm-dev`, it is production). Admin detection: use `hasViewAllRecords` (owd-2/3 pattern) rather than `GtmHomeSnapshotController.isAdmin()`'s permission-set-NAME check, so `getStageCounts` and the Pages tile grid can never disagree about who sees everything; this must be a private copy or the owd-3 generalized helper if it has landed by then (Architect to check `main`).

### 1.3 Server-side home (one place)

New class **`GtmLinkStageService`** (`public with sharing`, no DML, no `without sharing`). Proposed contract (Architect finalises signatures in `docs/architecture/` first per CLAUDE.md "Contract First"):

```
public static final List<String> STAGE_KEYS =
    new List<String>{'sent','engaged','started','submitted','quiet','hot','not_opened'};

public class StageCounts {            // all @AuraEnabled Integer, keys match STAGE_KEYS
    sent, engaged, started, submitted, quiet, hot, notOpened  // wire name camelCase for LWC
}

// Non-Aura, callable by GUS tool and tests. Throws IllegalArgumentException on unknown key.
public static List<Id> getLinkIdsForStage(String stageKey)

// Non-Aura, single computation shared by both entry points below.
public static StageCounts getStageCounts()

@AuraEnabled(cacheable=false)  public static StageCounts getStageCounts_Aura()   // naming per Architect
@AuraEnabled(cacheable=false)  public static List<Id> getLinkIdsForStageAura(String stageKey)
```

Implementation shape (reuse, do not fork): ONE private method computes a `Map<Id, LinkFacts>` from (1) the universe query, (2) one aggregate over `GTM_Link_Event__c` grouped by (`Saved_Configuration__c`, `Event_Type__c`) selecting COUNT and MAX(CreatedDate) — the same shape `getDeals()` already uses, (3) one aggregate over `GTM_Assessment_Request__c` grouped by `Saved_Configuration__c`. Both public methods are thin projections of that map, so counts and lists cannot diverge. Constant STAGE_KEYS is the single vocabulary GUS imports. Unknown/blank key: `getLinkIdsForStageAura` throws `AuraHandledException` whose message lists the valid keys (so GUS can relay it); blank key is a caller error, not "all" (the LWC simply omits the filter when there is no `c__stage`).

`GtmHomeSnapshotController.countStalled()` and `getDeals()` are NOT edited by this issue. Follow-up (Overview issue): `stalledCount` should be replaced by `getStageCounts().quiet`. Until that lands there are two definitions of stalled; call this out in the PR description and in the class header so it is not mistaken for finished.

### 1.4 Pages tab UX (`gtmRepLinkFinder`)

- **Control (AMENDED: consume the shared component, do not build a bar):** the product owner wants the filter UI reusable app-wide, so foundation issue `shared-filter-bar` (branch `ba-scope/issue-shared-filter-bar`, merges FIRST) delivers a presentation-only, config-driven filter-bar LWC plus a URL-state helper, in the style of `gtmModalShell`. `gtmRepLinkFinder` must NOT hand-roll chips; it passes the shared bar a config: a single-select chip set with URL param `c__stage`, options `sent` (Links sent), `engaged` (Prospect engaged), `started` (Assessment started), `submitted` (Assessment submitted), `quiet` (Went quiet), `hot` (Came back), each carrying its live count from `getStageCounts`, plus the bar's own clear/"All" affordance and active-filter display. `not_opened` stays a valid SERVER key (GUS/URL may use it) but is NOT a chip in this config by default (Architect may add it). Exact prop names, event names and helper API are owned by `shared-filter-bar`'s contract; this scope assumes only: config in (param name, options with key/label/count), a change event out, and a helper to read/write the URL param via the same `@wire(CurrentPageReference)` idiom. If that contract is not yet merged when the Architect starts, the Architect must pin to it rather than let this issue define a competing one. This issue still owns: the chip config, mapping counts into it, the intersect/filter logic, the result count and empty/error states. Active chip is shown and clearable via the shared bar (re-click active / All / Clear).
- **URL state:** `c__stage=<key>` (read/written through the shared URL-state helper where it fits, otherwise) read in the existing `captureLinkFinderState` wire and written by `writeDrillStateToUrl()` using the same "only non-default value written" convention (absent param = no filter). An unknown `c__stage` value must be ignored (no filter, no error banner spam; a small inline "Unknown filter" note is acceptable) so stale bookmarks never break the tab. `c__stage` must survive the tab's other URL writes (`writeDrillStateToUrl` rewrites the whole set — it must include `c__stage` in its param list or it will strip it on the first tile click).
- **Interaction with existing filters (preserve them):** `c__rlfAccountId` / `c__rlfContactId` / `c__rlfLinkId` keep working. Stage is INTERSECTED with them: the finder fetches the id set once via `getLinkIdsForStageAura(stage)` and (a) in `all` mode filters `tileRows` by `recordId in set`, (b) in `account` mode filters each Contact's `links` (and hides Contacts left with none) by the same set. Explicit fork resolved by BA: a `c__stage` deep link with NO account param forces/keeps `rlfMode='all'` (the grid is the only view that lists all links); a link with BOTH account and stage stays in account mode with the stage intersected. Do not add new Apex to the two existing link queries; the intersection is client-side over the id list, reusing `getMyConfigurations` / `getContactsWithLinks`.
- **Result count:** "N links — <stage label>" reflects the rendered tile/link list length after all filters (account + stage), so with no account filter it equals the Overview count for that key. Empty result: a specific empty state ("No links have reached <stage> yet") with a Clear filter action, distinct from the existing "no saved links" empty state and from a load error (error state shows the Apex message and falls back to UNFILTERED list with the error banner, never a silently empty list).
- **No param:** identical to today (no chips highlighted except "All", no extra Apex call required beyond the counts for the chip badges; if the counts call fails, chips render without badges and filtering still works).
- **Race/staleness:** counts and id set are fetched fresh on each mount and on each `c__stage` change (time-dependent `hot`); no `cacheable=true`.

### 1.5 URL contract other issues rely on (exact)

- **Navigate (Overview issue, and any future caller):**
  `this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: 'GTM_Pages' }, state: { c__stage: '<key>' } })`
- `<key>` is exactly one of: `sent`, `engaged`, `started`, `submitted`, `quiet`, `hot`, `not_opened` (lowercase, underscore, no other spellings; note these differ from `gtmOverview`'s internal `opened`/`requested` state keys — Overview must map `opened` -> `engaged`, `requested` -> `submitted`, `stalled` -> `quiet`, "Came back" -> `hot`).
- May be combined with `c__rlfAccountId` / `c__rlfContactId`. No other new params are introduced.
- **GUS contract:** GUS returns/consumes the same vocabulary and calls `GtmLinkStageService.getLinkIdsForStage(<key>)` (non-Aura, read-only, respects the running user's OWD scoping) and `getStageCounts()`; it must NOT re-implement any definition. GUS is a zero-DML tool surface (see §2).

### 1.6 Open forks (genuinely need a human / Architect; do not treat as settled)

1. **Universe** (§1.2): confirm Option A (Pages-tab set: no Opportunity requirement, no 200 cap, Rep_Direct excluded). Alternative Option B (keep `Opportunity__c != null`, keep LIMIT 200) makes Overview and Pages diverge from what the Pages tab shows unless the Pages filter is also restricted to Opportunity-linked links, which contradicts "the list must not silently drop links". BA recommends A.
2. **`hot` semantics:** "return visit" implemented as `views >= 2 AND latest Page View/Form Resumed within 48h`. Alternative: distinct `Session_Id__c` >= 2 (a refresh in the same session would not count). Session-based is more accurate but needs a `COUNT_DISTINCT(Session_Id__c)`; confirm which the mockup's "Came back" tile means. Default in this scope = view-count based (matches the `views` number shown in the Overview table).
3. **Rep_Direct in funnel** (§1.2): default excluded.
4. **Event ownership** for scoping (§1.2): needs a read-only check; default = scope by link owner only.
5. **`stalledCount` reconciliation:** this scope changes the definition (request-without-event no longer "quiet"). Confirm the human accepts the (small) behavioural change for the existing tile.
6. **Naming:** `c__stage` intentionally does not collide with `Presentation_Stage__c`; confirm no existing `c__stage` param on `GTM_Pages` (grep found none in `gtmPageBrowser` or `gtmRepLinkFinder`).

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? **NO change to GUS in this issue** (that is `gus-stage-filter-tool`). But `GtmLinkStageService` is the read-only backend GUS will call, so the zero-DML rule (AGENTS.md §1) is a hard requirement of THIS class: no `insert`/`update`/`delete`/`upsert`/`Database.*` DML, no `without sharing`, no callouts. QA must grep the new class for DML keywords.
- [ ] Altering Custom Metadata? **NO.** No `GTM_Assessment_*` XML, no `migration-accelerator/` YAML, no instrument change.
- [ ] Introducing database fields? **NO.** No new objects, fields, tabs or picklist values (all facts derive from existing `GTM_Link_Event__c`, `GTM_Assessment_Request__c`, `GTM_Saved_Configuration__c` fields). Existing FLS already grants those reads (the current controllers rely on them). **Permission-set implication (CLAUDE.md §6):** no field/object grants needed, BUT the new Apex class requires `classAccesses` entries: add `GtmLinkStageService` (enabled) to `GTM_Offering_User` and `GTM_Offering_Admin` (the same two sets that already grant `GtmHomeSnapshotController`). Not needed for `GTM_Content_*` or `GTM_Guest` (must remain guest-unreachable: class access absent from `GTM_Guest` is what keeps prospects out, per the existing convention). Without the grants, non-admin reps get "insufficient access to Apex class" on the Pages tab.

Other dependencies: (0) HARD DEPENDENCY: `shared-filter-bar` (filter-bar LWC + URL-state helper) must be merged before this issue's Developer step; the Pages tab consumes it via config and adds no bespoke filter markup/CSS of its own. (a) `overview-sales-dashboard` must adopt the key vocabulary and `getStageCounts()`; (b) `gus-stage-filter-tool` calls this class; both should base off this branch's contract doc, not each other. (c) Docs: Architect writes the contract into `docs/architecture/` (new doc, e.g. `gtm-link-stage-filter.md`) before Developer starts. (d) Deploy: no `experiences/` changes, so no `sf community publish` step; but this ships to `gtm-dev` (treated as production) — hold behind any open unexplained regression per deploy-sequencing memory, and the new Apex test class must be run via `--run-tests` on a validate (`--dry-run`) first.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. `GtmLinkStageService` exists, is `with sharing`, has no DML, and is the only place the seven keys are defined; every key's membership matches §1.1 exactly, including boundaries: exactly-48h-old Page View is `hot`, 48h + 1s is not; a single Page View is not `hot`; Section Viewed / Session End alone never make a link `hot`; a link with a request but no `Form Submitted` event is `submitted` and NOT `quiet`; a link with `Form Opened` and no Page View is `engaged` and `started`; a link with a `Drop-off` but no submit is `quiet`; a Rep_Direct and a Draft link are in no key; a link with no Opportunity IS counted; inactive links are counted; `sent = engaged + not_opened`; `submitted <= started <= engaged <= sent` always.
  2. For every key, `getStageCounts().<key>` equals `getLinkIdsForStage(<key>).size()` for the same user (asserted in a single test, including for the seven keys in one org state).
  3. OWD scoping: a rep (non-viewAll) sees counts/ids only for links they own even when another rep's links exist with events; a `viewAllRecords` user (admin) sees all; runs as the correct user via `System.runAs`. No links are dropped at >200 links (bulk test with 201+ links, `Test.startTest` governor-safe) and no per-link SOQL (query count bounded, assert with `Limits.getQueries()`).
  4. `gtmRepLinkFinder`: with no `c__stage` it behaves exactly as before (all existing specs pass unchanged). With `c__stage=quiet` on the page reference it passes the shared filter bar a config with "Went quiet" active, calls `getLinkIdsForStageAura('quiet')`, shows only tiles whose id is in the returned set, and the displayed count equals the tile count. A change event from the shared bar updates the URL (`c__stage`), clicking the active chip / "All" / "Clear filter" removes it and restores the full grid. `c__stage` survives `writeDrillStateToUrl` (a tile click does not strip it). `c__stage` + `c__rlfAccountId` intersect and keep account mode. Unknown `c__stage` value = no filter. Apex failure = error message + unfiltered list, never a silently empty grid. Empty result shows the stage-specific empty state with a Clear action.
  5. The CI header `ISSUE #stage-filter-pages-tab` is present on the scope file and in the PR; `agent-ci-gate.yml` scope-file check passes; class access granted to `GTM_Offering_User` and `GTM_Offering_Admin` and nothing else.
  6. QA validates in the live browser (per QA-browser-validation memory), read-only against `gtm-dev` (production): open `GTM_Pages?c__stage=<key>` for each key as a rep and as an admin, confirm the list count matches the chip count, confirm no-param Pages tab still works, and check every dependent surface (gtmPageBrowser header subtitle/mode toggle, account drill-down, link view, Overview navigation to Pages via account/contact still works). QA must not create, edit or delete any records on `gtm-dev`; seed data for boundary cases comes only from Apex tests (isolated test transactions).
- **Target Test Target:** Apex: `GtmLinkStageServiceTest` (new; every key and boundary above, OWD via `System.runAs`, bulk >200, count == list-size consistency, unknown-key error). Jest (finder consumes the shared bar, so specs assert the CONFIG passed to it and the handling of its change event, not the bar's internals, which `shared-filter-bar` tests itself): `force-app/main/default/lwc/gtmRepLinkFinder/__tests__/gtmRepLinkFinder.test.js` (extend, or a new sibling `gtmRepLinkFinder.stageFilter.test.js` following the `gtmOverview.repDirect.test.js` sibling-spec precedent) run via `npm test -- gtmRepLinkFinder`; also run the full `npm test` and the existing `GtmHomeSnapshotControllerTest` / `GtmSavedConfigurationControllerTest` to prove no regressions in the untouched controllers.

---

# ARCHITECT ADDENDUM (2026-09-19) — resolves the BA forks; supersedes §1.6 and any conflicting text above

Status: scope reviewed, no placeholders. Checklist verdicts confirmed: GUS surface NOT modified (class is the read-only backend; zero-DML/zero-callout enforced, AGENTS.md §1); no custom metadata; no new fields/objects (so no field FLS grants), but class-access grants ARE required. Developer starts only after `shared-filter-bar` has merged to main and this branch has merged main in.

## A. Standing rule: Salesforce-native evaluation (what was considered, why custom)

| Piece | Native option evaluated | Verdict |
|---|---|---|
| Per-key membership (quiet / hot / submitted etc.) | Standard list-view filters on `GTM_Saved_Configuration__c` | Cannot express it: needs child-event aggregates (distinct sessions, "opened form and NOT submitted", a rolling 48h window from now). List views filter only the record's own fields and simple cross-object criteria. Rejected. |
| Same, as stored data | Roll-up summary fields / flow-maintained counters on the link | Event -> link is a Lookup, not Master-Detail, so no roll-up summary. A flow/DLRS counter would add fields (permission grants everywhere), duplicate the source of truth, and `hot` is time-decaying so a stored flag goes stale with no event to trigger a recompute. Rejected. |
| Counts | Report (cross-object custom report type with/without child) + dashboard funnel chart | Can count "has a Form Opened event", but cannot do distinct sessions >= 2 within a rolling window, cannot union "Form Submitted event OR request", and a report cannot hand the SAME id list to the Pages tab or GUS (no shared definition, so count == list length is not guaranteed). Reports API from Apex is heavier than three aggregate queries and no more native in effect. Rejected. |
| Row-level security | Custom sharing code | NOT used: `with sharing` + Private OWD + the existing owner-scope idiom (native). |
| Class visibility | Custom checks | NOT used: native `classAccesses` on two permission sets. |
| Navigation / URL state | Custom router | NOT used: `standard__navItemPage` + `state.c__stage`, read via `CurrentPageReference` (native). |
| Filter UI | Custom chips | Delegated to `shared-filter-bar` (accepted custom, built on SLDS/base components). |
| Pages table | `lightning-datatable` | See section F. |

Custom is therefore justified ONLY for: (1) the shared `GtmLinkStageService` (accepted by product owner) and (2) the grouped Account>Contact>Link view (already exists, accepted). Nothing else custom is introduced by the stage-filter part.

## B. Fork resolutions (final)

1. Universe = Pages-tab set: `Presentation_Stage__c != null AND != 'Draft' AND != 'Rep_Direct'`, owner-scoped (`OwnerId = :UserInfo.getUserId()` unless the user holds viewAllRecords on `GTM_Saved_Configuration__c` via any assigned permission set). NO Opportunity requirement, no 200 cap.
   - CORRECTION TO BA FINDING 6: `getMyConfigurations()` DOES end in `LIMIT 200` (GtmSavedConfigurationController ~line 620). The Pages grid therefore silently caps today, and count == list length would break past 200. Developer must remove that `LIMIT 200` from `getMyConfigurations()` (bounded only by the SOQL row governor) and add an Apex test with >200 links proving all are returned. Callers of that method: `gtmRepLinkFinder` and `gtmSavedLinksBar` (Jest specs mock it; re-run both). Residual risk: Aura response size (~4 MB) at several thousand links; acceptable now (dev holds a handful), revisit with server-side paging if a rep ever nears ~3k links. The service's `truncated` flag covers the SOQL 50k ceiling (below).
2. Rep_Direct and Draft (and null-stage) links are excluded from EVERY key. The Overview issue must state this in the funnel footnote (e.g. "Excludes drafts and rep-direct assessments"). Record in the class header and contract doc so GUS explains it.
3. Inactive links (`Active__c = false`) are included.
4. `hot` = effective distinct visit sessions >= 2 AND latest visit >= now - 48h (exactly 48h old is INCLUDED, i.e. `lastVisitAt >= now.addHours(-48)`).
   - Verified in code: `GtmLinkEventController.logEvent/logEvents` write `Session_Id__c` from the client, which is a `crypto.randomUUID()` minted once per `gtmConfigurator` mount (`_makeSessionId`, with a random fallback); server truncates to 80 chars and stores null only if the client sent blank. Read-only aggregate on gtm-dev: 10 of 10 Page View events have a non-null `Session_Id__c`. So it is reliably populated but not guaranteed non-null, and a page reload mints a NEW session id (so "distinct sessions" == "distinct page loads"; it de-duplicates only the multiple `Page View` call sites within one load, which the count-based rule would double count).
   - Rule (handles nulls, one aggregate): per link, `viewSessions = COUNT_DISTINCT(Session_Id__c)` over Page View rows plus `nullSessionViews = COUNT(Id) - COUNT(Session_Id__c)` (each null-session view counts as its own visit). `hot` iff `viewSessions + nullSessionViews >= 2`. Fallback-to-view-count is therefore built in; no separate mode.
   - `lastVisitAt` = MAX(CreatedDate) over `Page View` and `Form Resumed` events (unchanged from §1.1). `views` shown in the UI = the same effective visit count, so the table and the rule agree. `engaged` still = any Page View row (`COUNT(Id) > 0`) OR form opened OR submitted.
5. `stalledCount`/`countStalled()` is SUPERSEDED. `overview-sales-dashboard` must switch every funnel/tile number to `getStageCounts()` (`stalled` -> `quiet`), delete or stop using `countStalled()` and `getDeals()`-derived funnel counting, and its footnote/help text must say: a link with a request but no Form Submitted event is no longer "quiet" (submitted = Form Submitted event OR a linked `GTM_Assessment_Request__c`). Hand this to that BA as a hard dependency. Until it lands two definitions coexist (call out in PR + class header).
6. Event ownership: scope by LINK owner only; NO `OwnerId` predicate on event/request rows.
   - Read-only aggregate on gtm-dev (counts only): 20 events total, ALL owned by a single user (a Standard-type System Administrator), 16 attached to links owned by that same user, 4 with no link. So dev data shows no guest-owned events and cannot prove or disprove the guest-insert ownership case. Code fact: `GtmLinkEventController` is `without sharing` and never sets OwnerId, and no sharing rule or trigger re-owns events.
   - Real risk the Developer/QA must close: under `with sharing` + Private OWD, a non-admin rep sees only events they own. If prospect (guest) inserts are owned by a guest/site user, a rep's aggregate over events would undercount. The existing Overview has the same exposure (`OwnerId = :runningUserId` on events) and works today, which suggests events land owned by the rep, but that is unverified. QA gate: as a NON-admin rep, on a link with a prospect-generated event, `getStageCounts()` must reflect it. If it does not, contingency (needs coordinator approval because it departs from "class is with sharing"): move ONLY the two aggregate queries into a private inner class declared `without sharing`, fed exclusively by ids from the sharing-checked, owner-scoped universe query, so no unowned link can leak. Do not do this pre-emptively.

## C. Contract (Developer promotes to `docs/architecture/gtm-link-stage-filter.md` as the first commit, before code — Contract First)

`public with sharing class GtmLinkStageService` — no DML, no callouts, no `without sharing`, no per-link queries (exactly 3 SOQL statements per computation: universe Ids; events aggregate; requests aggregate).

- `public static final List<String> STAGE_KEYS = {'sent','engaged','started','submitted','quiet','hot','not_opened'};` single vocabulary GUS imports.
- `public class StageCounts { @AuraEnabled Integer sent, engaged, started, submitted, quiet, hot, notOpened; @AuraEnabled Boolean truncated; }`
- `public static StageCounts getStageCounts()` and `public static List<Id> getLinkIdsForStage(String stageKey)` (non-Aura; GUS calls these; unknown/blank key throws `IllegalArgumentException` whose message lists valid keys).
- `@AuraEnabled(cacheable=false) public static StageCounts getStageCountsAura()`, `@AuraEnabled(cacheable=false) public static List<Id> getLinkIdsForStageAura(String stageKey)` (unknown/blank key -> `AuraHandledException` listing valid keys). Never `cacheable=true` (time-dependent `hot`, and Aura caches cacheable actions).
- Table-view addition (part 2, see F): `public class LinkStat { @AuraEnabled Id linkId; @AuraEnabled Integer visits; @AuraEnabled Datetime lastVisitAt; @AuraEnabled String funnelStage; }` and `@AuraEnabled(cacheable=false) public static List<LinkStat> getLinkStatsAura()`, where `funnelStage` = highest of submitted > started > engaged > not_opened. Built from the SAME private `Map<Id, LinkFacts>`; adds no query.
- Implementation: ONE private method builds `Map<Id, LinkFacts>`. Universe query selects `Id` only, `LIMIT 50000`; `truncated = (size == 50000)`. Events and requests are aggregated with a semi-join on the same WHERE clause (`Saved_Configuration__c IN (SELECT Id FROM GTM_Saved_Configuration__c WHERE <universe clause>)`), not a giant bind list. Iterate aggregate results with a `for (AggregateResult ar : Database.query(...))` loop (a plain `List<AggregateResult>` assignment fails past 2000 grouped rows). Use dynamic SOQL for `Saved_Configuration__c` references (repo convention). Event aggregate: group by (`Saved_Configuration__c`, `Event_Type__c`), select COUNT(Id), COUNT(Session_Id__c), COUNT_DISTINCT(Session_Id__c), MAX(CreatedDate).
- viewAll check: private copy of the `hasViewAllRecords('GTM_Saved_Configuration__c')` helper (same shape as `GtmSavedConfigurationController`). The owd-3 generalized helper has NOT landed on main (grep: none); if it has when the Developer starts, use it instead. Do NOT use `GtmHomeSnapshotController.isAdmin()`.

## D. Permissions and check-references.py

- Add `<classAccesses><apexClass>GtmLinkStageService</apexClass><enabled>true</enabled></classAccesses>` to `GTM_Offering_User` and `GTM_Offering_Admin` ONLY (same pattern as `GtmHomeSnapshotController`). Not to `GTM_Content_*` or `GTM_Guest`. No fieldPermissions/objectPermissions changes.
- `scripts/check-references.py` verification (read, not run against a change): section at ~line 346 flags any permission-set `apexClass` not present in source; the dangling-reference sweep at ~line 1560 does the same. It will PASS provided `GtmLinkStageService.cls` + `GtmLinkStageService.cls-meta.xml` (apiVersion 62.0, Active) exist in the SAME commit as the grants, and the LWC imports use the exact form `@salesforce/apex/GtmLinkStageService.<method>` naming a method that exists (~line 1164/1168 checks). The class is "referenced" via the LWC import and permission sets so it is not reported unreferenced. Developer must run `python3 scripts/check-references.py` (and `scripts/check-all.sh`) before hand-off; add `GtmLinkStageServiceTest` (name must end in `Test`).

## E. Pages-tab filter (stage part) — clarifications

- Consume `shared-filter-bar` exactly as merged; pin to its contract, do not invent props. `c__stage` is the URL param (funnel stage, NOT `Presentation_Stage__c`).
- Counts on chips come from `getStageCountsAura()`; the id set from `getLinkIdsForStageAura(stage)`; both fetched fresh on mount and on each `c__stage` change. Because the table (part 2) needs `getLinkStatsAura()` anyway, part 2 may derive the stage id set client-side from `funnelStage`/stats only for the four cumulative keys; `quiet`/`hot`/`not_opened` still come from the id-list call. Keep one source: prefer calling `getLinkIdsForStageAura` for every key to avoid a second definition in JS.
- `writeDrillStateToUrl()` must include `c__stage` (else the first click strips it). A `c__stage` deep link without an account param forces `rlfMode='all'`. Unknown value = no filter.

## F. Coordinator update: table view for the "all" mode

Current all-mode rendering (verified): `gtmRepLinkFinder.html` "Your recent links" = a `.rlf-tiles` grid of `<button class="rlf-tile">`, one per `getMyConfigurations()` row (company, status pill Active/Inactive, "offering . contact", "Saved <date>"); click = `handleSelectTile` seeds the trail and switches to account mode. The grouped Account>Contact>Link Miller view under `rlfMode='account'` stays untouched.

(a) Proposed columns, only from data that exists (Opportunity/Account/Contact/Offering/Active/CreatedDate/Owner already come back from `getMyConfigurations`; visits/last visit/funnel stage come from `getLinkStatsAura()` which reuses the service's computed facts, no extra query):
1. Account / company (`Company__c` or `Account__r.Name`) — sortable, click = open trail (existing tile behaviour)
2. Contact (`Contact__r.Name`)
3. Offering (`formatLabel(Offering__c)`)
4. Opportunity (`Opportunity__r.Name`, blank when none; links with no Opportunity are valid rows)
5. Funnel stage (`funnelStage` -> label: Not opened / Prospect engaged / Assessment started / Assessment submitted) shown as a status pill
6. Visits (`visits`) and Last visit (`lastVisitAt`, relative or date) — sortable
7. Link status (Active/Inactive) and Saved (`CreatedDate`) — sortable
8. Owner column ONLY for a viewAll user (admins), hidden for reps
Row action: "Open" (same as tile click). Do not add "Assessment" column data that requires new queries; if the product owner wants the assessment status/score, that is a follow-up (needs a per-link readout/request join not present in the service).

(b) `lightning-datatable` evaluation (native first): it natively provides sorting (`sortable` + `onsort`), row actions (`type: 'action'` / `button`), date/url/number/text cell types, keyboard/a11y, column resize, and is already used in this repo (`gtmRecycleBin`, `gtmAssessmentSubmissionView`). Gaps: no native pill/badge cell (use `cellAttributes.class` for colored text or a small custom type extending `LightningDatatable` with a template; custom types are a supported platform mechanism), no built-in row hover/whole-row click (use `onrowaction` "Open" or a link-style `button` cell in column 1), and no built-in client filtering (we filter the `data` array, which is exactly what the shared filter bar drives). Verdict: USE `lightning-datatable`; do NOT hand-build a table. Justify a custom cell type only if the stage pill must be a real pill; a colored-text cell via `cellAttributes.class` is the default and needs no custom type. Also verify it renders under the Lightning Experience app pages this tab lives on (internal only, so datatable's LWC-in-Aura constraints do not apply).

(c) RECOMMENDATION: SPLIT into two sequenced issues, both behind `shared-filter-bar`:
- `stage-filter-pages-tab` (this issue, narrowed): server `GtmLinkStageService` (+ test, permission grants, contract doc, the `LIMIT 200` removal) + `c__stage` filter wired into the EXISTING tile grid via the shared bar + URL contract. This unblocks `overview-sales-dashboard` and `gus-stage-filter-tool` sooner (they need only the service and the URL vocabulary).
- `pages-tab-table-view` (new, starts after this merges): replace the all-mode tile grid with `lightning-datatable`, add `LinkStat`/`getLinkStatsAura()` (the only service addition) and columns/sorting/row action, keeping account mode untouched. It changes rendering, specs and one Apex method; keeping it separate keeps the shared-contract PR small and reviewable. If the coordinator prefers one issue, the Developer should still commit in that order (service + tests, then filter on tiles, then table swap) and `LinkStat` moves into this issue.

---

# ARCHITECT ADDENDUM AMENDMENT (coordinator-approved split) — supersedes sections C (table-view addition), E (table sentence) and F above

**Narrowed scope of `stage-filter-pages-tab` (this issue) is exactly:**
1. `GtmLinkStageService` + `GtmLinkStageServiceTest` (contract in addendum section C, MINUS `LinkStat` and `getLinkStatsAura()`, which are REMOVED from this issue).
2. `classAccesses` grants on `GTM_Offering_User` and `GTM_Offering_Admin` only.
3. Contract doc `docs/architecture/gtm-link-stage-filter.md` (first commit).
4. Remove `LIMIT 200` from `GtmSavedConfigurationController.getMyConfigurations()`, with an Apex test proving >200 links are returned, and a re-run of the `gtmSavedLinksBar` and `gtmRepLinkFinder` Jest specs.
5. `c__stage` filter on the EXISTING tile grid via `shared-filter-bar` (section E; the id set always comes from `getLinkIdsForStageAura`).

**Moved OUT to new issue `pages-tab-table-view`** (a BA is scoping it; starts after this issue merges): the `lightning-datatable` all-mode table, its columns and row action, `LinkStat`, and `getLinkStatsAura()`. Section F of the addendum is retained only as input to that issue. Do NOT build any of it here. The tile grid stays.

**Decisions recorded**
- (a) Guest-created-event ownership stays a QA gate exactly as written in B.6. The `without sharing` inner-class contingency is NOT pre-approved: if QA finds an undercount, STOP and report to the coordinator for approval before any change.
- (b) Keep the private-copy `hasViewAllRecords('GTM_Saved_Configuration__c')` helper in `GtmLinkStageService`. Add a code comment and PR note that it must be de-duplicated onto the shared helper when `rep-data-scoping-owd-3` lands.
