# TASK SCOPE — ISSUE #pages-assessments-loading-state

## 1. Requirements Breakdown

- **Target Objective:** Both the Pages tab (`c-gtm-rep-link-finder`, LWC
  `gtmRepLinkFinder`) and the Assessments tab (`c-gtm-readouts-overview`, LWC
  `gtmReadoutsOverview`, table columns/query builder in `c/gtmAssessmentsTableModel`)
  are slow to load and currently give the rep no clear signal that data is on
  the way. The rep wants a visible loading state on both tabs so a slow load
  reads as "working" instead of "broken/empty."
- **System Component Impacted:** LWC (two components) + Apex (root-cause
  investigation only, no required change to ship the loading UI). No
  Experience Cloud route or YAML instrument involved — both tabs are
  internal rep-facing surfaces (GTM_Offerings app), not guest/prospect-facing.

### Component confirmation (read the actual code, not assumed names)

- **Pages tab** = `force-app/main/default/lwc/gtmRepLinkFinder/` (`GtmRepLinkFinder`
  class). On `connectedCallback()` it fires 4 concurrent Apex calls:
  `getIndustryProfiles`, `getMyConfigurations` (→ `savedLinks`), and two calls
  into `GtmLinkStageService` — `getLinkStatsAura()` and `getStageCountsAura()`.
- **Assessments tab** = `force-app/main/default/lwc/gtmReadoutsOverview/`
  (`GtmReadoutsOverview` class), which imports `PAGE_SIZE`, `buildQuery`, etc.
  from `c/gtmAssessmentsTableModel` as the user's issue description names it,
  and calls Apex `GtmAssessmentListController.getAssessmentPage` /
  `getAssessmentFilterOptions`.

### Root cause of the slow load (for the Developer's awareness — not required to fix)

- **Pages tab:** `GtmLinkStageService.getLinkStatsAura()` and
  `getStageCountsAura()` (`force-app/main/default/classes/GtmLinkStageService.cls`)
  both aggregate over up to `UNIVERSE_LIMIT = 50000` `GTM_Saved_Configuration__c`
  rows via a semi-join `SELECT ... GROUP BY` on the related visit-event object,
  with no pagination — this is a full aggregate scan, not a bounded query, and
  is very likely the dominant cost, run twice per page load, in parallel with
  `getMyConfigurations` and `getIndustryProfiles`. There is no single blocking
  await; the four calls race independently, but the *table itself* only
  reflects real stage/funnel data once the slowest of the four resolves.
- **Assessments tab:** `GtmAssessmentListController.getAssessmentPage` is
  already paginated (`PAGE_SIZE`, server-side sort, `enable-infinite-loading`)
  and bounded (`FILTER_OPTION_LIMIT = 50`, `OFFERING_OPTION_LIMIT = 200`,
  `PARTY_SCAN_LIMIT = 2000` in `GtmAssessmentListController.cls`), so this tab
  is architecturally closer to right-sized; its "slow with no indicator" complaint
  is more likely due to the *missing visible spinner* on first paint (see §3)
  than an unbounded query, though the initial `getAssessmentPage` call still
  has real per-request latency (status/tier/readout joins) worth profiling if the
  rep's specific complaint persists after this UI fix ships.
- **Recommendation (not in this issue's required scope):** open a follow-up
  to either cap/paginate `getLinkStatsAura`/`getStageCountsAura` or move that
  aggregation to a cached/summary object, since a spinner masks but does not
  fix a query that scales with total saved-configuration volume. Flag this to
  the Architect/Developer explicitly rather than silently absorbing it into
  this ticket's Definition of Done.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No — neither component is a GUS
      (Go-To-Market Utility Sidekick) tool/action surface; zero-DML rule
      (AGENTS.md §1) does not apply, no DML is introduced by this change.
- [ ] Altering Custom Metadata? No — no `instrument/<offering-key>/` YAML or
      `GTM_Assessment_*` custom metadata is touched by adding a loading
      indicator.
- [ ] Introducing database fields? No — no new Apex-exposed fields, objects,
      or schema. No permission-set mapping is required.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. **Pages tab:** on initial `connectedCallback()` load (before
     `getMyConfigurations`/`getIndustryProfiles`/`getLinkStatsAura`/
     `getStageCountsAura` all settle), the rep sees a visible loading
     indicator over the "Your recent links" table area — reuse the existing
     `lightning-spinner` pattern already present in this same file (see the
     `loadingSavedLinks`/`loadingLinks`/`stageLoading` spinners in
     `gtmRepLinkFinder.html`) rather than inventing a new pattern. A single
     combined "initial load" boolean (true until the first `loadSavedLinks()`
     promise settles, at minimum) is acceptable; the existing narrower
     spinners for saved-links/detail-open/stage-filter can stay as-is for
     their sub-states.
  2. **Assessments tab:** on initial `connectedCallback()` load (`isLoading`
     is already tracked in `GtmReadoutsOverview` but only feeds
     `lightning-datatable`'s `is-loading` attribute, which is easy to miss on
     a still-empty table before any rows exist), add a page-level
     `lightning-spinner` (same pattern/size convention as `gtmRepLinkFinder`)
     visible while `isLoading` is true and no rows have loaded yet, so the
     rep gets a clear signal even before the table renders any row shell.
     Keep the existing `is-loading`/`enable-infinite-loading` behavior on the
     datatable itself for subsequent "load more" pagination — that part
     already works correctly and is out of scope to change.
  3. No new spinner/skeleton component is introduced; both tabs reuse
     `lightning-spinner`, matching every other component in
     `force-app/main/default/lwc/*` (see e.g. `gtmAssessmentDetail`,
     `gtmLinkActivity`, `gtmReadoutView`, `gtmFeedbackQueue`) that already
     uses this exact base component for the same purpose.
  4. Root-cause query cost (see §1) is explicitly called out as a follow-up
     recommendation, not silently treated as "fixed" by the spinner.
- **Target Test Target:**
  - `force-app/main/default/lwc/gtmRepLinkFinder/__tests__/gtmRepLinkFinder.test.js`
    (and/or a new focused test file in that `__tests__/` directory covering
    the loading-state assertion) — extend to assert the loading indicator is
    present immediately after `connectedCallback()` and cleared once all
    initial calls resolve.
  - `force-app/main/default/lwc/gtmReadoutsOverview/__tests__/gtmReadoutsOverview.test.js`
    — extend to assert the new page-level spinner renders while `isLoading`
    is true and no rows are yet present, and disappears once `loadAssessments()`
    resolves.
  - `npm test` must pass for both suites; no Apex test changes are required
    since no Apex is being modified under this issue's required scope.
