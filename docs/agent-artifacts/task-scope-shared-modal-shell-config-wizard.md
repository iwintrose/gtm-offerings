# TASK SCOPE — ISSUE #shared-modal-shell-config-wizard

## 0. Relationship To Issue #shared-modal-shell

This is the deferred follow-up to `#shared-modal-shell` (merged, PR #211,
`origin/main` commit `7f78965`). That issue built the shared `gtmModalShell`
LWC (`force-app/main/default/lwc/gtmModalShell/`: props `is-open`, `title`,
`chrome-offset` [opt-in, default `false`]; slots default + `header-extras`;
a single `close` event only, no domain events) and migrated the simpler
consumer, `gtmRepDirectPicker`, onto it. It explicitly deferred
`gtmConfigWizard` because that component has real chrome-offset positioning
logic the picker never needed. This issue does that harder migration.

Verified by reading `gtmModalShell.js`/`.html` on `origin/main` directly:
the `_measureChromeOffset()` logic (host `getBoundingClientRect().top +
window.scrollY`, deferred one tick via `setTimeout(...,0)` in
`connectedCallback()`, `_topOffset` fallback of `106`) is **already fully
implemented inside `gtmModalShell`**, gated behind `chromeOffset`. It was
written pre-emptively for this exact follow-up (see
`docs/architecture/gtm-modal-shell.md`'s "Out of scope" / `chrome-offset`
row, which names `gtmConfigWizard` explicitly). This issue's job is
therefore to **wire `gtmConfigWizard` to consume the shell's existing
`chrome-offset` prop**, not to write new offset math.

## 1. Requirements Breakdown

- **Target Objective:** Replace `gtmConfigWizard`'s own internal
  scrim/sheet/header-close overlay chrome (markup in
  `gtmConfigWizard.html`, CSS `.mw-scrim`/`.mw-sheet`/etc. in
  `gtmConfigWizard.css`, and the `_measureChromeOffset()` +
  `connectedCallback()` `setTimeout` + `sheetStyle`/`scrimStyle`/
  `panelClass`/`sheetClass` getters in `gtmConfigWizard.js`, roughly lines
  319–423) with `<c-gtm-modal-shell is-open=... title=... chrome-offset>`,
  wrapping the wizard's existing step content (path chooser, 8-step full
  walkthrough, 2-step quick link, step-dot rail, done screen) unchanged.
  `chrome-offset` is passed **only** when `standalone` is true — the exact
  same condition `_measureChromeOffset()` already guards today (`if
  (!this.standalone) return;`), not a new one.
- **System Component Impacted:** LWC. Touches only
  `force-app/main/default/lwc/gtmConfigWizard/gtmConfigWizard.js`,
  `.html`, and `.css`. No other file changes required or in scope (see §5
  on mount order).

### Why this is the harder consumer (do not underestimate)

