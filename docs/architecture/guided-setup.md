# Guided Setup (Settings > Setup section)

Status: contract, written before code (CLAUDE.md section 4). Authoritative once merged.
Scope: `docs/agent-artifacts/task-scope-guided-setup.md` (BA, including addendum 1.H and open questions 8-10).
Surface: a first, default-selected section of the existing GTM Offerings Settings tab (ADR-0010). No new tab, no new object, no new field, no stored state.

Verification note: the Architect had no web or Salesforce-docs tool. Every platform-behaviour claim below marked (UNVERIFIED) is settled only by the spike in section 9, run on gtm-staging. Every code claim not so marked was read on origin/main (16222d3).

## 0. Deltas applied from the implementation plan (2026-09-20)

Source: `guided-setup-implementation-plan.md` section 2.4. Where this list and a later section disagree, this list wins.

1. Spikes Q1, Q2 and Q4 (section 9) no longer gate the build. They are replaced by a runtime fallback: any inline action the platform refuses (for example the admin lacks the "Assign Permission Sets" system permission) returns `fallbackToSetup = true` plus the Setup path, and the LWC shows that link instead of the button. Site identification uses one heuristic: the `Network` named `GTM`, else the only Network, else UNKNOWN (never DONE). QA still records what actually happened in section 10.
2. `SetupItem` gains `blockedBy` and `collapsedByDefault`; `AssignResult` gains `fallbackToSetup` and `setupPath` (section 5 shapes updated below).
3. `org_*` rows other than `org_digital_experiences` are static INFO rows with no detection and make no claim about state.
4. Add industry has landed (`add-industry.md`): `industry_added` uses the wording "add and publish an industry"; the reader returns only Published, active industries, so a Draft reads TODO until published.
5. `GtmScheduledJobsController` had no class access in `GTM_Offering_Admin` on main; the change adds it (gap G2), together with the two new Setup controllers.
6. Install and fresh-org runbooks and the `deploy-fresh-org.sh` closing message now point at Settings > Setup (section 8 is done, not pending). No relayed manual list remains; the API key stays an optional, neutral row.

## 1. Principles (binding)

1. Defaults are entered by the admin, never shipped. No industry, offering, page copy or example content is created by the deploy, the scripts, or this section. The "add examples" opt-in is an open question, not built.
2. The section only detects and points. It states, per row, why in one plain sentence, whether it is required/recommended/optional, whether a human must act, and where in the app the admin does it. It never stores "done"; every load and every Re-check re-detects.
3. Inline actions exist for exactly three things: assigning an allow-listed permission set, scheduling the two existing purge jobs, and creating empty framework page structure (no content) from the existing starter definitions. Everything else is a link.
4. No agent or doc explains steps to the user. The row text is the explanation. The install doc keeps one fallback sentence (section 8).
5. Neutral optional items: never red, never counted, never nagging. The AI provider keys are the canonical example.
6. Not a GUS tool. Neither controller is registered in `GtmAppAgentSurface.registeredTools()`; `GtmAgentToolSurface` is untouched and its zero-DML contract (AGENTS.md section 1) is unaffected.

## 2. Corrections to the BA scope (verified against origin/main)

