> **ARCHIVED:** Superseded by
> `docs/architecture/adr/0009-instrument-root-is-offering-neutral.md`
> (Status: Accepted — implemented). The end-state this plan describes has
> landed in the tree; ADR-0009 is the authoritative record. Kept here only
> for historical paper trail.

# Per-offering assessment instrument — implementation plan

Companion to `docs/architecture/adr/0007-assessment-instrument-becomes-per-offering.md`.
That ADR has the "why" and the full design reasoning; this file has the
file-by-file "how," in the order a Dev agent should do it, plus the QA
verification protocol. Read the ADR first.

**Scope guardrails, carried over from the architect session:**
- `GTM_Migration_Platform__mdt` / `GTM_Migration_Pair__mdt` / `GtmMigrationPairs`
  are **not touched** anywhere below — see ADR-0007 §5.
- Every step touching `force-app/main/default/permissionsets/` is part of
  the same commit as the field it grants, per ADR-0002 / CLAUDE.md §5.1 —
  not a follow-up.
- Nothing here runs against `gtm-dev` except through `scripts/deploy.sh`
  (or an explicit `--dry-run`) and the one data-backfill script called out
  in Phase 3. `gtm-dev` is production (CLAUDE.md §1).
- D11 (`docs/backlog.md`) is out of scope. Don't fix it. Phase 6 below
  notes the one place a future D11 fix needs to know about this work.

---

## Phase 0 — New schema, before anything reads or writes it

Order matters only in that the **fields must exist and deploy cleanly**
before any Apex in Phase 2 references them, and the **CMDT fields must
deploy before `scripts/build-instrument.py` is asked to emit values into
them**.

### 0.1 New field: `Offering_Key__c` on the five content CMDT types

Add, in each of:
- `force-app/main/default/objects/GTM_Assessment_Question__mdt/fields/`
- `force-app/main/default/objects/GTM_Assessment_Dimension_Override__mdt/fields/`
- `force-app/main/default/objects/GTM_Assessment_Pair__mdt/fields/`
- `force-app/main/default/objects/GTM_Assessment_Gate__mdt/fields/`
- `force-app/main/default/objects/GTM_Assessment_Supplement__mdt/fields/`

`Offering_Key__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Offering_Key__c</fullName>
    <label>Offering Key</label>
    <description>Which GTM offering this instrument row belongs to (e.g.
        migration-accelerator). Matches GTM_Offering__mdt.Offering_Key__c.
        Every row of this type belongs to exactly one offering -- there is
        no blank/shared fallback here, unlike GTM_Assessment_Config__mdt.
    </description>
    <required>true</required>
    <length>80</length>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

### 0.2 New field: `Offering_Key__c` on `GTM_Assessment_Config__mdt` — blank-is-default variant

Same file shape, in
`force-app/main/default/objects/GTM_Assessment_Config__mdt/fields/`, but
**`required=false`** and the description says what blank means:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Offering_Key__c</fullName>
    <label>Offering Key</label>
    <description>Which offering this config row applies to. Blank means
        "the default for every offering with no row of its own" -- the
        existing GTM_Assessment_Config.Default record stays blank and
        becomes that fallback. Matches GTM_Offering__mdt.Offering_Key__c.
    </description>
    <required>false</required>
    <length>80</length>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

No change to `GTM_Assessment_Config.Default.md-meta.xml` itself — leaving
`Offering_Key__c` unset on that record *is* the fallback design; do not add
a value to it.

### 0.3 New field: `Offering_Key__c` on `GTM_Assessment_Request__c`

`force-app/main/default/objects/GTM_Assessment_Request__c/fields/Offering_Key__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Offering_Key__c</fullName>
    <label>Offering Key</label>
    <description>Which GTM offering this assessment was scored against.
        Set once, server-side, at insert -- never client-supplied. Matches
        GTM_Offering__mdt.Offering_Key__c. Deliberately required=false: this
        object already holds real production rows with no value here yet;
        see the backfill script in Phase 3 and ADR-0007 SS3 for why this
        stays optional at the schema level rather than being flipped to
        required after backfill.
    </description>
    <required>false</required>
    <length>80</length>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

### 0.4 New CMDT type: `GTM_Assessment_Frame__mdt`

One record per offering; fallback to Migration Accelerator's hardcoded
constants when no record exists for a given offering (or for
`migration-accelerator` itself — do not create a `migration-accelerator`
frame record in this phase; the Apex fallback path is exercised and
verified precisely by its *absence*, see QA §2).

`force-app/main/default/objects/GTM_Assessment_Frame__mdt/GTM_Assessment_Frame__mdt.object-meta.xml`
— follow the existing `GTM_Assessment_Gate__mdt.object-meta.xml` as the
template for the wrapper (label, plural label, deployment status, etc).

Fields, each its own file under `.../fields/`:

| Field | Type | Required | Notes |
|---|---|---|---|
| `Offering_Key__c` | Text(80) | true | matches `GTM_Offering__mdt.Offering_Key__c` |
| `Min_Answer_Value__c` | Number(2,0) | true | replaces `GtmAssessmentScoring.MIN_ANSWER_VALUE` |
| `Max_Answer_Value__c` | Number(2,0) | true | replaces `MAX_ANSWER_VALUE` |
| `Bands_JSON__c` | Long Text Area(4096) | true | `[{"tier":"...","lowest":N,"highest":N}, ...]`, ascending, contiguous, replaces `GtmAssessmentScoring.bands()` |
| `Complexity_Min_Answer_Value__c` | Number(2,0) | false | blank = this offering has no complexity axis at all |
| `Complexity_Max_Answer_Value__c` | Number(2,0) | false | |
| `Complexity_Bands_JSON__c` | Long Text Area(4096) | false | same shape as `Bands_JSON__c` |

### 0.5 Permission-set grants (same commit as 0.1-0.4, per ADR-0002)

Re-run `grep -l "getGlobalDescribe\|Database.query" force-app/main/default/classes/*.cls`
first per CLAUDE.md §5.4 to reconfirm the dynamic-Apex list hasn't drifted,
then:

- Add a `fieldPermissions` block for
  `GTM_Assessment_Request__c.Offering_Key__c` to
  `force-app/main/default/permissionsets/GTM_Config_Manager.permissionset-meta.xml`,
  `readable=true`, `editable=false` (system-set, matches the pattern
  already used for `Assessment_Score__c`, `Instrument_Pair__c`, etc. — see
  the block starting at line ~636 of that file).
- `GTM_Config_View_All` currently grants **no** `GTM_Assessment_Request__c`
  field permissions at all (confirmed by inspection — it's scoped to a
  different object set). Do not add one there unless a Dev-phase check of
  the org shows a real user relying on that permission set to view
  assessment requests; if so, mirror the same grant.
- The six CMDT types have never had permission-set field entries anywhere
  in this repo (confirmed: zero matches for any of the six object names
  across all five permission sets) — Apex reads them via plain SOQL with no
  `WITH SECURITY_ENFORCED`/`stripInaccessible`, so FLS has never gated
  them. Do **not** add grants for `Offering_Key__c` on the five CMDT types
  or on `GTM_Assessment_Frame__mdt` — doing so would be inconsistent with
  every other field on those same objects and adds diff noise with no
  effect. This is a deliberate exception to the "grant every new field"
  default, reasoned from what's actually in the repo today, not an
  oversight — say so in the PR description so a reviewer doesn't add it
  back reflexively.
- `GTM_Assessment_Guest` / `GTM_Story_Guest` / `GTM_Platform_Visibility`:
  confirm no new object/tab is being introduced that these need (they
  aren't — `GTM_Assessment_Frame__mdt` is read only from `with sharing`
  internal Apex, never from a guest context). No changes expected; verify
  by grepping the same way as CLAUDE.md §5.1 documents, don't just assume.

### 0.6 Deploy and verify Phase 0 in isolation

```bash
sf project deploy start --source-dir force-app/main/default/objects/GTM_Assessment_Question__mdt \
  --source-dir force-app/main/default/objects/GTM_Assessment_Dimension_Override__mdt \
  --source-dir force-app/main/default/objects/GTM_Assessment_Pair__mdt \
  --source-dir force-app/main/default/objects/GTM_Assessment_Gate__mdt \
  --source-dir force-app/main/default/objects/GTM_Assessment_Supplement__mdt \
  --source-dir force-app/main/default/objects/GTM_Assessment_Config__mdt \
  --source-dir force-app/main/default/objects/GTM_Assessment_Request__c \
  --source-dir force-app/main/default/objects/GTM_Assessment_Frame__mdt \
  --source-dir force-app/main/default/permissionsets \
  --target-org gtm-dev --dry-run
```
then the same without `--dry-run`. Confirm via
`sf data query -q "SELECT COUNT() FROM GTM_Assessment_Request__c WHERE Offering_Key__c = null" --target-org gtm-dev`
that the count equals today's total row count (i.e. the field deployed
with every existing row blank, nothing defaulted unexpectedly).

---

## Phase 1 — YAML restructure + `build-instrument.py`

### 1.1 Move Migration Accelerator's content into its own directory

> **Historical record of a completed phase.** The paths below are written in
> their post-ADR-0009 form so this section does not teach a layout that no
> longer exists. The instrument root has since moved out of
> `migration-accelerator/` to a top-level `instrument/` (ADR-0009); when this
> phase was actually executed the root was still the doubled
> `migration-accelerator/instrument/`.

```
git mv instrument/dimensions.yaml    instrument/migration-accelerator/dimensions.yaml
git mv instrument/complexity.yaml    instrument/migration-accelerator/complexity.yaml
git mv instrument/gates.yaml         instrument/migration-accelerator/gates.yaml
git mv instrument/pairs              instrument/migration-accelerator/pairs
git mv instrument/supplements        instrument/migration-accelerator/supplements
```

**Do not edit file contents in this step.** In particular, do not touch any
`name:` field inside `pairs/*.yaml` — see ADR-0007 §2's constraint on
`Instrument_Pair__c` continuity. A follow-up commit may reformat/reword
content; this one only moves files.

### 1.2 `scripts/build-instrument.py` changes

