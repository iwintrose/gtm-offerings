# ADR-0009 — The instrument root is offering-neutral, and capability manifests are reference material

**Status:** Accepted — implemented on `agent/issue-16`. The 55-record CMDT
redeploy to `gtm-prod` is a human-attended post-merge step (see *Consequences*).

**Amends:** [ADR-0007](0007-assessment-instrument-becomes-per-offering.md) §2,
its *location* statement only.

## Context

ADR-0007 made the assessment instrument per-offering: one directory per
offering under a framework-level `instrument/` root, with `Offering_Key__c`
stamped from the directory name onto every emitted record. It explicitly
recorded the root as "existing root, unmoved" — which left the tree looking
like this:

```
migration-accelerator/
  instrument/
    migration-accelerator/     <- the only offering directory
      dimensions.yaml complexity.yaml gates.yaml
      pairs/*.yaml supplements/*.yaml
  capabilities/
    README.md
    platforms/hubspot.yaml
```

Three separate things sat under one offering-named root, and the doubled
`migration-accelerator/instrument/migration-accelerator/` made a
framework-level root read as one offering's property:

1. **The instrument root** is framework-level per ADR-0007 — it is not
   Migration Accelerator's, and a second offering's directory would have been
   authored inside a directory named after a different offering.
2. **`capabilities/`** is reference data for a *different repo*
   (`ma-migrator`), loaded by no running code in this app, yet sat as a
   sibling of the instrument tree where it read as part of this app's
   deployable offering data.
3. **An instrument directory was admissible on filesystem evidence alone.**
   `offering_dirs()` admitted any immediate subdirectory holding a
   `dimensions.yaml`, with no cross-check against `GTM_Offering__mdt`. A
   directory named for an offering that does not exist would have compiled and
   stamped a full scored instrument for it. No rogue offering existed — the
   gap was latent, not active.

ADR-0007 was also **internally inconsistent** on this point: its §5 phase list
already wrote the un-doubled `instrument/migration-accelerator/`, while only
its §2 diagram pinned the doubled root. This ADR resolves that inconsistency
rather than contradicting it.

### Why the instrument YAML cannot live under `force-app/`

Ruled out on evidence, not preference:

- `scripts/deploy.sh:67-82` builds pass 1 by globbing
  `force-app/main/default/*/` and appending `--source-dir` for every top-level
  directory it finds (minus `customMetadata` and `EXCLUDE_DIRS`). A new
  `force-app/main/default/instrument/` would be picked up automatically and
  handed to `sf project deploy start` as raw YAML.
- `.forceignore` carries no entry that would cover it, and adding one turns
  that pass into a `--source-dir` with no deployable components. Either way
  `deploy.sh` breaks.
- `.github/workflows/agent-ci-gate.yml:87` dry-runs the whole
  `force-app/main/default` tree and would hit the same raw YAML.
- `sfdx-project.json` has a single `packageDirectories` entry, and ADR-0001
  commits to an unlocked-package boundary later.

## Decision

### 1. The instrument root is promoted to a top-level, offering-neutral `instrument/`

```
BEFORE                                            AFTER
migration-accelerator/
  instrument/                                     instrument/
    migration-accelerator/                          migration-accelerator/
      dimensions.yaml  complexity.yaml                dimensions.yaml  complexity.yaml
      gates.yaml  pairs/*.yaml                        gates.yaml  pairs/*.yaml
      supplements/*.yaml                              supplements/*.yaml
  capabilities/                                   reference/ma-migrator-capabilities/
    README.md                                       README.md
    platforms/hubspot.yaml                          platforms/hubspot.yaml
```

The directory `migration-accelerator/` **ceases to exist**. Moves were done
with `git mv` so history follows; all 14 files show as pure renames.

`scripts/build-instrument.py`'s `INSTRUMENT` constant is now
`os.path.join(ROOT, "instrument")`, and the `HEADER` stamped into every
generated record reads `from instrument/`.

