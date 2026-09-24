# TASK SCOPE — ISSUE #related-lists-not-rendering

## 1. Requirements Breakdown

- **Target Objective:** In the GTM Offerings app, the Account, Contact and Opportunity record pages must show the "Assessment Requests" and "Engagement Links" related lists (contract docs/architecture/gtm-related-lists.md). The OWNER HAS DECIDED **OPTION 1**: put the two related lists on the standard object page layouts in metadata, and correct the contract doc. This scope is the decided fix; no design fork remains except the open questions in the last subsection.
- **System Component Impacted:** Metadata only. Standard-object page layouts (Account, Contact, Opportunity), the three GTM FlexiPages (GTM_Account/Contact/Opportunity_Record_Page), docs/architecture/gtm-related-lists.md, the guided-setup row spec `related-lists-standard-objects` (doc note only). No LWC, Apex, YAML or custom metadata.

### Confirmed root cause (live browser, gtm-staging, GTM Offerings app; owner-supplied, taken as ground truth)

The GTM_Account_Record_Page IS the active page. Its two `force:relatedListSingleContainer` cards (GTM_Assessment_Requests__r, the Engagement Links list) render the message "This related list cannot be displayed because it is not in the current page layout." Salesforce hides a related-list card unless that list is on the object's page layout. The earlier hypotheses H1-H4 in the previous version of this scope are closed. The contract doc sections 4 and 5 were wrong to assume the cards show without a layout entry and that adding them to the layout later would create duplicates.

### 1.1 Which layouts get the lists

Layouts are assigned per profile (and record type), so the rule is "every layout that a GTM user's profile is assigned for that object".

Read-only evidence gathered by this BA (Tooling API queries, structure only, explicit `-o`):

