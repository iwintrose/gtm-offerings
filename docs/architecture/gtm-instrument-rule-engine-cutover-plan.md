# GTM Instrument Rule Engine — Prepared Cutover Plan (NOT EXECUTED)

Status: **prepared, gated, not executed.** Deliverable of sub-issue
`assessment-instrument-rebuild-03-rule-engine-migration`, items 3 and 4 of
its scope doc (`docs/agent-artifacts/
task-scope-assessment-instrument-rebuild-03-rule-engine-migration.md`). This
document describes the cutover that a *later* PR will execute once its
explicit precondition is met. It changes no Apex in this sub-issue.

## 0. Why this is a plan and not a diff

`GtmAssessmentInstrument.cls` / `GtmAssessmentQuestions.cls` are the live
resolution engine behind Migration Accelerator's guest-facing assessment —
`docs/architecture/gtm-instrument-schema.md` §7's "Explicitly Out of Scope"
and this sub-issue's own scope doc both require the retirement/cutover step
to land **only after** a manual parity pass on `gtm-staging` confirms the
new-schema path reproduces identical branching, scoring, and outcome-tier
results against the legacy YAML/CMDT path, side by side, on real inputs. No
such parity pass can happen inside a worktree with no org access, so
swapping these classes' logic now — before that confirmation exists — would
ship an unvalidated behavior change into a production-data-adjacent surface
(Migration Accelerator is live, in-market). This document is the prepared,
reviewable plan; executing it is a separate PR, gated on that parity sign-off
and the owner's explicit go-ahead, per CLAUDE.md §5's promotion flow.

## 1. What stays exactly as-is in this sub-issue

- `GtmAssessmentInstrument.cls`, `GtmAssessmentQuestions.cls`,
  `GtmAssessmentInstrumentTest.cls`, `GtmAssessmentQuestionsTest.cls`: **no
  changes.** They keep reading `GTM_Assessment_Pair__mdt` /
  `GTM_Assessment_Dimension_Override__mdt` / `GTM_Assessment_Gate__mdt` /
  `GTM_Assessment_Supplement__mdt` / `GTM_Assessment_Question__mdt`, and keep
  driving the live guest assessment unchanged.
- `scripts/build-instrument.py` and the `GTM_Assessment_*__mdt` CMDT types:
  **no changes, not retired.** Still the source of truth for Migration
  Accelerator's live pair-adaptive content (per-pair overrides, ceilings,
  gates, complexity axis, supplements, callouts) until the cutover PR lands.
