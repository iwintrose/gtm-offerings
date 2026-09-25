# TASK SCOPE — ISSUE #14

## 1. Requirements Breakdown

- **Target Objective:** Extract a shared `c-gtm-card` LWC and migrate all four current consumers of the hand-duplicated `.ov-card` CSS family onto it (`gtmOverview`, `gtmHeatGrid`, `gtmTasksDueTodayWidget`, `gtmReadoutsAwaitingWidget`), eliminating the "keep these rules identical across four files" comment-discipline pattern and enforcing uniform text-overflow/truncation on all card text as part of the migration.

  Verified duplication (evidence):
  ```
  $ grep -rl "ov-card" force-app
  force-app/main/default/lwc/gtmHeatGrid/gtmHeatGrid.css
  force-app/main/default/lwc/gtmHeatGrid/gtmHeatGrid.html
  force-app/main/default/lwc/gtmOverview/gtmOverview.css
  force-app/main/default/lwc/gtmOverview/gtmOverview.html
  force-app/main/default/lwc/gtmReadoutsAwaitingWidget/gtmReadoutsAwaitingWidget.css
  force-app/main/default/lwc/gtmReadoutsAwaitingWidget/gtmReadoutsAwaitingWidget.html
  force-app/main/default/lwc/gtmTasksDueTodayWidget/gtmTasksDueTodayWidget.css
  force-app/main/default/lwc/gtmTasksDueTodayWidget/gtmTasksDueTodayWidget.html
  ```
  Each of the three widget CSS files (`gtmHeatGrid`, `gtmReadoutsAwaitingWidget`, `gtmTasksDueTodayWidget`) carries the identical hand-copied `.ov-card` / `.ov-card-h` / `.ov-card-b` block (border, border-radius, background, box-shadow, hover lift, reduced-motion override, header flex layout, body padding) with a literal warning comment:
  ```
  gtmReadoutsAwaitingWidget.css:6-10:
     what it's named. The shared class NAMES stay (readability/consistency
     across the four files) but the rules this component's markup actually
     uses have to be duplicated here. Keep in sync with gtmOverview.css's
     .ov-card/.ov-card-h/.ov-card-b/.ov-ic/.ov-ic--readouts/.ov-readouts/
     .ov-h/.ov-empty block if that ever changes.
  ```
  `gtmTasksDueTodayWidget.css:6-10` carries the same comment verbatim (only the modifier class list differs: `.ov-ic--tasks`/`.ov-tasks-today`). `gtmHeatGrid.css:40-43` carries the equivalent warning ("Keep in sync with gtmOverview.css's .ov-card/.ov-card-h/.ov-card-b/.ov-ic/.ov-ic--heat/.ov-heat block if that ever changes."). This is a real drift risk, confirmed by the codebase's own history: `gtmOverview.css:150` references "Issue 274: this used to duplicate gtmLinkCell.css's overflow/ellipsis... rule" — i.e. a prior truncation fix already had to be hand-propagated this way once, exactly the failure mode this issue exists to close off.

  Truncation gap (verified): only `gtmHeatGrid.css` (`text-overflow: ellipsis; white-space: nowrap;` at lines 21-22, tied to the `.gtm-link-cell` values-only reference from `gtmLinkCell.css`) and `gtmOverview.css` (lines 171-172, same rule, same issue-274 provenance) currently have any truncation rule at all. `gtmReadoutsAwaitingWidget.css` and `gtmTasksDueTodayWidget.css` have **no** `text-overflow`/`white-space`/`ellipsis` rules anywhere in their stylesheets — card body text in those two widgets can currently overflow/wrap unbounded. This confirms the issue's mandate to "enforc[e] uniform text-overflow/truncation rules across all card text as part of the migration" is not cosmetic — two of the four consumers are missing it outright today.

  **Not in scope for #14 (explicitly separate issue, do not merge):** `offeringChooser.css` / `chooseIndustry.css` `.tile` family. Verified via `gh issue view 15`: issue #15 covers that system and is described in #14's own body as "kept separate... see #9's closing comment" because that surface is the public, password-protected, client-branded front door, versus #14's internal admin/rep-facing surfaces (`gtmOverview` and its three dashboard widgets). No file overlap was found between the `.ov-card` grep results above and `.tile`-family files — `grep -rl "ov-card"` returns none of `offeringChooser.*` or `chooseIndustry.*`. The two issues can proceed independently; if the Architect step for #14 decides `c-gtm-card` should expose a generically reusable shell, note in the contract only — do not preemptively build #15's tile convergence here.

  **Prior extraction did not touch this surface (verified, do not assume otherwise):** issue #8 (header-bar-consistency) was closed this session as already-resolved via the `c-gtm-page-header` LWC (commit `861f020`, issue-B14a). That component only covers header bars — icon circle + eyebrow/title/meta + actions/slot (`force-app/main/default/lwc/gtmPageHeader/gtmPageHeader.js` docblock: "Shared page header bar: icon circle, eyebrow label, bold title, meta subtitle line, a declarative `actions` array..."). Grepping `gtmPageHeader` usage and the `.ov-card` file list above shows zero overlap: `gtmPageHeader` is a distinct component consumed elsewhere (verify at Architect/Developer time whether any of the four #14 consumers already use it for their header sub-region — a quick scan of the four `.html` files shows they still hand-roll their own `slds-card__header ov-card-h` markup, not `<c-gtm-page-header>`). The `.ov-card` family (outer card chrome: border/shadow/hover-lift/rail-color, plus `.ov-card-h`/`.ov-card-b` header/body regions) is a fully separate, still-open duplication problem, not a side effect already fixed by the header extraction.

