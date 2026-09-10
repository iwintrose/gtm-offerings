# TASK SCOPE — ISSUE #18

## 1. Requirements Breakdown

- **Target Objective:** Produce a written decision — migrate, don't
  migrate, or migrate a subset — on moving GTM Offerings' page/story
  content (currently `GTM_Page_Content__c` / `GTM_Page_Section__c`,
  authored via `gtmContentManager`, read via `GtmPageContentController` /
  `GtmPageContentReader`) to Contentful, a headless CMS. **This is an
  exploratory/research issue.** The deliverable is a decision document and,
  if migrating, a plan — not a working integration. No code should be
  written against this issue without a separate follow-up issue scoping
  the actual implementation.
- **System Component Impacted:**
  - `force-app/main/default/lwc/gtmContentManager/` — the in-org content
    authoring UI; a decision to migrate changes or replaces this.
  - `GtmPageContentController.cls` / `GtmPageContentReader.cls` — the read
    path both the guest Experience Cloud site and the internal app use
    today.
  - `GTM_Page_Content__c` / `GTM_Page_Section__c` — the current storage;
    real, live content exists here today (per `docs/backlog.md`'s D-series
    offering-content entries) that would need a migration plan, not a
    greenfield schema.
  - Explicitly OUT of scope, per the issue itself: the assessment
    instrument (`migration-accelerator/instrument/`, CMDT — separate
    system, tracked in issue #16) and GUS / readout tool surfaces
    (`AGENTS.md` §1).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No — explicitly out of scope per the
      issue body.
- [ ] Altering Custom Metadata? Not for this issue's deliverable (a
      decision/plan). A follow-up implementation issue would need to
      answer this once the plan exists.
- [ ] Introducing database fields? Not for this issue's deliverable. A
      migration plan may propose schema changes, but none are made here.

## 3. Plan Acceptance Criteria

- **Success Metric:** A written decision plus, if migrating, a plan that
  concretely answers all six open questions in the issue: guest read-path
  auth/token exposure, per-offering Contentful content-type modeling,
  editing UX (proxy vs. leave-Salesforce), migration of existing live
  content, caching/outage behavior for the guest-facing site, and
  cost/procurement approval as a prerequisite separate from the technical
  plan. A plan that skips any of the six and calls itself complete does
  not meet this issue's acceptance bar.
- **Target Test Target:** N/A for this issue (no code change expected). If
  the plan proposes a spike/prototype, that becomes its own follow-up
  issue with its own test targets, not folded into this one.
# TASK SCOPE — ISSUE #16

Resolve `migration-accelerator/`'s location: move or restructure without
losing offering/instrument functionality.

Supersedes the previous scope file (issue
"offering-instrument-construct-integrity", commit `fb63097`), which is
retained as background: it established the rogue-offering gap that this
issue's third constraint folds in.

## 0. Verified current state (read from code, not from spec docs)

Everything below was confirmed by reading the tree on `main` at the time of
writing. Several docs are stale against it; those are called out.

**What is actually under `migration-accelerator/` — 14 files, two trees:**

```
migration-accelerator/
  instrument/
    migration-accelerator/            <- the ONLY offering directory
      dimensions.yaml  complexity.yaml  gates.yaml
      pairs/  base.yaml any_to_mcn.yaml eloqua_to_sfmc.yaml
              hubspot_to_mcn.yaml hubspot_to_sfmc.yaml sfmc_to_mcn.yaml
      supplements/  hubspot_context.yaml mcn_readiness.yaml
                    sfmc_classic_readiness.yaml
  capabilities/
    README.md
    platforms/hubspot.yaml            <- the only manifest
```

One offering directory, named `migration-accelerator`, so the real path is
the doubled `migration-accelerator/instrument/migration-accelerator/`. That
doubling is the confusion the issue is circling: per ADR-0007 §2 the
`instrument/` root is **framework-level** and the per-offering directory
beneath it is offering-level, but the root's parent carries one offering's
name, so the tree reads as if the whole thing belongs to Migration
Accelerator.

**`build-instrument.py` path resolution and behaviour (all confirmed):**

- `ROOT` = repo root, derived from `__file__` (line 108). `INSTRUMENT =
  ROOT/migration-accelerator/instrument` (line 109). `CMD_DIR =
  ROOT/force-app/main/default/customMetadata` (line 110).
