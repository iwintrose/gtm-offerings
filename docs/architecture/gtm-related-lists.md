# GTM related lists on Account, Contact, Opportunity and the GTM objects

Status: implemented on branch `agent/issue-related-lists`, deployed to `gtm-staging` only. Related lists on standard objects require the per-org layout patch (sections 5, 6).

## 1. Terminology

`GTM_Saved_Configuration__c` (SC) is the **Engagement Link** in every rep-facing label. `GTM_Assessment_Request__c` (AR) is the **Assessment Request**. A `GTM_Readout__c` is part of an assessment for an offering.

Domain rule: a readout cannot exist until the assessment is SUBMITTED (by the recipient, or by the rep on their behalf). Consequences:

- The Readouts related list on an Assessment Request is empty until submission. That is correct, not a bug.
- The Engagement Link page has no direct Readout relationship (`GTM_Readout__c` has lookups to AR and Opportunity only, no SC lookup). Readouts are reached via the request. No schema change is made for this.
- There is NO standalone Readout record page. Readouts open inside their assessment workspace. (A Readout page was deployed to staging during the work and then removed from both source and staging.) The GTM Readout layout gets a Versions related list only so the default page and deep links are not blank.

## 2. Rep job-to-be-done

A rep on an Account, Contact or Opportunity sees that prospect's engagement links and assessment status, and can open each one. A rep on an Engagement Link sees its assessment requests, link activity and form drafts. A rep on an Assessment Request sees its readouts, form drafts and link events.

## 3. Relationships (real API names)

| Parent | Child | Lookup field | relationshipName | List API name in FlexiPage |
|---|---|---|---|---|
| Account | AR | Account__c | GTM_Assessment_Requests | GTM_Assessment_Requests__r |
| Contact | AR | Contact__c | GTM_Assessment_Requests | GTM_Assessment_Requests__r |
| Opportunity | AR | Opportunity__c | GTM_Assessment_Requests | GTM_Assessment_Requests__r |
| Account | SC | Account__c | GTM_Engagement_Links | GTM_Engagement_Links__r |
| Contact | SC | Contact__c | GTM_Engagement_Links | GTM_Engagement_Links__r |
| Opportunity | SC | Opportunity__c | GTM_Saved_Configurations (inconsistent, NOT renamed) | GTM_Saved_Configurations__r |
| SC | AR | Saved_Configuration__c | GTM_Assessment_Requests | layout related list |
| SC | Link Event | Saved_Configuration__c | GTM_Link_Events | layout related list |
| SC | Form Draft | Saved_Configuration__c | GTM_Form_Drafts | layout related list |
| AR | Readout | Assessment_Request__c | GTM_Readouts | layout related list |
| AR | Form Draft | Submitted_Request__c | GTM_Assessment_Drafts | layout related list |
| AR | Link Event | Assessment_Request__c | Link_Events | layout related list |
| Readout | Readout Version | Readout__c (MasterDetail) | Versions | layout related list |

relationshipName is never changed (it is referenced by Apex and metadata). Only `relationshipLabel` was normalised: SC.Account__c, SC.Contact__c and SC.Opportunity__c now all read "Engagement Links". The AR labels were already "Assessment Requests".

Verified against the staging org describe: the FlexiPage `relatedListApiName` must carry the `__r` suffix (a dry-run with the bare relationshipName failed with "Could not find related list"), and `parentFieldApiName` is required (`Account.Id`, `Contact.Id`, `Opportunity.Id`).

## 4. Columns

- GTM objects (our layouts, shipped): related-list columns are declared in the layout XML.
  - SC page: AR = NAME, Status__c, Assessment_Tier__c, Assessment_Score__c, Submitted_At__c; Link Events = NAME, Event_Type__c, Step__c, CREATED_DATE; Form Drafts = NAME, Status__c, Last_Saved_At__c, Expires_At__c.
  - AR page: Readouts = NAME, Status__c, Published_Date__c, Approved_Date__c; Form Drafts = NAME, Status__c, Last_Saved_At__c; Link Events = NAME, Event_Type__c, Step__c, CREATED_DATE.
  - Readout: Versions = NAME, Version_Number__c, Status_At_Snapshot__c, Change_Summary__c, CREATED_DATE.
- Account / Contact / Opportunity: the columns come from the `<fields>` of the `<relatedLists>` block on the object's page layout (see section 5 for how the block is added). Target columns: AR (`GTM_Assessment_Request__c.<Parent>__c`) = NAME, Status__c, Assessment_Tier__c, Assessment_Score__c, Submitted_At__c; SC (`GTM_Saved_Configuration__c.<Parent>__c`) = NAME, Offering__c, Presentation_Stage__c, Active__c. The layout related-list value is `<ChildObject>.<LookupField>` (the lookup field, so the inconsistent Opportunity relationshipName `GTM_Saved_Configurations` does not matter here).
- The four source `Opportunity-*` layouts and all other standard-object layouts are NOT modified in the repo. The blocks are added to the TARGET org's own layout by `scripts/patch-related-lists-layouts.py` (section 5, runbook in `docs/runbooks/gtm-offerings-install.md`).

## 5. Package vs layout patch

Real behaviour (owner-supplied, observed live on gtm-staging): a `force:relatedListSingleContainer` card is hidden with the message "This related list cannot be displayed because it is not in the current page layout." unless that list is on the object's assigned page layout. The earlier assumption that the cards render without a layout entry (and that adding the lists to the layout later would duplicate them) was wrong. UNVERIFIED: no Salesforce doc was fetched for this behaviour; it rests on the live observation.

