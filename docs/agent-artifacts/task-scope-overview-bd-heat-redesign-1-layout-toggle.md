# TASK SCOPE — ISSUE #overview-bd-heat-redesign-1-layout-toggle

## 1. Requirements Breakdown

- **Target Objective:** Piece 1 of the 4-way split of `overview-bd-heat-redesign` (parent scope: branch `ba-scope/issue-overview-bd-heat-redesign`, see §4 of that doc for the full split rationale). This is the lowest-risk, highest-value first slice: it alone closes out the superseded funnel bug and the "never blend Offerings into Today again" requirement, and it unblocks the remaining sub-tickets (`-2-heat-grid`, `-3-daily-widgets`) by establishing the new page shell. Siblings `-2-heat-grid` (the Account-spined heat grid + Call now/Follow up wiring) and `-3-daily-widgets` (Tasks due today / Readouts awaiting response) are written in parallel and are OUT of scope here. The follow-up ticket `gus-nudge-tool-and-readout-viewed-tracking` (GUS Nudge tool, readout-viewed/replied tracking) is also OUT of scope.

  **In scope**
  1. **Removal:** delete the existing "Pipeline health" 7-node conversion line/funnel from `gtmOverview` entirely — not fixed, not hidden behind a flag, removed. This includes `getStageCountsAura()` consumption inside `gtmOverview.js`, `funnelSegments`/`fs-row`/`fs-shape` and related state/getters/CSS, and its Jest spec (`gtmOverview.funnel.test.js` is deleted, not migrated). Confirm via `grep -n "getStageCountsAura\|funnelSegments\|fs-row\|fs-shape" force-app/main/default/lwc/gtmOverview/*` returning nothing (aside from whatever subset of "Came back"/"Went quiet" tiles in "Needs attention today" the Architect determines still legitimately depend on `GtmLinkStageService` — see open decision below).
  2. **Today/Offerings toggle:** add a toggle control at the page header (`gtmOverview.html`) that switches the page body between two views: "Today" and "Offerings". Persisted view selection is not required for this slice (default to Today on load) unless trivial to add.
  3. **Re-home the offering cards:** the existing per-offering content/performance card (story, configurator, live link count, submitted count, open rate, pages built — i.e. `getHomeSummary`/`getOfferingCounts` output) moves into the new "Offerings" view. When Today is selected, none of this card's markup renders, and vice versa (regression test required: assert offering card markup is absent when Today is selected and present when Offerings is selected, and never both).
  4. **Today view stays as-is:** the existing "Needs attention today" cards (`getActToday` — New requests / Came back / Went quiet / Readout waiting tiles) and "Opportunities waiting on you" follow-up table (`getDeals`/`dealGroups`/`dealRows`) remain in the Today view, functionally unchanged. Only their surrounding page layout (now living under the Today toggle state) changes.
  5. **Open decision for the Architect:** whether the "Came back"/"Went quiet" tiles inside "Needs attention today" (which read `funnelCounts.hot`/`funnelCounts.quiet` from `GtmLinkStageService`) still need that service post-funnel-removal, or whether they are being functionally subsumed by the heat grid in sub-ticket `-2-heat-grid`. Recommended default for this slice: leave those tiles and their `GtmLinkStageService` dependency untouched (they are explicitly in the "stays unchanged" list per the issue brief) — do not remove `GtmLinkStageService` usage from `gtmOverview` wholesale, only the funnel card's usage.
  6. **Supersession housekeeping:** issue `overview-funnel-visualization` is superseded by this redesign (its taper-fix Option-1/Option-2 decision is moot once the funnel is removed outright). The Architect has already recorded this in `docs/backlog.md` and cleaned up that issue's worktree; the Developer does not need to touch that issue's branch or artifacts.

  **Explicitly out of scope for this slice**
  - The heat grid itself, any new Apex aggregation over `GTM_Link_Event__c`, and the "Call now"/"Follow up" button wiring — all `-2-heat-grid`.
  - "Your tasks due today" and "Readouts awaiting response" widgets and their new Apex — `-3-daily-widgets`.
  - The GUS "Nudge" tool, pre-seeded GUS context wiring, and any readout-viewed/replied tracking field — follow-up ticket `gus-nudge-tool-and-readout-viewed-tracking`, not this ticket.
  - `GtmLinkStageService.cls` itself is not modified (still used by the Pages tab's own stage filter per `docs/architecture/gtm-link-stage-filter.md`); only `gtmOverview`'s funnel-card consumption of `getStageCountsAura()` is removed.
  - Any live `gtm-prod` data change or seed script.
  - Reuse note: branch `agent/issue-pages-table-account-column-consistency` (PR #260) built a shared `c/gtmLinkDatatable`/`c/gtmLinkCell` Account/Contact cell-type component. This slice does not need it (no new Account/Contact-bearing table is introduced here — the re-homed offering card and the untouched follow-up table don't need a new cell type). If PR #260 has not merged when the Developer starts, no action is needed for this slice either way.

- **System Component Impacted:** LWC only — `force-app/main/default/lwc/gtmOverview/` (`.js`/`.html`/`.css` and its Jest specs under `__tests__/`). No new Apex, no new SObjects/fields, no Custom Metadata, no YAML instrument content.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO.**
- [ ] Altering Custom Metadata? **NO.**
- [ ] Introducing database fields? **NO.**

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. `gtmOverview` renders a Today/Offerings toggle at the page header; the Offerings view contains only the existing per-offering content/performance card and nothing else; these are never blended into the Today view again (regression test: assert the offering card markup is absent when Today is selected and vice versa).
  2. The former funnel card and all of `GtmLinkStageService.getStageCountsAura()`'s consumption tied to the funnel card are removed from `gtmOverview.js`/`.html`/`.css` (confirmed by the grep above), except for whatever subset of "Came back"/"Went quiet" tiles the Architect/Developer determines legitimately survives inside "Needs attention today" per the open decision in §1.5.
  3. "Needs attention today" cards and "Opportunities waiting on you" follow-up table render unchanged, functionally, inside the Today view.
  4. No new "Company" header or terminology drift introduced (n/a here since no new table is added, but do not regress existing Account/Contact/Opportunity labeling while moving markup).
- **Target Test Target:** `force-app/main/default/lwc/gtmOverview/__tests__/*` — full rewrite/extension of the toggle + removal behavior; `gtmOverview.funnel.test.js` deleted, not migrated.
