# ADR-0010 — The GTM Offerings Settings surface is one tab with internal sections, not many tabs

**Status:** Accepted — planning-stage, no code shipped by this ADR. Implements
the container decision the user confirmed for the
`ba-scope/issue-app-settings-and-notifications` (v1) and
`ba-scope/issue-app-settings-and-notifications-v2` BA scopes. Relates to
CLAUDE.md §6 (permission-set Definition of Done) and to the in-flight
`GTM_Readout_Approval_Settings` tab/`gtmReadoutApprovalSettings` LWC shipped
in PR #141. Supersedes nothing; no prior ADR addressed this surface.

## Context

Two initiatives were scoped together because they end up on the same
surface:

- **Initiative A** — a general admin-settings surface inside the GTM
  Offerings app, replacing the single-purpose `GTM_Readout_Approval_Settings`
  tab with something that can host more than one config concern over time.
- **Initiative B** (refined in v2) — the Settings tab becomes the *rules*
  that a new Task/Custom-Notification feed reads at each of six existing
  readout/assessment lifecycle trigger points, rather than hardcoded
  per-event behavior.

The BA v1 pass flagged the container pattern as a real fork: this repo's
own precedent for "several admin concerns inside one app" is
`GTM_Content_Manager`'s pattern of **separate top-level Custom Tabs**
(`GTM_Content_Manager`, `GTM_Instrument_Author`, `GTM_Pages`; the former `GTM_Content_Home` tab was retired for the Home page, see `app-home-pages.md`), not one LWC
with internal navigation. Against that precedent, the user's own wording —
"this tab should have other configurable things within it" — reads as a
single tab with internal sections, and the user has since explicitly
confirmed **Option A: one tab, internal sections/nav rail, per user.**
This ADR records that decision and its consequences; it does not
relitigate it.

The user also confirmed the in-flight `GTM_Readout_Approval_Settings` tab
(shipped, merged in PR #141, not the mid-flight branch the original BA v1
pass was written against) folds into the new tab as **Section 1**, retiring
the standalone tab rather than leaving it to live indefinitely alongside
the new one.

## Decision

### Container: one Custom Tab, one shell LWC, internal sections

- One new Lightning Web Component tab, e.g. `GTM_Offerings_Settings`
  (`GTM_Offerings_Settings.tab-meta.xml`, `lwcComponent: gtmOfferingsSettings`),
  replaces `GTM_Readout_Approval_Settings` in the GTM Offerings app's tab set.
