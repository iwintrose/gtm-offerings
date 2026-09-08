# QA round 2 — per-offering assessment instrument (ADR-0007), fix commit `f56ea29`

**Reviewer:** QA agent (session `session_018UJzwgTCCMdESELzYMeWAZ`)
**Date:** 2026-09-08
**Scope:** commit `f56ea29`, the Dev's implementation of the Architect's
endorsed fix list (`per-offering-instrument-fix-list-round-1.md`, commit
`b3cc761`) for the three blocking findings in
`per-offering-instrument-qa-findings-round-1.md` (commit `9df398a`).
Re-verified independently against live `gtm-dev` (treated as production per
CLAUDE.md §1).

**Verdict: APPROVED.** All three round-1 blockers are closed, and closed at
the level that matters — I confirmed the fix on the *persisted field* and the
*guest endpoint*, not only on the methods the Dev demonstrated. Every one of
the Dev's seven claims holds, with one correction the Dev raised that lands
partly on them and mostly on **me** (item 7), and four non-blocking residuals
named below.

> **Deliberate omission:** this file does not contain the literal `gtm-dev`
> org id. `scripts/check-references.py` counts any doc containing it as
> deploy-blocking, and my round-1 report is itself one of the seven (see item
> 7). Writing the id here would take the count to 8 for no benefit.

---

## Method

Everything below was run by me, in this session, against live `gtm-dev`.
Nothing was taken from the Dev's report on faith.

- **The classes I tested are the classes in this branch.** Pulled `Body` for
  ten classes over the Tooling API and compared byte-for-byte against the
  working tree at `f56ea29`: **all ten identical**, including the four test
  classes (so the org is not running a stale copy of either the fix or its
  tests).

  ```
  IDENTICAL  GtmAssessmentRequestController      (64932 bytes)
  IDENTICAL  GtmAssessmentScoring                (42823 bytes)
  IDENTICAL  GtmAssessmentQuestions              (13221 bytes)
  IDENTICAL  GtmEstateComplexity                 (16472 bytes)
  IDENTICAL  GtmAssessmentInstrument             (69742 bytes)
  IDENTICAL  GtmAssessmentFrames                  (7797 bytes)
  IDENTICAL  GtmAssessmentRequestControllerTest  (58694 bytes)
  IDENTICAL  GtmAssessmentScoringTest            (45214 bytes)
  IDENTICAL  GtmAssessmentQuestionsTest          (10222 bytes)
  IDENTICAL  GtmEstateComplexityTest              (9919 bytes)
  ```

  (I initially ran this diff through a shell pipeline whose `sed` silently
  errored, which would have reported IDENTICAL for *any* pair of files. I
  caught it and redid the comparison in Python on the raw bytes. The numbers
  above are from the second, correct run.)
- Five anonymous-Apex scripts against the deployed classes, plus direct SOQL,
  plus a Tooling-API query of `ApexTestRunResult`.
- **Production residue: none.** The `Source__c` work drives the real
  `submitRequest` path, so it is DML. Every such run is wrapped in one
  `Database.setSavepoint()` rolled back in a `finally`, and each script
  counts four tables before and after. Every batch: `req=13 sec=42
  content=218 cfg=7` before, identical after. `emailSent=false` on all ten
  submissions — the CMDT config has `Send_Email__c = true` but
  `Notify_Email__c = null`, and I left `Notify_Email__c` blank on every
  probe link, so `notify()` could not fire. (Email is the one side effect a
  savepoint rollback would not undo, which is why it was checked rather than
  assumed.)
- **No browser.** Same gap as round 1, stated explicitly. Check 6 below is
  the Apex-entry-point substitute.

---

## Item 1 — `sourceLabelFor()` runs `getOfferings()`'s three tiers ✅

**Claim verified, and extended past what the Dev demonstrated.**

