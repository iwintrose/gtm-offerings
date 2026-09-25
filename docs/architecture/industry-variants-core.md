# Industry-Specific Section Variants — Core Object Model & Contracts

Issue: `industry-variants-core` (1 of 4 in the "Industry-Specific Section
Variants" series — see `docs/agent-artifacts/task-scope-industry-variants-core.md`
for the full series context and non-goals).

This document is the Contract-First artifact required by `CLAUDE.md` §4
before any Apex/LWC implementation. It formalizes the schema, Apex method
signatures, and LWC data contract for creating, publishing, and resolving a
whole-section, industry-scoped variant of an existing `GTM_Page_Section__c`.

## 1. Object Model

### `GTM_Page_Section__c` — two new fields

| Field | Type | Notes |
|---|---|---|
| `Industry_Key__c` | Text(80) | Null on base/generic sections. Set on a variant row to the industry slug it applies to (e.g. `healthcare`). Mirrors the slug convention already used by `GTM_Page_Content__c.Industry_Key__c`. |
| `Base_Section_Key__c` | Text(80) | Null on base/generic sections. Set on a variant row to the base section's `Section_Key__c` it is a variant of. |

A variant is a first-class `GTM_Page_Section__c` row, not a flag on the base
row. Its own `Section_Key__c` is derived as:

```
<baseKey>--<industrySlug>
```

e.g. base key `problem`, industry slug `healthcare` -> variant key
`problem--healthcare`. This key is built directly (not re-passed through
`GtmContentAddress.normaliseKey`, which would collapse the `--` separator
down to a single `-` and make the pair unrecoverable) — `baseKey` and
`industrySlug` are each normalised individually first, then joined literally
with `--`.

The variant's `GTM_Page_Content__c` field rows are addressed under the
variant's own `Section_Key__c` (so `Content_Address__c`/`Section_Address__c`
addressing is completely unchanged — see §4) and are additionally stamped
with `Industry_Key__c` = the same industry slug, reusing the existing field
(no schema change needed on `GTM_Page_Content__c`).

## 2. Apex Contracts

### `GtmPageSectionController.createSection` (extended)

```apex
@AuraEnabled
public static String createSection(
    String offeringKey,
    String templateType,
    String sectionKey,
    String label,
    String layoutType,
    String width,
    List<FieldSeed> fields,
    String industryKey,       // NEW, optional. Null/blank = ordinary section.
    String baseSectionKey     // NEW, optional. Required iff industryKey is set.
)
```

Behavior when `industryKey`/`baseSectionKey` are both blank: identical to
today — an ordinary section is created at `sectionKey`.

Behavior when both are supplied (a variant create):
- `baseSectionKey` must resolve to an existing `GTM_Page_Section__c` row for
  this `(offeringKey, templateType)`. Missing base -> `AuraHandledException`.
- Guard query for `(offeringKey, templateType, Base_Section_Key__c =
  baseSectionKey, Industry_Key__c = industryKey)` must return zero rows, or
  the call throws `AuraHandledException` ("a variant already exists"). This
  is a server-side duplicate guard, not just a UI-side check, so two
  concurrent requests can't create two variants for the same
  `(base, industry)` pair.
- The effective `sectionKey` passed by the client is ignored/derived
  server-side as `normaliseKey(baseSectionKey) + '--' + normaliseKey(industryKey)`
  — the server is authoritative on the key, exactly as the base-section path
  already is authoritative on duplicate detection.
- `fields` seeds the variant's content rows exactly as it does today for an
  ordinary section — the caller passes a **snapshot of the base section's
  current fields** (see `fieldsSnapshotFor` in §3), not a blank layout. Each
  seeded `GTM_Page_Content__c` row additionally gets `Industry_Key__c` =
  `industryKey` stamped on insert.
- The new section row itself gets `Industry_Key__c` = `industryKey` and
  `Base_Section_Key__c` = `normaliseKey(baseSectionKey)`.
- Everything else (Draft `Status__c`, `Sort_Order__c` via `nextSortOrder`,
  the `Section_Address__c` addressing, the savepoint/rollback transaction
  shape) is unchanged from the existing method.

### `GtmPageSectionController.createField` (extended)

```apex
@AuraEnabled
public static String createField(
    String offeringKey,
    String templateType,
    String sectionKey,
    String fieldKey,
    String fieldType,
    String label,
    String helpText,
    String industryKey   // NEW, optional. Stamped onto the new row when set.
)
```

