# TASK SCOPE — ISSUE #268

## 1. Requirements Breakdown

- **Target Objective:** In the "Your recent links" table (Pages tab, `gtmRepLinkFinder`), the Account and Contact column values must truncate with an ellipsis at the column's rendered width — matching the existing, correctly-truncating Offering column (e.g. "Migration A...") — instead of overflowing and visually overlapping the adjacent Offering column when the value is long.
- **System Component Impacted:** LWC. Specifically `force-app/main/default/lwc/gtmLinkCell/` (the shared custom cell renderer) and its consumers `force-app/main/default/lwc/gtmLinkDatatable/` (the `lightning-datatable` subclass registering the `gtmLink` custom type), `force-app/main/default/lwc/gtmRepLinkFinder/gtmRepLinkTableModel.js` (Pages tab), and `force-app/main/default/lwc/gtmAssessmentsTableModel/gtmAssessmentsTableModel.js` (Assessments tab).

### Root cause (confirmed by reading code)

This is a direct regression from the recent `pages-table-account-column-consistency` rebuild (PR #260), which replaced the old `type: 'button'` Account/Contact cells with a new shared custom cell type, `gtmLink` (`gtmLinkCell` mounted via `gtmLinkDatatable`).

- `gtmLinkCell.html` renders the value as a plain `<a>` (interactive) or `<span>` (static) with class `cellClass`, no wrapping container with a constrained width.
- `gtmLinkCell.css` (read in full) sets only:
  ```css
  .gtm-link-cell { display: block; text-align: left; }
  .gtm-link-cell_interactive { color: #0176d3; text-decoration: none; cursor: pointer; }
  .gtm-link-cell_interactive:hover, .gtm-link-cell_interactive:focus { text-decoration: underline; }
  .gtm-link-cell_static { color: #444; }
  ```
  There is **no `overflow: hidden`, `text-overflow: ellipsis`, `white-space: nowrap`, or `max-width: 100%`** anywhere in this file, and no `slds-truncate` class is applied in the template.
- By contrast, the Offering column in `gtmRepLinkTableModel.js` (line 62) is a plain built-in `{ type: 'text', fieldName: 'offeringLabel', ... }` column. Base `lightning-datatable` text-type cells get truncation for free from SLDS's own cell styling (`slds-truncate`/`slds-cell-*` wrapper markup that `lightning-datatable` generates internally for standard types). Custom types rendered via `gtmLinkDatatable`'s `customTypes` map (`standardCellLayout: true`) get the standard `<td>`/layout chrome, but **not** that inner truncation styling — the custom template's own markup is responsible for it, and `gtmLinkCell` never implements it. That's the exact mechanism: old `type: 'button'` cells got truncation for free from lightning-datatable's base button-cell styling; the new custom `gtmLink` type cells don't reimplement it.
- The Account/Contact columns in `gtmRepLinkTableModel.js` (lines 47, 55) additionally set `wrapText: true`. This is a column-level attribute, not one of the `typeAttributes` (`label, name, disabled, title, targetId, idField`) that `gtmLinkDatatable`'s `customTypes.gtmLink` declares as supported, so it has no effect on the custom cell's own markup — it's dead/misleading config left over from the base-type assumption, not a masking cause of the bug, but worth removing or reconciling as part of the fix so the column intent (truncate, don't wrap) is unambiguous.
- **Both tabs are affected**, not just Pages: `gtmAssessmentsTableModel.js` (Assessments tab) defines Contact (`contactLabel`) and Account (`companyLabel`) columns with the identical `type: 'gtmLink'` and no `wrapText` override, rendered through the same `gtmLinkCell`/`gtmLinkDatatable` pair. Since the missing CSS lives in the shared `gtmLinkCell.css`, the bug reproduces identically on Assessments.

No design fork or ambiguity here — this is a straightforward missing-CSS regression in a single shared component, confirmed against both consuming table models. No `gtm-prod` data risk (pure front-end styling, no schema/DML).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO** — pure LWC/CSS presentation fix, no Apex, no DML, no GUS tool code touched.
- [ ] Altering Custom Metadata? **NO** — no `GTM_Assessment_*` metadata or `instrument/` YAML involved.
- [ ] Introducing database fields? **NO** — no schema/field changes; no permission set mapping required.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. In `gtmLinkCell.css`, add truncation styling to `.gtm-link-cell` (and/or its interactive/static variants): `overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 100%;` (or apply SLDS's `slds-truncate` class in `gtmLinkCell.html` for parity with base `lightning-datatable` text cells) so the rendered `<a>`/`<span>` clips to the column's actual pixel width instead of overflowing.
  2. Confirm the cell's containing element (the custom type's standard `<td>`/wrapper from `gtmLinkDatatable`) constrains width the same way base text-type cells do — if the custom template needs an explicit width-bound wrapper `<div>` around the `<a>`/`<span>` (mirroring how SLDS wraps standard cell content) to make `overflow: hidden` actually clip rather than being ignored because the parent has no bounded width, add that wrapper in `gtmLinkCell.html`.
  3. Reconcile the `wrapText: true` attribute on the Account/Contact column defs in `gtmRepLinkTableModel.js` (lines 47, 55) — since it has no effect on the custom `gtmLink` type and contradicts the desired "truncate, don't wrap" behavior, remove it (or confirm/document why it's harmless if left) so column config isn't misleading.
  4. Apply the fix once in the shared `gtmLinkCell`/`gtmLinkDatatable` components (not duplicated per-tab) so both the Pages tab (`gtmRepLinkFinder`) and the Assessments tab (using `gtmAssessmentsTableModel.js`) inherit the truncation automatically.
  5. Verify manually (or via a Jest snapshot/DOM assertion in `gtmLinkCell.test.js`) that a long Account/Contact value truncates with a visible ellipsis at the column's rendered width, does not visually overlap/overlay the adjacent Offering column, and matches the existing Offering column's truncation behavior (e.g. "Migration A...").
  6. Confirm no regression to the existing interactive (clickable link) vs. static (plain span) rendering paths, hover/focus underline styling, or row-action/sort behavior inherited from `lightning-datatable`.
- **Target Test Target:** `force-app/main/default/lwc/gtmLinkCell/__tests__/gtmLinkCell.test.js` (extend with a long-value truncation assertion covering both interactive and static render paths). Manually verify rendering on both the Pages tab (`gtmRepLinkFinder`) and Assessments tab tables in a `gtm-staging` browser session, since CSS overflow/ellipsis behavior isn't always caught by JSDOM-based Jest snapshots alone.