`sourceLabelFor` is private, so the only honest way to exercise it is the
real `submitRequest` path — which is what the Dev did and what I did. The
Dev's demonstration covered the two real offerings, both of which resolve at
**tier 2**. The task asked specifically whether the chain still terminates
correctly for a key that resolves via the `GTM_Page_Section__c`-only tier.

**It does, and I did not need to construct a case — one exists naturally.**
Recon showed `gtm` has 15 active `GTM_Page_Section__c` rows and **no**
`offerings-listing`/`name` row, so it is a live tier-3 offering:

```
SEC migration-accelerator = 24   LISTNAME migration-accelerator = 1
SEC gtm                   = 15   (no LISTNAME row for gtm)
SEC my-test-offering      = 1    LISTNAME my-test-offering = 1
SEC data-cloud-accelorator= 2    LISTNAME data-cloud-accelorator = 1
GTM_Offering__mdt = 1 row (migration-accelerator → 'Migration Accelerator')
```

I then drove all four tiers plus three constructed boundary cases through the
real `submitRequest`, in savepoints, and asserted the *persisted* `Source__c`:

| offering key | tier exercised | `Source__c` | expected | |
|---|---|---|---|---|
| `migration-accelerator` | 1 — CMDT label | `Migration Accelerator` | `Migration Accelerator` | ✅ |
| `my-test-offering` | 2 — listing tile name | `My Test Offering` | own name | ✅ |
| `data-cloud-accelorator` | 2 — listing tile name | `Data Cloud Accelerator` | own name | ✅ |
| **`gtm`** | **3 — section-only** | **`gtm`** | raw key | ✅ |
| `qa-r2-inactive-name` | 3 — name row exists but `Active__c=false` | `qa-r2-inactive-name` | raw key, **not** the inactive name | ✅ |
| `qa-r2-blank-name` | 3 — active name row, blank `Text_Value__c` | `qa-r2-blank-name` | raw key | ✅ |
| `qa-r2-inactive-section` | 4 — only an *inactive* section | `Migration Accelerator` | terminal fallback | ✅ |
| `qa-round2-no-such-offering` | 4 — nothing anywhere | `Migration Accelerator` | terminal fallback | ✅ |

The three constructed rows (`qa-r2-*`) existed only inside the rolled-back
savepoint. The last four rows are the adversarial half: they prove each tier's
`Active__c` filter and `String.isNotBlank` guard actually gate the fall-through
rather than the tier order merely happening to work on the happy path.

Two further checks on this fix, neither in the Dev's report:

- **SOQL cost on a guest-reachable transaction.** Two new queries were added
  to `submitRequest`. Measured with `Limits.getQueries()`: **13 queries for a
  `migration-accelerator` submission, 11 for `data-cloud-accelorator`**,
  against a limit of 100. Note the direction — MA uses *more*, because tier 1
  hits and the new queries never run for it, while the second offering
  short-circuits its instrument resolution. The new tiers cost at most two
  queries and only when tier 1 misses. No limit risk.
- **Permissions.** The two new queries read `GTM_Page_Content__c` and
  `GTM_Page_Section__c`, neither of which is in `GTM_Assessment_Guest`
  (which grants Contact, Event, `GTM_Assessment_Request__c`,
  `GTM_Saved_Configuration__c`, Opportunity, Task). That is **correct, not a
  §5.1 gap**: both queries are plain inline SOQL with no
  `WITH SECURITY_ENFORCED`/`USER_MODE` clause in a `without sharing` class, so
  they run in system mode; and each is individually wrapped in the
  fail-open `try/catch` the fix list required, so even a permission or table
  failure costs the label a tier, never the submission.

The rewritten doc comment (`GtmAssessmentRequestController.cls:494-534`) now
names the three tiers and states the tier-4 limit plainly, which was the
other half of round-1 Finding 1.

## Item 2 — `frameMaxTotal()` gated on `compiledApplies` ✅

**Claim verified at the method, and — stronger than the Dev's claim — on the
persisted field.**

Method level, live:

