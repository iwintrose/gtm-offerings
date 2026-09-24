# GTM Page Header Layout Contract (`c-gtm-page-header`)

Issue: `page-header-layout-fix` (urgent live UI bug, `gtm-prod` treated as Production).
Scope: `force-app/main/default/lwc/gtmPageHeader/` (CSS only; markup and public API unchanged).

## 1. Defect

On the Overview tab the shared header collapses its title block to a sliver (eyebrow wraps one word per line, title cut, meta clipped) and the four action buttons overlap the title/heading bar. At narrow widths the last button is cut off at the right edge.

Root cause, in `gtmPageHeader.css`:

- `.hdr .slds-page-header__row` is `display:flex` with no `flex-wrap`.
- `.slds-page-header__col-title` has `min-width:0` and no `flex-basis`, so it shrinks to nothing.
- `.slds-page-header__col-actions` cannot shrink or wrap, so a wide action set consumes the row.

## 2. CSS rule table (contract)

| Selector (all under `.hdr`) | Required declarations |
|---|---|
| `.slds-page-header__row` | `display:flex; flex-wrap:wrap; align-items:flex-start; gap:1rem` |
| `.slds-page-header__col-title` | `flex:1 1 16rem; min-width:0; display:flex; align-items:flex-start; gap:.75rem` |
| `.slds-page-header__col-actions` | `flex:0 1 auto; min-width:0; display:flex; flex-wrap:wrap; justify-content:flex-end; align-items:center; gap:.5rem; margin-left:auto` |
| `.hdr-title` | existing declarations plus `overflow-wrap:anywhere` |
| `.hdr-meta`, `.hdr-eyebrow` | unchanged; `.hdr-meta` keeps `min-height:1.2em` |

Hard constraint (regression guard for `gtm-page-header-icon-shift`, commits 861f020, 768bbba, fb27785, b2ca7cc): never set `align-items:center` on the row or on the title column. Centering there re-positions the icon/title when the meta line is populated vs blank. `align-items:center` is allowed only on the inner actions column (it aligns buttons with each other, not the title).

## 3. Fork decisions

1. Wrap-only ships first. Moving the Overview actions into a primary button plus overflow menu is a documented follow-up (needs handler re-wiring to `lightning-button-menu` `onselect` and `gtmOverview.test.js` changes; too large for a live-bug fix).
2. When actions wrap under the title they are right-aligned (`justify-content:flex-end`, `margin-left:auto`), matching SLDS record headers.
3. Title floor is `16rem`. Long titles wrap with `overflow-wrap:anywhere` on `.hdr-title`; they are never truncated.
4. Sticky `.pb-head` (gtmPageBrowser): a taller wrapped header on phone is acceptable, but it must be re-confirmed that it causes no horizontal overflow and no height trap (the sticky header must not consume the viewport). Only 0 or 1 action is slotted there, so wrapping is rare.
5. All 11 consumers are checked: gtmOverview, gtmContentHome, gtmContentManager, gtmAssessmentSubmissionView, gtmAnalytics, gtmReadoutApprovalSettings, gtmReadoutsOverview, gtmPageBrowser, gtmInstrumentAuthor, gtmOfferingsSettings, gtmRecycleBin.
6. No Experience Cloud publish is needed: no consumer is under `experiences/`, and every consumer exposes only `lightning__AppPage` / `lightning__Tab` targets. Deploy is LWC-only.

## 4. Salesforce-native evaluation

- The standard SLDS page-header pattern is one brand primary action, then a `lightning-button-group` and/or a `lightning-button-menu` overflow for secondary actions.
- `lightning-button-group` does not wrap, so it is not used inside the shared header (it would reintroduce the overflow).
- Nothing standard replaces the header on a custom app page (Lightning App Builder page headers are not controllable from a custom LWC page body), so the custom component stays.
- The overflow-menu adoption for Overview remains the documented follow-up (fork 1).

