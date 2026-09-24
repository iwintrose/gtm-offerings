# Runbook: Salesforce API request budget and the org guard

## Purpose and the gtm-dev lock

Every `sf` call spends daily API requests from the org's allowance. `gtm-dev` was locked on 2026-09-18 by `TotalRequests Limit exceeded`. It is not to be contacted until the coordinator unlocks it; all agent work uses `gtm-staging`.

Contract: `docs/architecture/test-efficiency-request-guard.md`.

## What the counter counts

`scripts/lib/sfx` counts CLI invocations, not HTTP requests. One invocation costs several requests, so treat the count as a lower bound. Arguments are never recorded, so the counter holds no org id, username, token or query text.

## Estimated cost (all UNVERIFIED until one measured gtm-staging run)

These are BA estimates. They are unconfirmed; QA or the coordinator records one measured run.

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

## Cheaper patterns

1. No retrieve-back for LWC-only changes; Jest covers them (`check-org-drift.py` already does nothing for LWC-only diffs).
2. No dry run for small LWC-only bundles; the real deploy to gtm-staging validates equally.
3. Batch merged PRs into one deploy.
4. `--async` deploy plus one `sf project deploy report`, never a long hand-rolled `--wait` poll loop.
5. Never `sf org display` for status; never `sf org list --json` (it prints access tokens).
6. Use Bulk API (`sf data import bulk`, `sf data delete bulk`) for data volume; exact subcommand names are UNVERIFIED.
7. `RunSpecifiedTests` / `--class-names` instead of `RunLocalTests`; `RunLocalTests` only once, right before a deploy to gtm-dev, and only when gtm-dev is unlocked.
8. One org-info lookup per session, cached in a shell variable.

## Reading the counter summary

At the end of a guarded run, stderr shows `sf calls this run: <n>` and a tally by command head (for example `project deploy`). Above `SF_GUARD_WARN_AT` (default 50, must be a positive integer) it adds a `WARNING`. It warns only; the only hard refusal is the production rule below. Local-only commands (`project convert`, `project generate`, `--version`, `help`, `plugins`, `config`, `alias`) are not counted.

## Using the guard

- Bash and Python scripts join a session; Node scripts need `SF_GUARD_SFX` and throw without it. Run the whole thing via `scripts/check-all.sh --org <alias>` or `scripts/lib/sfx --session -- <command>`.
- An explicit org is required (`-o` / `--target-org`, or `SF_TARGET_ORG`). The machine default org is never used.
- Refused: the alias `gtm-dev` (case-insensitive), any name in `SF_GUARD_PROD_ALIASES` (adds to, never replaces, `gtm-dev`), any raw username (contains `@`; use the alias), and, when a local `alias.json` is readable, any alias mapping to the same username as `gtm-dev`. The alias-file layer is best effort and its format is UNVERIFIED.
- The guard fails closed: no counter or no `sfx` means exit 70 and no `sf` call.
- Override: `--allow-production` on the session AND `GTM_ALLOW_PRODUCTION=1` in the environment, both required. Never set either while gtm-dev is locked or without the coordinator's say-so. Never use it with `deploy-fresh-org.sh`. It is a safety rail against accidents, not a security boundary.
- Self-test: `scripts/tests/test-sfx-guard.sh` and `python3 -m unittest discover -s scripts/tests -p test_sf_guard.py` (offline, stub `sf`; also run by `scripts/check-all.sh --static`).

## Not yet wired through the guard

`deploy.sh`, `deploy-fresh-org.sh`, `seed-precheck.py`, `seed-synthetic-data.py` and `backfill-link-owner.py` still call `sf` directly and are not yet guarded or counted. `deploy.sh` still only skips the Opportunity layouts for a production alias. Do not rely on the guard for them yet.