**The offering key string `migration-accelerator` is not a path and did not
change.** `GTM_Offering.Migration_Accelerator.md-meta.xml`, every
`Offering_Key__c` value, `scripts/deploy.sh:142`, `scripts/check-all.sh:24-25`
and both `data/seed/migration-accelerator.story.*.json` filenames are
untouched. Only the string `migration-accelerator/` *with a trailing slash*
was substituted, hit by hit.

### 2. Capability manifests move to a top-level, non-deployable `reference/`

`reference/ma-migrator-capabilities/`. **Relocated, not deleted.**

- **Not deleted**, because deleting it removes the last offline resolution for
  36 rule-5 rationale citations, deepening the already-red flagless
  `build-instrument.py --check` CI step. Deletion needs human sign-off it does
  not have.
- **Not under `force-app/`** — it is another repo's reference data and would
  be swept into `deploy.sh`'s glob (see Context).
- **Not under `docs/`** — `docs/` documents *this* system. These are
  machine-readable manifests conforming to `ma-migrator`'s
  `capabilities/schema/capability.schema.json`, headed to another repo.
- **Top-level `reference/`** states plainly "reference material, not this
  app's deployable surface," keeps the 36 citations resolving against `ROOT`
  so rule 5 does not get worse, and stops `capabilities/` being a sibling of
  the instrument tree under an offering-named root.

The manifests' README now carries an explicit non-deployable header. Nothing
in the repo loads them: the only in-repo consumers are prose — a comment in
`GtmAssessmentInstrument.cls` naming the schema, and a fixture README citing
`hubspot.yaml`.

### 3. An instrument directory must name a real offering — a pre-flight, not a 15th rule

`scripts/build-instrument.py` gains `offering_keys_from_cmdt()` and
`check_offerings_exist()`, called from `main()` immediately after
`offering_dirs()` and **before** the build loop. For any instrument directory
whose name is not an `Offering_Key__c` on some committed `GTM_Offering__mdt`
record, the build fails loudly with a named, actionable error.

Design constraints, all deliberate:

- **It is a pre-flight precondition on the inputs, not a validation rule.**
  The rule count stays **14** and the success string `all 14 rules hold` is
  unchanged. The 14 rules are properties of an instrument's *contents*; this
  is a property of whether the directory should exist at all.
- **XML only.** It parses
  `force-app/main/default/customMetadata/GTM_Offering.*.md-meta.xml` with
  `xml.etree.ElementTree`. No DML, no callout, no org connection, no `sf` CLI
  — it behaves identically in CI and on a laptop with no authenticated org.
- **Not inside `build_offering()`.** That function is per-offering and
  deliberately cannot see anything outside its own directory.
- **A missing offering source is one distinct error, not a cascade.** If no
  `GTM_Offering.*.md-meta.xml` files exist at all, the check emits a single
  error naming the missing source rather than one error per offering
  directory, which would bury the actual cause.
- **Not a GUS tool.** The check belongs in the build script; nothing about it
  is threaded through `GtmAgentToolSurface`.

### 4. `qa-fixture-offering` gains a fixture record, NOT an opt-out flag

`docs/agent-artifacts/per-offering-instrument-plan.md`'s offering-isolation QA
procedure authored an instrument directory with no `GTM_Offering__mdt` record
— exactly what §3 now forbids. It gains a fixture record, created and
destroyed **inside** the procedure.

An opt-out flag was rejected: it would be a permanent, discoverable hole in
the exact gate this ADR installs, passable by any future agent to silence the
check, and would need its own documentation and tests. A fixture record is the
honest model — an instrument for an offering that exists — costs one small XML
file, and exercises the real path `GtmOfferingCreationTest` already covers.

