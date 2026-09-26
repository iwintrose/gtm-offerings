# TASK SCOPE — ISSUE #readout-navigation-consolidation-02-server-completeness-gate

**Parent intake:** `docs/agent-artifacts/task-scope-readout-navigation-consolidation.md` —
read that first. This is **Ticket 02 of 3** from that consolidation pass ("the real product
decision, resolved... per the task's own instruction to reason to a clear answer from existing
patterns rather than punt"). Tickets 01 (LWC entry-point fixes) and 03 (docs + `ANSWER_FIELDS`
dedup) are independent, parallel-buildable sub-issues — not this worktree's concern.

## 0. Architect verification note (read before building)

Every claim below was independently re-verified against current `main` by the Architect
(grep/`sed -n`/file reads, not taken on the parent doc's word) before this worktree was
provisioned. **One claim in the parent doc's Ticket 02 section does not hold and is corrected
here — this changes the shape of the completeness check itself, not the REJECT-vs-alternate-
status decision, which stays locked per the parent doc and is NOT re-litigated.** See §1.1.

## 1. Requirements Breakdown

- **Target Objective:** `GtmAssessmentRequestController.submitRequest()` (currently lines
  291–441, confirmed) validates only `name` (line 300: `String.isBlank(cleanName)`) and
  `email` (line 303: `!isValidEmail(cleanEmail)`) before proceeding into
  `recordAssessmentRequest()` (lines 768–965, confirmed by grep), which stamps
  `Submitted_At__c = DateTime.now()` unconditionally at line 937 (confirmed) and inserts
  `GTM_Assessment_Request__c` — no answer-completeness check anywhere in either method.
  **Fix: add a pre-DML completeness gate that REJECTS an incomplete submission**, in the same
  shape as the existing duplicate-link guard (confirmed at lines 346–368: an
  `AuraHandledException` thrown before `Database.setSavepoint()` at line 384 — verified via
  `awk` that the only `Savepoint`/DML in `submitRequest` occurs at/after that line, so both the
  duplicate-link guard and the new completeness gate sit cleanly before any writes).

- **The twelve fields, confirmed 1:1:** `RequestInput.targetPlatform / budgetRange /
  contactCount / monthlySendVolume / painPoints / migrationGoals / keyIntegrations /
  successCriteria / internalTeamSize / executiveSponsorship / decisionMakers / urgencyDriver`
  (`GtmAssessmentRequestController.cls` lines 100–111, confirmed) map 1:1 onto
  `Target_Platform__c … Urgency_Driver__c` assigned in `recordAssessmentRequest` (lines
  869–880, confirmed). All twelve fields already exist on `GTM_Assessment_Request__c` and are
  already FLS-granted in `GTM_Offering_User`/`GTM_Offering_Admin` (confirmed:
  `grep -l Pain_Points__c force-app/main/default/permissionsets/*.permissionset-meta.xml`
  returns both). **No new field, no new query, no new permission-set grant.**

- **Reuse the existing "meaningful answers" definition as a starting point, source of truth
  in both existing LWC read-gates:** `gtmAssessmentDetail.js`'s `hasMeaningfulAnswers` getter
  (lines 187–190, confirmed: `ANSWER_FIELDS.some((field) => !!this._fv(field))`) and
  `gtmReadoutWorkspace.js`'s equivalent (lines 168–169, confirmed: same shape over
  `getFieldValue`). Both gate `isSubmitted` as `Submitted_At__c set AND hasMeaningfulAnswers`
  — the AND-of-both-signals pattern from "Bug fix, round 2" in both files' own comments,
  confirmed present verbatim in both.

### 1.1 Correction to the parent doc's Ticket 02 — the twelve-field check alone is NOT a safe
      pre-DML reject gate; it WOULD reject some genuine, legitimately-completed submissions

The parent doc asserts: *"the client wizard's own `validateStep()` already blocks incomplete
submission through the real UI (every readiness/complexity/routing/contact step must be fully
answered before advancing), so this gap is unreachable through normal use today... this is
defense-in-depth, not a new prospect-facing flow."* This is **half true and half false**, and
the false half matters for where the code goes:

**True:** `validateStep()` (`gtmAssessmentQuestionnaire.js` lines 1197–1216, confirmed) blocks
advancement past the `routing`, `readiness`, `complexity`, and `contact` steps unless fully
answered — confirmed by reading the method directly (each branch pushes to `missing` for any
unanswered slot/field, and `handleNext()` at line 1067 returns early if `!this.validateStep()`).

**False, confirmed by independent trace of what actually feeds the twelve fields:**
- Eleven of the twelve fields (`painPoints, migrationGoals, keyIntegrations, successCriteria,
  budgetRange, contactCount, monthlySendVolume, internalTeamSize, executiveSponsorship,
  decisionMakers, urgencyDriver`) are the `BD_CONTEXT_FIELDS` (lines 156–247, confirmed) — a
  step whose own doc comment (lines 130–154) explicitly states **"THEY ARE NOT INSTRUMENT
  ANSWERS"**. This step's `kind` is `'bdContext'` (confirmed via `get isBdContext()` at line
  598), and `validateStep()`'s if/else chain (routing/readiness/complexity/contact) has **no
  `isBdContext` branch** — confirmed by reading the whole method. Worse: there is a dedicated
  `handleSkipBdContext()` handler (line 880, confirmed) that jumps straight to the `contact`
  step, explicitly skipping validation entirely. **All eleven of these fields are fully
  optional in the real UI.**
- The twelfth field, `targetPlatform`, comes from the `routing` step's `target` dropdown,
  which IS validated (`if (!this.routing.target) missing.push('target')`, line 1201) — but
  the dropdown includes a real, selectable `NOT_DECIDED` option, `'Not decided yet'`
  (confirmed: `const NOT_DECIDED = '__undecided__'` at line 281; `targetOptions` includes
  `{ value: NOT_DECIDED, label: 'Not decided yet' }` at line 909). `buildPayload` (confirmed
  at line 1265) maps this selection to `targetPlatform: ''` — an empty string — even though
  `routing.target` itself is non-blank and passes step validation.

**Net result, confirmed reachable through the standard wizard with zero bypass, zero direct
API call, zero adversarial behavior:** a prospect who (a) picks "Not decided yet" for target
platform and (b) clicks "Skip" (or simply leaves blank and advances through) the BD-context
step, while fully and correctly answering every readiness slot, every complexity question,
and their own contact info — a completely genuine, fully-intentional submission — will have
**all twelve of the proposed `ANSWER_FIELDS`-equivalent properties blank**. A gate that
rejects purely on those twelve fields would reject this submission before any DML, losing the
prospect's real readiness/complexity answers entirely (unlike the *existing* client-only gaps
this ticket is meant to backstop, where a false-negative today just mis-renders a tab — still
recoverable, since the record exists). This is not a hypothetical: both "Not decided yet" and
"Skip" are first-class, prominently offered UI affordances, plausibly common for early-stage
prospects.

**Why this doesn't reopen the locked product decision:** the parent doc's decision — reject
before DML, same shape as the duplicate-link guard, not a different status — is unaffected
and is followed as-is below. What's wrong is narrower: the specific field list borrowed from
the *display-gating* context (where a false negative is low-stakes and recoverable) is not
safe to reuse unmodified for a *write-time, reject-and-discard* gate (where a false positive
on "incomplete" discards real prospect data). The fix is to broaden what counts as
"meaningful," not to change the reject decision.

**Required fix — broaden the server-side check to also treat the mandatory instrument answers
as meaningful, OR'd with the twelve-field check:**

