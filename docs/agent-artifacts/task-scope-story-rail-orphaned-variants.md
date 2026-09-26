# TASK SCOPE — ISSUE #story-rail-orphaned-variants

## 1. Requirements Breakdown

- **Target Objective:** Restore visibility of 36 real, already-authored Migration Accelerator Story industry-variant sections (`problem`/`capabilities`/`clientProfile`/`faq` × 9 industries) — both in the Content Manager editor rail (where an editor must be able to see, open and edit them) and on the actual live/published Story page (where the finding below shows they are ALSO not rendering, a materially worse problem than the ticket as filed assumed).

  **Root cause, confirmed by reading the code, not assumed:**
  `force-app/main/default/lwc/gtmContentManager/gtmContentManager.js`,
  `railSections` (line 425) builds the rail from
  `this.contentSections.filter((s) => !this.isVariantRow(s))` (line 434,
  `isVariantRow(s) { return !!s.baseSectionKey; }`, line 423), then for each
  of those base rows attaches variants via
  `.filter((v) => this.isVariantRow(v) && v.baseSectionKey === s.sectionKey)`
  (lines 471-473). A variant whose `baseSectionKey` matches no real
  (non-variant) `GTM_Page_Section__c` row is never a member of `rows` (the
  base list) NOR ever attached as anyone's `.variants` — it is dropped from
  the rail entirely, with no error.

  Confirmed live via a direct read-only SOQL query against `gtm-staging`:
  ```
  $ sf data query --target-org gtm-staging --query "SELECT Id, Section_Key__c,
    Base_Section_Key__c, Industry_Key__c, Label__c, Layout_Type__c, Active__c,
    Status__c FROM GTM_Page_Section__c WHERE Offering_Key__c =
    'migration-accelerator' AND Template_Type__c = 'story' ORDER BY
    Base_Section_Key__c NULLS FIRST, Section_Key__c"
  Total number of records retrieved: 37.
  ```
  Of those 37: exactly **1** has `Base_Section_Key__c = null` (`Section_Key__c
  = 'test'`, `Layout_Type__c = 'hero'`, `Label__c = 'test'` — an unrelated
  leftover, matching the ticket's own description) and **36** are variants
  (`problem--<industry>`, `capabilities--<industry>`, `clientProfile--<industry>`,
  `faq--<industry>` for 9 industries), none of which has a matching base row
  (there is no `problem`/`capabilities`/`clientProfile`/`faq` row anywhere in
  this result set). This is why the editor rail shows "SECTIONS 1" —that one
  `test` row is the entire base list — and why the summary/overview counts
  (which query `GTM_Page_Section__c`/`GTM_Page_Content__c` directly, not
  through this grouping) still report all 37 correctly, per
  `GtmPageContentController.getTemplateSummary` (`GROUP BY Template_Type__c`
  over both objects, no base/variant distinction at all).

  **The requested "does the read side share this bug" verification — it does,
  and the live consequence is worse than the ticket assumed.**
  `GtmPageContentReader.getPageLayout` (the published-page reader) has the
  identical structural gap. Its `baseSections` query is filtered
  `AND Base_Section_Key__c = null` (line 131), and `resolveForIndustry`
  (lines 149-169) iterates *only* over that `baseSections` list, substituting
  a live variant's label/layout/width into an existing base entry
  (`variantsByBase.get(sec.Section_Key__c)`, line 157) — there is no code
  path that ever adds a variant as its own entry when no base row exists.
  `force-app/main/default/lwc/gtmStory/gtmStory.js` then makes this
  concretely visible: `getPageLayout({...}).then((layout) => { if
  (layout.sections && layout.sections.length) this._sectionRows =
  layout.sections; ...})` (line 601) and `get sections() { const rows =
  this._sectionRows.length ? this._sectionRows : DEFAULT_SECTIONS; ...}`
  (line 380) — `DEFAULT_SECTIONS` (the 11-entry JS fallback structure
  intended as the generic floor, lines 175-187) is used **only when zero**
  real section rows come back. Because the stray `test` row makes
  `layout.sections.length === 1` (not 0), the fallback never engages.

  **Net effect, confirmed by combining the query above with this code path:**
  the live/published Migration Accelerator Story page currently renders
  exactly **one** section — the empty `test` hero row (no
  `GTM_Page_Content__c` rows exist under it either, confirmed by a second
  query returning 0 rows) — and nothing else. Not just the 36 industry
  variants: `mechanism`, `pivot`, `bd`/use-pitch, and the un-personalized/no-
  industry-selected floor of `problem`/`capabilities`/`clientProfile`/`faq`
  are ALL silently absent too, because none of them have real base rows
  either and the one stray row that does exist blocks the JS fallback that
  would otherwise have shown them. This was not directly browser-verified
  (this BA pass has no browser tool), but three independent pieces of
  evidence triangulate to the same conclusion (the live SOQL result, the two
  cited Apex methods, and the two cited `gtmStory.js` lines) — flagging this
  as a confirmed, code-and-data-verified finding, not a guess, and
  recommending the Coordinator/QA do a live browser confirmation as the very
  next step given the severity jump this represents.

  **Immediate, separate, non-code observation for the Coordinator:** the
  stray `test` `GTM_Page_Section__c` row (`Section_Key__c = 'test'`, the
  owner's own scratch record from testing the "+ Industry variant" UI
  earlier tonight) is, on its
  own, the direct cause of the JS fallback being suppressed for a page that
  would otherwise be showing *something* coherent (the DEFAULT_SECTIONS
  floor) instead of one blank hero. Deactivating or deleting that one record
  in `gtm-staging` is a one-record data change, not a code change, and is
  not something this BA agent will do — flagging it explicitly as a call for
  the Coordinator to make (and, per "no casual writes," to decide whether it
  warrants a second look before touching even staging data) rather than
  quietly recommending it as settled.

  This also explains why the seed script that created the 36 variants,
  `scripts/data/seed-migration-accelerator-industry-variants.apex`, could
  ever produce a state its own header comment treats as safe ("hero,
  mechanism, pivot, bd, closing, header, footer stay generic — no variant
  rows are written for them"): that comment's assumption is that the JS
  DEFAULTS/DEFAULT_SECTIONS floor keeps covering everything the script
  doesn't touch. It does, right up until any base-less row (variant or
  otherwise) exists in the table, at which point the floor stops being used
  for the whole page, not just the sections a variant was added for. That is
  a structural gap in `gtmStory.js`'s own fallback logic, independent of
  whether the specific `test` row is ever cleaned up.

- **System Component Impacted:** LWC (`gtmContentManager.js` editor rail,
  `gtmStory.js` published-page renderer) + Apex
  (`GtmPageContentReader.getPageLayout`/`resolveForIndustry`/
  `variantSectionsByBase`). No YAML/instrument, no Experience Cloud route
  metadata change.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? — No. Unrelated surface.
- [ ] Altering Custom Metadata? — No. `GTM_Page_Section__c`/`GTM_Page_Content__c`
      are ordinary custom objects, not the YAML-driven
      `GTM_Assessment_*` metadata pipeline (ADR-0009 doesn't apply here).
- [ ] Introducing database fields? — No. `Base_Section_Key__c`,
      `Industry_Key__c` etc. already exist and are already populated
      correctly by the seed script; this is purely rendering/grouping logic
      over data that is already there. No permission-set mapping work needed.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. In Content Manager, opening Migration Accelerator's Story page shows all
     36 real industry variants in the rail — either grouped under a
     synthetic/canonical base entry (recommended: derive the canonical
     section-key list from `gtmStory.js`'s own `DEFAULT_SECTIONS` — promoted
     into the shared `c/gtmPageLayouts` module as the one source of truth, the
     same pattern already used for `TEMPLATE_LAYOUTS`/`LAYOUT_FIELDS` — rather
     than requiring a real `GTM_Page_Section__c` base row to exist) or, for
     any variant whose `baseSectionKey` matches no canonical key at all,
     listed flatly with an industry badge so nothing is ever silently
     dropped. Either shape is acceptable; silently dropping a real,
     authored, Published section is not.
  2. The identical fix lands on `GtmPageContentReader.getPageLayout` so the
     live/published page reflects the same set of sections the editor shows
     — a variant substitutes into its canonical slot for its industry even
     when no real base row exists for that slot.
  3. After the fix, re-running the live SOQL query from this doc plus a
     fresh `getEditorSections('migration-accelerator', 'story')` /
     `getPageLayout('migration-accelerator', 'story', '<each of the 9
     industry slugs>')` anonymous-Apex check shows every one of the 36
     variants reachable from both the editor and the publish-time reader.
  4. No regression to any existing page that DOES have real base rows for
     all its sections (i.e. every other offering/template combination in the
     org today) — existing Jest/Apex specs for the non-orphan case must stay
     green.
- **Target Test Target:**
  - Apex: `GtmPageContentReaderTest` (add a case seeding a variant with NO
    matching base row and asserting it still resolves into `getPageLayout`'s
    `sections` list for its industry — no such case exists today; the only
    existing variant-resolution tests, e.g. around line 717, always seed a
    real base row first).
  - LWC: `gtmContentManager/__tests__/gtmContentManagerVariants.test.js`
    (existing fixture always includes a real base row — needs a new case for
    an orphaned variant) and a new or extended spec on
    `gtmStory/__tests__/gtmStory.test.js` (today only tests the closing
    section's CTA; needs a case asserting `DEFAULT_SECTIONS`-derived
    canonical sections still render when the DB has variant-only rows and no
    real base rows).
  - Run `npm test -- gtmContentManager gtmStory` plus
    `sf apex run test --class-names GtmPageContentReaderTest --target-org
    gtm-staging` (targeted, per `docs/runbooks/api-request-budget.md` —
    `GtmPageContentReaderTest` is already live in the org).

## 4. Timing

- **Estimated effort:** Full day. This touches two Apex methods
  (`getPageLayout`, `resolveForIndustry`/`variantSectionsByBase`) and two LWC
  components (`gtmContentManager.js` rail grouping, `gtmStory.js` fallback
  logic), ideally centralizing the canonical section-key list into
  `c/gtmPageLayouts` so editor and renderer can't drift again — plus new test
  coverage on both the Apex and Jest sides, since today there is zero test
  coverage anywhere in the repo for "a variant exists with no matching base
  row" (confirmed by grep: no test seeds this shape). Not a one-line gate
  fix; it is a real, if contained, cross-layer change.
- **Target completion:** 2026-09-29. Not blocked on a user decision for the
  core fix (the "synthesize a canonical slot vs. flat orphan list" design
  choice is a legitimate Architect call, resolved above with a
  recommendation) — but the stray `test` row's disposition, and whether the
  Coordinator wants an immediate stopgap data deactivation ahead of the full
  fix given the live page is currently reduced to one blank section, is
  flagged above as the Coordinator's call, not assumed.
