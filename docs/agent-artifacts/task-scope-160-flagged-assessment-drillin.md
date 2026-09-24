# TASK SCOPE — ISSUE #160-flagged-assessment-drillin

## 1. Requirements Breakdown

- **Target Objective:** Let a content admin drill from the Team Analytics
  tab (`gtmAnalyticsTeam`, admin-only, same access boundary as #139/#145)
  into `GTM_Assessment_Request__c` records that were flagged during
  scoring, so "which assessments need a content-team look" is an aggregate
  view instead of something only discoverable by opening records one at a
  time. This is the explicitly-deferred follow-up named in
  `GtmAnalyticsTeamController.cls`'s own class doc comment and in the #139
  scoping comment ("instrument-version comparison and flagged-assessment
  drill-in are separate follow-ups").

  "Flagged" is precisely defined by existing data, confirmed by reading
  `GtmAssessmentScoring.cls`:
  - **Annotations** — non-blocking scoring observations. `Score.annotations`
    (`List<Annotation{code, message}>`) is serialized via `JSON.serialize()`
    into `Score.annotationsJson`, which `GtmAssessmentRequestController.cls`
    (line 788) persists verbatim to `GTM_Assessment_Request__c.Assessment_Flags__c`.
    Today the only annotation code ever produced is
    `GtmAssessmentScoring.FLAG_HIGH_REBUILD_RATIO` ("high_rebuild_ratio"),
    but the field is a JSON array and must be treated as open-ended (future
    annotation codes should not require a new drill-in code path). Shape:
    `[{"code":"high_rebuild_ratio","message":"High rebuild ratio — expect
    automation levels C/D to dominate."}, ...]`. Null/blank when there are
    no annotations (`annotationsJson` is only set when `annotations` is
    non-empty — see `GtmAssessmentScoring.cls` lines 678-680).
  - **Advisory** — the unsupported source/target pair gate that suppresses
    tier. `Score.advisory` (Boolean) → `Assessment_Advisory__c` (line 786 of
    `GtmAssessmentRequestController.cls`), and `Score.advisoryReason`
    (String, one line) → `Advisory_Reason__c` (trimmed to `MAX_SHORT`, line
    787). `Assessment_Advisory__c = true` means `tier` was null on that
    request (see `GtmAssessmentScoring.cls` line 324 doc comment).

  "Flagged" for this feature = `Assessment_Flags__c` is non-blank OR
  `Assessment_Advisory__c = true` — this is exactly the issue body's own
  filter definition and matches the two independent signals above.

- **System Component Impacted:** Apex (`GtmAnalyticsTeamController.cls` —
  new `@AuraEnabled` method(s) and row wrapper type(s), no schema change,
  no new object/field) + LWC (`gtmAnalyticsTeam` — new panel/section in the
  existing admin Team Analytics view).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? — **No.** `GtmAnalyticsTeamController` is
      a read-only analytics controller (no DML anywhere, per its own class
      doc), unrelated to the GUS chat/tool-calling surface. The new method
      must preserve that "no DML" property — confirmed as a hard
      constraint by the existing class's design, not merely convention.
- [ ] Altering Custom Metadata? — **No.** No `GTM_Assessment_*` or other
      Custom Metadata Type changes are needed; this reads existing fields
      on `GTM_Assessment_Request__c` (a standard custom object, not CMDT).
- [ ] Introducing database fields? — **No new schema.** Per the issue body
      ("No new schema needed") and confirmed by inspection:
      `Assessment_Flags__c`, `Assessment_Advisory__c`, and
      `Advisory_Reason__c` already exist and are already populated by
      `GtmAssessmentRequestController.cls`. No Permission Set mapping work
      is triggered by this issue — the new controller method exposes
      already-FLS-visible fields through Apex (which bypasses field-level
      security by default unless `WITH SECURITY_ENFORCED`/`stripInaccessible`
      is used elsewhere in this class; check the existing SOQL in
      `GtmAnalyticsTeamController.cls` for whether it already enforces FLS
      before deciding whether the new query needs to match that pattern).

## 3. Plan Acceptance Criteria

- **Success Metric:** A `GTM_Offering_Admin` user on the Team Analytics
  view (`gtmAnalyticsTeam`, reachable only via the admin-gated `hasTeamAccess()`
  toggle, same as today) can select a date range and see: (a) a flagged/advisory
  count summary for that range, and (b) a table listing each flagged or
  advisory `GTM_Assessment_Request__c` in range (at minimum: rep/owner,
  submitted date, flag reason(s) — parsed from `Assessment_Flags__c` JSON
  and/or `Advisory_Reason__c` — and a link). Clicking a row must navigate to
  that record's own detail view, using the same `NavigationMixin`
  `standard__recordPage` pattern already established in
  `gtmAssessmentSubmissionView.js` (there is no separate custom "detail
  route" component for this purpose to link into — `gtmAssessmentDetail`
  is a record-page-context component driven by `@api recordId` from the
  Lightning record page itself, not a navigable target with its own URL,
  so the correct target is the standard Salesforce record page for
  `GTM_Assessment_Request__c`). The new query must respect the same
  `with sharing` / admin-`viewAllRecords` access story the class already
  documents (no `without sharing` escalation), matching `getRepLeaderboard`'s
  existing pattern of validating `rangeStart`/`rangeEnd` via
  `validateRange()` and windowing on `CreatedDate`.

  Implementation shape (Architect-level detail, not a design fork — laid
  out here since the issue body already proposes this exact shape and no
  open question blocks it):
  - New method, e.g. `getFlaggedRequests(Date rangeStart, Date rangeEnd)`
    on `GtmAnalyticsTeamController`, `@AuraEnabled(cacheable=true)`,
    reusing `validateRange()`. SOQL: `SELECT Id, Name, OwnerId,
    CreatedDate, Assessment_Flags__c, Assessment_Advisory__c,
    Advisory_Reason__c FROM GTM_Assessment_Request__c WHERE CreatedDate
    >= :windowStart AND CreatedDate < :windowEnd AND (Assessment_Flags__c
    != null OR Assessment_Advisory__c = true)`, windowed the same way
    `getRepLeaderboard` windows (`DateTime.newInstance` on `rangeStart`/
    `rangeEnd.addDays(1)`). Returns a new wrapper (e.g. `FlaggedRow` with
    `requestId`, `repName` (resolved via the same owner-name-lookup pattern
    as `repNames` in `getRepLeaderboard`), `createdDate`, `advisory`,
    `advisoryReason`, and either the raw `flagsJson` or a pre-parsed
    `List<String> flagMessages` — decide in Architect design which side
    parses `Assessment_Flags__c` JSON, Apex or the LWC; either is
    reasonable, but the JSON shape above (`{code, message}` array) must be
    documented in whichever contract doc the Architect writes).
    Pagination: `getRepLeaderboard` has no pagination today (bounded by
    "one row per rep"); flagged-request counts are not bounded the same
    way, so the Architect should decide whether to cap/paginate (e.g. a
    `LIMIT` + "show more" or a hard row cap with a "narrow your date
    range" empty-state hint) rather than assume the existing pattern
    supports it as-is.
  - New panel in `gtmAnalyticsTeam.html`/`.js`, following the existing
    `panel table-panel` / `data-table` CSS/markup convention already used
    for the leaderboard table (see the `<div class="panel table-panel">`
    block in `gtmAnalyticsTeam.html`), sharing the same `rangeKey`/range
    picker already on the component (no second date picker) and the same
    `isLoading`/`loadError` conventions, loaded alongside
    `getRepLeaderboard` in `load()`.

- **Target Test Target:** `GtmAnalyticsTeamControllerTest.cls` (extend with
  coverage for the new method: flagged-only request, advisory-only
  request, both, neither, empty range, and the existing admin/non-admin
  access-boundary pattern already tested there) plus
  `force-app/main/default/lwc/gtmAnalyticsTeam/__tests__/gtmAnalyticsTeam.test.js`
  (extend for the new panel's render/empty/error states and the
  record-navigation call), run via `npm test` for the Jest half and the
  project's standard Apex test run for the class half.
