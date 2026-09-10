# ADR-0007 — The assessment instrument becomes per-offering, not a global singleton

**Status:** Accepted — implemented, phases 0-5, deployed to gtm-dev.

## Context

The assessment instrument — the eight scored readiness dimensions, the six
estate-complexity dimensions, branching pairs, gates, and layer-4
supplements that a prospect answers and that server-side Apex scores into a
tier — is today a **global singleton**, hardcoded end to end to Migration
Accelerator's content even though `GTM Offerings` is explicitly a
multi-offering platform (`GTM_Offering__mdt`, `GTM_Page_Content__c` /
`GTM_Page_Section__c`, and the GTM Content Manager app are all already
offering-scoped):

- None of the six instrument CMDT object definitions
  (`GTM_Assessment_Config__mdt`, `GTM_Assessment_Dimension_Override__mdt`,
  `GTM_Assessment_Gate__mdt`, `GTM_Assessment_Pair__mdt`,
  `GTM_Assessment_Question__mdt`, `GTM_Assessment_Supplement__mdt`) carry an
  offering field. Every record deployed today is implicitly Migration
  Accelerator's.
- The YAML source of truth (`migration-accelerator/instrument/*.yaml`,
  compiled by `scripts/build-instrument.py`) is a flat tree with no
  offering directory level, and its 14 validation rules assume exactly one
  instrument: 8 readiness slots, 6 complexity dimensions, a 1-4 / 1-3
  answer scale, and branching keyed specifically on a source/target
  **platform pair**.
- The scoring engine itself is compiled Apex, not data: `GtmAssessmentScoring`
  declares `DIMENSIONS` (the 8 keys), `MIN/MAX_ANSWER_VALUE`, the derived
  `MIN/MAX_TOTAL_SCORE`, the four `TIER_*` band edges, and two named-dimension
  override rules (`DIM_SOURCE_ACCESS`/`DIM_ORCHESTRATION`/`DIM_CONTENT` →
  `FLAG_HIGH_REBUILD_RATIO`) as `static final` constants. `GtmEstateComplexity`
  does the same for the complexity axis (`DIMENSIONS`, `MAX_ANSWER_VALUE`,
  `LIGHT_MAX`/`MODERATE_MAX`). Neither class takes an offering key. Adding a
  content-only CMDT filter would leave the frame itself (dimension count,
  answer scale, band edges) singleton no matter how the content is scoped.
- The read path, `GtmAssessmentInstrument.getPack(sourceName, targetName)`
  and its siblings (`resolve`, `resolveByPairKey`, `basePack`, `getFrame`,
  `getPlatforms`), takes no offering key and queries the six CMDT types
  unfiltered. Every caller — `GtmAssessmentRequestController.submitRequest`
  (guest submission scoring), `GtmReadoutModel.buildJson` (historical
  readout re-render via `resolveByPairKey`), the guest
  `gtmAssessmentQuestionnaire` LWC, and the internal `gtmInstrumentAuthor`
  LWC (the Instrument Editor) — inherits that blindness.
- `gtmInstrumentAuthor` already has a public `@api offeringKey =
  'migration-accelerator'` property, but it is a dead stub: nothing sets it
  from a selector UI, and it is never threaded into `getPack`/`getFrame`.
  There is no "choose an offering" control, unlike `gtmContentManager`
  (`GtmPageContentController.getOfferings()` → `@track offerings` →
  `<lightning-combobox>` → `selectedOffering` gates every subsequent call).
- The offering key already exists closer to the surface than expected:
  `GTM_Saved_Configuration__c.Offering__c` is resolved into
  `ConfigContext.offering` inside `GtmAssessmentRequestController` today,
  but is used only for deal naming and the annual-target lookup — it is
  never passed to `getPack`, `GtmAssessmentScoring.score`, or
  `GtmEstateComplexity.score`, and `GTM_Assessment_Request__c` has no
  `Offering_Key__c` field to persist it on. `GtmReadoutController.
  generateDraftReadout` independently re-derives the same offering key from
  `req.Saved_Configuration__r.Offering__c` (falling back to
  `'migration-accelerator'`) purely to stamp `GTM_Readout__c.Offering_Key__c`
  — the readout object is already offering-scoped; the assessment that
  produces it is not.
- `GTM_Migration_Platform__mdt` / `GTM_Migration_Pair__mdt` /
  `GtmMigrationPairs` (the *separate* "is this source→target platform move
  supported at all" eligibility gate, distinct from the adaptive
  instrument-content pairs above) is Migration Accelerator's own domain
  concept — a migration tool asking what platform a prospect is leaving.
  Nothing about it generalizes to an offering that isn't a migration.
