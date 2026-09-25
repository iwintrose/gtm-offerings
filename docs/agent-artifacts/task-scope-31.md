# TASK SCOPE — ISSUE #31

Title: "Retire 'Engagement Links' tab; fire real Tasks for engagement
follow-ups on Account/Contact/Opportunity Activity." Supersedes #29
(closed) and reframes D5 of issue #102-overview (Engagement Links does not
survive as a tab at all, promoted or otherwise).

All findings below were verified directly against `main` at commit
`138c310` via `Read`/`Grep`/`Bash` (`gh issue view 31`, file reads, and the
`grep`/`python3` scans quoted inline) — not taken on the coordinator's or
the issue's word alone. Three corrections to the coordinator's brief and
one to the issue text itself are called out explicitly where evidence
diverged from the summary handed to this BA pass.

## 1. Requirements Breakdown

- **Target Objective:** Delete the standalone "Engagement Links" tab
  (`GTM_Engagement_Links` / `gtmContactEngagement`) and replace its one real
  job — telling a rep which prospect needs a follow-up — with real
  Salesforce `Task` records visible on the Activity timeline of the
  Account/Contact/Opportunity the link belongs to, reusing
  `GtmContactEngagementController.classify()`'s existing six-state mapping
  and `GtmLifecycleNotificationService`'s existing fire/close Task
  mechanism. Two existing click-throughs that navigate to the tab must be
  repointed, and a small contextual task list must be added to the two
  in-app "open record" surfaces (Pages, Assessments) so a rep working one
  record isn't blind to it.
- **System Component Impacted:** Apex (`GtmLifecycleNotificationService`,
  `GtmContactEngagementController`, `GtmLinkEventController`,
  `GtmAssessmentRequestController`, `GtmReadoutController`) + LWC
  (`gtmTasksDueTodayWidget`, `gtmOverview`, `gtmReadoutWorkspace` or a new
  child, `gtmContactEngagement` deletion) + metadata teardown
  (`applications/GTM_Offerings.app-meta.xml`, one `tabs/` file, two
  `permissionsets/` tab-visibility entries) + two small FlexiPage edits
  (see §1B). No YAML/instrument, no Experience Cloud route changes beyond
  the existing guest event-logging call site already in place.

### 1A. Six-state → Task fire/close mechanism

**Verified state source.** `GtmContactEngagementController.classify()`
(`force-app/main/default/classes/GtmContactEngagementController.cls:421-438`)
returns exactly the six states named in the issue, in this precedence
order (highest first, from `STATE_RANK` at lines 74-81):
`submitted_draft` (1) → `published_unsent` (2) → `started_not_submitted`
(3) → `opened_not_started` (4) → `never_opened` (5) → `sent_complete` (6).
`STATE_ACTION` (lines 85-92) maps each to `open_readout` / `send_disabled`
/ `follow_up` / `follow_up` / `resend` / `none`. `classify()` is currently
`@TestVisible private static` — **not callable from outside this class
today.** Any new fire-trigger call site needs either (a) `classify()`
widened to `public static` (it is a pure function, no SOQL/DML, so
widening it does not cross the `with sharing`/`without sharing` boundary
the way a query would), or (b) the state-precedence table duplicated at
each trigger point. (a) is the only option consistent with the issue's own
instruction to reuse, not re-derive, the mapping — flag this as a required
implementation step, Architect sign-off needed since it makes
`GtmContactEngagementController` a dependency of three other classes it
does not know about today.

**WhatId target — correction to the coordinator's brief.** The brief
states "`Task.WhatId` → parent record (Contact/Account/Opportunity...)
the same mechanism already used for readout-approval and assessment-request
Tasks." That is not what the existing code does. Read directly:
`GtmReadoutController.cls:1708` (`GtmLifecycleNotificationService.fireTask(readoutId, approverId, ...)`),
`:2046` (`fireTask(readoutId, readout.OwnerId, ...)`), and
`GtmAssessmentRequestController.cls:1004`
(`fireTask(req.Id, req.OwnerId, ...)`) all set `WhatId` to the
**`GTM_Readout__c`/`GTM_Assessment_Request__c` record's own Id**, never to
an Account/Contact/Opportunity Id. This is deliberate and documented:
`docs/agent-artifacts/task-scope-notifications-unit-3b-lifecycle-wiring.md`
§1b explains `GTM_Assessment_Request__c.enableActivities` had to be flipped
to `true` (confirmed still `true` today,
`GTM_Assessment_Request__c.object-meta.xml:7`) specifically so `WhatId`
could point at that object, because the readout-approval workflow's
"go look at this" target *is* the readout/request record. The engagement-
link states are a genuinely different case, and the issue's own design
intent is correct even though its "same mechanism" framing overstates the
precedent: it explicitly wants these Tasks to land on the
Account/Contact/Opportunity Activity timeline instead, which is a new
`WhatId` target for this codebase's Task-tracking pattern, not a reuse of
the existing one. Account/Contact/Opportunity all being standard objects
with Activities enabled by default (no `enableActivities` metadata element
needed, unlike the custom-object case) makes this the *simpler* half of
the existing precedent, not a departure from it.