- `INSTRUMENT` (currently the flat directory) becomes the parent; add
  `offering_dirs()` = every immediate subdirectory of `INSTRUMENT`
  containing a `dimensions.yaml` (so a stray non-offering file at the old
  flat location, if any survives, doesn't get treated as an offering).
- `main()`'s body (frame load through pair/gate resolution) runs once per
  offering directory, in its own scope, with `errors`/`warnings` still
  global but every `fail()`/`warn()` message prefixed with the offering key
  so a failure is traceable to the right offering
  (`fail("%s/dimensions.yaml" % offering_key, ...)` pattern, or a `where`
  prefix helper).
- `base_questions()` (currently scans **all** `GTM_Assessment_Question.*`
  files in `CMD_DIR` with no offering filter) must filter to the rows whose
  `Offering_Key__c` value (now present on every emitted/hand-authored
  Question record — see Phase 2 for the hand-authored ones) matches the
  offering directory currently being validated. Read the new field the
  same way `Dimension_Key__c` is read today (`vals.get("Offering_Key__c")`).
- Every `record(...)` call for `GTM_Assessment_Pair`,
  `GTM_Assessment_Dimension_Override`, `GTM_Assessment_Supplement`,
  `GTM_Assessment_Gate` gains one more field in its `fields` list:
  `("Offering_Key__c", offering_key)`.
- The `existing = {...}` / stale-file cleanup logic (`main()`, near the
  bottom) already scans all four CMDT type prefixes across `CMD_DIR`
  regardless of offering — this is correct as-is and needs no change: a
  file that no longer appears in `out` (because its offering's YAML no
  longer emits it) is still correctly identified as stale and removed,
  now across *all* offerings' emitted files, not just one's.

**Open call, flagged in ADR-0007, not resolved by this plan:** Rules 1, 2,
9, 10, 11 and 12 hardcode Migration Accelerator's frame (`len(slots) != 8`,
`expect_max=4`, `COMPLEXITY_DIMENSION_COUNT = 6`,
`COMPLEXITY_MAX_ANSWER = 3`, the `COMPLEXITY_BANDS` tuple, etc.) as **global
Python constants**, not per-offering-directory values. Migration
Accelerator's own directory needs these to stay exactly as they are today —
no behavior change for the only offering that exists. A **second** offering
with a different slot count or answer scale needs these read per-offering
(most naturally: from that offering's own `dimensions.yaml`/`complexity.yaml`
`slots`/`dimensions` list length and each option set's own `expect_max`,
already present in the YAML — the constants mostly exist as a
cross-check against `GTM_Assessment_Frame__mdt`, described in Phase 2.4,
which is the actual source of truth once it exists). Do not attempt this
generalization speculatively in this phase — do it when a real second
offering is authored, against its real shape, so the generalization is
proven against an actual case rather than guessed. Leave a comment at each
hardcoded constant pointing at this plan file and ADR-0007 §2/Consequences
so the next author who opens a second offering directory knows exactly
what has to change and why it wasn't done here.

### 1.3 Rebuild and verify

```bash
python3 scripts/build-instrument.py
git diff --stat force-app/main/default/customMetadata/GTM_Assessment_*.md-meta.xml
```
Expect: every existing `GTM_Assessment_Pair.*`, `GTM_Assessment_Dimension_Override.*`,
`GTM_Assessment_Supplement.*`, `GTM_Assessment_Gate.*` file gains exactly
one new `<values><field>Offering_Key__c</field><value ...>migration-accelerator</value></values>`
block and is otherwise byte-identical. If anything else changed, stop and
find out why before proceeding — the move must be content-neutral except
for the new field.
```bash
python3 scripts/build-instrument.py --check   # must exit 0 a second time
```

---

## Phase 2 — Apex: the read path

Order within this phase: bottom-up (the classes with no Apex-internal
callers first), since each step's tests need the layer below it already
compiling.

### 2.1 `GTM_Assessment_Question__mdt` hand-authored rows get `Offering_Key__c` too

