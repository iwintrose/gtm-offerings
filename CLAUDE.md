# CLAUDE.md — GTM Offerings

Agent instructions for this repo. `AGENTS.md` is a symlink to this file — one
source of truth for Claude Code and any other agent tooling pointed at this
repo.

## 1. What this is

GTM Offerings is a Salesforce Lightning/Apex/LWC application, plus a guest-
facing Experience Cloud site, built for Publicis Sapient's BD/sales reps to
run go-to-market engagements. A rep sends a prospect an engagement link; the
prospect can read a configurable offering story, work through an AI-scored
assessment questionnaire, and later read a rep-authored, natively-approved
readout — all without logging in. Internally, reps and content authors work
in two Lightning apps: **GTM Offerings** (links, readouts, approvals) and
**GTM Content Manager** (instrument authoring, page content).

**Org status:** `gtm-dev` (org Id `00DgK00000XZieHUAT`) is treated as
**production**. There is no separate prod org. Every deploy, every seed
script, every destructive change lands on the org real prospects' data lives
in — there is no staging environment to make a mistake in first.

## 2. Repo layout

- `force-app/main/default/` — the SFDX source tree: `objects`, `classes`,
  `lwc`, `applications`, `tabs`, `permissionsets`, `approvalProcesses`,
  `customMetadata`, `experiences` (the Experience Cloud site), `flows`,
  `triggers`, `queues`, `profiles`, and more.
- `migration-accelerator/instrument/<offering-key>/*.yaml` — the assessment
  instrument's source of truth (questions, scoring, gates, branching pairs),
  **one directory per offering** since ADR-0007; `migration-accelerator/` is
  the only one today. **Author the YAML, never hand-edit the generated
  `force-app/main/default/customMetadata/GTM_Assessment_*` XML** — it's
  compiled by `scripts/build-instrument.py`, which validates each offering
  directory independently and stamps `Offering_Key__c` onto every record.
  The one exception is the 14 hand-authored `GTM_Assessment_Question.*`
  records, which the build script only reads (see §7).
- `migration-accelerator/*.html`, `index.html` (repo root) — a pre-Salesforce
  static-HTML prototype, not deployed anywhere in the current app. Left as-is
  in this pass; their fate (delete vs. keep) is an open call for a human, not
  this file's to make.
- `scripts/` — `deploy.sh`, `deploy-fresh-org.sh`, `build-instrument.py`,
  `check-references.py`, and `data/*.apex` seed/migration scripts.
- `data/seed/` — `sf data tree`-format seed JSON.
- `docs/architecture/` — this system's overview + ADRs.
- `docs/specs/` — per-feature Tier-2-style specs (pre-rename, verify names).
- `docs/runbooks/` — task-oriented operational procedures.
- `docs/backlog.md` — the living decision log, updated every working session.
- `docs/agent-artifacts/` — ephemeral agent output; promote to `architecture/`
  or `specs/` when worth keeping, don't treat as authoritative on its own.

## 3. Stack

