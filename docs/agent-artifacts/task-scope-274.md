# TASK SCOPE — ISSUE #274

## 1. Requirements Breakdown

- **Target Objective:** Three related dashboard-polish defects on the Home/Overview
  page (`lwc/gtmOverview` and its child widgets), reported from user screenshots:
  1. Text truncation (ellipsis on overflow) is missing across every dashboard
     widget's data cells, not just the one table #268 narrowly fixed — needs to
     become a single shared, reusable truncation pattern applied consistently to
     every widget, not another one-off.
  2. In the "Assessment results" widget, one row ("Commercial Metals Company
     (Sample)") renders centered and wraps to two lines while every other row is
     left-aligned single-line — all rows should render identically.
  3. The "Assessment results" card's table does not scroll horizontally at full
     card width the way "Who's hot right now" and other tables on the page do; it
     should be unified onto the same table pattern used elsewhere on the page.

  Broader superset of #268 (which was scoped only to the recent-links table); this
  issue explicitly extends that defect class dashboard-wide.

- **System Component Impacted:** LWC only —
  `force-app/main/default/lwc/gtmOverview/` (the Overview page, hosts the
  "Assessment results" widget inline and lays out "Who's hot right now"),
  `force-app/main/default/lwc/gtmHeatGrid/` ("Who's hot right now"),
  `force-app/main/default/lwc/gtmLinkCell/` (existing truncation utility component,
  used by `gtmHeatGrid`'s Account/Contact columns and by #268's fix), and
  `force-app/main/default/lwc/gtmAssessmentsTableModel/` (the shared column-model
  module `gtmOverview.js` imports `ASSESSMENT_COLUMNS` from — the "Company" column
  override lives in `gtmOverview.js`'s local `RESULT_COLUMNS`, not this module, but
  both need to be checked for the fix). No Apex, no Custom Metadata/YAML, no
  Experience Cloud route is touched — this is pure presentation/rendering.

### Investigation findings (ground truth as of this scoping — verify still current
before building)

- **"Assessment results" already uses a standard component, not a custom table.**
  `gtmOverview.html` (~line 243) renders `<lightning-datatable class="ar-table" ...
  columns={assessmentColumns} ...>` — it is **already** `lightning-datatable`, not
  a hand-rolled table. The issue's "Ask" (confirm whether this is a custom LWC or
  already standard) is answered: it is standard. Per this repo's Salesforce-first
  principle, no swap to a different component is needed here — the fix is styling
  the existing standard component correctly, not replacing it.
- **Root cause of defect #2 (the centered/wrapping row):** `gtmOverview.js`'s
  `RESULT_COLUMNS` (~line 21) defines the first column ("Company") as
  `type: 'button'` (`typeAttributes: { label: {fieldName:'openLabel'}, name:
  'open', variant:'base' }`), while the other three columns (`tierLabel`, `score`,
  `requestStatus`, spread in from `ASSESSMENT_COLUMNS` in
  `gtmAssessmentsTableModel`) are plain text-family columns. `lightning-datatable`
  renders `type: 'button'` cells as a `lightning-button`, which centers by default
  and does not truncate/ellipsis long labels the way a text cell does — that is
  exactly the "Commercial Metals Company (Sample)" row's visual difference from
  every other row. This is a single column's `typeAttributes`/cell-alignment
  problem inside an otherwise-correct standard component, not a structural defect.
  Fix direction: keep `lightning-datatable`, either restyle/left-align the button
  cell to match (SLDS/`lightning-datatable` supports `cellAttributes: { alignment:
  'left' }` and truncation is a known `lightning-datatable` limitation for button
  columns specifically — verify current base-component behavior before assuming a
  CSS-only fix is sufficient) or replace the button-type column with a text-type
  column plus a row-click/row-action handler that opens the same target, so all
  four columns render through the same text-cell path. Either sub-approach is
  buildable; picking between them is a Developer-level implementation decision, not
  ambiguous enough to block scoping.
- **"Who's hot right now" (`gtmHeatGrid`) is NOT `lightning-datatable`.** It is a
  hand-built CSS Grid "table" (`role="table"`/`role="row"`/`role="cell"` divs,
  `.heat-grid` / `.heat-grid__header` / `.heat-grid__row` in `gtmHeatGrid.css`),
  using `c-gtm-link-cell` for the Account/Contact columns and plain
  `{row.opportunityStage}` / `{row.latestSignal}` text spans (no truncation
  wrapper) for the rest. It reads as "consistent" today only because its columns
  are short-text or already using `gtm-link-cell`'s truncation — the underlying
  mechanism is still a custom grid, not a standard component. Per Salesforce-first,
  worth flagging to the Architect whether a rebuild onto `lightning-datatable` is
  in scope for this issue or a separate follow-up — the issue's ask was to confirm
  which components are custom vs standard, not necessarily to force every widget
  onto `lightning-datatable` outright. Recommend treating the truncation +
  alignment + scroll-width fixes as this issue's scope, and open a follow-up note
  (not built here) if the Architect decides `gtmHeatGrid`'s custom grid should be
  replaced outright.
