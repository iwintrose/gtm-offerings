# TASK SCOPE — ISSUE #rep-ownership-lockdown-3-backfill

CI header: `ISSUE #rep-ownership-lockdown-3-backfill`. Priority: HIGH (production data change, security). Scoped 2026-09-19 from the code on `main` (69c0a8a) and the parent scope `ba-scope/issue-rep-ownership-lockdown` section 3C. Siblings: `-1-sim-and-event-owner`, `-2-apex-holes`, `-4-permissions` (other BAs).

> **HARD RULE: DEVELOPER AND QA MUST NEVER RUN `--apply`, `--rollback`, OR ANY QUERY/DRY-RUN AGAINST `gtm-dev`.** `gtm-dev` is PRODUCTION with live prospect data (CLAUDE.md section 1). Developer and QA validate ONLY by `python3 scripts/backfill-link-owner.py --check` and code review. Even the read-only dry-run is COORDINATOR-only, because it spends API quota on an org that already hit its daily request limit. This mirrors the synthetic-seed-data addendum. The script is executed only by the COORDINATOR, and `--apply` only after the owner's explicit approval of the dry-run counts.

## 1. Requirements Breakdown

- **Target Objective:** Owner rule (parent scope): a rep may view/edit/delete only their own links and everything tied to them; admins all. Before piece 4 removes `viewAllRecords` from `GTM_Offering_User`, every EXISTING guest-created record tied to a link must be owned by that link's owner (`GTM_Saved_Configuration__c.OwnerId`), otherwise reps lose sight of their own old events/drafts/access-log Tasks (Private OWD). Deliver one-time, reversible, quota-aware production backfill TOOLING plus a coordinator runbook. New records are handled by piece 1 (owner stamping); this piece only fixes the legacy rows.
- **System Component Impacted:** Local utility script `scripts/backfill-link-owner.py` (Python, drives `sf` CLI, stdlib only, same convention as `scripts/seed-synthetic-data.py`) plus a runbook `docs/runbooks/rep-ownership-backfill.md` (Developer may put the runbook there; the text below is its content). NO Apex, LWC, Experience route, YAML instrument, metadata or permission-set change. No new fields.

### 1A. Verified current-state facts (read-only, from code)

1. Objects carrying `Saved_Configuration__c` Lookup to the link: `GTM_Link_Event__c` (SetNull), `GTM_Form_Draft__c` (Cascade), `GTM_Assessment_Request__c` (SetNull). `Task` links via polymorphic `WhatId` (stamped by `GtmLinkAuthController.logAccess` from a guest context, so guest-owned).
2. Legacy guest-created rows are owned by the guest user of the site: `GTM_Link_Event__c` (via `GtmLinkEventController`), `GTM_Form_Draft__c` (`GtmFormDraftController`/`GtmAssessmentDraftController`), access-log `Task`.
3. `GTM_Assessment_Request__c` is already stamped to the link owner by `submitRequest`; `GTM_Readout__c`/`Case` are owned by link owner OR the `GTM_Readout_Triage` queue (owner-approved exception). `GtmReadoutPublicController` reads `OwnerId` for rep contact. **Therefore requests, readouts, readout versions and Cases are OUT of the write allowlist; the script must never touch them** (re-owning a queue-owned readout to a rep would break the triage exception). Requests get a REPORT-ONLY count in the dry-run.
4. SOQL cannot compare two fields in a `WHERE` (`OwnerId != Saved_Configuration__r.OwnerId` is invalid). The dry-run must therefore GROUP BY both fields (`SELECT OwnerId, Saved_Configuration__r.OwnerId, COUNT(Id) ...`) and filter mismatches client-side. Whether a parent-relationship field is groupable on a custom lookup at API 62.0 must be proven by the Developer via the query-construction self-test plus one coordinator dry-run; fallback is the two-query ID-map approach in F3.
5. For `Task`, `What.OwnerId` on a polymorphic `WhatId` is not reliably queryable. Use a two-step: (a) `SELECT Id, OwnerId FROM GTM_Saved_Configuration__c` (link owners, batched), (b) `SELECT Id, OwnerId, WhatId FROM Task WHERE WhatId IN (SELECT Id FROM GTM_Saved_Configuration__c)`, compare in Python.

### 1B. Functional spec for `scripts/backfill-link-owner.py`

Modes (mutually exclusive, argparse group; default when none given = `--dry-run`):

