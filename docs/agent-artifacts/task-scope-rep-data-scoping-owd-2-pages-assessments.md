# TASK SCOPE — ISSUE #rep-data-scoping-owd-2-pages-assessments

## 0. Context (split rollout, sub-issue 2 of 3)

This work was split from a combined finding (`rep-data-scoping-owd`) into
three sequential sub-issues, per this session's precedent (#184) for large
multi-part work. This is sub-issue **2 of 3** — explicit ownership filters
in `GtmSavedConfigurationController`, `GtmReadoutController`, and
`GtmRepLinkFinderController`. It does not depend on sub-issue 3
(`rep-data-scoping-owd-3-analytics-permcheck`) and the two could run in
parallel, but both should land only after sub-issue 1
(`rep-data-scoping-owd-1-owd-overview`, the OWD flip on
`GTM_Assessment_Request__c` / `GTM_Link_Event__c`) is confirmed live in
`gtm-dev`, since this sub-issue's "admin bypass" logic assumes the
`viewAllRecords=true` grants on `GTM_Offering_Admin` are the actual access
mechanism post-flip.

## 1. Requirements Breakdown

- **Target Objective:** Add explicit, defense-in-depth ownership filters
  to three rep-facing read methods that today rely 100% on implicit
  OWD+sharing with no explicit filter of their own, so correctness does
  not silently depend on OWD never changing again in the future. Also fix
  `GtmReadoutController.getContactsWithRequests(accountId)`, which filters
  only by `Account__c` and leaks assessment requests across reps who share
  visibility into the same Account.
- **System Component Impacted:** Apex —
  `GtmSavedConfigurationController.getMyConfigurations()`,
  `GtmReadoutController.getReadoutsForReview()`,
  `GtmReadoutController.getContactsWithRequests()`,
  `GtmRepLinkFinderController.getContactsWithLinks()`.

### Confirmed current state (read in full)

- `GtmSavedConfigurationController.getMyConfigurations()` — `SELECT ...
  FROM GTM_Saved_Configuration__c ORDER BY CreatedDate DESC LIMIT 200`, no
  `WHERE` clause at all. Relies entirely on `with sharing` + Private OWD
  (already correct on this object). The method's own name ("my
  configurations") documents the intended scope that the query itself
  does not enforce.
- `GtmReadoutController.getReadoutsForReview()` — `SELECT ... FROM
  GTM_Readout__c WHERE Status__c IN ('Draft', 'Pending Approval',
  'Approved') ORDER BY LastModifiedDate DESC LIMIT 200`, no owner filter.
  Doc comment explicitly notes this is deliberate: `with sharing` means a
  rep sees owned readouts *and*, since `GTM_Readout_Triage` queue owns
  unclaimed orphans, the queue's readouts too **for every rep who is a
  queue member**. This is intentional and must be preserved — an
  `OwnerId = :UserInfo.getUserId()` filter alone would be **wrong** here
  (it would hide legitimately queue-visible orphan readouts from queue
  members). The correct explicit filter is `OwnerId = :UserInfo.getUserId()
  OR OwnerId IN :queueIdsTheUserBelongsTo` (or equivalent), not a bare
  owner match — flag this nuance clearly to the Developer so it isn't
  flattened into the same pattern as the other three methods.
- `GtmRepLinkFinderController.getContactsWithLinks(accountId)` — read in
  full per the audit's flag. `SELECT ... FROM GTM_Saved_Configuration__c
  WHERE Account__c = :accountId AND Contact__c != null ...`, no owner
  filter — same implicit-OWD-only pattern as `getMyConfigurations()`.
  Follow-up queries for `requestIdByConfig` (against
  `GTM_Assessment_Request__c`) and `readoutIdByRequest` (against
  `GTM_Readout__c`) are similarly unfiltered by owner, relying on the
  `configIds`/`requestIdByConfig` sets already being rep-scoped from the
  first query — once the first query is properly scoped, these follow-ups
  inherit correct scoping transitively (they only ever look up
  descendants of already-scoped Ids), so they do **not** need their own
  independent `OwnerId` filter, only the base `configs` query does.
- `GtmReadoutController.getContactsWithRequests(accountId)` — confirmed:
  `SELECT ... FROM GTM_Assessment_Request__c WHERE Account__c = :accountId
  AND Contact__c != null ...`, filtered only by Account, not by owner.
  Given `GTM_Assessment_Request__c` is ReadWrite today (Private after
  sub-issue 1 ships), this is the same-root-cause leak the audit flagged
  as high-risk: two reps sharing visibility into one Account (e.g. via a
  Salesforce sharing rule on Account, or once this object is Private and
  both reps have an Account-level sharing reason) would each see the
  other's requests on it. Needs the same `OwnerId = :UserInfo.getUserId()`
  treatment (with admin bypass) as the others.

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? **No.**
- [x] Altering Custom Metadata? **No** — Apex only.
- [x] Introducing database fields? **No** — filtering on existing
      `OwnerId`, no new fields or Permission Set changes needed.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. `getMyConfigurations()`, `getContactsWithLinks()`, and
     `getContactsWithRequests()` each add an explicit
     `OwnerId = :UserInfo.getUserId()` backstop, **with an admin bypass
     branch** so a user holding `viewAllRecords=true` on the relevant
     object still sees everything. Use whatever admin-detection mechanism
     sub-issue 3 lands (a generalized `viewAllRecords`-via-
     `ObjectPermissions` check) if sub-issue 3 has shipped first; if this
     sub-issue ships first, use a minimal local equivalent (e.g. query
     `ObjectPermissions` joined to `PermissionSetAssignment` for the
     specific object, not a hardcoded permission-set-name check) so this
     sub-issue doesn't reintroduce the exact hardcoded-name anti-pattern
     sub-issue 3 is meant to remove — do not add a second hardcoded
     `'GTM_Offering_Admin'` string literal here.
  2. `getReadoutsForReview()` gets the queue-aware variant described above
     (`OwnerId = :UserInfo.getUserId() OR OwnerId IN :myQueueIds`), not a
     bare owner filter — verify against `GTM_Readout_Triage` queue
     membership (`GroupMember` where `UserOrGroupId = :UserInfo.getUserId()`
     resolves the queue's `GroupId`, or query the user's queue
     memberships directly).
  3. All four methods keep working for `with sharing` correctness even if
     OWD is ever changed again in the future, without relying on that
     future change happening correctly.
- **Target Test Target:** Update/create Apex tests —
  `GtmSavedConfigurationControllerTest.cls`,
  `GtmReadoutControllerTest.cls`, `GtmRepLinkFinderControllerTest.cls` —
  asserting each method returns only the running user's own records (plus,
  for `getReadoutsForReview`, queue-owned records when the user is a queue
  member) under `System.runAs()` with seeded cross-rep data, and full
  visibility for a `GTM_Offering_Admin`-assigned user.
