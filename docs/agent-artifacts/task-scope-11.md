# TASK SCOPE — ISSUE #11

## 1. Requirements Breakdown

- **Target Objective:** Give reps and/or admins a way to notice, and then
  backfill, `GTM_Assessment_Request__c` / link rows that have a typed
  `Company__c` value but no linked `Account__c` — the exact pattern that
  `pages-table-account-column-consistency` (commit `306b584`, PR #260) made
  visible by fixing cell-rendering precedence. Before that fix these rows
  looked like ordinary blue links (base `lightning-datatable` `type:
  'button'` cells rendered them the same regardless of `disabled`); after
  the fix they correctly render as plain, non-clickable `<span>` text via
  the shared `c/gtmLinkCell` component, which is working as designed but
  now makes the gap in the data obvious for the first time. This issue is
  the explicit follow-up to *act* on that gap (surface it, let someone fix
  it), not to touch the rendering logic again.

  **Confirmed by reading the actual code** (not the GitHub issue body,
  which is a one-line stub with no acceptance criteria):
  - `force-app/main/default/lwc/gtmLinkCell/gtmLinkCell.js` /
    `gtmLinkCell.html` — the shared "Account or Contact" cell type. When
    `typeAttributes.disabled` is true it renders `<span class="...
    gtm-link-cell_static">{label}</span>` (lines 12-14 of the `.html`,
    `isInteractive` getter lines 40-42 of the `.js`) — non-clickable by
    design, with a `title` tooltip retained. This is the cell the fix
    introduced and the exact spot a "nudge" affordance (icon/badge) would
    need to be added, if the UX in this issue is "inline in the same
    cell."
  - `force-app/main/default/lwc/gtmRepLinkFinder/gtmRepLinkTableModel.js`
    lines 50-51 wire `accountDisabled`/`accountTitle`/`accountId` into the
    Account column's `gtmLinkCell` `typeAttributes` for the **Pages**
    table; line 131 is the precedence expression itself:
    `company: (l.Account__r ? l.Account__r.Name : '') || l.Company__c ||
    ''`. `accountDisabled` is presumably `!l.Account__c` (need to confirm
    exact field name at implementation time — grep found the render wiring
    but not the `accountDisabled` assignment line in this file; Architect
    should re-grep `accountDisabled\s*:` in this file before implementing).
  - `force-app/main/default/classes/GtmAssessmentListController.cls` lines
    693-707, method `toRow(GTM_Assessment_Request__c r, GTM_Readout__c
    ro)` — the **Assessments** table's server-side equivalent. Explicit
    comment at lines 700-701: *"Account__r.Name (a governed lookup) wins
    over the free-typed Company__c fallback whenever both are
    populated."* `row.accountId = r.Account__c;` (line 699) and
    `row.company = (r.Account__r != null && String.isNotBlank(r.Account__r
    .Name)) ? r.Account__r.Name : r.Company__c;` (lines 705-707). A row
    with `Company__c` set and `Account__c` null is exactly the target
    population: `accountId` is null/blank so the datatable model will mark
    `accountDisabled = true`, and `company` falls back to the raw typed
    text.
  - Query source: `GtmAssessmentListController.cls` lines 95-96 selects
    `Contact__c, Contact__r.Name, Account__c, Account__r.Name, Company__c,
    Requester_Name__c` from (need to confirm exact object at top of
    method, consistent with `GTM_Assessment_Request__c` per the method
    signature) — this is the query the backfill report/list would reuse or
    extend with an `Account__c = null AND Company__c != null` filter.
  - The **Pages** table's underlying object is the link/request object
    queried by `gtmRepLinkFinder`'s Apex counterpart (likely
    `GtmRepLinkFinderController.cls`, confirmed present at
    `force-app/main/default/classes/GtmRepLinkFinderController.cls` and
    already implementing rep-ownership row scoping — see below); Architect
    should confirm the exact SOQL/object there before implementing the
    Pages-side identification query, since this BA pass did not fully
    trace that file's query shape (time-boxed to the rendering-fix trail
    above).

  **Ambiguity that needs a decision, not a guess** (flagging per BA
  instructions rather than picking one silently):
  1. **UX shape is genuinely open.** The issue text offers two options
     ("a rep-facing nudge or admin report") without picking one, and there
     is no existing precedent in this codebase for an inline "fix this"
     affordance inside a `lightning-datatable` static cell — every
     existing admin-facing gap-surfacing pattern in this codebase is a
     separate list view / report, not row-level inline UI (see Salesforce-
     first note below). Recommend, but do not treat as decided:
     - **Option A (rep-facing nudge):** add a small icon (e.g.
       `utility:info` or `utility:warning`) next to the static label in
       `gtmLinkCell` when `disabled` is true *and* the row has a
       `Company__c` value with no `Account__c` (a new `typeAttributes.
       showBackfillHint` flag), with a tooltip prompting the rep to link
       the real Account. This keeps the affordance where the rep already
       sees the row, and requires zero new schema, but pushes the actual
       linking action into an existing Account-lookup edit flow (probably
       an existing "Edit link" modal — not investigated in this pass).
     - **Option B (admin report):** a native Salesforce list view /
       report on `GTM_Assessment_Request__c` (and whatever Pages-table
       object) filtered to `Account__c = null AND Company__c != null`,
       visible only to `GTM_Offering_Admin`. Zero LWC/Apex changes; purely
       declarative (list view + optional report + dashboard component).
       Weaker for individual-rep awareness, but matches the memory note
       "Rep can view/edit/delete only their own... backfills need
       approval" much more cleanly, since a report naturally becomes the
       admin's approval queue.
     - These are not mutually exclusive (rep nudge to *notice*, admin
       report to *approve/action* the actual Account link change), but
       committing to build both is a scope/cost decision for a human or
       the Architect, not this BA pass.
  2. **Approval step.** Per project memory
     ("`feedback_rep_ownership_rule`": reps see/edit only their own
     records; admins see all; **backfills need approval**), if this issue
     is understood to let a rep or admin actually *write* `Account__c`
     onto these rows (not just flag them), that write is a backfill and
     per that rule needs an approval step before commit — i.e. it should
     not be a bare inline "type an Account, save" edit. Whether that
     approval step is a new admin-review UI, a Chatter/task-based
     approval process, or simply "only `GTM_Offering_Admin` can perform
     the write, no separate approval object" is undecided and should be
     confirmed by the issue owner/Architect before implementation,
     because it changes both the Apex write-path design and the
     permission-set grant needed (see §2/§3).
  3. **Salesforce-first check performed:** grepped
     `force-app/main/default/objects/**/listViews/` and found no existing
     list views under the `GTM_Assessment_Request__c` or link object
     directories that already do this filter (checked via `find
     force-app/main/default/objects -iname "*ListView*"` — none matched
     an Account-null filter name). A native list view / report is
     therefore not already available and would need to be authored net-
     new as XDX metadata (declarative, not code) if Option B is chosen —
     this satisfies "evaluate native Salesforce before building custom"
     and should be the Architect's starting point over a custom LWC panel.

