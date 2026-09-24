# TASK SCOPE — ISSUE #184

## 0. Investigation summary (read this before the sections below)

This is **not** a single open task — it's two already-largely-resolved
threads plus one genuine gap. Verified against current `main` (post PR #239
Home-page retirement, post PR #186 crash fix, post the `184-schema-cascade`
/ `184-controller` / `184-lwc` / `184-permissions` / `184-purge-batch` slices):

1. **The crash (original bug report) is already fixed and verified live.**
   PR #186 (`agent/issue-184-crash-archived-page-open`, merged
   2026-09-15, commit `88812293`) added a null-safety guard in
   `gtmContentHome.js`'s `cards` getter (`o.pages || []`) so a card whose
   `pages` arrives empty/undefined no longer throws. Issue comment #3
   documents a live browser repro of the *exact* original click path
   (Content Manager → Home → Archived offerings → Configurator row on a
   0-section archived offering) confirming no crash. **No further crash-fix
   work is needed.**

2. **`gtmContentHome` is still live and reachable**, contrary to the
   "maybe moot after PR #239" concern in this task's brief. PR #239 changed
   the app's **Home tab from a custom `GTM_Content_Home` tab to the
   `standard-home` actionOverride** in `GTM_Content_Manager.app-meta.xml`,
   but that override still points at the `GTM_Content_Home` FlexiPage, which
   still embeds the `gtmContentHome` LWC (`componentName>gtmContentHome`,
   `GTM_Content_Home.flexipage-meta.xml` line 6). Same component, same
   "Archived offerings" tile, same click path — just reached via the
   platform's standard Home tab instead of a custom tab. **Issue #184 is not
   moot; do not close it as obsolete.**

3. **Most of the recycle-bin feature is already built**, across five
   commits/slices documented in `docs/architecture/offering-archive-cascade.md`
   (`184-schema-cascade`, `184-controller`, `184-lwc`, `184-permissions`,
   `184-purge-batch`):
   - Schema: `Archived_Date__c` on `GTM_Page_Section__c` (new) and
     `Archived__c` + `Archived_Date__c` on `GTM_Page_Content__c` (both new).
   - Cascade: `GtmPageSectionArchiveCascade.trigger` +
     `GtmOfferingArchiveCascadeHandler.cls` (with `GtmOfferingArchiveCascadeTest.cls`).
   - Controller: `GTM_RecycleBinController.cls` — `getArchivedItems()`
     (cacheable), `restoreRecord`/`restoreRecords`, `deleteRecords`
     (permanent), with `GTM_RecycleBinControllerTest.cls`.
   - LWC: `force-app/main/default/lwc/gtmRecycleBin/` — list view, search,
     row-level restore, checkbox bulk restore, two-step-confirmed bulk
     permanent delete.
   - Retention/purge: `GTM_PurgeRecordsBatch.cls` (+ test).
   - Permissions: `Archived_Date__c`/recycle-bin grants already present in
     `GTM_Content_Admin`, `GTM_Content_Manager`, `GTM_Offering_Admin`, and
     `GTM_Offering_User` permission sets.
   - The issue's own architectural decision ("continue with custom
     `Archived__c`-style fields, not native Recycle Bin `delete`/`undelete`")
     was followed correctly throughout — no native-recycle-bin API use found.

4. **The one real gap: the final placement direction was never applied.**
   Issue comment #1 ("Update: recycle bin placement... supersedes earlier
   LWC section") explicitly redirected the LWC host: `gtmRecycleBin` must
   live as a section **inside** each app's Settings surface
   (`gtmOfferingsSettings` for GTM Offerings; a net-new
   `GTM_Content_Manager_Settings` tab + `gtmContentManagerSettings` LWC,
   mirroring `gtmOfferingsSettings`, for GTM Content Manager) — **not** as a
   standalone top-level tab/page. Current code does the opposite of that
   redirect:
   - `gtmRecycleBin.js-meta.xml` still exposes it as a standalone
     `lightning__AppPage` / `lightning__Tab`.
   - `gtmContentHome.js`'s `handleOpenRecycleBin()` navigates via
     `standard__component` to `c__gtmRecycleBin` directly — a standalone
     route, not a Settings-tab section.
   - `gtmOfferingsSettings.js` has **zero** references to recycle bin
     (confirmed via `grep -c "recycle" gtmOfferingsSettings.js` → `0`).
   - No `GTM_Content_Manager_Settings` tab or `gtmContentManagerSettings`
     LWC exists anywhere in the repo — the app still has only `Home`,
     `Content Manager`, and `Instrument Editor` tabs.
   - This placement mismatch looks like the `184-lwc` slice landing before
     comment #1's redirect was read/applied, or the redirect landing after
     that slice merged. Either way it's an open contract violation against
     the user's explicit, already-had direction — not a design question for
     this BA pass to re-litigate.

## 1. Requirements Breakdown