**Per-row WhatId resolution — verified against the actual DTO.**
`GtmContactEngagementController.LinkEngagementSummary` carries `contactId`
and `accountId` (both sourced from `GTM_Saved_Configuration__c.Contact__c`/
`Account__c`, lines 359-361) but **no `opportunityId`** — confirmed by
reading `toSummary()` in full and the `SELECT` list at lines 235-239, which
projects `Contact__c, Contact__r.Name, Account__c` but never
`Opportunity__c`, even though `GTM_Saved_Configuration__c.Opportunity__c`
exists as a field (confirmed,
`objects/GTM_Saved_Configuration__c/fields/Opportunity__c.field-meta.xml`).
So despite the issue's title naming "Account/Contact/Opportunity Activity"
generically, the six-state classification as it exists today can only
target Contact or Account, never Opportunity, without an additive change
to `getEngagementSummaries`'s SELECT list and DTO. Both `Contact__c` and
`Account__c` are optional lookups (neither has a `<required>` element;
confirmed by reading both `.field-meta.xml` files in full) —
`GtmSavedConfigurationController.resolveContact` (line 1254) returns
`null` outright when no client-contact email was captured, so a given row
can legitimately have `contactId = null`. **Recommendation:** WhatId =
`coalesce(contactId, accountId)` per row, Contact preferred when present
(a "follow up"/"resend" action is about a specific prospect relationship),
falling back to Account. Opportunity-level follow-up would require a
separate, explicit scope addition (extend the SELECT + DTO); flag it as
out of this ticket's boundary unless the Architect decides otherwise.

**Concrete trigger points — this is not a scheduled/batch-job design for
five of the six states.** Every field `classify()` reads is written at an
existing, already-identified Apex call site:

| State transition | Driving field | Write site (verified) | Sharing context |
|---|---|---|---|
| → `opened_not_started` | first `GTM_Link_Event__c` with `Event_Type__c = 'Page View'` | `GtmLinkEventController.logEvent`/`logEvents` (`classes/GtmLinkEventController.cls:33-49`, `:85-107`) — guest-callable, best-effort try/catch already wraps the insert | `without sharing` |
| → `started_not_submitted` | first `GTM_Link_Event__c` with `Event_Type__c = 'Form Opened'` | same controller, same call sites | `without sharing` |
| → `submitted_draft` | `GTM_Assessment_Request__c.Submitted_At__c` set | `GtmAssessmentRequestController.postInsertBestEffort` (`classes/GtmAssessmentRequestController.cls:937` sets the field inside the same `insert req;` transaction at line ~955; the method already fires `SUBJECT_NEW_REQUEST` here per "Notification wiring point 7," lines 997-1006) | `without sharing` |
| → `published_unsent` | `GTM_Readout__c.Status__c = 'Published'` | `GtmReadoutController.publishReadout` (`:2003`, existing `fireTask(readoutId, ...)` call for `SUBJECT_READOUT_PUBLISHED` sits right after at `:2046`) | `with sharing` |
| → `sent_complete` (closes the `published_unsent` Task; fires nothing new — `STATE_ACTION` for this state is `'none'`) | `GTM_Readout__c.Notification_Sent_Date__c` stamped | `GtmReadoutController` `sendPublishNotification` (`:2239`), called automatically by `publishReadout` in the same rep-initiated transaction in the normal case | `with sharing` |
| → `never_opened` ("resend" nudge) | **nothing — this is the default/fallback branch of `classify()`, not an event.** Every freshly created link starts here. | **No existing write site exists to hook.** | n/a |