- `offering_dirs()` (lines 176-190) lists immediate subdirectories of
  `INSTRUMENT` and admits any that contains a `dimensions.yaml`. **No
  cross-check against `GTM_Offering__mdt` exists** — the prior scoping pass
  was correct.
- The 14 rules all run inside `build_offering()` (line 560) against one
  directory at a time; `Offering_Key__c` is stamped from the directory name
  onto every emitted record (lines 1126, 1151, 1181, 1201, 1216).
- `--check` validates, diffs against the committed XML, writes nothing, and
  exits 1 on any rule violation **or** on staleness (lines 1299-1309).
- Frame invariants (8 slots, 6 complexity dimensions, 1-4/1-3 scales, bands
  14/20/26) are still global Python constants (lines 118-146) — ADR-0007's
  deliberately-deferred open call, out of scope here.

**Baseline: both CI static checks already fail on `main`.** This matters
because the issue's acceptance says "no regression," and a naive reading
would call today's state passing. Measured:

| Command | Exit on `main` today | Why |
|---|---|---|
| `python3 scripts/build-instrument.py --check` | **1** | Rule 5 (cited paths resolve) has no `ma-migrator` working copy, so ~40 citations fail |
| `python3 scripts/build-instrument.py --check --allow-missing-source-root` | **0** | `Instrument up to date: 55 records across 1 offering(s) (migration-accelerator), all 14 rules hold.` |
| `python3 scripts/check-references.py` | **1** | One pre-existing deploy-blocker unrelated to this issue: `CLAUDE.md` contains the literal `gtm-dev` org id (redacted here deliberately — quoting the value would make this file a second blocker) |

`.github/workflows/agent-ci-gate.yml:56` runs the **flagless** form, so that
step is red on `main` regardless of this issue. The regression baseline for
this work is therefore the *flagged* form plus the *exact* pre-existing
`check-references.py` failure set, not "exit 0".

**`GTM_Offering__mdt` records in source:** exactly one —
`force-app/main/default/customMetadata/GTM_Offering.Migration_Accelerator.md-meta.xml`,
`Offering_Key__c = migration-accelerator`. It matches the one instrument
directory name, so **no rogue offering exists today**; the gap is latent, not
active.

**The four named production engagements are not instrument directories.**
TD Bank / Medtronic / LA Metro / MUCH Music are real `GTM_Assessment_Request__c`
/ saved-configuration rows in `gtm-dev` (`docs/backlog.md` line 211, D10 at
lines 739-754 — D10 is about link passwords, not instruments). They score
against the deployed `GTM_Assessment_*` CMDT generated from the single
`migration-accelerator` directory, and re-render historical readouts through
`GtmAssessmentInstrument.resolveByPairKey` keyed on the stored
`Instrument_Pair__c` DeveloperName. That DeveloperName derives from each
pair YAML's `name:` field — ADR-0007 §2's hard constraint.

**`check-references.py` asserts almost nothing about this tree.** Its only
two `migration-accelerator` touchpoints are line 727 (a secret/org-id scan
root) and line 1247 (an inventory print string). Consequence: if the tree
moves and line 727 is not updated, the YAML silently drops out of secret
scanning — a coverage loss that reports as success. Its section 11
(line 680) enumerates `os.listdir(force-app/main/default)` and demands each
directory be named by a deploy script.

**`sf project deploy` / `force-app` constraint — verified, and it is decisive.**
`scripts/deploy.sh` lines 67-82 build pass 1 by globbing
`force-app/main/default/*/` and appending `--source-dir` for every top-level
directory found (minus `customMetadata` and `EXCLUDE_DIRS`). A new
`force-app/main/default/instrument/` would be picked up automatically and
handed to `sf project deploy start` as a source dir; `.forceignore` today
carries no entry that would cover it, and adding one turns that pass into a
`--source-dir` with no deployable components. Either way `deploy.sh` breaks.
`agent-ci-gate.yml:87` (`sf project deploy start --source-dir
force-app/main/default --dry-run`) would hit the same raw YAML. Combined
with `sfdx-project.json`'s single `packageDirectories` entry and ADR-0001's
future unlocked-package boundary, **moving `instrument/` into `force-app/`
is ruled out on evidence, not preference.** ADR-0007 §2 already recorded the
root as "existing root, unmoved."