## 5. Test plan

- Jest (`gtmPageHeader.test.js`) statically asserts each rule in section 2 against the CSS source (jsdom has no layout engine), without weakening existing assertions.
- All 11 consumer Jest specs and full `npm test` stay green.
- Throwaway visual harness (never committed, outside `force-app/`): five scenarios at 360/600/900/1100/1400px (no actions/blank meta; one icon-only button; four Overview buttons; ~80-char title incl. no-space variant with three actions; populated vs blank meta with identical icon/eyebrow top offset).
- Owed live QA on `gtm-prod` after deploy: Overview (all four buttons visible and working at wide/narrow/phone), Settings, Assessments, Pages (sticky, Back to Pages), Content Manager home, Analytics, Recycle Bin, Readout Approval Settings (no icon).

---

# Addendum A: Declarative actions, compact hamburger (issue `page-header-actions-menu`)

Scope: `force-app/main/default/lwc/gtmPageHeader/` (html, js, css, Jest) plus consumers gtmOverview, gtmContentHome, gtmRecycleBin. LWC only: no Apex, no metadata, no permission sets, no Experience Cloud publish. Sections 2-5 above remain in force; this addendum only adds to them. Look source of truth is the owner mockup (claude.ai artifact NVZjbuxNM8sS1y3UpCVeFo, 1400/1000/600 closed+open/360); the Architect could not load it (no artifact tool in this session), so the owner requirements below stand in for it and the live check must compare against the mockup.

## A.1 Public API

Existing `iconName`, `eyebrow`, `title`, `meta` and `<slot name="actions">` are unchanged. New:

- `@api actions` : array (default `[]`) of `{ name: string (required, unique), label: string (required), iconName: string (required), variant?: 'brand'|'neutral'|'destructive' (default 'neutral'), disabled?: boolean }`. The FIRST entry is the primary action. `variant` is honoured on wide buttons only (`lightning-menu-item` has no variant).
- Event `headeraction` : `CustomEvent('headeraction', { detail: { name } })`, non-bubbling, non-composed, fired from BOTH variants (wide `lightning-button` click reads `event.currentTarget.dataset.name`; menu `onselect` reads `event.detail.value`). Consumers use one `onheaderaction` handler that switches on `event.detail.name` and calls the existing handlers. A disabled action never fires.
- Rule of thumb: 2+ labelled actions use `actions`; single, icon-only or custom controls stay in the slot. Slot content renders at every width, before the buttons/hamburger, and is never folded into the menu.
- Consumers pass `disabled` through computed getters that return a fresh array (e.g. Content Home `isLoading`, Recycle Bin `restoreSelectedDisabled`/`emptyTrashDisabled`/`isLoading`) so LWC re-renders on change.

## A.2 Breakpoint decision (F1/F5)

- Measure the header's OWN (host) width, not the viewport: the Salesforce shell, utility bar and App Builder panels make the container narrower than the window. Compact when host width < 900px, wide at >= 900px.
- Mechanism: ResizeObserver, NOT a CSS container query. Rationale: there is real doubt that the LWC CSS compiler and synthetic-shadow selector scoping handle `@container` rules and `container-type` on `:host` in this org, and that cannot be verified without a browser; `container-type` also adds layout/stacking containment on the host, which is a hazard for a dropdown that must escape the header. Viewport `@media` is rejected (wrong measure).
- Implementation contract: in `renderedCallback` (once, guarded) create `new ResizeObserver(entries => ...)` on `this.template.host`, read `entries[0].contentRect.width`, set a tracked `isCompact = width < 900`; only assign when the value changes; `disconnect()` in `disconnectedCallback`. If `typeof ResizeObserver === 'undefined'`, stay wide (no throw). Initial state is wide until the first callback (one frame). Template uses `lwc:if={isCompact}` / `lwc:else`: exactly one variant is in the DOM. Never mix with CSS display toggling.
- Jest: jsdom has no ResizeObserver, so tests define `global.ResizeObserver` as a stub that records the callback and its target, then invoke the callback with `[{ contentRect: { width } }]` inside `act`-style awaits (`await Promise.resolve()`). Also test the undefined-guard and disconnect.

