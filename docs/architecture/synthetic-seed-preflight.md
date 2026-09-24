# Synthetic demo seed: field-writability contract, preflight and teardown

Status: design (issue demo-seed-fix). Supersedes the "--check" description in the
`scripts/seed-synthetic-data.py` module docstring where they differ.

## 1. Incident

`--load` into the test org failed at plan step 4. `data/seed/synthetic-demo.saved-configurations.json`
wrote `Industry_Label__c` on all 6 records; that field is a FORMULA (derives from `Industry__c`) so the
API rejects it (`INVALID_FIELD_FOR_INSERT_UPDATE`). `--check` passed because it (a) never asked whether a
field is writable, and (b) hand-maintains `REQUIRED_FIELDS`. Steps 1-3 had already committed 5 Accounts,
7 Contacts, 5 Opportunities (standard objects, untagged, so `--teardown` cannot find them by flag).

## 2. Audit result (all files in `data/seed/`, checked against `force-app/.../objects/*/fields/*.field-meta.xml`)

Only ONE defect exists in the seed data: `Industry_Label__c` (formula) on `GTM_Saved_Configuration__c`
demoCfg1..6. Every other custom field written by `synthetic-demo.*.json` exists, is not
formula/rollup/autonumber, has an in-set value where the picklist is restricted, has a correctly typed
value (checkbox=bool, number=number, text within length, email well-formed), every required field
(`Offering__c`; `Offering_Key__c`+`Status__c` on Readout; `Event_Type__c`; `Draft_Type__c`+`Status__c`;
`Readout__c` master-detail) is present, and every `@ref` resolves to an earlier plan step of the type the
lookup points at. `migration-accelerator.*` and `test-offering.*` (GTM_Page_Content__c / GTM_Page_Section__c)
are clean. Account/Contact/Opportunity fields loaded fine live (17 records inserted). No validation
rules/lookup filters exist on the 6 GTM objects; the only trigger, `GtmReadoutApprovalSync`, is
`before/after update`, so it does not fire on the seed's inserts. No other latent failure exists for the
five objects that never loaded, on the evidence of the repo metadata. The org itself (deployed field set,
FLS of the running user) can still differ, which is why section 4 adds a live preflight.

Latent gaps (not failing today):
- `--teardown` is a stub: `cmd_teardown` prints "NOT EXECUTING" and returns 3. It cannot clean anything.
- `--load` on failure raises an uncaught `CalledProcessError`; no cleanup guidance.
- `--load` has no "already loaded" guard, so a second run duplicates every standard record.
- `scripts/check-references.py` section 10 only checks that `__c` keys exist, not that they are writable.
- No CI step runs `seed-synthetic-data.py --check`.

## 3. Contract: offline `--check` writability rules (no org call)

For every record in every plan file, per key `k` (excluding `attributes`), on object `O`:

| Rule | Applies to | Failure |
|---|---|---|
| exists | custom `O`: `objects/O/fields/k.field-meta.xml` must exist. Standard `O`: `k` must be in `STANDARD_WRITABLE[O]` (explicit allowlist, seeded with the fields the seed uses today plus obvious peers) | "field does not exist / not on the standard-field allowlist" |
| not formula | `<formula>` element present | "formula field, not writable" |
| not rollup | `<type>Summary</type>` | "roll-up summary, not writable" |
| not autonumber | `<type>AutoNumber</type>`; and `k == "Name"` when the object's `<nameField><type>` is `AutoNumber` (all 6 GTM objects) | "auto-number, not writable" |
| not system | `k` in `Id, CreatedDate, CreatedById, LastModifiedDate, LastModifiedById, SystemModstamp, IsDeleted, LastActivityDate, OwnerId` | "system-managed" (OwnerId denied: the seed must not pick owners; load user owns) |
| reference shape | field type Lookup/MasterDetail: value must be `"@<referenceId>"`, the referenceId must be defined at an earlier-or-same plan step, and its sobject must equal the field's `<referenceTo>` (raw 15/18-char Ids rejected as org-specific). Exception: `referenceTo == User` fields are rejected outright | "unresolvable / wrong-type reference" |
| required | metadata-derived: `<required>true</required>` or MasterDetail. Standard-object required list stays hand-maintained. Also assert the hand `REQUIRED_FIELDS` for custom objects equals the metadata-derived set, so drift is a check failure | "missing required field" |
| picklist | value in `<valueSet>` for every Picklist (restricted: error; unrestricted: allowed but printed as a note). Existing behaviour retained | as today |
| type shape | Checkbox=bool; Number/Currency numeric, within precision/scale; Text/LongTextArea/Html/Email string within `<length>`; Email regex; Date `YYYY-MM-DD`; DateTime ISO-8601 | "wrong type/too long" |
| plan/object coverage | plan step `sobject` and each record's `attributes.type` agree (exists today) and the object directory exists for custom objects | "unknown object" |