- **System Component Impacted:** LWC (new shared component `c-gtm-card` under `force-app/main/default/lwc/gtmCard/`, plus edits to the four consumer LWCs' `.html`/`.css`: `gtmOverview`, `gtmHeatGrid`, `gtmTasksDueTodayWidget`, `gtmReadoutsAwaitingWidget`). No Apex, no Custom Metadata, no Experience Cloud route changes — all four consumers are internal admin/rep-facing (GTM_Offerings app), confirmed by the issue body ("Internal admin/rep-facing surfaces only") and by their being distinct from the Experience Cloud `.tile` surfaces covered by #15.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No — this is presentational card-chrome LWC/CSS work with no Apex or DML involved.
- [ ] Altering Custom Metadata? No — no YAML/metadata changes required.
- [ ] Introducing database fields? No — no new objects/fields; this is a pure UI refactor of existing rendered data.

## 3. Plan Acceptance Criteria

- **Success Metric:** All four current `.ov-card` consumers (`gtmOverview`, `gtmHeatGrid`, `gtmTasksDueTodayWidget`, `gtmReadoutsAwaitingWidget`) render through the new `c-gtm-card` component with visually identical chrome to today (border/radius/background/box-shadow/hover-lift/reduced-motion behavior, per-widget rail color and icon-circle modifier preserved via props/slots) AND every card's text region (title, meta/description lines) applies a consistent `text-overflow: ellipsis; white-space: nowrap; overflow: hidden;` (or equivalent multi-line clamp, Architect's call) truncation rule — including `gtmReadoutsAwaitingWidget` and `gtmTasksDueTodayWidget`, which have none today. The four component-specific `.ov-card`/`.ov-card-h`/`.ov-card-b` rule blocks and their "KEEP THESE IN SYNC" comments are deleted from the three widget CSS files and from `gtmOverview.css` once superseded by the shared component (the `gtmOverview.css` `.ocard` sibling-selector rules for the offerings grid at lines 294-330 should be reviewed by the Architect — they share the same rail/hover treatment and may also fold into the new component's prop-driven API, but confirm before assuming so since `.ocard` is a second, adjacent class family, not `.ov-card` itself). No regression in `gtmHeatGrid`'s existing `.gtm-link-cell`-synced ellipsis rule (lines 21-22) or in `gtmOverview`'s issue-274 truncation fix (lines 171-172) — both should end up expressed through the same shared truncation utility, not duplicated a third way.

  **Salesforce-first check (per repo convention):** Base `lightning-card` was evaluated and does not natively support this design's icon-circle header slot, per-card colored top rail (`border-top: 3px solid <color>`), or the box-shadow hover-lift/translateY affordance — these are custom SLDS-adjacent treatments layered on top of `slds-card` today (`class="slds-card ov-card ..."`), not `lightning-card`'s own rendering. `lightning-card` is already used elsewhere in the codebase for simpler admin-tool cases (`gtmRepDirectShare`, several `conduit*` components) that don't need this decoration, confirming it's a viable base for plain cases but not a drop-in replacement here. Building a custom `c-gtm-card` LWC (mirroring the precedent already set by `c-gtm-page-header`, which took the same approach for header bars) is justified; the Architect should still confirm at design time rather than treat this as final, and should keep `slds-card`/SLDS utility classes as the styling substrate inside `c-gtm-card` rather than reinventing box-shadow/spacing values from scratch.

  **Proposed prop/slot contract (starting point for Architect, not final):**
  - `@api railColor` (or a small named-variant enum matching existing modifiers: `deals`/`results`/`offerings`/`heat`/`readouts`/`tasks`) — drives the top rail border-color, replacing today's per-consumer `.ov-deals`/`.ov-results`/etc. classes.
  - `@api iconName`, `@api iconVariant` — drives the `.ov-ic`/`.ov-ic--*` icon-circle, consistent with `gtmPageHeader`'s existing `iconName` prop naming.
  - `@api title` (or a `header` slot for the two-line stacked-header case `gtmOverview.css` already special-cases at `.ov-results .ov-card-h`, lines 528-542 — a named slot avoids re-inventing that layout-variant logic inside the shared component).
  - Default slot for card body content, so each of the four consumers keeps full control of body markup/behavior (e.g. `gtmHeatGrid`'s table, `gtmTasksDueTodayWidget`'s list) while the shell (border/shadow/hover/header chrome) is owned by `c-gtm-card`.
  - A `truncate` or `line-clamp` CSS utility (either a shared class exported alongside the component or documented convention) that consumer markup applies to title/meta text nodes, so the truncation rule is centrally defined once instead of copy-pasted per consumer as today.
  - This contract must be written up in `docs/architecture/` per AGENTS.md/CLAUDE.md §4 ("Contract First") before implementation — this scope doc is not itself that contract.

- **Target Test Target:** Jest specs for the new `gtmCard` component (`force-app/main/default/lwc/gtmCard/__tests__/gtmCard.test.js`, to be created) covering prop-driven rail color/icon/slot rendering and truncation class application, plus updated/passing existing specs for the four migrated consumers if Jest specs exist for them today (confirm at Architect/Developer time — `gtmPageHeader` has `__tests__/gtmPageHeader.test.js` as the precedent pattern to follow) via `npm test`.
