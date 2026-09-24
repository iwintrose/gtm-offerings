# TASK SCOPE — ISSUE #rep-initiated-assessment-no-page-1-picker-and-record

## 0. Split rationale (applies to all three files in this set)

This feature does not fit one PR (precedent: this session already split
comparable work into #184/#102 and the currently in-flight
`rep-data-scoping-owd-1/2/3` trio). It is split into three sequential
sub-issues, all under one BA scope branch
(`ba-scope/issue-rep-initiated-assessment-no-page`):

1. **`-1-picker-and-record`** (this file): the real Contact/Account picker
   UI + the pageless assessment record/entry-point creation + closing the
   accidental bare-URL path. This is the foundation the other two build on.
2. **`-2-share-and-continue`**: the "in-progress" share link and the
   prospect-facing continue/finish UI for mode (b) (rep starts, prospect
   finishes).
3. **`-3-readout-link-confirmation`**: confirms/wires the existing readout
   share-link mechanism (`Public_Link_Token__c`) onto the pageless path —
   smallest of the three, likely close to a no-op given investigation below,
   but kept separate so it can be verified/QA'd independently and dropped
   without blocking 1/2 if it turns out to need nothing at all.

Each sub-issue is independently deployable and testable; #2 depends on #1
merging first (needs the new object/flag from #1), #3 depends on #1 only
loosely (needs an assessment-request Id to attach a token flow to, which
already exists today).

## 1. Requirements Breakdown

- **Target Objective:** Give a rep a real, supported way to initiate an
  assessment on behalf of a specific, searched-and-selected Contact/Account
  with NO `GTM_Saved_Configuration__c` "page" implied — replacing the
  accidental bare-URL "direct booking" path that silently created duplicate
  Accounts/Contacts from typed text today.

  Confirmed (do not re-litigate): both submission modes — (a) rep fills in
  and submits the whole assessment live, and (b) rep starts it and hands off
  a link for the prospect to finish — must be supported by the same
  mechanism, and results must be shareable two ways (in-progress
  view/continue link, and a separate readout/results link). This file scopes
  only the picker + underlying record/entry-point; #2 and #3 scope the two
  link types.

- **System Component Impacted:** LWC (`gtmConfigurator`, a new/extended
  entry-point component reusing `gtmConfigWizard`'s Contact/Account search),
  Apex (`GtmSavedConfigurationController`, `GtmAssessmentRequestController`),
  Custom Metadata / schema (new field on `GTM_Saved_Configuration__c`),
  Permission Sets.

## 2. Investigation findings (ground truth for the Architect)

**A. The accidental path, confirmed and located.** In
`force-app/main/default/lwc/gtmConfigurator/gtmConfigurator.js`, the
`accessBlocked` getter (around line 999) is:

```js
get accessBlocked() {
    return !this.isConfigManager && !this.savedRecordId;
}
```

`isConfigManager` is true for ANY internal Salesforce user (`GtmViewerContext.isRep`
checks `UserInfo.getUserType() == 'Standard'`, see
`GtmSavedConfigurationController.isConfigManager()`). So any internal user
hitting the bare `/configurator` route with no `savedRecordId` in the URL is
waved straight through to a live, unattributed questionnaire — no Contact
search, no page. This is the exact bug the stakeholder wants closed. It must
be tightened so an internal user with no `savedRecordId` is redirected to
(or shown) the new proper rep-initiated entry point instead of being let
through to the bare questionnaire.

**B. What happens today with no `savedRecordId` on submit.**
`GtmAssessmentRequestController.RequestInput.savedRecordId` is optional;
when blank, `resolveConfigContext()` (private, not yet read here in full —
Architect should trace it) has no config link to key off, so Contact/Account
resolution falls back to whatever `submitRequest()` does with the raw
`name`/`email`/`company`/`prospect` strings on the request. This is the
duplicate-creation behavior to replace for the rep-initiated path: the new
flow must supply a real `contactId`/`accountId` (from the picker below)
rather than relying on this fuzzy-resolve fallback. Confirm in this
sub-issue's implementation whether `RequestInput` needs new
`contactId`/`accountId` fields analogous to `SaveInput.contactId`/
`accountId` on `GtmSavedConfigurationController` (very likely yes — same
"exact record beats fuzzy match" precedent already established there).

**C. The Contact/Account picker precedent to reuse, confirmed real.**
`GtmSavedConfigurationController.searchContacts(String searchTerm)`
(`with sharing`, matches Contact Name/Email/Account Name, returns
`ContactSearchResult{contactId, name, email, accountId, accountName}`) is
the exact search-and-select mechanism already live in `gtmConfigWizard`'s
Customize panel (its `SaveInput.contactId`/`accountId` fields document this:
"Set when the rep picked an existing Contact from searchContacts() rather
than typing a name/email freehand"). Reuse this Apex method and the
equivalent picker UI pattern in `gtmConfigWizard.js`/`.html` directly rather
than building a new search. `getAccountDeals`/`findAccountByName` (deal
picker) are adjacent precedent for "pick from real records, don't
free-type" and may be relevant if the new flow also needs an Opportunity
association (it should, to be consistent — a rep-initiated assessment on an
Account very likely wants the same Opportunity linkage
`GtmSavedConfigurationController.saveConfiguration()` already does).

**D. The record-creation call, decided.** Investigated whether the pageless
assessment needs a new object or should reuse `GTM_Saved_Configuration__c`
flagged to exclude it from "All Pages." Decision: **reuse
`GTM_Saved_Configuration__c`**, not a new object, for these reasons:
  - It already carries every field this flow needs: `Account__c`,
    `Contact__c`, `Opportunity__c`, `Generated_URL__c`, `Link_Password__c`,
    `Config_Payload__c`, `Notify_Email__c`, `Presentation_Stage__c`.
  - The just-landed completeness filter on `getMyConfigurations()` (branch
    `agent/issue-pages-assessments-cleanup`, already reviewed — see §0 note
    to Architect below) already filters "All Pages" down to
    `Presentation_Stage__c NOT IN (null, 'Draft')`. A pageless-assessment
    record marked with a **new, distinct** `Presentation_Stage__c` value
    (e.g. `'Assessment_Only'` — exact label is the Architect's call, flag
    to stakeholder if it needs to be picklist-visible in a report) is
    automatically excluded from "All Pages" for free, with no extra filter
    logic — it is neither null/Draft (which the filter already excludes)
    nor one of the "real page" stages, so a *second* exclusion clause is
    needed: `getMyConfigurations()`'s query must also exclude this new
    stage value explicitly (it currently only excludes null/Draft, and
    would otherwise start showing "Assessment_Only" records as if they were
    pages — this is a required follow-on edit to the query built in
    `agent/issue-pages-assessments-cleanup`, not a revert of it).
  - Reusing the existing object also means the existing password-gate
    (`Link_Password__c`) and guest-access flow described in #2's scope file
    work unmodified — a second parallel object would have needed its own
    copy of that whole mechanism.
  - A brand-new lightweight join object was considered and rejected: it
    would duplicate `Account__c`/`Contact__c`/`Opportunity__c`/password/URL
    fields already proven out on `GTM_Saved_Configuration__c`, doubles the
    guest-access surface to secure and test, and blocks the stakeholder's
    open question below (converting a pageless assessment into a full page
    later) since that would require a record-type migration instead of a
    same-record field flip.
  - This does mean `GTM_Saved_Configuration__c`'s existing "this record IS
    a page" assumptions elsewhere in the codebase (any other query/report
    that reads this object) need to be audited for the same exclusion the
    Architect must apply to `getMyConfigurations()`. Flag explicitly to
    Architect: grep every other SOQL against `GTM_Saved_Configuration__c`
    for the same gap before considering this done.

**E. Entry-point placement — flagged as open, do not guess.** The
stakeholder specified "a real button/tab, not a bare URL" but did not say
where. Candidates: a new button on the GTM Offerings app's Overview tab
(next to the existing "New engagement link" launcher —
`getSiteHomePageUrl()`/`getConfiguratorPageUrl()` already show that pattern
exists), or a new choice presented inside the wizard itself once a rep
starts it with no page intent. **Flag to Architect/stakeholder**: exact
placement, label wording, and icon are UI-design calls this scope
deliberately does not make.

## 3. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? NO — this touches `GtmSavedConfigurationController`,
      `GtmAssessmentRequestController`, and LWCs, not the GUS chat/tool
      surface. If a later sub-issue wires GUS into rep-initiated assessments,
      re-verify the zero-DML rule in `AGENTS.md` §1 at that time.
- [x] Altering Custom Metadata? NO custom metadata (YAML instrument) change
      is implied here — this is a `GTM_Saved_Configuration__c` picklist
      value addition (schema/CMDT-adjacent but not the YAML-authored
      assessment instrument pipeline). Do not touch
      `force-app/main/default/customMetadata/GTM_Assessment_*` for this.
- [x] Introducing database fields? YES — at minimum a new
      `Presentation_Stage__c` picklist value (`'Assessment_Only'` or
      Architect-chosen equivalent) on the existing field, and confirm
      whether `RequestInput` needs new `contactId`/`accountId` fields (Apex
      class members, not database fields, no permission-set mapping
      needed for those). The picklist value itself needs no new
      permission-set grant (field already granted); if the Architect
      decides a genuinely new field is needed (e.g. a boolean
      `Is_Assessment_Only__c` instead of overloading the picklist), that
      NEW field must be mapped to `GTM_Offering_User`/`GTM_Offering_Admin`
      per `CLAUDE.md` §6 before this is done.

## 4. Plan Acceptance Criteria

- **Success Metric:**
  1. An internal user hitting the bare `/configurator` route with no
     `savedRecordId` no longer reaches a live, unattributed questionnaire —
     `accessBlocked`'s exemption is closed and replaced by routing to the
     new entry point (or a message directing them to it).
  2. A rep can search and select a real, existing Contact/Account (via the
     reused `searchContacts` picker pattern) and create a
     `GTM_Saved_Configuration__c` record flagged so it does NOT appear in
     "All Pages" (`getMyConfigurations()` correctly excludes it, verified by
     a new test alongside the existing completeness-filter tests on
     `GtmSavedConfigurationControllerTest`).
  3. No duplicate Account/Contact is created when a rep completes this flow
     with a picked (not typed) Contact — the DML path uses the picked
     `contactId`/`accountId` directly, not the fuzzy `resolveContact`/
     `resolveAccount` fallback.
- **Target Test Target:** `GtmSavedConfigurationControllerTest` (new tests
  for the pageless-flag creation path and the `getMyConfigurations()`
  exclusion of the new stage value), `GtmAssessmentRequestControllerTest`
  (new test confirming a picked `contactId`/`accountId` bypasses fuzzy
  resolution), plus a new Jest spec for whichever LWC hosts the picker
  (either extending `gtmConfigWizard.test.js` or a new component's own
  `__tests__`).
