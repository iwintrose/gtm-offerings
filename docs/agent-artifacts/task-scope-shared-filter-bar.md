# TASK SCOPE — ISSUE #shared-filter-bar

## 0. Investigation Summary (read-only)

- **Precedent:** `gtmModalShell` (`force-app/main/default/lwc/gtmModalShell/`, contract `docs/architecture/gtm-modal-shell.md`, Jest in its `__tests__/`) is presentation-only, has a documented Props/Slots/Events table, and dispatches only its own events. The new component copies that shape.
- **URL-state idiom today:** `gtmReadoutsOverview.js` (~L87-126) reads `c__*` params in a `@wire(CurrentPageReference)` handler and writes them with `window.history.replaceState` (a real navigation would remount the tab). `gtmRepLinkFinder.js` (~L443-507) does the same with an `rlf`-prefixed namespace (`c__rlfMode`, `c__rlfAccountId`, ...) so it cannot collide with `gtmPageBrowser`'s `c__template/c__recordId/c__company/c__offering`. Existing params that a filter util must never disturb: `c__assessmentRequestId`, `c__readoutId`, `c__offeringKey`, `c__browseMode`, `c__repDirectId`, `c__rlf*`, `c__rafAccountId`, `c__rafContactId`, `c__template`, `c__recordId`, `c__company`, `c__offering`. The existing write idiom rebuilds only its own keys on a `URL` object and leaves the rest alone. The util should reuse that approach rather than invent NavigationMixin navigation (see fork F1).
- **Styling:** this repo has no CSS custom-property design tokens. "Tokens" are literal hexes repeated per component. The new component must reuse only hexes already in use: `gtmRepLinkFinder.css` toggle buttons (`.rlf-toggle-btn`: border `#dedede`, bg `#fff`, text `#444`, hover border `#0176d3`, active bg/border `#0176d3` with `#fff` text), card surface (`#fff`, border `#e5e5e5`, radius `.25rem`), muted text `#747474`, body `#181818`; `gtmOverview.css` pills (`.pill--info` `#dce9fb`/`#0b3d75`, `.pill--good` `#d7f0e0`/`#14532d`, `.pill--warn` `#fdeacb`/`#7a4a05`, `.pill--quiet` `#ececec`/`#545454`), the selected-ring `rgba(11, 61, 117, .35)`, and divider `#f0f0f0`. Active-filter chips should use the `.pill--info` pair. No new hex values.
- **Sibling issues:** `stage-filter-pages-tab` and `assessments-tab-filter` (the latter already has a commit `ad30f1d` scoping a filter bar on the Assessments tab; the Architect should reconcile that scope with this shared component) CONSUME this issue and **cannot start implementation until `shared-filter-bar` has merged**. Nothing here wires either tab.

## 1. Requirements Breakdown

