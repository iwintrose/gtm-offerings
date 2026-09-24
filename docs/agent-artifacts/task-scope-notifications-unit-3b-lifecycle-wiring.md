# TASK SCOPE — ISSUE #notifications-unit-3b-lifecycle-wiring

## 1. Requirements Breakdown

- **Target Objective:** Wire the six ADR-0010 lifecycle trigger points to
  actually read `GTM_Notification_Settings__c` (shipped in Unit 3a,
  `agent/issue-notifications-unit-3`, not yet merged to `main` as of this
  scope pass — confirmed via `git log`/`git show` against that branch, not
  assumed) and fire/close Task + Custom Notification ("bell") events
  accordingly. Unit 3a shipped the schema
  (`GTM_Notification_Settings__c`), the admin-gated read/write controller
  (`GtmNotificationSettingsController.getOrgDefaults()` /
  `setNotificationSettings()`), the `gtmOfferingsSettingsNotifications` LWC
  section, the `GTM_Notification` custom notification type
  (`force-app/main/default/notificationtypes/GTM_Notification.notiftype-meta.xml`),
  and the `GTM_Offering_Admin` permission-set grants for the object — none
  of that is touched again here. This unit's job is exclusively the
  lifecycle wiring: reading the settings and firing/closing Task and bell
  events from the right Apex call sites.

- **System Component Impacted:** Apex only. Three existing classes gain new
  conditional DML (`GtmReadoutController`, `GtmReadoutApprovalHandler`) plus
  one class the ADR/Unit-3a scope doc misidentified (`GtmHomeSnapshotController`
  — corrected below to `GtmAssessmentRequestController`); one new small
  shared helper class; one metadata flip
  (`GTM_Assessment_Request__c.enableActivities`) required to make the
  design below work at all. No LWC, no new Custom Metadata, no `instrument/`
  YAML.

### 1a. Real design gap #1 — corrected: the "sixth wiring point" is not in `GtmHomeSnapshotController`