- Real production data exists against today's global instrument:
  `GTM_Assessment_Request__c` has real submitted/scored records (the
  TD Bank, Medtronic, LA Metro, MUCH Music engagements — `docs/backlog.md`
  D10), all implicitly Migration Accelerator's, that must not be lost,
  orphaned, or silently rescored.

The user has confirmed the design direction (not re-litigated here):

1. **Fully independent per offering.** Each offering gets its own complete
   instrument — dimensions, questions, scoring, gates, branching. A second
   offering's instrument does not have to resemble Migration Accelerator's
   in shape, dimension count, or answer scale.
2. **Branching is offering-specific, not a framework-level "source/target
   platform pair" concept.** Migration Accelerator's platform-pair branching
   is one offering's authored choice, not something every offering inherits
   or must express the same way.

## Decision

> **Amended by [ADR-0009](0009-instrument-root-is-offering-neutral.md).**
> §2's *location* statement only — the instrument root moved from
> `migration-accelerator/instrument/` to a top-level `instrument/`, and the
> capability manifests moved to `reference/ma-migrator-capabilities/`.
> Everything else in this ADR remains fully in force: the per-offering
> directory model, `Offering_Key__c` stamping on all seven objects, the 14
> validation rules running within one offering directory, and the pair
> `name:` freeze. Note that §5's phase list at line 197 already wrote the
> post-ADR-0009 path; only the §2 diagram pinned the old root.

### 1. Offering scoping is a field, added to exactly seven objects

Add `Offering_Key__c` (`Text(80)`, description "Matches
`GTM_Offering__mdt.Offering_Key__c`" — the established convention, see
`GTM_Page_Content__c`/`GTM_Readout__c`/`GTM_Saved_Configuration__c`) to:

- `GTM_Assessment_Question__mdt`
- `GTM_Assessment_Dimension_Override__mdt`
- `GTM_Assessment_Pair__mdt`
- `GTM_Assessment_Gate__mdt`
- `GTM_Assessment_Supplement__mdt`
- `GTM_Assessment_Config__mdt` — **blank means "applies to every offering
  with no row of its own"** (the one deliberate exception; see below)
- `GTM_Assessment_Request__c` — a real transactional object, not CMDT; see
  §3 for why it is `required=false` despite the convention elsewhere being
  `required=true`.

`GTM_Migration_Platform__mdt` / `GTM_Migration_Pair__mdt` are **not**
touched — see §5.

### 2. The instrument YAML tree gets an offering directory level

```
instrument/                                          (framework-level root; relocated by ADR-0009)
    migration-accelerator/                            NEW directory, MA's content moved in verbatim
        dimensions.yaml
        complexity.yaml
        gates.yaml
        pairs/*.yaml
        supplements/*.yaml
    <second-offering-key>/                             a later offering, same shape
        dimensions.yaml
        ...
```

`scripts/build-instrument.py` iterates every subdirectory of
`instrument/` as an independent offering, running all
14 rules **within** each offering directory (never across two), and stamps
`Offering_Key__c` = the directory name onto every record it emits. An
offering's `pairs/` directory is optional — an offering that does not want
platform-pair-shaped branching authors a single `base.yaml` (source=`*`,
target=`*`) and never resolves anything else, or omits `pairs/` and
`supplements/` entirely if it wants no adaptive layer or layer-4 questions
at all. This is what makes requirement 2 real: the *mechanism* (a
resolution chain of `GTM_Assessment_Pair__mdt` rows, keyed by
`Source_Key__c`/`Target_Key__c`, and slot branching via
`Show_When_JSON__c` predicates over *any* earlier-answered slot, not
specifically "source"/"target") stays exactly as tested today, but no
offering is required to use more than the one `base` row it needs to.
Genuinely different branching (not two named platform keys but some other
early answer) already works through the same `Show_When_JSON__c`/variant
mechanism today, unchanged — it is not source/target-specific at the
predicate level, only Migration Accelerator's own pairs happen to key their
`Pair__mdt` rows on those two names.

**Constraint that must hold across the move:** every pair's `name:` field
(the value `build-instrument.py` derives every `GTM_Assessment_Pair__mdt`
and `GTM_Assessment_Dimension_Override__mdt` DeveloperName from) must be
copied verbatim. `Instrument_Pair__c` on every existing
`GTM_Assessment_Request__c` row is a stored DeveloperName
(`GtmAssessmentInstrument.resolveByPairKey`, used to re-render a historical
readout) — renaming a pair during the directory move breaks every already-
submitted assessment's ability to explain itself later. The move relocates
files; it must not edit their content.