The 14 existing `GTM_Assessment_Question.*.md-meta.xml` files are
hand-authored directly (not YAML-generated — `build-instrument.py` only
*reads* them, per its `base_questions()` docstring). Add
`<values><field>Offering_Key__c</field><value xsi:type="xsd:string">migration-accelerator</value></values>`
to each of the 14 by hand. This is a one-time, mechanical edit — do not
route it through the build script, which does not own this object's
records and should not start now (that would be a larger, separate change
to the authoring convention — see ADR-0007's second open call).

### 2.2 `GtmAssessmentScoring.cls` — frame becomes offering-parameterized

- `DIMENSIONS`, `MIN_ANSWER_VALUE`, `MAX_ANSWER_VALUE`, `MAX_TOTAL_SCORE`,
  `MIN_TOTAL_SCORE`, `TIER_*`, `TIERS`, `DISCOVERY_FIRST_MAX`/
  `PREP_REQUIRED_MAX`/`ACCELERATOR_READY_MAX` stay exactly as-is, renamed
  in comments to "the migration-accelerator fallback frame" rather than
  "the frame" — they become the fail-open default, not the only frame.
- New: `private static GTM_Assessment_Frame__mdt frameFor(String offeringKey)`
  — queries `GTM_Assessment_Frame__mdt` by `Offering_Key__c`, per-transaction
  cached in a `Map<String, GTM_Assessment_Frame__mdt>` (mirrors the existing
  `cachedPairs`/etc. pattern in `GtmAssessmentInstrument`), returns `null`
  on no match or any exception (fail-open, consistent with every other
  method in this file).
- `score(...)` gains a leading `String offeringKey` parameter. Internally,
  wherever it currently reads `MAX_ANSWER_VALUE`/`bands()`/etc. directly, it
  resolves through a small local struct built from `frameFor(offeringKey)`
  when present, else the existing constants. `bands()` becomes
  `bands(String offeringKey)`; keep a zero-arg `bands()` overload that calls
  `bands('migration-accelerator')` so `GtmAssessmentInstrument.getFrame()`
  (the content-authoring preview, called with no offering context today —
  see 2.4) has a non-breaking path during this phase, removed once 2.4 wires
  it through properly.
- `DIM_SOURCE_ACCESS`/`DIM_ORCHESTRATION`/`DIM_CONTENT`/
  `FLAG_HIGH_REBUILD_RATIO` and the rebuild-ratio annotation logic inside
  `score(...)` (the block reading `resolvedKeyFor(pack, DIM_SOURCE_ACCESS)`
  etc.) get wrapped in `if ('migration-accelerator'.equalsIgnoreCase(offeringKey))`.
  Every other offering skips this annotation entirely — it is not
  generalized, per ADR-0007 §6.
- Update `GtmAssessmentScoringTest.cls`: every existing call site gains
  `'migration-accelerator'` as the new first argument (preserves every
  existing assertion unchanged); add new test(s) proving `frameFor` fail-open
  behavior — an offering key with no `GTM_Assessment_Frame__mdt` row falls
  back to the compiled constants, and a deliberately malformed
  `Bands_JSON__c` also falls back rather than throwing.

### 2.3 `GtmEstateComplexity.cls` — same treatment, second axis

Same shape as 2.2: `DIMENSIONS`/`MAX_ANSWER_VALUE`/`LIGHT_MAX`/`MODERATE_MAX`
stay as the migration-accelerator fallback; `score(...)` gains
`offeringKey`; a `frameFor` (or shared helper with 2.2 — consider one
shared `GtmAssessmentFrames.cls` utility read by both, to avoid duplicating
the CMDT query/cache/fallback logic in two classes — **recommended**, not
mandatory) resolves `Complexity_*` fields from the same
`GTM_Assessment_Frame__mdt` record. Update `GtmEstateComplexityTest.cls`
the same way as 2.2.

### 2.4 `GtmAssessmentInstrument.cls` — the resolution engine

- `getPack`, `resolve`, `resolveByPairKey`, `basePack`, `getFrame` all gain
  a leading `String offeringKey` parameter — no default, no overload
  without it; every caller in this phase is updated in the same commit, so
  a compile-time-enforced "you must decide the offering" is preferable to
  a silently-defaulting overload that could paper over a caller nobody
  updated. `getPlatforms()` is the one exception: it reads
  `GTM_Migration_Platform__mdt`, which per ADR-0007 §5 stays unscoped and
  Migration-Accelerator-only, and is left exactly as-is.
- `pairRows()`, `overridesByPair()`, `supplementsFor(setKeys)`, `gates()`
  each gain `offeringKey` and add `WHERE Offering_Key__c = :offeringKey` to
  their SOQL. The `cachedPairs`/`cachedOverrides`/`cachedSupplements`/
  `cachedGates` static fields become `Map<String, List<...>>` keyed by
  offering (a single guest or admin transaction should never need two
  offerings' data, but keying by offering costs nothing and removes any
  chance of one offering's resolve serving another's cached rows within a
  batched admin preview).
- The `@TestVisible` override fields (`pairOverride`, `overrideOverride`,
  `supplementOverride`, `gateOverride`) stay flat lists, **not** offering-
  keyed — a test that sets an override intends it to apply regardless of
  which offering key the test then calls `resolve` with. Don't over-engineer
  this; it's existing test-fixture plumbing, not production behavior.
- `baseSlots()`/`baseComplexity()` currently build from
  `GtmAssessmentScoring.DIMENSIONS`/`GtmEstateComplexity.DIMENSIONS` with no
  offering awareness — thread `offeringKey` through to these too once 2.2/2.3
  land, so a non-migration-accelerator offering's base frame reflects its
  own `GTM_Assessment_Frame__mdt` record rather than always starting from
  Migration Accelerator's 8/6.
- `getFrame()` (the authoring-preview endpoint,
  `@AuraEnabled(cacheable=true)`) gains `offeringKey` and calls
  `GtmAssessmentScoring.bands(offeringKey)` (drop the temporary zero-arg
  overload from 2.2 once this lands).
- Update `GtmAssessmentInstrumentTest.cls`: every call site gains
  `'migration-accelerator'`; add a fixture offering (any key that is not
  `'migration-accelerator'`, e.g. `'test-offering'`) with its own minimal
  `pairOverride`/`overrideOverride` set via the `@TestVisible` setters and
  prove `resolve('test-offering', ...)` never returns any row whose
  `Offering_Key__c` (if inspectable) or content matches
  `'migration-accelerator'`'s fixtures — this is the unit-level half of the
  isolation proof QA repeats end-to-end in Phase 5.

### 2.5 `GtmAssessmentRequestController.cls`

- `loadConfig()` gains `offeringKey`, queries
  `GTM_Assessment_Config__mdt WHERE Offering_Key__c = :offeringKey OR Offering_Key__c = null ORDER BY Offering_Key__c NULLS LAST LIMIT 1`
  (an offering-specific row wins over the blank fallback — mirrors
  `GtmPageContentController.getPageContent`'s industry-then-default
  precedence exactly, including the `NULLS LAST` idiom already used there).
  `DEFAULT_CONFIG` (`'Default'`, matched by `DeveloperName` today) is no
  longer how the fallback is found — the query now finds it by blank
  `Offering_Key__c`, not by name; the constant can be removed or repurposed
  as a comment-only reference to the record's `DeveloperName`.
- Add `private static String resolveOfferingKey(ConfigContext ctx)` →
  returns `ctx.offering` when non-blank, else `'migration-accelerator'`
  (verbatim copy of `GtmReadoutController.generateDraftReadout`'s existing
  inline expression — factor it out and have `GtmReadoutController` call
  the same helper if that's a reasonable shared home, otherwise duplicate
  the one-liner; either is fine, don't force a cross-class dependency for
  one ternary).
- `submitRequest`: call `resolveOfferingKey(ctx)` once, thread the result
  into `loadConfig(offeringKey)`.
- `recordAssessmentRequest`: thread the same `offeringKey` into
  `resolveInstrumentPack` → `GtmAssessmentInstrument.getPack(offeringKey, ...)`,
  `GtmAssessmentScoring.score(offeringKey, ...)`,
  `GtmEstateComplexity.score(offeringKey, ...)`, and set
  `req.Offering_Key__c = offeringKey` on the new `GTM_Assessment_Request__c`
  before insert. Also replace the hardcoded `Source__c = 'Migration Accelerator'`
  literal a few lines above it — either leave it as a literal (it is a
  *display* label for where the request came from, arguably legitimately
  MA-specific copy today) or thread the offering's label through
  (`GTM_Offering__mdt.Label__c`) if a second offering will submit through
  this same controller before `Source__c` gets its own design pass. Flag
  this specific line for the Dev agent to make a judgment call on, rather
  than pre-deciding it here — it's copy, not schema, and lower-risk either
  way.
- `resolvePairEligibility`: wrap the existing body in
  `if (!'migration-accelerator'.equalsIgnoreCase(offeringKey)) { return new GtmAssessmentScoring.PairEligibility(); }`
  at the top, per ADR-0007 §5.
- Update `GtmAssessmentRequestControllerTest.cls`: existing MA-flow tests
  need no behavior change (offering resolves to `'migration-accelerator'`
  via the same fallback path they exercise today); add one test that sets
  `GTM_Saved_Configuration__c.Offering__c` to a non-MA value on the linked
  config and asserts the resulting `GTM_Assessment_Request__c.Offering_Key__c`
  matches it and that `resolvePairEligibility` returned the inert/
  not-evaluated result for that path.

### 2.6 `GtmReadoutController.cls` / `GtmReadoutModel.cls`

- `GtmReadoutController.generateDraftReadout`: replace the
  `offeringKey = req.Saved_Configuration__r != null && ... ? ... : 'migration-accelerator'`
  derivation with `String offeringKey = String.isNotBlank(req.Offering_Key__c) ? req.Offering_Key__c : 'migration-accelerator';`
  and confirm `Offering_Key__c` is in the SOQL that loads `req` for this
  method (add it to the `SELECT` list if it isn't already covered by a
  `SELECT ... FROM GTM_Assessment_Request__c` elsewhere in the same
  method/class).
- `GtmReadoutModel.buildJson(req)`: at the `resolveByPairKey` call site,
  change to `GtmAssessmentInstrument.resolveByPairKey(offeringKeyOf(req), req.Instrument_Pair__c)`
  where `offeringKeyOf(req)` is the same blank-falls-back-to-MA expression
  (small local helper, or reuse 2.5's `resolveOfferingKey` if `buildJson`
  can reasonably take a `GTM_Assessment_Request__c` with `Offering_Key__c`
  already queried — confirm the SOQL that loads `req` for readout building
  includes the new field).
- Update `GtmAssessmentReadoutTest.cls` / `GtmReadoutModelTest.cls`: same
  mechanical `offeringKey` threading; add one test rendering a readout from
  a request whose `Offering_Key__c` is blank (simulating a pre-backfill or
  legacy row) and asserting it still resolves via the `'migration-accelerator'`
  fallback rather than erroring — this is the regression guard for Phase 3's
  backfill assumption.

---

## Phase 3 — Data backfill (the one live-data-risk step)

Run **after** Phase 0 is deployed and **before** Phase 2's Apex (which
starts relying on `Offering_Key__c` being populated for existing rows,
e.g. in `GtmReadoutController`) goes live, or immediately after Phase 2
deploys and before any user exercises the readout-regeneration path against
an old request — either ordering is safe given the fallback in 2.6, but
running the backfill promptly removes any window where it matters.

