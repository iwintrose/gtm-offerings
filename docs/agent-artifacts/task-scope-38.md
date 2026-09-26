# TASK SCOPE — ISSUE #38

## 1. Requirements Breakdown

- **Target Objective:** Extend `GtmSetupChecklistController`'s existing derive-only
  Setup-checklist detector catalogue with two new rows that surface, inside the
  app's own Setup UI, two org-configuration gaps that tonight (2026-09-26) cost
  hours to diagnose in `gtm-staging` because they were only visible in a debug
  log / a raw Apex test failure, never in the app:
  1. **Agentforce Agent API configured** — `GTM_Agent_Settings__c.Agentforce_Agent_Id__c`
     is non-blank, and (ideally) resolves to a real `BotDefinition` row.
  2. **No known SDO demo-org automation blocking Case** — the specific
     `SDO Service - Case - On Create` (`ApiName SDO_Service_Case_Creation`) flow
     is absent or inactive, plus a documented, evidence-based recommendation on
     whether any *other* active "SDO Service" flow deserves the same treatment.

  Both rows must follow the class's existing pattern exactly — own try/catch
  per detector (isolation via the `forceFailKey` test seam), re-detect from
  live org state every call, no persisted flags, no DML/callouts — plus Apex
  tests in the existing `GtmSetupChecklistControllerTest.cls`, plus updates to
  `docs/runbooks/fresh-org-deploy.md` §6 items 15–16 (already drafted as
  uncommitted, uncommitted-on-`main` changes tonight — see "Pre-existing
  uncommitted state on `main`" below) to point at the new in-app items, and to
  `docs/architecture/guided-setup.md` §6's item-catalogue table (this repo's
  contract-first rule, `CLAUDE.md` §4). **No LWC template/markup change is
  required** to render either new row — `gtmSetupChecklist.html`/`.js` render
  every catalogue row generically off the `SetupItem` DTO's fields (tier,
  status, detail, actionType, linkKind) with no per-key branching for display.
  **One LWC *data* change is required, though**, and it is easy to miss — see
  finding (d) below.

  **Two things a prior pass (or this issue's own text) could lead an
  implementer to get wrong, verified against the literal code, not guessed:**

  **(a) `STATUS_TODO`/`STATUS_BLOCKED` cannot legally sit on an `OPTIONAL` or
  `INFO` tier row.** `GtmSetupChecklistControllerTest.optionalAndInfoRowsAreNeverCountedOrTodo`
  iterates every item in the *whole* catalogue (not a fixed key list, so it
  automatically covers new detectors) and asserts:
  ```
  if (i.tier == 'OPTIONAL' || i.tier == 'INFO') {
      Assert.areNotEqual('TODO', i.status, i.key);
      Assert.areNotEqual('BLOCKED', i.status, i.key);
  }
  ```
  The issue's own status spec for both new detectors explicitly calls for
  `TODO` (and `BLOCKED`/`UNKNOWN`) — so **neither new detector may be tier
  `OPTIONAL` or `INFO`**, even though the closest analog in the file today
  (`ai_keys`, "GUS chat provider key", the same "opt-in Agentforce" spirit) is
  `OPTIONAL` with `STATUS_NOT_SET` for the unset case. `TIER_RECOMMENDED` is
  the fit that satisfies both the issue's spec and this existing test
  unmodified: it is the tier every other "query org state, TODO if unmet"
  detector already uses (`triage_queue`, `manager_on_reps`, `scheduled_jobs`,
  `site_members`, `reps_assigned`), it is excluded from `requiredTotal`/
  `requiredDone` (so it never blocks an admin's "required" completion
  percentage for a feature that is admittedly inactive/opt-in today), and —
  concretely — it means the hardcoded `Assert.areEqual(8, c.requiredTotal)`
  (in `blankOrgReturnsWholeCatalogueWithinBudget`) and `Assert.areEqual(8,
  c2.requiredTotal)` (in `aFailingDetectorIsIsolatedToItsOwnRow`) do **not**
  need to change. **Recommend `TIER_RECOMMENDED` for both new detectors**;
  this is a real design choice for the Architect to confirm, not something I
  changed, but going `REQUIRED` instead is the one choice that forces both of
  those hardcoded counts to be bumped and should be a deliberate call, not an
  oversight.

  **(b) `STATUS_BLOCKED` in this file always means "another checklist row
  isn't met yet", carried via a populated `blockedBy` list** (see
  `detectOfferingPublished`, `detectOfferingListed`, `detectIndustry`,
  `detectSiteActive`'s "no site exists" branch — every call to the `blocked()`
  helper passes a `blockedBy` key list, or explicitly `null` for a genuinely
  external blocker). The issue's "Agentforce Agent ID set but doesn't resolve
  to a real `BotDefinition`" case is a *dangling reference*, not an unmet
  dependency on another checklist row — there is no `blockedBy` candidate for
  it. **Recommend `STATUS_UNKNOWN`** for that specific sub-case (it already
  carries the right meaning in this file — "could not be verified, needs a
  human to check" — see `detectGuest`'s and `detectSiteActive`'s `UNKNOWN`
  branches for the pattern) rather than introducing a `BLOCKED` row with an
  empty `blockedBy`, which would be a new, undocumented shape for that field.
  The issue itself offers "BLOCKED/UNKNOWN" as alternatives, so this is a
  recommendation to pick one consistent with existing precedent, not a
  contradiction to resolve.

  **(c) The SDO-flow detector cannot be meaningfully unit-tested end to end.**
  `FlowDefinitionView` reflects real, deployed org metadata that Apex tests
  cannot insert or fabricate — a fresh/CI/scratch org will not carry the SDO
  demo-org flow bundle at all, so the "absent → DONE" branch is the only one
  exercisable by an automated test in most run contexts (this matches the
  issue's own spec: "Status DONE if absent or inactive"). The "present and
  active → TODO" branch can only be genuinely proven against a live org that
  actually carries the bundle (`gtm-staging`, tonight, before the fix — see
  the live evidence below) or via `forceFailKey`-style isolation proof of the
  *failure* path, not the true-positive path. Flag this to QA as a manual/
  live-org verification note, not a gap the Developer needs to engineer around
  — the class's own established pattern for equally uncontrollable org state
  (see `guestAndSiteRowsAreNeverFalselyDoneWithoutASite`'s and
  `unassignedAdminOffersAssignToMeAction`'s "if status == X then assert Y else
  assert Z" conditionals) is exactly this kind of defensive, org-state-aware
  assertion, not a mock.

  **(d) The LWC's Settings-tab deep link for a `sectionLink()`-based row is
  driven by a second, client-side, hardcoded key→section map, not by the
  server's `navState.sectionId` field alone.** `gtmSetupChecklist.js`'s
  `followLink()`:
  ```js
  followLink(detail) {
      const sectionId = SETTINGS_SECTION_BY_KEY[detail.key];
      if (sectionId) {
          this.dispatchEvent(new CustomEvent('selectsection', { detail: { sectionId } }));
          return;
      }
      if (detail.linkKind === 'NAV_ITEM' && detail.navApiName) { ... }
      else if (detail.linkKind === 'SETUP_PATH' && detail.setupPath) { ... }
  }
  ```
  `SETTINGS_SECTION_BY_KEY` (top of the same file) is a hardcoded
  `{ analytics_digest: 'analytics-notifications', ai_keys: 'claude-gus',
  approval_routing: 'approval-routing' }` map. The Apex `sectionLink()` helper
  deliberately sets `linkKind = LINK_NONE` (not `NAV_ITEM`/`SETUP_PATH`), so if
  the Agentforce detector uses `sectionLink(i, 'claude-gus', ...)` to point at
  the existing GUS Configuration section (per the issue's own instruction,
  confirmed correct below) **and its new key is not also added to this JS
  map**, clicking the row's link silently does nothing — no error, no
  navigation, nothing in `linkKind` for the template to fall back on. This is
  a one-line addition (`agentforce_agent: 'claude-gus'`, or whatever key name
  is chosen), but it is a real, silent, easy-to-miss gap in the existing
  contract that the Developer must not skip. The `settingsSectionRowsCarryTheirSectionId`
  Apex test only proves the *server* DTO carries the right `navState.sectionId`
  — it does not and cannot catch this client-side map being out of sync,
  since that map lives only in the LWC, not in Apex. **This is the one LWC
  change this task actually needs.**

- **System Component Impacted:** Apex (`GtmSetupChecklistController.cls` +
  `GtmSetupChecklistControllerTest.cls`), one small LWC data-map addition
  (`gtmSetupChecklist.js`'s `SETTINGS_SECTION_BY_KEY`, only if the Agentforce
  detector uses `sectionLink()` per the recommendation above — no template
  changes), and documentation (`docs/runbooks/fresh-org-deploy.md`,
  `docs/architecture/guided-setup.md`). No new Apex classes, no new LWC
  bundles, no schema changes, no permission-set changes (both fields/objects
  read here are already granted — see checklist below).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO.** `GtmSetupChecklistController` is not
  a `GtmAgentToolSurface`/`GtmAppTool` implementation and is never called from
  GUS's chat surfaces — it backs the admin-only Setup checklist UI
  (`gtmSetupChecklist` LWC) exclusively. The AGENTS.md §1 GUS-Tool-Surface
  zero-DML rule does not apply here as a *named* rule, but this class carries
  its own, equally strict "Derive-only... NO DML, NO callouts" contract in its
  header — both new detectors must be pure SOQL/schema/custom-setting reads,
  same as every existing one.
- [ ] Altering Custom Metadata? **NO.** Neither detector reads or writes any
  `customMetadata`; nothing under `instrument/<offering-key>/` is touched.
- [ ] Introducing database fields? **NO.** Both detectors read fields/objects
  that already exist and are already permission-set-granted:
  `GTM_Agent_Settings__c.Agentforce_Agent_Id__c` is already granted
  `readable`/`editable` on `GTM_Offering_Admin` (confirmed:
  `force-app/main/default/permissionsets/GTM_Offering_Admin.permissionset-meta.xml`
  lines 400–403), and `Network`/`FlowDefinitionView`/`BotDefinition` are
  standard objects already queried elsewhere in this same class (`Network`) or
  independently confirmed queryable below (`BotDefinition`,
  `FlowDefinitionView`) without any new permission-set grant. If access to
  `BotDefinition` or `FlowDefinitionView` turns out to be restricted for a
  `GTM_Offering_Admin`-only (non-System-Administrator-profile) user in some
  org, the existing `try/catch → UNKNOWN` pattern this class already uses for
  `Network`/`Site` (`detectGuest`, `detectSiteActive`'s `networksReadable`
  flag) is the precedent to reuse, not a new permission-set grant.

## 3. Plan Acceptance Criteria

- **Success Metric:** Two new rows appear in the Setup checklist's existing
  UI (`gtmSetupChecklist`) with `tier = RECOMMENDED` (see the tier finding
  above; confirm with Architect if a different tier is deliberately chosen,
  and update the two hardcoded `requiredTotal` counts in
  `GtmSetupChecklistControllerTest.cls` if so), correct status/detail text
  following the issue's spec, and a working `LINK` action: the Agentforce row
  links to the existing "GUS Configuration" section (`sectionLink(i,
  'claude-gus', ...)`, confirmed below to be the real, live location of the
  Agentforce Agent ID / My Domain URL / Consumer Key fields today), and the
  SDO-flow row links to Setup → Flows (a new `SETUP_PATHS` entry, e.g.
  `'flows' => '/lightning/setup/Flows/home'`, is needed — no such entry exists
  today). Both detectors are isolated by their own try/catch per the class's
  existing `forceFailKey`-provable pattern. `docs/runbooks/fresh-org-deploy.md`
  §6 items 15–16 and `docs/architecture/guided-setup.md` §6's item-catalogue
  table both reference the new in-app items, per item 12's existing
  convention. `npm run test` (Jest) and a targeted Apex run both pass with no
  regression to any existing assertion (in particular
  `optionalAndInfoRowsAreNeverCountedOrTodo`, `blankOrgReturnsWholeCatalogueWithinBudget`'s
  `used <= 30` SOQL budget, and `settingsSectionRowsCarryTheirSectionId`).
- **Target Test Target:** `force-app/main/default/classes/GtmSetupChecklistControllerTest.cls`
  — add new test methods following the file's existing conventions (a
  `forceFailKey`-based isolation test per new detector, matching
  `aFailingDetectorIsIsolatedToItsOwnRow`; add both new keys to `ALWAYS_KEYS`
  since neither is a conditional/helper row like `content_access`; extend
  `settingsSectionRowsCarryTheirSectionId` if the Agentforce row uses
  `sectionLink()`). Run via `sf apex run test --class-names
  GtmSetupChecklistControllerTest --target-org gtm-staging` per this repo's
  QA convention (never `RunLocalTests`, never a real deploy from an agent).
  Jest: no new Jest spec is expected unless `gtmSetupChecklist.js`'s
  `SETTINGS_SECTION_BY_KEY` map addition is judged worth a regression test in
  `lwc/gtmSetupChecklist/__tests__/gtmSetupChecklist.test.js` (recommended,
  small, given finding (d) above is exactly the kind of silent gap a one-line
  Jest assertion would catch for good).

---

## Evidence log (every claim above, independently re-verified this session)

**Class header confirms the derive-only contract and test seam** (`force-app/main/default/classes/GtmSetupChecklistController.cls` lines 1–14, 82):
```
* Derive-only: nothing is stored. Every call re-detects from live org state
* (SOQL, schema and custom-setting reads only). NO DML, NO callouts.
*
* Each detector runs inside its own try/catch, so one failing or unreadable
* check yields status UNKNOWN for that row alone and never an exception, and
* never a false DONE. No org id, username, or secret ever appears in an item.
...
    @TestVisible private static String forceFailKey;
```
`getChecklist()` (lines 228–241) wraps each `detect(s, c)` call in its own
try/catch, checking `forceFailKey` first — this is the isolation mechanism
`aFailingDetectorIsIsolatedToItsOwnRow` proves.

**`GTM_Agent_Settings__c.Agentforce_Agent_Id__c` confirmed the correct field**
(`GtmAgentSettingsController.cls` lines 47, 60, 79, 99, 144) — it is read by
`getAgentSettings()`, written by `setAgentSettings()`, is a non-secret 50-char
Text field ("Agent ID / My Domain URL / consumer key are identifiers, not
secrets" per the class's own comment), and its field metadata
(`force-app/main/default/objects/GTM_Agent_Settings__c/fields/Agentforce_Agent_Id__c.field-meta.xml`)
confirms: `<description>ID of the published Agentforce agent for the upcoming
Agent API integration. Saved but inactive: GUS does not call Agentforce yet.
Not a secret.</description>`.

**The GUS chat-provider-key Settings tab, confirmed the real location per
fresh-org-deploy.md item 12's precedent.** `gtmOfferingsSettings.js` line 37:
`{ id: 'claude-gus', label: 'GUS Configuration' }`; its comment (lines 18–19):
`"ADR-0010; id 'claude-gus' retained for the deep-link contract) exposes
GTM_Agent_Settings__c through gtmOfferingsSettingsAgent."` The
`gtmOfferingsSettingsAgent.html` template (confirmed by reading it in full)
already renders `Agent ID` / `My Domain URL` / `Consumer Key` inputs when
`Agentforce` is the selected chat provider — this is the real, live location
the new detector's `LINK` must point at, exactly as the issue instructed
("wherever the existing GUS chat-provider-key field lives").

**`BotDefinition` confirmed queryable, live, on `gtm-staging`** — not assumed:
```
$ sf data query --target-org gtm-staging --query "SELECT Id, DeveloperName, MasterLabel, Type, IsDeleted FROM BotDefinition LIMIT 10"
{
  "records": [
    { "Id": "0XxgK000002MowHSAS", "DeveloperName": "GTM_Configurator_Assistant",
      "MasterLabel": "GTM Configurator Assistant", "Type": "ExternalCopilot", "IsDeleted": false }
  ],
  "totalSize": 1
}
```
And the org-default `GTM_Agent_Settings__c` row's `Agentforce_Agent_Id__c`
value matches this exact `BotDefinition.Id` — confirming both that tonight's
fix (item 1 in the issue) is live now, and that the "resolves to a real
BotDefinition row" detection path is real and exercisable, not speculative:
```
$ sf data query --target-org gtm-staging --query "SELECT Agentforce_Agent_Id__c, Agentforce_My_Domain_URL__c, Agentforce_Client_Id__c, Chat_Provider__c FROM GTM_Agent_Settings__c WHERE SetupOwnerId = '<org-default-setup-owner-id>'"
{ "records": [ { "Agentforce_Agent_Id__c": "0XxgK000002MowHSAS",
    "Agentforce_My_Domain_URL__c": "<redacted -- org-specific My Domain URL>",
    "Agentforce_Client_Id__c": null, "Chat_Provider__c": "Agentforce" } ] }
```

**The specific SDO flow is confirmed deactivated on `gtm-staging` right now**
(matching the issue's "fixed tonight" claim, independently re-verified, not
trusted):
```
$ sf data query --target-org gtm-staging --query "SELECT Label, ApiName, IsActive, TriggerType, RecordTriggerType, TriggerObjectOrEventLabel FROM FlowDefinitionView WHERE Label = 'SDO Service - Case - On Create'"
{ "records": [ { "Label": "SDO Service - Case - On Create",
    "ApiName": "SDO_Service_Case_Creation", "IsActive": false,
    "TriggerType": "RecordAfterSave", "RecordTriggerType": "Create",
    "TriggerObjectOrEventLabel": "Case" } ] }
```

**A real recommendation on "does more than one flow deserve a checklist
entry" — based on a live full audit, not a guess.** Querying every `%SDO%`
flow on `gtm-staging` (34 rows total) and reading each one's
`TriggerObjectOrEventLabel`/`RecordTriggerType`/`IsActive`:

- **No Contact- or Task-triggered SDO flow exists at all** in this org today
  (the 34 rows' trigger objects are: Case, Agent Work, Asset, Email Message,
  Lead, Messaging Session, Messaging User, Voice Call, Incident, or `null`
  for non-record-triggered/autolaunched flows) — so the issue's explicit
  Contact/Task concern is a non-issue *in this org, today*; nothing to add a
  checklist row for there.
- **Two other Case-triggered, active, record-change flows exist** that were
  not named in the issue and are worth flagging to the Architect as
  candidates for the *same kind* of scrutiny, though **not** confirmed broken
  (that would need either a live test Case insert or retrieving+reading their
  flow definition's input-variable metadata, neither of which is BA-appropriate
  investigation — this is a "worth a look," not a "confirmed second bug"):
  - `SDO_Service_Case_Status_Updated` ("SDO Service - Case - Status Updated"),
    `IsActive: true`, `RecordTriggerType: CreateAndUpdate` on Case — this
    **does** fire on Case creation (not just update), so if it carries the
    same "required input variable with no default" foot-gun as
    `SDO_Service_Case_Creation` did, it would produce the identical
    `CANNOT_EXECUTE_FLOW_TRIGGER` symptom on every Case insert, undetected by
    a checklist that only names the one already-found flow.
  - `SDO_Service_Case_Wrap_Up_Classification` ("SDO Service - Case Wrap-Up
    Classification"), `IsActive: true`, `RecordTriggerType: Update` only — so
    it cannot block a Case *insert* (`GtmReadoutController.fileReviewCase` is
    a create), lower risk, named here only for completeness.
  - Several other active `SDO Service - Case - *` entries (`Routing`,
    `SetCasePrediction`, `Create Case for Channel`, `Set Default Entitlement
    on Case`) show `TriggerType: null` in `FlowDefinitionView` — these are
    autolaunched/subflows invoked *from* other automation, not directly
    record-triggered on Case DML, so they are not a plausible cause of
    `fileReviewCase`'s specific symptom and are out of scope for this ticket.
  - **Recommendation:** keep this ticket's SDO detector scoped to the one
    confirmed flow the issue names (`SDO_Service_Case_Creation`), exactly as
    the issue's own "out of scope" section asks ("not feasible to generalize;
    this is specifically about the known SDO bundle") — but log
    `SDO_Service_Case_Status_Updated` as a named follow-up candidate (a
    one-line addition to the same detector's query, or its own row, once
    someone confirms live whether it shares the same defect) rather than
    silently dropping it. This is a genuine "worth a decision" item, not
    something to fold into this ticket's build silently or to leave
    completely unmentioned.

**Existing detectors most similar in shape, to build from directly (not
guessed):**
- **"Is a custom setting/field populated" shape → `detectAiKeys`**
  (`GtmSetupChecklistController.cls` lines 703–712): reads
  `GtmAgentSettingsController.getAgentSettings()`, checks a boolean-ish
  condition, calls `sectionLink(i, 'claude-gus', 'Open GUS settings')`. The
  Agentforce detector should follow this exact shape for its "is
  `Agentforce_Agent_Id__c` set" half, reusing the same `sectionLink('claude-gus', ...)`
  call (see finding (d) above for the one thing this reuse requires on the
  LWC side).
- **"Query some org state and report a boolean-ish status" shape →
  `detectQueue`** (lines 614–624): `setupLink(i, 'queues', 'Open Queues')`,
  one SOQL query, `done()`/`i.status = STATUS_TODO` branch. The SDO-flow
  detector should follow this shape — a `setupLink` to a new `'flows'`
  `SETUP_PATHS` entry, one `FlowDefinitionView` query, `done()` if
  absent/inactive, `STATUS_TODO` with the exact symptom text (per the issue's
  own instruction: "with a clear explanation of the exact symptom this
  causes") if present and active.

## Pre-existing uncommitted state on `main` (not part of this task, noted for
awareness only)

`git status` at the start of this scoping pass showed three files already
modified, uncommitted, on `main`: `docs/runbooks/fresh-org-deploy.md` (the
items 15–16 rows this issue's own Context section describes as "documented…
tonight" — confirmed via `git diff`, these are exactly items 15 and 16 already
quoted above) and two permission-set files
(`GTM_Offering_Admin.permissionset-meta.xml`, `GTM_Offering_User.permissionset-meta.xml`)
granting FLS on `Case.Readout__c` — a different, unrelated fix from the same
session (a review-Case comment-thread field-visibility gap, per the inline
comments in the diff). **None of this is part of issue #38's scope** — it
predates this BA pass, is not something I created or modified, and should be
left exactly as-is; it is called out here only so the Architect/Developer
don't mistake it for scope creep introduced by this ticket, and don't lose
track of it as separate, already-in-flight work needing its own commit.