| BA claim | Fact on origin/main | Consequence |
|---|---|---|
| `Presentation_Stage__c` is a draft flag on `GTM_Offering__mdt` | It is a field on `GTM_Saved_Configuration__c` (a rep link's stage). `GTM_Offering__mdt` has no stage field (fields: Annual_Target, CMS_Channel_Id, Has_Conduit, Label, Monthly_Target, Offering_Key, Site_Path). `GtmOverviewOfferingCounts` filters Draft on links, not offerings. | Rows 8/14/15 in the scope are re-specified below. |
| Offerings are created only via Setup > Custom Metadata | An offering is created in-app: `GtmPageContentController.createOffering(name)` (Content Manager home) inserts a tile `GTM_Page_Section__c` (Template `offerings-listing`, Section `tile`) plus three `GTM_Page_Content__c` rows. Draft/Published is `GTM_Page_Section__c.Offering_Status__c` (default Draft), flipped by `setOfferingStatus`; `Archived__c` is separate. | Offering exists/published rows detect the tile section and deep link into Content Manager, not Setup. |
| `Metadata.Operations` is unused | Correct, but the `createOffering` doc comment says a metadata row "is enqueued". It is not (no `Metadata.` usage in classes). The comment is stale. | See gap G1. |
| Public offerings listing follows tiles | `GtmPageContentReader.getOfferingTiles()` starts from `GTM_Offering__mdt` rows and only then applies tile content/status. An offering created in-app with no `GTM_Offering__mdt` row does not appear there. | Gap G1: prospects cannot see an in-app-created offering until a human adds the `GTM_Offering__mdt` record. (UNVERIFIED end to end; from code reading. Spike Q6.) |
| `GtmScheduledJobsController` is reusable by the admin | Reusable, but its class is NOT in `GTM_Offering_Admin` classAccesses on origin/main (grep of permissionsets and profiles: no match; `GtmAgentSettingsController` and `GtmReadoutApprovalSettingsController` are). | Pre-existing defect: the Scheduled Jobs section works only for users whose access bypasses class checks. Fix (add the grant) is part of this change. |
| Self-approval bypasses the manager route | Confirmed. `GtmReadoutController` (header, `isSelfApprovalEnabled` ~1411) reads `Self_Approval_Enabled__c`; self-approval is a direct Draft->Approved for the owner with no `Approval.process()`. Approval process routes to owner's Manager otherwise. Note controller uses `getInstance()`; the Approval Routing section writes/reads `getOrgDefaults()`. | Manager row is shown only while the org-default toggle is false. Checklist uses `getOrgDefaults()`; a user/profile-level override is not modelled (accepted, stated in the row detail). |
| `Site`/`Network` exposure | `GtmPageContentReader.getSiteInfo()` already queries `Network (Id, UrlPathPrefix)` inside try/catch, proving `Network` is queryable from this app's Apex. | Site detection starts from `Network`. Identifying which Network is ours is UNVERIFIED (spike Q4). |

## 3. Gaps that block a fully in-app blank install (raise to coordinator)

- G0 (blocker for row `industry_added`): there is no in-app way to add an industry on main. `TEMPLATE_LAYOUTS['industry-chooser'] = []` and `noLayoutsReason` deliberately closed the generic Add-section path (docs/backlog.md D12) with the stated follow-up "purpose-built Add industry flow". Until that ships, the row can detect and deep link but the admin cannot complete it in the app. Contract for the dependency (owned by its own task, not this one): `GtmPageContentController.createIndustry(String label, List<GtmPageSectionController.FieldSeed> fields)` returning the SECTION key (`industry-<slug>`), specified in `docs/architecture/add-industry.md` (authoritative; see 3A); surfaced as an "Add industry" control on the Industry Chooser page in Content Manager. This task's row deep-links to that page and needs nothing else from it. The Add-industry task is now a separate task that lands BEFORE guided-setup; the row's text reads "add and publish an industry".
- G1 (gap for `offering_listed`): in-app offering creation does not create the `GTM_Offering__mdt` record the public listing needs. Options for the user: (a) row deep-links to Setup > Custom Metadata Types > GTM Offering > Manage Records (human step), (b) a later `Metadata.Operations.enqueueDeployment` task (async, needs Customize Application, UNVERIFIED). This task ships (a).
- G2: the `GtmScheduledJobsController` class-access grant is missing (section 2). 
- Dependency (coordinator split): the empty-vs-error message in `chooseIndustry` is owned by slug `industry-empty-state`. This task adds only the checklist row and must not touch `chooseIndustry.js`, its html, or its Jest spec.

## 3A. Framework and offering page STRUCTURE (revision 2, user correction)

User direction: a blank install (for example gtm-staging) has none of the Content Manager sections that gtm-dev has, so the Framework cards are empty and not editable. Setup must lay down the structure from the page definitions that already exist, with no new html/js/css, no content and no seeding.

What the code does today (origin/main):
- `STARTER_PAGES` (and `starterFor(templateType)`, which adds each layout's declared fields via `fieldsFor`) live only in `lwc/gtmPageLayouts/gtmPageLayouts.js`, client-side. There is no Apex copy and no `data/seed` framework data (offering key `gtm` sections exist only as org records).
- The only place they are applied is `gtmContentHome.handleGoToPage`: the "New Offering Page" modal calls `starterFor(template)` and passes the result to `GtmPageSectionController.createPage(offeringKey, templateType, sections)`. So a "create from starter" action already exists in the Content Manager UI, one page at a time, for the framework (owner "Framework") and for an offering, but only for a user with Content Manager access, and it does not offer `assistant` (`SETTINGS_TEMPLATES` filter).
- `createPage` inserts, per starter section, a `GTM_Page_Section__c` (`Status__c = 'Draft'`, `Active__c = true`, key/label/help/layout/width/order from the seed) and one empty `GTM_Page_Content__c` row per field the layout declares (no text; json fields get `[]`). It is all-or-nothing per page in one savepoint and REFUSES a page that already has any section ("That page already has sections"), so it never duplicates or overwrites, but it also never fills in a single missing section of a partly built page.
- `GtmPageContentController.createOffering(name)` does NOT use starters. It inserts only the `offerings-listing`/`tile` section (Published) and three tile content rows (name, mark, description with placeholder text "Describe X here."). An offering's `story` and `configurator` pages are separate `createPage` calls from the same modal. Note the placeholder description is existing behaviour, not something this task adds.
- `GtmPageSectionController` is granted only to `GTM_Content_Manager`/`GTM_Content_Admin`, not `GTM_Offering_Admin`.

Design (reuse, do not fork):
- New required checklist row `framework_pages` ("Create the framework pages"), first in the CONTENT category, before `industry_added`. Detection per framework template in `offerings-page`, `industry-chooser`, `faq-bd`, `faq-content-manager`, `assistant`: `SELECT COUNT() FROM GTM_Page_Section__c WHERE Offering_Key__c='gtm' AND Template_Type__c=:t`. DONE when every one has at least one section (an existing page, however it has drifted, counts as built). TODO lists the missing templates in `detail`. Action type `CREATE_FRAMEWORK_PAGES`, `humanMustAct = false` (one click by the admin, nothing typed).
- The LWC builds the seeds with `starterFor(template)` imported from `c/gtmPageLayouts` (the single definition; no copy in Apex, no new html/js/css) and, for each missing template only, calls one new thin Apex method that delegates to the existing `GtmPageSectionController.createPage` (called, not copied):

Contract (seeds are per template, so the method takes a template and its seeds; non-setup DML only, kept apart from the permission-set methods):
```apex
@AuraEnabled
public static FrameworkPageResult createFrameworkPage(
    String templateType, List<GtmPageSectionController.SectionSeed> sections);

public class FrameworkPageResult {
    @AuraEnabled public String  templateType;
    @AuraEnabled public Boolean created;    // false = already existed, nothing touched (idempotent)
    @AuraEnabled public Integer sectionCount;
    @AuraEnabled public String  message;
}
```
  Rules: `offeringKey` is fixed to `GtmPageContentController.FRAMEWORK_KEY` inside the method (never a parameter); `templateType` must be one of the five framework templates (hard allow-list; anything else, including offering templates and null, throws before DML); if any section already exists for `gtm`/`templateType` return `created=false` without calling `createPage` (so a page is never re-laid, never duplicated, never overwritten and the "already has sections" exception is not surfaced as an error); otherwise call `GtmPageSectionController.createPage('gtm', templateType, sections)`. This wrapper exists so `GTM_Offering_Admin` need not be granted `GtmPageSectionController` (which is a content-role class), consistent with the class-access-only-to-what-is-needed rule; the wrapper is granted to `GTM_Offering_Admin` only. Seeds are client-supplied like the existing modal, so a caller with this class can write no more than `GTM_Offering_Admin` already can (full CRUD on both page objects).
- The LWC loops over `missing` templates, one call each (5 calls at most, each its own transaction), then re-fetches the checklist. A failure on one template leaves the others created and the row TODO for the remainder; re-clicking is safe.
- Result: sections exist as Draft, fields exist and are empty, the Framework cards in Content Manager become editable and show no content. Nothing is seeded and no text is written. (UNVERIFIED: whether public framework pages render from Draft sections. `GtmPageSectionController` line ~503 has a `neverLive = Status__c != 'Published'` rule, so publishing may be needed in the Content Manager; spike Q10.)

New offering: the same definitions apply to an offering's `story` and `configurator` (and `offerings-listing`, already made by `createOffering`). This task does not change offering creation (that is Content Manager's "New Offering" then "New Offering Page"). A row `offering_pages` (tier O, INFO) reports, for each non-archived offering, which of `story`/`configurator` has no sections, and links to Content Manager home; it does not create anything. Rationale: creating pages for offerings the admin has not chosen or named is the "shipped default" the user rejected, and per-offering creation already exists in the UI.

Industries (G0, revised): the `industry-chooser` starter creates the `industries` section as a `card-grid` (its "One card per industry offered" help text), but individual industries are `industry-<key>` sections read by `GtmPageContentReader.getIndustryProfiles`, and no starter creates them. The generic Add-section modal was closed on purpose (`TEMPLATE_LAYOUTS['industry-chooser'] = []`, backlog D12). So after `framework_pages`, an admin still cannot add an industry in the app: G0 stands. The `industry_added` row therefore depends on a separate small piece, "Add industry":
```apex
// GtmPageContentController; authoritative contract: docs/architecture/add-industry.md
@AuraEnabled
public static String createIndustry(String label, List<GtmPageSectionController.FieldSeed> fields);   // returns the SECTION key, industry-<slug>
```
  Summary of the add-industry contract (its own doc wins on any difference; this task depends on it and does not implement it): label trimmed, non-blank, capped at 80; the slug is capped at 71 characters so the section key `industry-<slug>` stays within 80; blank/punctuation-only keys and duplicates (case and punctuation variants) are refused with a plain message; the `industry-chooser` page must exist (else "create the framework pages first", the `framework_pages` prerequisite); creation refuses at 200 sections on the page; it inserts one section `industry-<slug>` (`industry-tile` layout, Draft, Active, ordered after existing) and ALL 12 `industry-tile` field rows empty, with only `industryLabel` holding a value, stored as a draft value (not `pickerBlurb` as well); rolled back as a unit on failure. A new industry is a Draft and stays hidden from the public chooser until the admin clicks Publish on the Industry Chooser page (the user's decision). `getIndustryProfiles` will also honour section `Status__c` and `Active__c`, so the reader counts only PUBLISHED, active industries; it is also called by `gtmConfigWizard`, `gtmSavedLinksBar` and `gtmConfigurator`, so their lists change with it (that is the add-industry task's regression surface, not this one's). Consequence for this checklist: `industry_added` reuses the reader unchanged and reads TODO after an industry is added but before Publish, so its detail text and deep link say "add and publish an industry". UI: an "Add industry" control on the Industry Chooser page (add-industry task; `gtmContentManager`). Sequencing: add-industry is a separate task that lands before guided-setup ships the row; `chooseIndustry.*` and the add-industry files are not touched here (the neutral empty state belongs to industry-empty-state).

Drift risk (record plainly): the real gtm-dev framework sections have likely diverged from `STARTER_PAGES` (renamed, reordered, added, extra fields), and no framework data is in source control. Consequences: (a) `framework_pages` treats any existing section as "built" and never edits it, so gtm-dev is untouched and a fresh org is laid out to the current starters, meaning gtm-staging and gtm-dev structures can differ; (b) structure defined by `STARTER_PAGES` is the only version that will ever be in source control, so if gtm-dev content is what the business regards as correct, the definitions should be reconciled to it. A read-only comparison needs a retrieve from gtm-dev of `GTM_Page_Section__c` (`Offering_Key__c`, `Template_Type__c`, `Section_Key__c`, `Label__c`, `Layout_Type__c`, `Width__c`, `Sort_Order__c`, `Help_Text__c`, `Status__c`, `Active__c`) and of `GTM_Page_Content__c` STRUCTURE only (`Template_Type__c`, `Section_Key__c`, `Field_Key__c`, `Field_Type__c`, `Label__c`, `Sort_Order__c`; explicitly not the text/rich/JSON values) for `Offering_Key__c='gtm'`. This retrieve is currently quota-blocked, so it has not been done. After it, diff against `STARTER_PAGES` per template and decide as a separate change whether to update `STARTER_PAGES` (client definitions) to the live shape; this task does not do so. Any export committed must carry no content text.

## 4. UX and states

Section `setup` is first in `SECTIONS` and the default (`selectedSectionId = SECTIONS[0].id` already picks the first entry, so no other change to default logic). Layout: header line "N of M required steps done" (plus ", K could not be verified" if any REQUIRED row is UNKNOWN), then groups in order: Required, Recommended, Optional, Info and organisation checks. Each row: status icon, title, one-sentence why, detail line, a "You need to do this" / "Done for you" marker (`humanMustAct`), one action, and a global Re-check button (and re-detect on `connectedCallback`). Optional/Info rows are collapsed by default and are never counted.

Status vocabulary (`status`): `DONE`, `TODO`, `NOT_SET` (optional/recommended not entered; neutral), `BLOCKED` (a prerequisite is missing; `detail` names it), `UNKNOWN` (cannot be detected or the read failed; never rendered as done), `INFO` (state shown, not completable). `tier`: `REQUIRED`, `RECOMMENDED`, `OPTIONAL`, `INFO`. Required-count math: `requiredDone` counts REQUIRED rows with DONE; UNKNOWN/BLOCKED/TODO count as not done.

Per-row isolation: each detector is wrapped so an exception yields `UNKNOWN` with `detail = 'This could not be checked.'` for that row only; the page never fails on one bad detector. Blank org (zero of everything) must render with no error and no red on optional rows.

## 5. Apex contract

### 5.1 `GtmSetupChecklistController` (with sharing, NO DML, NO callouts)

```apex
public with sharing class GtmSetupChecklistController {
    @AuraEnabled(cacheable=false)
    public static SetupChecklist getChecklist();

    /** Active Standard-type users matching name/username substring, max 25, for the assign picker. */
    @AuraEnabled(cacheable=false)
    public static List<UserOption> searchAssignableUsers(String searchTerm);

    public class SetupChecklist {
        @AuraEnabled public List<SetupItem> items;
        @AuraEnabled public Integer requiredTotal;
        @AuraEnabled public Integer requiredDone;
        @AuraEnabled public Integer requiredUnknown;
        @AuraEnabled public Boolean selfApprovalEnabled;
        @AuraEnabled public String  checkedAt;      // ISO-8601 datetime string
    }
    public class SetupItem {
        @AuraEnabled public String  key;            // stable id, see catalogue
        @AuraEnabled public String  tier;           // REQUIRED|RECOMMENDED|OPTIONAL|INFO
        @AuraEnabled public String  category;       // ACCESS|SITE|CONTENT|CONFIGURATION|ORG
        @AuraEnabled public String  status;         // DONE|TODO|NOT_SET|BLOCKED|UNKNOWN|INFO
        @AuraEnabled public String  title;
        @AuraEnabled public String  why;            // exactly one plain sentence
        @AuraEnabled public String  detail;         // current state, e.g. "2 draft offerings are hidden"
        @AuraEnabled public Boolean humanMustAct;   // true if a person must act outside a one-click action
        @AuraEnabled public String  actionType;     // NONE|LINK|ASSIGN_TO_ME|ASSIGN_PICKER|SCHEDULE_JOBS|CREATE_FRAMEWORK_PAGES
        @AuraEnabled public String  actionLabel;
        @AuraEnabled public String  linkKind;       // NAV_ITEM|SETUP_PATH|NONE
        @AuraEnabled public String  navApiName;     // NAV_ITEM: tab api name
        @AuraEnabled public Map<String,String> navState;   // NAV_ITEM: c__ params
        @AuraEnabled public String  setupPath;      // SETUP_PATH: relative path starting /lightning/setup/
        @AuraEnabled public String  permissionSetName;     // for ASSIGN_* (one of the allow-list)
        @AuraEnabled public List<String> blockedBy;        // keys of unmet prerequisites; empty list, never null (plan 2.4 delta 2)
        @AuraEnabled public Boolean collapsedByDefault;    // true for OPTIONAL and INFO tiers (plan 2.4 delta 2)
    }
    public class UserOption {
        @AuraEnabled public Id     userId;
        @AuraEnabled public String name;
        @AuraEnabled public String username;   // display only; never logged or committed
    }
}
```

Rules: `getChecklist` performs only SOQL/schema/custom-setting reads. No org id, username or key ever appears in an item. `searchAssignableUsers` returns `UserType = 'Standard'`, `IsActive = true` only, so a guest/site/portal user can never be offered. Links are relative paths (`/lightning/setup/...` via `standard__webPage`, in-app via `standard__navItemPage`), so no `URL.getOrgDomainUrl()` is needed and no host is hard-coded. All Setup paths live in one private constant map so a wrong path is a one-line fix (each is UNVERIFIED until QA opens it, spike Q7).

### 5.2 `GtmSetupActionController` (with sharing, DML)

```apex
public with sharing class GtmSetupActionController {
    /** Assign one allow-listed GTM permission set. One setup-object DML per call, nothing else in the transaction. */
    @AuraEnabled
    public static AssignResult assignPermissionSet(Id userId, String permissionSetName);

    /** Convenience: same rules, target = UserInfo.getUserId(). */
    @AuraEnabled
    public static AssignResult assignPermissionSetToMe(String permissionSetName);

    /** See section 3A: creates one framework page's structure via GtmPageSectionController.createPage; idempotent. */
    @AuraEnabled
    public static FrameworkPageResult createFrameworkPage(String templateType, List<GtmPageSectionController.SectionSeed> sections);

    public class AssignResult {
        @AuraEnabled public Boolean assigned;       // false when already held (idempotent)
        @AuraEnabled public String  permissionSetName;
        @AuraEnabled public String  message;
        @AuraEnabled public Boolean fallbackToSetup; // true when the platform refused the inline action; the LWC shows setupPath instead (plan 2.4 delta 2)
        @AuraEnabled public String  setupPath;       // relative /lightning/setup/... path for the fallback link
    }
}
```

Allow-list (hard-coded `Set<String>`, matched exactly, never built from input or a query): `GTM_Offering_User`, `GTM_Content_Manager` (assignable to any active Standard user), `GTM_Offering_Admin`, `GTM_Content_Admin` (self only, i.e. `userId == UserInfo.getUserId()`; granting the admin tier to someone else is a deep link to Setup, so this section is not an admin-promotion lever). `GTM_Guest`, `Conduit_User`, every non-GTM set, and any unknown name throw `AuraHandledException` before any DML. Coordinator default 10 accepted: `GTM_Content_Manager` is in the list so content rows are not left BLOCKED; `GTM_Content_Admin` stays self-only (roles remain separable: a rep-facing admin can be given Content Manager without Content Admin).
Guards: target user must be `Standard` type and active; permission set resolved by `Name` from `PermissionSet` with `IsOwnedByProfile = false`; skip and return `assigned=false` if an assignment exists (idempotent); insert with `Database.insert(..., false)` and translate failure to a plain message (this also covers the duplicate-detection gotcha, CLAUDE.md section 6). No other DML method exists in this class. Job scheduling is NOT wrapped: the LWC calls the existing `GtmScheduledJobsController.scheduleJob(jobKey)` (idempotent, aborts then reschedules) directly, so there is one implementation. Queue members and Manager values: links only in this release.

Authorisation boundary: Apex class access granted only to `GTM_Offering_Admin` (repo convention, see `GtmAgentSettingsController` header). No in-Apex role check is added because a System Administrator who does not yet hold the set must be able to use "assign to me" (the chicken-and-egg case). No custom permission is introduced (would be new metadata; not needed).

## 6. Item catalogue (detection rule per row)

`Tier` = R required (app cannot work without it), Rec recommended (shown, does not block), O optional, I info. `Human` = a person must act outside a one-click action.

| key | Tier | Detection | Action | Human | Why (one sentence) |
|---|---|---|---|---|---|
| `admin_assigned` | R | `PermissionSetAssignment` count for `GTM_Offering_Admin` with active assignee >= 1 | ASSIGN_TO_ME if the viewer lacks it, else none | No | Someone must hold the admin permission set to configure the app. |
| `content_access` | R (BLOCKED helper for content rows) | Viewer holds `GTM_Content_Manager` or `GTM_Content_Admin` | ASSIGN_TO_ME `GTM_Content_Manager` | No | Content rows open pages that need the Content Manager permission set. |
| `reps_assigned` | Rec | count of `GTM_Offering_User` assignments >= 1 | ASSIGN_PICKER | Yes (choose who) | Reps need this permission set to use the app. |
| `guest_permset` | R | Resolve site guest user (spike Q4/Q1), then `PermissionSetAssignment` for `GTM_Guest`; unresolvable -> UNKNOWN, never DONE | LINK to site Builder guest-profile settings, or inline only if spike Q1 passes (never via the allow-list) | Yes unless spike passes | Prospects see nothing on the site until the guest permission set is on the site's guest user. |
| `site_active` | R | `Network` row for our site with `Status = 'Live'`; no Network -> BLOCKED (Digital Experiences off); site not identifiable -> UNKNOWN. Published-vs-unpublished-changes is not detectable (say so in detail) | LINK Setup > Digital Experiences > All Sites | Yes | Prospects can only reach pages on an active, published site. |
| `framework_pages` | R | Per template in offerings-page, industry-chooser, faq-bd, faq-content-manager, assistant: any `GTM_Page_Section__c` for `gtm`; DONE when all five have sections; TODO lists the missing ones; never BLOCKED by content access (the action needs only `GTM_Offering_Admin`) | CREATE_FRAMEWORK_PAGES (section 3A) | No (one click) | The framework pages (offerings page, industry chooser, help panels, assistant) have no sections until they are created, so the Content Manager cards are empty and cannot be edited. |
| `industry_added` | R | Reuse `GtmPageContentReader.getIndustryProfiles('gtm','industry-chooser')` (no copied SOQL); count entries with non-blank `industryLabel` (the reader returns only Published, active industries once add-industry lands); 0 -> TODO with detail "Add an industry, then Publish the Industry Chooser page" (a Draft just added reads TODO until Publish); entries without labels -> TODO "incomplete" | NAV_ITEM `GTM_Content_Manager` state `c__offering=gtm`, `c__template=industry-chooser` (the Industries grid created by `framework_pages`); BLOCKED if `framework_pages` is not DONE (reason: create the framework pages first) or `content_access` is not met; creation depends on the separate Add-industry piece, gap G0 (section 3A) | Yes | Prospects choose their industry on the Industry Chooser page, which stays empty until you add and publish an industry. |
| `offering_created` | R | `SELECT COUNT() FROM GTM_Page_Section__c WHERE Template_Type__c='offerings-listing' AND Section_Key__c='tile' AND Offering_Key__c != 'gtm' AND Active__c = true`; 0 is a normal blank org (TODO) | NAV_ITEM `GTM_Content_Home` | Yes | An offering is what reps sell and prospects see. |
| `offering_published` | R | Same filter with `Offering_Status__c = 'Published'` and `Archived__c != true` (mirrors `GtmPageContentReader.getOfferingTiles`). created>0 and published=0 -> TODO with "N draft offering(s) are hidden until published" | NAV_ITEM `GTM_Content_Home` | Yes | Draft offerings are hidden on purpose, so nothing shows until one is published. |
| `offering_listed` | R (coordinator decision) | Non-empty `GtmPageContentReader.getOfferingTiles()`; if published>0 but listed=0 -> TODO "published, but no site record yet" (gap G1) | SETUP_PATH custom metadata records for `GTM_Offering` | Yes | The public offerings page lists an offering only once its site record exists. |
| `triage_queue` | Rec | Queue `GTM_Readout_Triage` (`Group.Type='Queue'`) exists, else BLOCKED "queue not deployed"; member count via `GroupMember` >= 1 | LINK Setup > Queues | Yes (choose members) | A readout with no owner lands in this queue, and nobody can see it until someone is a member. |
| `manager_on_reps` | Rec, shown only while org-default `Self_Approval_Enabled__c = false`; hidden (not shown) otherwise | Users holding `GTM_Offering_User` with `ManagerId = null`: count and first 5 names in detail | LINK Setup > Users | Yes | With manager approval, a readout submitted by a rep with no manager has nowhere to go. |
| `scheduled_jobs` | Rec | `GtmScheduledJobsController.getStatuses()`, DONE when both `isScheduled` | SCHEDULE_JOBS (existing controller) | No | Old drafts and deleted records are purged on a schedule; the app works without it. |
| `site_members` | Rec | UNVERIFIED queryability of `NetworkMember`/membership; UNKNOWN if not readable | LINK site Administration > Members | Yes | Reps who open the site themselves must be members of it. |
| `offering_pages` | I | Per non-archived offering, `story`/`configurator` templates with zero sections (detail lists them) | LINK Content Manager home | Yes | An offering's story and configurator pages exist only after they are created in the Content Manager. |
| `page_offerings` | O | any active `GTM_Page_Content__c` `gtm`/`offerings-page` | NAV_ITEM | Yes | Intro copy on the front page that lists every offering. |
| `page_faq_bd` | O | `gtm`/`faq-bd` | NAV_ITEM | Yes | Reps see this help panel; without it they see no help. |
| `page_faq_cm` | O | `gtm`/`faq-content-manager` | NAV_ITEM | Yes | Content authors see this help panel; without it they see no help. |
| `page_assistant` | O | `gtm`/`assistant`; confirm built-in fallback in code before wording the why (UNVERIFIED) | NAV_ITEM | Yes | Sets the assistant's name and greeting. |
| `analytics_digest` | O | `GTM_Analytics_Settings__c.getOrgDefaults().Notify_Weekly_Digest__c` (fields verified in `GtmAnalyticsSettingsController`: digest enabled/day/hour; there is no recipient field) | NAV_ITEM `GTM_Offerings_Settings` state naming section `analytics-notifications` (UNVERIFIED that the shell reads a state param; else link is to the Settings tab and detail names the section) | Yes | Turns on the weekly analytics email digest. |
| `approval_routing` | I | Current mode text from `getOrgDefaults()`: "Manager approval" or "Self-approval"; never DONE | link to section `approval-routing` (same tab; a shell event, no navigation) | Yes (policy decision) | Decides whether a readout goes to the rep's manager or is self-approved. |
| `ai_keys` | O, neutral | `GtmAgentSettingsController.getAgentSettings()` booleans only (`hasApiKey`, `hasOpenAiApiKey`, `hasGeminiApiKey`); text "Not set: GUS chat is off, everything else works" | link to section `claude-gus` | Yes (a secret) | Enables the GUS chat assistant; nothing else depends on it. |
| `org_my_domain`, `org_digital_experiences`, `org_chatter`, `org_email_deliverability`, `site_email_verified` | I (read-only) | Best-effort read (`Network` presence implies Digital Experiences; others UNVERIFIED and default to UNKNOWN, e.g. email verification state is not exposed in SOQL) | LINK to the Setup page | Yes | Org switches this app needs but cannot change for you. |

Nothing outside this table is documented in a runbook; anything found later is added as a row.

Group headings and counts: Required = `admin_assigned`, `guest_permset`, `site_active`, `framework_pages`, `industry_added`, `offering_created`, `offering_published`, `offering_listed` (coordinator default: `offering_listed` may be demoted to Recommended if the user prefers, since it is gap G1). `content_access` is a helper: rendered inside content rows as BLOCKED reason and as its own row only when unmet; it does not count toward N of M.

## 7. LWC contract

- `gtmSetupChecklist` (new, `force-app/main/default/lwc/gtmSetupChecklist/`): calls `getChecklist` on connect and on Re-check (no `@wire` caching). Renders the groups from section 4. Actions: `LINK` -> `NavigationMixin` (`standard__navItemPage` with `state`, or `standard__webPage` with the relative `setupPath`); `ASSIGN_TO_ME` -> `assignPermissionSetToMe`; `ASSIGN_PICKER` -> `searchAssignableUsers` then `assignPermissionSet`; `SCHEDULE_JOBS` -> `GtmScheduledJobsController.scheduleJob` per unscheduled job; `CREATE_FRAMEWORK_PAGES` -> for each missing template `createFrameworkPage(t, starterFor(t))` with `starterFor` imported from `c/gtmPageLayouts` (import only; that module is not edited). After any action, re-fetch the whole checklist. Error text shown from the server message; no client-side "done" flag.
- `gtmOfferingsSettings`: add `{ id: 'setup', label: 'Setup' }` as `SECTIONS[0]`, `isSetupSelected` getter, and one `<template if:true={isSetupSelected}><c-gtm-setup-checklist>` in html. Existing Jest spec updated (section count, default selection). Sections `approval-routing` and `claude-gus` links dispatch a `selectsection` event handled by the shell (one small handler); if that is not done, those two rows fall back to plain text naming the section.
- Must not touch: `gtmPageLayouts.js` (single source of starter definitions), `chooseIndustry.*`, any Home/landing file (PR #239), `gtmContentManager`/`gtmContentHome` (deep links use their existing state params `c__offering`, `c__template`).

## 8. Docs and script (done in workstream E; PR #238 has merged)

`docs/runbooks/gtm-offerings-install.md` and `fresh-org-deploy.md` (exist only on `agent/issue-site-shell-metadata`) shrink to: prerequisites the deploy itself needs (My Domain, Digital Experiences, Chatter), authorize, deploy, then "Open GTM Offerings > Settings > Setup", plus the single fallback sentence for a first admin who cannot see the tab. Deploy-script closing message points at the same place; scripted flags behave as before. No industry list, no "type these" content anywhere. No install-time `InstallHandler` (no package exists; in-app assign-to-me covers both routes).

## 9. Spike plan (QA, gtm-staging only; do not run against gtm-dev)

Run as anonymous Apex and UI on gtm-staging, one throwaway user per question, record exact error text in section 10. Each result is yes/no plus the message.
- Q1. Can Apex assign `GTM_Guest` to the site guest user (`insert PermissionSetAssignment(AssigneeId=<guest user>, PermissionSetId=...)`)? Is `Site.GuestUserId` queryable to find that user? Is a licence-less set eligible for the Guest User License? Does it take effect without re-publish? If no: `guest_permset` is LINK + human, detection remains; status UNKNOWN if the guest user cannot be resolved. `GTM_Guest` stays off the allow-list regardless.
- Q2. Does `insert PermissionSetAssignment` from a `with sharing` `@AuraEnabled` method succeed when the running user holds `GTM_Offering_Admin` but is not a System Administrator and lacks the "Assign Permission Sets" system permission? Expected risk: setup-object DML may still require that user permission even in Apex. Decision rule: if it fails, do NOT add `AssignPermissionSets` to `GTM_Offering_Admin` (that set carries Modify All on GTM objects and the permission would allow assigning any set to anyone). Instead demote `ASSIGN_*` to LINK (Setup > Permission Sets) and keep detection; the allow-list Apex stays only if it works for the non-System-Admin case.
- Q3. Same for `GroupMember` insert to the queue (only relevant if queue-member inline is ever added; not built in this release).
- Q4. Which `Network` is ours (name/`UrlPathPrefix`, without hard-coding), what values does `Status` take (Live, UnderConstruction, DownForMaintenance), and is published-vs-draft detectable at all?
- Q5. Can the non-System-Admin `GTM_Offering_Admin` user read `PermissionSetAssignment`, `PermissionSet`, `Network`, `GroupMember`, `Group`, `User.ManagerId`, `NetworkMember`, `CronTrigger`? List which return zero silently (not an error) because that is the false-DONE hazard (a silent zero on `GTM_Guest` assignments must not read as "not done" nor as "done"; if a read cannot be distinguished from empty, the row is UNKNOWN).
- Q6. Create an offering with `createOffering`, publish it, add no `GTM_Offering__mdt`: does it appear on the public offerings page? (Confirms gap G1.)
- Q7. Open every `SETUP_PATH` in section 5.1 and record which Setup URLs resolve; and confirm `standard__navItemPage` `GTM_Content_Manager` with `c__offering=gtm`,`c__template=industry-chooser` lands on the Industry Chooser page.
- Q8. Can email-verified state be detected at all (`Network.EmailSenderAddress` populated vs verified), and does anything expose "site published"? Expected: no; rows stay UNKNOWN.

- Q9. On a blank gtm-staging: run `createFrameworkPage` for the five templates as a `GTM_Offering_Admin`-only user; confirm sections and empty field rows exist, no text values, second run is a no-op (`created=false`), and the Framework cards in Content Manager (with `GTM_Content_Manager` assigned) show editable, empty pages. Confirm no `GTM_Page_Content__c` row has a non-blank value except none.
- Q10. Do public framework pages (industry chooser, offerings page, FAQ panels, assistant) render from Draft sections/empty fields, or must sections be Published first? Record what a guest sees.
- Q12. With add-industry deployed: add an industry, confirm `industry_added` is TODO with the publish wording, Publish the Industry Chooser page, re-check, confirm DONE.
- Q11. Compare the resulting staging structure to gtm-dev's when the read-only retrieve is possible (quota-blocked now); record differences per template.

## 10. Spike results

Q1, Q2, Q4 are non-gating (section 0, delta 1): QA records observed behaviour of the runtime fallback here.

(Empty until QA runs section 9. The Developer must not implement an inline guest assignment or any inline user assignment beyond what these results permit.)

## 11. Permission-set impact (CLAUDE.md section 6)

| Set | Change |
|---|---|
| `GTM_Offering_Admin` | Add `classAccesses` for `GtmSetupChecklistController` and `GtmSetupActionController` (`GtmPageSectionController` is deliberately NOT granted; the wrapper calls it), and add the missing `GtmScheduledJobsController` (gap G2). No user permissions added. No org-wide Modify/View All. Detection reads `GTM_Page_Content__c`/`GTM_Page_Section__c` which the set already grants full CRUD/View All on. |
| `GTM_Offering_User`, `GTM_Content_Manager`, `GTM_Content_Admin`, `GTM_Guest` | None. The two new classes must not appear in any of them (test in 12). |
| New objects/fields/tabs | None, so no FLS grants. |

System-context DML is expected to work without `AssignPermissionSets` (Apex runs in system mode) but this is UNVERIFIED and is spike Q2; the fallback (LINK) is defined above so the design does not depend on it.

## 12. Test plan

Hermetic Apex: `@isTest` with no `SeeAllData`, no Migration Accelerator custom metadata, no `GTM_Offering__mdt` rows assumed, no org-specific ids. Must pass with zero offerings, zero page content, zero networks, zero users beyond the test's own. Any assertion about an org-state that a test cannot control (Network, CronTrigger already scheduled) asserts "status is one of the valid states" rather than a fixed value. Setup-object DML (`PermissionSetAssignment`) in its own `System.runAs` block, separated from non-setup DML, to avoid MIXED_DML_OPERATION.

`GtmSetupChecklistControllerTest`: blank state returns every catalogue key exactly once with valid tier/status; zero offerings -> `offering_created` TODO (not error); a Draft tile -> `offering_published` TODO with the draft count; adding a Published tile flips it and nothing else; industry rows with and without `industryLabel`; `manager_on_reps` present when the org-default `Self_Approval_Enabled__c` is false and absent when true (insert the setting row in the test); optional rows never `TODO` with tier OPTIONAL and never counted in `requiredTotal`; `ai_keys` never contains key text (insert a key, serialise the whole checklist, assert the key string is absent); one detector throwing (simulate via `@TestVisible` seam) yields UNKNOWN for that row only; `searchAssignableUsers` excludes inactive and non-Standard users.
`GtmSetupActionControllerTest`: allow-list accepts the four names within the self/other rules; `GTM_Guest`, `Conduit_User`, a made-up name, null and blank all throw with no assignment created; admin-tier set for another user throws; second assign is idempotent (`assigned=false`, one row); inactive or non-Standard target rejected; a metadata test that queries `SetupEntityAccess` (ApexClass) and asserts only the `GTM_Offering_Admin` set grants each new class (guards the class-access boundary, since `runAs` does not enforce class access); `GtmScheduledJobsController.scheduleJob` idempotency is already covered by `GtmScheduledJobsControllerTest` and is not duplicated.
Jest: `gtmSetupChecklist.test.js` (groups, counts, UNKNOWN never rendered as done, optional rows collapsed and uncounted, each `actionType`, re-fetch after action, error text shown); `gtmOfferingsSettings` spec updated.
Repo checks: `python3 scripts/check-references.py` exits 0; `grep` the diff for org ids, usernames, emails, keys.
Deployment: any Apex deploy to production-type gtm-dev triggers a full local test run, so nothing here deploys to gtm-dev. Target is gtm-staging; QA validates live in a browser there: blank org walkthrough, each row's link, the assign flow with a non-admin user for negative access, the other Settings sections, Overview empty state, and the guest questionnaire route after `guest_permset`.

## 12A. Acceptance additions (revision 2)

On a blank install (gtm-staging), no CLI and no docs: an admin holding `GTM_Offering_Admin` opens Settings > Setup, sees `framework_pages` as a required TODO listing the five missing pages, clicks the action once, and after re-detect the row is DONE. With `GTM_Content_Manager` assigned (via the assign-to-me row), the Framework cards in the Content Manager are editable and empty of content; `GTM_Page_Content__c` rows for `gtm` have no text/rich/JSON content (JSON `[]` and icontext empty-shell defaults from `createPage` excepted); clicking again creates nothing; an org that already has framework sections (gtm-dev) is left byte-for-byte unchanged and the row is DONE. Nothing is seeded by the deploy, the scripts or Setup beyond this admin-triggered structure. `industry_added` remains TODO until an industry is added AND published (via the separate Add-industry task; a Draft counts as not done) and its deep link opens the Industry Chooser page. Test additions: `createFrameworkPage` allow-list (offering templates, blank, null throw with no DML), idempotency (second call `created=false`, section count unchanged), never touches an existing page, creates no non-empty text values, hermetic and no Migration Accelerator data; Jest: the action loops only over missing templates and re-fetches.

## 13. Sequencing and conflict files

Order: (1) Add-industry, a separate task with its own contract that lands before guided-setup (it overlaps PR #240 on `gtmContentManager` files; its doc section 11 records that), (2) guided-setup. Design and this contract land now. Implement after PR #238 and PR #239 merge; PR #214, #240, compact-filters and industry-empty-state are not touched by this design.
Files this implementation would edit that other in-flight work also touches (on the branches as of this writing):
- `force-app/main/default/permissionsets/GTM_Offering_Admin.permissionset-meta.xml` (classAccesses): #238 and #239 both change it. Conflict certain unless rebased.
- `docs/architecture/adr/0010-gtm-offerings-settings-tab-is-one-tab-with-sections.md`: #239 edits it; a one-line addendum (Setup is section 0) should be added only after #239 merges. This contract does not edit ADR-0010.
- `scripts/deploy-fresh-org.sh` closing message and `docs/runbooks/gtm-offerings-install.md` / `fresh-org-deploy.md`: exist only on #238's branch and #238 rewrites the script heavily.
- `force-app/main/default/lwc/gtmOfferingsSettings/*` and its spec: unmodified by the other listed PRs on their branches; `gtmScheduledJobsSettings` is touched by #240 (not edited here).
- `force-app/main/default/lwc/chooseIndustry/*`: owned by industry-empty-state; do not edit.