Both ADR-0010 and the Unit 3a scope doc (`docs/agent-artifacts/task-scope-notifications-unit-3.md`
§1d point 6) describe the New-Assessment-Request wiring point as living in
"`GtmHomeSnapshotController` (Status = New `GTM_Assessment_Request__c`
creation path)". **This is wrong and was never true of the actual code** —
verified by reading `GtmHomeSnapshotController.cls` in full: it is a
read-only dashboard-aggregation class (`getSnapshot()`,
`getRecentNewAssessmentRequests()`, `getDeals()`, `getLinkSitemap()`); it
contains no `insert GTM_Assessment_Request__c` anywhere and never could,
since it is a KPI reader, not a submission handler. The actual, only,
creation site of a `Status__c = 'New'` `GTM_Assessment_Request__c` record
in this codebase is `GtmAssessmentRequestController.submitAssessment(...)`
(confirmed by `grep -rn "new GTM_Assessment_Request__c("` returning exactly
one hit), specifically inside its `postInsertBestEffort(...)` best-effort
tail (after `insert req;`, alongside `generateDraftReadout(req.Id)`).
`GtmAssessmentRequestController` is `without sharing` and is the guest/
Experience-Cloud-facing prospect-submission controller — the running user
at insert time can be a guest user, not an internal rep, which materially
changes the notification wiring: the Task must be assigned via
`req.OwnerId` (already resolved server-side from `ctx.ownerId` in the
existing code, defaulting to the configurator's routed rep/queue), never
to the running (possibly guest) user. **Wiring point 6 is corrected to
`GtmAssessmentRequestController.postInsertBestEffort`, not
`GtmHomeSnapshotController`.** This is a correction to prior scope, not a
new decision — Architect/Developer should not re-derive it.

### 1b. Real design gap #2 — Task-tracking mechanism, resolved: reuse `Task.WhatId`, no new lookup fields

The developer who attempted this correctly flagged that several
`Auto_Close_*` fields require finding, at a *later* lifecycle moment, the
specific Task a *prior* lifecycle moment created. The candidate fix is
either (a) new `Id`-holding fields on `GTM_Readout__c`/
`GTM_Assessment_Request__c` to remember a created Task's Id, or (b) reusing
`Task.WhatId` (the polymorphic lookup every Task already carries back to
its parent record) plus a known, constant `Subject` string per lifecycle
stage, queried at close-time with
`WHERE WhatId = :recordId AND Subject = :knownSubject AND Status != 'Completed'`.

**Resolved: (b), reuse `Task.WhatId` + a per-stage constant `Subject`. No
new fields on `GTM_Readout__c` or `GTM_Assessment_Request__c`.** Reasoning:

- `GTM_Readout__c` already has `enableActivities` = `true` (confirmed in
  `force-app/main/default/objects/GTM_Readout__c/GTM_Readout__c.object-meta.xml`),
  so `Task.WhatId = <readoutId>` already works today with zero schema
  change — every readout-scoped Task in this design (points 1/2/3/4/5
  below) uses this path for free.
- `GTM_Readout__c` already carries `Assessment_Request__c` as a queried
  field in `GtmReadoutController.loadForUpdate` (confirmed: `SELECT ...,
  Assessment_Request__c FROM GTM_Readout__c`), so
  `submitForApproval`/`recallApproval` can resolve the originating
  request's Id from the readout already in hand, with no new lookup and no
  extra query round-trip.
- The tradeoff (b) accepts, made explicit rather than hidden: `Subject`
  becomes a load-bearing exact-match key, not just display text. This
  means the fire-side code must never interpolate record-specific text
  (readout name, requester name, etc.) into `Subject` — that content goes
  in `Description` instead — or the close-side exact-match query silently
  stops finding the Task it's supposed to close. This constraint is
  documented in the shared helper (§1d) so it's enforced in one place, not
  re-derived at each of the six call sites.
- **One schema change *is* still required, and must not be missed:**
  `GTM_Assessment_Request__c.object-meta.xml` currently has **no**
  `enableActivities` element at all (confirmed by reading the file in
  full — it has `enableFeeds` but not `enableActivities`), which means
  `Task.WhatId` **cannot** be set to a `GTM_Assessment_Request__c` Id today
  — the platform rejects a `WhatId` pointing at an activity-disabled
  object. Wiring point 6 (fire) and the `Auto_Close_New_Request_Tasks__c`
  half of wiring point 1 (close) both require this. **Flip
  `<enableActivities>true</enableActivities>` into
  `GTM_Assessment_Request__c.object-meta.xml` as part of this unit.** This
  is a one-line object-level metadata change, not a new field — it does
  not touch FLS/permission-set field grants (CLAUDE.md §6's
  field-permission mapping rule is about **fields**, not this object-level
  toggle), and does not require new object permissions since Activity
  visibility rides the running user's existing access to the parent
  record and to Tasks generally. Confirm this deploys cleanly against
  `gtm-staging` before treating it as done — enabling Activities on an
  object with existing records has no destructive effect (no record shape
  change), but it is still a genuine object-level metadata deploy and
  should be verified, not assumed.

### 1c. Real design gap #3 — flagged, not resolved: `Auto_Close_Published_Tasks__c` has no defined close-trigger

This is a genuine ambiguity neither ADR-0010 nor the Unit 3a scope doc
actually resolves, and I am not resolving it here — it needs a human or
Architect call before Developer builds it. The field table says
`Auto_Close_Published_Tasks__c` is "only meaningful when
`Published_Notification_Mode__c = 'Bell + Task'`; ignored otherwise" but
**never states what later lifecycle event closes that Task.** Contrast
with every other `Auto_Close_*` field, each of which has an explicit
"closes when `<method>` runs" clause:

- `Auto_Close_Submit_Tasks__c` → closes at `stampApproval`.
- `Auto_Close_Approved_Tasks__c` → closes at `publishReadout`.
- `Auto_Close_New_Request_Tasks__c` → closes at `submitForApproval` (per
  the ADR's own resolved decision).
- `Auto_Close_Published_Tasks__c` → **no stated closing event.**

The Task created at `publishReadout` (when the mode is `Bell + Task`) has
no natural "this readout moved past Published" moment in the six
enumerated wiring points — `returnToDraft` is explicitly blocked from a
`Published` readout in the existing code (`GtmReadoutController.
returnToDraft` throws "unpublish it first"), so it cannot be the close
trigger for a Published-stage Task. The only code path that moves a
readout off `Published` at all is `unpublishReadout` (Published →
Approved), which exists in `GtmReadoutController.cls` today but **is not
one of the ADR's six enumerated lifecycle points** and carries no
notification-settings field of its own. Two honest options, presented
without picking one:

1. Wire `Auto_Close_Published_Tasks__c` to `unpublishReadout` — the only
   code path that is a plausible "this is no longer true" moment for a
   Published-stage Task, even though it wasn't named as one of the six.
2. Treat `Auto_Close_Published_Tasks__c` as currently un-wireable within
   this unit's scope (build the Task-firing half only; leave the field
   readable/settable in the UI but functionally inert until a follow-up
   defines its trigger) and flag this back to the user/Architect as an
   open item rather than silently building option 1's guess.

**This scope doc does not choose between them — that decision needs the
same kind of explicit human sign-off the New-Assessment-Request
trigger-moment question got in ADR-0010's own addendum, not a BA guess.**
Everything else in this scope doc is fully specified and buildable
independent of this one open question.


### 1c-RESOLVED — Owner decision on `Auto_Close_Published_Tasks__c`'s close-trigger (post-BA-scope)

The open question in §1c above is now **resolved by the owner: Option 1,
no auto-close action.** `Auto_Close_Published_Tasks__c` ships as a
**no-op** for now — the checkbox exists and is settable in
`gtmOfferingsSettingsNotifications` (Unit 3a, unchanged), but **nothing in
this unit's code reads it to close a Task automatically**. A human closes
that Task manually if needed. Do **not** wire it to `unpublishReadout` or
any other lifecycle point, and do **not** build any new "acknowledge" /
"mark done" action on the Published-stage Task — that is explicitly out of
scope for this unit. Wiring point 4/5's fire-side behavior (§3) is
unaffected and still ships. Developer should not re-ask or re-derive this;
treat it as closed.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO.** `GtmReadoutController`,
      `GtmReadoutApprovalHandler`, `GtmAssessmentRequestController`, and the
      new shared helper are not `GtmAppTool` implementations and are not
      reachable from any GUS chat tool surface. The zero-DML tool-surface
      rule in AGENTS.md §1 does not apply to this unit.
- [ ] Altering Custom Metadata? **NO.** No `__mdt` involvement; no
      `migration-accelerator/` YAML; no `scripts/build-instrument.py`
      interaction.
- [ ] Introducing database fields? **NO new fields.** One object-level
      metadata flip only: `<enableActivities>true</enableActivities>`
      added to `GTM_Assessment_Request__c.object-meta.xml` (§1b). Since no
      field is introduced, there is **no new permission-set field-mapping
      requirement** under CLAUDE.md §6 — Task visibility/edit rights ride
      the running user's standard Activity access (every internal profile
      already has base Task CRUD; this repo does not restrict Task object
      permissions per CLAUDE.md §6's five-permission-set table, confirmed
      by grep: none of the five permission sets carry a `Task`
      `objectPermissions` block today, so none needs one added). If a
      later review determines Task-level FLS/object-perm restriction is
      actually needed for this feature, that is new scope, not part of
      this unit's Definition of Done.