Salesforce DX source format, `sf` CLI, API version 62.0 (`sfdx-project.json`).
Apex + LWC (Jest via `@salesforce/sfdx-lwc-jest`, `npm test`). Experience
Cloud (Aura/`ChatterNetworkPicasso` template — not LWR). No namespace; this
repo has no custom Claude Code sub-agents under `.claude/agents/` (there is
none — don't assume a sub-agent roster like a sibling project might have).

## 4. Deploy conventions — read this before running anything against `gtm-dev`

- **`./scripts/deploy.sh <org-alias> [--run-tests]`** — the deploy path
  actually run against `gtm-dev`, battle-tested. Two passes (everything,
  then `customMetadata` records separately, retried up to 4x on the flaky
  `GTM_Offering__mdt` seed record) — see the script for why.
- **`./scripts/deploy-fresh-org.sh <org-alias> [--run-tests] [--check-only]
  [--with-profiles] [--with-agent]`** — a different, more elaborate
  eight-pass script for a genuinely from-zero org. **Unverified** — its own
  runbook (`docs/runbooks/fresh-org-deploy.md`) says outright that nothing
  in this repo has ever been deployed to a fresh org, and to treat the first
  run as the test. Use `deploy.sh` for an org that already has its
  Experience Cloud sites and base setup (that's every deploy so far); reach
  for `deploy-fresh-org.sh` only for the from-zero case, and read its
  runbook's caveats first.
- **The `-c` flag is not dry-run.** In the installed `sf` CLI, `sf project
  deploy start -c` means `--ignore-conflicts`, **not** a dry run. The actual
  dry-run flag is `--dry-run` (no short alias). Assuming `-c` is safe to use
  as a dry run turns a "let me check this first" step into a live deploy —
  this has already happened once in this project's history. Always spell out
  `--dry-run`.
- **A metadata deploy only updates a site's draft.** Any deploy touching
  `force-app/main/default/experiences/` needs a publish afterward —
  `sf community publish -n "<site name>"` (or Experience Builder → Publish)
  — or guests keep seeing stale content. This is the Experience Cloud
  equivalent of an nginx reload: routine, and easy to forget.

## 5. Systemic gotchas

1. **FLS/permission-set gaps.** A new field, object, or tab is invisible to
   anything that respects field-level security until it's explicitly
   granted in a permission set — found and fixed multiple times on this
   project (`GTM_Saved_Configuration__c`, the `GTM_Content_Home` tab,
   `GTM_Readout__c`, `GTM_Readout_Version__c`, and a `GTM_Config_Manager`
   grant gap on `GTM_Page_Content__c`/`GTM_Page_Section__c` found during the
   `MA_`→`GTM_` rename). **Granting the relevant permission set(s) is part
   of a field/object/tab's definition of done, not a follow-up.** See
   ADR-0002. Check `force-app/main/default/permissionsets/` — the five are
   `GTM_Config_Manager`, `GTM_Config_View_All`, `GTM_Assessment_Guest`,
   `GTM_Story_Guest`, `GTM_Platform_Visibility`.
2. **Duplicate-detection rules.** A naive `insert Account`/`insert Contact`
   in a seed/demo script can hard-fail against standard duplicate rules in
   an org that already has similarly-named records. Fix: set
   `Database.DMLOptions.DuplicateRuleHeader.allowSave = true` before the DML
   — see `scripts/data/reset-accelerator-demo.apex` for the worked example.
3. **Single trigger point per side effect.** Never let an Apex class and a
   Flow both react to the same DML for the same outcome — a real double-send
   email bug came from exactly this. See ADR-0003.
4. **Dynamic Apex field/object access.** `Schema.getGlobalDescribe().get('X')
   .newSObject()` and string-built `Database.query()` are used deliberately
   in classes whose fields churn as the instrument/schema evolves, trading
   compile-time safety for deploy resilience. Currently:
   `GtmAssessmentRequestController`, `GtmFormDraftController`,
   `GtmLinkEventController` (dynamic `SObject` construction),
   `GtmFeedbackController`, `GtmHomeSnapshotController`, `GtmLegacyConfigId`,
   `GtmStageActionsController` (dynamic SOQL) — reconfirm with
   `grep -l "getGlobalDescribe\|Database.query" force-app/main/default/classes/*.cls`
   before trusting this list, it drifts. See ADR-0004.
5. **Sample/demo data must be verifiably non-real, not just differently
   labeled.** `scripts/data/reset-accelerator-demo.apex` seeds four wholly
   invented clients (`Northlight Media Group`, `Ashford Capital Bank`,
   `Solara Health Systems`, `Harborline Transit Authority`) after an earlier
   version used real company names by mistake — don't reintroduce a real
   name there. The one deliberate exception is
   `scripts/data/seed-cmc-sample.apex`'s use of the real Commercial Metals
   Company name — that's intentional, chosen by the user, and should not be
   "fixed" to a fictional name by an agent who doesn't know the history.
   The seed script being fixed doesn't guarantee the org's current data is
   clean — real-company Account names with no `(Demo)` suffix have shown up
   in `gtm-dev` before, so check what's actually there rather than assuming.
6. **`Network.allowInternalUserLogin` and who a site thinks is looking.**
   This field controls whether a logged-in internal Salesforce user opening
   a site URL is served the site's **rep** experience or its **guest**
   experience — with it `false`, an internal user got the guest view (Gus
   and the saved-links bar hidden, password prompts on their own links)
   even while authenticated into the org. It's `true` on both sites today.
   It's deliberately **not** in `force-app/` — a full `Network` metadata
   file would overwrite live site settings on every future deploy — so a
   regression here is invisible to any static check or `git diff`. Fix
   pattern: `sf project retrieve start --metadata "Network:<site name>"
   --target-metadata-dir /tmp/n`, edit `allowInternalUserLogin` in the
   retrieved file, deploy that one file back. The code-side half is
   `GtmViewerContext.isRep()` — `UserInfo.getUserType() == 'Standard'` — kept
   in its own class specifically so guest Apex access to it doesn't have to
   be granted through a class (`GtmSavedConfigurationController`) that would
   also expose `saveConfiguration`/`deleteConfiguration`/`searchContacts`.
7. **Route reachability is a property of the live site, not the source
   tree.** A route/page existing under `force-app/main/default/experiences/`,
   deploying cleanly, and passing `check-references.py` is not evidence a
   real prospect can reach it — see **ADR-0006**. Right now `GTM1`
   (`Network.Status = Live`) has only a `/configurator` route; the fuller
   story/industry/assessment/readout build lives on `GTM_Accelerator1`,
   which is `DownForMaintenance`. Before asserting a URL is live, check
   `Network.Status` for the target site, not just that the route exists in
   source. See `docs/architecture/overview.md`'s container diagram and
   `docs/backlog.md` D9 for the concrete, currently-tracked instance of
   this gap.

## 6. Packaging / distribution

Unpackaged SFDX + `scripts/deploy.sh` today; an **unlocked** package (not
managed — this is an internal accelerator, not ISV/AppExchange IP) is
deliberately deferred until there's a real second or third org to install
into, since a package can't carry `ExperienceBundle`/profiles/org state and
would only move part of the solution. Full reasoning: ADR-0001.

## 7. The assessment/readout/approval feature

Shape: instrument authoring → branching questionnaire → server-side scoring
→ auto-generated readout → native Approval Process → guest-viewable publish.
Full detail lives in `docs/runbooks/assessment-instrument.md` and
`docs/runbooks/readout-public-link.md` — read those, don't ask this file to
repeat them. The approval process is `GTM_Readout_Approval`
(`force-app/main/default/approvalProcesses/`); unassigned/unclaimed readouts
land in the `GTM_Readout_Triage` queue — both are Setup-UI objects an agent
can't `grep` for like Apex or LWC.

## 8. Where to find things

| Need | Look here |
|---|---|
| Feature specs | `docs/specs/` — pre-rename (`MA_`), verify names against code first |
| Runbooks | `docs/runbooks/`: `assessment-instrument.md` (instrument content/scoring), `readout-public-link.md` (readout link, approval, guest security), `questionnaire-resume.md` (save/resume), `fresh-org-deploy.md` (from-zero deploy, unverified), `experience-site-lifecycle.md` (deleting a component a site still references) |
| Decision log | `docs/backlog.md` — a jot pad, not architecture doc; updated every session |
| Architecture | `docs/architecture/overview.md` + `docs/architecture/adr/0001`–`0006` |
| Deploy | `DEPLOYMENT.md` first; `docs/runbooks/fresh-org-deploy.md` for the from-zero case |

## 9. Commands

```bash
# Dry run (the real one — see §4)
sf project deploy start --source-dir force-app/main/default/<dir> --target-org gtm-dev --dry-run

# Deploy (battle-tested path)
./scripts/deploy.sh gtm-dev --run-tests

# Run Apex tests directly
sf apex run test --target-org gtm-dev

# LWC unit tests
npm test

# Static reference audit — 0 deploy-blocking expected
python3 scripts/check-references.py

# Authoritative inventory counts — regenerate, never hardcode elsewhere
python3 scripts/check-references.py --inventory

# Instrument YAML/CMDT drift check
python3 scripts/build-instrument.py --check
```

## 10. What NOT to do

- Don't hand-edit generated `force-app/main/default/customMetadata/GTM_Assessment_*`
  XML — edit the YAML in `migration-accelerator/instrument/` and rebuild.
- Don't ship a new field, object, or tab without also touching the relevant
  permission set(s) in the same change (§5.1, ADR-0002).
- Don't use `-c` expecting dry-run behavior — it means `--ignore-conflicts`.
- Don't add a Flow and an Apex trigger/class reacting to the same DML (§5.3,
  ADR-0003).
- Don't "fix" `seed-cmc-sample.apex`'s use of a real company name — that
  one's intentional (§5.5).
- Don't trust `docs/specs/*.md` symbol names without checking current code
  first — they predate the `MA_`→`GTM_` rename.
- Don't claim a route/URL is "live" from source or a passing static check
  alone — verify the target site's `Network.Status` first (§5.7, ADR-0006).
- Don't treat `gtm-dev` as anything other than production — there is no
  separate prod org to make mistakes in first.