- **gtm-prod** has only the stock layouts: Account Layout, Account (Marketing/Sales/Support) Layout; Contact Layout, Contact (Marketing/Sales/Support) Layout; Opportunity Layout, Opportunity (Marketing/Sales/Support) Layout. No SDO layouts.
- **gtm-prod GTM users** (PermissionSetAssignment for GTM_* sets): profiles System Administrator (GTM_Offering_User x3, GTM_Offering_Admin x4, content sets x2), Standard Platform User (GTM_Offering_User x1, GTM_Content_Manager x1). Guest-set holders are not app users. ProfileLayout for both System Administrator and Standard Platform User maps Account, Contact and Opportunity to the plain "Account Layout", "Contact Layout" and "Opportunity Layout" (no record-type-specific layouts seen in the query). So on prod ONE layout per object matters: Account Layout, Contact Layout, Opportunity Layout.
- **gtm-staging** System Administrator uses SDO layouts: Account: "SDO - Account", "Account Layout", "SDO - Account Community" (and the owner also saw "SDO - Partner Account"); Contact: "SDO - Contact", "SDO - Partner Contact"; Opportunity: "Opportunity Layout" and "SDO - Opportunity". (Profile-to-layout mapping for staging's other GTM profile holders was not resolved: the profile-grouped permission set query failed on staging. Architect must re-run it, e.g. via `User` -> `ProfileId` joins, before finalising the staging list.)
- **Source** has only four Opportunity layouts (Opportunity Layout, plus Marketing, Sales, Support) and no Account or Contact layouts. Those four already carry a documented production guard in scripts/deploy.sh (lines ~121-135): deploy.sh SKIPS every `Opportunity-*` layout for prod aliases, because the repo copies had five foreign fields stripped (MainCompetitors__c and friends) and would overwrite prod's live layouts.

**Decision for the Architect (recommended, confirm in step 1):**
- Add lists to the layouts actually assigned to GTM users' profiles in EACH target org, not to every layout of the object. Minimum set:
  - Prod (the only one that matters for the real product): Account Layout, Contact Layout, Opportunity Layout.
  - Staging (to verify Option 1 with the owner's browser test): "SDO - Account", "Account Layout", "SDO - Account Community" (and "SDO - Partner Account" since the owner listed it), "SDO - Contact", "SDO - Partner Contact", "Opportunity Layout", "SDO - Opportunity", plus any others the staging GTM profiles resolve to. These staging-only SDO layouts must NEVER enter the repo or reach prod (see 1.2).
- The four source Opportunity layouts are the repo's Opportunity layouts; the two lists would be added to "Opportunity Layout" (and, optionally, the other three) subject to the prod guard.

### 1.2 CRITICAL PROD RISK and safe approach

A layout deploy REPLACES the whole layout in the target org (sections, fields, buttons, related lists, quick actions). Layouts retrieved from gtm-staging (an SDO demo org with SDO fields, components and quick actions) must NOT be deployed to gtm-prod: that would push demo fields/actions onto live prospect pages, drop prod's own fields, and could fail or partially break because SDO fields do not exist there. The existing repo Opportunity copies are already known-unsafe for prod for the same reason.

Recommended approach (BA recommendation; Architect to confirm, owner approves anything touching prod):

1. **Repo carries NO full standard layouts for Account/Contact, and does not gain new full standard layouts.** Prefer not to commit whole standard layouts to the repo at all. Options ranked:
   a. (Recommended) A **prod-safe patch procedure**, not a deployable artifact: a small script or runbook step (`scripts/` or docs/runbooks/gtm-offerings-install.md "Production guard" section) that (i) retrieves the TARGET org's own layout, (ii) inserts only the two `<relatedLists>` blocks defined below, (iii) prints a `diff` against the retrieved original that must show ONLY those two additions, (iv) runs a validate-only deploy (`sf project deploy validate` / `--dry-run` with explicit `-o`), and only then (v) a real deploy on the owner's explicit go-ahead. The script must refuse to run if the diff contains anything other than the two blocks.
   b. Commit only the two blocks as a snippet/fragment file (non-deployable path, e.g. docs or reference) for the patch script to apply.
   c. Committing full layouts is acceptable ONLY for GTM-owned objects (already the case) and, as today, the four Opportunity layouts under the existing prod guard. Do not extend that pattern to Account/Contact.
2. **deploy.sh guard**: the existing guard skips only `Opportunity-*` on prod aliases. If any new Account/Contact layout files were ever added to force-app, the guard would NOT skip them. Requirement: either no such files are added to force-app (approach 1a) or the guard is widened to `Account-*`, `Contact-*`, `Opportunity-*` for prod aliases. The Architect must pick one; the guard change is required if any full standard layout enters force-app.
3. For **staging only**, retrieve the SDO layouts to a scratchpad (`sf project retrieve start -o gtm-staging -m Layout:...`), add the two blocks, validate-only then deploy on staging for the browser test. Do not commit them.
4. **Prod read-only checks already done** (above): layouts exist, GTM users' profiles use the stock "<Object> Layout". Before any prod patch, re-retrieve prod's Account Layout, Contact Layout and Opportunity Layout fresh (they may drift), and confirm the repo's Opportunity Layout is NOT what gets deployed (deploy.sh already skips it on prod).
5. Real deploy to gtm-prod only after the owner's explicit go-ahead. Agents run validate-only against gtm-staging (and prod validate-only only if the owner authorises that separately). `sf community publish` is not relevant (no experiences touched).

### 1.3 Related-list API names, lookup names, columns

Layout `<relatedList>` syntax is `<ChildObject>.<LookupField>` (verify by retrieving an existing GTM layout; the repo's GTM_Assessment_Request__c layout shows the same element pattern). From contract section 3 (source of truth for lookups):

| Parent layout | Related list (layout value) | Notes |
|---|---|---|
| Account | `GTM_Assessment_Request__c.Account__c` | AR |
| Account | `GTM_Saved_Configuration__c.Account__c` | Engagement Links (relationshipName GTM_Engagement_Links) |
| Contact | `GTM_Assessment_Request__c.Contact__c` | AR |
| Contact | `GTM_Saved_Configuration__c.Contact__c` | Engagement Links |
| Opportunity | `GTM_Assessment_Request__c.Opportunity__c` | AR |
| Opportunity | `GTM_Saved_Configuration__c.Opportunity__c` | Engagement Links. Its relationshipName is the inconsistent `GTM_Saved_Configurations` (NOT renamed); the layout value still uses the lookup FIELD, so it is not affected, but any FlexiPage card must use `GTM_Saved_Configurations__r`. |

Person Accounts are enabled on staging: the Contact lookups appear as `__pr` on Account. Layout entries use the lookup field, so they are unaffected; person-account contacts are not aggregated (already documented).

Columns now come from the layout `<fields>` (an improvement over the FlexiPage cards, which had no column control). Use the contract's target columns: AR = `NAME`, `Status__c`, `Assessment_Tier__c`, `Assessment_Score__c`, `Submitted_At__c`; SC = `NAME`, `Offering__c`, `Presentation_Stage__c`, `Active__c`. Each must be a real field (verify with check-references.py and a dry-run). Set `<sortField>`/`<sortOrder>` only if the Architect wants newest-first; otherwise omit.

### 1.4 Permissions (five permission sets rule)

- No new fields or objects, so no new grants for the fields themselves. Already verified in the contract (section 7) and re-confirmed: GTM_Offering_User and GTM_Offering_Admin carry object CRUD and field grants on AR (Account__c, Contact__c, Opportunity__c ...) and SC lookups. A related list on a layout only shows columns the user can read and rows they can access.
- The Architect must verify each column field added in 1.3 has a `fieldPermissions` entry in GTM_Offering_User and GTM_Offering_Admin (required fields such as SC.Offering__c are implicit and take no entry; an explicit entry on a required field fails deploy). GTM_Content_Manager / GTM_Content_Admin and GTM_Guest do NOT get these (page/section content only; guests never see these pages).
- Users lacking GTM_Offering_User will see the layout related list disappear silently (no object access): expected, not a defect.
- Sharing caveat unchanged (contract section 8): AR/SC are Private, so a non-owner rep sees empty lists on a shared Account.
- Layout deploy does not require the permission sets to change, but Definition of Done still requires the Architect to state this check explicitly in the contract.

### 1.5 Duplicate risk on the GTM record page's Related tab

The GTM FlexiPages have, on the Related tab, the two explicit `relatedListSingleContainer` cards followed by `force:relatedListContainer` (the layout-driven container: it renders every related list on the assigned layout). Once the two lists are on the layout, they WILL appear in the container as well as in the two cards, i.e. **twice**. The old contract statement that this "would duplicate" was true for the future, but the cards themselves were never going to show without the layout entry, so the cards are now redundant.

Required approach: **remove the two explicit `force:relatedListSingleContainer` cards from each of the three GTM FlexiPages (Account, Contact, Opportunity)** and let the layout-driven `relatedListContainer` render the lists (this also gives column control via the layout and removes the property mismatch on the Opportunity `GTM_Saved_Configurations__r` name). If the Architect prefers to keep the explicit cards for ordering (at the top of the Related tab), the alternative is to keep them and remove the two lists from the container, which is not possible for a layout-driven container, so removal of the cards is the recommended path. The Architect must confirm the exact rendering in the browser (lists appear once, GTM lists ordered acceptably relative to standard lists; list order on the layout is controlled by the `<relatedLists>` order, so place the two new blocks near the top of the layout's related lists).
Downside recorded for the contract: outside the GTM Offerings app (standard page for the same profile) the same layout also shows the lists, so "other apps unaffected" only holds for page assignment, not for layout content. Reps in other apps will see the two extra related lists on Account/Contact/Opportunity. Owner should accept this consequence (see open questions).

### 1.6 Docs to correct

docs/architecture/gtm-related-lists.md:
- Section 4: remove "The Opportunity layouts and all standard-object layouts are deliberately NOT modified (packaging)"; state that columns for the standard-object lists come from the layout `<fields>`, and give the target columns in 1.3.
- Section 5: remove the "NOT in the package: any override of standard-object layouts" and the "they will appear twice" assumptions; record the real behaviour (a `relatedListSingleContainer` card is hidden with the message "This related list cannot be displayed because it is not in the current page layout." unless the list is on the assigned layout), that the lists live on the layout, that the FlexiPage no longer carries the explicit cards, and the **packaging tradeoff**: adding lists to a subscriber's standard layout is a shared-resource change (replaces the layout on deploy, affects all apps/profiles using that layout), so it is delivered by the prod-safe patch procedure (1.2), not by shipping full standard layouts in the package. State the UNVERIFIED items honestly (no Salesforce doc fetched).
- Section 6: update "Remaining admin step: none" to say the layout patch is a required per-org step.
- Section 9: update the guided-setup row: the detect/act text must check that the assigned layout of each object contains the two related lists (Tooling API: Layout metadata `relatedLists`) rather than checking for FlexiPage cards; act = the prod-safe patch or LINK to the object's page layout editor (`/lightning/setup/ObjectManager/<Object>/PageLayouts/view`). The row key `related-lists-standard-objects` is unchanged. Guided-setup code is owned by another branch: this issue updates the doc only and notes the row change; no code.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO. Zero-DML rule in AGENTS.md §1 is unaffected.
- [ ] Altering Custom Metadata? NO (GTM_Assessment_* untouched). Layout and FlexiPage XML only. No migration-accelerator/ YAML change.
- [ ] Introducing database fields? NO new fields. Permission Set mapping is still checked (1.4): column fields must have grants in GTM_Offering_User and GTM_Offering_Admin; no new grants expected.

## 3. Plan Acceptance Criteria

- **Success Metric:** On gtm-staging only (never gtm-prod), hard refresh, opened via the GTM Offerings app tabs, after the layout patch and FlexiPage cleanup are deployed to staging:
  1. The owner-named test Account: Related tab shows "Assessment Requests (2)" and "Engagement Links (3)", each exactly ONCE, plus the standard lists, and no "cannot be displayed" message anywhere.
  2. A Contact of that account: both lists render with correct counts for that contact, once each.
  3. The owner-named test Opportunity: both lists render (Engagement Links via the Opportunity lookup), once each.
  4. Other apps (Sales, Service Console, GTM Content Manager): pages still assign as before (no page-assignment leakage). The lists appearing on the shared layout in those apps is the known consequence noted in 1.5 and must be reported, not treated as a failure.
  5. `python3 scripts/check-references.py` reports 0 deploy-blocking findings (FlexiPage card removal and any layout related-list references must resolve).
  6. Validate-only deploy (`--dry-run` / `sf project deploy validate`, explicit `-o gtm-staging`) passes for the changed FlexiPages and staging layouts. No real deploy without the owner's explicit go-ahead; prod is patched only via 1.2 with the diff showing just the two blocks per layout, validate-only first.
  7. Confirm no full standard layout retrieved from staging is present in the diff/commit, and deploy.sh guard state (1.2 item 2) is consistent with what was added to force-app.
  8. docs/architecture/gtm-related-lists.md corrected per 1.6; guided-setup row `related-lists-standard-objects` updated in the doc (section 9) or explicitly noted as pending the guided-setup branch.
- **Target Test Target:** No Apex class or LWC Jest spec applies (metadata-only). Run `npm test` as a regression guard, `python3 scripts/check-references.py`, the validate-only staging deploy, and the live browser pass above (QA must check every dependent surface, not only the changed one: Account, Contact, Opportunity, and the SC/AR pages).

### Open questions (not in scope, do not implement)

1. **Owner add-on (OPEN QUESTION ONLY, NOT IN SCOPE):** a rep jump from a Pages row to that link's assessment (i.e. from a row in the Pages list, open the assessment for that engagement link). Not scoped; needs a separate issue and a UX trace of the rep's click path (which record/route it opens, and behaviour when the link has zero or several Assessment Requests).
2. Owner to accept that the lists will appear on the shared layout for reps using other apps (see 1.5). If not acceptable, the alternative is a dedicated layout per profile assignment, which is heavier and touches profile layout assignments (a design fork for the owner).
3. Staging profile-to-layout mapping for all GTM users needs a re-run by the Architect (BA query failed on that grouping).
