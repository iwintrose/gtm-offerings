# TASK SCOPE — ISSUE #49

## 1. Requirements Breakdown

- **Target Objective:** Resolve two gaps in the Content Manager 'Manage offering' feature: (a) deploy `GTM_Page_Section__c.Offering_Status__c` and `Archived__c` to `gtm-dev` so Apex queries referencing those fields do not fail at runtime, and (b) add a collapsible 'Archived offerings' recycle-bin section to `gtmContentHome` so archived offerings are visible and restorable rather than silently removed from the main grid.
- **System Component Impacted:** Apex (`GtmPageContentController`, `GtmPageContentReader`), LWC (`gtmContentHome`), Salesforce Object `GTM_Page_Section__c`, Permission Sets (`GTM_Content_Manager`, `GTM_Content_Admin`)

---

### Verified findings from code inspection

**Field schemas (confirmed)**

- `Offering_Status__c` — Picklist (restricted), values: `Draft` / `Published`, default `Published`, not required. Inline help text correctly documents it as offering-level only on the tile section.
- `Archived__c` — Checkbox, default `false`. Same tile-section-only semantics.

**Permission sets (confirmed — no action needed)**

Both `GTM_Content_Manager.permissionset-meta.xml` and `GTM_Content_Admin.permissionset-meta.xml` already contain explicit `fieldPermissions` entries for `GTM_Page_Section__c.Offering_Status__c` and `GTM_Page_Section__c.Archived__c` with `readable: true` and `editable: true`. PR #27 included these grants. No new permission-set entries are required.

**Apex (confirmed)**

`GtmPageContentController.getHomeSummary()` (lines 505–516) issues a SOQL query `SELECT Offering_Key__c, Offering_Status__c, Archived__c FROM GTM_Page_Section__c WHERE Template_Type__c = 'offerings-listing' AND Section_Key__c = 'tile'`. This query will throw a `System.QueryException: No such column 'Offering_Status__c'` at runtime on `gtm-dev` until the fields are deployed. Both `setOfferingStatus` and `setOfferingArchived` similarly reference these fields in DML. No Apex changes are required for the recycle-bin feature — `getHomeSummary()` already returns `archived` and `offeringStatus` on every `OfferingSummary` in its response, including for archived offerings. The data is already present client-side.

**LWC current state (confirmed)**

`gtmContentHome.js` `cards` getter (line 131) maps all offerings — active and archived — into the same array. `filteredCards` (line 243) applies only a text search filter, with no archived/active split. The HTML at line 64 renders `for:each={filteredCards}` in a single `off-grid` div. An archived offering today appears in the main grid with an "Archived" badge, rather than being separated out. There is no collapsed section, no recycle-bin UI, and no `archivedCards` / `activeCards` getter. The `isArchived` flag is already computed per card (line 180).

---

### (a) Missing permission-set grants

None. Both fields are already granted in both permission sets. This sub-task is complete as delivered by PR #27.

### (b) Deploy procedure for the two fields

The Developer agent must:

1. Run a dry-run validation: `./scripts/deploy.sh gtm-dev --dry-run` scoped to at minimum:
   - `force-app/main/default/objects/GTM_Page_Section__c/fields/Offering_Status__c.field-meta.xml`
   - `force-app/main/default/objects/GTM_Page_Section__c/fields/Archived__c.field-meta.xml`
   - `force-app/main/default/permissionsets/GTM_Content_Manager.permissionset-meta.xml`
   - `force-app/main/default/permissionsets/GTM_Content_Admin.permissionset-meta.xml`

2. Report the dry-run result to the human operator.

3. **The actual non-dry-run deploy to `gtm-dev` requires explicit human authorization before execution.** `gtm-dev` is treated as Production (CLAUDE.md §1). The Developer agent must not run `./scripts/deploy.sh gtm-dev` (without `--dry-run`) until the human operator explicitly approves.

### (c) Recycle-bin UI change in `gtmContentHome`