When `industryKey` is blank, behavior is unchanged. When set, the new
`GTM_Page_Content__c` row's `Industry_Key__c` is stamped with it — this is
the same field `GtmPageContentReader.getPageContent` already reads, so a
field added to a variant section is industry-scoped exactly like a field
added directly with an industry key.

### `GtmPageSectionController.getEditorSections` (extended)

Adds `Industry_Key__c`, `Base_Section_Key__c` to the SELECT list and to the
`EditorSection` DTO:

```apex
public class EditorSection {
    // ...existing fields unchanged...
    @AuraEnabled public String industryKey;      // NEW
    @AuraEnabled public String baseSectionKey;   // NEW
}
```

Sort order (`BySortOrder`) is unchanged — a variant sorts by its own
`Sort_Order__c` like any other row; grouping variants under their base in
the rail is a client-side presentation concern (see §3), not a change to
how sections are ordered or published.

### `GtmPageContentReader` — new helper + three call sites

```apex
/**
 * The Published/Active variant section per base section key, for one
 * industry. Returns a map keyed by Base_Section_Key__c -> the variant's
 * own GTM_Page_Section__c row (queried with the fields each call site
 * needs: Section_Key__c, Label__c, Layout_Type__c, Width__c).
 */
private static Map<String, GTM_Page_Section__c> variantSectionsByBase(
    String offeringKey, String templateType, String industryKey
)
```