The procedure now carries an explicit warning that the fixture offering record
must **never** be committed to `main` or deployed to `gtm-prod`, because
`GTM_Offering__mdt` records are what the app enumerates to present offerings
to BD reps: a committed fixture would publish a spurious offering into
Production. The previously-offered option of keeping the fixture instrument
directory committed as a permanent regression fixture is withdrawn — with the
record deleted it would leave `main` permanently red, and with the record kept
it would leave a fake offering in Production.

## What ADR-0007 keeps

This ADR amends **only** ADR-0007 §2's statement about where the root lives.
Fully in force, unchanged:

- The per-offering directory model — one directory per offering, all 14 rules
  running **within** one offering directory and never across two.
- `Offering_Key__c` stamping from the directory name onto every emitted record
  (all 55 generated records still carry `migration-accelerator`).
- The 14 validation rules and the `all 14 rules hold` success string.
- **The pair `name:` freeze.** Every pair YAML `name:` is byte-identical.
  These derive the stored `Instrument_Pair__c` DeveloperName that
  `GtmAssessmentInstrument.resolveByPairKey` uses to re-render historical
  readouts for TD Bank, Medtronic, LA Metro and MUCH Music. Renaming one
  orphans submitted assessments.
- The frame constants (8 slots, 6 dimensions, 1-4/1-3 scales, bands 14/20/26)
  remain global Python constants — ADR-0007's deliberately-deferred open call,
  untouched here.

## Consequences

**The rationale rewrite is behaviourally inert.** 59 citation paths inside 5
instrument YAML files were rewritten (36 to the relocated `hubspot.yaml`, 23
to the un-doubled instrument root), which regenerated 55 of the 70
`GTM_Assessment_*` records via `scripts/build-instrument.py`. The diff is
confined to the generated header comment and `Rationale__c` values.
`Rationale__c` is read by no Apex, no LWC, no SOQL field list and no
permission set; it is `LongTextArea(4000)` and the largest committed value is
2586 chars, so rule 14 has headroom. No score, tier, question or readout reads
it. The 14 hand-authored `GTM_Assessment_Question.*` records are read-only to
the build script and were not touched.

**A Production redeploy is required, and is a human-attended step.** `gtm-prod`
is Production (`CLAUDE.md` §1) and holds four live engagements. Landing this
means redeploying 55 CMDT records there. This is the ordinary instrument path
(ADR-0007 §4: configuration redeploy, not a data migration) and is inert as
above — but it is a deploy against live prospect data and must be run through
`scripts/deploy.sh` (which retries the flaky CMDT pass 4x) with a human on the
deploy, never as an unattended agent step. **It was deliberately not performed
as part of this change.**

**Known future cost, accepted rather than solved.** When the `ma-migrator`
handoff actually happens and the manifests leave this repo, those 36 citations
get rewritten a second time and rule 5 loses its offline resolution for them.
That is cheaper than deleting the manifests now, and whether the two teams'
handoff has happened is not a fact verifiable from this repo.

**Stale paths fixed in passing, not inherited.** `rename-pair-keys.py` pointed
at a flat `pairs/` directory that never existed post-ADR-0007, so its
`os.path.isdir` guard made the tool silently find zero pairs to rename — while
its own docstring carried the correct per-offering path. It now iterates
offering directories. Also corrected: `gtmInstrumentAuthor.js`'s *user-facing*
copy-paste instruction (documentation cannot correct a path the product itself
prints at the author), `docs/architecture/overview.md`'s pre-ADR-0007 flat
glob, `check-references.py`'s secret-scan root (a coverage loss there would
have reported as success — it now scans both `instrument/` and `reference/`,
verified by probe), and three stale cross-references inside `hubspot.yaml`.

**Deliberately left alone.** The three CSS provenance comments in
`gtmStory.css`, `gtmConfigurator.css` and `chooseIndustry.css` cite
`gtm-offerings/migration-accelerator/<page>.html`, a dead HTML prototype
directory — historical attribution, not a live path. ADR-0007 line 22 uses the
flat path correctly, describing the pre-decision state in Context.
