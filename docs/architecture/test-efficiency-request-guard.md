# Contract: org-request guard, call counter and request budget (test-efficiency, piece 1)

Status: design, Architect step. Scope: `docs/agent-artifacts/task-scope-test-efficiency.md`, piece 1 only (script guards and the API-request budget doc). Pieces 2 (static analysis) and 3 (bulk/governor tests) and the scratch-org spike are out of scope here. This change is scripts, one workflow file and docs only: no Apex, no LWC, no metadata, no YAML instrument, no GUS tool surface, no fields, no permission sets. Nothing in it contacts an org.

Web/doc tooling was NOT available to the Architect. Every claim about Salesforce CLI behaviour, request counts and file formats below is marked UNVERIFIED and must be confirmed by one measured run on gtm-staging (using the counter, not the org).

## 1. Verified findings (against origin/main dc5005c)

| ID | BA claim | Result |
|---|---|---|
| F2a | `scripts/check-all.sh` defaults org to gtm-dev | CONFIRMED, line 9: `ORG="${SF_TARGET_ORG:-gtm-dev}"`. |
| F2b | `deploy.sh` accepts gtm-dev with no override; guards only Opportunity layouts | CONFIRMED. Lines 98-105 set `IS_PROD_ALIAS` and lines 120-134 only skip the four `Opportunity-*` layouts; the deploy itself still runs. Matched on the typed alias only. |
| F2c | `check-org-drift.py` accepts gtm-dev | CONFIRMED, line 26: `os.environ.get("SF_TARGET_ORG", "gtm-dev")`. |
| F3a | `deploy.sh` pass 2 retries up to 4 times | CONFIRMED, lines 180-192 (`CMDT_ATTEMPTS=4`, `--wait 30`, `sleep 10`). |
| F3b | `deploy-fresh-org.sh` calls `sf org display` twice | PARTLY. The calls are at lines 290 and 377 but the second runs only when `AUTH_USER` is empty (env sender email set, or the first lookup failed). Typical run: one call; worst case: two. Not a fixed two. Cheap fix in this change: remember a failed lookup so the second call is skipped. |
| F4 | `check-org-drift.py` retrieves back even for LWC-only changes | NOT CONFIRMED. `KINDS` (lines 29-35) is ApexClass, PermissionSet, Profile, CustomApplication, FlexiPage; LWC is not a kind, so `--changed` on an LWC-only diff prints "Nothing to check." and makes no `sf` call. The retrieve-back that costs requests for LWC-only work is an agent habit (ad hoc retrieve), not this script. The budget doc still carries the rule. Note `--changed` uses `git diff --name-only HEAD`, so it sees only uncommitted changes. |
| New-1 | (not in BA scope) | Node scripts `check-page-order.mjs` (line 42) and `check-live-page-contract.mjs` (line 33) fall back to `''` and then omit `--target-org`, so `sf` uses whatever default org is configured on the machine, which can silently be gtm-dev. The guard must treat "no explicit org" as a refusal. |
| New-2 | | `seed-precheck.py` (line 44), `seed-synthetic-data.py` (`run_sf`, line 387) and `backfill-link-owner.py` (line 214) also call `sf`; they need the same wrapper. `backfill-link-owner.py --check` and `seed-synthetic-data.py --check` are offline and stay unguarded. |
| F1 | CI logs in to gtm-dev via JWT | Coordinator confirmed no secrets are set, so the step has always skipped. Still repointed (section 5). |

## 2. Design: one wrapper, `scripts/lib/sfx`

A single executable bash file is the only place that runs `sf` for repo scripts. Bash scripts call it, Python scripts `subprocess` it, Node scripts `execFileSync` it. One implementation, one self-test. Bash 3.2 compatible (macOS).

### 2.1 Interface

```
scripts/lib/sfx --session [--allow-production] -- <command> [args...]   # start a counted session, run command, print summary
scripts/lib/sfx <sf args...>                                             # guarded, counted sf call (needs a session)
```

`--session` creates a per-run counter file (`mktemp`, mode 600, under `${TMPDIR:-/tmp}`), exports:

- `SF_GUARD_COUNT_FILE` (absolute path of the counter file)
- `SF_GUARD_SFX` (absolute path of `sfx` itself; children use this so a Node script running from the copied harness directory still finds it)
- `SF_GUARD_ALLOW_FLAG=1` only if `--allow-production` appeared in the session wrapper's own args or in the command args after `--` (the entry script must then treat `--allow-production` as a known no-op option)