- `instrument/migration-accelerator/**/*.yaml`: left in place, per this
  sub-issue's scope doc §2 — historical/authoring record (`reference/
  ma-migrator-capabilities/` and ADR-0009 treat this directory as meaningful
  history), not silently deleted.

## 2. What sub-issue 03 *does* add, ungated

- `force-app/main/default/lwc/gtmRuleEngine/gtmRuleEngine.js`: re-targeted
  (comment/doc only — the evaluator functions and the `Rules_JSON__c` shape
  were already schema-agnostic) onto
  `GTM_Instrument_Question_Definition__c.Rules_JSON__c`. This is safe to ship
  now because `gtmRuleEngine` is a pure, framework-agnostic module not yet
  wired into any live LWC (sub-issue 04 wires it into `gtmInstrumentAuthor`)
  — there is no runtime behavior to regress.
- `scripts/migrate-instrument-yaml.py`: a one-time, local-only migration
  script producing new-schema record data (JSON + Markdown report) for
  Migration Accelerator's base 8-slot Readiness frame and its four score
  bands, run and validated locally in this sub-issue (see
  `scripts/tests/test_migrate_instrument_yaml.py`). Its output has **not**
  been loaded into `gtm-staging` or any org — see the script's own
  module-docstring execution boundary. Loading its output into `gtm-staging`
  is a separate step for the coordinator/owner, not part of this PR.

## 3. The cutover PR's precondition (must be true before it opens)

1. Sub-issue 04 (`assessment-instrument-rebuild-04-editor-lwc-wiring`) has
   landed a working authoring UI against
   `GTM_Instrument_Definition__c`/`_Question_Definition__c`/`_Outcome_Range__c`,
   and a content author has used it to author (by hand, informed by
   `scripts/migrate-instrument-yaml.py`'s output and the "NOT migrated"
   section of its report) the full Migration Accelerator instrument,
   including the per-pair adaptive content this script deliberately did not
   auto-convert (§4 below).
2. A side-by-side manual QA pass on `gtm-staging`, same inputs, old
   YAML-driven instrument vs. new schema-driven instrument, shows identical
   branching, scoring, and outcome-tier results, for the base pack and for
   at least the two worked-sample pairs (`hubspot_to_mcn`,
   `hubspot_to_sfmc`) that exercise every adaptive layer.
3. That parity confirmation is recorded in the cutover PR's description,
   per this sub-issue's scope doc §3 Plan Acceptance Criteria.
4. The owner has given explicit go-ahead for the `gtm-prod` deploy that
   follows (CLAUDE.md §5) — the cutover PR itself only needs `gtm-staging`
   sign-off to merge to `main`; the `gtm-prod` promotion is a further,
   separate gate.

## 4. What the cutover PR will still have to solve (not solved by this plan)

The migration script's "NOT migrated" report (§ of its own docstring;
concrete counts for Migration Accelerator: 6 pair files, 3 gates, 6
complexity dimensions, 3 supplement sets) names real schema gaps the new
01-schema model has no construct for yet. **Per the human owner's explicit
decision (recorded here as part of sub-issue 04), these four gaps are an
intentional, owner-resolved descope for the rebuild — not an open or
undecided question.** The new-schema editor (sub-issue 04) deliberately
ships with no authoring UI for any of the four, and no follow-on schema
sub-issue is planned to add one:

- **Per-pair adaptive overrides.** The new schema has one question list per
  `GTM_Instrument_Definition__c`, not one per (source, target) pair.
  Migration Accelerator ships on the new schema with pair-adaptivity
  dropped — a real behavior change from the legacy YAML/CMDT path, owner-
  approved, not a gap awaiting a pair-scoped override construct analogous to
  `GTM_Assessment_Dimension_Override__mdt`.
- **Gates.** `Rules_JSON__c`'s `SHOW`/`HIDE`/`SKIP_TO_SECTION`/
  `MAKE_REQUIRED` actions cannot express a tier-qualifying, score-preserving
  gate, and no mapping is being added. Gate predicates are out of scope for
  the new-schema editor.
- **Estate Complexity (second scored axis).** No home in
  `GTM_Instrument_Outcome_Range__c`, which maps one score to one range, and
  none is being added — a single-axis score/range model is the accepted
  shape going forward.
- **Supplements (layer-4, outside-the-32 questions with their own named
  index) and callouts (capability-gap narrative blocks).** No field on any
  new-schema object, and none is planned — these stay legacy-YAML-only
  content, not ported.

Because this is an owner-resolved descope rather than an unresolved
question, `GtmAssessmentInstrument.cls`/`GtmAssessmentQuestions.cls` staying
on the legacy YAML/CMDT path for Migration Accelerator's full pair-adaptive/
gated/complexity-axis/supplement content is the accepted long-term state for
that offering, not a stopgap awaiting a decision. The cutover PR's job is
rewiring the data source for what the new schema *does* cover (single
question list, per-option points, inline branching, one-axis outcome
mapping); it does not need to re-litigate or solve any of the four items
above.

## 5. Retirement checklist for the cutover PR (once §3's precondition holds)

- [ ] Point `GtmAssessmentInstrument.baseSlots()`/`baseComplexity()` (or
      their §4-informed successors) at `GTM_Instrument_Question_Definition__c`
      instead of `GtmAssessmentQuestions.questionsFor()` /
      `GTM_Assessment_Question__mdt`.
- [ ] Remove `GtmAssessmentInstrument.resolveInternal()`'s
      `GTM_Assessment_Pair__mdt`/`_Dimension_Override__mdt` resolution chain
      — §4's owner-resolved descope means Migration Accelerator ships
      without pair-adaptivity on the new schema, not with a replacement
      construct.
- [ ] Remove `gates()`/`GTM_Assessment_Gate__mdt` reads — §4's owner-resolved
      descope means Migration Accelerator readouts no longer carry tier
      qualifiers on the new schema; this is the accepted outcome, not a
      placeholder pending a mapping decision.
- [ ] Retire `scripts/build-instrument.py` and delete (or explicitly mark
      superseded, per the human owner's call — see scope doc §2) the
      `GTM_Assessment_*__mdt` custom metadata types and their compiled
      records under `force-app/main/default/customMetadata/`.
- [ ] Update `GtmAssessmentInstrumentTest.cls`/`GtmAssessmentQuestionsTest.cls`
      to assert against the new schema (their `@TestVisible` override seams
      — `pairOverride`/`overrideOverride`/`supplementOverride`/`gateOverride`
      /`rowOverride` — will need new-schema equivalents or removal, depending
      on §4's resolution).
- [ ] Decide the fate of the `instrument/migration-accelerator/` YAML
      directory (archive vs. leave in place as historical record — not
      silently delete, per scope doc §2) and record that decision here.
