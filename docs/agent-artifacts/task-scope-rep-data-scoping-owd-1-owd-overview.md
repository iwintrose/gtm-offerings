# TASK SCOPE — ISSUE #rep-data-scoping-owd-1-owd-overview

## 0. Context (split rollout, sub-issue 1 of 3)

This work was split from a combined finding (`rep-data-scoping-owd`) into
three sequential sub-issues, per this session's precedent (#184) for large
multi-part work. This is sub-issue **1 of 3** — the OWD flip itself
(highest risk, single atomic step) + Overview widget hardening. It must
ship and be verified live in `gtm-dev` before sub-issues 2
(`rep-data-scoping-owd-2-pages-assessments`) and 3
(`rep-data-scoping-owd-3-analytics-permcheck`) start, since those two
sub-issues' defense-in-depth filters are only a backstop for the
structural change this sub-issue makes — but this sub-issue's rollout is
the one genuinely dangerous step here and should not be entangled with
unrelated Apex review cycles. Sub-issues 2 and 3 do not depend on each
other and could run in parallel, but both should land after this one is
confirmed live, since their "admin bypass" logic assumes the
`viewAllRecords=true` grants on `GTM_Offering_Admin` are the actual access
mechanism post-flip.

## 1. Requirements Breakdown

- **Target Objective:** Close the highest-severity finding from this
  session's security audit: `GTM_Assessment_Request__c` and
  `GTM_Link_Event__c` are org-wide ReadWrite, so any authenticated rep
  (`GTM_Offering_User`) can read and edit every other rep's assessment
  requests and prospect activity logs — across the Overview KPI tiles, the
  Overview "New assessment requests" panel, the Assessments tab
  contact-requests drill-in, and the standard Salesforce
  `GTM_Assessment_Request__c` tab. Fix this at the platform level (OWD),
  matching the already-correct `GTM_Saved_Configuration__c`/
  `GTM_Readout__c` Private pattern, then make every `GtmHomeSnapshotController`
  widget provably rep-scoped (not merely "should be by sharing now").
- **System Component Impacted:** Custom Object metadata
  (`GTM_Assessment_Request__c.object-meta.xml`,
  `GTM_Link_Event__c.object-meta.xml`) + Apex
  (`GtmHomeSnapshotController.cls`).

### Confirmed current state (read, not assumed)

- `force-app/main/default/objects/GTM_Assessment_Request__c/GTM_Assessment_Request__c.object-meta.xml`
  — `<sharingModel>ReadWrite</sharingModel>`.
- `force-app/main/default/objects/GTM_Link_Event__c/GTM_Link_Event__c.object-meta.xml`
  — `<sharingModel>ReadWrite</sharingModel>` (object label is "GTM Activity
  Log" in metadata; API name is still `GTM_Link_Event__c`).
- Neither object has a custom "owner"/"rep" lookup field — no
  `Rep__c`/`Owning_Rep__c` etc. exists in either object's `fields/`
  directory. **The ownership field to filter/scope on is the standard
  `OwnerId`** field every custom object gets by default. Confirmed by
  reading `GtmHomeSnapshotController`, `GtmReadoutController` (Generator
  inner class explicitly sets `OwnerId` on `GTM_Readout__c` and reads
  `req.OwnerId` off `GTM_Assessment_Request__c`), and
  `GtmAnalyticsTeamController` (`getFlaggedRequests`/`getRepLeaderboard`
  both group by `req.OwnerId` / `cfg.OwnerId` already) — `OwnerId` is
  already the load-bearing ownership field for both objects in existing
  code, this is not a new convention.
- `GTM_Offering_Admin.permissionset-meta.xml` already grants
  `viewAllRecords=true` on both `GTM_Assessment_Request__c` (line ~203)
  and `GTM_Link_Event__c` (line ~233). **No new permission-set work is
  needed for the admin-sees-everything half** — this grant only takes
  effect once `with sharing` Apex actually respects OWD, which requires
  the flip.
- `GtmHomeSnapshotController.getSnapshot()` — confirmed by full read:
  - `activeEngagementCount` — queries `GTM_Saved_Configuration__c` only,
    already correctly scoped (Private OWD object).
  - `newAssessmentCount` — `SELECT COUNT() FROM GTM_Assessment_Request__c
    WHERE Status__c = 'New'`, **no owner filter, no `with`/`without
    sharing` override needed since the class is `with sharing`** — today
    this is org-wide because the object is ReadWrite; after the flip it
    becomes implicitly rep-scoped by sharing alone.
  - `recentViews` and `countStalled()` — both query
    `GTM_Link_Event__c` with no owner filter; `countStalled()` uses two
    dynamic `Database.query` aggregate calls (comment explains why:
    `Saved_Configuration__c` lookup field must stay dynamic so it can be
    repointed). Same "implicitly scoped only after the flip" situation.
  - `getRecentNewAssessmentRequests()` — the flagged PII leak: selects
    `Requester_Name__c`, `Company__c`, `Current_Platform__c` off the 5
    newest `GTM_Assessment_Request__c` rows org-wide, no owner filter.
    This is the "New assessment requests" Overview panel.
  - `getDeals()` is already correctly scoped via
    `GTM_Saved_Configuration__c`'s Private OWD (comment on the method says
    so explicitly) and is **out of scope** — it already relies on the
    same "flip OWD, don't hand-roll a filter" pattern being extended here.
