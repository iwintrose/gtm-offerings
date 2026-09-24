# TASK SCOPE — ISSUE #184-purge-batch

## 1. Requirements Breakdown

- **Target Objective:** Build `GTM_PurgeRecordsBatch`, a Batch Apex class
  (paired with `Schedulable`, matching the existing `GtmAssessmentDraftPurge`
  shape) that permanently hard-deletes `GTM_Page_Section__c` and
  `GTM_Page_Content__c` records that have sat in the archived/recycle-bin
  state (`Archived__c = true`) for 30+ days, per issue #184's original
  retention plan. Note: no literal "30 days" wording was found re-quoted
  anywhere in `docs/backlog.md` for this issue — the 30-day figure comes
  from the issue body itself (per this task's own framing) and from the
  30-day convention already established in
  `docs/architecture/offering-archive-cascade.md` §"Consequences" as the
  retention clock `Archived_Date__c` exists to support. Treat 30 days as a
  named, `@TestVisible` constant (mirroring `GtmAssessmentDraftPurge`'s
  `SUBMITTED_GRACE_DAYS` pattern) so it is trivially adjustable, not a
  magic literal buried in a query.
  - **Query surface:** both objects' `Archived__c = true AND
    Archived_Date__c < :cutoff` rows, per the schema/cascade design in
    `docs/architecture/offering-archive-cascade.md`. `Archived_Date__c`
    is the field this whole schema slice (#187) was built to give a purge
    batch a retention clock to key off — use it, not `LastModifiedDate`.
  - **"Purge" means hard delete**, consistent with
    `GTM_RecycleBinController.deleteRecord`/`deleteRecords`
    (`force-app/main/default/classes/GTM_RecycleBinController.cls`), which
    already implements "permanently delete an archived record" as a plain
    `Database.delete` (via `hardDelete`, `AccessLevel.USER_MODE`) — not a
    soft "deleted" status field or a move to another object. This batch is
    the time-based, automatic equivalent of that manual admin action, so it
    should call the same terminal operation (hard `Database.delete`,
    `allOrNone=false` so one blocked row doesn't strand the batch — follow
    `GtmAssessmentDraftPurge.execute()`'s exact pattern) rather than
    inventing new terminology or a different delete path. It does **not**
    need to reuse `GTM_RecycleBinController`'s methods directly (those are
    `@AuraEnabled`, user-invoked, and re-validate `Archived__c = true` via
    a fresh query scoped to caller-supplied Ids — a batch has its own
    `start()`/`execute()` scope already filtered correctly), but the
    delete semantics and `allOrNone=false` failure handling must match.
  - **Tile-row / cascade consideration:** unlike the cascade trigger (which
    treats the offering's tile row, `Section_Key__c='tile'` +
    `Template_Type__c='offerings-listing'`, as the parent whose state
    drives siblings), this batch purges whatever rows are independently
    past their own 30-day `Archived_Date__c` — it does not need to special-
    case tile vs. non-tile rows the way `GTM_RecycleBinController`'s
    restore path does (restore has a "parent still archived" block; purge
    is a terminal delete, not a restore, so there is no equivalent
    parent-dependency hazard to protect against — a tile row past 30 days
    and its already-restored-or-still-archived siblings are each
    independently eligible purely by their own `Archived_Date__c`). Note
    this explicitly as a design decision in code comments so a future
    reader does not assume cascade logic was accidentally dropped.
  - **What this explicitly does NOT include** (separate sub-issues, do not
    build here):
    - `184-recyclebin-lwc` — the recycle-bin LWC UI (`gtmRecycleBin` per
      `GTM_RecycleBinController.cls`'s header comment). No LWC/JS/markup
      work belongs in this slice.
    - `184-permissions` — permission-set grants and action-gating for the
      recycle-bin controller's `@AuraEnabled` actions (explicitly deferred
      per that controller's own header comment: "Nobody can actually reach
      this controller from the UI until that lands"). This batch class
      itself is server-side/scheduled only and does not add any new
      user-facing FLS-gated surface, but see the Code Dependency Checklist
      below for the one exception (CRUD/FLS on the two archive fields
      already exists from #187 — confirm, do not re-grant).
  - **Ambiguity flag for the Architect step:** the exact 30-day figure and
    whether it should be a Custom Metadata-configurable value (vs. a hard
    Apex constant) is not settled by any doc found in this repo — issue
    #184's body is the only source, and this BA pass could not independently
    verify its exact wording (not fetched from GitHub; only local repo docs
    were searched). If the Architect or Developer has access to the live
    GitHub issue text, confirm the exact retention window and any mention
    of a configurable-vs-hardcoded threshold before implementing. Absent
    that confirmation, default to a hardcoded `@TestVisible` constant
    (`PURGE_AFTER_DAYS = 30`), matching `GtmAssessmentDraftPurge`'s
    convention, as the lower-risk/reversible choice.
  - **Scheduled-job registration — flagged as a Definition-of-Done gap:**
    a batch class alone will not run on any cadence by itself.
    `GtmAssessmentDraftPurge` (the pattern class) is *not* scheduled by any
    deploy step either — confirmed via
    `docs/architecture/gtm-analytics-v1.md:128` ("Not scheduled by any
    deploy step...") and `docs/runbooks/questionnaire-resume.md`, which
    documents scheduling it as a manual one-time anonymous-Apex step
    (`System.schedule('MA Assessment Draft Purge', '0 0 3 * * ?', new
    GtmAssessmentDraftPurge());`) run by hand post-deploy, not via any
    Custom Metadata "Scheduled Jobs" record or automated registration
    mechanism — no such CMDT type exists in this codebase. **This sub-issue
    should follow the identical pattern**: ship `GTM_PurgeRecordsBatch`
    implementing both `Database.Batchable<SObject>` and `Schedulable`
    (so it is schedulable), document the equivalent manual
    `System.schedule(...)` anonymous-Apex step in a runbook (either a new
    doc or an addition to `docs/architecture/offering-archive-cascade.md`),
    and call out in the PR description that a human must run that
    `System.schedule` call by hand in `gtm-dev` after deploy — the class
    shipping alone does not make the purge actually run. Do not attempt to
    build a CMDT-based auto-registration mechanism; that would be new
    infrastructure well outside this issue's scope.
- **System Component Impacted:** Apex (new Batch/Schedulable class +
  its test class, `force-app/main/default/classes/`), plus a
  documentation update (runbook/architecture doc) for the manual
  `System.schedule` registration step. No LWC, no Custom Metadata schema
  change, no new object/field (the `Archived__c`/`Archived_Date__c` fields
  this batch queries already exist from #187).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No — this is a backend batch/scheduled
      class with no `@AuraEnabled` surface and no direct interaction with
      the GUS chat tool surface. The zero-DML rule in AGENTS.md §1 does not
      apply (this class's entire purpose is Apex-side `Database.delete`,
      run outside any GUS tool-call context).
- [ ] Altering Custom Metadata? No — no `GTM_Offering__mdt` or other CMDT
      change. Do not touch `migration-accelerator/` YAML or any
      `force-app/main/default/customMetadata/GTM_Assessment_*` XML for
      this task.
- [ ] Introducing database fields? No — `Archived__c` and
      `Archived_Date__c` on both `GTM_Page_Section__c` and
      `GTM_Page_Content__c` already exist and are already permission-set
      mapped per #187 (`docs/architecture/offering-archive-cascade.md`
      §"Consequences": `GTM_Offering_Admin`/`GTM_Content_Admin` full
      read/edit, `GTM_Content_Manager` matching existing grant,
      `GTM_Offering_User`/`GTM_Guest` none). This batch class itself runs
      as System context (batch/scheduled Apex bypasses FLS/sharing by
      default unless explicitly declared `with sharing` — follow
      `GtmAssessmentDraftPurge`'s own class-level sharing declaration,
      which is `with sharing`, as the precedent for this new class too),
      so no new permission-set mapping is required for this slice. Do not
      re-open or re-grant permission-set changes here — that would
      duplicate `184-permissions`' scope.

## 3. Plan Acceptance Criteria

- **Success Metric:** A scheduled/batchable `GTM_PurgeRecordsBatch` exists
  that, when run, permanently deletes every `GTM_Page_Section__c` and
  `GTM_Page_Content__c` row where `Archived__c = true` and
  `Archived_Date__c` is older than the purge-after-days threshold (30 by
  default), leaves rows not yet past that threshold untouched, uses
  `Database.delete(scope, false)` (or equivalent `allOrNone=false`) so one
  undeletable row does not strand the batch, and does not touch any row
  belonging to `GtmAssessmentDraftPurge`'s own object
  (`GTM_Form_Draft__c`) or any other unrelated object. A100% passing new
  Apex test class covers: (a) a record past the threshold is deleted, (b)
  a record archived but not yet past the threshold is preserved, (c) a
  non-archived record is never touched even if old, (d) both target
  objects are covered, (e) the `Schedulable.execute` method correctly
  kicks off the batch. The PR also adds/updates a runbook documenting the
  manual `System.schedule(...)` command needed to actually activate this
  in `gtm-dev`, explicitly flagging that deploying the class alone does
  not start the purge.
- **Target Test Target:** New Apex test class, e.g.
  `GTM_PurgeRecordsBatchTest.cls` (mirroring
  `GtmAssessmentDraftPurge`'s pairing with its own test class — confirm
  exact existing test class name/pattern for `GtmAssessmentDraftPurge` at
  implementation time if one exists alongside it in
  `force-app/main/default/classes/`, and match its structure/assertions
  style, e.g. `Test.startTest()`/`Test.stopTest()` around
  `Database.executeBatch`).