Implementation shape: one function `field_facts(sobject, field) -> dict(type, formula, required, length,
precision, scale, referenceTo, picklist_values, restricted)` parsed from field-meta.xml (with an
`lru_cache`), plus `object_facts(sobject) -> dict(name_field_type)` from `<O>.object-meta.xml`. Everything
reads `force-app`; no `sf`, no network. `picklist_values()` is folded into it.

`scripts/check-references.py` section 10: add the same three cheap rules for `__c` keys (formula,
`Summary`, `AutoNumber`, and `Name` on an AutoNumber object) using a small local helper that reads the
field's `<type>`/`<formula>`. It stays a defence-in-depth mirror; `seed-synthetic-data.py --check` is the
authority for the demo set (check-references also covers `migration-accelerator.*`/`test-offering.*`).

## 4. Contract: load safety (no partial load)

Cross-step atomicity is impossible with `sf data import tree --plan` (each file commits on its own), so
the design prevents the failure instead of undoing it, and cleans up when prevention was not enough.

`--load -o <alias> --i-understand-this-writes-to-org <alias>` becomes, in order:
1. Existing guard (alias repeated) and offline `--check` (must be clean).
2. NEW live read-only preflight `preflight_org(org)` (still refuses without the guard): one
   `sf sobject describe -s <O> -o <alias> --json` per plan object (Account, Contact, Opportunity + the 6 GTM
   objects = 9 read-only calls). For every key the seed writes, assert the describe field exists and is
   `createable: true`, that every restricted picklist value is in `picklistValues` (`active`), and that
   every required (`nillable:false && createable && !defaultedOnCreate`) createable field is written. Any
   failure prints all problems and exits 1 before a single DML. This is what catches org drift (field not
   yet deployed to the test org, FLS of the loading user) that offline metadata cannot see. Expose it as
   `--preflight -o <alias>` too (read-only, no confirmation flag needed since it writes nothing).
3. NEW already-loaded guard: `sf data query` (read-only) for any `GTM_Saved_Configuration__c` etc. with
   `Is_Synthetic__c = true` and any standard record matching the orphan rule (section 5). If any exist,
   refuse and instruct `--teardown` first.
4. `sf data import tree --plan`. Catch `CalledProcessError` (no traceback), and on nonzero exit print the
   failing step and exactly: "Partial load possible. Run: --teardown -o <alias> --i-understand-this-writes-to-org <alias>".
   No automatic delete on failure (a delete the user did not confirm is worse than a message); teardown
   is safe to re-run by design.
5. `run_sf`'s "would run:" wording is corrected to "running:".

## 5. Contract: teardown (implement it; today it is a stub)

`--teardown` executes `build_teardown_plan()` for real, honouring the existing hard safety rule, plus one
additional final phase. Sequence:
1. Query `SELECT Id, Account__c, Contact__c, Opportunity__c FROM GTM_Saved_Configuration__c WHERE Is_Synthetic__c = true`,
   also `Account__c, Contact__c, Opportunity__c` from `GTM_Assessment_Request__c` and `Opportunity__c` from
   `GTM_Readout__c` WHERE `Is_Synthetic__c = true`; collect the standard Ids BEFORE deleting anything.