- In the package: the three FlexiPages (`GTM_Account_Record_Page`, `GTM_Contact_Record_Page`, `GTM_Opportunity_Record_Page`), the three GTM layouts with related lists, label fixes. The FlexiPages NO LONGER carry the two explicit `relatedListSingleContainer` cards; the Related tab is the layout-driven `force:relatedListContainer`, which shows every related list on the assigned layout, so each GTM list appears once.
- The lists live on the standard-object page layouts: Account Layout / Contact Layout / Opportunity Layout in prod, and every layout the GTM profiles are assigned in the org (on staging: SDO - Account, SDO - Partner Account, Account Layout, SDO - Account Community, SDO - Contact, SDO - Partner Contact, SDO - Opportunity, Opportunity Layout).
- Packaging tradeoff: adding a related list to a subscriber's standard layout is a shared-resource change. A layout deploy REPLACES the whole layout in the target org and affects every app and profile that uses that layout (reps in other apps also see the two lists). Shipping full Account/Contact layouts would push one org's fields, actions and demo (SDO) content onto another org, so full standard layouts are NOT in the package or the repo. The lists are delivered by the prod-safe patch procedure: retrieve the target org's own layout, run `scripts/patch-related-lists-layouts.py` (inserts only the two `<relatedLists>` blocks, idempotent, refuses unless the diff is only those additions), validate-only deploy (`--dry-run`, explicit `-o`), then a real deploy only on the owner's go-ahead. Activation/assignment of any page for a standard object stays a human-confirmed step. (Packaging claim UNVERIFIED against Salesforce docs.)
- The FlexiPages keep the standard sections so the page is not a downgrade: highlights panel, Details tab, Related tab, Activity tab (`runtime_sales_activities:activityPanel`), Chatter feed sidebar. Not carried over from a customised org page: Path, org-specific components, org-specific actions.
- Permissions checked: no new fields or objects. Column fields need grants in GTM_Offering_User and GTM_Offering_Admin (required fields such as SC.Offering__c are implicit and carry no entry). GTM_Content_* and GTM_Guest get nothing.

## 6. Assignment (app level, in metadata)

Assignment is done in `force-app/main/default/applications/GTM_Offerings.app-meta.xml` with three `actionOverrides` (actionName `View`, type `Flexipage`, formFactor `Large`, pageOrSobjectType Account/Contact/Opportunity, content `GTM_<Object>_Record_Page`), following the same element pattern as the existing Home override. Element names match the CustomApplication metadata as retrieved from staging and the dry-run accepted them; the Metadata API doc page itself could not be read (JS shell), so doc citation is unverified.

- Only users inside the GTM Offerings app get these pages. The org default and other apps (including GTM Content Manager) are untouched. Users outside the app see the standard page.
- Remaining required per-org step for reps inside the app: the layout patch (section 5). Without it the Related tab shows no GTM lists. App assignment alone is not enough.
- The existing SC and AR record pages are still assigned in the org, not in source.

## 7. Permissions

Checked, no change needed. GTM_Offering_User and GTM_Offering_Admin have object CRUD and the relevant field grants on AR, SC, Link Event, Form Draft, Readout and Readout Version. Required fields (Readout.Status__c, SC.Offering__c, Link_Event.Event_Type__c, Form_Draft.Status__c and Draft_Type__c) and the MasterDetail Readout_Version.Readout__c are implicitly visible and correctly carry no field grant.

## 8. Risks

- AR, SC, Readout, Link Event and Form Draft are Private sharing. A rep who is not the owner sees an empty related list on a shared Account/Contact/Opportunity, which can be read as "no engagement". Guided setup copy should say lists show only your own records; admins (View All) see everything. GTM_Offering_User has View All on Link Event and Form Draft, so those lists on the SC/AR page are not owner-limited.
- Person Accounts (enabled in staging): the Account describe shows the Contact lookups as `__pr`. The Account page uses the Account__c relationship (`__r`), which is unaffected; person-account contacts are not aggregated on the Account page.
- The `__r` suffix and `parentFieldApiName` are needed; if a lookup field is renamed or deleted, the page fails to deploy.
- Columns on standard pages come from the patched layout blocks (section 4); a later layout edit by an admin can change them.

## 9. Guided Setup row (for a later workstream; guided-setup code is owned by another branch and untouched here)

- key: `related-lists-standard-objects`
- title: Add related lists to Account, Contact and Opportunity
- tier: RECOMMENDED
- detect: for each of Account, Contact, Opportunity, the layout(s) assigned to the user's profile contain both related lists (`GTM_Assessment_Request__c.<Parent>__c` and `GTM_Saved_Configuration__c.<Parent>__c`). Tooling API: Layout metadata `relatedLists` (and ProfileLayout for the assignment). It replaces the earlier check for FlexiPage cards. If assignment cannot be resolved, show "Review".
- act: the prod-safe patch (`scripts/patch-related-lists-layouts.py`, a per-org admin/operator step) or a LINK to the object's page layout editor (`/lightning/setup/ObjectManager/<Object>/PageLayouts/view`), with copy explaining the Private-sharing caveat and that the lists show for all apps using that layout. This issue updates the doc only; the guided-setup code is owned by another branch, and the row key `related-lists-standard-objects` is unchanged.
