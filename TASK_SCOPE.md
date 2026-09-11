# TASK SCOPE — ISSUE #40

## 1. Requirements Breakdown

- **Target Objective:** A Content Manager (GTM_Content_Manager permission
  set) user should be able to rename what a page is *called* in the
  Content Manager's own page picker/editor — today `TEMPLATE_LABELS` in
  `force-app/main/default/lwc/gtmPageLayouts/gtmPageLayouts.js` is a
  hardcoded JS constant (`story: 'Story'`, `'faq-bd': 'BD App Help (FAQ)'`,
  etc.) with no authoring path.

  **Important finding — verify before designing anything new.** The
  content-model decision the issue and `docs/backlog.md` B6 both describe
  as still-open ("needs a content-model decision... own field vs. a new
  addressable content key, same shape as B1") **has already been made and
  built, and is live on `main`.** Confirmed via
  `git merge-base --is-ancestor 1b525bf HEAD` against current `main`
  (`838dac9`) — commit `1b525bf` ("feat: page names editable from the
  offering/framework card (B6)"):
  - Added `GtmPageContentController.renamePage(offeringKey, templateType,
    title)`, which writes the override to a reserved, never-rendered
    content address `<offeringKey>::<templateType>::page::title`
    (`Section_Key__c = 'page'`, `Field_Key__c = 'title'` on the existing
    `GTM_Page_Content__c` object) — explicitly modeled on the existing
    `renameOffering`, and, per its own commit message, the same
    reuse-the-existing-object pattern B1 used for the CMS-editable FAQ
    widget (commit `8171624`: "reuses the existing `MA_Page_Content__c` /
    `MA_Page_Section__c` content-address mechanism rather than a new
    object" — i.e. an addressable content key, not a new field).
  - Added a `pageTitles` map (`GtmPageContentController.HomeSummary`,
    keyed `"<offeringKey>::<templateType>"`) returned from
    `getHomeSummary()`, read back as an override over `TEMPLATE_LABELS`.
  - Wired a rename icon + inline Save/Cancel row into
    `gtmContentHome.js`/`.html`/`.css` (the Content Manager home
    dashboard's page list) only.
  - Its commit message states "No new permission-set grants needed —
    reuses `GTM_Page_Content__c` columns already fully granted."

  **So there is no unresolved content-model fork left for the Architect
  to decide from scratch.** The correct Architect action is to *ratify*
  "reuse the existing address scheme exactly as built in `1b525bf`," not
  re-open a field-vs.-addressable-key debate a prior pass already closed
  and shipped. Picking a different mechanism now (e.g. a dedicated field)
  would create a second, conflicting way to name a page alongside the one
  already live in `gtm-dev`.

  **What issue #40 is actually still asking for, once `1b525bf` is
  accounted for:** `1b525bf` only wired the override into `gtmContentHome`
  (the Content Manager's home/dashboard page list). Every other
  `TEMPLATE_LABELS` consumer still reads the hardcoded constant directly
  and ignores `pageTitles`, so a page renamed from the home dashboard
  still shows its old hardcoded name everywhere else — including "their
  own picker," which is literally what the issue title calls out (the
  Content Manager editor's own template picker is a *different* component
  from the home dashboard `1b525bf` touched). Confirmed by reading each
  consumer:
  - `force-app/main/default/lwc/gtmContentManager/gtmContentManager.js`
    (line 277, `loadTemplates()`'s card labels; line 701,
    `selectedTemplateLabel` getter/breadcrumb) — the Content Manager
    editor's own template-picker cards and header. **Not touched by
    `1b525bf` at all**, and this is the surface the issue title names.
    It already has `this.selectedOffering` in scope, so it has what it
    needs to look up an override — it just doesn't ask for one.
  - `force-app/main/default/lwc/gtmOverview/gtmOverview.js` (line 11) —
    defines its own **second, independently hardcoded** `TEMPLATE_LABELS`
    object rather than importing the one from `gtmPageLayouts.js`. It is
    already out of sync even from the old hardcoded baseline (missing
    `offerings-page`, `faq-bd`, `faq-content-manager`, `assistant`
    entirely — those templateTypes fall back to raw slug text there
    today), and applies no override either.
  - `force-app/main/default/lwc/gtmFeedbackQueue/gtmFeedbackQueue.js`
    (line 45) — imports the real `TEMPLATE_LABELS` from `gtmPageLayouts`
    but applies no `pageTitles`-style override, so a renamed page's
    feedback-queue entries still show the old name.
  - `GtmPageContentController.cls` only populates `pageTitles` inside
    `getHomeSummary()` (lines ~518-535) — there is no equivalent exposed
    from `getTemplateSummary()` (what `gtmContentManager` calls to build
    its picker) or from any Apex method `gtmOverview`/`gtmFeedbackQueue`
    call, so those three surfaces have no server-side data to read a
    rename from even if their JS asked for one.

- **System Component Impacted:** LWC (`gtmContentManager`, `gtmOverview`,
  `gtmFeedbackQueue`) + Apex (`GtmPageContentController` — extending
  whichever method backs `gtmContentManager`'s `getTemplateSummary`, and
  any equivalent lookup `gtmOverview`/`gtmFeedbackQueue` should call, to
  also surface the existing `pageTitles`-style override). No Experience
  Cloud route, Custom Metadata, or YAML instrument changes.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **No.** None of the affected files
      (`gtmContentManager`, `gtmOverview`, `gtmFeedbackQueue`,
      `GtmPageContentController`) implement `GtmAgentToolSurface` or sit
      in GUS's tool-call path (`GtmAgentProxyController`,
      `GtmAgentGetConfigState`/`GtmAgentApplyConfigUpdate`,
      `GtmReadoutAgentSurface`). AGENTS.md §1's zero-DML-in-tool rule does
      not apply.
- [ ] Altering Custom Metadata? **No.** Page titles live on
      `GTM_Page_Content__c` (a standard custom object, reserved-address
      row), not on any `GTM_*__mdt` Custom Metadata Type — no
      `migration-accelerator/` YAML or `customMetadata/GTM_Assessment_*`
      XML is touched by this scope.
- [ ] Introducing database fields? **No new field or object.** This scope
      only reads the already-existing address
      (`Section_Key__c='page'`/`Field_Key__c='title'` on
      `GTM_Page_Content__c`) from additional call sites; `renamePage()`
      and the underlying schema already exist. The prior commit's message
      claims no new permission-set grant was needed because those
      `GTM_Page_Content__c` columns were already fully granted — **the
      Architect/Developer step must verify this directly** (diff
      `GTM_Content_Manager.permissionset-meta.xml` and
      `GTM_Content_Admin.permissionset-meta.xml`'s existing
      `GTM_Page_Content__c` field grants for `Text_Value__c`,
      `Section_Key__c`, `Field_Key__c`, `Template_Type__c`,
      `Offering_Key__c`) rather than trusting an unverified prior claim,
      per this repo's own docs-drift caveat. If a gap is found, it is an
      addition to a `fieldPermissions` entry on the existing object for
      `GTM_Content_Manager` (read access — this scope's three surfaces
      are all read paths) and, if not already present, `GTM_Content_Admin`
      (already full CRUD/FLS on the object per CLAUDE.md §6) — not a new
      object/field mapping exercise, since the schema itself pre-exists.
      `GTM_Offering_User`/`GTM_Offering_Admin`/`GTM_Guest` are unaffected:
      `gtmOverview` and `gtmFeedbackQueue` run under `GTM_Offering_User`,
      which needs the same read-only confirmation as
      `GTM_Content_Manager` above if it does not already carry it —
      confirm this permission set too, not just the Content ones.

## 3. Plan Acceptance Criteria

- **Success Metric:** A page renamed once, via `gtmContentHome`'s
  existing (`1b525bf`) rename control, shows the new name consistently
  everywhere a page name is displayed, with no second/parallel renaming
  mechanism introduced:
  1. `gtmContentManager`'s template-picker cards (`loadTemplates()`) and
     its `selectedTemplateLabel` breadcrumb/header both reflect the
     override, resolved via the same `<offeringKey>::<templateType>`
     `pageTitles` shape `getHomeSummary()` already returns (either by
     having `gtmContentManager` also call `getHomeSummary()`/a new
     lightweight equivalent, or by extending `getTemplateSummary()` to
     include the override per row — left to the Architect/Developer to
     choose based on payload size and existing call patterns, not
     specified further here).
  2. `gtmOverview`'s locally-duplicated `TEMPLATE_LABELS` constant is
     removed in favor of importing the canonical one from
     `gtmPageLayouts.js` (fixing the pre-existing `offerings-page`/
     `faq-bd`/`faq-content-manager`/`assistant` omissions as a direct
     side effect), and applies the same override.
  3. `gtmFeedbackQueue` applies the override too, so a feedback item's
     "page" column matches the page's current name.
  4. No regression to `gtmContentHome`'s existing `1b525bf` rename
     UI/flow (rename icon, inline Save/Cancel, `renamePage` Apex call).
- **Target Test Target:** New/extended Jest specs —
  `force-app/main/default/lwc/gtmContentManager/__tests__/gtmContentManager.test.js`
  (assert `selectedTemplateLabel` and template-card labels prefer an
  override over `TEMPLATE_LABELS`) and
  `force-app/main/default/lwc/gtmOverview/__tests__/gtmOverview.test.js`
  (assert the local `TEMPLATE_LABELS` duplicate is gone, every
  `gtmPageLayouts.js` template type resolves to a real label, and an
  override wins when present) — confirm each spec file exists already
  before assuming it needs only extension versus net-new creation. If the
  Architect/Developer step extends an Apex method (e.g.
  `getTemplateSummary`) to return per-template override titles, add
  coverage to `force-app/main/default/classes/GtmPageContentControllerTest.cls`.
