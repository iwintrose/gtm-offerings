# TASK SCOPE — ISSUE #overview-bd-heat-redesign-5-visual-parity

## 0. Environment gap (read before anything else)

The BA step for this task ran with **no Artifact/web-fetch tool available** —
only `Read`/`Bash`/`Write` against the local filesystem. The mockup
(`https://claude.ai/artifact/CQa7TFeUiGToJrXvcyDFGE`, `project/Main.dc.html`)
could **not** be opened or diffed against. Everything below about the mockup's
exact class names, hex values, spacing tokens and icon colors is therefore
**inferred from the existing `.ov-card` / `.ov-card-h` pattern already used
elsewhere on this same page** (which the user's complaints describe as the
correct reference — "the rest of `gtmOverview`" already has this chrome), not
confirmed against the mockup markup itself. **The Architect or Developer agent
MUST open `project/Main.dc.html` via the Artifact tool before writing any CSS**
and correct any value below that the mockup specifies differently (exact
colors, the precise `.card-h .ic` icon-circle background/size/border-radius,
and any spacing that differs from what's inferred here). Treat every "inferred
from existing pattern" cell in the table below as a starting hypothesis to
confirm, not a locked spec.

## 1. Requirements Breakdown

- **Target Objective:** Rebuild the visual/chrome layer (HTML structure +
  CSS) of the three widgets added across issues
  `overview-bd-heat-redesign-1` through `-4`
  (`gtmHeatGrid`, `gtmTasksDueTodayWidget`, `gtmReadoutsAwaitingWidget`) and
  the pre-existing "Assessment results" card so every card on the Overview
  Today view shares one consistent chrome language: card background, border,
  top rail, `.ov-card-h` icon-circle header, and body padding — matching the
  approved mockup, not just "close enough." Explicitly a **tear-down and
  rebuild of markup/CSS for these surfaces**, not an incremental patch — the
  user rejected a polish pass.
- **System Component Impacted:** LWC only —
  `force-app/main/default/lwc/gtmOverview/{gtmOverview.html,gtmOverview.css}`,
  `force-app/main/default/lwc/gtmHeatGrid/{gtmHeatGrid.html,gtmHeatGrid.css}`,
  `force-app/main/default/lwc/gtmTasksDueTodayWidget/{...}`,
  `force-app/main/default/lwc/gtmReadoutsAwaitingWidget/{...}`. No Apex, no
  Custom Metadata, no YAML instrument content is in scope. **Data-fetching
  and business logic (`connectedCallback`, wire/imperative Apex calls, row
  shaping, action handlers, navigation) in all four components' `.js` files
  stay untouched** — this is a visual-layer rebuild only. If a class rename
  in the HTML breaks a Jest selector (`data-id`, existing class hooks used by
  `__tests__/*.test.js`), keep the `data-id`/test-hook attributes stable or
  update the tests in the same commit; do not silently break coverage.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **No.**
- [ ] Altering Custom Metadata? **No.**
- [ ] Introducing database fields? **No.**

(All three "if YES" branches are inapplicable — this is a pure front-end
markup/CSS change with no new schema, no GUS tool, no metadata.)

## 3. Widget-by-widget parity table (Today view, in render order)

Reference pattern already live on this page (`gtmOverview.css`): `.ov-card`
(white bg, 1px `#e5e5e5` border, `.25rem` radius, `0 1px 1px rgba(0,0,0,.05)`
shadow, **3px colored top rail** via `border-top-color`, hover lift) +
`.ov-card-h` (flex row, `.6rem` gap, `.7rem .75rem .6rem` padding, `3rem`
min-height, `1px solid #f3f3f3` bottom border, a `lightning-icon` immediately
before an `.ov-h` title) + `.ov-card-b` (`.5rem .6rem .65rem` padding). Five
existing cards already do this correctly: Opportunities to follow up on
(`.ov-deals`, rail `#fe9339`), Assessment results (`.ov-results`), Offerings
(`.ov-offerings`, rail `#9050e9`), and the offering sub-cards (`.ocard`).

| Card | Mockup spec (pending Artifact confirmation) | Current state | Required change |
|---|---|---|---|
| **Heat grid** (`gtmHeatGrid`, "Who's hot right now") | Full `.ov-card` treatment: bg/border/rail/shadow, `.ov-card-h` with icon + title ("Who's hot right now" is implied by the `aria-label` but never rendered as a visible heading today), `.ov-card-b` padding around the table | `.heat-grid` root div has **zero chrome**: no background, no border, no radius, no shadow, no padding, no rail, no icon, no visible title — just a CSS grid dropped straight onto the page's `#f3f3f3` background (`gtmHeatGrid.css` lines 1-5, `gtmHeatGrid.html` line 2) | Wrap in `<article class="slds-card ov-card ov-heat">` with an `.ov-card-h` (icon + a real visible `<h2 class="ov-h">Who's hot right now</h2>`, not just an `aria-label`) and `.ov-card-b` wrapping the existing grid; assign `.ov-heat` a rail color (needs mockup confirmation — no existing rail color assigned to this card yet) |
| **Act Today tiles** (`.at-row` / `.at-tile`) | Not in the complaint list; already has its own chrome (`border-top: 3px solid #0176d3`, bg, shadow) distinct from `.ov-card` — likely correct as-is per mockup, but confirm rail/icon convention isn't meant to apply here too | Has independent tile chrome already (`gtmOverview.css` lines 100-118), no icon | Out of primary scope; Developer should sanity-check against mockup but user did not flag this row |
| **Tasks due today** (`gtmTasksDueTodayWidget`) | Full `.ov-card` treatment: icon-circle header, rail color, `.ov-card-b` body padding matching other cards | Wrapped only in generic `slds-box slds-theme_default` (`gtmTasksDueTodayWidget.html` line 2; `.css` is a 3-line stub with only `position: relative`) — no icon, no colored rail, no `.ov-card-h`/`.ov-card-b` split, plain `<h2 class="slds-text-heading_small">` instead of `.ov-h` | Replace `slds-box` wrapper with `<article class="slds-card ov-card ov-tasks-today">`, add `.ov-card-h` (icon + `.ov-h` "Your tasks due today"), move list into `.ov-card-b`; assign a rail color (needs mockup confirmation) |
| **Readouts awaiting response** (`gtmReadoutsAwaitingWidget`) | Same as Tasks due today — mirrored card | Identical situation to Tasks widget: bare `slds-box slds-theme_default`, 3-line CSS stub, no icon/rail/`.ov-card-h` | Same rebuild pattern as Tasks due today; needs its own rail color (needs mockup confirmation) — must visually pair with Tasks widget as equal-weight siblings (`.ov-daily-widgets` grid already makes them equal-width) |
| **Opportunities to follow up on** (`.ov-deals`) | Reference — already correct | Already has full `.ov-card`/`.ov-card-h`/`.ov-card-b` chrome, rail `#fe9339`, icon `standard:opportunity` | No change needed; used as the pattern reference for the three widgets above |
| **Assessment results** (`.ov-results`) | Full `.ov-card` chrome (already has it structurally) **plus**: no header/table overlap, and subheader typography consistent with other cards | Has `.ov-card`/`.ov-card-h`/`.ov-card-b` chrome and an icon (`standard:task`) already — chrome-wise closer to correct than the 3 new widgets. Two real defects: (1) header/table overlap bug — see §4; (2) `.ov-h-note` (the "View all assessments · Ready to book" sub-row) has **no dedicated CSS rule for `.ov-view-all`/`.ov-ready-to-book`** anywhere in `gtmOverview.css`, unlike every other in-card button group on this page which does get an explicit rule (compare `.ocard-acts .slds-button { font-size: 12px; }` for the Offerings cards) — these two `lightning-button` elements render at default library size/weight instead of matching the page's button language | Fix the overlap (§4) and add an explicit `.ov-h-note lightning-button` (or equivalent) style so the two action buttons match size/weight/color used by every other secondary button on this page, and confirm `.ov-h-stack`'s two-line header layout matches the mockup's subheader typography |

## 4. Root-caused bug: Assessment results header overlapping the table

**Where:** `force-app/main/default/lwc/gtmOverview/gtmOverview.html` lines
211-244 (`.ov-results` card) and `gtmOverview.css` (`.ov-card-h` line 39,
`.ov-h-stack` line 388, `.ov-h-note` line 287).

**Structural difference that isolates this card:** every other `.ov-card-h`
on this page (`Opportunities to follow up on`, `Offerings`, each `.ocard`) is
a single-line header: one `lightning-icon` + one bare `<h2 class="ov-h">`, and
`.ov-card-h` has `align-items: center` with only `min-height: 3rem` — no
explicit height reservation beyond that floor. Assessment results is the
**only** header on the page that stacks a second, interactive row
(`.ov-h-stack` wrapping `.ov-h` + `.ov-h-note`, where `.ov-h-note` holds two
full `lightning-button` custom elements plus a literal `&middot;` text node
between them, per `gtmOverview.html` lines 214-223). That two-row content,
combined with:
- `.ov-card-h`'s `align-items: center` (vertically centers the whole
  `.ov-h-stack` block within the header, rather than pinning it to the top),
  and
