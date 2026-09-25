# GTM Card Contract (`c-gtm-card`)

Issue: `14` (ov-card-consistency). Scope: new `force-app/main/default/lwc/gtmCard/`,
plus HTML/CSS edits to its four consumers: `gtmOverview`, `gtmHeatGrid`,
`gtmTasksDueTodayWidget`, `gtmReadoutsAwaitingWidget`. Structural precedent:
`c-gtm-page-header` (issue #8, commit `861f020`,
`docs/architecture/gtm-page-header-layout.md`).

## 1. Problem

Four components hand-duplicated the identical `.ov-card`/`.ov-card-h`/
`.ov-card-b` chrome block (border/radius/background/box-shadow/hover-lift/
reduced-motion/header layout/body padding), each carrying a "KEEP THESE
RULES IN SYNC WITH gtmOverview.css" comment, because LWC shadow DOM scopes
each component's CSS to its own template only -- a real cross-bundle CSS
`@import` was tried twice (gtmHeatGrid.css, gtmOverview.css comments) and
both times broke Jest by pulling in the target component's JS module. Two of
the four consumers (`gtmReadoutsAwaitingWidget`, `gtmTasksDueTodayWidget`)
had zero text-truncation CSS at all, so card body text could overflow/wrap
unbounded.

## 2. Design decisions (resolving the open questions)

### 2.1 `railColor`: named-variant enum, not a free color

`@api variant` accepts one of `deals | heat | tasks | readouts | offerings`;
any other value (including unset) falls back to the neutral gray rail
(`#747474`, `.gcard`'s own default `border-top-color`) with no icon-circle
color override. Rationale: matches `gtmPageHeader`'s own prop convention
(named props, not raw CSS values) and there is no case in the four
consumers where a card needs an arbitrary one-off color -- every existing
rail color is already one of a fixed, small set, always paired 1:1 with an
icon-circle color (e.g. `.ov-heat` always pairs with `.ov-ic--heat`). A
single `variant` prop drives both the rail AND the icon-circle background/
foreground together, so a consumer can't pass a rail color that doesn't
match its icon color by mistake -- the previous per-consumer class pairs
made that a real (if minor) drift risk. `gtmOverview`'s "Assessment
results" card and its `.ocard` offering cards that use variants outside
this set (`results` = plain gray, `offerings` = purple) use `variant=""`
(default gray) and `variant="offerings"` respectively -- no `results`
variant is needed since it's identical to the no-variant default.

### 2.2 Title prop vs. header slot: named slot `header`, with the title/icon
render as its LWC fallback content

`c-gtm-card` exposes a named `<slot name="header">` plus an explicit
`@api customHeader` boolean. A consumer with a plain single-line header
just sets `icon-name`/`title` and leaves `customHeader` false (default);
`c-gtm-card` renders the icon-circle plus a single `<h2 class="gcard-title
slds-truncate">{title}</h2>` itself. `gtmOverview`'s "Assessment results"
card, which needs the two-line stacked header (`.ov-results .ov-card-h`
today, `h2` + a note row with two `lightning-button`s and a middot),
instead sets `custom-header` and projects its own markup with
`slot="header"`, which suppresses the icon/title render entirely -- no
branching logic inside `c-gtm-card` itself about what that markup looks
like, so the shared component never has to know about that one consumer's
layout variant.

`customHeader` is an explicit flag rather than the more "automatic"-looking
option of having `c-gtm-card` detect whether real content was projected
into the slot (native `<slot>`'s own fallback-content behavior, or
`slot.assignedElements().length`). Both were tried and rejected: this
component ships through `sfdx-lwc-jest`'s synthetic-shadow test environment
(the same one every other component in this repo tests against, and the
one non-native-shadow orgs run in production), and in that environment
neither native slot-fallback hiding nor `assignedElements()` reflects real
light-DOM assignment reliably -- confirmed empirically while building this
component's own Jest spec (`assignedElements()` returned `[]` even
immediately after appending a real `slot="header"` child and awaiting a
microtask). An explicit boolean is a one-line, unambiguous, and equally
CSS/markup-light contract that works identically in both the synthetic and
native cases, so there's no dependency on shadow-mode behavior that can't
be verified outside a real browser. `headerAlign="start"`
(vs. the default `"center"`) is a separate, orthogonal prop that only
controls the header row's own `align-items`/`min-height` (ported from the
`.ov-results .ov-card-h` override), since a slotted two-line header still
needs the shared header row's own alignment relaxed regardless of what's
inside it.