- The class's own top-of-file doc comment currently claims "no per-record
  data, so it's safe to show org-wide regardless of who's looking" — this
  is the incorrect claim the audit found; it must be corrected as part of
  this change, not just the code under it.

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? **No** — `GtmHomeSnapshotController` is
      not a `GtmAgentToolSurface` implementation; zero-DML rule N/A.
- [x] Altering Custom Metadata? **No** — this changes `sharingModel` on two
      **Custom Object** `.object-meta.xml` files (standard SFDX metadata),
      not Custom Metadata Type (`__mdt`) records under
      `migration-accelerator/` YAML. CLAUDE.md's "Do Not Hand-Edit
      Metadata" YAML rule does not apply here; this is a direct,
      deliberate hand-edit of the object's `sharingModel` element, which is
      the correct and only way to make this change.
- [x] Introducing database fields? **No** — no new fields. `OwnerId` is a
      pre-existing standard field on both objects; permission-set mapping
      for it is not "introducing a field" since profiles/permission sets
      do not need explicit `fieldPermissions` grants for `OwnerId` (it is
      a standard field, always visible to anyone with object read access,
      same class of exception CLAUDE.md §6 describes for required/
      MasterDetail fields). No new Permission Set work is required for
      this scope beyond what already exists (`viewAllRecords=true` on
      `GTM_Offering_Admin` for both objects, already confirmed present).

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. `GTM_Assessment_Request__c.object-meta.xml` and
     `GTM_Link_Event__c.object-meta.xml` both have
     `<sharingModel>Private</sharingModel>`.
  2. `GtmHomeSnapshotController.getSnapshot()`'s `newAssessmentCount` and
     `recentViews`/`countStalled()` are confirmed — by a rep-scoping test,
     not code inspection alone — to only count/aggregate records the
     calling rep owns (or, for an admin with `viewAllRecords=true`, all
     records), once the OWD flip is live. If the stakeholder's "explicit,
     unambiguous" requirement is read literally, add an explicit
     `WHERE OwnerId = :UserInfo.getUserId()` (with an admin-bypass branch,
     using the same `viewAllRecords` detection built in sub-issue #3 if it
     ships first, or a simple `FeatureManagement`/permission-set check
     otherwise) to all four `getSnapshot()` queries and to
     `getRecentNewAssessmentRequests()` as defense-in-depth on top of the
     OWD flip — the Developer should treat "OWD flip alone" as the
     platform-correct minimum and the explicit filter as the stakeholder's
     stated preference for zero ambiguity; do not skip the explicit filter
     just because the flip alone is technically sufficient.
  3. The stale "safe to show org-wide" doc comment on `Snapshot`/
     `getSnapshot()` is corrected to describe the actual (now Private-OWD
     +/- explicit-filter) scoping.
  4. `getRecentNewAssessmentRequests()` no longer returns another rep's
     requester PII (name/company/platform) to a rep who doesn't own that
     request.
  5. Deploy runbook note: this is a **live production OWD change with no
     staging environment** (CLAUDE.md §1 — `gtm-dev` is Production).
     Flag prominently in the PR:
     - Existing sharing rules, if any manually configured in Setup for
       these two objects, must be reviewed before deploy — a Private flip
       can silently revoke access granted only implicitly by ReadWrite
       today (e.g. any report, list view, or flow that assumed org-wide
       visibility).
     - Any Queue (e.g. `GTM_Readout_Triage`, referenced in
       `GtmReadoutController`) or automation that reads/writes these two
       objects under a *user* context (not `without sharing` Apex) should
       be audited for reliance on ReadWrite visibility before this ships.
     - Recommend deploying at low-traffic time and having a rollback plan
       (revert `sharingModel` to `ReadWrite`) ready, since this cannot be
       rehearsed in a staging org.
- **Target Test Target:** New/updated Apex test class(es) for
  `GtmHomeSnapshotController` — likely `GtmHomeSnapshotControllerTest.cls`
  (create if it doesn't exist; verify by search) — asserting
  `getSnapshot()` and `getRecentNewAssessmentRequests()` return
  rep-scoped-only results for a non-admin `System.runAs()` user with
  another rep's records seeded, and full org-wide results for a user
  assigned `GTM_Offering_Admin`.
