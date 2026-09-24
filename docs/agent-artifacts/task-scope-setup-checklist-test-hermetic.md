# TASK SCOPE — ISSUE #setup-checklist-test-hermetic

## 1. Requirements Breakdown

- **Target Objective:** Make `GtmSetupChecklistControllerTest.guestAndSiteRowsAreNeverFalselyDoneWithoutASite` hermetic so it passes on any org state. A validate-only deploy of main to `gtm-prod` with RunLocalTests (1026 tests) has exactly one failure, at test line 294: `Assert.areEqual('LINK', m.get('guest_permset').actionType)` gave `Expected: LINK, Actual: NONE`. Production behavior must NOT change.
- **Root cause (confirmed in code and read-only queries):**
  - `GtmSetupChecklistController.detectGuest` first calls `setupLink(...)`, which sets actionType LINK. It then reads org-wide setup data the test cannot control. Network is read with `SELECT ... FROM Network LIMIT 200`, and the site is resolved by name `GTM` (constant `SITE_NAME`), or by being the only network. The guest user is read from `Site.GuestUserId`, then `PermissionSetAssignment` is counted for `PS_GUEST` on that guest user.
  - If a guest user is found and has GTM_Guest, the row goes through `done()`. `done()` resets actionType to NONE and linkKind to NONE. That is the intended production behavior.
  - Otherwise the row is UNKNOWN (no readable or identified site) or TODO (guest lacks the permset), and actionType stays LINK.
  - `@IsTest` without SeeAllData still sees Network, Site and the guest PermissionSetAssignment, because they are setup objects.
  - gtm-prod (read-only, names and statuses only): 3 networks, namely `GTM` (Live) and two `ZZ DELETE` sites (DownForMaintenance). The site resolves by name to `GTM`. GTM_Guest has 2 assignments (count only). So guest_permset is legitimately DONE with actionType NONE.
  - gtm-staging: 2 networks (`SDO - Consumer` Live, `GTM` Live). The test passes there because GTM_Guest is not assigned to the GTM guest user (row is TODO, action LINK) or the guest lookup gives UNKNOWN. Either way the pass is incidental, not an invariant. The same hard-coded assertion can fail after any staging fix-up.
  - `site_active` (only Network.Status) and `site_members` (NetworkMember count) are equally org-state dependent. The test does not assert their actionType beyond "not ASSIGN_*", so they are safe today.
- **Recommended fix (test-only, one file):** In `force-app/main/default/classes/GtmSetupChecklistControllerTest.cls`, replace line 294 with a status-consistent invariant. Apply it in the existing loop to all three keys, because each calls `setupLink` and `done()`, so the invariant is the same:
  - status is in VALID_STATUSES (already asserted).
  - actionType is in {NONE, LINK} (never ASSIGN_TO_ME, ASSIGN_PICKER, CREATE_FRAMEWORK_PAGES or SCHEDULE_JOBS).
  - If status == 'DONE' then actionType == 'NONE' and linkKind == 'NONE'.
  - If status != 'DONE' (TODO, UNKNOWN, BLOCKED) then actionType == 'LINK'.
  - Rename or adjust the comment so the test states its real intent: "never falsely DONE without a site". Optionally add: if the org has zero Networks (`[SELECT COUNT() FROM Network] == 0`), then guest_permset must not be DONE (this one is hermetic-conditional, not org-dependent).
  - No test seam is needed. The existing `@TestVisible forceFailKey` is not suited to this case: it forces UNKNOWN through the catch, and it yields LINK only for keys whose `unknown()` row had already set a link, which it does not (`unknown()` calls `base()`, so actionType is NONE). Do not add a new production seam. Do not modify `GtmSetupChecklistController.cls`.
- **Sibling test audit (same class, org-state dependence):**
  - `guestAndSiteRowsAreNeverFalselyDoneWithoutASite`: the only test that breaks on prod (line 294).
  - `unassignedAdminOffersAssignToMeAction`: already branches on TODO vs DONE. OK.
  - `frameworkPagesDetailListsMissingTemplateIdsLiterally`: already guarded by `if (status == 'TODO')`. OK.
  - `draftOfferingCreates...`, `archivedOfferingDoesNotCountAsPublished` and `industryWithLabel...` use before/after guards. The `industryWithLabel` and `draftOffering` asserts of 'DONE' are made after inserting their own data, so they are robust.
  - `blankOrgReturnsWholeCatalogueWithinBudget`: `requiredTotal == 8` is a constant of the catalogue, not org state. The `used <= 30` SOQL budget is independent of network count, since Networks are read in a single query. Low risk. It should be re-checked in the prod validate run, which the failure report already shows passing.
  - `aFailingDetectorIsIsolatedToItsOwnRow`: `approval_routing` and `framework_pages` are not org-state dependent. OK.
  - `settingsSectionRowsCarryTheirSectionId`, `noDetailContainsAnOrgIdOrUsername`, `aiKeysRowNeverExposesKeyText` and `managerRowShownOnlyInManagerApprovalMode` create their own data or assert constants. OK.
  - `searchAssignableUsers*`: create their own users with unique names. OK.
  - `permissionSetAssignmentsAreDetected`: assigns its own permission sets and expects DONE, which is org-independent.
  - Conclusion: only the one test needs changing; no other sibling assertion would differ on an org with sites or guest already configured.
- **Ambiguity:** none. Production data is not touched. Only read-only queries were run: `gtm-prod` Network name/status and a GTM_Guest assignment count.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO. The change is a test-class edit only; no zero-DML rule concerns (no GUS tool touched, no production Apex changed).
- [ ] Altering Custom Metadata? NO.
- [ ] Introducing database fields? NO. No metadata or permission set changes.

## 3. Plan Acceptance Criteria

- **Success Metric:** `GtmSetupChecklistControllerTest` passes 100% on `gtm-staging` (validate-only or test run, explicit `-o gtm-staging`). A validate-only deploy of main plus this change to `gtm-prod` with RunLocalTests (`--dry-run`, explicit `-o gtm-prod`, no real deploy) shows zero failures, including the previously failing test. `GtmSetupChecklistController.cls` is byte-identical to main. No metadata, permission set, or custom metadata diff.
- **Target Test Target:** Apex class `GtmSetupChecklistControllerTest` (method `guestAndSiteRowsAreNeverFalselyDoneWithoutASite`, plus the whole class for regression).
