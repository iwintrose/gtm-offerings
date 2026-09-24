# TASK SCOPE — ISSUE #opportunities-table-redesign-v2

## 0. Supersession Notice

**This issue supersedes the unmerged branch `agent/issue-overview-redesign-table-nav`
(commit `53a18a2`, scope branch `ba-scope/issue-overview-redesign-table-nav`).**
That branch built an earlier version of the "Opportunities to follow up on" widget on
`gtmOverview`. The user has since iterated on a mockup (Claude Artifact
`https://claude.ai/artifact/8k1XCBAVuPZSR73ixi1gAB`) across three rounds and approved a
different column layout and pagination behavior. The superseded branch is **not** simply
wrong — most of its plumbing is reusable — but its markup/column content must not ship
as-is.

**Decision left to the Architect:** whether to branch fresh off `main` and re-apply only
the reusable pieces described below, or check out `agent/issue-overview-redesign-table-nav`
and edit forward. Either is acceptable; the Architect should pick based on how much diff
noise the salvage produces. What must NOT happen is merging the superseded branch's HTML
column layout unmodified — it does not match the approved mockup (has 5 columns, not 3;
still shows CRM stage / On the page / Last activity; still has a duplicate account-name
line under the Account row; is unpaginated).

### Reusable from `agent/issue-overview-redesign-table-nav` (verified present on that branch)

- **Apex (`GtmHomeSnapshotController.cls`, `DealSummary` DTO):** already adds
  `accountId`, `contactId`, `contactName` fields and queries `Account__c`, `Contact__c`,
  `Contact__r.Name` on `GTM_Saved_Configuration__c` in `getDeals()`. This grouping data is
  reusable as-is — Opportunity fields (`opportunityId`/`opportunityName`/`stageName`) were
  already present on `main` before that branch, also reusable.
- **JS grouping/flattening (`gtmOverview.js`):** `dealGroups` getter (Account → Contact
  Map nesting) and `dealRows` getter (flattens to one row per line tagged
  `type: 'account' | 'contact' | 'deal'`, required because LWC's template compiler does
  not support multi-root `for:each` nesting) — reusable as the hierarchy engine, but
  `dealRows`/the per-row `deal` object shape needs the new column fields added (see §1).
