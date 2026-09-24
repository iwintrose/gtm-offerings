# GTM Column Chooser (Pages and Assessments tables)

Status: contract (Architect). Source of truth for the Developer and QA. Scope: `docs/agent-artifacts/task-scope-table-columns.md`. No Apex, metadata, permission-set or Experience Cloud change (Code Dependency Checklist: all three NO, agreed; AGENTS.md section 1 GUS tool surface is not touched).

HONEST LIMITS. The Architect has no browser or org access and no web/doc tool in this session. Everything about `lightning-checkbox-group` internals, datatable width recalculation and real focus order is UNVERIFIED and is marked so; each is a QA check on `gtm-staging`. `gtm-dev` is Production and is NOT a deploy target. Nothing here is verified against Salesforce documentation (no doc tool); claims about base-component behaviour come from the repo's own B.13 notes in `gtm-filter-bar.md`.

## 1. Verified inventory (origin/main dc5005c)

- Pages (`gtmRepLinkTableModel.js` `buildColumns(showOwner)`): 9 data columns (company, contactName, offeringLabel, opportunityName, funnelLabel, visits, lastVisitAt, statusLabel, createdDate), plus `ownerName` when `showOwner` (10), plus one `type: 'action'` column (row action `Open`). All data columns sortable; client sort in `sortRows`; default `sortedBy = 'lastVisitAt'`. `gtmRepLinkFinder.js` `get columns()` calls `buildColumns` on every access (new array identity every render).
- Pages open path: column 1 button (`typeAttributes.name = 'open'`, disabled when no account) AND the row action `Open` both fire `rowaction` name `open`. So Company is NOT the only way in on Pages; no pinned column on Pages (last-column guard only). Release 2 adds more row actions to the same action column.
- Assessments (`gtmAssessmentsTableModel.js` `COLUMNS`): 8 columns (name, contactUrl, companyUrl, tierLabel, score, requestStatus, readoutLabel, submittedAt). `name` (button, label Assessment, initialWidth 120) is the ONLY non-sortable data column and the ONLY way into the workspace (no action column). Server sort via `SORT_KEY_BY_FIELD` (contactUrl, companyUrl, tierLabel, score, requestStatus, readoutLabel, submittedAt); `mapRow` already emits `offeringKey` (line ~202), so no Apex change.
- Overview results card (`gtmOverview.js` line 13) imports `COLUMNS as ASSESSMENT_COLUMNS` and looks up columns by `fieldName` (`.find`). Its own `RESULT_COLUMNS` are 4, unsortable. The `COLUMNS` export shape (array of 8 objects, order, keys) MUST NOT change. `gtmOverview.html` has exactly one datatable (`.ar-table`).
- Other datatables: `gtmRecycleBin` (6 + action) and `gtmAssessmentSubmissionView` (3): out of scope. The BA inventory is correct.
- Scope review: compliant with CLAUDE.md and AGENTS.md (no placeholders left; the `gtm-staging`-only rule, no persistence, contract-first, Salesforce-first evaluation all present). Corrections to the scope: (a) Pages Company is not the sole opener (row action `Open` exists), so nothing on Pages is pinned; (b) `lightning-checkbox-group` per-option disabled is UNVERIFIED and probably unsupported, so pinned columns are NOT offered as checkboxes (section 4); (c) the scope proposes hiding the chooser with the table: keep that.

## 2. Decisions (coordinator defaults applied)

1. Assessments default: `name` (pinned), `companyUrl`, `tierLabel`, `requestStatus`, `readoutLabel`. Chooser adds Contact, Offering, Score, Submitted.
2. Kebab is not counted; the pinned opener is.
3. Pages default: `company`, `contactName`, `funnelLabel`, `lastVisitAt`, `statusLabel`. Chooser adds Offering, Opportunity, Visits, Saved, and Owner whenever `showOwnerColumn` (including View All).
4. No persistence: memory only, parent field. No storage, URL param, setting, object. Reload and tab switch reset. Filter change, no-match then Clear, and Back to links must NOT reset (parent must not remount; QA confirms).
5. Hidden sorted column: sort is kept silently, no re-query, no hint.
6. Offering offered on Assessments (new `OFFERING_COLUMN`, section 6).
7. Recycle Bin excluded. 8. Narrow: the table scrolls horizontally inside its own wrapper. 9. Build the component and contract now (phase A); wire Pages after Release 2 and Assessments after Release 3 (phase B).