- `isOpen` is a public **getter/setter**, not a plain field — opening the
  wizard triggers one-time seeding of company/industry/state/notifyEmail/
  accent from parent-loaded record data (`gtmConfigWizard.js` lines
  ~55–92). Whatever prop/attribute binding replaces the wizard's own
  `isOpen` handling for the *shell's* `is-open` must not interfere with
  this seeding — `gtmConfigWizard` keeps owning its own `@api isOpen`
  getter/setter exactly as today; only the shell's `is-open` attribute
  (bound to `this.isOpen`, the wizard's own resolved value) changes.
- Multi-step UI: 8-step "full" walkthrough, 2-step "quick" path, a
  clickable step-dot progress rail (`stepDots` getter, `handleStepJump`),
  and a header label that changes per step (`headerLabel` getter,
  `Step N of 8` / `Quick link` / `New prospect page`). The step-dot rail
  and any per-step chrome (e.g. a progress bar) that currently lives in
  the wizard's own header markup should go into the shell's
  `header-extras` slot, matching the shell's documented intent
  ("reserved for a future gtmConfigWizard migration's step-dot rail" per
  `docs/architecture/gtm-modal-shell.md`). `title` should resolve to the
  wizard's existing `headerLabel` getter.
- Two embedding contexts with different chrome-offset needs: `standalone`
  mode (`gtmOverview`, launched from a Lightning tab — needs chrome
  offset) and embedded mode (`gtmConfigurator`, the live Experience Cloud
  prospect page — no offset, full-height panel). Both must keep working
  identically post-migration.
- `gtm-dev` is production for prospect-facing traffic (no staging
  environment, per `CLAUDE.md`) — `gtmConfigWizard` embedded in
  `gtmConfigurator` is the live prospect-engagement-link creation flow
  reps use today. This migration must not regress link creation, autosave,
  or the open-duplicate-Opportunity prompt while changing only the
  chrome around it.
- The existing `gtmConfigWizard.test.js` Jest suite (1205+ lines) must
  keep passing, with any assertions that reached into
  `.mw-scrim`/`.mw-sheet` class names or the old
  `_measureChromeOffset`/`sheetStyle`/`scrimStyle` internals updated
  deliberately, and called out explicitly in the PR description — not
  silently adjusted to make a red suite green.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No — no Apex/DML touched. (N/A)
- [ ] Altering Custom Metadata? No. (N/A)
- [ ] Introducing database fields? No. (N/A)

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. `gtmConfigWizard` renders its overlay chrome via
     `<c-gtm-modal-shell is-open title chrome-offset>`, not its own
     `.mw-scrim`/`.mw-sheet` markup/CSS. The `chrome-offset` attribute is
     bound so it is present exactly when `this.standalone` is true, and
     absent otherwise — matching today's `_measureChromeOffset()` guard
     exactly.
  2. `_measureChromeOffset()`, its `connectedCallback()` `setTimeout`
     call, `_standaloneTopOffset`, `sheetStyle`, and `scrimStyle` are
     removed from `gtmConfigWizard.js` — that measurement now lives
     entirely in `gtmModalShell` (already true as of `#shared-modal-shell`,
     verified above; this issue only needs to stop duplicating it in the
     wizard, not reimplement it).
  3. The `isOpen` getter/setter's seeding behavior (company/industry/
     state/notifyEmail/accent-on-open) is byte-for-byte unchanged and
     still runs off the wizard's own `@api isOpen` setter, independent of
     the shell's `is-open` attribute plumbing — verified by the existing
     Jest suite's coverage of that behavior continuing to pass.
  4. The step-dot progress rail, quick-vs-full path chooser, autosave,
     open-duplicate-Opportunity prompt, and all other domain logic and
     events (`close`, `done`, `configsaved`) in `gtmConfigWizard.js` are
     untouched apart from what's structurally required to slot the
     existing step content into the shell's default slot and any
     header chrome into `header-extras`.
  5. `gtmConfigWizard.test.js` continues passing, with any necessarily
     changed assertions (e.g. reaching into old `.mw-scrim`/`.mw-sheet`
     class names, or `_measureChromeOffset`/`sheetStyle`/`scrimStyle`
     internals) updated deliberately and called out in the PR
     description.
  6. Zero visual/structural/behavioral change for all 5 known consumers
     of `gtmConfigWizard`: `gtmOverview` (standalone, this repo's
     Lightning tab) plus the mount-order comment's stated 2 other
     Lightning tabs and 2 Experience Cloud sites (not present in this
     repo as separate LWC files — reached via `gtmConfigurator`, which is
     embedded across those Experience Cloud sites). This is a pure
     internal refactor of the wizard's own chrome; every consumer keeps
     passing the exact same props/handlers it does today.
  7. QA must verify live in `gtm-dev`, per this repo's standing QA
     browser-validation rule, on at least: `gtmOverview` (internal,
     standalone/chrome-offset path) and one Experience Cloud site
     consumer of `gtmConfigurator` (guest-facing, embedded/no-offset
     path) — including a check at a scrolled position, not just at page
     top, since this is exactly the kind of change that silently breaks
     only at a specific scroll offset per the `KEEP THIS FIRST` mount-order
     comments in `gtmOverview.html` and `gtmConfigurator.html`.

- **Target Test Target:**
  `force-app/main/default/lwc/gtmConfigWizard/__tests__/gtmConfigWizard.test.js`
  (must remain green; diff on any changed assertions explained in the PR),
  plus a manual/QA live-browser pass on `gtmOverview` (Lightning,
  standalone) and one Experience Cloud site rendering `gtmConfigurator`
  (guest-facing, embedded), at both an unscrolled and a scrolled page
  position.

## 4. Out of Scope — Do Not Touch

