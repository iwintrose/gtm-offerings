# TASK SCOPE — ISSUE #48

## 1. Requirements Breakdown

- **Target Objective:** Issue #48 asserts that issue #26's Draft/Published Status and Archive backend
  (`GtmPageContentController.setOfferingStatus` / `setOfferingArchived` / `getHomeSummary`) was merged
  with **no UI anywhere** to drive it, and asks for that UI to be built in `gtmContentHome`.
- **System Component Impacted:** None — this is a verification/no-op finding, not a build task.

  **This issue is already resolved on `main` as of commit `49ce6bf` ("feat(gtm-content-manager):
  industry-profile authoring, per-offering industry copy, and offering Status/Archive (issue-26)"),
  merged via PR #27 (`838dac9`, the current HEAD of `main`).** Verified directly against the working
  tree, not just the commit message:

  - `force-app/main/default/lwc/gtmContentHome/gtmContentHome.js` imports and calls both
    `setOfferingStatus` (line 643, inside `handleToggleOfferingStatus()`) and `setOfferingArchived`
    (line 674, inside `handleConfirmArchiveToggle()`), reading initial state from `getHomeSummary()`'s
    `offeringStatus`/`archived` fields via the `cards` getter (lines 178–186).
  - `force-app/main/default/lwc/gtmContentHome/gtmContentHome.html` renders a `"Manage offering"`
    button per offering card (`showManage`, lines 163–168) that is a **distinct element** from the
    existing per-page `"Settings"` link (`handleOpenSettings`), and a modal (`manageOpen`, lines
    283–333) exposing a Status toggle button and a two-step Archive/Restore confirm flow — matching
    issue #26's own acceptance criterion #3 verbatim.
  - `force-app/main/default/lwc/gtmContentHome/__tests__/gtmContentHome.test.js` has a full Jest
    describe block ("offering Manage control (Status / Archive)", 6 tests) asserting: the control
    renders and is distinct from Settings, it's absent from the framework card, the modal opens/shows
    the right offering, Status toggling calls `setOfferingStatus` with the flipped value, Archive
    requires a confirm step before calling `setOfferingArchived`, and un-archiving calls
    `setOfferingArchived(false)` with no confirm. **Ran this suite directly
    (`npx sfdx-lwc-jest`): all 6 tests pass.**
  - `force-app/main/default/classes/GtmPageContentControllerTest.cls` (lines 432–536) already has
    Apex coverage for `setOfferingStatus`/`setOfferingArchived`: creating a tile section when none
    exists, updating one in place, rejecting invalid status values, refusing the framework key for
    both methods, and setting/clearing the Archived flag. Issue #48's acceptance criterion asking to
    "confirm existing GtmPageContentControllerTest.cls coverage... it should already exist... verify,
    don't just assume" — **verified: it exists and is adequate** (covers both success and rejection
    paths for both methods).

  **Why issue #48's premise is false:** the issue's own evidence is
  `grep -rln "Offering_Status__c\|Archived__c" force-app/main/default/lwc/` returning zero results.
  That grep is a false negative, not a real gap: the LWC layer never references those two Custom
  Field API names as literal strings — it consumes them exclusively through the Apex
  `OfferingSummary.offeringStatus` / `OfferingSummary.archived` DTO properties (already differently
  named from the underlying fields) and through the imperative Apex method imports
  `setOfferingStatus` / `setOfferingArchived`. Grepping for the two Custom Field API names in
  `force-app/main/default/lwc/` was never going to find a hit even in a fully-wired implementation,
  which is exactly the state found here. Issue #48 was almost certainly filed by re-running the
  same verification grep from issue #26's own writeup without re-checking it against the LWC that
  PR #27 had, by then, already shipped.

  **This is not a design fork requiring a human decision on how to build the feature** — the feature
  is built, and built to spec. The only open question, and the reason this is being escalated rather
  than silently closed, is **process**, which only a human can settle: is issue #48 simply stale
  (opened before, or without seeing, PR #27's merge) and should be closed with a comment pointing at
  `49ce6bf`/PR #27 and this scope file, or is there a *narrower* real gap the issue's author actually
  observed (e.g., a specific environment where the Manage control is not rendering, a permission
  set gap hiding the control from certain profiles, or a discrepancy between what's in `gtm-dev`
  today and what's in this repo's `main`) that got mis-described using an outdated grep. Recommend:
  do not open a Developer/Architect worktree against this issue as a build task. Have a human
  (a) confirm whether `gtm-dev` is actually running the code at `838dac9`/PR #27 or an older deploy
  that predates it, and (b) close or re-scope issue #48 accordingly.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **N/A** — no GUS/tool-surface code is touched by this issue; the
      feature already lives entirely in `gtmContentHome` (LWC) and `GtmPageContentController` (Apex),
      neither of which is a `GtmAgentToolSurface` implementation.
- [ ] Altering Custom Metadata? **No** — `Offering_Status__c` and `Archived__c` are standard Custom
      Fields on `GTM_Page_Section__c` (real DML-backed fields, not Custom Metadata Type records), per
      the Apex header comments at `GtmPageContentController.cls` lines 725-730 and 758-761 ("Ordinary
      DML... this is a real custom field, not custom metadata, so there is no async deploy step"). No
      `migration-accelerator/` YAML or `GTM_Assessment_*` XML is implicated by this issue at all.
- [ ] Introducing database fields? **No** — both fields were already introduced and permission-set
      mapped as part of issue #26/PR #27 (out of scope to re-verify FLS here since no new field is
      being introduced by this issue; if reopened as a real gap, a fast follow-up check should confirm
      `Offering_Status__c`/`Archived__c` are present in `GTM_Content_Manager`/`GTM_Content_Admin`
      permission sets, since that is where a genuine "control renders but is invisible/read-only to
      some content authors" symptom would actually originate — but this was not observed in the code
      review above and is speculative).

## 3. Plan Acceptance Criteria

- **Success Metric:** No code change is required to close this issue. Success is a human decision
  (see §1) to either (a) close issue #48 as already resolved by PR #27 / commit `49ce6bf`, citing this
  `TASK_SCOPE.md` and the passing Jest run as evidence, or (b) re-file a narrower issue describing the
  specific real-world symptom (e.g., against `gtm-dev` specifically) if one still exists once (a) is
  ruled out.
- **Target Test Target:** `force-app/main/default/lwc/gtmContentHome/__tests__/gtmContentHome.test.js`
  (already passing — 6/6 tests, verified via `npx sfdx-lwc-jest` in this scoping session) and
  `GtmPageContentControllerTest.cls` methods `setOfferingStatus_createsTheTileSectionWhenNoneExistsYet`,
  `setOfferingStatus_updatesAnExistingTileSectionInPlace`,
  `setOfferingStatus_rejectsAnythingOtherThanDraftOrPublished`, `setOfferingStatus_refusesTheFramework`,
  `setOfferingArchived_setsAndClearsTheFlagOnTheTileSection`, `setOfferingArchived_refusesTheFramework`
  (lines 432-536) — no new test authoring is in scope unless issue #48 is re-scoped per §1.