The frame invariants the script hardcodes today (exactly 8 readiness slots,
exactly 6 complexity dimensions, a 1-4 / 1-3 answer scale, band edges
14/20/26) are **Migration Accelerator's frame, not the framework's**. A
second offering with a different dimension count or scale needs those
checks parameterized per offering directory rather than as the script's
global constants — see the open call in the companion plan file.

### 3. `GTM_Assessment_Request__c.Offering_Key__c` is populated by Apex, not authored, and stays `required=false`

`GtmAssessmentRequestController.recordAssessmentRequest` resolves the
offering key the same way `GtmReadoutController.generateDraftReadout`
already independently does — from `ctx.offering`
(`GTM_Saved_Configuration__c.Offering__c`), falling back to
`'migration-accelerator'` for a direct booking with no linked
configuration — and stores it on the request at insert time. Unlike
`GTM_Readout__c.Offering_Key__c` (`required=true`, safe because that object
had no live rows when the field was introduced),
`GTM_Assessment_Request__c` already holds real production data. Marking
the new field `required=true` in the same deploy that introduces it is the
kind of "looks fine, quietly breaks something real" risk CLAUDE.md's other
gotchas describe (duplicate rules, FLS gaps) — deploy it as
`required=false`, backfill (§4), verify zero blanks, and leave it
`required=false` permanently: Apex always populates it on every insert
path, so a schema-level requirement is redundant enforcement bought at real
deploy risk for no behavioral gain.

`GtmReadoutController.generateDraftReadout` is changed to **read**
`req.Offering_Key__c` instead of re-deriving it from
`Saved_Configuration__r.Offering__c` — one offering key, set once, at the
point the request was actually scored, rather than two independent
derivations of "probably the same thing" that could in principle disagree
if a link's `Offering__c` were edited between submission and readout
generation. `GtmReadoutModel.buildJson` passes `req.Offering_Key__c` into
`GtmAssessmentInstrument.resolveByPairKey` so a re-rendered historical
readout resolves against the same offering's pair table, not whichever
offering happens to be "current."

### 4. Existing data is backfilled, never rebuilt or reset

Deployed CMDT records (`GTM_Assessment_Question__mdt`: 14,
`GTM_Assessment_Pair__mdt`: 6, `GTM_Assessment_Dimension_Override__mdt`: 34,
`GTM_Assessment_Gate__mdt`: 3, `GTM_Assessment_Supplement__mdt`: 12,
`GTM_Assessment_Config__mdt`: 1) are all build artifacts or CMDT records
already fully described in source — moving Migration Accelerator's YAML
into `instrument/migration-accelerator/` and rebuilding via
`scripts/build-instrument.py` regenerates every one of them with
`Offering_Key__c = 'migration-accelerator'` populated, and the normal
`scripts/deploy.sh` metadata deploy overwrites the org's copies. This is
configuration redeploy through the path this repo already uses for every
instrument change — not a data migration.

The one real data migration is `GTM_Assessment_Request__c`: a one-time,
idempotent Apex script (in the shape of
`scripts/data/migrate-assessment-link-form-to-gtm.apex`) sets
`Offering_Key__c = 'migration-accelerator'` on every existing row where the
field is blank, after the field itself has deployed and before anything
downstream (readout re-render, the Instrument Editor) is exercised against
production. It touches only the new field; nothing else on any request row
changes, and no row's score, tier, or answers are recomputed. See the
companion plan file for the exact script and verification query.

### 5. `GtmMigrationPairs` / `GTM_Migration_Platform__mdt` / `GTM_Migration_Pair__mdt` stay Migration-Accelerator-only, unscoped

This is a *different* concept from the adaptive instrument content above —
"can the accelerator process this platform move at all," not "which
questions does this pair ask." It is a Migration Accelerator business rule
with no equivalent in an offering that isn't a migration. Rather than
inventing a generalization nothing needs yet, `GtmAssessmentRequestController.
resolvePairEligibility` is gated to run only when `offeringKey ==
'migration-accelerator'`; every other offering gets the same inert,
non-evaluated `PairEligibility` the whole system already fails open to when
pair metadata is absent. The two `GTM_Migration_*__mdt` types are untouched
— no `Offering_Key__c`, no directory move, no script change.

### 6. `GtmAssessmentScoring` and `GtmEstateComplexity` stop being compiled singletons

