# QA round 1 — per-offering assessment instrument (ADR-0007, commits `f9e48b6`..`b89f7df`)

**Reviewer:** QA agent (session `session_018UJzwgTCCMdESELzYMeWAZ`)
**Date:** 2026-09-07
**Scope:** the seven commits after `b029be4` on
`claude/gtm-offerings-ma-deploy-vtf5vl` implementing ADR-0007 phases 0–6,
re-verified independently against live `gtm-dev` (org `00DgK00000XZieHUAT`,
treated as production per CLAUDE.md §1).
**Verdict: NOT APPROVED.** The central isolation guarantee holds and is
reproducible — I re-derived it from scratch and could not break it. But
three residual Migration-Accelerator leaks survive in the same code paths
the change claims to have de-singletonised, one of them contradicting a
claim written into the Dev's own Apex doc comment, and all three are now
*live* rather than hypothetical because **two real non-Migration-Accelerator
offerings already exist in `gtm-dev`** — a fact the Dev's report does not
mention and which changes the reachability of every one of them.

Nothing found here is a data-loss or data-corruption defect. No existing
production row was harmed. The blockers are correctness-of-claim and
residual-leak issues, sized below.

---

## Method

Everything below was run by me, in this session, against live `gtm-dev`.
Nothing was taken from the Dev's report on faith.

- **The classes I tested are the classes in this branch.** Retrieved
  `GtmAssessmentScoring`, `GtmAssessmentFrames`, `GtmEstateComplexity`,
  `GtmAssessmentInstrument`, `GtmAssessmentRequestController`,
  `GtmAssessmentQuestions`, `GtmReadoutModel`, `GtmReadoutController` from
  the org and diffed each against the working tree: **all eight byte-identical**
  (modulo a trailing newline the platform strips). So the anonymous-Apex
  results below exercise exactly this branch's deployed code, not a stale
  org copy.
- Six anonymous-Apex scripts against the real deployed classes (no mocks,
  no test context), plus direct SOQL, plus a `PermissionSet` metadata
  retrieve.
- **No browser.** Plan §QA-3 asks for a real browser session on
  `GTM_Instrument_Author`. I do not have one and did **not** verify any
  rendering. Check 6 below is the Apex-entry-point substitute the task
  authorised, and is labelled as such.

---

## What checks out (verified independently, evidence inline)

### ✅ 1. Apex suite — reproduced

`sf apex run test --target-org gtm-dev --test-level RunLocalTests --wait 60`,
run by me, test run `707gK00000rdkjd`:

```
Outcome     Passed
Tests Ran   559
Pass Rate   100%
Fail Rate   0%
```

Dev's claim of 559/559 confirmed exactly.

### ✅ 2. Isolation proof — reproduced from first principles, and extended

Synthetic key of my own choosing (`qa-round1-no-such-offering`); no fixture
CMDT deployed, matching the Dev's approach.

**Migration Accelerator, unchanged:**

```
A1 MA slots = 8
A2 MA slot keys = (estate_scale, source_access, orchestration_portability,
   content_portability, data_model_readiness, integration_containment,
   consent_portability, decision_readiness)
A3 MA complexity dims = 6
A4 MA frame slotCount=8 min=1 max=4 minTotal=8 maxTotal=32
A5 MA bands = [Discovery First 8-14][Prep Required 15-20]
              [Accelerator-Ready 21-26][Fast-Track 27-32]
B1 MA all-4 total=32 maxTotal=32 tier=Fast-Track hasAnswers=true dims=8
B2 tierFor(MA): 8=Discovery First 14=Discovery First 15=Prep Required
   20=Prep Required 21=Accelerator-Ready 26=Accelerator-Ready
   27=Fast-Track 32=Fast-Track
B3 MA access-gate total=29 tier=Discovery First capped=true
B4 MA annotations = [{"code":"high_rebuild_ratio", ...}]
C1 MA complexity total=18 hasAnswers=true band=Heavy
C2 MA bandFor 9=Light 10=Moderate 13=Moderate 14=Heavy
G5 MA pairs base/hubspot_to_sfmc/eloqua_to_sfmc/sfmc_to_mcn/any_to_mcn/
   hubspot_to_mcn — all 8 slots, version 2026.09.1
```