**Rationale citations are the real coupling cost of any move.** Rule 5
(`check_rationale`, line 210) resolves every path-shaped token in a
`rationale:` against `ROOT` first, then the `ma-migrator` root. Inside the
instrument YAML: **36** citations of
`migration-accelerator/capabilities/platforms/hubspot.yaml` and **23** of
`migration-accelerator/instrument/...`. Moving either tree breaks all of
them until the text is rewritten, and the rewrite regenerates **55** of the
70 `GTM_Assessment_*` XML files (both the citation text and the generated
`from migration-accelerator/instrument/` header at line 481).

**That rewrite is behaviourally inert, which de-risks it.** `Rationale__c`
is `LongTextArea(4000)` on four CMDT types; the largest committed value is
2586 chars, so rule 14 has ample headroom. Grepping
`force-app/main/default/classes/` and `.../lwc/` for `Rationale__c` returns
**nothing**, and `GtmAssessmentInstrument`'s five SOQL statements (lines
590, 1345, 1363, 1393, 1408) use explicit field lists that never include it.
No guest permission set grants it. It is authoring documentation only — no
score, tier, question, or readout reads it.

**`capabilities/` is genuinely not offering data.** Its README states the
manifests follow `ma-migrator/capabilities/schema/capability.schema.json`,
are "intended to move to `ma-migrator/capabilities/platforms/` once the two
teams align," are written with internal paths relative to the *ma-migrator*
repo root so they read correctly after the move, and that "Nothing here is
loaded by any running code today." Confirmed: the only in-repo consumers are
prose — `GtmAssessmentInstrument.cls:389` names the schema in a comment, and
`lwc/gtmReadoutView/__tests__/data/README.md:23` cites `hubspot.yaml`. No
Apex, LWC, script, or CI job loads it.

**Pre-existing stale paths a relocation must not paper over.** These are
already wrong on `main` (pre-ADR-0007 flat layout) and are in the blast
radius either way:

- `scripts/rename-pair-keys.py:67` — `PAIRS = ROOT/migration-accelerator/instrument/pairs`,
  a directory that does not exist. `plan()` guards with `os.path.isdir`, so
  the tool **silently finds zero pairs to rename**. It is the remedy
  `build-instrument.py` names in its own double-underscore warning (line
  554), so the named remedy is broken. Its own docstring at line 22 states
  the correct per-offering path — docstring and code disagree.
- `force-app/main/default/lwc/gtmInstrumentAuthor/gtmInstrumentAuthor.js:514`
  (comment) and **`:526`** — the latter is inside `yamlFragment`'s emitted
  string, i.e. a **user-facing** copy-paste instruction telling a content
  author to paste into `migration-accelerator/instrument/pairs/<pair>.yaml`.
  No Jest test asserts that string.
- `docs/architecture/overview.md:186` — `migration-accelerator/instrument/*.yaml`, flat.
- ADR-0007 line 22 uses the flat path too, but correctly: it is describing
  the pre-decision state in Context. Leave it alone.

**Full reference inventory a relocation must update** (path-shaped
`migration-accelerator/` references outside the tree itself; 122 hits):
`scripts/build-instrument.py` (7), `scripts/check-references.py:727`,
`scripts/rename-pair-keys.py:22,67`,
`docs/agent-artifacts/per-offering-instrument-plan.md` (7, incl. the phase-1
`git mv` block at lines 192-196 and the `qa-fixture-offering` procedure at
lines 612, 701), `docs/architecture/adr/0007-*.md` (5),
`docs/runbooks/assessment-instrument.md:53,363`,
`docs/runbooks/fresh-org-deploy.md:45`, `docs/architecture/overview.md:186`,
`CLAUDE.md:34,42`, `.claude/agents/gtm-ba.md:33`,
`.claude/agents/gtm-architect.md:20`,
`lwc/gtmInstrumentAuthor/gtmInstrumentAuthor.js` (3), and the 55 generated
CMDT XML files.

**Two traps for a mechanical find-and-replace of the string
`migration-accelerator`:**

1. It is also the **offering key**, appearing in ~40 files that must not
   change: `GTM_Offering.Migration_Accelerator.md-meta.xml`, every
   `Offering_Key__c` value, `scripts/deploy.sh:142`,
   `scripts/check-all.sh:24-25`, the `Offering_Key__c` field descriptions on
   eight objects, `gtmInstrumentAuthor.test.js` (7 assertions), and both
   seed files, which are named **by the offering key**:
   `data/seed/migration-accelerator.story.records.json` /
   `.sections.json` (wired in `scripts/check-content-contract.py:46-47`).