runs the command, then prints the summary (section 2.3) on exit through a trap, preserving the command's exit status, and removes the counter file.

Entry scripts join a session with a re-exec at the top (before argument parsing):

```bash
# bash entry script
SFX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/sfx"
[ -x "$SFX" ] || { echo "sfx guard helper missing: refusing to run" >&2; exit 70; }
[ -n "${SF_GUARD_COUNT_FILE:-}" ] || exec "$SFX" --session -- "$0" "$@"
```

```python
# python entry script: scripts/lib/sf_guard.py
from lib import sf_guard;  sf_guard.ensure_session()   # os.execv into `sfx --session -- python3 <script> <argv>` when SF_GUARD_COUNT_FILE unset; SystemExit(70) if sfx missing
sf_guard.sf(["project", "retrieve", "start", ...], capture=True)  # subprocess.run([SF_GUARD_SFX, ...]); returns CompletedProcess
```

Node scripts do not self-join: they read `process.env.SF_GUARD_SFX` and throw (fail closed) when unset, with the message "run via scripts/check-all.sh or `scripts/lib/sfx --session -- node ...`". `sf_guard.py` is a thin (under 60 lines) module; all policy lives in `sfx`.

### 2.2 Guard rules (evaluated before any `sf` process starts)

1. Fail closed: if `SF_GUARD_COUNT_FILE` is unset, not a writable regular file, or `SF_GUARD_SFX` is unset, exit 70 with "cannot count sf calls: refusing to run sf". A missing `sfx` file is caught by the caller stubs above (exit 70). If appending to the counter fails, exit 70 without running `sf`.
2. Local-only commands are exempt from both the org guard and the count (they make no org request): first words `project convert`, `project generate`, `--version`, `version`, `help`, `plugins`, `config`, `alias`. Everything else is org-bound and counted. Unknown first words are org-bound (fail closed).
3. Org resolution: the value after `-o`, `--target-org` (also `--target-org=<v>` and `-o<v>`), else `$SF_TARGET_ORG`, else REFUSE ("no explicit org: pass -o/--target-org; the machine default org is never used"). This closes New-1.
4. Refuse if the lowercased org value equals any entry of the lowercased, comma-separated `SF_GUARD_PROD_ALIASES` (default `gtm-dev`; the variable can only add, never remove: implementation is `gtm-dev,${SF_GUARD_PROD_ALIASES:-}`).
5. Raw usernames without an org call: any org value containing `@` is REFUSED outright ("use the alias"), because the mapping from username to org cannot be known offline. Best effort on top: if a local alias file is readable (`$SF_HOME/alias.json`, `~/.sf/alias.json`, `~/.sfdx/alias.json`; format `{"orgs": {"<alias>": "<username>"}}` UNVERIFIED) and the given alias maps to the same username as `gtm-dev`, refuse it too. If no alias file is readable, only rules 4 and 5a apply and the runbook says so. No usernames are committed anywhere; the mapping is read from the developer's own machine at run time and never printed.
6. Production override: refusals from rules 4 and 5 are lifted only when BOTH `SF_GUARD_ALLOW_FLAG=1` (set by `--session` from `--allow-production`) AND `GTM_ALLOW_PRODUCTION=1` are present. Even then the run prints "PRODUCTION ORG: allowed by flag+env" to stderr. Doc rule: while gtm-dev is locked and until the coordinator unlocks it, nobody sets these.
7. Refusal message names the rule but never prints the org value beyond the alias the user typed, and never a username.

### 2.3 Counter and summary

- Each allowed org-bound call appends one line: `<epoch-seconds> <first two words of the sf command>` (for example `1790000000 project deploy`). Arguments are never recorded, so no org id, username, token, query text or path can leak.
- Summary printed to stderr at session end: `sf calls this run: <total>` and a per-command-head tally, then, when total exceeds `SF_GUARD_WARN_AT` (integer, default 50): `WARNING: <total> sf calls exceeds budget <N>; see docs/runbooks/api-request-budget.md`. Invalid `SF_GUARD_WARN_AT` (not a positive integer) fails closed with exit 70 at session start.
- Warn only; no hard cap (coordinator default 5). The only hard refusal is the gtm-dev rule.
- State honestly in the summary footer and the doc: this counts CLI invocations, not HTTP requests. One invocation costs several requests (UNVERIFIED).