- **Target Objective:** One reusable filter capability usable anywhere in the app. The Pages tab (funnel stages) and the Assessments tab (status/tier/readout/date/offering) must share one component, one behaviour and one URL-state convention. Only the placement varies (tab body, card header, modal). GUS chat will later speak the same filter keys. This issue delivers only the shared primitives and their contract:
  1. `gtmFilterBar` LWC. Presentation-only and config-driven.
     - `filters` array. Each entry has `key`, `label`, `type` (`chips` | `select` | `toggle` | `date-range`), `options` (`[{value,label,count?}]`) and `param` (URL param name).
     - `values` map (`{ [key]: value }`; `chips` and `select` may be multi-valued as an array, an Architect decision, see F3; `date-range` value is `{from,to}` or a preset token).
     - `result-count` display, optionally with a noun label.
     - Active-filter chips, each individually removable.
     - "Clear all".
     - Full-width and compact (`variant="compact"`) layouts. Wraps in narrow containers.
     - Keyboard and ARIA behaviour: `role="group"` with a label, `aria-pressed` on toggle/chip buttons, `aria-live="polite"` count, removable chips reachable and operable by keyboard, visible focus.
     - Dispatches ONE `filterchange` event `{key, value}` and `clear`. No Apex, no domain knowledge, no built-in filtering.
  2. `gtmFilterUrlState` JS utility module (a plain module under `lwc/`, not a component). Maps a config's `param` names to and from `c__` page state.
     - `readFilterState(pageRefState, filters)` returns a `values` map from the wired `CurrentPageReference.state`.
     - `buildFilterUrlState(currentState, filters, values)` returns a new state object.
     - `writeFilterState(...)` applies it via the repo's `replaceState` idiom or the NavigationMixin state update (F1).
     - It touches ONLY the config's own params. Every other `c__` param, including `c__assessmentRequestId` and `c__repDirectId`, is preserved byte for byte. Empty and default values remove the param, so URLs stay clean. Unknown or invalid values (not in `options`) are ignored on read.
  3. Architecture contract `docs/architecture/gtm-filter-bar.md` with these sections.
     - Props, events and slots table.
     - Config schema.
     - URL rules: `c__` prefix, per-consumer namespacing to avoid collisions, multi-value encoding, date encoding, and the rule that URL is the source of truth on refresh.
     - Server-side convention: each domain exposes ONE Apex method taking the filter-key set and returning `{rows, counts, total}`. It uses no DML, `with sharing` / `WITH USER_MODE`, and cacheable if read-only. The component, its page, the Overview funnel counts and the GUS tools all call that same method, so all four agree. The GUS filter keys are exactly the config `key`s.
     - Worked example configs, documented only and not implemented. (a) Pages: one `chips` filter keyed `stage` with values `sent|engaged|started|submitted|quiet|hot`. (b) Assessments: `status`, `tier`, `readout`, `range` (`date-range`) and `offering`. The Architect must confirm the exact option values against the code (F2).
  4. Jest tests: `gtmFilterBar/__tests__/gtmFilterBar.test.js` and `gtmFilterUrlState/__tests__/gtmFilterUrlState.test.js`.
