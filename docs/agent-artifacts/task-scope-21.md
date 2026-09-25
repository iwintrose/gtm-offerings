# TASK SCOPE — ISSUE #21

## 1. Requirements Breakdown

- **Target Objective:** `GtmPageContentController.renamePage(offeringKey, templateType, title)` and its
  UI wiring in `gtmContentHome.js`/`gtmContentHome.html` currently allow renaming the display title of
  **any** page in the app, including the fixed, structural/Framework page types. Neither layer has a
  gate excluding those page types from the rename affordance. The fix must block renaming for the
  canonical structural page-type set so the product-owner requirement ("should not be able to rename the
  [structural] pages") actually holds, both through the UI and through direct Apex/API calls.

  Evidence this gap exists today (verified live against `main`, not the plan doc):
  - `force-app/main/default/classes/GtmPageContentController.cls:594-619` — `renamePage()` validates only
    that `offeringKey`/`templateType`/`title` are non-blank and truncates to 120 chars. There is no
    check against `templateType` at all before it upserts the `page::title` override row.
  - `force-app/main/default/lwc/gtmContentHome/gtmContentHome.js:593-628` (`handleStartPageRename`,
    `handleSavePageRename`) — no `canRename`-style flag is read or checked; the handlers act on
    whatever `data-template`/`data-offering` the clicked row carries.
  - `force-app/main/default/lwc/gtmContentHome/gtmContentHome.js:248-276` (the `pages` array built per
    card) — every entry returned by `templatesFor(o.offeringKey)` (minus `SETTINGS_TEMPLATES`) gets an
    identical row shape; there is no per-template `canRename` field computed or threaded through.
  - `force-app/main/default/lwc/gtmContentHome/gtmContentHome.html:118-124` and the duplicate block at
    `:243-249` — the `pg-rename` edit-icon `<button>` is rendered unconditionally for every page row
    (`<template if:false={p.isRenaming}>` — no `if:true={p.canRename}` or similar guard wraps it).

  This directly contradicts `docs/agent-artifacts/content-manager-ia-plan.md` §3.2 ("There is currently
  **no** UI or Apex path that renames a `Layout_Type__c`/`TEMPLATE_LABELS` page title ... this already
  matches what the PO wants ... no change needed here"). That claim is **false** as of current `main`;
  QA's finding (source of this issue) is correct. The plan text itself even lists the exact set of names
  to protect (Offerings Page, Industry Chooser, BD App Help FAQ, Content Manager Help FAQ, Story,
  Configurator, Offerings Listing), which lines up with what's below.

  **Canonical protected-title list**, taken from the single source of truth for template types,
  `force-app/main/default/lwc/gtmPageLayouts/gtmPageLayouts.js:431-440` (`TEMPLATE_LABELS`), cross-checked
  against the framework/offering split at lines 413/425 (`OFFERING_TEMPLATES`, `FRAMEWORK_TEMPLATES`):

  | `templateType` | `TEMPLATE_LABELS` display name | Owner |
  |---|---|---|
  | `offerings-page` | Offerings Page | Framework |
  | `industry-chooser` | Industry Chooser | Framework |
  | `faq-bd` | BD App Help (FAQ) | Framework |
  | `faq-content-manager` | Content Manager Help (FAQ) | Framework |
  | `story` | Story | Offering |
  | `configurator` | Configurator | Offering |
  | `offerings-listing` | Offerings Listing | Offering |
  | `assistant` | Assistant | Framework (Settings, not a "page" row — see below) |

  All eight are structural: `TEMPLATE_LAYOUTS`/`STARTER_PAGES` (`gtmPageLayouts.js:202-226`,
  `:328-388`) hard-code what each one is built from, and Apex/SOQL key off `templateType` directly
  (`GtmPageContentController.cls:588-590` comment: "templateType itself can't change — Apex, SOQL and
  every layout lookup key off it"). There is no ninth, offering-specific template type — `story`,
  `configurator`, and `offerings-listing` are the fixed shape every offering gets, not something an
  offering names itself; only the offering's own display name (`renameOffering`, already correctly
  scoped per §3.3 of the plan) is meant to be editable text.

  `assistant` is a partial exception worth flagging explicitly rather than silently including or
  excluding: it is registered in `FRAMEWORK_TEMPLATES` and has a `TEMPLATE_LABELS` entry, but
  `gtmContentHome.js`'s `pages` array explicitly filters out everything in `SETTINGS_TEMPLATES` (line
  250: `.filter((t) => SETTINGS_TEMPLATES.indexOf(t) === -1)`), so it never appears as a rename-able row
  in the pages list in the first place — it's reached only via the separate "Settings" link. Confirm
  `SETTINGS_TEMPLATES` (defined near the top of `gtmContentHome.js`) contains `'assistant'` before relying
  on this; if so, the client-side page-list gate never needs to special-case it, but the **server-side**
  `renamePage()` gate should still cover `assistant` in its blocklist for defense in depth, since Apex has
  no knowledge of what the current UI happens to filter.

- **System Component Impacted:** Apex (`GtmPageContentController.cls`) and LWC
  (`gtmContentHome.js`/`gtmContentHome.html`) — no Custom Metadata, YAML instrument, or Experience Cloud
  route changes required. Small, well-bounded fix confined to these two files (plus their Jest/Apex test
  counterparts).

- **Recommendation — fix in both layers (defense in depth), server-side is the must-have:**
  1. **Server-side (mandatory):** Add a `STRUCTURAL_TEMPLATE_TYPES` (or reuse/mirror
     `TEMPLATE_LABELS.keySet()`, but a plain hardcoded `Set<String>` is simpler and matches how
     `FRAMEWORK_KEY`/`templatesFor()` are already mirrored by comment convention between the two files) in
     `GtmPageContentController.cls`, containing the eight `templateType` keys above. `renamePage()` should
     throw `AuraHandledException` (matching its existing validation style at line 597/601) when
     `templateType` is in that set, **before** the upsert. This is the safer half: it also blocks direct
     Apex/API/Anonymous-Apex calls to `renamePage`, which a client-side-only fix cannot.
  2. **Client-side (should-have, not optional):** Compute a `canRename` boolean per page row in
     `gtmContentHome.js`'s `pages` mapper (same place `isRenaming`/`isBuilt` are already computed,
     `:258-274`), `true` unless `templateType` is in the same structural set (mirror it as a local JS
     constant/array — this codebase's established pattern, per the `FRAMEWORK_KEY` comment in
     `GtmPageContentController.cls:14-20`, is two independently-maintained copies that must agree, not a
     shared import between Apex and LWC — importing from `c/gtmPageLayouts`'s `TEMPLATE_LABELS` keys is
     possible and preferable to a fresh hardcoded list if it doesn't create a dependency-direction problem;
     check whether `gtmContentHome` already imports from `gtmPageLayouts` — it does, e.g. `templatesFor`,
     so reusing `TEMPLATE_LABELS`/`OFFERING_TEMPLATES`/`FRAMEWORK_TEMPLATES` from there to derive the
     protected set is the better, DRY-er choice over a third hand-copied list). Then in
     `gtmContentHome.html` (both occurrences, `:118-124` and `:243-249`), wrap the `pg-rename` button in
     `<template if:true={p.canRename}>` so the edit icon simply doesn't render for structural pages —
     matching the existing `canRename` pattern already used for offering-level rename at
     `gtmContentHome.js:185`. This is the better UX (no dead-end error dialog) and matches the plan's own
     stated bias toward defense in depth, but by itself does not close the direct-API gap, so it must not
     ship without part 1.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No — `renamePage` has no GUS/agent tool exposure; this is a plain
      `@AuraEnabled` method called from `gtmContentHome.js` only. Grep confirms no `@InvocableMethod` or
      GUS action-catalog reference to `renamePage`. Zero-DML rule in AGENTS.md §1 not applicable (existing
      `upsert` in `renamePage` is pre-existing, unchanged by this fix — the fix only adds a validation
      throw *before* that upsert executes, it does not add new DML).