- the complete absence of any CSS rule sizing `.ov-h-note`'s two
  `lightning-button`s (no `.ov-view-all`/`.ov-ready-to-book` rule exists in
  `gtmOverview.css` — confirmed via full-file grep), so they render at each
  browser's default Lightning base-component size instead of the page's
  `12px`/`12.5px` secondary-button scale used everywhere else (e.g.
  `.ocard-acts .slds-button { font-size: 12px; }`),

is the mechanism: the header's actual rendered content height is
uncontrolled and inconsistent with the `min-height: 3rem` floor the layout
was designed around, while `.ov-card-b`/`.ov-results-body` immediately below
it (`flex: 1 1 auto; min-height: 0; overflow-y: auto; padding-top: 0;`) has
**zero top padding**, specifically because that zero-padding rule was written
for a plain single-line header (documented at `gtmOverview.css` line 283: "No
top padding, so the sticky header sits flush against the card header instead
of leaving a gap rows scroll through" — written for the deals table, reused
here via the shared `.ov-row2-card` class). When the header content
overflows its `min-height: 3rem` expectation, the zero-top-padding body
starts immediately where the *old* single-line header would have ended, not
where the new two-line header actually ends — producing the visible overlap.

**This was exposed, not newly introduced, by the redesign sequence**: the
funnel-card removal (`overview-bd-heat-redesign-1-layout-toggle`, commit
`5e5308c9`) left `.ov-h-stack`/`.ov-h-note` in place ("`.ov-h-stack` survives
because the Assessment results card header (Row 3) still uses it" — comment
at `gtmOverview.css` line 386) without re-auditing whether the zero-top-
padding/`min-height: 3rem` pairing still held once this was the only header
using the two-row `.ov-h-stack` shape on the page.