Confirmed exact event-type strings the guest configurator actually sends
(`lwc/gtmConfigurator/gtmConfigurator.js:1558-1665`, calling
`this._logEvent('Page View')` / `this._logEvent('Form Opened')`, which
routes to the imperative `logEvent` Apex import at line 2155) match
`classify()`'s checks (`Event_Type__c == 'Page View'`/`'Form Opened'`)
character-for-character.

**Open design question, not resolved here — flagged for Architect/owner,
not guessed:** `never_opened`'s "Resend" action has no state-changing DML
event to hook (a link simply *starts* in this state and never leaves it
via any write). Firing a Task the instant a link is created ("resend
something you just made and haven't sent yet") would be a real UX
regression, not a helpful nudge. The two honest options, neither picked
here: (1) exclude `never_opened` from real-Task firing in this unit
entirely — a rep still sees it via whatever surface eventually replaces
the queue view, just not as an Activity-timeline Task — or (2) add a new
small Scheduled/Batch Apex job (e.g., "N days old, still zero engagement
events") that re-evaluates and fires via `fireTasksBulk`, which is a
materially different, heavier mechanism than the other five states need
and genuinely is the "batch job re-evaluating state transitions" shape the
coordinator's brief speculated about generically — but only for this one
state, not all six. This determines whether the batch job exists at all;
Developer should not build it speculatively before this is decided.

**Bulk-safety implication, per `GtmLifecycleNotificationService`'s own
docstring mandate (lines 32-45):** `GtmLinkEventController.logEvents` can
process up to `MAX_EVENTS_PER_CALL = 60` events in one call today (though
currently always scoped to one `configId`/one WhatId per call — confirmed
by the method signature taking a single `configId` string, not a list), so
`fireTask`/`closeOpenTasks` (singular) suffice at that call site as long
as the single-config scoping holds; if a future change ever batches
multiple configs into one `logEvents`-style call, that would have to move
to `fireTasksBulk`/`closeOpenTasksBulk` per the class's own stated
discipline. The one call site that *would* need the bulk variants from day
one is the hypothetical `never_opened` scheduled job above, since it would
by design span many `GTM_Saved_Configuration__c` rows in one transaction.

### 1B. The two click-through fixes

Both confirmed exactly as briefed:
`force-app/main/default/lwc/gtmTasksDueTodayWidget/gtmTasksDueTodayWidget.js:105-109`
(`handleRowActivate`) and
`force-app/main/default/lwc/gtmOverview/gtmOverview.js:366-393`
(`handleAccountClick`/`handleContactClick`) all call
`this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: 'GTM_Engagement_Links' }, ... })`.

**Recommendation: navigate to the parent record's native Activity tab**
(`type: 'standard__recordPage', attributes: { recordId, objectApiName, actionName: 'view' }`
— Account for `gtmTasksDueTodayWidget` rows, since
`GtmTasksDueTodayController.accountIdsByWhatId` only ever resolves an
`accountId`, never a `contactId`, per its own class header; Account for
`gtmOverview.handleAccountClick`; Contact for
`gtmOverview.handleContactClick`), not a bare `standard__recordPage` on
the Task itself. Reasoning, consistent with `gtmTasksDueTodayWidget`'s own
existing doc comment ("GTM has no in-app 'working view' of a bare Task,
but it does of an Account's engagement links, which is what a rep chasing
a task on that account actually wants next" — same logic, just retargeted
from the dead tab to the record's own Activity tab): a bare Task detail
page has no relationship context (no other open items on that
Account/Contact visible alongside it), while the Activity tab shows every
open Task for that record together, which is exactly the multi-Task,
"what's outstanding on this account" view a rep chasing a follow-up wants.
`WhatId`'s polymorphism (Account **or** Opportunity on
`GtmTasksDueTodayController`'s rows; Account **or** Contact on
`gtmOverview`'s two handlers) is already resolved server-side before the
click, so this is a same-shape swap of `apiName`/`type`, not new logic.

**Additional finding, not in the original brief — a genuine follow-on
fix needed for this to actually work end-to-end.** Verified via a
structured read of all three FlexiPages
(`GTM_Account_Record_Page`, `GTM_Opportunity_Record_Page`,
`GTM_Contact_Record_Page`): every one of them has its "Activity" tab
(`flexipage:tab` wrapping `runtime_sales_activities:activityPanel`) set to
`active = false`, and the "Related" tab (`Standard.Tab.relatedLists`) has
no `active` property at all — which per Salesforce FlexiPage tab-set
semantics means **Related, not Activity, is the tab that actually opens by
default** on all three record pages today. Landing a rep on
`standard__recordPage` alone, without also flipping `active` on the
Activity tab component instance to `true` in these three FlexiPage
XML files, gets the rep to the right record but not to the right tab — a
silent one-extra-click regression from what the fix intends. There is no
verified, documented `NavigationMixin` `state` parameter for
deep-linking directly into a specific FlexiPage tab (unlike, say,
`standard__objectPage`'s `filterName`) — this is knowledge-based, not
fetched from live Salesforce docs this session, flagged the same way this
repo's own `docs/architecture/gtm-row-open-and-links.md` flags its own
unverified navigation claims. **Recommendation:** include the three
`active=true` FlexiPage edits as part of this ticket's Developer scope,
alongside the two LWC click-through changes — otherwise the fix is
functionally incomplete.

### 1C. Contextual task widget for open Pages/Assessment records

**Correction to a literal reading of the issue text.** "An open Page or
Assessment record" does **not** mean the native FlexiPages
(`GTM_Saved_Configuration_Record_Page`,
`GTM_Assessment_Request_Record_Page`) — those are verified, per
`docs/architecture/gtm-row-open-and-links.md` §"Still on the record page,"
to be **overridden for View inside the GTM Offerings app** (where reps
live) via `actionOverrides` in `GTM_Offerings.app-meta.xml` pointing at
`GTM_SC_View_Redirect`/`GTM_AR_View_Redirect`, which immediately navigate
reps away to the custom `GTM_Pages`/`GTM_Assessments` tab SPA views. The
native FlexiPages are reachable only from the Content Manager app or Setup
(admin/debug use, per that doc's own explicit statement). Dropping a new
widget into those FlexiPages would put it somewhere reps essentially never
see inside the app this ticket is actually about.

**Verified actual mount points.** The real "open Page" and "open
Assessment" surfaces reps use inside the GTM Offerings app are:
- `GTM_Pages` tab → `gtmPageBrowser` → `c-gtm-rep-link-finder` → (when a
  specific link's readout exists) `c-gtm-readout-workspace`, or (when it
  doesn't yet) `c-gtm-assessment-detail`
  (`lwc/gtmRepLinkFinder/gtmRepLinkFinder.html:146-151,174`).
- `GTM_Assessments` tab → `gtmReadoutsOverview` → `c-gtm-readout-workspace`
  (`lwc/gtmReadoutsOverview/gtmReadoutsOverview.html:10-16`).

`gtmReadoutWorkspace` (`@api assessmentRequestId`, already wires
`getRecord` on `GTM_Assessment_Request__c` including `Contact__r.Name`,
`Account__r.Name`, `Saved_Configuration__c` —
`lwc/gtmReadoutWorkspace/gtmReadoutWorkspace.js:7-38,74-86`) is the one
component shared by **both** entry paths. **Recommendation:** mount the
new contextual widget inside `gtmReadoutWorkspace`, scoped by the
Contact/Account id it already resolves via its existing wire — one mount
point covers both "open Page" and "open Assessment" since both routes
converge there. This is a **scoped reuse of `gtmTasksDueTodayWidget`'s
query shape**, not the same component verbatim: that widget's Apex
(`GtmTasksDueTodayController.getTasksDueToday`) is hardcoded to "the
running user's own open Tasks... due today or overdue" — a contextual
widget needs "every open Task on *this* Contact/Account regardless of due
date," a different WHERE clause. Recommend a new, narrow
`@AuraEnabled` method (new class or a focused addition — Architect's call)
rather than bending `GtmTasksDueTodayController`'s existing contract to
serve two different scopes.

### 1D. Full teardown checklist

All four items in the issue's teardown list confirmed present exactly as
described, each verified by direct file read:

1. **`app-meta.xml` tab entry** —
   `force-app/main/default/applications/GTM_Offerings.app-meta.xml:63`:
   `<tabs>GTM_Engagement_Links</tabs>`. Delete this line only; do not
   touch the adjacent `GTM_Pages`/`GTM_Assessments`/etc. lines.
2. **`tab-meta.xml` file** —
   `force-app/main/default/tabs/GTM_Engagement_Links.tab-meta.xml` (whole
   file, `lwcComponent: gtmContactEngagement`). Delete.
3. **Two permission-set `tabSettings` entries** — both confirmed, each
   with an identical comment block referencing the tab's original ticket
   (`issue-102-1-engagement-links-landing`):
   `GTM_Offering_Admin.permissionset-meta.xml:1218-1224` and
   `GTM_Offering_User.permissionset-meta.xml:947-953`. Delete both
   `tabSettings` blocks (and their preceding comment lines, which are now
   dangling references).
4. **`gtmContactEngagement` LWC bundle** — checked whether it is *also*
   mounted anywhere else per the issue's explicit caution. Its own
   `js-meta.xml` (`lwc/gtmContactEngagement/gtmContactEngagement.js-meta.xml`)
   exposes `lightning__RecordPage`/`Contact` as a valid target *in
   principle*, and the class's own top-of-file docstring
   (`GtmContactEngagementController.cls:1-12`) explicitly describes "The
   Contact record page widget (gtmContactEngagement mounted with recordId
   = a Contact Id)" as one of its two intended callers. **Verified this is
   stale documentation, not current deployed reality**: a repo-wide
   `grep -rln "gtmContactEngagement" force-app/main/default/` returns only
   the component's own files, its test, the tab metadata, the two
   permission-set comment lines, the controller, and one comment-only
   reference in `gtmOverview.js` — **zero FlexiPage or experience-bundle
   XML anywhere in source mounts it.** So there is no committed
   Contact-record-page placement to separately tear down. Caveat, stated
   plainly rather than silently assumed away: an admin could in principle
   have dragged this component onto a Contact Lightning Record Page by
   hand in Lightning App Builder without that change ever being retrieved
   back into this repo's DX source — source absence is strong evidence,
   not proof, of runtime absence. Recommend Developer/QA do one empirical
   check against `gtm-staging` (Setup → Object Manager → Contact →
   Lightning Record Pages) before deleting the bundle, not just trust the
   grep.
5. **Naming collision to avoid touching by mistake, found during this
   pass, not in the original brief:**
   `GTM_Saved_Configuration__c.Account__c` and `.Contact__c` (the lookup
   fields, not the tab) both carry `<relationshipName>GTM_Engagement_Links</relationshipName>`
   (confirmed by reading both `.field-meta.xml` files in full — this is
   the child-relationship name used by the *related list* shown on
   Account/Contact record pages, documented separately in
   `docs/architecture/gtm-related-lists.md`). This is a same-string,
   different-metadata-type coincidence with the tab being retired here.
   **Do not rename or remove these `relationshipName` values** — they are
   out of this ticket's four teardown targets and unrelated to the tab.

### 1E. `GtmContactEngagementController`'s fate

`classify()`'s logic is explicitly being reused per the issue, so the
class is **not** deleted outright. What retires: the tab-facing query
method, `getEngagementSummaries` (with its pagination, role-hierarchy
"team" scoping, and `EngagementQueueResult`/`LinkEngagementSummary` DTO) —
once nothing calls it (confirm via a final grep for
`getEngagementSummaries` from any remaining LWC before deleting it; today
its only caller is `gtmContactEngagement.js`, which is itself being
deleted per §1D). What stays: the class file itself, narrowed to
`classify()` (widened to `public static` per §1A) plus the
`STATE_*`/`STATE_RANK`/`STATE_ACTION`/`STATE_ACTION_LABEL`/`STATE_LABEL`
constants the new fire-trigger call sites need — or, Architect's call,
extract just those constants/method into a smaller dedicated class (e.g.
`GtmEngagementStateClassifier`) and let `GtmContactEngagementController`
itself retire completely if nothing else in it survives. Either shape is
acceptable; document whichever is chosen, per the same "Developer's call,
document it" precedent `ADR-0010` itself uses for comparable forks.

### 1F. Permission-set / FLS impact (CLAUDE.md §6)

**Verified: no permission-set change is needed for `Task` itself.**
`grep -n "<object>Task</object>" force-app/main/default/permissionsets/*.permissionset-meta.xml`
returns exactly one hit, in `GTM_Guest.permissionset-meta.xml` — neither
`GTM_Offering_Admin` nor `GTM_Offering_User` carries an explicit
object-permissions block for `Task` at all today. This is not an
oversight: `GtmLifecycleNotificationService`'s own class-header docstring
(lines 24-30) already states Task DML "rides the running user's standard
Activity access" and explicitly does not widen or narrow it. This repo's
own test fixtures corroborate it empirically —
`GtmReadoutControllerTest.createRep` (`:1002-1019`) assigns every test rep
the standard **"Standard User" Profile** (not a custom, activity-restricted
profile), and Salesforce's Standard User profile grants full
Create/Read/Edit/Delete on Activities (Task) by default — this is a
well-established, standard Salesforce platform default, not something
this repo's own metadata needs to (or currently does) express. Since
`GtmLifecycleNotificationService.fireTasksBulk` is already inserting real
Tasks today from `GtmAssessmentRequestController`/`GtmReadoutController`/
`GtmReadoutApprovalHandler` without any Task-specific permission-set grant
existing, extending the same call to the three new call sites in §1A
requires **no new Task permission-set entry.** The one FLS-adjacent
check that *does* need to happen at build time, not assumed: confirm the
running user's `OwnerId` target for each new Task (the rep who owns the
`GTM_Saved_Configuration__c` link, mirroring the existing `req.OwnerId`/
`readout.OwnerId` pattern) resolves to a real, active User in every call
path, including the two guest-context (`without sharing`) call sites,
exactly as `GtmAssessmentRequestController.postInsertBestEffort`'s
existing comment already requires for its own Task ("the Task owner must
be `req.OwnerId`... never the running — possibly guest — user").

### 1G. Salesforce-first check (CLAUDE.md convention)

A pure-Flow alternative (Record-Triggered Flow on `GTM_Link_Event__c`
after insert, on `GTM_Assessment_Request__c`, and on `GTM_Readout__c` for
the two field changes) was considered and rejected, for reasons specific
to this design rather than "avoid Apex" generically:

- The "Salesforce-first" question this issue actually answers is **UI
  surface**, not DML mechanism — the whole point of the ticket is
  replacing a bespoke custom-LWC tab with the native Task object and
  native Activity Timeline (`runtime_sales_activities:activityPanel`,
  already mounted on all three record pages). That native-first bar is
  already cleared by the design regardless of what writes the Task.
- The state-precedence logic this needs (`classify()`'s six-way ranked
  state machine, with skip-ahead transitions — e.g. a link can jump
  `never_opened` → `submitted_draft` directly if a prospect fills the form
  fast) already exists, is already unit-tested
  (`GtmContactEngagementControllerTest.testAllSixStatesRankInD13Order` and
  siblings), and is already the single source of truth the LWC data layer
  depends on. Re-encoding the same ranked precedence declaratively across
  four separate Flow trigger contexts (one per object/field) risks two
  independently-maintained copies of the same state machine drifting
  apart — exactly the "undocumented dependency drift" CLAUDE.md §4 warns
  against, and a direct violation of the issue's own "reuse, don't
  re-derive" instruction, which is satisfiable in Apex (call `classify()`)
  but not naturally in Flow without duplicating the table.
- `GtmLifecycleNotificationService`'s own docstring states its reason for
  existing is that "the Task-tracking contract lives in exactly one
  place" — every other lifecycle Task in this codebase already goes
  through this one Apex service. A parallel Flow-based mechanism for only
  the engagement-link case fragments that single-source-of-truth property
  for no offsetting benefit.
- Bulk-safety is the concrete, already-documented reason the existing
  service exposes `fireTasksBulk`/`closeOpenTasksBulk` instead of
  per-record DML (its own docstring: looping single-record DML "will blow
  the 100-query/150-DML governor limits once enough records are approved
  in one operation"). The hypothetical `never_opened` batch job (§1A) in
  particular needs exactly this bulk-safe, one-aggregate-DML-per-call
  contract; a Flow-based batch equivalent would need its own separate
  bulkification story that already exists, tested, in Apex today.

**Conclusion: Apex (extending `GtmLifecycleNotificationService`) is the
right call**, consistent with — not in tension with — Salesforce-first,
because the native-first win here is Task + Activity Timeline replacing a
custom tab, not the absence of Apex.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **No.** No `GtmAgentToolSurface`/
      `GtmAppTool` implementation, proxy surface class, or Agentforce
      metadata is touched by any change described above; nothing here
      intersects GUS (Name TBD) at all.
- [ ] Altering Custom Metadata? **No.** No `__mdt` type is touched. The two
      small FlexiPage `active` flag edits in §1B are standard `FlexiPage`
      metadata (RecordPage layout), not Custom Metadata Type records —
      CLAUDE.md's "Do Not Hand-Edit Metadata" rule is specifically about
      the generated `GTM_Assessment_*` Custom Metadata XML from
      `scripts/build-instrument.py`, which is unrelated to this ticket.
- [ ] Introducing database fields? **No new fields.** This design reuses
      `Task.WhatId` (polymorphic, already supported by Account/Contact/
      Opportunity out of the box) plus new `SUBJECT_*` exact-match string
      constants on `GtmLifecycleNotificationService`, exactly the existing
      pattern — no schema change, no CLAUDE.md §6 field-to-permission-set
      mapping obligation is triggered. (Contrast with the *prior*,
      already-shipped Unit 3b work, which did need one real
      `enableActivities` object-level flip on `GTM_Assessment_Request__c`
      — that is already done, confirmed still `true` today, and is not
      part of this ticket's work.)

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. `GTM_Engagement_Links` tab is gone from the GTM Offerings app nav,
     its `tab-meta.xml` file deleted, and neither `GTM_Offering_Admin` nor
     `GTM_Offering_User` grants it visibility.
  2. `gtmContactEngagement` LWC bundle and its Jest tests are deleted (once
     the Contact-record-page staging check in §1D item 4 clears);
     `GtmContactEngagementController`'s tab-facing `getEngagementSummaries`
     path is removed while its `classify()`/state-constant logic survives
     and is called from the new fire-trigger sites, per whichever shape
     (in-place vs. extracted class) the Developer documents.
  3. A rep who has a link sitting in `follow_up`/`resend`/`open_readout`
     state (per `classify()`, for the five states with a resolved trigger
     point — `never_opened` excluded pending the open question in §1A)
     sees a real, open `Task` on the Activity tab of that link's Contact
     (or Account, when Contact is null) after the corresponding
     transition (page view/form open/submit/publish/send) fires — verified
     directly in the Activity Timeline UI on `gtm-staging`, not just via
     a SOQL assertion.
  4. That Task auto-closes (via `closeOpenTasks`/`closeOpenTasksBulk`) the
     moment the link progresses past that state, exactly matching the
     existing exact-match `WhatId + Subject` close contract — no dangling
     Tasks left open after a state advances, no Task closed early by a
     different state's transition.
  5. `gtmTasksDueTodayWidget`'s row click and `gtmOverview`'s
     `handleAccountClick`/`handleContactClick` land the rep on the
     resolved Account/Contact record with the Activity tab already
     selected (not just the record's default Related tab) — verified in
     browser, since the FlexiPage `active` flag fix in §1B is what makes
     this true, not just the LWC change alone.
  6. The new contextual widget appears inside `gtmReadoutWorkspace` (or
     wherever the Developer's Architect-reviewed design lands it) when a
     rep opens a specific link/assessment from either the `GTM_Pages` or
     `GTM_Assessments` tab, showing exactly that record's open Tasks — not
     the running user's global "due today" list.
  7. No new permission-set entry is required for `Task` object access
     (§1F); if staging testing surfaces a contradiction to that finding,
     that is itself a blocker to resolve, not silently patch around.
- **Target Test Target:**
  - Apex: `GtmLifecycleNotificationServiceTest` (extend with new
    engagement-state fire/close cases, following its existing
    `fireTaskCreatesAnOpenTaskAgainstWhatId`/`closeOpenTasksClosesOnlyExactWhatIdAndSubjectMatches`
    pattern), `GtmContactEngagementControllerTest` (if `classify()` moves
    or its access modifier changes, its existing 18 tests — e.g.
    `testAllSixStatesRankInD13Order`,
    `testStateLabelIsNeverBlankForAnyClassifiedRow` — must still pass
    unmodified in behavior), `GtmLinkEventControllerTest`,
    `GtmAssessmentRequestControllerTest`, `GtmReadoutControllerTest` (new
    assertions at the trigger points identified in §1A).
  - Jest: `gtmTasksDueTodayWidget.test.js` and `gtmOverview.test.js`
    (both currently assert `apiName: 'GTM_Engagement_Links'` at the exact
    lines cited in §1B — these assertions must change to the new
    `standard__recordPage` navigation shape, not just the production
    code), plus a new/updated spec for wherever the contextual widget is
    mounted (`gtmReadoutWorkspace.test.js` or a new child component's own
    spec).
  - `sf project deploy validate --target-org gtm-staging` (checkOnly) for
    the FlexiPage `active` flag edits and the tab/permission-set/app-meta
    teardown, since those are metadata-only changes Jest cannot cover.