2. Three CSS provenance comments —
   `lwc/gtmStory/gtmStory.css:2`, `lwc/gtmConfigurator/gtmConfigurator.css:2`,
   `lwc/chooseIndustry/chooseIndustry.css:2` — cite
   `gtm-offerings/migration-accelerator/<page>.html`, an old HTML prototype
   directory that no longer exists in this repo. Historical attribution, not
   a live path. Do not rewrite them.

## 1. Requirements Breakdown

- **Target Objective:** Stop `migration-accelerator/` from conflating three
  different things under one offering-named root, and close the latent
  rogue-offering hole, without changing a single scored answer for the four
  live engagements. Concretely, the user wants three separations made real in
  the tree: (a) the **framework-level instrument root** — which per ADR-0007
  holds one directory per offering and is not Migration Accelerator's
  property — must stop living inside a directory named after one offering;
  (b) `capabilities/` — reference material for an entirely different repo,
  loaded by no running code — must stop sitting where it can be read as part
  of this app's deployable offering data; and (c) an instrument directory
  must stop being admissible on filesystem evidence alone, so that
  `offering_dirs()` can no longer compile and stamp a scored instrument for
  an offering key with no `GTM_Offering__mdt` record behind it. The
  functional floor is absolute: the 14 rules, the per-offering directory
  model, `Offering_Key__c` stamping, and every pair `name:` (and therefore
  every stored `Instrument_Pair__c` DeveloperName) survive byte-identical in
  meaning.

  **Design fork, resolved on evidence rather than left open.** The issue asks
  where things should live, which is the Architect's call — but two of the
  three candidate answers are eliminated by verified facts above, so the
  Architect is choosing inside a narrow, evidenced space rather than
  guessing:
  - `instrument/` into `force-app/` — **ruled out.** `deploy.sh:67-82`
    globs every top-level directory under `force-app/main/default/` into
    `sf project deploy start`; the CI gate dry-runs the whole tree; there is
    one `packageDirectories` entry; ADR-0007 §2 already recorded this root
    as unmoved. Any variant of this breaks the deploy path.
  - `capabilities/` into `force-app/` — **ruled out**, per the issue and per
    the README: it is headed to `ma-migrator` and is not this app's
    deployable surface.
  - What remains, and what the Architect should choose between and record as
    the before/after: promote the instrument root to an offering-neutral
    location outside `force-app/` (the doubled path collapses to
    `instrument/<offering-key>/`, which is what ADR-0007 actually describes),
    versus leave the root physically where it is and resolve the
    conflation by documentation plus the validation gate alone. The first
    resolves the naming defect and costs 122 reference updates plus 55
    regenerated XML files; the second costs almost nothing and leaves the
    misleading path in place. Either is defensible; the Architect must pick
    one, state it, and not leave the tree half-moved.

  **One item to flag rather than settle, which does not block this run.**
  Physically relocating `capabilities/` out of this repo now makes rule 5
  *strictly worse* offline: 36 citations that resolve against `ROOT` today
  would only resolve against an `ma-migrator` working copy, which CI does
  not have — and rule 5 is already the sole reason the gate's
  `build-instrument.py --check` step is red. Keeping `capabilities/` in this
  repo (relocated, clearly labelled non-deployable, e.g. under a
  `docs/reference/` or a sibling `reference/` tree) is the option that does
  not deepen an existing CI failure. Whether the two teams' handoff has
  actually happened is a fact neither this scope nor the Architect can
  verify from the repo; if the Architect's design deletes the manifests
  rather than relocating them, that needs human sign-off first, because it
  drops the last offline resolution for those 36 citations.

  **Production-data gate.** `gtm-dev` is Production (`CLAUDE.md` §1) and
  holds the four live engagements. Landing the rationale/header rewrite
  means redeploying 55 CMDT records there. This is the ordinary instrument
  path (ADR-0007 §4: configuration redeploy, not a data migration) and is
  behaviourally inert because nothing reads `Rationale__c` — but it is a
  deploy against live prospect data and must be run through `scripts/deploy.sh`
  (which retries the flaky CMDT pass 4x) with a human on the deploy, never
  as an unattended agent step.

