# TASK SCOPE — ISSUE #test-efficiency

Status: SCOPE ONLY. No code, config or org call was made to produce this. Everything about plugin names, rule names, CLI request counts and scratch-org limits is UNVERIFIED (no web or doc tool was available to the BA); the Architect must confirm each against Salesforce docs before designing (feedback: Architect checks docs before custom-building). Base: origin/main at dc5005c (includes #238 to #244).

## 1. Requirements Breakdown

- **Target Objective:** Stop the API-limit and governor-limit failures from repeating. gtm-dev (Developer Edition, treated as Production) has been over its daily request limit (`TotalRequests Limit exceeded`) since 2026-09-18 and is unusable; agent deploys, retrieve-backs, queries and test-run polling consumed it. All work now runs on gtm-staging (own quota) and must stay inside a budget. User question: does running local raise the chance of not blowing API and governor limits, and is there another way to optimize? User decision: all three pieces are logical. Answer in short: local static analysis and Jest cost zero org requests, so yes for API limits; they cannot exercise Apex governors (per-transaction, org-only), so governor safety needs (a) static anti-pattern detection locally and (b) bulk/limit-assertion Apex tests run on gtm-staging. Three pieces:
  1. Local static analysis for Apex and LWC (zero org calls), baseline-diffed in `scripts/check-all.sh` and `.github/workflows/agent-ci-gate.yml`.
  2. Governor-aware Apex test pattern (200-record bulk plus `Limits.*` assertions) and a ranked candidate list.
  3. An API-request budget for agents and scripts, cheaper patterns, script guards, and an evaluation of scratch orgs vs gtm-staging as the single test org.
- **System Component Impacted:** Tooling and CI (no product behaviour): `scripts/check-all.sh`, a new analyzer config file and baseline file (Architect to place), `.github/workflows/agent-ci-gate.yml`, `scripts/deploy.sh`, `scripts/deploy-fresh-org.sh`, `scripts/check-org-drift.py`, `scripts/seed-synthetic-data.py`, a new budget doc under `docs/runbooks/`, optionally a new `config/project-scratch-def.json` (does not exist; `config/` directory does not exist). Apex test classes under `force-app/main/default/classes/` for piece 2. No LWC, Experience Cloud route, YAML instrument or GUS tool surface change.
- **Ambiguities / human decisions (not settled here):** (a) which piece first; (b) whether scratch orgs are wanted at all; (c) the CI gate still authenticates to gtm-dev via JWT secrets and runs a metadata `--dry-run` there on every agent PR push (see 3.3 finding F1) -- whether to repoint it to gtm-staging or drop it is a human call because it concerns a Production org; (d) anything touching gtm-dev data or config is out of bounds for this task.

### 1.1 What is verified from the repo vs not

VERIFIED (read from files):
- `scripts/check-all.sh`: `run "<label>" <cmd>` counts failures; static checks are `check-content-contract.py`, `check-references.py`, `check-configurator-bindings.mjs` (via `lwc-node-harness.sh`); live checks (page order, five `check-live-page-contract.mjs` pairs = 6 org-reading steps) are skipped with `--static`. Default org is `gtm-dev` (`ORG="${SF_TARGET_ORG:-gtm-dev}"`), which is now wrong and dangerous: a bare `check-all.sh` targets the locked Production org.
- `agent-ci-gate.yml` runs on `agent/issue-*` pushes and PRs: scope-file check, `npm ci`, `npm test` (Jest), `backfill-link-owner.py --check`, and a baseline-diff of `check-references.py` and `build-instrument.py --check` against a fresh `origin/main` worktree (extract "  x " findings, `sort -u`, `comm -23`, fail only on new ones). Then `npm install --global @salesforce/cli`, JWT login to gtm-dev using secrets, and `sf project deploy start --dry-run --ignore-conflicts` of the whole `force-app/main/default` (skipped with a warning if secrets are missing).
- `package.json` has only `sfdx-lwc-jest` scripts; there is no ESLint/Prettier script, no `.eslintrc`, no `.sf`/`.sfdx` dir, no `config/`. `sfdx-project.json` has two package dirs (`force-app`, `test-fixtures`), API 62.0, no scratch settings.
- 130 Apex files under `classes/` are test-related by name (`*Test*`); production classes doing SOQL/DML are listed in section 2 of the inventory below (approximate `grep` counts, single-line patterns only, so multi-line SOQL may be undercounted).
- Existing tests that already use `Limits.*`: `GtmStageActionsControllerTest` (9), `GtmLinkStageServiceTest` (6), `GtmReadoutPublishNotificationTest` (5), `GtmAgentProxyControllerTest` (5), `GtmStageFilterAppToolTest` (4), `GtmAgentProxyControllerReadoutTest` (2), `GtmOverviewOfferingCountsTest` (2). Tests with loops of 30 to 200+ iterations: `GtmAssessmentListControllerTest`, `GtmLinkStageServiceTest`, `GtmLinkEventBatchTest`, `GtmPageContentControllerTest`, `GtmSavedConfigurationControllerTest` (the exact loop bounds and whether they assert limits must be re-read by the Architect; the grep only shows a loop with a bound of 30 to 299 exists).
- Org-touching scripts and their `sf` calls: `deploy.sh` (pass 1 `deploy start --wait 60`, pass 2 `deploy start --wait 30` with up to 4 retries, `sleep 10`), `deploy-fresh-org.sh` (9 passes; `sf project deploy start` per pass with `--wait 60`, `sf project convert source` local, one combined `--metadata-dir` deploy, two `sf org display --json`, two `sf data query --json`, `sf org assign permset` per set, `sf data import tree` per seed file with an idempotency query first, optional `sf apex run test --test-level RunLocalTests`), `check-org-drift.py` (one `sf project retrieve start --target-metadata-dir` per invocation, timeout 600, components from `git diff --name-only HEAD`), `seed-synthetic-data.py` (`sf data import tree`, and `sf data delete bulk` per step on teardown), `check-live-page-contract.mjs` and `check-page-order.mjs` (query the org, count unverified). `deploy.sh` guards only the Opportunity layouts for the alias `gtm-dev`; it does NOT refuse to run against gtm-dev.

NOT VERIFIABLE from the repo (mark UNVERIFIED for the Architect): Code Analyzer plugin name and install command, rule names and engine names, whether `sf code-analyzer` is GA vs the `sf scanner` plugin retirement status, output formats and exit-code semantics, per-command CLI request counts, scratch-org lifetime and active-org limits, whether a Developer Hub in gtm-staging allows the counts assumed here, whether the ChatterNetworkPicasso Aura site shell deploys to a scratch org.

## 2. Inventory

### 2.1 Piece 1 -- local static analysis (candidate tooling, all UNVERIFIED)

Salesforce first: native beats a custom regex script. Candidate: Salesforce Code Analyzer (`sf code-analyzer` v5, plugin `@salesforce/plugin-code-analyzer`; install via `sf plugins install code-analyzer`) UNVERIFIED. It wraps PMD (Apex rules), ESLint (LWC, via `@salesforce/eslint-config-lwc` and the LWC/`@lwc/eslint-plugin-lwc` rules), and possibly regex, retire-js, flow and sfge engines (sfge = graph engine, slower, needs Java) UNVERIFIED. Older alternative: `sf scanner` (`@salesforce/sfdx-scanner`, `sf scanner run`); UNVERIFIED whether it is now retired in favour of code-analyzer. Both need Java 11+ for PMD (UNVERIFIED) -- check the GitHub runner image (ubuntu-latest normally has Java, UNVERIFIED) and the dev machines.

Target rules (names are candidates, UNVERIFIED): PMD Apex `OperationWithLimitsInLoop` (SOQL/DML in loops), `AvoidDmlStatementsInLoops`, `AvoidSoqlInLoops`, `ApexCRUDViolation` (CRUD/FLS), `ApexSOQLInjection` (missing bind variables), `AvoidHardcodingId`, `ApexSharingViolations`, `AvoidDebugStatements` (optional), and for unbounded queries there may be no stock rule (mark as a gap; a small custom PMD XPath rule or a `check-apex-soql.py` regex for `[SELECT ... FROM ...]` with no `LIMIT`/`WHERE` would be custom and must be justified only if no native rule exists). ESLint side: `@lwc/lwc/*` rules only; low value for governor safety, include only as a cheap baseline.

Repo-specific caution: this codebase has 60+ production Apex classes with `with sharing`/`without sharing` mixes and only 2 classes referencing `WITH USER_MODE`/`stripInaccessible`/`security_enforced` (`GTM_RecycleBinController`, `GtmInstrumentController`), so `ApexCRUDViolation` will produce a large first baseline. Do not "fix while baselining"; the baseline approach exists exactly to avoid that.

Baseline capture (proposed):
1. Add a minimal config (Architect places it, e.g. `code-analyzer.yml` at the repo root) that selects only the rules above, scoped to `force-app/main/default/classes` (exclude `*Test*.cls` for the governor rules) and `force-app/main/default/lwc` (exclude `__tests__`).
2. Run once against `origin/main` locally, outputting machine-readable JSON or CSV (format UNVERIFIED).
3. Reduce each finding to a stable key that survives line drift: `<rule>|<file>|<enclosing method or class>|<hash of the flagged source line>` (not the line number). Sort unique, write to a committed `scripts/baselines/code-analyzer-baseline.txt` (or similar).
4. The gate re-runs on the branch, builds the same keys, and fails on `comm -23 branch baseline`. Findings that disappear are allowed; an optional `--update-baseline` mode removes them (ratchet only goes down). Keep the two-run "branch vs fresh origin/main worktree" method already used for check-references.py as the alternative when the baseline file would create merge conflicts across parallel agent PRs (the existing CI approach recomputes main each run and never conflicts; recommend it for consistency; a committed baseline file is faster locally).
5. Suppression: prefer `// NOPMD` with a reason comment for reviewed false positives over baseline growth.

### 2.2 Piece 2 -- governor-aware tests: candidate classes (approx counts: SOQL / DML statement lines / sharing keyword hits)

Highest risk = user-driven volume plus queries or DML that could sit in a loop or scale with rows, and used by rep-facing list screens or bulk actions:

| Rank | Class | SOQL / DML (approx) | Why |
|---|---|---|---|
| 1 | `GtmAssessmentListController` | 3 / 0 | Feeds the Assessments tab list; filters, rollups over all assessments; volume = every assessment in the org. Test already loops (size to verify). |
| 2 | `GtmLinkStageService` | 3 / 0 | Stage computation over links and events for filters and the GUS stage tool (#233); volume = all links. Test already has 6 `Limits.` uses; extend to 200 links. |
| 3 | `GtmPageContentController` | 4 / 19 | Highest DML count; page and section content save/copy; likely per-section DML. Test has loops; verify limit assertions. |
| 4 | `GtmSavedConfigurationController` | 3 / 12 | Save/clone configuration; DML across multiple sObject types. |
| 5 | `GtmReadoutController` | 5 / 12 | Highest SOQL count; readout and comment loading, publish. Also `GtmReadoutApprovalHandler`, `GtmReadoutCommentController`, `GtmReadoutPublicController` (guest/public path, queries per request), `GtmReadoutAgent*` (read-only tool surfaces; must stay zero-DML per AGENTS.md section 1). |
| 6 | `GtmAssessmentRequestController` | 0 / 12 | 12 DML lines on a guest/prospect path. |
| 7 | `GtmPageSectionController` | 1 / 11 | Section save DML. |
| 8 | `GtmHomeSnapshotController`, `GtmAnalyticsTeamController`, `GtmOverviewOfferingCounts`, `GtmActTodayController` | 4/0, 2/0, 2/0, n/a | Aggregations for the Overview dashboard (#234, #236); read-only, watch query count and row counts; `GtmOverviewOfferingCountsTest` already uses `Limits`. |
| 9 | Batch/scheduled: `GTM_PurgeRecordsBatch`, `GtmAssessmentDraftPurge`, `GtmAnalyticsDigestJob`, `GtmLinkEventBatch` | | Bulk by design; assert batch scope of 200 completes. |
| lower | `GtmStageActionsController`, `GtmFeedbackController`, `GtmLinkEventController`, `ConduitCmmController`, `GtmInstrumentController`, `GtmOfferingArchiveCascadeHandler` and the trigger handlers | | Small volumes or already bulk-tested (`GtmStageActionsControllerTest` asserts limits). |

Recommendation for "bulk test first" (smallest correct set): ranks 1 to 4 (`GtmAssessmentListController`, `GtmLinkStageService`, `GtmPageContentController`, `GtmSavedConfigurationController`). For each, add ONE test method: insert 200 parent records (Test.startTest/stopTest around the call), call the public entry point, assert `Limits.getQueries()` is under a fixed ceiling that does not depend on N (e.g. the count measured with 1 record must equal the count with 200, or `<= 10` as a stated ceiling) and `Limits.getDmlStatements()` likewise, and `Limits.getDmlRows()` equals the expected N. The "same query count at 1 vs 200 records" assertion is the strongest, catches SOQL-in-loop regardless of absolute limits, and needs no magic numbers. Follow test-data rules in CLAUDE.md section 6 (duplicate rules: use unique emails/tokens). Tests run only in an org, so this is run on gtm-staging, one targeted `sf apex run test --class-names ... --synchronous` per changed class, not `RunLocalTests`.

### 2.3 Piece 3 -- API-request budget inventory (all request counts are ESTIMATES, UNVERIFIED)

Model: a Metadata API deploy = 1 request to start, then status polling. `--wait N` polls every few seconds (UNVERIFIED interval, likely a few seconds) so a 60-minute wait on a slow deploy can cost tens of polls. Each `sf data query` = 1 REST call (plus 1 for auth refresh when the token expired). `sf org display` = 1 to 2 calls (UNVERIFIED; it may refresh the token and query user info). `sf org list --json` prints access tokens, which is a secret-hygiene problem regardless of cost. `retrieve start` = 1 start + polls + 1 fetch. `apex run test` async = 1 enqueue + polls (default polls each few seconds) + 1 to 3 result queries; `--synchronous` = 1 call but only one class at a time (limit UNVERIFIED).

| Action | Where | Est. requests (UNVERIFIED) | Notes |
|---|---|---|---|
| Dry run of `force-app` | CI gate, agent QA | about 10 to 40 | Full-tree validation; the CI gate does this on every agent push if the JWT secrets exist. |
| Real deploy, small bundle | `sf project deploy start --source-dir <changed>` | about 5 to 20 | Cost driven by polling, not size. `--async` then one `sf project deploy report` cuts polls to about 3. |
| Full `deploy.sh` | pass 1 + pass 2 (up to 4 retries) | about 20 to 100+ | Retries on flaky `GTM_Offering__mdt` multiply cost; each retry re-polls. |
| `deploy-fresh-org.sh` | 9 passes, org display x2, query x2 to 6, permset assign x5, seed import per file | about 100 to 300 | Blank orgs only; one-off. |
| Retrieve-back (drift check) | `check-org-drift.py` | about 5 to 25 per run | Repeated after every deploy in the current workflow; skippable for LWC-only changes. |
| Targeted test run | `apex run test --class-names X` | about 5 to 30 | Poll-driven. `RunLocalTests` on 130 test files is far larger (polls for minutes). |
| Live checks in check-all.sh | 6 node scripts | about 6 to 60 (unverified per script) | Default org is gtm-dev; must change. |
| Seed/teardown | `seed-synthetic-data.py` | tree import 1 to few per file; bulk delete 1 + polls per object | Use bulk API for volume; preflight queries per object add up. |
| Status/health polls by agents | ad hoc `sf org display`, `sf data query` | 1 to 2 each | The unbudgeted class of spend; agents repeat them. |

Findings:
- **F1 (high):** `.github/workflows/agent-ci-gate.yml` logs into gtm-dev with JWT secrets and dry-runs the entire tree on every agent branch push and PR. If the secrets are set, every push burns gtm-dev quota and touches Production. The workflow itself warns the secrets may be unset (UNVERIFIED whether they are). Needs a human decision (repoint to gtm-staging secrets, or drop the step and rely on local checks plus a staging dry-run by the agent). This scope does not change it without that decision.
- **F2 (high):** `scripts/check-all.sh` defaults `ORG` to `gtm-dev`. `deploy.sh` and `check-org-drift.py` accept gtm-dev without an explicit override.
- **F3:** `deploy.sh` pass 2 retries up to 4x with `--wait 30`; `deploy-fresh-org.sh` calls `sf org display` twice and repeats `sf data query` idempotency checks.
- **F4:** `check-org-drift.py` retrieves after each change, including LWC-only changes that Jest already covers.

Cheaper patterns (recommended, ranked below): skip retrieve-back for LWC-only changes (Jest plus one confirming check); skip the dry run for small bundles (a real deploy to staging validates as well and costs about the same); one batched deploy per group of merged PRs; `--async` deploy plus a single `sf project deploy report`; avoid `sf org display` and never use `sf org list --json` (prints tokens); bulk API (`sf data import bulk` / `delete bulk`) for data volume; cache one org-info lookup per session; a documented per-change budget; a script guard.

Guard design (for the Architect): a shared helper sourced by the scripts (`scripts/lib/org-guard.sh` or similar) that (1) refuses org alias `gtm-dev` (case-insensitive, same pattern `deploy.sh` uses) unless `--i-know-this-is-production` (name to be decided) is passed; (2) counts `sf` invocations via a shell function wrapper `sfx()` writing to a per-run counter file and prints a summary; (3) warns (not fails) when the count exceeds a documented N; (4) defaults `check-all.sh` ORG to `gtm-staging` or requires `SF_TARGET_ORG`. A wrapper counts CLI invocations, not true HTTP requests (each invocation is several requests); the guard is a proxy, state that honestly. Optionally the org's own usage can be read from `sf limits api display` but that call itself costs a request and would fail on a limit-exceeded org, so do not depend on it.

### 2.4 Scratch orgs vs gtm-staging as the single test org

Facts: repo has NO `config/project-scratch-def.json`; gtm-staging has Dev Hub enabled (per user; unverified in repo, though `docs/runbooks/gtm-offerings-install.md` line 29 lists Dev Hub as optional). Scratch orgs have their own API quota per org (UNVERIFIED; commonly stated as a per-org limit). Lifetime: default 7 days, max 30 (UNVERIFIED). Active scratch orgs per Dev Hub: about 40 for Developer Edition Dev Hub, about 3 in some trial/DE configurations (UNVERIFIED, must check the actual number in the Dev Hub's Limits). Daily creation limit also exists (UNVERIFIED).

Org shape needed (from `docs/runbooks/gtm-offerings-install.md` sections 1 and deploy pass 8 and 9): edition Developer; features `ExperienceBundle`/Digital Experiences (`Communities` feature and `networkEnabled` UNVERIFIED names), `Chatter`; settings `communitiesSettings` (`enableNetworksEnabled`, digital experiences enabled), `lightningExperienceSettings`, `enableMyDomain`/`myDomainSettings` (My Domain is required before Digital Experiences), possibly `Sharing` model for Opportunity/Account, Leads and Duplicate Rules (CLAUDE.md section 6), and whatever the `settings/` directory in `force-app/main/default/settings` already carries (Architect to read it and derive the definition from it rather than duplicating). Opportunity layouts: the four Opportunity-* layouts are safe on a fresh org, which is exactly why a scratch org (or fresh org) is the right target for install and blank-install tests. Agentforce/bots are excluded by default (`--with-agent` off) and would not be provisioned in scratch either.

Open technical risk: whether the ChatterNetworkPicasso Aura site shell (Network + CustomSite + ExperienceBundle in one combined deployment, pass 9, which the runbook says a validation cannot fully prove) deploys into a scratch org. Cannot be determined from the repo. A time-boxed spike on gtm-staging's Dev Hub is the only way to know; treat the answer as unknown until then.

Bounded-cost agent lifecycle (proposal): `sf org create scratch --definition-file config/project-scratch-def.json --duration-days 1 --alias agent-<id> --set-default` (about 5 to 15 requests, UNVERIFIED), `sf project deploy start` per scripts/deploy-fresh-org.sh (about 100 to 300, its own quota, not gtm-staging's), `sf apex run test`, then `sf org delete scratch --target-org agent-<id> --no-prompt` (1 to 3). Requests on the scratch org do not count against gtm-staging or gtm-dev; create/delete count against the Dev Hub (small). Use a 1 day duration so an abandoned org expires on its own.

Comparison:
- gtm-staging as single test org: zero setup, has real data shape and site; but one shared quota and shared state (parallel agents collide), so a runaway agent can lock it like gtm-dev.
- Scratch per agent task: isolated quota and state, clean blank-install test, cheap teardown; but needs a definition file (new config), a 100 to 300 request full deploy each time (so use it for install/blank-install tests, NOT for every small change), and the site shell may not deploy. Recommendation: keep gtm-staging for day-to-day targeted deploys and Apex tests; add scratch orgs only for blank-install and install-runbook validation, and only after the spike answers the site-shell question.

## 3. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO. No tool surface changes. Piece 2 tests must not add DML to any `GtmAgentToolSurface` implementation; the analyzer, if it flags DML in `GtmReadoutAgent*`/`GtmAppTool`, supports the zero-DML rule in AGENTS.md section 1 rather than violating it.
- [ ] Altering Custom Metadata? NO. No `customMetadata/GTM_Assessment_*` or `migration-accelerator/` YAML change. (Note the CLAUDE.md wording refers to `instrument/<offering-key>/`; nothing there changes.)
- [ ] Introducing database fields? NO. No new fields, objects or permission set mapping. (If a future guard stores a counter it must live in a local temp file, never in an org object.)

Other dependencies: a new Node/Java toolchain dependency (Java for PMD) affects `.github/workflows/agent-ci-gate.yml` and `scripts/check-all.sh` (which currently needs only python3 and node); `package.json` may gain a `devDependency` or the CLI plugin is installed at run time (Architect to choose; prefer a cached CI install to keep the added seconds small). No `.forceignore` change needed unless a config file lands under `force-app/`; keep new files outside `force-app/`. Any change to `agent-ci-gate.yml` that removes the gtm-dev dry-run is gated on the human decision above.

## 4. Recommendation (ranked by requests saved x ease)

| Rank | Item | Requests saved | Ease | Notes |
|---|---|---|---|---|
| 1 | Script guard: refuse gtm-dev without an explicit flag; `check-all.sh` default org off gtm-dev; per-run `sf` call counter with warning | High (prevents the recurring failure class) | Easy, pure bash | Also fixes F2. |
| 2 | Documented request budget table plus workflow rules (skip retrieve-back for LWC-only, skip dry run for small bundles, batch merged PRs, `--async` + one `report`, no `sf org display`/`sf org list --json`, bulk API) | High | Easy, docs only | Ships with rank 1. |
| 3 | CI gate F1: stop hitting gtm-dev (repoint or remove the dry-run) | High if secrets are set, else none | Easy but needs human sign-off | Human decision. |
| 4 | Local static analysis with baseline diff | Medium (fewer failed deploys/test reruns; zero org calls itself) | Medium: tool install, Java, baseline capture | Best governor coverage without an org. |
| 5 | Bulk/limit-assertion tests for ranks 1 to 4 classes | Low for requests (adds a few test runs) but the only real governor proof | Medium; needs staging runs | Run targeted, not RunLocalTests. |
| 6 | Scratch orgs for blank-install tests | Medium for staging quota, only for install validation | Hard: definition file, site-shell spike, 100+ request deploy each | Optional; defer until wanted. |

Smallest correct set: ranks 1 + 2 (plus 3 once decided) now; rank 4 next; rank 5 for the four classes; rank 6 only if the user wants scratch orgs.

## 5. Plan Acceptance Criteria

- **Success Metric:** Measurable without an org where possible.
  1. Static analysis: `scripts/check-all.sh --static` runs the analyzer with zero `sf` org calls (the analyzer step does not require an authenticated org; verify by running with no default org configured and with network access to Salesforce blocked), completes in under 60 seconds on a CI runner for the full Apex and LWC tree (target N=60, tune after the first measurement), exits nonzero when a synthetic new SOQL-in-loop or DML-in-loop finding is added to a test branch and zero when only baselined findings exist. The baseline file exists, is deterministic (two consecutive runs produce identical sorted keys), and lists at least the pre-existing findings; a documented refresh command exists.
  2. Guard: running `scripts/deploy.sh gtm-dev` (and `check-all.sh`, `check-org-drift.py`, `deploy-fresh-org.sh`) without the explicit production flag exits nonzero before any `sf` call; verifiable with a stub `sf` on PATH that records invocations and shows zero calls. The counter prints a per-run total and warns above the documented N.
  3. Budget: a `docs/runbooks/` document contains a per-change budget table (dry run, deploy, retrieve-back, targeted test run, status poll, seed) with estimates labelled UNVERIFIED until measured once on gtm-staging (measure via a counter, not the org), the rules listed in section 2.3, and the gtm-dev lock note.
  4. Governor tests: for each of the four first-wave classes there is one bulk test that inserts 200 records and asserts the query count is unchanged from the 1-record case and DML statements are at or below the stated ceiling; they pass on gtm-staging in a single targeted run of the four classes (one run recorded in the QA log). Existing Apex tests remain green.
  5. Scratch orgs (only if wanted): `config/project-scratch-def.json` exists with no org IDs, usernames or secrets; a documented create/deploy/test/delete sequence with an explicit request estimate; spike result recorded on whether the site shell deploys.
  6. No file added or changed contains an org ID, username, token or secret; no command in the work targets gtm-dev.
- **Target Test Target:** Offline: `npm test` (the existing LWC Jest suite must stay green; no new Jest spec needed since no LWC changes), `scripts/check-all.sh --static` (with the analyzer step and baseline check), the guard stub-`sf` test (a new shell test script, Architect to name it), and `python3 scripts/check-references.py` / `scripts/build-instrument.py --check` unchanged versus main. Org-side (gtm-staging only): `sf apex run test --class-names GtmAssessmentListControllerTest,GtmLinkStageServiceTest,GtmPageContentControllerTest,GtmSavedConfigurationControllerTest --target-org gtm-staging --synchronous` or the equivalent async run (exact new test method names decided by the Architect).

## 6. Risks

- Analyzer false-positive noise and a huge initial CRUD/FLS baseline; mitigated by baseline-diff and rule minimalism. Baseline keys drift with refactors (mitigated by keying on rule|file|method|line-hash, not line numbers).
- Java dependency and tool startup time on CI and agent machines (sfge especially); keep to PMD and ESLint only. Plugin/CLI versions unverified and change fast; pin versions.
- Static analysis cannot prove governor safety (dynamic paths, recursion, triggers firing across objects); bulk tests on staging are still required.
- CLI-invocation counters undercount real HTTP requests; the budget is a proxy and its estimates are UNVERIFIED until one measured run.
- Removing the CI dry-run reduces deploy-blocking feedback; mitigate with `check-references.py` and a staging dry-run by the agent.
- Scratch org site-shell deploy may not work; a scratch org run of `deploy-fresh-org.sh` is 100 to 300 requests and 9 passes, so it can still be expensive; a runaway agent can also exhaust the Dev Hub's daily scratch creation allowance (UNVERIFIED).
- Bulk tests run only on gtm-staging (own quota); 200-record inserts must respect Duplicate Rules and unique tokens (CLAUDE.md section 6), and staging tests must never be pointed at gtm-dev by the guard.
- Overlap: `docs/agent-artifacts/task-scope-local-validation-expansion.md` already covers static metadata checks in `check-references.py` (permission sets, picklists). This task adds Apex/LWC analysis and a request budget and must not duplicate it; the Architect should read that file first.

## 7. Jest / CI impact

- Jest: none. No LWC change, so `npm test` is unchanged. If the ESLint LWC rules run via the analyzer, `__tests__` and fixtures stay excluded (they are already `.forceignore`d from deploy).
- CI (`agent-ci-gate.yml`): add one step (analyzer plus baseline diff) before the org steps; add Java setup if needed; keep the step under a stated time budget; the metadata dry-run step against gtm-dev is flagged for a human decision (F1). `scripts/check-all.sh` gains an analyzer `run` line in the static block and a changed default org.
- No change to `agent-workspace.sh`, `deploy-fresh-org.sh` behaviour beyond the guard.

## 8. Open questions for the user

1. Which piece first? Recommended order: (3) guard + budget doc, then (1) static analysis, then (2) bulk tests.
2. Scratch orgs: wanted at all, or is gtm-staging as the single test org enough? If wanted, only for blank-install tests, after a time-boxed spike on the site shell.
3. CI gate F1: are the JWT secrets currently set (does CI hit gtm-dev on every push)? Repoint to gtm-staging or remove the dry-run?
4. Is Java acceptable as a new tool requirement on dev machines and CI for PMD?
5. Should the request budget N be a warning only, or a hard refusal above a threshold?
6. Static analysis scope: Apex only first, or Apex and LWC together?
