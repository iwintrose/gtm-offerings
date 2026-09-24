# TASK SCOPE — ISSUE #migration-pairs-sort-test-fix

## 1. Requirements Breakdown

- **Target Objective:** Fix a failing Apex test. `GtmMigrationPairsTest.listPlatformsReturnsActiveKeyAndLabelOrderedByLabel` (`force-app/main/default/classes/GtmMigrationPairsTest.cls`, lines 201-218) failed on `gtm-dev` after wizard PR #223 deployed, with "ordered case-insensitively by label: Expected: oracle Eloqua, Actual: Marketing Cloud Engagement".
  - **Root cause:** the test's expectations are wrong, not the production code. I verified `GtmMigrationPairs.PlatformOption.compareTo` (lines 100-105) lowercases both labels (null becomes `''`) and calls `String.compareTo`. That is correct case-insensitive ordering.
  - **Correct order for the fixture:** `account engagement` (mcae), `marketing cloud engagement` (sfmc), `oracle eloqua` (eloqua). Inactive row 'Zeta Retired' and blank-key row 'No Key' are skipped.
  - **Test defect:** the test asserts `options[1].label == 'oracle Eloqua'` and `options[2].key == 'sfmc'`. The order of those two is swapped.
  - **Required fix (TEST-ONLY):** correct the assertions to
    - `options[0]`: key `mcae`, label `Account Engagement` (already correct, unchanged)
    - `options[1]`: key `sfmc`, label `Marketing Cloud Engagement`
    - `options[2]`: key `eloqua`, label `oracle Eloqua`
  - **Keep unchanged:** the `size() == 3` assertion; the fixture, including the lowercase-initial 'oracle Eloqua' label; the retired and blank-key rows; the assertion messages' intent (case-insensitive ordering; inactive and blank-key rows skipped).
  - **Out of scope:** no change to `GtmMigrationPairs.cls`, metadata, LWC, or permission sets.
  - **Ambiguity:** none. No `gtm-dev` data is touched.
- **System Component Impacted:** Apex test class only, `GtmMigrationPairsTest.cls`.
- **Process lesson (record for the pipeline):** Developer and QA agents cannot execute Apex tests (no org access allowed), so this defect was only caught at coordinator deploy time on `gtm-dev` (treated as production). The QA step for this issue therefore cannot run the test. It must verify by reading: hand-sort the fixture labels case-insensitively (lowercase them, then sort) and check that each assertion matches that order.
- **Live verification:** the coordinator will deploy and run `GtmMigrationPairsTest` afterwards.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? N/A. No tool-surface change; the test performs no DML.
- [ ] Altering Custom Metadata? N/A. The test uses in-memory `platformOverride` fixtures only, and no `migration-accelerator/` YAML is touched.
- [ ] Introducing database fields? N/A. No fields, so no Permission Set mapping is needed.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  - The diff touches only `GtmMigrationPairsTest.cls`, within `listPlatformsReturnsActiveKeyAndLabelOrderedByLabel`.
  - The ordering assertions match the hand-sorted, case-insensitive order: mcae / Account Engagement, then sfmc / Marketing Cloud Engagement, then eloqua / oracle Eloqua.
  - The `size() == 3` assertion is retained.
  - The ordering assertions still include a label whose first letter differs only by case from its neighbours. The lowercase-initial 'oracle Eloqua' fixture is what proves case-insensitivity and must be kept. A plain ASCII sort would place it last, so the test is only meaningful with that fixture.
  - Every assertion in the method is checked by QA against the hand-sorted order, since QA cannot run the test. The assertions are in the correct order, and inactive and blank-key rows are still excluded.
  - No changes to production code, metadata, or permission sets.
  - Live pass on `gtm-dev` is confirmed by the coordinator after deploy.
- **Target Test Target:** Apex class `GtmMigrationPairsTest`, method `listPlatformsReturnsActiveKeyAndLabelOrderedByLabel`. Run by the coordinator, not by QA. QA does a read-only hand-sort check.