2. Delete in the existing child-to-parent order via `sf data delete bulk` (Ids from a query), each step
   filtered exactly as in `build_teardown_plan()`; empty result set = no-op (idempotent).
3. Delete the collected Opportunity, Contact, Account Ids (allowlist).
4. NEW orphan sweep for a failed/partial load (standard records with no flagged saved-config pointing at
   them). A standard record is an orphan candidate only if it matches the exact seed identity, ALL of:
   - Account: `Name IN (<the seed Names in synthetic-demo.accounts.json>)`; then, IN PYTHON on the returned `Description`, it must start with `Synthetic demo account seeded by scripts/seed-synthetic-data.py` (SOQL cannot filter on Description, a long text area: it can only SELECT it)
   - Opportunity: `Name IN (<the seed Names in the opportunities file>)`; then, IN PYTHON on the returned `Description`, it must start with `Synthetic demo opportunity seeded by scripts/seed-synthetic-data.py`
   - Contact: `LastName IN (<the 7 LastNames in the contacts file>)` AND `Email IN (<the 7 Emails in the contacts file>)` (all `.invalid`) AND `Account.Name IN (<seed Account Names>)`
   The IN lists are read from the seed files at run time, never typed by hand. Then subtract any orphan
   candidate still referenced by a non-synthetic row (`GTM_Saved_Configuration__c`/`GTM_Assessment_Request__c`
   with `Is_Synthetic__c != true` and `Account__c/Contact__c/Opportunity__c IN candidates`); if any such
   reference exists, skip that record and print it (never delete a record a real row points at).
   Print the candidate list and counts before deleting. Cascade note: deleting an Account soft-deletes its
   Contacts/Opportunities anyway; delete children first to keep counts accurate.
5. `assert_teardown_plan_is_safe()` is extended: allow the orphan-sweep step ONLY when its WHERE contains
   both a seed-derived `Name IN`/`LastName IN` and the `Description LIKE`/`Email IN` marker; still refuse
   any unfiltered or `Is_Synthetic__c`-on-standard-object clause. `--check-teardown` (offline) covers it.
6. Exit codes: 0 done or nothing to do; 1 a step failed (print what remains); the stub's exit 3 is removed.

Real prospect data can never be selected: every clause is an exact-identity match on values that only this
repo's seed files contain (`.invalid` TLD, `[DEMO] ` prefix, the script's own description marker) plus the
"no real row references it" subtraction.

## 6. Tests / acceptance

The repo has no pytest suite. Python checks are exercised as self-contained scripts run in CI (see
`.github/workflows/agent-ci-gate.yml`: `python3 scripts/backfill-link-owner.py --check`) and by hand.
Follow that pattern:
- `python3 scripts/seed-synthetic-data.py --check` : exit 0 on the corrected data.
- NEW `python3 scripts/seed-synthetic-data.py --self-test` : offline mutation tests. In a temp copy of the
  records (monkeypatch `load_records`) inject one defect at a time and assert `check_seed_files()` returns a
  problem naming the field: (1) `Industry_Label__c` on a Saved Configuration (must be the regression test),
  (2) an AutoNumber write (`Name` on `GTM_Readout__c`), (3) a nonexistent `Bogus__c`, (4) a roll-up/`Summary`
  field (synthetic fixture field in a temp objects dir, use the `OBJECTS_DIR` override), (5) `OwnerId`,
  (6) restricted picklist value not in set, (7) missing required field, (8) `@ref` to wrong sobject type,
  (9) raw 18-char Id in a lookup, (10) wrong type (string for Checkbox), (11) `Name` on Account is still
  allowed (negative control), (12) unmutated data yields zero problems. Also assert the orphan-sweep WHERE
  built from the seed files contains every seed Name/Email and is accepted by `assert_teardown_plan_is_safe`,
  and that a WHERE with no marker is rejected. Exit nonzero on any failure. No org, no `sf`.
