# gtmReadoutWorkspace — Contract (issue-gtm-readout-workspace)

## What this is

A single shared 3-tab LWC, rendered **INLINE by its parent** — swapped in for
the list/columns content the parent was already showing, not opened as a
modal/dialog and not a page navigation, per the product owner's approved
mockup (this superseded an earlier `lightning/modal` design during this same
build). It replaces the ad-hoc `standard__navItemPage` deep-link into
`GTM_Assessment_Submission_View` that `gtmReadoutsOverview.handleOpenReadout`
and `gtmRepLinkFinder`'s `handleViewReadout`/`handleGenerateReadout` used,
without adding anything to the `GTM_Offerings` app's tab bar (Overview /
Pages / Assessments stays the final 3-tab structure).

**This version reflects a second round of refinement** made directly off a
live product-owner click-through of the first build (six changes below);
the original 4-tab/Preview-default design is superseded, not additive.

**Ownership split:** `gtmReadoutWorkspace` itself holds no visibility state.
The parent (`gtmReadoutsOverview` or `gtmRepLinkFinder`) tracks which
card/link is selected and conditionally renders `<c-gtm-readout-workspace>`
in place of (or below) its own list/columns markup when something is
selected. `gtmReadoutWorkspace` renders its own "← Back" affordance, which
does nothing but `dispatchEvent(new CustomEvent('back'))` — the parent
listens for `back` and clears its own selected state, unmounting the
workspace and returning to the list/columns view. This mirrors the mockup's
back-link pattern and keeps the workspace itself a pure, stateless-about-
visibility composition component.

## Tabs

| Tab | Component embedded | Notes |
|---|---|---|
| Assessment | `c-gtm-assessment-detail` | Same `record-id` (`Assessment Request` Id) `gtmRepLinkFinder` already passes it. Now also renders a "Prospect's Answers" section below "Assessment Details" (see below). |
| Readout | `c-gtm-readout-review` | Same component `gtmAssessmentSubmissionView`/the retired tab already embedded; it self-resolves the readout from either a `c__readout` page-ref state or its own `@api recordId` (Assessment Request Id) via `GtmReadoutController.getReadoutByRequest`, so no new resolution logic was added here. Gated on submission — see below. |
| Conduit | `c-conduit-dashboard` | Only rendered when `Has_Conduit__c` on the request's offering resolves true. Passed `@api recordId` = this workspace's `assessmentRequestId` — confirmed via `ConduitPlanController.cls`: every query filters by `Assessment_Request__c`. Untouched by this refinement. |

There is no Preview tab (removed — see "Link/password section" below).

## Public API

```js
@api assessmentRequestId; // required — GTM_Assessment_Request__c Id.
                          // Both entry points always have this: gtmReadoutsOverview's
                          // ReadoutSummary.assessmentRequestId, and gtmRepLinkFinder's
                          // selectedLinkRequestId.

@api readoutId = null;   // optional — GTM_Readout__c Id, null until a readout
                          // exists for the request. Used by the Readout tab
                          // once reachable (see gating below).

@api offeringKey = '';   // optional — offering key for the link section's
                          // "Preview the assessment" c-gtm-configurator embed.

@api initialTab = '';    // optional (issue-102-1-engagement-links-landing) —
                          // set to 'readout' to override the refinement #3
                          // default below on first render, ONLY when readoutId
                          // is also set. See "Default-active-tab logic" below.
```

The workspace also dispatches a bubbling-free `back` `CustomEvent` (no
payload) when its own "← Back" control is clicked — the parent is expected
to listen for this and unmount the workspace.

## Default-active-tab logic (refinement #3)

- The workspace always lands on the **Assessment** tab, regardless of
  whether `readoutId` was supplied. A rep opening the workspace — from a
  card, a "View readout" click, or a freshly generated readout — sees the
  assessment context first, not the readout content, per direct
  product-owner feedback after the live click-through (the original design
  defaulted to Readout when `readoutId` was present; this is now
  superseded).
- A rep can freely switch tabs afterward; the default only governs the tab
  active on first render.
- **Opt-in override (issue-102-1-engagement-links-landing, D7 + acceptance
  criterion 4):** `c-gtm-assessment-detail`'s "Open the readout" forward
  action is a new, distinct entry point refinement #3 did not enumerate —
  an explicit "take me to the readout" click, not "open the workspace"
  generically. Its standalone-mode (`NavigationMixin`) navigation sets
  `initialTab='readout'` (via `c__focusReadoutTab` in the page-ref state,
  read by `gtmReadoutsOverview` and passed straight through) so THIS one
  path lands on Readout instead of Assessment. Every other origin — a card,
  "View readout", a freshly generated readout, any caller that leaves
  `initialTab` unset — keeps the unchanged refinement #3 default. The
  tabset-mode half of the same forward action needs no such rider: it is
  already a same-component `activeTabValue` swap
  (`handleOpenReadoutFromDetail`), not a fresh mount.

## Readout-tab submission gating (refinement #5)

- The Readout tab's content is gated on whether the prospect has actually
  answered the assessment questions, read via the standard `getRecord` UI
  API wire (the same mechanism `c-gtm-assessment-detail` already uses for
  its own fields) — no new Apex.
- While unsubmitted, the tab shows the same reminder message the Assessment
  tab's "Prospect's Answers" section shows (see below):
  `"{Contact Name} at {Account Name} has not submitted the assessment.
  Reach out to them to remind them."`, instead of the Generate Readout
  prompt or readout content. This applies defensively even though the tab
  has no realistic path to reach without a submission in the normal flow,
  since `lightning-tab` has no native `disabled` affordance to rely on.
- Once submitted, the tab reverts to its previous behavior: "Generate
  Readout" prompt when no readout exists yet, `c-gtm-readout-review`
  once one does.