- **System Component Impacted:** **YAML Instrument** is the primary surface —
  `migration-accelerator/instrument/migration-accelerator/**` (12 YAML files)
  and the build/audit tooling that resolves it: `scripts/build-instrument.py`
  (`INSTRUMENT` line 109, `offering_dirs()` lines 176-190, `HEADER` line 481,
  `check_rationale` line 210), `scripts/check-references.py:727`, and the
  broken `scripts/rename-pair-keys.py:67`. Secondary, non-offering surface:
  `migration-accelerator/capabilities/` (2 files). One **LWC** file is in
  scope and only one:
  `force-app/main/default/lwc/gtmInstrumentAuthor/gtmInstrumentAuthor.js`,
  whose `yamlFragment` getter emits a stale author-facing path at line 526
  (plus the comment at 514). Generated metadata:
  `force-app/main/default/customMetadata/GTM_Assessment_{Pair,Dimension_Override,Supplement,Gate}.*`
  (55 of 70 files churn). Docs: ADR-0007 (needs an amendment or a superseding
  ADR — it recorded the root as unmoved), `docs/architecture/overview.md:186`,
  `docs/runbooks/assessment-instrument.md:53,363`,
  `docs/runbooks/fresh-org-deploy.md:45`, `CLAUDE.md` §2, and
  `docs/agent-artifacts/per-offering-instrument-plan.md`. **No Apex** is
  impacted: no class or trigger reads the YAML tree or `Rationale__c`. **No
  Experience Cloud route** is impacted: the guest questionnaire reads
  deployed CMDT, never the filesystem.

## 2. Code Dependency Checklist

- [ ] **Modifying GUS Tool Surface? NO.** Verified: no
      `GtmAgentToolSurface` implementation, no `GtmReadoutAgentSurface`/
      `GtmReadoutAgentFiles`/`GtmReadoutAgentContext`, and no
      `GtmAgentProxyController` path references the instrument tree,
      `capabilities/`, or `Rationale__c`. Nothing in this issue adds or
      changes a tool, so the zero-DML/zero-callout rule in AGENTS.md §1 is
      not engaged. If the Architect's design instead threads the offering
      cross-check through a GUS tool (it should not — the check belongs in
      the build script), that rule applies in full and the check must
      *read* `GTM_Offering__mdt`, never write.