- NEW CI step in `agent-ci-gate.yml` next to the backfill step running `--check`, `--check-teardown`,
  `--self-test` (all offline).
- `python3 scripts/check-references.py` : section 10 reports no new "would-not-deploy" finding versus main
  (the CI gate is baseline-diffed); demonstrate the new rule by temporarily re-adding `Industry_Label__c`
  and seeing it flagged (not committed).
- Preflight/teardown org paths are not unit-testable offline: split shell-outs behind one
  `run_sf_json(args, org)` function so `--self-test` can stub it and assert (a) preflight rejects a describe
  where `Industry_Label__c` has `createable:false`, (b) `--teardown` issues deletes in plan order and never
  a query lacking a marker, (c) a second run with empty query results is a no-op.

## 7. Deployment / QA plan

1. Developer implements (files in scope doc), runs `--check`, `--check-teardown`, `--self-test`,
   `check-references.py`, `npm test` untouched.
2. QA re-runs the same, plus the mutation of re-adding `Industry_Label__c` (must fail `--check`).
3. Coordinator (not the Developer or QA agents) runs, against `gtm-staging` ONLY, in this order:
   a. `--preflight -o gtm-staging` (read-only) must be clean. Also confirm no `[DEMO]` records exist
      (coordinator already deleted the 17 loose ones).
   b. `--load -o gtm-staging --i-understand-this-writes-to-org gtm-staging`; expected inserts: 5 Account,
      7 Contact, 5 Opportunity, 6 Saved Config, 3 Assessment Request, 2 Readout, 3 Readout Version,
      8 Link Event, 3 Form Draft = 42.
   c. Verify counts by SOQL, and that `Industry_Label__c` renders 'Retail' etc. on the saved configs.
   d. `--teardown -o gtm-staging ...`; verify all custom rows and all 17 standard rows are gone; run it a
      second time and confirm a clean no-op; run `--load` again to prove reload works.
   e. Orphan-sweep test on staging only: insert nothing by hand; instead have the Developer's stubbed
      self-test cover it, and optionally the coordinator loads only via a plan copy to step 3, then runs
      `--teardown` to see the sweep delete exactly those 17 and nothing else.
4. gtm-dev is never a target; the script refuses nothing by alias name today, so add a hard refusal in
   `cmd_load`/`cmd_teardown` if `-o` equals `gtm-dev` (alias only; no org ID committed) unless an explicit
   `--allow-production` flag that this issue does not document beyond the docstring.

## 8. Amendment: SOQL filterability (issue demo-seed-fix, live dry-run finding)

The first live `--teardown --dry-run` failed: `field 'Description' can not be filtered in a query call`.
Description on Account, Contact and Opportunity (and any LongTextArea, Html or EncryptedText custom field)
can be SELECTed but never used in a WHERE. Rules now enforced in code:

- The orphan sweep filters only on filterable identity fields (seed Name; seed LastName + Email +
  Account.Name), SELECTs `Description` (or `Email`), and accepts a row only if `sweep_row_verified()` confirms
  the script's Description marker (or a `.invalid` Email) in Python. Same-name rows without the marker are
  reported as "LEFT ALONE" and never deleted.
- `assert_query_filterable(soql)` parses every WHERE (string literals stripped) and refuses a
  non-filterable field, resolving `__r` and standard relationships against `NONFILTERABLE_STANDARD` and the
  `<type>` in the field metadata. It runs inside `soql_query` (every runtime query), inside
  `assert_teardown_plan_is_safe` (`--check-teardown`), and over every query the teardown and guards build in `--self-test`.
- `assert_query_safe(soql)` additionally requires an identifying filter: `Is_Synthetic__c` on a custom object,
  an Id/AccountId allowlist, or on standard objects ONLY exact seed literals read from the seed files.
- The self-test stub rejects a Description/long-text WHERE the way the real org does, independently of the script's guard.

Query audit (read from the code, Salesforce SOQL rules) versus live-only confirmation is in the issue report.