The current `off-grid` div renders all offerings together. The required change introduces a two-section layout:

1. **Active grid (unchanged name):** Replace the `for:each={filteredCards}` loop with `for:each={filteredActiveCards}`. Add a JS getter `get activeCards()` that returns `this.cards.filter(c => !c.isArchived)`. Add `get filteredActiveCards()` that applies the existing search logic over `activeCards` rather than all cards.

2. **Archived section (new, collapsible):** Below the `off-grid` div, add a collapsible `<details>` element (or an equivalent SLDS-compatible disclosure pattern) labelled "Archived offerings (N)" where N is `archivedCards.length`. Add `get archivedCards()` returning `this.cards.filter(c => c.isArchived && !c.isFramework)`. Render archived cards inside the collapsed section using the same `for:each` card template. The section should be closed by default. The framework offering is never archivable (guarded in `setOfferingArchived` Apex) so it is excluded.

3. **Search behavior design fork — requires human decision:** Two valid options exist:
   - **Option A:** The search field (`searchTerm`) filters only the active grid; the archived section is always rendered in full (unaffected by search).
   - **Option B:** The search field applies across both sections simultaneously, and the archived section auto-expands if a search term matches an archived offering.
   Option B is friendlier for lookup but more complex. The Architect must choose which behavior to implement before the Developer begins. This scope cannot settle this without human input.

4. **Empty-state message:** If `archivedCards.length === 0`, the archived section should not render at all (use `if:true={hasArchivedCards}` guard). Add `get hasArchivedCards()` returning `this.archivedCards.length > 0`.

5. **No new Apex method needed.** `getHomeSummary()` already returns archived offerings in its response. The archived section is a client-side filter.

### (d) Apex changes needed to surface archived offerings

None required. `getHomeSummary()` already includes all offerings with their `archived` flag. The LWC already receives this data; it simply does not render a separate section for it.

---

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? — **NO.** No changes to the GUS assistant Apex methods, LWC components, or Experience Cloud routes. Zero-DML rule does not apply here.
- [x] Altering Custom Metadata? — **NO.** `Offering_Status__c` and `Archived__c` are standard custom fields on `GTM_Page_Section__c` (a custom object), not Custom Metadata Types. No YAML instrument changes. No `migration-accelerator/` changes.
- [x] Introducing database fields? — **YES, deploying two existing-in-source fields to org.** Both fields are already in source and already granted in both relevant permission sets. No new permission set mapping work is required. The deploy is the only action needed.

---

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. `./scripts/deploy.sh gtm-dev --dry-run` exits 0 with the two field files and their permission set entries included.
  2. After human-authorized live deploy: a SOQL query in org `SELECT Id, Offering_Status__c, Archived__c FROM GTM_Page_Section__c LIMIT 1` executes without error.
  3. After live deploy: `GtmPageContentController.getHomeSummary()` is callable from the Content Manager app without throwing a query exception (verified by opening the Content Manager home page and confirming offerings load).
  4. After live deploy and LWC change: archiving an offering via the Manage modal moves it out of the main grid and into the collapsed "Archived offerings" section on the same page load (after the success toast triggers a data reload).
  5. After LWC change: the "Restore from archive" action in the Manage modal for an archived offering moves it back to the active grid.
  6. After LWC change: if no offerings are archived, the "Archived offerings" section does not render.

- **Target Test Target:**
  - Apex: `GtmPageContentControllerTest` — specifically any test methods covering `getHomeSummary`, `setOfferingStatus`, and `setOfferingArchived`. Run via `./scripts/deploy.sh gtm-dev --run-tests` after live deploy.
  - LWC: `force-app/main/default/lwc/gtmContentHome/__tests__/gtmContentHome.test.js` — add or extend Jest specs covering: (i) archived card does not appear in active grid, (ii) archived section renders when `archivedCards` is non-empty, (iii) archived section is absent when all offerings are active.