## 3. Six wiring points — before/after pseudocode

All six read through `GtmNotificationSettingsController.getOrgDefaults()`
(Unit 3a, unchanged) and route Task fire/close through one new shared
helper, `GtmLifecycleNotificationService` (new class, this unit), so no
lifecycle class hand-rolls its own Task query/DML. Bell events route
through the same helper's `fireBell(...)`, wrapping
`Messaging.sendCustomNotification` against the `GTM_Notification`
`CustomNotificationType` Unit 3a already shipped.

```apex
// New, this unit: force-app/main/default/classes/GtmLifecycleNotificationService.cls
public with sharing class GtmLifecycleNotificationService {
    // Subject is a load-bearing exact-match key (see §1b) -- never
    // interpolate record-specific text into it. Record-specific text goes
    // in Description only.
    public static final String SUBJECT_APPROVE_READOUT      = 'Approve this readout';
    public static final String SUBJECT_READOUT_APPROVED     = 'Readout approved -- ready to publish';
    public static final String SUBJECT_RETURNED_TO_DRAFT    = 'Readout returned to draft -- revise and resubmit';
    public static final String SUBJECT_NEW_REQUEST          = 'New assessment request needs review';
    // Published-stage subject reserved but its close trigger is the open
    // question in §1c -- fire-side only is unambiguous, wired here.
    public static final String SUBJECT_READOUT_PUBLISHED    = 'Readout published';

    /** Bulk-safe: caller passes one WhatId/ownerId/subject/description per Task. */
    public static void fireTask(Id whatId, Id ownerId, String subject, String description) { ... }

    /** Bulk-safe close: exact WhatId + Subject match, open Tasks only. */
    public static void closeOpenTasks(Id whatId, String subject) { ... }

    public static void fireBell(Id recipientId, Id targetId, String title, String body) { ... }
}
```