```
A [migration-accelerator]      scoringMax=32     (unchanged)
A [my-test-offering]           scoringMax=null   (was 32)
A [data-cloud-accelorator]     scoringMax=null   (was 32)
A [gtm]                        scoringMax=null
A [qa-round2-no-such-offering] scoringMax=null
```

Persisted-field level, from the same rolled-back real submissions as item 1 —
this is the assertion that actually matters, since round-1 Finding 2 was about
what `GtmAssessmentRequestController.cls:682` writes:

```
[migration-accelerator]  Instrument_Max_Score__c=32   Assessment_Score__c=3
[my-test-offering]       Instrument_Max_Score__c=null Assessment_Score__c=null
[data-cloud-accelorator] Instrument_Max_Score__c=null Assessment_Score__c=null
[gtm]                    Instrument_Max_Score__c=null Assessment_Score__c=null
```

A real submission against a second offering no longer writes "measured out of
32" onto a row whose score is null. Migration Accelerator's row is byte-for-byte
what it always was.

I also confirmed the constructor default cannot leak past this: `Score()` still
initialises `this.maxTotal = MAX_TOTAL_SCORE`, but `score()` overwrites it
unconditionally at `GtmAssessmentScoring.cls:534` before any branch can return.

## Item 3 — `Questionnaire` maxima derived per offering ✅

**Claim verified.** `GtmEstateComplexity.maxTotalFor(String)` is new at
`GtmEstateComplexity.cls:309` and public, as the fix list specified.

```
A [migration-accelerator]      qn r=8/32   c=6/18    (unchanged)
A [my-test-offering]           qn r=0/null c=0/null  (was 0/32, 0/18)
A [data-cloud-accelorator]     qn r=0/null c=0/null  (was 0/32, 0/18)
A [gtm]                        qn r=0/null c=0/null
A [qa-round2-no-such-offering] qn r=0/null c=0/null
```

Adversarial angle the Dev did not cover — **the null/blank key**, which is the
legacy "no offering in hand" meaning and is reachable from any caller that
omits the parameter:

```
B nullKey  scoringMax=32 complexityMax=18   qn r=0/32 c=0/18
B blankKey                                  qn r=0/32 c=0/18
```

This is **not a regression** — see residual R2 below for why it is worth
naming anyway.

## Item 4 — isolation not reopened ✅

**Claim verified, and extended.** All eight Migration Accelerator dimension
keys at value 4, scored against each non-MA offering with no pack:

```
C1 [data-cloud-accelorator] total=null maxTotal=null tier=null dimKeys=0 scored=0 hasAnswers=false
C1 [my-test-offering]       total=null maxTotal=null tier=null dimKeys=0 scored=0 hasAnswers=false
C1 [gtm]                    total=null maxTotal=null tier=null dimKeys=0 scored=0 hasAnswers=false
C4 [all three] complexity total=null band=null hasAnswers=false
C5 [migration-accelerator] total=32 maxTotal=32 tier=Fast-Track dimKeys=8 scored=8   (control)
C6 [migration-accelerator] complexity total=3 band=Light                             (control)
```

Round 1 proved this for a null pack and an empty pack. The stronger adversarial
form — **injecting Migration Accelerator's real, live 8-slot pack into another
offering's `score()` call** — is new here, and is specifically the shape the
new `null` from `frameMaxTotal()` has to survive on `pointsAreTrustworthy()`'s
`pack.maxTotal() == frameMaxTotal(...)` comparison:

```
C0 MA pack slots=8 maxTotal=32
C3 [data-cloud-accelorator] maxTotalFor(offering, MA pack) = null
C3 [my-test-offering]       maxTotalFor(offering, MA pack) = null
C3 [gtm]                    maxTotalFor(offering, MA pack) = null
```

No exception thrown — `Integer == null` evaluates `false` in Apex, as the
Architect predicted — and the denominator stays null even when a foreign pack
hands it a confident 32. See residual R1 for the one thing this turned up.

## Item 5 — test suites ✅