`scripts/data/backfill-assessment-offering-key.apex` (new file, follow the
header/comment style of `scripts/data/migrate-assessment-link-form-to-gtm.apex`):

```apex
// One-time backfill: every GTM_Assessment_Request__c row submitted before
// Offering_Key__c existed was, in practice, Migration Accelerator's --
// it is the only offering that has ever been assessed (see ADR-0007).
// Idempotent: only touches rows where the field is still blank, so running
// it twice, or after Phase 2's Apex has already started setting it on new
// rows, is safe.
List<GTM_Assessment_Request__c> toFix = [
    SELECT Id FROM GTM_Assessment_Request__c
    WHERE Offering_Key__c = null
];
System.debug('Backfilling ' + toFix.size() + ' request(s).');
for (GTM_Assessment_Request__c r : toFix) {
    r.Offering_Key__c = 'migration-accelerator';
}
if (!toFix.isEmpty()) {
    Database.update(toFix, false);
}
```

Run: `sf apex run --file scripts/data/backfill-assessment-offering-key.apex --target-org gtm-dev`.

**Verification (do this, don't just trust the script ran):**
```bash
sf data query -q "SELECT COUNT() FROM GTM_Assessment_Request__c WHERE Offering_Key__c = null" --target-org gtm-dev
# must return 0
sf data query -q "SELECT Offering_Key__c, COUNT(Id) cnt FROM GTM_Assessment_Request__c GROUP BY Offering_Key__c" --target-org gtm-dev
# must show exactly one bucket: migration-accelerator, count == total row count
```
Nothing else about these rows changes — no score, tier, answer, or
timestamp is touched. This is the data-preservation guarantee the task
required; verify it by also diffing `Assessment_Score__c`/`Assessment_Tier__c`/
`Section_Scores__c` before and after on a couple of the real named accounts
(TD Bank, Medtronic, LA Metro, MUCH Music — `docs/backlog.md` D10) to prove
the backfill script touched only the one field it claims to.

---

## Phase 4 — `gtmInstrumentAuthor` LWC + its Apex controller(s)

### 4.1 Add the offering selector, following `gtmContentManager`'s exact pattern

- Reuse `GtmPageContentController.getOfferings()` as-is (it already returns
  `{offeringKey, label, publicUrl}` with the framework entry first — the
  Instrument Editor has no use for a "framework" pseudo-offering, so filter
  it out client-side: `rows.filter(o => o.offeringKey !== 'gtm')`, matching
  `GtmPageContentController.FRAMEWORK_KEY`). Do not write a second
  `getOfferings`-shaped Apex method for this component — one source of the
  offering list, reused, is the whole point of following the established
  pattern rather than inventing a parallel one.
- `gtmInstrumentAuthor.js`: replace the dead `@api offeringKey = 'migration-accelerator'`
  stub with the `gtmContentManager` shape: `@track offerings = []`,
  `@track selectedOffering = ''`, `connectedCallback` calls `getOfferings()`
  and presets `selectedOffering` to the single offering when there's only
  one (same one-liner `gtmContentManager` uses at its own `getOfferings`
  callback). Add `get offeringOptions()` mapping to `{label, value}` for a
  `<lightning-combobox>`, and `handleOfferingChange(event)` setting
  `selectedOffering` and re-triggering `getPack`/`getFrame`.
- `gtmInstrumentAuthor.html`: add the combobox near the top of the
  authoring shell (above the frame/pair preview), same visual slot
  `gtmContentManager.html` uses for its own offering combobox — check that
  file's markup for the exact component and CSS class names to reuse rather
  than inventing new ones.
- Every existing call to `getPack({...})` / `getFrame({...})` in
  `gtmInstrumentAuthor.js` gains `offeringKey: this.selectedOffering` in its
  params object; guard each call site so it doesn't fire with a blank
  `selectedOffering` (mirrors `gtmContentManager`'s `hasOffering` /
  `showPagePicker` gating pattern).
- Update `gtmInstrumentAuthor.test.js`: existing tests mock `getPack`/
  `getFrame` — update the mocked call assertions to expect the new
  `offeringKey` param; add one test asserting the combobox renders when
  `getOfferings` resolves with 2+ offerings, and that changing it re-calls
  `getPack`/`getFrame` with the new key.

### 4.2 `GTM_Instrument_Author` tab / hosting page

No change expected — the tab hosts the LWC directly
(`force-app/main/default/tabs/GTM_Instrument_Author.tab-meta.xml`), and the
LWC now self-serves its own offering list via `connectedCallback`, the same
way `gtmContentManager` does when embedded on its own tab. Confirm by
inspection that nothing else references the now-removed `@api offeringKey`
default (`grep -rn "c-gtm-instrument-author" force-app/main/default --include=*.html`
already showed only the tab references the bundle — recheck at
implementation time in case something changed).

---

## Phase 5 — `gtmAssessmentQuestionnaire` (guest-facing questionnaire)

This component's `getPack`/`getPlatforms`/`getQuestionnaire` calls need the
same `offeringKey` parameter threaded through once `GtmAssessmentInstrument.
getPack` requires it (Phase 2.4 is a breaking signature change — this
component **must** be updated in the same deploy as Phase 2, or it breaks
the live guest questionnaire outright). Two sub-cases:

- **`GtmAssessmentQuestions.getQuestionnaire()`** (used for the base
  question set, separately from `getPack`) also needs `offeringKey` and a
  `WHERE Offering_Key__c = :offeringKey` filter in `questionsFor(instrument)` —
  this was not called out in ADR-0007's text but is a real caller found
  during this session's research and must not be missed; treat it as part
  of Phase 2's blast radius, not a later addition.
- Per CLAUDE.md's D11 note (`docs/backlog.md`) and the task's own framing,
  the live `GTM1` site's actual booking surface (`gtmConfigBooking`) does
  not call `gtmAssessmentQuestionnaire` at all today — that component's own
  route lives only on the down-for-maintenance `GTM_Accelerator1` site. Its
  offering key today would come from wherever it currently gets `sourceName`/
  `targetName` (check its parent's `@api` props at implementation time —
  not traced in this architect pass since it's downstream of a route this
  session was told not to fix). Thread `offeringKey` through the same way
  as `gtmInstrumentAuthor` does, defaulting to `'migration-accelerator'`
  when the surrounding page/site has no other offering concept yet (which,
  per ADR-0006/D9, is every route on the only two sites that currently
  exist).
- Update `gtmAssessmentQuestionnaire.test.js` for the new param, same
  mechanical shape as 4.1.

---

## Phase 6 — What this changes about D11, without fixing it

`docs/backlog.md` D11 says the live booking flow (`gtmConfigBooking`) sends
no `answers` array, so real submissions today score nothing. **Not fixed
here.** But whoever picks up D11 afterward needs to know: once this plan
lands, `submitRequest` requires a real offering key to resolve the *right*
instrument (Phase 2.5's `resolveOfferingKey` reads
`GTM_Saved_Configuration__c.Offering__c` via the linked config — the same
field a D11 fix already has available, since `gtmConfigBooking` is reached
from a saved, offering-tagged engagement link). A D11 fix that wires
`gtmConfigBooking` to collect and send real answers must confirm the config
it's booking against still resolves an offering key the same way (it will,
automatically, through the unchanged `resolveConfigContext`/
`resolveOfferingKey` path) — no new work required on D11's part *because*
of this plan, just an assumption D11's implementer should verify rather
than rediscover. Leave a one-line pointer to this section in
`docs/backlog.md`'s D11 entry when this plan is implemented (not now — this
architect pass doesn't touch `docs/backlog.md`).

