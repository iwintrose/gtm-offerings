# TASK SCOPE — ISSUE #page-header-layout-fix

## 1. Requirements Breakdown

- **Target Objective:** Fix the shared `c-gtm-page-header` so it never collapses or overlaps, at any width from ~360px to wide desktop. Production bug reported by the product owner on the Overview tab in `gtm-dev` (treated as Production).
  - Symptoms: the title block shrinks to a sliver. Eyebrow "Go to market" wraps one word per line, the "GTM Offerings" title is cut, and the meta line is clipped. The four Overview action buttons overlap the title and heading bar. At narrower widths the last button runs off the right edge.
  - **Verified root cause** (read `force-app/main/default/lwc/gtmPageHeader/gtmPageHeader.css`):
    - `.hdr .slds-page-header__row` is `display:flex; align-items:flex-start; gap:1rem` with **no `flex-wrap`**.
    - `.slds-page-header__col-title` is `display:flex; min-width:0` with **no flex-basis**, so it shrinks to nothing.
    - `.slds-page-header__col-actions` is `display:flex; margin-left:auto; gap:.5rem` with no wrap and no shrink limit, so a wide action set consumes the row.
  - **Required behaviour (minimum, wrap-only fix):**
    - Row gets `flex-wrap: wrap`.
    - The title column gets a floor, e.g. `flex: 1 1 16rem` (Architect picks 16-20rem), keeping `min-width: 0`.
    - The actions column gets `flex: 0 1 auto; flex-wrap: wrap; justify-content: flex-end; margin-left: auto`. When wrapped under the title it must still be right-aligned (or left-aligned, an Architect call) and never clipped.
    - Actions wrap among themselves and never overlap or overflow.
  - **Must NOT regress prior fixes** (git log for the folder: 861f020 B14a extraction, 768bbba, fb27785, b2ca7cc gtm-page-header-icon-shift):
    - Icon and title stay top-aligned. Keep `align-items:flex-start` on the row and on `.slds-page-header__col-title`. Do not reintroduce centering.
    - `.hdr-meta` keeps `min-height:1.2em` so a blank meta line reserves its height.
    - Existing static CSS assertions in `__tests__/gtmPageHeader.test.js` (it reads the CSS file) must stay green. Extend, do not weaken.
    - With `flex-wrap`, an actions block that drops under the title will sit in a new row. The `align-items:flex-start` icon/title stays pinned. Verify that `align-items:center` on `col-actions` (inner) does not shift the title.
- **System Component Impacted:** LWC only. Primary change is `gtmPageHeader.css` (possibly `gtmPageHeader.html`). Possible consumer edit in `gtmOverview.html` if the Architect adopts the overflow-menu option (see forks). No Apex, no metadata, no permission sets, no YAML.

### Consumer inventory (all 11 checked; grep of `c-gtm-page-header` in `force-app/main/default/lwc`)

Slot `actions` is the only slot. Consumers and what they slot:

| Consumer | Actions slotted | Risk |
|---|---|---|
| gtmOverview | **4 labelled buttons** (brand "New engagement link", "New assessment (no page)", "Find a link you sent", "See Assessments"), all with icons | **The reported bug**, widest set. Longest labels. |
| gtmContentHome | 3 labelled buttons (Refresh, Recycle Bin, brand New offering) | Medium. Same collapse risk at narrow widths. |
| gtmRecycleBin | 3 labelled buttons (Refresh, Restore selected, "Delete Selected Permanently", which is long and destructive) | **High.** Long label, same defect class. Not named in the report but likely broken too. |
| gtmAnalytics | `lightning-combobox` (class `an-range`, **fixed `width:12rem`** in gtmAnalytics.css) + refresh `lightning-button-icon` | Medium. A fixed-width combobox is fine if it can wrap; do not add `flex-shrink` overrides that fight it. Also has its own `c-gtm-page-header { display:block; margin-bottom:1rem }` rule, which is harmless but doubles the margin with `.hdr` `margin-bottom:1rem`. Note it, do not "fix" it unless it is visible. |
| gtmPageBrowser | 0 or 1 button ("Back to Pages", class `pb-back`, shown only in a sub-mode). Host has class `pb-head`: `display:block; margin-bottom:1rem; position:sticky; top:0; z-index:2` | Low width risk. **Sticky header:** if wrapping makes the header taller on phone, it occupies more of the sticky viewport. Confirm it remains acceptable. `.pb-back` has no rule in the CSS, so no override. |
| gtmAssessmentSubmissionView | 1 icon button (refresh) | Low. |
| gtmReadoutsOverview | 1 icon button (refresh) | Low. |
| gtmContentManager | none | Long-title/meta check only. |
| gtmInstrumentAuthor | none | Long-title/meta check only. |
| gtmOfferingsSettings | none (title "Settings", meta {sectionsMeta}) | Title-collapse check only. |
| gtmReadoutApprovalSettings | none, and **no icon-name, no meta** | Header with no icon: `lightning-icon icon-name=""` renders empty. Check the title alignment when the icon is absent. Existing behaviour, not to be regressed. |