**Apex, my own run, test run `707gK00000refJP`:**

```
outcome = Passed    testsRan = 566    passing = 566    failing = 0    passRate = 100%
```

All seven new tests present and passing, verified by name in my run:

```
OK  GtmAssessmentQuestionsTest.anOfferingWithNoInstrumentIsOfferedNoQuestionsAndNoDenominator
OK  GtmAssessmentRequestControllerTest.tierOneMigrationAcceleratorKeepsTheExactLegacyLiteral
OK  GtmAssessmentRequestControllerTest.tierTwoAnOfferingWithOnlyPageContentGetsItsOwnAuthoredName
OK  GtmAssessmentRequestControllerTest.tierThreeARealButUnnamedOfferingGetsItsKeyNotAnotherOfferingsName
OK  GtmAssessmentRequestControllerTest.tierFourAGenuinelyUnknownOfferingStillFallsBackToTheLegacyLiteral
OK  GtmAssessmentScoringTest.theDenominatorLeaksNoFurtherThanTheNumeratorDid
OK  GtmEstateComplexityTest.theComplexityMaximumIsPerOfferingAndNullWhereThereIsNoInstrument
```

Each of the seven is genuinely discriminating rather than vacuously green: I
independently measured the pre-fix values in round 1 (`maxTotal=32`,
maxima `32`/`18`, `Source__c = 'Migration Accelerator'` for both real
offerings) and the post-fix values above, and every new assertion inverts on
that difference.

**Measurement note, not a defect:** the `sf` CLI summary says `testsRan = 566`
while the JSON's own `tests` array holds 565 records and the org's
`ApexTestRunResult.MethodsEnqueued` is **565** (`MethodsFailed: 0`). The CLI
appears to be off by one. Round 1's "559" came from the same CLI summary, so
both baselines are measured identically and the delta is `+7` either way. The
load-bearing facts — seven new tests, zero failures — are unaffected.

**Jest, my own run:** `Test Suites: 1 skipped, 8 passed`; `Tests: 1 skipped,
163 passed, 164 total` — unchanged, as claimed. This is via
`npx jest --testPathIgnorePatterns "/node_modules/" "/.claude/"`, not the
documented `npm test`: the stale gitignored worktree
`.claude/worktrees/agent-a26c5231ddadc2b1d` is still present, so round-1
Finding 5 stands unfixed (correctly — it was non-blocking and out of scope).

**Other static checks, my own runs:**

```
python3 scripts/build-instrument.py --check
  → Instrument up to date: 55 records across 1 offering(s), all 14 rules hold.
```

The deploy claim itself I could not re-run (re-deploying to production to check
a deploy is not a QA action). I verified its *outcome* instead, which is the
stronger evidence: all ten deployed class bodies byte-identical to `f56ea29`.

## Item 6 — D14 deferral is legitimate, not scope-creep avoidance ✅

**Dev's characterization is accurate.** Read the current code:

- `GtmAssessmentInstrument.getFrame()` (`:635-652`) takes its ladder from
  `GtmAssessmentScoring.bands(offeringKey)` and then derives
  `f.minTotal`/`f.maxTotal` from `bands[0].lowest`/`bands[last].highest`.
- `GtmAssessmentScoring.bands(offeringKey)` (`:216-222`) ends
  `return authored == null ? migrationAcceleratorBands() : authored;` — the
  fail-open, which is reached whenever there is no frame record *or* no
  parseable `Bands_JSON__c`.

Reproduced live after the fixes:

```
CHECK6 [migration-accelerator]  slotCount=8 maxTotal=32 bands=[Discovery First 8-14]…[Fast-Track 27-32]
CHECK6 [my-test-offering]       slotCount=0 maxTotal=32 bands=[Discovery First 8-14]…[Fast-Track 27-32]
CHECK6 [data-cloud-accelorator] slotCount=0 maxTotal=32 bands=[Discovery First 8-14]…[Fast-Track 27-32]
CHECK6 [gtm]                    slotCount=0 maxTotal=32 bands=[Discovery First 8-14]…[Fast-Track 27-32]
```