- **Click-through handlers:** `handleAccountClick` (→ `GTM_Pages` tab, actually should be
  retargeted to an Accounts tab per the new mockup — see Requirements Breakdown ambiguity
  note below), `handleLinkRowClick` (→ `GTM_Pages`, `c__template:'link', c__recordId`),
  `handleOpportunityClick` (`event.stopPropagation()` so inner `<a>` navigations don't
  double-fire the row's own click handler) — all reusable, `handleAccountClick`'s target
  tab/state needs revisiting, and two new handlers are needed for the Contact row and the
  Assessment cell link (see §1).
- **Nav idiom used throughout this component (do not invent a new one):**
  `this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName:
  '<tab>' }, state: { c__xxx: ... } })`. Existing precedents to copy: `c__template:'link',
  c__recordId` (Pages tab, deep-links a `GTM_Saved_Configuration__c`, consumed by
  `gtmPageBrowser.js`); `c__assessmentRequestId` (Assessments tab, deep-links a
  `GTM_Assessment_Request__c`, consumed by `gtmReadoutsOverview.js` — already opens that
  request's detail/modal, exactly the "Assessments tab drilled down to that specific
  assessment" behavior the mockup calls for).

## 1. Requirements Breakdown

- **Target Objective:** Replace the "Opportunities to follow up on" widget on
  `gtmOverview` with the mockup-approved redesign: same Account → Contact → Link
  3-level grouping as the superseded branch, but a different, narrower 3-column layout
  (down from 5), no duplicate account-name text, and pagination by account group (page
  size 5) to fix the "so long" complaint that motivated this rework. Remove the CRM
  stage / On the page / Last activity columns and the card subtitle "What each recipient
  did with the page you sent" entirely — user has explicitly said none of that is
  relevant to what should ship.
- **System Component Impacted:** LWC (`force-app/main/default/lwc/gtmOverview/` —
  `.html`, `.js`, `.css`) and Apex (`force-app/main/default/classes/
  GtmHomeSnapshotController.cls`, specifically `DealSummary` + `getDeals()`) to add the
  Opportunity/Assessment fields the new columns need, if not already present (see field
  gap analysis below). No new objects, fields, or metadata — this only reads existing
  schema.

### Column-by-column build spec (from the approved mockup / written spec)

1. **Account row** (group header, spans full width): Account Name only, links to an
   Accounts tab. **Ambiguity flag for the Architect:** the superseded branch's
   `handleAccountClick` links to `GTM_Pages` with `c__rlfAccountId` state (i.e. it opens
   the Pages tab filtered to that account, reusing `gtmRepLinkFinder`'s existing
   Account→Contact→Link drill-down, per that branch's own comment referencing "D7"). The
   new written spec says "links to the Accounts tab" — it is not settled whether this
   means (a) the standard Salesforce Account object list/record view, or (b) the same
   Pages-tab-filtered-by-account behavior the old branch built. Given no standard
   `Accounts` custom tab/nav item is confirmed to exist in this app's nav (only
   `GTM_Pages`, `GTM_Assessments`, `GTM_Content_Manager` are referenced elsewhere in this
   component), **the Architect must confirm which target is intended** — most likely
   reusing the existing `c__rlfAccountId` → `GTM_Pages` pattern is correct and "Accounts
   tab" in the written spec is loose phrasing for "the tab where accounts are browsed in
   this app," but this should be confirmed against the mockup artifact directly (readable
   via the Figma/Docs MCP or Bash before building) rather than assumed.
2. **Contact row** (nested under Account): Contact Name (first + last — `DealSummary`
   already carries `contactName` as a single already-concatenated `Contact__r.Name`
   string from the branch's diff, which is fine, Salesforce's `Name` on Contact is
   already "First Last"). Links to a Contacts tab — same ambiguity as above applies
   (verify against mockup / existing nav item names before implementing; do not invent a
   `GTM_Contacts` tab reference without confirming it exists).
3. **Link row**, 3 columns:
   - **Col 1 (identity):** Offering name as the primary link text, going to the Pages tab
     drilled into that specific link (reuse `handleLinkRowClick`'s existing
     `c__template:'link', c__recordId` pattern exactly). Link/config name (e.g. "Mike P
     Intro") as smaller secondary text underneath — **not** a repeat of the account name
     (the superseded branch's `deal-sub` under the deal name currently shows
     `row.deal.account`, i.e. account name — this is exactly the duplication the user
     asked removed; the secondary text must become the link/config's own name, e.g.
     `d.configName`, which `DealSummary` already has as `configName`). Check whether
     `DealSummary` exposes an offering label distinct from `configName` — grep shows
     `industryLabel` and `company` exist but no explicit offering display name; confirm
     with the Offering metadata (`GTM_Saved_Configuration__c.Offering__c` /
     `Offering_Key__c`) whether a human-readable offering name needs a new query field
     (e.g. join `Offering__r.Name` or resolve via the existing `GTM_Offering__mdt`) — if
     so this is a `getDeals()` query change, not a new field on any object, so no
     permission-set work applies.
   - **Col 2 ("Opportunity"):** Opportunity number linking to the Opportunity record
     page, Opportunity stage as a pill below using existing `.pill--good` / `.pill--warn`
     / `.pill--info` / `.pill--quiet` tone classes already defined in
     `gtmOverview.css` (lines ~282-285) — reuse tone-mapping logic already implicit in
     the superseded branch's `row.deal.stageClass`/`stageLabel` getters (need to
     re-inspect that mapping and carry it forward, do not invent new colors). Note
     `DealSummary.opportunityName` currently holds the Opportunity's `Name` field, which
     in this org may or may not be a distinct "Opportunity number" — **verify whether
     Opportunity Name is what's meant by "Opportunity number" in the mockup, or whether a
     separate Opportunity Number field/`OpportunityNumber` convention is expected**; if
     the org has no separate number field, `opportunityName` (already queried, no Apex
     change needed) is almost certainly the intended value — confirm against the mockup
     screenshot.
   - **Col 3 ("Assessment"):** if an assessment exists, `AR-###` (i.e.
     `GTM_Assessment_Request__c.Name`, confirmed auto-number format elsewhere in this
     controller — `RequestSummary.name = req.Name` already treats it this way) linking to
     the Assessments tab drilled into that specific assessment (reuse the existing
     `c__assessmentRequestId` → `GTM_Assessments` idiom already consumed by
     `gtmReadoutsOverview.js`, do not invent a new state param), with the submission date
     below it — `GTM_Assessment_Request__c.Submitted_At__c` is the correct field (confirmed
     to exist on the object; `CreatedDate` is the request's creation time, not
     necessarily submission time, so prefer `Submitted_At__c` if it's reliably populated
     for submitted requests — Architect/Developer should check whether `Submitted_At__c`
     is null for any request currently surfaced via `requestId`/`requestStatus` on
     `DealSummary`, and fall back to `CreatedDate` only if `Submitted_At__c` is
     unpopulated for submitted-status records). If no assessment exists yet: render an
     em dash placeholder (`—`), no link, no broken href — same defensive pattern the
     superseded branch already used for `row.deal.hasRequest` (`<span
     class="deal-none">—</span>`).

### Pagination

- Paginate at the **Account** level: 5 account groups per page (matches the mockup),
  each page rendering all of that group's nested contacts and link rows in full — not a
  flat row-count-based page size.
- Needs: Previous/Next controls, a current-page indicator, and a total count (of account
  groups, presumably, though total link-row count as a secondary stat would also read
  fine — mockup should be checked for exact wording).
- This is pure client-side JS state added around the existing `dealGroups`/`dealRows`
  getters (slice `dealGroups` by page before flattening to `dealRows`) — `getDeals()`
  already returns up to 200 records in one Apex call (`LIMIT 200`), so no server-side
  pagination/Apex change is required for this unless the Architect decides 200 is an
  insufficient cap for the paginated UI (out of scope to change unless flagged).

### Removed content (explicit, do not carry forward)

- Column headers/cells for "CRM stage", "On the page", "Last activity".
- The card header's `<span class="ov-h-note">What each recipient did with the page you
  sent</span>` subtitle — delete this element entirely, not just its text.
- The account row's duplicate account-name line (previously appeared as a second
  `deal-group-name`-adjacent element or via the `deal-sub` account name under the link
  row's own name, per user note — the exact prior duplication site should be re-verified
  against whichever branch state the Architect starts from, since the written spec says
  it appeared twice: once under the offering name in the link row, and the account row
  itself was also said to have had "a duplicate account name below the link name" — both
  instances must be checked and removed).

### New column headers

Three headers only: something like "Account / contact / link" (exact wording should
match the mockup precisely — re-check the artifact rather than guessing further), plus
"Opportunity" and "Assessment".

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? — **No.** This is the `gtmOverview` LWC and
      `GtmHomeSnapshotController` Apex, not any GUS chat/tool-calling surface. Existing
      `getDeals()` already has zero DML (read-only SOQL/AggregateResult), and this issue
      adds no DML — verify this remains true if `getDeals()`'s query is extended with new
      fields (should be a pure SELECT-list addition, no write paths touched).
- [ ] Altering Custom Metadata? — **No.** No `GTM_Assessment_*` custom metadata records
      are touched; this reads `GTM_Saved_Configuration__c`, `Opportunity`, and
      `GTM_Assessment_Request__c` standard/custom **object** records (not metadata types),
      so the YAML-vs-XML hand-edit rule in CLAUDE.md §2 does not apply here.
- [ ] Introducing database fields? — **No new fields.** Everything referenced
      (`Opportunity.Name`/`StageName`, `GTM_Assessment_Request__c.Name`/
      `Submitted_At__c`, `GTM_Saved_Configuration__c.Account__c`/`Contact__c`/
      `Offering__c`) already exists on the org's schema per the field-metadata directory
      listing checked during scoping. If the Architect/Developer determines a
      human-readable Offering display name genuinely requires a new query relationship
      (e.g. `Offering__r.Name` via a lookup that doesn't currently exist, rather than the
      existing `Offering_Key__c` string), that is a **query-field addition only** (adding
      a field to an existing SOQL SELECT list), not a new schema field — so no
      Permission Set mapping is triggered under CLAUDE.md §6. If in the course of
      implementation any *actual* new custom field turns out to be necessary, stop and
      re-scope — that would require the CLAUDE.md §6 permission-set grants
      (`GTM_Offering_User`/`Admin`) this checklist currently rules out.

## 3. Plan Acceptance Criteria

- **Success Metric:** On `gtmOverview`, the "Opportunities to follow up on" card renders
  the 3-level Account → Contact → Link hierarchy with exactly 3 leaf-row columns
  (Account/Contact/Link identity, Opportunity, Assessment) and no CRM-stage/On-the-page/
  Last-activity content anywhere; the card subtitle is gone; account-name text appears
  exactly once per account row and is not repeated under the link row's offering name;
  every link row's Assessment cell shows either a working `AR-###` deep link + submission
  date, or an em dash with no link when no assessment exists; the widget is paginated by
  account group (5 per page) with working Previous/Next and a page/total indicator, and
  scrolling/loading a large deal set no longer produces one long unbroken table; rep
  users still only see their own `OwnerId`-scoped deals (regression check — must not
  regress the rep-data-scoping-OWD work already landed this session); all pill/tone
  colors reuse `gtmOverview.css`'s existing `.pill--*` classes, zero new hex/color
  literals introduced.
- **Target Test Target:** `force-app/main/default/lwc/gtmOverview/__tests__/gtmOverview.test.js`
  (Jest — extend with cases for the new 3-column row shape, the em-dash "no assessment"
  branch, and account-level pagination slicing/Previous-Next behavior) and
  `force-app/main/default/classes/GtmHomeSnapshotControllerTest.cls` (Apex — extend
  `getDeals()` coverage for any new `DealSummary` fields, e.g. Offering display name,
  `Submitted_At__c` propagation, and confirm the `OwnerId`-scoping test cases already
  present, per the `rep-data-scoping-owd-1` comments in
  `GtmHomeSnapshotController.cls`, still pass unchanged).
## Addendum — Architect Review & Ambiguity Resolutions (2026-09-18)

Code Dependency Checklist reviewed against actual repo state: all three boxes are
correctly unchecked/No. `getDeals()` remains a read-only SOQL query (no DML added by
this change); no `GTM_Assessment_*` custom metadata is touched; no new schema fields are
introduced (offering label is resolved via an additional SELECT, see Resolution 3), so no
permission-set grants are triggered under CLAUDE.md §6.1. No placeholder brackets remain
in the scope doc. Checklist is compliant — proceeding to provisioning.

### Resolution 1 — "Accounts tab" / "Contacts tab" link targets

Read the CURRENT `main` (post-merge) `force-app/main/default/lwc/gtmOverview/gtmOverview.js`
directly. Finding: **`handleAccountClick` does not exist on `main` at all**, and neither
does any Account/Contact grouping — the "Opportunities to follow up on" widget on `main`
today (`loadDeals()`, lines ~97-128) is still the old flat list, where the account name
renders as **plain text** (`<span class="deal-sub">{d.account}</span>` in
`gtmOverview.html` line 177) with no link and no click handler at all. The
Account→Contact→Link hierarchy, `dealGroups`/`dealRows`, and `handleAccountClick` only
exist on the **unmerged** `agent/issue-overview-redesign-table-nav` branch
(commit `53a18a2`), confirmed by reading that branch directly:

```
handleAccountClick(event) {
    const accountId = event.currentTarget.dataset.accountId;
    if (!accountId) return;
    this[NavigationMixin.Navigate]({
        type: 'standard__navItemPage',
        attributes: { apiName: 'GTM_Pages' },
        state: { c__rlfAccountId: accountId }
    });
}
```

Since that superseded branch is the only place an account-name *link* currently exists
in this codebase, and the user's "(good now)" comment can only be referring to that
existing behavior (there is nothing else it could mean — main has no account link to
approve), the resolution is: **preserve this exact mechanism** —
`standard__navItemPage` → `GTM_Pages` with `state: { c__rlfAccountId: accountId }` —
unmodified, for the Account row link. This also matches CLAUDE.md §4's "typical/no new
idiom" preference and the scope doc's own nav-idiom inventory (no `Accounts`/`Contacts`
custom tab exists in this app's nav — only `GTM_Pages`, `GTM_Assessments`,
`GTM_Content_Manager`).