```apex
private static Boolean hasMeaningfulAnswers(RequestInput input) {
    return String.isNotBlank(input.painPoints)
        || String.isNotBlank(input.migrationGoals)
        || String.isNotBlank(input.successCriteria)
        || String.isNotBlank(input.decisionMakers)
        || String.isNotBlank(input.budgetRange)
        || String.isNotBlank(input.urgencyDriver)
        || String.isNotBlank(input.keyIntegrations)
        || String.isNotBlank(input.executiveSponsorship)
        || String.isNotBlank(input.targetPlatform)
        || String.isNotBlank(input.internalTeamSize)
        || String.isNotBlank(input.monthlySendVolume)
        || String.isNotBlank(input.contactCount)
        // Readiness (8 slots) and complexity answers are the ACTUAL scored
        // instrument content and are mandatory in the real wizard
        // (validateStep()'s isReadiness/isComplexity branches, confirmed) --
        // a far more reliable "this is a real submission" signal than the
        // eleven optional BD-context fields above. A submission with a full
        // set of readiness/complexity answers but every BD-context field
        // left blank (a real, legitimate path -- see §1.1) must NOT be
        // rejected.
        || (input.answers != null && !input.answers.isEmpty())
        || (input.complexityAnswers != null && !input.complexityAnswers.isEmpty());
}
```

Confirmed both `answers` and `complexityAnswers` are already `List<AnswerInput>` properties on
`RequestInput` (lines 118, 128, confirmed) — no new property needed. Confirmed readiness slots
are "eight... for every respondent, on every branch path" (steps getter comment, line ~531) —
i.e. `answers` is always fully populated (all 8 keys) by the time a genuine submission reaches
`handleNext()`'s last step, making `!input.answers.isEmpty()` a safe, always-true-for-real-
submissions signal. This keeps the gate's actual purpose (reject a genuinely empty/adversarial
submission) intact while removing the false-positive risk identified above.

**Developer: build the `hasMeaningfulAnswers` helper with this broadened OR from the start —
do not build the twelve-field-only version and patch it later.** Add at least one test
exercising the "full readiness/complexity answers, all twelve flat fields blank" case
alongside the "everything blank" rejection case, so this exact scenario has regression
coverage (see §3, Target Test Target).

## 2. Prospect-facing behavior on rejection

Confirmed: because the wizard's own `validateStep()` blocks the *mandatory* steps
(routing/readiness/complexity/contact) and, with the §1.1 fix, `answers`/`complexityAnswers`
being non-empty is itself sufficient to pass the gate, **the real wizard (`
gtmAssessmentQuestionnaire.js`) cannot reach this rejection through normal use once the
broadened check above is built** — every path through `handleNext()`'s validated steps
guarantees `answers` is non-empty by the last step. This remains a defensive backstop against
a bypass (a future client change, a direct Apex/API call, or non-standard traffic), not an
expected-to-fire prospect flow, same framing as the parent doc — just now actually true.

On the rare/adversarial path where it does fire: throw the same shape of
`AuraHandledException` `submitRequest()` already uses for its other two pre-DML rejections
(`'Please enter your name.'`, `'Please enter a valid work email.'`, and the duplicate-link
message at lines 361–364) — e.g. `'Please answer the assessment questions before
submitting.'` — placed alongside the name/email checks (~after line 305, before the
duplicate-link query at line 346, matching the parent doc's placement). No new response shape:
`RequestResult` is never returned in this path, same as the other two rejections (the
exception itself IS the response). The existing generic error-surfacing in
`gtmAssessmentQuestionnaire.js`'s `submit()`/error handler displays whatever message the
exception carries — confirmed no new UI component or wizard-side handling is required, since
it already has to handle the two existing rejection messages generically.

## 3. Code Dependency Checklist (CLAUDE.md §6 / AGENTS.md §1) — Architect-reviewed, not assumed

- [x] **Modifying GUS Tool Surface?** **NO, confirmed by grep, not assumed.**
      `grep -n "class GtmAssessmentRequestController"` shows
      `public without sharing class GtmAssessmentRequestController {` — no `implements`
      clause. `grep -rln "GtmAgentToolSurface" force-app/main/default/classes/` returns only
      `GtmAgentProxyController.cls`, `GtmAgentToolSurface.cls` (the interface itself),
      `GtmAppAgentSurface.cls`, `GtmAppTool.cls`, `GtmReadoutAgentSurface.cls` —
      `GtmAssessmentRequestController` is not among them. The zero-DML/zero-callout-inside-a-
      tool contract does not apply to this ticket.
- [x] **Altering Custom Metadata?** **NO.** `GTM_Assessment_Config__mdt` is read (`loadConfig`,
      already-existing call), never written. No `GTM_Assessment_*` custom metadata XML and no
      `instrument/<offering-key>/` YAML is touched by this ticket.
- [x] **Introducing database fields?** **NO, confirmed by direct inspection.** All twelve
      fields already exist on `GTM_Assessment_Request__c`
      (`ls force-app/main/default/objects/GTM_Assessment_Request__c/fields/` confirmed all
      twelve `.field-meta.xml` files present) and are already FLS-granted in both
      `GTM_Offering_User` and `GTM_Offering_Admin` (confirmed via grep above). No
      permission-set change required in this ticket.

## 4. Confirmed ripple effect — flag explicitly, not a surprise mid-build

`GtmAssessmentRequestControllerTest.cls`'s shared `sampleInput()` fixture (lines 3–15,
confirmed by direct read) sets `name`, `email`, `company`, `role`, `currentPlatform`,
`environmentSize`, `timeline`, `context`, `prospect`, `industry` — **none of the twelve
`ANSWER_FIELDS`-mapped properties, and no `answers`/`complexityAnswers` either.** Confirmed via
`grep -c "submitRequest(" GtmAssessmentRequestControllerTest.cls` = **69** call sites, and
confirmed via `grep -rl "\.submitRequest("  force-app/main/default/classes/*.cls` that this is
the **only** Apex test file that calls `submitRequest` at all.

