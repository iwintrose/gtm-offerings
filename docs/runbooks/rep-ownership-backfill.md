# Runbook: rep-ownership OwnerId backfill (COORDINATOR ONLY)

Issue: `rep-ownership-lockdown-3-backfill`. Tool: `scripts/backfill-link-owner.py`.

`gtm-prod` is PRODUCTION with live prospect data. Developers and QA never run
`--dry-run`, `--apply` or `--rollback`; they run only `--check` (no org call).
Even the read-only dry-run is coordinator-only because it spends API quota.

## What it does

Re-owns legacy guest-owned rows to the owner of their link
(`GTM_Saved_Configuration__c.OwnerId`) so reps keep seeing their own history
after `viewAllRecords` is removed from `GTM_Offering_User` (piece 4).

- Written (allowlist, field `OwnerId` only): `GTM_Link_Event__c`,
  `GTM_Form_Draft__c`, and `Task` rows whose current owner is a Guest user.
- Never written: assessment requests, readouts, readout versions, Cases
  (readouts may be owned by the `GTM_Readout_Triage` queue by design).
  Requests and readouts get a report-only mismatch count. Non-guest-owned
  Tasks on links are report-only (counted by owner, not compared).
- Skipped and counted, never written: rows with a null/missing link
  (orphans), targets that are inactive, Guest, queue or unknown users.
- Idempotent: the plan is recomputed from live data; a second `--apply`
  plans 0 rows.

## Preconditions

1. Piece 1 (owner stamping on new rows) is deployed and verified.
2. `python3 scripts/backfill-link-owner.py --check` passes on the merged
   branch. Run from a clean checkout of `main`, not a Developer worktree.
3. `sf org display -o gtm-prod` works; `sf limits api display -o gtm-prod`
   shows `DailyApiRequests` Remaining well above the estimate plus 500
   (the script also enforces this; `--max-api-calls` defaults to 200).
4. **Confirm the Task assignment-email/notification setting before
   `--apply`.** Changing a Task's owner can email the new owner if the
   org/user setting "Send notification email when I'm assigned" is on. If it
   is on for reps, turn it off (or accept mass email) before applying, and
   record the decision. Also check `force-app` for Task/Event triggers or
   flows fired by owner change.

## Steps

1. Local gate: `python3 scripts/backfill-link-owner.py --check`.
2. Dry-run (read-only): `python3 scripts/backfill-link-owner.py -o gtm-prod`.
   Record counts by current owner, by target owner, skips by reason,
   report-only counts, the "grouped-query mode" line (`relationship` or
   `two-query-fallback`; both are supported, and the first real run proves
   which the org accepts) and the API estimate. Output contains no record
   content.
3. APPROVAL CHECKPOINT. Ask the owner directly for approval (a relayed or
   paraphrased approval is not enough): "gtm-prod is PRODUCTION. The dry-run
   found N link events, N form drafts and N access-log tasks owned by someone
   other than their link's rep. Approving will reassign only their OwnerId to
   the link owner, writing a rollback file first, about K API calls. Reply
   'approved: run the ownership backfill on gtm-prod' to proceed."
4. Apply (only after approval):
   `python3 scripts/backfill-link-owner.py --apply -o gtm-prod --i-understand-this-writes-to-org gtm-prod --scratch-dir "$TMPDIR/gtm-backfill"`
   and type `gtm-prod` at the prompt (or pass `--yes-alias gtm-prod`). The
   rollback CSVs (`rollback-<sobject>.csv`, Ids only) are written and
   verified before the first update; the scratch dir must be outside the git
   work tree (the script refuses otherwise). Keep CSVs out of git and shared
   drives. Writes use Bulk API 2.0 (`sf data update bulk`) in chunks of 2000
   (`--batch-size`, hard cap 10000); any failed row stops the run.
5. Verify: re-run step 2. Mismatches must be 0 for all three objects except
   the reported skips. Spot check:
   `sf data query -o gtm-prod -q "SELECT COUNT(Id) FROM GTM_Link_Event__c WHERE OwnerId IN (SELECT Id FROM User WHERE UserType = 'Guest')"`
   equals the orphan count only; likewise `GTM_Form_Draft__c`.
6. Gate: the LAST dry-run before piece 4 deploys must show zero mismatches.
   If not, piece 4 does not deploy. Then QA validates in the browser that a
   rep still sees their own historical events and not another rep's.
7. Rollback (owner's instruction only):
   `python3 scripts/backfill-link-owner.py --rollback <csv> -o gtm-prod --i-understand-this-writes-to-org gtm-prod --scratch-dir "$TMPDIR/gtm-backfill"`.
   It restores `OldOwnerId` only where the current owner still equals the
   backfilled owner. If piece 4 already shipped, also restore
   `viewAllRecords=true` on `GTM_Offering_User` and redeploy.
8. Cleanup: after the owner confirms, archive or securely delete the scratch
   CSVs. Nothing from that directory is ever committed.

## Questions for the owner

1. Rep B previewing rep A's link creates events/drafts owned by B. This
   script moves them to A (owner rule: tied to the link). Confirm, or leave
   them with B.
2. Orphans (link deleted, `Saved_Configuration__c` null): stay guest-owned
   and become invisible to reps after piece 4. Leave, delete via a separate
   approved task, or assign to an admin? Default: leave and report.
3. If the dry-run shows more than 50,000 rows in total, stop and revisit
   (Bulk job limits, off-peak run, higher `--max-api-calls`).
4. Non-guest-owned Tasks on links (rep-logged) are report-only. Should any be
   moved?