- **System Component Impacted:** LWC only, at `force-app/main/default/lwc/gtmFilterBar/` (new) and `force-app/main/default/lwc/gtmFilterUrlState/` (new JS module), plus a new doc under `docs/architecture/`. No Apex, Custom Metadata, Experience Cloud route or YAML instrument is changed. **Out of scope:** any domain filtering logic, wiring on either tab, Apex methods, GUS tool changes.
- **Open forks flagged for the Architect (not settled here):**
  - **F1, URL write mechanism.** The existing idiom is `history.replaceState` (no remount, no history entry). The owner wording says "NavigationMixin/state update". `NavigationMixin.Navigate` with a `state` merge creates history entries and may remount the tab in Lightning, whereas `replaceState` is proven in this repo. Recommend the util exposes a pure state builder plus one writer, defaulting to `replaceState`. Architect to check the Salesforce docs (per the team's rule) before deciding.
  - **F2, exact filter vocabularies.** Pages stage keys (`sent|engaged|started|submitted|quiet|hot`) and the Assessments status/tier/readout/offering options must be taken from the existing funnel and assessment code (`gtmOverview.js`, the readouts overview), not from this scope. Do not trust the list above without checking; it is the owner's wording.
  - **F3, single vs multi-select.** Whether `chips` is single- or multi-valued, and how multi-values are encoded in the URL (comma-separated is the likely choice). This affects the `filterchange` `value` shape, and GUS keys must match.
  - **F4, param namespacing.** A bare `c__stage` could collide when both tabs are embedded in the same app page. Recommend a consumer-supplied `param` such as `c__pgStage` / `c__asStatus`, following the `rlf` precedent.
  - **F5, `assessments-tab-filter` prior work.** Commit `ad30f1d` already scoped a filter bar on the Assessments tab. The Architect must reconcile it so the tab does not build a bespoke bar.
  - **F6, GUS zero-DML.** The GUS tool surface is untouched here, but the contract fixes the future rule that GUS calls the same read-only Apex method.
  - No `gtm-dev` production data is touched by this issue.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No. This issue only documents the future server convention (read-only, zero DML per AGENTS.md §1) and does not touch any GUS tool. N/A.
- [ ] Altering Custom Metadata? No. Pure LWC, JS and docs. N/A.
- [ ] Introducing database fields? No. No new schema, so no Permission Set mapping is needed. N/A.

## 3. Plan Acceptance Criteria

- **Success Metric:** QA passes when all of the following hold.
  - `gtmFilterBar` renders each of `chips`, `select`, `toggle` and `date-range` from a `filters` config.
  - It shows the result count and one removable chip per active filter, and a "Clear all" control.
  - It dispatches exactly one `filterchange` `{key,value}` per user change, and `clear` on Clear all or on removing the last chip.
  - The chips, chip-remove buttons, toggle and Clear all are keyboard operable with correct ARIA (`aria-pressed`, labelled group, `aria-live` count).
  - The compact variant renders.
  - The component makes no Apex import and contains no domain terms.
  - The CSS introduces no hex value that is not already present in `gtmRepLinkFinder.css` or `gtmOverview.css`.
  - The `gtmFilterUrlState` round trip (config, URL state, values, config) is lossless.
  - Writing filters leaves unrelated `c__` params (`c__assessmentRequestId`, `c__repDirectId`, and others) untouched, and empty values remove only the config's own params.
  - `docs/architecture/gtm-filter-bar.md` exists with props, events, URL rules, the server convention and both worked example configs, and neither consumer tab is modified.
  - `npm test` and the repo's local validation stay green.
  - **Merge ordering:** `stage-filter-pages-tab` and `assessments-tab-filter` depend on this issue merging first. Neither may start implementation until it has merged.
- **Target Test Target:** LWC Jest specs `force-app/main/default/lwc/gtmFilterBar/__tests__/gtmFilterBar.test.js` and `force-app/main/default/lwc/gtmFilterUrlState/__tests__/gtmFilterUrlState.test.js` (run with `npx sfdx-lwc-jest -- gtmFilterBar gtmFilterUrlState`, then full `npm test`). No Apex test class applies.

---

## 4. ARCHITECT ADDENDUM (2026-09-19) — binding on Developer/QA

Scope review: no placeholders; all three Code Dependency Checklist items are N/A (no GUS tool change, no custom metadata, no fields, so no permission-set work). Approved with the decisions below. Where this addendum conflicts with section 1, this addendum wins.

### 4.1 Standing rule: Salesforce-native first (product owner, 2026-09-19)

The component is a THIN COMPOSITION of base `lightning-*` components plus our config/URL-state contract. No hand-built controls.

(a) Base components evaluated

| Need | Use | Notes |
|---|---|---|
| `select` filter | `lightning-combobox` | `options`, `value`, `onchange`. Native. |
| `chips`, multi-select | `lightning-checkbox-group` with `type="button"` (button-style toggles) | Native multi-select; value is `string[]`. No aria-pressed hand-rolling needed, the base component owns the semantics. |
| `chips`, single-select | `lightning-radio-group` with `type="button"` (or `lightning-button-group` if the group needs icons) | Native single-select with the same look. |
| `toggle` | `lightning-input type="toggle"` (or `type="checkbox-button"`) | Native. |
| `date-range` | `lightning-combobox` of presets (7/30/90 days, "Custom") plus two `lightning-input type="date"` (from/to) shown only for Custom | `lightning-input type="date"` IS the base datepicker. Do not use the unexported `lightning-datepicker` directly. |
| Active-filter chips, individually removable | `lightning-pill-container` (`items`, `onitemremove`) | Native keyboard removal and ARIA. |
| Clear all | `lightning-button variant="base"` | |
| Search box | `lightning-input type="search"` is NOT needed: no filter type here is free text. Do not add one. | |
| Result count | `<p aria-live="polite">` | Plain text; nothing native exists. |
| Group label | `<fieldset>`/`<legend>` or `role="group"` `aria-label` | |

(b) Standard list-view filtering evaluated and rejected. List-view filters (`lightning-list-view`, list-view filter panel) only apply to standard object list views. Our consumers are custom LWC tabs over aggregated, Apex-computed rows (funnel stage definitions, joined readout/request grain), which list-view filters cannot express. Not usable here.

(c) Standard navigation/state: USED. `NavigationMixin` and `@wire(CurrentPageReference)` are the state mechanism (see F1). Nothing custom for routing.

What custom logic remains, and why (this is the whole of it)
1. `gtmFilterBar` template: the mapping from a `filters` config to the right base component per `type`, the `values` map to base-component `value` translation, the derived pill list, the result-count line, and the single normalised `filterchange {key, value}` / `clear` events. No native component maps a config to a bar or normalises events.
2. `gtmFilterUrlState` module: pure functions `readFilterState`, `buildFilterUrlState`, and a thin `writeFilterState`. No native helper turns a filter config into `c__` state, validates values against options, or protects sibling params.
3. Layout CSS for `variant="compact"` and wrapping only (SLDS utility classes first; the hex allowlist in section 1 still applies to anything left).
Anything beyond these three is a review failure.

Jest note: `lightning-*` stubs from `@salesforce/sfdx-lwc-jest` are used; tests drive the base components via their `change`/`itemremove` events rather than DOM buttons.

### 4.2 Fork decisions

- **F1 (URL write): DECISION = `NavigationMixin.Navigate` with the SAME `standard__navItemPage` page reference and a merged `state`, `replace = true` (the second argument of `Navigate(pageRef, replace)`).** Reasons: it is the documented, supported way to change the state of the current page; it updates Lightning's own page reference so `CurrentPageReference` re-fires and the URL, refresh and back/forward stay consistent, whereas `history.replaceState` bypasses the router (the wire goes stale and the router can mis-restore on back). `replace=true` avoids one history entry per chip click so Back leaves the tab rather than stepping through filter states; the writer takes an option `{ mode: 'replace' | 'push' }` (default `replace`) for a consumer that wants push. State keys must use the `c__` prefix (platform rule for `standard__navItemPage` state). Caveats the Developer MUST implement:
  1. The `Navigate` call needs the component instance (mixin), so the util does NOT navigate itself. `gtmFilterUrlState` exports pure `readFilterState` / `buildFilterUrlState` and `buildNavigateArgs(pageRef, filters, values, {mode})` returning `{ pageReference, replace }` (same `type` and `attributes`, `state` merged); the consumer does `this[NavigationMixin.Navigate](pageReference, replace)`. The bar/consumer never uses `window.history` for filter params.
  2. Mixed-writer hazard: `gtmReadoutsOverview` and `gtmRepLinkFinder` still write their own selection params with `history.replaceState`, so the wired `CurrentPageReference.state` can be STALE against the real URL. To avoid a filter navigate dropping `c__assessmentRequestId`, `c__repDirectId`, `c__rlf*` etc., export `mergeLocationState(pageRefState)` which overlays every `c__*` from `window.location.search` onto the wired state; the consumer passes that as `currentState`. Untouched params are preserved byte for byte. Jest covers this (jsdom `window.location`).
  3. Consumers must treat a re-fired `CurrentPageReference` as idempotent (re-read filters, no double fetch when values are unchanged). Document this in the contract.
  4. UNVERIFIED and not testable without a live org (not authorised): whether the tab component is re-created or only receives the new state on a state-only Navigate. Live Salesforce docs could not be browsed from this environment; the decision rests on the documented `Navigate(pageRef, replace)` API and `CurrentPageReference` behaviour. The BA's remount claim is unsourced (the existing repo comments only say replaceState avoids "a real navigation"). Mitigation: all writing goes through the single `buildNavigateArgs` function so switching to `replaceState` later is a one-function change. The first consumer issue (`stage-filter-pages-tab`) must include a note in its QA checklist to confirm no remount/flicker on a chip click once a deploy is authorised; if it remounts, fall back to `replaceState` in that one function and record it in the contract.
  Existing `history.replaceState` use in `gtmRepLinkFinder`/`gtmReadoutsOverview` is NOT migrated in this issue.
- **F2 (vocabularies): the component and util are vocabulary-free.** Option values live only in the consumer configs. The sibling issues own and must verify their vocabularies against code/picklists. Flag from review: the owner wording for Pages (`sent|engaged|started|submitted|quiet|hot`) is missing `not_opened`, which `task-scope-stage-filter-pages-tab.md` defines; the Assessments tab (`Status__c`: New/Contacted/Scheduled/Completed/No Show; `Assessment_Tier__c`: Discovery First/Prep Required/Accelerator-Ready/Fast-Track; readout Draft/Pending Approval/Approved/Published) are in the sibling scope and carry open forks (row grain, "Ready to book" tier semantics). The worked examples in `docs/architecture/gtm-filter-bar.md` must be labelled ILLUSTRATIVE, must NOT be treated as the authoritative vocabulary, and must point to the sibling scopes/Apex as the source. Unknown values on read are dropped by validation against the config's own `options`.
- **F3 (single vs multi): `chips` supports both.** Config flag `multi: true|false` (default false). `filterchange.value` is a string for single, `string[]` for multi (empty selection = `''` / `[]`, meaning "remove"). URL encoding for multi: ONE param, comma-separated values (`c__stage=quiet,hot`); option values must not contain commas (util rejects such option values at config time in dev, and drops them on read). `select` is single-valued only in this issue. `date-range` value is a preset token (`7`, `30`, `90`) or `{from,to}` (ISO `YYYY-MM-DD`), encoded as the preset token alone or `YYYY-MM-DD..YYYY-MM-DD` in the one param. GUS filter keys equal the config `key`s and multi means an array.
- **F4 (param names): consumer-prefixed, supplied via each filter's `param`. Never generic names.** `c__stage` (Pages, the owner-named param) and `c__astatus` / `c__atier` / `c__areadout` / `c__arange` / `c__aoffering` / `c__apreset` (Assessments). The util rejects (throws in dev/test, ignores in prod) a `param` that is not `c__`-prefixed or that collides with the reserved list in section 0 (`c__assessmentRequestId`, `c__readoutId`, `c__offeringKey`, `c__browseMode`, `c__repDirectId`, `c__rlf*`, `c__rafAccountId`, `c__rafContactId`, `c__template`, `c__recordId`, `c__company`, `c__offering`), and unit tests assert it.
- **F5 (assessments-tab-filter): superseded.** Commit `ad30f1d` on `main` scoped a bespoke Assessments bar. That scope is SUPERSEDED by the amended scope on `ba-scope/issue-assessments-tab-filter`, which makes `gtmReadoutsOverview` consume `gtmFilterBar` + `gtmFilterUrlState`. `assessments-tab-filter` must not build its own bar or URL read/write for filters. Its scope's line "each touches only its own keys via replaceState" is amended by F1 above: filter params are written via `buildNavigateArgs`; the tab's own selection params keep `writeSelectionToUrl()` until a separate migration, with `mergeLocationState` protecting both. The next Architect pass on that issue must apply this.
- **F6 (GUS): untouched.** No GUS tool, no Apex. The contract documents only the future read-only method convention (zero DML, zero callout inside a tool, per AGENTS.md §1).

### 4.3 Consumers and layout requirements

- Consumers: `stage-filter-pages-tab` (Pages tab, param `c__stage`, chips) and `assessments-tab-filter` (Assessments tab). Both are blocked until this issue merges.
- Placement independence: a future consumer may place the bar in a card header. The component must NOT assume full width: no fixed widths or viewport assumptions, flex-wrap layout, `variant="compact"` drops the label/count row spacing and uses `label-variant="label-hidden"`/small sizes on base components, and must render sensibly at ~320px container width (Jest asserts the compact class; QA checks wrapping by reading CSS, no live browser needed).

### 4.4 Execution restrictions

- LWC-only, Jest is sufficient. NO live deploy, NO Apex test run, NO other execution against `gtm-dev` is authorised for Developer or QA (`gtm-dev` is Production). Do not run `deploy.sh`, `sf project deploy`, or `sf apex run test`. Validation = `npx sfdx-lwc-jest -- gtmFilterBar gtmFilterUrlState`, full `npm test`, and the repo's local validation scripts (no org).
- Contract-first: write `docs/architecture/gtm-filter-bar.md` BEFORE the code (section 1 item 3, plus 4.1, 4.2 and 4.3 above).
- No edits to `gtmOverview`, `gtmReadoutsOverview`, `gtmRepLinkFinder`, or any Apex/GUS file.