Every band edge, the access gate, the `high_rebuild_ratio` annotation and
all six pair resolutions are intact.

**Unknown offering — the bug class the Dev claims to have fixed:**

```
D1 GHOST slots=0 complexity=0 supplements=0 gates=0
D2 GHOST score total=null maxTotal=32 tier=null hasAnswers=false dims=0
D3 GHOST null-pack total=null maxTotal=32 tier=null hasAnswers=false dims=0
D4 GHOST complexity total=null hasAnswers=false band=null dimScores=null
D6 GHOST basePack slots=0     D7 GHOST resolveByPairKey('base') slots=0
```

The `compiledApplies` fix is real: an unknown offering handed all eight of
MA's dimension keys at value 4 scores **nothing**, with a null pack and with
an empty pack. I could not make it borrow MA's allowlist. (`maxTotal=32` is
the leak in Finding 2 below — the *score* is correctly null.)

**Angles the Dev's proof did not cover, which I tried:**

- *Malformed `Bands_JSON__c`.* `GtmAssessmentFrames.parseBands` is public,
  so I drove it directly with nine hostile payloads. Every one returned
  `null` (→ fall back to compiled bands), none threw: `[]`, `not json`,
  a bare object, a **gap** (`8-14` then `16-20`), an **overlap** (`8-14`
  then `12-20`), a **descending** band (`lowest 15 > highest 10`), a blank
  `tier`, a null edge, a fractional `lowest` (`8.5`). A well-formed
  2-band set parsed correctly and `tierFor` banded 0/3/6/7/99/null
  correctly (below-floor → lowest band, above-ceiling → top band,
  null → null).
- *A frame record with `Complexity_*` set but base fields blank.* Not
  directly executable: `GtmAssessmentFrames.rowOverride` is
  `@TestVisible private`, so it cannot be injected from anonymous Apex,
  and I will not deploy a `GTM_Assessment_Frame__mdt` record into
  production to test it. I read `frameFor()` instead: it composes
  per-field (`minValue != null && maxValue != null && minValue >= 1 &&
  maxValue > minValue` gates the scale; `parseBands != null` gates the
  bands; either sets `fromRecord = true`). **Noted, not blocking:** bands
  alone setting `fromRecord = true` also switches off the
  "exactly 8 slots or fall back" rule while the offering is still using
  Migration Accelerator's 1–4 *scale*. Defensible, but the coupling is not
  documented.
- *Case and whitespace variants* — see Finding 4, which this turned up.

### ✅ 3a. Guest permission-set grant is really deployed

Not read from source — retrieved from the org
(`sf project retrieve start --metadata "PermissionSet:GTM_Assessment_Guest"`).
The live permission set grants exactly nine CMDT types, including:

```
GTM_Assessment_Config__mdt, GTM_Assessment_Dimension_Override__mdt,
GTM_Assessment_Frame__mdt,  GTM_Assessment_Gate__mdt,
GTM_Assessment_Pair__mdt,   GTM_Assessment_Question__mdt,
GTM_Assessment_Supplement__mdt, GTM_Migration_Pair__mdt,
GTM_Migration_Platform__mdt
```

**Necessary:** traced the guest call path in source —
`GtmAssessmentRequestController.submitRequest` (`@AuraEnabled`, and
`GtmAssessmentRequestController` is in the guest permission set's
`classAccesses`) → `recordAssessmentRequest` → `GtmAssessmentScoring.score(
offeringKey, …)` → `ResolvedFrame frameFor()` → `GtmAssessmentFrames.frameFor()`
→ `SELECT … FROM GTM_Assessment_Frame__mdt`. Same for
`GtmEstateComplexity.score`. The plan's prediction that the type is "read
only from `with sharing` internal Apex" is wrong and the Dev was right to
override it.
**Sufficient:** the grant is type-level; this repo has never carried CMDT
`fieldPermissions` anywhere, and `GtmAssessmentFrames` needs no separate
`classAccesses` entry (Apex class access gates the `@AuraEnabled` entry
point only, which is already granted).

### ✅ 4. Backfill — verified directly

```
SELECT COUNT() FROM GTM_Assessment_Request__c WHERE Offering_Key__c = null  →  0
SELECT COUNT() FROM GTM_Assessment_Request__c                               →  13
```

