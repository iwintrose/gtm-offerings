# Guided Setup: implementation plan (parallel build)

Status: plan, docs only. Written 2026-09-20 against origin/main (79a97ac: site shell, Home pages, Add industry #244 all landed).
Inputs: `docs/architecture/guided-setup.md` and the BA scope `docs/agent-artifacts/task-scope-guided-setup.md` (both on branch `agent/issue-guided-setup`, rows 1-22 and addendum 1.H), `add-industry.md`, `site-shell-metadata.md`, `docs/runbooks/gtm-offerings-install.md`.
Authority: `guided-setup.md` (section 5-7 contracts) stays the contract of record when it is merged. This plan (a) finalises the step list, (b) resolves what that doc left to spikes by designing runtime fallbacks so no Developer waits on a spike, (c) splits the build. Where this plan differs, it says so in section 2.4 ("deltas") and the merged contract must be updated by workstream E.

## 0. Hard requirements and how each is met

| Requirement | How |
|---|---|
| Setup lives in the app, never relayed by an agent | A first, default-selected `Setup` section of the existing Settings tab (ADR-0010). Row text is the explanation. The install runbook shrinks to "open Settings > Setup" plus one fallback sentence. |
| User-entered defaults, never seeded | No industry, offering, or copy is created by Setup. The only writes are: assign an allow-listed permission set, schedule two existing jobs, and create EMPTY framework page structure from existing starter definitions (no text). Industries and offerings are created by the admin through the existing Add industry / New Offering flows via deep links. |
| API keys optional | `ai_keys` is OPTIONAL, neutral, collapsed, never counted, never red. |
| Blank install | Every detector returns a valid status with zero rows of everything; per-row exception isolation; Apex tests are hermetic. |
| Salesforce first | See 0.1. |

### 0.1 Native options evaluated (decision: custom checklist, native used for every link target)

Knowledge-based; there is no docs tool in this environment, so the claims marked (U) are verified by the QA pass in section 6, not assumed.
- Guidance Center / Setup Assistant: org-level Lightning Experience onboarding for standard Salesforce features; not a place a customer app contributes per-app, state-detecting steps. (U)
- In-App Guidance (prompts, walkthroughs): shows static messages on pages; it cannot run Apex to detect state, cannot perform an action, and cannot reflect "this is still missing". It can complement later (a one-time prompt pointing at Settings > Setup) but is org configuration, not source-deployable in this repo. Out of scope.
- Path: record-stage guidance on an object record; there is no record for "the app install". Not applicable.
- Flow / Screen Flow: could render a static checklist but cannot cheaply detect the eight kinds of org state (queues, permission set assignment, Network status, jobs) with the isolation and test coverage required, and adds a second tech to a repo that is Apex + LWC.
- Native Setup pages (Permission Sets, Queues, Digital Experiences, Users): the ACTION target of every human-only step. The checklist never re-implements them; it deep links to the exact page.
Decision: a thin LWC checklist that detects and points, calling native Setup for anything it cannot safely do. Justified because no native surface reports per-app live state with an action.

## 1. Final step list

Legend. Detect = auto-check on every load and Re-check (derive-only, nothing stored). Act = in-app one-click action or deep link. Verify = how the row proves itself done (always: re-detect after the action; the row flips only from server state). Auto = can Apex do it; Human = must be clicked by a person.

Tiers: R required (counted), Rec recommended (shown, not counted), O optional (collapsed, neutral, not counted), I info (never completable). Only R rows count in "N of M required steps done". `content_access` is a helper (own row only when unmet).

| # | key | Tier | Detect | Act | Verify | Auto / Human |
|---|---|---|---|---|---|---|
| 1 | `admin_assigned` | R | active `PermissionSetAssignment` for `GTM_Offering_Admin` >= 1 | ASSIGN_TO_ME (viewer lacks it), else none | count >= 1 after re-check | AUTO (Apex, with runtime fallback to Setup link) |
| 2 | `content_access` | helper | viewer holds `GTM_Content_Manager` or `GTM_Content_Admin` | ASSIGN_TO_ME `GTM_Content_Manager` | viewer assignment exists | AUTO (fallback link) |
| 3 | `reps_assigned` | Rec | `GTM_Offering_User` assignments >= 1 | ASSIGN_PICKER (search users, assign) | count >= 1 | AUTO after the human picks who |
| 4 | `guest_permset` | R | resolve site guest user, then `GTM_Guest` assignment; unresolvable -> UNKNOWN (never DONE) | LINK to Experience Builder guest-profile settings (v1); no inline assign | assignment visible on re-check | HUMAN in v1 (inline guest assign is a v2 option, section 7 D3) |
| 5 | `site_active` | R | `Network` for our site, `Status='Live'`; no Network -> BLOCKED; ambiguous -> UNKNOWN | LINK Setup > Digital Experiences > All Sites | Status Live | HUMAN (activate/publish) |
| 6 | `framework_pages` | R | per template (offerings-page, industry-chooser, faq-bd, faq-content-manager, assistant) any `GTM_Page_Section__c` for `gtm` | CREATE_FRAMEWORK_PAGES (one click, nothing typed) | all five have sections | AUTO (empty structure only) |
| 7 | `industry_added` | R | `GtmPageContentReader.getIndustryProfiles('gtm','industry-chooser')` count with `industryLabel` (Published, active only) | NAV_ITEM `GTM_Content_Manager` `c__offering=gtm`,`c__template=industry-chooser` ("Add industry", then Publish) | count >= 1 | HUMAN (types the industry) |
| 8 | `offering_created` | R | tile sections: `offerings-listing`/`tile`, `Offering_Key__c != 'gtm'`, `Active__c=true` | NAV_ITEM `GTM_Content_Home` ("New Offering") | count >= 1 | HUMAN |
| 9 | `offering_published` | R | same filter, `Offering_Status__c='Published'`, `Archived__c != true`; created>0 and published=0 -> detail "N draft offering(s) are hidden until published" | NAV_ITEM `GTM_Content_Home` | published >= 1 | HUMAN |
| 10 | `offering_listed` | R (default; may demote) | `GtmPageContentReader.getOfferingTiles()` non-empty; published>0 and listed=0 -> "published, but no site record yet" (gap G1, GTM_Offering__mdt row missing) | SETUP_PATH Custom Metadata Types > GTM Offering > Manage Records | tiles non-empty | HUMAN (metadata row cannot be written by Apex safely here) |
| 11 | `triage_queue` | Rec | queue `GTM_Readout_Triage` exists (else BLOCKED "queue not deployed"); `GroupMember` >= 1 | SETUP_PATH Queues | member count >= 1 | HUMAN (choose members) |
| 12 | `manager_on_reps` | Rec | shown only while `GTM_Readout_Approval_Settings__c.getOrgDefaults().Self_Approval_Enabled__c = false`; users with `GTM_Offering_User` and `ManagerId = null` (count + first 5 names) | SETUP_PATH Users | count = 0 | HUMAN |
| 13 | `scheduled_jobs` | Rec | `GtmScheduledJobsController.getStatuses()` both scheduled | SCHEDULE_JOBS (existing `scheduleJob` per job) | both scheduled | AUTO |
| 14 | `site_members` | Rec | `NetworkMember` readable? else UNKNOWN | LINK site Administration > Members | count > 0 | HUMAN |
| 15 | `page_offerings`, `page_faq_bd`, `page_faq_cm`, `page_assistant` | O | any active `GTM_Page_Content__c` value for that `gtm` template | NAV_ITEM to that Content Manager page | content exists | HUMAN (authoring) |
| 16 | `analytics_digest` | O | `GTM_Analytics_Settings__c.getOrgDefaults()` digest flag | shell event `selectsection` -> `analytics-notifications` | flag true | HUMAN |
| 17 | `ai_keys` | O, neutral | `GtmAgentSettingsController.getAgentSettings()` booleans only | shell event -> `claude-gus` | any `has*Key` | HUMAN (a secret) |
| 18 | `approval_routing` | I | mode text from org defaults | shell event -> `approval-routing` | never DONE | HUMAN (policy) |
| 19 | `offering_pages` | I | per non-archived offering, `story`/`configurator` with zero sections | NAV_ITEM `GTM_Content_Home` | informational | HUMAN |
| 20 | `org_digital_experiences`, `org_my_domain`, `org_chatter`, `org_email` | I | `org_digital_experiences`: Network table readable/present; the other three are STATIC info rows with no detection (status INFO, no claim of state) | SETUP_PATH | none | HUMAN |

Rows dropped versus the BA scope: rep-Manager and email-sender checks are not "required" (12 is conditional; email is INFO because verification state is not exposed to SOQL, U). Row 9 of the BA table (purge jobs "required") is Recommended.
Counts: R = 8 (rows 1, 4, 5, 6, 7, 8, 9, 10). Order on screen: Required, Recommended, Optional, Info; within a tier by the table order above.

### 1.1 What Apex can automate versus what a human must click

| Automatable in Apex (inline) | Not automatable in v1 (link) |
|---|---|
| Assign `GTM_Offering_User`/`GTM_Content_Manager` to any active Standard user; `GTM_Offering_Admin`/`GTM_Content_Admin` to self only (allow-list) | Guest access: `GTM_Guest` onto the site guest user, and publishing the site (both stay human: guest user resolution and "publish" are not reliably exposed; U) |
| Schedule the two purge jobs (existing `GtmScheduledJobsController.scheduleJob`) | Queue membership, Manager on users, site members (choices about people; Setup pages) |
| Create empty framework page structure (existing `GtmPageSectionController.createPage`, via thin wrapper) | Industry, offering, page copy, keys, analytics recipients (defaults must be typed by the admin) |
| Read all state (SOQL only) | `GTM_Offering__mdt` record (metadata write) |

Runtime fallback rule (replaces the spike gate): any inline action that fails for a platform reason (for example the running admin lacks the "Assign Permission Sets" system permission, `INSUFFICIENT_ACCESS`, `MIXED_DML`) returns a structured result with `fallbackToSetup = true` and the exact Setup path, and the LWC renders that link in place of the button. Nothing is ever reported done on failure. So the build never depends on the unresolved platform question, and the QA pass simply records which path fired.

## 2. Contracts

### 2.1 Data model: derive-only

No new object, field, custom setting, or custom metadata. Nothing stores "done": every load and Re-check re-detects from live org state. Consequences: no permission-set FLS grants (CLAUDE.md 6.1 has nothing to add for schema), no migration, trivially reversible (delete the classes, the LWC and the one SECTIONS entry). The only permission-set change is class access (2.5). Per-user dismissal or hide is rejected: it would need a field and would hide a real gap.

### 2.2 `GtmSetupChecklistController` (with sharing, no DML, no callouts)

Adopt `guided-setup.md` section 5.1 verbatim (methods `getChecklist()`, `searchAssignableUsers(String)`, DTOs `SetupChecklist`, `SetupItem`, `UserOption`), with these additions.
- `SetupItem` gains `List<String> blockedBy` (keys of unmet prerequisites; empty list, never null) and `Boolean collapsedByDefault` (true for O and I).
- Static constants: `TIER_*`, `STATUS_*`, `ACTION_*`, `LINK_*` as `public static final String` (Apex and Jest fixtures share the literals). Setup paths in ONE private `Map<String,String> SETUP_PATHS`.
- Detector pattern: `private interface Detector { SetupItem detect(Ctx c); }` is not needed; use one private static method per key returning `SetupItem`, called from a list of `DetectorRef` via a `switch`-free registry `List<String> KEYS`, each wrapped: `try { item = detectX(ctx) } catch (Exception e) { item = unknown(key, tier) }`. A `@TestVisible static String forceFailKey` seam lets a test prove isolation.
- `Ctx` is built once per call: viewer id, `Map<String,Integer> assignmentCountsBySet` from ONE aggregate query on `PermissionSetAssignment` grouped by `PermissionSet.Name` for the five GTM sets, the viewer's held set names from ONE query, org-default settings rows, the `Network` list from ONE query. Detectors read from `Ctx`; they issue their own query only for data the Ctx does not hold (queue, page sections, users without manager).
- Permission checks: the class is granted only to `GTM_Offering_Admin`; SOQL runs `with sharing`. Unreadable object (`isAccessible()` false) yields UNKNOWN for that row, not an exception. Detection of `PermissionSetAssignment` is aggregate-only and returns no usernames; `searchAssignableUsers` returns `name`, `username` (display only, never logged), Standard and active only, max 25, term length capped at 80, `String.escapeSingleQuotes` not needed because bind variables are used.
- Errors: `getChecklist` never throws for a detector failure; it throws `AuraHandledException` only if the whole class cannot run (for example the Ctx queries themselves are not permitted), with the message "Setup could not be loaded." No stack, org id or username in any message or `detail`.
- Governor budget for one `getChecklist` (target <= 25 SOQL of 100, <= 10k rows): Ctx 5; framework template sections 1 aggregate (`GROUP BY Template_Type__c`); offerings tile counts 1 aggregate; industry via reader 1 (reader's own); tiles via reader 1 to 2; queue 2; manager users 1; content-page presence 1 aggregate (`GROUP BY Template_Type__c` on `gtm`); story/configurator per offering 1 aggregate; jobs via existing controller 1; agent settings 1. No SOQL in loops (assert with a `Limits.getQueries()` bound in the blank-org test: <= 30). No DML, no callouts, cacheable=false.
- Site identification (the one heuristic): from the Ctx `Network` list pick the row whose `Name = 'GTM'` (the documented site name, `site-shell-metadata.md` section 5); if none, and exactly one Network exists, use it; otherwise the site rows are UNKNOWN (never DONE). No hard-coded org host or id.
- `guest_permset` v1: status is TODO/DONE only if the guest user can be resolved from `Site`/`Network` in a try block; else UNKNOWN with detail "Open Experience Builder > Settings > General > Guest User Profile and confirm GTM Guest is assigned." The action is a LINK; never `ASSIGN_*`.

### 2.3 `GtmSetupActionController` (with sharing, DML only in these three methods)

Adopt `guided-setup.md` section 5.2 (`assignPermissionSet`, `assignPermissionSetToMe`, `createFrameworkPage`, DTOs `AssignResult`, `FrameworkPageResult`) and section 3A rules (framework template allow-list, `gtm` fixed inside the method, idempotent, never re-lays an existing page). Additions.
- `AssignResult` gains `Boolean fallbackToSetup` and `String setupPath` (from the runtime fallback rule, section 1.1). Failure never throws to the client except for a rule violation (allow-list, self-only, inactive/non-Standard target), which throws `AuraHandledException` with a plain message and performs no DML.
- Allow-list constants as `guided-setup.md` section 5.2; exact-match, never from input. Assignment insert is `Database.insert(list, false)`; translate `Database.Error` to a plain message; a duplicate assignment pre-check returns `assigned=false` (idempotent). PermissionSetAssignment DML is the only DML in `assign*`; `createFrameworkPage` calls `GtmPageSectionController.createPage` and is a separate transaction from any assignment (avoids MIXED_DML). The LWC must never chain an assignment and a page create in one Apex call.
- `createFrameworkPage` return when the page exists: `created=false`, no DML, no exception. `createPage` returns `Integer` (section count) on main; map it to `sectionCount`. Exceptions from `createPage` (all-or-nothing savepoint) surface as the server message; the other templates are unaffected.
- Governor: `assign*` 2 SOQL + 1 DML; `createFrameworkPage` bounded by `createPage` (existing, per-page, at most about 50 DML rows for the largest starter); the LWC calls it at most 5 times, each its own transaction.
- Scheduling: no wrapper. The LWC calls existing `GtmScheduledJobsController.scheduleJob(jobKey)`.

### 2.4 Deltas from `guided-setup.md` (workstream E updates that doc)

1. Section 9 spikes Q1/Q2/Q4 no longer gate the build: replaced by the runtime fallback (1.1) and the site heuristic (2.2). QA records outcomes in its pass (section 6) into section 10 of the doc.
2. `blockedBy` and `collapsedByDefault` added to `SetupItem`; `fallbackToSetup`/`setupPath` added to `AssignResult`.
3. `org_*` rows other than `org_digital_experiences` are static INFO with no detection (no invented state).
4. Industry and Add industry are landed: `industry_added` deep link and wording confirmed against `add-industry.md` ("add and publish an industry"; the reader returns only Published, active industries).
5. `GtmScheduledJobsController` class access is missing from `GTM_Offering_Admin` on main (grep confirms no grant); the change adds it (gap G2).

### 2.5 Permission sets (CLAUDE.md 6.1; class access only, no schema)

Owned by workstream B only. `GTM_Offering_Admin`: add `classAccesses` (enabled) for `GtmSetupChecklistController`, `GtmSetupActionController`, `GtmScheduledJobsController`. `GtmPageSectionController` is NOT granted. No user permission added (`AssignPermissionSets` deliberately not added: the set carries Modify All on GTM objects). Other four sets: no change; a metadata test asserts none of them grants the two new classes. No new object, field, tab, so no FLS or tab-visibility work in any set.

### 2.6 LWC contracts

Components (all under `force-app/main/default/lwc/`):
- `gtmSetupChecklist` (container). `@api` none. Imports Apex `getChecklist`, `searchAssignableUsers`, `assignPermissionSet`, `assignPermissionSetToMe`, `createFrameworkPage`, `GtmScheduledJobsController.scheduleJob`; `starterFor` from `c/gtmPageLayouts` (import only, never edited). State: `checklist`, `loading`, `errorMessage`, `busyKey`. Behaviour: load in `connectedCallback` and on Re-check; render header "N of M required steps done" (plus ", K could not be verified" if `requiredUnknown > 0`); groups in tier order; passes each item to `c-gtm-setup-item`; handles `itemaction` events; after any action always re-fetches the whole checklist; shows server message text on failure; never holds a local "done".
- `gtmSetupItem` (presentational). `@api item` (a `SetupItem`), `@api busy` (Boolean), `@api pickerUsers` (array of `{value,label}`). Fires `CustomEvent('itemaction', { detail: { key, actionType, permissionSetName, linkKind, navApiName, navState, setupPath, userId } })` (bubbles false, composed false), and `CustomEvent('pickersearch', { detail: { term } })`. Renders icon by status, title, why, detail, a "You need to do this" or "Done for you" marker from `humanMustAct`, collapsed state from `collapsedByDefault`, and the single action control. Neutral styling for NOT_SET/INFO/OPTIONAL (no error color, no red).
- `gtmOfferingsSettings` (existing shell): add `{ id: 'setup', label: 'Setup' }` as `SECTIONS[0]`, `isSetupSelected` getter, one `<c-gtm-setup-checklist onselectsection={handleSelectSection}>` block, and `handleSelectSection(event)` that sets `selectedSectionId` if `event.detail.sectionId` is a known section id. The checklist fires `selectsection` (`{ sectionId }`) for the three settings-section rows.
- Navigation: `NavigationMixin.Navigate` with `standard__navItemPage` (`attributes.apiName`, `state`) for `NAV_ITEM`; `standard__webPage` with the relative `setupPath` for `SETUP_PATH`. State params for `GTM_Content_Manager`: `c__offering`, `c__template` (existing).
- Error handling: `reduceErrors` style helper local to the container (`error.body.message`, else a generic sentence); busy flag cleared in `finally`; a failed template in the framework loop continues to the next and the final re-fetch shows the true state.

The DTO shapes above and section 2.2 are the interface between A, B, C and D (section 3). Nothing else is shared.

## 3. Workstreams (parallel, disjoint file ownership)

Common: each Developer works in its own worktree from the same base; no workstream edits a file owned by another. The DTO/constant literals in section 2 are frozen at plan time. Deploy target is gtm-staging only (gtm-dev is treated as production and an Apex deploy there triggers a full local test run; nothing here deploys there).

| WS | Owner scope | Files owned (create unless noted) | Depends on |
|---|---|---|---|
| A. Checklist Apex | detectors, catalogue, search | `classes/GtmSetupChecklistController.cls` (+meta), `classes/GtmSetupChecklistControllerTest.cls` (+meta) | none (reads existing classes: `GtmPageContentReader`, `GtmScheduledJobsController`, `GtmAgentSettingsController`) |
| B. Actions Apex + access | assign, createFrameworkPage, permission sets | `classes/GtmSetupActionController.cls` (+meta), `classes/GtmSetupActionControllerTest.cls` (+meta), edit `permissionsets/GTM_Offering_Admin.permissionset-meta.xml` (the ONLY workstream touching it; adds all three classAccesses) | none (calls existing `GtmPageSectionController.createPage`) |
| C. Checklist container LWC | container, actions, navigation, Jest | `lwc/gtmSetupChecklist/**` (js, html, css, meta, `__tests__/gtmSetupChecklist.test.js`, `__tests__/fixtures.js`) | interface only (DTOs); Apex imports mocked in Jest via `jest.mock('@salesforce/apex/...', () => ..., { virtual: true })` |
| D. Item component + shell | presentational row, shell integration | `lwc/gtmSetupItem/**` (+ its Jest), edit `lwc/gtmOfferingsSettings/gtmOfferingsSettings.{js,html}` and `__tests__/gtmOfferingsSettings.test.js` | interface only (`item` shape, `itemaction`, `selectsection`) |
| E. Docs and script | runbook shrink, script message, contract update | `docs/runbooks/gtm-offerings-install.md`, `docs/runbooks/fresh-org-deploy.md`, `scripts/deploy-fresh-org.sh` (closing message text only), `docs/architecture/guided-setup.md` (apply deltas 2.4, merge from `agent/issue-guided-setup` first), `docs/architecture/adr/0010-...md` (one-line addendum: Setup is section 0), `docs/backlog.md` entry | none |

Not touched by anyone: `chooseIndustry.*`, `gtmPageLayouts.js`, `gtmContentManager`, `gtmContentHome`, `GtmAgentToolSurface`, `GtmAppAgentSurface` (neither new controller is a GUS tool; zero-DML/zero-callout contract untouched), `GTM_Assessment_*` metadata, `instrument/**`.

### 3.1 Interface contract between workstreams (frozen)

1. Apex to LWC: exactly the DTO field names and string constants in `guided-setup.md` 5.1/5.2 plus 2.2/2.3 additions. Status values `DONE|TODO|NOT_SET|BLOCKED|UNKNOWN|INFO`; tier `REQUIRED|RECOMMENDED|OPTIONAL|INFO`; actionType `NONE|LINK|ASSIGN_TO_ME|ASSIGN_PICKER|SCHEDULE_JOBS|CREATE_FRAMEWORK_PAGES`; linkKind `NAV_ITEM|SETUP_PATH|NONE`.
2. Catalogue keys: exactly the keys in section 1 (the four `page_*` keys are `page_offerings`, `page_faq_bd`, `page_faq_cm`, `page_assistant`). A owns the catalogue; C's fixture lists every key once so D/C tests cover them.
3. C to D: `<c-gtm-setup-item item={item} busy={busy} picker-users={users} onitemaction onpickersearch>`. D guarantees it renders any item without throwing for any valid status/tier/actionType combination and fires the `itemaction` detail shape in 2.6.
4. C to shell: fires `selectsection` `{ sectionId }` with ids `approval-routing`, `analytics-notifications`, `claude-gus`; D handles it.
5. Fixture: C publishes `__tests__/fixtures.js` early (first 5 minutes, pushed to its branch) exporting `blankChecklist`, `allDoneChecklist`, `unknownRequiredChecklist`; D and C use copies (D copies the literal into its own test, so no cross-file import).
6. Permission-set XML: only B edits; A and C never do. Class names in the XML must equal A and B's class names (frozen above).

### 3.2 Merge order

1. B and A (Apex plus permission sets; independent, either order; run `sf` deploy validation `--dry-run` to staging for both together).
2. D, then C (D's `gtmSetupItem` exists before C's html references it; the shell edit is independent).
3. E (docs and script; also pulls in `guided-setup.md` from `agent/issue-guided-setup`, so do it last to avoid a doc conflict).
4. One deploy to gtm-staging (`./scripts/deploy.sh <staging-alias> --run-tests`), then the single QA pass (section 5).
If B (permission XML) conflicts with any concurrent branch that edits `GTM_Offering_Admin`, B rebases; no other workstream touches the file.

## 4. Test plan

Hermetic Apex: `@isTest`, no `SeeAllData`, no Migration Accelerator custom metadata, no `GTM_Offering__mdt` rows assumed, no org ids/usernames. Must pass with zero offerings, zero page content, zero users beyond the test's own. Org-uncontrollable state (Network, already-scheduled jobs) asserts "status is one of the valid values". Setup-object DML (`PermissionSetAssignment`) in its own `System.runAs` block, separate from non-setup DML.

A: `GtmSetupChecklistControllerTest`: blank org returns every catalogue key exactly once with valid tier/status and no exception; `requiredTotal` = 8; optional and info rows never counted and never TODO; `Limits.getQueries()` <= 30 on blank; zero offerings gives `offering_created` TODO; Draft tile gives `offering_published` TODO with the draft count; publishing flips only that row; an industry with and without `industryLabel`; `manager_on_reps` present when org-default `Self_Approval_Enabled__c=false`, absent when true; `ai_keys` never contains key text (insert a key, serialise the whole checklist, assert absent); `forceFailKey` yields UNKNOWN for that row only; `searchAssignableUsers` excludes inactive and non-Standard users and caps at 25; no `detail` contains an org id pattern.
B: `GtmSetupActionControllerTest`: the four allow-listed names accepted within the self/other rules; `GTM_Guest`, `Conduit_User`, an invented name, null, blank throw with no assignment; admin-tier set for another user throws; second assign `assigned=false` and one row; inactive/non-Standard target rejected; `fallbackToSetup` path (simulated via a `@TestVisible` seam that forces the DML failure) returns the Setup path and never `assigned=true`; `createFrameworkPage` rejects offering templates/null/blank with no DML, is idempotent (second call `created=false`, section count unchanged), never touches an existing page, writes no non-empty text value; a metadata test queries `SetupEntityAccess` (ApexClass) and asserts only the `GTM_Offering_Admin` set grants each of the three classes (runAs does not enforce class access) and that `GtmPageSectionController` is not granted to it.
C: `gtmSetupChecklist.test.js`: header math and unknown suffix; tier order and grouping; optional/info collapsed and uncounted; UNKNOWN and BLOCKED never render a "done" state; each actionType calls the right mock (`assignPermissionSetToMe`, picker then `assignPermissionSet`, `scheduleJob` per unscheduled job, `createFrameworkPage` looping only over missing templates using `starterFor`); the whole checklist is re-fetched after every action; a failing action shows the server message and does not mark done; `fallbackToSetup` renders a link; `selectsection` fired for the three rows; blank fixture renders without error.
D: `gtmSetupItem` Jest: every status x tier renders; neutral (no error class) for NOT_SET/OPTIONAL/INFO; `itemaction` detail shape per actionType; marker text from `humanMustAct`. `gtmOfferingsSettings` spec updated: section count 5, default selection `setup`, `selectsection` switches sections, unknown id ignored.
E: `python3 scripts/check-references.py` exits 0; `bash -n scripts/deploy-fresh-org.sh`; grep the whole diff for org ids, usernames, emails, keys (none).
All: `npm test` (Jest) green, Apex run on staging with `--run-tests`; `sf project deploy start --dry-run` before the real deploy (never `-c`).

## 5. The ONE browser-validation script (single QA pass, gtm-staging, blank state)

QA reuses one Chrome tab, one browser agent. Preconditions: fresh or blank-content staging org with the app deployed; QA user A = System Administrator holding only `GTM_Offering_Admin`; user B = Standard user with `GTM_Offering_User` only; user C = Standard user with no GTM sets. Record every result as pass/fail plus the exact message; the recorded values fill `guided-setup.md` section 10.
1. As A open GTM Offerings > Settings. Expect Setup is the first, selected section; header "N of 8 required steps done"; no error banner; optional rows collapsed and neutral (no red); `ai_keys` reads "not set, everything else works".
2. Rows blank-state: `framework_pages` TODO listing five missing templates; `industry_added`, `offering_created`, `offering_published`, `offering_listed` TODO or BLOCKED with a named prerequisite; `guest_permset`/`site_active` DONE, TODO, BLOCKED or UNKNOWN but never DONE by mistake. Record which.
3. `content_access` (if A lacks it): click Assign to me. Expect success, or a Setup link (fallback) with the message; record which. Re-check reflects the true state.
4. Click Create framework pages once. Expect `framework_pages` DONE after re-check. Open Content Manager > Pages > Framework: five cards exist, editable, empty. Click again: nothing new is created (row already DONE, and re-running from the wrapper is a no-op).
5. Click the `industry_added` link: lands on the Industry Chooser page. Use Add industry, type a label. Back on Setup, Re-check: row still TODO with "publish" wording. Publish the page, Re-check: DONE.
6. Click `offering_created` link, New Offering, name it; Re-check: created DONE, published TODO with the draft count. Publish; Re-check: published DONE; `offering_listed` shows either DONE or "published, but no site record yet" with the Custom Metadata link (record which and whether the public offerings page shows it).
7. `reps_assigned`: use the picker to assign `GTM_Offering_User` to user B; Re-check DONE. Try to assign `GTM_Guest`/another admin set: no such control exists (negative).
8. `scheduled_jobs`: click Schedule; both jobs report scheduled; click again is a no-op.
9. `triage_queue`, `manager_on_reps` (only while approval is Manager mode), `site_members`, `guest_permset`, `site_active`, and `org_*` links: click each and record whether the Setup URL resolves.
10. Open the other four Settings sections (`approval-routing`, `analytics-notifications`, `claude-gus`, `scheduled-jobs`) and the three `selectsection` rows; each switches sections. Overview and the rest of the GTM Offerings app still load (regression).
11. Negative access: as B and C, confirm the Settings tab/Setup section is not reachable and a direct call is refused (user C cannot open the app tab; B has no Settings tab). Confirm the two new classes appear only in `GTM_Offering_Admin` (Setup > Permission Sets > class access).
12. Guest route: in a private window open the site's questionnaire/industry chooser as a guest; record whether the empty industry list shows the neutral prospect-safe message (from #241) and no admin wording.
13. Blank-org proof: nothing was seeded: `GTM_Page_Content__c` rows for `gtm` hold no text/rich values other than the empty JSON/icontext shells; no industry/offering existed before the admin created them.

## 6. Time estimate (about 60 minutes wall clock, five parallel agents)

| Phase | Minutes | Notes |
|---|---|---|
| T+0 to 5 | 5 | Coordinator hands this plan to five Developers; each creates its worktree via `scripts/agent-workspace.sh create`; C publishes `fixtures.js` at minute 5. |
| T+5 to 35 | 30 | Parallel: A 30 (largest: about 20 detectors plus tests), B 25 (three methods, tests, permission XML), C 30 (container plus Jest), D 15 (row component, shell, specs; then helps review A), E 10 (docs, script text). |
| T+35 to 45 | 10 | Merge in the order 3.2, run `npm test`, `check-references.py`, staging `--dry-run`. |
| T+45 to 50 | 5 | Real deploy to gtm-staging with `--run-tests`; fix-forward any Apex test failure (Continuous Debug Loops). |
| T+50 to 60 | 10 | Single QA browser pass (section 5, sized to about 10 minutes of clicking; the steps are ordered so one failure does not block the rest). |
| Total | about 60 | Critical path: A (30) plus merge/deploy/QA (25) plus kickoff (5). If A slips, defer `page_*`, `site_members` and `org_*` detectors to a follow-up (they are O/Rec/I) rather than move the finish; the required rows and the actions are the ship criteria. |

## 7. Risks and open decisions (decided; user not asked)

| # | Item | Decision |
|---|---|---|
| D1 | `offering_listed` (GTM_Offering__mdt row, gap G1) is required or recommended | Required, human link. It is the true reason an in-app offering is invisible to prospects. Demote to Recommended only if QA step 6 shows the public page lists it without the row. |
| D2 | Do assign actions work for a non-System-Admin `GTM_Offering_Admin` holder | Do not add `AssignPermissionSets` to the set. Runtime fallback (1.1) shows the Setup link; QA records the case. |
| D3 | Inline `GTM_Guest` assignment | Not in v1 (human link). Revisit only if QA proves a licence-compatible, publish-independent path; would need its own allow-list entry and test. |
| D4 | Site identity | `Name='GTM'`, else the only Network, else UNKNOWN. Wrong site name in an org shows UNKNOWN, never DONE. |
| D5 | Setup visible to whom | Section is in the shared Settings tab; controllers are class-gated to `GTM_Offering_Admin`. Non-admins see the section fail with "Setup could not be loaded" if they somehow reach it; no separate in-Apex role check (chicken-and-egg for first admin). Acceptable. |
| D6 | Permission set assigned inline needs a page reload for tabs | Detail text on the assigned row says "Reload the page to see new tabs". No auto-reload. |
| D7 | Drift between gtm-dev framework structure and `STARTER_PAGES` | `framework_pages` treats any existing section as built and never edits it, so gtm-dev is untouched; staging gets the current starters. Reconciliation is a separate task (needs a read-only structure retrieve, quota-blocked). |
| D8 | Draft framework sections may not render publicly (U) | QA step 12 records what a guest sees; the follow-up, if needed, is publishing in Content Manager, not Setup. |
| D9 | Unresolved platform claims (Guidance Center scope, `Site.GuestUserId` queryability, NetworkMember readability) | Each has a defined UNKNOWN or link fallback so none blocks the build; QA records outcomes. |
| D10 | Production risk | gtm-dev is production: nothing deploys there in this task; a later Apex deploy there runs the full local test suite. Blank-install proof happens on gtm-staging. |
| D11 | Two workstreams needing the same file | Prevented by the ownership table; the only shared risk file is `GTM_Offering_Admin.permissionset-meta.xml` (owned by B). |
| D12 | ADR-0010 addendum and doc merge | Done in E after everything else; if `agent/issue-guided-setup` has moved, E rebases the doc, not the code. |
