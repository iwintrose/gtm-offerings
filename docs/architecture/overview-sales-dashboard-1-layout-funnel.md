# Overview sales dashboard, piece A: layout shell, funnel, follow-up table

Status: Architect addendum (issue `overview-sales-dashboard-1-layout-funnel`).
Scope source: `docs/agent-artifacts/task-scope-overview-sales-dashboard-1-layout-funnel.md`
(parent: `ba-scope/issue-overview-sales-dashboard`). Siblings B (`-2-act-today`) and C
(`-3-offerings-results`) are out of scope. No new Apex, no new fields, no metadata.

## Salesforce-native-first evaluation (recorded)

| Need | Native option | Verdict |
|---|---|---|
| Funnel | Report/dashboard funnel chart | Rejected (confirmed). Cannot express child-event aggregates, distinct sessions or "Form Submitted event OR linked request"; cannot click through to `GTM_Pages` `c__stage`; would create a second stage definition. Counts come from `GtmLinkStageService`. Trapezoid is custom CSS (`clip-path`). |
| Follow-up table | `lightning-datatable` / tree-grid | Rejected. Account > Contact > Link grouping with chips and stage pill is not expressible. Stays custom. |
| Card chrome (Row 2) | `lightning-card` + SLDS utilities | ADOPT for the two Row-2 cards (title, icon, body) with `slds-grid`, `slds-scrollable_y`, `slds-m-*`; custom CSS only for fixed height, sticky header, trapezoid, chips. Must not change the approved look and must not regress the SLDS-2 button-compliance tests or the `.ov-cols > .ov-card` padding overrides (css ~222-228): if `lightning-card` shadow-DOM styling cannot reproduce the header/body padding with SLDS hooks, keep the existing `.ov-card` wrapper for that card and record why in the PR. |
| Buttons/icons | `lightning-button`, `lightning-icon` | Keep as used today. |

## Decisions on the BA's forks

1. Window: NO "last 90 days". Subtitle: "Links you have sent". Footnote: "Draft and Rep_Direct links are not counted." When `truncated` is true show a small note, "Counts capped at 50,000 links."
2. Stacked (<1100px): both cards keep the shared fixed height (470px).
3. `headerMeta` bridge: read `getSnapshot().newAssessmentCount` (Integer; treat null as 0) instead of `requests.length`; remove the `requests` array and its render. Piece B later moves the tiles and repoints again.
4. `stalledCount` / `countStalled()`: Apex untouched in A; the asides UI is removed and nothing on the page may display `stalledCount`. Piece B must retire `countStalled`, `stalledCount` and their Apex tests so only one definition of stalled/quiet (`quiet`, from the service) exists after B. `getDeals()`: table only, LIMIT 200 and Private OWD scoping unchanged.
5. Funnel has its own state machine independent of `getDeals()`: `funnelLoading`, `funnelError` (reuse the existing error-banner idiom, message from `getStageCountsAura` failure, funnel card only), `funnelEmpty` (`sent === 0`: "No links sent yet"). The follow-up table keeps its own states.
6. `lightning-card`: see table above.
7. Close date: ship, isolated in ONE template block marked `<!-- OPTIONAL: close date (owner may drop) -->`, deletion of which must leave the rest valid. QA flags it.
8. Palette (approved exception; this list is the only new hex allowed):

| Segment (top to bottom) | Fill | Label colour | Contrast |
|---|---|---|---|
| Links sent | `#4a9fe0` | `#181818` | about 6.2:1 |
| Prospect engaged | `#1e3560` | `#ffffff` | about 11:1 |
| Assessment started | `#8fd9d6` | `#181818` | above 10:1 |
| Assessment submitted | `#4aa79b` | `#181818` | about 6.2:1 |

   Correction to the BA note: white on `#4a9fe0` (about 2.9:1) and on `#4aa79b` (about 2.9:1) FAILS AA, so those two use the existing dark text `#181818` (already in the stylesheet, not a new hex). Label colours therefore add no new hex.
9. QA note carried (do not resolve in code): the non-admin rep live gate from `stage-filter-pages-tab` is still OWED. As a rep, funnel counts must match the clicked Pages list; if counts look too low (prospect-generated events under Private OWD), STOP and report. No `without sharing` change is approved.

## LWC data contract (`gtmOverview`)

Imports: `getStageCountsAura` from `@salesforce/apex/GtmLinkStageService.getStageCountsAura` (imperative, called from `connectedCallback`, not wired, since `cacheable=false`).

State: `funnelCounts` (`{sent, engaged, started, submitted, truncated}`), `funnelLoading`, `funnelError`.

Getters: `funnelSegments` returns four items in order `sent, engaged, started, submitted`, each `{key, label, count, ariaLabel, style/class, dropNote}`. Drop-off notes: `Math.max(0, prev - count)`, positive phrasing, never "did not":
- engaged: "N went quiet after the send"
- started: "N opened but have not started"
- submitted: "N started and are still in progress"
First segment has no note. Zero differences show no note. `hasFunnelCounts`, `showFunnelEmpty`, `showFunnelTruncatedNote`.

Segments: `role="button"`, `tabindex="0"`, `aria-label` "<label>: <count>", click plus Enter/Space handler `handleFunnelSegmentActivate` reading `data-key` and calling
`this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: 'GTM_Pages' }, state: { c__stage: key } })`. Space must `preventDefault`.

Layout: Row 2 grid, `grid-template-columns: minmax(0, 5fr) minmax(0, 7fr)` (Developer may tune, must keep the approved look), one custom property `--ov-row2-h: 470px` on the grid, both cards `height: var(--ov-row2-h)`. Follow-up card: flex column, `min-height: 0`, body `overflow-y: auto`, sticky header row (`position: sticky; top: 0`, opaque `#fff` background). Below 1100px grid collapses to one column, height retained.

Removals: as listed in scope item 1 (middle panel, `selectedFunnelStage`, `handleFunnelStageClick`, asides, pagination, old client funnel and its CSS) with their tests deleted, not skipped. Grep `gtmOverview.repDirect.test.js` for collateral.

Permissions: `GtmLinkStageService` classAccess already granted on `GTM_Offering_User` and `GTM_Offering_Admin` (verified). No FLS/permission change.

## Test plan
Jest per scope section 3, new spec `__tests__/gtmOverview.funnel.test.js`, header `ISSUE #overview-sales-dashboard-1-layout-funnel`. Include: deals mock disagreeing with counts mock, counts above 200, truncated note, funnel error/empty independent of table, `headerMeta` from `newAssessmentCount`, no "last 90 days" text, hex allowlist. Validate-only check-only deploy with specified tests (`GtmLinkStageServiceTest`, `GtmHomeSnapshotControllerTest`) is allowed; no real deploy.
