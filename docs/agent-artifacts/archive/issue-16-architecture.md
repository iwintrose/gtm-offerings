> **ARCHIVED:** Superseded by
> `docs/architecture/adr/0009-instrument-root-is-offering-neutral.md`
> (Status: Accepted — implemented). This file's decision, implementation
> steps, and "what must NOT change" list are all restated as settled fact in
> ADR-0009. Kept here only for historical paper trail.

# Issue #16 — Architecture Decision & Implementation Plan

Author: Solution/Technical Architect agent. Input: `TASK_SCOPE.md` (BA, issue #16).
Branch: `agent/issue-16`. Worktree: `../worktrees/issue-16`.

This document is the Developer's instruction set. Where it conflicts with
`TASK_SCOPE.md`, this document wins (the conflicts are listed in §0 and are
corrections, not preferences).

---

## 0. Verification of the BA's load-bearing claims

Re-measured independently on `main` @ `f07e558`. All of the following were
confirmed true as written:

- `scripts/deploy.sh:67-82` globs `force-app/main/default/*/` and appends
  `--source-dir` per top-level directory (skipping `customMetadata` and
  `EXCLUDE_DIRS`). Confirmed. `.forceignore` contains only `**/__tests__/**`,
  `**/node_modules/**`, `**/coverage/**`, `**/__pycache__/**` — nothing that
  would cover a new `force-app/main/default/instrument/`. The force-app
  options stay ruled out.
- `build-instrument.py`: `ROOT` line 108, `INSTRUMENT` line 109, `CMD_DIR`
  line 110, `offering_dirs()` lines 176-190 (admits any immediate subdir
  holding a `dimensions.yaml`, **no** `GTM_Offering__mdt` cross-check),
  `check_rationale` line 210 (resolves against `ROOT` first, then
  `source_root()`), `HEADER` line 481. Confirmed.
- Exactly one `GTM_Offering__mdt` record in source:
  `GTM_Offering.Migration_Accelerator.md-meta.xml`, `Offering_Key__c =
  migration-accelerator`. Confirmed — no rogue offering today, the gap is latent.
- Baseline `python3 scripts/build-instrument.py --check --allow-missing-source-root`
  → exit **0**, `Instrument up to date: 55 records across 1 offering(s)
  (migration-accelerator), all 14 rules hold.` Confirmed.
- Citation counts inside the instrument YAML: **36** to
  `migration-accelerator/capabilities/platforms/hubspot.yaml`, **23** to
  `migration-accelerator/instrument/...`. Confirmed. 55 of the 70
  `GTM_Assessment_*` XML files contain the path; 14 are the hand-authored
  `GTM_Assessment_Question.*`. Confirmed.
- `scripts/rename-pair-keys.py:67` points at a non-existent flat `pairs`
  dir while its own docstring line 22 has the correct per-offering path.
  `gtmInstrumentAuthor.js:526` emits a stale author-facing paste path.
  Confirmed.

### Correction 1 — the `check-references.py` baseline is 1 blocker, and the scope file itself adds a second

`python3 scripts/check-references.py` exits **1**, but its summary line reads
`2 deploy-blocking, 96 needing a manual step` — not 1. The two are:

```
  x CLAUDE.md        contains a hardcoded Salesforce record id ...
  x TASK_SCOPE.md    contains a hardcoded Salesforce record id ...
```

`TASK_SCOPE.md` quotes the `gtm-dev` org id verbatim while describing the
`CLAUDE.md` blocker, so the scope file trips the very check it is documenting.
`TASK_SCOPE.md` is a **tracked** file (committed at `fb63097`, carrying the
previous issue's scope); the BA superseded its contents in the working tree, and
that updated copy is now in this worktree. So it will normally be committed on
this branch — which is fine, *provided the org id literal is redacted first*:

- **Redact the org id in `TASK_SCOPE.md` line 66** before committing. Replace
  the literal with a description (e.g. "the `gtm-dev` org id"). The sentence
  still reads correctly and the blocker count stays at 1. Do not delete the
  finding, just stop reproducing the value.
- **The regression baseline is: exactly one deploy-blocker, `CLAUDE.md`, plus
  96 manual-step findings.** Anything beyond that is a regression. If you skip
  the redaction, `check-references.py` reports 2 and QA will correctly read it
  as a regression this issue introduced.
- Do not reproduce the org id literal in any new file (this document
  deliberately does not).

### Correction 1b — the provisioning wrapper clobbered a tracked file (already fixed)

`scripts/agent-workspace.sh:62` unconditionally does `cat > "$dir/CLAUDE.md"`,
overwriting the repo's tracked 98-line `CLAUDE.md` with a 12-line scoped
constraint stub. In this worktree that showed up as a staged-for-nothing
deletion of 98 lines; a `git add -A` would have put "delete the project's
CLAUDE.md" into the PR.

**Already remediated by the Architect:** the scoped constraint was preserved as
the untracked `AGENT_WORKTREE_SCOPE.md` and `CLAUDE.md` was restored with
`git checkout -- CLAUDE.md`. `git status` in this worktree is now clean apart
from `TASK_SCOPE.md` (modified, expected) and the two untracked files.

**Developer:** read `AGENT_WORKTREE_SCOPE.md` for the worktree constraint, and
confirm `CLAUDE.md` shows no diff before committing, other than the intended
§2 path edits in Step 6. The wrapper defect itself is out of scope for this
issue — report it, do not fix it here.

### Correction 2 — ADR number

`0008-*` is taken (`the-guest-assessment-is-hosted-by-the-engagement-link...`).
The new ADR is **0009**, not 0008.

### Correction 3 — ADR-0007's prose already anticipates the move

ADR-0007 line **197** already writes the target shape,
`instrument/migration-accelerator/`. Only the §2 diagram at line 111 pins the
root to the doubled location (`(existing root, unmoved)`). The ADR is
internally inconsistent today; the move resolves it rather than contradicting it.

### Correction 4 — an additional in-scope reference the inventory missed

`scripts/build-instrument.py:1244` — the "no offering directories found" error
text hardcodes `migration-accelerator/instrument/`. It is inside a string split
across lines 1243-1245, so a line-scoped edit will miss it.

No unfilled placeholders exist in `TASK_SCOPE.md`. Its Code Dependency
Checklist is correct as marked: GUS tool surface NO (the cross-check belongs in
the build script, never in a tool — do not thread it through
`GtmAgentToolSurface`); Custom Metadata YES (regenerated only via
`build-instrument.py`); new database fields NO (so no permission-set work, and
`Rationale__c` stays unexposed to both guest sets).

---

## 1. DECISION

**Option (a): physically promote the instrument root to an offering-neutral
top-level location, and relocate `capabilities/` to a clearly non-deployable
top-level `reference/` tree. The directory `migration-accelerator/` ceases to
exist.**

Option (b) — docs plus the validation gate alone — is rejected.

### Before / after

```
BEFORE                                              AFTER
migration-accelerator/
  instrument/                                       instrument/
    migration-accelerator/                            migration-accelerator/
      dimensions.yaml                                   dimensions.yaml
      complexity.yaml                                   complexity.yaml
      gates.yaml                                        gates.yaml
      pairs/*.yaml            (6 files)                 pairs/*.yaml
      supplements/*.yaml      (3 files)                 supplements/*.yaml
  capabilities/                                     reference/ma-migrator-capabilities/
    README.md                                         README.md
    platforms/hubspot.yaml                            platforms/hubspot.yaml
```

Exact moves (use `git mv` so history follows):

```
git mv migration-accelerator/instrument/migration-accelerator instrument-tmp
rmdir migration-accelerator/instrument
mkdir instrument && git mv instrument-tmp instrument/migration-accelerator
mkdir -p reference
git mv migration-accelerator/capabilities reference/ma-migrator-capabilities
rmdir migration-accelerator
```

(The two-step through `instrument-tmp` avoids `git mv` refusing a move into a
path that is currently a descendant of the source. Any equivalent sequence is
fine; the end state is what is specified.)

### Reasoning

1. **The defect the issue names is a path, and only a path change fixes it.**
   The doubled `migration-accelerator/instrument/migration-accelerator/` makes
   a framework-level root read as one offering's property. Option (b) leaves
   that string reproduced in the build script's own docstring, in the CMDT
   header stamped into 55 files, and — decisively — in
   `gtmInstrumentAuthor.js:526`, a *user-facing* copy-paste instruction shown
   to content authors. Documentation cannot correct a path the product itself
   prints at the author.
2. **The cost is one-time, bounded, and mostly docs.** 122 reference updates,
   of which the code-bearing ones are 3 scripts and 1 LWC; the rest are
   markdown. The 55 XML regenerations are produced mechanically by re-running
   the build script.
3. **The regeneration is provably inert.** `Rationale__c` is read by no Apex,
   no LWC, no SOQL field list, and no permission set — verified. The 55-file
   churn changes documentation text inside metadata, not behaviour. Rule 14's
   4000-char ceiling has headroom (largest committed value 2586).
4. **Deferring is strictly more expensive.** Every future offering directory
   would be authored inside a directory named for a different offering, and
   the rationale rewrite would then have to touch two offerings' YAML plus a
   second live instrument.
5. **ADR-0007 already describes the target** at line 197; option (a) makes the
   ADR self-consistent.

### Why `capabilities/` goes to `reference/ma-migrator-capabilities/`

- **Not deleted.** Per the BA's constraint, and because deleting it removes the
  last offline resolution for 36 rule-5 citations, deepening the already-red
  flagless `build-instrument.py --check` CI step. Deletion needs human sign-off
  it does not have.
- **Not under `force-app/`.** It is another repo's reference data and would be
  swept into `deploy.sh`'s glob.
- **Not under `docs/`.** `docs/` documents *this* system; these are machine-
  readable manifests conforming to `ma-migrator`'s
  `capabilities/schema/capability.schema.json`, headed to another repo.
- **Top-level `reference/`** states plainly "reference material, not this app's
  deployable surface," keeps the 36 citations resolving against `ROOT` (so
  rule 5 does not get worse), and stops `capabilities/` being a sibling of the
  instrument tree under an offering-named root — which is the conflation the
  issue is about.
- Known future cost, to be recorded in the ADR, not solved here: when the
  `ma-migrator` handoff actually happens, those 36 citations get rewritten a
  second time. That is cheaper than deleting the manifests now.

### Rogue-offering cross-check

Add to `scripts/build-instrument.py` a **pre-flight gate**, not a 15th rule:

```
def offering_keys_from_cmdt():
    """Every Offering_Key__c on a committed GTM_Offering__mdt record."""
    # glob CMD_DIR/GTM_Offering.*.md-meta.xml, parse with the already-imported
    # xml.etree.ElementTree, walk <values> children, take the <value> text of
    # the block whose <field> text is 'Offering_Key__c'. Return a set of str.
```

Called from `main()` immediately after `offerings = offering_dirs()` and
**before** the `for offering_key, idir in offerings:` build loop (around line
1240-1249), with these semantics:

- If **no** `GTM_Offering.*.md-meta.xml` files exist at all: emit **one**
  distinct error naming the missing source. Do not emit one error per offering
  directory — a cascade hides the real cause.
- Otherwise, for each `(name, path)` in `offerings` where `name` is not in the
  key set: `fail()` with a named, actionable message, e.g.
  `instrument/<name>/: no GTM_Offering__mdt record has Offering_Key__c =
  '<name>'. An instrument directory must correspond to a committed offering.
  Add force-app/main/default/customMetadata/GTM_Offering.<Name>.md-meta.xml,
  or rename the directory to an existing offering key.`
- Use the existing `fail()` mechanism so exit code and formatting are
  consistent with the 14 rules.

**Constraints on the implementation:**

- The literal success string `all 14 rules hold` (lines ~1306 and ~1311) must
  be unchanged, and the rule count must stay 14. Acceptance criterion 1 asserts
  that string. This gate is a pre-flight precondition, not a rule.
- The check reads XML only. No DML, no callout, no org connection, no `sf` CLI
  invocation. It must work offline in CI.
- Do not put this logic inside `build_offering()` — that function is
  per-offering and deliberately cannot see anything outside its own directory.

**Prove it, then remove the proof** (acceptance criterion 4): create a
throwaway `instrument/zz-rogue-offering/dimensions.yaml`, run
`python3 scripts/build-instrument.py --check --allow-missing-source-root`,
capture the nonzero exit and the named error into the commit message or PR
body, then delete the directory and re-confirm exit 0. Do not commit the
throwaway directory.

### `qa-fixture-offering`: fixture record, NOT an opt-out flag

**Decision: the QA procedure gains a fixture `GTM_Offering__mdt` record.**

Reasoning: an opt-out flag is a permanent, discoverable hole in the exact gate
this issue exists to install — any future agent can pass it to silence the
check, and it would need its own documentation and tests. A fixture record is
the honest model (an instrument for an offering that exists), costs one small
XML file, and exercises the real path that `GtmOfferingCreationTest` already
covers. The fixture is created and destroyed inside the QA procedure, so the
gate stays absolute in the committed tree.

Edit `docs/agent-artifacts/per-offering-instrument-plan.md`:

- **§4 (around line 612)** — before "Author a minimal second offering
  directory", insert a step: author
  `force-app/main/default/customMetadata/GTM_Offering.QA_Fixture_Offering.md-meta.xml`
  with `Offering_Key__c = qa-fixture-offering` and a `Label__c`, noting that
  `build-instrument.py`'s pre-flight offering cross-check requires it and the
  build will fail loudly without it. Update the directory path in that line to
  `instrument/qa-fixture-offering/`.
- **§5 (around line 701)** — extend the cleanup to delete the fixture
  `GTM_Offering__mdt` XML alongside the fixture instrument directory, and add:
  the fixture offering record must never be committed to `main` or deployed to
  `gtm-dev`, because it would publish a spurious offering into Production.
- Fix the stale phase-1 `git mv` block at lines 192-196 to the post-move paths
  (it is a historical record of a completed phase; rewrite the paths so it does
  not teach the old layout, and add a one-line note that the root has since
  moved per ADR-0009).

---

## 2. Ordered implementation plan

Work only in `../worktrees/issue-16` on `agent/issue-16`. Never touch `main`.
**Do not deploy to any org in this run** — the PR is the deliverable.

### Step 1 — move the trees

Perform the `git mv` sequence in §1. Do not edit any file contents in this
step. Commit separately if you like, so the rename is reviewable on its own.

### Step 2 — rewrite the rationale citations inside the instrument YAML

12 YAML files under `instrument/migration-accelerator/`. Two substitutions,
**inside `rationale:` values only**:

- `migration-accelerator/capabilities/platforms/hubspot.yaml`
  → `reference/ma-migrator-capabilities/platforms/hubspot.yaml`  (36)
- `migration-accelerator/instrument/` → `instrument/`  (23)

**Nothing else in these files may change.** Not slot keys, positions, option
values, points, band edges, `show_when` predicates, gate predicates, and above
all not a single pair `name:` field.

### Step 3 — update the tooling

| File | Line(s) | Change |
|---|---|---|
| `scripts/build-instrument.py` | 109 | `INSTRUMENT = os.path.join(ROOT, "instrument")` |
| `scripts/build-instrument.py` | 5-9 | docstring paths → `instrument/<offering-key>/...` |
| `scripts/build-instrument.py` | 481 | `HEADER` → `from instrument/. Do not hand-edit...` |
| `scripts/build-instrument.py` | 1243-1245 | error text → `instrument/` (string spans lines) |
| `scripts/build-instrument.py` | ~1240 | **add** the offering cross-check pre-flight (§1) |
| `scripts/check-references.py` | 727 | scan root `migration-accelerator` → **both** `instrument` **and** `reference`. Coverage loss here reports as success — verify by confirming the secret scan still reaches the YAML. |
| `scripts/check-references.py` | 1247 | inventory string → `instrument/` |
| `scripts/rename-pair-keys.py` | 67 | `PAIRS` → the real per-offering path. It currently points at a directory that never existed post-ADR-0007, so `plan()`'s `os.path.isdir` guard makes the tool silently no-op. It must resolve per offering directory (iterate offerings, or take an offering key argument) so `--apply` yields a non-empty plan for the six committed pairs. |
| `scripts/rename-pair-keys.py` | 22 | docstring path → post-move path |

### Step 4 — regenerate the custom metadata

```
python3 scripts/build-instrument.py
```

Expect 55 `GTM_Assessment_{Pair,Dimension_Override,Supplement,Gate}.*` files to
change. **Never hand-edit generated XML** (`CLAUDE.md` §2). The 14
`GTM_Assessment_Question.*` records are hand-authored and read-only to the
script — if `git status` shows any of them modified, stop and investigate.

### Step 5 — the one LWC file

`force-app/main/default/lwc/gtmInstrumentAuthor/gtmInstrumentAuthor.js`:

- line 33 (comment) → `instrument/`
- line 514 (comment) → `instrument/migration-accelerator/pairs/*.yaml`
- **line 526** (inside `yamlFragment`'s emitted string, user-facing) →
  `` `# instrument/<offering-key>/pairs/<pair>.yaml, then run` ``

No Jest test asserts line 526 today. The seven existing `migration-accelerator`
assertions in `gtmInstrumentAuthor.test.js` are **offering-key** assertions and
must keep passing unchanged.

### Step 6 — docs

| File | Line(s) | Change |
|---|---|---|
| `docs/architecture/adr/0009-*.md` | new | See §3 below |
| `docs/architecture/adr/0007-*.md` | 111-112 | diagram → new root; drop "(existing root, unmoved)" |
| `docs/architecture/adr/0007-*.md` | 124 | `instrument/` |
| `docs/architecture/adr/0007-*.md` | Decision hdr | add forward pointer: §2's *location* superseded by ADR-0009 |
| `docs/architecture/adr/0007-*.md` | **22** | **DO NOT TOUCH** — pre-decision Context |
| `docs/architecture/adr/0007-*.md` | 197 | already correct; leave |
| `docs/architecture/overview.md` | 186 | → `instrument/<offering-key>/*.yaml` (also fixes the pre-ADR-0007 flat glob) |
| `docs/runbooks/assessment-instrument.md` | 53, 363 | → `instrument/migration-accelerator/pairs/...` |
| `docs/runbooks/fresh-org-deploy.md` | 45 | → `instrument/`. Its counts (57/45) are stale against the real 70/55; correcting them is welcome but optional and out of the acceptance set. |
| `docs/agent-artifacts/per-offering-instrument-plan.md` | 192-196, 612, 701 | per §1 |
| `CLAUDE.md` | 34, 42 | → `instrument/<offering-key>/`; line 42 should name both new roots |
| `.claude/agents/gtm-ba.md` | 33 | → `instrument/` |
| `.claude/agents/gtm-architect.md` | 20 | → `instrument/<offering-key>/*.yaml` |
| `force-app/main/default/lwc/gtmReadoutView/__tests__/data/README.md` | 23 | → `reference/ma-migrator-capabilities/platforms/hubspot.yaml` |
| `reference/ma-migrator-capabilities/README.md` | — | add a header line: non-deployable, not loaded by any running code, pending `ma-migrator` handoff; keep the existing schema/handoff prose |

Also update the prose comment in `GtmAssessmentInstrument.cls:389` if it names
a repo-relative capabilities path (it names the schema; check before editing —
if it names only `capability.schema.json`, leave it).

### Step 7 — verify, then stop

```
python3 scripts/build-instrument.py --check --allow-missing-source-root   # expect 0
python3 scripts/check-references.py                                       # expect 1, ONE blocker (CLAUDE.md)
git diff main -- '**/pairs/*.yaml' | grep '^[-+].*name:'                  # expect EMPTY
grep -rn "migration-accelerator/" --exclude-dir=.git .                    # every hit must resolve
npm test
./scripts/check-all.sh --static
```

Then the rogue-offering proof from §1, then delete the throwaway directory.

**Do not run `scripts/deploy.sh` or any `sf project deploy`.** The 55-record
CMDT redeploy to `gtm-dev` is a Production change against four live
engagements and is a human-attended step after merge, run through
`scripts/deploy.sh` (which retries the flaky CMDT pass 4x). Note it as a
required post-merge action in the PR body; do not perform it.

---

## 3. The new ADR

`docs/architecture/adr/0009-instrument-root-is-offering-neutral.md`. Must state:
where the instrument YAML lives and why it is outside `force-app/` (the
`deploy.sh:67-82` glob evidence); where the capability manifests live, that
they are non-deployable and pending the `ma-migrator` handoff, and that the
36 citations will need a second rewrite when that handoff lands; that it
supersedes **only** ADR-0007 §2's location statement while ADR-0007's
per-offering model, `Offering_Key__c` stamping, 14 rules, and pair-`name:`
freeze remain fully in force; and the new offering cross-check with the
fixture-record decision for `qa-fixture-offering`.

---

## 4. What must NOT change

1. **Every pair YAML `name:` field.** Byte-identical. These derive the stored
   `Instrument_Pair__c` DeveloperName that `GtmAssessmentInstrument.resolveByPairKey`
   uses to re-render historical readouts for TD Bank, Medtronic, LA Metro and
   MUCH Music. Renaming one orphans submitted assessments. ADR-0007 §2.
2. **The offering-key string `migration-accelerator`.** It is not a path. Do
   not let a find-and-replace touch: `GTM_Offering.Migration_Accelerator.md-meta.xml`,
   any `Offering_Key__c` value in any XML, `scripts/deploy.sh:142`,
   `scripts/check-all.sh:24-25`, the `Offering_Key__c` field descriptions on
   the eight objects, the seven assertions in `gtmInstrumentAuthor.test.js`,
   and the two seed files named by the offering key
   (`data/seed/migration-accelerator.story.records.json` /
   `.sections.json`, wired at `scripts/check-content-contract.py:46-47`).
   **Substitute only on `migration-accelerator/` with a trailing slash, and
   review every hit by hand.**
3. **The three CSS provenance comments** — `lwc/gtmStory/gtmStory.css:2`,
   `lwc/gtmConfigurator/gtmConfigurator.css:2`,
   `lwc/chooseIndustry/chooseIndustry.css:2`. They cite
   `gtm-offerings/migration-accelerator/<page>.html`, an HTML prototype
   directory that no longer exists. Historical attribution, not a live path.
4. **ADR-0007 line 22.** It uses the flat path correctly, describing the
   pre-decision state in Context.
5. **The 14 hand-authored `GTM_Assessment_Question.*` records.** Read-only to
   the build script.
6. **Score-bearing YAML content.** Slot keys, positions, option values, points,
   band edges, `show_when` and gate predicates. The only permitted YAML content
   edit in this issue is a `rationale:` citation path.
7. **The frame constants** (8 slots, 6 dimensions, 1-4/1-3 scales, bands
   14/20/26, lines 118-146). ADR-0007's deliberately-deferred open call —
   out of scope.
8. **The `all 14 rules hold` success string** and the rule count.
9. **No new object, field, or tab**, therefore no permission-set edits, and
   `Rationale__c` stays unexposed to `GTM_Assessment_Guest` / `GTM_Story_Guest`.
10. **The org id literal.** Redact it from `TASK_SCOPE.md` before committing
    and never introduce it into a new file (§0, Correction 1).
11. **`CLAUDE.md`'s 98 lines.** Only the §2 path edits at lines 34 and 42 may
    change. Verify the wrapper's stub has not returned (§0, Correction 1b).
