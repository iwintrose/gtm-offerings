# The assessment instrument — what it measures and where to edit it

Two axes, reported side by side and never added together.

| Axis | Range | What a high number means | Stored on `GTM_Assessment_Request__c` |
|---|---|---|---|
| **Migration Readiness** | 8–32 (8 dimensions × 1–4) | Small, simple, portable, well-owned estate — *easy to scope* | `Assessment_Score__c`, `Assessment_Tier__c`, `Section_Scores__c` |
| **Estate Complexity** | 6–18 (6 dimensions × 1–3) | Big, deep, heavily customised estate — *bigger engagement* | `Estate_Complexity_Score__c`, `Estate_Complexity_Band__c`, `Estate_Complexity_Basis__c`, `Estate_Complexity_Dimensions__c` |

They are separate on purpose. A heavy estate is a **bigger** piece of work, not
a worse client; blending the two would turn the most valuable opportunities into
the lowest-scoring ones. Readiness decides *whether* an engagement can be
scoped; complexity decides *how big* it is.

## Readiness bands (`Assessment_Tier__c`)

| Band | Label | What it says to sell |
|---|---|---|
| 8–14 | **Discovery First** | Can't responsibly scope yet — access, documentation or estate knowledge is missing. Sell discovery, not migration. |
| 15–20 | **Prep Required** | Migratable with named prerequisites before build: credentials, rationalisation, decision owners, a form/consent audit. |
| 21–26 | **Accelerator-Ready** | Estate is knowable and largely portable. Standard engagement path. |
| 27–32 | **Fast-Track** | Small, clean, well-owned estate. Compressed engagement; fixed-scope candidate. |

Every dimension is scored so **4 = lowest migration risk**. A sophisticated
marketing operation scores *low* here, and that is correct: it is harder to
migrate.

## The two overrides — these outrank the band

1. **Access gate.** `source_access == 1` caps the tier at **Discovery First**
   regardless of the total. No extract, no offering. The score is left alone;
   only the band is pulled down, and `Discovery First` is a real, sellable
   recommendation rather than a refusal.
2. **Unsupported-pair gate.** If the source/target combination is one the
   accelerator cannot process, the tier is **suppressed entirely**
   (`Assessment_Tier__c` stays null, `Assessment_Advisory__c` is set, and
   `Advisory_Reason__c` says why). The score and breakdown survive as input for
   a manual conversation. Banding a feasibility instrument for a pair the tool
   can't handle is a false promise.

There is also one **non-blocking annotation**: `orchestration_portability == 1`
*and* `content_portability == 1` raises `high_rebuild_ratio` into
`Assessment_Flags__c` — "expect automation levels C/D to dominate" — even at a
high total, because it is true regardless of the headline number.

## Where to change things

| I want to change… | Edit | Deploy needed? |
|---|---|---|
| A question, an answer option, a dimension's display name | `GTM_Assessment_Question__mdt` records (Setup → Custom Metadata Types) | No — metadata only |
| Which source/target pairs are supported, or their "why not" wording | `GTM_Migration_Pair__mdt` | No |
| Platform spellings that free-text answers should resolve to | `GTM_Migration_Platform__mdt` → `Aliases__c` (semicolon-separated) | No |
| What each answer option is **worth**, and **which** question a branch asks | `instrument/migration-accelerator/pairs/*.yaml`, then `python3 scripts/build-instrument.py` — authored through the **Instrument Editor** tab in the GTM Content Manager app. See *Branches and scores* below | No Apex; the generated metadata deploys |
| The respondent-facing form itself — steps, grouping, progress | `gtmAssessmentQuestionnaire` (guest-accessible, `/assessment` on the Experience Cloud site) | Yes — LWC |
| The set of dimension **keys**, the scales, the band edges, the override rules | `GtmAssessmentScoring.cls` / `GtmEstateComplexity.cls` | Yes — Apex |

The split is deliberate. The keys are the allowlist a guest-reachable endpoint
scores against, so editing a text field must never change what counts; the
wording is what a consultant needs to tune without a developer.

Drift between the two halves is visible rather than silent:
`GtmAssessmentQuestions.unscoredKeys()` names configured keys the scorer ignores,
and `missingKeys()` names scoreable dimensions with no question configured.
`GtmAssessmentQuestionsTest` asserts both are empty against whatever metadata the
org actually has.

