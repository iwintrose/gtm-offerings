# TASK SCOPE — ISSUE #assessment-instrument-rebuild-03-rule-engine-migration

> Sub-issue 03 of 4 in the `assessment-instrument-rebuild` umbrella (see
> `task-scope-assessment-instrument-rebuild-01-schema.md` for the full
> sequencing note and supersession of `docs/architecture/
> gtm-instrument-editor.md`). Depends on 01 (schema) and 02 (submission
> model) being deployed to `gtm-staging` first.

## 1. Requirements Breakdown

- **Target Objective:** Two linked pieces of work: (a) carry the existing,
  already-tested `gtmRuleEngine` evaluator (`evaluateRules`,
  `detectCircularDependencies`, `cleanupHiddenValues`) forward onto the new
  01-schema question/rule shape — the JSON rule shape itself (`logic`,
  `conditions[]`, `action`, `target`) is unchanged, so this is a re-target
  of field names/source objects, not a re-derivation of the evaluator
  logic; (b) write a one-time migration script (e.g.
  `scripts/migrate-instrument-yaml.py`, alongside the existing
  `scripts/build-instrument.py`) that reads
  `instrument/migration-accelerator/**/*.yaml` and produces new
  instrument-definition records (01 schema) for Migration Accelerator,
  preserving every `Question_Key__c` slug so existing branching references
  in `Rules_JSON__c`-equivalent fields don't break. Once QA validates
  parity on `gtm-staging`, retire the YAML/CMDT build path
  (`scripts/build-instrument.py`, `GTM_Assessment_*__mdt`) and update
  `GtmAssessmentInstrument.cls`/`GtmAssessmentQuestions.cls` to read from
  the new model instead. Per the approved plan, this is a **full cutover,
  not an additive fallback** — no offering keeps a "grandfather" YAML path
  after this sub-issue ships; that differs from the superseded
  `gtm-instrument-editor.md`'s grandfather rule (§4 of that doc), and this
  scope doc explicitly overrides it.
- **System Component Impacted:** LWC (`gtmRuleEngine`) + Apex
  (`GtmAssessmentInstrument.cls`, `GtmAssessmentQuestions.cls`) + a new
  Python migration script under `scripts/` + retirement of
  `scripts/build-instrument.py` and the `instrument/migration-accelerator/`
  YAML→CMDT build path (the YAML source files themselves are historical
  record and may be left in place or archived — do not silently delete
  without flagging to the human owner, since `reference/
  ma-migrator-capabilities/` and ADR-0009 treat this directory as
  meaningful history).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? Verify whether GUS reads
      `GTM_Assessment_*__mdt` directly anywhere (grep before starting) —
      if any GUS-invocable action queries the old CMDT, it must be
      re-pointed at the new schema in this sub-issue, respecting the
      zero-DML rule in AGENTS.md §1.
- [ ] Altering Custom Metadata? Yes, in the sense that this sub-issue
      *retires* the `GTM_Assessment_*__mdt`-generating path. Per CLAUDE.md
      layout constraints, changes to instrument content normally go
      through `migration-accelerator/` YAML + `scripts/build-instrument.py`
      — this sub-issue is the explicit, approved exception that removes
      that path rather than updating it, once parity is validated. Do not
      hand-edit the generated `GTM_Assessment_*__mdt` XML directly at any
      point; the 14 core hand-authored `GTM_Assessment_Question.*` records
      remain read-only for the build script per the CLAUDE.md exception,
      and their fate (migrate vs. leave as legacy-only) should be flagged
      to the human owner if unclear rather than guessed.
- [ ] Introducing database fields? No new fields in this sub-issue beyond
      what 01/02 already introduced; this sub-issue populates data into
      those existing structures via the migration script.

## 3. Plan Acceptance Criteria

- **Success Metric:** Running the migration script against `gtm-staging`
  produces new instrument-definition records for every offering under
  `instrument/migration-accelerator/`, with every `Question_Key__c`
  preserved so branching rules resolve identically; a side-by-side manual
  QA pass on staging (old YAML-driven instrument vs. new schema-driven
  instrument, same inputs) shows identical branching, scoring, and
  outcome-tier results; only after this parity is confirmed does the PR
  retire `scripts/build-instrument.py` and the CMDT build path. This
  sub-issue must **not** merge the retirement step without an explicit
  parity confirmation recorded in the PR description — this is a
  production-data-adjacent cutover (Migration Accelerator is a live,
  in-market offering) and should be flagged for the owner's explicit
  go-ahead before any `gtm-prod` deploy, per CLAUDE.md §5 promotion flow.
- **Target Test Target:** `gtmRuleEngine.test.js` (Jest, re-targeted field
  names), plus any existing Apex tests for `GtmAssessmentInstrument.cls`/
  `GtmAssessmentQuestions.cls` (exact class names to confirm against
  `force-app/main/default/classes/` at implementation time) updated to
  assert against the new schema instead of `GTM_Assessment_*__mdt`.
