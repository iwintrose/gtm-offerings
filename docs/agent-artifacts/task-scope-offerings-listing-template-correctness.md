# TASK SCOPE — ISSUE #offerings-listing-template-correctness

## 1. Requirements Breakdown

- **Target Objective:** Make the "Offerings Listing" page template correct
  per the owner's already-settled architecture decision this session ("The
  Offering -> Offering Listing should not have an industry variation...
  simply a short blurb... value prop and brief capability... all the page
  content must be populated in the fields - not hard coded content"). This
  groups two related findings from tonight's live gtm-staging session; both
  are about the same template, but they have very different real states —
  verified below, not taken on the ticket's word.

  ### Finding A ("+ Industry variant" button on Offerings Listing) — ALREADY FIXED on `main`, not yet redeployed to `gtm-staging`

  This is the one correction in this doc: **the code defect as described no
  longer exists on `main`.** Confirmed three ways:
  1. `force-app/main/default/lwc/gtmPageLayouts/gtmPageLayouts.js`,
     `TEMPLATE_LAYOUTS['offerings-listing'] = ['offering-tile']` — does not
     include `'industry-profile'`. `gtmContentManager.js`'s
     `supportsIndustryVariants` getter (line 972) is `!!layouts &&
     layouts.includes('industry-profile')`, which gates BOTH the "Industry
     view" toggle and the "+ Industry variant" button
     (`gtmContentManager.html` lines 213-221 and 301-304) — so both are
     already `false`/hidden for `offerings-listing` on `main`.
  2. A dedicated regression spec already exists and passes:
     `force-app/main/default/lwc/gtmContentManager/__tests__/gtmContentManagerIndustryVariantScoping.test.js`,
     explicitly titled for `issue #industry-variant-ui-scoping-fix`, asserting
     "hides the Industry view toggle and + Industry variant button on
     offerings-listing." Ran it directly: `npx jest
     .../gtmContentManagerIndustryVariantScoping.test.js` → **12/12 passed.**
  3. `git log` shows this landed in the just-merged `PR #32`
     (`7eb458c8 fix(lwc): scope Industry view toggle & + Industry variant
     button to configurator (#32)`, merged 2026-09-25 18:52:40 -0400 — the
     evening before tonight's live observation).

  **So why did the owner+coordinator see it live in `gtm-staging` tonight?**
  Because `gtm-staging` is running pre-fix code. Retrieved the actually-
  deployed `gtmContentManager.js` from `gtm-staging` (read-only metadata
  retrieve, not a deploy) and diffed it against `main`:
  ```
  $ sf project retrieve start --target-org gtm-staging --metadata
    LightningComponentBundle:gtmContentManager --target-metadata-dir
    <scratch> --unzip
  $ diff <retrieved>/gtmContentManager.js
    force-app/main/default/lwc/gtmContentManager/gtmContentManager.js
  22c22
  < import { addableLayouts, fieldsFor, templatesFor, TEMPLATE_LABELS,
    LAYOUT_LABELS, FRAMEWORK_KEY } from 'c/gtmPageLayouts';
  ---
  > ... FRAMEWORK_KEY, TEMPLATE_LAYOUTS } from 'c/gtmPageLayouts';
  [... every industryView-reset guard and the `supportsIndustryVariants`
  getter itself, entirely absent from the retrieved copy ...]
  ```
  The version live in `gtm-staging` right now has no `TEMPLATE_LAYOUTS`
  import and no `supportsIndustryVariants` getter at all — it predates PR #32
  entirely. **This is a stale-deployment problem, not a code defect.** No
  Developer work is needed for this half; it needs `main` (or at minimum
  this LWC bundle) redeployed to `gtm-staging`, which is an ops/deploy
  action, not something this pipeline needs to build.

  ### Finding B ("Offerings Listing" has no populated blurb field) — real, but not a missing-field problem — it's a data gap on top of an already-correct schema

  Traced the actual chain the "choose your offering" card uses, rather than
  assuming it is hardcoded (it explicitly is NOT, contrary to the ticket's
  own guess):
  - `LAYOUT_FIELDS['offering-tile']` in `gtmPageLayouts.js` (line 46)
    already declares `text: ['mark', 'name'], rich: ['description']` — the
    blurb field already exists in the layout contract.
  - `GtmPageContentReader.getOfferingTiles()` (line 334) already reads real
    `GTM_Page_Content__c` rows keyed `Template_Type__c = 'offerings-listing'`,
    `Section_Key__c = 'tile'`, `Field_Key__c` in `mark`/`name`/`description`,
    and marks a tile `isLive` once `description` is non-blank.
  - `force-app/main/default/lwc/offeringChooser/offeringChooser.js` (the
    live "choose your offering" front door renderer) calls
    `getOfferingTiles` and only gives a card an `href` (makes it clickable)
    when `isLive` is true; otherwise it renders as a placeholder
    ("Space reserved for the next practice offering added to this
    framework.").
  - `GtmPageContentController.createOffering()` (line 632, the normal "New
    offering" creation path in Content Manager) already correctly writes all
    3 rows, including a real placeholder description
    (`'Describe ' + clean + ' here.'`) an editor immediately overwrites — so
    an offering created today through the ordinary UI flow would NOT hit
    this bug.

  **So the schema, layout contract, and both read paths are already fully
  correct.** The live "1 sections · 0 fields" state is a pure data gap:
  confirmed by direct read-only query against `gtm-staging`:
  ```
  $ sf data query --target-org gtm-staging --query "SELECT Id,
    Offering_Key__c, Template_Type__c, Section_Key__c, Label__c,
    Layout_Type__c, Active__c, Status__c FROM GTM_Page_Section__c WHERE
    Template_Type__c = 'offerings-listing'"
  -> 2 rows: migration-accelerator/tile and test-offering/tile, both
     Active=true, Status=Published, Layout_Type__c=offering-tile.

  $ sf data query --target-org gtm-staging --query "SELECT Id,
    Offering_Key__c, Section_Key__c, Field_Key__c ... FROM
    GTM_Page_Content__c WHERE Template_Type__c = 'offerings-listing'"
  -> 0 rows.
  ```
  Both of the org's two real offerings have a `tile` section shell with
  **zero** field content rows underneath — this is exactly the "1 sections ·
  0 fields" the ticket describes (confirmed against
  `GtmPageContentController.getTemplateSummary`'s `fieldCount`, which is a
  raw `COUNT(GTM_Page_Content__c)`, matching the 0-row query above exactly).
  Since neither offering's `tile` section has content, and `createOffering`
  proves this is not how the normal creation path behaves, these two
  sections were almost certainly seeded via a raw/manual path (mirroring the
  same class of gap as the sibling `story-rail-orphaned-variants` issue: a
  script or manual insert that wrote the section shell but skipped the
  content rows a real creation flow guarantees). **A live consequence worth
  flagging clearly:** because neither offering's tile has a non-blank
  `description`, `isLive` is `false` for both today, meaning **both of the
  org's real offering cards on the actual live "choose your offering" guest
  page are currently non-clickable placeholders** — this is a live guest-
  funnel break, not merely an authoring inconvenience, though (as with the
  sibling issue) this was not independently browser-verified in this pass
  (no browser tool available to this BA agent); the conclusion follows
  directly from the query above plus `offeringChooser.js`'s `isLive`/`href`
  logic.

  A second, durable gap behind Finding B: there is no way for an editor to
  self-serve a fix like this. `GtmPageSectionController.createField` (line
  492) is a fully generic, already-written Apex method for exactly this
  situation — its own doc comment says "A field the layout declares but has
  no record for — a gap, where the page falls back to a built-in default" —
  but it is never imported or called anywhere in `gtmContentManager.js` or
  `.html` (confirmed by grep — zero matches for `createField`/`addField` in
  either file). Today, only a script or a raw data operation can close this
  gap; an editor staring at "0 fields" has no button to press.

- **System Component Impacted:** LWC (`gtmContentManager.js`/`.html` — new
  "add missing field" affordance) + Apex (wiring the existing `createField`
  method, no new method needed) + a one-time data backfill
  (`GTM_Page_Content__c` rows for 2 existing offerings' `tile` sections,
  `gtm-staging` only) + an ops redeploy (Finding A, no Developer work).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? — No.
- [ ] Altering Custom Metadata? — No. Same `GTM_Page_Section__c`/
      `GTM_Page_Content__c` model as the sibling issue; unrelated to the
      YAML/instrument pipeline.
- [ ] Introducing database fields? — No new custom fields. `mark`/`name`/
      `description` already exist as generic `Field_Key__c` rows under the
      existing `offering-tile` layout contract; this wires up an existing
      Apex method and backfills missing rows, it does not add schema. No
      permission-set mapping needed — `GtmPageSectionController` is already
      a class Content Manager users have access to (its other methods,
      `createSection`/`deleteSection`/etc., are already imported in
      `gtmContentManager.js`), and Apex class access is granted per class,
      not per method, so `createField` is already reachable once wired.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. Finding A: confirm (not re-fix) that redeploying `main`'s
     `gtmContentManager`/`gtmPageLayouts` bundles to `gtm-staging` removes
     the "+ Industry variant" button and "Industry view" toggle from the
     Offerings Listing editor screen. This is a QA/ops verification step
     bundled here for completeness, not new Developer scope — flag to the
     Coordinator to schedule the redeploy; do not re-implement the fix.
  2. Finding B: both `migration-accelerator` and `test-offering` have real
     `mark`/`name`/`description` content rows under their `offerings-
     listing::tile` section in `gtm-staging` (backfilled to match what
     `createOffering` would have written, with a real, non-placeholder
     description an editor can immediately see and edit), and both offering
     cards render as live/clickable on `offeringChooser`'s "choose your
     offering" page.
  3. An editor who opens a section showing fewer fields than its layout
     declares (any layout, not just `offering-tile` — this should be a
     generic affordance, matching `createField`'s own generic contract) has
     a UI action to add the missing field(s), calling the existing
     `GtmPageSectionController.createField` — no new Apex method required.
  4. No regression to the existing "+ Add section" / "+ Industry variant"
     flows on templates that do carry those affordances.
- **Target Test Target:**
  - LWC: `gtmContentManager/__tests__/gtmContentManagerIndustryVariantScoping.test.js`
    (re-run only, to confirm it still passes post-redeploy — no changes
    expected here) and a new test case in
    `gtmContentManager/__tests__/gtmContentManager.test.js` (or a new spec)
    covering the "add missing field" affordance calling `createField`.
  - Apex: no new Apex test class needed for `createField` itself (it is
    existing, already-tested surface per
    `GtmPageSectionControllerTest` — confirm that class already covers it
    before assuming new Apex test scope).
  - Data: the two verification queries already run in this doc, re-run
    post-backfill to confirm non-zero, correct field values.
- **Success Metric caveat:** this doc bundles a "nothing to build" finding
  (A) with a "small, real build" finding (B) deliberately, per the
  Coordinator's own instruction that these two are closely related
  "Offerings Listing template correctness" work — but the Architect step
  should not schedule Developer time against Finding A; only Finding B and
  the data backfill need a worktree.

## 4. Timing

- **Estimated effort:** Half a day for Finding B (wiring one already-written
  Apex method into one LWC's existing field-editor UI, following the same
  modal/button pattern already used for "+ Industry variant," plus one
  small idempotent data-backfill script for the 2 existing offerings,
  staging only — modeled directly on `GtmPageContentController.createOffering`'s
  own field values so there is no ambiguity about what "correct" content
  looks like). Finding A needs zero development time — only a redeploy,
  which is the Coordinator's action, not this pipeline's.
- **Target completion:** 2026-09-28 for Finding B + backfill. Finding A has
  no target completion in this pipeline; it is a standing "redeploy `main`
  to `gtm-staging`" item for the Coordinator, and should be called out to
  them directly rather than silently absorbed into this timeline — flagging
  explicitly rather than assuming it will happen incidentally alongside
  whatever else next reaches `gtm-staging`.