## 3. Contract: `c-gtm-column-chooser` (`force-app/main/default/lwc/gtmColumnChooser/`)

Presentational and CONTROLLED: it owns only open/close state. It never queries, never persists.

Props (`@api`):
| Prop | Type | Meaning |
|---|---|---|
| `columns` | `Array<{key: string, label: string, default?: boolean, pinned?: boolean}>` | The full catalogue in canonical order (parents build it with `buildCatalogue`, section 5). `key` = datatable `fieldName`. |
| `selectedKeys` | `string[]` | The parent's current visible keys (any order; the chooser normalizes with `normalizeKeys`). `undefined` or `null` means defaults. |
| `label` | string, default `'Columns'` | Trigger text. |

Event: `columnschange`, `CustomEvent` (bubbles false, composed false), `detail: { keys: string[] }` = the resulting visible keys INCLUDING pinned keys, in catalogue order. Fired once per tick and once per Reset. There is no separate reset event. The chooser never mutates `selectedKeys`; if the parent ignores the event nothing changes (controlled).

Derived display: `shown = normalizeKeys(...).length`, `total = columns.length`. Trigger accessible name: `Columns, {shown} of {total} shown` (via `aria-label` on the `<button>`; visible text `Columns` plus a `utility:table` or `utility:column` icon; no count badge needed). A visually hidden `aria-live="polite"` region (`slds-assistive-text`, sibling of the button, outside the popover) is updated on each change with `{shown} of {total} columns shown` (datatable does not announce column changes; whether it does is UNVERIFIED, QA/VoiceOver check).

Markup: wrapper `div.gtm-col-chooser` (position: relative; the bubbling handlers live here); `<button type="button" class="slds-button slds-button_neutral" aria-haspopup="dialog" aria-expanded aria-controls>`; popover `div[data-pop][role="dialog"][aria-label="Choose columns"][tabindex="-1"]` (non-modal, no trap, no backdrop, same reasoning as B.13.3); inside: optional line `Always shown: {pinned labels}` (text, only when pinned columns exist), `lightning-checkbox-group` (label "Columns", `variant="label-hidden"`), inline hint text (role `status`) for the last-column guard, and `lightning-button` "Reset to default" (`variant="base"` or neutral, `disabled` when the visible set already equals the default).

Behaviour:
- Ticks apply immediately, no Apply, no draft. The group `value` = selected non-pinned keys; `options` = non-pinned catalogue entries `{label, value}`.
- Pinned guard: pinned entries are NOT options (per-option `disabled` on the group is UNVERIFIED; do not rely on it). They are listed in the static "Always shown" line, and `normalizeKeys` always re-adds them, so no code path can hide one.
- Last-column guard: if a change would leave zero visible columns (only possible when nothing is pinned, i.e. Pages), ignore it: emit nothing, show the hint "At least one column must stay shown", and force the group back to the prior value by re-creating it (wrap the group in a one-item `for:each` keyed by a `_rev` counter; increment on violation). Whether re-assigning a fresh `value` array alone would revert the checkbox in the base component is UNVERIFIED, which is why the recreate is specified; QA verifies with a real click.
- Reset: emits `columnschange` with `defaultKeys(columns)` (pinned included, canonical order); leaves the popover open and focus on the Reset button (which then becomes disabled, so move focus to the group when disabling would drop it: focus the popover container as fallback).
- Canonical order: emitted keys follow catalogue order, never tick order.

### 3.1 Which of gtm-filter-bar.md B.13.x apply