- **System Component Impacted:** LWC (`gtmLinkCell`,
  `gtmRepLinkTableModel`, possibly `gtmRepLinkFinder`) if Option A;
  Apex (`GtmAssessmentListController.toRow`, `GtmRepLinkFinderController`)
  for the disabled/hint flag and/or a new backfill-write method; Salesforce
  declarative metadata (list view/report, and permission set) if Option B
  or for the admin queue regardless of which UX is chosen.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No — this touches rep/admin-facing
      tables and Apex list/read controllers, not the GUS chat tool
      surface. If the Architect later decides GUS itself should
      surface/act on this nudge, AGENTS.md §1's zero-DML rule for GUS
      tools must be re-checked at that time.
- [ ] Altering Custom Metadata? No — `Company__c`/`Account__c` are
      standard object fields on the link/assessment SObjects, not
      `GTM_Assessment_*` instrument custom metadata. No YAML/migration-
      accelerator change is implicated.
- [ ] Introducing database fields? Likely **no** new field is required to
      *detect* the gap (existing `Account__c`/`Company__c` suffice), but
      if the approval-workflow decision above (§1 item 2) lands on "track
      approval state," a new field (e.g. a checkbox/status on the link or
      assessment object, or a junction "backfill request" object) would be
      introduced — in that case, per CLAUDE.md §6, mapping to permission
      sets is mandatory: add FLS to `GTM_Offering_Admin` (full CRUD) and,
      if reps need to see their own row's pending/approved state,
      read-only FLS on `GTM_Offering_User` as well. No new field exists
      yet, so this is conditional on the Architect's UX decision, not a
      commitment in this scope.

## 3. Plan Acceptance Criteria

- **Success Metric:** For rows where `Account__c` is null and `Company__c`
  is populated, the chosen surface (nudge icon and/or admin list
  view/report) correctly identifies 100% of such rows for the current
  user's visibility scope (rep sees only their own per the ownership rule;
  admin sees all), and — if a write path is included in this issue's
  final scope — linking a real Account to a previously-gap row (a) updates
  `Account__c`, (b) causes `gtmLinkCell`/`gtmRepLinkTableModel`/
  `GtmAssessmentListController.toRow` to now render that row as an
  interactive link (proving the existing precedence fix and the new
  backfill path compose correctly), and (c) if an approval step is in
  scope, the write is blocked/queued until an admin approves it rather
  than committing immediately on rep action.
- **Target Test Target:**
  `force-app/main/default/lwc/gtmLinkCell/__tests__/gtmLinkCell.test.js`
  and `force-app/main/default/lwc/gtmRepLinkFinder/__tests__/
  gtmRepLinkTableModel.test.js` for the LWC-side hint rendering (Option
  A); `force-app/main/default/classes/
  GtmAssessmentListControllerTest.cls` for the Apex-side row-shape/gap-
  detection field; and (if a new admin report/list view or write
  endpoint is added) a corresponding new Apex test class alongside
  `GtmRepLinkFinderControllerTest.cls`, following this repo's existing
  pattern of one `*Test.cls` per controller.