- **Bug fix — gate on real answers, not a timestamp alone:** the gate used to
  be `!!Submitted_At__c` alone. That conflates "a submission timestamp was
  written" with "the prospect actually answered questions", and the two can
  diverge in either direction (a timestamp set without real answers, or
  real answers present without the timestamp ever having been stamped). The
  fix added a second signal — at least one of the instrument's own answer
  fields is non-blank —
  `Pain_Points__c`, `Migration_Goals__c`, `Success_Criteria__c`,
  `Decision_Makers__c`, `Budget_Range__c`, `Urgency_Driver__c`,
  `Key_Integrations__c`, `Executive_Sponsorship__c`, `Target_Platform__c`,
  `Internal_Team_Size__c`, `Monthly_Send_Volume__c`, `Contact_Count__c` —
  the same fields "Prospect's Answers" renders. The gate
  ("`isSubmitted`"/"`hasMeaningfulAnswers`") is the AND of both signals:
  `Submitted_At__c` must be set AND at least one answer field must be
  non-blank — neither signal alone is sufficient. (An intermediate version of
  this fix briefly dropped `Submitted_At__c` from the check entirely; see
  "Round 3 — three direct product-owner corrections after a live review,"
  item "3 & 4" below, for why it was reinstated as an AND — that is the
  current, correct behavior.) This same fix was made in
  `c-gtm-assessment-detail`'s own copy of this gate. As of
  issue-readout-navigation-consolidation-03-docs-and-answer-fields-dedup,
  the `ANSWER_FIELDS` list and the "at least one non-blank" check
  (`hasMeaningfulAnswers`) are genuinely shared code, extracted into
  `c/gtmAssessmentAnswerFields` and imported by both components; each still
  combines it with its own independent `Submitted_At__c` field read and its
  own independent not-submitted message (per the existing doc note above),
  which were not extracted.
- **Conduit tab gets the same answers-completeness gate, additively.** The
  tab's presence is still driven purely by the offering-level
  `Has_Conduit__c` check (below) — an ineligible offering shows no Conduit
  tab at all, unchanged. But an eligible offering whose assessment has no
  real answers yet now shows the same not-submitted reminder message inside
  the tab instead of `c-conduit-dashboard` (which would otherwise have
  nothing meaningful to resolve off an unanswered assessment request).

## Assessment tab — "Prospect's Answers" section (refinement #4)

`c-gtm-assessment-detail` (embedded, unmodified in structure otherwise) now
renders a second card below "Assessment Details":

- **Not answered** (no instrument answer field populated — see the
  answers-completeness bug fix below): shows
  `"{Contact Name} at {Account Name} has not submitted the assessment.
  Reach out to them to remind them."`, using the same `Contact__r.Name` /
  `Account__r.Name` (falling back to `Company__c`) fields the component
  already wires for its "Connected Records" card. **Contact-name resolution
  (bug fix):** many requests are submitted by a prospect who has no linked
  CRM Contact record yet, so `Contact__r.Name` is legitimately blank far
  more often than "no contact at all" implies. The name prefers, in order:
  `Contact__r.Name` (a real linked Contact), then `Requester_Name__c` (the
  name the person actually typed in at submission — always present for a
  submitted-or-not request coming through the assessment form), and only
  falls back to the generic `"The contact"` placeholder when both are blank.
  Same fallback chain in `gtmReadoutWorkspace`'s own copy of this message
  for the Readout tab's gating (below) — the two are independent getters
  reading the same fields, not shared code, so both had to be fixed.
- **Answered**: shows the prospect's actual submitted answers, read
  directly off `GTM_Assessment_Request__c` — these are the raw instrument
  answers `GtmAssessmentScoring` already writes at submission time (Pain
  Points, Migration Goals, Success Criteria, Decision Makers, Budget Range,
  Urgency Driver, Key Integrations, Executive Sponsorship, Target Platform,
  Internal Team Size, Monthly Send Volume, Contact/Lead Database Size), not
  a new data source. No new Apex — added fields to the existing `getRecord`
  wire's `FIELDS` array only.
- **Bug fix — gate on real answers, not `Submitted_At__c` alone:** the
  submitted/not-submitted split above used to be `!!Submitted_At__c` alone.
  The fix added "at least one of the twelve instrument answer fields listed
  above is non-blank" (`hasMeaningfulAnswers`) as a second signal —
  `Submitted_At__c` can diverge from whether real answers exist in either
  direction (a timestamp written without answers, or answers present without
  a timestamp). The gate (`isSubmitted`) here is the AND of both signals:
  `Submitted_At__c` must be set AND `hasMeaningfulAnswers` must be true —
  see "Round 3 — three direct product-owner corrections after a live
  review," item "3 & 4," below, for why `Submitted_At__c` was kept in the
  gate rather than dropped. `gtmReadoutWorkspace`'s Readout/Conduit-tab gate
  (above) makes the identical AND-gate check, over the same twelve fields.
  The `ANSWER_FIELDS` list and `hasMeaningfulAnswers` check itself are
  shared code as of issue-readout-navigation-consolidation-03-docs-and-
  answer-fields-dedup (`c/gtmAssessmentAnswerFields`, imported by both
  components); each component still reads its own `Submitted_At__c` field
  independently to complete its own AND-gate.

Because `c-gtm-assessment-detail` is also embedded elsewhere (the
`GTM_Assessment_Request__c` record page, `gtmAssessmentSubmissionView`,
`gtmRepLinkFinder`), this section shows in those contexts too — additive
only, nothing else in the component changed.

## Link/password section + inline "Preview the assessment" (refinement #6)

