# TASK SCOPE — ISSUE #102-1

**Parent intake:** #102, "BD workflow intake: relay model for engagement link → submission → readout → deliver → MA handoff." **Split map:** `docs/agent-artifacts/task-scope-102-overview.md` — read that first; it explains why this is sub-ticket 1 of 5 and what's already shipped vs. still needed.

This ticket covers **deliverable A (the engagement-link landing)** and **deliverable B (the forward hand-off)** from the intake, together, because B's hand-off button is meaningless without A's landing to hand off to and both are governed by the same "one row = one recipient's next action" contract (stakeholder decision D8).

## 1. Requirements Breakdown

- **Target Objective:** Replace the readout-keyed, filing-cabinet navigation with a single dedicated landing — "Engagement Links" — that lists every link a BD has sent, one row per link, grouped visually by contact, ranked as a **queue** (what needs the BD's action first, not recency), each row carrying exactly one primary forward action for its state. Clicking a row's assessment content, in turn, must offer an explicit next-step control ("Open the readout") rather than dead-ending on a read-only screen. This directly answers the stakeholder's original complaint: *"you're creating this experience with tabs but not fully understanding what I want... here are all of my engagement links by contact and by company."*

  **Binding stakeholder rulings this ticket must implement exactly, not reinterpret (from #102's own comment thread):**
  - **D1 — new dedicated tab**, shaped like Overview's "Deals in play" card. Overview keeps its existing summarized Deals card unchanged in shape; this ticket adds a new, separate landing, it does not rebuild Overview into the landing.
  - **D6 — scope toggle**, `[My links | My team | All]`, defaulting to **My links**. This is a scope control (whose rows appear), not the state filter (`[All | Needs action | Sent | Draft]`) — that chip row is out of scope for this ticket, it belongs to 102-2 and needs #277's `Status__c` field first.
  - **D7 — keep auto-creation, label the control "Open the readout."** Do not build a "Generate" action; the Draft readout already exists by the time the BD reaches this screen (created inside the prospect's own submit transaction, `GtmAssessmentRequestController.cls:858`). The click opens it, it does not create it.
  - **D8 — one row per engagement link, visually grouped by contact.** Row shape:
    ```
    Jordan Reyes — Commercial Metals
       SC-0015   submitted    [Open the readout]
       SC-0022   not opened   [Resend]
    Priya Sundaram — Solara Health
       SC-0031   opened       [—]
    ```
    Every row state needs a defined primary action. Enumerate and implement all six states below (D8 + D13 together):
    | State | Primary action |
    |---|---|
    | Submitted, readout in Draft | Open the readout |
    | Readout published but not sent | Send to prospect *(— 102-3's deliverable actually builds "Send"; this ticket must at minimum route to wherever that action will live, or show it disabled with a tooltip if 102-3 hasn't shipped yet — confirm with Architect which)* |
    | Started but not submitted | Follow up |
    | Opened, not started | Follow up |
    | Never opened | Resend |
    | Sent / complete | — (no action) |
  - **D13 — the landing is a queue, ranked by who is blocking, not by CreatedDate.** Ranking, highest priority first:
    1. Submitted, readout in Draft (BD is blocker)
    2. Readout published but not sent (BD is blocker)
    3. Started but not submitted (nudge-able)
    4. Opened, not started (nudge-able)
    5. Never opened
    6. Sent / complete (no action; should fall to the bottom)
    Within a rank, most-recent-activity first. **This ranking must be computed in the Apex query/response, not client-side after the fact** — per D13's own "Data implication," sorting and paging break if state is computed per-row in the client.
  - **D3 (auto-generation)** is already answered by D7 above — do not re-litigate "generate vs. open."

- **System Component Impacted:** Apex (`GtmContactEngagementController`, new/extended methods), LWC (`gtmContactEngagement` — extend, do not replace; `gtmAssessmentDetail` — add forward action; `gtmOverview` — repoint one navigation target), tab/nav metadata (`applications/GTM_Offerings.app-meta.xml`, possibly a new `.tab-meta.xml` if the existing `GTM_Saved_Configuration__c` tab isn't reused directly), permission sets (existing `GTM_Saved_Configuration__c` tab is already `Visible` to both rep permission sets per the intake's own verification — confirm this is still true on current `main` before assuming no permission-set work is needed here).

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? **No.** This ticket touches no `GtmAgentToolSurface` implementation, no tool registration, no DML inside a tool. Not applicable.
- [ ] Altering Custom Metadata? **No.** No `customMetadata/GTM_Assessment_*` XML involved. Not applicable.
- [x] Introducing database fields? **No new fields.** This ticket is read-only query/response shaping over existing fields (`Contact__c`, `Account__c`, `Company__c`, `Offering__c`, `Active__c`, `GTM_Link_Event__c.Event_Type__c`/`CreatedDate`, `GTM_Assessment_Request__c.Submitted_At__c`, `GTM_Readout__c.Status__c`) plus the addition of a `recordId` field to the existing `LinkEngagementSummary` Apex wrapper class (not a database field — a DTO field, no metadata deploy, no permission-set mapping required). If the Architect's design surfaces the two score axes or any other field not already covered by 102-1's `Contact` scope, defer that to 102-2 (deliverable C explicitly extends field coverage; this ticket's job is the list, not the detail).

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. A BD navigating to the new "Engagement Links" tab sees every link scoped to `[My links | My team | All]` (default My links), ranked per D13's 6-tier priority order (verified: change one link's state in test data and confirm it re-sorts to the correct rank, not just displays a correct-looking badge).
  2. Rows are grouped visually by contact per D8's shape; each row shows its correct single primary action for its state (all six states from the table above must be exercisable and produce the right action, or the right disabled/empty state for "Sent/complete").
  3. Clicking a row's link navigates to the submission detail (`gtmAssessmentDetail`, wherever it's mounted — tabset or record page).
  4. `gtmAssessmentDetail` renders a new "Open the readout" forward action after the existing content, and clicking it lands on the readout — via `active-tab-value` swap inside the tabset context, and via `NavigationMixin` on the standalone `GTM_Assessment_Request_Record_Page` context (dual-mode, both must work — the intake documents these as the two real mount points; confirm no third mount point exists via `grep -rln "c-gtm-assessment-detail" force-app/main/default/lwc/*/*.html force-app/main/default/flexipages/*.flexipage-meta.xml` before assuming only two).
  5. The three `<lightning-tab>` elements in whatever container hosts Readout/Assessments/Migration Accelerator get real `value` attributes and an `active-tab-value` binding (today: `grep -rn "active-tab-value|activeTabValue" force-app/main/default/lwc/` returns nothing — this ticket is what first makes that non-empty), and the tabs are reordered so Assessments precedes Readout.
  6. `GtmContactEngagementController.getEngagementSummaries` is generalized from `WHERE Contact__c = :contactId` to an owner/team/all-scoped query (no `Opportunity__c != null` filter inherited from `GtmHomeSnapshotController.getDeals()` — that filter is exactly what makes today's Deals table incapable of listing every link, do not repeat it here), gains a `recordId` field, and has real bounded paging (do not repeat the silent uncounted `LIMIT 200`/`LIMIT 500` pattern found in `getDeals()`/`getAllReadouts()` — return a count and a truncated flag if a limit is hit).
  7. Overview's existing `handleContactClick` (in `gtmOverview.js`, built this session) is repointed from `gtmRepLinkFinder`/Pages-tab navigation to the new Engagement Links landing, scoped to that contact.
  8. All new/changed Apex is `with sharing`, uses `WITH SECURITY_ENFORCED` or equivalent FLS-safe pattern consistent with the existing `GtmContactEngagementController` code, and ships with Apex test coverage for the new scoping logic (My links / My team / All) and the new ranking logic (all six states, boundary cases like a link with a readout but no `Submitted_At__c`).
  9. `npm test` (Jest) passes for `gtmContactEngagement`, `gtmAssessmentDetail`, and `gtmOverview`'s changed test files; no test suite regresses.
  10. No reference to `gtmRepLinkFinder`/Pages tab is *removed* from nav in this ticket — D5's nav retirement is explicitly out of scope for 102-1 (it's 102-2's job, sequenced after this landing is proven). This ticket only adds the new tab; it does not retire the old ones.

- **Target Test Target:** `GtmContactEngagementControllerTest` (extend with new scoping/ranking/paging assertions), plus a new or extended Jest spec for `gtmContactEngagement` (queue ranking, row-action-per-state) and `gtmAssessmentDetail` (`__tests__/gtmAssessmentDetail.test.js` — forward-action dual-mode navigation). Run `sf apex run test --class-names GtmContactEngagementControllerTest --target-org gtm-staging` (never `RunLocalTests`, per `docs/runbooks/api-request-budget.md`) and `npm run test` for the LWC suites before handing to QA.