- [ ] Altering Custom Metadata? No — `GTM_Page_Content__c` is a standard custom object record (content
      override row), not Custom Metadata Type. No `migration-accelerator/` YAML or metadata XML touched.
- [ ] Introducing database fields? No — no new object/field. No permission-set mapping required.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. Calling `GtmPageContentController.renamePage('gtm', 'offerings-page', 'Hacked Title')` (and the same
     for `industry-chooser`, `faq-bd`, `faq-content-manager`, `story`, `configurator`,
     `offerings-listing`, `assistant`) from Apex/Anonymous Apex throws `AuraHandledException` and performs
     no DML (verify via a `System.assert` on record count / `Test.startTest`/`stopTest` with no new
     `GTM_Page_Content__c` row at that `Content_Address__c`).
  2. Calling `renamePage` with a non-structural `templateType` (there are none today besides the eight
     above, so this is effectively "confirm the guard is scoped to exactly that set, not overly broad") —
     if any future template type is added, it must remain renamable by default; the checklist item is
     to prove the block-list is exact, not a false-positive-prone heuristic.
  3. In the UI, the rename pencil icon does not render on any of the 7 page-list rows for a structural
     template (assistant already excluded from the pages list by `SETTINGS_TEMPLATES`, verify separately
     that its Settings surface, if it exposes any rename control at all today, is likewise blocked — grep
     showed none, confirm no rename control exists there either).
  4. Existing, correct rename paths are unaffected: offering-name rename (`renameOffering`, plan §3.3) and
     FAQ-entry-text edits (in-place `question`/`answer` editing via `gtmFieldEditor`, plan §3.4) continue
     to work exactly as before — this fix must not touch either of those methods/paths.
  5. `docs/agent-artifacts/content-manager-ia-plan.md` §3.2 should be corrected by a human (or the
     Developer, if in scope) once the fix lands, since its "no change needed here" claim is now known to
     be false as shipped; note this so it doesn't mislead a future QA pass into re-trusting the doc over
     the code.

- **Target Test Target:**
  - Apex: a new test method (or methods) in `force-app/main/default/classes/GtmPageContentControllerTest.cls`
    (confirm exact file name via `find force-app -iname "GtmPageContentController*Test*"` at implementation
    time) asserting `renamePage` throws for each structural `templateType` and still succeeds for a
    non-structural call is the primary target-test.
  - LWC/Jest: `force-app/main/default/lwc/gtmContentHome/__tests__/gtmContentHome.test.js` — add/extend a
    spec asserting the rename button (`.pg-rename`) is absent for a structural page row and present for a
    non-structural one (there currently are none besides the eight, so this spec may need to assert
    against the full known set, or assert the `canRename` computed property directly on the row objects
    the mapper produces).