Replaces the removed Preview tab. Rendered above the tabset, only when the
request has a saved configuration (`Saved_Configuration__c` populated) —
mirrors `gtmRepLinkFinder`'s own view-step link/password block exactly, same
markup pattern, same Apex:

- **Assessment Link** — read-only field + "Copy link" button, sourced from
  `Saved_Configuration__r.Generated_URL__c` (read via the same `getRecord`
  wire used for the submission gate above).
- **Password** — read-only field, masked until revealed via "Show"
  (`GtmSavedConfigurationController.getPassword`, the same Apex
  `gtmRepLinkFinder` calls), then "Copy"; "New password" regenerates via
  `GtmSavedConfigurationController.regeneratePassword` (same
  confirm-before-regenerate flow gtmRepLinkFinder uses). No new Apex.
- **"Preview the assessment" / "Hide preview" toggle** — mirrors
  `gtmRepLinkFinder`'s "Preview the link" toggle exactly: clicking it
  renders `c-gtm-configurator` (`offering-key={offeringKey}`,
  `template-type="configurator"`, `view-only={false}`) inline below the
  section. Uses the same `offeringKey` prop this workspace already receives
  (the wiring gap fixed in commit `aeb5f19` applies here unchanged).
  **Bug fix:** `c-gtm-configurator` has no `@api` way to be told which saved
  record to render at all — it only ever reads its own `?cfgId=` query
  param off the real browser URL, once, in its own `connectedCallback`
  (`readUrlParams()`). `offeringKey` alone only ever pointed it at the
  generic/blank template for that offering, not the specific configuration
  actually sent to this prospect. This workspace now does exactly what
  `gtmRepLinkFinder.setCfgIdParam`/`clearCfgIdParam` already do for its own
  "Preview the link": once the `getRecord` wire resolves
  `Saved_Configuration__c`, it writes `?cfgId=<that id>` onto the current
  URL via `window.history.replaceState` (best-effort, same try/catch), and
  clears it again on "Back" and `disconnectedCallback` so it can't leak into
  the next thing that reads the URL. The `c-gtm-configurator` embed also
  takes `key={cfgId}`, mirroring `gtmRepLinkFinder`'s `key={selectedLink.recordId}`,
  so a fresh instance mounts (and re-reads the URL) whenever the underlying
  saved configuration changes rather than reusing a stale one.

## Conduit-tab gating (unchanged)

- On `connectedCallback`, the workspace calls
  `GtmAssessmentRequestController.getOfferingHasConduit(assessmentRequestId)`
  (read-only, no DML) which resolves `GTM_Assessment_Request__c
  .Offering_Key__c` → `GTM_Offering__mdt.Has_Conduit__c` for that key.
- The Conduit tab is omitted from the tabset entirely (not just disabled)
  when this resolves false — mirrors `showGenerateReadout`'s existing
  omit-rather-than-disable pattern in `gtmRepLinkFinder`.
- Fails closed: any error/blank offering key resolves to `false`, same as
  the existing `sourceLabelFor()`/`offeringAnnualTarget()` best-effort
  pattern in `GtmAssessmentRequestController`.

## `Has_Conduit__c` field addition (unchanged, prior round)

- New `Checkbox` field on `GTM_Offering__mdt`, default `false`.
- Set explicitly `true` only on the `Migration_Accelerator`
  `GTM_Offering__mdt` record today (the only offering with a Conduit
  dashboard); any future offering with a Conduit mapping sets this on its
  own row instead of a code change.
- FLS: custom metadata field-level access in this org is controlled at the
  type level via `customMetadataTypeAccesses`, not per-field
  `fieldPermissions` entries (there are none anywhere in this repo for any
  `__mdt` field) — granted via a `GTM_Offering__mdt` `customMetadataTypeAccesses`
  entry on `GTM_Offering_User` and `GTM_Offering_Admin` only (both previously
  had none at all for this type). Not granted to `GTM_Content_Manager`/
  `GTM_Content_Admin` (already have object-level access from before this
  issue) or `GTM_Guest` (this workspace has no guest-facing path).

## `gtmReadoutsOverview` — Assessments tab changes

