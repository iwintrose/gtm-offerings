# TASK SCOPE — ISSUE #industry-variants-visibility-nav

## 0. Series Context & Dependency

Issue 2 of 4 in the "Industry-Specific Section Variants" series (product
owner isiah@eawpublications.com approved). **Hard dependency:**
`docs/agent-artifacts/task-scope-industry-variants-core.md` (issue
`industry-variants-core`) must be merged first — this issue's
`variantSectionsByBase` reuse and rail grouping assume the core object
model (`Industry_Key__c`/`Base_Section_Key__c` on `GTM_Page_Section__c`) and
the base "+ Industry variant" rail UI already exist. Do not start this
issue's worktree until core is merged to `main`.

## 1. Requirements Breakdown

- **Target Objective:** Let a content editor (a) fully hide a base section
  for a given industry (not just override its copy), (b) reorder a section
  for one industry only without affecting any other industry or the
  generic view, and (c) browse/manage all of this per-industry through a
  new "Industry view" toggle in the Content Manager rail, since the rail is
  confirmed flat/single-level today with no existing nesting to extend
  (verified: `force-app/main/default/lwc/gtmContentManager/gtmContentManager.html`
  lines 193-262 render one flat list of sections; Developer must re-confirm
  exact current line numbers before editing since core-issue work will have
  already touched this file).
- **System Component Impacted:** Apex (`GtmPageContentReader.cls`,
  `GtmPageSectionController.cls`), Custom Object schema (two more fields on
  `GTM_Page_Section__c`), LWC (`gtmContentManager`), Permission Sets.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO — confined to
      `GtmPageContentReader.cls`/`GtmPageSectionController.cls`, neither in
      `GtmAgentToolSurface.cls` (same check as core issue, re-verified for
      this file set: `grep -rn "GtmPageSectionController\|GtmPageContentReader" force-app/main/default/classes/GtmAgentToolSurface.cls` → no hits).
- [x] Altering Custom Metadata? NO — two more **Custom Object** fields on
      `GTM_Page_Section__c` (not `GTM_Assessment_*` Custom Metadata Type
      records), same distinction as the core issue.
- [x] Introducing database fields? YES:
      - `Hidden_For_Industry__c` (Long Text Area or a multi-select
        picklist-backed list field — Developer to pick the concrete field
        type during implementation based on the industry-slug set's
        stability; plan specifies it holds a list of industry slugs that
        exclude a base section entirely for that industry).
      - `Industry_Sort_Overrides__c` (Long Text Area, JSON —
        `{"healthcare": 25}`-shaped, reorders a section for one industry
        only).
      Both need explicit `fieldPermissions` entries added to
      `GTM_Content_Manager.permissionset-meta.xml` and
      `GTM_Content_Admin.permissionset-meta.xml`, same as the core issue's
      two fields — mandatory per CLAUDE.md §6, not optional cleanup.

## 3. Detailed Scope

### Object model additions
- `Hidden_For_Industry__c` — list of industry slugs a base section is
  excluded for.
- `Industry_Sort_Overrides__c` — JSON map of industry slug to sort order,
  scoped to that one industry only; does not touch `Sort_Order__c` (the
  generic/default order, owned by the core issue's fields, stays untouched).

### Apex changes
- `GtmPageContentReader.getPageLayout` — extend the core issue's
  `variantSectionsByBase` into a new `resolveForIndustry(baseSections,
  industryKey)` that is the single resolution point for: (a) skip a section
  entirely if `industryKey` is present in its `Hidden_For_Industry__c`, (b)
  substitute the variant if one exists (reusing core-issue logic), (c)
  apply `Industry_Sort_Overrides__c[industryKey]` to that section's sort
  value, then re-sort the final list. Developer must not duplicate
  resolution logic elsewhere — this method is explicitly meant to be the
  only place industry-aware layout resolution happens.
- New `GtmPageSectionController.setSectionHiddenForIndustry(sectionId,
  industryKey, hidden)` — toggles membership in `Hidden_For_Industry__c`.

### LWC changes
- `gtmContentManager.js`/`.html` — add an "Industry view" toggle at the top
  of the rail. Selecting an industry filters/annotates the rail so each
  base section shows one of three states: Generic / Customized (links to
  its variant, from the core issue's UI) / Hidden (toggle to un-hide, calls
  `setSectionHiddenForIndustry`). Also add drag reordering scoped to that
  industry, writing `Industry_Sort_Overrides__c` (reuse the existing drag
  mechanism if one exists for generic ordering — Developer to confirm
  during implementation; if none exists, this is new UI work, not just
  wiring). New `industryView` state flag and `industryFilterKey` in
  `gtmContentManager.js`. New rail-body template variant in the `.html`.
  Reuses `getIndustryProfiles` for the industry picker (same call the core
  issue's "+ Industry variant" modal uses).

## 4. Non-Goals (this issue)

- No drafted Migration Accelerator copy — `task-scope-industry-variants-content-load.md`.
- No Agentforce drafting assistant — `task-scope-industry-variants-agentforce-draft.md`.
- Does not change the generic/default `Sort_Order__c` or the base
  "+ Industry variant" creation flow — that stays exactly as built in the
  core issue.
- No live per-visitor personalization.

## 5. Plan Acceptance Criteria

- **Success Metric:** For any industry, hiding a section removes it from
  that industry's prospect-facing layout only; reordering a section for one
  industry does not change any other industry's order or the generic
  order; the rail's Industry view correctly labels every base section as
  Generic/Customized/Hidden for the selected industry and un-hiding works
  from the rail.
- **Target Test Target:** New Apex tests in `GtmPageContentReaderTest.cls`
  covering `resolveForIndustry` (hide, sort-override, combination with a
  variant substitution) and in `GtmPageSectionControllerTest.cls` for
  `setSectionHiddenForIndustry`; Jest specs for the new rail industry-view
  mode in `force-app/main/default/lwc/gtmContentManager/__tests__/`; manual
  QA per the approved plan's Verification step 6 — Industry view rail mode
  checked across all 9 industries (see
  `task-scope-industry-variants-content-load.md` for the industry list),
  confirming reordering one industry doesn't affect others.