APPLY (reuse the exact pattern, names and timings from `gtmFilterBar.js` `_open`, `_close`, `_attachDocClick`, `_detachDocClick`, `_markInside`, `handlePointerDown`, `handleWrapperClick`, `handleKeydown`, `handleFocusOut`, `renderedCallback`, `_clamp`, `_clearTimers`, `disconnectedCallback`, reduced to a single popover and a boolean `_open` instead of `_openKey`):
- B.13.2: `focusout` closes ONLY when `relatedTarget` is a real Element (`nodeType === 1`) that is neither the popover content nor the trigger and not the host; null, document/window, inside the popover, the own trigger, `_settling`, and `_pointerDown` never close. `_pointerDown` set on pointerdown/mousedown (500 ms safety, cleared 0 ms after click). `_settling` for the open-time programmatic focus move. Timers and listeners cleared in `_close` and `disconnectedCallback`.
- B.13.3: bubbling `pointerdown`, `mousedown`, `click`, `keydown` handlers on the wrapper in the chooser's OWN shadow call `_markInside()` (flag cleared with `setTimeout(0)`); the document `click` listener (a) is attached in a `setTimeout(0)` after the opening click, (b) returns immediately when `_insideInteraction` is set, (c) never closes synchronously (closes in `setTimeout(0)` with the flag re-checked). The old `composedPath`/`contains` checks are kept only as an extra inside signal. No backdrop (no `position: fixed`).
- B.13.4/B.13.5 content-stable identities: CRITICAL here, because the parent re-renders on every tick (new `columns` array from a getter, new `selectedKeys`) and the base group would replace its inputs mid-click (the exact Assessments failure). Keep `_stable` memoisation compared by JSON content for BOTH the `options` array and the `value` array given to `lightning-checkbox-group`; the catalogue prop setter must not reset `_open`. `value` legitimately changes after a tick (content differs), `options` must keep identity across ticks.
- Tab-away rule (B.13.5): Tab from inside the popover to any Element outside (the filter bar's triggers, Clear filters, the table) closes it. Tab from the trigger into the popover must not.
- Escape: `keydown` Escape while open calls `event.stopPropagation()`, closes and returns focus to the trigger.
- One popover at a time: the chooser lives in its own shadow. Opening it: a click on the chooser is an outside click for the filter bar (its deferred document listener closes any open filter popover). Opening a filter popover: the chooser's document listener sees an outside click and closes it. Tab across the two closes the previous one via its own `focusout` rule (the filter bar's `relatedTarget` is retargeted to the chooser host, an Element outside its popover, so it closes). QA verifies each direction with real input.
- One-shot viewport clamp on open (`_clamp`, EDGE constant) and `max-width: calc(100vw - 1rem)`; the popover is right-anchored (`right: 0`) because the chooser is at the end of the toolbar row, so clamp handles the left edge.
- Focus on open: first focus the `lightning-checkbox-group` (guard `typeof focus === 'function'`), fall back to the popover div; in `renderedCallback`, guarded by `_focusPending`, never call `_open`/`_close` from render.

DO NOT APPLY: single-select close-on-pick; search input and per-filter `_search`; drafts, Apply and custom date range (C.8); the `_openKey` multi-slot model and the More add flow; `filterchange`/`clear` events.

### 3.2 Shared helper vs copy (recommendation)

Recommendation: COPY the pattern now into `gtmColumnChooser.js` (about 90 lines, single popover), and do NOT extract a shared popover module in phase A. Reasons: extraction must edit `gtmFilterBar.js`, which compact-filters releases R1b onwards are editing (guaranteed conflict and re-test of a component that took three real-input fixes); a behavioural regression in the filter bar would be paid in Production-type risk with no staging safety net; a copy is 1 file and easy to test. To make a later extraction mechanical, keep the popover block in the chooser as a contiguous section with the same method names as the filter bar, marked `// POPOVER MECHANICS (mirrors gtmFilterBar B.13.2-B.13.5)`. Follow-up (separate task, after compact-filters merges): extract `gtmPopoverController` (a plain class taking `{getWrapper, getPop, getTrigger, onClose}`) and migrate both components; not part of this change.

Styling: SLDS classes, plus the small CSS the filter bar uses for `.gtm-filter-bar__pop` (absolute, background `var(--slds-g-color-neutral-base-100, #fff)` or the same tokens the filter bar CSS already uses, border, radius, `z-index` above the datatable, box shadow). Dark theme: use only SLDS styling hooks/tokens or the same token/fallback pairs already in `gtmFilterBar.css`; NO new hex literals outside the existing allowlist (`scripts/check-references.py`). QA checks the popover in dark theme.