- **Shared page-header retained (correction to a prior round):** a prior
  round on this branch removed `c-gtm-page-header` from this component
  entirely, in a misguided attempt to address a product-owner screenshot
  showing a bare "Assessments" icon+title bar. That screenshot was actually
  the **platform-level flexipage/tab header** Lightning renders above
  whatever the embedded LWC returns — a layer this component's own template
  cannot reach or suppress — so removing the component's internal header
  neither fixed the complaint nor was warranted on its own terms. Per
  `docs/agent-artifacts/header-bar-consistency-assessment.md`,
  `c-gtm-page-header` is the established shared header used consistently
  across the app's pages (`gtmOverview`, `gtmContentHome`, etc.), and this
  component's correct usage is `icon-name="standard:report"
  eyebrow="Readouts" title="Assessment Submissions"` with the Refresh
  button in its `actions` slot — restored as such. Controlling the
  platform-level header, if ever pursued, would be a separate,
  metadata-level investigation (the `GTM_Assessments` tab / flexipage
  configuration), out of scope for this component.
- **Search (refinement #2):** an inline `lightning-input type="search"` in
  the same toolbar filters the already-loaded `readouts` list client-side by
  Account (`company`) or Contact/requester (`name`) — no new Apex,
  `getReadoutsForReview` already returns the full actionable list. Mirrors
  the Account/Contact search pattern from `gtmRepLinkFinder`'s Pages tab.

## Entry-point wiring

- `gtmReadoutsOverview.handleOpenReadout` — sets `selectedAssessmentRequestId`
  (from `ReadoutSummary.assessmentRequestId`, already returned by
  `getReadoutsForReview`) and `selectedReadoutId` (the row's own id) on the
  parent, which conditionally renders `<c-gtm-readout-workspace>` in place of
  the cards grid. `handleWorkspaceBack` (the `back`-event listener) clears
  both, returning to the grid.
- `gtmRepLinkFinder.handleViewReadout` — sets the same local
  `showWorkspace = true` (plus `assessmentRequestId`/`readoutId` already on
  hand from `selectedLink`) so the view step renders the workspace instead of
  its own Preview/Assessment/Readout block; `handleWorkspaceBack` sets
  `showWorkspace = false`, returning to the normal view step.
- `gtmRepLinkFinder.handleGenerateReadout` — calls
  `generateReadoutForRequest` exactly as before, then, once the promise
  resolves, sets `showWorkspace = true` with the resulting `readoutId` (no
  change to the Apex call itself, only to what happens with its result).

## Selection state survives a browser refresh (bug fix)

Both `gtmReadoutsOverview` (Assessments tab) and `gtmRepLinkFinder` (Pages
tab) used to keep their "which record is currently selected" state purely
in `@track` fields, so an F5 while looking at the workspace (or, for
`gtmRepLinkFinder`, mid-way through its Account → Contact → Link Miller
columns) reset the component back to its list/first-step view, losing the
selection. Fixed the same way, in both, using the established pattern
already in this codebase for a `standard__navItemPage` tab's own URL state
(`gtmPageBrowser`, `gtmContentManager`) rather than inventing a new one:

- **Write** — on every selection/back-navigation action, the selected id(s)
  are mirrored onto the current URL via `window.history.replaceState`
  (best-effort, wrapped in try/catch — a sandbox that blocks History
  mutation degrades to "no refresh-survival", not a broken click). This is
  the same mechanism `gtmRepLinkFinder.setCfgIdParam`/`clearCfgIdParam` and
  `gtmContentManager.stripNewFromUrl` already use for a URL-state update
  that is a history replace, not a navigation — it does not requery
  `CurrentPageReference` on its own.
  - `gtmReadoutsOverview.writeSelectionToUrl` — `c__assessmentRequestId`,
    `c__readoutId`, `c__offeringKey`.
  - `gtmRepLinkFinder.writeDrillStateToUrl` — `c__rlfAccountId`,
    `c__rlfContactId`, `c__rlfLinkId`, namespaced with an `rlf` prefix (not
    just `c__accountId`) so they can never collide with `gtmPageBrowser`'s
    own `c__template`/`c__recordId`/`c__company`/`c__offering` state on the
    same tab's URL. Written at every depth — picking an Account, a Contact,
    or a Link, and clearing the appropriate suffix on each "Back" — so a
    refresh restores to whatever depth the rep was actually at, not only
    the deepest (fully-selected-link) state.
- **Restore** — on load, both read that same state back via the standard
  `@wire(CurrentPageReference)` mechanism (the same one `gtmPageBrowser`
  already relies on for this tab's own deep-link state) and re-derive the
  selection from it:
  - `gtmReadoutsOverview.capturePageRef` sets the three `@track` fields
    directly from the wired state — the row data those fields need
    (offering key, etc.) is already carried in the URL state itself, so
    there is no dependency on `getReadoutsForReview`'s own list having
    loaded first.
  - `gtmRepLinkFinder.captureLinkFinderState` re-enters the existing
    Account → Contact → Link flow at whatever depth the URL state
    specifies, via a new `restoreDrillState` method that calls the same
    `GtmRepLinkFinderController.getContactsWithLinks` Apex the ordinary
    Account-search step already calls — no new Apex — and then applies the
    contact/link ids on top of the result once it resolves. Deliberately
    does **not** run when a `targetRecordId` prop is already present:
    that's the wizard's "Done" deep-link path (via `gtmPageBrowser`'s own
    `c__template=link`/`c__recordId` state), which is already refresh-safe
    today through `gtmPageBrowser` re-driving `targetRecordId` on every
    load, so layering this restore on top of it would just race it.

## Explicitly unmodified

`GtmReadoutController.cls`, `ConduitPlanController.cls` logic (only
`conduitDashboard`'s stale doc comment was touched, prior round),
`gtmConfigurator`, the Pages Miller-columns navigation, and Conduit-tab
gating (`Has_Conduit__c`). `c-gtm-assessment-detail`'s existing structure
(Connected Records / Assessment Details cards) is unmodified — the
Prospect's Answers section is additive only.

## Round 3 — three direct product-owner corrections after a live review

### 1. "Preview the assessment" now opens as a MODAL

This reverses part of an earlier round's design: the "Preview the assessment"
button used to toggle an inline `c-gtm-configurator` embed open/shut below
the link/password section (see "Link/password section" above). Per direct
product-owner correction, confirmed live, this ONE action now opens as a
modal instead — nothing else in the workspace changes (the tabset, the link/
password fields themselves, all stay inline exactly as before).

- New component: `gtmAssessmentPreviewModal`, extending the standard
  `lightning/modal` base component (`LightningModal`). A repo-wide grep found
  no prior `lightning/modal` usage anywhere in this codebase to follow, so
  this implements the documented base-component contract directly: a caller
  invokes `MyModal.open({...props})`, which returns a Promise; the modal
  closes itself via `this.close()`/`this.dismiss()`.
- `gtmReadoutWorkspace.handleTogglePreview` now calls
  `GtmAssessmentPreviewModal.open({ size: 'large', offeringKey, cfgId })`
  instead of flipping a local `showPreview` boolean. `showPreview` and the
  inline embed markup (and its now-dead `.grw-preview-row`/`.grw-stage` CSS)
  were removed. `previewToggleLabel` is now a static `'Preview the
  assessment'` (no more "Hide preview" state, since there's nothing to hide
  inline any more).