- `gtmOfferingsSettings` is a thin shell: a left-hand nav rail (`lightning-
  vertical-navigation` or an equivalent hand-rolled list — Developer's
  call) listing sections, with the selected section's child LWC rendered in
  the main panel. The shell owns no settings logic of its own; each section
  is its own child component with its own `@wire`/Apex controller pair,
  matching the existing `gtmReadoutApprovalSettings` pattern of "one LWC,
  one admin-gated Apex controller class per settings surface" — the shell
  does not introduce a shared save/load abstraction across sections, since
  the three sections have unrelated backing objects (a migrated Hierarchy
  Custom Setting, another Hierarchy Custom Setting, and — deferred, see
  below — Custom Metadata) and forcing one generic contract across them
  would be exactly the kind of invented abstraction CLAUDE.md §4 warns
  against ("Plan Before Action... prefer minimal, reversible
  modifications").
- Sections for the first version of this tab:
  1. **Approval** (migrated from `GTM_Readout_Approval_Settings`)
  2. **Claude / GUS** (Initiative A's `GTM_Agent_Settings__c` fields)
  3. **Notifications** (Initiative B's new `GTM_Notification_Settings__c`)
- Tab visibility: `GTM_Offering_Admin` only, `Visible`. `GTM_Offering_User`
  (reps) gets no tab visibility grant at all — same posture the existing
  `GTM_Readout_Approval_Settings` tab already has today (confirmed: only
  `GTM_Offering_Admin`'s permission set carries a `tabSettings` entry for
  it), and consistent with the user's stated "this tab will be hidden to
  reps."

### Migration of the approval section

- **Retire, do not leave dual-running:** `GTM_Readout_Approval_Settings.tab-
  meta.xml` is deleted (not deprecated-in-place) once Section 1 ships, and
  its `tabSettings` entry is removed from `GTM_Offering_Admin`. A dangling
  duplicate entry point to the same Custom Setting is a support/confusion
  liability with no offsetting benefit — the tab is metadata-only
  (no records reference the tab itself), so deleting it is a clean,
  reversible operation (`git revert` restores it if ever needed).
- **`gtmReadoutApprovalSettings` LWC becomes a child component, embedded,
  not iframed or `c-` referenced as a standalone page anymore.** Concretely:
  rename/move its template content into a new `gtmOfferingsSettingsApproval`
  section component (or keep the existing component name and simply stop
  giving it its own tab — either is acceptable; Developer's call, document
  whichever is chosen) that the shell renders when "Approval" is selected
  in the nav rail. Its Apex controller,
  `GtmReadoutApprovalSettingsController`, is untouched — it has no
  dependency on being hosted by a specific tab, only on the running user's
  Apex-class access (already `GTM_Offering_Admin`-only), so **zero Apex
  changes are required for the migration**, only an LWC/tab-metadata move.
- **`GTM_Readout_Approval_Settings__c` (the Hierarchy Custom Setting object
  itself) is untouched.** Nothing about the container decision changes the
  data model of the setting that shipped in PR #141.
- Sequencing note: this migration is Unit 1 of implementation (see
  "Sequencing" below) precisely because it is the lowest-risk, already-
  proven piece — no new Apex, no new schema, pure LWC/tab-metadata
  reorganization plus one permission-set edit.

### Section 2 candidates from BA v1: resolved now, not deferred to Developer guesswork

**Claude API key / model (`GTM_Agent_Settings__c.Claude_API_Key__c`,
`Claude_Model__c`) — IN SCOPE for the first version of this tab.** This is a
straightforward Custom Setting wrap: a new admin-gated Apex controller
(`GtmAgentSettingsController`, parallel in shape to
`GtmReadoutApprovalSettingsController`) exposing `getOrgDefaults()`/`upsert`
against the org-default row, and a `gtmOfferingsSettingsAgent` (name
Developer's call) section LWC with a masked/password-style input for the
API key and a text or picklist input for the model override. No new
fields are needed on `GTM_Agent_Settings__c` — both fields already exist.

**`GTM_Offering__mdt` target-value editing — OUT OF SCOPE for the first
version of this tab. Deferred, not silently dropped.** This is a real
design fork and is resolved here rather than left open:

- Custom Metadata Type records are metadata, not data. There is no direct
  DML path (`insert`/`update` do not work on `__mdt` sObjects at runtime).
  The only programmatic write path is the async Metadata API —
  `Metadata.Operations.enqueueDeployment()` with a `Metadata.
  DeployContainer` — which (a) requires a deployment to complete
  asynchronously via a callback (`Metadata.DeployCallback`), typically
  taking seconds to minutes, not an immediate save; (b) is blocked or
  behaves inconsistently in some org types/API versions when invoked from
  a context that itself originated from a user-facing transaction; and
  (c) has no simple "is this safe to retry" story if a deployment fails
  partway — very different failure modes from a Custom Setting `upsert`,
  which is transactional and immediate.
- CLAUDE.md's own "always production, no staging" gotcha (§1) makes this
  materially riskier here than in an org with a staging environment to
  rehearse the async-deploy failure modes against.
- Given `gtm-prod` is a live-prospect-data production org with no staging
  environment, shipping an async, deploy-based write path inside a
  brand-new settings surface's first version is disproportionate risk for
  a "seeded numbers are placeholders" convenience fix. **Decision: defer.**
  `GTM_Offering__mdt` target-value editing does not appear as a section in
  this tab's first version. If it is picked up later, it should be scoped
  as its own ticket/ADR addendum, and the two realistic options to weigh
  at that time are (a) the `Metadata.Operations` async-deploy path
  described above, gated to `GTM_Offering_Admin` with a clear "this may
  take a minute and will not apply immediately" UI affordance, or (b)
  migrating just the specific editable numeric fields (`Monthly_Target__c`,
  `Annual_Target__c`) off `GTM_Offering__mdt` onto a new per-offering
  `__c` object or a keyed Custom Setting, leaving `GTM_Offering__mdt`
  itself (and everything `scripts/build-instrument.py` reads from it —
  confirmed that script only reads `Offering_Key__c` for validation and
  `.field-meta.xml` schema-level `length` for Text/LongTextArea capacity
  checks, never target-value record data, so option (b) would not
  intersect the build script at all) as the offering-identity source of
  truth it already is. Not deciding between (a)/(b) now — that choice is
  deferred along with the feature itself.

## Initiative B: Notifications is Section 3

Per BA v2's reframing, Initiative B's six lifecycle events become
admin-configurable rules read by the existing trigger points, backed by a
new Hierarchy Custom Setting, `GTM_Notification_Settings__c` — mechanically
identical in every respect to `GTM_Readout_Approval_Settings__c` (org-default
row only, `getOrgDefaults()`/`upsert`, admin-only controller class,
`GtmNotificationSettingsController` parallel to
`GtmReadoutApprovalSettingsController`). This ships as Section 3 of the same
tab, with its own `gtmOfferingsSettingsNotifications` child component.

### `GTM_Notification_Settings__c` field list (per BA v2 §2, confirmed as final for Section 3)

| Field | Type | Governs |
|---|---|---|
| `Notify_On_Submit_For_Approval__c` | Checkbox | Task + bell notification fires when a readout is submitted for approval (`GtmReadoutController.submitForApproval`) |
| `Auto_Close_Submit_Tasks__c` | Checkbox | Whether the approver's Task auto-closes when `GtmReadoutApprovalHandler.stampApproval` runs for the same record |
| `Notify_On_Approved__c` | Checkbox | Task + bell fires for the submitting rep when a readout clears approval (`GtmReadoutApprovalHandler.stampApproval`) |
| `Auto_Close_Approved_Tasks__c` | Checkbox | Whether that Task auto-closes when the rep calls `publishReadout` |
| `Published_Notification_Mode__c` | Picklist (`None` / `Bell Only` / `Bell + Task`) | What fires, if anything, on `GtmReadoutController.publishReadout` |
| `Auto_Close_Published_Tasks__c` | Checkbox | Only meaningful when `Published_Notification_Mode__c = 'Bell + Task'`; ignored otherwise |
| `Notify_On_New_Assessment_Request__c` | Checkbox | Whether a new `GTM_Assessment_Request__c` (Status = `New`) becomes a Task + bell event instead of only a passive `GtmHomeSnapshotController` dashboard count |
| `Auto_Close_New_Request_Tasks__c` | Checkbox | On/off only — **the trigger moment itself is not decided by this ADR; see "Open product question" below.** |
| `Notify_On_Returned_To_Draft__c` | Checkbox | Task + bell fires for the rep when a manager calls `returnToDraft` |

Deliberately **no field** for the Recalled-by-submitter event — per BA v2's
analysis, confirmed here: recall's only job is closing out whatever Task
`Notify_On_Submit_For_Approval__c` created, so it inherits that field's
effective state rather than needing an independent one. Deliberately **no
field** for Returned-to-Draft's auto-close behavior — per BA v2, that
Task's auto-close-on-resubmission is a hardcoded lifecycle coupling, not a
configurable axis; no admin toggle plausibly wants a dangling "revise this"
Task to survive its own resubmission.

### Open product question — flagged for the user, not decided here

BA v2 correctly identifies that **New Assessment Request's auto-close
trigger moment is a genuine, unresolved product/workflow decision**, not an
architecture question this ADR can settle: should the Task auto-close when
the rep opens the request record, when they call `generateDraftReadout`, or
only once they actually submit the resulting readout for approval? Each
answer implies different Apex wiring (a read-time trigger vs. a
`generateDraftReadout`-time trigger vs. reusing the existing
`submitForApproval` trigger point) but none is technically harder than
another — this is entirely about what "actioned" means to a rep's daily
workflow, and picking wrong produces a real UX regression (either Tasks
that never close, training reps to ignore the feed, or Tasks that close
before the rep actually did anything). **This ADR does not pick one.** The
field `Auto_Close_New_Request_Tasks__c` ships as a plain boolean; the
Apex wiring for *which* method flips it is blocked on this decision and is
called out explicitly as a question for the user before Unit 3 (see
Sequencing) is built.

## `CustomNotificationType` deployability — verified

Confirmed against current Salesforce metadata capabilities (not assumed):
`CustomNotificationType` is a standard, long-supported metadata type,
deployable in DX source format as
`force-app/main/default/customNotificationTypes/<Name>.customNotificationType-meta.xml`
(this repo currently has zero such files/directory, confirmed by the BA
pass). A metadata deploy of a new `CustomNotificationType` record ships
cleanly with **no required manual Setup step for the type's existence** —
once deployed, Apex can call `Messaging.sendCustomNotification` against it
immediately.

What is **not** covered by the metadata deploy, and must be called out
explicitly rather than assumed away:

- Whether users see notifications **at all** depends on the org-wide
  "Enable in-app and mobile notifications" setting under Setup ›
  Notification Builder. If this repo's `gtm-prod` org has never enabled
  the notification builder before (no prior `CustomNotificationType` exists
  today, so this is plausible), that org-wide toggle is a one-time manual
  Setup click that a component/class deploy cannot flip on its own —
  it can be captured as source via the `NotificationsSettings` metadata
  type, but only if that settings file is added deliberately; it will not
  appear by merely adding the notification type.
- **Per-user delivery-channel preference** (desktop banner vs. mobile push
  vs. off) is inherently a personal Setup preference each user controls in
  their own notification settings — this cannot be pre-set by a metadata
  deploy or by admin action on behalf of users, and is standard, expected
  Salesforce behavior, not a defect of this design.
- **Decision:** add one explicit manual-step line to `scripts/deploy.sh`'s
  post-deploy echo block (per the BA's own flagged precedent for other
  manual steps) reading approximately: *"If this is the first
  CustomNotificationType in this org, confirm Setup › Notification
  Builder › in-app/mobile notifications is enabled — a metadata deploy
  does not turn this on by itself."* This is Unit 3 implementation detail,
  recorded here so Developer doesn't have to re-derive it.

## Permission-set plan (CLAUDE.md §6, all five sets)

| Set | New tab (`GTM_Offerings_Settings`) | `GTM_Notification_Settings__c` | Migrated approval section |
|---|---|---|---|
| `GTM_Offering_Admin` | `tabSettings: Visible`. Apex class access to `GtmOfferingsSettingsController`-family classes (or per-section controllers) already implied by existing pattern. | Object perms: `allowRead`/`allowEdit` true, `viewAllRecords`/`modifyAllRecords` false (matches `GTM_Readout_Approval_Settings__c` precedent exactly — a Hierarchy Custom Setting's org-default row has no meaningful row-level `viewAll`/`modifyAll` semantics beyond object-level access). Field perms: `readable`/`editable` true on every field in the table above. | Carry forward existing `allowRead`/`allowEdit` on `GTM_Readout_Approval_Settings__c` and `Self_Approval_Enabled__c` unchanged. Remove the old `tabSettings` entry for `GTM_Readout_Approval_Settings`; add the new tab's entry instead (net: one tab entry swapped, not added). |
| `GTM_Offering_User` | **No grant.** No `tabSettings` entry — reps do not see this tab, matching today's approval-tab posture and the user's explicit "hidden to reps" statement. | **No object-level grant.** Per BA v2's own resolution: the notification-firing Apex runs inside existing lifecycle methods under those methods' own execution context (not called by a rep querying the setting client-side), so reps never need direct FLS on `GTM_Notification_Settings__c`. Confirm at Unit 3 build time that no client-side read of this setting is added to any rep-facing LWC before treating this as final. | No change — reps never had access to the approval settings object either. |
| `GTM_Content_Manager` | No grant — this tab is GTM Offerings app scope, not Content Manager app scope; none of the three sections (approval routing, Claude key, notifications) are content-authoring concerns. | No grant, same reasoning. | No grant, same reasoning (unchanged from today). |
| `GTM_Content_Admin` | No grant, same reasoning as `GTM_Content_Manager` above. | No grant. | No grant, unchanged. |
| `GTM_Guest` | No grant — guest/prospect users never see an internal admin tab. | No grant. | No grant, unchanged. |

The Claude API key/model section (Section 2) needs no *new* field-level
grant beyond what CLAUDE.md §5 already documents `GTM_Agent_Settings__c`
holding on `GTM_Offering_Admin` — verify that existing grant at Unit 2 build
time rather than assuming; if it is missing today, adding it is part of
Unit 2's Definition of Done per CLAUDE.md §6, not a follow-up.

## Sequencing — three units, not one PR

Given the size (new tab shell + nav-rail LWC + three sections, one a
migration, one touching a genuine Custom-Metadata-vs-Custom-Setting design
fork already resolved above, one a new object with six lifecycle wiring
points and a notification-type deploy), this ships as three sequential
units, each its own worktree/branch/PR, not one combined change:

- **Unit 1 (provisioned now):** Tab shell (`gtmOfferingsSettings` +
  `GTM_Offerings_Settings.tab-meta.xml`) + migrate the approval section in
  as Section 1, retiring `GTM_Readout_Approval_Settings`. Lowest risk: no
  new Apex, no new schema, one permission-set tab-entry swap. This is the
  only unit with a worktree provisioned by this ADR pass.
- **Unit 2 (sequenced next, not provisioned yet):** Claude/GUS Section 2 —
  new `GtmAgentSettingsController`, new `gtmOfferingsSettingsAgent` child
  component, verify/add the `GTM_Agent_Settings__c` permission-set grants.
- **Unit 3 (sequenced last, not provisioned yet, blocked on the user's
  answer to the New-Assessment-Request trigger-moment question above):**
  `GTM_Notification_Settings__c` object + `GtmNotificationSettingsController`
  + `gtmOfferingsSettingsNotifications` Section 3 + the six lifecycle
  wiring points in `GtmReadoutController`/`GtmReadoutApprovalHandler`/
  `GtmHomeSnapshotController` + the new `CustomNotificationType` +
  `scripts/deploy.sh` manual-step echo line + full permission-set grants
  for the new object.

## Consequences

- Reps never see any settings tab at any point in this rollout — no
  intermediate state exposes partial config to `GTM_Offering_User`.
- The approval-settings migration is a pure metadata/LWC move with zero
  Apex risk, so it can ship and be verified in isolation before Unit 2/3
  add any new schema or lifecycle-wiring risk.
- `GTM_Offering__mdt` target-value editing remains a Setup-only operation
  for the foreseeable future; this is a known, explicitly deferred gap,
  not an oversight — a future ADR addendum should reference this one
  rather than re-litigate the Custom-Metadata-vs-Custom-Setting tradeoff
  from scratch.
- Unit 3 cannot start until a human (not this Architect pass) answers the
  New-Assessment-Request auto-close trigger-moment question; Developer
  should not be handed Unit 3 scope until that answer exists.

## Addendum (guided setup)

The Setup checklist is section 0 of this tab: the first, default-selected entry in `SECTIONS`, deriving every row from live org state and storing nothing (`docs/architecture/guided-setup.md`). Post-install steps live there, not in runbooks; the optional AI key stays its own neutral section.

## Addendum (Unit 3 implementation contract, verified against `main` at provisioning time)

Written by the Architect pass provisioning `agent/issue-notifications-unit-3`,
per CLAUDE.md §4 Contract First. Extends this ADR rather than forking a new
one — Unit 3's decisions are already fully specified above; this addendum
only pins down facts that have drifted or were left implicit since the ADR
was written, so the Developer does not have to re-derive them mid-build.

### `SECTIONS` array has drifted from what this ADR/the BA scope doc assumed

Two other units shipped on top of this tab since this ADR was written and
are **not** described above: "Analytics Notifications" (issue #147, weekly
digest on/off, its own `GTM_Analytics_Settings__c` object — unrelated to
`GTM_Notification_Settings__c`, do not conflate) and "Scheduled Jobs"
(issue #184, purge-batch activation). `force-app/main/default/lwc/
gtmOfferingsSettings/gtmOfferingsSettings.js` currently holds, in order:

```js
const SECTIONS = [
    { id: 'setup', label: 'Setup' },
    { id: 'approval-routing', label: 'Approval Routing' },
    { id: 'analytics-notifications', label: 'Analytics Notifications' },
    { id: 'claude-gus', label: 'Claude / GUS' },
    { id: 'scheduled-jobs', label: 'Scheduled Jobs' }
];
```

Unit 3 appends a sixth entry, `{ id: 'notifications', label: 'Notifications'
}`, at the **end** of the array (position 6, after `scheduled-jobs` — not
position 4/"Section 3" as the original sequencing language implied, since
two unplanned sections landed in between). Follow the established per-section
wiring pattern exactly: an `isNotificationsSelected` getter
(`this.selectedSectionId === 'notifications'`), a `<template
if:true={isNotificationsSelected}>` block in `gtmOfferingsSettings.html`
mounting `<c-gtm-offerings-settings-notifications>`, and a doc-comment line
added to the file's existing top-of-file section summary (same place
"Scheduled Jobs" documents itself). Do not reorder or rename any existing
entry.

### `submitForApproval` must check two independent flags, unambiguously

`GtmReadoutController.submitForApproval` reads through
`GtmNotificationSettingsController.getOrgDefaults()` and branches on **two
unrelated fields, each governing a different Task**:

1. `Notify_On_Submit_For_Approval__c` — gates firing the *new* Task+bell
   event to the approver for this submission.
2. `Auto_Close_New_Request_Tasks__c` — gates closing the *original*
   new-request Task (if one exists, created back when the source
   `GTM_Assessment_Request__c` was logged) that this readout traces back to.

These are not an if/else of the same toggle — both checks run every time
`submitForApproval` executes, independently, against two different Task
records. Implement as two sequential, independently-gated blocks, not a
single combined conditional.

### `CustomNotificationType` file to create

`force-app/main/default/customNotificationTypes/GTM_Notification.customNotificationType-meta.xml`
(name Developer's call within reason — `GTM_Notification` is the suggested
default), standard shape:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomNotificationType xmlns="http://soap.sforce.com/2006/04/metadata">
    <masterLabel>GTM Offerings</masterLabel>
    <description>Task/bell lifecycle events gated by GTM_Notification_Settings__c (readout approval, publish, return-to-draft, new assessment request).</description>
    <customNotifTypeName>GTM_Notification</customNotifTypeName>
    <desktop>true</desktop>
    <mobile>true</mobile>
</CustomNotificationType>
```

### `scripts/deploy.sh` manual-step line

Add to the existing "Done. Manual steps this script can't do for you" echo
block (after the existing GUS API key line), verbatim per §1e of the scope
doc:

```
echo "    - If this is the first CustomNotificationType in this org, confirm"
echo "      Setup > Notification Builder > in-app/mobile notifications is"
echo "      enabled -- a metadata deploy does not turn this on by itself."
```

### Permission-set precedent confirmed

`GTM_Offering_Admin.permissionset-meta.xml` already carries explicit
`classAccesses` entries for both `GtmAgentSettingsController` and
`GtmReadoutApprovalSettingsController` (not implicit access) — add the same
explicit entry for `GtmNotificationSettingsController`. The
`GTM_Readout_Approval_Settings__c` object-permissions block
(`allowRead`/`allowEdit` true, `viewAllRecords`/`modifyAllRecords` false) is
the confirmed precedent shape for `GTM_Notification_Settings__c`'s object
permissions on the same permission set.