- [x] **Altering Custom Metadata? YES — generated records, plus one possible
      new hand-authored record.** Two distinct effects. (1) The rationale and
      header rewrite regenerates 55 `GTM_Assessment_*.md-meta.xml` files.
      These must be produced **only** by re-running
      `python3 scripts/build-instrument.py` after editing the YAML in
      `migration-accelerator/instrument/` (per CLAUDE.md §2's "Do Not
      Hand-Edit Metadata"); hand-editing the XML is a blocked defect, and the
      14 hand-authored `GTM_Assessment_Question.*` records are read-only to
      the script and must not be touched. Every pair YAML's `name:` field is
      frozen — ADR-0007 §2: renaming a pair breaks
      `resolveByPairKey`/`Instrument_Pair__c` for every already-submitted
      assessment, including all four live engagements. (2) Closing the
      rogue-offering gap means `offering_dirs()` (or a new sibling check)
      reads `force-app/main/default/customMetadata/GTM_Offering.*.md-meta.xml`
      and fails the build for any instrument directory whose name is not an
      `Offering_Key__c` on some record. Note the knock-on the Architect must
      handle: `docs/agent-artifacts/per-offering-instrument-plan.md`'s
      `qa-fixture-offering` isolation procedure (lines 612, 701) authors an
      instrument directory with **no** `GTM_Offering__mdt` record — exactly
      what the new gate forbids. Either that procedure gains a fixture
      `GTM_Offering__mdt` record, or the gate needs an explicit, narrow,
      documented opt-out. Do not close the gap and silently break the
      documented QA proof.
- [ ] **Introducing database fields? NO.** No new object, field, or tab.
      `GTM_Offering__mdt.Offering_Key__c` and the seven
      `GTM_Assessment_*.Offering_Key__c` fields from ADR-0007 §1 already
      exist and already carry the "matches
      `GTM_Offering__mdt.Offering_Key__c`" convention in their descriptions;
      this issue adds a build-time *validation* over existing schema, not
      schema. Because nothing new is introduced, the five permission sets in
      `force-app/main/default/permissionsets/` (`GTM_Config_Manager`,
      `GTM_Config_View_All`, `GTM_Assessment_Guest`, `GTM_Story_Guest`,
      `GTM_Platform_Visibility`) need **no** change, and `Rationale__c` must
      stay unexposed to the two guest sets. If the Architect's design does
      add a field, CLAUDE.md §6's FLS mapping across all five becomes
      mandatory Definition of Done.

## 3. Plan Acceptance Criteria

- **Success Metric:** All six of the following hold, and QA fails the build
  if any one does not.
  1. **No scoring regression.** `python3 scripts/build-instrument.py --check
     --allow-missing-source-root` exits 0 and prints
     `all 14 rules hold` for the `migration-accelerator` offering, and the
     rebuilt CMDT set still contains **70** `GTM_Assessment_*` records with
     `Offering_Key__c = migration-accelerator` on every generated one.
     `python3 scripts/check-references.py` exits with the *same single*
     pre-existing deploy-blocker (`CLAUDE.md`'s org id) and no new one — the
     documented baseline in §0, not exit 0.
  2. **Historical readouts still explain themselves.** Every pair YAML
     `name:` is byte-identical to `main`, provable by
     `git diff main -- '**/pairs/*.yaml' | grep '^[-+].*name:'` returning
     nothing, so no stored `Instrument_Pair__c` on the TD Bank / Medtronic /
     LA Metro / MUCH Music requests is orphaned. Score-bearing content —
     slot keys, positions, option values, points, band edges, `show_when`
     predicates, gate predicates — is likewise unchanged; the only permitted
     YAML content edits are `rationale:` citation paths.
  3. **The before/after is written down and the two trees stay separate.** A
     new or amended ADR states where the instrument YAML lives, where the
     capability manifests live, and why — explicitly reconciling with
     ADR-0007 §2, which currently records the root as unmoved. The
     instrument tree and `capabilities/` do not end up siblings under one
     offering-named root again, and `capabilities/` is not under
     `force-app/`.
  4. **The rogue-offering gap is closed, or deferred in writing.** Either
     `build-instrument.py` fails loudly for an instrument directory with no
     matching `GTM_Offering__mdt.Offering_Key__c` — demonstrated by a
     temporary throwaway directory containing a `dimensions.yaml`, which
     must produce a nonzero exit and a named error, then be deleted — or the
     deferral is recorded in the ADR with a stated reason. Silently dropping
     it fails this build.
  5. **No reference is left dangling and no offering key is corrupted.**
     `grep -rn "migration-accelerator/" .` (excluding `.git/`) shows every
     surviving path-shaped reference pointing at a directory that exists;
     the three CSS provenance comments and ADR-0007's Context line 22 are
     untouched; the offering-key string `migration-accelerator` is unchanged
     in `GTM_Offering.Migration_Accelerator.md-meta.xml`, every
     `Offering_Key__c` value, `scripts/deploy.sh:142`,
     `scripts/check-all.sh:24-25`, and both
     `data/seed/migration-accelerator.story.*.json` filenames.
  6. **The stale paths found in flight are fixed, not inherited.**
     `scripts/rename-pair-keys.py:67` resolves to a directory that actually
     exists, so `--apply`'s plan is non-empty for the six committed pairs;
     `gtmInstrumentAuthor.js:526`'s author-facing paste instruction names
     the real path; `docs/architecture/overview.md:186` no longer shows the
     pre-ADR-0007 flat glob. `scripts/check-references.py:727` still scans
     the relocated YAML for secrets and org ids.

- **Target Test Target:** LWC Jest spec —
  `force-app/main/default/lwc/gtmInstrumentAuthor/__tests__/gtmInstrumentAuthor.test.js`
  (run via `npm test`); it is the only Jest suite covering the one force-app
  file in scope, and its seven `migration-accelerator` assertions are exactly
  the offering-key-vs-directory-name distinction this issue must not blur.
  Apex regression classes, which must pass **unchanged** as proof the
  pipeline output is behaviourally identical:
  `GtmAssessmentInstrumentTest.cls`, `GtmAssessmentScoringTest.cls`, and
  `GtmOfferingCreationTest.cls` (the last covers the in-app
  `GTM_Offering__mdt` creation path the new cross-check validates against) —
  run via `sf apex run test --tests GtmAssessmentInstrumentTest
  --tests GtmAssessmentScoringTest --tests GtmOfferingCreationTest`.
  Script gates, both required:
  `python3 scripts/build-instrument.py --check --allow-missing-source-root`
  and `python3 scripts/check-references.py`, each compared against the §0
  baseline. Full sweep before the PR: `npm test` plus
  `./scripts/check-all.sh --static`.
