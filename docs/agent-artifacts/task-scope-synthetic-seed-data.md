# TASK SCOPE — ISSUE #synthetic-seed-data

## 1. Requirements Breakdown

- **Target Objective:** Build a synthetic/demo data layer so the app looks populated for UI exploration and stakeholder walkthroughs. Seed a small, realistic-looking set of Accounts, Contacts, Opportunities ("deals"), `GTM_Saved_Configuration__c` engagement-link pages spread across the `Presentation_Stage__c` lifecycle, `GTM_Assessment_Request__c` records, `GTM_Link_Event__c` activity, `GTM_Form_Draft__c` drafts, and `GTM_Readout__c` (+`GTM_Readout_Version__c`) readouts. GUS reading this data as tool-use context is an incidental side benefit, not a design driver — do not add anything (eval transcripts, fine-tuning fixtures, prompt-test data) that only serves GUS training/evaluation; that is explicitly out of scope per the user's direction.
- **System Component Impacted:** Data layer (`data/seed/`) plus new load/teardown tooling (`scripts/`, likely `scripts/seed-synthetic-data.sh` or `.py` following the `build-instrument.py` convention) and one schema addition (see §2) across the standard SFDX object metadata in `force-app/main/default/objects/`. No LWC or Apex business-logic changes are anticipated — this is data + a small provisioning/teardown script, not a new feature surface.