Rejected alternative: a `title` prop plus a second `subtitle`/`meta` prop
to cover the two-line case generically. Rejected because the "Assessment
results" header isn't a title+subtitle pair -- it's a title plus two action
buttons and a separator -- so a generic two-string prop pair would not have
actually covered it; a slot with title/icon as its fallback avoids
designing a bespoke prop shape for a single consumer.

### 2.3 The `.ocard` sibling family: folds into `c-gtm-card`

`gtmOverview.css` lines ~294-330 (pre-migration) applied the identical
rail/hover/reduced-motion treatment to `.ocard` (the per-offering cards in
the Offerings view) as a sibling-selector pair with `.ov-card`
(`.ov-card, .ocard { border-top: 3px solid #747474; ... }`,
`.ov-card:hover, .ocard:hover { ... }`). Decision: fold `.ocard` into
`c-gtm-card` rather than leaving it separate. It is the same file already
being migrated for this issue (`gtmOverview.html`/`.css`), the chrome rules
are byte-identical to `.ov-card`'s, and leaving `.ocard` as a fifth
hand-duplicated sibling would recreate exactly the "keep two things in sync
by hand" problem this issue exists to close -- just narrowed from four
files to two rules inside one file. `.ocard`'s own header content
(icon + stacked offering name/key, `.ocard-top`/`.ocard-id`) is distinct
enough from the single title+icon default to go through the `header` slot,
the same mechanism used for "Assessment results" (§2.2). `.ocard`'s
body-only classes (`.ocard-sum`, `.ocard-acts`, `.ocard-panel`,
`.ocard-counts`, `.ocount-footnote`) stay in `gtmOverview.css` unchanged --
they are offering-specific body content, not shared card chrome, and
`c-gtm-card`'s default slot leaves the body fully owned by the consumer.
`.ocard`'s rail/icon color (`#9050e9`, purple) is expressed as
`variant="offerings"`, matching the existing `.ov-offerings`/`.ov-ic--offerings`
pairing used elsewhere on the same page.