**This one shared fixture must be updated** (set at least one flat field, e.g.
`input.painPoints = '...'`, **or** give it a minimal non-empty `answers` list — either
satisfies the broadened §1.1 gate) **or every happy-path test in the file will start failing.**
This is a single, centralized, low-risk fixture edit, not a 69-site rewrite — but it is a
required part of this ticket, not a follow-up.

## 5. Success Metric / Target Test Target

- **Success Metric:** A `submitRequest()` call with valid name/email, all twelve
  `ANSWER_FIELDS`-mapped `RequestInput` properties blank, AND empty/null `answers` and
  `complexityAnswers`, throws an `AuraHandledException` before any DML (no
  Account/Contact/Opportunity/Task/Request row created — assert record counts unchanged,
  mirroring the existing duplicate-submission test's assertion style). A second new test:
  the same call but with all twelve flat fields blank and a non-empty `answers` list (the
  §1.1 scenario) **succeeds** — this is the regression guard for the corrected behavior.
  Every existing test in `GtmAssessmentRequestControllerTest.cls` still passes once
  `sampleInput()` is updated per §4. No change to `classify()`, `Generator.run()`, or any
  tab-gating getter in `gtmAssessmentDetail.js`/`gtmReadoutWorkspace.js` — those stay exactly
  as they are today; this ticket is server-write-side only.
- **Target Test Target:** `GtmAssessmentRequestControllerTest.cls` — add
  `rejectsSubmissionWithNoMeaningfulAnswers()` and
  `acceptsSubmissionWithReadinessAnswersButNoFlatFields()` (or equivalent names); update
  `sampleInput()`. Run via
  `sf apex run test --class-names GtmAssessmentRequestControllerTest --target-org gtm-staging`
  per `AGENTS.md`'s QA step (never `RunLocalTests`).

## 6. Definition of Done

- No new custom object/field/permission-set work (confirmed §3).
- No change to `RequestResult`'s shape or any public Apex method signature other than the new
  private `hasMeaningfulAnswers(RequestInput)` helper and the new guard clause inside
  `submitRequest()`.
- The completeness gate sits before `Database.setSavepoint()` (line 384 today), alongside the
  existing name/email checks — never inside the try/Savepoint block.
- `sampleInput()` updated per §4; all 69 existing `submitRequest()` call sites in
  `GtmAssessmentRequestControllerTest.cls` still pass.
- Both new tests in §5 pass against `gtm-staging` (never `RunLocalTests`).
- No LWC file is touched by this ticket (`gtmAssessmentQuestionnaire.js`,
  `gtmAssessmentDetail.js`, `gtmReadoutWorkspace.js` are all read-only reference material for
  this ticket, confirming reachability — not edit targets). Ticket 03 owns any future
  `ANSWER_FIELDS` dedup; do not preemptively touch those files here.
