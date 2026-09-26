# Add industry (Content Manager > Framework > Industry Chooser)

Status: contract, written before code (CLAUDE.md section 4). Slug `add-industry`. Verified against `origin/main` 16222d3.
Scope: `docs/agent-artifacts/task-scope-add-industry.md`. Nothing here is implemented.

## 0. Decisions binding this contract

1. Industries are entered by the user. Nothing is seeded, no Migration Accelerator data, no example industry, in any test or script.
2. A new industry stays HIDDEN from the public chooser until the admin clicks Publish.
3. The public reader `getIndustryProfiles` will honour section `Status__c` and `Active__c` (mirrors `getPageLayout`). This also makes "hide" and "delete" hide an industry publicly (a pre-existing gap). It ships to gtm-prod only after the read-only check in section 6.
3. The public reader `getIndustryProfiles` will honour section `Status__c` and `Active__c` (mirrors `getPageLayout`). This also makes "hide" and "delete" hide an industry publicly (a pre-existing gap). It ships to gtm-dev only after the read-only check in section 6.
4. Atomic server call `createIndustry(label, fields)` in `GtmPageContentController`. Client passes `fieldsFor('industry-tile')`. No new class, so no permission-set change.
5. Name-only modal. Server duplicate check by key; client warns on similar label. Leave the starter's `industries` card-grid section alone.

## 1. Verified findings on origin/main (and corrections to the BA scope)

| Claim | Result |
|---|---|
| `createIndustry` does not exist | Confirmed, no match in `force-app`. |
| `createSection` slugifies with `GtmContentAddress.normaliseKey`, refuses duplicates, inserts Draft, atomic rows | Confirmed. Key cap is 80 (`.left(80)`). |
| Rail foot at `gtmContentManager.html` ~240 | Confirmed: `gcm-rail-foot` at line 240 holds the single "Add section" button (`handleOpenAdd`); generic modal at ~286-330. |
| 12 fields of `industry-tile` match the 12 keys the reader consumes | Confirmed. `LAYOUT_FIELDS['industry-tile']` (`gtmPageLayouts.js` line 94): text `industryLabel`, `whyHead`, `demoRoot`; rich `pickerBlurb`, `coverSub`, `problem`, `useCase`, `solution`, `proofLine`, `whyLine`; json `uniquePoints`, `demoDeps`. Reader branches: the same 12. |
| `getPageLayout` honours Status and Active, `getIndustryProfiles` does not | Confirmed. `getPageLayout` (Reader lines 74) filters `Active__c = true AND Status__c = 'Published'`; `getIndustryProfiles` (Reader ~293-305) reads content rows only, `Active__c = true AND Section_Key__c LIKE 'industry-%'`. |
| Permission-set class grants | Confirmed. `GtmPageContentController`: GTM_Content_Manager, GTM_Content_Admin, GTM_Offering_Admin, GTM_Offering_User. `GtmPageSectionController`: only the two Content sets. `GtmPageContentReader`: all five incl. GTM_Guest. |

Corrections and new findings (not in the BA scope):