**1. `GtmReadoutController.submitForApproval`** (Draft → Pending Approval)

```
// before: Approval.process(...) only

// after, before the Approval.process(...) call (so a submission that
// fails validation never fires a stray notification):
NotificationSettingsDto s = GtmNotificationSettingsController.getOrgDefaults();
if (s.notifyOnSubmitForApproval) {
    Id approverId = resolveManagerId(readout.OwnerId); // new small helper: User.ManagerId of readout owner
    if (approverId != null) {
        GtmLifecycleNotificationService.fireTask(
            readoutId, approverId, SUBJECT_APPROVE_READOUT,
            'A readout is waiting on your approval.');
        GtmLifecycleNotificationService.fireBell(approverId, readoutId,
            'Readout awaiting your approval', 'A readout is waiting on your approval.');
    }
}
if (s.autoCloseNewRequestTasks && readout.Assessment_Request__c != null) {
    GtmLifecycleNotificationService.closeOpenTasks(
        readout.Assessment_Request__c, SUBJECT_NEW_REQUEST);
}
// Hardcoded, not gated by any setting (per ADR-0010's own resolution --
// "no admin toggle plausibly wants a dangling 'revise this' Task to
// survive its own resubmission"):
GtmLifecycleNotificationService.closeOpenTasks(readoutId, SUBJECT_RETURNED_TO_DRAFT);
```

**2. `GtmReadoutController.recallApproval`** (Pending Approval → Draft, submitter-initiated)

```
// after a successful Approval.process(..., 'Removed') result:
// Corollary wiring, not a separate settings field (ADR-0010: "recall's
// only job is closing out whatever Task Notify_On_Submit_For_Approval__c
// created" -- inherits that field's effective state, no independent check).
NotificationSettingsDto s = GtmNotificationSettingsController.getOrgDefaults();
if (s.notifyOnSubmitForApproval) {
    GtmLifecycleNotificationService.closeOpenTasks(readoutId, SUBJECT_APPROVE_READOUT);
}
```

**3. `GtmReadoutApprovalHandler.stampApproval`** (Draft/Pending Approval → Approved, trigger context)

```
// after the existing field-stamping loop, per approved readout:
NotificationSettingsDto s = GtmNotificationSettingsController.getOrgDefaults();
for (GTM_Readout__c readout : approvedReadouts) {
    if (s.autoCloseSubmitTasks) {
        GtmLifecycleNotificationService.closeOpenTasks(readout.Id, SUBJECT_APPROVE_READOUT);
    }
    if (s.notifyOnApproved) {
        GtmLifecycleNotificationService.fireTask(readout.Id, readout.OwnerId,
            SUBJECT_READOUT_APPROVED, 'Your readout was approved and is ready to publish.');
        GtmLifecycleNotificationService.fireBell(readout.OwnerId, readout.Id,
            'Readout approved', 'Your readout was approved and is ready to publish.');
    }
}
// NOTE: stampApproval is a BEFORE-UPDATE handler on GTM_Readout__c itself,
// but Task is a different sObject -- DML against Task here is safe (no
// recursive-trigger risk on GTM_Readout__c) and does not need to move to
// an after-update handler.
```

