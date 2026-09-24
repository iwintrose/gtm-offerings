# Offering archive cascade — schema + trigger contract

**Status:** Accepted — issue #184, slice 1 of 5 (`184-schema-cascade`).
**Scope:** Data model and cascade automation only. Controller/LWC exposure,
permission-set follow-ups beyond the minimal grants below, and the purge
batch are separate slices (`184-controller`, `184-lwc`, `184-permissions`,
`184-purge-batch`).

## Context

`GTM_Page_Section__c.Archived__c` already exists and is the source of truth
for "is this offering archived" — `GtmPageContentController.setOfferingArchived()`
writes it onto the offering's **tile row** (`Section_Address__c` =
`<offeringKey>::offerings-listing::tile`, i.e. `Section_Key__c='tile'` and
`Template_Type__c='offerings-listing'`). No other row for the offering is
touched today: every other `GTM_Page_Section__c` row for that
`Offering_Key__c`, and every `GTM_Page_Content__c` row, stays unarchived
regardless of the tile's state. There is also no audit timestamp — nothing
records *when* an offering was archived, which blocks both a "Deleted Date"
display and the future purge batch (`184-purge-batch`) from having a
retention clock to key off.

### Correction to the issue text

Issue #184's body describes extending the archive pattern to
`GTM_Offering__c` (parent) and `Offering_Feature__c` (children). **Neither
object exists in this codebase.** Confirmed against
`force-app/main/default/objects/`: offerings are defined by the custom
metadata type `GTM_Offering__mdt` (`Offering_Key__c`, `Label__c`,
`Site_Path__c`), which is deployed via Metadata API, not DML, and per
CLAUDE.md §2 is never hand-edited. There is no SObject "parent" record to
cascade from. The only queryable per-offering "parent" that already carries
archive state is the tile `GTM_Page_Section__c` row described above, which
is why this design cascades from that row rather than from an
`GTM_Offering__c` record. **This design does not add fields to
`GTM_Offering__mdt` and does not introduce `Offering_Feature__c` or any new
object.**

## Decision

### 1. New fields

| Object | Field | Type | Notes |
|---|---|---|---|
| `GTM_Page_Section__c` | `Archived_Date__c` | DateTime | New. Alongside existing `Archived__c`. |
| `GTM_Page_Content__c` | `Archived__c` | Checkbox, default `false` | New — this object had no archive field at all. |
| `GTM_Page_Content__c` | `Archived_Date__c` | DateTime | New. |

Neither `Archived_Date__c` field is user-editable in intent (no UI writes to
it directly in this slice); it is always trigger-stamped. It is left as a
normal, non-required field rather than read-only-via-validation-rule, to
keep a future admin data-fix from being blocked.

### 2. Self-stamp: one owner per object for "when did Archived__c change"

Per ADR-0003 (single trigger point per side effect), each object owns
stamping its own `Archived_Date__c` in a `before update` trigger, whenever
`Archived__c`'s value actually changes on that specific record (not merely
touched — a checkbox field is never null, so this is a direct `!=`
comparison against `Trigger.oldMap`). Writing `Archived__c` with the value
it already has is a no-op: `Archived_Date__c` is left untouched.

This one rule handles three cases uniformly, whether the write comes from a
human, `setOfferingArchived()`, or the cascade in §3:

- `GtmPageSectionArchiveCascade.trigger` (`before update`) stamps
  `GTM_Page_Section__c.Archived_Date__c`.
- `GtmPageContentArchiveStamp.trigger` (`before update`) stamps
  `GTM_Page_Content__c.Archived_Date__c`.

### 3. Cascade: tile row is the source of truth

`GtmPageSectionArchiveCascade.trigger` also runs `after update` on
`GTM_Page_Section__c`. For every updated record that **is** the offering's
tile row (`Section_Key__c='tile'` and `Template_Type__c='offerings-listing'`)
and whose `Archived__c` changed in this transaction, the handler
(`GtmOfferingArchiveCascadeHandler.cascadeFromTiles`):

1. Collects `Offering_Key__c -> new Archived__c value` for every changed
   tile in the batch.
2. Queries every other `GTM_Page_Section__c` row sharing that
   `Offering_Key__c` (tile rows themselves excluded — they were the trigger
   source, not a cascade target) whose `Archived__c` does **not** already
   match the target value, and updates just `Archived__c` on those rows.
3. Queries every `GTM_Page_Content__c` row sharing that `Offering_Key__c`
   whose `Archived__c` does not already match the target value, and updates
   just `Archived__c` on those rows.

