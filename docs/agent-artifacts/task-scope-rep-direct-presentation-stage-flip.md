# TASK SCOPE — ISSUE #rep-direct-presentation-stage-flip

## 1. Requirements Breakdown

- **Target Objective:** Stop `GtmAssessmentRequestController.postInsertBestEffort()`
  from unconditionally overwriting `GTM_Saved_Configuration__c.Presentation_Stage__c`
  to `'Assessment'` on every real `submitRequest()` call, so that a `Rep_Direct`
  record — which is documented and tested elsewhere in this codebase to be
  permanent/pageless for its entire life — actually stays `Rep_Direct` after a
  prospect (or the rep, pre-filling) submits a real assessment against it. A
  non-`Rep_Direct` config (e.g. `Sent`) must continue to advance to `Assessment`
  exactly as it does today — that is legitimate, unrelated behavior and is not
  to be touched by this fix.
- **System Component Impacted:** Apex (`GtmAssessmentRequestController.cls`,
  specifically `recordAssessmentRequest()`/`postInsertBestEffort()`, plus the
  `ConfigContext`/`resolveConfigContext()` plumbing that feeds it); LWC
  (`gtmConfigurator.js`'s `isRepDirect` gate is the visible symptom of the bug
  but is not itself the root cause — it reads `presentationStage` correctly,
  the record it reads is what's wrong). No YAML instrument, no Experience
  Cloud route/metadata, no Custom Metadata changes.

**Confirmed root cause — read, not assumed.** `force-app/main/default/classes/GtmAssessmentRequestController.cls`
lines 967-982, exactly as reported:

```
private static void postInsertBestEffort(
    GTM_Assessment_Request__c req, Id cfgId, ConfigContext ctx,
    String cleanName, RequestInput input
) {
    try {
        // Advance the linked config to Assessment stage
        if (cfgId != null) {
            try {
                SObject cfgUpdate = Schema.getGlobalDescribe().get('GTM_Saved_Configuration__c').newSObject();
                cfgUpdate.put('Id', cfgId);
                cfgUpdate.put('Presentation_Stage__c', 'Assessment');
                update cfgUpdate;
            } catch (Exception ex) { ... }
        }
```

Called unconditionally from `recordAssessmentRequest()` (line 963) after every
successful `submitRequest()` insert, for every offering, every path
(legacy Migration-Accelerator pipeline and the generic
`GTM_Instrument_Definition__c` path alike — `isGenericPath` never gates this
call). No read of the config's current stage happens anywhere in this method
or its caller today.

**Confirmed symptom in `gtmConfigurator.js`.** Line 816:
`this.isRepDirect = rec.presentationStage === 'Rep_Direct';` — re-derived from
the server on every page load (`loadSavedConfiguration()`), strict equality,
no memoization across visits. Downstream: `showCustomizeButton` (932-937),
`showAssistant` (949-951), `showChapterBody` (1194-1196: `!this.showPublishedGate
&& !this.isUnconfigured && !this.isRepDirect`), and `showRepDirectQuestionnaire`
(1211-1220: requires `this.isRepDirect`). Once `isRepDirect` is false,
`showChapterBody` is true and `showRepDirectQuestionnaire` is false — the page
falls through to branded-chapter rendering via `getPageLayout` (line 423) with
`CHAPTER_DEFAULTS` (imported from `c/gtmConfiguratorCopy`, used at line 504) as
the fallback when no content is published.

**Confirmed the fallback is live, not theoretical, for Migration Accelerator
today.** Queried `gtm-staging` directly tonight:

```
$ sf data query --target-org gtm-staging --query \
  "SELECT COUNT(Id) cnt FROM GTM_Page_Section__c WHERE Offering_Key__c = 'migration-accelerator' \
   AND Template_Type__c = 'configurator' AND Status__c = 'Published'"
┌─────┐
│ CNT │
├─────┤
│ 0   │
└─────┘

$ sf data query --target-org gtm-staging --query \
  "SELECT Status__c, COUNT(Id) cnt FROM GTM_Page_Section__c WHERE Offering_Key__c = 'migration-accelerator' \
   AND Template_Type__c = 'configurator' GROUP BY Status__c"
Total number of records retrieved: 0.
```

Zero rows at all (Published or otherwise) for `migration-accelerator`/
`configurator`. So a `Rep_Direct` record that gets flipped to `Assessment` and
is later re-visited would render 100% hardcoded `CHAPTER_DEFAULTS` content —
exactly the half-finished/unpublished-content exposure this whole area of
work exists to prevent.

**Confirmed this has already happened — live reproduction on `gtm-staging`,
not a hypothetical.** Queried for any `GTM_Saved_Configuration__c` currently
at `Presentation_Stage__c = 'Assessment'`:

```
$ sf data query --target-org gtm-staging --query \
  "SELECT Id, Name, Presentation_Stage__c, Company__c, Industry__c, Config_Payload__c, \
   Generated_URL__c, Contact__c, Account__c, Opportunity__c, CreatedDate \
   FROM GTM_Saved_Configuration__c WHERE Presentation_Stage__c = 'Assessment'"

ID                  NAME     PRESENTATION_STAGE__C  COMPANY__C                              INDUSTRY__C  CONFIG_PAYLOAD__C  GENERATED_URL__C
a1ggK000001l04DQAQ  SC-3829  Assessment              [DEMO] Brightfield Financial Partners  null         null               null
a1ggK000001l04EQAQ  SC-3830  Assessment              [DEMO] Cascade Regional Health          null         null               null
a1ggK000001l04FQAQ  SC-3831  Assessment              [DEMO] Ironclad Freight & Logistics     null         null               null
a1ggK000001l04GQAQ  SC-3832  Assessment              [DEMO] Helix BioSciences                null         null               null
a1ggK000001l04HQAQ  SC-3833  Assessment              [DEMO] Prime Stream Media               null         null               null
a1ggK000001l04IQAQ  SC-3834  Assessment              [DEMO] Civic Works Authority            null         null               null
Total number of records retrieved: 6.
```

All 6 have `Config_Payload__c = null`, `Generated_URL__c = null`,
`Industry__c = null` — exactly the shape `createRepDirectAssessment()`
produces (`GtmSavedConfigurationController.cls` line ~310-314: only
`Contact__c`/`Offering__c`/`Account__c`/`Presentation_Stage__c` are set; no
`Config_Payload__c`, no `Generated_URL__c`, no `Industry__c`) and never had a
`generateRepDirectShareLink()` call (which would have populated
`Generated_URL__c`). Confirmed `Is_Synthetic__c = true` on all 6, and each has
exactly one matching `GTM_Assessment_Request__c` created at the identical
timestamp:

```
$ sf data query --target-org gtm-staging --query \
  "SELECT Id, Name, Saved_Configuration__c, Offering_Key__c, Status__c, CreatedDate \
   FROM GTM_Assessment_Request__c WHERE Saved_Configuration__c IN (...)"

NAME     SAVED_CONFIGURATION__C  OFFERING_KEY__C         STATUS__C   CREATEDDATE
AR-4358  a1ggK000001l04DQAQ      migration-accelerator   New         2026-09-25T03:24:31.000+0000
AR-4360  a1ggK000001l04EQAQ      migration-accelerator   New         2026-09-25T03:24:31.000+0000
AR-4362  a1ggK000001l04FQAQ      test-offering           Completed  2026-09-25T03:24:31.000+0000
AR-4364  a1ggK000001l04GQAQ      migration-accelerator   New        2026-09-25T03:24:31.000+0000
AR-4366  a1ggK000001l04HQAQ      test-offering           Contacted  2026-09-25T03:24:31.000+0000
AR-4368  a1ggK000001l04IQAQ      migration-accelerator   Completed  2026-09-25T03:24:31.000+0000
```

This is direct, live proof that a prior synthetic-seed run already exercised
`createRepDirectAssessment()` → `submitRequest()` and this exact bug silently
flipped all 6 of those configs out of `Rep_Direct` — confirming the
`demo-seed-integrity-rebuild` issue's Architect-review finding end to end, not
just by code inspection.

**No evidence of REAL (non-synthetic) data corruption on `gtm-staging`.**
Same query restricted to `Is_Synthetic__c = false OR Is_Synthetic__c = null`
at `Presentation_Stage__c = 'Assessment'` returned 0 rows. A full stage/
synthetic breakdown of every `GTM_Saved_Configuration__c` row currently on
`gtm-staging` shows **all 18 existing rows are synthetic** (`Is_Synthetic__c =
true`) — there are currently zero real/production-style records on this org
at all:

```
PRESENTATION_STAGE__C  IS_SYNTHETIC__C  CNT
Assessment             true             6
In_Review              true             3
Draft                  true             1
Sent                   true             7
Rep_Direct             true             1
```

`gtm-prod` was **not** queried or touched for this scope, per instruction —
that is a decision for the owner, not this BA pass, and is called out
explicitly under §5 Non-Goals / Data Remediation Follow-up below.

## 1a. Investigation — what legitimately depends on the stage reaching `Assessment`

Grepped every Apex class, LWC, Flow, permission set, report and list view in
the repo for `Presentation_Stage__c` / `presentationStage`. Full result list
and what each one means for this fix:

- **`GTM_Config_Send_To_Client.flow-meta.xml`** — record-triggered flow, fires
  only when `Presentation_Stage__c EqualTo 'Sent'` (start filter, line 21-24)
  and skips if the prior value was already `'Sent'`. Completely unrelated to
  the `'Assessment'` transition this bug causes — **no interaction, no risk**.
- **`GtmStageActionsController.cls`** — the rep-facing manual stage-advance
  UI's backing controller (`advanceStage()`). `VALID_STAGES = {'Assessment',
  'In_Review', 'Draft', 'Sent'}` (line 35-37) — **`Rep_Direct` is not and has
  never been a valid target of this manual control**, confirming Rep_Direct is
  intentionally outside the rep-driven Draft→Sent→In_Review/Assessment
  lifecycle this controller manages. This class is not called by
  `submitRequest()`/`postInsertBestEffort()` at all (they write via a
  dynamically-typed `SObject.put()`, not through this controller), so it's
  unaffected either way — cited only as corroborating evidence that
  `Rep_Direct` was never meant to participate in this state machine.
- **`GtmSavedConfigurationController.cls`**:
  - `createRepDirectAssessment()` (~line 279-326) — doc comment: "an
    automatically excluded from `getMyConfigurations()`'s 'All Pages' list --
    it never had a page to begin with."
  - `generateRepDirectShareLink()` (~line 334-410) — doc comment, verbatim:
    "Only works on a record whose `Presentation_Stage__c` is already
    `'Rep_Direct'` -- **never changes that value**, so this record still never
    reappears in `getMyConfigurations()`'s 'All Pages' list." This is a
    second, independent piece of code in this same class explicitly designed
    around the assumption that `Rep_Direct` is permanent — the bug under scope
    is the one place in the codebase that violates it.
  - `getMyConfigurations()` (~line 584-628) — the "Pages" tab's query
    **permanently excludes** `Presentation_Stage__c != 'Rep_Direct'` (line
    613-615) regardless of what the value becomes later. This is
    self-consistent with the intended permanent-`Rep_Direct` design: even
    after this fix, a submitted Rep_Direct assessment still correctly never
    appears in "All Pages" (it never had a page), and today, **before** the
    fix, the same exclusion means a bug-corrupted record silently vanishes
    from "All Pages" too (it becomes stage `'Assessment'` but has no
    `Generated_URL__c`, so it wouldn't render sensibly there anyway) — the
    corruption's damage shows up on the *guest-facing* configurator page, not
    in this rep-facing list.
- **`GtmLinkStageService.cls`** and **`GtmOverviewOfferingCounts.cls`** — both
  build their "universe" of stage-filterable links with the identical
  permanent exclusion (`Presentation_Stage__c != 'Draft' AND != 'Rep_Direct'`,
  `GtmLinkStageService.cls` lines 234-236 and 430-432;
  `GtmOverviewOfferingCounts.cls` lines 58-60). Same conclusion as above — no
  legitimate dependency on `Rep_Direct` ever becoming a counted/filterable
  stage.
- **`GtmStageFilterAppTool.cls`** (the GUS app-tool `find_links_by_stage`) —
  queries `Presentation_Stage__c` directly (line 110/123) but only surfaces
  whatever `GtmLinkStageService` already scoped as its universe — inherits the
  same permanent exclusion, no separate risk.
- **`postInsertBestEffort()` itself** — the Task/Bell rep notification
  (`GtmLifecycleNotificationService.fireTask`/`fireBell`, lines 1001-1009) and
  the draft-readout generation (`generateDraftReadout(req.Id)`, line 992) are
  **both unconditional on stage already** — gated only on
  `settings.notifyOnNewAssessmentRequest && req.OwnerId != null` and on
  `req.Id` respectively. Grepped `GtmLifecycleNotificationService.cls`
  directly: zero references to `Presentation_Stage__c` anywhere in that class.
  **This directly answers the "rep-facing 'your assessment came back'
  notification" concern the fix needs to preserve: it does not depend on the
  stage flip at all, today or after this fix** — a rep is notified about a new
  assessment request the same way regardless of whether the linked config is
  `Rep_Direct`, `Sent`, or anything else.
- **`gtmRepDirectShare.js`** (`force-app/main/default/lwc/gtmRepDirectShare/`)
  — the "Share with prospect" / "Answer some questions now" component:
  "Renders nothing at all for any record that is not Rep_Direct" (its own
  header comment, line 32-33); `isRepDirect` getter (line 71-73) reads
  `Presentation_Stage__c` via `@wire(getRecord)`. **Today**, once
  `postInsertBestEffort` corrupts the stage, this component also silently
  disappears from the record after a real submission — which happens to look
  intentional (an already-submitted assessment arguably doesn't need a
  "share"/"pre-fill" action anymore) but is really the same underlying bug
  reaching a second surface. **After the fix** (stage correctly stays
  `Rep_Direct`), this component will keep rendering its "Share"/"pre-fill"
  actions even after a real submission has landed — which is the *actual*,
  currently-untested behavior implied by its own doc comment ("renders...for
  any record that is not Rep_Direct", full stop, no submitted-state carve-out
  anywhere in this file). **This is a real, pre-existing gap the fix will
  newly expose**, not introduce: nothing in `gtmRepDirectShare.js` checks
  whether an assessment has already been submitted before showing "Share with
  prospect" / "Answer some questions now" again. Flagging this for Developer
  to confirm intentional or file as a fast-follow — it is not blocking (the
  server already refuses a second submission via the one-per-link duplicate
  guard in `submitRequest()`, so nothing breaks functionally; a rep could just
  see a stale-looking action after a prospect has already answered), and it is
  explicitly **not required for this issue's acceptance criteria**, but
  omitting it from this scope doc would hide a real interaction.
- **Reports / List Views** — grepped `force-app/main/default` for any
  `.report-meta.xml` / `.listView-meta.xml` referencing
  `GTM_Saved_Configuration__c` or `Presentation_Stage__c`: **none found**. No
  report/list-view dependency exists.
- **Permission sets** (`GTM_Offering_Admin`, `GTM_Offering_User`) grant field
  access to `Presentation_Stage__c` (already existing FLS, unrelated to this
  fix — no new field, no new grant needed).

**Conclusion on item 1:** the naive guard — skip (or no-op) the
`Presentation_Stage__c = 'Assessment'` write in `postInsertBestEffort()`
specifically when the config's current stage is already `'Rep_Direct'` — is
safe. No code in this repository depends on a `Rep_Direct` config eventually
reaching `'Assessment'`; every piece of code that reads
`Presentation_Stage__c` either (a) is unrelated to the `'Sent'`→flow path, (b)
already treats `Rep_Direct` as permanently excluded by design, or (c) is
already stage-independent (the rep notification/readout generation). The one
real, pre-existing interaction found (`gtmRepDirectShare.js` staying visible
after a real submission once the stage genuinely never flips) is a
UI-polish gap to flag, not a blocker, and not in this issue's acceptance
criteria.

**Implementation-shape note for the Architect/Developer (BA does not write
code, this is scoping guidance only):** `resolveConfigContext()` (line
455-485) already runs one SOQL against `GTM_Saved_Configuration__c` per
submission and populates `ConfigContext` — it does **not** currently select
`Presentation_Stage__c` (its `SELECT` list, line 463-465, has
`OwnerId, Opportunity__c, Account__c, Contact__c, Company__c, Offering__c,
Estimated_Value__c, Link_Password__c, Notify_Email__c` but not
`Presentation_Stage__c`). The cheapest, no-extra-query shape for the guard is
adding `Presentation_Stage__c` to that existing SELECT, threading it through
`ConfigContext` into `postInsertBestEffort()` (which already receives `ctx`),
and skipping the update when `ctx.presentationStage == 'Rep_Direct'` — rather
than issuing a brand-new SOQL query inside `postInsertBestEffort()` itself.
This is a suggestion, not a mandate; Developer/Architect should verify it
against the final call shape.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? — **No.** `GtmStageFilterAppTool.cls` reads
      through `GtmLinkStageService`'s existing universe and is unaffected;
      nothing in this fix touches `GtmAgentToolSurface`/any `GtmAppTool`.
- [ ] Altering Custom Metadata? — **No.** No YAML/`GTM_Assessment_*` metadata
      changes.
- [ ] Introducing database fields? — **No.** This is a logic guard on an
      existing field write; no new object/field, so no new Permission Set
      mapping is required.

## 3. Plan Acceptance Criteria

- **Success Metric:** QA must mechanically prove all four of the following
  against real Apex execution (unit tests, not manual browser-only checks,
  though a browser walk of the two `gtmConfigurator` render paths is also
  expected per this repo's QA browser-validation rule):
  1. A `GTM_Saved_Configuration__c` created via
     `GtmSavedConfigurationController.createRepDirectAssessment()` (or
     inserted directly with `Presentation_Stage__c = 'Rep_Direct'`) that then
     has `GtmAssessmentRequestController.submitRequest()` called against it
     (with `savedRecordId` set to that record's Id) **retains
     `Presentation_Stage__c = 'Rep_Direct'`** after the call returns — query
     the record post-submission and assert the value did not change. This is
     the exact regression this issue exists to close; there is currently
     **no test anywhere in the repo that asserts this** (see below).
  2. A `GTM_Saved_Configuration__c` at a normal stage (e.g. `'Sent'`, the
     realistic pre-submission stage for a real branded link) that has
     `submitRequest()` called against it **still advances to
     `Presentation_Stage__c = 'Assessment'`** exactly as it does today — a
     regression test proving the non-`Rep_Direct` path is unchanged is
     mandatory, not optional, since this is the behavior the whole rest of
     the app (BD pipeline visibility, `GtmLinkStageService`'s stage filter,
     `getMyConfigurations()`'s "All Pages" list) depends on.
  3. `gtmConfigurator.js`'s `isRepDirect` gate (and everything that reads it —
     `showCustomizeButton`, `showAssistant`, `showChapterBody`,
     `showRepDirectQuestionnaire`) behaves correctly for both cases: a
     `Rep_Direct` link, revisited after a real submission, still renders the
     pageless questionnaire branch (`showRepDirectQuestionnaire`,
     `!showChapterBody`) and never falls through to
     `CHAPTER_DEFAULTS`/branded-chapter rendering; a normal `Sent`→`Assessment`
     link's chapter rendering is unaffected.
  4. `GtmSavedConfigurationControllerTest.generateRepDirectShareLinkPopulatesUrlAndPasswordWithoutFlippingStage`
     (existing, line ~1531-1578 of `GtmSavedConfigurationControllerTest.cls`)
     continues to pass unmodified — it already asserts a different method
     (`generateRepDirectShareLink`) never flips the stage, and documents the
     same invariant this fix extends to `submitRequest()`. It does not need
     editing, but a regression here would mean the fix broke something
     unrelated.

- **Existing test coverage — confirmed gap, not a test to invert.** Searched
  every test class in the repo for a caller of `submitRequest`:

  ```
  $ grep -rln "submitRequest" force-app/main/default/classes/ | grep -i test
  force-app/main/default/classes/GtmAssessmentRequestControllerTest.cls
  ```

  Only one test class calls it. Searched that file directly for any
  stage/Presentation_Stage__c assertion:

  ```
  $ grep -in "Presentation_Stage__c\|stage" force-app/main/default/classes/GtmAssessmentRequestControllerTest.cls
  368:            StageName = 'Qualification',
  439:            SELECT Name, AccountId, Amount, StageName
  504:            StageName = 'Prospecting',
  581:            StageName = 'Negotiation/Review',
  ```

  All four hits are unrelated `Opportunity.StageName` test fixtures — **zero
  hits on `Presentation_Stage__c`**. No existing test asserts, locks in, or
  even exercises the current buggy unconditional-flip behavior on
  `GTM_Saved_Configuration__c`. This means: (a) there is nothing to "flip" or
  invert in an existing test as part of this fix, but (b) Developer must
  **add** the two new regression tests described in acceptance criteria #1
  and #2 above from scratch — this test gap is itself part of why the bug
  shipped unnoticed, and closing it is in scope for this issue, not a
  nice-to-have.

- **Target Test Target:** `GtmAssessmentRequestControllerTest` (new methods
  covering both the `Rep_Direct`-stays-`Rep_Direct` and the normal-stage-still-
  advances cases) plus
  `GtmSavedConfigurationControllerTest.generateRepDirectShareLinkPopulatesUrlAndPasswordWithoutFlippingStage`
  as a non-regression check; on the LWC side,
  `lwc/gtmConfigurator/__tests__/` (existing suite — check for and extend
  coverage of `isRepDirect`/`showChapterBody`/`showRepDirectQuestionnaire` for
  a record whose `presentationStage` is `'Rep_Direct'` both before and after a
  submission-triggering reload).

## 4. Non-Goals (explicit)

- Does **not** fold in any part of the `demo-seed-integrity-rebuild` seed-data
  rebuild — that issue's own scope
  (`docs/agent-artifacts/task-scope-demo-seed-integrity-rebuild.md`, branch
  `ba-scope/issue-demo-seed-integrity-rebuild`) is unchanged by this doc, and
  is explicitly the next issue to sequence once this one lands, per that
  issue's Architect review.
- Does **not** touch `gtmRepDirectShare.js`'s post-submission visibility gap
  noted in §1a — flagged for awareness, not required for this issue's
  acceptance criteria.
- Does **not** propose, plan, or perform any data remediation in `gtm-staging`
  or `gtm-prod`. See §5.

## 5. Data Remediation Follow-up (owner awareness only — not this issue's scope)

Six synthetic `GTM_Saved_Configuration__c` rows on `gtm-staging` (`SC-3829`
through `SC-3834`, all `Is_Synthetic__c = true`) are currently sitting at
`Presentation_Stage__c = 'Assessment'` when their creation pattern (no
`Config_Payload__c`, no `Generated_URL__c`, no `Industry__c`, a matching
`GTM_Assessment_Request__c` created in the same transaction) indicates they
originated as `Rep_Direct`. This code fix does not retroactively correct
already-corrupted rows — only the owner (or a follow-up data task, explicitly
authorized) should decide whether/how to backfill those 6 rows back to
`Rep_Direct`, since they are test/synthetic data likely to be wiped and
regenerated by the `demo-seed-integrity-rebuild` effort anyway. **`gtm-prod`
was not queried for this scope** (out of scope per instruction) — whether any
real, production `Rep_Direct` link has been silently corrupted by this same
bug is unknown and unverified; flagging this explicitly so it is not
mistaken for "checked and clean." If the owner wants that checked, it needs
its own explicit go-ahead given `gtm-prod` holds live prospect data.

## 6. Sequencing

This issue blocks `demo-seed-integrity-rebuild` (that issue's Architect
review refused to provision a worktree until this is addressed) and should be
built, tested, and merged first. No other open issue in
`docs/agent-artifacts/` was found to depend on or conflict with this fix.