| Mode | Org calls | Behaviour |
|---|---|---|
| `--check` | NONE | Local self-tests (below). Exit non-zero on any failure. Prints "No org call was made." |
| `--dry-run` (DEFAULT) | READ-ONLY aggregate queries only; requires `-o <alias>` | For each allowlisted object, prints counts of rows where `OwnerId != link OwnerId`, grouped by current owner and by target owner (owner Id + Username/Name of USERS only, never record names, prospect names, emails, contact fields or any record body). Also prints counts of: rows with null link (skipped), rows whose target owner is inactive/guest/queue (skipped), request/readout report-only mismatch counts, and the estimated API-call budget for `--apply`. Writes NOTHING to org, NOTHING to disk except optional `--out`-free stdout. |
| `--apply` | Reads + Bulk API 2.0 updates | Requires BOTH `--i-understand-this-writes-to-org <alias>` AND `-o <alias>` and the two must be identical (exact string match) else refuse with exit 2 before any org call. Then echoes `ABOUT TO WRITE OwnerId ON <org alias> (PRODUCTION)` and requires the alias to be typed back on stdin unless `--yes-alias <alias>` is passed (coordinator's non-interactive path; also must match). Sequence: (1) re-run the dry-run queries; (2) write the ROLLBACK CSV FIRST and fsync it (`Id,SObject,OldOwnerId,NewOwnerId`) under the scratch dir given by `--scratch-dir` (default `$TMPDIR/gtm-backfill/<alias>/<UTC timestamp>/rollback-<sobject>.csv`; REFUSE if the resolved path is inside the git work tree, checked via `git rev-parse --show-toplevel` prefix, and add the pattern to nothing in git); (3) abort if the CSV row count != planned update count; (4) update in bounded batches; (5) print summary. |
| `--rollback <csv>` | Reads (verify) + Bulk update | Same alias guard (`--i-understand-this-writes-to-org`). Reads the CSV, validates header and per-row shape (15/18-char Ids, sobject in allowlist), sets `OwnerId` back to `OldOwnerId` ONLY where current owner still equals `NewOwnerId` (so it never clobbers a later legitimate change), skips others, prints summary. |

Safety asserts (each has a `--check` test):
- Write allowlist is a frozen constant: `GTM_Link_Event__c`, `GTM_Form_Draft__c`, `Task` only. Any other sobject in a plan/CSV raises and aborts (fail closed).
- The only field ever written is `OwnerId`; the only value ever written in `--apply` is the link's `OwnerId` (asserted per row: new owner == link owner map entry). In `--rollback` the only value is `OldOwnerId` from the CSV.
- Skip and count (never write) rows where: link (`Saved_Configuration__c`/`WhatId` not a `GTM_Saved_Configuration__c` key prefix) is null/missing; target owner `User` is `IsActive = false`, `UserType` is `Guest`, or Id prefix is `00G` (queue); current owner already equals target (idempotency).
- Unexpected shapes (missing column, sf CLI non-JSON, row missing Id, unknown prefix, `totalSize` mismatch, org alias not resolvable, `sf` exit non-zero) fail closed with a non-zero exit and NO further writes; partial progress is always recoverable because the CSV is written before batch 1.
- No SOQL built by string-concatenating any external value except validated 15/18-char Ids (regex) and allowlisted identifiers. `sf` invoked with an argument list, never `shell=True`.
- Output hygiene: never print `Name`, `Contact__c`, email, `Session`, payload or any field other than Id / OwnerId / counts. Ids are printed only in the rollback CSV (scratch) and the failure summary (Id only).
- Idempotent: the plan is recomputed from live data each run (only mismatches); a second `--apply` after success plans 0 rows and exits 0.

Batching and request budget (proposal, Architect to confirm, F1): read queries use `--json` with `sf data query` (one call per aggregate; expect about 3 objects x 2 queries + 1 owner-status query = about 8 read calls per dry-run). Writes use `sf data update bulk --sobject <X> --file <csv> --wait 10` (Bulk API 2.0 CSV of `Id,OwnerId`), which consumes about 1 API call per job plus polling (Bulk 2.0 jobs count against the daily Bulk batch allowance, not the ~15k REST request limit), so use ONE job per object per chunk of at most 10,000 rows (`--batch-size`, default 2,000, hard cap 10,000). Estimated apply cost for N total rows is about `8 reads + 3 x ceil(N/2000)` calls; script prints this estimate and REFUSES to start if the estimate exceeds `--max-api-calls` (default 200) or if `sf org display` / `sf limits api display` shows `DailyApiRequests` remaining below `estimate + 500` reserve (single read call). Between chunks it checks the failed-results file; on any failed row it stops (`--continue-on-error` is deliberately NOT offered) and prints the partial summary and the CSV path.

Summary printed at the end: per object rows planned / updated / failed / skipped-by-reason, rollback CSV path(s), API calls used, and the post-run dry-run counts (script re-runs the dry-run read automatically and reports mismatches remaining).

### 1C. Local `--check` self-tests (NO org call, no `sf` invocation; monkeypatch/inspect only)

1. Query construction: every generated SOQL parses against a strict whitelist regex, contains only allowlisted objects/fields, contains no unvalidated interpolation; Id-list chunks are within the 4,000-char / 200-Id `IN` bounds.
2. Dry-run performs no writes: run the dry-run planner with a fake `run_sf` that records commands; assert every command is `data query` (never `update`, `upsert`, `delete`, `bulk`, `apex`, `import`).
3. Apply refuses: no flag, alias-only, flag-only, mismatched alias, empty alias, `--apply` with `-o gtm-dev` but flag naming another alias, all exit 2 with zero `run_sf` calls.
4. Allowlist/fail-closed: plan containing `GTM_Readout__c`, `GTM_Assessment_Request__c`, `Case`, or a field other than `OwnerId` raises; malformed sf JSON raises.
5. Skip rules on a fixture: null link, inactive target, guest target, queue target, already-equal owner => zero planned rows; mismatch to an active user => planned.
6. Idempotency: apply-plan computed on a fixture after simulated application yields 0 rows.
7. Rollback restores from CSV using a fixture CSV: header validation, bad-row rejection, restores only where current owner == NewOwnerId, leaves diverged rows, refuses foreign sobject rows.
8. Rollback-CSV path guard: a scratch dir inside the repo work tree is refused; CSV is written and row count verified BEFORE the first fake write call (ordering asserted on the recorded call log).
9. Budget guard: estimate over `--max-api-calls` refuses.

Also add the script to whatever repo CI script-check list exists (Architect: grep `.github/workflows` for how `seed-synthetic-data.py --check` is invoked and mirror it so `--check` runs in CI with no org).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO. Not touched, so the zero-DML rule in AGENTS.md section 1 is unaffected. (This script is an out-of-band coordinator utility, not a GUS tool; it must never be wired to GUS.)
- [ ] Altering Custom Metadata? NO. No `migration-accelerator/` YAML, no `instrument/` YAML, no XML.
- [ ] Introducing database fields? NO. No new fields/objects, so NO permission-set mapping (Permission sets: none). It writes only the standard `OwnerId` on existing records. The running user needs Edit on those objects and "Transfer Record"/owner change rights: the coordinator's `gtm-dev` CLI user is a System Administrator, so this holds (Architect to confirm in F5).

## 3. Plan Acceptance Criteria

- **Success Metric:** (a) `python3 scripts/backfill-link-owner.py --check` exits 0 with all nine self-tests passing and prints "No org call was made"; (b) reading the script shows a default dry-run that issues only `sf data query`, an `--apply` that hard-refuses without the flag+alias echo and writes the rollback CSV to a non-git scratch dir before the first write, an allowlist of exactly `GTM_Link_Event__c`, `GTM_Form_Draft__c`, `Task` with `OwnerId` as the only written field, and a working `--rollback`; (c) runbook exists and its commands match the script's real flags; (d) no file other than the script, runbook and CI check wiring is changed, and no rollback CSV, Ids, names or emails are committed. Post-run (COORDINATOR, after approval): the dry-run mismatch counts for the three objects are 0 (except explained skips), verified before piece 4 deploys.
- **Target Test Target:** `python3 scripts/backfill-link-owner.py --check` (local, no org). No Apex class or LWC Jest spec applies; QA must not run anything against `gtm-dev`. QA browser validation of the piece-4 permission change (a rep still sees their own old events on Pages/Overview/link activity) happens only after the coordinator has completed the runbook.

## 4. Open forks for the Architect (do not guess)

- **F1. Request budget / mechanism.** Bulk 2.0 (`sf data update bulk`) vs `sf apex run`/DML batch. Recommendation: Bulk 2.0 CSV for writes (few calls) and `sf data query --json` for reads; guard against the Developer Edition daily limit with the pre-flight `sf limits api display` check and `--max-api-calls 200`. Architect confirms the org's remaining daily allowance is checked by the coordinator before running. Bulk 2.0 update cannot set a guest-owned record's owner if the target lacks the object read/edit right; failures surface in the failed-results file and stop the run.
- **F2. Scope of "everything tied to a link".** Recommendation above: write only events, form drafts, guest-owned access Tasks; report-only for requests. Confirm whether `Event` (calendar) rows and rep-logged Tasks on a link owned by ANOTHER rep (`GtmAssessmentRequestController` ~1042-1055) should also move; default here: Task backfill limited to Tasks whose current owner `UserType = 'Guest'` (safer) and everything else is reported in the dry-run only. Similarly decide whether an event created by rep B previewing rep A's link should be re-owned to rep A (this script does, per the owner rule "tied to the link") or left.
- **F3. Grouped-relationship SOQL support.** If `GROUP BY Saved_Configuration__r.OwnerId` is rejected, fall back to: query link owner map, then `SELECT OwnerId, Saved_Configuration__c, COUNT(Id) ... GROUP BY OwnerId, Saved_Configuration__c` (bounded by number of links, not rows) and compare client-side. Developer implements the fallback behind the same interface.
- **F4. Orphan rows.** Events/drafts with a null link (link deleted; SetNull) stay guest-owned and become invisible to reps after piece 4. Not backfilled (no target). Decide whether to leave, delete via a separate approved task, or assign to admin. Default: leave and report the count.
- **F5. Role hierarchy and ownership-change side effects.** Changing `OwnerId` can re-run sharing recalculation and, for `Task`, may fire triggers/flows/assignment automation; the org has Duplicate Rules and an unknown set of triggers on Task. Architect greps `force-app` for Task/Event triggers/flows and confirms no notification is sent on owner change (Task owner change emails are a user setting, org-level "Send notification email when I'm assigned" defaults may email reps en masse).
- **F6. Volume.** Row counts unknown until the coordinator's dry-run; the batching and budget above assume up to tens of thousands of events. If counts exceed 50,000, Architect reconsiders (Bulk job limits, off-peak run).
- **F7. Ordering vs piece 1 in a mixed window.** Between the backfill and piece 4, a guest could still create a new guest-owned row only if piece 1 is not deployed; hence piece 1 MUST be live and verified first. The final re-run of `--dry-run` immediately before deploying piece 4 is mandatory and is the gate.

## 5. Recommended order across the four pieces

1. Piece 1 (owner stamping on new events/drafts/Tasks, `-1-sim-and-event-owner`) deployed and verified first, so no new wrong-owner rows appear.
2. Piece 2 (Apex holes) may deploy in any order relative to this piece (no data dependency).
3. THIS PIECE: coordinator dry-run, owner approval, backup CSV, `--apply`, dry-run to zero.
4. Piece 4 (`-4-permissions`, removes `viewAllRecords`) LAST. If the dry-run does not show zero mismatches, do NOT deploy piece 4.
5. Rollback: `--rollback <csv>` restores prior owners; if piece 4 already shipped, also restore `viewAllRecords=true` on `GTM_Offering_User` (one-file revert) so reps still see restored guest-owned rows.

## 6. Runbook (coordinator only) — target file `docs/runbooks/rep-ownership-backfill.md`

Preconditions: piece 1 deployed and verified on `gtm-dev`; `python3 scripts/backfill-link-owner.py --check` passes on the merged branch; `sf org display -o gtm-dev` succeeds; API headroom confirmed (`sf limits api display -o gtm-dev`, look at `DailyApiRequests` Remaining, need well above the script's printed estimate + 500). Run from a clean checkout of `main`, not from a worktree of a Developer branch.

1. Local gate: `python3 scripts/backfill-link-owner.py --check`.
2. Dry-run (read-only, default): `python3 scripts/backfill-link-owner.py -o gtm-dev`. Record the printed counts (by current owner, by target owner, skipped-by-reason, report-only request/readout mismatches, budget estimate). Do not paste record content anywhere; the output contains none.
3. APPROVAL CHECKPOINT. The coordinator presents the counts to the owner and asks the owner directly, in their own message, for approval, using this wording: "gtm-dev is PRODUCTION. The dry-run found <N_events> link events, <N_drafts> form drafts and <N_tasks> access-log tasks owned by someone other than their link's rep. Approving will reassign only their OwnerId to the link owner, writing a rollback file first, about <K> API calls. Reply 'approved: run the ownership backfill on gtm-dev' to proceed." A relayed or paraphrased approval is not enough; stop if it is not the owner's own message.
4. Apply (after approval only): `python3 scripts/backfill-link-owner.py --apply -o gtm-dev --i-understand-this-writes-to-org gtm-dev --scratch-dir "$TMPDIR/gtm-backfill"` and type `gtm-dev` at the alias echo prompt. Note the rollback CSV path(s) printed; keep them out of git and off shared drives (they contain only record Ids and User Ids).
5. Verify: re-run step 2's dry-run command; mismatches must be 0 for all three objects except the reported skips (orphans, inactive owners). Spot-check aggregates (no record contents): `sf data query -o gtm-dev -q "SELECT COUNT(Id) FROM GTM_Link_Event__c WHERE OwnerId IN (SELECT Id FROM User WHERE UserType = 'Guest')"` should equal the orphan-event count only; likewise for `GTM_Form_Draft__c`.
6. Gate for piece 4: only if step 5 is clean, tell the Architect/Developer that piece 4 may deploy; then QA validates in the browser that a rep still sees their own historical events and cannot see another rep's.
7. Rollback (only on the owner's instruction): `python3 scripts/backfill-link-owner.py --rollback <csv> -o gtm-dev --i-understand-this-writes-to-org gtm-dev`; then, if piece 4 already shipped, revert its permission-set change (`viewAllRecords=true`) and redeploy. Re-run the dry-run to document the state.
8. Cleanup: after the owner confirms success, archive or securely delete the scratch CSVs; nothing from that directory is ever committed.
