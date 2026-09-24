# TASK SCOPE — ISSUE #rep-data-scoping-owd-3-analytics-permcheck

## 0. Context (split rollout, sub-issue 3 of 3)

This work was split from a combined finding (`rep-data-scoping-owd`) into
three sequential sub-issues, per this session's precedent (#184) for large
multi-part work. This is sub-issue **3 of 3** — generalize
`GtmAnalyticsTeamController.hasTeamAccess()` off the hardcoded
permission-set name, and add server-side guards to the three Analytics
methods. It does not depend on sub-issue 2
(`rep-data-scoping-owd-2-pages-assessments`) and the two could run in
parallel, but both should land only after sub-issue 1
(`rep-data-scoping-owd-1-owd-overview`, the OWD flip on
`GTM_Assessment_Request__c` / `GTM_Link_Event__c`) is confirmed live in
`gtm-dev`, since this sub-issue's generalized access check assumes the
`viewAllRecords=true` grants on `GTM_Offering_Admin` are the actual access
mechanism post-flip.

## 1. Requirements Breakdown

- **Target Objective:** Replace `GtmAnalyticsTeamController.hasTeamAccess()`'s
  hardcoded `PermissionSet.Name = 'GTM_Offering_Admin'` literal with a
  generalized, standard-Salesforce check for "does the running user hold a
  permission set granting `viewAllRecords=true` on the relevant object(s)"
  — so a future, differently-named permission set granting equivalent
  broader visibility is honored automatically. Also add server-side
  `hasTeamAccess()` (or its generalized successor) guards inside
  `getRepLeaderboard()`, `getInstrumentVersionComparison()`, and
  `getFlaggedRequests()` themselves, since today those three trust only
  the client-side UI toggle and a rep calling them directly via Apex/dev
  console bypasses the gate entirely and gets the org-wide rollups anyway.

### Research: correct standard Salesforce mechanism (point 4)

- Apex has no single describe-level call that answers "does this user have
  `viewAllRecords` escalation on object X" the way
  `Schema.sObjectType.X.isAccessible()` answers object-level CRUD. That
  describe call reflects the union of the user's actual object
  permissions but does not distinguish "sees own records only" from "sees
  all records" — both look identically `isAccessible() == true`.
- `UserRecordAccess` is record-scoped (`RecordId`, `HasReadAccess`, etc.)
  and requires a specific record Id per query — not usable for a blanket
  "can this user see everyone's records" check without querying it once
  per record, which defeats the purpose here.
- The correct standard mechanism: **query `ObjectPermissions`** (a real,
  queryable, standard sObject exposing exactly `SobjectType`,
  `PermissionsViewAllRecords`, `PermissionsModifyAllRecords`, and
  `ParentId` back to `PermissionSet`) joined through
  `PermissionSetAssignment` for the running user:
  ```
  SELECT Id FROM ObjectPermissions
  WHERE SobjectType = 'GTM_Assessment_Request__c'
    AND PermissionsViewAllRecords = true
    AND ParentId IN (
      SELECT PermissionSetId FROM PermissionSetAssignment
      WHERE AssigneeId = :UserInfo.getUserId()
    )
  LIMIT 1
  ```
  This is standard, declarative-first (per CLAUDE.md §5's general
  principle), not a hand-rolled reimplementation of sharing, and is
  agnostic to which permission set(s) grant the escalation — a brand-new
  permission set with `viewAllRecords=true` on the object is honored with
  zero code change, which is exactly the stakeholder's stated goal. This
  is the design to implement; no fallback/hardcoded-name path is needed —
  it fully replaces the current hardcoded check.
  - Note for the Developer: `ObjectPermissions` also reflects Profile-level
    grants if that org ever assigns `viewAllRecords` via Profile rather
    than Permission Set for these objects — confirm current profiles don't
    already do this in an unexpected way (a quick `SELECT SobjectType,
    PermissionsViewAllRecords FROM ObjectPermissions WHERE SobjectType IN
    ('GTM_Assessment_Request__c','GTM_Link_Event__c','GTM_Saved_Configuration__c','GTM_Readout__c')`
    in `gtm-dev` before writing the Apex, to confirm no surprise grants
    exist beyond `GTM_Offering_Admin`).
- **System Component Impacted:** Apex — `GtmAnalyticsTeamController.cls`.

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? **No.**
- [x] Altering Custom Metadata? **No.**
- [x] Introducing database fields? **No** — no new fields or Permission
      Set metadata; this reads the existing `ObjectPermissions` grant
      already present on `GTM_Offering_Admin`, it doesn't add one.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. `hasTeamAccess()` (or a renamed/generalized successor, e.g.
     `hasOrgWideAnalyticsAccess()`) no longer references the literal
     string `'GTM_Offering_Admin'` anywhere in
     `GtmAnalyticsTeamController.cls`; it queries `ObjectPermissions` as
     described above (recommend checking `viewAllRecords` on
     `GTM_Assessment_Request__c` as the representative object, consistent
     with what the rest of the class's org-wide queries actually touch —
     confirm with the Architect whether to check all three objects
     `GTM_Saved_Configuration__c`/`GTM_Assessment_Request__c`/
     `GTM_Readout__c` or just one is sufficient, since today's hardcoded
     check is effectively "all or nothing" per permission set anyway).
  2. `getRepLeaderboard()`, `getInstrumentVersionComparison()`, and
     `getFlaggedRequests()` each call the guard at the top of the method
     and throw `AuraHandledException` (consistent with this class's
     existing `validateRange()` pattern) for a caller without the
     escalation — a rep calling these directly (bypassing the UI toggle)
     gets a clean permission error, not org-wide data.
  3. Existing `hasTeamAccess()` UI-gating callers (the Analytics LWC
     toggle) continue to work unchanged — this is an internal
     implementation swap, not a public method signature change, unless
     the Architect decides a rename is warranted (in which case update the
     one known caller in the `gtmAnalytics` LWC accordingly).
- **Target Test Target:**
  `GtmAnalyticsTeamControllerTest.cls` (locate or create) — assert
  `hasTeamAccess()` returns `true` for a user assigned any permission set
  with `viewAllRecords=true` on the checked object (not just literally
  `GTM_Offering_Admin` — seed a second, differently-named test permission
  set with the same grant to prove the generalization actually works) and
  `false` otherwise; assert `getRepLeaderboard()` /
  `getInstrumentVersionComparison()` / `getFlaggedRequests()` throw
  `AuraHandledException` under `System.runAs()` for a plain
  `GTM_Offering_User`-only user.