## A.3 Markup contract

Inside `.slds-page-header__col-actions`: `<slot name="actions">`, then either
- wide: one `lightning-button` per action (`label`, `icon-name`, `variant`, `disabled`, `data-name`, class `hdr-action`), or
- compact: ONE `lightning-button-menu` (class `hdr-menu`, `icon-name="utility:rows"`, `alternative-text="Page actions"`, `menu-alignment="right"`) containing one `lightning-menu-item` per action in array order (`value`=name, `label`, `prefix-icon-name`=action iconName, `disabled`).

Salesforce-native evaluation: `lightning-button`, `lightning-button-menu`, `lightning-menu-item` (with `prefix-icon-name`) are the native pieces and are used as-is; `lightning-button-group` still rejected (does not wrap); the SLDS page-header pattern (primary plus overflow menu) is what this implements. Nothing standard replaces a custom header on an App Page, so no hand-rolled menu or dropdown is built.

Menu rules:
- Opens DOWNWARD, never upward: `menu-alignment="right"` only (never `auto`, never a `bottom-*` value; `auto` can flip upward). Right alignment anchors the dropdown's right edge to the hamburger so it extends left and stays inside the viewport at 360px.
- Icons kept: each item's `prefix-icon-name` equals its action `iconName` (Overview: utility:new, utility:identity, utility:search, utility:preview). Jest asserts this for every item.
- Primary action first in the menu.
- Hamburger icon `utility:rows` (F4).
- No red menu item is possible (F3): Delete is LAST with `utility:delete`; the existing two-step confirm modal (`handleAskEmptyTrash` only sets `deleteConfirmStep=1`) is the safety. No extra confirm in the header.

## A.4 CSS rule additions (existing section 2 rules unchanged and must stay asserted)

`.hdr` gets a class `hdr-compact` when `isCompact`.

| Selector (under `.hdr`) | Declarations |
|---|---|
| `.slds-page-header__col-actions` (base, wide) | add `align-self:flex-end` (bottom-right on the title row and when wrapped under the title). Keep `flex:0 1 auto; margin-left:auto; justify-content:flex-end; align-items:center` |
| `.hdr-compact .slds-page-header__col-actions` | `align-self:flex-start; flex-wrap:nowrap` (hamburger top-right beside the title; keep `margin-left:auto`) |
| `.hdr-compact .slds-page-header__col-title` | `flex-basis:10rem` override so the 44px hamburger never wraps under the title at 360px (16rem + 44px + 1rem gap + 2rem padding = 348px plus page padding does not fit a 360px window). The base `flex:1 1 16rem` rule stays and stays asserted; the 10rem override applies only in compact. Long titles still wrap via `overflow-wrap:anywhere` |
| `.hdr-menu` | wrapper/host min 44x44px touch target (`min-width:2.75rem; min-height:2.75rem`), best effort via the host; verify it does not clip the button in the live check |

Clipping/stacking rules: add NO `overflow`, `contain`, `transform`, `container-type`, or `position`+`z-index` on `.hdr`, the row, the title column or the actions column. Audit (done): the consumers' `overflow:hidden` rules sit on `.ov-card`, `.ocard`, `.off`, `.pb-stage` (cards/panels that are siblings of the header, not ancestors of `c-gtm-page-header`); `.pb-head` in gtmPageBrowser is `position:sticky; top:0; z-index:2` with no overflow. gtmPageBrowser has no hamburger (F2), so the sticky z-index needs no change now; any future sticky consumer with `actions` must raise its z-index above following siblings. Jest statically asserts none of the forbidden properties appear in gtmPageHeader.css. Live check: open menu at 600 and 360 is fully visible, drops down over content, causes no page scrollbar or horizontal overflow.