---

## QA verification protocol (independent, after Phase 0-5 land)

Do not just re-read the diff. Prove isolation the same way this session's
own Configurator content-wiring proof worked: call the exact production
Apex the UI calls, from a real Apex context against `gtm-dev`, not a
mock.

### 1. Author two offerings with genuinely different content

- Confirm `migration-accelerator`'s instrument is untouched: run
  `python3 scripts/build-instrument.py --check` and diff
  `sf apex run --file <ad-hoc script calling GtmAssessmentInstrument.getFrame('migration-accelerator')>`
  before and after the whole change lands — same 8 slots, same band edges,
  same pair count.
- **First, author the fixture offering record.** `build-instrument.py` runs a
  pre-flight cross-check (ADR-0009) that fails the build for any instrument
  directory whose name is not an `Offering_Key__c` on some committed
  `GTM_Offering__mdt` record. Without this file the build fails loudly before
  it compiles anything, and the rest of this procedure cannot run. Author
  `force-app/main/default/customMetadata/GTM_Offering.QA_Fixture_Offering.md-meta.xml`
  with `Offering_Key__c = qa-fixture-offering` and a `Label__c` such as
  "QA Fixture Offering".

  > **Never commit or deploy the fixture offering record.** It is created for
  > the duration of this proof and destroyed in section 5. Committing it to
  > `main` or deploying it to `gtm-dev` would publish a spurious offering into
  > Production, where it would surface to BD reps as a real offering.

