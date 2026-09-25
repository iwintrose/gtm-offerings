# TASK SCOPE — ISSUE #industry-variants-core

## 0. Series Context

This is issue 1 of 4 in the "Industry-Specific Section Variants" series, approved
by the product owner (isiah@eawpublications.com):

1. **industry-variants-core** (this doc) — object model, Apex, base rail UI for creating/publishing an industry variant.
2. **industry-variants-visibility-nav** — depends on #1 — per-industry hide/reorder + "Industry view" rail sub-nav.
3. **industry-variants-content-load** — depends on #1 (and benefits from #2 for QA, but not blocked by it) — drafted copy for Migration Accelerator, 9 industries x 4 sections, loaded via a staged one-time data script.
4. **industry-variants-agentforce-draft** — depends on #1 — Track A "Draft with AI" authoring aid. Track B (live Data Cloud personalization) is explicitly NOT scoped for building in any of these four docs.

## 1. Requirements Breakdown

- **Target Objective:** Let a content editor create a whole-section content
  variant of an existing page section, scoped to one industry, so that
  `GtmPageContentReader` (which already prefers an `Industry_Key__c`-tagged
  `GTM_Page_Content__c` row when one exists — confirmed at
  `force-app/main/default/classes/GtmPageContentReader.cls` lines 31-37 and
  144-148) has something real to select between. Today no code path ever
  writes `Industry_Key__c`, so the field is inert; verified via
  `grep -rn "Industry_Key" force-app/main/default/classes/GtmPageSectionController.cls`
  returning zero hits, and via `grep -rn "industryKey\|Industry_Key"` across
  `gtmContentManager.js`/`gtmFieldEditor.js` returning only an unrelated
  `industryKeyPreview` getter used by the pre-existing, unrelated "Add
  industry" (Industry Chooser taxonomy tile) modal in
  `force-app/main/default/lwc/gtmContentManager/gtmContentManager.js`
  (lines 802, 809).
- **System Component Impacted:** Apex (`GtmPageSectionController.cls`,
  `GtmPageContentReader.cls`), Custom Object schema
  (`GTM_Page_Section__c` new fields), LWC
  (`gtmContentManager`, `gtmFieldEditor`), Permission Sets.