## Scoring is server-side, always

`GtmAssessmentRequestController` recomputes both axes from the raw answers and
discards any client-supplied score, tier or basis — including
`complexityBasis: "Measured"`, which is downgraded to `Self-Estimated`, because
a questionnaire answer is a pre-scan estimate whatever the client calls it.
`Measured` is written only when a real extract has been scanned.

---

# The adaptive layer — same frame, pair-specific content

Everything above describes the instrument every prospect gets. This half
describes how it adapts to *what they are moving from and to* without any of
the numbers becoming incomparable.

## What adapts, and what never does

| Never changes | Changes per pair |
|---|---|
| 8 slots, 1–4 each, 8–32 total | The wording and the anchors of slots 2–7 |
| The four band edges (14/20/26) | Which questions slots 2–7 ask (substitution) |
| Slot 1 (`estate_scale`) and slot 8 (`decision_readiness`) | Extra questions **outside** the 32 (supplements) |
| That a supplement can never reach the readiness total | Which named gaps are called out, and how hedged |

There is deliberately **no per-pair weighting and no per-pair band**. The
instrument's only real output is that one prospect's score can be compared to
another's, and "19 would have been Accelerator-Ready if you'd come from Marketo"
is the sentence a per-pair band eventually produces. Per-pair severity is
expressed two other ways instead: through **option calibration** (a 4 is harder
to earn on a hostile pair) and through **gates**, which qualify the tier without
touching the number.

## The five layers

Author at the lowest layer that does the job. Every layer up costs a little
comparability, so the cost has to be paid for.

| | Layer | What it does | Cost |
|---|---|---|---|
| L0 | constant | The slot does not vary | None |
| L1 | reword | Same anchors, this pair's nouns and examples | None — the scale is unchanged |
| L2 | recalibrate | The anchors move; a 4 is harder or easier to earn | Two pairs' 3s now describe different estates |
| L3 | substitute | A different question in the same **position**, carrying the same **risk theme** | Two prospects' totals are made of different things |
| L4 | supplement | Extra questions **outside** the 32, producing their own named index | None to the 32; a longer questionnaire |

**L3 is for differences of kind, not of degree.** The seeded example: in HubSpot
the CRM *is* the marketing platform, so "is your data model knowable and
mappable" is not a harder version of the right question — it is a different one,
and slot 5 is replaced with `crm_and_data_model_entanglement`. Slots 1 and 8 are
never substitutable: the size question every conversation opens with and the
question of whether anyone can say yes have to mean the same thing everywhere,
or two 24s stop describing the same eight things.

## The resolution chain

Most specific wins, shallow-merged **per slot and per field**:

```
exact pair (hubspot__mcn)
  → source-family × target (inbound_suite__mcn)
    → target-only (any__mcn)
      → base
```

Merging runs least-specific-first, so a more specific pack overwrites. A field a
more specific pack leaves null **inherits** rather than clearing — a target-only
pack can move the consent anchors while the exact pair changes only slot 5, and
neither has to restate the other. Callouts are the one thing that **accumulate**
rather than replace, keyed by `pattern`, with the more specific pack winning a
collision: a target's structural gaps are still true when a pair adds its own.

Families come from `GTM_Migration_Platform__mdt.Family_Key__c` — the same table
that already owns "which spellings mean the same platform" now also owns "which
platforms behave alike".

A target of **"Not decided yet"** resolves to base and the readout says so.

## Posture — what is measured and what is asserted

Every pack declares a posture at each end:

| Posture | Means |
|---|---|
| `instrumented` | A real adapter reads or writes it |
| `assisted` | Canonical IR + a gap catalogue, with an operator-run extraction |
| `interview_only` | No adapter. The numbers are what the client told us |

`Capability_Posture__c` is always the **weaker of the two ends** (the build
script enforces it) and drives an above-the-fold sentence *before* the score.
The "estate figures are illustrative" marker keys on the **source** posture
instead, because estate figures come from reading the source — so Eloqua→SFMC is
`assisted` both ends, SFMC→MCN has measured counts and an unverified
destination, and HubSpot→MCN is `interview_only` throughout.

## Gates

