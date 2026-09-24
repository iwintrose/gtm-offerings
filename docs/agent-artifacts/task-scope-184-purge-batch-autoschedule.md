# TASK SCOPE — ISSUE #184-purge-batch-autoschedule

## 1. Requirements Breakdown

- **Target Objective:** Eliminate the manual, human-run anonymous-Apex
  `System.schedule(...)` step currently required to activate **both**
  scheduled purge jobs in this app:
  - `GTM_PurgeRecordsBatch` (issue #184 part 5, shipped in not-yet-merged
    PR #195, branch `agent/issue-184-purge-batch`). Today the class exists
    but does nothing on a fresh deploy — its own header comment says so
    explicitly.
  - `GtmAssessmentDraftPurge` (already on `main` today,
    `force-app/main/default/classes/GtmAssessmentDraftPurge.cls`). It has
    the identical gap: `implements Database.Batchable<SObject>, Schedulable`
    but nothing ever calls `System.schedule(...)` on it. Its own header
    comment says "Schedule it daily. See
    `docs/runbooks/questionnaire-resume.md`," and that runbook's only
    activation path today is the manual anonymous-Apex command
    `System.schedule('MA Assessment Draft Purge', '0 0 3 * * ?', new GtmAssessmentDraftPurge());`
    (`docs/runbooks/questionnaire-resume.md:170`).

  **Scope-boundary decision (made by the user, not left open):** this
  issue covers **both** jobs in one fix, not `GTM_PurgeRecordsBatch`
  alone. The two jobs share the exact same activation gap (Schedulable
  class exists, nothing schedules it without a human running anonymous
  Apex), and the user wants one mechanism that closes both rather than
  shipping a fix that still leaves `GtmAssessmentDraftPurge`
  unactivatable. This is a widened scope versus the BA's original
  recommendation (which defaulted to narrow, `GTM_PurgeRecordsBatch`-only,
  scope) — that recommendation is superseded by this explicit user
  decision.

  The org this ships into (`gtm-dev`, treated as production per CLAUDE.md
  §1) will often be set up by someone other than the person who deployed
  it, so the activation step must not require CLI/anonymous-Apex access.
  Give an admin a UI-driven way to see whether each purge job is scheduled
  and to schedule/reschedule each with a click.

  **Recommended mechanism (for the Architect to confirm, not a BA
  decision to finalize):** reuse the exact pattern already live in
  `GtmAnalyticsSettingsController.cls` (issue #147) — a Custom Setting
  (or reuse of an existing one) holding scheduling state, an
  `@AuraEnabled` `getSettings()`/`saveSettings()`-style pair, and a
  private `abortExistingJob()` helper that queries
  `[SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :JOB_NAME LIMIT 1]`
  before aborting, so re-saving is idempotent (abort-then-reschedule, never
  a duplicate-job exception). Because this issue now covers two jobs, the
  controller/data shape should be **generic across both** rather than a
  single hardcoded job: a `jobName`/`cronExpression`-parameterized method
  pair (or a small `List<PurgeJobStatus>`-style wrapper) that the
  `getSettings()` call returns one entry per known job, and `saveSettings()`
  (or a per-job `scheduleJob(String jobKey)` action) can abort-then-reschedule
  either job independently, using the same `CronTrigger`
  existence-check idempotency pattern for both. Expose this as a new
  "Scheduled Jobs" section in `gtmOfferingsSettings`, alongside "Approval
  Routing," "Analytics Notifications," and "Claude / GUS" — the section
  should list **both jobs**, each showing its own current status
  (scheduled / not scheduled, next run description) and its own manual
  "Schedule Now" / reschedule action, mirroring
  `GtmAnalyticsSettingsController.getSettings()`'s `nextRunDescription`
  convention, applied per-job.

  **Reasoning against the alternatives raised in the initiating brief**
  (unchanged from the original scope, still applies to both jobs):
  - *Auto-schedule silently on first Settings-page load* (option b/c) is
    rejected as the primary mechanism. It requires a cheap-enough
    existence check to run on every page load of `gtmOfferingsSettings`
    regardless of which section the admin is viewing, which either means a
    `CronTrigger` query firing on every load (wasteful, and subtly changes
    a read-only page load into one with the potential for hidden
    side-effects) or a `@AuraEnabled` call gated behind first-visit
    tracking (added state, added edge cases: what happens if that flag
    trips before the retention custom-object fields are even deployed,
    what happens on a sandbox refresh where the flag persists but the job
    doesn't). It also breaks the same "admin's own click is what commits
    the change" boundary `GtmAnalyticsSettingsController`'s own doc
    comment calls out for issue #147 — auto-scheduling on load is a
    deploy/agent-adjacent action happening without a human's explicit
    action, the same class of thing that comment says matters here.
  - *Manual button only, no status display* (bare option a) is close but
    weaker than showing current status — a status-blind button invites an
    admin to click it repeatedly "just in case" or to never notice it
    still isn't scheduled after a failed click.
  - Recommended: **status display + manual trigger, per job**, matching
    the Analytics Notifications section's shape as closely as possible
    (this is option (a) with visibility added, not full option (c) — no
    silent auto-fire-on-load). This keeps the change additive, reuses a
    pattern QA and reviewers already know, and keeps the "human clicks
    Save" (or "human clicks Schedule Now") contract intact for each job
    independently, without leaving either admin action blind to whether
    the corresponding job is live.

- **System Component Impacted:** Apex (new/extended controller class,
  possibly a new lightweight Custom Setting or an addition to an existing
  one — Architect to decide which; must be shaped to manage **two** jobs,
  `GTM_PurgeRecordsBatch` and `GtmAssessmentDraftPurge`, not one), LWC
  (`gtmOfferingsSettings` shell plus one new child section component, e.g.
  `gtmOfferingsSettingsScheduledJobs` — Architect's call on name — that
  renders a list/row per job rather than a single hardcoded job), and
  correspondingly the `GTM_Content_Admin`/`GTM_Offering_Admin` permission
  sets per CLAUDE.md §6 if any new custom setting/object field is
  introduced. **Not** a YAML Instrument or Experience Cloud Route change.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? — **No.** This does not touch
      `GtmAgentToolSurface`, `GtmAgentProxyController`, or any tool
      implementation; the AGENTS.md §1 zero-DML-in-tool rule does not
      apply here, though the general "propose vs. commit" spirit (a
      human's click, not an automatic trigger, commits the schedule
      change) is the reasoning behind rejecting the silent-auto-schedule
      option above.
- [ ] Altering Custom Metadata? — **No**, this is Custom Setting /
      Apex / LWC work, not `GTM_Assessment_*` CMDT. `scripts/build-instrument.py`
      and the YAML-is-truth rule are not implicated.
- [ ] Introducing database fields? — **Possibly.** If the Architect
      chooses to add a dedicated `GTM_Purge_Settings__c` (or similarly
      named) Custom Setting rather than reusing/extending an existing one,
      any new field must be mapped into `GTM_Offering_Admin` (and
      `GTM_Content_Admin` if content-object-adjacent) per CLAUDE.md §6 —
      full CRUD/FLS on the new setting, `viewAllRecords`/`modifyAllRecords`
      left at the object's existing setting, never org-wide Modify/View
      All Data. If instead the Architect folds this into the existing
      `GTM_Analytics_Settings__c` object or another already-permissioned
      custom setting, confirm the existing permission set entries already
      cover the new field(s) or extend them.

- **Code surface now explicitly includes `GtmAssessmentDraftPurge.cls`**,
  not just `GTM_PurgeRecordsBatch`, per the user's scope decision above.
  `GtmAssessmentDraftPurge.cls` itself does **not** need its purge
  query/delete logic touched — only its scheduling activation path is in
  scope, same as `GTM_PurgeRecordsBatch`.

## 2a. `GtmAssessmentDraftPurge.cls` shape review (for the new controller to schedule it)

Read directly (`force-app/main/default/classes/GtmAssessmentDraftPurge.cls`,
current `main`):

- It `implements Database.Batchable<SObject>, Schedulable` — same
  interface pairing the controller will need to call
  `System.schedule(jobName, cronExpr, (Schedulable) new GtmAssessmentDraftPurge())`
  against, structurally identical to how it will call
  `GTM_PurgeRecordsBatch`.
- **No existing cron-expression constant on the class itself.** The only
  cron string in the codebase for this job lives in the runbook
  (`docs/runbooks/questionnaire-resume.md:170`):
  `System.schedule('MA Assessment Draft Purge', '0 0 3 * * ?', new GtmAssessmentDraftPurge());`
  — i.e. daily at 3:00 AM, job name `'MA Assessment Draft Purge'`. The
  class does not expose either the job name or the cron expression as an
  `@TestVisible`/`public static final` constant the way a
  parameterized controller would want to reference; both currently live
  only as a copy-pasted literal in the runbook doc. **Recommend the
  Architect add a small `@TestVisible private static final String
  CRON_EXPRESSION` (and optionally `JOB_NAME`) constant to
  `GtmAssessmentDraftPurge.cls` itself**, mirroring whatever constant
  shape the Architect chooses for `GTM_PurgeRecordsBatch`, so the new
  settings controller has one canonical source for the schedule instead
  of a second copy-pasted cron literal living in Apex. This is a small,
  additive, low-risk touch to the class (adding a constant, not changing
  `start`/`execute`/`finish` logic) — it does not require touching the
  `SUBMITTED_GRACE_DAYS` constant or any purge logic.
- It otherwise already exposes what's needed: no constructor arguments,
  no required setup beyond `System.schedule`, so the settings controller
  can treat it exactly like `GTM_PurgeRecordsBatch` for scheduling
  purposes once (optionally) the cron/job-name constant lands on it.
- Confirm whether `GTM_PurgeRecordsBatch` (per PR #195, not yet merged —
  BA has not read its final diff since it isn't on `main`) uses the same
  `'0 0 3 * * ?'`-style daily cron or a different cadence; if they differ,
  the generic "Scheduled Jobs" section must carry a per-job cron
  expression, not a single shared one. This is an Architect check against
  PR #195's actual diff once it exists in a reachable branch.

## 3. Plan Acceptance Criteria

- **Success Metric:** After deploying this change to a fresh or existing
  `gtm-dev`-equivalent org, an admin with `GTM_Offering_Admin` (or the
  relevant admin permission set) can open the GTM Offerings Settings tab
  and, for **each** of `GTM_PurgeRecordsBatch` and `GtmAssessmentDraftPurge`
  independently:
  - see whether that job is currently scheduled (and its next-run
    description if so), and
  - click a single action to schedule (or reschedule) it —
  without Setup, Developer Console, or the `sf` CLI. Re-clicking either
  job's action does not throw a duplicate-CronTrigger error (idempotent
  abort-then-reschedule per job, matching
  `GtmAnalyticsSettingsController.abortExistingDigestJob()`). Existing
  tests for both jobs' purge logic continue to pass unmodified — this
  issue only adds a scheduling UI/controller layer, it does not change
  either job's query/delete logic. `GTM_PurgeRecordsBatch`'s tests are
  whatever ships with PR #195; `GtmAssessmentDraftPurge`'s existing tests
  (already on `main`) must remain green.
- **Target Test Target:** New Apex test class for the scheduling
  controller (mirroring `GtmAnalyticsSettingsControllerTest.cls` — cover
  `getSettings()`/`saveSettings()` (or per-job schedule action) for
  **both** jobs, idempotent reschedule for **both**, and the CronTrigger
  guard for **both**), plus a new Jest spec for the new settings section
  LWC (mirroring `gtmOfferingsSettingsAgent/__tests__/gtmOfferingsSettingsAgent.test.js`
  in shape, asserting both job rows render and each row's action fires
  independently). Exact class/spec file names are an Architect/Developer
  decision once the component is named.

---

## Sequencing note for the Architect (not a scope ambiguity, a dependency)

This issue has **two independent halves with different readiness**:

1. **`GTM_PurgeRecordsBatch` half** depends on PR #195 being merged first —
   `GTM_PurgeRecordsBatch` does not exist on `main` yet (confirmed: only
   present on `origin/agent/issue-184-purge-batch`, commit `55a751f`).
   The Architect should either (a) wait to provision the worktree until
   #195 merges, or (b) provision against a base that includes #195's
   commit if the workflow needs to start in parallel.
2. **`GtmAssessmentDraftPurge` half has no such dependency** —
   `GtmAssessmentDraftPurge.cls` already exists on `main` today (verified
   directly, current file read above) and can be scheduled by the new
   controller as soon as the controller/LWC work begins, independent of
   PR #195's merge status. If the Architect wants to unblock partial
   progress before #195 lands, the `GtmAssessmentDraftPurge` row of the
   "Scheduled Jobs" section can be built and tested first, with the
   `GTM_PurgeRecordsBatch` row following once #195 merges.

Flagging both explicitly rather than guessing which sequencing the
Architect prefers.

## Scope-boundary decision — RESOLVED (was previously open, now decided)

The prior version of this scope file left open whether to fold
`GtmAssessmentDraftPurge` into this issue or keep it narrow to
`GTM_PurgeRecordsBatch` only, recommending the narrow option by default.
**The user has since explicitly decided: combined scope.** Both jobs are
covered by this single issue, using one generic "Scheduled Jobs"
mechanism rather than a single-purpose "Purge Batch" section. This
section is retained only as a record of that decision, not as an open
question for the Architect.