Guards preserved and asserted: 16rem title floor, no `align-items:center` on the row or title column, `.hdr-meta{min-height:1.2em}`, icon-shift/B14a assertions.

## A.5 Behaviour by width (all measured on the header host)

- >= ~1150px: buttons inline on the title row, bottom-right (`align-self:flex-end`).
- 900px to ~1150px: the four labelled buttons wrap to their own right-aligned row under the title (existing #230 wrap; automatic from the 16rem floor, no JS).
- < 900px: one hamburger, top-right beside the title block.
- Slot content (Analytics combobox + refresh) follows the same alignment; it may wrap under the title in compact (accepted).

## A.6 Fork decisions

| Fork | Decision |
|---|---|
| F1 breakpoint measure | Header host width, not viewport |
| F2 | Back to Pages (gtmPageBrowser) and icon-only refresh buttons (gtmAnalytics, gtmAssessmentSubmissionView, gtmReadoutsOverview) stay on the slot |
| F3 destructive in menu | Accept no red; Delete last with `utility:delete`; two-step modal is the safety |
| F4 | Hamburger `utility:rows`; one array order used for menu and wide: primary first, others in current relative order |
| F5 | ResizeObserver + `lwc:if` (container query rejected, see A.2) |
| F6 | gtmOverview.test.js (`lightning-button[slot="actions"]` assertions, ~lines 577/599/612) and gtmRecycleBin tests move to the `actions` prop / `headeraction` event; modal buttons unchanged |
| F7 | Sticky `.pb-head` needs no change (no hamburger there); 348px fit resolved by the compact 10rem title override |
| Alert to owner | Content Home wide order changes to New offering, Refresh, Recycle Bin (primary first) instead of primary right-most. Overview already lists its primary first |

## A.7 Consumer migration table

| Consumer | Action |
|---|---|
| gtmOverview | `actions` = new-engagement-link (brand, utility:new), new-rep-direct-assessment (utility:identity), browse-links (utility:search), see-assessments (utility:preview); one `handleHeaderAction` switch calling the existing four handlers |
| gtmContentHome | `actions` getter: open-new-offering (brand, utility:new), refresh (utility:refresh, `disabled: isLoading`), open-recycle-bin (utility:recycle_bin_empty) |
| gtmRecycleBin | `actions` getter: refresh (`isLoading`), restore-selected (utility:undo, `restoreSelectedDisabled`), delete-selected (destructive, utility:delete, `emptyTrashDisabled`) last |
| gtmAnalytics, gtmAssessmentSubmissionView, gtmReadoutsOverview, gtmPageBrowser | stay on slot; regression run only |
| gtmContentManager, gtmInstrumentAuthor, gtmOfferingsSettings, gtmReadoutApprovalSettings | no actions; regression run only |

## A.8 Verification

- Jest: extend `gtmPageHeader.test.js` (prop rendering, ResizeObserver stub toggling wide/compact at 899/900, exactly one variant in the DOM, `headeraction` payload from both variants, primary first, `prefixIconName` parity, disabled/variant mapping, `menu-alignment="right"` and no `auto`/`bottom-*`, aria label, slot still rendered in both modes, static CSS assertions from A.4 including forbidden properties); update gtmOverview (incl. funnel/repDirect), gtmContentHome, gtmRecycleBin specs; run all other consumer specs; full `npm test` green.
- Throwaway harness (never committed, outside `force-app/`): fully OFFLINE, inline CSS only, no CDN or external stylesheet; hand-copied minimal SLDS rules; scenarios 1400/1200/1000/600 closed+open/360; layout proof only.
- Validate-only (`--dry-run` / check-only) LWC deploy allowed. Live deploy to `gtm-prod` (Production) is NOT authorised for Developer or QA; live browser QA of all 11 consumers is owed after an explicitly authorised deploy.