Only the boolean is written by the cascade — `Archived_Date__c` on the
cascaded rows is left to each object's own `before update` self-stamp
trigger from §2, which fires on this second DML as an ordinary update and
stamps a value change it can see for itself. This keeps "stamp the date"
as a single owned behavior rather than duplicating that logic inside the
cascade handler.

Filtering to rows whose `Archived__c` does not already equal the target
value is what makes cascade re-entrant and gives the no-op guarantee:
re-archiving an already-archived offering (or re-restoring an already-live
one) finds zero rows to update, so no `Archived_Date__c` on any sibling is
touched. This also bounds recursion — the second-order updates never touch
a tile row (tile rows are explicitly excluded from the `GTM_Page_Section__c`
cascade query), so the `after update` handler never re-enters itself.

### 4. Direction

Both archive (`false -> true`) and restore (`true -> false`) flow through
the identical code path — the handler branches on the tile's *new* value,
not on a hardcoded "archive" assumption, so restoring an offering un-archives
every sibling row the same way archiving archived them.

## Consequences

- A future edit to a single `GTM_Page_Section__c` sibling row's
  `Archived__c` (bypassing the tile) is **not** pushed back up to the tile
  or to other siblings — the tile row remains the only source of truth in
  this design, matching `setOfferingArchived()`'s existing behavior of only
  ever writing the tile. A stray sibling edit is a data-quality question for
  a later slice (e.g. the `184-permissions` slice could lock direct edits to
  `Archived__c` on non-tile rows via FLS), not something this trigger
  corrects for.
- Bulk-safe: both the self-stamp and cascade handlers operate on
  `List<SObject>`/`Map<Id,SObject>`, no SOQL/DML inside a loop, and the
  cascade issues one query and one DML statement per object per invocation
  (not per tile row), so archiving many offerings in one batch stays within
  governor limits.
- Permission-set grants for the three new fields ship in this same change
  (per CLAUDE.md §6.1's "grants land with the field, not a follow-up"
  rule): `GTM_Offering_Admin` and `GTM_Content_Admin` get full read/edit on
  all three; `GTM_Content_Manager` gets read/edit matching its existing
  grant on `GTM_Page_Section__c.Archived__c`; `GTM_Offering_User` gets none,
  matching that `Archived__c` is *not* currently granted to that permission
  set either (reps do not directly toggle archive state via FLS today —
  that stays true for these three fields too, pending whatever the
  `184-controller`/`184-lwc` slices decide about rep-facing UI); `GTM_Guest`
  gets none of the three, deliberately.

## Retention purge (issue #184, part 5)

`GTM_PurgeRecordsBatch` (`force-app/main/default/classes/GTM_PurgeRecordsBatch.cls`)
is the time-based, automatic counterpart to `GTM_RecycleBinController`'s
manual "permanently delete" action. It implements
`Database.Batchable<SObject>` + `Schedulable`, mirroring
`GtmAssessmentDraftPurge`'s shape exactly (`with sharing`, a named
`@TestVisible` retention constant, `Database.delete(scope, false)` so one
undeletable row does not strand the batch, and an empty `finish()`).

- **Retention window:** `PURGE_AFTER_DAYS = 30` (hardcoded Apex constant,
  not Custom Metadata-configurable).
- **Query surface:** both `GTM_Page_Section__c` and `GTM_Page_Content__c`
  where `Archived__c = true AND Archived_Date__c < :cutoff`, using
  `Archived_Date__c` (the retention clock this schema slice exists to
  support) rather than `LastModifiedDate`.
- **No tile/cascade special-casing:** unlike the cascade trigger above,
  this batch treats every row as independently eligible by its own
  `Archived_Date__c` — purge is a terminal delete, not a restore, so there
  is no "parent still archived" hazard to guard against here.

### 🚨 Manual activation required — this does NOT run automatically

Deploying `GTM_PurgeRecordsBatch` does **not** put it on any schedule.
Exactly like `GtmAssessmentDraftPurge` (see `docs/architecture/gtm-analytics-v1.md`
and `docs/runbooks/questionnaire-resume.md`), there is no CMDT-based or
other automatic scheduling mechanism in this codebase — a human must run a
one-time anonymous-Apex `System.schedule(...)` call by hand in `gtm-prod`
after this class is deployed, or the purge will simply never run:

```apex
System.schedule(
    'GTM Purge Records Batch',
    '0 0 4 * * ?',
    new GTM_PurgeRecordsBatch()
);
```

Confirm the job is registered afterward via Setup > Scheduled Jobs (or
`SELECT Id, CronJobDetail.Name, NextFireTime FROM CronTrigger`).
