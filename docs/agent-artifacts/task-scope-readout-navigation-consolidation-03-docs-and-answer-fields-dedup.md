# TASK SCOPE — ISSUE #readout-navigation-consolidation-03-docs-and-answer-fields-dedup

> Sub-issue 03 of 3 in the `readout-navigation-consolidation` split (see
> `docs/agent-artifacts/task-scope-readout-navigation-consolidation.md`,
> "Ticket 03" section, for the full parent scoping, the 3-way split
> rationale, and the Code Dependency Checklist covering all three
> tickets). No build-order dependency on Ticket 01
> (`readout-navigation-consolidation-01-lwc-entry-points`) or Ticket 02
> (`readout-navigation-consolidation-02-server-completeness-gate`) — all
> three are independently buildable in parallel worktrees per the parent
> doc. Ticket 02 is separately extracting an equivalent "meaningful
> answers" check server-side in Apex (`hasMeaningfulAnswers(RequestInput
> input)` on `GtmAssessmentRequestController`) — that is different
> language, different data shape (`RequestInput` properties vs. wired
> `getRecord` field values), no shared-code mechanism between them in this
> codebase. **Do not unify across languages; this ticket is client-side
> (LWC) only.**

## 1. Requirements Breakdown

- **Target Objective:** Two small, independent fixes bundled into one
  ticket because both are docs/dedup cleanup in the same feature area:

  **(a) Docs fix.** `docs/architecture/gtm-readout-workspace.md`'s
  "Readout-tab submission gating (refinement #5)" section (heading
  confirmed at line 90) has stale prose at line 118: *"`Submitted_At__c`
  is intentionally no longer part of the check (it's still read/wired,
  just unused for gating)."* This is self-contradicted by the same file's
  later "Round 3" section (heading confirmed at line 345), specifically
  item "3 & 4. Readout/Conduit gating — require genuine completion"
  (lines 465-481), which documents the actual, current, correct logic:
  *"The gate (`isSubmitted`) is now the AND of both signals —
  `Submitted_At__c` must be set ... AND at least one instrument answer
  field must be non-blank ... Neither signal alone is sufficient."*
  Independently re-confirmed against current code (not taken on the BA's
  word): `gtmAssessmentDetail.js`'s `isSubmitted` getter (lines 192-193):
  `return !!this._fv(SUBMITTED_AT) && this.hasMeaningfulAnswers;` and
  `gtmReadoutWorkspace.js`'s `isSubmitted` getter (lines 172-173):
  `return !!getFieldValue(this._requestRecord, SUBMITTED_AT) &&
  this.hasMeaningfulAnswers;` — both already implement the AND gate the
  Round 3 section describes. Only the refinement #5 section's own prose
  is out of date. **Fix: edit the stale paragraph at line 118 (and its
  surrounding sentence) to state the AND-gate directly, or replace it
  with a forward reference to the Round 3 section — pick whichever reads
  more naturally in context, but the file must not contain two
  contradictory descriptions of the same gate afterward.** Zero code
  change, zero behavior change.

  **(b) `ANSWER_FIELDS` dedup.** The same 12-field "which fields count as
  a meaningful answer" list (`Pain_Points__c`, `Migration_Goals__c`,
  `Success_Criteria__c`, `Decision_Makers__c`, `Budget_Range__c`,
  `Urgency_Driver__c`, `Key_Integrations__c`, `Executive_Sponsorship__c`,
  `Target_Platform__c`, `Internal_Team_Size__c`, `Monthly_Send_Volume__c`,
  `Contact_Count__c`) is independently declared as `const ANSWER_FIELDS =
  [...]` in both `gtmAssessmentDetail.js` (lines 61-65, built from its own
  `@salesforce/schema/...` imports at lines 29-40) and
  `gtmReadoutWorkspace.js` (lines 30-33/38, same field set, its own
  imports; its own comment at line 28 already acknowledges the
  duplication: "same list c-gtm-assessment-detail's 'Prospect's Answers'
  section renders and gates on"). Independently confirmed a third,
  conceptual duplication in `gtmAssessmentAnswersPreview.js`'s `QUESTIONS`
  array (lines 55-68), which pairs the same 12 fields (via its own
  `@salesforce/schema/...` imports at lines 9-20) with a `key` and a
  prospect-facing `question` string for the "Preview the assessment"
  modal. Confirmed by reading the file directly: it does **not** import
  `ANSWER_FIELDS` from anywhere — it declares its own independent field
  list, exactly as the parent doc flagged needed build-time confirmation
  for. **Fix: extract the field-identity list (and the
  `hasMeaningfulAnswers` gate helper used by the two gate consumers) into
  one shared LWC module, consumed by all three components.**

- **System Component Impacted:** Docs only for (a):
  `docs/architecture/gtm-readout-workspace.md`. LWC only for (b):
  `gtmAssessmentDetail`, `gtmReadoutWorkspace`, `gtmAssessmentAnswersPreview`,
  plus one new shared LWC module. No Apex, no schema/custom-metadata, no
  permission sets in this ticket.

### 1.1 Existing convention for shared LWC utility modules (confirmed, not invented)

This codebase already has exactly one precedent for a plain-JS
(non-visual) shared LWC module to follow, rather than inventing a new
file location/pattern: `force-app/main/default/lwc/gtmNavigate/` — a
folder containing only `gtmNavigate.js` (named exports, e.g. `export
const PAGES_TAB`, `export function engagementLinkRef(...)`), a minimal
`gtmNavigate.js-meta.xml` (`<isExposed>false</isExposed>`, no
`<targets>`), and its own `__tests__/`. It's imported elsewhere as
`import { openAssessment } from 'c/gtmNavigate';` — no `.html`/`.css`,
since it renders nothing.

**Follow this exact pattern** for the new module (matching the parent
doc's suggested name/location): create
`force-app/main/default/lwc/gtmAssessmentAnswerFields/gtmAssessmentAnswerFields.js`
(+ matching `.js-meta.xml` + `__tests__/`), exporting `ANSWER_FIELDS`
(the 12 `@salesforce/schema/...` field references — the module does its
own schema imports) and a `hasMeaningfulAnswers(record, fields =
ANSWER_FIELDS)` helper wrapping `getFieldValue`. Each of the two gate
consumers (`gtmAssessmentDetail.js`, `gtmReadoutWorkspace.js`) keeps
whatever *other*, non-`ANSWER_FIELDS` field imports it separately needs
— e.g. `gtmAssessmentDetail.js` still imports `PAIN_POINTS` etc.
directly for its individual per-field getters (lines 206-223: `get
painPoints()`, `get hasPainPoints()`, etc.) in addition to importing the
shared `ANSWER_FIELDS` array for the gate; only the gate/list
declaration itself moves to the shared module, not every individual
field reference.

- **Note on `.js-meta.xml` `apiVersion`:** `gtmNavigate.js-meta.xml` uses
  `66.0`, which is inconsistent with this project's standard
  `sourceApiVersion` (`62.0` in `sfdx-project.json`, and what
  `gtmAssessmentDetail.js-meta.xml`/`gtmReadoutWorkspace.js-meta.xml`
  both already use, confirmed by direct read). **Match the project
  standard (`62.0`) for the new module, not `gtmNavigate`'s outlier
  value.**
- `gtmAssessmentAnswersPreview.js`'s `QUESTIONS` array needs its
  `field`/`key` pairs to stay associated with each `question` string for
  rendering — the shared module should supply the field-identity list
  (`ANSWER_FIELDS`, in a defined, stable order) that `QUESTIONS` can be
  restructured to map over (e.g. keyed by field API name), rather than
  being useful only to the two gate-only consumers. The requirement is a
  single source of truth for field identity, not one specific object
  shape — confirm the cleanest wiring at implementation time.

## 2. Code Dependency Checklist

- [ ] **Modifying GUS Tool Surface?** NO — independently confirmed, not
      inherited from the parent doc on faith:
      `grep -rl "implements GtmAgentToolSurface" force-app/main/default/classes/`
      returns only `GtmAppAgentSurface.cls`, `GtmReadoutAgentSurface.cls`,
      `GtmAgentProxyController.cls`; a grep for `GtmAgent|GusUtility|GtmAppTool`
      across `gtmAssessmentDetail.js`, `gtmReadoutWorkspace.js`,
      `gtmAssessmentAnswersPreview.js` returned zero matches. No Apex is
      touched by this ticket at all.
- [ ] **Altering Custom Metadata?** NO — this ticket touches no
      `GTM_Assessment_*__mdt` and no `instrument/<offering-key>/` YAML.
      The docs fix is prose-only in an architecture doc; the dedup is a
      pure client-side JS refactor of an already-loaded `getRecord` field
      list, not instrument content.
- [ ] **Introducing database fields?** NO — no new fields, no
      field-level-security changes. The refactor consumes the same 12
      already-FLS-granted fields (`Pain_Points__c` … `Contact_Count__c`)
      the two existing components already read via the same
      `getRecord`/`@salesforce/schema` mechanism; the shared module
      changes only *where* the field list is declared, not which fields
      are queried or how they're secured. No permission-set changes are
      in scope for this ticket (re-confirmed independently here, not
      merely inherited from the parent doc's combined §2).

## 3. Plan Acceptance Criteria

- **Success Metric:**
  - `docs/architecture/gtm-readout-workspace.md` states the `isSubmitted`
    AND-gate consistently in both the "refinement #5" section and the
    "Round 3" section — no remaining sentence anywhere in the file claims
    `Submitted_At__c` is unused for gating.
  - `gtmAssessmentDetail.js`, `gtmReadoutWorkspace.js`, and
    `gtmAssessmentAnswersPreview.js` all import the field-identity list
    from one shared module (`c/gtmAssessmentAnswerFields` or equivalent)
    instead of each declaring/duplicating it independently. Behavior is
    unchanged: same 12 fields, same AND-gate semantics, same rendered
    "Prospect's Answers" / Readout-tab / preview-modal content as before
    the refactor — this is a pure refactor, not a behavior change.
  - Does **not** touch the Apex-side gate being built independently in
    Ticket 02 — different runtime, different data shape, no shared-code
    mechanism between them in this codebase. Do not attempt to unify
    across languages.
- **Target Test Target:**
  `force-app/main/default/lwc/gtmAssessmentDetail/__tests__/gtmAssessmentDetail.test.js`,
  `force-app/main/default/lwc/gtmReadoutWorkspace/__tests__/gtmReadoutWorkspace.test.js`
  (existing `isSubmitted`/"Prospect's Answers" gating assertions must
  still pass unchanged after the extraction), and
  `force-app/main/default/lwc/gtmAssessmentAnswersPreview/__tests__/gtmAssessmentAnswersPreview.test.js`,
  plus new `__tests__/` coverage for the shared module itself. Run via
  `npm run test`.

## 4. Definition of Done

- No new custom object/field/permission-set work (confirmed in §2).
- No change to any Apex class, method signature, or Ticket 02's Apex-side
  gate.
- Pure refactor: same 12 fields, same AND-gate logic, same rendered
  content in all three consuming components before and after.
- `npm run test` passes for all four touched/new LWC bundles
  (`gtmAssessmentDetail`, `gtmReadoutWorkspace`,
  `gtmAssessmentAnswersPreview`, the new shared module).