Narrow width: the trigger never truncates below its icon; the popover is `max-width: calc(100vw - 1rem)`, `max-height: 20rem; overflow: auto`, clamped on open. Placement (section 7) wraps.

Keyboard: Tab reaches the trigger (after the filter bar in DOM order, before the table); Enter/Space toggles; focus moves to the group; Space toggles a checkbox; Tab moves to Reset then out (closing per the Tab-away rule); Escape closes and refocuses the trigger.

## 4. Pure helper (`force-app/main/default/lwc/gtmColumnState/gtmColumnState.js`, module-only, js-meta `isExposed=false` like `gtmAssessmentsTableModel`)

```js
buildCatalogue(allColumns, defaultKeys, pinnedKeys = [])
  // -> [{ key: col.fieldName, label: col.label, default: defaultKeys.includes(key) || pinned, pinned }]
  // skips columns without fieldName/label (the action column); preserves order.
defaultKeys(catalogue)            // keys where default || pinned, catalogue order
normalizeKeys(catalogue, keys)    // drop unknown, add pinned, catalogue order, de-dupe;
                                  // if empty -> defaultKeys(catalogue); null/undefined -> defaults
visibleColumns(allColumns, catalogue, keys)
  // -> allColumns filtered to: columns WITHOUT a fieldName (the action column) always kept,
  //    plus columns whose fieldName is in normalizeKeys(catalogue, keys); same object identities, same order.
isDefault(catalogue, keys)        // normalizeKeys deep-equals defaultKeys
isSortedColumnVisible(visibleCols, sortedBy)  // true if some column has fieldName === sortedBy
```
Pure, no LWC imports, never mutates inputs, tolerant of null/undefined arrays. Because `visibleColumns` keeps the original column objects, `sortable`, `typeAttributes`, `cellAttributes`, `initialWidth` are untouched.

## 5. Parent wiring (phase B)