Matches the D14 entry exactly.

**On scope, which is what the task asked me to confirm.** This is a genuinely
different site from the three that were fixed: `getFrame().maxTotal` is derived
from the *bands*, not from `frameMaxTotal()`, so Fix 2 could not have closed it
as a side effect. And the Architect's fix list did not merely omit it — it
pre-authorised exactly what the Dev did, in writing:

> "Re-run Check 6's Instrument Editor Apex-substitute table … to confirm
> `getFrame`'s band ladder no longer shows Migration Accelerator's edges next
> to a 0 slot count — **or, if that's out of this round's scope, confirm it
> explicitly and leave it named rather than silently unaddressed.**"

The Dev took the second branch and named it in the decision log. The reasoning
also holds on its merits: the fail-open is load-bearing, because
`GTM_Assessment_Frame__mdt` has **zero rows** in this org, so *every*
Migration Accelerator assessment alive today reaches its ladder through that
same fallback. Removing it would break the one offering that works. Deciding
what a frameless offering should preview instead is a design call. Deferral
endorsed.

See residual R3 for one thing the D14 entry should gain.

## Item 7 — the `check-references.py` count: **the Dev is right about head, and I was wrong to call 6 a baseline** ⚠️

I re-ran this myself on current head and in a clean detached worktree at each
commit. The true numbers:

| tree | deploy-blocking |
|---|---|
| `b89f7df` (round-1 head, what I reviewed) | **6** |
| `9df398a` (my round-1 QA report) | **7** |
| `b3cc761` (Architect's fix list) | 7 |
| `f56ea29` (Dev's fix, current head) | **7** |

**Owning my half.** The Dev is right that the number is 7 and that my report's
"6" no longer describes any tree anyone can check out. Worse, my round-1 report
presented it as a *stable baseline* — "6 deploy-blocking, 94 needing a manual
step … Identical to the claimed baseline" — when the very act of committing
that report was what changed it. The seventh blocker **is my own round-1 QA
report**: `check-references.py` flags any file containing the hardcoded org id,
and I quoted the org id in my report's Scope line. My number was accurate at
the instant I ran it and stale the moment I committed, and I should have either
run it after committing or said which tree it described.

**Correcting the Dev's half, for the record.** The Dev's stated method —
"checked out your own commit `b89f7df` directly" — does **not** give 7; it
gives 6, verified in a clean detached worktree. The likely mechanism is a
`git checkout <sha> -- .`-style restore, which rewrites tracked files but does
not delete files absent from that commit, so the round-1 report would have
survived into the tree being measured. This does not change the conclusion.

**The conclusion that matters:** the delta from 6 to 7 is caused **entirely by
QA's own artifact** and **zero by the Dev's code**. All seven blockers are
markdown files quoting the org id (`AGENTS.md`, `CLAUDE.md`, and five
`docs/agent-artifacts/*.md`); no source file is implicated, and `f56ea29`
changed the count by nothing. `94 needing a manual step` is unchanged
throughout. This file deliberately omits the org id so head stays at 7.

---

## Residuals — none blocking, all named

**R1 — a foreign pack now produces a numerator with no denominator.** Turned
up by the item-4 injection test. Handing `score()` one offering's key and
another offering's real pack yields:

```
C2 [data-cloud-accelorator] MA-PACK-INJECTED total=32 maxTotal=null tier=Fast-Track dimKeys=8 scored=8
```

A full score and a real tier, measured out of `null`. Before Fix 2 this case
returned `total=32, maxTotal=32` — coherent and wrong; it now returns
incoherent-and-flagged, which is arguably the better failure but is worth
someone's eyes. **Not reachable in production:** `submitRequest` has the only
production call site (`GtmAssessmentRequestController.cls:646`) and resolves
its pack from the same `offeringKey` it passes, and
`GtmAssessmentInstrument.getPack(<second offering>, …)` returns 0 slots
(verified live). So this requires a caller to deliberately mismatch key and
pack. It is a contract on `score()`'s 4-arg overload that is currently
unwritten.

**R2 — the null/blank offering key is the last "N questions out of 32".**
`getQuestionnaire(null)` returns **0 readiness questions with
`readinessMaxScore = 32`**, because `rows()` binds `:offeringKey` and matches
nothing, while `maxTotalFor(null, …)` treats a blank key as Migration
Accelerator. Pre-existing and **unchanged** by this commit (the old constructor
hardcoded 32/18 too), so it is not a regression. It is worth naming because
`theDenominatorLeaksNoFurtherThanTheNumeratorDid` now *pins*
`maxTotalFor(null, null) == 32` as intended behaviour, so the two halves of the
null-key case are now deliberately inconsistent with each other rather than
accidentally so.

**R3 — D14's entry understates what the fixes changed.** For the *same*
offering, in the *same* transaction, the org now reports:

```
CHECK6 [my-test-offering] getFrame().maxTotal = 32   |   GtmAssessmentScoring.maxTotalFor(...) = null
```

The three fixes made the authoring-preview surface and the scoring surface
actively contradict each other, where before they agreed on 32. That is the
right direction — the persisted, guest-facing surface is the one that became
honest — but D14 currently reads as "one preview is stale" rather than "two
surfaces now disagree", and the disagreement is the more useful description for
whoever picks it up.

**R4 — the rewritten doc comment still slightly overclaims, on `gtm`.** It
says the tiers mirror `getOfferings()` "because an offering that shows one name
in the offering picker and a different one on the request it produced is its own
bug." For `gtm` that is exactly what now happens: `getOfferings()` labels it
`Framework (all offerings)` (from `GtmPageContentController.FRAMEWORK_LABEL`),
while `sourceLabelFor('gtm')` returns the raw key `gtm` via tier 3 — verified
live. Latent, not live: all 7 `GTM_Saved_Configuration__c` rows carry
`Offering__c = 'migration-accelerator'`, and `gtm` is a framework pseudo-offering
the Instrument Editor filters out of its combobox. The Dev implemented tier 3
exactly as the fix list specified, so this is an unforeseen edge in the endorsed
design, not a deviation from it.

**Carried forward unfixed from round 1, correctly out of scope:** Finding 4
(cache key trimmed, SOQL bind not — `GtmAssessmentQuestions.cls:245` unchanged)
and Finding 5 (the stale `.claude/worktrees/` copy still red under the
documented `npm test`).

---

## Summary

| # | Dev's claim | Result |
|---|---|---|
| 1 | `sourceLabelFor()` runs all three tiers | ✅ verified on the persisted `Source__c` for all 4 tiers + 3 constructed boundary cases; tier 3 confirmed via the natural `gtm` case |
| 2 | `frameMaxTotal()` gated on `compiledApplies` | ✅ verified at the method **and** on `Instrument_Max_Score__c` end-to-end |
| 3 | `Questionnaire` maxima per offering | ✅ verified; `GtmEstateComplexity.maxTotalFor()` present and public |
| 4 | Isolation not reopened | ✅ reproduced, and extended with foreign-pack injection |
| 5 | Apex 566/566, Jest 163/1-skip, deploy clean | ✅ both re-run by me; deploy outcome verified by 10/10 byte-identical class bodies |
| 6 | D14 deferral, not a fix | ✅ code reads as described; deferral explicitly pre-authorised by the fix list and sound on its merits |
| 7 | check-references baseline is 7, not 6 | ⚠️ **Dev right about head (7), QA wrong to call 6 a baseline; Dev's stated method for `b89f7df` gives 6, not 7. Delta is 100% QA's own artifact, 0% Dev's code.** |

The three blocking findings from round 1 are closed. The central isolation
guarantee survived every attempt I made to break it, including one the round-1
proof did not attempt. Approved.