- Jest support: sfdx-lwc-jest ships stubs for `lightning/modalHeader`,
  `lightning/modalBody` and `lightning/modalFooter` (a modal's own
  sub-components) but not for `lightning/modal` itself — the base class a
  modal component extends. `jest.config.js` now maps `^lightning/modal$` to
  a small hand-written stub at `force-app/test/jest-mocks/lightningModal.js`
  (a `LightningElement` subclass with a static `open()` and instance
  `close()`/`dismiss()`), the same way it already maps `c/gtmBrandTokens` for
  its own resolver gap.

### 2. Preview modal — answers-only redesign (final product-owner decision)

The brief originally asked for the modal to embed the actual prospect-facing
assessment FORM (`c-gtm-assessment-questionnaire`), not the marketing/story
landing page `c-gtm-configurator` it rendered at the time. That was
investigated and explicitly blocked (see history below, kept for the
record) rather than guessed around. The product owner has since made a
final call, resolving the blocker directly: **the modal shows a read-only
"answers only" preview — the actual assessment questions, each with the
prospect's submitted answer if they answered it, or "Not answered" if they
didn't** — covering both "not yet submitted" and "submitted but skipped
some questions" uniformly, with no separate reminder-message substitution.
This is explicitly none of: the live interactive
`c-gtm-assessment-questionnaire` (writes real data), `c-gtm-configurator`
(the marketing/story page, the prior wrong-content bug), or a screenshot/
rendered-image of either.

**New component: `gtmAssessmentAnswersPreview`.**

- `@api recordId` — the `GTM_Assessment_Request__c` Id. The same
  identifying prop the modal (and, before it, `gtmReadoutWorkspace`) already
  has in hand as `assessmentRequestId`; `gtmReadoutWorkspace.
  handleTogglePreview` now passes it through to `GtmAssessmentPreviewModal.
  open({...})` as `assessmentRequestId`, and `gtmAssessmentPreviewModal`
  forwards it to this component's `record-id`.
- Read-only `getRecord` wire, no Apex, no DML, no localStorage/draft calls
  of any kind — purely presentational, no write actions, no submit button.
- Question source: **reuses `c-gtm-assessment-detail`'s own `ANSWER_FIELDS`
  list verbatim** (the twelve fields its "Prospect's Answers" section
  already renders — `Pain_Points__c`, `Migration_Goals__c`,
  `Success_Criteria__c`, `Decision_Makers__c`, `Budget_Range__c`,
  `Urgency_Driver__c`, `Key_Integrations__c`, `Executive_Sponsorship__c`,
  `Target_Platform__c`, `Internal_Team_Size__c`, `Monthly_Send_Volume__c`,
  `Contact_Count__c`), not a new or reinvented field list. Each field is
  paired with its prospect-facing question wording, carried over verbatim
  from `gtmAssessmentQuestionnaire.BD_CONTEXT_FIELDS` (eleven of the twelve
  — `Target_Platform__c` is the twelfth, worded from the routing step's own
  "what are you moving to" question) so a rep reads the same vocabulary the
  prospect was actually asked.
- Renders every one of the twelve questions unconditionally, with the
  field's value if non-blank or a literal "Not answered" placeholder if
  blank — the same rendering regardless of whether `Submitted_At__c` is set,
  per the product owner's "no separate reminder-message substitution"
  instruction.

**Investigation history, kept for the record (why `c-gtm-assessment-
questionnaire` was never viable and why `c-gtm-configurator` was never the
right embed either):**

- `gtmAssessmentQuestionnaire.js` has no `viewOnly`/read-only mode of any
  kind — no such `@api` property exists, and nothing in its logic gates
  behavior on one. It is built entirely for **live prospect data entry**:
  `connectedCallback` calls `getPlatforms`/`getQuestionnaire`, restores or
  hydrates a draft, and every keystroke handler (`handleChoice`,
  `handleRouting`, `handleContact`, etc.) writes to `localStorage`
  (`persist()`) and, on step transitions, pushes a server-side draft via
  `GtmAssessmentDraftController.saveDraft` (`pushDraft`). Reaching its last
  step and clicking through calls `GtmAssessmentRequestController.submitRequest`
  — a real, scored assessment request — for real, against whatever
  `savedRecordId` is passed in. Embedding it here would have let a rep's
  preview click write real draft rows, and possibly submit a second, real
  request, against the prospect's own saved configuration.
- `gtmConfigurator`'s own `@api viewOnly` has no equivalent on
  `gtmAssessmentQuestionnaire` — `viewOnly` only gates `gtmConfigurator`'s
  own editing chrome and is never read by the questionnaire at all.