**Ambiguity flagged for the Architect:** this issue is scoped for `gtm-dev`, which `CLAUDE.md` §1 treats as **production** with live prospect data and no staging environment. Seeding synthetic records here is a genuine, non-boilerplate safety concern — not routine data work. The BA is deliberately NOT deciding unilaterally whether seeding directly into `gtm-dev` is acceptable versus first standing up a scratch/sandbox org for this purpose (the user's separately-noted desire for a staging environment, `project_staging_env_desired`, is directly relevant background here and should be weighed by the Architect/human owner before any load step actually runs against `gtm-dev`). The BA's role stops at design: producing seed data + a script that is safe *if* run, and flagging that the decision of *where/when* to run it against the only production org is a human call, not something to execute autonomously.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO.** No `GtmAgentToolSurface` implementation, tool registration, or DML-inside-tool concern applies — this is pure data provisioning, not GUS tooling. (AGENTS.md §1 zero-DML-inside-tool rule confirmed not triggered.)
- [ ] Altering Custom Metadata? **NO** in the `GTM_Assessment_*` CMDT sense — do not touch `migration-accelerator/` instrument YAML or `force-app/main/default/customMetadata/GTM_Assessment_*` XML; those define instrument *logic/questions*, not sample transactional data, and are out of scope here. **YES** in a narrower sense: this task requires one new schema field per seeded custom object (see below), which is a `CustomField` metadata addition, not a CMDT record change.
- [x] Introducing database fields? **YES.** Recommend a dedicated boolean flag field `Is_Synthetic__c` (Checkbox, default `false`) added to each seeded custom object: `GTM_Saved_Configuration__c`, `GTM_Assessment_Request__c`, `GTM_Link_Event__c`, `GTM_Form_Draft__c`, `GTM_Readout__c`. Standard objects (`Account`, `Contact`, `Opportunity`) cannot cleanly take a new custom field without touching unrelated standard-object metadata broadly used elsewhere in the org — the Architect should confirm whether a shared custom field (e.g. `Account.Is_Synthetic__c`, `Contact.Is_Synthetic__c`, `Opportunity.Is_Synthetic__c`) is acceptable there too, since the tagging mechanism is only trustworthy if it covers every object being seeded, standard or custom. Per CLAUDE.md §6 (FLS & Permission Set Deficiencies), each new field is invisible to profile-based FLS until added to a permission set — mapping is mandatory:
  - `Is_Synthetic__c` on `GTM_Saved_Configuration__c`, `GTM_Assessment_Request__c`, `GTM_Link_Event__c`, `GTM_Form_Draft__c`, `GTM_Readout__c` → add to `GTM_Offering_Admin` (full CRUD/FLS) and `GTM_Content_Admin` where applicable; add read-only or full FLS to `GTM_Offering_User`/`GTM_Content_Manager` only if reps/content editors need to see the flag in the UI (likely not — this is an internal/admin housekeeping field, so restrict FLS to the Admin permission sets to avoid cluttering rep-facing layouts).
  - If a shared field is added to `Account`/`Contact`/`Opportunity`, the same FLS mapping across the 5 permission sets applies.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. A seed script (naming convention following `scripts/build-instrument.py`, e.g. `scripts/seed-synthetic-data.py` or `.sh`) inserts a demo-sized set of records — target roughly 5–8 Accounts, 1–2 Contacts each, 1 Opportunity per Account, and a spread of `GTM_Saved_Configuration__c` pages covering all five `Presentation_Stage__c` values (`Draft`, `In_Review`, `Sent`, `Assessment`, `Rep_Direct`), plus a handful of `GTM_Assessment_Request__c`, `GTM_Link_Event__c`, `GTM_Form_Draft__c`, and `GTM_Readout__c` records reachable from those pages — without tripping Duplicate Rules (CLAUDE.md §6: use `Database.insert(records, false)` or equivalent matching-safe insert path in the script, not naive `insert`) and without violating required fields (`GTM_Saved_Configuration__c.Offering__c`, `GTM_Readout__c.Offering_Key__c`/`Status__c`, `GTM_Link_Event__c.Event_Type__c`, `GTM_Form_Draft__c.Draft_Type__c`/`Status__c` all confirmed required in current metadata and must be populated with valid values).
  2. Every synthetic record is tagged on both dimensions the user specified: `Is_Synthetic__c = true` (flag field, §2) AND a `[DEMO]` prefix on every human-readable name field touched (Account.Name, Contact.LastName/Name, `GTM_Saved_Configuration__c.Name`/page-title field, `GTM_Readout__c` title field) as a visual-inspection backstop even though the flag field is the authoritative mechanism. This dual-tagging decision is deliberate per the user's explicit instruction and is documented here rather than left to be decided silently in code.
  3. A companion teardown path in the same script (e.g. `--teardown` flag) queries every seeded object `WHERE Is_Synthetic__c = true` and bulk-deletes, is idempotent (safe to run with zero synthetic records present), and never issues any query or DML without the `Is_Synthetic__c = true` filter — this is the load-bearing safety guarantee against touching real prospect data.
  4. Seed data itself is authored following the existing `data/seed/` sf-data-tree JSON convention (`attributes.type`/`referenceId` cross-references, as seen in `data/seed/migration-accelerator.story.records.json`) rather than inventing a new format, confirmed compatible for these objects; if the Architect determines sf-data-tree can't cleanly express the cross-object reference chain needed (Account → Contact → Opportunity → `GTM_Saved_Configuration__c` → `GTM_Assessment_Request__c`/`GTM_Readout__c`), that gap must be flagged explicitly rather than silently switching mechanisms.
  5. New `Is_Synthetic__c` fields are mapped to permission sets per §2 before deploy (CLAUDE.md §6 Definition of Done).
- **Target Test Target:** `GtmSavedConfigurationControllerTest.cls` and `GtmReadoutControllerTest.cls` (regression: confirm existing queries like `getDeals()`/readout listing logic are unaffected by new synthetic records or the new field); plus a manual verification pass — run the script's `--teardown` path against a scratch/dev-adjacent context first (per the flagged ambiguity above) and confirm a `SELECT COUNT()` across all five tagged objects returns 0 afterward, and that no row lacking `Is_Synthetic__c = true` was touched.

## 4. Data Safety

- **Tagging mechanism (decision, not left to code):** Dual-tag every synthetic record — (1) `Is_Synthetic__c` boolean field (authoritative, queryable, drives teardown) added to each seeded custom object (`GTM_Saved_Configuration__c`, `GTM_Assessment_Request__c`, `GTM_Link_Event__c`, `GTM_Form_Draft__c`, `GTM_Readout__c`) and, pending Architect confirmation, mirrored onto `Account`/`Contact`/`Opportunity`; (2) a `[DEMO]` prefix on every human-readable name/title field as a visual-inspection backstop so anyone scanning list views or reports can recognize synthetic rows even before checking the flag. Both are required — the flag alone is invisible in default list views; the prefix alone is not safely queryable/reliable for bulk teardown.
- **Teardown mechanism:** The same script that seeds data supports a `--teardown` (or separate `--cleanup`) mode that deletes strictly by `WHERE Is_Synthetic__c = true` per object, in dependency order (child records — `GTM_Link_Event__c`, `GTM_Form_Draft__c`, `GTM_Assessment_Request__c`, `GTM_Readout__c` — before parent `GTM_Saved_Configuration__c`, before `Opportunity`/`Contact`/`Account`) to respect lookups/master-detail relationships, and is idempotent and safe to re-run. The script must never run an unfiltered delete against any of these objects.
- **Production-org risk:** `gtm-dev` is the only environment and is treated as production (CLAUDE.md §1) — every record this script inserts lands directly alongside live prospect data the moment it's run there. The BA is not authorizing when/whether this script is actually executed against `gtm-dev`; that decision (and whether a scratch org should be stood up first) belongs to the Architect/human owner, and is called out explicitly in §1 above.

## 5. Architect Addendum — Resolution of gtm-dev Execution Ambiguity

The BA correctly declined to decide, unilaterally, whether/when the seed
script should actually be run against `gtm-dev` (the only org, treated as
production per CLAUDE.md §1, no staging environment currently exists —
see `project_staging_env_desired`). This addendum resolves that ambiguity
for the purposes of THIS issue's Definition of Done.

**Resolution: this issue's scope is BUILD + LOCAL VALIDATION ONLY. Live
execution against `gtm-dev` is explicitly OUT OF SCOPE for the Developer
and for QA on this issue.**

- **In scope (Developer):**
  - Author the seed/teardown script per §2/§3 above (schema fields,
    permission-set grants, `data/seed/` sf-data-tree records, dependency-
    ordered load/delete logic, `Is_Synthetic__c` + `[DEMO]` dual-tagging).
  - Validate schema-correctness of every record shape without inserting
    live data — e.g. `sf data create record --dry-run` equivalents,
    `sf project deploy start --dry-run` for the metadata/field additions,
    or local structural validation against the object's field
    definitions/required-field list pulled from `force-app/main/default/objects/`.
  - Validate dependency-order correctness of the load sequence (Account →
    Contact → Opportunity → `GTM_Saved_Configuration__c` →
    `GTM_Assessment_Request__c`/`GTM_Readout__c`, and the reverse for
    teardown) via code review / unit-level checks of the script logic
    itself, not a live run.
  - Validate idempotency of the teardown filter (`WHERE Is_Synthetic__c =
    true`, never unfiltered) by inspecting/unit-testing the query-building
    logic in the script — confirm no code path can construct a query or
    DML statement without that filter — again without executing against
    `gtm-dev`.
  - Regression-test `GtmSavedConfigurationControllerTest.cls` and
    `GtmReadoutControllerTest.cls` per §3 (these run against whatever org
    the Developer's existing test workflow already targets for Apex unit
    tests — that is unchanged/pre-existing practice, not new production
    writes introduced by this issue).
- **Explicitly OUT of scope (Developer and QA):**
  - Do NOT run the seed script's load path against `gtm-dev`.
  - Do NOT run the teardown/`--teardown` path against `gtm-dev` "just to
    verify it works" — that is precisely the naive verification instinct
    this addendum blocks. A script that only "looks correct" until
    someone actually runs it is not sufficient justification; the org has
    live prospect data and no rollback/staging safety net.
  - QA must NOT execute either path live as part of its normal "validate
    in the browser" pass (`feedback_qa_browser_validation`) for this
    issue — QA validates the code (script logic, field/permission-set
    metadata deploys cleanly via dry-run, tests pass) but not a live
    seed/teardown run.
- **Explicit human/coordinator decision required before any live run:**
  Whether, when, and by whom the seed script is actually executed against
  `gtm-dev` — including whether a scratch/sandbox org should be stood up
  first (per `project_staging_env_desired`) instead of ever running this
  against `gtm-dev` at all — is a separate decision to be made by the
  coordinator/human owner after this issue's code has been reviewed and
  merged. It is not implied approval, and no agent in this roster (BA,
  Architect, Developer, QA) may execute the live load or teardown path
  unprompted as part of closing out this issue.