**4/5. `GtmReadoutController.publishReadout`** (Approved → Published; two independent reads in one method, per the ADR's own framing — not two methods)

```
// after the existing update readout / insert version block succeeds,
// alongside the existing sendPublishNotification(...) best-effort call:
NotificationSettingsDto s = GtmNotificationSettingsController.getOrgDefaults();
if (s.autoCloseApprovedTasks) {
    GtmLifecycleNotificationService.closeOpenTasks(readoutId, SUBJECT_READOUT_APPROVED);
}
if (s.publishedNotificationMode != GtmNotificationSettingsController.MODE_NONE) {
    Boolean withTask = s.publishedNotificationMode == GtmNotificationSettingsController.MODE_BELL_AND_TASK;
    if (withTask) {
        GtmLifecycleNotificationService.fireTask(readoutId, readout.OwnerId,
            SUBJECT_READOUT_PUBLISHED, 'Your readout was published.');
        // s.autoClosePublishedTasks read here for completeness of intent,
        // but its CLOSE side has no defined trigger point -- see open
        // question in §1c. Do not silently wire it to unpublishReadout
        // without the sign-off described there.
    }
    GtmLifecycleNotificationService.fireBell(readout.OwnerId, readoutId,
        'Readout published', 'Your readout was published.');
}
```

**6. `GtmReadoutController.returnToDraft`** (Approved → Draft, manager-initiated)

```
// after the existing insert version / update readout block succeeds:
NotificationSettingsDto s = GtmNotificationSettingsController.getOrgDefaults();
if (s.notifyOnReturnedToDraft) {
    GtmLifecycleNotificationService.fireTask(readoutId, readout.OwnerId,
        SUBJECT_RETURNED_TO_DRAFT, 'A manager returned your readout to draft for revision.');
    GtmLifecycleNotificationService.fireBell(readout.OwnerId, readoutId,
        'Readout returned to draft', 'A manager returned your readout to draft for revision.');
}
// This Task's own auto-close-on-resubmission is the hardcoded call inside
// submitForApproval (wiring point 1 above), not a field read here.
```

**Corrected 7th point (was mislabeled "6" in prior scope — see §1a): `GtmAssessmentRequestController.postInsertBestEffort`** (new `Status = 'New'` request)

```
// after the existing generateDraftReadout(req.Id) best-effort call, still
// inside the same try/catch so a notification failure never fails the
// prospect's submission:
NotificationSettingsDto s = GtmNotificationSettingsController.getOrgDefaults();
if (s.notifyOnNewAssessmentRequest && req.OwnerId != null) {
    GtmLifecycleNotificationService.fireTask(req.Id, req.OwnerId,
        SUBJECT_NEW_REQUEST, 'A new assessment request came in and needs review.');
    GtmLifecycleNotificationService.fireBell(req.OwnerId, req.Id,
        'New assessment request', 'A new assessment request came in and needs review.');
}
```

(ADR-0010 counts this as one of "six" lifecycle points; this scope doc's
pseudocode above enumerates seven code-level call sites because
`recallApproval`'s close-only wiring and `publishReadout`'s two
independent reads are corollaries of points already counted in the ADR's
six, not additional settings fields. No new field is introduced beyond the
nine Unit 3a already shipped.)

## 4. Plan Acceptance Criteria

- **Success Metric:** QA confirms, in a `gtm-staging` validate-only pass
  plus browser/Apex-test verification: (1) each of the seven call sites
  above fires/closes Tasks and bells exactly per its setting, toggled
  off/on; (2) `Auto_Close_New_Request_Tasks__c` closes the originating
  request's Task specifically at `submitForApproval` time via
  `Task.WhatId = <requestId>` lookup, not at request-open or
  `generateDraftReadout` time; (3) `recallApproval` closes the approver
  Task created by `submitForApproval` when `Notify_On_Submit_For_Approval__c`
  is on, and does nothing when it's off; (4) `returnToDraft`'s Task is
  confirmed closed automatically (hardcoded, not setting-gated) the next
  time `submitForApproval` runs on the same readout; (5)
  `GTM_Assessment_Request__c` deploys cleanly with `enableActivities=true`
  and a Task can be inserted against it with `WhatId` set (this must be
  verified as a real deploy+DML check, not assumed from the metadata file
  alone); (6) `Auto_Close_Published_Tasks__c`'s close-side behavior is
  **not** built until the §1c open question is answered — if Developer is
  handed this scope before that answer exists, the fire-side (Task/bell
  creation on `Bell + Task` mode) may still ship, but no code should guess
  a close trigger for it.
- **Target Test Target:** Extended coverage (on/off branch per field) in
  `GtmReadoutControllerTest.cls` (`submitForApproval`, `recallApproval`,
  `publishReadout`, `returnToDraft`, plus the `stampApproval` coverage that
  already lives in this file per the trigger wiring) and
  `GtmAssessmentRequestControllerTest.cls` (new-request Task/bell firing).
  New small test coverage for `GtmLifecycleNotificationService` itself
  (fire/close primitives, bulk-safety with 2+ records). Run via
  `sf apex run test --class-names GtmReadoutControllerTest,GtmAssessmentRequestControllerTest,GtmLifecycleNotificationServiceTest,GtmNotificationSettingsControllerTest --target-org gtm-staging` (never `RunLocalTests`, per `docs/runbooks/api-request-budget.md`).

## Definition of Done

- [ ] `GTM_Assessment_Request__c.object-meta.xml` has
      `<enableActivities>true</enableActivities>` added and deployed;
      verified with a real Task insert against a request record's Id on
      `gtm-staging` (not assumed from the XML alone).
- [ ] New `GtmLifecycleNotificationService.cls` (+ test class) shipped:
      `fireTask`, `closeOpenTasks`, `fireBell`, bulk-safe, Subject
      constants documented as exact-match keys.
- [ ] All seven call sites in §3 implemented exactly as pseudocoded,
      reading settings exclusively through
      `GtmNotificationSettingsController.getOrgDefaults()` (no direct
      `GTM_Notification_Settings__c.getOrgDefaults()` query duplicated
      across the three/four classes).
- [ ] Wiring point 6/7 (new-request notification) lives in
      `GtmAssessmentRequestController.postInsertBestEffort`, not
      `GtmHomeSnapshotController` — confirmed by this scope doc's own
      correction in §1a; Developer must not restore the earlier
      (incorrect) attribution.
- [x] `Auto_Close_Published_Tasks__c`'s close-side trigger question is
      **resolved (owner, Option 1): no auto-close action.** The checkbox
      remains settable in the UI but is a no-op in this unit's Apex — no
      code reads it to close a Task, and no new "acknowledge"/"mark done"
      action is built. The fire-side (Task+bell on `Bell + Task` mode)
      ships per §3 points 4/5 as originally pseudocoded. Do not wire this
      field to `unpublishReadout` or any other lifecycle point.
- [ ] `recallApproval` closes the `submitForApproval` Task when
      `Notify_On_Submit_For_Approval__c` is on (§3 point 2), and
      `submitForApproval` unconditionally closes any open
      `Returned to draft` Task on the same readout (§3 point 1, hardcoded).
- [ ] No new fields on `GTM_Readout__c` or `GTM_Assessment_Request__c`; no
      permission-set changes required by this unit (§2).
- [ ] Extended Apex test coverage per §4's Target Test Target, all passing
      against `gtm-staging`.
- [ ] QA validate-only run against `gtm-staging` per the Success Metric in
      §4, including explicit confirmation of the `enableActivities` deploy
      and the `Auto_Close_New_Request_Tasks__c` timing behavior.