A gate is a boolean predicate over the answers that adds a tier **qualifier** and
a readout block. It never touches the score and never moves the band. **A
Fast-Track score carrying `foundation-gated` is legitimate and common** — a
small, clean, portable estate that still cannot start for four months because
the target's data layer does not exist — and the readout says both at once.

Three ship in v1:

| Gate | Fires when | Qualifier |
|---|---|---|
| `foundation_gated` | target = MCN and `data_cloud_state` = 1 | foundation-gated |
| `no_core_platform` | target ∈ {MCN, SFMC} and `core_footprint` = 1 | platform-precursor required |
| `consent_parity_risk` | target = MCN and `consent_portability` ≤ 2 | consent workstream off critical path |

A field with no answer makes its clause **false**. A gate that fires on data
nobody supplied reads to a prospect as the tool guessing.

## Ceilings

Where a pack caps a slot (`Max_Attainable__c`), the excluded options still
**render, greyed, with `Ceiling_Reason__c` beside them**. A prospect who can see
that a 4 was not on offer and why can argue with the instrument; one who cannot
has been quietly marked down. Two ship on `hubspot__mcn`: `source_access` at 3
("no HubSpot connector ships today") and `consent_portability` at 3 (MCN Consent
& Custom Preferences is Spring '26+ with parity unverified).

The ceiling is enforced **server-side too**: an answer above it is **dropped, not
clamped** — the same rule the scorer has always applied to out-of-range values,
for the same reason.

---

# Branches and scores — what a content author sets

Two things a content author now owns that used to be implicit or impossible:
what each option is **worth**, and **which** of several authored questions a
respondent is asked. Both are authored in the pair YAML and both go through the
build script before they can reach anybody.

The editor for them is the **Instrument Editor** tab in the *GTM Content
Manager* app (`gtmInstrumentAuthor`). It is on the content-author side on
purpose: a rep works a deal in `gtmReadoutReview` and must not be able to retune
the instrument that deal was scored on. The editor reads the resolved pack,
lets you set points and predicates, **previews the branches**, and emits the
YAML to commit. It does not write custom metadata, because the YAML is the
source of truth and the metadata is a build output — see
`scripts/build-instrument.py`.

## Setting scores — per-option points

Points used to be implicit in position: option 1 was worth 1, option 4 worth 4.
They are now explicit and author-set, stored beside the label:

```yaml
    options:
      - value: 1
        label: "Nobody is sure. Consent state exists in more than one system."
        points: 1
      - value: 2
        label: "Another team's system masters it and is out of scope."
        points: 1          # deliberately the same as option 1
      - value: 3
        label: "Another system masters it, the owner is named and engaged."
        points: 3
      - value: 4
        label: "A single system masters consent and it is in scope."
        points: 4
```

`value` is the option's **identity** — what a stored answer means — and never
changes. `points` is what it is **worth**. Omit `points` and it defaults to the
value, which is exactly what every option was worth before this existed, so no
already-authored content changes.

**What points may and may not do.** They may make a scale *non-linear* — "these
two answers are equally bad" is a true thing about an estate, and a scale that
cannot say it is lying by rounding. They may **not** change what a slot is
worth. Build rule 10 requires every option set to bottom out at **1**, top out
at **4**, and never descend. Every slot is therefore worth 1–4, every pair is
scored out of **32**, and the four band edges (14/20/26) still mean what they
say. An author who could set the top option to 3 would have built an instrument
scored out of 31 wearing bands calibrated for 32 — the same "your 19 would have
been Accelerator-Ready coming from Marketo" failure the fixed frame exists to
prevent, arriving by a different door.

There is a **second lock at runtime**: `GtmAssessmentScoring` derives the maximum
from the authored points (`Pack.maxTotal()`) and, if it comes to anything other
than 32, refuses the authored points wholesale and scores on the identity scale
instead. The build script catches this at authoring time; the runtime catch is
for a hand-edited custom metadata record, which never passes through the build
script. Same two-lock pattern as the pinned-slot rule.

The maximum a submission was actually scored against is stored on
`GTM_Assessment_Request__c.Instrument_Max_Score__c`, so a readout reopened after
someone retunes an offering's scores prints the maximum it was measured against
rather than today's.

## Adding a branch — `show_when`

Pair resolution asks "who is moving where" **before** the first question.
Branching asks "what have they already told us". A branch is authored as one
extra `overrides:` entry on the same slot:

```yaml
  # The DEFAULT: no show_when, so it always applies.
  - dimension: consent_portability
    layer: recalibrate
    question: >-
      How is subscription and consent state modelled in Marketing Cloud today?
    options: [...]

  # A VARIANT: substitutes for the default when the predicate matches.
  - dimension: consent_portability
    layer: substitute
    variant_key: consent_owned_elsewhere
    variant_order: 10
    show_when:
      all:
        - { field: integration_containment, op: lte, value: 2 }
    new_key: consent_ownership_outside_platform
    label: Consent Ownership Outside the Platform
    question: >-
      Who actually MASTERS consent — the CRM, a CDP, a preference service?
    options: [...]
    rationale: ...
```

The worked example ships on `sfmc__mcn`, slot 7. Read that file before authoring
your own.

**The predicate language is the gate language.** `show_when` uses exactly the
shape `GTM_Assessment_Gate__mdt.Predicate_JSON__c` uses — `{all: [...]}` /
`{any: [...]}` / `{field, op, value}`, with `op` one of
`eq ne lt lte gt gte in not_in`. That is deliberate: one grammar to learn, one
evaluator (`GtmPredicate`) to keep correct. A field with no answer makes its
clause **false**, so a branch whose input is unanswered simply does not fire.

**A predicate may only look backwards.** It may reference `source`, `target`, or
a slot at a **strictly lower position**. Build rule 8 enforces it. That is what
lets branching resolve in one pass in position order, and it is the only reason
the questionnaire (branching as the respondent answers) and the server
(branching from the finished answer map) are guaranteed to agree.

Predicates speak in **answer values** (the 1–4 option the respondent picked),
never in points. An author writes about the answer on the screen; what that
answer is worth is a separate decision they may retune without silently
rewiring every branch in the instrument.

## How the eight-slot invariant survives branching

This is the part to get right, because branching is the one feature that could
plausibly break comparability — two respondents answering different numbers of
questions produce totals that are not comparable at all.

- **Branches substitute; they never remove.** A `show_when` chooses *which*
  question fills a slot. Every slot has a default — the unconditional row — and
  a variant is built as a *copy of that resolved default with the variant's row
  merged over it* (`GtmAssessmentInstrument.buildVariants`). There is no
  authoring shape and no code path that yields a slot with no question.
- **Eight slots are always answered**, so every total is out of 32 and every
  band means the same thing on every path.
- **Only supplements are genuinely additive**, and they score into their own
  named index (`Supplement_Scores__c`), never into the 32.
- **Slots 1 and 8 cannot be branched away**, exactly as they cannot be
  substituted. Two locks: the build script, and `applyRow` in the resolver.
- The path taken is recorded on
  `GTM_Assessment_Request__c.Instrument_Branch_Path__c` — base slot key → variant
  key. `Instrument_Pair__c` says which pack; this says which path through it.

Four new build rules enforce all of the above:

| | Rule |
|---|---|
| 8 | A `show_when` references only `source`, `target`, or a strictly-earlier slot |
| 9 | At most one default per slot per pack; every variant has a unique `variant_key`, and two or more variants need `variant_order` |
| 10 | Authored points bottom at 1, top at 4, never descend |
| 11 | Every variant is **reachable** (some set of answers makes it the first match), and no two slots can ever resolve to the same key |

Rule 11 is the one that repays the effort: a variant shadowed by a broader
predicate above it is a question **nobody will ever be asked**, which on screen
is indistinguishable from a question that works. The script enumerates the
answers a slot's variants could see — every referenced field is 1–4, and rule 8
keeps the set small — and fails the build if any variant is never first.

## Previewing before you ship

The Instrument Editor's **Preview** tab walks the branches with the same module
the respondent's questionnaire uses (`c/gtmPredicate`), so it cannot agree with
itself and disagree with the form. Pick a source and target, answer as a
respondent, and it shows:

- which question filled each slot, and which branch fired;
- the running total out of 32, and the band once all eight are answered — with
  the band edges read from `GtmAssessmentInstrument.getFrame()` rather than from
  a copy in the component;
- the branch path exactly as the server would store it.

## Adding a pair — the whole procedure

1. `instrument/migration-accelerator/pairs/<source>__<target>.yaml`. Copy
   `hubspot__mcn.yaml`; it exercises every layer.
2. Declare `source`, `target` (canonical `Platform_Key__c` values, or `*`),
   `specificity`, the three postures, and a `posture_statement`.
3. Add `overrides` at the lowest layer that works. Every `rationale` cites file
   paths, and the build script fails if a cited path does not exist.
4. If the source platform is new, add an `GTM_Migration_Platform__mdt` record with
   its aliases and (optionally) a `Family_Key__c`.
5. `python3 scripts/build-instrument.py` — compiles the YAML into
   `force-app/main/default/customMetadata/GTM_Assessment_*`.
6. Deploy. No Apex change: nothing in Apex branches on a platform name, and
   nothing may start.

The build script enforces eleven rules, each of which exists because the
corresponding mistake is **silent** — the instrument still runs and still prints
a number:

1. Exactly 8 active slots resolve for every pair
2. Every option set has exactly 4 options, values 1–4, no gaps or duplicates
3. `substitute` requires a non-empty rationale and a substitutable slot
4. `max_attainable` requires a ceiling reason and a full four-option set
5. Every cited rationale path exists
6. A supplement key never collides with a dimension key
7. Gate predicates reference only declared fields
8. A `show_when` references only `source`, `target`, or a strictly-earlier slot
9. One default per slot; unique `variant_key`s; `variant_order` where it matters
10. Authored option points bottom at 1, top at 4, and never descend
11. Every branch variant is reachable, and no two slots can resolve to one key

Run it in CI as `python3 scripts/build-instrument.py --check`, which validates
and diffs without writing.

## Where the adaptive layer stores things

| Field on `GTM_Assessment_Request__c` | Holds |
|---|---|
| `Instrument_Pair__c` | DeveloperName of the pack that scored it. **Essential** — without it a stored `Section_Scores__c` blob becomes unreadable the moment a pack is edited |
| `Instrument_Version__c` | Which edition of that pack |
| `Supplement_Scores__c` | The layer-4 index, answers and verbatim notes, in their own field so they can never be summed into the 32 |
| `Instrument_Max_Score__c` | What the submission was scored **out of**, derived from the authored points at submit time. Always 32 in a healthy instrument; stored because points are editable and a total needs its maximum to stay readable |
| `Instrument_Branch_Path__c` | Which authored question filled each slot — base slot key → variant key. `Instrument_Pair__c` says which pack, this says which path through it |

`Section_Scores__c` already took arbitrary JSON keys, so a substituted slot id
stores with no migration.

## Two open decisions

### ⚠ [DECISION NEEDED] D-AMP — does AMPscript survive into Marketing Cloud Next?

Two curated sources in `ma-migrator` currently ship and contradict each other:

- `skills/mce-mcn-helper/references/framework-reference.md` says AMPscript
  **carries over** — "Core functions work… Data target changes from DE to DMO",
  and repeats it under *What Carries Over* as a talking point.
- `docs/specs/tier-2/sfmc-next-target-adapter.md` says it **does not exist** —
  `ampscript: false` ("critical delta vs classic"), `personalization.ampscript`
  unsupported, gap pattern `ampscript_block` at severity major.

Moot for HubSpot→MCN; **load-bearing for `sfmc__mcn`**, where it decides the
`content_portability` anchors and a callout. The product owner has been asked and
has not answered.

**Seeded position:** the adapter spec's — no AMPscript — because being wrong in
the optimistic direction costs the client money (a rebuild you did not budget for
is a mid-programme change request; one you budgeted for and did not need is a
refund). The callout carries `verification_required: true` so the readout hedges.

**Whoever resolves it: fix it in one place.** Either correct the framework
reference's row, or drop the callout and revert `sfmc__mcn`'s
`content_portability` to the base anchors. Both wordings must not ship live.

### `verification_required` across the MCN manifest

Many MCN capability assertions are working assumptions pending a real tenant —
branching limits, wait semantics, engagement split, SMS/push, random split. That
flag is carried from the manifest through the callout to the readout, which
renders "state this as our working model, not as a platform guarantee"
automatically. It is not a reminder for an author; it is the mechanism. When a
tenant confirms a capability, clear the flag in the pair YAML and rebuild.