Common: a parent field `visibleKeys = undefined` (memory only). Catalogue memo (recompute only when the column list identity/showOwner changes): `catalogue = buildCatalogue(allColumns, DEFAULT_COLUMN_KEYS, PINNED_COLUMN_KEYS)`. `columns` for the datatable is MEMOIZED by `(showOwner, JSON of normalized keys)`: do not return a new array from a getter on every render (today's Pages `get columns()` does; a new `columns` identity per render can reset datatable widths/scroll; UNVERIFIED, QA). Handler: `handleColumnsChange(e) { this.visibleKeys = e.detail.keys; }`. Do NOT reset `visibleKeys` in any filter, sort, load, page-reference or Back-to-links handler; do not put the state in a child that an `if:true` unmounts.

Sorting when the sorted column is hidden: keep `sortedBy`/`sortBy`/`sortDir` and the row order; pass `sorted-by={effectiveSortedBy}` = `sortedBy` only when `isSortedColumnVisible`, else `undefined` (datatable then shows no arrow; passing a non-column field is UNVERIFIED, hence the guard). The direction stays. Pages: `sortRows(..., this.sortedBy, ...)` unchanged. Assessments: `sortBy`/`sortDir` are not touched and `getAssessmentPage` is NOT re-called on a column change (assert in Jest). Showing the column again restores the arrow with no extra work. Header sort clicks work on visible columns as today.

Pages (`gtmRepLinkFinder`):
- `gtmRepLinkTableModel.js`: keep `buildColumns` unchanged (all columns, action last); add `export const DEFAULT_COLUMN_KEYS = ['company','contactName','funnelLabel','lastVisitAt','statusLabel'];` and `export const PINNED_COLUMN_KEYS = [];`.
- Catalogue built from `buildColumns(showOwnerColumn)`; Owner appears when `showOwnerColumn` (never in default). `showOwnerColumn` can flip after stats load: a stored `ownerName` key stays valid, unknown keys are dropped by `normalizeKeys`.
- Template: wrap the filter bar and the chooser in `div.rlf-toolbar` (display flex, `align-items: flex-start`, `gap`, `flex-wrap: wrap`; the bar container `flex: 1 1 auto; min-width: 0`, the chooser `flex: 0 0 auto`), chooser rendered only when `hasTableRows` (the bar is outside that template today, hence the wrapper decision below). NO slot in `gtmFilterBar` (shared, edited by in-flight releases). Because the chooser must hide when the table hides but the bar does not, render the chooser inside the wrapper under `if:true={hasTableRows}`; the bar keeps its own `showFilterBar` gate.
- The action column (Open and R2's actions) is never part of the catalogue and is always kept by `visibleColumns`.

Assessments (`gtmReadoutsOverview`):
- `gtmAssessmentsTableModel.js`: `COLUMNS` UNCHANGED and still exported (Overview and its specs). Add `DEFAULT_COLUMN_KEYS = ['name','companyUrl','tierLabel','requestStatus','readoutLabel']`, `PINNED_COLUMN_KEYS = ['name']`, `OFFERING_COLUMN = { label: 'Offering', fieldName: 'offeringKey', type: 'text', sortable: false }` (not in `SORT_KEY_BY_FIELD`: no server sort key, no Apex change) and `TABLE_COLUMNS` = `COLUMNS` with `OFFERING_COLUMN` inserted after Company. Only `gtmReadoutsOverview` uses `TABLE_COLUMNS`; `gtmOverview` keeps `COLUMNS`.
- Catalogue from `TABLE_COLUMNS`; chooser options: Contact, Offering, Score, Submitted (Company, Tier, Status, Readout also listed since they are non-pinned; the default set simply excludes Contact, Offering, Score, Submitted).
- Placement: `div.ov-toolbar` wrapper around `c-gtm-filter-bar` (`flex 1 1 auto; min-width: 0`) and the chooser, chooser rendered under `if:true={showTable}` semantics (see risk: `showTable` unmounts on no-match; the chooser hides then, state persists in the parent field).
- No Apex change: the hidden columns (contact, score, submittedAt, offeringKey) are already in every `AssessmentRow`/`mapRow` output; `buildQuery`, paging, sort keys and the filter contract are untouched; no Apex test run is triggered.

Widths: default 5 columns must fit at 1078px and 1440px with no horizontal scroll (measured in QA); with more columns the existing wrapper scrolls inside itself (`.rlf-table-wrap` `overflow:auto`, `.ov-table`).

## 6. Jest plan

NEW (phase A):
- `gtmColumnState/__tests__/gtmColumnState.test.js`: buildCatalogue (labels, default flag, pinned implies default, action column skipped); defaultKeys; normalizeKeys (unknown dropped, pinned re-added when absent, canonical order not input order, duplicates, empty -> defaults, null/undefined -> defaults); visibleColumns (action column kept, identities preserved, order canonical, does not mutate inputs); isDefault; isSortedColumnVisible.
- `gtmColumnChooser/__tests__/gtmColumnChooser.test.js`: trigger name `Columns, 5 of 10 shown` and updates; click opens (`aria-expanded`, popover, group focus with `focus()` guard); options exclude pinned and show "Always shown"; tick emits `columnschange` once with canonical-order keys including pinned; untick likewise; last-column guard (Pages-like catalogue): emits nothing, hint shown, group recreated; pinned cannot be removed by any event; Reset emits defaults and is disabled at default; Escape closes and refocuses the trigger; outside click closes (deferred, not synchronous; the opening click does not close it); real event-order emulation from B.13.2 (pointerdown, mousedown, focusout to the container, focusin, mouseup, click, change, null-relatedTarget focusout) keeps it open and the tick registers; B.13.3 retargeted document click on an inside click does not close it and a following microtask flush then `change` still emits; Tab-away (`relatedTarget` Element outside) closes, null/document `relatedTarget` does not; parent re-render with new equal-content `columns` and `selectedKeys` keeps the same group element and the same `options` reference and leaves it open; timers/listeners removed on disconnect (no document listener left).
CHANGED at wiring time (phase B; do NOT touch now):
- `gtmRepLinkFinder/__tests__/gtmRepLinkTableModel.test.js`: `buildColumns` assertions stay (function unchanged); ADD `DEFAULT_COLUMN_KEYS` (5, all exist in `buildColumns(true)`), `PINNED_COLUMN_KEYS` empty.
- `gtmRepLinkFinder/__tests__/gtmRepLinkFinder.table.test.js`: lines ~114/120/132 ("Owner column hidden for a rep and shown for a viewAll user", and the stats-failure test) assert `ownerName` in/not in `table.columns` and now must assert Owner is in the CATALOGUE (chooser `columns`) but NOT in `table.columns` by default, and appears after a `columnschange` including it; line ~154 (`columns[0].typeAttributes.name === 'open'`) still holds with the default (company first); ADD default 5 fieldNames in order plus the action column, sort retained when the sorted column is hidden (rows unchanged, `sortedBy` not passed), choice survives a filter change and a no-match then Clear, and does not survive a fresh mount.
- `gtmRepLinkFinder.test.js` (~36 toggle/mode references broken by Release 2): rewrite done by R2's Developer; phase B only adds the chooser presence and no other assertion. Any spec that reads `table.columns` length or order must be updated; grep `columns` in all `gtmRepLinkFinder*.test.js` at wiring time.
- `gtmReadoutsOverview/__tests__/gtmReadoutsOverview.test.js` line ~161 ("declares the columns in order..."): must change from all 8 to the default 5 (labels Assessment, Company, Readiness tier, Request status, Readout; types `button,url,text,text,text`; the `cellAttributes.class` index checks move from `cols[3]`/`cols[6]` to `cols[2]`/`cols[4]`; the "only non-sortable data column" assertion still holds), plus new tests: ticking Contact/Score/Submitted/Offering adds them in canonical order; Assessment cannot be hidden; hiding the sorted column keeps `sortBy`/`sortDir`, does NOT call `getAssessmentPage` again (mock call count unchanged) and passes no `sortedBy`; a filter change keeps the choice; mount resets it.
- `gtmAssessmentsTableModel/__tests__/gtmAssessmentsTableModel.test.js`: `COLUMNS` assertions unchanged (must pass unmodified); ADD `DEFAULT_COLUMN_KEYS`, `PINNED_COLUMN_KEYS`, `TABLE_COLUMNS` (COLUMNS plus Offering after Company; `COLUMNS` length still 8).
- `gtmOverview` specs (`gtmOverview.row3.test.js` line ~162 pins the 4 result columns; `gtmOverview.js` imports `COLUMNS`): must pass UNMODIFIED. No other spec pins Pages/Assessments column order or count beyond those listed (grep of origin/main; re-grep at wiring time).
- `gtmFilterBar` specs: unchanged (no shared-bar edit).
Jest cannot prove: real focus order, activation-vs-microtask timing, base-component internals, datatable width recalculation, screen readers, dark theme rendering.

## 7. Developer file lists

PHASE A (now, worktree `issue-table-columns`; all new files, zero overlap with any in-flight branch):
1. `force-app/main/default/lwc/gtmColumnState/gtmColumnState.js`
2. `force-app/main/default/lwc/gtmColumnState/gtmColumnState.js-meta.xml` (copy of `gtmAssessmentsTableModel`'s: `isExposed` false)
3. `force-app/main/default/lwc/gtmColumnState/__tests__/gtmColumnState.test.js`
4. `force-app/main/default/lwc/gtmColumnChooser/gtmColumnChooser.html`, `.js`, `.css`, `.js-meta.xml` (`isExposed` false, same apiVersion as sibling components)
5. `force-app/main/default/lwc/gtmColumnChooser/__tests__/gtmColumnChooser.test.js`
6. `docs/architecture/gtm-column-chooser.md` (this note; Developer keeps it in sync)
Not to touch in phase A: any parent, model or spec file, `gtmFilterBar`. Phase A is deployable and inert (component unused). Run `npm test` and `python3 scripts/check-references.py`.

PHASE B (only after Releases 2 and 3 merge, re-branch or rebase on the new origin/main):
- Pages, after Release 2: `gtmRepLinkFinder/gtmRepLinkTableModel.js` (add the two constants), `gtmRepLinkFinder.js` (visibleKeys, memoized columns, effectiveSortedBy, handler), `gtmRepLinkFinder.html` (toolbar wrapper, chooser), `gtmRepLinkFinder.css` (toolbar rules), specs `gtmRepLinkTableModel.test.js`, `gtmRepLinkFinder.table.test.js`, plus any `gtmRepLinkFinder*.test.js` that pins columns.
- Assessments, after Release 3: `gtmAssessmentsTableModel/gtmAssessmentsTableModel.js`, `gtmReadoutsOverview.js/.html/.css`, specs `gtmAssessmentsTableModel.test.js`, `gtmReadoutsOverview.test.js`.
Pages may be wired before R3 lands; do not block Pages on R3.

## 8. Overlap risk and merge order

- Release 2 (Pages) edits `gtmRepLinkFinder.html/js/css`, `gtmRepLinkFinder*.test.js`, `gtmRepLinkTableModel.js` (`buildColumns`/`getRowActions`): full overlap with Pages wiring; R2 also rewrites about 36 toggle/mode assertions in `gtmRepLinkFinder.test.js`.
- Release 3 (Assessments; Apex, gated on the user's direct authorisation) edits `gtmReadoutsOverview.html/js/css`, its spec (a large describe), and `gtmAssessmentsTableModel.js`: full overlap with Assessments wiring; the Apex part does not overlap.
- Phase A overlaps NOTHING (new folders and one new doc). The Architect did not open the in-progress worktrees; the overlap is derived from the release plan in `gtm-filter-bar.md` Addendum C and the file lists above, so re-run `git fetch` and check open PRs touching these six files and `gtmFilterBar` before phase B.
- Recommended order: (1) phase A now, merge whenever green (independent); (2) Release 2 merges, then Pages wiring; (3) Release 3 merges (or is deferred), then Assessments wiring. If R3 is delayed, ship Pages alone; Assessments wiring is a separate PR. Do not fold the wiring into R2/R3 branches.

## 9. QA plan (`gtm-staging` only, real input, locked single tab, demo data: 6 links, 3 assessments)

Validate live, every dependent surface, not only the changed one. Real mouse and keyboard, not script `input.click()`.
1. Default: Pages shows Account / company, Contact, Funnel stage, Last visit, Status (5, kebab excluded, also for a View All user); Assessments shows Assessment, Company, Readiness tier, Request status, Readout (5).
2. Widths: at 1078px and 1440px with the default, `scrollWidth <= clientWidth` on both tables' scroll containers; then all columns on: the wrapper scrolls inside itself, the page does not. Also 768, 480, 320: popover clamps, no clipping.
3. Real click on `Columns`: `aria-expanded="true"`, popover visible, focus inside, stays open across several ticks (the B.13.2/B.13.3/B.13.4 failure class, including while the parent re-renders).
4. Tick then untick with real clicks and Space: each change applies immediately, canonical order, correct cell content (dates, links, icons), trigger name updates ("Columns, N of M shown"), rows/filters/count/URL unchanged.
5. Reset to default restores exactly the 5, button disabled at default.
6. Pinned guard: Assessment cannot be hidden and is not offered as a checkbox; last-column guard on Pages (untick down to one; the last cannot be removed and the checkbox visibly reverts).
7. Sorting: header sort on visible sortable columns still works after adds and removes (Pages incl. funnel-stage rank; Assessments server sort and infinite load). Hide the sorted column: row order unchanged, no new Apex call (Network panel), no console error.
8. Persistence: reload resets to default; Pages to Assessments and back resets to default; a filter change, no-match then Clear, deep links (`c__stage`, `c__astatus`, `c__atier`, `c__areadout`) and Pages Back to links KEEP the choice (confirms the parent does not remount).
9. Keyboard and screen reader: Tab order (filter bar, Columns, table), Enter/Space opens, Space toggles, Tab-away closes, Escape closes and refocuses the trigger; VoiceOver reads "Columns, 5 of 10 shown" and the live update (mark UNVERIFIED if not possible).
10. One popover at a time with the filter bar, in both directions (click and Tab). Dark theme popover legible. Chooser sits in the same toolbar row at 1078 and 1440.
11. Dependent surfaces: filters, Overview Act-today and results card (same 4 columns), row Open and Assessment opener, GUS stage-filter tool. `npm test` green, `check-references.py` not regressed, no new hex outside the allowlist, no org IDs/usernames/secrets committed.
Fallback if the custom popover proves fragile after live QA: `lightning-button-menu` with checked menu items (closes per pick, UNVERIFIED).