**Consumer CSS overrides that could fight the fix (checked):**
- gtmContentHome.css and gtmOverview.css contain **only comments** about the header. No width, nowrap or order rules target it.
- gtmAnalytics.css has `c-gtm-page-header{display:block;margin-bottom:1rem}` and `.an-range{width:12rem}`.
- gtmPageBrowser.css has `.pb-head{display:block;margin-bottom:1rem;position:sticky;top:0;z-index:2}`.
- **No `white-space:nowrap`, order or fixed-width rule on the header itself was found** in these four files. Other consumers have no header-targeting CSS.
- LWC shadow DOM scopes styles, so consumer CSS cannot reach header internals. Only host-level rules apply.

**Open forks flagged for the Architect (BA does not settle these):**
1. **Wrap-only vs. overflow menu on Overview.** Standing rule: Salesforce-native first. The standard SLDS page-header pattern is one primary action (brand button) plus a `lightning-button-group` and/or a `lightning-button-menu` overflow for the secondary actions. Decide whether Overview's four buttons become "New engagement link" (brand) + button group / overflow menu. The other three are all navigational or create-type; "New assessment (no page)" is a plausible secondary. Record the decision in the Architect contract. Minimum required regardless: the wrap fix in the shared component, since any consumer can slot many actions. If the menu option is chosen, the handlers (`handleNewRepDirectAssessment`, `handleBrowseLinks`, `handleSeeAssessments`) must be re-wired to `lightning-button-menu` `onselect`/`lightning-menu-item` events, and `gtmOverview.test.js` (which references `c-gtm-page-header`) needs updating. That is a larger change than a CSS fix on a live production bug. The BA recommends the wrap fix ships first and the menu is a follow-up, but the choice is the Architect's.
2. **Right-align vs. left-align when actions wrap under the title.** SLDS record headers right-align actions. Left-align is arguably more natural on phone. Architect decides. Requirement: never clipped or overlapping either way.
3. **Title floor value** (16rem vs. 20rem), and whether long titles should truncate with ellipsis or wrap. Requirement: title and eyebrow must not break one-word-per-line at any width. Suggest wrapping the title text with `overflow-wrap:anywhere` on `.hdr-title`, and never truncating silently.
4. **Sticky `.pb-head`**: whether a taller wrapped header on phone is acceptable (see table).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO.** Pure presentational LWC CSS/markup. The zero-DML rule (AGENTS.md §1) is not engaged.
- [ ] Altering Custom Metadata? **NO.** No `migration-accelerator/` YAML or XML change.
- [ ] Introducing database fields? **NO.** No fields, so no Permission Set change.

Additional dependency notes:
- `docs/architecture/` contract: CLAUDE.md §4 says Contract First. The Architect should record the CSS contract (row wrap, title floor, actions wrap/justify, forks decided) in `docs/architecture/` before the Developer starts.
- This is production (`gtm-dev`). Do not stack another deploy on an unexplained regression (memory: deploy sequencing). Deploy is LWC-only. **No `sf community publish` is needed unless the header is used in a published Experience site.** All 11 consumers appear to be internal app pages; the Architect should confirm.

## 3. Plan Acceptance Criteria

