# TASK SCOPE — ISSUE #industry-variant-ui-scoping-fix

## 0. Series Context & Dependency

Bug fix against already-merged, live functionality from the "Industry-Specific
Section Variants" series (`task-scope-industry-variants-core.md`,
`task-scope-industry-variants-visibility-nav.md`, PRs #17/#18/#23, all merged
to `main`). This is not a new issue in that series — it is a correction to
UI scoping the series shipped too broadly. No dependency on any other open
worktree; can proceed standalone against current `main`.

## 1. Requirements Breakdown

- **Target Objective:** The product owner (isiah@eawpublications.com) took a
  live screenshot of `GTM Content Manager > Migration Accelerator > All
  pages > Offerings Listing` (Content Address
  `migration-accelerator::offerings-listing::tile`, footer "gtm-offerings —
  shared front door"). The rail shows an "Industry view" toggle and a
  "+ Industry variant" button on the one section present. Neither control
  makes sense here: "Offerings Listing" is the tile through which
  Migration Accelerator (or any offering) introduces itself on the shared,
  cross-offering "choose your offering" page — every offering has exactly
  one, and there is no concept of an industry-specific variant of a tile a
  prospect sees before they have chosen (or been assigned) any offering at
  all. Fix: hide/condition the "Industry view" toggle and "+ Industry
  variant" button so they only render on the one template type where
  industry variants are a real capability — `configurator` — and do not
  render for any other template type (`story`, `offerings-listing`,
  `offerings-page`, `industry-chooser`, `faq-bd`, `faq-content-manager`,
  `assistant`).

- **System Component Impacted:** LWC only —
  `force-app/main/default/lwc/gtmContentManager/gtmContentManager.html` and
  `gtmContentManager.js`. No Apex, no schema, no custom metadata changes are
  required (see root-cause evidence below — the gap is purely in what the
  UI renders, not in what the server allows or validates).

### Root-cause evidence (read, not guessed)

1. **The only template with industry-aware content is `configurator`.**
   `force-app/main/default/lwc/gtmPageLayouts/gtmPageLayouts.js` line
   202-206, `TEMPLATE_LAYOUTS`:
   ```
   configurator: ['chapter-cards', 'chapter-lede', 'chapter-proof', 'chapter-phases',
                  'chapter-close', 'offering-defaults', 'industry-profile'],
   'offerings-listing': ['offering-tile'],
   ```
   Only `configurator` carries the `industry-profile` layout. `offerings-listing`
   carries only `offering-tile`, with this comment right above it (lines
   206-208): "The offerings page draws its tiles from the offerings
   themselves, so there is nothing to add to it beyond the chrome it already
   has." `OFFERING_TEMPLATES` (line 413) is `['story', 'configurator',
   'offerings-listing']` — three per-offering template types, and only one of
   them is industry-aware.

2. **The rail controls render unconditionally, with no template check at
   all.** `gtmContentManager.html`:
   - Line 210-217: the "Industry view" toggle button (`gcm-industry-toggle`,
     `handleToggleIndustryView`) sits directly inside
     `<template if:false={settingsOpen}>` — the *only* gating condition is
     "not in settings mode." No `selectedTemplate`/`isFrameworkPage`/
     `isIndustryPage`-style check wraps it, unlike the industry-chooser-only
     "Add industry" button at line 332 (`<template if:true={isIndustryPage}>`)
     which *does* use exactly this pattern for a different piece of UI.
   - Line 297-299: the `+ Industry variant` button (`sec-variant-add`,
     `handleOpenVariant`) sits inside the generic `for:each={railSections}`
     loop (line 266) with no conditional wrapper at all — it renders for
     every section on every page, including `offerings-listing::tile`,
     `story` sections, and framework pages.

3. **The JS getters that already exist for exactly this kind of scoping are
   not reused here.** `gtmContentManager.js` already has
   `get isFrameworkPage()` (line 937: `this.selectedOffering ===
   FRAMEWORK_KEY`) and `get isIndustryPage()` (line 999-1001:
   `this.selectedOffering === FRAMEWORK_KEY && this.selectedTemplate ===
   'industry-chooser'`), used to scope the "Add industry" button and the
   add-section modal's copy. No equivalent `get supportsIndustryVariants()`
   (or similar) exists to scope the toggle/button being fixed here — the gap
   is that this specific piece of UI was never given the same treatment.

4. **The server has no restriction either — confirming this is a pure UI
   gap, not a mask over a real capability someone actually wanted enabled
   broadly.** `GtmPageSectionController.createSection` (`.cls` line
   253-293) accepts any `offeringKey`/`templateType` combination for a
   variant create (`isVariant` branch, line 272) with no allow-list check
   against `configurator`; `GtmPageContentController.createSection` (line
   190-199) is a thin pass-through. If a content editor had used the button
   on `offerings-listing::tile` before this bug was reported, the write
   would have silently succeeded and created an orphaned, meaningless
   industry-tagged copy of a shared tile with no renderer path that ever
   reads `industryKey` for that template (`STARTER_PAGES['offerings-listing']`,
   `gtmPageLayouts.js` line 336-338, has exactly one section, `tile`, and no
   industry-variant concept in its shape).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO — this issue never touches Apex.
      `grep -rn "gtmContentManager" force-app/main/default/classes/GtmAgentToolSurface.cls`
      → no hits (the LWC is not in the tool surface at all).
- [ ] Altering Custom Metadata? NO.
- [ ] Introducing database fields? NO — no schema change. This is a
      client-side render-condition fix only.

## 3. Detailed Scope

### Chosen approach

Option (a) from the brief, using the **existing** `TEMPLATE_LAYOUTS`/
`OFFERING_TEMPLATES` data already in `gtmPageLayouts.js` as the allow-list —
no new metadata flag needed, because the code already encodes "which
templates are industry-aware" via the presence of the `industry-profile`
layout key in `TEMPLATE_LAYOUTS['configurator']` and nowhere else. Do not
introduce a parallel/duplicate hard-coded list in `gtmContentManager.js`;
derive the check from `selectedTemplate === 'configurator'` (the one
existing template type with `industry-profile`), matching the same
`this.selectedTemplate === '...'`/`isFrameworkPage`/`isIndustryPage` idiom
already used elsewhere in this file (see root-cause item 3). If, during
implementation, the Developer finds a second template type is added to
`TEMPLATE_LAYOUTS` with `industry-profile` in the future, prefer checking
`TEMPLATE_LAYOUTS[this.selectedTemplate].includes('industry-profile')`
(imported from `c/gtmPageLayouts`) over a literal `=== 'configurator'`
string, so the allow-list has exactly one source of truth — the Developer
should pick whichever is more consistent with the rest of the file's
existing style once they're looking at it in context.

### LWC changes

- `gtmContentManager.js`:
  - Add a new getter, e.g. `get supportsIndustryVariants()`, returning
    whether `this.selectedTemplate` is industry-variant-capable (see chosen
    approach above).
  - `handleToggleIndustryView` should be a no-op (or the toggle simply not
    rendered — see HTML changes) when `!this.supportsIndustryVariants`, so a
    stale click from before a page switch cannot leave `industryView: true`
    stuck on for a template that then hides its own exit control.
  - When `selectedTemplate`/`selectedOffering` changes and
    `!this.supportsIndustryVariants`, reset `industryView` to `false` (mirror
    whatever pattern `handleSelectTemplate`/`handleSelectOffering` already
    use to reset other per-template UI state — Developer to confirm exact
    reset site).
- `gtmContentManager.html`:
  - Line ~211-217: wrap the `gcm-industry-toggle` button (and by extension
    the `industryView`/`hasIndustryFilter` blocks at lines 219-262, which are
    only reachable by toggling it) in
    `<template if:true={supportsIndustryVariants}>`.
  - Line ~297-299: wrap the `sec-variant-add` (`+ Industry variant`) button
    in the same `<template if:true={supportsIndustryVariants}>` condition,
    scoped per the `railSections` loop item (this button is per-section, but
    the condition is per-page/template, not per-section — every section on a
    `configurator` page should get it, none on any other template).

### Explicitly not touched

- `isFrameworkPage`, `isIndustryPage`, the "Add industry" button, and the
  industry-chooser add-section flow — unrelated, already correctly scoped.
- Apex (`GtmPageSectionController.cls`, `GtmPageContentController.cls`,
  `GtmPageContentReader.cls`) — no change. A defensive server-side guard
  against creating an industry variant for a non-`configurator` template
  would be reasonable *hardening* but is out of scope for this bug fix
  (the reported bug is what the UI shows, not a data-integrity incident);
  flag it in `docs/backlog.md` as a follow-up if the Developer/Architect
  agree it's worth a small separate PR, but do not fold it into this fix.
- No change to `TEMPLATE_LAYOUTS`, `OFFERING_TEMPLATES`, `STARTER_PAGES`, or
  any other data in `gtmPageLayouts.js` — that data is already correct;
  only the LWC's consumption of it needs a fix.

## 4. Non-Goals (this issue)

- Not a redesign of the industry-variants system — `configurator` pages keep
  every current toggle/button/behavior exactly as-is.
- Not a cleanup of any pre-existing orphaned variant data. If manual QA (or
  the Developer, incidentally) finds an industry-variant section already
  created under a non-`configurator` template in `gtm-staging` from before
  this fix, note it in the scope hand-off / QA report but do not silently
  delete data — that decision needs the product owner.
- No new metadata flag/field on template or page records — the existing
  `TEMPLATE_LAYOUTS` allow-list already carries this information; adding a
  redundant flag would be a second source of truth to keep in sync for no
  benefit.

## 5. Plan Acceptance Criteria

- **Success Metric:** On
  `migration-accelerator::offerings-listing::tile` (and any other
  non-`configurator` template/page, including all `FRAMEWORK_TEMPLATES`:
  `offerings-page`, `industry-chooser`, `faq-bd`, `faq-content-manager`,
  `assistant`), the rail shows neither the "Industry view" toggle nor any
  "+ Industry variant" button. On any offering's `configurator` page (e.g.
  Migration Accelerator's actual prospect-facing configurator), both
  controls still render and behave exactly as before this fix — no
  regression to the already-shipped industry-variants feature. Switching
  between a `configurator` page and any other template/page in the same
  session correctly shows/hides the controls each time, with no stuck state
  (e.g. `industryView` left `true` after navigating away and back).
- **Target Test Target:** New Jest specs in
  `force-app/main/default/lwc/gtmContentManager/__tests__/` asserting the
  toggle and button are absent from the rendered DOM when
  `selectedTemplate` is `offerings-listing`, `story`, `offerings-page`,
  `industry-chooser`, `faq-bd`, `faq-content-manager`, or `assistant`, and
  present when it is `configurator`. Manual QA: load
  `migration-accelerator::offerings-listing::tile` in `gtm-staging` (or via
  `npm test` local component render, if staging data isn't loaded) and
  visually confirm parity with the reported screenshot's fix — no Industry
  view toggle, no + Industry variant button — then load Migration
  Accelerator's `configurator` page and confirm both controls are still
  present and functional (open the modal, pick an industry, cancel without
  saving to avoid writing test data).