**The gap this surfaces, reported rather than hidden (per the product
owner's explicit instruction):** the live intake form
(`gtmAssessmentQuestionnaire`) asks up to roughly 23 questions per
respondent — 8 scored readiness slots (dynamically branched per source/
target pair via `GtmAssessmentInstrument.getPack`/`gtmPredicate.
resolveSlots`), 6 complexity dimensions (also pack-adapted), and up to 9
supplement questions (scored + free-text, also pack-resolved). **None of
those ~23 questions are persisted as individually-addressable fields on
`GTM_Assessment_Request__c`** — only their aggregate score is stored
server-side (`GtmAssessmentScoring`). The only individually-readable,
previewable answers that exist anywhere are the twelve `ANSWER_FIELDS`
this component renders (the eleven BD-context fields from ADR-0008 section
5, plus `Target_Platform__c`) — a fixed-schema side channel that was never
meant to capture the branching instrument itself. This means the preview
modal, by construction, can only ever show those twelve; the 8+6+~9
branching questions have no answer data anywhere for any component to
preview, modal or otherwise. Closing that gap (e.g. persisting individual
readiness/complexity/supplement answers, not just their score) is a
separate, larger data-model change, out of scope for this modal-content
fix.

### 3 & 4. Readout/Conduit gating — require genuine completion

**Readout tab (reverses part of a prior round for `isSubmitted`):** a prior
round dropped `Submitted_At__c` from the gate entirely, unlocking on "at
least one instrument answer field is non-blank" alone. Confirmed live: a
record with only ONE field filled in (e.g. just `Target_Platform__c`,
everything else blank) still unlocked full readout content, which the
product owner considers "not submitted" in spirit. The gate
(`isSubmitted`) is now the AND of both signals — `Submitted_At__c` must be
set (the prospect actually completed and submitted the form) AND at least
one instrument answer field must be non-blank (the existing
`hasMeaningfulAnswers` check, kept as a sanity check against a
stamped-but-empty record). Neither signal alone is sufficient. Applied
identically, independently, in both places that had their own copy of this
gate: `gtmAssessmentDetail.js`'s `isSubmitted` getter (used by its own
"Prospect's Answers" section) and `gtmReadoutWorkspace.js`'s own
`isSubmitted` getter (used by its Readout tab).

**Conduit tab (no longer blocks at all):** previously showed the identical
reminder-only message the Readout tab shows, fully replacing
`c-conduit-dashboard`, whenever the combined gate above failed. Per direct
product-owner correction: Conduit should **always** render
`c-conduit-dashboard` whenever the offering is conduit-eligible
(`Has_Conduit__c`), regardless of submission status — that gating stays
purely offering-level, unchanged. When the assessment has not been
submitted (same combined rule), a small note banner
(`notSubmittedNote`, "Note: {Contact Name} at {Account Name} has not
submitted the assessment yet.", using the same Contact→Requester_Name__c→
"The contact" fallback chain as everywhere else) is shown *above* the
dashboard, not instead of it. `gtmReadoutWorkspace.html`'s Conduit tab
template no longer branches on `isSubmitted` for whether to render
`c-conduit-dashboard` at all — only for whether to show the note.

## Account → Contact → Assessment Request trail (issue-gtm-assessments-account-contact-trail)

Adds a second Assessments-tab browse mode: `gtmReadoutAccountFinder`, an
Account → Contact → Assessment Request Miller-columns trail directly
replicating `gtmRepLinkFinder`'s existing Account → Contact → Link pattern
on the Pages tab. This is additive, not a replacement — the coordinator's
binding decision (see `WORKTREE_SCOPE.md` on this branch) kept the existing
flat card-grid + free-text search fully intact as "All Assessments",
alongside the new trail as "By Account or Contact", behind a simple toggle in
`gtmReadoutsOverview`.

### Ownership split (mirrors the workspace's own split above)

`gtmReadoutAccountFinder` never renders `gtmReadoutWorkspace` itself and
holds no opinion about it — unlike `gtmRepLinkFinder`, which embeds the
workspace inline as part of its own "view" step. Instead, picking a request
in the trail dispatches a bubbling-free `selectrequest` CustomEvent
(`detail: { assessmentRequestId, readoutId, offeringKey }`), and
`gtmReadoutsOverview` — which already owns `selectedAssessmentRequestId`/
`selectedReadoutId`/`selectedOfferingKey` for the flat grid's own
`handleOpenReadout` — sets that same state from the event. Both browsing
modes therefore render through the exact same `<c-gtm-readout-workspace>`
embed already documented above; there is exactly one place in this tab
that mounts that component, never two.

### New Apex: `GtmReadoutController.getContactsWithRequests(Id accountId)`

Read-only, no DML, `cacheable=true`, `with sharing` (enforced at the class
level). Returns `List<ContactRequests>` — one entry per Contact on the
given Account that has at least one `GTM_Assessment_Request__c` filed
against it (joining on the object's own direct `Account__c`/`Contact__c`
lookups, both pre-existing and already FLS-granted on
`GTM_Offering_User`/`GTM_Offering_Admin` — confirmed, not re-granted), each
carrying its own `List<RequestSummary>` (newest first). `RequestSummary`
additionally resolves the most recent `GTM_Readout__c` per request (nullable
— no readout generated yet is a normal, unremarkable state, not an error),
via the same two-flat-follow-up-query shape
`GtmRepLinkFinderController.getContactsWithLinks` already uses for its own
Saved-Configuration → Request → Readout resolution (SOQL cannot nest an
aggregate relationship two levels below the root).

No new custom object/field/permission-set work was needed: `Account__c`
and `Contact__c` on `GTM_Assessment_Request__c` already exist and are
already FLS-granted for the same profiles the flat grid's
`getReadoutsForReview` already relies on.

### URL-state contract (extends, does not replace, the existing one)

`gtmReadoutsOverview` already persisted `c__assessmentRequestId`/
`c__readoutId`/`c__offeringKey` for the selected-workspace state (see
above). This issue adds one more param to that same
`capturePageRef`/`writeSelectionToUrl` pair: `c__browseMode` (`'account'`
when the trail is active; omitted, not written as `'all'`, when it isn't —
so a bookmarked/shared link from before this toggle existed keeps behaving
exactly as it always did).

`gtmReadoutAccountFinder` owns its own trail-depth URL state independently,
mirroring `gtmRepLinkFinder`'s own `c__rlfAccountId`/`c__rlfContactId`/
`c__rlfLinkId` mechanism exactly, but namespaced `c__rafAccountId`/
`c__rafContactId` (Readout Account Finder) so the two components' URL state
can never collide if ever rendered together. It does not persist a selected
request in its own namespace — once a request is picked, control (and
persistence) passes to the parent's existing `c__assessmentRequestId` state
via the `selectrequest` event above, so there is exactly one place that
owns "which request/readout is open," matching the ownership split.

