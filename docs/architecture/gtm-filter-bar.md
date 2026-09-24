# GTM Filter Bar (`gtmFilterBar` + `gtmFilterUrlState`)

Status: contract for issue `shared-filter-bar`. Consumers (`stage-filter-pages-tab`, `assessments-tab-filter`) build against this file and may not start until it has merged.

## 1. Purpose and native-first rule

One reusable filter capability. `gtmFilterBar` is a thin composition of base `lightning-*` components and native SLDS chip buttons driven by a `filters` config; `gtmFilterUrlState` is a pure JS module that maps the same config to and from `c__` page state. Neither knows any domain vocabulary, calls Apex, or filters data. Standard list-view filters do not apply (consumers are custom tabs over Apex-aggregated rows).

| Config `type` | Base component |
|---|---|
| `select` | `lightning-combobox` |
| `chips`, `multi: true` | one native `<button class="slds-button">` per option in a wrapping `role="group"` container (Addendum A) |
| `chips`, single | same chip buttons, single-select (Addendum A) |
| `toggle` | `lightning-input type="toggle"` |
| `date-range` | `lightning-combobox` (presets + Custom) and two `lightning-input type="date"` (Custom only) |
| Active-filter pills | individual `lightning-pill` in a wrapping container (`onremove`) (Addendum A) |
| Clear all | `lightning-button variant="base"` |
| Result count | `<p aria-live="polite">` |

## 2. `gtmFilterBar` contract

### Props (`@api`)

| Prop | Type | Default | Notes |
|---|---|---|---|
| `filters` | `FilterConfig[]` | `[]` | See section 3. |
| `values` | `{ [key]: value }` | `{}` | Controlled. The bar holds no filter state of its own (except an unsaved half-entered custom date range). |
| `resultCount` | number | none | Shown when a number. |
| `resultLabel` | string | `''` | Noun after the count, e.g. "results". |
| `label` | string | `Filters` | Accessible label of the `role="group"` wrapper. |
| `variant` | `'default'` \| `'compact'` | `default` | Compact: tighter spacing, hidden labels (placeholder used for selects), small gaps. |

### Events

| Event | Detail | When |
|---|---|---|
| `filterchange` | `{ key, value }` | Exactly one per user change. Value shape below. |
| `clear` | none | "Clear all", or removing the pill of the last active filter. |

`filterchange.value` by type: single chips / select = `string` (`''` = remove); multi chips = `string[]` (`[]` = remove); toggle = `boolean`; date-range = preset token string (e.g. `'30'`), `{from, to}` (ISO `YYYY-MM-DD`), or `''`. Removing a pill (not the last) dispatches `filterchange` with the empty value for that key. Bubbles: no. Composed: no.

### Slots

None.

### Layout

Flex-wrap, no fixed widths; works full-width and at ~320px (card header). Chips and pills wrap individually; selects and date inputs shrink (`min-width: 0`) or stack (Addendum A). Only hexes already used in `gtmRepLinkFinder.css` / `gtmOverview.css` are allowed; SLDS utility classes first.

## 3. Config schema

```
FilterConfig {
  key: string            // unique; equals the GUS filter key
  label: string
  type: 'chips' | 'select' | 'toggle' | 'date-range'
  param: string          // URL param, must start with c__, must not be reserved
  options?: [{ value, label, count? }]   // chips/select; date-range presets (default 7/30/90)
  multi?: boolean        // chips only, default false
  defaultValue?: any     // equal to default => param omitted from URL
}
```

Option values must not contain commas. Unknown values (not in `options`) are dropped on read.

## 4. URL rules (`gtmFilterUrlState`)

- Every param is `c__`-prefixed (platform rule for `standard__navItemPage` state) and consumer-prefixed (F4). Reserved, rejected: `c__assessmentRequestId`, `c__readoutId`, `c__offeringKey`, `c__browseMode`, `c__repDirectId`, `c__rlf*`, `c__rafAccountId`, `c__rafContactId`, `c__template`, `c__recordId`, `c__company`, `c__offering`. Invalid configs: `validateFilters` returns problems, `assertValidFilters` throws (dev/test); `readFilterState` / `buildFilterUrlState` silently skip an invalid filter (prod).
- Multi = ONE param, comma-separated (`c__stage=quiet,hot`), canonicalised to option order.
- Date range = preset token alone (`30`) or `YYYY-MM-DD..YYYY-MM-DD` (from <= to, real dates).
- Toggle = `true`; false/absent removes the param.
- Empty and default values remove the param. Only the config's own params are touched; every other `c__` param is preserved byte for byte.
- The URL is the source of truth on refresh: consumers derive `values` from `CurrentPageReference.state` via `readFilterState`.

### Functions (pure, no navigation)

- `readFilterState(state, filters) -> values`
- `buildFilterUrlState(currentState, filters, values) -> newState`
- `buildNavigateArgs(pageRef, filters, values, { mode = 'replace', currentState }) -> { pageReference, replace }` (same `type`/`attributes`, `state` merged; `replace` true unless `mode: 'push'`)
- `mergeLocationState(pageRefState) -> state` overlays every `c__*` from `window.location.search` onto the wired state, because `gtmReadoutsOverview` / `gtmRepLinkFinder` still write selection params with `history.replaceState`, so the wired state can be stale.
- `validateFilters`, `assertValidFilters`, `RESERVED_PARAMS`.

### Write mechanism (F1)

The consumer calls `this[NavigationMixin.Navigate](pageReference, replace)` using `buildNavigateArgs(pageRef, filters, values, { currentState: mergeLocationState(pageRef.state) })`. The bar and util never use `window.history` for filter params. All writing goes through `buildNavigateArgs`, so falling back to `replaceState` is a one-function change.

Consumers MUST treat a re-fired `CurrentPageReference` as idempotent (re-read filters; no double fetch when values are unchanged).

UNVERIFIED (no org access authorised): whether a state-only Navigate remounts the tab component. The first consumer's QA checklist must confirm no remount/flicker on a chip click once a deploy is authorised; if it remounts, fall back to `replaceState` inside `buildNavigateArgs`' consumer wrapper and record it here.

## 5. Server-side convention (documented only)

Each domain exposes ONE Apex method taking the filter-key set and returning `{ rows, counts, total }`: no DML, no callouts, `with sharing` / `WITH USER_MODE`, `cacheable=true` if read-only. The page, the Overview funnel counts and GUS tools call that same method so all agree. GUS filter keys equal config `key`s (multi = array). GUS tools stay zero-DML (AGENTS.md §1).

## 6. Worked examples (ILLUSTRATIVE ONLY)

These are NOT the authoritative vocabularies. The sibling issues own and must verify their option values against code and picklists: see `task-scope-stage-filter-pages-tab.md` (which also defines `not_opened`, missing below) and the `assessments-tab-filter` scope / Apex.

(a) Pages:

```js
[{ key: 'stage', label: 'Stage', type: 'chips', multi: true, param: 'c__stage',
   options: [{ value: 'sent', label: 'Sent' }, { value: 'engaged', label: 'Engaged' },
             { value: 'quiet', label: 'Quiet' }, { value: 'hot', label: 'Hot' }] }]
```

(b) Assessments:

```js
[{ key: 'status', label: 'Status', type: 'chips', multi: true, param: 'c__astatus', options: [...] },
 { key: 'tier', label: 'Tier', type: 'select', param: 'c__atier', options: [...] },
 { key: 'readout', label: 'Readout', type: 'select', param: 'c__areadout', options: [...] },
 { key: 'range', label: 'Date', type: 'date-range', param: 'c__arange' },
 { key: 'offering', label: 'Offering', type: 'select', param: 'c__aoffering', options: [...] }]
```

# Addendum A: Responsive chips (issue `filter-bar-responsive`)

Status: Architect decisions. Presentation-only; the props, `filterchange` / `clear` events and config schema in sections 2 and 3 are UNCHANGED. No consumer edits.

## A.1 Problem

`lightning-radio-group` / `lightning-checkbox-group` with `type="button"` render one nowrap inline-flex button group inside the base component's shadow DOM. Our stylesheet cannot reach it, so a single chip group (Pages: 7 count-labelled single-select chips; Assessments: multi groups) is an unbreakable item and overflows or squashes when narrow.

## A.2 Salesforce-native evaluation (standing rule)

| Option | Verdict |
|---|---|
| Wrap the base group with wrapper CSS | Not possible: inner `.slds-button-group` / `.slds-radio_button-group` is inside the base component's shadow DOM. Rejected. |
| `lightning-radio-group` / `lightning-checkbox-group type="button"` (current) | No wrap attribute or styling hook. Rejected for chips. |
| `lightning-button-group` | Wraps nothing either (nowrap group); also joins buttons flush. Rejected. |
| Individual buttons in our own `slds-grid slds-wrap` container | Chosen. SLDS button blueprint, native controls, wraps naturally. |
| `lightning-combobox` for narrow single-select | Native, but single-value only and hides counts/selection. Deferred, see A.6. There is no native multi-select combobox; multi chips stay buttons at all widths. |

## A.3 Chip rendering (chosen)

- Each option is its own `<button type="button" class="slds-button slds-button_neutral gtm-filter-bar__chip" aria-pressed="true|false" data-key data-value>`. Selected adds `slds-button_brand` in place of neutral (existing SLDS brand look; NO new hex, NO custom properties). Label text = `option.label`; counts stay inside the label (as `_optionsWithCounts` builds them today).
- Why native `<button>` and not `lightning-button`: the base `lightning-button` does not document an `aria-pressed` attribute (not verifiable offline), and we cannot set ARIA on its inner button from outside its shadow. A native button using the SLDS blueprint classes is still Salesforce-standard markup and gives correct keyboard/AT behaviour for free. Developer: if the Component Library is checked and `aria-pressed` IS supported, do not switch; keep native for consistency and record it.
- Container per filter: `<div class="slds-grid slds-wrap gtm-filter-bar__chips" role="group" aria-label={f.label}>` with gap via `slds-m-right_x-small slds-m-bottom_xx-small` on each chip (or `gap` in CSS). Above it, a visible label (`<span class="slds-form-element__label">{f.label}</span>`) in the default variant only; in the compact variant the label is not rendered visibly but the `aria-label` on the group wrapper is retained (always present in both variants). No new hexes; `.gtm-filter-bar__chip { max-width: 100%; }` and allow label text to wrap (`white-space: normal`) so one very long option cannot overflow at 320px.
- Semantics: `role="group"` + `aria-pressed` toggle buttons for BOTH single and multi. No `radiogroup`, no roving tabindex or arrow-key logic; every chip is Tab-reachable, Space/Enter activates (native button click).
- Single-select behaviour (parity with the radio group): click a non-selected chip emits `filterchange {key, value: '<option value>'}`; click the already-selected chip is a no-op (NO event, no deselect; removal is via pill / Clear all).
- Multi-select: click toggles membership; emits `filterchange {key, value: string[]}` in OPTION ORDER (canonical, matches `gtmFilterUrlState`), not click order. Removing the last selected value emits `[]`.
- Exactly one `filterchange` per user click. Handler reads `data-key` / `data-value` from `event.currentTarget`.

## A.4 Pills

Cannot verify offline that `lightning-pill-container` wraps at 320px (its inner listbox is in base shadow DOM), so use individual `lightning-pill` elements in `<div class="slds-grid slds-wrap gtm-filter-bar__pills">` (each `slds-m-right_xx-small slds-m-bottom_xx-small`, `label`, `data-key`, `data-value` where multi). Map `onremove` to the SAME handler logic as today's `handlePillRemove` (same `filterchange` empty-value / `clear`-on-last semantics; the payloads are unchanged). Remove `lightning-pill-container` use.

## A.5 Other rows must wrap and never overflow at 320px

- Every `.gtm-filter-bar__item` keeps `min-width: 0; max-width: 100%`. Select / combobox and date-preset comboboxes: item wrapper is `flex: 1 1 12rem`-style (min-width 0 allowed, so a combobox shrinks rather than overflows) at narrow widths.
- Date-range custom row: `.gtm-filter-bar__dates` stays `slds-grid slds-wrap`; the preset combobox and From / To inputs each get `min-width: 0` and a `flex: 1 1 8rem` basis so From and To sit side by side when they fit and stack when not. No fixed widths.
- Status row (pills, Clear all, count) is already `slds-wrap`; keep.
- CSS uses only SLDS utilities plus `#747474` already present. No `@container`, no new hex.

## A.6 Decisions on forks (BA open forks 1-5)

1. Single-select: `role="group"` + `aria-pressed`, no radiogroup / arrow keys; clicking selected chip is a no-op (A.3).
2. Combobox collapse below ~600px: NOT included. Judgement: at 320px a count label such as "Assessment submitted (12)" is roughly 11-12rem including padding, so about 1 chip per row for the longest and 2 for the short ones; 7 chips is roughly 5 rows (~10rem tall). Tall but fully usable and every count/selection stays visible; not judged unusable. Follow-up only if the owner finds it too tall on the live check. If ever built, it is the only place a ResizeObserver would be needed, and MUST copy the guarded pattern in `docs/architecture/gtm-page-header-layout.md` Addendum A (create in `renderedCallback` once, `typeof ResizeObserver === 'undefined'` early return, only assign on change, disconnect in `disconnectedCallback`, `lwc:if` so one variant in the DOM). This fix adds NO ResizeObserver.
3. Selected style: native `<button>` (A.3) with `slds-button_brand` selected / `slds-button_neutral` unselected.
4. Compact variant: visible labels hidden; `aria-label` on each group wrapper remains, and the outer `role="group" aria-label={label}` stays.
5. Pills: individual `lightning-pill` in a wrapping container (A.4).

## A.7 Verification

- Jest (`gtmFilterBar.test.js`): chips render for single and multi (button count = option count, labels incl. counts); `aria-pressed` true only on selected; group has role="group" + aria-label (default and compact); wrap container has `slds-wrap`; single: click unselected emits `{key,value:'x'}` once, click selected emits nothing; multi: toggle on/off emits arrays in option order, `[]` when last removed; keyboard: `Enter`/`Space` on a native button is a click, so assert `click()` handling plus that chips are real `<button>` elements and not tabindex=-1; pills render as `lightning-pill` in a wrap container and remove maps to the same `filterchange`/`clear` as before; the exact payloads consumed by `gtmRepLinkFinder` (`stage`, string) and `gtmReadoutsOverview` (status/tier/readout/offering arrays or strings) are asserted. Static CSS assertions: no new hex beyond `#747474`, no `@container`. Consumer specs `gtmRepLinkFinder` and `gtmReadoutsOverview` and full `npm test` stay green.
- Offline harness (throwaway, scratchpad only, NOT committed): static HTML with SLDS-shaped markup and inline CSS only, no CDN; serve with `python3 -m http.server` on localhost. Frames at 320 / 480 / 768 / 1200 plus a compact card-header frame. Each must show: no horizontal scrollbar or overflow beyond the frame; chips wrapped (320: ~1-2 per row, ~5 rows for the 7 Pages chips; 480: 2-3 per row; 768: 4-5; 1200: one or two rows); counts visible in every label; one very long label wraps inside its chip; Assessments set stacks one filter per row at 320 with multi groups wrapped; Custom date range From/To side by side or stacked, within frame; pills and Clear all wrap; result count visible; compact frame shows no visible group labels but chips wrapped. The harness proves layout only, not real `lightning-*` rendering.
- Owed live check after an authorised deploy (not authorised now; a validate-only `--dry-run` / check-only deploy of the LWCs is allowed): Pages tab at wide and narrow widths with a stage selected and counts loaded, then the Assessments tab including Custom date range and a long offering list.

---

# Addendum B: Compact Jira-style bar (issue `compact-filters`)

Contract first: this addendum is the source of truth for the Developer. It supersedes Addendum A.3 (chips), A.4 (pills) and the "Layout" note in section 2 for how filters are RENDERED. Section 2 events, section 3 config and section 4 URL rules are unchanged except for the one additive optional config field in B.3.

## B.1 Decisions (owner, this conversation)

1. Scope: Assessments (`gtmReadoutsOverview`) and Pages (`gtmRepLinkFinder`) only, through the one shared `gtmFilterBar`. The bar is NOT added to Overview/Home, Analytics or the Content Manager.
2. No search box. Filters only.
3. An active filter shows INSIDE its button (its value, or a count) plus one "Clear filters" link. The removable-pill row and the duplicated pressed-chip display are removed.
4. No saved filters. The shareable URL (`gtmFilterUrlState`) is the persistence; its contract does not change.
5. Assessments row: Status, Readiness tier, Submitted on the row; Readout, Offering and Ready to book under "More". Pages: one filter (Funnel stage), no "More", counts stay in the option labels.

## B.2 Unchanged (frozen) contract

- `@api` props (`filters`, `values`, `resultCount`, `resultLabel`, `label`, `variant`) keep their names, types and meaning. `variant="compact"` is still accepted (Pages passes it); both variants now render the same single-row layout, `compact` only tightens gaps.
- Events: `filterchange {key, value}` exactly once per user change with the section 2 value shapes; `clear` (no detail, not bubbling, not composed). Value shapes: single = string, `''` to remove; multi = string[] in OPTION order (never click order), `[]` to remove; toggle = boolean; date-range = preset token, `{from,to}` ISO, or `''`.
- `gtmFilterUrlState` imports nothing from the bar and reads only the `filters` config, the `values` map and the two events' consumer handlers. It needs no change and its spec must pass unmodified.
- Config `key`, `param` and option `value`s are unchanged everywhere (the Overview drill-ins `c__stage` / `c__astatus`, the GUS `gtmGusUtility` map `GTM_Pages: ['c__stage']` and `GtmStageFilterAppTool` keys depend on them). Config ORDER in `buildFilterConfig` is unchanged (the `gtmReadoutsOverview` spec asserts it); the bar, not the config order, decides what is on the row.
- Removed events/behaviour: pill remove (`handlePillRemove`) disappears. Consequence: a single-select value (Pages stage) can no longer be un-picked from its own control; it is removed only by "Clear filters" (which emits `clear`; the consumer already handles it). Multi, toggle and date-range controls remove themselves inside their popover and emit `filterchange` with the empty value; when that empties the LAST active filter the bar still emits `filterchange` (not `clear`), which the consumers already treat identically to an empty value. Only "Clear filters" emits `clear`.

## B.3 Config: one additive optional field

`FilterConfig.more?: boolean` (default `false`). `true` puts the filter in the "More" popover instead of on the row. Unknown to `gtmFilterUrlState` (it ignores unknown fields; the Developer must confirm with a test that `validateFilters` returns `[]` for a config carrying `more`). `buildFilterConfig` in `gtmAssessmentsTableModel.js` sets `more: true` on `preset`, `readout`, `offering`. `gtmRepLinkFinder` sets nothing (no More is rendered when no filter has `more: true`).

## B.4 Salesforce-native evaluation and why the popover shell is custom

No web or doc tool was available to the Architect; every "base component does X" claim below is from working knowledge and is marked UNVERIFIED where a Developer/QA check is required.

- Contents use base components: `lightning-checkbox-group` (multi; NOTE the base component is `lightning-checkbox-group`, not `lightning-input type="checkbox-group"`, which does not exist), `lightning-radio-group` (single, and date presets), `lightning-input type="toggle"` (Ready to book), `lightning-input type="date"` (Custom range From/To), `lightning-input type="search"` label-hidden for the long-list filter, `lightning-button variant="base"` for "Clear filters".
- Date presets use `lightning-radio-group`, NOT `lightning-combobox`, inside the popover, so no dropdown is nested inside a dropdown (nested listbox clipping and Escape/focus conflicts). This drops the combobox from the date filter's UI only; the emitted values are identical.
- `lightning-button-menu` rejected: menu items cannot hold inputs (no long-list filter, no date inputs, no toggle), and it closes on selection, which breaks multi-select. `lightning-combobox` is single value only. `lightning-dual-listbox` is a two-pane picker, far too heavy.
- Therefore only the popover SHELL is hand-built, from the SLDS dropdown blueprint (`slds-dropdown-trigger slds-dropdown-trigger_click` with `slds-is-open`, `slds-dropdown`), with no extra libraries. If a Developer can show a base component that does this on API 62.0, use it and update this doc.

## B.5 Anatomy

```
<div role="group" aria-label={label} class="gtm-filter-bar slds-grid slds-wrap slds-grid_vertical-align-center">
  [per primary filter]  <div class="slds-dropdown-trigger slds-dropdown-trigger_click [slds-is-open]">
                          <button type="button" class="slds-button slds-button_neutral gtm-filter-bar__trigger [gtm-filter-bar__trigger--active]"
                                  aria-haspopup="dialog" aria-expanded="true|false" aria-controls={popId} aria-label={triggerAria}>
                            <span class="gtm-filter-bar__trigger-text">{triggerText}</span> <lightning-icon icon-name="utility:down" size="xx-small" alternative-text="">
                          </button>
                          <div id={popId} role="dialog" aria-label={filter.label} class="slds-dropdown slds-dropdown_left gtm-filter-bar__pop" tabindex="-1"> ...controls (B.6)... </div>
                        </div>
  [if any filter.more]  same pattern, trigger text "More" (+ " (n)" when n more-filters are active), popover holds one titled section per more filter (B.6 controls stacked)
  [if any active]       <lightning-button variant="base" label="Clear filters" onclick=clear>
  <p class="gtm-filter-bar__count" aria-live="polite">{resultCount + ' ' + resultLabel}</p>   // same row, margin-left:auto
</div>
```

