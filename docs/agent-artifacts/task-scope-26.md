# TASK SCOPE — ISSUE #26

## 1. Requirements Breakdown

- **Target Objective:** Rebuild `gtmHeatGrid` ("Who's hot right now" widget
  on the Home/Overview page) from its current hand-rolled `div role="table"`
  CSS-Grid layout onto `lightning-datatable`, following the same extension
  pattern the Assessments/Pages tab tables already use
  (`c/gtmLinkDatatable`, a `lightning/datatable` subclass registering a
  custom `gtmLink` cell type via `static customTypes`), so that column
  alignment, truncation, and resize come from the platform component
  instead of hand-maintained grid CSS. This is the proper follow-up to the
  immediate CSS patch in commit `e3816aa` (`min-width: 0` /
  `overflow: hidden` on `.heat-grid__col`), which only fixed the live
  truncation/column-shift bug without addressing its root cause (a
  hand-rolled table with none of `lightning-datatable`'s built-in behavior).
  Secondary objective: audit (not assume) whether the "Opportunities to
  follow up on" `.deals` grid in `gtmOverview.html` — the sibling hand-rolled
  grid `e3816aa`'s commit message explicitly named as the same pattern —
  should move to `lightning-datatable` too, or is different enough
  (grouped/multi-line rows) to justify staying custom. My reading of the
  actual markup/CSS (evidence below) is that `.deals` should very likely
  stay custom, but this is a recommendation for the Architect to confirm,
  not a settled fact — the issue text itself says "don't assume either way,
  check."

  **Flag — unresolved architecture-doc conflict, needs an explicit human/
  Architect decision, not a silent BA override:** The heat grid's own
  accepted architecture doc,
  `docs/architecture/overview-bd-heat-redesign-2-heat-grid.md` (lines
  149–166), documents a *considered-and-rejected* decision to NOT use
  `gtmLinkDatatable`/`lightning-datatable` for this component:

  > "Account and Contact columns use `<c-gtm-link-cell>` directly ... NOT a
  > `<c-gtm-link-datatable>` `lightning-datatable` subclass, because the
  > day-strip and action-button cells have no equivalent `lightning-datatable`
  > base type and inventing custom `customTypes` entries for them would
  > still need bespoke templates ... satisfying 'no reintroduction of the
  > `type:'button'`-with-data-driven-`disabled` pattern' while still
  > allowing the non-tabular parts of the row (heat strip, action button) to
  > render as plain markup."

  Issue #26 asks to reverse exactly this decision. That may well be the
  right call now (the issue's own reasoning — Salesforce-first, alignment/
  truncation "for free" — is sound, and this BA pass finds that custom
  `customTypes` entries for both the day-strip and action-button ARE
  buildable, see §3 below), but the existing doc is marked "Status:
  Accepted" and was a deliberate, reasoned choice at the time (from PR
  #260's heat-grid slice), not an oversight. The Architect step must
  explicitly supersede/update
  `docs/architecture/overview-bd-heat-redesign-2-heat-grid.md` with the new
  decision and rationale, not just land new code while the accepted doc
  still says the opposite.

- **System Component Impacted:** LWC only.
  - `force-app/main/default/lwc/gtmHeatGrid/gtmHeatGrid.html` (rebuilt to
    mount a `lightning-datatable` subclass instead of the CSS-Grid divs),
    `.js` (column definitions replace/augment row-shaping logic),
    `gtmHeatGridModel.js` (pure helpers — `intensityClass`, `dayTitle`,
    `buildRows` — are largely reusable/adaptable, see §3), `.css` (most of
    it — `.heat-grid`, `.heat-grid__header`, `.heat-grid__row`,
    `.heat-grid__col*` grid-template rules — is deleted since
    `lightning-datatable` owns its own layout/scroll wrapper; `.heat-cell*`
    shade classes and `.heat-strip` survive inside the new custom cell
    type's own CSS).
  - New: a `lightning-datatable` subclass (parallel to `gtmLinkDatatable`,
    e.g. `gtmHeatGridDatatable`) registering two NEW custom cell types (heat
    strip, next-best-action) via `static customTypes`, each with its own
    template component (parallel to `gtmLinkCellTemplate.html` /
    `gtmLinkCell`). The existing `gtmLink` type from `gtmLinkDatatable` is
    reused as-is for Account/Contact (confirmed identical `typeAttributes`
    contract needed: `label`, `name`, `disabled`, `title`, `targetId`,
    `idField` — see §3).
  - Possibly `force-app/main/default/lwc/gtmOverview/gtmOverview.html`/
    `.css`/`.js` (the `.deals` grid) IF the Architect's audit decision
    (informed by §3's evidence below) is to migrate it too — not assumed
    in scope by default given the evidence found.
  - **No Apex, no Custom Metadata, no new fields/objects, no permission
    sets.** Verified by reading `GtmHeatGridActionsController.cls` in full:
    its one `@AuraEnabled` method, `createFollowUpTask(opportunityId,
    accountName)`, returns an `Id` and has no dependency on how the caller
    renders rows; `GtmLinkStageService.getHeatGridAura()`'s
    `HeatGridResult`/`HeatRow`/`HeatDay` Apex contract
    (`docs/architecture/overview-bd-heat-redesign-2-heat-grid.md` lines
    34–63) is unchanged by a client-side rendering swap. This is a pure LWC
    refactor.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO.** Nothing in `gtmHeatGrid` touches
      `GtmAgentToolSurface`/`GtmAppTool`/any GUS surface class; confirmed by
      reading `gtmHeatGrid.js` (imports only `GtmLinkStageService
      .getHeatGridAura` and `GtmHeatGridActionsController
      .createFollowUpTask`, both pre-existing, both untouched by this
      issue) and `GtmHeatGridActionsController.cls` (no GUS involvement).
- [ ] Altering Custom Metadata? **NO.** No `instrument/<offering-key>/`
      YAML or `GTM_Assessment_*` CMDT is in scope; this is a Home-page
      widget, not the assessment instrument.
- [ ] Introducing database fields? **NO.** No new Apex, objects, or fields
      — the Apex contract (`HeatGridResult`/`HeatRow`/`HeatDay`) is
      untouched (see §1). No permission-set mapping is needed as a result.

## 3. Plan Acceptance Criteria

- **Success Metric:** `gtmHeatGrid` renders through a `lightning-datatable`
  subclass with column alignment/truncation/resize inherited from the
  platform (no more hand-maintained `grid-template-columns`/`min-width: 0`
  CSS to keep header and row cells in sync), and the two hard cases below
  are resolved with evidence, not assumption, before the Developer starts:

  1. **Column mapping** (verify each against actual current behavior read
     in `gtmHeatGrid.html`/`.js`/`gtmHeatGridModel.js`):

     | Current column | New `lightning-datatable` column type |
     |---|---|
     | Account | Reuse `gtmLink` type as-is from `gtmLinkDatatable`'s `static customTypes` (identical `typeAttributes` shape already produced by `buildRows()`'s `accountCellAttrs`: `label`, `name: 'openAccount'`, `disabled`, `title`, `targetId: accountId`, `idField: 'accountId'`) |
     | Contact | Same, `contactCellAttrs` / `name: 'openContact'` |
     | Stage | Base `text` type (verify default single-line-truncate-with-ellipsis behavior live — see citation gap below; today's `.gtm-link-cell_static.slds-truncate` markup already gets its truncation from the platform's own `.slds-truncate` utility per `gtmHeatGrid.css`'s own comment, so this is likely a same-behavior, less-code swap) |
     | Latest signal | Base `text` type, same reasoning as Stage |
     | Last 14 days (heat strip) | **New custom cell type required.** No base `lightning-datatable` type renders repeated child markup (14 shaded day cells per row) — confirmed by checking the base type list this repo already relies on elsewhere (`text`, `boolean`, `currency`, `date`, `email`, `location`, `number`, `percent`, `phone`, `url`, `button`, `button-icon`, `action`; see citation gap below for live verification). The pure helpers `intensityClass()`/`dayTitle()` in `gtmHeatGridModel.js` are cell-agnostic already and are directly reusable inside the new cell type's own component, unchanged. |
     | Next best action | **Hard case — new custom cell type required, not the base `button` type.** See finding below. |

  2. **Next-best-action column — re-verified finding on "does
     `lightning-datatable`'s built-in button type support a disabled
     button with a keyboard/hover-reachable tooltip natively":** The
     current markup (`gtmHeatGrid.html` lines 50–73) wraps the
     `lightning-button` in a non-disabled `<span class="heat-grid__action-tip"
     title={row.actionTitle} tabindex={row.actionTooltipTabIndex}>`
     specifically because — per the inline comment already in that file —
     "a disabled HTML element never fires hover/focus events, so a `title`
     on a disabled `lightning-button`'s inner `<button>` is inert." This
     repo's own precedent (`gtmLinkDatatable.js`'s comment, lines 9–13)
     already states as fact that "`<lightning-datatable>` itself has no
     supported way to accept a custom cell type without subclassing" — the
     same platform constraint applies one level deeper here: the base
     `button` column type's documented `typeAttributes` are `label`,
     `name`, `title`, `disabled`, `value`, `variant`, `iconName`,
     `iconPosition` (per this repo's own citation convention in
     `docs/architecture/gtm-assessments-table.md` line 186, "Current
     Lightning Component Reference") — there is no attribute to substitute
     a non-disabled wrapper element or inject a `tabindex`, and disabling
     the rendered `<button>` is exactly the same native-HTML
     keyboard-unreachability problem this component already had to work
     around. **Conclusion: the base `button` type cannot reproduce today's
     reachable-tooltip-on-disabled behavior; a custom cell type is still
     needed**, reusing the exact tooltip-wrapper-span + conditional
     `tabindex` pattern from today's markup, inside a new template
     component parallel to `gtmLinkCellTemplate.html`/`gtmLinkCell`.
     — **Citation gap, flagged rather than guessed:** this BA pass has no
     live web-fetch/browser tool available in this environment, so the
     `button` type's `typeAttributes` list above and the base-type roster
     are stated from trained knowledge of the Lightning Web Components
     Developer Guide / Base Components Reference for `lightning-datatable`
     ("Custom Data Types" page and the `lightning-datatable` component
     reference), not a doc fetched during this session. Per the
     instruction to "cite official docs, don't guess platform
     capabilities," the Architect or Developer must confirm this list
     against the live current Salesforce docs before finalizing the
     custom-type decision — the repo's own convention for doing this is
     visible in `docs/architecture/gtm-assessments-table.md` line 186
     ("Current Lightning Component Reference: `lightning-datatable`
     ... column types `url`, `button`, `date`, `number`; ..."), i.e. name
     the exact doc section cited, inline, in the updated architecture doc.

  3. **Busy state — a real gap, not an assumption:** `gtmHeatGrid.js`
     tracks `@track busyRowId` (set to `row.accountId` before the "Follow
     up" Apex call, cleared in `.finally()`, and used as a re-entrancy
     guard: `if (!row || !row.opportunityId || this.busyRowId) return;`),
     but **`busyRowId` is never read anywhere in `gtmHeatGrid.html`** —
     grepped and confirmed zero template bindings. Today's "busy state" is
     a silent re-entrancy lock only; there is no visible spinner, disabled
     styling, or label change on the button while the Follow-up Apex call
     is in flight, and no existing Jest test (`gtmHeatGrid.test.js`) asserts
     any visual busy behavior either. The issue's phrasing ("per-row
     `lightning-button` with busy state") describes an intent the current
     code only half-implements. The Architect must decide explicitly
     whether the rebuild (a) preserves this as an invisible guard only, or
     (b) adds a real visible busy indicator (e.g. the button's own `label`
     swapping to "Saving…" plus `disabled` while busy, which a custom cell
     type can support since it owns its own template) — this is a product/
     UX decision, not a default this BA pass is making.

  4. **`.deals` grid audit finding:** Read `gtmOverview.html` lines 143–202
     and `gtmOverview.css` (`.deal`/`.deals`/`.deal-group-head`/
     `.deal-contact-head` rules, lines 304–403). The `.deals` "table" is
     not one-row-per-record: it interleaves three structurally different
     `role="row"` kinds per the `for:each={dealRows}` loop —
     `row.isAccount` (a grouping header row, one per Account),
     `row.isContact` (a grouping sub-header row, one per Contact within an
     Account), and `row.isDeal` (the actual data row) — and each `isDeal`
     row's cells are themselves multi-line stacks: column 1
     (`.deal-id`) stacks offering label / config name / engagement badge
     (3 lines), column 2 (`.deal-opp`) stacks opportunity link / CRM-stage
     pill / optional close date (up to 3 lines), column 3
     (`.deal-assessment`) stacks the request link / submitted-date caption
     (2 lines). `lightning-datatable` models exactly one row per record and
     one line per cell with no native row-grouping/section-header concept;
     reproducing this structure would require either (a) flattening the
     grouped rows into a single sortable table (a real UX/product change
     beyond a like-for-like rebuild, out of this issue's stated scope), or
     (b) three-to-four new bespoke custom cell types just to stack multiple
     lines inside one cell, which forfeits most of the "alignment/
     truncation/resize come free" benefit the issue is chasing in the first
     place. **My reading: `.deals` is the "different enough to justify
     staying custom" case the issue anticipates** — but per the issue's own
     instruction not to assume, this is a recommendation for the Architect
     to ratify (or override with a stated reason), not a decision this BA
     pass is finalizing. `gtmHeatGrid`, by contrast, genuinely is one row
     per Account with one line per cell (matching the Assessments/Pages
     table shape) except for the two hard cases in item 1, both of which
     are solvable with a single custom cell type each — that structural
     difference is exactly why the two grids may reasonably land on
     opposite outcomes despite `e3816aa`'s commit message naming both as
     "the same pattern" (that message was written by the immediate-patch
     author identifying the CSS symptom, not auditing the row-shape
     difference this BA pass found).

  5. **Testing implications — re-verified against the actual jest stub,
     not assumed:** `node_modules/@salesforce/sfdx-lwc-jest/src/
     lightning-stubs/datatable/datatable.js` shows the `lightning/
     datatable` Jest stub is a bare `LightningElement` exposing only its
     `@api` properties (`columns`, `data`, `keyField`, `sortedBy`, etc.) —
     it renders NO row or cell DOM at all in the test environment. This is
     confirmed by how the existing `c-gtm-link-datatable` consumer
     (`gtmRepLinkFinder.table.test.js`) is actually tested: every assertion
     reads `table(el).columns` / `table(el).data` directly (e.g.
     `expect(table(el).columns[0].typeAttributes.name).toBe('open')`) or
     dispatches synthetic `sort`/`rowaction` `CustomEvent`s at the stub
     element (`table(el).dispatchEvent(new CustomEvent('rowaction', ...))`)
     — it never queries rendered `<tr>`/`<td>` markup, because the stub
     doesn't produce any. This means **most of `gtmHeatGrid.test.js`'s nine
     current tests cannot survive the rebuild unchanged** — specifically
     the ones that query `.heat-grid__row` elements, count `lightning-button`
     elements by array index (`buttons[0]`, `buttons[1]`, `buttons[2]`),
     read `.tabIndex`/`.title` off the `.heat-grid__action-tip` wrapper
     span, or query `.heat-grid__col--stage .gtm-link-cell` — none of that
     DOM will exist once rows/cells render through `lightning-datatable`.
     The rebuild's test plan must split into three tiers: (a)
     `gtmHeatGridModel.test.js`'s existing pure-function tests
     (`intensityClass`, `dayTitle`, `buildRows`, `encodeDefaultFieldValues`)
     — mostly reusable as-is or with light adaptation once `buildRows()`'s
     output shape changes from per-row markup fields to
     column-`typeAttributes`-ready fields; (b) new host-level
     `gtmHeatGrid.test.js` assertions against the new datatable subclass's
     `columns`/`data` properties and dispatched `sort`/`rowaction` events,
     mirroring `gtmRepLinkFinder.table.test.js`'s pattern exactly; (c) new,
     STANDALONE Jest specs for each new custom cell-type component (heat
     strip, next-best-action), mounted directly the way
     `gtmLinkCell/__tests__/gtmLinkCell.test.js` tests `gtmLinkCell` in
     isolation — this is the only tier that can actually assert the real
     rendered tooltip-reachable-on-disabled / busy-indicator DOM behavior,
     since the datatable stub cannot.

- **Target Test Target:**
  - `force-app/main/default/lwc/gtmHeatGrid/__tests__/gtmHeatGrid.test.js`
    (existing 9-test suite — expect a substantial rewrite per finding 5
    above, not a drop-in pass)
  - `force-app/main/default/lwc/gtmHeatGrid/__tests__/gtmHeatGridModel.test.js`
    (existing pure-function suite — adapt to the new `buildRows()`/column
    shape)
  - New Jest specs for each new custom cell-type component this issue
    introduces (heat-strip cell, next-best-action cell), parallel to
    `force-app/main/default/lwc/gtmLinkCell/__tests__/gtmLinkCell.test.js`
  - If (and only if) the Architect's `.deals` audit decision is to migrate
    it: `force-app/main/default/lwc/gtmOverview/__tests__/gtmOverview.test.js`
    (the `.deal*` assertions at lines 695–832) as a follow-up test target —
    NOT bundled into this issue's default scope given the finding in item 4
    above.
  - Run via `npm test` (repo's `package.json` `"test": "sfdx-lwc-jest"`
    script), scoped to the `gtmHeatGrid`/new cell-type directories during
    development.