- **Target Objective:** Relocate the already-built `gtmRecycleBin` component
  out of its standalone `lightning__AppPage`/`lightning__Tab` exposure and
  into a Settings-tab section per app, per the user's explicit (and
  superseding) direction in issue comment #1:
  - GTM Offerings app: embed a "Recycle Bin" section/child-route inside the
    existing `gtmOfferingsSettings` LWC (reached via the existing
    `GTM_Offerings_Settings` tab). Reuse the component, do not duplicate its
    list/restore/delete logic.
  - GTM Content Manager app: create a new `GTM_Content_Manager_Settings`
    custom tab and a new `gtmContentManagerSettings` LWC (mirroring
    `gtmOfferingsSettings`'s structure), add the tab to
    `GTM_Content_Manager.app-meta.xml`'s tab list, and embed the same
    recycle-bin section there.
  - Both settings hosts should drive a shared inner
    `gtmRecycleBin` module/markup (already exists) rather than forking it —
    the comment explicitly calls for one shared component used by both
    hosts so restore/purge/list logic isn't duplicated.
  - Update `gtmContentHome.js`'s `handleOpenRecycleBin()` (and the
    "Recycle Bin" header action that calls it) to navigate to the new
    Content-Manager-Settings location instead of the standalone
    `c__gtmRecycleBin` route. Decide alongside the Architect whether
    `gtmRecycleBin`'s `lightning__AppPage`/`lightning__Tab` targets should be
    narrowed/removed now that it's meant to be embedded rather than a
    standalone destination — flag this as an open call for the Architect,
    not something to silently leave both ways.
  - No crash-fix or data-model work is in scope — items 1–3 above are done
    and verified; re-verify only as a smoke check, don't rebuild them.
- **System Component Impacted:** LWC (`gtmOfferingsSettings`, new
  `gtmContentManagerSettings`, `gtmRecycleBin`, `gtmContentHome`), plus one
  new custom Tab metadata (`GTM_Content_Manager_Settings`) and an
  `applications/GTM_Content_Manager.app-meta.xml` tab-list edit. No Apex or
  schema changes anticipated — `GTM_RecycleBinController` already exposes
  everything the relocated UI needs.

### Ambiguity flag for the Architect

This is genuinely two things bundled under one issue number, and the
Architect should treat them as such when scoping the worktree/PR:

1. **A placement/relocation task** (this scope) — move an existing,
   functioning component to satisfy an explicit prior user direction. Low
   risk, no new backend surface, should be a small, fast PR.
2. **A possible second, separate ticket**: whether the "Recycle Bin" header
   action / entry point on `gtmContentHome` itself should still exist once
   both apps have a Settings-tab home for it, or whether `gtmContentHome`
   should instead just link into Settings (avoiding two entry points into
   the same feature). The issue thread doesn't settle this explicitly — flag
   it back to the user/Architect rather than guessing an answer.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No — this touches Content Manager/Offerings
      Settings UI and recycle-bin navigation only, not GUS. N/A.
- [ ] Altering Custom Metadata? No new/changed `GTM_Offering__mdt` or other
      Custom Metadata Type records — the design doc already confirmed
      `GTM_Offering__mdt` is out of scope for this feature (no SObject
      parent exists to cascade from). N/A.
- [x] Introducing database fields? No — all required fields
      (`Archived_Date__c` on both objects, `Archived__c` on
      `GTM_Page_Content__c`) already exist and are already mapped to
      permission sets (verified: present in `GTM_Content_Admin`,
      `GTM_Content_Manager`, `GTM_Offering_Admin`, `GTM_Offering_User`).
      This task adds a new **Tab** (`GTM_Content_Manager_Settings`), which
      needs the same FLS/tab-visibility treatment: add it to the
      `GTM_Content_Manager` permission set's tab visibilities (the way
      `GTM_Offerings_Settings` is presumably already granted in
      `GTM_Offering_User`/`GTM_Offering_Admin` — verify and mirror before
      calling this done).

## 3. Plan Acceptance Criteria

- **Success Metric:**
  - QA can no longer reach `gtmRecycleBin` as a standalone
    tab/app-page route; it is only reachable via GTM Offerings →
    `GTM_Offerings_Settings` tab and GTM Content Manager →
    `GTM_Content_Manager_Settings` tab.
  - From `gtmContentHome`'s Home screen, clicking "Archived offerings" still
    shows the archived tile (already fixed, re-verify no regression) and the
    "Recycle Bin" header action lands the user in the relocated
    Content-Manager-Settings location, not a broken/dead standalone route.
  - Restore (single + bulk) and permanent delete (two-step confirm) both
    still function identically from the new location — this is a relocation,
    not a rewrite of `GTM_RecycleBinController` or `gtmRecycleBin`'s
    internal logic.
  - `GTM_Content_Manager_Settings` tab is visible to `GTM_Content_Manager`
    and `GTM_Content_Admin` permission-set holders and not visible to
    `GTM_Offering_User`-only users (mirrors the existing
    `GTM_Offerings_Settings` tab's scoping pattern for the other app).
- **Target Test Target:**
  - Jest: `force-app/main/default/lwc/gtmRecycleBin/__tests__/gtmRecycleBin.test.js`,
    `force-app/main/default/lwc/gtmOfferingsSettings/__tests__/gtmOfferingsSettings.test.js`,
    and a new `gtmContentManagerSettings.test.js` covering the embedded
    recycle-bin section and tab navigation.
  - Apex: `GTM_RecycleBinControllerTest.cls` (regression only — no
    controller changes expected, so this should pass unmodified; re-run to
    confirm no drift).
  - `force-app/main/default/lwc/gtmContentHome/__tests__/gtmContentHome.test.js`
    for the updated `handleOpenRecycleBin()` navigation target.
