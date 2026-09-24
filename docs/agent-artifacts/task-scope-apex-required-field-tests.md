# TASK SCOPE — ISSUE #apex-required-field-tests

## 1. Requirements Breakdown

- **Target Objective:** Make five Apex tests pass on any org (they fail on gtm-staging with REQUIRED_FIELD_MISSING in setup), and determine whether GtmReadoutControllerTest.generationFilesTheOwningRepAReviewCase is a real defect or staging-only.
- **System Component Impacted:** Apex test classes only (test data). No production Apex, LWC, or metadata change expected.

Findings (read-only; verified against source and gtm-staging):

1. GtmContactEngagementControllerTest.testFullyPopulated: helper `makeReadout` inserts `GTM_Readout__c` with only `Assessment_Request__c` and `Status__c`. `GTM_Readout__c.Offering_Key__c` is `required=true` (objects/GTM_Readout__c/fields/Offering_Key__c.field-meta.xml, introduced in 4889b0f, PR #28, 2026-09-10). The test was added afterwards (5155799, issue-39, 2026-09-11), so it was broken from birth. Other readout tests (e.g. GtmReadoutPublicControllerTest) set `Offering_Key__c = 'migration-accelerator'`.
2. GtmLinkRecoveryControllerTest (4 methods): `@TestSetup` inserts `GTM_Saved_Configuration__c` with Contact__c, Active__c, Generated_URL__c but no `Offering__c`, which is `required=true` (GTM_Saved_Configuration__c/fields/Offering__c.field-meta.xml, also 4889b0f). Test added in c9c6333 (issue-44, 2026-09-11), after the field became required. Note: GtmContactEngagementControllerTest.makeConfig already sets `Offering__c`, but the Saved_Configuration also requires nothing else that is missing there.
3. Cause is test data only. Production code is not wrong: the required flags are intentional schema. These are not staging-specific; they fail on any org where the fields are deployed as source defines (a fresh scratch org included). They were likely never run in CI after those merges.
4. generationFilesTheOwningRepAReviewCase: NOT confirmed as a test-data issue. Source is consistent: Case.Readout__c exists in source and on staging (Tooling API CustomField confirmed); `GtmReadoutController.fileReviewCase` inserts the Case inside a try/catch that only System.debug's on failure, so any insert failure silently yields 0 Cases. gtm-staging is an SDO org with many active Case flows/triggers (SDO_Service_Case_Creation, SDO_Service_Case_Routing, SDO_Service_Case_Status_Updated, triggers SDO_Service_AI_CaseSentimentTrigger, SDO_Tool_SalesforceRewind_Case) and Case field/validation config that do not exist in a blank org. The most likely cause is an SDO-side failure on Case insert (required field, validation rule, flow fault), i.e. staging-specific, but this is unproven. Developer must capture the debug log ("Could not file the readout review case: ...") from a run of that method to get the actual exception before classifying it. Also, the sibling test `aQueueOwnedReadoutSurvivesWhateverHappensToItsReviewCase` and `reviewCaseCanBeSwitchedOffInConfig` should be checked on staging for the same symptom. If the exception is SDO-only, do not change production code; document as a known staging-only failure (or make the test tolerant only if the owner agrees). If it is a real product defect on a blank org, escalate as a separate issue.
   Open question for owner: whether SDO-only failures should be excluded/documented rather than worked around in tests. No gtm-prod involvement.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO (test data only; zero-DML rule in AGENTS.md §1 not affected)
- [ ] Altering Custom Metadata? NO
- [ ] Introducing database fields? NO (no permission set changes expected; if the Case investigation finds otherwise, revisit)

## 3. Plan Acceptance Criteria

- **Success Metric:** (a) GtmContactEngagementControllerTest.makeReadout sets `Offering_Key__c` (e.g. 'migration-accelerator'); GtmLinkRecoveryControllerTest @TestSetup sets `Offering__c` on the saved configuration; no production class or metadata file changes. (b) All 5 listed tests pass on gtm-staging and every other method in both classes still passes. (c) Developer reports the captured exception for generationFilesTheOwningRepAReviewCase and classifies it as staging/SDO-only or a real defect; no production change unless proven real. (d) No metadata/permset changes unless the Case investigation demonstrates one is needed. Validate-only against gtm-staging; no gtm-prod deploy.
- **Target Test Target:** `sf apex run test -o gtm-staging -n GtmContactEngagementControllerTest`, `sf apex run test -o gtm-staging -n GtmLinkRecoveryControllerTest`, and `sf apex run test -o gtm-staging -n GtmReadoutControllerTest` (with `--result-format human --code-coverage` and a debug log for the Case test).
