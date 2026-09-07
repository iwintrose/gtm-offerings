# Fix list — per-offering instrument, round 1 (ADR-0007)

**Author:** Architect (session `session_018UJzwgTCCMdESELzYMeWAZ`)
**Date:** 2026-09-07
**Input:** `docs/agent-artifacts/per-offering-instrument-qa-findings-round-1.md`
(commit `9df398a`), independently spot-checked against the working tree
before this list was written.

## Verdict on QA's findings

All three blocking findings are confirmed real, at the exact locations QA
cites, and I agree with QA's severity read (Medium/blocking, correctness-
of-claim and residual-leak — not overreach, not cosmetic). This is not a
rubber stamp; each was re-read against the current `.cls` files below.

- **Finding 1** (`Source__c` false for real second offerings) — confirmed.
  `GtmAssessmentRequestController.cls:512-531` (`sourceLabelFor`) only
  queries `GTM_Offering__mdt`; it has no equivalent to the two-stage
  fallback `GtmPageContentController.getOfferings()` runs at lines 241-286
  (page-only discovery via `GTM_Page_Section__c`, then a display-name
  upgrade via `GTM_Page_Content__c` `offerings-listing`/`name`). The doc
  comment at lines 495-511 asserts "a second offering gets its own name
  instead of a lie" without qualification — that's the false claim.
- **Finding 2** (`frameMaxTotal` leaks 32) — confirmed exactly as reported.
  `GtmAssessmentScoring.cls:800-804`:
  ```apex
  private static Integer frameMaxTotal(List<String> dimensionKeys, ResolvedFrame frame) {
      return frame.fromRecord
          ? dimensionKeys.size() * frame.maxAnswer
          : MAX_TOTAL_SCORE;
  }
  ```
  Gated on `fromRecord` only. `compiledApplies` exists on the same
  `ResolvedFrame` struct (line 424) and is exactly the flag
  `untrustedPackFallback()` (line 761, one method away) already uses for
  the equivalent decision. `Instrument_Max_Score__c` is not required
  (`force-app/main/default/objects/GTM_Assessment_Request__c/fields/Instrument_Max_Score__c.field-meta.xml:6`),
  so returning `null` here is a safe field value, not a schema change.
- **Finding 3** (`Questionnaire` maxima hardcoded) — confirmed exactly as
  reported. `GtmAssessmentQuestions.cls:84-85`, inside the no-arg
  `Questionnaire()` constructor, sets `readinessMaxScore =
  GtmAssessmentScoring.MAX_TOTAL_SCORE` and `complexityMaxScore =
  GtmEstateComplexity.MAX_TOTAL_SCORE` unconditionally. `getQuestionnaire()`
  (line 97) already receives `offeringKey` and threads it into
  `questionsFor()` — it just never reaches the two maxima. Confirmed this
  is a guest-reachable, `cacheable=true` endpoint (line 96) and confirmed
  (via `Grep`) `new Questionnaire()` has exactly one call site
  (`GtmAssessmentQuestions.cls:98`), so its constructor is free to change
  without touching any test or other caller.

QA's non-blocking findings (4–6) are correctly scoped as non-blocking and
are **not** in this round's fix list — Dev should leave them for a
follow-up unless a fix falls out for free while touching the same lines
(e.g. Finding 4's trim-before-bind, if Dev is already editing
`GtmAssessmentQuestions.rows()` for Finding 3).

---

## Fix 1 — `sourceLabelFor()` needs `getOfferings()`'s fallback chain

**Decision: mirror `getOfferings()`'s existing pattern.** This is the
simplest option and the codebase already has the precedent twice
(`getOfferings()` and `getHomeSummary()`) — a third divergent
implementation would be the thing worth blocking on, not adding a fourth
lookup strategy from scratch.

Change `GtmAssessmentRequestController.sourceLabelFor(offeringKey)` to a
three-tier resolution, in order:

1. **Unchanged.** `GTM_Offering__mdt.Label__c` lookup (existing code,
   lines 516-525). Keeps Migration Accelerator's literal-for-literal
   behavior and anything else that already has a deployed CMDT row.
2. **New.** If that misses, query `GTM_Page_Content__c` the same way
   `getOfferings()` does (`Template_Type__c = 'offerings-listing'`,
   `Field_Key__c = 'name'`, `Offering_Key__c = :offeringKey`,
   `Active__c = true`, `LIMIT 1`). If `Text_Value__c` is non-blank, return
   it — this is what makes `my-test-offering` and
   `data-cloud-accelorator` (both of which have page content but no CMDT
   row) show their own name today.
3. **New.** If that also misses, check whether the offering is real at
   all via `GTM_Page_Section__c` (`Offering_Key__c = :offeringKey`,
   `Active__c = true`, `LIMIT 1`, same table `getOfferings()`'s page-only
   branch groups on). If a row exists, return the raw `offeringKey`
   (matches `getOfferings()`'s own `label = key` fallback-of-last-resort
   convention at line 260) rather than `LEGACY_SOURCE_LABEL` — a real
   offering with no name authored anywhere yet should show its key, not
   someone else's name.
4. **Unchanged.** Only when the key is blank, or resolves to nothing in
   any of the three tables, fall back to `LEGACY_SOURCE_LABEL`. This is
   the genuinely-unknown-offering case (typo, synthetic test key) and
   `Migration Accelerator` staying the terminal fallback there is fine —
   QA did not flag that case, and there is no better default available.

Wrap tiers 2 and 3 in the same `try/catch` the existing code already uses
(lines 516-529) — a missing/unreadable table must not cost the submission
its label.

**Also fix the doc comment** (lines 495-511): replace "a second offering
gets its own name instead of a lie" with language that names the three
tiers and states plainly that a genuinely unresolvable key still gets
`LEGACY_SOURCE_LABEL`. QA's blocking objection is as much about the false
claim as the behavior — closing the behavior gap without correcting the
comment would leave the same class of finding for round 2.

## Fix 2 — `frameMaxTotal()` must gate on `compiledApplies`, matching `untrustedPackFallback()`

One-line shape change, `GtmAssessmentScoring.cls:800-804`:

```apex
private static Integer frameMaxTotal(List<String> dimensionKeys, ResolvedFrame frame) {
    if (frame.fromRecord) {
        return dimensionKeys.size() * frame.maxAnswer;
    }
    return frame.compiledApplies ? MAX_TOTAL_SCORE : null;
}
```

Verified this does not disturb the two existing call sites:

- `pointsAreTrustworthy()` (line 835): `pack.maxTotal() == frameMaxTotal(...)`
  — for an unresolved offering `frameMaxTotal` now returns `null`;
  `pack.maxTotal()` for an empty/untrusted pack is an `Integer`, and
  `Integer == null` evaluates to `false` in Apex without throwing, so this
  falls through to "untrustworthy" exactly as today.
- `maxTotalFor()` (line 848-855): already the public entry point
  `GtmAssessmentRequestController` calls to persist
  `Instrument_Max_Score__c`. No signature change needed — the null now
  propagates correctly through `pointsAreTrustworthy` → `frameMaxTotal`.

No test currently pins `frameMaxTotal`'s unresolved-offering value at 32
(the QA repro used live anonymous Apex, not a unit test) — Dev should add
one asserting `maxTotalFor('<nonexistent-key>', null) == null` and
`maxTotalFor('migration-accelerator', null) == 32` (unchanged) alongside
whatever regression test covers Fix 3.

## Fix 3 — `Questionnaire`'s maxima must be derived per offering, not compiled constants

Two changes:

1. **`GtmAssessmentScoring`** already has what's needed:
   `maxTotalFor(offeringKey, pack)` with `pack = null` already resolves
   correctly through `untrustedPackFallback()` + the fixed `frameMaxTotal()`
   from Fix 2 (empty dimension list when `!compiledApplies`, `MAX_TOTAL_SCORE`
   when `compiledApplies`, frame-derived when `fromRecord`). **No new
   method needed on this class** — reuse `maxTotalFor(offeringKey, null)`.