## 3. Script changes (contract)

| File | Change |
|---|---|
| `scripts/lib/sfx` (new, executable) | The wrapper above. |
| `scripts/lib/sf_guard.py` (new) | `ensure_session()`, `sf(args, capture=False, **kw)`. No policy. |
| `scripts/check-all.sh` | Re-exec into a session. Parse args in a loop: `--static`, `--org <alias>`, `--allow-production`. Org = `--org`, else `SF_TARGET_ORG`, else none; NO default. If not `--static` and no org: print usage, exit 2 before any check runs. Pass the resolved org to the node scripts explicitly. |
| `scripts/deploy.sh` | Re-exec into a session at top; accept `--allow-production` as a no-op option; usage text says alias only, not username; replace the four `sf` calls (`project deploy start` twice, plus pass-2 loop) with `"$SF_GUARD_SFX"`. Keep the Opportunity-layout guard (defence in depth). Behaviour otherwise unchanged (pass-2 retry count unchanged). |
| `scripts/deploy-fresh-org.sh` | Same session/flag handling; route every `sf` call except `project convert source` through `"$SF_GUARD_SFX"`; skip the second `sf org display` when the first already ran and failed. Note: `sf org display --json` prints tokens; the script already discards all but the username; leave as is and document. |
| `scripts/check-org-drift.py` | Remove the gtm-dev default: org from `SF_TARGET_ORG` or a new `--org <alias>` option, else exit 2 ("no explicit org"). `retrieve()` uses `sf_guard.sf`. Accept and drop `--allow-production`. |
| `scripts/seed-precheck.py` | Use `sf_guard.sf` for its query. |
| `scripts/seed-synthetic-data.py` | `run_sf` uses `sf_guard.sf`; `--check` and `--check-teardown` do not call it and must not need a session. Its own double-confirm stays. |
| `scripts/backfill-link-owner.py` | Its `_subprocess_runner` uses `sf_guard.sf` only for the org-bound path; `--check` remains offline. Keep its own gates. |
| `scripts/check-page-order.mjs`, `scripts/check-live-page-contract.mjs` | Replace `execFileSync('sf', ...)` with `execFileSync(process.env.SF_GUARD_SFX, ...)`; throw when unset; require an explicit org (throw instead of falling back to `''`). |
| `.github/workflows/agent-ci-gate.yml` | Section 5. |
| `scripts/tests/test-sfx-guard.sh` (new) | Section 6, shell self-test with a stub `sf`. |
| `scripts/tests/test_sf_guard.py` (new) | Section 6, Python self-test. |

`agent-workspace.sh` does not call an org and is unchanged.

## 4. Docs contract