- **Mount order / placement is explicitly out of scope for this issue.**
  Do **not** change where `<c-gtm-config-wizard>` sits in any of its 5
  consumer templates, and do **not** remove or edit the `KEEP THIS FIRST`
  comments in `force-app/main/default/lwc/gtmOverview/gtmOverview.html`
  (lines ~12–21) or `force-app/main/default/lwc/gtmConfigurator/gtmConfigurator.html`
  (lines ~3–17). The wizard's offset math only resolves correctly today
  because it is mounted as the literal first child of its container on
  all 5 known consumers; whether the shell's own `chrome-offset`
  measurement still carries that same constraint is a separate concern
  from this issue's chrome-swap. If, during implementation, it turns out
  the shell removes or changes that constraint, flag it explicitly in the
  PR description as an observation for a future issue — do not act on it
  by editing mount order or deleting the warning comments here.
- No changes to `gtmModalShell` itself unless its existing contract is
  genuinely insufficient (e.g. `header-extras` cannot actually hold the
  step-dot rail). If that happens, stop and flag it rather than
  quietly forking the shell or working around its contract locally — that
  is a signal for the Architect step to revisit, not something to patch
  around inside `gtmConfigWizard`.
- No Apex, custom metadata, or permission-set changes.

## 5. Architect Addendum (post-QA-fail, header-extras layout fix)

QA correctly stopped rather than let the Developer patch this from inside
`gtmConfigWizard.css` alone (see `TEST_FAILURES.log` in this worktree for
the full QA report). Root cause confirmed by reading both files directly:

- `gtmModalShell.css` `.gms-head` is `display:flex; align-items:center;
  justify-content:space-between;` with **no `flex-wrap`**, and the two
  wizard elements now slotted into `header-extras`
  (`.mw-progress`, `.mw-dotrow`) have no width/flex-basis of their own —
  they render as unconstrained flex siblings of the title span and close
  button inside a 420px-wide `.gms-sheet`, which collapses or overflows
  them.
- A plain `flex-wrap: wrap` + `flex-basis: 100%` fallback on the slotted
  elements is **not sufficient and was rejected**: the DOM order inside
  `.gms-head` is title → `<slot name="header-extras">` → close button
  (`gtmModalShell.html` line 4-7). A `flex-basis:100%` item forces a wrap
  at its own position in flex order, which would push the close button
  down onto a third line below the wrapped extras content instead of
  keeping it next to the title — a different, still-broken layout.

**Authorized fix (this issue, this worktree only):** restructure
`gtmModalShell.html`/`.css` so `header-extras` is a **dedicated full-width
row**, not a flex sibling competing with title/close:

- `gtmModalShell.html`: split the current single `.gms-head` div into two
  rows inside one wrapping container (e.g. `.gms-head-wrap`):
  1. existing title + close button row (keep flex/space-between, drop
     the `<slot name="header-extras">` from it)
  2. a new row directly below it, e.g. `<div class="gms-extras"><slot
     name="header-extras"></slot></div>`, full width, no flex.
- `gtmModalShell.css`: move the `border-bottom` currently on `.gms-head`
  onto the new wrapping container so the divider still sits below
  whichever row is visually last; give `.gms-extras` horizontal padding
  matching `.gms-head` (`0 1rem`) and no vertical padding/min-height, so
  that when the slot has no assigned content (this is exactly
  `gtmRepDirectPicker`'s case today — confirmed by reading
  `gtmRepDirectPicker.html`: it does not use `header-extras` at all) the
  row collapses to zero height and is visually identical to today. This
  is the reason `gtmRepDirectPicker` is low-risk here: it never populates
  that slot, so an empty `.gms-extras` row with no vertical
  padding/border of its own renders as nothing.
- Verify by inspection (and Jest DOM query if the existing suite already
  queries `.gms-head`/`.gms-x`) that `gtmRepDirectPicker`'s rendered
  header is pixel-identical before/after — no new visible row, no shift
  in title/close position.

**Scope grant:** this specifically authorizes the Developer to modify
`force-app/main/default/lwc/gtmModalShell/gtmModalShell.html` and
`force-app/main/default/lwc/gtmModalShell/gtmModalShell.css` for this
header-extras wrap fix only (plus whatever `gtmConfigWizard.css` follow-up
is needed once `.mw-progress`/`.mw-dotrow` sit in their own full-width
row — e.g. they may finally want explicit `width: 100%` there too, since
they're no longer flex siblings of anything). Do **not** touch
`gtmModalShell.js` (no prop/event contract change is needed for this) and
do not touch any other consumer of `gtmModalShell`. All other constraints
in this scope doc (§4 Out of Scope) still apply — this addendum only lifts
the single "no changes to `gtmModalShell` itself" line for this narrow,
QA-driven reason.