- **Success Metric:** At every width from 360px through 1400px, on the Overview tab and every other consumer:
  1. The title block never collapses. The eyebrow, title and meta each render on their own line and never break one word per line. The title column has a usable minimum width.
  2. The action buttons never overlap the title or heading bar, and never run off the right edge. They wrap under the title on narrow widths and wrap among themselves.
  3. On one line, the actions are right-aligned.
  4. **No regression:** the icon and title stay top-aligned and do not move when the meta line is populated or blank. `.hdr-meta` still reserves its min-height. The blank-meta and no-icon headers (gtmReadoutApprovalSettings) look unchanged.
  5. All existing `gtmPageHeader.test.js` assertions pass, plus new static-CSS assertions for `flex-wrap:wrap` on the row, the title flex-basis floor and the actions wrap.
  6. Jest suites of all 11 consumers still pass.

- **Target Test Target:**
  - Primary: `npx sfdx-lwc-jest -- force-app/main/default/lwc/gtmPageHeader` (`__tests__/gtmPageHeader.test.js`; extend its CSS-source assertions).
  - Regression: run each consumer spec: gtmOverview, gtmContentHome, gtmContentManager, gtmAssessmentSubmissionView, gtmAnalytics, gtmReadoutApprovalSettings, gtmReadoutsOverview, gtmPageBrowser, gtmInstrumentAuthor, gtmOfferingsSettings and gtmRecycleBin. Full `npm test` is acceptable.
  - **Jest cannot verify layout** (jsdom has no layout engine). The layout acceptance is the throwaway visual harness plus the live check below.

### Visual verification harness (throwaway, NOT committed into force-app)

- **Location:** the QA/coordinator's scratchpad or a temp dir outside `force-app/`. Never commit it.
- **Build:** a static `harness.html`.
  - It inlines the header's real CSS (copy from `gtmPageHeader.css` after the fix) and SLDS from the CDN (or a local SLDS CSS) so `.slds-page-header__*` and `.slds-button` behave.
  - Markup mirrors `gtmPageHeader.html`: `.slds-page-header.hdr > .slds-page-header__row > (.slds-page-header__col-title with icon placeholder + .slds-media__body{eyebrow, h1.hdr-title, p.hdr-meta}) + .slds-page-header__col-actions` with `.slds-button` elements standing in for `lightning-button`.
  - Render each scenario in an iframe or resizable container at **360 / 600 / 900 / 1100 / 1400px** widths.
- **Scenarios (each at all 5 widths):**
  1. No actions (empty actions column, blank meta).
  2. 1 action (a single icon-only refresh button).
  3. 4 actions, using the exact Overview labels: "New engagement link" (brand), "New assessment (no page)", "Find a link you sent", "See Assessments".
  4. A long title (~80 characters, no spaces variant too), with 3 actions using the Recycle Bin label "Delete Selected Permanently".
  5. A populated meta line ("3 offerings · 2 requests waiting" plus a long variant), compared side by side with the blank-meta variant.
- **What must look right:**
  - Eyebrow "Go to market" on one line at all widths (title column floor respected).
  - The title is never clipped mid-word. A long title wraps or breaks cleanly.
  - No button overlaps text or the header border. No horizontal scroll or overflow of the `.hdr` box at 360px. The last button is fully visible.
  - Actions wrap under the title at narrow widths and are aligned as decided (Fork 2). On wide widths they sit on the title row, right-aligned.
  - **Icon and eyebrow top edge stays at the same y-offset** between the blank-meta and populated-meta variants (the icon-shift regression check). Measure with devtools or a screenshot diff.
  - Row bottom padding is sane and there is no extra blank strip when actions are empty.

### Owed live checks on `gtm-dev` after deploy (QA browser validation, all dependent surfaces)

- **Overview** (the reported bug): at a wide window, a narrowed window and phone width. The four buttons are visible and clickable, and each still works (`handleNewEngagementLink`, `handleNewRepDirectAssessment`, `handleBrowseLinks`, `handleSeeAssessments`).
- **Settings** (gtmOfferingsSettings): no actions, title intact.
- **Assessments** (gtmAssessmentSubmissionView and gtmReadoutsOverview): refresh icon button aligned.
- **Pages** (gtmPageBrowser): header still sticky, "Back to Pages" shows in the sub-mode.
- **Content Manager home** (gtmContentHome): 3 buttons, plus gtmContentManager and gtmInstrumentAuthor headers.
- Also spot-check gtmAnalytics (combobox plus refresh), gtmRecycleBin (long destructive label) and gtmReadoutApprovalSettings (no icon).
- Deploy is LWC-only via `./scripts/deploy.sh <org-alias>`. Use `--dry-run` for validation. Do not use `-c`.