All 13 carry `Offering_Key__c = 'migration-accelerator'`. The Dev's claim
that the four accounts in `docs/backlog.md` D10 are not in this org is
correct — the real rows are Northwind Retail ×6, Northwind Retail Group,
Commercial Metals Company ×2, the three `(Demo)` accounts, and two rows
whose `Company__c` is the literal `<script>alert(1)</script>` XSS probe
(pre-existing; untouched; `LastModifiedDate` changed by the backfill,
`Company__c` value intact).

**Data-preservation, cross-checked three ways** (there is no history
tracking on this object — `GTM_Assessment_Request__History` does not exist
— so a literal before/after diff is not reproducible after the fact, and I
say so rather than repeating the Dev's assertion):

1. `scripts/data/backfill-assessment-offering-key.apex` selects `Id` only
   and assigns one field. It cannot carry another value.
2. There is **no Apex trigger and no active record-triggered Flow** on
   `GTM_Assessment_Request__c` (only `GtmReadoutApprovalSync.trigger` exists
   in the repo, on a different object; `FlowDefinitionView` shows no active
   flow bound to this object). So the update could not have recomputed
   anything as a side effect.
3. Every stored score/tier and complexity/band pair is still internally
   consistent with the **unchanged** MA ladder: 18→Prep Required,
   24/26→Accelerator-Ready, 16→Prep Required, 32→Fast-Track,
   15→Heavy, 12→Moderate. Nothing was rescored.

I also re-rendered every scored row through the real display path
(`GtmReadoutModel.adaptiveReadout` + `buildJson`): **all 12 render, none
null, none throwing**, each resolving `resolveByPairKey('migration-accelerator',
<stored pair>)` — including `base`, `eloqua_to_sfmc` and the legacy rows
with a null `Instrument_Pair__c`.

### ✅ 7. The YAML `git mv` really is path-segment-only

Not trusted from the commit message. Mechanically verified: extracted the
rename-aware diff `b029be4..5dad779 -- migration-accelerator/instrument`,
took the 23 removed and 23 added lines in order, and asserted that each
added line, with `migration-accelerator/instrument/migration-accelerator/`
normalised back to `migration-accelerator/instrument/`, is **byte-identical**
to its removed counterpart.

```
minus lines: 23   plus lines: 23   mismatches: 0
name: lines in diff: []
```

Zero prose changed, and **no `name:` field was touched** — the constraint
ADR-0007 §2 says would break every already-submitted assessment's ability
to re-render. Distribution: gates 2, hubspot_to_mcn 6, hubspot_to_sfmc 8,
hubspot_context 3, sfmc_classic_readiness 4 = 23, matching the claim.

On the "exactly 55 new `Offering_Key__c` blocks": the generated CMDT diff
carries **69**, not 55 — but the extra 14 are the hand-authored
`GTM_Assessment_Question` rows from Phase 2.1, which the Dev pulled forward
into this same commit and disclosed. 55 generated (34 Dimension_Override +
12 Supplement + 6 Pair + 3 Gate) + 14 Question = 69. The claim is accurate
once read against what it says ("the *regenerated* diff"). The only other
changed lines in `customMetadata` are 8 rationale strings whose sole
difference is the same inserted path segment.

### ✅ 8. `docs/backlog.md` D11 pointer

Present, and accurate. It correctly states that `getPack`, `score`,
`GtmEstateComplexity.score` and `getQuestionnaire` now all require an
`offeringKey`, that an unresolvable offering scores **nothing** rather than
falling back, and that `resolveConfigContext` → `resolveOfferingKey` already
supplies the key a D11 fix will need. I verified each of those four
statements against the code; all four are true.

### ✅ 9. Static checks — reproduced, no regression

```
$ python3 scripts/build-instrument.py --check
Instrument up to date: 55 records across 1 offering(s) (migration-accelerator),
all 14 rules hold.                                                    (exit 0)

$ python3 scripts/check-references.py
6 deploy-blocking, 94 needing a manual step                           (exit 0)
```

Identical to the claimed baseline. The new cross-offering filename-collision
guard is real (`scripts/build-instrument.py:1106-1120`, `emit()` refuses a
`DeveloperName` already emitted by another offering), and the deferred
frame constants carry the promised pointer comment
(`scripts/build-instrument.py:118-140`), which names the change, where the
per-offering values would come from, and why it was left.

**Org-side CMDT counts** match ADR-0007 §4 exactly, all offering-tagged:

```
Question 14, Pair 6, DimOverride 34, Gate 3, Supplement 12
   — all Offering_Key__c = 'migration-accelerator', zero blank on any type
Config: 1 row (Default) with Offering_Key__c = null  ← the intended fallback
GTM_Assessment_Frame__mdt: 0 rows                    ← the intended absence
```

---

## Findings

### 🔴 Finding 1 (Medium) — the `Source__c` claim is false for the offerings that actually exist

The Dev's report says the new `sourceLabelFor()` means "a second offering
gets its own name instead of a lie," and
`GtmAssessmentRequestController.cls:505-510` states the same in a doc
comment. **That is not true in `gtm-dev` today.**

`GtmPageContentController.getOfferings()` — the exact call the Instrument
Editor and Content Manager use to populate their offering pickers — returns
**four** entries live:

```
G1 getOfferings = [ {gtm, "Framework (all offerings)"},
                    {migration-accelerator, "Migration Accelerator"},
                    {my-test-offering, "My Test Offering"},
                    {data-cloud-accelorator, "Data Cloud Accelerator"} ]
```

But `GTM_Offering__mdt` holds exactly **one** row:

```
DeveloperName,Offering_Key__c,Label__c
Migration_Accelerator,migration-accelerator,Migration Accelerator
```

`getOfferings()` has an explicit fallback that discovers *page-only*
offerings from `GTM_Page_Section__c` when no CMDT row exists yet
(`GtmPageContentController.cls`, "An offering that has pages but no metadata
row yet is a real offering"). **`sourceLabelFor()` has no equivalent
fallback.** Verified live:

```
K1 [my-test-offering]        Source__c = Migration Accelerator (FALLBACK — no mdt row)
K1 [data-cloud-accelorator]  Source__c = Migration Accelerator (FALLBACK — no mdt row)
```

So a real assessment submitted against either of the two second offerings
that exist right now is stamped `Source__c = 'Migration Accelerator'` — the
exact mislabelling the judgment call was made to prevent, on the exact field
the doc comment says "a rep filters a list view by, so a wrong value there
is not cosmetic, it hides work."

The narrower claim — *no pre-existing row's value changed* — **is** true and
I verified it: `GTM_Offering__mdt.Label__c` for `migration-accelerator` is
the literal string `Migration Accelerator`, byte-identical to
`LEGACY_SOURCE_LABEL`, so `sourceLabelFor('migration-accelerator')`
returns exactly what the old hardcoded constant returned. All 13 rows'
current `Source__c` values are consistent with that.

**Why this blocks:** not the behaviour (which is a benign fallback) but the
claim. A reviewer reading that comment will believe the second-offering case
is handled. It is not, and the fix is small: mirror `getOfferings()`'s
page-only fallback, or say plainly in the comment that an offering without a
`GTM_Offering__mdt` row still gets the legacy literal.

### 🔴 Finding 2 (Medium) — a residual MA denominator leak: `maxTotal` is 32 for every offering

`GtmAssessmentScoring.frameMaxTotal()` (line 800):

```apex
private static Integer frameMaxTotal(List<String> dimensionKeys, ResolvedFrame frame) {
    return frame.fromRecord
        ? dimensionKeys.size() * frame.maxAnswer
        : MAX_TOTAL_SCORE;                        // ← 32, Migration Accelerator's
}
```

It is gated on `fromRecord` **only** — never on `compiledApplies`. This is
precisely the asymmetry `untrustedPackFallback()` was fixed to avoid one
method away. Verified live:

```
D2 GHOST score total=null maxTotal=32 tier=null hasAnswers=false dims=0
K1 [my-test-offering]       SCORE total=null max=32 tier=null dims=0
K1 [data-cloud-accelorator] SCORE total=null max=32 tier=null dims=0
```

`GtmAssessmentRequestController.cls:682` persists this value unconditionally
(`Instrument_Max_Score__c = scored.maxTotal`). So a real submission against a
second offering writes **"scored out of 32"** — Migration Accelerator's
denominator — onto a row whose score is correctly null. It is a milder form
of the same bug the Dev caught (the numerator is safe, the denominator is
not), and it is exactly the "looks most like a correct answer" failure mode
`resolvedDimensions()`'s own doc comment warns about.

Same one-line shape as the accepted fix:
`frame.fromRecord ? … : (frame.compiledApplies ? MAX_TOTAL_SCORE : null)`
(or `dimensionKeys.size() * frame.maxAnswer`, which is 0 for an empty list).

### 🔴 Finding 3 (Medium) — `getQuestionnaire`'s maxima are still hardcoded to MA, on the guest endpoint

`GtmAssessmentQuestions.Questionnaire`'s constructor (lines 81-86):

```apex
this.readinessMaxScore  = GtmAssessmentScoring.MAX_TOTAL_SCORE;   // 32
this.complexityMaxScore = GtmEstateComplexity.MAX_TOTAL_SCORE;    // 18
```

Phase 5 threaded `offeringKey` into `getQuestionnaire()` and into the SOQL
underneath it — correctly, and I verified the content filter works — but the
maxima it returns alongside were left global. Verified live:

```
G4 [migration-accelerator]      getQuestionnaire = 8/6  maxima=32/18
G4 [qa-round1-no-such-offering] getQuestionnaire = 0/0  maxima=32/18
K1 [my-test-offering]           qn=0/0                  qnMaxima=32/18
K1 [data-cloud-accelorator]     qn=0/0                  qnMaxima=32/18
```

The class's own comment says these exist "so the client prints '18 out of
32' from the server." Zero questions and a server-supplied denominator of 32
is the same borrowed-denominator problem as Finding 2, on a **guest-reachable,
`cacheable=true`** endpoint. This is not in the Dev's declared deferral list,
which named only `GtmReadoutModel` / `GtmReadoutController` /
`GtmReadoutAgentContext` — and unlike those, this one is on the *live
submission* stack, not the readout display stack.

If deferring is the right call, it needs the same explicit, greppable
comment the readout overloads got. Right now it is silent.

### 🟡 Finding 4 (Low) — cache key and SOQL bind key disagree; a padded offering key silently yields a wordless instrument

`GtmAssessmentQuestions.rows()` (line 245) and `GtmAssessmentInstrument`'s
five `*Rows()` helpers (lines 1340-1420) all compute their cache key as
`offeringKey.trim().toLowerCase()` but bind the **raw, untrimmed**
`:offeringKey` into the SOQL. Case is harmless (SOQL `=` on Text is
case-insensitive — verified, `MIGRATION-ACCELERATOR` → 8 slots). Leading
whitespace is not. Verified live, one transaction:

```
N3 questions padded-first ('  migration-accelerator  ') : 0
N4 questions clean-after  ('migration-accelerator')      : 0   ← poisoned
```

(A clean call in a fresh transaction returns 8 — `G4` above — so `N4 = 0` is
the empty result cached under the *trimmed* key, served to the correct key
for the rest of the transaction.)

The visible consequence:

```
O1 padded getPack pairKey=base slots=8
O2 estate_scale=>label[null] q[NULL] opts=0,  source_access=>label[null] q[NULL] opts=0,
   … all eight slots, keyed, with no label, no question text and zero options
```

An eight-slot questionnaire with no words. `baseSlots()`'s catch-and-carry-on
turns a missed row lookup into a keyed-but-empty instrument, which is right
when metadata genuinely is not deployed and wrong here, where it is.

Reachability is low — `resolveOfferingKey()` trims, and the LWCs pass keys
that come from CMDT — so this is not urgent. But it is new code introduced
by this change, and the fix is to bind the same normalised value the cache
is keyed by.

### 🟡 Finding 5 (Low, environment) — `npm test` as documented does not reproduce "163/163"

The documented command (CLAUDE.md §9) reports, in this working copy:

```
Test Suites: 2 failed, 2 skipped, 14 passed, 16 of 18 total
Tests:       10 failed, 2 skipped, 310 passed, 322 total
```

Every failure is inside `.claude/worktrees/agent-a26c5231ddadc2b1d/` — a
stale, gitignored worktree pinned at an unrelated older commit (`35d686a`)
whose old `gtmInstrumentAuthor`/`gtmAssessmentQuestionnaire` tests resolve
`c/…` modules against the **main** tree's new components and so never render
(`expect(q(el,'.ia-slot').length).toBe(8)` → received `0`, because the new
component correctly gates rendering on `selectedOffering`). Excluding it:

```
$ npx jest --testPathIgnorePatterns "/node_modules/" "/.claude/"
Test Suites: 1 skipped, 8 passed, 8 of 9 total
Tests:       1 skipped, 163 passed, 164 total
```

So the Dev's number is right, but not via the documented command. Not a
defect in the change; flagged because the next agent to run `npm test` here
will see ten red tests naming the two components this work touched, and will
reasonably think it broke something. Deleting the stale worktree, or adding
it to `testPathIgnorePatterns` in `jest.config.js`, closes it.

### 🟡 Finding 6 (Process) — the isolation proof was available against real offerings and was not used

The Dev's stated reason for skipping plan §QA-1's fixture offering — avoid
leaving fixture CMDT in production — is sound, and I followed the same rule.
But it was not necessary: `my-test-offering` and `data-cloud-accelorator`
are **real, already-present, selectable offerings** in this org. §QA-2 and
§QA-3 could both have been executed against them with nothing deployed at
all. Doing so is what surfaced Findings 1–3, none of which a synthetic
never-existing key makes visible, because a synthetic key never reaches
`getOfferings()`, `sourceLabelFor()`, or the Instrument Editor's combobox.

### ℹ️ Check 6 — Instrument Editor, Apex-entry-point substitute (no browser)

**I did not see this rendered.** Stating that explicitly, per the task.
What I did instead: called the exact Apex the LWC calls, with the exact
parameters it passes, for two different offerings.

`gtmInstrumentAuthor.connectedCallback` → `GtmPageContentController.getOfferings()`
returns four rows; the component filters `gtm` out, leaving three
selectable offerings, and (because `offerings.length !== 1`) leaves
`selectedOffering = ''` until the user picks — so the combobox path is
genuinely live, not the single-offering shortcut. Switching offerings
re-calls `getFrame({offeringKey})` and `getPack({offeringKey, …})`, which
return, live:

| offeringKey | `getFrame.slotCount` | `getPack.slots` | first slot label |
|---|---|---|---|
| `migration-accelerator` | 8 | 8 | `Estate Scale & Structure` |
| `my-test-offering` | 0 | 0 | — |
| `data-cloud-accelorator` | 0 | 0 | — |

The shapes are renderable and do switch. **But** `getFrame` for the two
empty offerings still returns Migration Accelerator's full four-band ladder
(`Discovery First 8-14 … Fast-Track 27-32`) next to a slot count of 0 — the
documented no-frame-record fail-open, but in the *authoring* surface it
means an author opening a brand-new offering is shown Migration
Accelerator's band edges as if they were that offering's. Same family as
Findings 2 and 3; noted rather than raised separately.

---

## Summary

| # | Check | Result |
|---|---|---|
| 1 | Apex `RunLocalTests` re-run | ✅ 559/559, 100% |
| 1 | Jest re-run | ⚠️ 163 pass / 1 skip in-tree; documented `npm test` shows 10 red (F5) |
| 2 | Isolation proof re-derived + extended | ✅ holds; could not break it |
| 3 | Guest CMDT grant live, necessary, sufficient | ✅ |
| 4 | Backfill 13/13, 0 blank, nothing rescored | ✅ |
| 5 | `Source__c` unchanged for pre-existing rows | ✅ — but the *second-offering* half of the claim is false (F1) |
| 6 | Instrument Editor end-to-end | ⚠️ Apex-level only; no browser |
| 7 | YAML move is path-segments only | ✅ 23/23 lines, 0 mismatches, no `name:` touched |
| 8 | `docs/backlog.md` D11 pointer | ✅ present and accurate |
| 9 | `build-instrument.py --check` / `check-references.py` | ✅ clean / 6+94, unchanged |

**Blocking:** Findings 1, 2, 3.
**Non-blocking, should be fixed or documented:** Findings 4, 5, 6.

The design is sound and the hard part — making an unrecognised offering
score nothing instead of confidently scoring 32 against somebody else's
questions — is real, reproducible, and survived every attempt I made to
break it. What is left is the same leak, one layer out, in the two places
`compiledApplies` was not applied.