Returns an empty map when `industryKey` is blank (no industry selected ->
no variant substitution, matching today's behavior exactly). Only
`Status__c = 'Published'` and `Active__c = true` variant rows are
considered — the same "what's live" rule `getPageLayout` already applies to
every other section.

Wired into:

- **`getPageContent`** — after building the flat `section::field` map from
  the ordinary content query, remap every row whose `Section_Key__c` is a
  live variant's key so its entries land under `<baseKey>::<fieldKey>`
  instead of `<variantKey>::<fieldKey>`. This is a whole-section swap: the
  base section's own rows for that base key are superseded entirely by the
  variant's rows, not merged field-by-field (per the "whole-section
  variants only" decision in the scope doc — no per-field override). The
  renderer/prospect-facing template code never needs to know a variant key
  exists.
- **`getPageLayout`** — for each base section returned by the existing
  Published/Active section query, if `variantSectionsByBase` has an entry
  for its key, substitute the variant's `Label__c`/`Layout_Type__c`/
  `Width__c` into the `SectionDto` — but keep the base's own `sectionKey`
  and `Sort_Order__c`. Ordering/visibility per industry is explicitly out
  of scope for this issue (`#industry-variants-visibility-nav`); the base
  section's position in the sequence never moves.
- **`getFieldMeta`** — same remap treatment as `getPageContent`: a field
  meta row addressed under a live variant's key is re-keyed to the base
  key so the renderer's field-meta lookups agree with `getPageContent`'s
  remapped content map. (Confirmed necessary: `getPageLayout` calls
  `getFieldMeta` and matches its `sectionKey`/`fieldKey` pairs against
  `content`'s `section::field` keys to draw unknown fields — if `content`
  is remapped to base keys and `fieldMeta` is not, every variant field
  would silently stop rendering.)
- **`getIndustryProfiles`** — explicitly untouched (per scope doc).

## 3. LWC Contracts

### `gtmContentManager.js`/`.html`

- **Rail grouping**: `railSections` groups variant sections (`s.baseSectionKey`
  is non-blank) under their base section (`s.baseSectionKey` blank,
  `s.sectionKey` matches). A variant chip is a peer row nested under its
  base, not a separate rail section; clicking it sets `activeKey` through
  the existing `handleSelectSection` — no new selection mechanism.
- **New "+ Industry variant" modal** (modeled on the existing "Add
  industry" modal): opened per base section (`data-key`-scoped, mirroring
  `handleAskDelete`'s pattern of tracking a base-section target). Lists
  industries via `getIndustryProfiles('gtm', 'industry-chooser')`, filtered
  to exclude any industry that already has a variant
  (`sections.some(s => s.baseSectionKey === target.sectionKey &&
  s.industryKey === candidate.industryKey)`).
- **New helper**:

  ```js
  /**
   * A snapshot of a section's current fields, in the FieldSeed shape
   * createSection expects, used to seed a new variant with the base
   * section's copy instead of a blank layout.
   */
  fieldsSnapshotFor(sectionKey) {
      return this.records
          .filter((r) => r.sectionKey === sectionKey)
          .map((r) => ({
              fieldKey: r.fieldKey,
              fieldType: r.fieldType || 'text',
              label: r.label || ''
          }));
  }
  ```

- Delete/hide affordances are reused as-is for variant rows — no new
  controls; a variant row is a `GTM_Page_Section__c` row like any other and
  goes through the same `handleAskDelete`/`handleToggleActive` handlers.

### `gtmFieldEditor.js`

```js
@api industryKey = '';   // NEW. Blank for an ordinary section's editor.
```

Threaded through to `createField`:

```js
createField({
    offeringKey: this.offeringKey,
    templateType: this.templateType,
    sectionKey: this.activeKey,
    fieldKey,
    fieldType,
    label,
    helpText,
    industryKey: this.industryKey || null   // NEW
});
```

`gtmContentManager` passes `industry-key={activeSection.industryKey}` down
to `c-gtm-field-editor` alongside the existing bindings, so a field added
while a variant section is active is automatically industry-scoped.

### `gtmPagePreview` / `gtmPageLayouts.js`

No contract changes. Verified during implementation (§Detailed Scope of the
task-scope doc flags both as "expected no changes, verify") — the preview
renders from `gtmContentManager`'s already-resolved `previewSections`/
`previewContent`/`previewFieldMeta` working copy, which does not
distinguish variant rows from ordinary ones at the editor layer (variant
resolution is a guest/public-page-read concern in `GtmPageContentReader`,
not an editor-preview concern).

## 4. What Is Explicitly Unchanged

- `Content_Address__c`/`Section_Address__c` addressing (`GtmContentAddress`)
  — untouched. A variant's fields are addressed under the variant's own
  section key like any other section's fields.
- Draft/publish/discard state machine (`Draft_State__c`, `Status__c`,
  `deleteSection`/`restoreSection`/`saveSectionOrder`/`publishPage`/
  `discardDrafts`) — untouched. A variant section is a
  `GTM_Page_Section__c` row and goes through the exact same generic
  lifecycle; covered by a new explicit Apex test rather than assumed safe.
- `slugify`/`normaliseKey` — reused exactly as they exist today.
- `getIndustryProfiles` — untouched.

## 5. Non-Goals (restated from task scope)

No per-field override, no per-industry visibility/hide/reorder, no
Migration Accelerator content, no Agentforce authoring aid. See task scope
§4 for the full list and which follow-up issue owns each.

## 6. UI Scoping Fix (issue `industry-variant-ui-scoping-fix`)

Follow-up bug fix, not a new capability — documented here as a lightweight
addendum rather than a new architecture doc, per the task scope's own
guidance.

The "Industry view" toggle and "+ Industry variant" button (§3 above)
originally rendered unconditionally on every template, including
framework-level, non-industry-aware templates such as `offerings-listing`
(the shared "choose your offering" tile — see
`docs/agent-artifacts/task-scope-industry-variant-ui-scoping-fix.md` for the
full root-cause writeup). Fixed by gating both on a new
`gtmContentManager.js` getter:

```js
get supportsIndustryVariants() {
    const layouts = TEMPLATE_LAYOUTS[this.selectedTemplate];
    return !!layouts && layouts.includes('industry-profile');
}
```

`TEMPLATE_LAYOUTS` is imported from `c/gtmPageLayouts` (already the single
source of truth for which templates carry which layout types — no
duplicate/hardcoded template-name list). Today only `configurator` carries
`'industry-profile'`, so this getter is behaviorally identical to
`this.selectedTemplate === 'configurator'`, but it stays correct
automatically if a future template gains `industry-profile` support,
without a second edit. This mirrors the existing `isFrameworkPage`/
`isIndustryPage` idiom in the same file (§3 above).

`industryView` (the toggle's own on/off state) is reset to `false`
whenever a template switch lands on a page that doesn't support industry
variants — in `loadPage()` (covers `handlePickTemplate`/`handlePageChange`/
the page-picker auto-select path) and at every call site that clears
`selectedTemplate` outright (`handleOfferingChange`, `handleBackToPages`,
`handleSaveAndExit`, `openRequestedPage`) — so a stale toggle from a prior
`configurator` page can never leave the industry-view rail stuck open
behind a now-hidden exit control. `handleToggleIndustryView` is also a
no-op when `!supportsIndustryVariants`, as defense in depth.

No Apex, schema, or `TEMPLATE_LAYOUTS` data changes — this was a pure
under-scoped LWC render-condition gap; the server already accepted any
`offeringKey`/`templateType` combination for a variant create with no
allow-list check. Hardening `GtmPageSectionController.createSection`/
`GtmPageContentController.createSection` with a server-side guard against
non-`configurator` variant creates was flagged as an optional follow-up in
`docs/backlog.md`, out of scope for this fix.