New `docs/runbooks/api-request-budget.md` with: purpose and the gtm-dev lock note (locked since 2026-09-18 by `TotalRequests Limit exceeded`; not to be contacted; all agent work on gtm-staging); the honest note that the counter counts invocations; the table below (all figures are the BA's estimates, marked UNVERIFIED until one measured gtm-staging run, which the Developer does not perform; QA or the coordinator records it); the cheaper patterns; how to read the counter summary; guard usage, including `--allow-production` plus `GTM_ALLOW_PRODUCTION=1` and when never to use them.

| Action | Estimated requests | Status |
|---|---|---|
| Dry run of `force-app` (`--dry-run`) | 10 to 40 | UNVERIFIED |
| Real deploy, small bundle (`--source-dir <changed>`) | 5 to 20 (polling dominates) | UNVERIFIED |
| Real deploy, `--async` then one `sf project deploy report` | about 3 to 5 | UNVERIFIED |
| Retrieve-back (`check-org-drift.py`) | 5 to 25 | UNVERIFIED |
| Targeted test run (`--class-names X`) | 5 to 30 | UNVERIFIED |
| `RunLocalTests` (130 test files) | far larger, minutes of polling | UNVERIFIED |
| Status polls (`deploy report`, `sf data query` polling) | 1 to 2 each | UNVERIFIED |
| `sf org display` | 1 to 2 (may refresh token) | UNVERIFIED |
| `sf data query` | 1 (plus 1 if token refresh) | UNVERIFIED |
| Bulk delete (`sf data delete bulk`) | 1 plus polls per object | UNVERIFIED |
| Full `deploy.sh` (pass 1 + pass 2, up to 4 retries) | 20 to 100+ | UNVERIFIED |
| `deploy-fresh-org.sh` | 100 to 300 | UNVERIFIED |

Cheaper-pattern rules to state in the doc (each one line, with the reason):

1. No retrieve-back for LWC-only changes; Jest covers them (`check-org-drift.py` already does nothing for LWC-only diffs).
2. No dry run for small LWC-only bundles; the real deploy to gtm-staging validates equally.
3. Batch merged PRs into one deploy.
4. `--async` deploy plus one `sf project deploy report`, never a long `--wait` poll loop by hand.
5. Never `sf org display` for status; never `sf org list --json` (it prints access tokens; secret hygiene).
6. Bulk API (`sf data import bulk`, `sf data delete bulk`) for data volume; the exact bulk subcommand names are UNVERIFIED.
7. `RunSpecifiedTests` / `--class-names` instead of `RunLocalTests`; `RunLocalTests` only once, immediately before a deploy to gtm-dev, when gtm-dev is unlocked.
8. One org-info lookup per session, cached in a shell variable.

Wording updates (exact anchors, append-only to avoid conflicts with `local-validation-expansion`, which edits `AGENTS.md` section 2 and `CLAUDE.md` section 5 for the check-references sequence):

- `AGENTS.md`: replace QA step 1 (line 80, `Runs the test execution suite ... (\`npm run test\`, \`sf apex run test\`, etc.).`) with the same sentence ending "... `sf apex run test --class-names <targeted classes> --target-org gtm-staging`; never `RunLocalTests` (see docs/runbooks/api-request-budget.md)". Add a new subsection `### C. Org Request Discipline` after the last bullet of `### B` (line 88, the Propose-vs-Commit bullet, end of file section): 4 to 6 bullets: gtm-dev is locked and refused by `scripts/lib/sfx`; all agent org work targets gtm-staging; run `scripts/lib/sfx`-wrapped scripts only; follow the budget doc; report the counter summary in the QA log.
- `CLAUDE.md` section 5 (lines 67-82): add one bullet under "Script Commands" (after the Zero-Org Deploy bullet, line 73-75): "Guard: repo scripts refuse the alias gtm-dev unless `--allow-production` and `GTM_ALLOW_PRODUCTION=1` are both present; `check-all.sh` requires `--org <alias>`; see docs/runbooks/api-request-budget.md."
- `.claude/agents/gtm-qa.md` line 18: `sf apex run test --target-org gtm-dev` becomes `sf apex run test --target-org gtm-staging --class-names <targeted classes>`; append one sentence to the hard-boundary paragraph (line 56) is NOT needed. `.claude/agents/gtm-developer.md`, "Before handing off" section (after line 40): one bullet pointing at the budget doc. These two files are agent prompt configuration: flag them to the coordinator for human review; the Developer should make the edit in the PR, not merge it.
- `docs/runbooks/fresh-org-deploy.md` (usage near line 241): add "`--allow-production` is never appropriate for this script".

## 5. CI change (F1 decision from coordinator default 3)

`.github/workflows/agent-ci-gate.yml`, lines 190-220 only:

- Rename the step "Authenticate to gtm-dev (JWT)" to "Authenticate to the CI target org (JWT; never gtm-dev)".
- Add `env: CI_SF_ALIAS: ${{ vars.CI_SF_ALIAS || 'gtm-staging' }}` (a repository variable, default the placeholder alias `gtm-staging`; no org id or username in the file). Use `--alias "$CI_SF_ALIAS"` and `--target-org "$CI_SF_ALIAS"`; add a first check that lowercased `$CI_SF_ALIAS` is not `gtm-dev` (exit 1).
- Run the dry run through the guard: `scripts/lib/sfx --session -- bash -c 'exec "$SF_GUARD_SFX" project deploy start --source-dir force-app/main/default --target-org "$CI_SF_ALIAS" --dry-run --ignore-conflicts'`. Keep `--dry-run` and `--ignore-conflicts` exactly (CLAUDE.md section 5: `-c` is not a dry run).
- Update the skip-warning text to say the secrets must be gtm-staging credentials, never gtm-dev.
- Optional (Developer discretion, recommended): skip the dry run when the PR diff vs origin/main touches nothing under `force-app/` (this change, for example), to save staging quota.
- Behavioural note: the secrets are unset today, so the step stays skipped; the file cannot be exercised because Actions is down for billing. Validate by `python3 -c "import yaml; yaml.safe_load(open(...))"` and a careful read only. UNVERIFIED end to end.

## 6. Test plan (all offline, no org, no network)

`scripts/tests/test-sfx-guard.sh` (bash, TMP dir, a stub `sf` first on PATH that appends its argv to a file and exits 0; the stub call log is the oracle that "zero sf calls happened"). Cases:

1. gtm-dev refused: `sfx --session -- "$SFX" project deploy start -o gtm-dev` exits nonzero, stub log empty.
2. Case-insensitive: `GTM-DEV`, `Gtm-Dev` refused, also `--target-org=gtm-dev`.
3. Flag only refused; env only refused; flag AND env accepted (stub log has one call).
4. Other aliases accepted: `gtm-staging` exit 0, stub log one line.
5. Raw username refused: `-o someone@example.invalid` exits nonzero, stub empty, output does not contain the string `someone@example.invalid`.
6. No explicit org and no `SF_TARGET_ORG`: refused; with `SF_TARGET_ORG=gtm-staging`: accepted; with `SF_TARGET_ORG=gtm-dev`: refused.
7. Alias-file best effort: a fake `$HOME/.sf/alias.json` mapping `alias2` and `gtm-dev` to the same fake username: `-o alias2` refused.
8. Local commands exempt and uncounted: `project convert source` and `--version` succeed with a gtm-dev-free session, count 0.
9. Counter counts: 3 accepted calls produce `sf calls this run: 3`; summary lines contain no arguments (grep asserts absence of the org alias text and query text).
10. Warning: with `SF_GUARD_WARN_AT=2` and 3 calls, output contains `WARNING`; with 2 calls, it does not; `SF_GUARD_WARN_AT=abc` exits 70.
11. Fail closed: `sfx project deploy start -o gtm-staging` without a session (`SF_GUARD_COUNT_FILE` unset) exits 70, stub empty; counter file made read-only (`chmod 444`) exits 70, stub empty; a scratch copy of a bash entry script with `sfx` removed exits 70 (missing helper).
12. Entry scripts end to end with the stub: `scripts/deploy.sh gtm-dev` exits nonzero before any stub call (the deploy.sh test must not reach the real `sf`); `scripts/check-all.sh` (no args) exits 2; `scripts/check-all.sh --static` runs with zero stub calls; 

`scripts/tests/test_sf_guard.py` (stdlib `unittest`, run by `python3 -m unittest`): `ensure_session` re-execs (tested with a subprocess), exits 70 when `sfx` is missing (via env override of the lib path), `sf()` passes args and returns the completed process; `check-org-drift.py` with no `--org`/`SF_TARGET_ORG` exits 2 and makes no stub call; with `--org gtm-dev` exits nonzero and no stub call.

Also run, unchanged: `npm test`, `python3 scripts/check-references.py`, `python3 scripts/build-instrument.py --check`, `bash -n` on every changed shell file, `python3 -m py_compile` on Python files, `node --check` on the two .mjs files. Wire `scripts/tests/test-sfx-guard.sh` and `python3 -m unittest discover -s scripts/tests` into `scripts/check-all.sh` static block (labels "sfx guard self-test") and add a step to the CI gate before the Salesforce CLI setup. The static block must stay org-free.

## 7. Definition of done

- `scripts/lib/sfx --session -- scripts/lib/sfx project deploy start -o gtm-dev` refuses; nothing hits an org in any test.
- No file added or changed contains an org id, username, token or secret; test usernames use `example.invalid`.
- The counter never records arguments.
- `docs/runbooks/api-request-budget.md` exists with every estimate marked UNVERIFIED and the pattern rules above.
- CI file diff limited to lines 190-220 plus one optional path-filter step and the self-test step.

## 8. Risks

- Wrapper adds a process hop per `sf` call (milliseconds); acceptable.
- `SF_GUARD_ALLOW_FLAG` could be exported by hand; the guard is a safety rail against accident, not a security boundary. The Propose-vs-Commit style separation: humans decide production.
- Alias-file format and location are UNVERIFIED; that layer is best effort, the `@` refusal is the airtight layer.
- `sfx --session` re-exec changes `$0` handling in entry scripts; the Developer must test `deploy.sh` invoked by relative and absolute path.
- Editing `.claude/agents/*.md` and `AGENTS.md` needs human review.