- Author a minimal second offering directory,
  `instrument/qa-fixture-offering/`, with:
  - `dimensions.yaml`: a **different** slot count if Phase 1's open call
    was resolved, or the same 8-slot shape with visibly different `key`
    values and wording if it wasn't (either is a valid isolation proof —
    the point is the *content*, not necessarily the *shape*, differs from
    Migration Accelerator's).
  - At least one `GTM_Assessment_Question__mdt` row (hand-authored, per
    Phase 2.1's convention) with `Offering_Key__c = 'qa-fixture-offering'`
    and a `Dimension_Key__c` that does **not** exist in any
    `migration-accelerator`-tagged row.
  - One `pairs/base.yaml` (`source: "*"`, `target: "*"`), no branching.
- Build (`python3 scripts/build-instrument.py`) and deploy just this new
  offering's emitted CMDT files plus the hand-authored Question row to
  `gtm-dev`.

### 2. Prove no leakage, both directions, via the real Apex entry points

Run each of these via `sf apex run` (anonymous Apex hitting the actual
deployed classes, not a local test-context mock) and record the output:

```apex
// (a) MA's pack must not contain the fixture offering's dimension key.
GtmAssessmentInstrument.Pack maPack = GtmAssessmentInstrument.getPack('migration-accelerator', null, null);
for (GtmAssessmentInstrument.Slot s : maPack.slots) {
    System.assert(s.key != '<qa-fixture-dimension-key>', 'LEAK: MA pack contains fixture dimension');
}

// (b) The fixture offering's pack must not contain any of MA's 8 dimension keys.
GtmAssessmentInstrument.Pack fixturePack = GtmAssessmentInstrument.getPack('qa-fixture-offering', null, null);
Set<String> maKeys = new Set<String>(GtmAssessmentScoring.DIMENSIONS);
for (GtmAssessmentInstrument.Slot s : fixturePack.slots) {
    System.assert(!maKeys.contains(s.key), 'LEAK: fixture pack contains an MA dimension key: ' + s.key);
}

// (c) getFrame() for each offering returns each offering's own band edges,
// not a shared/merged set.
GtmAssessmentInstrument.Frame maFrame = GtmAssessmentInstrument.getFrame('migration-accelerator');
GtmAssessmentInstrument.Frame fxFrame = GtmAssessmentInstrument.getFrame('qa-fixture-offering');
System.debug('MA bands: ' + JSON.serialize(maFrame.bands));
System.debug('Fixture bands: ' + JSON.serialize(fxFrame.bands));
// Manually confirm these differ (or, if deliberately authored the same,
// confirm each was independently resolved -- check debug logs for two
// separate GTM_Assessment_Frame__mdt queries, not one shared cache hit
// serving both).

// (d) A real submitReuqest-shaped scoring call for the fixture offering
// must not silently fall back to MA's frame.
GtmAssessmentScoring.Score fxScore = GtmAssessmentScoring.score(
    'qa-fixture-offering',
    new Map<String, Integer>{ '<qa-fixture-dimension-key>' => 3 },
    new GtmAssessmentScoring.PairEligibility(),
    fixturePack
);
System.debug('Fixture score maxTotal: ' + fxScore.maxTotal);
// Must equal the fixture offering's own dimension-count * max-answer-value,
// not 32 (MA's).
```

- Also confirm via `sf data query` that `GTM_Assessment_Pair__mdt`,
  `GTM_Assessment_Dimension_Override__mdt`, `GTM_Assessment_Gate__mdt`,
  `GTM_Assessment_Supplement__mdt`, and `GTM_Assessment_Question__mdt` rows
  for the two offerings are disjoint sets when filtered by
  `Offering_Key__c` — a belt-and-suspenders data-level check alongside the
  Apex-level one above.

### 3. Prove the Instrument Editor's selector actually switches content

Load `GTM_Instrument_Author` as an internal user in `gtm-dev` (real
browser session, per CLAUDE.md's "route reachability" discipline — don't
infer this from source), confirm the offering combobox lists both
offerings, and confirm switching it re-renders visibly different content
(different dimension labels/questions) without a full page reload glitching
between the two.

### 4. Prove the data-preservation guarantee (Phase 3) held

Re-run the Phase 3 verification queries. Additionally, pick the real
`GTM_Assessment_Request__c` row for one of the four named accounts in
`docs/backlog.md` D10, confirm `Offering_Key__c = 'migration-accelerator'`,
and confirm `GtmReadoutModel.buildJson` (called via
`GtmReadoutController.generateDraftReadout` or directly) still reproduces
the same `Instrument_Pair__c` resolution chain and slot wording it did
before this change — i.e., open (or regenerate a draft of) that account's
actual readout and confirm it still reads the same as before, not
regenerated against the fixture offering or a blank pack.

### 5. Clean up the fixture offering

Once QA is recorded, remove `qa-fixture-offering`'s CMDT records from
`gtm-dev`, then delete **both** halves of the fixture from the repo:

```
rm -r instrument/qa-fixture-offering/
rm force-app/main/default/customMetadata/GTM_Offering.QA_Fixture_Offering.md-meta.xml
```

Neither is a judgement call any more, and the earlier option of keeping the
fixture directory committed as a permanent regression fixture is **no longer
available** (ADR-0009):

- The offering record must go because `GTM_Offering__mdt` records are what
  the app enumerates to present offerings to BD reps. A committed or
  deployed `qa-fixture-offering` record would publish a fake offering into
  Production.
- The instrument directory must therefore go with it, because
  `build-instrument.py`'s pre-flight cross-check fails any instrument
  directory with no matching offering record. Keeping the directory while
  deleting the record would leave `main` with a permanently red build — and
  keeping both would leave a fake offering in Production. The fixture is
  created and destroyed inside this procedure, which is exactly what keeps
  the cross-check absolute in the committed tree.
