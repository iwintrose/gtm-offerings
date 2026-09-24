# TASK SCOPE — ISSUE #rep-initiated-assessment-no-page-2-share-and-continue

(See sub-issue `-1-picker-and-record`'s §0 for the overall split rationale.
This sub-issue depends on #1 merging first: it needs the pageless
`GTM_Saved_Configuration__c` record and its distinguishing
`Presentation_Stage__c` value to exist.)

## 1. Requirements Breakdown

- **Target Objective:** Support mode (b) of the confirmed requirement — a
  rep starts a pageless assessment (selects Contact/Account via #1's picker,
  optionally pre-fills some answers) and hands off a link for the prospect
  to view/continue and submit it themselves. This is the "in-progress share
  link," the first of the two required link types (requirement 4(i) in the
  original stakeholder brief — the results/readout link is 4(ii), scoped
  separately in `-3-readout-link-confirmation`).

- **System Component Impacted:** LWC (`gtmConfigurator`'s guest-access +
  password-gate logic, `gtmAssessmentQuestionnaire`), Apex
  (`GtmSavedConfigurationController`'s existing `Generated_URL__c`/
  `Link_Password__c` mechanism, `GtmAssessmentRequestController`).

## 2. Investigation findings (ground truth for the Architect)

**A. The existing share mechanism, confirmed and how it works end to end.**
`GTM_Saved_Configuration__c.Generated_URL__c` is a rep-supplied full URL
(built client-side in `gtmConfigWizard`, not derived server-side) pointing
at the `/configurator` route with query params; `Link_Password__c` is a
plaintext-stored password field, mandatory on every real link since
backlog decision **D10** ("Every link requires a password now, no
exceptions" — `_ensureGeneratedPassword()` in `gtmConfigWizard.js` now runs
unconditionally before every save). A prospect visiting the link is
password-gated: `gtmConfigurator.js`'s `accessBlocked` getter
(`!isConfigManager && !savedRecordId`) lets a guest with a `savedRecordId`
through to the password-entry step, which validates against
`GtmLinkAuthController` (HMAC token issue/verify — `issueToken`/
`verifyAndIssueToken`, referenced from both `GtmSavedConfigurationController.
saveConfiguration()`'s `previewToken` minting and
`GtmAssessmentRequestController.RequestInput.submissionToken`). This is a
proven, already-hardened (D10) mechanism — **reuse it as-is** for the
pageless in-progress link rather than building new auth. The only
difference from today's page-link flow: the prospect lands directly on the
assessment questionnaire (or a resume-in-progress state), never on branded
page content, since #1 establishes there IS no page for this record.

**B. Resume/continue mechanics likely already exist and should be reused,
not rebuilt.** `GtmAssessmentRequestController.RequestInput.draftToken`
and `GTM_Form_Draft__c` (`Draft_Type__c = 'Assessment'`,
`GtmAssessmentDraftController`, a guest-reachable controller per
`docs/architecture/overview.md`'s guest gate list) already implement
"prospect saved their place and finishes later" for the existing
page-linked flow. Architect must trace `GtmAssessmentDraftController` in
full (not yet read in this BA pass — flagged, not guessed) to confirm
whether the SAME draft mechanism, keyed off the pageless
`GTM_Saved_Configuration__c`'s Id, already covers "rep pre-fills some
answers, prospect finishes" with zero new code, or needs an explicit
"pre-filled by rep" seam added to `GtmAssessmentDraftController`/
`GTM_Form_Draft__c`. This is the single largest unresolved technical
question in this sub-issue — resolve it before writing new draft-handling
code, since duplicating `GTM_Form_Draft__c`'s job would be exactly the kind
of second-parallel-mechanism this whole feature is trying to avoid
(mirroring the reasoning in #1 §2.D against a second object).

**C. Mode (a) — rep completes it live — needs no new share link at all.**
When the rep submits on the prospect's behalf in one sitting, this
sub-issue's link mechanism is not invoked; `submitRequest()` runs directly
against the pageless record's `contactId`/`accountId` from #1. Only mode
(b) needs the share link scoped here.

**D. Closing note carried from #1.** The `accessBlocked` tightening
described in #1 (removing the internal-user bare-URL exemption) and this
sub-issue's guest-access reuse are not in tension: after #1's fix, a guest
(prospect) with a `savedRecordId` for a pageless record still gets through
`accessBlocked` exactly as today — the fix in #1 only removes the
INTERNAL-user no-savedRecordId exemption, it does not touch the
guest-with-savedRecordId branch this sub-issue depends on.

## 3. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? NO.
- [x] Altering Custom Metadata? NO — no YAML instrument change.
- [x] Introducing database fields? Likely NO new fields if `GTM_Form_Draft__c`
      is confirmed reusable per §2.B; if the Architect determines a new
      "rep pre-filled" marker field is needed on `GTM_Form_Draft__c`, it is
      guest-insert-only territory (Guest User licence: insert/read only,
      never update/delete — see `docs/backlog.md` "Known and accepted") and
      must be mapped to `GTM_Guest` alongside whatever internal
      permission set a rep needs to pre-fill it.

## 4. Plan Acceptance Criteria

- **Success Metric:** A rep can start a pageless assessment (#1), optionally
  answer some questions, and generate a working, password-protected
  in-progress link that a prospect can open, resume from wherever the rep
  left off (or from scratch if the rep pre-filled nothing), and submit
  themselves — with the resulting `GTM_Assessment_Request__c` correctly
  attributed to the real picked Contact/Account/Opportunity, no page ever
  implied to exist.
- **Target Test Target:** `GtmAssessmentDraftControllerTest` (extended, or
  confirmed already sufficient) and `GtmAssessmentRequestControllerTest`;
  a Jest spec on `gtmConfigurator` covering the pageless-record guest
  access path (extend the existing `__tests__` suite already present for
  `accessBlocked`-adjacent behavior — see
  `gtmConfigurator.previewToken.test.js` as precedent for this kind of
  test).
