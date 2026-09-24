# TASK SCOPE — ISSUE #pages-table-account-column-consistency

## 1. Requirements Breakdown

- **Target Objective:** Fix the "Your recent links" table on the Pages tab
  (`gtmRepLinkFinder`) so the Account and Contact columns render with one
  consistent visual style regardless of whether the row has a real
  `Account__c`/`Contact__c` lookup, and rename the columns to plain
  Salesforce-standard-object names ("Account", "Contact") instead of the
  hybrid "Account / company" label. This is a rework of the column
  definition, not a CSS override on top of the existing `type: 'button'` +
  `disabled` mechanism — the user explicitly rejected a hot-fix/CSS-patch
  approach.

- **Root cause (confirmed by reading
  `force-app/main/default/lwc/gtmRepLinkFinder/gtmRepLinkTableModel.js` and
  `gtmRepLinkFinder.html` in full):**
  - `BASE_COLUMNS_BEFORE_OWNER` (lines 43-56) defines both the Account and
    Contact columns as `type: 'button'`, with `typeAttributes.disabled`
    bound to `accountDisabled` / `contactDisabled`.
  - `buildRows()` (lines 118-119, 143-146) sets `accountDisabled = !l.Account__c`
    and `contactDisabled = !l.Contact__c` — i.e. any row without a real
    lookup gets `disabled: true`.
  - Base SLDS `lightning-datatable` renders `type: 'button'` cells very
    differently by disabled state: enabled → blue, left-aligned,
    link-styled button; disabled → plain grey, centered text. Because
    `disabled` is driven by data (does this row have a lookup?), not a
    fixed column property, two rows in the *same column* render with
    different alignment and color depending on whether a real Account/
    Contact was ever attached. This is a base-component styling
    side-effect of overloading "no target to navigate to" onto the
    `disabled` attribute of a `button`-type cell — not a bug in a custom
    style sheet, so there is no local CSS to patch; the divergence comes
    from `lightning-datatable`'s own SLDS button-cell template.
  - Header label is hardcoded to the literal string `'Account / company'`
    (`gtmRepLinkTableModel.js` line 44).
  - The column's display value, `company`, is built as
    `l.Company__c || (l.Account__r ? l.Account__r.Name : '') || ''`
    (line 126) — the custom `Company__c` free-text field takes priority
    over the real `Account__r.Name` relationship whenever both are
    populated, which is backwards: a governed lookup's name should win
    over a hand-typed duplicate, not lose to it silently.

- **Second table with the identical bug, found in scope (not just a
  "target pattern to match" — this is the same anti-pattern replicated):**
  `force-app/main/default/lwc/gtmAssessmentsTableModel/gtmAssessmentsTableModel.js`
  drives the "All Assessments" table (`gtmReadoutsOverview` results card,
  contract `docs/architecture/gtm-assessments-table.md`). Its `COLUMNS`
  array (lines 194-256) defines **Contact** (`contactLabel`,
  `contactDisabled: !row.contactId`) and **Company** (`companyLabel`,
  `companyDisabled: !row.accountId`) columns with the exact same
  `type: 'button'` + data-driven `disabled` construction
  (`mapRow()`, lines 325-330). So there is no independent "correct"
  styling reference to copy from — **both tables need the same rework**,
  and they should converge on one shared pattern so they do not drift
  apart again. The Assessments table's "Company" column has the same
  naming problem (`companyLabel` built from `row.company`, no direct
  `Account__r.Name` reference visible at this layer — `row.company` comes
  from the Apex `AssessmentRow`, not audited here since Apex is out of
  BA's read scope for this pass, but the Architect should check
  `GtmAssessmentListController`'s `AssessmentRow.company` population for
  the same `Company__c`-overrides-`Account__r.Name` issue before assuming
  it is clean).
  - Both tables' row-action fallback labels already correctly say
    "No account on this link/assessment" (see
    `NO_ACCOUNT_ACTION_LABEL`/`getRowActions` in both files) — i.e. the
    row-level action menu already treats "no account" as a normal,
    expected state, not an error. The inline column styling is the only
    place the inconsistency shows.

