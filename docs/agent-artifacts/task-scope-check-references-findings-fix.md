# TASK SCOPE — ISSUE #check-references-findings-fix

## 1. Requirements Breakdown

- **Target Objective:** Fix 3 pre-existing, confirmed-real defects surfaced by the expanded
  `scripts/check-references.py` checker (new FLS-completeness and picklist-validity checks, added
  by the separate, not-yet-merged `local-validation-expansion` issue on branch
  `agent/issue-local-validation-expansion`, commit `1d30137`). This issue's branch only needs to
  fix the 3 underlying data points on `force-app/` and `data/seed/` — it must NOT touch
  `scripts/check-references.py` itself; that checker code ships via the separate
  `local-validation-expansion` merge. The 3 defects are:
  1. `GTM_Offering_User` permission set is missing a `fieldPermissions` grant for
     `GTM_Form_Draft__c.Saved_Configuration__c`. Confirmed by reading
     `force-app/main/default/permissionsets/GTM_Offering_User.permissionset-meta.xml`: the set
     already grants `Saved_Configuration__c` on the two sibling objects
     `GTM_Assessment_Request__c` (readable=true, editable=false) and `GTM_Link_Event__c`, but has
     no equivalent entry for `GTM_Form_Draft__c`. Add one, matching the same
     readable/editable shape used for the sibling objects (readable=true, editable=false — this
     field is populated by the platform/flow, not hand-edited by the rep, matching the existing
     `Saved_Configuration__c` grants).
  2. `GTM_Offering_Admin` permission set is missing a `fieldPermissions` grant for
     `GTM_Page_Section__c.Archived__c`. Confirmed by reading
     `force-app/main/default/permissionsets/GTM_Offering_Admin.permissionset-meta.xml`: the set
     already grants `GTM_Page_Content__c.Archived__c` (readable=true, editable=true, with an
     explanatory comment referencing `issue-184-schema-cascade`) and
     `GTM_Page_Content__c.Archived_Date__c`, and also already grants
     `GTM_Page_Section__c.Archived_Date__c`, but has no `GTM_Page_Section__c.Archived__c` entry.
     Add one, matching the sibling shape (readable=true, editable=true).
  3. `data/seed/synthetic-demo.assessment-requests.json` (added by the merged
     `synthetic-seed-data` issue, commit `ff48de4` / PR #216, now on `main`) seeds
     `GTM_Assessment_Request__c.Target_Platform__c = "Eloqua"` at line 59 of that file, which is
     not in the field's actual `<valueSet>` (confirmed by reading
     `force-app/main/default/objects/GTM_Assessment_Request__c/fields/Target_Platform__c.field-meta.xml`:
     valid values are `Salesforce Marketing Cloud (SFMC)`, `Salesforce Marketing Cloud Next`,
     `Marketo`, `HubSpot`, `Pardot / Account Engagement`, `Not decided yet`, `Other`). Change the
     literal `"Eloqua"` to `"Marketo"` (a realistic, plausible substitute for a demo record; the
     other two seed records in the same file already use `Salesforce Marketing Cloud (SFMC)`, so
     `Marketo` keeps the synthetic dataset varied rather than duplicating the existing value).
- **System Component Impacted:** Permission Sets (`force-app/main/default/permissionsets/`) +
  Seed Data (`data/seed/`). No Apex, no LWC, no Custom Metadata/YAML instrument changes, no new
  fields or objects.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No — this touches permission set XML and a static JSON seed
      file only; no Apex DML paths are introduced or changed.
- [ ] Altering Custom Metadata? No — `GTM_Form_Draft__c`, `GTM_Page_Section__c`,
      `GTM_Assessment_Request__c`, and their fields already exist; this issue adds no fields, no
      objects, and touches no `instrument/<offering-key>/` YAML or
      `force-app/main/default/customMetadata/GTM_Assessment_*` XML.
- [ ] Introducing database fields? No — both `Saved_Configuration__c` (on `GTM_Form_Draft__c`) and
      `Archived__c` (on `GTM_Page_Section__c`) already exist and are already mapped to Permission
      Sets on their sibling objects; this issue is purely filling in a missed grant on an existing
      field for an existing permission set, using the exact grant shape already established for
      the sibling object in that same set. No new Permission Set mapping decision is required.

## 3. Plan Acceptance Criteria

- **Success Metric:** After this fix, checking out this issue's branch on top of a tree that also
  includes the `local-validation-expansion` checker changes (branch
  `agent/issue-local-validation-expansion`, commit `1d30137`) and running
  `python3 scripts/check-references.py` must exit `0` with zero findings from the 3 new check
  categories (FLS-completeness for `GTM_Form_Draft__c.Saved_Configuration__c` and
  `GTM_Page_Section__c.Archived__c`, and picklist-validity for the seeded `Target_Platform__c`
  value). This issue's own branch does not need to carry the checker code — Developer must verify
  the fix by running the checker locally against a checkout/merge that includes both diffs, and
  report that verification explicitly in the PR description since CI on this branch alone won't
  exercise the new checks.
- **Target Test Target:** `python3 scripts/check-references.py` (run against a local tree with
  both this issue's diff and the `local-validation-expansion` diff applied, per above). No Apex
  test class or Jest spec is implicated by this change — Developer should still run
  `./scripts/deploy.sh <org-alias> --dry-run` (or org-appropriate validate-only deploy) to confirm
  the permission set XML additions deploy cleanly.