The separate status row is deleted; the count now shares the row and wraps only when it must. The `.gtm-filter-bar__count` `#747474` colour stays (the only allowed hex).

### Trigger text and accessible name

| State | Visible text | `aria-label` |
|---|---|---|
| none | `Status` | `Status, no filter applied` |
| one value (single, multi with one, preset, toggle) | `Status: New` (value label, ellipsis at `max-width: 14rem`; counts in Pages option labels are NOT repeated: use the option label without its `(n)` for the button text) | `Status: New` |
| two or more | `Status: 2` | `Status: 2 selected, New, Contacted` |
| date custom | `Submitted: 2026-01-01 to 2026-01-31` (ellipsis) | same text |
| toggle on | `Ready to book: On` | same |
| More | `More` or `More (2)` | `More filters, 2 active` / `More filters, none active` |

Rule: `aria-label` always STARTS with the visible text (WCAG label-in-name). Active trigger gets `slds-button_brand`-free styling: use `gtm-filter-bar__trigger--active` (bold text, `slds-button_neutral` kept; no new hex) so the active state is not colour-only. `aria-expanded` is the string `"true"`/`"false"`.

## B.6 Popover contents per filter type (all controlled by `values`; no local filter state except drafts)

| type | control | emits |
|---|---|---|
| `chips` multi | `lightning-checkbox-group` (label-hidden, `label={filter.label}`) | on change: merge (see long-list rule), option order, `filterchange {key, string[]}` |
| `chips` single | `lightning-radio-group` | `filterchange {key, string}`; then the popover CLOSES and focus returns to the trigger. Picking the already-selected value emits nothing (as A.6.1). |
| `select` | `lightning-radio-group` with a leading "Any" (`''`) option | `filterchange {key, string}`; closes |
| `toggle` | `lightning-input type="toggle"` | `filterchange {key, boolean}` |
| `date-range` | `lightning-radio-group`: Any time (`''`), each preset, Custom range; when Custom (or value is `{from,to}`): two `lightning-input type="date"` From/To (existing draft logic, unchanged: emit `{from,to}` only when both set and from <= to) | as `handlePresetChange` / `handleDateChange` today |

Option labels including counts (`Links sent (12)`) keep using `_optionsWithCounts` unchanged.

### Unbounded option lists (Offering)

- The checkbox group is wrapped in `div.gtm-filter-bar__list` with `max-height: 14rem; overflow-y: auto` (the ONLY scroll region; the popover itself is `overflow: visible` so the native date-picker calendar is not clipped).
- If a filter has more than 8 options, a label-hidden `lightning-input type="search"` (`label="Filter <label> options"`, placeholder "Filter options") sits above the list and case-insensitively filters the visible options. Its text is local state only, cleared on close, and never emitted.
- Selected values hidden by the search text MUST be preserved: the group emits only visible values, so on change compute `next = (currentValue minus visibleOptionValues) union event.detail.value`, then order by option order. A Jest test covers this.
- Empty result: visible text "No matches" inside the list.
- Unknown-value behaviour is unchanged (option list is server-supplied; `buildFilterConfig` already keeps URL values as options).

## B.7 Keyboard and focus (all assertions are Jest or QA acceptance)

- Trigger is a real `<button>`: Enter and Space open (native click); the same activates when already open (toggle closed).
- On open, focus moves to the first focusable control in the popover: call `.focus()` on the first of the search input, else the group (`lightning-checkbox-group` / `lightning-radio-group` / `lightning-input` expose `focus()`: UNVERIFIED, so guard with `typeof el.focus === 'function'` and fall back to focusing the popover container `tabindex="-1"`).
- Escape while focus is inside the trigger or popover closes it and returns focus to that trigger (`keydown` on the wrapper). Escape also closes when a nested date picker has not consumed it (whether the base date picker stops propagation is UNVERIFIED; QA checks that one Escape does not both close the calendar AND the popover in a way that loses focus).
- Tab is NOT trapped. Tab order is DOM order: trigger, then its popover controls, then the next trigger. When focus leaves the wrapper (`focusout` with a `relatedTarget` outside the wrapper, or none after a click elsewhere) the popover closes WITHOUT stealing focus.
- Arrow keys: none custom. `lightning-radio-group` uses native radio arrow behaviour; checkbox-group items are Tab/Space. No roving tabindex is built.
- Only one popover open at a time (opening one closes another).
- Outside click closes: attach a document `click` listener while open (add in open, remove in close and in `disconnectedCallback`), test the event path with `event.composedPath().includes(wrapper)` and fall back to `wrapper.contains(event.target)`. Whether a component's `document.addEventListener` and `composedPath` behave the same under Lightning Web Security vs Locker and synthetic vs native shadow is UNVERIFIED (no doc tool); if it fails on staging, drop the document listener and rely on `focusout` alone, which is sufficient because a click on any focusable outside moves focus and a click on plain page background is the only gap (acceptable, note in the PR).
- The result count keeps `aria-live="polite"`. Changing a selection changes the trigger text/`aria-label`, which is the selection announcement; no extra live region.
- Popover: `role="dialog"` (non-modal, no `aria-modal`), `aria-label` = filter label. `aria-haspopup="dialog"` rather than `"true"` because `"true"` announces a menu, which this is not (screen reader behaviour UNVERIFIED; QA spot-checks with VoiceOver).

## B.8 Positioning, clipping, narrow widths (down to 320px)