For the **Contact row**, mirror this same shape analogously rather than inventing a
`standard__recordPage`/Contact-record nav: add a new `handleContactClick` that navigates
`standard__navItemPage` → `GTM_Pages` with a new state key, e.g.
`c__rlfContactId: contactId` (or extend `gtmRepLinkFinder`'s existing filter contract if
it already accepts a contact-level filter — Developer should check
`gtmRepLinkFinder.js`/its controller for whether a `c__rlfContactId` (or equivalently
named) filter param is already wired before inventing a new one; if not, this is a small,
additive state-param extension of the exact same idiom, not a new nav pattern).

### Resolution 2 — "Opportunity number"

Checked `force-app/main/default/objects/Opportunity/fields/` — no custom
`Opportunity_Number__c` or similar field exists on the org's Opportunity object schema.
`Opportunity.Name` (standard field) is the only candidate, already queried and already
exposed as `DealSummary.opportunityName` / `d.opportunityName` in `gtmOverview.js`. No
Apex or SOQL change needed for this column's primary value. Resolved: **use
`opportunityName` as-is.**

### Resolution 3 — Offering display name for column 1

`GTM_Saved_Configuration__c.Offering__c` is a plain text field (offering key string), not
a lookup — confirmed via `force-app/main/default/objects/GTM_Saved_Configuration__c/fields/`.
There is no `Offering__r.Name` relationship to join. The existing, established convention
for resolving an offering key to its human-readable label is `GTM_Offering__mdt`, queried
by `Offering_Key__c` and joined against `Label__c`, with a fallback to the raw key when no
metadata record matches yet (see `GtmPageContentController.getOfferings()` and
`getHomeSummary()`, both of which gtmOverview's own "Offerings" card already consumes via
`getHomeSummary`). Resolved: `getDeals()` needs a **query-side addition only** — either a
supplemental `SELECT Offering_Key__c, Label__c FROM GTM_Offering__mdt` map built once per
call and used to resolve each row's `Offering__c` key to a label (falling back to the raw
key string, matching the existing convention exactly), added as a new
`DealSummary.offeringLabel` field. This is not a new database/custom field — `GTM_Offering__mdt`
already exists and is already queried elsewhere — so per the Code Dependency Checklist,
no permission-set grant is triggered.

### Worktree

Provisioned via `scripts/agent-workspace.sh create opportunities-table-redesign-v2` per
AGENTS.md §2, branch `agent/issue-opportunities-table-redesign-v2`, based on the BA scope
branch `ba-scope/issue-opportunities-table-redesign-v2`. Per the BA's §0 Supersession
Notice, the Developer should branch fresh off `main` (already the base of this worktree)
and re-apply only the reusable pieces (grouping getters, click handlers per Resolution 1,
Apex `DealSummary` additions) rather than checking out the superseded branch directly —
main has diverged since `53a18a2` and re-applying is lower-noise than rebasing forward.