- F1. Key length. `GTM_Page_Section__c.Section_Key__c` and `GTM_Page_Content__c.Section_Key__c` are Text(80). The section key is `industry-` (9 chars) plus the slug, so the slug must be at most 71 characters. The scope's "trim to 80" would overflow the field and fail the insert. Rule: slug = `normaliseKey(label)` cut to 71 and re-trimmed of a trailing dash. Client `slugify` for this modal uses the same 71 cap.
- F2. Existing Apex reader tests will break by design. `GtmPageContentReaderTest` `getIndustryProfiles_*` tests (lines ~455-560) insert content rows only, with no section rows. After the join they return nothing. Their fixtures must add a Published, Active section (assertions unchanged). This is a fixture edit, not a weakened assertion.
- F3. The join also affects per-offering callers. `getIndustryProfiles` is called by `chooseIndustry`, `gtmConfigWizard`, `gtmSavedLinksBar` (framework `gtm`/`industry-chooser`) and `gtmConfigurator` (each offering's `configurator` page, `industry-profile` sections). The pre-check (section 6) therefore covers all offerings and templates, not just `gtm`.
- F4. Section ceiling. `publishSections`, `getPageLayout` and `discardSections` use `LIMIT 200` sections per page. "No cap on industries" is only true below 200 sections on the page (starter sections included). `createIndustry` refuses at 200 with a plain message rather than creating a section that can never be published.
- F5. `GtmAgentGetConfigState` (line ~101) also enumerates `industry-%` sections itself. Whether it filters Draft is UNVERIFIED and out of scope; the Developer reads it and reports, does not change it. Resolved later by issue #19: it did not filter Draft (it read `GTM_Page_Content__c` rows only, `Active__c = true`), so a created-but-unpublished industry leaked into GUS's `availableIndustries`. `buildOutput()` now builds the same Published-and-Active `liveKeys` set from `GTM_Page_Section__c` (framework `gtm` / `industry-chooser`) and reads only content rows whose `Section_Key__c` is in it, matching `getIndustryProfiles` (section 3).
- F6. Discard already does the right thing: `discardSections` deletes a never-published (Draft) section with its rows. So "Discard changes" on the Industry Chooser page removes an unpublished new industry cleanly.
- F7. A published industry whose label is later cleared and republished would still render a key-labelled tile. Pre-existing, owned by the `chooseIndustry` (industry-empty-state) task; not changed here.
- F8. Tooling: no web or Salesforce documentation tool was available in this session. Behaviour claims about platform semantics (SOQL `!=` including nulls, Aura deserialising another class's inner type) are marked UNVERIFIED below and are covered by a QA check.

## 2. Apex contract: `GtmPageContentController.createIndustry`

```apex
@AuraEnabled
public static String createIndustry(
    String label,
    List<GtmPageSectionController.FieldSeed> fields   // fieldKey, fieldType, label, from fieldsFor('industry-tile')
);   // returns the new SECTION key, e.g. 'industry-financial-services'
```

Note for the guided-setup contract: it lists `createIndustry(String label)` returning "the industry key". This contract widens the signature (adds `fields`), returns the section key (with the `industry-` prefix, which the rail needs as `activeKey`; strip 9 characters for the industry key), and creates all 12 rows, not only `industryLabel` and `pickerBlurb`. Guided-setup only deep-links to the page and never calls this method, so it is unaffected apart from the doc text (section 8).

Order of checks and exact user-facing messages (all `AuraHandledException`):

1. Permission guard: `Schema.sObjectType.GTM_Page_Section__c.isCreateable() && Schema.sObjectType.GTM_Page_Content__c.isCreateable()`, else "You do not have permission to add industries." (Needed because the class is `without sharing` and is granted to GTM_Offering_User. Do not retrofit other methods.)
2. `label` trimmed; blank -> "Give the industry a name." Longer than 80 -> cut to 80 (no error, matches `createOffering`); stored `Label__c` and the label value never exceed 80.
3. `slug = GtmContentAddress.normaliseKey(label)`; null -> "That name has no letters or numbers to build a key from." Then cut to 71 and strip a trailing dash. `sectionKey = 'industry-' + slug`. Do not re-implement the regex.
4. `fields` validation (shape only; the 12 keys are NOT hard-coded in Apex, that is the drift `createSection` warns about): non-null and non-empty; at most 40 entries; no duplicate `fieldKey`; each `fieldKey` matches `^[A-Za-z][A-Za-z0-9]{0,79}$`; each `fieldType` in `text, rich, json, icontext`; one entry has `fieldKey = 'industryLabel'` and `fieldType = 'text'`. Failure -> "The industry layout is not valid. Reload and try again."
5. Page exists: at least one `GTM_Page_Section__c` with `Offering_Key__c = 'gtm'` (`FRAMEWORK_KEY`), `Template_Type__c = 'industry-chooser'`. Else "Create the Industry Chooser page first."
6. Ceiling: `COUNT()` of sections on that page >= 200 -> "The Industry Chooser page has reached its limit of 200 sections."
7. Duplicate by key: a section with the same offering, template and `Section_Key__c = sectionKey` -> `An industry called "<label>" already exists. Edit it instead.`
8. Insert, inside one `Database.setSavepoint()`, catching `DmlException` -> rollback and "The industry could not be created: <detail>":
   - Section: `Section_Address__c = GtmContentAddress.forSection('gtm','industry-chooser',sectionKey)`, `Layout_Type__c = 'industry-tile'`, `Width__c = 'standard'`, `Label__c = label`, `Active__c = true`, `Status__c = 'Draft'`, `Sort_Order__c = (max existing on that page, 0 if none) + 10`.
   - One content row per seed, addressed with `GtmContentAddress.forField`, `Sort_Order__c = 10, 20, ...`, `Active__c = true`, `Field_Type__c`/`Label__c` from the seed. Empty values: json `[]`, icontext `{"label":"","icon":""}` (same rule as `createSection`). The `industryLabel` row only: `Draft_Value__c = label`, `Status__c = 'Draft'`, `Text_Value__c` left blank. All other rows have no value.
9. Return `sectionKey`.

Not called by any GUS tool (AGENTS.md section 1 zero-DML surface untouched). No object, field or permission-set change. Apex deploy to a production-type org forces a full local test run (gtm-prod is not a target, see section 7).
Not called by any GUS tool (AGENTS.md section 1 zero-DML surface untouched). No object, field or permission-set change. Apex deploy to a production-type org forces a full local test run (gtm-dev is not a target, see section 7).

## 3. Reader contract: `GtmPageContentReader.getIndustryProfiles` Status/Active join

Two queries replace one. Signature and `IndustryProfile` shape unchanged.

```apex
Set<String> liveKeys = new Set<String>();
for (GTM_Page_Section__c sec : [
    SELECT Section_Key__c
    FROM   GTM_Page_Section__c
    WHERE  Offering_Key__c  = :offeringKey
    AND    Template_Type__c = :templateType
    AND    Active__c        = true
    AND    Status__c        = 'Published'
    AND    Section_Key__c LIKE 'industry-%'
    LIMIT  200
]) { liveKeys.add(sec.Section_Key__c); }
if (liveKeys.isEmpty()) return out;

// existing content query, with one added predicate:
//   AND Section_Key__c IN :liveKeys
```

- Mirrors `getPageLayout` exactly: `Draft_State__c` is deliberately not read, so a pending hide, reorder or delete does not change the public page until Publish.
- `Active__c = true` on the content row and the rest of the existing query stay.
- Result order stays `ORDER BY Section_Key__c`.
- Draft industry with no published label: the section is Draft, so it is not in `liveKeys`, no profile is created, no tile. There is never a raw-key ghost tile. (Its `Draft_Value__c` label is invisible to the public reader by construction, which reads only `Text_Value__c`.)
- The Content Manager preview (`chooseIndustry` `_preview` path) builds tiles from draft content passed by the editor, not from this method, and is unaffected.

## 4. How Publish makes a Draft industry live (existing path, no change)

`GtmPageContentController.publishPage('gtm','industry-chooser')` is template-agnostic:

1. `publishSections` loads every section on the page; a section with `Status__c = 'Draft'` (`wasNew`) gets `Status__c = 'Published'`, `Draft_State__c` cleared (pending sort/active applied, pending delete removes the section and its rows).
2. The content step selects rows with `Status__c = 'Draft'` and non-null `Draft_Value__c`, snapshots a version, copies the draft into the live column (`Text_Value__c` for text) and marks the row `Published`. The `industryLabel` row (seeded as Draft with `Draft_Value__c = label`) therefore goes live in the same call; the other 11 rows have no draft and are untouched.
3. After Publish `getIndustryProfiles` returns the industry with its label. Confirmed by reading `publishSections`/`publishPage`; a test proves it (section 5).

The rail's existing "unpublished" marker (`isNew = Status__c == 'Draft'`) applies to industry sections unchanged.

## 5. LWC contract: `gtmContentManager`

Control. In the rail foot (html line ~240) the "Add section" button is replaced, not supplemented, when `selectedTemplate === 'industry-chooser'` by an "Add industry" button (same `gcm-add` class, `utility:office`, `disabled={isSaving}`). All other templates keep "Add section". `TEMPLATE_LAYOUTS['industry-chooser']` stays `[]`; the generic modal is not reopened. The `noLayoutsReason` branch for `industry-chooser` becomes unreachable; remove or reword it and its (untested) string only if dead.

New tracked state: `industryOpen` (Boolean), `industryName` (String), `industryError` (String, server error shown inside the modal).

Imports: `createIndustry from '@salesforce/apex/GtmPageContentController.createIndustry'`. `fieldsFor` is already imported from `c/gtmPageLayouts`.

Getters:
- `isIndustryPage`: `selectedOffering === 'gtm' && selectedTemplate === 'industry-chooser'` (hard-code `'gtm'` only via the existing framework constant if the component has one).
- `industrySlug`: `slugify(industryName)` capped at 71 (separate from the 80-cap `slugify`; add an optional length argument, do not change the existing default).
- `industryKeyPreview`: `industry-<slug>` or ''.
- `industryAddressPreview`: `gtm::industry-chooser::industry-<slug>` or ''.
- `industryValidation` (string, in order): blank -> "Give the industry a name."; empty slug -> "That name has no letters or numbers to build a key from."; slug matches an existing `sections[].sectionKey` -> `An industry called "<name>" already exists. Edit it instead.`; else ''. Warn (not block) if the label matches an existing industry label case-insensitively but with a different key: "There is already an industry with a similar name."
- `canAddIndustryDisabled`: `!industrySlug || !!duplicate || isSaving`.

Modal states: closed; open-idle (empty, button disabled, no error shown until the user types); open-invalid (inline validation message, button disabled); open-valid (key and address preview, button enabled); saving (button disabled, `isSaving`, `saveMessage = 'Adding industry...'`); server-error (modal stays open, `industryError` shown, name preserved so the admin can fix it); success (modal closes, `saveMessage = 'Industry added'`, reload, land on the new section).

Text: title "Add an industry"; sub "Give it a name. Its key is generated. Fill in the rest of its tile afterwards, then Publish to show it on the site."; input "Industry name" (required, `max-length` 80); read-only key and address preview (`modal-addr` class); buttons "Cancel" and "Add industry" (brand). Reuse existing modal markup and CSS (`scrim`, `modal`, `modal-h/b/f`).

Call:
```js
createIndustry({ label: this.industryName.trim(), fields: fieldsFor('industry-tile') })
  .then(sectionKey => { this.industryOpen = false; this.saveMessage = 'Industry added';
        this.activeKey = sectionKey; return this.loadPage(); })
  .then(() => { this.activeKey = sectionKey; this.scrollRailTo(sectionKey); })
  .catch(err => { this.industryError = this.messageFrom(err) || 'The industry could not be created.'; })
  .finally(() => { this.isSaving = false; });
```
(Developer: hold `sectionKey` in a local, as `handleCreateSection` does with `key`.)

Files not to edit: `chooseIndustry.*` (industry-empty-state task), `gtmFilterBar.*`, `gtmAssessmentsTableModel.js` (compact-filters), `guided-setup.md` on its own branch, permission sets.

## 6. Read-only pre-check for existing draft or hidden industries (gates any gtm-prod deploy)

Run BEFORE the reader change reaches any org holding real data. Read-only (`sf data query`), structure only, no content values. Run on gtm-staging first (design and staging work are not blocked). The gtm-prod run is quota-blocked now; it gates a gtm-prod deploy only.
## 6. Read-only pre-check for existing draft or hidden industries (gates any gtm-dev deploy)

Run BEFORE the reader change reaches any org holding real data. Read-only (`sf data query`), structure only, no content values. Run on gtm-staging first (design and staging work are not blocked). The gtm-dev run is quota-blocked now; it gates a gtm-dev deploy only.

```
# Q1 industry sections that would disappear (not Published, or hidden)
sf data query --target-org <alias> --query "SELECT Offering_Key__c, Template_Type__c, Section_Key__c, Layout_Type__c, Status__c, Active__c, Draft_State__c FROM GTM_Page_Section__c WHERE Section_Key__c LIKE 'industry-%' AND (Status__c != 'Published' OR Status__c = null OR Active__c = false) ORDER BY Offering_Key__c, Template_Type__c, Section_Key__c"

# Q2 every industry section (the baseline)
sf data query --target-org <alias> --query "SELECT Offering_Key__c, Template_Type__c, Section_Key__c FROM GTM_Page_Section__c WHERE Section_Key__c LIKE 'industry-%' ORDER BY Offering_Key__c, Template_Type__c, Section_Key__c"

# Q3 industry content with live rows, grouped (compare to Q2: a group with no matching Q2 row has no section and would vanish)
sf data query --target-org <alias> --query "SELECT Offering_Key__c, Template_Type__c, Section_Key__c, COUNT(Id) n FROM GTM_Page_Content__c WHERE Section_Key__c LIKE 'industry-%' AND Active__c = true GROUP BY Offering_Key__c, Template_Type__c, Section_Key__c ORDER BY Offering_Key__c, Template_Type__c, Section_Key__c"
```

Pass criteria: Q1 returns zero rows, and every Q3 group appears in Q2. Any Q1 row or Q3-without-Q2 group is an industry that would vanish publicly after the change (framework `gtm`/`industry-chooser`, or an offering's per-offering `industry-profile` sections). Report them to the user; the user decides whether to publish, delete or accept each before the deploy. The `!=`-includes-null behaviour is UNVERIFIED (no doc tool), which is why `Status__c = null` is written explicitly. Do not write any results into the repo with content text; org IDs, usernames and secrets are never committed.

## 7. Deployment rules

- gtm-staging only. `--dry-run` first, spelled out (never `-c`), then deploy. Apex deploy uses the test level the runbook requires; a full local test run is expected on production-type orgs.
- gtm-prod is Production and NOT a deploy target unless the user directly authorises it, and never before section 6 passes there.
- gtm-dev is Production and NOT a deploy target unless the user directly authorises it, and never before section 6 passes there.
- Experience Cloud: no site metadata is touched, so no `sf community publish` is needed; the reader change is Apex only.

## 8. Amendments required to `docs/architecture/guided-setup.md` (branch `agent/issue-guided-setup`, NOT edited here)

Sections 3A (G0 revised paragraph) and 3 (G0) and the `industry_added` row of section 6 must be updated by the guided-setup owner: signature `createIndustry(String label, List<GtmPageSectionController.FieldSeed> fields)`, returns the section key, creates all 12 industry-tile rows (label only in `industryLabel`, held as a draft value), new industries are Draft and invisible publicly until Publish, and `industry_added` (which reuses `getIndustryProfiles`) will count only PUBLISHED industries after this change. Consequence to design in that doc: a just-added, unpublished industry will read TODO "No industries have been added yet" until Publish. Recommend its detail text says "add an industry, then Publish the Industry Chooser page".

## 9. Test plan

Hermetic: each test builds its own `industry-chooser` page and data, no `SeeAllData`, no Migration Accelerator data, nothing seeded.

Apex, `GtmPageContentControllerTest` (new):
- happy path: returns `industry-financial-services`; 1 section (Draft, Active, layout `industry-tile`, sort after existing, address correct); 12 content rows; `industryLabel` has `Draft_Value__c` = label, blank `Text_Value__c`, Status Draft; json rows `[]`.
- duplicate: "Financial Services", "financial services", "Financial-Services", "Financial Services!" all refused after the first; section and row counts unchanged.
- blank label; label of only punctuation ("!!!"); label over 80 chars (created, `Label__c` length 80, section key length at most 80); 71-char slug boundary; page missing; ceiling at 200 sections; invalid fields (null, empty, no `industryLabel`, duplicate key, bad key); rollback (force a DML failure, e.g. a field seed whose `Label__c` exceeds 255? or a pre-inserted content row at the same `Content_Address__c`; assert zero sections remain); not createable (`System.runAs` a Standard User with no GTM permission set; skip with a documented assertion if the profile is absent).
- drift alarm: a test-local list of the 12 keys equals the keys `getIndustryProfiles` reads (seed one row per key, assert every field lands on the profile).
- publish round trip: create, `publishPage('gtm','industry-chooser')`, assert section Published and `getIndustryProfiles('gtm','industry-chooser')` returns it with its label.

Apex, `GtmPageContentReaderTest`: existing `getIndustryProfiles_*` fixtures gain a Published, Active section per industry key (F2; assertions unchanged). New: Draft section not returned (rows present); hidden (Active false) section not returned; Published and Active returned with label; a pending drafted hide (`Draft_State__c` set, Active still true) still returned; content rows with no section not returned; a mix returns only the live one.

Jest, `gtmContentManager.test.js` (new describe, appended): on `industry-chooser` the rail shows "Add industry" and not "Add section"; on another template "Add section" stays and no "Add industry"; modal key and address preview; disabled when blank, punctuation-only or duplicate (case and punctuation variants) with the plain messages; 71-char cap in the preview; success calls `createIndustry` with `label` and 12 `fieldsFor('industry-tile')` seeds, closes, reloads, lands on the returned key; server error keeps the modal open with the message; `createSection` is NOT called. `gtmPageLayouts.test.js`: assert `fieldsFor('industry-tile')` keys equal the 12-key list (add only if not already covered).

Specs that must pass unmodified: all existing describes in `gtmContentManager/__tests__/gtmContentManager.test.js` (page-title overrides #40, shared page header B14b5, 0-section render), `gtmPageLayouts/__tests__/gtmPageLayouts.test.js`, and the `chooseIndustry`, `gtmConfigurator`, `gtmConfigWizard`, `gtmSavedLinksBar` specs (they mock the Apex, so they are unaffected). Apex assertions in existing tests are not to be weakened; only fixtures change (F2). `npm test` and `sf apex run test --test-level RunLocalTests` (staging) must pass.

## 10. Developer file list

Edit:
- `force-app/main/default/classes/GtmPageContentController.cls` (add `createIndustry` and private helpers only)
- `force-app/main/default/classes/GtmPageContentControllerTest.cls`
- `force-app/main/default/classes/GtmPageContentReader.cls` (`getIndustryProfiles` join, comment updated)
- `force-app/main/default/classes/GtmPageContentReaderTest.cls` (fixtures plus new tests)
- `force-app/main/default/lwc/gtmContentManager/gtmContentManager.js`, `.html` (rail-foot swap, modal), and `.css` only if the existing modal classes are insufficient
- `force-app/main/default/lwc/gtmContentManager/__tests__/gtmContentManager.test.js` (append; add the `createIndustry` jest.mock)
- `force-app/main/default/lwc/gtmPageLayouts/__tests__/gtmPageLayouts.test.js` (only the 12-key assertion, if missing)
- `docs/backlog.md` (record D12 follow-up done, the reader behaviour change and the pre-check)

Do not create or edit: permission sets, any `-meta.xml`, objects, fields, custom metadata, `instrument/`, `chooseIndustry.*`, `gtmFilterBar.*`, `gtmAssessmentsTableModel.js`, `GtmPageSectionController.cls`.

## 11. Sequencing and overlap

Files this task edits that other open work also edits (compared with `git diff origin/main...<branch>`):
- PR #240 (`agent/issue-browser-followups`): `gtmContentManager.js` (one hunk near line 253), `gtmContentManager.html` (hunks near lines 137-167, above the rail foot), and `__tests__/gtmContentManager.test.js`. Same three files as this task; hunks are in different places, so a textual conflict is unlikely except in the test file (both append) and imports.
- compact-filters: touches `gtmFilterBar.*` and `gtmAssessmentsTableModel.js`, `docs/architecture/gtm-filter-bar.md`; no overlap with this task's files.
- industry-empty-state: `chooseIndustry.*` only; no file overlap. Behavioural dependency: its neutral empty notice is what the public page shows once this reader change hides all Draft industries; acceptance check needs it deployed to the same org.
- guided-setup: `docs/architecture/guided-setup.md` and its scope only; doc amendment in section 8 is the coupling.

Recommendation: implement on top of #240 once it merges (rebase `agent/issue-add-industry` onto `origin/main` after the merge, then start the LWC work). The Apex work has no overlap with anything open and can begin now on this branch. Land add-industry before guided-setup ships its `industry_added` row.

## 12. QA plan (gtm-staging)

Preconditions: gtm-staging is a blank install where the framework Industry Chooser page exists and has zero industry sections. Run section 6 Q1-Q3 there first and record the result.

1. `npm test` and Apex tests locally/CI green. `sf project deploy start --dry-run --target-org <staging alias> --test-level RunLocalTests` passes; then the real deploy to staging.
2. Content Manager > Framework > Industry Chooser as a GTM_Content_Manager user: "Add industry" shows; an offering page and an FAQ page still show "Add section".
3. Add "Financial Services": modal previews `industry-financial-services` and its address; blank, "!!!" disabled with the plain message; submit closes the modal, lands on a new rail item marked unpublished, `industryLabel` filled, the other 11 fields empty, no "fields have no record yet" notice.
4. Public `/gtm/s/choose-industry` (guest, and a signed-in prospect): the neutral "no industries" notice still shows, no tile, no key-labelled ghost.
5. Publish the page: the "Financial Services" tile appears with its label; click goes to the configurator with `?industry=financial-services`; the configurator, wizard and saved-links bar list it.
6. Duplicates ("financial services", "Financial-Services", "Financial Services!") are refused; row and section counts unchanged. A name over 80 chars trims.
7. Edit `industryLabel` (rename), reorder, hide then Publish (tile disappears), show then Publish (tile returns).
8. Delete an unpublished industry: immediate, no orphan rows (`SELECT COUNT() FROM GTM_Page_Content__c WHERE Section_Key__c = 'industry-<key>'` = 0). Delete a published one: marked, then removed at Publish; the public page returns to the neutral notice. "Discard changes" on an unpublished new industry removes it.
9. Repeat add as GTM_Content_Admin and as GTM_Offering_Admin (proves class access and the Aura-typed `FieldSeed` parameter, UNVERIFIED). A GTM_Offering_User (rep) is refused by the guard, or has no UI, without a server error page.
10. Nothing seeded: after deploy and before step 3 there are no industry, offering or page-copy records that this change created.
11. Dependent surfaces: Content Manager preview pane on the Industry Chooser page, an offering's configurator page with `industry-profile` sections (still shown once published), and the guided-setup `industry_added` row if that branch is present (reads DONE only after Publish).
12. gtm-prod: NOT deployed. When the quota resets, run section 6 read-only on gtm-prod and hand the result to the user; only a direct user authorisation enables a gtm-prod deploy.
12. gtm-dev: NOT deployed. When the quota resets, run section 6 read-only on gtm-dev and hand the result to the user; only a direct user authorisation enables a gtm-dev deploy.

## 13. Gate for the LWC part: class access and the `FieldSeed` parameter (UNVERIFIED, decided by a QA run, not by speculation)

Verified from `force-app/main/default/permissionsets` on origin/main 0538a34 (class grants only):

| Permission set | GtmPageContentController | GtmPageSectionController | GtmPageContentReader |
|---|---|---|---|
| GTM_Content_Manager | yes | yes | yes |
| GTM_Content_Admin | yes | yes | yes |
| GTM_Offering_Admin | yes | NO | yes |
| GTM_Offering_User | yes | NO | yes |
| GTM_Guest | no | no | yes |

`createIndustry` is on `GtmPageContentController` and takes `List<GtmPageSectionController.FieldSeed>`. A user with only GTM_Offering_Admin (or GTM_Offering_User) can call the controller but has no grant on `GtmPageSectionController`, the class that declares the `FieldSeed` type. Whether the Aura framework will deserialise that inner type for such a user is not documented in anything available to this task, so the signature is NOT changed on speculation.

Practical reach: the only UI that calls `createIndustry` is `gtmContentManager`, and it also imports `getEditorSections` from `GtmPageSectionController`, so a user holding only GTM_Offering_Admin cannot load the editor at all. The question is therefore live only for a user who has GTM_Offering_Admin plus one Content set's UI access but not the section class (none of the shipped combinations), or for a future caller such as guided-setup, which today only deep-links and never calls the method.

QA gate (gtm-staging, blocks sign-off of the LWC part, browser plan step 9):
1. As a GTM_Content_Manager user and as a GTM_Content_Admin user: "Add industry" succeeds (both classes granted; expected to pass).
2. As a user assigned ONLY GTM_Offering_Admin, call `createIndustry` through the Aura path (a temporary Lightning page or the Content Manager component if the user can open it) with `fieldsFor('industry-tile')` seeds. Record exactly one of: (a) succeeds, so nothing to do; (b) fails with a deserialisation, "invalid type" or access error before Apex runs, so the fix is a `createIndustry` parameter type owned by `GtmPageContentController` itself (a small inner `IndustryFieldSeed` class with the same three `@AuraEnabled` members), which is a contract change to be made by the Architect and re-tested, not something Developer does ahead of evidence; (c) fails inside Apex with the plain "You do not have permission to add industries." message, which is the guard working (the user lacks create access on the objects).
3. As a GTM_Offering_User: the guard message or no UI, and no Aura error page.
Until step 2 is recorded, the LWC part may merge for Content Manager and Content Admin users only.