The Experience Cloud `.tile` family (`offeringChooser.css`/
`chooseIndustry.css`) is explicitly NOT part of this decision -- it is a
different, out-of-scope surface (issue #15) with zero file overlap with
`.ov-card`/`.ocard`, confirmed in `task-scope-14.md` §1. Nothing here
should be read as building #15's tile convergence.

### 2.4 Shared truncation utility: the platform's own `.slds-truncate`
base class -- not a new custom class

Decision: consumers apply the SLDS framework's own `.slds-truncate` utility
class (`overflow:hidden; text-overflow:ellipsis; white-space:nowrap;
max-width:100%; display:block` -- already free in every LWC template in
this org, not a component-specific stylesheet) directly to any single-line
card text node that needs truncation, instead of a bespoke class owned by
`c-gtm-card`. This is not a third duplicate of the "Issue 274" ellipsis
rule that already exists twice (`gtmHeatGrid.css`'s `.gtm-link-cell`,
`gtmOverview.css`'s `.gtm-link-cell`/`.at-name` pairing, both left as
values-only copies of `gtmLinkCell.css`'s real rule because a real
cross-bundle CSS import broke Jest, per both files' own comments) --
`.slds-truncate` is a zero-duplication mechanism because it is not owned by
any component's bundle at all, so there is nothing to keep "in sync." It
was ALREADY partially in use (the two truncation-gap widgets' primary text
lines, `gtmTasksDueTodayWidget.html`'s `<span class="slds-truncate">
{row.subject}</span>` and `gtmReadoutsAwaitingWidget.html`'s
`<div class="slds-truncate">{row.accountName}</div>`), just inconsistently
-- the secondary lines (`whatName`, `opportunityName`, `proxyLabel`) had no
truncation rule at all, which is the actual "zero truncation CSS" gap. This
migration adds `.slds-truncate` to those secondary lines, closing the gap,
and replaces `gtmHeatGrid.css`'s and `gtmOverview.css`'s local `.gtm-link-cell`
value-only copies with the same `.slds-truncate` class directly in markup,
deleting the local duplicate rule blocks (the `.gtm-link-cell_static` color
rule in `gtmHeatGrid.css` and the `.at-name` font-weight rule in
`gtmOverview.css` are unrelated to truncation and are kept).

`c-gtm-card` itself applies `.slds-truncate` to its own fallback-content
`<h2 class="gcard-title slds-truncate">` title, so the header title is
truncated the same way as everything else, with no separate mixin.

Rejected alternative: a `::slotted(.gtm-truncate)` rule inside
`gtmCard.css`. This would in fact work (shadow DOM does let a host style
one level of slotted children via `::slotted`), but it would introduce a
SECOND truncation mechanism alongside the platform's existing
`.slds-truncate` for no behavioral gain, and would only cover slotted
content, not card header text that's outside any slot.

## 3. Public API (`c-gtm-card`)

| Prop | Type | Default | Notes |
|---|---|---|---|
| `iconName` | string | `''` | SLDS icon name for the header icon-circle; omitted -> no icon rendered. Only used by the slot's fallback content -- ignored if `header` slot is populated. |
| `title` | string | `''` | Header title text; rendered `slds-truncate`d. Only used by the slot's fallback content. |
| `variant` | string enum | `''` | One of `deals \| heat \| tasks \| readouts \| offerings`; drives rail color + icon-circle color together. Unknown/omitted -> neutral gray rail, no icon-circle color override. |
| `headerAlign` | string enum | `'center'` | `'center'` (default, single-line header, 3rem min-height) or `'start'` (two-line/stacked header, no min-height floor, bottom padding only). |
| `customHeader` | boolean | `false` | `true` suppresses the icon/title fallback header so a `slot="header"` child fully owns the header row (see §2.2). |
| `flushTop` | boolean | `false` | `true` zeroes the body region's top padding, for a consumer whose body is its own scroll container with a sticky header row that must sit flush against the card header (ported from `.ov-deals-body`/`.ov-results-body`'s `padding-top: 0`, both scoped to the SAME element as the shared body padding in the old markup -- now that padding lives inside `c-gtm-card`'s own shadow DOM, there is no other way for a consumer to override it). |

Slots: `header` (named, optional -- rendered alongside/instead of the
icon+title fallback per `customHeader` above), default (card body, fully
owned by the consumer).

CSS classes exported for consumer reuse are `.gcard`, `.gcard-h`,
`.gcard-h--start`, `.gcard-b`, `.gcard-title`, `.gcard-ic`,
`.gcard-ic--<variant>`, `.gcard--<variant>` -- these live inside
`gtmCard.css`'s own shadow scope and are not selectable from a consumer's
stylesheet; they are listed here only so the mapping from the old
`.ov-card`/`.ov-ic--*`/`.ov-<variant>` names is traceable.

## 4. Migration notes

- `slds-card` stays on the host `<article>` (via `cardClass`) for SLDS
  grid-trap parity (`.ov-cols > .ov-card + .ov-card { margin: 0; }` and
  friends) -- those margin-reset selectors move to target
  `c-gtm-card`'s host tag instead of `.ov-card`/`.ocard`.
- `gtmHeatGrid`, `gtmTasksDueTodayWidget`, `gtmReadoutsAwaitingWidget` each
  lose their entire duplicated `.ov-card`/`.ov-card-h`/`.ov-card-b`/`.ov-ic`/
  rail-color CSS block and its "keep in sync" comment; their markup's
  `<article class="slds-card ov-card ov-*">` / `<div class="slds-card__header
  ov-card-h">...</div><div class="slds-card__body ov-card-b">` wrapper
  becomes `<c-gtm-card icon-name="..." title="..." variant="...">...
  </c-gtm-card>`.
- `gtmOverview` keeps its own page-level CSS (`.ov`, `.ov-cols`, `.at-row`,
  `.deals`, `.ocard-sum`, etc.) untouched except for deleting the
  `.ov-card`/`.ov-card-h`/`.ov-card-b`/`.ov-ic`/`.ocard`/`.ocard-top` chrome
  rules superseded by `c-gtm-card`, per §2.3.
- Migration order (per task scope): `gtmReadoutsAwaitingWidget` first
  (closes a real truncation gap), then `gtmTasksDueTodayWidget` (the other
  gap), then `gtmHeatGrid`, then `gtmOverview` last (largest, touches both
  `.ov-card` and `.ocard`).

## 5. Test plan

- `gtmCard/__tests__/gtmCard.test.js` (pattern: `gtmPageHeader.test.js`):
  icon/title fallback rendering, `variant` enum mapping (valid values map to
  the right rail/icon classes, invalid/omitted falls back to no modifier
  class), `headerAlign` class toggle, header slot overriding the fallback
  content, default slot projection.
- Existing Jest specs for the four consumers stay green (updated where they
  assert on now-removed local classes/markup).
- `npm test`, `python3 scripts/check-references.py`, and
  `python3 scripts/build-instrument.py --check` all pass (no instrument/
  metadata surface touched by this issue, so the latter two are
  expected no-ops).