A single browser refresh therefore restores, in this order: (1) which
browse mode was active (`c__browseMode`), (2) if a request/readout was
already open, that state wins and both browse-mode UIs are hidden behind
the workspace (existing behavior, unchanged); (3) otherwise, if the trail
was active and mid-drill, `gtmReadoutAccountFinder`'s own `c__raf*` state
restores the Account/Contact depth via the same `getContactsWithRequests`
call its normal drill-down already makes.

## Pages-tab quick-access tile grid (issue-gtm-assessments-account-contact-trail)

Per direct product-owner feedback on a live review ("For the Pages Tab
below the search you should include the Tiles that relate to the Pages
similar to the Tiles for the assessments — it helps the person find pages
quicker"): `gtmRepLinkFinder` now renders a card/tile grid directly below
its Account search, visible only on the first ("account") step — i.e. it
sits in the same visual slot `gtmReadoutsOverview`'s own flat card grid
occupies relative to *its* search, and reuses that same `.rcard`/`.cards`
visual treatment (`.rlf-tile`/`.rlf-tiles` here).

Reuses `GtmSavedConfigurationController.getMyConfigurations()` — the same
Apex `gtmSavedLinksBar` already calls for its own "your saved links" bar —
rather than adding new Apex; it already returns every
`GTM_Saved_Configuration__c` a rep can see, flat, newest first, which is
exactly this grid's shape.

Clicking a tile re-enters the exact same `restoreDrillState(accountId)`
code path the URL-restore mechanism already uses (seeding
`_restoredContactId`/`_restoredLinkId` from the tile's own Account/Contact/
link ids first), landing on the identical "view" step a rep would reach by
hand-walking the Miller columns to that same link — not a second,
parallel selection path. `restoreDrillState` now also calls
`writeDrillStateToUrl()` once the link is found, so a tile-driven landing
survives a refresh the same way a hand-drilled one already does.

## Header/search parity with the Pages tab (product-owner mockup)

Two related, product-owner-confirmed visual-parity fixes, both aimed at the
same underlying gap: `gtmReadoutsOverview`'s layout was built independently
of `gtmPageBrowser`'s and had drifted from it.

**Outer padding/background (`.ov` vs. `.pb`):** `gtmReadoutsOverview.css`'s
`.ov` rule is now a byte-for-byte match of `gtmPageBrowser.css`'s `.pb`
rule (`padding: 1rem clamp(.75rem, 2vw, 1.25rem) 1.5rem; background:
#f3f3f3; min-height: 100%;`) — previously `.ov` was `padding: 0.75rem;`
with no background, which is what produced the visible content shift a
rep saw switching between the Pages and Assessments tabs. Keep these two
rules in sync by hand going forward (a comment in each file cross-references
the other); there is no shared base class today.

**Trail-mode header subtitle:** matching the product owner's mockup,
`gtmReadoutsOverview`'s `c-gtm-page-header` now passes a `meta` prop (the
same slot `gtmPageBrowser` already uses for "Search Account → Contact →
Link to find one you sent") reading **"Search Account → Contact →
Assessment to view the assessment submitted"** — but only while the "By
Account/Contact" trail mode is active (`headerMeta` getter, gated on
`isAccountMode`). The flat "All Assessments" grid mode keeps its existing,
subtitle-less header, since it is a search+grid rather than a drill-down
trail. The trail's own Account-search input
(`gtmReadoutAccountFinder`'s `.raf-head`) is structurally identical to
`gtmRepLinkFinder`'s own `.rlf-head` (same `lightning-record-picker`,
same wrapper classes/layout, `raf-` prefixed instead of `rlf-` only to
avoid a class-name collision if both ever render on the same page), so it
already matches Pages' Account-search treatment pixel-for-pixel without
further changes.

**Known side effect, accepted by the product owner (do not "fix" by making
the subtitle constant):** because `headerMeta` is blank in "All Assessments"
mode and non-blank in "By Account or Contact" mode, the header card is one
line shorter in "All Assessments," and the header icon visibly shifts
vertical position when a rep toggles between modes. An earlier commit on
this branch made `headerMeta` return the subtitle text unconditionally in
both modes specifically to eliminate that shift — the product owner then
reversed that call directly: the subtitle must not appear in "All
Assessments" at all, and the icon-shift is an accepted cosmetic side effect,
not a defect to re-solve with a different approach (e.g. a fixed min-height)
right now.