- **System Component Impacted:** LWC (`gtmRepLinkFinder`,
  `gtmRepLinkTableModel.js`, and `gtmAssessmentsTableModel.js` /
  `gtmReadoutsOverview`'s consumption of `TABLE_COLUMNS`). No Apex schema
  change is required for the rename itself; Apex only needs a look if the
  Architect confirms `AssessmentRow.company` has the same
  `Company__c`-wins-over-`Account__r.Name` precedence bug (see above).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **No** — this is a Pages/Assessments
      table rendering fix, not a GUS chat tool.
- [ ] Altering Custom Metadata? **No** — no `GTM_Assessment_*` metadata
      or YAML instrument changes involved.
- [ ] Introducing database fields? **No new fields.** No Apex/schema
      changes are required unless the Architect's Apex check above turns
      up the same `Company__c` precedence bug server-side, in which case
      only existing-field usage changes (query/precedence order), not new
      fields — no permission-set mapping is implicated either way.

## 3. Plan Acceptance Criteria

- **Success Metric (functional):**
  1. In `gtmRepLinkFinder`'s "Your recent links" table, the column
     currently labeled "Account / company" is relabeled to **"Account"**
     (no "company" anywhere in the header or in any UI copy for this
     column). The Contact column keeps its existing "Contact" label
     (already correct) but must get the same structural fix as Account so
     both use one consistent pattern.
  2. Every row in the Account column renders with the *same* alignment
     and color treatment regardless of whether `Account__c` is populated
     — i.e., rows with and without a real Account lookup must be visually
     indistinguishable in font weight/alignment/color, differing only in
     whether the text is clickable. Same requirement for Contact. This
     must be verified by inspecting at least one row of each state (has
     lookup / no lookup) side by side, not just reading the column config
     — screenshot or DOM check across a mixed data set.
  3. `gtmAssessmentsTableModel.js`'s `Contact` and `Company`→**`Account`**
     columns get the equivalent fix and rename in the same change (or, if
     the Architect judges the two tables' fixes are large enough to
     split, the second scope file/PR must be opened explicitly — do not
     silently leave one table fixed and the other still broken, since a
     rep bouncing between Pages and Assessments tabs would immediately
     notice the remaining inconsistency).
  4. Clicking an Account (or Contact) cell that has a real lookup still
     navigates to that Account/Contact record — the existing
     `NavigationMixin.Navigate` behavior in `gtmRepLinkFinder.js`
     (`openAccountRecord`/`openContactRecord`, wired through
     `handleRowAction` off the cell's `rowaction` event, lines ~265-296)
     must not regress. **Implementation note for the Architect:** the
     current click-to-navigate wiring depends on `lightning-datatable`'s
     `type: 'button'` cells firing a `rowaction` event on click, with
     `typeAttributes.name` (`openAccount`/`openContact`) identifying the
     action. If the fix removes `type: 'button'` in favor of `type: 'text'`
     or `type: 'url'` to kill the disabled-driven style split, that click
     wiring goes away and must be reimplemented — either (a) a custom
     `lightning-datatable` cell type (LWC's documented pattern for
     extending base types) that renders as always-consistent text/link
     styling but still emits the same `rowaction` shape on click, or (b) a
     `type: 'url'` cell pointed at a generated record URL, accepting that
     `url` cells navigate via `href`/`target` rather than
     `NavigationMixin`, which changes new-tab-vs-same-tab behavior and
     needs explicit sign-off if kept. Keeping `type: 'button'` but forcing
     `disabled` to always be `false` is **not acceptable** — clicking a row
     with no Account/Contact must not silently no-op or error; the "no
     account on this link" messaging currently in `accountTitle`/
     `NO_ACCOUNT_TITLE` must still surface somewhere (tooltip, row-action
     menu label, or an explicit "—" placeholder that is visually
     non-interactive) so accountless rows plainly do not look clickable —
     the Architect must pick one construct and document it in
     `docs/architecture/`, not both.
  5. **Fallback-data decision (needs Architect/owner sign-off, not
     assumed here):** `Company__c` (rep-typed text, no real Account
     lookup) is real prospect-facing data reps already rely on and must
     **not** be silently dropped from the table — a rep who typed a
     company name because they hadn't yet linked an Account still needs
     to see it. Recommendation for the Architect to confirm: keep
     `Company__c` as the *display fallback text* when `Account__c` is
     blank (so the cell still shows a name), but drop the current
     precedence order (`Company__c || Account__r.Name`) in favor of
     `Account__r.Name || Company__c` — the real lookup should always win
     when both exist, since a stale/duplicate typed name should not mask
     a governed record. Separately, flag as a **data-quality gap, not a
     styling bug**: links/assessments that have a typed `Company__c` but
     no linked `Account__c` are exactly the rows this whole issue makes
     newly visible as a *pattern* (they were previously camouflaged by
     the button style difference) — worth a backlog item for reps to
     backfill real Account lookups on those records, but that is out of
     scope for this fix itself.
  6. No other columns, filters, sorting, or row-action menus in either
     table change behavior. `SORT_KEYS`/`COLUMNS` field names
     (`company`/`companyLabel`) can be kept internally if renaming the
     JS property is riskier than necessary — only the **label text**
     rename and the **cell-styling/type** rework are required; the BA does
     not mandate a `company` → `account` property rename, but if the
     Architect does rename it for clarity, all call sites (`buildRows`,
     `SORT_KEYS`, `DEFAULT_VISIBLE_FIELDS`, existing Jest specs under
     `gtmRepLinkFinder/__tests__/` and
     `gtmAssessmentsTableModel/__tests__/`) must be updated together.

- **Target Test Target:**
  - `force-app/main/default/lwc/gtmRepLinkFinder/__tests__/gtmRepLinkFinder.table.test.js`
    and `gtmRepLinkFinder.contactLink.test.js` (existing specs covering
    this exact table/column — must be extended, not just left green by
    accident, to assert the header text is "Account" with no "company" in
    it, and that styling-relevant cell properties, e.g. cell
    class/type/disabled, are identical in shape whether or not the row has
    an Account).
  - `force-app/main/default/lwc/gtmAssessmentsTableModel/__tests__/gtmAssessmentsTableModel.test.js`
    (and `.vocabulary.test.js` if header/label vocabulary assertions live
    there) for the equivalent Assessments-table fix.
  - `npm test` (Jest via `@salesforce/sfdx-lwc-jest`) must pass for both
    components; no Apex test target unless the Architect's Apex
    precedence check above turns up a real change to
    `GtmAssessmentListController`, in which case
    `GtmAssessmentListControllerTest.cls` is the target.

## Ambiguity flagged for the Architect

This issue is **not** ambiguous on the visual bug or its root cause (both
confirmed above), but two decisions genuinely need a human/Architect call
before implementation, not a BA guess:
1. Which non-button cell construct (custom cell type vs. `type: 'url'` vs.
   something else) replaces `type: 'button'` — this is an LWC/Salesforce
   base-component design choice with UX tradeoffs (new-tab behavior,
   keyboard accessibility, native tooltip support), not a requirements
   question.
2. Whether `gtmAssessmentsTableModel.js`'s fix ships in the same PR as
   `gtmRepLinkTableModel.js`'s, or as a separate, explicitly-scoped
   follow-up — both are acceptable, but leaving it undecided risks a
   half-fixed pair of tables reaching QA.

No `gtm-prod` data or production deploy is implicated by this issue; it is
a pure front-end rendering/labeling fix validated in a worktree and against
`gtm-staging`.