- The popover is `position: absolute` under its trigger wrapper (SLDS dropdown), `z-index` from the SLDS class (above the datatable header). Width: `min-width: 12rem; width: max-content; max-width: calc(100vw - 1rem)`; More popover `width: 20rem` capped by the same `max-width`. No `@container`, no custom properties (Addendum A static-CSS rule stays; that spec is updated per B.11).
- Viewport clamp: when a popover opens, once in `renderedCallback` guarded by a `_placeOnce` flag, read `getBoundingClientRect()`; if `right > document.documentElement.clientWidth - 8` shift left by the overshoot (inline `left` in px on the popover); if `left < 8` shift right. Reset the inline style on close. This is a one-shot measure, not a ResizeObserver. No ResizeObserver anywhere in the bar.
- Host containers checked on main: the Pages bar is a direct child of `.rlf` (not inside `.rlf-stage`, which is `overflow: hidden`), and the Assessments bar sits in `.ov-filters { display:block }`; neither wraps the bar in an overflow-hidden box. QA must confirm no clipping in the live page; if a clip appears, the fallback is `position: fixed` with coordinates from the trigger rect, closing on scroll and resize (do NOT do this speculatively).
- "More" on narrow widths: there is NO JS width switch. Membership of "More" is static (the `more` flag). The row is `slds-wrap`, so at 320px the four Assessments controls (Status, Readiness tier, Submitted, More) plus "Clear filters" and the count flow to about 2 to 3 lines. This deliberately does not fold primary filters into More at 320px (the BA's idea) so the bar stays free of a ResizeObserver; revisit only if QA finds 320px unusable.
- Trigger `min-width: 0; max-width: 100%`; text ellipsis so a long value cannot force horizontal scroll.

## B.9 Removed / retained CSS and markup

Remove `.gtm-filter-bar__chip*`, `__chips*`, `__pills`, `__pill`, the pills row, the `lightning-pill` and the "Clear all" button. Keep `:host { display:block; min-width:0 }`, the `#747474` count style, and `.gtm-filter-bar__item`-style `min-width: 0`. The Jest static-CSS spec keeps its "no other hex, no `@container`, no `var(--`, no ResizeObserver" assertions and drops the chip-specific ones (B.11).

## B.10 Measurable acceptance criteria

Measure in the browser on `gtm-staging` (never `gtm-prod`), with DevTools, the outer height in px of the `c-gtm-filter-bar` host (`getBoundingClientRect().height`), with NO filter active and again with all filters active, at viewport widths 1078px and 1440px, on Assessments and on Pages. QA records BEFORE numbers on current main first (the BA's numbers are estimates only), then AFTER.
Measure in the browser on `gtm-staging` (never `gtm-dev`), with DevTools, the outer height in px of the `c-gtm-filter-bar` host (`getBoundingClientRect().height`), with NO filter active and again with all filters active, at viewport widths 1078px and 1440px, on Assessments and on Pages. QA records BEFORE numbers on current main first (the BA's numbers are estimates only), then AFTER.

1. Height, no filter active: one control row only (target <= 44px including margins, one line of buttons) at 1078 and 1440 on BOTH tabs. Assessments reduction >= 60% versus the measured BEFORE (the Architect may not tighten this until the BEFORE numbers exist).
2. Height, all filters active: still one row of buttons at 1078 and 1440 (only the "Clear filters" link and count join the same row); NO second pills row; height not more than 8px above the no-filter height.
3. Every existing filter is reachable: Assessments Status (5), Readiness tier (4), Submitted (Any time, 7/30/90, Custom range with From/To), and under More: Readout (5), Offering (all server values), Ready to book; Pages Funnel stage (all 7 including Not opened yet). Counts still appear in the Pages option labels.
4. URL round-trip and deep links: each of these yields the same filter values, button text and rows as today: `c__stage=not_opened`, `c__stage=hot`/`quiet` from the Overview funnel drill-ins, the GUS stage-filter tool effect (`c__stage`), `c__astatus=new` (Overview drill-in), a multi value (`c__astatus=new,contacted`), `c__atier`, `c__areadout`, `c__aoffering`, `c__arange=30` and `c__arange=2026-01-01..2026-01-31`, `c__apreset=true`. Changing a filter writes exactly the params `buildNavigateArgs` produces (multi comma-separated in option order, defaults omitted, unrelated `c__` params preserved byte for byte, replace semantics), and reload restores the state. A value that lives under More (e.g. a deep-linked `c__aoffering`) shows in the "More (n)" trigger text.
5. Result count text (`N assessments`, the Pages count/label) still renders in an `aria-live="polite"` region and updates on each change.
6. Keyboard, on both tabs, mouse unplugged: Tab reaches every trigger; Enter and Space open it; focus lands inside; Space toggles a checkbox and one `filterchange` fires; Escape closes and focus is on that trigger; Tab away closes; no keyboard trap; VoiceOver reads the trigger's name including its value or count and its expanded/collapsed state.
7. Narrow: at 320px, 480px, 768px, 1078px and 1440px there is no horizontal page scroll, no trigger overflows, and the open popover (including More and the date From/To with its calendar) stays fully inside the viewport and is not clipped by any ancestor. Offering list bounded at 14rem with vertical scroll and, above 8 options, the filter-inside input works and preserves hidden selections.
8. "Clear filters" appears only when a filter is active, emits `clear` once, and the consumer returns to the unfiltered state and URL. A Pages stage picked in its popover can be removed via Clear filters.
9. `filterchange` is emitted exactly once per user change with the frozen payloads (B.2).
10. No new hex other than `#747474`; no org ID, username or secret in any committed file.

## B.11 Jest plan

Must pass UNMODIFIED: `gtmFilterUrlState/__tests__/gtmFilterUrlState.test.js`; `gtmReadoutsOverview/__tests__/gtmReadoutsOverview.test.js` (it dispatches `filterchange` and `clear` on the `c-gtm-filter-bar` element and reads `.filters`, so it also proves the frozen API and the unchanged config order; it reads `key/param/type/label/options/multi` only, so the added `more` field is safe); `gtmRepLinkFinder/__tests__/gtmRepLinkFinder.stageFilter.test.js` and `gtmRepLinkFinder.table.test.js` (same style); `gtmAssessmentsTableModel/__tests__/gtmAssessmentsTableModel.test.js` (the `more` flag is additive; it uses `validateFilters` and `readFilterState` only).

Must CHANGE: `gtmFilterBar/__tests__/gtmFilterBar.test.js`. The current specs that assert visible chip buttons, `aria-pressed`, `lightning-pill` rendering/removal, "Clear all" and the labelled chips groups (Addendum A tests "renders one native button per option", "aria-pressed...", "single/multi toggles", "renders one pill per active filter...", "removing the last pill dispatches clear", "Clear all dispatches clear...", "long label stays in one chip", and the chip-specific lines in the static CSS test) are rewritten to the B contract. Retained in spirit: one `filterchange` per change for each type, custom date range emitting `{from,to}` once, result count aria-live, group `aria-label`, compact variant accepted, exact consumer payloads, and the static CSS test minus the `white-space: normal` and `flex: 1 1 8rem` chip assertions (keep hex, `@container`, `var(--`, `min-width: 0`, and NO ResizeObserver). New specs: trigger `aria-expanded/aria-haspopup/aria-label` per B.5 table; open/close on click, Escape returns focus to trigger, focusout closes, only one open; in-button summary (none/one/many/date/toggle/More count); "Clear filters" shown only when active, emits `clear`; multi emits option-ordered arrays and preserves selections hidden by the search input; single closes after pick and re-pick is a no-op; More renders only if a filter has `more`; the config with `more` passes `validateFilters`; no `lightning-pill` and no status row in the DOM.

Apex, permission sets, schema and custom metadata: NONE. This is an LWC-only change (`lwc/gtmFilterBar/*`, one additive line group in `lwc/gtmAssessmentsTableModel/gtmAssessmentsTableModel.js`, this doc). No Apex class is added or edited, so no Apex test run is triggered on any org. `GtmStageFilterAppTool` and the GUS tool surface are untouched (AGENTS.md section 1 contract not in play).

## B.12 Deployment rules

Deploy LWCs only, to `gtm-staging` first, with `sf project deploy start --dry-run` (never `-c`) then the real deploy, then a browser check of every page and deep link in B.10.4 (Pages, Assessments, Overview funnel drill-ins, GUS stage-filter tool). `gtm-prod` is Production and is NOT a deploy target unless the user directly authorises it. Internal Lightning app tabs: no Experience Cloud publish needed. `gtm-staging` provisioning is a prerequisite that the Architect could not verify from the repo; if it does not exist QA cannot sign off.
Deploy LWCs only, to `gtm-staging` first, with `sf project deploy start --dry-run` (never `-c`) then the real deploy, then a browser check of every page and deep link in B.10.4 (Pages, Assessments, Overview funnel drill-ins, GUS stage-filter tool). `gtm-dev` is Production and is NOT a deploy target unless the user directly authorises it. Internal Lightning app tabs: no Experience Cloud publish needed. `gtm-staging` provisioning is a prerequisite that the Architect could not verify from the repo; if it does not exist QA cannot sign off.

## B.13 Developer notes: UNVERIFIED items and what was done (issue `compact-filters`)

No doc, web or browser access was available to the Developer either; nothing below is verified against a live org. Jest (jsdom, synthetic shadow) cannot prove the browser behaviours, so each stays a QA check on `gtm-staging`.

| Item | Handling in code | Status |
|---|---|---|
| `focus()` on `lightning-checkbox-group` / `lightning-radio-group` / `lightning-input` | `renderedCallback` calls `first.focus()` only if `typeof first.focus === 'function'`, else focuses the popover container (`tabindex="-1"`). Search input is preferred as the first target. | UNVERIFIED. QA: on open, focus is visibly inside the popover. |
| Document click and `composedPath` under LWS vs Locker, synthetic vs native shadow | Document `click` listener (added on open, removed on close and in `disconnectedCallback`). "Inside" = `composedPath()` includes the wrapper, OR `event.target` is the host, OR `wrapper.contains(target)`. `focusout` (deferred one tick, closes only when no element in the shadow holds focus) is an independent second closer, so the bar still closes if the click listener misbehaves. | UNVERIFIED. QA: click page background, another control, and inside the popover (must stay open). |
| Base date picker and Escape | The wrapper `keydown` handler closes on Escape and returns focus to the trigger. If the date picker stops propagation, Escape closes only the calendar (desired); if not, both close. No workaround built. | UNVERIFIED. QA: Escape in From/To. |
| VoiceOver with `aria-haspopup="dialog"` | Kept `"dialog"` with non-modal `role="dialog"` and `aria-label`. | UNVERIFIED. QA: VoiceOver reads name, value or count, and expanded state. |

Deviations from Addendum B, all presentation-only:

- More trigger `aria-label` when active is `More (n) filters, n active` (not `More filters, n active`) so it starts with the visible text `More (n)` (B.5 rule wins over the table row). Inactive stays `More filters, none active`.
- A popover is rendered only while open (`if:true`), so there is nothing to reset for the viewport clamp and hidden popovers cost nothing. Popover ids are `gtm-filter-bar-pop-<key>`; More is keyed `__more__`.
- Date presets do not close the popover on pick (B.6 says nothing; Custom needs it open). Single chips and `select` close and return focus, as specified. Re-picking an already selected single value emits nothing and closes.
- `focusout` closes on a deferred tick (not synchronously) so a base-component re-render that momentarily drops focus does not close a multi-select popover.

### B.13.1 Defect found in the real runtime (missed by Jest): popovers did not open

Observed on `gtm-staging` in the real Lightning runtime against d066904: mouse clicks, Enter and programmatic clicks on a trigger all left `aria-expanded="false"` with no `[role=dialog]`; the shadow root saw no mutation and focus ended on nothing. The open state was set and reset inside the same event.

Cause (reproduced in Jest by emulating the runtime, not observed directly): `_open` attached the document `click` listener synchronously, during the very click that opened the popover. That click was still bubbling, so it reached `document` and fired the just-added listener. In the runtime the document-level event is retargeted to an outer host (`c-gtm-readouts-overview`) with a filtered `composedPath()`, so all three "inside" tests (path includes wrapper, target is our host, wrapper contains target) failed, the click was treated as outside, and `_close` ran before LWC re-rendered. The earlier jsdom test passed because jsdom's synthetic shadow retargets to OUR host, which the "target is the host" fallback accepted. A second latent hazard: `focusout` could close the popover while the programmatic focus move was settling.

Fix:
- The document listener is attached on a `setTimeout(0)` AFTER the opening click has finished bubbling (skipped if the popover closed or another opened meanwhile). The "inside" test is unchanged and still tolerant of retargeting.
- A `_settling` flag ignores `focusout` from open until one tick after `renderedCallback` has moved focus; if focus did not land inside (base `focus()` missing or ineffective) the dialog container itself takes focus.
- `_close` and `disconnectedCallback` clear every timer and remove the listener (no leak).

Tests now dispatch real bubbling composed click events that propagate to document, with the document listener wrapped to hand back a retargeted event with an empty `composedPath()`; they fail on d066904 and pass now. They cover click, Enter/Space, More, focus into the popover, same-interaction focusout, outside click, click inside, Escape focus return, one popover at a time, and listener cleanup.

STILL NOT PROVABLE IN JEST: real retargeting and `composedPath` under LWS/Locker, real focus semantics (whether base components take focus), real browser focus/blur ordering on mouse-down, Escape inside the native date picker, and screen readers. QA must re-verify all of these live.

---

# Addendum C: Placement, addable filters, Pages filter set (issue `compact-filters`, follow-up)

Follow-up commit(s) on the SAME branch `agent/issue-compact-filters`. The branch's earlier pieces (Addendum B bar, d066904, 8b2b087, 10aa799) are deployed and validated on `gtm-staging`; this addendum only adds to them. It changes B.1 item 5 (More is now an "add a filter" list, not a stacked panel; supersedes B.5/B.6 "More" wording and the `More (n)` text in B.5) and B.2's "consumers untouched" line (see C.1). Frozen and unchanged: the bar's `@api` props, `filterchange {key,value}` and `clear` payloads and timing, the config schema apart from what C.2/C.3 say, and the `gtmFilterUrlState` URL contract. Deploy rules are unchanged (B.12): `gtm-staging` only, `--dry-run` never `-c`, `gtm-prod` is Production and not a target. No web or doc tool: items marked UNVERIFIED need a staging check.
Follow-up commit(s) on the SAME branch `agent/issue-compact-filters`. The branch's earlier pieces (Addendum B bar, d066904, 8b2b087, 10aa799) are deployed and validated on `gtm-staging`; this addendum only adds to them. It changes B.1 item 5 (More is now an "add a filter" list, not a stacked panel; supersedes B.5/B.6 "More" wording and the `More (n)` text in B.5) and B.2's "consumers untouched" line (see C.1). Frozen and unchanged: the bar's `@api` props, `filterchange {key,value}` and `clear` payloads and timing, the config schema apart from what C.2/C.3 say, and the `gtmFilterUrlState` URL contract. Deploy rules are unchanged (B.12): `gtm-staging` only, `--dry-run` never `-c`, `gtm-dev` is Production and not a target. No web or doc tool: items marked UNVERIFIED need a staging check.

**Amended after the user answered the six Addendum C questions:** added filters are REMEMBERED across reloads (C.2, reverses the earlier session-only recommendation); adding a filter from More AUTO-OPENS its popover (C.2); the Pages tab offers the FULL filter set, each independently addable (C.3); Owner only for View All users; the seven Funnel stage options stay as they are; the new Pages filters apply in All Pages mode only. The ONE contract addition of the whole addendum is the optional `@api storageKey` prop (C.2); `filterchange`/`clear` payloads and timing stay frozen.

## C.1 Placement: bar in the same row as the scope pills, far right

> NOTE: applies to release 1 only. In the end state the toggles are folded into filters and the bar is the sole toolbar at the start of the content; see C.9.4 (supersedes this section).

Decision (user): on Pages and Assessments the bar sits in the SAME row as the scope pills (`All Pages | By Account or Contact`, `All Assessments | By Account or Contact`), aligned to the far right, wrapping below the pills only when there is no room.

Options: (1) a slot in the bar, rejected: the pills are consumer markup and are not the bar's children, so a slot cannot place the bar beside them and would only invert the dependency. (2) A flex toolbar row in each consumer, chosen: the smallest correct change; two wrapper divs and a few CSS lines, no bar API change.

This BREAKS the earlier "consumers untouched" rule (B.2/B.11) and the BA scope's "consumers unchanged" line. It is an explicit, bounded exception: markup wrapper and CSS only, no consumer JS logic, no config or event change.

### Markup and CSS

`gtmRepLinkFinder.html`: wrap the existing `.rlf-mode-toggle` div and the existing `showFilterBar` `c-gtm-filter-bar` in a new `<div class="rlf-toolbar">`; the toggle div keeps its class and children byte for byte (specs query `.rlf-mode-toggle` and its `button`s). The `stageError` paragraph stays OUTSIDE and below the toolbar. Give the bar element `class="rlf-toolbar-bar"`.

`gtmReadoutsOverview.html`: the bar today lives inside `<template if:true={isAllMode}>`, after `loadError`, while the toggle is a level above. Move the `c-gtm-filter-bar` (with all its attributes and handlers unchanged, `class="ov-toolbar-bar"` replacing `ov-filters`) into a new `<div class="ov-toolbar">` that also holds `.ov-mode-toggle`, inside a `<template if:true={isAllMode}>` guard at the bar's position so it still renders only in All mode. `loadError` and the capped `ov-count` paragraph stay below the toolbar. Account mode: toolbar holds the pills only.

CSS (consumer files; both same rules, prefix differs):
- `.rlf-toolbar, .ov-toolbar { display: flex; flex-wrap: wrap; align-items: center; column-gap: 0.75rem; row-gap: 0.25rem; margin-bottom: 0.75rem; min-width: 0; }` (no `overflow: hidden` on the toolbar or any ancestor; the popover must escape it).
- The existing `.rlf-mode-toggle` / `.ov-mode-toggle` `margin-bottom: 0.75rem` moves to the toolbar (set the toggle's to 0 inside the toolbar) so vertical space is not doubled. The toggle gets `flex: 0 0 auto`.
- `.rlf-toolbar-bar, .ov-toolbar-bar { flex: 1 1 18rem; min-width: 0; margin: 0; }` (drops `.ov-filters { margin-bottom: 0.6rem }`).
- No `@container`, no new hex, no media query needed: `flex-wrap` alone wraps the bar under the pills when the remaining width is under 18rem.

### Bar change (one small edit, needed for right alignment)

The consumer cannot style the bar's inner row (shadow DOM), so `gtmFilterBar.html/js/css` gets: root row `slds-grid_align-end` (cluster packs to the right in the host), and `.gtm-filter-bar__count { margin-left: auto }` becomes `margin-left: 0.5rem` (otherwise the auto margin would push the triggers left and strand the count at the edge). Every consumer of the bar is now right-aligned, so no `@api` prop is added.

### Narrow behaviour (QA verifies)

- 1078/1440px: pills left, bar cluster right, one row.
- 768px: pills and bar still share the row if the bar fits its content in the leftover width; else the bar wraps under the pills and stays right-aligned (acceptable).
- 480px: bar wraps under the pills, the trigger cluster itself wraps to 1 to 2 lines.
- 320px: pills row, then bar row(s) of 2 to 3 lines; no horizontal page scroll; triggers `min-width: 0` with ellipsis.

### Popovers at the right edge (supersedes B.8 anchoring)

- Popovers now default to `right: 0; left: auto` under their trigger wrapper (they open LEFTWARD, right edges aligned), instead of `left: 0`.
- Keep the one-shot viewport clamp from B.8 in both directions (shift left if `right > clientWidth - 8`, shift right if `left < 8`), because at 320px a first-in-row trigger on the left can still overflow to the left.
- Width caps unchanged (`max-width: calc(100vw - 1rem)`). QA checks every trigger, the More popover, and the date calendar for the Assessments Submitted filter at 320/480/768/1078/1440px for full containment.
- The Lightning app shell's own scroll container could clip (UNVERIFIED): confirm live. Fallback stays `position: fixed` with trigger-rect coordinates, closing on scroll and resize.

### Files and specs (placement)

Consumer files that change (markup and CSS only): `lwc/gtmRepLinkFinder/gtmRepLinkFinder.html` + `.css`; `lwc/gtmReadoutsOverview/gtmReadoutsOverview.html` + `.css`. Bar files: `lwc/gtmFilterBar/gtmFilterBar.html`, `.js` (root class), `.css`.

Must pass UNMODIFIED: `gtmReadoutsOverview.test.js`, `gtmRepLinkFinder.stageFilter.test.js`, `gtmRepLinkFinder.table.test.js`, `gtmRepLinkFinder.test.js` (a fifth consumer spec; it queries `.rlf-mode-toggle` and its buttons, and asserts `querySelector('lightning-input')` is null in the CONSUMER shadow root; the bar's internals are in its own shadow root so that holds), `gtmFilterUrlState.test.js`, `gtmAssessmentsTableModel.test.js`. None of these assert DOM order between the toggle and the bar (they locate the bar with `querySelector('c-gtm-filter-bar')`, the toggle with `.rlf-mode-toggle` / `.ov-toggle-btn`, and `.ov-count` by class), so the wrapper does not affect them. The Assessments spec asserts `.ov-count` text; that paragraph stays. If any spec does break, that is a contract regression: fix the markup, not the spec.
`gtmFilterBar.test.js` changes only where it asserts root classes, the count's margin or popover `left: 0` (update to the C contract); add specs listed in C.2/C.5.

## C.2 "More" adds filters to the row (Jira style)

Decision (user): "More filters" opens a popover LISTING the extra filters (`more: true`); choosing one ADDS it to the row as its own button; only filters the user cares about show.

### State (kept inside the bar; URL contract untouched)

- `_added`: a Set of filter keys the user has added (component state, `@track`-style replacement, not an `@api`).
- Shown on the row = all filters without `more` (always), UNION `_added`, UNION every `more` filter that currently has an active value in `values`. Consequently a deep link such as `c__aoffering=x` or `c__apreset=true` always shows its button.
- The `values` setter (or `renderedCallback`-free equivalent, to avoid render loops) unions the active `more` keys into `_added` so that after "Clear filters" a button the user was using does not vanish under them. Clear values only; added buttons stay.
- Hidden = `more` filters not shown.

### Persistence: remembered per browser (user decision: "remember, do not forget on reload")

Rejected: a URL param (changes the URL contract and `gtmFilterUrlState`). Chosen: per-browser `localStorage`, guarded, storing ONLY the list of added filter KEYS (never values; values stay in the URL, so a shared link is unaffected and no user data is stored).

- New optional prop: `@api storageKey` (string, attribute `storage-key`, default `''`). With no key the bar keeps added filters in component state only (the previous behaviour, so the bar stays reusable). This is the ONLY contract addition; it changes no event payload. Consumers pass a static string: `gtmRepLinkFinder.html` `storage-key="pages"`, `gtmReadoutsOverview.html` `storage-key="assessments"`. Pages and Assessments therefore never share a list.
- Physical key: `gtm.filterbar.added.<storageKey>`; value: a JSON array of strings, capped at 20 entries.
- Read once when the bar connects (and again if `storageKey` changes), inside `try/catch`: `JSON.parse`, must be an array, keep string entries only; anything else (malformed, blocked storage, private window that throws, `SecurityError`, `localStorage` undefined) yields "nothing remembered" and the bar renders normally.
- Write on every explicit user add or remove (ticking or unticking in More, the x on a button), inside `try/catch` that swallows failure (the in-memory state is already updated, so the UI is right for this session). Clearing values ("Clear filters") does NOT write and does NOT forget: it keeps the added buttons, as already designed (C.2 State). The x on a button removes it AND forgets it.
- What is written: all keys in `_added` PLUS any key already in storage that is unknown to the CURRENT config (see next bullet); implicit adds (a `more` filter that has an active URL value, C.2 State) are unioned into `_added` and are therefore written with the next explicit write, but on their own never trigger a write.
- Remembered key not in the current config: IGNORED for display (no button, no error, no console noise, not counted in More). It is NOT deleted from storage, because the config can be legitimately smaller for a while: Pages has Owner only once the data shows more than one owner, and account mode has only Funnel stage. The only deletion is through the x/untick on a key that is in the config. A key removed permanently from the code is harmless and is dropped naturally by the 20-entry cap.
- Shown set on load = filters without `more`, plus remembered keys that exist in the config and are `more: true`, plus `more` filters with an active value in `values`.
- Fallback tiers: (1) `localStorage`; (2) a module-level in-memory map (`const SESSION_ADDED = {}` keyed by storage key) shared by all bar instances for the life of the page, which survives the bar being destroyed and re-created (the Pages link view step, the Assessments workspace) even when storage is blocked; (3) nothing (component state only). Behaviour of `localStorage` under Lightning Web Security versus Locker, and whether the Lightning shell or Experience Cloud clears it, are UNVERIFIED (no doc tool).
- Scope of memory: per browser profile, not per Salesforce user; two reps sharing one browser profile share the (non-sensitive) key lists. Acceptable; noted.

### More button, list and removal

- Trigger text: `More` plus the number of HIDDEN filters when any (`More (2)`); its `aria-label` says both counts: `More filters, 2 not shown, 1 added`. When nothing is hidden the More button is not rendered (there is nothing to add; removal is via each added button).
- The More popover (`role="dialog"`, `aria-label="Add filters"`, `aria-haspopup="dialog"`/`aria-expanded` on the trigger as in B.7) holds ONE checklist: a `role="group"` labelled "Add filters" with one native checkbox per `more` filter (`lightning-input type="checkbox"`, label = filter label). Checked = on the row. A filter with an active value is checked and disabled with helper text "In use" (remove it with its own x, which also clears it).
- Ticking an unchecked entry adds it and OPENS it (user decision: the new filter's popover opens automatically, with focus inside it):
  1. `_added` gains the key; persist per the Persistence section; nothing is emitted (an empty filter changes no values).
  2. The More popover closes WITHOUT returning focus: call `_close(false)`, never `_close(true)`, so focus is not sent to the More trigger first.
  3. In the same handler call `_open(newKey)`. `_open` already sets `_openKey`, `_focusPending` (focus moves to the popover's first control on the next render), `_placeOnce` (viewport clamp) and `_settling`, and it defers attaching the outside-click document listener with `setTimeout(0)`. The new trigger renders with `aria-expanded="true"` because `_openKey` equals its slot key; the More trigger is not expanded.
  4. Interaction with the real-input closing rules (B.13.2, 68b4de5) that the opening MUST respect: (a) the tick is a real pointer sequence (pointerdown, focusout/focusin, click, change): `_close(false)` clears `_pointerDown`, and `_open` sets `_settling`, so a null-`relatedTarget` `focusout` caused by the More checkbox being removed from the DOM never closes the new popover (only a real Element outside the wrapper closes on `focusout`); (b) the deferred document listener is attached only after the current click finishes, so the tick's own click, still bubbling, cannot count as an "outside click" (the new popover lives in the same wrapper anyway); (c) a stale `_pointerTimer` from the tick may only ever set `_pointerDown` to false, harmless; (d) `_open`/`_close` must not be called from `renderedCallback` and the add must not re-open when a later `values` re-render happens (the open state is `_openKey`, untouched by re-renders).
  5. Focus lands inside the new popover by the existing `renderedCallback` path (`focus()` on the search input or first base component, fallback to the dialog). Announce "Offering filter added" in the visually hidden `aria-live="polite"` line.
  6. Edge: if the added filter's slot cannot render (unknown key), do nothing.
- Unticking an added, empty entry removes it from the row (nothing emitted).
- Each ADDED (not always-shown) button is a normal trigger plus a small adjacent close control: `lightning-button-icon` (`utility:close`, `size="xx-small"`, `alternative-text="Remove <label> filter"`) in the same wrapper, visible only for added filters. Activating it: removes the key from `_added`; if the filter had a value it first emits `filterchange {key, emptyValue}` once (empty per type: `''`, `[]`, `false`), never `clear`, so a hidden filter can never silently filter; then persist the removal and return focus to the More button (or, if More is no longer rendered, to the previous trigger). Announced "Offering filter removed".
- "Clear filters" is unchanged: emits `clear`, clears values, keeps added buttons, and does NOT forget them (nothing is written to storage). Only the x on a button (or unticking it in More) removes it and forgets it.
- Tab order: triggers in row order, each followed by its own close control; More last. `Escape` behaviour as B.7.

### Assessments and Pages config effects

`more` flags stay as B.3 (Assessments: `preset`, `readout`, `offering`); the bar's row order is primaries in config order, then added filters in config order, then More. Pages: see C.3.

## C.3 Pages filter set (user decision: the FULL set, each addable independently, Jira style)

> NOTE: the "All Pages mode only" rule (item 6 of the user answers and the scope-limits bullets below) holds only while the By Account or Contact toggle exists (release 1). In the end state the whole set applies always and Account and Contact are ordinary filters; see C.9.

Data model check. The Pages table is fed by `GtmSavedConfigurationController.getMyConfigurations()` (imperative, no row LIMIT, owner-scoped unless the user holds View All), which selects from `GTM_Saved_Configuration__c`: `Offering__c` (Text 100), `Industry__c` (Text 50), `Company__c`, `Account__c`/`Account__r.Name`, `Contact__c`/`Contact__r.Name`, `Opportunity__c`/`Opportunity__r.Name`/`Opportunity__r.StageName`, `Generated_URL__c`, `Active__c` (Checkbox), `CreatedDate`, `OwnerId`/`Owner.Name`, `Presentation_Stage__c` (Draft and Rep_Direct are excluded by the query). The component holds all of these on `savedLinks`, plus per-link `linkStats` (`visits`, `lastVisitAt`, `funnelStage`) from `getLinkStatsAura`. The stage filter is a client-side intersect with a server id set (`tableRows`). Every filter below is therefore CLIENT-SIDE over data already loaded and composed by AND with the stage set: NO Apex change, no metadata, no permission set, no schema change.

| Filter | Source | Type | Default placement | Param | Notes |
|---|---|---|---|---|---|
| Funnel stage | `GtmLinkStageService` id set (existing; the seven options stay exactly as they are) | single | row | `c__stage` (unchanged) | keeps counts in option labels; NOT `more` |
| Offering | distinct `Offering__c` | multi | row | `c__poffering` | NOT `c__offering` (reserved) |
| Sent | `CreatedDate` | date-range, presets 7/30/90 + custom | row | `c__psent` | |
| Industry | distinct `Industry__c`, label `Industry_Label__c` if present | multi | More | `c__pindustry` | |
| Deal stage | `Opportunity__r.StageName` | multi | More | `c__pdeal` | rows without an opportunity never match while it is active |
| Account | `Account__c` (value = Id, label = `Account__r.Name`) | multi with in-popover search | More | `c__pacct` | Ids because names can contain commas (option values must not); rows without an account never match while active |
| Contact | `Contact__c` (value = Id, label = `Contact__r.Name`) | multi with in-popover search | More | `c__pcontact` | same rule |
| Link status | `Active__c` | single: Active / Turned off | More | `c__pactive` | |
| Last visit | `linkStats.lastVisitAt` | date-range presets 7/30/90 + custom | More | `c__plast` | offered only when `linkStats` exists for every row (the result carries a `truncated` flag: if true, omit the filter rather than show a partial one; Developer verifies the flag's meaning); never-opened links are excluded while a range is active (Funnel stage "Not opened yet" already isolates them) |
| Owner | `OwnerId` (value) / `Owner.Name` (label) | multi | More | `c__powner` | ONLY in the config when the loaded data has more than one distinct owner (i.e. View All users); a normal rep never sees it (user: correct) |

Independence: each filter is its own `more` flag; adding, removing or clearing one never requires or affects another (AND semantics, C.4). Default on the row: Funnel stage, Offering, Sent (recommended, user did not object). Everything else is in the More list, shown in the table's order.

Considered and NOT offered, with reason:
- Has an assessment / opened or not: already answered by Funnel stage (`Assessment started/submitted`, `Prospect engaged`, `Not opened yet`), which stays as is; a second control would duplicate it with different semantics.
- Source or target platform: the `GTM_Saved_Configuration__c` fields folder has no such field; the only place it could live is the `Config_Payload__c` JSON blob, which we do not parse client-side. Would need a schema or Apex change: out of scope.
- Estimated value (`Estimated_Value__c`): needs a numeric-range filter type the bar does not have. `Is_Synthetic__c`, `Presentation_Stage__c`, `Company__c` text: internal or free text, not useful as rep filters.
- Readout status per request: needs Apex; would force a full Apex test run on the production-type `gtm-prod`. Not in this change.
- Readout status per request: needs Apex; would force a full Apex test run on the production-type `gtm-dev`. Not in this change.

Consumer wiring (`gtmRepLinkFinder.js`):
- Extend the config from the single `STAGE_URL_CONFIG` entry to the full list above; build options from `savedLinks`/`linkStats` after they load. Values already in the URL must be kept as options even before data loads (label falls back to the raw value until names are known), exactly like `buildFilterConfig`'s `extraOfferingValues`, so `readFilterState` never drops a deep link. Values must not contain commas.
- Call the URL helper (`readFilterState`, `buildNavigateArgs`, `mergeLocationState`) with the FULL Pages config in both modes so a mode switch never wipes `c__p*` params; APPLY and DISPLAY the extra filters in All Pages mode only. In "By Account or Contact" mode the bar receives the Funnel-stage entry only (`filterConfig` gated on `isAllMode`), and `filterValues` contains only `stage`. This keeps the account or contact view as it is today (user: correct).
- Client filtering: `tableRows` = stage set ∩ Offering ∩ Sent ∩ Industry ∩ Deal ∩ Account ∩ Contact ∩ Link status ∩ Last visit ∩ Owner (an inactive filter matches everything). `filterResultCount` stays `tableRows.length` in All mode; `filterResultLabel` unchanged.
- `handleFilterChange` currently ignores keys other than `stage`; it must accept the new keys and write them through `buildNavigateArgs` (replace) like the Assessments consumer.
- Unchanged: `GtmStageFilterAppTool`, `gtmGusUtility` (`GTM_Pages: ['c__stage']`; the assistant can still only set the stage), Overview drill-ins (`c__stage`). Developer must grep that no other page already uses a `c__p*` param name above (only `c__panel` and `c__pgStage` exist elsewhere on main; no clash).
- `gtmRepLinkFinder.test.js` stays unmodified in its existing assertions; new behaviour is tested in the stage-filter and table specs (C.5).

## C.4 How filters combine

- Filters AND together across filters: a row must match every active filter (Status new AND Offering X AND Submitted in the last 30 days).
- A multi-select filter (Assessments Status, Readiness tier, Readout, Offering; Pages Offering, Industry, Deal stage, Account, Contact, Owner) allows several values, OR within that filter. Its popover STAYS OPEN while the user ticks (under the Apply model, C.8, nothing is emitted until Apply); it closes on Escape, on Tab to an element outside the bar, on an outside click, or when another popover opens.
- Single-select filters that pick one value (Pages Funnel stage and Link status, i.e. `chips` single and `select`) CLOSE the popover on pick. CORRECTION to the first draft of this addendum: date-range filters (Submitted, Sent, Last visit) do NOT close on preset pick, because Custom range needs From/To to be entered in the same popover (B.13.2: "Multi, toggle, date presets and search never close it"). Ready to book (toggle) also stays open.
- The result count and "Clear filters" reflect ALL active filters together; Clear filters resets every value at once and keeps the added buttons (C.2). The URL carries every active value and nothing else.
- Live findings from the real-input browser test on `gtm-staging` against the build BEFORE 68b4de5 (recorded as found):
  - CONTRADICTED IN BROWSER (design said selecting works and multi-select stays open): with a real click, choosing an option did nothing (no `change`, so no URL change, trigger label, Clear filters or count) and multi-select popovers closed after every pick. Both defects are fixed in 68b4de5 (B.13.2), which is deployed to `gtm-staging`; a real-input RE-TEST of the fix is still awaited, so this stays open until QA records it.
  - CONFIRMED in browser: stacking of Status, Readiness tier and the More filters works (AND across filters); the closed bar stayed one row of 36px; after "Clear filters" the URL was clean (no `c__a*` params left).
  - Any further contradiction the re-test finds is added here as `CONTRADICTED IN BROWSER: <what actually happens>` and is a defect against B/C, not a doc edit.

## C.5 QA measurements and Jest for the follow-up

QA measures on `gtm-staging` (never `gtm-prod`), both tabs, at 1078px and 1440px, BEFORE (current branch build) and AFTER:
QA measures on `gtm-staging` (never `gtm-dev`), both tabs, at 1078px and 1440px, BEFORE (current branch build) and AFTER:
1. Placement: the bar's row relative to the scope pills. Bar cluster right edge within 16px of the content's right edge and vertical centre within 8px of the pills' centre when it fits; wraps below at the C.1 breakpoints.
2. Total vertical space of pills plus bar: outer height in px from the top of the pills to the bottom of the bar (`getBoundingClientRect`). AFTER is at most the pills height plus 8px at both widths on both tabs, and still one row with every filter active (including all Pages filters added).
3. Popovers open leftward and stay inside the viewport for every trigger and the More list at 320/480/768/1078/1440px; date calendar contained.
4. Add-a-filter flow with REAL input (mouse and keyboard, not scripted clicks; scripted clicks hid the 68b4de5 defects): open More, tick Offering, More closes, the Offering popover OPENS with focus inside it and stays open (does not flash closed), `aria-expanded="true"` on the Offering button and `false` on More; pick a value: one `filterchange`, URL updated; Escape returns focus to the Offering button; x removes and clears it; a deep link with an active `more` value shows its button without using More.
5. REMEMBERED filters, live: add Industry on Pages, reload the page: the Industry button is still on the row (empty); Assessments has its own separate list; the x removes it and after reload it stays gone; "Clear filters" keeps added buttons and after reload they are still there; open in a private window and with site data blocked: the bar renders normally, just without memory (and the in-memory tier survives leaving and re-entering the link view step); two tabs behave sanely; storage holds only key names (inspect Application > Local Storage: no values, no ids beyond filter keys).
6. Pages All Pages mode: each new filter works alone and stacked with Funnel stage and the others; count equals table rows; Owner appears only for a View All user with data from more than one owner; account or contact view shows Funnel stage only; a deep link such as `c__stage=not_opened&c__poffering=x&c__pindustry=y` restores all three; `c__p*` params survive switching All Pages to By Account or Contact and back.
7. URL round-trip and all B.10.4 deep links still work; `filterchange` once per change; `clear` once; GUS stage-filter tool and Overview drill-ins unchanged.

Jest, new or changed (bar spec `gtmFilterBar.test.js`; Pages specs `gtmRepLinkFinder.stageFilter.test.js` and `gtmRepLinkFinder.table.test.js` receive ADDITIONS only; `gtmRepLinkFinder.test.js` must pass unmodified in its existing assertions):
- Bar, storage: `storage-key` set reads `gtm.filterbar.added.<key>` and shows remembered `more` filters; no `storage-key` never touches storage; add and remove write the expected JSON (keys only, no values); Clear filters does not write; a throwing `localStorage` (getter throws, `getItem` throws, `setItem` throws, invalid JSON, non-array JSON) renders the bar normally with no exception, and the session fallback (module map) restores the added set after destroy and re-create; unknown remembered keys are ignored for display, not counted in More, and preserved in the next write; the 20-entry cap.
- Bar, add flow: ticking a More entry adds its trigger, closes More without focusing the More trigger, OPENS the new popover (`aria-expanded="true"`, More `false`), focus lands inside, nothing is emitted, and (using the B.13.2 real-event-order emulation: pointerdown, focusout to the container, focusin, click, change, null-`relatedTarget` focusout of the removed checkbox) the new popover is still open afterwards and a later `values` re-render does not close or re-open it; the deferred document listener does not treat the tick's own click as an outside click.
- Bar, remaining: shown-set logic (primaries, added, active `more` always shown); More text and aria for hidden and added counts; More not rendered when nothing is hidden; x on an active filter emits one empty-value `filterchange` never `clear`, and removes and forgets; Clear filters keeps added buttons; deep-link active `more` value renders its button and its checkbox disabled ("In use"); root class and right-anchored popover per C.1.
- Pages: config validates with `validateFilters` (no reserved or duplicate params; `c__offering` rejected); each new filter narrows `tableRows` and the count; filters AND with the stage set; Owner is absent with one owner and present with two; deep link restores values and keeps unknown-until-loaded ids; account mode passes only the stage entry and `filterValues` only `stage`; `c__p*` params survive a mode switch.
- Unmodified, must pass: `gtmReadoutsOverview.test.js`, `gtmFilterUrlState.test.js`, `gtmAssessmentsTableModel.test.js`, `gtmRepLinkFinder.test.js` (existing assertions), and the existing assertions of the two Pages specs above.

## C.6 Developer file list for Addendum C (worktree `/Users/isiwintr/Documents/Workbench/worktrees/issue-compact-filters`)

1. `force-app/main/default/lwc/gtmFilterBar/gtmFilterBar.html`, `gtmFilterBar.js`, `gtmFilterBar.css`, `__tests__/gtmFilterBar.test.js`: add-filter state, x control, More checklist, right alignment, right-anchored popovers, count margin, auto-open on add, and the new optional `@api storageKey` with guarded `localStorage` plus the module-level fallback map. This prop is the only contract addition.
2. `force-app/main/default/lwc/gtmRepLinkFinder/gtmRepLinkFinder.html` (toolbar wrapper; `storage-key="pages"` on the bar), `gtmRepLinkFinder.css` (toolbar), `gtmRepLinkFinder.js` (full Pages config, client filtering over `savedLinks` and `linkStats`, `filterValues`, `handleFilterChange` for the new keys, mode-gated config, URL wiring), and additions to `__tests__/gtmRepLinkFinder.stageFilter.test.js` and `__tests__/gtmRepLinkFinder.table.test.js`. `__tests__/gtmRepLinkFinder.test.js` unmodified. If the filter-option or row-matching logic grows, put it in a NEW pure helper `lwc/gtmRepLinkFinder/gtmRepLinkFilterModel.js` with its own `__tests__/gtmRepLinkFilterModel.test.js` (preferred over enlarging the component, mirroring `gtmAssessmentsTableModel`).
3. `force-app/main/default/lwc/gtmReadoutsOverview/gtmReadoutsOverview.html` (toolbar wrapper; `storage-key="assessments"` on the bar) and `gtmReadoutsOverview.css` (toolbar). Its spec unmodified.
4. `force-app/main/default/lwc/gtmAssessmentsTableModel/gtmAssessmentsTableModel.js`: none (its `more` flags already exist).
5. No Apex, no metadata, no permission set, no schema, no `gtmFilterUrlState` change. No org IDs, usernames or secrets committed.

## C.7 Questions still the user's to decide

(See also C.8.10 for the Apply-model questions.)

1. Last visit as a Pages filter depends on `linkStats` being complete (the result has a `truncated` flag). Keep it in the More list, or drop it to avoid ever showing a partial result?
2. Account and Contact as filters use ids as option values and can be long lists (searchable inside the popover). Both wanted, or Account only?
3. Should the remembered list be shared per browser (as specified) or should a "Reset filters layout" action exist to forget everything at once? The x per button already forgets one at a time; a reset is not in this design unless asked.
4. Default row on Pages is Funnel stage, Offering, Sent. Confirm, or name a different default.

## C.8 Apply model for multi-select and custom date popovers (user input; PREFERRED UX)

User input: "Salesforce popovers seem to have an apply button, maybe you need that." Recorded as the PREFERRED interaction for the multi-select and custom-range popovers. It supersedes the C.4 sentences "a multi-select popover stays open while ticking" (still true, but nothing is emitted while ticking) and "date-range presets do not close on pick" (presets now apply and close, below). Sequencing is in C.8.9.

### C.8.1 Rationale

- Assessments loads rows server-side: apply-on-pick fires one Apex query, one re-render and one URL `Navigate(replace)` per tick. A local draft means ONE query per intent.
- The two real-runtime defects (68b4de5, f7a20d8; B.13.2/B.13.3) were both about the popover being torn down or re-rendered in the middle of an interaction caused by `filterchange` re-rendering the consumer and the bar. With a draft, ticking emits nothing, so no consumer re-render or fetch can occur mid-interaction. HONEST LIMIT: this removes the emit-then-re-render cycle; it does NOT by itself prevent a spurious close from the outside-click or focus closers. With a draft, a spurious close silently discards the user's ticks, so those closers must stay correct (or be removed, C.8.9).
- Salesforce's own filter panels and list-view filters use Apply or Done rather than firing on each selection (working knowledge; no doc tool, so UNVERIFIED wording).

### C.8.2 Which controls

| Control | Model |
|---|---|
| `chips` multi (Assessments Status, Readiness tier, Readout, Offering; Pages Offering, Industry, Deal stage, Account, Contact, Owner) | LOCAL DRAFT, Apply button |
| Custom date range From/To (Submitted, Sent, Last visit) | LOCAL DRAFT, Apply button |
| Single chips and `select` (Pages Funnel stage, Link status), date PRESET radios (Any time, 7/30/90) | apply-on-pick, closes on pick (unchanged) |
| Ready to book toggle | immediate, popover stays open (unchanged) |
| "Custom range" radio | reveals From/To and stays open; only Apply emits the `{from,to}` |
| More checklist (C.2) | exempt: it changes the layout, not the data; adds immediately, no Apply |

Frozen contract unchanged: Apply emits exactly ONE `filterchange {key, value}` with today's shape (multi = `string[]` in option order, `[]` = remove; custom range = `{from,to}` ISO, from <= to). "Exactly once per user change" now means once per Apply; nothing is emitted while ticking; an Apply whose draft equals the applied value emits nothing and just closes. `clear` unchanged.

### C.8.3 Draft state

- `_draft`: a map `{ [key]: value }`, held only while that popover is open; never persisted (persistence in C.2 stores filter KEYS only).
- Initialised on open from the APPLIED `values[key]` (copy, option order; custom range from/to from a `{from,to}` value or empty). So a deep link `c__astatus=new,contacted` opens with those two ticked.
- While open, an external `values` change (e.g. deep-link navigation) refreshes the draft only if the draft is not dirty; a dirty draft is never overwritten mid-edit.
- Discarded on every close except Apply. The popover for a newly added filter opens with an EMPTY draft (C.8.7).
- The trigger text and `aria-label` (B.5 table) always show the APPLIED value only, never the draft.

### C.8.4 Layout inside the popover

Bottom of the popover, below the (scrollable, bounded) list, separated by a 1px top border using an SLDS utility (`slds-border_top`) with `slds-m-top_small slds-p-top_x-small`:

```
[ Select all shown ]   (only when the option list has more than 8 options; left, base link style)
[ Clear ]        Unapplied changes     [ Apply ]
```
Left: `Clear` (native `slds-button slds-button_neutral`). Middle: the dirty cue (below). Right: `Apply` (native `slds-button slds-button_brand`). One row, `slds-grid slds-grid_vertical-align-center`, `slds-wrap` so at 320px the buttons wrap under each other and the popover stays inside the viewport (B.8 clamp). Native `<button type="button">` elements are used instead of `lightning-button` because `aria-label` on `lightning-button` is UNVERIFIED and the chips already use native buttons.

- `Clear` empties the DRAFT only (nothing emitted). To remove the applied value the user presses Apply with an empty draft, which emits `[]`.
- `Apply`: if the draft differs from the applied value, emit once, then close and return focus to the trigger (`_close(true)`, the popover DOM disappears so focus must move); if identical, close without emitting. Custom range with an incomplete or reversed range: do not close and do not emit; show an inline `role="alert"` message ("Choose a start and end date; start on or before end") next to the inputs (this replaces the silent "emit only when both set" rule of the old per-keystroke behaviour).
- Unsaved-changes cue (judged useful because outside-click discards): when dirty, show the text "Unapplied changes" in `#747474` (the only allowed hex) between Clear and Apply. Not colour-only (it is text), inside a `slds-assistive-text`-free visible span; no extra live region (the Apply announcement below is enough). The trigger itself does NOT change while dirty.
- After Apply, announce in the existing visually hidden `aria-live="polite"` line: "Status filter applied, 2 selected".

### C.8.5 Keyboard and accessible names

- Tab order inside the popover: search input (if present), Select all shown (if present), the checkbox group or radio group or date inputs, Clear, Apply; then the next trigger. Tab is not trapped (B.7).
- Space toggles a checkbox (draft only). Enter on `Apply` activates it (native button). Enter inside the checkbox group does nothing extra (no implicit submit, to avoid surprising applies). Enter in the search input does nothing.
- Escape: DISCARDS the draft, closes, returns focus to the trigger (same key handling as B.7).
- Names: Apply `aria-label="Apply Status filter"` (starts with the visible text "Apply", label-in-name); Clear `aria-label="Clear Status selection"` (draft only); Select all shown `aria-label="Select all shown Offering options"`. The dialog keeps `aria-label` = the filter label, so a screen reader hears "Status dialog ... Apply Status filter".

### C.8.6 Search, "Select all shown" and the hidden-selection rule

- The in-popover search filters what is VISIBLE (local state, never emitted, cleared on close) exactly as B.6.
- "Select all shown" adds every currently visible option value to the DRAFT (it never selects hidden options). It appears only when the list has more than 8 options. It is not a toggle; "Clear" empties the draft.
- The hidden-selection preservation rule from B.6 is kept and now operates on the draft: the checkbox group emits only visible values, so on its change `draft = (draft minus visibleOptionValues) union event.detail.value`, ordered by option order. Apply emits the WHOLE draft (visible and hidden), one payload.
- URL length risk: unbounded lists (Offering, Account, Contact) with "Select all shown" can build a very long `c__` param. Cap a multi draft at 50 values; beyond that show "Choose up to 50" and do not add more. The cap is a default the user can change (C.8.10).

### C.8.7 Interaction with Clear filters, the x, More and auto-open

- "Clear filters" (link, outside every popover): a click counts as an outside interaction, so an open popover closes and its draft is discarded, then `clear` is emitted and applied values are cleared (unchanged behaviour). The next open initialises from the now-empty `values`.
- The x on an added button: discards that popover's draft if open, removes and forgets the filter, and emits one empty-value `filterchange` if it had an applied value (unchanged C.2 behaviour). No Apply is involved.
- Opening another trigger while one is dirty discards the first draft (same as outside click). Documented, not warned.
- More add-a-filter flow: ticking a More entry adds the filter and auto-opens its popover with an EMPTY draft and focus inside (C.2 rules for `_close(false)`, `_open(newKey)`, `_settling` and the deferred document listener are unchanged). The user picks values, presses Apply, and only then does anything reach the URL. A newly added filter that is then closed without Apply stays on the row (remembered per C.2) with no value.
- Single-select and preset radios and the toggle keep their immediate emit and existing close behaviour, so they may emit while other popovers hold no draft; only one popover is ever open.

### C.8.8 Escape and outside-click decision

Recommend DISCARD for Escape, outside click, Tab-away and opening another trigger. Reason: predictable, matches a dialog-with-Apply, and avoids an unintended query when a stray click closes the popover (the very failure class of B.13.2/B.13.3). Alternative (not recommended): apply the draft on outside click, like Jira's instant filters; it reintroduces an emit from the outside-click path and any spurious close would fire a query. See C.8.10.

### C.8.9 Sequencing and fallback

- These changes belong to Addendum C on the same branch. f7a20d8 (inside-interaction flag) is being deployed and tested live now. The Apply model is BUILT AFTER that live test, together with the rest of Addendum C.
- If f7a20d8 fails a third time, the Apply model becomes the FALLBACK design and is built immediately, in a stricter form: remove the document outside-click closer entirely (the popover then closes only on the trigger toggle, Escape, Apply, the x, another trigger, and a `focusout` whose `relatedTarget` is a real Element outside the wrapper), and add the temporary diagnostics named in B.13.3 before changing further logic. With no outside-click closer, no ordering race can discard or close a draft.

### C.8.10 Questions still the user's to decide

1. Should an outside click APPLY the draft instead of discarding it (not recommended, C.8.8)?
2. Cap on multi-select values: 50 by default (URL length). Change it?
3. Is "Unapplied changes" text the right cue, or should it be omitted (a plain, uncued Apply)?
4. Should the date PRESET radios (7/30/90) stay one-click (as specified) or also use Apply?
(Earlier open items C.7 remain, except that the remembered-filter and auto-open answers are settled.)

### C.8.11 Jest, QA and Developer files for the Apply model

Jest (`gtmFilterBar.test.js`). Specs that assert a `filterchange` per tick for multi and per keystroke for custom range must CHANGE to tick then Apply (this includes the B.13.2/B.13.3 real-event-order regressions, which keep their event emulation but assert emit-on-Apply). New specs:
- ticking two values emits nothing; Apply emits ONE `filterchange` with both values in option order, closes, and returns focus to the trigger; a no-change Apply emits nothing and closes;
- draft initialised from `values` (deep link); trigger text and `aria-label` show the applied value while a different draft is ticked; an external `values` change refreshes a clean draft and never overwrites a dirty one;
- Clear empties the draft only; Apply after Clear emits `[]`;
- Escape, outside click, Tab-away (real Element `relatedTarget`) and opening another trigger discard the draft and emit nothing; Clear filters and the x discard and behave as C.8.7;
- hidden-selection preservation with the search text, "Select all shown" (adds visible only, appears above 8 options), the 50-value cap;
- custom range: invalid or reversed range shows the alert and does not emit or close; valid emits one `{from,to}`; the presets emit and close on pick; "Custom range" radio reveals inputs and does not emit;
- toggle and single-select stay immediate;
- More add: the auto-opened popover has an empty draft and nothing is emitted until Apply;
- names: `aria-label` "Apply Status filter", "Clear Status selection", the "Unapplied changes" cue only when dirty.
Unmodified must-pass specs: `gtmReadoutsOverview.test.js`, `gtmRepLinkFinder.test.js` (existing assertions), both other Pages specs' existing assertions, `gtmFilterUrlState.test.js`, `gtmAssessmentsTableModel.test.js` (they dispatch `filterchange` on the bar element and never click inside it, so they are unaffected).

QA (real mouse and keyboard, on `gtm-staging`): tick two Status values and confirm the URL, the trigger text, the count and the network (no Apex `getAssessmentPage` call) are unchanged until Apply; Apply writes both values in ONE URL change and ONE server query, and the popover closes with focus on the trigger; Escape and an outside click discard (reopen shows the applied values, no query fired); Clear then Apply removes the filter; Offering search plus "Select all shown" plus Apply keeps hidden selections; custom range needs a valid pair and Apply; Pages Funnel stage still applies on pick; a deep link opens with the draft equal to the URL values; measure that the popover buttons row stays inside the viewport at 320/480/768px and that bar heights (C.5) are unchanged.

Developer files (Apply model): `force-app/main/default/lwc/gtmFilterBar/gtmFilterBar.html`, `gtmFilterBar.js`, `gtmFilterBar.css`, `__tests__/gtmFilterBar.test.js` only. No consumer, no `gtmFilterUrlState`, no Apex, no metadata, no permission-set change. It adds no `@api`; the frozen `filterchange`/`clear` contract holds, and `storageKey` (C.2) remains the only contract addition of Addendum C.

## C.9 Scope toggles folded into the filter model (user insight; SUPERSEDES C.1 placement-beside-pills and C.3 "All Pages mode only" in the end state)

User: "the All Assessments / All Pages and By Account or Contact on both are just another set of filters; it's all just filtering the data on the page." Decision: ONE toolbar, no separate pills row. Staged, because the by-account views hold real actions that a filter cannot reproduce (C.9.1) and because folding Assessments needs Apex (C.9.2). The frozen `filterchange`/`clear` payloads, the props (plus the C.2 `storageKey`), and the `gtmFilterUrlState` contract are unchanged; legacy-param mapping is done in the CONSUMERS before `readFilterState` (the reserved-param list in `gtmFilterUrlState` keeps rejecting `c__browseMode`, `c__rafAccountId`, `c__rafContactId`, `c__rlf*` as filter params, which is why the mapping cannot live in the helper). Facts below were read on `origin/main` 0538a34 (which is ahead of this worktree's base; the Developer must rebase onto current `origin/main` before starting, because `gtmRepLinkFinder.html` already differs by a line).

### C.9.1 What each view really does

**Pages (`gtmRepLinkFinder`), "All Pages" (`isAllMode`, default).** One datatable of the rep's links from `getMyConfigurations()` (owner-scoped unless View All, Draft and Rep_Direct excluded, no LIMIT, all rows client-side, client sort, no pagination), columns Account/company (button), Contact, Offering, Opportunity, Funnel stage, Visits, Last visit, Status (text only), Saved, Owner (View All only); `linkStats` from `getLinkStatsAura`; the Funnel-stage bar; a single row action `Open` (disabled for rows with no account). `Open` calls `openLinkRow`, which sets `rlfMode = 'account'` and drills into that link, so today the ONLY route from the table to a link's detail is through the account view.

**Pages, "By Account or Contact" (`isAccountMode`).** (1) A unified Account/Contact search (`searchAccountsAndContacts`, searches every Account and Contact in the org, including ones with no links) with a crumb trail; (2) after an Account: a "Which Contact is this for?" list with link counts (`getContactsWithLinks`), or a Contact pick goes straight on; (3) a "Which link?" list where EACH link row carries actions: an Active/Inactive toggle (`setActive`, DML; the ONLY place in the UI to turn a link on or off), Copy link, New password (`regeneratePassword`, DML); (4) the view step for one link: Engagement Link box with Copy, Password box with Show (`getPassword`, on demand) / Copy / New password, "Assessment submission" with View readout / Generate Readout (`generateReadoutForRequest`, DML) and the embedded `c-gtm-assessment-detail`, an inline `c-gtm-readout-workspace`, and "Preview the link" (embedded `c-gtm-configurator`). The Funnel-stage bar applies to the contact list. URL state: `c__rlfAccountId`, `c__rlfContactId`, `c__rlfLinkId`, `c__rlfMode`, `c__rlfShowPreview`, `c__rlfShowWorkspace`, `c__rlfPwRevealed`; browser back and refresh restore it. The `modechange` event feeds `gtmPageBrowser`'s header subtitle (`linkFinderMode`).

**Assessments (`gtmReadoutsOverview`), "All Assessments" (`isAllMode`, default).** Server-paged datatable (`getAssessmentPage` with `AssessmentQuery`: status, tier, readout, offering, range, preset, sort, offset, pageSize; infinite loading; 10,000 cap), the filter bar, a row click that opens `c-gtm-readout-workspace` (`c__assessmentRequestId`, `c__readoutId`, `c__offeringKey`), and the Rep-Direct modal (`c__repDirectId`).

**Assessments, "By Account or Contact" (`browseMode = 'account'`, `c__browseMode=account`).** `gtmReadoutAccountFinder`: the same unified search, a contact list with request counts (`getContactsWithRequests`), a "Which assessment?" request list, then a `selectrequest` event that opens the SAME workspace as an All-view row click. Filters, bar and table do not apply in this mode (their params are preserved and ignored). URL: `c__browseMode`, `c__rafAccountId`, `c__rafContactId`.

**Classification.**
- Pure filtering (a filter can reproduce it): narrowing the list to an Account or a Contact, on both tabs; the Assessments account view entirely (it only finds a request and opens the same workspace).
- NOT filtering, must survive as actions or a different presentation: Pages link ACTIONS (Active toggle, Copy link, New password); the Pages link DETAIL view (password reveal, Generate/View readout, assessment detail, workspace, preview); the Miller-column navigation itself (redundant once the list is filterable); the contact-first "N links per contact" overview (a grouped presentation).
- Behaviour a filter changes: the search reaches ALL org Accounts and Contacts (including ones with no links) while a filter's options come from the loaded data, so an account with no links cannot be picked (it would have shown "No saved links found").
- Assessments account/contact filtering is NOT available client-side (server-paged, capped) and `AssessmentQuery` has NO account or contact member (`GtmAssessmentListController`): it REQUIRES AN APEX CHANGE (new `AssessmentQuery` members and WHERE clauses, test class updates), which forces a full Apex test run on the production-type `gtm-prod`, so it needs its own scope and the user's direct authorisation. Rows already carry `accountId`/`contactId`.
- Assessments account/contact filtering is NOT available client-side (server-paged, capped) and `AssessmentQuery` has NO account or contact member (`GtmAssessmentListController`): it REQUIRES AN APEX CHANGE (new `AssessmentQuery` members and WHERE clauses, test class updates), which forces a full Apex test run on the production-type `gtm-dev`, so it needs its own scope and the user's direct authorisation. Rows already carry `accountId`/`contactId`.

### C.9.2 Options and recommendation

| Option | What | Trade-offs |
|---|---|---|
| A. Filters plus row actions plus detail view (RECOMMENDED) | Account and Contact become ordinary searchable filters (More list, or on the row) available always; the toggle, tile/Miller columns and crumbs go; link actions become row actions; `Open` goes to the existing link detail with one Back button that returns to the filtered list | Smallest UI, one mental model, reuses the bar; loses the contact-first grouped overview and org-wide zero-link account search; requires moving the Active toggle, Copy link and New password into row actions or the detail view |
| B. A single-select "View" filter: All / Grouped by account or contact | Keeps a grouped presentation as a filter value | Reproduces Miller columns inside the list, a lot of new UI; a "filter" that changes layout is confusing |
| C. A Jira-style "Group by" control (Account / Contact) | Groups rows in the table | Datatable has no grouping; would need a custom grouped table; sorting by the Account and Contact columns (already sortable) covers most of the need |

Recommend A. If the user wants the grouped overview later, add C as a separate follow-up, not now.

Pages, in the end state:
- Row actions on the datatable (native row-action menu, the same mechanism as today's `Open`): `Open`, `Copy link`, `New password`, and `Turn off` / `Turn on` (calls `setActive`, then updates the row and refreshes stats). The row-action handlers reuse the existing `handleCopyLink`, `handleRegeneratePassword`, `handleToggleActive` code. The Status column keeps showing the state.
- `Open` navigates to the existing detail (view) step, unchanged content, with the bar hidden (as `showFilterBar` already is when a link is selected) and one `Back to links` button in place of the crumbs; going back restores the same filters from the URL.
- Account and Contact filters: options from the loaded `savedLinks` (Account: value = Id, label = name; Contact likewise), searchable inside the popover (>8 options), multi, in More by default. `c__pacct`, `c__pcontact` (C.3, unchanged).
- Full Pages set ALWAYS applies (C.3 item 6 no longer holds in the end state): Funnel stage, Offering, Sent, Industry, Deal stage, Account, Contact, Link status, Last visit, Owner (View All only). The stage id-set intersect now also runs in the former account view (there is no separate account view).
- `gtmPageBrowser`'s `modechange` handler and `linkFinderMode` subtitle logic become dead: the subtitle must no longer depend on mode (Developer removes the `onmodechange` binding and reads the header subtitle from the selected-link state only); this is one more consumer file.

Assessments, in the end state:
- After the Apex change is authorised: Account and Contact filters (`c__aacct`, `c__acontact`, options served like `offeringOptions` from the server, searchable), the toggle, `gtmReadoutAccountFinder` and `browseMode` removed; the workspace opens exactly as today.
- Until then the Assessments toggle STAYS, in the same toolbar row (C.1 unchanged for Assessments). This leaves the two tabs temporarily inconsistent; that is the price of not touching Apex.

### C.9.3 Deep-link and drill-in mapping (nothing may break)

| Producer / param | Today | After the fold |
|---|---|---|
| Overview drill-in `handleAccountClick` (`gtmOverview.js`), any bookmark: `c__rlfAccountId=<id>` alone | forces account mode, lists that account's contacts | consumer maps to Account filter `c__pacct=<id>`; the list shows that account's links; the URL is rewritten (replace) to `c__pacct`. Until release 2 (toggle retained) behaviour is UNCHANGED |
| `handleContactClick`: `c__rlfAccountId` + `c__rlfContactId` | account mode, contact's links | Account and Contact filters (`c__pacct`, `c__pcontact`) |
| `c__rlfAccountId` + `c__rlfContactId` + `c__rlfLinkId` (`writeDrillStateToUrl`, saved and shared links, `openLinkRow`) | restores the link view step | UNCHANGED: a `c__rlfLinkId` present means "open this link's detail"; the three params stay the detail-view deep-link contract. Additionally `c__rlfShowPreview`, `c__rlfShowWorkspace`, `c__rlfPwRevealed` unchanged |
| `c__rlfMode=all` / absent | All Pages | ignored (no mode exists) and no longer written; still tolerated on read forever |
| `c__rlfMode=account` (no ids) | empty account search | ignored: the plain filtered list with no account chosen |
| `c__stage` (Overview funnel drill-ins `hot`/`quiet`, GUS `GTM_Pages: ['c__stage']`, `GtmStageFilterAppTool`) | stage filter | unchanged |
| `c__browseMode=account` (Assessments; Overview never sets it) | account view | unchanged until the Apex-backed fold; then ignored on read (no mode exists), no longer written |
| `c__rafAccountId` / `c__rafContactId` | account trail restore | after the Assessments fold: mapped to `c__aacct` / `c__acontact`; until then unchanged |
| `c__assessmentRequestId` (+ `c__readoutId`, `c__offeringKey`) from Overview and Home | opens the workspace | unchanged |
| `c__astatus`, `c__areadout`, `c__apreset`, `c__repDirectId` | filters, ready-to-book, Rep-Direct modal | unchanged |

The mapping runs in the consumer before `readFilterState`: translate the legacy key into the new filter param in the state object handed to the helper, then let the standard `buildNavigateArgs(replace)` write the new params on the next change, while `mergeLocationState` keeps unrelated params. `gtmOverview.js` producers are NOT changed by this work (they keep emitting the legacy params, which is why the mapping is required); switching them to `c__pacct`/`c__pcontact` is an optional later cleanup. Overview drill-ins to the Pages tab were re-checked after #239 (custom Overview tab retired in favour of the Home page; `gtmOverview` remains in the Home flexipage): the producers are still live.

### C.9.4 Placement revised (supersedes C.1)

- End state: the bar is the ONLY toolbar, at the START of the page content (right under the page header), no pills row, no `.rlf-mode-toggle` or `.ov-mode-toggle` markup. The bar is left-aligned (root `slds-grid_align-start`, count after the triggers) and popovers anchor `left: 0` again (the far-right anchoring of C.1 existed only to sit beside pills); the viewport clamp stays in both directions. `.rlf-toolbar` and `.ov-toolbar` wrappers are dropped; the bar sits directly in the consumer template.
- Until each tab's fold, C.1 applies unchanged (bar in the same row as the pills, far right).

### C.9.5 Staging (recommended)

1. Release 1 (both tabs): the rest of Addendum C as already agreed (toolbar row beside the pills, remembered filters, auto-open, More, full Pages set), PLUS on Pages the Account and Contact filters and the `c__rlfAccountId`/`c__rlfContactId` to `c__pacct`/`c__pcontact` mapping for the All Pages view. The toggle remains, so the "consumer specs unmodified" guarantee HOLDS for this release (only additions; see below).
2. Release 2 (Pages only): remove the toggle, the tile/Miller columns and the crumbs; add row actions and `Back to links`; drop the `modechange` binding in `gtmPageBrowser`. This BREAKS the "consumer specs stay unmodified" guarantee, by design.
3. Release 3 (Assessments), only after the user directly authorises the Apex change: Apex `AssessmentQuery` account/contact members and tests (full Apex test run on `gtm-prod` is then required for that deploy; validate on `gtm-staging` first), Account/Contact filters, remove the toggle and `gtmReadoutAccountFinder` use, rewrite its specs.
3. Release 3 (Assessments), only after the user directly authorises the Apex change: Apex `AssessmentQuery` account/contact members and tests (full Apex test run on `gtm-dev` is then required for that deploy; validate on `gtm-staging` first), Account/Contact filters, remove the toggle and `gtmReadoutAccountFinder` use, rewrite its specs.
Why staged: `gtmRepLinkFinder.test.js` is 1,317 lines / 54 tests with about 36 references to the toggle or mode (7 tests call `switchToAccountModeIfNeeded`; the whole "browse-mode toggle" and "unified Account/Contact search" describes are about the by-account view), so an all-at-once fold hides regressions; and release 1 gives the user the new filters and toolbar to react to before the irreversible removals.

### C.9.6 Specs: exactly what changes

Release 1: NONE of the existing assertions changes. Constraints so they stay green: the Funnel-stage entry remains `filters[0]` with its options and counts (`gtmRepLinkFinder.stageFilter.test.js` reads `bar(el).filters[0]`); the toggle markup and `modechange` behaviour stay; new Pages filters and mapping get NEW specs.

Release 2 (Pages), must be rewritten or removed:
- `gtmRepLinkFinder.test.js`: the helper `switchToAccountModeIfNeeded` (around line 135) and its 7 callers (the flows must reach the detail through `Open` or a `c__rlfLinkId` deep link instead); the whole `describe('browse-mode toggle ...')` (around line 1074: asserts `.rlf-mode-toggle` buttons `['All Pages','By Account or Contact']`, mode switching, `.rlf-mode-toggle` still present on the view step, the account button click, `modechange`); the `describe('unified Account/Contact search ...')` (around line 1222; account search moves to the Account/Contact filters and is replaced by filter specs); the assertions at about lines 137 and 1089 that query `.rlf-mode-toggle`; URL-state tests that assert `c__rlfMode` and the Account then Contact then Link drill (about 54 references to `c__rlf`) keep the three detail-view params but drop `c__rlfMode`; the per-link Active toggle / Copy link / New password tests move from the "Which link?" list to row-action tests.
- `gtmRepLinkFinder.stageFilter.test.js`: the test around line 186 ("a stage deep link with no account forces all mode": `c__rlfMode`, toggle click, `modechange`, `tiles`) and the "`c__stage` + account keeps account mode" test that follows it; they become "stage plus Account filter intersect".
- `gtmRepLinkFinder.table.test.js`: the `c__rlf` reference (one) and any `Open` row-action assertion that expects account mode.
- Unaffected: `gtmRepLinkTableModel.test.js` (columns and actions extend), `gtmFilterUrlState.test.js`, `gtmAssessmentsTableModel.test.js`, `gtmReadoutsOverview.test.js`, `gtmOverview*` (producers unchanged; the `c__rlfAccountId` drill-in assertions stay valid).
- `gtmPageBrowser` spec (if it asserts the `modechange` subtitle) updated.
Release 3 (Assessments): `gtmReadoutsOverview.test.js` describe `browse mode toggle (Account/Contact trail)` (from about line 883: `.ov-toggle-btn` clicks, `c__browseMode` read and written, filters ignored in account mode) and the `.ov-toggle` and `c__browseMode` references (about 19 toggle/mode references, 8 `c__` legacy ones); `gtmReadoutAccountFinder` specs are retired or kept only if the component is kept; new specs for the server-backed Account/Contact filters and Apex `GtmAssessmentListControllerTest`.

### C.9.7 QA measurements (adds to C.5)

- Total vertical space of the toolbar, before and after, at 1078px and 1440px on both tabs: "before" is the pills row plus the bar row of the current branch build (or origin/main); "after" in the end state is ONE toolbar row with no pills row (target: at most one control row, at most 44px, both tabs, in the state with all filters active); in release 1 the pills-plus-bar row stays at most the pills height plus 8px (C.5).
- Every by-account capability still reachable (Pages, release 2): find an account and a contact with the new filters (including a deep link `c__rlfAccountId=<id>` landing on the filtered list); Open a link to its detail and back with filters intact; Turn off then Turn on a link from a row action and see the Status change and the link actually inactive for a visitor; Copy link; New password (a new password is generated and shown once); Show/Copy password in detail; View readout and Generate Readout; the assessment detail and Preview the link; browser back and refresh at every depth (list with filters, detail, detail with preview or workspace or revealed password); an account with no links gives the empty state with "Clear filters".
- Deep links from the C.9.3 table: the Overview account and contact drill-ins, saved and shared link URLs with `c__rlfLinkId`, `c__stage`, the GUS stage-filter tool, and old bookmarks carrying `c__rlfMode`.
- Assessments (release 3 only): the Account/Contact filters return the same rows the old trail listed for that account; the workspace opens from a filtered row.

### C.9.8 Jest additions (new specs)

- Legacy mapping: `c__rlfAccountId` alone maps to `c__pacct` and is rewritten; `c__rlfAccountId` plus `c__rlfContactId` map to both filters; ids plus `c__rlfLinkId` still open the detail view; `c__rlfMode` (either value) is ignored; unrelated params survive; unknown ids are kept as options until data loads (no drop).
- Account and Contact filters: options and values (Id/label), searchable list above 8, AND with the other filters and the stage set, count matches rows, an account with no rows gives the empty state.
- Release 2: row actions (`Open`, `Copy link`, `New password`, `Turn off`/`Turn on` calling `setActive` with the row id and updating Status); `Back to links` restores filters; the detail view is reachable by `Open` and by deep link; `gtmPageBrowser` no longer depends on `modechange`; no `.rlf-mode-toggle` in the DOM; the bar is the only toolbar and is left-aligned with popovers anchored left.
- Release 3: Apex `GtmAssessmentListControllerTest` cases for the new members (positive, negative, no-filter, bulk) and the LWC filter wiring.

### C.9.9 Developer file list for the fold (release 2 and 3 are separate branches or commits; release 1 file list is C.6 plus the Account/Contact items)

Release 1: C.6 files, plus in `gtmRepLinkFinder.js` the Account and Contact filter config, options and legacy mapping (and preferably the new pure helper `gtmRepLinkFilterModel.js` and its spec).
Release 2: `lwc/gtmRepLinkFinder/gtmRepLinkFinder.html`, `.css`, `.js` (remove `rlfMode`, toggle, tile/Miller/crumb markup and code paths; add row actions and `Back to links`), `gtmRepLinkTableModel.js` (`getRowActions` gains Copy link, New password, Turn on/off), `lwc/gtmPageBrowser/gtmPageBrowser.html` and `.js` (drop `onmodechange` and `linkFinderMode` dependency), `lwc/gtmFilterBar/*` (start alignment and left-anchored popovers), and the rewritten specs listed in C.9.6. Not touched: `gtmOverview.js`, `gtmFilterUrlState`, Apex, metadata, permission sets.
Release 3: `lwc/gtmReadoutsOverview/gtmReadoutsOverview.html`, `.css`, `.js`, its spec, `lwc/gtmAssessmentsTableModel/gtmAssessmentsTableModel.js` (new filters, options), `classes/GtmAssessmentListController.cls` and `GtmAssessmentListControllerTest.cls` (Apex, needs direct user authorisation; full Apex test run on a production-type org), possibly `gtmReadoutAccountFinder` retirement. No permission-set or schema change expected (`GTM_Saved_Configuration__c`/request fields already read).

### C.9.10 Capabilities at risk and questions still the user's to decide

> ANSWERED: see C.10 (Option A approved, Assessments Apex approved, defaults recorded). C.9.5's "release 3 waits" and C.9.9's file lists are superseded by C.10.2 to C.10.4.

At risk if implemented carelessly: (1) the link Active on/off toggle (today only in the account view's link list) must become a row action or it disappears; (2) copy link and new password per row must stay one click from the list; (3) org-wide account search reaching accounts with no links is lost (empty-state instead); (4) the contact-first "N links per contact" overview is lost unless Option C is added later; (5) Assessments cannot fold without an Apex change and the toggle stays there until then; (6) the header subtitle in `gtmPageBrowser` depends on `modechange`; (7) large surface: about 90 existing Pages specs assertions touch the toggle or drill, so a mistake there hides regressions.
Questions:
1. Approve Option A (filters plus row actions plus detail) and its losses (3) and (4), or want a grouped view later?
2. Approve the staging (release 1 keeps the toggle; release 2 removes it on Pages; release 3 needs Apex)?
3. Authorise the Assessments Apex change (full Apex test run on the production-type org), or leave the Assessments toggle in place?
4. Should the Active on/off control be a row action (menu item) or a visible switch column in the table?
5. After the fold the bar is left-aligned at the start of the content. Confirm (the earlier far-right request existed to sit beside the pills).

## C.10 Releases 2 and 3 finalized: fold BOTH toggles, Account/Contact filters from data only (user decisions; build-ready)

Answers to C.9.10 (user): (1) Option A APPROVED, fold "By Account or Contact" into the filters and remove the mode toggle on BOTH tabs, "let's get this all live". The Account and Contact filters are "simply a search built into the filters instead of a check box", and (hard rule) NEITHER tab may ever offer an account or contact that has no page (Pages) or no assessment request (Assessments): options AND search results come ONLY from parties that have at least one link, or at least one visible assessment request. The org-wide search of accounts with no links is DROPPED. (2) The Assessments Apex change is APPROVED ("fold into full apex"): a full Apex test run on the production-type `gtm-dev` can be batched with the add-industry Apex change. Defaults for the unanswered items (recorded as decisions): link actions become a row-action menu; the bar is left-aligned once the pills are gone; staging is R1, then R2 and R3 (parallel). This supersedes C.9.5's "release 3 waits on authorisation" and C.9.10 questions 1 to 5.

Why Pages and Assessments differ on Apex: Pages loads every link client-side (`getMyConfigurations`, no paging), so filtering by account or contact is a client-side intersect with no server change. Assessments is server-paged (50 rows per fetch, cap 10,000), so the filter must be part of the server query (`AssessmentQuery`), and its options must be served by the server.

### C.10.1 Contract additions to the bar (the only ones besides `storageKey`), all additive and optional

`filterchange`/`clear` payloads and timing stay frozen. Three additions, needed because the two toggles disappear on different schedules and one filter list is server-backed:
1. `@api align` : `'end'` (default, today's release-1 behaviour beside the pills) or `'start'`. `'start'` = root `slds-grid_align-start`, count after the triggers, popovers anchored `left: 0` (C.9.4). R2 sets `align="start"` on the Pages bar and R3 on the Assessments bar, each when its own toggle is removed.
2. Config field `remoteSearch?: boolean` on a multi `chips` filter. The popover always shows its search input (regardless of the >8 rule), does NOT filter options locally, hides "Select all shown", and after 300 ms of no typing fires `optionsearch` (below). Selections not in the current option list are kept in the draft exactly like the hidden-selection rule (B.6) and still shown on the trigger by the label the consumer keeps for them.
3. New event `optionsearch` with detail `{ key, term }` (trimmed string, `''` when cleared or on first open), `bubbles: false, composed: false`. The consumer answers by re-passing `filters` with that filter's `options` replaced (max 50). A per-filter boolean config `loading` renders "Searching..." in an `aria-live="polite"` line while the consumer waits; an empty result renders "No matches".
These live in `gtmFilterBar.html/js/css` and its spec only. To avoid R2 and R3 colliding on those files, the bar prep (items 1 to 3) is ONE small commit made FIRST by the Release-1 Developer on `agent/issue-compact-filters-r1` (they already own those files); R2 and R3 branch from it. If R1 has already merged, the same commit is a tiny standalone branch merged before R2/R3 start.

### C.10.2 Release 2 (Pages): contract

**Removed** from `gtmRepLinkFinder`: `rlfMode` and every `isAllMode`/`isAccountMode` gate (the list is the only view), `handleShowAllMode`/`handleShowAccountMode`, `dispatchModeChange` and the `modechange` event, `.rlf-mode-toggle`/`.rlf-toolbar` markup and CSS, the `rlf-head` search, `searchResults`, the `searchAccountsAndContacts` import and its call (the org-wide search is GONE), the crumb trail, the contact and link Miller columns, the "Nothing picked yet" empty state, `getContactsWithLinks` for LISTS. **Kept** unchanged: the link detail (view) block, the preview block, the workspace, password reveal, `setActive`, `regeneratePassword`, `getPassword`, `generateReadoutForRequest`, the stage id-set logic, `linkStats`.

**Bar**: the Pages `c-gtm-filter-bar` becomes the first child of `.rlf` under the page header (`align="start"`, `storage-key="pages"` kept), shown only when no link is open.

**Account and Contact filters (data only)**
- `account`: key `account`, label "Account", multi chips, param `c__pacct`, `more: true`. Options are the DISTINCT `Account__c` of `savedLinks` (value = Id, label = `Account__r.Name`, else `Company__c`). `contact`: key `contact`, "Contact", `c__pcontact`, `more: true`; distinct `Contact__c` of `savedLinks` (label = `Contact__r.Name`; when two options share a name, append ` (<company>)`). Both use the LOCAL search (no `remoteSearch`), so they can only ever contain parties with at least one link, because `savedLinks` is exactly the rep's (or, for View All, everyone's) non-draft links.
- An id from the URL that is not among the options is kept as an option (label fallback "Account <last 4 of id>" until data loads) so `readFilterState` never drops a deep link; after load, an id with no rows yields the zero-result empty state and stays clearable (never silently discarded).
- Matching: `Account__c IN accountValues AND Contact__c IN contactValues AND` every other Pages filter and the stage id set (C.3, C.4).

**Row-action menu (Salesforce first: native datatable row actions, not a hand-built menu)**
- `getRowActions(row, doneCallback)` in `gtmRepLinkTableModel.js` returns, in order: `Open` (`name: 'open'`, disabled with the existing no-account label when `row.openDisabled`), `Copy link` (`copy-link`, disabled when `row.generatedUrl` is empty), `New password` (`new-password`), and `Turn off` or `Turn on` (`toggle-active`, label from the row's current state). While a row's request is in flight (`isToggling`/`isRegenerating`) its DML actions are `disabled: true` and labelled `Updating...`. The company button keeps `name: 'open'`.
- Accessible names: each menu item's visible label is its name and is unique within a menu ("Turn off", "Copy link", "New password", "Open"). Native row-action menus cannot carry the row's company in the item label, and how the platform announces the per-row menu button is UNVERIFIED, so QA checks it with VoiceOver. The company `Open` button already names the row. Fallback only if QA fails it: a per-row `lightning-button-menu` column with `alternative-text="Actions for <company>"` (not built now).
- `Turn off`/`Turn on`: calls `setActive({recordId, active: !current})` (existing DML, `AuraHandledException` on `DmlException`); no confirmation (parity with today's toggle); on success update the record's `Active__c` in `savedLinks`, so the Status column, the Link status filter and row actions re-derive; on failure show the existing inline error (`loadError` style) and leave the row unchanged. Semantics to preserve: the link stays in the rep's list; only the client-facing gate changes (`GtmConfigurationStatusController`).
- `Copy link`: existing `copyToClipboard(url)`; `New password`: existing `confirm()` then `regeneratePassword`, copy to clipboard and show once (existing `alert`), parity, native dialogs replaced only in a later change.

**`Open` reaches the link detail**
- `Open` (row action or company button) calls a `loadLinkDetail(row)` that reuses today's `restoreDrillState`/`openLinkRow` data path: it needs `row.accountId` (rows without an account stay disabled) and calls `getContactsWithLinks({accountId})` ONLY to fetch that link's detail fields (`requestId`, `readoutId`, `hasPassword`, contact), then sets `selectedLink` and renders the unchanged view block. No new Apex.
- URL: writes `c__rlfLinkId` plus the existing `c__rlfShowPreview`, `c__rlfShowWorkspace`, `c__rlfPwRevealed`; it no longer writes `c__rlfAccountId`, `c__rlfContactId`, `c__rlfMode`. On read it accepts all legacy keys: with `c__rlfLinkId` it finds the row in `savedLinks` (after load) to get the account id, then loads the detail; if the link is not in `savedLinks` (not the rep's) show "That link is not available." above the list.

**`Back to links`**
- One button (`Back to links`, `slds-button slds-button_neutral`, at the top of the detail block, replaces the crumbs/back buttons) clears `selectedLink`, `showPreview`, `showWorkspace`, revealed password, and removes `c__rlfLinkId` and the three show flags from the URL with the existing replace navigation. All filter params (`c__stage`, `c__p*`) are untouched, so the same filtered, sorted list returns (sort state is component state and the component stays mounted). Focus returns to the `Open` control of the row that was opened (row id remembered), else to the bar.

**Legacy deep links (consumer, before `readFilterState`)**: `c__rlfAccountId` without `c__rlfLinkId` maps to `c__pacct`; `c__rlfContactId` to `c__pcontact` (only when no `c__rlfLinkId`); `c__rlfMode` ignored; the legacy keys are stripped on the first replace. Overview drill-ins (`handleAccountClick`, `handleContactClick`) stay unchanged and now land on the filtered list.

**`gtmPageBrowser`**: remove `onmodechange` and `linkFinderMode`; `headerMeta` no longer branches on mode (line 120 `if (this.linkFinderMode === 'all') return ''` becomes the only path).

**Release 2 Developer file list**: `lwc/gtmRepLinkFinder/gtmRepLinkFinder.html`, `.css`, `.js`; `lwc/gtmRepLinkFinder/gtmRepLinkTableModel.js` (`getRowActions`, columns unchanged); NEW preferred `lwc/gtmRepLinkFinder/gtmRepLinkFilterModel.js` (options and matching) with `__tests__/gtmRepLinkFilterModel.test.js`; `lwc/gtmPageBrowser/gtmPageBrowser.html`, `.js`; specs below. No Apex, no metadata, no permission set. Not touched: `gtmFilterUrlState`, `gtmOverview.js`, anything under `gtmReadoutsOverview`.

**Release 2 Jest**: unmodified must pass: `gtmFilterUrlState.test.js`, `gtmAssessmentsTableModel.test.js`, `gtmRepLinkTableModel.test.js` for columns (its `getRowActions` assertions are extended, see below), `gtmReadoutsOverview.test.js`, `gtmOverview*`. REWRITE in `gtmRepLinkFinder.test.js`: the `switchToAccountModeIfNeeded` helper (about line 135) and its 7 callers (they reach the view step through the row `Open` action or a `c__rlfLinkId` deep link instead); the asserts at about lines 137 and 1089 on `.rlf-mode-toggle`; the whole `describe('...browse-mode toggle...')` (about line 1074: the two-button assertion, mode switching, toggle present on the view step, `modechange`); the whole `describe('...unified Account/Contact search...')` (about line 1222; replaced by filter specs); the URL-state, preview/workspace/password and drill describes (about lines 708 and 835, 54 `c__rlf` references) keep `c__rlfLinkId` and the show flags but drop `c__rlfMode`/account-contact writes and gain legacy-read cases; the per-link Active toggle, Copy link and New password tests (now row-action tests). REWRITE in `gtmRepLinkFinder.stageFilter.test.js`: the test around line 186 ("a stage deep link with no account forces all mode": `c__rlfMode`, toggle click, `modechange`, `tiles`) and the next one ("`c__stage` + account keeps account mode...", becomes "stage AND Account filter intersect"); its `filters[0]` Funnel-stage assertions stay. `gtmRepLinkFinder.table.test.js`: the single `c__rlf` reference and any `Open` expectation of account mode. `gtmPageBrowser.test.js`: the `modechange`/`linkFinderMode` subtitle test (about line 154). NEW: account and contact options only from `savedLinks` distinct values with correct labels and duplicate-name disambiguation; `searchAccountsAndContacts` is NEVER called (mock asserts zero calls); an account with no links is not offered and a typed name that matches nothing shows "No matches"; account/contact AND with stage and other filters and the count; unknown deep-link id kept then empty state; row actions (order, names, disabled states, `setActive` args and record update, failure keeps the row, `regeneratePassword` and copy paths); `Open` loads the detail and writes `c__rlfLinkId` only; `Back to links` clears state, keeps filters and returns focus; legacy mapping and stripping; no `.rlf-mode-toggle` in the DOM; `align="start"` passed to the bar.

### C.10.3 Release 3 (Assessments): exact Apex and LWC contract

**Apex (`GtmAssessmentListController`, `with sharing`, zero DML, zero callouts; `GtmAssessmentListControllerTest`).** Verified in the repo: the class is already granted in `GTM_Offering_Admin` and `GTM_Offering_User` (`apexClass` entries at line 86 of both), so new `@AuraEnabled` methods on it need NO permission-set change; no field, object or tab is added (`Account__c`, `Contact__c`, `Company__c` already exist and are already read).

1. `AssessmentQuery` gains `@AuraEnabled public List<String> accountIds;` and `@AuraEnabled public List<String> contactIds;` (strings from the LWC).
2. `Filters` gains `List<Id> accountIds`, `List<Id> contactIds`, and `Boolean accountActive`, `contactActive`. `normalise` converts each string with `Id.valueOf` inside `try/catch`, keeps only ids whose `getSobjectType()` is `Account` (respectively `Contact`), de-duplicates, keeps at most the first 50 ids. DIFFERENCE from status/tier (which drop unknown values and then ignore the filter): if the input list is NON-EMPTY but yields NO valid id, set `f.impossible = true` (zero rows), so a corrupted deep link can never show an unfiltered list under an "active" filter (documented, tested).
3. `filterSql` adds `Account__c IN :accountVals` and `Contact__c IN :contactVals` (AND with everything else; account and contact are ANDed, values within each are ORed). Bind-variable discipline is UNCHANGED and mandatory: `accountVals` and `contactVals` MUST be declared as locals with exactly these names in `queryVisible` AND in `ElevatedReads.queryOrphans` (the class comment already states this rule; a missing local is a runtime SOQL bind error). No user text is ever concatenated into SOQL: ids are bound lists.
4. Ownership and scope are UNCHANGED and shared: a rep sees requests they own (`OwnerId = :me`, on top of `with sharing`) plus the queue-orphan arm; View All sees all. The new filters are conditions inside the SAME predicate, never a replacement for it, so filtering by an account can never reveal another rep's request.
5. New method for the filter options (searchable, bounded):
```
public class FilterOption {
    @AuraEnabled public String value;      // Id
    @AuraEnabled public String label;      // account name, or contact name
    @AuraEnabled public String sublabel;   // contact: company; account: null
}
@AuraEnabled   // not cacheable: options must reflect the current data and scope
public static List<FilterOption> getAssessmentFilterOptions(String kind, String searchTerm, List<String> includeIds)
```
- `kind` is a whitelist (`'account'` or `'contact'`, chosen via `switch`/map to a constant field name; any other value returns an empty list). The field names are constants, never user text.
- Scope: the SAME viewAll / `OwnerId = :me` / queue-orphan predicate as `getAssessmentPage`, via a private helper shared with it (extract the scope computation, do not copy it). The orphan arm reads only the Account/Contact ids of orphan requests through `ElevatedReads` (the only `without sharing` code), bounded by the orphan id set.
- Only parties with at least one visible request: aggregate over `GTM_Assessment_Request__c WHERE Account__c != null` (respectively `Contact__c != null`) with the scope predicate, `GROUP BY Account__c, Account__r.Name` (respectively `Contact__c, Contact__r.Name, Company__c`) `ORDER BY` name `LIMIT 50` (constant `FILTER_OPTION_LIMIT`). Grouping by a parent name is believed valid SOQL but is UNVERIFIED offline; the tested fallback is `GROUP BY Account__c` plus a bound `SELECT Id, Name FROM Account WHERE Id IN :ids` under `with sharing`, falling back to `Company__c`/`Requester_Name__c` when the name is not readable. Never lists an account or contact that has no request.
- `searchTerm`: trimmed, at most 80 characters; blank returns the first 50 alphabetically. The term is applied as a bind variable (`Account__r.Name LIKE :likeTerm OR Company__c LIKE :likeTerm`) where `likeTerm = '%' + escaped + '%'` and `%`, `_` and `\` in the term are escaped with `\` so a user cannot widen the match; a quote or SOQL fragment in the term is inert text.
- `includeIds`: up to 50 ids from the URL; the method also returns those that are visible so the LWC can label restored values (they are unioned with the search hits, de-duplicated, ids not visible are simply absent).
- FLS/sharing: `with sharing` at class level; labels come from `Account__r.Name`/`Contact__r.Name` exactly as `toRow` already does; if `Account`/`Contact` is not accessible the label falls back to `Company__c`/`Requester_Name__c` (same parity as rows).
6. `AssessmentPage`, `AssessmentRow` and `offeringOptions` are unchanged.

**Apex tests (hermetic: create their own Account, Contact, Requests, Readouts; no Migration Accelerator or other offering data; must pass with zero offerings and must not depend on org data):** account filter includes only matching rows; contact filter; both AND; AND with status and range; multiple values OR; invalid ids dropped, and all-invalid non-empty input returns zero rows; a wrong-type id (a Contact id in `accountIds`) is invalid; the 50-id cap; another rep's request is never returned or listed as an option (run as two users, using the existing test's user/permission-set helpers); View All sees all; the queue-orphan arm for rows and options; `getAssessmentFilterOptions`: returns ONLY accounts/contacts that have a visible request and never one without (create an Account with no request and assert it is absent), search term match and no-match, wildcard characters escaped (`%`, `_`), an injection string returns an empty list without exception, LIMIT respected (create more than 50), `includeIds` returns visible ones only, unknown `kind` returns empty; existing tests stay green. Because an Apex deploy to the production-type `gtm-dev` runs the FULL local test suite, every test in the org (including those written for the add-industry change, batched in the same deploy) must be self-contained; validate first on `gtm-staging` with `--dry-run` and the local-tests level, and deploy to `gtm-dev` only under the deployment rules (never `-c`, staging first, direct user authorisation at deploy time).

**LWC (`gtmReadoutsOverview`, `gtmAssessmentsTableModel`)**
- Config: append (after `offering`, so the existing key order for the first six is unchanged) `account` ("Account", multi chips, `c__aacct`, `more: true`, `remoteSearch: true`) and `contact` ("Contact", `c__acontact`, `more: true`, `remoteSearch: true`). Add both keys to `FILTER_KEYS`; `buildFilterConfig(offeringOptions, extraOfferingValues, accountOptions, contactOptions)` gains two optional arrays (`{value,label}`) merged with URL values (label fallback until resolved).
- Query mapping (`toQuery`): `values.account` to `accountIds`, `values.contact` to `contactIds`.
- Options flow: on `optionsearch` (also fired once with `''` on first open) call `getAssessmentFilterOptions({kind, searchTerm, includeIds: current values})` imperatively; guard with a sequence counter so a slower earlier response never overwrites a newer one; on error keep the previous options and show an inline message; pass `loading` while pending; keep currently selected values in `options` (with their known labels) so the trigger text stays correct.
- Remove `browseMode`, `handleShowAllMode`/`handleShowAccountMode`, `isAllMode`/`isAccountMode` gating (the table is always shown unless the workspace is open), the `gtmReadoutAccountFinder` usage, `.ov-mode-toggle`/`.ov-toolbar` markup and CSS, and the `c__browseMode` read/write. `gtmReadoutAccountFinder` is left in the repo unreferenced (retiring it needs a destructive deploy and is a separate cleanup, not part of this release). The bar becomes the first child under the header with `align="start"` and `storage-key="assessments"`. The Rep-Direct modal and the workspace are untouched.
- Legacy mapping (consumer, before `readFilterState`; the reserved helper list keeps rejecting these as filter params): `c__rafAccountId` maps to `c__aacct`, `c__rafContactId` to `c__acontact` (only when the new param is absent), `c__browseMode` is ignored, and all three are stripped on the first replace navigation. `c__assessmentRequestId`, `c__readoutId`, `c__offeringKey`, `c__repDirectId`, `c__astatus`, `c__areadout`, `c__apreset` are unchanged.
- Docs: update the "Account mode" line in `docs/architecture/gtm-assessments-table.md` (about line 171).

**Release 3 Developer file list**: `classes/GtmAssessmentListController.cls`, `classes/GtmAssessmentListControllerTest.cls`; `lwc/gtmReadoutsOverview/gtmReadoutsOverview.html`, `.css`, `.js`; `lwc/gtmAssessmentsTableModel/gtmAssessmentsTableModel.js`; `docs/architecture/gtm-assessments-table.md`; specs below. No permission-set, schema or metadata change. Not touched: `gtmFilterUrlState`, `gtmOverview.js`, `gtmReadoutAccountFinder` (left in place), anything under `gtmRepLinkFinder`.

**Release 3 Jest**: unmodified must pass: `gtmFilterUrlState.test.js`, all `gtmRepLinkFinder*` and `gtmPageBrowser` specs (independent of R2 only if R2 has not yet merged; they change in R2), `gtmOverview*`, and `gtmAssessmentsTableModel.test.js` (existing assertions: it uses `validateFilters` and `readFilterState`, unaffected by two appended filters; add cases). REWRITE in `gtmReadoutsOverview.test.js`: the `describe('browse mode toggle (Account/Contact trail)')` (from about line 883: `.ov-toggle-btn` clicks, `c__browseMode` read and written, filters ignored in account mode) is replaced; the other `c__browseMode`/toggle references (about 19 toggle or mode references and 8 legacy `c__` ones, around lines 110, 899 to 980) are removed or rewritten; the `jest.mock` of the account-finder child (lines 39 to 49) is dropped; the filter-config test at about line 597 (`filters.map(...)` equal to the six keys) becomes eight keys with `account` and `contact` appended and `remoteSearch` true; `URL state persistence (existing params unaffected)` and `restoring filters` gain `c__aacct`/`c__acontact` cases. NEW: query includes `accountIds`/`contactIds` and offset 0 on change; `optionsearch` calls `getAssessmentFilterOptions` with kind, term and `includeIds`, results replace only that filter's options, stale response ignored, error keeps options; legacy `c__rafAccountId`/`c__rafContactId`/`c__browseMode` mapping and stripping; the toggle markup is gone; workspace open/close unaffected; `align="start"` passed.

### C.10.4 Order and parallelism

1. Release 1 (Developer now, `agent/issue-compact-filters-r1`): Jira-style More, remembered filters, auto-open, the full Pages filter set including Account and Contact with the legacy mapping, toolbar beside the pills, density token, PLUS the bar prep commit of C.10.1 (`align`, `remoteSearch`, `optionsearch`, `loading`).
2. Release 2 and Release 3 then run IN PARALLEL on separate branches by different Developers. Their file sets do not overlap: R2 = `gtmRepLinkFinder/*`, `gtmPageBrowser/*`; R3 = `GtmAssessmentListController*`, `gtmReadoutsOverview/*`, `gtmAssessmentsTableModel/*`, `gtm-assessments-table.md`. Neither touches `gtmFilterBar/*` (prep done in R1), `gtmFilterUrlState/*`, or `gtmOverview/*`. This document is the shared contract (docs edits only by the Architect).
3. R3 needs the Apex full-test-run deploy (batched with add-industry): schedule it once, validated on `gtm-staging` first. R2 is LWC-only and does not trigger a full Apex run on its own.
4. Each release is deployed to `gtm-staging` and browser-validated before the next reaches `gtm-dev`; `gtm-dev` is Production and only under direct user authorisation.

### C.10.5 QA plan (real input, locked single tab; `gtm-staging` synthetic demo set)

Use REAL mouse and keyboard in the locked single tab (scripted clicks hid the earlier defects, B.13). The synthetic demo set on `gtm-staging` provides links and assessment requests to filter; create at least one Account and one Contact with NO link and NO request to prove absence.
- No-page/no-assessment rule (both tabs): open the Account filter, type the name of the account that has no link/request: "No matches"; same for Contact; the empty search shows only parties with data; there is no org-wide search anywhere; network log on Pages shows NO `searchAccountsAndContacts` call.
- Fold: no mode toggle, no pills, one toolbar at the start of the content on both tabs; measure the toolbar's total height at 1078px and 1440px before (pills row plus bar) and after (one row), target at most 44px with all filters active.
- Parity: for a known account and contact, the Account/Contact filters return the same links (Pages) and the same assessments (Assessments) the old trail listed; counts equal rows; AND with stage, status, tier, range, offering.
- Pages row actions with real clicks: `Open` reaches the detail and `Back to links` restores the same filtered, sorted list and focus; `Turn off` then `Turn on` (Status column and Link status filter update; the client-facing link actually gates); `Copy link`; `New password` (new password shown and copied once); detail: Show/Copy password, Generate/View readout, assessment detail, Preview the link; refresh and browser back at list, detail, preview, workspace, revealed password.
- Deep links: Overview account and contact drill-ins (`c__rlfAccountId`, `c__rlfContactId`), `c__rlfLinkId` shared links, old bookmarks with `c__rlfMode`, `c__stage`, GUS stage-filter tool, Assessments `c__browseMode=account&c__rafAccountId=...`, `c__assessmentRequestId`, `c__astatus`, `c__areadout`, `c__apreset`, `c__repDirectId`; the URLs get cleaned (legacy keys stripped) on first change.
- Assessments server behaviour: account/contact search hits the server once per pause (debounce), stale responses never overwrite; a rep sees only accounts and contacts from their own requests, a View All user sees all (two users); a deep-linked id shows a label, not a raw id; infinite scroll and the 10,000 cap still work with the new filters.
- Apex: full local test run green on `gtm-staging` before any `gtm-dev` deploy; no new console errors; keyboard and screen-reader checks from B.10/C.5 on the new popovers, the row-action menu, and `Back to links`.

### C.10.6 Remaining blockers and questions for the user

Blockers: none in the design. Unverified (no doc or web tool): `GROUP BY` on a parent name in SOQL (fallback specified), the platform announcement of native datatable row-action menu items, `localStorage` under LWS (C.2), base-component `focus()`.
Questions the user may still answer (defaults chosen if not): (1) keep the native `confirm()`/`alert()` dialogs for "New password" for now (default: yes, replace later)? (2) is a 50-value cap per multi-select right (default 50)? (3) should Turn off ask for confirmation (default: no, parity with today)? (4) leave `gtmReadoutAccountFinder` in the repo unreferenced until a later destructive-deploy cleanup (default: yes)?

### B.13.2 Defects found only with REAL mouse/keyboard input (selection did nothing; multi-select closed after each pick)

Observed on `gtm-staging` against 10aa799 with real input. Choosing an option in any popover closed it with no `change` event (URL, trigger label, Clear filters and count unchanged); a script-dispatched `input.click()` worked. Multi-select popovers also closed after every pick. Jest missed both because its synthetic clicks never reproduce the browser's focus hops.

Cause (confirmed by reproducing the event order in Jest): the `focusout` closer treated focus movement as "popover lost focus". On a real click the order is pointerdown, mousedown, `focusout` (input, to the popover container div), `focusin` (div), mouseup, click, and later a `focusout` on the div with a null `relatedTarget`. The deferred check saw no focused element and tore the popover down before the click could toggle the input. The same closer fired when a consumer re-render made the base component drop focus, which is why multi-select closed after each pick (nothing in the change handler closes it).

Fix:
- A `focusout` now closes the popover ONLY when its `relatedTarget` is a real Element outside the wrapper (Tab away). A null `relatedTarget`, `document`/`window`, or anything inside the wrapper never closes it.
- `pointerdown`/`mousedown` inside the bar set a short-lived `_pointerDown` flag (cleared one tick after the click completes, 500 ms safety) that suppresses any focus-based close, and the open-time `_settling` flag still applies.
- The popover otherwise closes only on: outside click (deferred document listener), Escape (focus returns to the trigger), opening another popover, single-select pick (`chips` single, `select`), and Clear filters. Multi, toggle, date presets and search never close it, and the open state lives in `_openKey`, which a `values` re-render does not touch.
- Timers and listeners are cleared on close and in `disconnectedCallback`.

Tests emulate the real event order (pointerdown, mousedown, focusout to the container, focusin, mouseup, click, change, null-relatedTarget focusout) and a consumer re-render with new `values`; 3 of them fail on 10aa799.

STILL NOT PROVABLE IN JEST: the actual browser focus and blur ordering (jsdom fires `blur` with the `document` as `relatedTarget`, which is why non-Element targets are ignored), whether base components take focus, real retargeting under LWS/Locker, and screen readers. Consequence to accept: tabbing off the end of the page (null `relatedTarget`) leaves the popover open until an outside click or Escape.

### B.13.3 68b4de5 did NOT fix the real runtime: the document click listener closed the popover on inside clicks

The real-input test of the deployed 68b4de5 still showed no change and a closed popover on a mouse click, and on Tab then Space on a checkbox. Verified in the code: the document `click` listener (attached on a deferred tick in 8b2b087) decided "inside" only from `composedPath()`, `event.target === host` and `wrapper.contains(target)`. In the real runtime the document-level event is retargeted to an outer host (`c-gtm-readouts-overview`) with a filtered path, so every click INSIDE the popover looked like an outside click. The deferral only protected the opening click, not later ones. Sequence on a real click: click reaches document, `_close()` runs synchronously, LWC re-renders in the microtask checkpoint that follows the listener (the JS stack is empty for a user event), the popover DOM including the input is removed, and the input's activation behaviour (its `change`, which fires after click dispatch) never fires on the removed element. Space produces a click too, so it failed the same way. A script `input.click()` works because `change` fires inside the same JS stack, before any microtask checkpoint. jsdom missed it on both counts (no such retargeting; no microtask checkpoint between a listener and the activation behaviour), and my 8b2b087 retargeting emulation only exercised the OPENING click.

Rules now (frozen unless this fails again):
- Inside-interaction detection uses bubbling handlers in OUR OWN shadow (`pointerdown`, `mousedown`, `click`, `keydown` on the wrapper) which set `_insideInteraction` and clear it on a `setTimeout(0)`. These run before the event reaches document and never depend on `composedPath` or retargeting. The document listener returns immediately when the flag is set; the old path/target/contains checks remain only as an extra inside signal, never the sole one.
- The document listener NEVER closes synchronously: a genuine outside click closes in a `setTimeout(0)` (flag re-checked), so an in-flight `change` completes first.
- Chosen over a backdrop: a transparent full-viewport backdrop needs `position: fixed`, which breaks under a transformed ancestor in Lightning pages, blocks click-through to other controls and scrolling, and adds a new layer to clip-test. The flag needs none of that.
- Nothing else closes or re-creates the popover during an inside interaction: multi, toggle, date and search handlers never call `_close`, and open state lives in `_openKey`.

Tests emulate the runtime retargeting on the document listener AND click inside the popover with real bubbling events, flush microtasks, and only then fire `change` (checkbox and radio), plus Space/keydown and an outside click racing an in-flight change; 4 of them fail on 68b4de5.

STILL NOT PROVABLE IN JEST: the real browser's activation-behaviour timing relative to microtask checkpoints, real retargeting under LWS/Locker, real focus/blur order, whether base components take focus, and screen readers. If this fails a third time, add temporary live diagnostics (console logging in `_close` with a stack and reason, and in the doc click listener with `_insideInteraction`, `event.target`, and `composedPath().length`) before changing logic again.

### B.13.4 Third failure: Assessments still broken with real input while Pages works (diagnose first)

Real-input test of f7a20d8 on `gtm-staging`. WORKS: Pages (single-select radios): open, pick (URL, trigger text, Clear filters, count), popover closes, focus returns to the trigger, second pick, Clear filters, Escape. FAILS: Assessments (Status and Readiness tier checkboxes, Submitted radios): no `change`/`input` event, URL and trigger unchanged, popover closes, `activeElement` falls to BODY. Since Pages radios work and Assessments radios fail, the bug is not checkbox vs radio; the trace (mousedown target SPAN, focus hops, click on the SPAN, then NO change) is consistent with the option input being replaced between mousedown and click, so the label activates nothing.

Code reading (no live evidence yet), Assessments vs Pages consumers:
- `gtmReadoutsOverview.js` `syncFiltersFromState` (about line 125) assigns `this.filterConfig = buildFilterConfig(...)` UNCONDITIONALLY on every `CurrentPageReference` wire firing, in `connectedCallback` (line 98), and again after each load (line 192): a NEW `filters` array of NEW objects (and, via `readFilterState`, a new `filterValues` object on change) each time. Pages passes a static config array (`gtmRepLinkFinder.js` line 47) that never changes identity.
- `gtmReadoutsOverview.html` (line 35) passes `filters={filterConfig}`, so each of those re-renders hands the bar new objects.
- Before this change the bar rebuilt its `options` and `value` arrays for the base components on every render, so any parent re-render gave `lightning-checkbox-group` / `lightning-radio-group` NEW `options` arrays, which makes the base component re-render its inputs. That is the only Assessments-only difference found; whether the runtime actually re-renders the parent during a mouse interaction (a page-reference re-fire, a load state change) is NOT confirmed. The bar has no `filters`/`values` setter logic that resets `_openKey`; open state was already independent of prop identity.

Diagnostics commit a35decc (`// TEMP-DIAG`, revert before the PR): `console.info('[GTMFB]', ...)` lines for `close <reason> openKey <key> <stack>` (reasons: `outside-click-timer`, `focusout-outside`, `escape`, `trigger-toggle`, `single-repick`, `single-pick`, `clear-filters`), `docclick inside-flag ... target ... pathLen` and `docclick-decision inside|outside`, `setter filters|values lenBefore lenAfter sameIdentity openKey`, and `connected`, `rendered <n> openKey`, `disconnected`. No values, URLs or personal data.

How to read them: open the browser console on the Assessments tab, filter by `[GTMFB]`, click Status, then click the 'New' option with the real mouse. Expected healthy output: `connected`, `rendered`, `setter` lines only before the click; during the click at most `docclick inside-flag true`. A `close <reason>` line names what closed it (its stack shows the caller). Many `setter filters sameIdentity false` lines or `rendered` lines DURING mousedown->click prove parent churn re-renders the bar mid-click; `connected` after `disconnected` proves the bar was re-created (parent `if:true`).

Fix (separate commit): the bar keeps content-stable identities for the `options` and `value` arrays it gives base components (`_stable`, compared by JSON content), so a parent re-render with equal content passes the same arrays and the base component does not re-render or replace its inputs. Jest (real `buildFilterConfig`, harness setting new `filters`/`values` objects) asserts the same group element, same `options`/`value` references, popover still open, and one `filterchange` when the `change` follows a parent re-render; 2 tests fail without it. This is a robustness fix chosen from code reading, not a confirmed cause: if the live diagnostics show a different closer or a different re-render source, follow the diagnostics, not this note.

STILL NOT PROVABLE IN JEST: whether the real runtime re-renders the parent mid-click, how the base components key and replace their inputs on an options change, real focus/activation timing, retargeting under LWS/Locker, and screen readers.

### B.13.5 Live confirmation, Tab-away fix, diagnostics reverted

Live real-input test on `gtm-staging` of 8fccb0d (with the TEMP-DIAG trace) PASSED on Assessments and Pages: real clicks and Space register on Status, Readiness tier, Submitted and More; multi-select stays open ("Status: 2", URL `new%2Ccontacted`); Submitted "Last 7 days" registers; Escape returns focus to the trigger; outside click closes; a second popover closes the first; clicks on More padding and headings do not close it; Clear filters gives a clean URL; the bar is 36px with four filters active; no console errors.

Confirmed cause of the Assessments failure: content-stable option/value identities (`_stable`) fixed it. The `[GTMFB]` trace showed that on Assessments the parent passes a NEW `filters` array and `values` object on every render, several times per click (`setter filters ... sameIdentity false` and repeated `rendered n`) while `openKey` stayed set. Without stable identities each render handed the base components new `options` arrays, which replaced their inputs between mousedown and click.

The diagnostics commit a35decc was reverted (6d570f8): `gtmFilterBar.js` again has plain `@api filters` / `@api values` and no `console.info`, `[GTMFB]`, `TEMP-DIAG` or `diagStack`. The `_stable` memo and every earlier fix are kept.

Tab-away defect (found live): with Status open, Tab to the neighbouring "Submitted" trigger left the Status popover open, because `handleFocusOut` ignored any focus that landed inside the bar. It now closes when `relatedTarget` is an Element that is neither the open popover's content nor its own trigger (a sibling trigger or the Clear filters button included). It still never closes for a null `relatedTarget`, `document`/`window`, focus inside the popover, its own trigger, or during the pointerdown flag window.

Note: after opening a popover, focus starts on its FIRST option, so the first Tab lands on the second option. This is expected, not a defect.

Still unverified live: the Custom date range (From/To and its calendar), the Ready to book toggle, Offering values (long list and search), 1078px and narrower widths (768, 480, 320), and screen readers.

Follow-up (optional, out of scope here): `gtmReadoutsOverview.syncFiltersFromState` rebuilds `filterConfig` on every page-reference firing and after each load; it could rebuild only when the offering options or raw offering values change. The bar no longer depends on it.

## C.10 Release 1 implementation record (branch `agent/issue-compact-filters-r1`, merged with origin/main 0538a34; no Apex, permission-set, schema or `gtmFilterUrlState` change)

Built as specified in C.1 to C.3 and C.9.5 release 1, with these facts and deviations:

- `gtmFilterBar`: More is an add-a-filter checklist (`lightning-input type="checkbox"` per `more` filter, `role="group"` "Add filters"); ticking adds the button and AUTO-OPENS its popover (`_close(false)` then `_open(key)`, so the B.13.x closing rules apply unchanged); each added button has a `lightning-button-icon` x (after the popover in DOM order) that emits one empty-value `filterchange` when it had a value (never `clear`), forgets the key and returns focus to More. `More (n)` counts HIDDEN filters and is not rendered at 0. A `more` filter with a value is always shown (absorbed into the added set in memory only, never written), so it survives Clear filters. New optional `@api storageKey`: `localStorage` `gtm.filterbar.added.<key>`, a JSON array of filter keys only, capped at 20, every access in try/catch; a working storage is trusted (including "empty"); a throwing or invalid storage falls back to a module-level map, then to component state. Unknown remembered keys are ignored for display and kept in the stored list. Additive optional config field `searchable: true` (forces the filter-inside search input, used for Account and Contact); `gtmFilterUrlState` ignores it. The cluster is right-aligned (`slds-grid_align-end`), popovers anchor `right: 0` (one-shot clamp now adjusts `right`), and triggers and Clear filters use `--gtm-control-h: 32px` (with `--gtm-control-pad-x`, `--gtm-control-font: 12px`) declared on `:host`, floored by `max(24px, ...)`. A consumer can override the token from outside on the `c-gtm-filter-bar` element.
- Consumers: `.rlf-toolbar` and `.ov-toolbar` wrap the untouched `.rlf-mode-toggle` / `.ov-mode-toggle` and the bar (`storage-key="pages"` / `"assessments"`); markup and CSS only in Assessments. On Pages the stage-error paragraph stays below the toolbar and the bar is now shown in BOTH views whenever no link is open (previously it was hidden in account mode until a stage was picked), which is what makes the new filters usable in the by-account view.
- Pages filters: new pure `gtmRepLinkFilterModel.js` (config builder and matching) with its own spec; `gtmRepLinkFinder.js` appends them after Funnel stage (`filters[0]` and its seven options unchanged): row = Funnel stage, Offering (`c__poffering`), Sent (`c__psent`); More = Industry (`c__pindustry`), Deal stage (`c__pdeal`), Account (`c__pacct`), Contact (`c__pcontact`), Link status (`c__pactive`, single), Last visit (`c__plast`, only with complete stats, i.e. the stats call succeeded and was not truncated), Owner (`c__powner`, only with more than one distinct owner). All client-side over `savedLinks`/`linkStats`, ANDed with the stage id set, applied to the table AND to the account-mode contact lists (matched through `savedLinks` by link Id; a link absent from `savedLinks` never matches while an extra filter is active). URL values are kept as options before data loads. `c__offering` is not used.
- NOT built, and why (needs a decision): the legacy deep-link mapping of C.9.3 (`c__rlfAccountId` alone becoming `c__pacct`, with `c__rlfContactId` becoming `c__pcontact`, and dropping `c__rlfMode`). Existing assertions that must pass unmodified rely on the unchanged behaviour: `gtmRepLinkFinder.test.js` ("restores mid-depth state (account picked, no contact/link yet)", which expects `getContactsWithLinks` to be called and the contact buttons to show in account mode) and the related restore tests around it, and `gtmRepLinkFinder.stageFilter.test.js` ("c__stage + account keeps account mode and intersects the Contact links"). C.9.3 itself says the behaviour is unchanged until the toggle is removed (release 2), so the mapping belongs to release 2 with those specs. `c__pacct`/`c__pcontact` work today as ordinary filter params.

Unverified live (needs a staging pass with real input): every new Pages filter and its option lists on real data (Account and Contact search with more than 8 options, Owner for a View All user, Last visit gating), auto-open focus and the B.13.x closing rules after ticking in More, the x (focus return, empty-value emit), remembered filters across reloads and with storage blocked (LWS vs Locker), the toolbar wrapping and right-anchored popovers at 320, 480, 768, 1078 and 1440px (including the date calendar), the 32px token height and the bar height with many filters added, the account-mode bar, and screen readers.

### C.9.9 Release 3 (Assessments) as built

- `gtmFilterBar` additive API: a filter config entry may set `serverSearch: true`. The bar then skips its client-side option narrowing for that filter, treats it as usable with zero options, and fires `filtersearch` with `detail {key, value}` on every search-box change (the consumer debounces and replaces `options`). Selected values must stay in `options` (the consumer pins them).
- `gtmReadoutsOverview`: Account (`c__aacct`) and Contact (`c__acontact`) are multi, searchable, `more` filters with `serverSearch`. Options come from `getAssessmentFilterOptions(kind, searchTerm, includeIds)` (300 ms debounce; restored/selected ids sent as `includeIds`, unresolved ids kept labelled by id). `buildQuery` sends `accountIds` / `contactIds`.
- Removed: the scope toggle, `browseMode`, the `gtmReadoutAccountFinder` embed and the account-mode header subtitle. `gtmReadoutAccountFinder` itself is left in the repo, unused. Legacy links: `c__browseMode` ignored and dropped on the next URL write; `c__rafAccountId` / `c__rafContactId` map to the filters (an explicit `c__aacct` / `c__acontact` wins) and the URL is rewritten with replace.
- Readout filter gained `approved-sent` ("Approved, sent") to match the Apex `READOUT_KEYS` added in #245.

## Addendum: filter recovery hardening (issue industry-filter-source)

Report: after several filter clicks on Pages and Assessments nothing loaded, even after Clear filters; Apex all Success; demo records deleted and reloaded mid-session.

### Causes
- Stale ids were treated as valid. Assessments (`gtmReadoutsOverview`): every id in `c__aacct` / `c__acontact` (and legacy `c__raf*`) became an option via `mergePartyOptions`, so it parsed as a valid filter value and was sent as `accountIds`/`contactIds`; the Apex intentionally returns zero rows for an all-invalid id list, so the page looked blank. The old test even asserted "kept when the server does not return it". Pages (`gtmRepLinkFinder`): `rawValues()` in `gtmRepLinkFilterModel.buildExtraFilters` does the same for c__pacct/c__pcontact/etc.
- Clear did not reset `_partyRaw` (Assessments) or `_pageState` (Pages), so restored ids kept riding in `includeIds` / option lists; a stale (older) echo also re-ran `setPartyRaw` before the echo guard returned.
- `loadSavedLinks` (Pages) had no sequence token; overlapping/failed loads could stick `loadingSavedLinks` and there was no Retry. Assessments showed the error without Retry, and a synchronous throw from the Apex call escaped the promise chain (loading flag stuck).
- Echo guard: `_navSig` only expired when a later page-reference arrived; if none did, it stayed set.
- gtmFilterBar: `_settling`, `_pointerDown`, `_insideInteraction`, `_focusPending`, `_memo` were only reset via `_close()`, which is a no-op when nothing is open, so Clear could not unwedge them.

### Fixes
- Assessments: `loadPartyOptions` compares requested ids with those the server returned (it returns an id only if it exists and is visible); unlabelled ids are dropped from `_partyRaw` and the filter value, the URL is rewritten and the list reloads (`dropStaleParty`). `loadAssessments` wraps the call in try/catch, clears `loadError` on success, keeps prior rows on error, and clears the loading flags in `finally` for the newest request token (`_seq`); the error banner has a Retry button (`handleRetry`). Clear resets `_rawOfferings`, `_partyRaw`, `_partyTerm`.
- Pages: `loadSavedLinks` has `_linksSeq`, a sync-throw guard, `finally`, and a Retry button; after a successful load `pruneStaleExtra` drops chips values that match no link option and rewrites the URL. Clear resets `_pageState`.
- Echo guard (both): a `setTimeout(ECHO_GUARD_MS)` clears `_navSig` after each write (safety expiry), cleared on disconnect. The Assessments guard also restores `_partyRaw` when it ignores an older echo.
- gtmFilterBar: `handleClearAll` calls `_resetTransient()` (timers, doc listener, open key, search, focus/settle/pointer/inside flags, `_memo`). The remembered "added" keys (`gtm.filterbar.added.<key>`) only control which empty filter buttons are shown; they never filter results, and unknown keys are ignored, so they are intentionally kept across Clear.

### Platform notes (UNVERIFIED)
Salesforce docs (CurrentPageReference wire, NavigationMixin state, `c__` namespaced state params) were not fetched in this session; developer.salesforce.com is JS-rendered and returned no usable content to the tooling available, so behaviour is treated as unverified. No new platform API is used: the existing `@wire(CurrentPageReference)` and `NavigationMixin.Navigate(pageRef, replace)` patterns are unchanged. Assumption kept from before: the wire can re-fire with an older state after a navigation, which is why the guard exists.

### Tests
`gtmReadoutsOverview.recovery.test.js` (10 rapid changes then Clear; stale account/contact id in URL dropped; Apex rejection then Clear; sync throw), `gtmRepLinkFinder.pagesFilters.test.js` (rapid changes + Clear + stale echo; rejected load then Retry; unknown account id dropped), `gtmFilterBar.test.js` (Clear after rapid open/close).
---

# Filter-to-data tie audit (issue `filter-data-tie`, top-priority defect)

User report, seen on `gtm-staging` with the synthetic demo data (Pages 6 seeded links, Assessments 3 requests): the filter options do not match the values in the columns, the filters "tie into nothing", and the same number of rows always shows. This is a READ-ONLY CODE TRACE of `origin/main` (dc5005c) plus the Release 1 branch `agent/issue-compact-filters-r1` (read via `git show`, nothing switched or staged there). No code was run and no org was touched: everything under "actual data" is computed from `data/seed/synthetic-demo.*.json` and the Apex source, and is marked UNVERIFIED until the parallel live capture confirms it. Line numbers are on `origin/main` unless a branch is named.

## T.1 Verdict in one paragraph

The filter PLUMBING is wired end to end on both tabs (option value -> `filterchange` -> query or client filter -> rows bound to the table -> count). I found NO dead getter, no table bound to an unfiltered array, no wrong key name, no mode gate that swallows the filter. What is wrong is that the option lists and the columns do not describe the same thing, and that the demo data cannot exercise most filters. Concretely: (1) Pages "Funnel stage" options are CUMULATIVE and BEHAVIOURAL server definitions while the Funnel stage column shows ONE exclusive stage, so several options return the same rows and two options (`Went quiet`, `Came back`) can never match a value that any column can display; with the demo data the seven options collapse to 4 / 3 / 3 / 3 / 0 / 0 / 1 rows and all three of the 3-row results show the identical column text "Assessment submitted". (2) On Assessments the option VALUES do match the real picklists and the server maps them correctly, but the demo requests carry no tier, no score and no `Submitted_At__c`, so Tier, Ready to book and the Submitted ranges are empty or all-rows, and Offering has a single value and no column at all. (3) Several option LABELS differ from the column text (Readout, Link status). (4) Two candidate races could still make a working filter look dead in the real runtime (T.6); they need the live network capture to confirm.

## T.2 Pages (`gtmRepLinkFinder`, `gtmRepLinkTableModel`, `GtmLinkStageService`)

**Data path.** Rows: `getMyConfigurations()` -> `savedLinks` (`GtmSavedConfigurationController`, owner-scoped unless View All; universe `Presentation_Stage__c != null AND != 'Draft' AND != 'Rep_Direct'`, so the demo's Draft (cfg1) and Rep_Direct (cfg6) links are NOT in the table: the table has 4 rows, not 6; if the browser shows 6 that is itself a finding for the live capture). Stats: `getLinkStatsAura()` -> `linkStats` (per link `visits`, `lastVisitAt`, `funnelStage`). Stage filter: `getLinkIdsForStageAura(stageKey)` -> `stageIdSet`; counts: `getStageCountsAura()`.

**The filter does apply to the bound rows (correct code).** `gtmRepLinkFinder.js:441` `get tableRows()`: takes `this.savedLinks`, intersects with `stageIdSet` when `stageKey` is set (shows `[]` while `stageLoading`), then `buildRows` and `sortRows`; the datatable template binds `data={tableRows}`; `filterResultCount` (line 551) is `tableRows.length`; `changeStage` (line 605) calls `applyStage` first (line 493) and only then navigates. On Release 1 the same getter also runs `filterLinks(links, this.linkStats, this.pageExtra)` (branch `gtmRepLinkFinder.js:456`) and `handleFilterChange` (branch line 656) stores each extra key in `pageExtra`. No bug found there.

**What decides a link's stage (`GtmLinkStageService.cls`).** Not `Presentation_Stage__c` (the class header says they are unrelated) and not any column value: it is COMPUTED from `GTM_Link_Event__c` rows and `GTM_Assessment_Request__c` rows (lines 21, 55-80, 116-126, 182-262):
- `hasFormOpened` = an event of type `Form Opened` or `Form Resumed`; `hasSubmittedEvent` = `Form Submitted`; `hasRequest` = ANY assessment request whose `Saved_Configuration__c` is the link.
- `isSubmitted = hasSubmittedEvent || hasRequest`; `isStarted = hasFormOpened || isSubmitted`; `isEngaged = pageViewRows > 0 || isStarted`; `isQuiet = isStarted && !isSubmitted`; `isHot = visits >= 2 && lastVisitAt >= now-48h`.
- The Funnel stage COLUMN shows `funnelStage()` (lines 70-75): ONE exclusive value: submitted, else started, else engaged, else not_opened (`gtmRepLinkTableModel.js:10-16` labels: Not opened / Prospect engaged / Assessment started / Assessment submitted).
- The FILTER options (`gtmRepLinkFinder.js:33-41`, hard-coded) are matched by `getLinkIdsForStage` (lines 116-126) CUMULATIVELY: `sent` = every link; `engaged` = engaged OR started OR submitted; `started` = started OR submitted; `submitted`; `quiet` and `hot` are behavioural flags with NO column value; `not_opened` = not engaged.

**Per-option table (Pages Funnel stage, main).**

| Option label / value | Should test | Column shows | Match? | Demo-data result (computed, UNVERIFIED) |
|---|---|---|---|---|
| Links sent / `sent` | every link | (no such value) | NO-OP by design: matches all rows | 4 rows = no change |
| Prospect engaged / `engaged` | engaged or later | "Prospect engaged" only for the engaged-but-not-started links | MISMATCH: includes rows whose column reads "Assessment submitted" | 3 |
| Assessment started / `started` | started or later | "Assessment started" only for started-not-submitted | MISMATCH (same) | 3 |
| Assessment submitted / `submitted` | submitted | "Assessment submitted" | matches | 3 |
| Went quiet / `quiet` | started and not submitted | no column value | NOT VISIBLE in any column | 0 |
| Came back / `hot` | 2+ visits and last visit within 48h | Visits and Last visit columns only, no flag | NOT VISIBLE | 0 |
| Not opened yet / `not_opened` | not engaged | "Not opened" (label differs: "Not opened yet" vs "Not opened") | label differs, logic matches | 1 |

**Why the demo collapses (computed from the seed).** Universe = cfg2 (In_Review), cfg3 (Sent), cfg4 (Sent), cfg5 (Assessment). Requests: req3 -> cfg2, req2 -> cfg3, req1 -> cfg5, so cfg2, cfg3 and cfg5 all have `hasRequest`, hence all three are "submitted", started AND engaged; cfg4 has no events and no request, so it is "not opened". There is NO `Form Opened` or `Form Resumed` event in `synthetic-demo.link-events.json` (cfg2 has a `Drop-off` at step `clientProfile`, which the service does not treat as started), every event is created at load time (one session per link, no second visit, `lastVisitAt` all "today"), so `quiet` and `hot` are structurally empty. Result: Links sent 4, Prospect engaged 3, Assessment started 3, Assessment submitted 3, Went quiet 0, Came back 0, Not opened yet 1; the three 3-row results show the identical rows and the identical column text. This matches the report "the same number of rows always".

**Release 1 extra Pages filters (branch `gtmRepLinkFilterModel.js`).** Their option values are DERIVED from the loaded rows (`collect(...)`, lines about 32-46), so option values match the data by construction; the match logic (`matchesExtra`) tests the same row fields. Tie to columns:

| Filter (key, value set) | Field tested | Column | Match / issue |
|---|---|---|---|
| Offering (`offering`, from `Offering__c`) | `Offering__c` | Offering | ties; demo has ONE value (`migration-accelerator`), so it always returns all rows |
| Sent (`sent`, 7/30/90 or range) | `CreatedDate` | Saved | ties; every demo link is created at the same instant, so every preset returns all rows |
| Industry (`industry`) | `Industry__c` | NONE | NO COLUMN: the user cannot see what is being filtered (demo has 4 distinct industries, so it does filter) |
| Deal stage (`deal`) | `Opportunity__r.StageName` | NONE (the Opportunity column shows the opportunity NAME) | NO COLUMN |
| Account / Contact | `Account__c` / `Contact__c` | Account/company, Contact | tie |
| Link status (`active`: "Active" / "Turned off") | `Active__c` | Status shows "Active" / "Inactive" | LABEL MISMATCH "Turned off" vs "Inactive"; demo has all `Active__c = true`, so "Turned off" gives 0 |
| Last visit (`last`) | `linkStats.lastVisitAt` | Last visit | ties; demo all "today" so all presets return all rows |
| Owner (`owner`) | `OwnerId` | Owner (only for View All) | ties; only one owner in demo so the filter is hidden |

## T.3 Assessments (`gtmReadoutsOverview`, `gtmAssessmentsTableModel`, `GtmAssessmentListController`)

**Data path (correct code).** `loadAssessments()` (`gtmReadoutsOverview.js:167`) builds `buildQuery(filterValues, sort, offset, 50)` (`gtmAssessmentsTableModel.js:208`), calls `getAssessmentPage`, and REPLACES `rows` when not appending (line 187) with `totalCount` from the server (line 188); the bar's count is `barResultCount` = `totalCount` unless capped (line 226). `handleFilterChange` (235) -> `applyFilters` (254) -> `loadAssessments()`; a stale response is dropped by the `_seq` guard. So the datatable does re-fetch and replace rows on every query change and the count is the server total. No bug found in that chain.

**Per-filter mapping (option value the UI sends -> query member -> WHERE -> real field values).**

| Filter | UI options (label / value) | `AssessmentQuery` member | Apex mapping and WHERE | Real values | Match? |
|---|---|---|---|---|---|
| Status | New / `new`, Contacted / `contacted`, Scheduled / `scheduled`, Completed / `completed`, No Show / `no-show` (`gtmAssessmentsTableModel.js:15-21`) | `status` | `STATUS_BY_KEY` (controller line 38) key -> label; `Status__c IN :statusVals` (line 297) | picklist `Status__c`: New, Contacted, Scheduled, Completed, No Show; demo: Completed, Scheduled, New | YES. Filters work; 3 distinct demo values give 1 row each |
| Readiness tier | Fast-Track / `fast-track`, Accelerator-Ready / `accelerator-ready`, Prep Required / `prep-required`, Discovery First / `discovery-first` (line 23) | `tier` | `TIER_BY_KEY` (line 46); `Assessment_Tier__c IN :tierVals` (line 298) | picklist `Assessment_Tier__c`: Discovery First, Prep Required, Accelerator-Ready, Fast-Track; demo: NOT SET on any request | Values match the picklist; DATA GAP: every tier option returns 0 rows and the Tier column is "-" |
| Ready to book | toggle -> `'ready-to-book'` (`buildQuery` line 218) | `preset` | expanded in `normalise` (controller line 213): status New AND tier in (Fast-Track, Accelerator-Ready) | tier missing in demo | 0 rows in demo (structural) |
| Readout | None yet / `none`, Draft, Waiting on approval / `pending`, Approved, not sent / `approved-unsent`, Published (line 30) | `readout` | derived AFTER the query in Apex (`readoutKey`, line 484): blank -> none, Draft, Pending Approval -> pending, Published, Approved AND not notified -> approved-unsent, ELSE `''` | `GTM_Readout__c.Status__c`: Draft, Pending Approval, Approved, Published; demo: Published, Pending Approval | Works for the demo. LABEL mismatch: column shows the raw `readoutStatus` ("Pending Approval", `mapRow` line 199) while the option says "Waiting on approval" / "Approved, not sent". GAP: an Approved-and-already-sent readout gets key `''`: no option matches it, so those rows cannot be found with any Readout option |
| Submitted | Any time, Last 7/30/90, Custom | `range` | `Submitted_At__c` in range, or `CreatedDate` when `Submitted_At__c` is null (controller line 302) | demo requests have no `Submitted_At__c`, all created at load time | Column ties (it shows the same fallback), but presets all return all rows, custom ranges 0 |
| Offering | derived from the server (`offeringOptions`, distinct `Offering_Key__c`) | `offering` | `Offering_Key__c IN :offeringVals` | demo: one value `migration-accelerator` | Values tie by construction; NO Offering COLUMN in the table, and with one value the filter is a no-op |

**Assessments columns (in order):** Assessment, Contact, Company, Readiness tier, Score, Request status, Readout, Submitted. Filters with no column: Offering, Ready to book (derived).

**Where the option lists were authored.** Status, Tier, Readout: hard-coded constants in `gtmAssessmentsTableModel.js` that mirror the Apex vocabularies (`STATUS_BY_KEY`, `TIER_BY_KEY`, `READOUT_KEYS`); they are correct today but nothing enforces the mirror, so they can drift silently from the picklists. Offering: from the server (data-driven). Pages Funnel stage: hard-coded `STAGE_OPTIONS`; Release 1 Pages filters: data-driven. Nothing derives option labels from the column text.

## T.4 Root causes (ranked)

1. **Pages Funnel stage: option semantics vs column semantics** (`gtmRepLinkFinder.js:33-41` vs `gtmRepLinkTableModel.js:10-16` vs `GtmLinkStageService.cls:70-75,116-126`). Cumulative and behavioural filters against an exclusive single-value column. Not a bug in the code path; a design mismatch that the user reads as "filters tie into nothing".
2. **Demo data cannot exercise the filters** (`data/seed/synthetic-demo.*.json`): no `Form Opened`/`Form Resumed` events, no second visit, all events and requests at one timestamp, all `Active__c` true, one offering, no `Assessment_Tier__c`, no `Assessment_Score__c`, no `Submitted_At__c`. Most filters therefore return all rows or none.
3. **Column/option gaps**: Industry, Deal stage (Pages) and Offering (Assessments) have no column; label mismatches "Turned off"/"Inactive" and "Waiting on approval"/"Pending Approval"; an unreachable readout state (Approved and sent).
4. **Possible runtime races (UNVERIFIED, T.6)** that would make a correct filter appear dead.

## T.5 Proposed fixes (LWC-only vs Apex vs data)

**LWC-only (no Apex, no Apex test run):**
- L1 Pages Funnel stage clarity. Recommended: keep the seven option VALUES and the server semantics (Overview drill-ins, the GUS stage-filter tool and `docs/architecture/gtm-link-stage-filter.md` depend on them) but (a) relabel the cumulative options so they say what they do: "All links sent", "Opened (or further)", "Assessment started (or further)", "Assessment submitted", "Went quiet (started, not submitted)", "Came back (2+ visits, last 48h)", "Not opened yet"; and (b) show the result count per option as today. Files: `gtmRepLinkFinder.js` (`STAGE_OPTIONS` labels; `STAGE_COUNT_FIELD` unchanged), its stage-filter spec. NOTE the earlier user decision "the seven Funnel stage options stay as they are" (C answers): this changes only labels, so it needs the user's approval.
- L2 Link status option label "Turned off" -> "Inactive" (`gtmRepLinkFilterModel.js` `LINK_STATUS_OPTIONS`, branch) and its spec.
- L3 Give every filter a visible column: add Industry (`Industry_Label__c || Industry__c`) and Deal stage (`Opportunity__r.StageName`) columns to the Pages table (`gtmRepLinkTableModel.js` `BASE_COLUMNS_BEFORE_OWNER`, `buildRows` fields, sort keys); add an Offering column to Assessments (`gtmAssessmentsTableModel.js` `COLUMNS`, `mapRow` uses `formatLabel(row.offeringKey)`; `offeringKey` is already on the row). Alternative if the user prefers fewer columns: drop those filters from the row and keep them under More.
- L4 Readout label parity: render the Readout column with the SAME labels as the option list ("Waiting on approval", "Approved, not sent") by mapping `readoutStatus` (+ `readoutNotificationSent`, already on the row) to the option key in `mapRow` (`gtmAssessmentsTableModel.js:199`), `READOUT_STYLE` keys adjusted, spec updated. (The row already carries `readoutNotificationSent`.)
- L5 Hide a single-option filter: when a data-driven filter has fewer than 2 options (Offering with one value), render it disabled or omit it, so a no-op filter is not shown. Careful: `gtmReadoutsOverview.test.js` asserts the six config keys, so do it inside the bar (a `hideWhenSingle` config flag) or keep the key and only mark it disabled.
- L6 Vocabulary parity tests (Jest): assert `STATUS_OPTIONS`, `TIER_OPTIONS`, `READOUT_OPTIONS` values equal the Apex maps' keys via a shared fixture, so drift fails a test.

**Apex (call out; batch with the other Apex deploy, full local test run on `gtm-dev`):**
- A1 `AssessmentRow` gains `readoutKey` (the derived key) and the readout vocabulary gains `approved-sent` ("Approved and sent") so every readout state is filterable; `READOUT_KEYS`, `readoutKey`, the filter and the LWC option list change together. Belongs in the assessments Apex worktree `/Users/isiwintr/Documents/Workbench/worktrees/issue-assessments-account-filters-apex` (same class `GtmAssessmentListController`, same test class, same deploy), so add it there.
- A2 Vocabulary parity test in `GtmAssessmentListControllerTest` (same worktree): `STATUS_BY_KEY`/`TIER_BY_KEY` values must equal `Schema` describe picklist labels for `Status__c` and `Assessment_Tier__c` (hermetic, describe only).
- A3 (optional) `GtmLinkStageService.LinkStat` gains booleans `quiet` and `hot` so the Pages Funnel stage column can show "Went quiet"/"Came back" badges; additive, in `GtmLinkStageService` (a different class, so a separate small change or worktree, batched in the same deploy). Not needed if L1 is accepted.
None of the Apex items is needed to make the CURRENT filters function; they close the gaps in T.4 item 3.

**Data (not code): fix the demo so the filters can be exercised**: `data/seed/synthetic-demo.*.json` and `scripts/seed-synthetic-data.py` plus `scripts/synthetic-demo.plan.json`: add `Assessment_Tier__c` and `Assessment_Score__c` to the three requests (spread across at least three tiers, one Fast-Track New for Ready to book), set `Submitted_At__c` on Completed/Scheduled requests with dates spread over more than 90 days, spread `CreatedDate` where the loader allows (or use `Submitted_At__c`), add `Form Opened` events (cfg2 has a `Drop-off`, so give it `Form Opened` and REMOVE its request or move it to another link so it is "started, not submitted" and therefore "Went quiet"), add a second Page View session within 48 hours for one link ("Came back"), set one link `Active__c = false`, add a second offering key (test-offering already exists in `data/seed`), and a readout that is Approved-and-sent. This alone would make every option produce a visibly different row set.

## T.6 Two candidate runtime races to confirm with the live network capture (UNVERIFIED)

Each is a way a correct filter looks dead. The browser agent should record, per pick, which Apex calls fire and with what arguments.
- R-A Echo reset on Assessments: `applyFilters` sets `filterValues` and starts `loadAssessments()`, then `writeFiltersToUrl()` navigates; the `CurrentPageReference` wire re-fires and `syncFiltersFromState` (`gtmReadoutsOverview.js:117-130`) calls `readFilterState(state, filterConfig)` and compares with `filterValues`. If a wire firing carries the OLD state before the navigation lands (or `buildNavigateArgs` drops the value), `filterValues` is reset to `{}` and an unfiltered fetch replaces the rows. Discriminator: after one pick, does `getAssessmentPage` fire twice, the second with an empty `status`?
- R-B Same on Pages: `captureLinkFinderState` (`gtmRepLinkFinder.js` around line 675) calls `applyStage(readFilterState(state, STAGE_URL_CONFIG).stage || '')` on every re-fire; a stale re-fire with no `c__stage` clears the just-picked stage. Discriminator: after one pick, does `getLinkIdsForStageAura` fire once, and does `stageKey` stay set?
Also capture: (1) is `filterchange` emitted at all on a real pick on the deployed build (trigger text, URL, a call to Apex)? The bar had real-input defects (B.13.2, B.13.3) fixed in 68b4de5/f7a20d8/f329144, all on `origin/main` via #242; confirm the staging build actually contains them; (2) the actual number of Pages rows shown (the code path predicts 4, not 6).

## T.7 What must be tested with REAL input on `gtm-staging` after the fixes

Real mouse and keyboard in the locked single tab; write down rows before and after each pick.
1. Pages, with the improved demo data: each Funnel stage option gives its predicted, DIFFERENT row set and count; the Funnel stage column text of every returned row is consistent with the option's stated meaning (T.5 L1); Went quiet and Came back return at least one row; Link status "Inactive" returns the turned-off link; Offering, Sent, Industry, Deal stage, Account, Contact each change the rows and each has a visible column (L3); count equals the visible rows.
2. Assessments: each Status, Tier, Readout option returns the predicted rows; Ready to book returns the New Fast-Track request; Submitted presets and a custom range include and exclude the expected requests; Offering with a second offering; the Readout column text equals the option label (L4); count text equals the server total; rows are REPLACED (not appended) on each change; Clear filters restores all.
3. Network check for R-A/R-B: one Apex call per pick, argument includes the picked value, no follow-up call with an empty value.
4. Deep links still restore the same rows: `c__stage=not_opened`, `c__astatus=completed`, `c__atier=fast-track`, `c__areadout=published`, `c__arange=30`, Overview drill-ins, the GUS stage-filter tool.
5. Both tabs after a reload with filters in the URL show the SAME rows as before the reload.

## T.8 Where each fix belongs

- LWC-only (L1-L6): the Release 2 Pages branch (`gtmRepLinkFinder/*`) and the Release 3 LWC branch (`gtmReadoutsOverview/*`, `gtmAssessmentsTableModel/*`), or a small standalone LWC-only branch for L1-L4 if the user wants the fix before the folds ship; L2 and the Pages columns depend on Release 1's `gtmRepLinkFilterModel.js`, so they go on top of `agent/issue-compact-filters-r1`.
- Apex A1 and A2: in the existing worktree `/Users/isiwintr/Documents/Workbench/worktrees/issue-assessments-account-filters-apex` (same class, same test class, same deploy, same full-test-run batch). A3 only if L1 is rejected, in a separate small change.
- Data fix: `data/seed/*` and `scripts/seed-synthetic-data.py`; no deploy, loaded to `gtm-staging` only.