The same conditional treatment now applies to the Pages tab's
`gtmPageBrowser`/`gtmRepLinkFinder`: `gtmPageBrowser`'s own default-mode
`headerMeta` ("Search Account → Contact → Link to find one you sent") only
covers the case where `gtmRepLinkFinder` isn't in story or link mode, but
that default case spans *both* of `gtmRepLinkFinder`'s own internal
"All Pages"/"By Account or Contact" sub-modes — `gtmPageBrowser` had no way
to distinguish them. `gtmRepLinkFinder` now dispatches a `modechange`
CustomEvent (`detail`: `'all'` or `'account'`) any time its own `rlfMode`
changes (the two toggle handlers, tile selection, URL-restore, and once on
initial `connectedCallback` so the parent learns the starting mode too).
`gtmPageBrowser` listens via `onmodechange` on the `<c-gtm-rep-link-finder>`
tag, stores it in `linkFinderMode` (`@track`, defaulting to `'account'` to
match `gtmRepLinkFinder`'s own default), and blanks its subtitle when
`linkFinderMode === 'all'`. This is a minimal, single-purpose child→parent
signal — not a general mode-sync mechanism — added only because
`gtmPageBrowser` otherwise treats `gtmRepLinkFinder` as an opaque child.

## Pages-tab browse-mode toggle (issue-gtm-assessments-account-contact-trail follow-up)

Product-owner live-screenshot comparison found the Pages tab's "nothing
picked yet" screen still showed the `.rlf-empty-state` message and the
`.rlf-tiles-section` tile grid together, unconditionally, next to the
always-visible `.rlf-head` Account search bar — unlike the Assessments tab
(above), which already gates its two browsing modes ("All Assessments" /
"By Account or Contact") behind an explicit toggle. `gtmRepLinkFinder` now
carries the identical toggle, same two-mode split, same visual treatment:

- **"By Account or Contact"** (`rlfMode = 'account'`, the default): shows only
  the `.rlf-head` search bar + `.rlf-empty-state` message + the (unchanged)
  Miller-columns drill-down once an account is picked. This is the pre-
  existing, always-on behavior the toggle is layered on top of, so a rep
  who never touches the toggle (or an existing bookmarked/shared link with
  no `c__rlfMode` param) sees exactly what they saw before this change.
  Deliberately the opposite default from `gtmReadoutsOverview`'s own
  `browseMode` ('all' there) for that same backward-compatibility reason.
- **"All Pages"** (`rlfMode = 'all'`): shows only the `.rlf-tiles-section`
  tile grid; the `.rlf-head` search bar and `.rlf-empty-state` message are
  hidden entirely (`showHead` getter).

The toggle itself (`.rlf-mode-toggle`/`.rlf-toggle-btn`/
`.rlf-toggle-btn--active`) is a byte-for-byte duplicate of
`gtmReadoutsOverview.css`'s `.ov-mode-toggle`/`.ov-toggle-btn`/
`.ov-toggle-btn--active` rules under `rlf-`-prefixed class names — not
extracted into a shared file, since this codebase has no established
cross-LWC shared-CSS import mechanism today (see the `.ov`/`.pb`
"keep in sync by hand" precedent above, same reasoning applies here). Keep
these three rules in sync by hand if either changes.

It only renders on the very first "nothing picked yet" (`isAccountStep`)
screen — once a rep drills into Contact/Link/View, the toggle disappears
and `.rlf-head`/the crumb trail resume their existing, always-visible
behavior unchanged, mirroring how the Assessments tab's own toggle behaves
once `showWorkspace` is true (both toggles get out of the way once there is
real content to look at instead of a browsing choice to make).

Mode selection extends the existing `c__rlfAccountId`/`c__rlfContactId`/
`c__rlfLinkId` URL-state contract with one more param, `c__rlfMode`
(`'all'` when tile-grid mode is active; omitted, not written as
`'account'`, when it isn't — same "only write the non-default value"
convention `gtmReadoutsOverview`'s own `c__browseMode` uses, just with the
opposite default value per the note above), so a refresh restores both the
drill depth and which mode a rep had selected.

## "See Assessments" button icon (regression fix)

`gtmOverview.html`'s "See Assessments" action button carried
`icon-name="utility:assessment"`, which is not a real SLDS utility icon —
it silently rendered no icon at all rather than erroring, so this went
unnoticed through an earlier round that flagged but never fixed it. Now set
to `icon-name="utility:preview"`, the same icon already used elsewhere in
this codebase (e.g. `gtmRepLinkFinder`'s "Preview the link"/"View readout"
buttons) for the same "go look at this" meaning, confirmed rendering there
today.

## Contact-first search — investigated, not implemented (issue-gtm-assessments-account-contact-trail follow-up)

Product owner asked whether a rep can genuinely search by Contact, not just
drill down Account-first. As of this branch, both trails (`gtmReadoutAccountFinder`
on Assessments, `gtmRepLinkFinder`'s Miller columns on Pages) only support
Account-first entry: a `lightning-record-picker` on `Account`, then a list of
that Account's Contacts to pick from. There is no way today to type a
Contact's name directly and skip straight to their assessments/links.

**Apex/data-model layer is straightforward to add:** both
`GTM_Assessment_Request__c` and `GTM_Saved_Configuration__c` already carry
direct `Contact__c` lookup fields (already FLS-granted), so a
`getRequestsForContact(Id contactId)` (readouts) / a Contact-first variant of
`getContactsWithLinks` (links) would each be a small, mechanical variant of
the existing Account-scoped methods — same sharing/no-DML/cacheable shape,
just `WHERE Contact__c = :contactId` instead of joining through `Account__c`.
This part is not the blocker.

**UI/UX for a second, parallel search field is not established anywhere in
this codebase and was not guessed at.** Both trails' header rows
(`.raf-head-row` / `.rlf-head`) are built around exactly one
`lightning-record-picker` (Account) plus one Miller-columns drill-down keyed
off that single starting point; there is no existing pattern in the app for
two parallel entry-point search fields feeding the same result view,
and adding one raises open questions this issue's scope doesn't answer
unilaterally: layout (stacked vs. side-by-side, in the same `-head-row` or a
new one), what a picked Contact does to the Account field's own state (clear
it? auto-populate it read-only from the Contact's own Account?), how the
crumb trail should represent a Contact-first entry (skip the Account crumb
entirely, or synthesize one from the Contact's Account?), and whether this
needs its own URL-state param (`c__rafContactSearch`-style) alongside the
existing `c__raf*`/`c__rlf*` drill-state params. Doing this identically
across two independent components (Assessments' `gtmReadoutAccountFinder`
and Pages' `gtmRepLinkFinder`) doubles that surface.

**Decision:** stopped here per this issue's own instructions rather than
guessing at UX for two components at once. Recommend a follow-up issue,
scoped explicitly to the UX question above (ideally with a product-owner
mockup, matching how the existing toggle/tile-grid additions on this same
branch were each driven by a specific mockup or live-review note) before
building the Apex + LWC change described above.