**Fix direction (for the Developer step, not applied here):**
1. Give `.ov-results .ov-card-h` (or a new modifier class, e.g.
   `.ov-card-h--stacked`) `align-items: flex-start` instead of inheriting the
   shared `align-items: center`, so the icon aligns to the top of a two-line
   header instead of centering against its full height.
2. Either raise `.ov-card-h`'s `min-height` for the two-line case or drop
   `min-height` in favor of natural content height plus explicit padding —
   confirm against the mockup's header height once §0 is resolved.
3. Add a real CSS rule sizing `.ov-view-all`/`.ov-ready-to-book` to match the
   page's secondary-button scale (do not leave them at library defaults).
4. Do not blindly reapply the deals table's `padding-top: 0` rationale to
   `.ov-results-body` without re-deriving it for the two-line header case —
   re-measure whether zero top padding is still correct once the header
   height is fixed, rather than assuming the deals-table comment still
   applies verbatim.
5. This must be verified live in the browser (computed styles / actual
   rendered header height) by QA, not just by re-reading the CSS — a static
   read establishes the credible mechanism and the fix direction, not a
   pixel-confirmed root cause.

## 5. Definition of Done

- Every card on the Overview Today view (`gtmHeatGrid`, Act Today tiles —
  if in scope per mockup, `gtmTasksDueTodayWidget`,
  `gtmReadoutsAwaitingWidget`, Opportunities to follow up on, Assessment
  results) visually matches the mockup's `.card`/`.card-h`/`.card-h .ic`/
  `.card-b` chrome pattern **consistently** — same background, border, top
  rail treatment, icon-circle header, and body padding shape — old cards and
  new cards indistinguishable in chrome quality.
- The Assessment results header/table overlap bug (§4) is fixed and does not
  regress at any viewport width already handled by the page's breakpoints
  (`1100px`, `900px`, `768px`, `480px` — all already have rules touching
  `.ov-cols`/`.ov-row3`/`.at-row` that must still apply cleanly).
- The Assessment results subheader ("View all assessments · Ready to book")
  visually matches the button/typography language used elsewhere on the page
  (no more unstyled default `lightning-button` sizing).
- No change to `gtmOverview.js`, `gtmHeatGrid.js`, `gtmTasksDueTodayWidget.js`,
  or `gtmReadoutsAwaitingWidget.js` data/logic — diff review should show only
  `.html`/`.css` changes in these four components (plus test-file updates
  only if a `data-id`/selector genuinely had to move, not a rewrite of test
  intent).
- **Success Metric:** Visual QA (browser-rendered screenshot, per the "QA
  browser validation" rule already in force for this project) shows all five
  Today-view cards sharing one consistent chrome language against the
  mockup, and the header/table overlap is gone at both a full desktop width
  and the `1100px` stacked breakpoint.
- **Target Test Target:** `npm run test -- gtmOverview gtmHeatGrid
  gtmTasksDueTodayWidget gtmReadoutsAwaitingWidget` (all four components'
  existing Jest specs, particularly
  `gtmOverview/__tests__/gtmOverview.dailyWidgets.test.js` and
  `gtmOverview/__tests__/gtmOverview.row3.test.js`, which already assert
  render order/structure around the widgets touched here) — must stay green;
  plus a live browser pass against `gtm-staging` (QA step) since this is a
  purely visual defect class that Jest's jsdom rendering will not catch
  (Jest does not compute real layout/overlap).