- **Existing truncation utility, currently applied narrowly.** `gtmLinkCell.css`
  already implements the exact pattern needed
  (`overflow:hidden; text-overflow:ellipsis; white-space:nowrap; max-width:100%`)
  and is reused by `gtmHeatGrid`'s Account/Contact columns and by #268's
  recent-links fix. Separately, `gtmOverview.css`'s `.at-name` (~line 150-153,
  "Needs attention today" tiles) hand-duplicates the identical three CSS rules
  locally instead of reusing a shared class/component. This is the concrete
  evidence for problem #1: the pattern exists but is applied ad hoc/duplicated in
  two unrelated places, not centralized — and is entirely absent from
  `gtmHeatGrid`'s Stage/Latest-signal/Next-best-action columns and from every
  plain-text cell in the `lightning-datatable`-based Assessment results and
  Assessments-tab tables. Fix direction: promote the three-rule block into one
  shared, reusable class (e.g. a `.gtm-truncate` utility class in a shared/common
  stylesheet, or reuse `gtm-link-cell` in more places since it is already a real
  component) and apply it to every widget's overflow-prone data cell on this page,
  not just the two currently covered.
- **Root cause of defect #3 (scroll width):** `lightning-datatable` renders its own
  internal horizontal-scroll container sized to its column widths; `gtmHeatGrid`'s
  CSS Grid (`grid-template-columns: 1.2fr 1.2fr 1fr 2fr 1.6fr 1fr`) stretches to
  100% of `.heat-grid`'s parent width with no independent scroll container. These
  are two structurally different width/scroll mechanisms, which is why they behave
  differently at the same card width. `gtmOverview.css`'s `.ov-results-body` only
  sets `overflow-y: auto` (vertical), nothing horizontal — confirm in-browser
  whether `lightning-datatable`'s own internal scroll wrapper is what's rendering
  narrower, or whether an ancestor `.ov-card-b`/`.ov-results` width/padding rule is
  constraining it, before picking a fix. Do not build a second, different table
  wrapper for this card — the issue is explicit that the fix should unify onto the
  existing full-width pattern, not add a third variant.
- **No ambiguity requiring a human decision found for problems #1-#3** — all three
  are concrete, reproducible rendering defects in existing LWC/CSS with a traceable
  root cause above. The one open call worth flagging to the Architect (not
  blocking, per above) is whether rebuilding `gtmHeatGrid` off its custom CSS grid
  onto `lightning-datatable` belongs in this issue's scope or should be a separate
  follow-up — recommend keeping it out of this issue unless the Architect judges
  the truncation/scroll fix requires it structurally.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **No.** This issue never touches
      `GtmAgentProxyController`, any `GtmAgentToolSurface` implementation, or
      GUS-adjacent Apex/LWC.
- [ ] Altering Custom Metadata? **No.** No `instrument/<offering-key>/` YAML or
      `force-app/main/default/customMetadata/GTM_Assessment_*` XML is in scope.
- [ ] Introducing database fields? **No.** No new Apex, SObject fields, or
      permission-set grants are needed — this is LWC template/JS/CSS only.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. Every dashboard widget on the Home/Overview page (at minimum: "Who's hot
     right now", "Assessment results", "Needs attention today" tiles, and any
     other data-cell widget on the page) truncates overflowing text with an
     ellipsis via one shared, reusable pattern (not per-widget duplicated CSS) —
     confirmed by visually reproducing the original long-name overflow case with a
     sample Account/Contact/Opportunity name across each widget.
  2. Every row in the "Assessment results" widget renders identically —
     left-aligned, single-line, no centered/wrapped outlier row — confirmed
     against the specific "Commercial Metals Company (Sample)" record (or an
     equivalent long-name fixture) that reproduced the original bug.
  3. The "Assessment results" card's table scrolls horizontally at full card
     width, matching "Who's hot right now"'s scroll behavior, using the same
     underlying table pattern rather than a second bespoke one.
  4. QA must validate this live in the browser per standing QA policy (not just
     read the diff) — table/scroll/truncation bugs are visual-rendering defects
     that a unit-test pass alone will not catch.
- **Target Test Target:** `lwc/gtmOverview/__tests__/gtmOverview.row3.test.js`
  (existing Assessment-results-row coverage — extend for the column-type/alignment
  fix) and `lwc/gtmOverview/__tests__/gtmOverview.dailyWidgets.test.js`. If
  `gtmHeatGrid` gains a shared truncation class/component, add or extend a Jest
  spec under `lwc/gtmHeatGrid/__tests__/` (create one if none exists) asserting the
  truncation class/attribute is present on its text cells. Run via
  `npm run test`. This is a pure front-end change — no Apex test class is
  affected, no `sf apex run test` needed. QA's browser pass is mandatory before
  sign-off (see Success Metric 4).
