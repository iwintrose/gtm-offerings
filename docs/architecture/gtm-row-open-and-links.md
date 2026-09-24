# GTM row open button and link targets (Assessments and Pages tables)

Status: implemented on branch `agent/issue-assessments-row-open`. LWC only; no Apex, schema or permission change.

## Decisions

1. **Pattern matched to Pages.** The Pages table (`gtmRepLinkTableModel.buildColumns`) ends with a native `type: 'action'` column (row-action menu at the far right, standard datatable density). The Assessments table now does the same: `TABLE_COLUMNS = [...COLUMNS, OFFERING_COLUMN, ACTION_COLUMN]`. The `COLUMNS` export (used by gtmOverview's results card for tier/score/status only) keeps its first columns; the trailing action column is only in `TABLE_COLUMNS`.
2. **Menu, because Pages uses a menu.** Items: Open assessment, Open contact, Open account. Items without an id are disabled and say why in the label (native menu items have no tooltip). "Open readout" is deliberately not a separate item: the readout is reviewed, approved and sent inside the readout workspace that "Open assessment" already opens (request id + latest readout id + offering key), so a second item would land on the same screen.
3. **Open is unchanged behaviour.** Menu item `open` and the AR-#### cell both fire action `open`, handled by `GtmReadoutsOverview.handleRowAction`, which renders `gtmReadoutWorkspace` inline and writes `c__assessmentRequestId/c__readoutId/c__offeringKey` to the URL.
4. **Links are NavigationMixin, not hrefs.** Contact and Company were `type: 'url'` cells with hand-built `/lightning/r/...` hrefs (full page loads outside the Lightning router, and they fell back to a different record when the id was missing). They are now `type: 'button'` (variant base) cells named `openContact` / `openAccount` that call `NavigationMixin.Navigate({type:'standard__recordPage', attributes:{recordId, objectApiName, actionName:'view'}})`. If the id is missing the cell is disabled (title explains) and the handler does nothing: no link to a substitute record.
5. **Pages Contact** was plain text; it is now the same Contact button (`openContact`, `GtmRepLinkFinder.openContactRecord`). Pages Company already opens the in-app link detail view (the existing convention) and stays; its Open menu item is unchanged.
6. **Rep scope.** Every row comes from owner-scoped Apex (`getAssessmentPage`, `getMyConfigurations`); the new navigation only uses ids on those rows. Nothing new exposes other reps' records.
7. **Apex:** no change. `AssessmentRow` already has `recordId, contactId, accountId, readoutId`; `getMyConfigurations` output already has `Account__c, Contact__c`.
8. **Density:** the action column and buttons are the native datatable controls, which follow the table's own row height; no custom CSS added.

## Audit table

Rep job-to-be-done: what the rep does next, in the fewest clicks.

### Assessments table

| Column | Before | After | Rep job-to-be-done |
|---|---|---|---|
| Assessment (AR-####) | button `open` -> inline workspace | unchanged | Review, approve and send the readout |
| Contact | `url` cell, href `/lightning/r/Contact/<contactId>`; with no contact fell back to the Account, then to the assessment request record (wrong record under a Contact label) | button `openContact` -> `standard__recordPage` Contact `<contactId>`; disabled when no contactId | See who they are before reaching out |
| Company | `url` cell, href Account, fell back to the request record | button `openAccount` -> `standard__recordPage` Account `<accountId>`; disabled when no accountId | Account context for the deal |
| Readiness tier, Score, Request status, Readout (status text), Submitted, Offering | text/number/date, not links | unchanged (not links; readout id is not shown as a link, the workspace is reached through Open assessment) | Prioritise |
| (new) trailing row menu | none | Open assessment (`open`), Open contact (`openContact`), Open account (`openAccount`) | One-click open from the far right of the row |

### Pages table (issue-pages-columns-links)

| Column | Before | After | Rep job-to-be-done |
|---|---|---|---|
| Page (new, FIRST) | none | button `open`, label = `GTM_Saved_Configuration__c.Name` (AutoNumber `SC-{0000}`, from `getMyConfigurations`, never blank), -> in-app link detail (`openLinkRow`); disabled with reason when no account (the detail restore needs the account) | Jump into a page's detail from its number |
| Account / company | first column, button `open` -> in-app detail | button `openAccount` -> `standard__recordPage` Account `<Account__c>` (view); disabled + title when no account | Account context |
| Contact | button `openContact` -> Contact record | unchanged; disabled when no contact | Contact context |
| Offering, Opportunity, Funnel stage, Visits, Last visit, Status, Saved, Owner, Industry, Deal stage | text/number/date | unchanged | Read status |
| Row menu (far right) | Open, Copy link, New password, Turn on/off | unchanged | Share or manage the page |

Proposed default-visible set (<= 5): Page, Account, Contact, Funnel stage, Last visit (`DEFAULT_VISIBLE_FIELDS` in `gtmRepLinkTableModel.js`). The rest belong in the column chooser list. `docs/architecture/gtm-column-chooser.md` and a chooser component do not exist on this branch, so all columns still render; applying the default set is deferred until the chooser lands.

Name can never be blank: it is an AutoNumber name field. No Apex change (`Name`, `Account__c`, `Contact__c` already selected).

There is no Link/URL or Readout link cell on Pages; the generated URL is only used by Copy link.

## Tests

- `gtmReadoutsOverview.test.js` "row open and record links": action column is last with Open assessment / Open contact / Open account (disabled with no ids); menu Open opens the workspace; Contact navigates to Contact with the contact id; Company to Account with the account id; missing ids do not navigate.
- `gtmAssessmentsTableModel.test.js` / `.vocabulary.test.js`: mapRow carries ids and disabled flags; trailing action column.
- `gtmRepLinkFinder.contactLink.test.js`: Pages Contact and Account columns (type/name, disabled state, Navigate payloads), SC column first and opens detail, default set <= 5.

## References

Salesforce docs (NavigationMixin standard__recordPage; lightning-datatable types url, button, action, row-actions) cited from knowledge:
- https://developer.salesforce.com/docs/platform/lwc/guide/reference-navigation.html
- https://developer.salesforce.com/docs/component-library/bundle/lightning-datatable/documentation

Both pages are client-rendered and were NOT fetched in this session (no browser/WebFetch was used; treat as unverified against the live docs, and no 403 was observed because no request was made).

---

# Engagement-link and assessment links always open the working view (issue-sc-links-to-pages)

Rule: an SC (GTM_Saved_Configuration__c) link opens the Pages view (GTM_Pages tab, link detail). An AR (GTM_Assessment_Request__c) opens the Assessments readout workspace. A readout (GTM_Readout__c) only exists inside an assessment, so it opens its parent AR workspace with the readout focused. Never a bare record page.

## Readout rule

A GTM_Readout__c cannot exist until an assessment is SUBMITTED (by the recipient, or by the rep on their behalf); a readout is part of an assessment for an offering. So there is no standalone readout page: `openReadout(host, readoutId, arId, offeringKey)` navigates to `GTM_Assessments` with `c__assessmentRequestId` + `c__readoutId` + `c__offeringKey`, which gtmReadoutsOverview already renders as the workspace. A readout with no known parent AR does nothing (it cannot occur in practice; `ReadoutSummary.assessmentRequestId` is always returned).

## Shared helper: `c/gtmNavigate` (new module, JS only)

| Function | Target |
|---|---|
| `openEngagementLink(host, cfgId, accountId, contactId)` | GTM_Pages. With account AND contact: `c__rlfLinkId, c__rlfAccountId, c__rlfContactId, cfgId` (drill-in deep link). Otherwise: `c__template=link, c__recordId, cfgId` (opens by link id alone; gtmPageBrowser passes it to gtmRepLinkFinder `targetRecordId`). |
| `openAssessment(host, arId, readoutId?, offeringKey?)` | GTM_Assessments, `c__assessmentRequestId` (+ `c__readoutId`, `c__offeringKey`) |
| `openReadout(host, readoutId, arId, offeringKey?)` | as openAssessment with the readout focused |
| `engagementLinkRef`, `assessmentRef` | pure page-reference builders |

`host` is the calling NavigationMixin component (Navigate is a host method), so the requested signature has the host as first argument.

Account-less links: the drill-in restore reads `getContactsWithLinks`, which returns only links with a contact, so it cannot open a link with no account or no contact. No Apex change was needed: the helper falls back to the `c__template=link` path, and gtmRepLinkFinder's Pages table row action now opens such rows by link id (`openDisabled` is now always false; before, no-account rows were disabled).

## Audit table (every path that could reach an SC / AR / readout record page)

| Surface | Before | After |
|---|---|---|
| gtmOverview deals table, SC row click | Pages via `c__template=link` (already in-app), account-less unsupported by drill | `openEngagementLink` (rlf drill-in when account+contact, else by link id) |
| gtmOverview deals table, AR click | GTM_Assessments `c__assessmentRequestId` | `openAssessment` |
| gtmOverview Assessments card row `open` | GTM_Assessments `c__assessmentRequestId` only | `openAssessment` (adds readout + offering) |
| gtmOverview deal object fields `linkUrl`, `requestUrl` | built `/lightning/r/GTM_Saved_Configuration__c` and `/lightning/r/GTM_Assessment_Request__c` URLs, unused by the template | removed |
| gtmAssessmentDetail (AR record page) Engagement Link tile | `<a href=/lightning/r/GTM_Saved_Configuration__c/id/view>` (SC record page) | click handler -> `openEngagementLink` (Pages) |
| gtmStageActions "View assessment" | `<a href=/lightning/r/GTM_Assessment_Request__c/id/view target=_blank>` | button -> `openAssessment` |
| gtmAssessmentSubmissionView Name link and row action | `/lightning/r/GTM_Readout__c/id/view` record page | button cell + `openReadout` (parent AR workspace, readout focused) |
| gtmSavedLinksBar SC number (Experience site, rep-facing) | `<org>/lightning/r/GTM_Saved_Configuration__c/id/view` | `<org>/lightning/n/GTM_Pages?c__template=link&c__recordId=id` (URL form, unverified in browser) |
| Opportunity `Engagement_Link_Info__c` (formula HYPERLINK) | `"/" & Engagement_Link__c` (SC record page) | `/lightning/n/GTM_Pages?c__template=link&c__recordId=` & id (URL form, unverified in browser) |
| gtmRepLinkFinder Pages table SC / Open | in-app detail, but disabled when no account; account-without-contact failed with "could not be opened" | opens by link id for those rows; unchanged otherwise |
| gtmReadoutsOverview AR cell / Open assessment | inline workspace | unchanged (already correct) |
| gtmReadoutsOverview / gtmRepLinkFinder Account and Contact cells | Account/Contact record pages | unchanged (deliberate, not SC/AR) |
| gtmConfigurator "View in Salesforce" (Account/Opportunity/Contact only) | Account/Opportunity/Contact record pages | unchanged (no SC target) |
| gtmLinkActivity, SC record page (`GTM_Saved_Configuration_Record_Page` flexipage) | hosts admin/debug components on the SC record page | unchanged, admins keep it via the Content Manager app, see "Still on the record page" |
| GUS agent (gtmGusUtility `handleAgentAction`, GtmAgent* Apex) | navigates only to tab apiName + state; no Apex-built record URLs (grep found none) | unchanged |
| Home pages (GTM_Offerings_Home / GTM_Content_Home) | components only; no SC/AR record links (grep) | unchanged |
| Flow GTM_Config_Send_To_Client, Apex emails / Tasks | only the prospect Generated_URL (sharedUrl); no record-page URLs (grep of classes/flows) | unchanged |
| Opportunity layout `Engagement_Link__c` lookup click, global search, list views, related lists, Opportunity Related List | standard SC record page | fixed by the app-level View override (GTM Offerings app only), see "Still on the record page" |

## Still on the record page: app-level View override (implemented)

Decision (user): inside the GTM Offerings app only, View on GTM_Saved_Configuration__c and GTM_Assessment_Request__c is overridden so clicks anywhere (Opportunity `Engagement_Link__c` lookup, global search, list views, related lists) land in the working views.

Findings (verified by dry-run against gtm-staging):
- App-level `actionOverrides` in `GTM_Offerings.app-meta.xml` MUST be `type` Flexipage. A LightningComponent (Aura `lightning:actionOverride`) override failed validation: "Action overrides for Lightning apps must be of type Flexipage." (deploy id 0AfgK00000TxrvgSAB). So the Aura approach was abandoned; no Aura bundle exists.
- A Flexipage override needs a RecordPage flexipage. Two minimal pages host one LWC:
  - `GTM_SC_View_Redirect` (sobjectType GTM_Saved_Configuration__c)
  - `GTM_AR_View_Redirect` (sobjectType GTM_Assessment_Request__c)
  - both contain only `c-gtm-record-view-redirect`.
- `gtmRecordViewRedirect` (LWC): `getRecord` (Id only) proves the record is accessible; then `NavigationMixin.Navigate(ref, true)` (replace, so Back does not bounce). SC -> `standard__navItemPage` GTM_Pages, state `c__template=link`, `c__recordId`, `cfgId` (same as `engagementLinkRef`). AR -> GTM_Assessments, `c__assessmentRequestId`. It shows a spinner while loading (not a blank page) and a warning alert if the record is not accessible or deleted (no redirect). Unknown object: never redirects. Loop guard: destination is a tab page, not a record view, plus a one-shot `_done` flag.
- Only the GTM Offerings app is affected. Content Manager app, Setup, and any non-app context keep the standard SC/AR record page. Standard page: `GTM_Saved_Configuration_Record_Page` still hosts gtmRepDirectShare, gtmLinkSitemap, gtmLinkActivity.

How admins reach the standard record page: open the Content Manager app (or any app without the override, e.g. via the App Launcher), then open the record by URL `/lightning/r/GTM_Saved_Configuration__c/<id>/view` or via the tab in that app. There is no URL parameter that bypasses an app override inside the GTM Offerings app, so no in-app "Admin view" button was added. Caveat: the Content Manager app may not surface the SC tab; if not, add the GTM_Saved_Configuration__c tab to it (follow-up, not done).

Docs consulted (knowledge only; fetch not available this session, UNVERIFIED except where marked by the deploy result above):
- https://developer.salesforce.com/docs/atlas.en-us.lightning.meta/lightning/components_config_for_actions_override.htm
- https://developer.salesforce.com/docs/atlas.en-us.api_meta.meta/api_meta/meta_customapplication.htm (actionOverrides)
- https://developer.salesforce.com/docs/platform/lwc/guide/reference-navigation.html (Navigate replace argument)

Manual check (no Jest for the flexipage/app behaviour; Jest covers the LWC): in the GTM Offerings app, on staging, click an Opportunity's Engagement Link lookup, an SC from global search and from the GTM_Saved_Configuration__c list view: each opens GTM_Pages on that link with a brief spinner; Back returns to the origin, not the record page. Same for an AR: opens Assessments. In the Content Manager app the same click still shows the record page. Open a record the rep cannot see: warning message, no redirect.

Merge note: the branch agent/issue-related-lists also edits `GTM_Offerings.app-meta.xml` (adds View overrides for Account/Contact/Opportunity in the same place). Our block is delimited by `BEGIN/END issue-sc-links-to-pages view overrides` comments. On conflict keep both blocks (different pageOrSobjectType values) and both sets of `actionOverrides`, all before `<brand>`.

Rollback: remove the marked `actionOverrides` block from `GTM_Offerings.app-meta.xml` and redeploy it (and `sf project deploy` the destructive removal of the two flexipages and the `gtmRecordViewRedirect` bundle if desired; they are inert once unreferenced). Reverting the commit does the same. The override is a metadata assignment only, no data change.

## Tests

- `gtmReadoutsOverview.test.js` "row open and record links": action column is last with Open assessment / Open contact / Open account (disabled with no ids); menu Open opens the workspace; Contact navigates to Contact with the contact id; Company to Account with the account id; missing ids do not navigate.
- `gtmAssessmentsTableModel.test.js` / `.vocabulary.test.js`: mapRow carries ids and disabled flags; trailing action column.
- `gtmRepLinkFinder.contactLink.test.js`: Pages Contact and Account columns (type/name, disabled state, Navigate payloads), SC column first and opens detail, default set <= 5.

## References

Salesforce docs (NavigationMixin standard__recordPage; lightning-datatable types url, button, action, row-actions) cited from knowledge:
- https://developer.salesforce.com/docs/platform/lwc/guide/reference-navigation.html
- https://developer.salesforce.com/docs/component-library/bundle/lightning-datatable/documentation

Both pages are client-rendered and were NOT fetched in this session (no browser/WebFetch was used; treat as unverified against the live docs, and no 403 was observed because no request was made).

---

# Engagement-link and assessment links always open the working view (issue-sc-links-to-pages)

Rule: an SC (GTM_Saved_Configuration__c) link opens the Pages view (GTM_Pages tab, link detail). An AR (GTM_Assessment_Request__c) opens the Assessments readout workspace. A readout (GTM_Readout__c) only exists inside an assessment, so it opens its parent AR workspace with the readout focused. Never a bare record page.

## Readout rule

A GTM_Readout__c cannot exist until an assessment is SUBMITTED (by the recipient, or by the rep on their behalf); a readout is part of an assessment for an offering. So there is no standalone readout page: `openReadout(host, readoutId, arId, offeringKey)` navigates to `GTM_Assessments` with `c__assessmentRequestId` + `c__readoutId` + `c__offeringKey`, which gtmReadoutsOverview already renders as the workspace. A readout with no known parent AR does nothing (it cannot occur in practice; `ReadoutSummary.assessmentRequestId` is always returned).

## Shared helper: `c/gtmNavigate` (new module, JS only)

| Function | Target |
|---|---|
| `openEngagementLink(host, cfgId, accountId, contactId)` | GTM_Pages. With account AND contact: `c__rlfLinkId, c__rlfAccountId, c__rlfContactId, cfgId` (drill-in deep link). Otherwise: `c__template=link, c__recordId, cfgId` (opens by link id alone; gtmPageBrowser passes it to gtmRepLinkFinder `targetRecordId`). |
| `openAssessment(host, arId, readoutId?, offeringKey?)` | GTM_Assessments, `c__assessmentRequestId` (+ `c__readoutId`, `c__offeringKey`) |
| `openReadout(host, readoutId, arId, offeringKey?)` | as openAssessment with the readout focused |
| `engagementLinkRef`, `assessmentRef` | pure page-reference builders |

`host` is the calling NavigationMixin component (Navigate is a host method), so the requested signature has the host as first argument.

Account-less links: the drill-in restore reads `getContactsWithLinks`, which returns only links with a contact, so it cannot open a link with no account or no contact. No Apex change was needed: the helper falls back to the `c__template=link` path, and gtmRepLinkFinder's Pages table row action now opens such rows by link id (`openDisabled` is now always false; before, no-account rows were disabled).

## Audit table (every path that could reach an SC / AR / readout record page)

| Surface | Before | After |
|---|---|---|
| gtmOverview deals table, SC row click | Pages via `c__template=link` (already in-app), account-less unsupported by drill | `openEngagementLink` (rlf drill-in when account+contact, else by link id) |
| gtmOverview deals table, AR click | GTM_Assessments `c__assessmentRequestId` | `openAssessment` |
| gtmOverview Assessments card row `open` | GTM_Assessments `c__assessmentRequestId` only | `openAssessment` (adds readout + offering) |
| gtmOverview deal object fields `linkUrl`, `requestUrl` | built `/lightning/r/GTM_Saved_Configuration__c` and `/lightning/r/GTM_Assessment_Request__c` URLs, unused by the template | removed |
| gtmAssessmentDetail (AR record page) Engagement Link tile | `<a href=/lightning/r/GTM_Saved_Configuration__c/id/view>` (SC record page) | click handler -> `openEngagementLink` (Pages) |
| gtmStageActions "View assessment" | `<a href=/lightning/r/GTM_Assessment_Request__c/id/view target=_blank>` | button -> `openAssessment` |
| gtmAssessmentSubmissionView Name link and row action | `/lightning/r/GTM_Readout__c/id/view` record page | button cell + `openReadout` (parent AR workspace, readout focused) |
| gtmSavedLinksBar SC number (Experience site, rep-facing) | `<org>/lightning/r/GTM_Saved_Configuration__c/id/view` | `<org>/lightning/n/GTM_Pages?c__template=link&c__recordId=id` (URL form, unverified in browser) |
| Opportunity `Engagement_Link_Info__c` (formula HYPERLINK) | `"/" & Engagement_Link__c` (SC record page) | `/lightning/n/GTM_Pages?c__template=link&c__recordId=` & id (URL form, unverified in browser) |
| gtmRepLinkFinder Pages table SC / Open | in-app detail, but disabled when no account; account-without-contact failed with "could not be opened" | opens by link id for those rows; unchanged otherwise |
| gtmReadoutsOverview AR cell / Open assessment | inline workspace | unchanged (already correct) |
| gtmReadoutsOverview / gtmRepLinkFinder Account and Contact cells | Account/Contact record pages | unchanged (deliberate, not SC/AR) |
| gtmConfigurator "View in Salesforce" (Account/Opportunity/Contact only) | Account/Opportunity/Contact record pages | unchanged (no SC target) |
| gtmLinkActivity, SC record page (`GTM_Saved_Configuration_Record_Page` flexipage) | hosts admin/debug components on the SC record page | unchanged, admins keep it via the Content Manager app, see "Still on the record page" |
| GUS agent (gtmGusUtility `handleAgentAction`, GtmAgent* Apex) | navigates only to tab apiName + state; no Apex-built record URLs (grep found none) | unchanged |
| Home pages (GTM_Offerings_Home / GTM_Content_Home) | components only; no SC/AR record links (grep) | unchanged |
| Flow GTM_Config_Send_To_Client, Apex emails / Tasks | only the prospect Generated_URL (sharedUrl); no record-page URLs (grep of classes/flows) | unchanged |
| Opportunity layout `Engagement_Link__c` lookup click, global search, list views, related lists, Opportunity Related List | standard SC record page | fixed by the app-level View override (GTM Offerings app only), see "Still on the record page" |

## Standard SC record page: override options (research)

Docs consulted from knowledge only. WebFetch/browser were not available in this session, so nothing below was fetched or checked against live docs (no 403 observed; simply UNVERIFIED). Sources to confirm:
- Override standard actions: https://developer.salesforce.com/docs/atlas.en-us.lightning.meta/lightning/components_config_for_actions_override.htm (unverified)
- Object action overrides (CustomObject `actionOverrides`, `type` Flexipage / LightningComponent / Visualforce / Default): https://developer.salesforce.com/docs/atlas.en-us.api_meta.meta/api_meta/customobject.htm (unverified)
- Lightning navigation `standard__navItemPage` state: https://developer.salesforce.com/docs/platform/lwc/guide/reference-navigation.html (unverified)

Options for GTM_Saved_Configuration__c (and GTM_Assessment_Request__c) View:
1. **Lightning-component View override** (an Aura component implementing `lightning:actionOverride` + `force:hasRecordId` that immediately calls `lightning:navigation` to the GTM_Pages tab). Salesforce supports LWC/Aura component overrides for View on custom objects; LWC-only overrides are not offered for the View action in all release contexts (unverified), so this is an Aura bundle.
2. **Flexipage override** (existing `GTM_Saved_Configuration_Record_Page` with a hosted component that Navigates on connect). No Aura needed, but a record page that redirects on load flashes and breaks Back (redirect loop risk).
3. **Leave the standard page** and fix only the surfaces we own (this change).

Recommendation: option 1 is the least surprising Salesforce-first fit, but it was NOT implemented, because it is not clearly safe:
- it removes the only admin/debug record view of an SC (the flexipage hosts gtmRepDirectShare, gtmLinkSitemap, gtmLinkActivity), so admins lose their debugging surface;
- it applies to every user, including Content Manager roles who do not hold the GTM_Pages tab, who would land on a permission wall;
- it overrides View for the whole org (gtm-dev is treated as production), a hard-to-see change of behaviour for global search, list views and related lists, and a redirect from a record page can loop with anything that still links to it (gtmLinkActivity `parentIsSavedConfiguration`);
- it cannot be verified without browser work, which was out of scope.
If the user wants it: add the Aura override component, then `actionOverrides` `View` -> `LightningComponent` (`c:GtmSavedConfigurationViewRedirect`) with `formFactor` Large, guard: redirect only when the user holds the GTM_Pages tab, else fall back to the record page. Reverse by removing the `actionOverrides` entry. Ship to staging first behind `--dry-run`.

Instead, the Opportunity `Engagement_Link_Info__c` formula (the clickable SC link on the Opportunity page) is repointed at the Pages tab; that is a one-line, reversible formula change. The raw `Engagement_Link__c` lookup still lands on the SC record page.

## Tests

- `gtmNavigate.test.js`: helper page references, account-less fallback, readout to parent AR, no record page ever.
- Surface tests updated/added: gtmOverview (SC row drill-in state), gtmAssessmentSubmissionView (readout -> parent AR workspace, Name is a button cell), gtmAssessmentDetail (SC name -> Pages), gtmStageActions (View assessment -> workspace), gtmRepLinkFinder table/model/contactLink (no-account and no-contact rows open).