2. **`GtmEstateComplexity` has no equivalent public method** — `score()`
   computes the band internally but nothing exposes the *maximum* for a
   caller with no pack. Add one, same shape as `GtmAssessmentScoring`'s,
   reusing the existing private `frameFor()`/`acceptedDimensions()`:
   ```apex
   public static Integer maxTotalFor(String offeringKey) {
       ResolvedFrame frame = frameFor(offeringKey);
       List<String> dims = acceptedDimensions(null, frame);
       return frame.fromRecord
           ? dims.size() * frame.maxAnswer
           : (frame.compiledApplies ? MAX_TOTAL_SCORE : null);
   }
   ```
3. In `GtmAssessmentQuestions.getQuestionnaire(offeringKey)`
   (`GtmAssessmentQuestions.cls:97-106`), after constructing `out`, set:
   ```apex
   out.readinessMaxScore  = GtmAssessmentScoring.maxTotalFor(offeringKey, null);
   out.complexityMaxScore = GtmEstateComplexity.maxTotalFor(offeringKey);
   ```
   Leave the no-arg `Questionnaire()` constructor's fields as a documented
   default (or drop the constructor-time assignment entirely and let them
   default to `null`) — the single call site (`getQuestionnaire`, line 98)
   sets the real value immediately after construction either way, so no
   behavior depends on the constructor's own default.

This closes the guest-reachable leak without touching `questionsFor()`,
`allowlistFor()`, or the SOQL Phase 5 already threaded `offeringKey`
through correctly (QA confirmed that part works).

---

## Testing directive for Dev's re-verification pass

**Both, not either.** Continue testing a synthetic/nonexistent offering
key (it is what proves the core "unrecognized offering scores nothing"
guarantee, and QA's own extension of that proof — hostile band payloads,
null/empty packs, all-eight-MA-keys — should stay in the regression
suite), **and** add `my-test-offering` and `data-cloud-accelorator` as
first-class cases in every re-verification step, specifically because:

- They are the only way to exercise the `GTM_Page_Content__c` /
  `GTM_Page_Section__c` fallback tiers Fix 1 adds — a synthetic key that
  has never existed anywhere hits tier 4 (`LEGACY_SOURCE_LABEL`) and would
  make Fix 1 look done when it is not.
- They are real, already-present, selectable offerings — no fixture CMDT
  needs to be deployed to production to use them (same constraint Dev
  correctly respected last round).
- This is literally what QA's Finding 6 (process) says was missing: a
  synthetic key never reaches `getOfferings()`, `sourceLabelFor()`, or the
  Instrument Editor's combobox, so it structurally cannot catch this class
  of bug again.

Concretely, Dev's re-verification must include, for **both**
`my-test-offering` and `data-cloud-accelorator`:

- `sourceLabelFor` / a real submitted `GTM_Assessment_Request__c` row →
  `Source__c` is the offering's own page-content name (or its raw key if
  no name is authored), never `'Migration Accelerator'`.
- `GtmAssessmentScoring.maxTotalFor(key, null)` and
  `GtmEstateComplexity.maxTotalFor(key)` → both `null` (neither offering
  has a `GTM_Assessment_Frame__mdt` row today).
- `getQuestionnaire(key)` → `readinessMaxScore` and `complexityMaxScore`
  both `null`, not `32`/`18`.
- Re-run Check 6's Instrument Editor Apex-substitute table (QA's report,
  lines 462-488) against both keys to confirm `getFrame`'s band ladder no
  longer shows Migration Accelerator's edges next to a 0 slot count — or,
  if that's out of this round's scope, confirm it explicitly and leave it
  named rather than silently unaddressed.

If a real browser session against `GTM_Instrument_Author` is available
this round, use it — QA flagged its absence as a gap, not a blocker, but
closing it removes the last "Apex-substitute" caveat in the verdict.
