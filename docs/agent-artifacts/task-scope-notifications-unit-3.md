# TASK SCOPE — ISSUE #issue-notifications-unit-3

## 1. Requirements Breakdown

- **Target Objective:** Ship ADR-0010's Unit 3 — the "Notifications" Section 3
  of the `gtmOfferingsSettings` tab. This is the last of the three sequenced
  units (Unit 1 = tab shell + migrated Approval section, merged via PR #169;
  Unit 2 = Claude/GUS section, also merged via PR #169) and was previously
  blocked pending a human product decision that is now resolved (see below).
  The objective is to turn ADR-0010's six lifecycle events from hardcoded
  per-event behavior into admin-configurable rules, backed by a new
  Hierarchy Custom Setting, and to wire six existing Apex trigger points to
  read those rules before firing a Task/bell `CustomNotificationType` event.
  This ADR is the primary source of truth for this scope doc; do not
  relitigate any decision it already made — only decisions it explicitly
  left open (the trigger-moment question below) are re-opened here, and that
  one is now closed too.

- **System Component Impacted:** Apex (new controller class +
  `GTM_Notification_Settings__c` Hierarchy Custom Setting object + six
  lifecycle wiring points across three existing classes) + LWC (new
  `gtmOfferingsSettingsNotifications` child component wired into the
  existing `gtmOfferingsSettings` shell's nav rail as Section 3) +
  metadata (new `CustomNotificationType`) + permission sets (five-set grant
  plan below) + `scripts/deploy.sh` (one new manual-step echo line).

### 1a. Pre-flight verification against current `main` (confirmed by this BA pass)

- **Unit 1 — confirmed shipped.** `force-app/main/default/tabs/GTM_Offerings_Settings.tab-meta.xml`
  exists; `GTM_Readout_Approval_Settings.tab-meta.xml` no longer exists in
  the tree (retired, not left dual-running, matching the ADR). The
  `GTM_Offering_Admin` permission set carries a `tabSettings` entry for
  `GTM_Offerings_Settings` and no leftover entry for the old tab name.
- **Unit 2 — confirmed shipped.** `GtmAgentSettingsController.cls` (+ test
  class) exists; `lwc/gtmOfferingsSettingsAgent` exists alongside
  `lwc/gtmOfferingsSettings` (the shell). `GTM_Agent_Settings__c` field
  permissions (`Claude_API_Key__c` etc.) are present on `GTM_Offering_Admin`.
  Both merged via PR #169 ("agent/issue-settings-units-2-3").
- **Unit 3 — confirmed not started.** No `GTM_Notification_Settings__c`
  object directory under `force-app/main/default/objects/`, no
  `GtmNotificationSettingsController`, no `gtmOfferingsSettingsNotifications`
  LWC, no `force-app/main/default/customNotificationTypes/` directory at
  all (zero files, matching the ADR's own confirmation that this repo had
  none as of ADR-authoring time — still true now).
- **No confusion with the unrelated Analytics digest feature.** `main`
  already has a `GTM_Analytics_Settings__c` Hierarchy Custom Setting
  (issue #147, weekly digest email on/off + day/hour) with its own grant on
  `GTM_Offering_Admin`. This is a separate feature from
  `GTM_Notification_Settings__c` and must not be conflated with it or reused
  — Unit 3 introduces a distinct new object with the field list below.
- **Lifecycle trigger-point method names confirmed present and matching the
  ADR's references:** `GtmReadoutController.submitForApproval` (line ~1674),
  `GtmReadoutController.publishReadout` (line ~1930),
  `GtmReadoutController.returnToDraft` (line ~2237),
  `GtmReadoutApprovalHandler.stampApproval` (line ~52, trigger-handler
  class, `without sharing`), and `GtmHomeSnapshotController` (Status = `New`
  `GTM_Assessment_Request__c` counting logic, `with sharing`) all exist on
  `main` unchanged from what the ADR describes. No other `main` change since
  the ADR was written affects this scope.
- **Conclusion:** the foundation Unit 3 builds on is exactly what the ADR
  assumes. No re-scoping needed on that front.

### 1b. New object: `GTM_Notification_Settings__c` (Hierarchy Custom Setting)

Mechanically identical to `GTM_Readout_Approval_Settings__c` and
`GTM_Agent_Settings__c`: org-default row only, exposed through a
`getOrgDefaults()`/`upsert` admin-gated Apex controller pair
(`GtmNotificationSettingsController`, parallel in shape to
`GtmReadoutApprovalSettingsController`/`GtmAgentSettingsController`), no
row-level access model beyond object-level FLS.

Field list (verbatim from ADR-0010, confirmed final for Section 3 — do not
alter without a new ADR addendum):

| Field | Type | Governs |
|---|---|---|
| `Notify_On_Submit_For_Approval__c` | Checkbox | Task + bell fires when a readout is submitted for approval (`GtmReadoutController.submitForApproval`) |
| `Auto_Close_Submit_Tasks__c` | Checkbox | Whether the approver's Task auto-closes when `GtmReadoutApprovalHandler.stampApproval` runs for the same record |
| `Notify_On_Approved__c` | Checkbox | Task + bell fires for the submitting rep when a readout clears approval (`GtmReadoutApprovalHandler.stampApproval`) |
| `Auto_Close_Approved_Tasks__c` | Checkbox | Whether that Task auto-closes when the rep calls `publishReadout` |
| `Published_Notification_Mode__c` | Picklist (`None` / `Bell Only` / `Bell + Task`) | What fires, if anything, on `GtmReadoutController.publishReadout` |
| `Auto_Close_Published_Tasks__c` | Checkbox | Only meaningful when `Published_Notification_Mode__c = 'Bell + Task'`; ignored otherwise |
| `Notify_On_New_Assessment_Request__c` | Checkbox | Whether a new `GTM_Assessment_Request__c` (Status = `New`) becomes a Task + bell event instead of only a passive `GtmHomeSnapshotController` dashboard count |
| `Auto_Close_New_Request_Tasks__c` | Checkbox | On/off only — trigger moment resolved below (was the ADR's one open item) |
| `Notify_On_Returned_To_Draft__c` | Checkbox | Task + bell fires for the rep when a manager calls `returnToDraft` |

Deliberately **no field** for the Recalled-by-submitter event (inherits
`Notify_On_Submit_For_Approval__c`'s effective state — recall only closes out
whatever Task that field created). Deliberately **no field** for
Returned-to-Draft's auto-close (hardcoded lifecycle coupling on
resubmission, not a configurable axis — no admin toggle plausibly wants a
dangling "revise this" Task to survive its own resubmission).

### 1c. Resolved decision — `Auto_Close_New_Request_Tasks__c` trigger moment

ADR-0010 explicitly left this open ("blocked on the user's answer... before
Unit 3 is built"). **The user has now resolved it in this task's kickoff:**
when `Auto_Close_New_Request_Tasks__c` is enabled, the New-Assessment-Request
Task closes at `GtmReadoutController.submitForApproval` time — i.e. the same
trigger point that already exists for `Auto_Close_Submit_Tasks__c`, not at
read-time (rep opens the request) and not at `generateDraftReadout` time.
Rationale carried forward from the resolution: every other auto-close field
in the table above ties to a concrete completed action, never a passive
"viewed it" moment, and reusing `submitForApproval` needs zero new trigger
infrastructure — lowest risk, most consistent with the existing pattern.
Concretely: the `submitForApproval` wiring point (see 1d below) must check
**both** `Auto_Close_Submit_Tasks__c` (closes the approval-flow Task it
created) **and** `Auto_Close_New_Request_Tasks__c` (closes the originating
new-request Task, if one was created back when the request was logged) —
these are two independent Tasks that can both resolve at the same Apex
call, not one shared toggle.

### 1d. Six lifecycle wiring points (all reads of the new setting; writes stay in the two DML-owning classes named)

1. `GtmReadoutController.submitForApproval` — read
   `Notify_On_Submit_For_Approval__c` to decide whether to fire the
   Task+bell event for the approver; read `Auto_Close_New_Request_Tasks__c`
   (per 1c above) to decide whether to close the originating new-request
   Task, if any exists for this readout's source request.
2. `GtmReadoutApprovalHandler.stampApproval` — read
   `Auto_Close_Submit_Tasks__c` to decide whether to close the approver's
   Task created in (1); read `Notify_On_Approved__c` to decide whether to
   fire the Task+bell event back to the submitting rep.
3. `GtmReadoutController.publishReadout` — read
   `Auto_Close_Approved_Tasks__c` to decide whether to close the Task
   created in (2); read `Published_Notification_Mode__c`
   (`None`/`Bell Only`/`Bell + Task`) to decide what fires on publish.
4. `GtmReadoutController.publishReadout` (same call, second read) — read
   `Auto_Close_Published_Tasks__c`, only meaningful/consulted when
   `Published_Notification_Mode__c = 'Bell + Task'` — this is the fourth
   distinct config read inside the same method, not a fifth wiring point,
   but must be implemented as its own conditional branch, not folded
   silently into (3)'s logic, since it is ignored under the other two modes.
5. `GtmReadoutController.returnToDraft` — read
   `Notify_On_Returned_To_Draft__c` to decide whether to fire the Task+bell
   event to the rep; the Task's own auto-close-on-resubmission stays the
   existing hardcoded behavior (no new field, see 1b above).
6. `GtmHomeSnapshotController` (Status = `New` `GTM_Assessment_Request__c`
   creation path) — read `Notify_On_New_Assessment_Request__c` to decide
   whether the new request becomes an active Task+bell event in addition to
   the existing passive dashboard count.

All six reads go through `GtmNotificationSettingsController.getOrgDefaults()`
(or an equivalent cached-read helper on that class) — do not have each
lifecycle class query `GTM_Notification_Settings__c.getOrgDefaults()`
directly and duplicate null-handling/default logic across three classes.

### 1e. `CustomNotificationType` — deployability confirmed, one manual-step gap

Confirmed per ADR-0010: `CustomNotificationType` deploys cleanly in DX
source format at
`force-app/main/default/customNotificationTypes/<Name>.customNotificationType-meta.xml`
(zero such files exist in this repo today, confirmed again by this pass) —
`Messaging.sendCustomNotification` works immediately post-deploy with no
manual Setup step for the type's existence itself. What the deploy does
**not** cover, and must be handled explicitly:

- The org-wide "Enable in-app and mobile notifications" toggle under
  Setup › Notification Builder is a one-time manual click a metadata deploy
  cannot flip on its own (this repo's `gtm-prod` has never shipped a
  `CustomNotificationType` before, so this toggle's current state is
  unverified and should be assumed off until checked).
- Per-user delivery-channel preference (desktop/mobile/off) is a personal
  Setup preference no deploy or admin action can pre-set — expected
  behavior, not a defect to work around.
- **Required deliverable:** add one manual-step line to `scripts/deploy.sh`'s
  post-deploy echo block, reading approximately: *"If this is the first
  CustomNotificationType in this org, confirm Setup › Notification Builder
  › in-app/mobile notifications is enabled — a metadata deploy does not turn
  this on by itself."* This line is Unit 3's responsibility per the ADR;
  Developer should not treat it as optional polish.

### 1f. `gtmOfferingsSettingsNotifications` LWC (Section 3)

New child component, same shape as the existing `gtmOfferingsSettingsAgent`
(Unit 2) and the migrated Approval section (Unit 1): one LWC, backed by
`GtmNotificationSettingsController`, rendered by the existing
`gtmOfferingsSettings` shell when "Notifications" is selected in the nav
rail. Add it to the `SECTIONS` array in
`force-app/main/default/lwc/gtmOfferingsSettings/gtmOfferingsSettings.js`
(currently holds Section 0 Setup checklist, Section 1 Approval, Section 2
Claude/GUS — Notifications becomes Section 3, appended, not inserted
earlier in the list). The shell owns no settings logic — this component
manages its own `@wire`/Apex load-save pair exactly like its Section 1/2
siblings; do not introduce a shared save/load abstraction across sections
(ADR-0010 explicitly rejects that generalization).

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? **NO.** This unit does not touch
      `GtmAgentToolSurface`, any `GtmAppTool` implementation, or any of the
      GUS chat surfaces. No zero-DML-in-tool concern applies here.
- [ ] Altering Custom Metadata? **NO** — `GTM_Notification_Settings__c` is a
      Hierarchy **Custom Setting**, not Custom Metadata (`__mdt`). No
      `migration-accelerator/` YAML or `scripts/build-instrument.py`
      interaction. (The ADR's separately-deferred `GTM_Offering__mdt`
      target-value editing question is explicitly out of scope for this
      unit and for this whole ADR's first version — do not pull it in.)
- [x] **Introducing database fields? YES.** New object
      `GTM_Notification_Settings__c` with the nine fields listed in §1b.
      Per CLAUDE.md §6, mapping to permission sets is mandatory and is
      **not** to be re-derived — ADR-0010 already produced the authoritative
      grant table (reproduced verbatim below); Developer implements exactly
      this, not a fresh interpretation:

  | Set | New tab section (Notifications, part of existing `GTM_Offerings_Settings` tab) | `GTM_Notification_Settings__c` |
  |---|---|---|
  | `GTM_Offering_Admin` | No new tab entry needed — Unit 1 already granted `tabSettings: Visible` on `GTM_Offerings_Settings`; Section 3 rides the same tab. Apex class access to `GtmNotificationSettingsController` (implied by existing per-section-controller pattern; verify the permission set actually lists Apex class access entries for `GtmAgentSettingsController`/`GtmReadoutApprovalSettingsController` as precedent before assuming implicit access — add an explicit `classAccesses` entry for `GtmNotificationSettingsController` if the precedent classes have one). | Object perms: `allowRead`/`allowEdit` true, `viewAllRecords`/`modifyAllRecords` false (matches `GTM_Readout_Approval_Settings__c`/`GTM_Agent_Settings__c` precedent exactly — org-default row has no meaningful row-level viewAll/modifyAll semantics beyond object access). Field perms: `readable`/`editable` true on **all nine** fields in §1b. |
  | `GTM_Offering_User` | **No grant.** Reps never see this tab (unchanged posture from Units 1/2). | **No object-level grant.** The notification-firing Apex runs inside existing lifecycle methods (`submitForApproval`, `stampApproval`, `publishReadout`, `returnToDraft`, `GtmHomeSnapshotController`'s request path) under those methods' own execution context, not via a rep querying the setting client-side. **Verify at build time that no client-side read of `GTM_Notification_Settings__c` is added to any rep-facing LWC** before treating this as final — if the Developer adds one, this grant becomes mandatory and this box must be re-checked. |
  | `GTM_Content_Manager` | No grant — GTM Offerings app scope, not Content Manager app scope. | No grant, same reasoning. |
  | `GTM_Content_Admin` | No grant, same reasoning as `GTM_Content_Manager`. | No grant, unchanged. |
  | `GTM_Guest` | No grant — guest/prospect users never see an internal admin tab. | No grant. |

## 3. Plan Acceptance Criteria

- **Success Metric:** QA must confirm, in a `gtm-staging` validate-only pass
  plus browser verification (per the standing QA-browser-validation rule):
  (1) Section 3 "Notifications" renders in the existing
  `gtmOfferingsSettings` nav rail and its Apex controller pair loads/saves
  the org-default row correctly for all nine fields; (2) each of the six
  lifecycle wiring points in §1d correctly gates its Task/bell firing (and,
  where applicable, its auto-close) on the corresponding setting field —
  toggle each field off/on and exercise `submitForApproval`,
  `stampApproval` (via the approval trigger), `publishReadout`,
  `returnToDraft`, and a new `GTM_Assessment_Request__c` (Status = `New`)
  creation, confirming Task/bell events fire or don't fire exactly per the
  table; (3) specifically confirm `Auto_Close_New_Request_Tasks__c`
  closes the originating request Task at `submitForApproval` time, not at
  request-open or `generateDraftReadout` time (the resolved decision in
  §1c) — this is the one behavior most likely to regress silently since it
  reuses an existing trigger point rather than adding a dedicated one;
  (4) `Auto_Close_Published_Tasks__c` is confirmed ignored when
  `Published_Notification_Mode__c` is `None` or `Bell Only`, and honored
  only under `Bell + Task`; (5) the new `CustomNotificationType` metadata
  deploys cleanly and `scripts/deploy.sh`'s post-deploy echo block prints
  the new Notification Builder manual-step line; (6) all five permission
  sets deploy with exactly the grants in §2's table — no accidental grant
  leakage to `GTM_Offering_User`/`GTM_Content_Manager`/`GTM_Content_Admin`/
  `GTM_Guest`.
- **Target Test Target:** New Apex test class
  `GtmNotificationSettingsControllerTest` (parallel to
  `GtmReadoutApprovalSettingsControllerTest`/`GtmAgentSettingsControllerTest`)
  covering `getOrgDefaults()`/`upsert` and admin-only access; plus updated
  coverage in the existing test classes for the three lifecycle-owning
  classes touched — `GtmReadoutControllerTest` (submit/publish/return-to-draft
  paths), the approval-trigger test coverage for
  `GtmReadoutApprovalHandler` (`stampApproval`), and
  `GtmHomeSnapshotControllerTest` (new-request path) — each asserting both
  the "setting on" and "setting off" branches for its respective field(s),
  run via `sf apex run test --class-names GtmNotificationSettingsControllerTest,GtmReadoutControllerTest,GtmReadoutApprovalHandlerTest,GtmHomeSnapshotControllerTest --target-org gtm-staging` (never `RunLocalTests`, per `docs/runbooks/api-request-budget.md`). LWC side: new Jest spec for `gtmOfferingsSettingsNotifications` (`npm run test`), covering load/save of all nine fields and the "Bell + Task"-only visibility/relevance of `Auto_Close_Published_Tasks__c` in the UI.

## Definition of Done

- [ ] `GTM_Notification_Settings__c` Hierarchy Custom Setting object deployed
      with the nine fields in §1b, org-default row seedable via the new
      controller (no hand-edited XML for anything except the object/field
      definitions themselves, which are hand-authored schema, not generated
      output — this does not fall under the `build-instrument.py`-generated
      `GTM_Assessment_*` XML restriction in CLAUDE.md).
- [ ] `GtmNotificationSettingsController` (`getOrgDefaults()`/`upsert`,
      admin-gated) + `GtmNotificationSettingsControllerTest` shipped.
- [ ] `gtmOfferingsSettingsNotifications` LWC + Jest spec shipped, wired into
      `gtmOfferingsSettings`'s `SECTIONS` array as Section 3 (after Setup,
      Approval, Claude/GUS).
- [ ] All six lifecycle wiring points in §1d implemented, each reading
      through `GtmNotificationSettingsController` (no duplicated
      direct-query logic across the three lifecycle-owning classes).
- [ ] `Auto_Close_New_Request_Tasks__c` wired specifically to
      `GtmReadoutController.submitForApproval` per the resolved decision in
      §1c — not to a read-time or `generateDraftReadout`-time trigger.
- [ ] New `CustomNotificationType` metadata file deployed; the
      `scripts/deploy.sh` manual-step echo line for Notification Builder
      added per §1e.
- [ ] All five permission sets updated exactly per §2's table — `GTM_Offering_Admin`
      gets full CRUD/FLS on the new object (never org-wide Modify/View All
      Data) plus Apex class access confirmed/added for
      `GtmNotificationSettingsController`; the other four sets get no grant.
- [ ] Existing Apex test coverage for `GtmReadoutController`,
      `GtmReadoutApprovalHandler`, and `GtmHomeSnapshotController` extended
      to assert both branches (setting on/off) of every field they now
      consult; new `GtmNotificationSettingsControllerTest` passes.
- [ ] QA validate-only run against `gtm-staging` plus browser verification
      of all six lifecycle events per the Success Metric in §3, including
      explicit confirmation of the `Auto_Close_New_Request_Tasks__c` timing
      behavior.
- [ ] No client-side read of `GTM_Notification_Settings__c` added to any
      rep-facing (`GTM_Offering_User`-visible) LWC; if the Developer finds
      this necessary, that is a scope deviation requiring a return to BA/
      Architect, not a silent addition, since it would invalidate the
      "no grant needed for `GTM_Offering_User`" permission-set decision
      in §2.