To honor "does not have to resemble Migration Accelerator's at all," the
scoring frame itself — not just its content — becomes offering-scoped data,
not a compiled constant. A new CMDT type,
`GTM_Assessment_Frame__mdt` (`Offering_Key__c`, `Min_Answer_Value__c`,
`Max_Answer_Value__c`, `Bands_JSON__c`, `Complexity_Min_Answer_Value__c`,
`Complexity_Max_Answer_Value__c`, `Complexity_Bands_JSON__c`), holds one
record per offering. `GtmAssessmentScoring.score(...)` and
`GtmEstateComplexity.score(...)` take an `offeringKey`, read that offering's
frame record, and — for `offeringKey == 'migration-accelerator'`, or any
offering with no frame record deployed yet — fall back to exactly today's
hardcoded constants (8 slots, 1-4, 14/20/26; 6 dimensions, 1-3, 9/13). This
is the same fail-open discipline `GtmAssessmentInstrument.resolve` already
uses for a missing pack, applied one layer down. The two named-dimension
override rule (`DIM_SOURCE_ACCESS`/`DIM_ORCHESTRATION`/`DIM_CONTENT` →
`FLAG_HIGH_REBUILD_RATIO`) is judged to be genuine Migration Accelerator
business judgment, not generic config, and is **not** promoted to data — it
stays Apex, dispatched only for `offeringKey == 'migration-accelerator'`. A
future offering wanting an equivalent "annotate without touching the
number" already has the generic mechanism for that: a
`GTM_Assessment_Gate__mdt` row (`Predicate_JSON__c` + `GtmPredicate`), which
was built generic from the start for exactly this purpose. Full detail and
the interface shape are in the companion plan file.

## Consequences

- Every one of the six read-path Apex entry points on
  `GtmAssessmentInstrument`, both scoring classes, and every caller
  (`GtmAssessmentRequestController`, `GtmReadoutModel`,
  `GtmReadoutController`, `gtmAssessmentQuestionnaire`, `gtmInstrumentAuthor`
  and its Apex controller) gains a required `offeringKey` parameter. This
  is a wide, mechanical change with a large test-file blast radius
  (`GtmAssessmentInstrumentTest`, `GtmAssessmentScoringTest`,
  `GtmEstateComplexityTest`, `GtmAssessmentRequestControllerTest`,
  `GtmAssessmentReadoutTest`, `GtmReadoutModelTest`, both LWC Jest suites) —
  sized accordingly in the companion plan, not attempted as one commit.
- `scripts/build-instrument.py`'s 14 rules run per-offering-directory. Its
  currently-hardcoded frame constants (8 slots, 6 complexity dimensions,
  1-4/1-3 scale, 14/20/26 band edges) need to become per-offering-read
  rather than global Python constants before a second offering with a
  genuinely different shape can be authored — flagged as an open
  implementation call in the plan, not fully resolved by this ADR.
  Migration Accelerator's own instrument is unaffected either way, since
  its directory keeps exactly the values the constants have today.
  `GTM_Assessment_Question__mdt` base-wording rows stay hand-authored CMDT
  XML per offering (the existing "reword in Setup, deploy nothing"
  convention) rather than becoming YAML-generated — a second offering's
  content author hand-writes its base question rows the same way
  Migration Accelerator's are maintained today; `build-instrument.py`
  continues to only *read* them for cross-validation, never write them.
- `GTM_Assessment_Config__mdt` moves from one universal record to a
  precedence chain (offering-specific row wins, blank `Offering_Key__c` is
  the fallback) — mirrors `GtmPageContentController`'s
  industry-then-offering-default precedence exactly, and is zero-risk for
  the existing single `Default` record, which simply becomes the
  fallback by staying blank.
- Once this lands, D11 (`docs/backlog.md` — the live booking flow sends no
  scored `answers` array) changes shape slightly: whichever fix is chosen
  must also thread the booking flow's offering key (already resolvable
  from the engagement link's `GTM_Saved_Configuration__c.Offering__c`, the
  same `ctx.offering` this ADR's changes already read) into
  `submitRequest`/`getPack`, or a fixed D11 would submit real answers
  against the wrong offering's instrument. This ADR does not fix D11; it
  changes what "fixed" has to include.
- Two implementation details were not fully determined by the two
  confirmed answers and are called out explicitly as open calls in the
  companion plan: (1) whether `build-instrument.py`'s hardcoded frame
  constants become per-offering-directory-read now or are deferred until a
  second offering actually needs a different shape, and (2) whether a
  second offering's base question wording stays hand-authored CMDT XML
  (this ADR's default) or gets a YAML-generation path added to the build
  script.
