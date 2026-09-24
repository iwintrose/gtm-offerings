# TASK SCOPE — ISSUE #assessment-instrument-rebuild-02-submission

> Sub-issue 02 of 4 in the `assessment-instrument-rebuild` umbrella (see
> `task-scope-assessment-instrument-rebuild-01-schema.md` for the full
> sequencing note and supersession of `docs/architecture/
> gtm-instrument-editor.md`). **Do not start this sub-issue until 01's
> schema is deployed to `gtm-staging`** — the new `Offering__c` lookup and
> instrument-definition objects referenced here must exist first.

## 1. Requirements Breakdown

- **Target Objective:** Generalize `GTM_Assessment_Request__c` (and its
  controllers `GtmAssessmentRequestController.cls`,
  `GtmAssessmentDraftController.cls`) from a Migration-Accelerator-specific
  submission object into the generic, offering-agnostic submission model
  for the rebuilt instrument system, per the user's explicit requirement
  that every submission tie back to Contact, Account, Opportunity, and
  Offering via real lookups (not text-key matching). Concretely: add an
  `Offering__c` lookup field alongside the existing `Offering_Key__c` text
  field (keep the text field for backward query compatibility during
  transition, per ADR-0009's existing convention); strip out the
  Migration-Accelerator-only fields (`Estate_Complexity_Band__c`,
  `Estate_Complexity_Basis__c`, `Estate_Complexity_Dimensions__c`,
  `Estate_Complexity_Score__c`, `Instrument_Pair__c`,
  `Instrument_Branch_Path__c`) out of the generic path — either by making
  them optional/unused for non-Migration-Accelerator offerings or by
  relocating them to a Migration-Accelerator-specific extension object;
  keep per-question answers as a single JSON blob keyed by the new schema's
  `Question_Key__c` (no child-record-per-answer, to avoid row explosion
  under guest load) matching the existing `Section_Scores__c`/
  `Supplement_Scores__c` hybrid precedent. Preserve two deliberate existing
  guest-safety decisions unchanged: no duplicate-detection on the guest
  submission path (tracked separately as issue #32 — do not "fix" this
  here) and the savepoint/rollback transaction pattern already in
  `GtmAssessmentRequestController`.
- **System Component Impacted:** Apex (`GtmAssessmentRequestController.cls`,
  `GtmAssessmentDraftController.cls`) + Schema (`GTM_Assessment_Request__c`
  field changes) + Permission Sets.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? Verify whether any GUS-invocable Apex
      action reads/writes `GTM_Assessment_Request__c` fields being removed
      or renamed (grep `GtmAssessmentRequestController` and related
      `@InvocableMethod`/`@AuraEnabled` callers before touching field
      names) — if yes, the zero-DML rule in AGENTS.md §1 applies to any
      GUS-surfaced action.
- [ ] Altering Custom Metadata? No — this sub-issue changes a custom
      *object* (`GTM_Assessment_Request__c`), not `GTM_Assessment_*__mdt`
      custom metadata. The YAML/CMDT build path is untouched until
      sub-issue 03.
- [ ] Introducing database fields? Yes — new `Offering__c` lookup on
      `GTM_Assessment_Request__c`. Mapping to permission sets is mandatory:
      `GTM_Guest` needs create/edit access for guest submission,
      `GTM_Content_Manager`/`Admin` need read/CRUD as appropriate,
      `GTM_Offering_User`/`Admin` per the existing rep-ownership rule
      (reps see only their own linked submissions — confirm this still
      holds with the new lookup in place).

## 3. Plan Acceptance Criteria

- **Success Metric:** A guest submission on `gtm-staging` for an offering
  using the new instrument schema creates a `GTM_Assessment_Request__c`
  record with `Contact__c`, `Account__c`, `Opportunity__c` (when
  applicable), and the new `Offering__c` all populated with real lookup
  values (not just text), and per-question answers stored as the JSON blob
  keyed by `Question_Key__c`. The savepoint/rollback and no-dup-check
  behaviors are verified unchanged by re-running existing Apex tests for
  `GtmAssessmentRequestController` after the field changes — no test may
  be deleted to make this pass; if a Migration-Accelerator-specific test
  asserts on a field being relocated, update the assertion to target the
  new location, not remove the coverage.
- **Target Test Target:** `GtmAssessmentRequestControllerTest`,
  `GtmAssessmentDraftControllerTest` (exact class names to be confirmed
  against `force-app/main/default/classes/` at implementation time — grep
  for `@isTest` classes referencing `GtmAssessmentRequestController` if
  the names differ).
