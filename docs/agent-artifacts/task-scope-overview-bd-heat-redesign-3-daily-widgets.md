# TASK SCOPE — ISSUE #overview-bd-heat-redesign-3-daily-widgets

> Sub-ticket 3 of 4 in the `overview-bd-heat-redesign` split. Full parent
> context: `docs/agent-artifacts/task-scope-overview-bd-heat-redesign.md`
> (branch `ba-scope/issue-overview-bd-heat-redesign`, see its §4 for the
> split rationale). This doc extracts only the already-decided scope for
> this slice — it does not invent new scope. Parallelizable with
> `overview-bd-heat-redesign-2-heat-grid` per the BA's recommendation
> (§4 of the parent doc: "independent of the heat grid's data model").

## 1. Requirements Breakdown

- **Target Objective:** Add two self-contained, native-Salesforce-backed
  widgets to the rebuilt `gtmOverview` Today view:
  1. **"Your tasks due today"** — the rep's own open Salesforce Tasks due
     today or overdue, scoped to Account/Opportunity records tied to GTM
     links (not every Task the rep owns org-wide).
  2. **"Readouts awaiting response"** — Accounts with a `GTM_Readout__c` in
     `Published` status whose `Notification_Sent_Date__c` is populated,
     using a coarse time-since-sent proxy. **No real "viewed" or "replied"
     signal exists on this object or its related objects
     (`GTM_Readout_Approval_Log__c`, `GTM_Readout_Version__c`) — do not
     build or fake one.** Widget copy must say something like "sent N days
     ago, no update since," never "viewed" or "replied," since the app has
     no way to know either of those facts. Real viewed/replied tracking is
     explicitly out of scope here and belongs to the separate follow-up
     ticket `gus-nudge-tool-and-readout-viewed-tracking` (parent doc §4,
     item 4) — do not attempt it as part of this sub-ticket.
- **System Component Impacted:** `force-app/main/default/lwc/gtmOverview/`
  (adds these two widgets into the Today view; exact decomposition into
  child LWCs vs. inline markup is a Developer-level implementation
  decision, not pre-scoped here) plus **two new read-only Apex controller
  methods** (naming TBD, follow the `Gtm*ControllerTest.cls` convention
  already used in this app, e.g. `GtmActTodayControllerTest.cls`,
  `GtmLinkStageServiceTest.cls`):
  - A Task query scoped to the running user (`OwnerId = :UserInfo.getUserId()`
    or the app's existing delegated-ownership convention — check
    `GtmViewerContext.cls` and the OWD-series scope docs under
    `docs/agent-artifacts/` for the established rep-ownership pattern
    before writing a fresh query shape), `ActivityDate <= TODAY`,
    `IsClosed = false`, filtered to `WhatId` in the set of
    Opportunities/Accounts that have a `GTM_Saved_Configuration__c` (not
    every Task the rep owns).
  - A `GTM_Readout__c` query for the coarse proxy:
    `Status__c = 'Published'` and `Notification_Sent_Date__c != null`,
    surfacing the Account, the sent date, and days-since-sent for display.
  - **No new SObjects or fields required for either widget.** The
    Readout widget deliberately avoids the schema gap (see above) by using
    only existing fields.
- **Dependency:** This slice depends on
  `overview-bd-heat-redesign-1-layout-toggle` (currently in development,
  branch `agent/issue-overview-bd-heat-redesign-1-layout-toggle`) for the
  Today/Offerings toggle shell these widgets render inside. Do not start
  wiring these widgets into final page markup until that shell lands or is
  available to rebase onto; the Apex and widget-internal logic can be
  built independently in the meantime.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO.** Neither widget touches
  `GtmAgentToolSurface`/`GtmAppTool`; both are plain read-only Apex called
  from the LWC, no agent-tool involvement.
- [ ] Altering Custom Metadata? **NO.** No `GTM_Assessment_*` metadata, no
  `migration-accelerator/instrument/<offering-key>/` YAML touched.
- [ ] Introducing database fields? **NO.** Both widgets are confirmed
  buildable against existing fields only (standard Task fields;
  `GTM_Readout__c.Status__c` and `Notification_Sent_Date__c`, both already
  present). The permission-set-grant obligation in `CLAUDE.md` §6.1 does
  not apply to this ticket since no new field/object is introduced. If a
  future Developer finds they need a new field to make either widget work,
  that is scope creep into the deferred
  `gus-nudge-tool-and-readout-viewed-tracking` ticket — stop and flag it
  rather than adding the field here.

## 3. Plan Acceptance Criteria

(Extracted from parent doc §3, items 4, 5, 9, 10 — renumbered here for this
slice only.)

- **Success Metric:**
  1. "Your tasks due today" widget reads the rep's own open Tasks due
     today/overdue, related to Account/Opportunity records tied to GTM
     links, using the app's existing rep-ownership convention (check
     `GtmViewerContext.cls` / OWD-series scope docs before writing a fresh
     query pattern — do not duplicate an existing Task-creation/query
     helper if one already exists; grep first).
  2. "Readouts awaiting response" widget lists Accounts where
     `GTM_Readout__c.Status__c = 'Published'` and
     `Notification_Sent_Date__c` is populated, worded as "sent N days ago,
     no update since" — never claims "viewed" or "replied" as fact.
  3. Both new Apex controller methods are read-only (no DML on the GET
     path) and each ships with an Apex test class covering the
     today-vs-overdue Task date boundary and the Published/sent-date
     filter boundary for the Readout query.
  4. No new fields, objects, or permission-set changes are introduced by
     this ticket (confirmed in §2 above) — if this constraint is violated
     during implementation, stop and escalate rather than silently adding
     a field.
  5. New/changed Jest coverage lives under
     `force-app/main/default/lwc/gtmOverview/__tests__/` (or a child
     component's own `__tests__/` if the Developer splits these into
     dedicated LWCs) for both widgets' rendering and empty/boundary states.
- **Target Test Target:** New Apex test classes for the two new controller
  methods (naming TBD, `Gtm*ControllerTest.cls` convention), plus Jest
  specs for the new widget markup/logic under `gtmOverview/__tests__/`.

## 4. Explicitly Out of Scope

- Real readout-viewed/replied tracking (new field(s), guest-write path via
  `GtmViewerContext`) — deferred to
  `gus-nudge-tool-and-readout-viewed-tracking`.
- The heat grid itself, and the "Call now"/"Follow up"/"Nudge"/"Book the
  call" button wiring — that is `overview-bd-heat-redesign-2-heat-grid`.
- The Today/Offerings toggle shell, funnel-card removal, and offering-card
  re-homing — that is `overview-bd-heat-redesign-1-layout-toggle`
  (dependency, see above, not duplicated work).
- Any live `gtm-prod` data change or seed script.