- **Scope boundary:** whole-section variants only (decided already, not
  per-field overrides — this is a closed design question, not left open for
  the Architect). This is a general Content Manager capability, not scoped
  to Migration Accelerator alone, even though Migration Accelerator is the
  first adopter (see issue #industry-variants-content-load).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO — this issue does not touch
      `GtmAgentToolSurface.cls` or any GUS-facing Apex; verified this issue's
      Apex changes are confined to `GtmPageSectionController.cls` and
      `GtmPageContentReader.cls`, neither of which is part of the GUS tool
      surface (`grep -rn "GtmPageSectionController\|GtmPageContentReader" force-app/main/default/classes/GtmAgentToolSurface.cls`
      returns no hits).
- [x] Altering Custom Metadata? NO — these are two new **Custom Object
      fields** on `GTM_Page_Section__c` (a real sObject, confirmed present at
      `force-app/main/default/objects/GTM_Page_Section__c/fields/`, currently
      containing `Active__c`, `Archived_Date__c`, `Archived__c`,
      `Draft_State__c`, `Help_Text__c`, `Label__c`, `Layout_Type__c`,
      `Offering_Key__c`, `Offering_Status__c`, `Section_Address__c`,
      `Section_Key__c`, `Sort_Order__c`, `Status__c`, `Template_Type__c`,
      `Width__c` — no `Industry_Key__c` or `Base_Section_Key__c` yet), not
      Custom Metadata Type records under
      `force-app/main/default/customMetadata/GTM_Assessment_*`. The
      "do not hand-edit generated XML" rule in CLAUDE.md §2 applies to the
      `GTM_Assessment_*` metadata build output only, not this object's field
      XML, so field-meta XML for the two new fields is authored directly by
      the Developer, not through `scripts/build-instrument.py`.
- [x] Introducing database fields? YES — two new fields on
      `GTM_Page_Section__c`:
      - `Industry_Key__c` (Text, 80) — set only on variant rows; matches the
        industry slug convention already used by
        `GTM_Page_Content__c.Industry_Key__c`.
      - `Base_Section_Key__c` (Text, 80) — set only on variant rows; points
        back to the base section's `Section_Key__c`.
      Mapping to Permission Sets is mandatory (CLAUDE.md §6): add explicit
      `fieldPermissions` entries for both fields to
      `force-app/main/default/permissionsets/GTM_Content_Manager.permissionset-meta.xml`
      and `GTM_Content_Admin.permissionset-meta.xml` (Admin keeps the
      object's existing `viewAllRecords`/`modifyAllRecords` setting — do not
      widen it). No other permission set needs these fields (`GTM_Offering_User/Admin`
      and `GTM_Guest` don't touch page-section authoring).

## 3. Detailed Scope

### Object model
- `GTM_Page_Section__c` gains `Industry_Key__c` (Text 80) and
  `Base_Section_Key__c` (Text 80), both null on base/generic sections.
- A variant is its own `GTM_Page_Section__c` row. Its `Section_Key__c` is
  derived as `<baseKey>--<industrySlug>` (e.g. `problem--healthcare`).
- Variant's `GTM_Page_Content__c` field rows are stamped with the same
  `Industry_Key__c` slug (this reuses the existing field, no schema change
  needed there — confirmed already present per `GtmPageContentReader.cls`
  line 31).

### Apex changes
- `GtmPageSectionController.createSection` (currently at line 140, signature
  to be read in full by the Developer before editing) — add optional
  `industryKey`/`baseSectionKey` params. Validate the base section exists
  and that no variant already exists for that `(base, industry)` pair (query
  guard, not just a UI-side check — prevents duplicate variants from
  concurrent requests). Derive the `<baseKey>--<industrySlug>` key. Seed the
  variant's fields from a snapshot of the base section's *current* fields,
  passed in by the client (`fieldsSnapshotFor`, see LWC section below) —
  not a blank layout.
- `GtmPageSectionController.createField` (currently at line 315) — add
  optional `industryKey` param, stamp onto the new `GTM_Page_Content__c`
  row.
- `GtmPageSectionController.getEditorSections` (currently at line 20,
  SELECT list confirmed at lines 26-28: `Section_Key__c, Label__c,
  Help_Text__c, Layout_Type__c, Width__c, Sort_Order__c, Active__c,
  Status__c, Draft_State__c`) — add `Industry_Key__c`, `Base_Section_Key__c`
  to the SELECT and to the `EditorSection` DTO.
- `deleteSection`/`restoreSection`/`saveSectionOrder`/`publishPage`/
  `discardDrafts` — expected no code changes since they operate generically
  on section rows regardless of variant status; Developer must add at least
  one new Apex test asserting variant publish/discard works end to end
  (do not just assume "generic" is safe without a test).
- `GtmPageContentReader` — add a new private helper,
  `variantSectionsByBase(offeringKey, templateType, industryKey)`, that
  finds the Published/Active variant per base section. Wire it into:
  - `getPageContent` — remap variant rows from
    `<variantKey>::<fieldKey>` to `<baseKey>::<fieldKey>` (whole-section
    swap, so the prospect-facing template code doesn't need to know about
    variant keys).
  - `getPageLayout` — substitute the variant's `Label__c`/`Layout_Type__c`/
    `Width__c` for the base's, but keep the base's `sectionKey` and
    `Sort_Order__c` (ordering is untouched in this issue; see
    #industry-variants-visibility-nav for per-industry ordering).
  - `getFieldMeta` — same remap; Developer must verify this method needs
    the same treatment during implementation (plan flags this as
    "verify," not settled).
  - `getIndustryProfiles` is explicitly untouched.

### LWC changes
- `gtmContentManager.js`/`.html` — group variant sections under their base
  section in the rail. Clicking a variant chip sets `activeKey` the same way
  clicking any other section does — no new selection mechanism to build.
  Add a new "+ Industry variant" modal, modeled on the existing "Add
  industry" modal (Industry Chooser taxonomy tile creation, confirmed to
  exist around lines 780-882 of `gtmContentManager.js` — Developer must
  re-check the exact current line range before copying, since this is a
  live file). The new modal lists industries via the existing
  `getIndustryProfiles('gtm','industry-chooser')` call, filtered to exclude
  industries that already have a variant for that base section. Add a new
  `fieldsSnapshotFor(sectionKey)` helper used to seed `createSection`'s new
  snapshot param. Reuse the existing delete/hide affordances for variants —
  do not build new ones.
- `gtmFieldEditor.js` — thread a new `@api industryKey` through to
  `createField` calls. Optional "Editing: `<Section>` — `<Industry>`
  variant" header banner (nice-to-have, not launch-blocking if time is
  short — flag to QA either way).
- `gtmPagePreview` — expected no changes; Developer must verify during
  implementation rather than assume.
- `gtmPageLayouts.js` — no changes.

## 4. Non-Goals (this issue)

- No per-industry visibility/hide, no per-industry reorder, no "Industry
  view" rail sub-navigation mode — that is
  `docs/agent-artifacts/task-scope-industry-variants-visibility-nav.md`.
- No drafted Migration Accelerator copy content — that is
  `docs/agent-artifacts/task-scope-industry-variants-content-load.md`.
- No Agentforce/"Draft with AI" authoring aid — that is
  `docs/agent-artifacts/task-scope-industry-variants-agentforce-draft.md`.
- No per-field override mechanism (already decided: whole-section only).
- No live per-visitor content generation.

## 5. Plan Acceptance Criteria

- **Success Metric:** A content editor can, on any offering's configurator
  page, click "+ Industry variant" on a section, pick an industry, get a
  pre-seeded copy of that section's current fields, edit it, and publish
  it. After publish, `GtmPageContentReader.getPageContent`/`getPageLayout`
  return the variant's content/layout for that industry and the unmodified
  base content for every other industry and for the generic (no-industry)
  case. FLS for the two new fields is confirmed present on
  `GTM_Content_Manager`/`GTM_Content_Admin` and confirmed absent (no
  regression) elsewhere.
- **Target Test Target:** New/updated Apex tests in
  `force-app/main/default/classes/GtmPageSectionControllerTest.cls` (create
  section/field with industry params, duplicate-variant guard, variant
  publish/discard) and
  `force-app/main/default/classes/GtmPageContentReaderTest.cls` (variant
  resolution in `getPageContent`/`getPageLayout`/`getFieldMeta`); Jest specs
  for `force-app/main/default/lwc/gtmContentManager/__tests__/` and
  `force-app/main/default/lwc/gtmFieldEditor/__tests__/` covering the new
  modal and the `industryKey` field-editor plumbing; manual QA per
  §Verification steps 1-5 of the approved plan (staging validate-only
  deploy, Apex tests, `npm test`, manual create/publish/prospect-page
  check, FLS confirmation).
