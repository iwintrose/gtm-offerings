# Link readiness -- Draft / Invalid / Ready / Sent for engagement links

Status: Proposed (issue `link-draft-state`). Docs only; no feature code in this change.
Branch: `agent/issue-link-draft-state` (cut from `agent/issue-sc-links-to-pages`).

## 1. Requirement (sales-rep persona)

An engagement link (`GTM_Saved_Configuration__c`, "SC") that is not completed must be
visibly in a draft or invalid phase. The Pages list, the Pages detail and the preview must
say so in rep language and give one obvious way to continue and finish THIS link. It must
never be blank. A prospect who opens an unfinished link must see a neutral "not available
yet" page, never a blank page, an error, or internals.

## 2. Findings: what the code does today

Verified by reading code; no org calls were made. Line numbers are approximate and taken
from this branch.

### 2.1 What "completed" means today: nothing defines it

- `Presentation_Stage__c` restricted picklist: `Assessment`, `In_Review`, `Draft`, `Sent`,
  `Rep_Direct` (`objects/GTM_Saved_Configuration__c/fields/Presentation_Stage__c`).
- `GtmSavedConfigurationController.saveConfiguration` (~L413-545):
  - Hard requirements: `generatedUrl` and `offering` non-blank. On a NEW record also at
    least one Account signal (accountId or company text) OR Contact signal (contactId or
    email); note the OR, so a link with only a company name and no contact saves fine.
  - New record is stamped `Presentation_Stage__c = 'Draft'` (~L524). An update never touches
    the stage.
  - Every wizard autosave (from step 1; `_save(advance)` in `gtmConfigWizard.js` ~L1335)
    calls this, and `_ensureGeneratedPassword()` guarantees a password. So EVERY wizard
    record already has `Generated_URL__c`, `Link_Password__c`, `Config_Payload__c` from its
    first autosave. URL and password therefore do NOT distinguish finished from abandoned.
- `createRepDirectAssessment` (~L310) inserts a pageless record with stage `Rep_Direct`
  (Account/Contact/Offering only, no URL, no payload). Not an engagement page.
- Stage transitions in code: `GtmStageActionsController.advanceStage` (In_Review, Draft,
  Sent, Assessment) driven by `gtmStageActions`; `GtmAssessmentRequestController` (~L840)
  sets `Assessment` on submit. The flow `GTM_Config_Send_To_Client` emails the client when
  stage becomes `Sent`. **Nothing in the wizard ever moves a link from Draft to anything
  else.** Flag for the coordinator (Q1): unless `gtmStageActions` is mounted somewhere the
  rep uses, wizard-built links sit at `Draft` forever.
- `Active__c` is an independent on/off switch (rep "Turn off"). `GtmConfigurationStatusController.isActive` and `getPublicConfiguration` use only it.

### 2.2 What the rep sees today for a draft: nothing (the row is hidden)

- `getMyConfigurations()` (~L600-635) filters
  `Presentation_Stage__c != null AND != 'Draft' AND != 'Rep_Direct'` and its comment says a
  Draft is "excluded from All Pages rather than cluttering it". `GtmLinkStageService`
  (~L189) uses the same universe so counts equal list lengths.
- So a Draft link is not in the Pages table at all. It is reachable only by deep link
  (`c__rlfLinkId`, `c__cfgId`) or `getContactsWithLinks` (Account drill), which has no stage
  filter. In those, `gtmRepLinkFinder` opens the detail and "Preview the link" mounts
  `c-gtm-configurator` view-only for `selectedLink.recordId`, which renders whatever partial
  `Config_Payload__c` exists (a half-built page or generic template). No message says it is
  unfinished.
- The Pages table "Status" column and the "Link status" filter (`gtmRepLinkFilterModel.js`
  L62-64 options Active/Inactive; `gtmRepLinkTableModel.js` L118/138 statusLabel
  Active/Inactive) know only `Active__c`. A Draft with `Active__c = true` would read "Active".
- Seed (`data/seed/synthetic-demo.saved-configurations.json`): demoCfg1 `Draft`,
  demoCfg2 `In_Review`, two `Sent`, one `Assessment`, one `Rep_Direct`. All have Account,
  Contact, Opportunity, Offering, Industry set, so the seed has no INVALID row (a test
  fixture with a blank Contact must be added, see section 9).

### 2.3 What a prospect sees today for a draft: the full page, or a partial one

- `gtmConfigurator` reads `?cfgId=` and calls `getPublicConfiguration` (guest, `without
  sharing`). It returns nothing except `isActive=false` for inactive links. Draft is not
  considered. So a prospect opening a Draft link sees the page rendered from the partial
  payload (password gate first, since a password always exists). Not blank and not an
  error, but possibly half-built, and it leaks unfinished content.
- `Active__c = false` shows "This preview link is no longer active." (`gtmConfigurator.html` L649). Reuse that pattern for the not-yet-available case.

### 2.4 Salesforce-first check

I could not fetch Salesforce documentation in this environment (no web tool available in this
session). All citations below are from prior knowledge and are **unverified**; the
Developer/QA must confirm before relying on them.

- Path (Lightning Path, setup name "Path Settings"): a native component on the record page
  for a picklist such as `Presentation_Stage__c`; `help.salesforce.com` topic "Guide Users
  with Path" (unverified URL).
- SLDS badge/pill/alert: `lightningdesignsystem.com/components/badges/` and
  `/components/alert/` (unverified).
- `lightning-badge`, `lightning-datatable` cell types (`badge` is not a datatable type;
  use a custom type or class text) (unverified).

Recommendation: **do not use Path for this.**

1. Path renders picklist values only. Readiness is derived from missing fields (Contact,
   password, etc.) that Path cannot express, and the wizard step the rep must return to is
   not a Path stage.
2. Path lets a rep click a stage to change it. Clicking `Sent` fires
   `GTM_Config_Send_To_Client`, which emails the client. That is a live-prod side effect
   from a stray click, and Path would bypass `gtmStageActions` and its guard rails.
3. The Pages detail is a custom LWC (`gtmRepLinkFinder`); Path is only available on the
   standard record page, which reps do not use here (GTM_Pages is a nav item).
4. The stage picklist is coarse and partly unrelated (In_Review means "the client asked us
   to prepare a proposal", not "rep unfinished").

Native pieces we DO use: SLDS badge/alert markup and `lightning-button`, `lightning-badge`,
plus `Presentation_Stage__c` unchanged as an input. Custom Apex is justified because the
readiness rule crosses fields and must be shared by the list, detail and guest page.

## 3. Definition: link readiness (single source of truth)

Computed in ONE place: Apex `GtmLinkReadiness` (`with sharing`, no DML, no callouts,
pure function of one `GTM_Saved_Configuration__c` row, plus a bulk Aura wrapper).
No JS mirror: the UI asks Apex for the result for the ids it is showing (one extra query
per page load, no per-row queries). A JS reimplementation is explicitly forbidden (drift).

### 3.1 Inputs

Stage, Active, Account__c, Contact__c, Offering__c, Industry__c, Generated_URL__c,
Link_Password__c, Config_Payload__c. All existing fields; nothing new.

### 3.2 Required-field checklist

| Key | Field | Rule | Rep label (missing) | Wizard step |
|---|---|---|---|---|
| `account` | `Account__c` | non-null | an account | 1 |
| `contact` | `Contact__c` | non-null | a contact | 1 |
| `offering` | `Offering__c` | non-blank | an offering | 1 (launch parameter) |
| `industry` | `Industry__c` | non-blank | an industry | 2 |
| `password` | `Link_Password__c` | non-blank | a link password | 7 |
| `url` | `Generated_URL__c` | non-blank | a generated link | 8 |
| `content` | `Config_Payload__c` | non-blank and parses as a JSON object | page content | 3 |

`content` is skipped for `Rep_Direct` (pageless). Wizard steps: 1 Who is this page for
(account + contact), 2 industry, 3 brand colour, 4 setup size, 5 anything specific,
6 confirm your details, 7 password, 8 Save (from `gtmConfigWizard.html`).

### 3.3 States (evaluated in this order, first match wins)

| Order | State | Condition | Meaning |
|---|---|---|---|
| 1 | `NO_PAGE` | stage = `Rep_Direct` | Pageless assessment. Not a page; unchanged behaviour, not shown on Pages. |
| 2 | `SENT` | stage in (`Sent`, `Assessment`) | Out the door. Never downgraded to INVALID, even if a legacy row lacks a field (a warning line may list them, no alarm). |
| 3 | `IN_REVIEW` | stage = `In_Review` | Our team is preparing the proposal. The rep has nothing to finish. |
| 4 | `INVALID` | stage in (`Draft`, null) AND at least one required field missing | Unfinished; carries `missing[]` keys. |
| 5 | `DRAFT` | stage in (`Draft`, null) AND nothing missing | Complete data, not yet sent. Rep can review and send. |

Overlay, not a state: `active = (Active__c != false)`. A Sent link with `active=false`
shows the status pill as before plus "Turned off". Overlay never changes readiness.

Result shape (Apex, `@AuraEnabled` members):

```apex
public class Readiness {
    @AuraEnabled public Id       linkId;
    @AuraEnabled public String   state;        // NO_PAGE | SENT | IN_REVIEW | INVALID | DRAFT
    @AuraEnabled public List<String> missing;  // keys from 3.2, in checklist order; empty unless INVALID
    @AuraEnabled public Integer  resumeStep;   // lowest wizard step among missing; 8 for DRAFT; null otherwise
    @AuraEnabled public Boolean  guestVisible; // 3.6
}
public static Readiness evaluate(GTM_Saved_Configuration__c r)                     // non-Aura, tests/GUS
@AuraEnabled(cacheable=false) public static List<Readiness> getReadinessAura(List<Id> linkIds)  // rep, with sharing
```

Rep visibility follows `with sharing`; ids the user cannot read are simply absent.

### 3.4 Migration for existing rows

Derive-only. No data change, no field, no backfill, no permission-set change (nothing new
is introduced; the class needs read access to fields the rep already reads). Every existing
row gets a state on read. Expected effect on prod (coordinator to confirm with a count query,
Q1): rows currently at `Draft` with everything present become DRAFT and start appearing on
Pages where they were previously hidden.

## 4. Rep-facing copy (exact)

Pill labels and short reason (list "Readiness" column, detail header). Reason lists at most
two missing items then "and N more". Join with " and ".

| State | Pill | Tone | Short reason |
|---|---|---|---|
| INVALID | `Draft, incomplete` | warning (amber) | `Draft: needs {missing list} before it can be sent` e.g. "Draft: needs an account and a contact before it can be sent" |
| DRAFT | `Draft` | neutral (grey-blue) | `Ready to review. Open it to check the page and send it to your contact.` |
| IN_REVIEW | `In review` | info (blue) | `Our team is preparing this proposal. You will get an email when it is ready.` |
| SENT | `Sent` | success | (none) |
| SENT + inactive | `Sent, turned off` | weak | `This link is turned off. Your contact cannot open it.` |

Pages detail banner (top of the detail view and ABOVE the preview, always rendered for
INVALID / DRAFT / IN_REVIEW; SLDS `slds-notify_alert`, amber for INVALID, blue otherwise):

- INVALID title: `This page is a draft and is not finished`
  body: `It still needs {missing list}. Until then your contact sees a "not available yet" message, so it is safe to leave. Continue editing to finish it.`
  primary button: `Continue editing` (section 5); secondary: `Back to links`.
- DRAFT title: `This page is a draft and has not been sent`
  body: `Everything needed is filled in. Review the page, then send the link to your contact.`
  primary: `Review and send` (opens wizard on the final step 8, same deep link); secondary: `Preview the link`.
- IN_REVIEW title: `This page is in review`
  body: `Our team is preparing your proposal. You do not need to do anything. We will email you when it is ready.`
  no primary (secondary `Preview the link`).

Preview area when INVALID: the preview is NOT mounted (no half-built page). In its place
an SLDS empty-state card: heading `Nothing to preview yet`, text `Finish the draft to see the page your contact will get.`, and the same `Continue editing` button.
When DRAFT: preview mounts as today with a persistent strip above it: `Draft preview. Your contact cannot see changes until you send.`

Tooltips on row action menu for INVALID rows: `Open` becomes `Continue editing`.

## 5. Primary actions and navigation

`Continue editing` / `Review and send` navigate to the configurator wizard for THIS link:

```
{ type: 'standard__navItemPage', attributes: { apiName: 'GTM_Overview' },   // confirm nav api name of the wizard host tab
  state: { c__continueLink: '<recordId>', c__step: '<resumeStep>', c__offering: '<Offering__c>' } }
```

The wizard host (`gtmOverview`, which already owns `wizardOpen`) reads `c__continueLink`,
mounts `c-gtm-config-wizard` with two NEW `@api` props: `resumeRecordId` and `resumeStep`.
These are deliberately not `savedRecordId`, which jumps to the finished "Link generated"
screen (step 9) and is documented as unsafe for half-filled links in `gtmOverview.html`.
On open the wizard must hydrate its state from the record (payload, industry, accent,
Contact/Account, notify email) via the existing rep `getConfiguration`, then land on
`resumeStep`. Back button behaves normally. Saving continues to update the same record
(`recordId` is passed), so no duplicate is created and the SC number is unchanged. On Done
it returns to Pages for the same link (`c__template=link&c__recordId=`), existing behaviour.
Fallback: if the record or param is unusable, the wizard opens on step 1 with the
message `We could not reopen that draft. Start again from step 1.`

`resumeStep` is computed server-side (3.3) so the Pages UI holds no step logic.

## 6. Pages list and filters

- New column `Readiness` replaces nothing; it is added next to `Status`. `Status`
  (Active/Inactive) is unchanged so existing bookmarks (`c__pactive`) keep working.
- Filter-bar "Link status" (More popover) keeps Active/Inactive and gains a second chip
  group `Readiness` (param `c__pready`, values `draft`, `incomplete`, `in_review`,
  `sent`; multi-select). Default: no selection (all shown). Draft rows are now INCLUDED by
  default, sorted by the existing sort (CreatedDate desc).
- Universe: add `getMyLinksWithDrafts()` (new method, same owner scoping, `Rep_Direct`
  excluded, null stage excluded only if it also has no Account/Contact/URL; null-stage
  legacy rows count as Draft/INVALID per 3.3) in `GtmSavedConfigurationController`.
  `getMyConfigurations()` and `GtmLinkStageService` keep their current filter so
  stage counts, Overview funnel and the GUS tool are unchanged; Draft rows have no funnel
  stat and show "-" in Funnel stage, are absent when a `c__stage` filter is active.
- Row click / Open on INVALID and DRAFT rows opens the detail with the banner (section 4);
  the row's account link and contact link stay disabled when null (existing behaviour).
- Header count text ("N links") counts all rows shown; add a hint chip `N drafts` that
  applies the readiness filter `draft,incomplete` when clicked.

## 7. Opportunity and Account related lists

Native related lists (Engagement Links on Account/Opportunity, if placed on the page
layout) show the record Name (SC-nnnn) and configured columns. Readiness is derived in Apex and cannot be a related-list column without a new formula or
persisted field, which this issue forbids. Decision: no change to related lists in this issue. The SC number links to the
standard record page, which is out of scope; reps reach readiness through Pages. If the
coordinator wants readiness on related lists, that needs a persisted or formula field plus
permission-set grants across the five sets (Q3).

## 8. Prospect side (guest)

`GtmConfigurationReader.getPublicConfiguration` / `GtmConfigurationStatusController` are
`without sharing` guest entry points. Add to `PublicConfig` ONE boolean `available`
(default true). Rule: `available = false` iff `Active__c` is true AND the link is INVALID
per 3.3 (stage Draft/null AND required fields missing); `Rep_Direct`, `In_Review`,
`Sent`, `Assessment` and complete `DRAFT` are always available. Rationale: DRAFT with full
data may already be in a prospect's inbox (Q1), and we must not break live links.

When `available = false` the payload returns nothing else (same discipline as the inactive
branch: no company, industry, payload). `gtmConfigurator` reuses the existing inactive
panel (`gtmConfigurator.html` ~L646) with the new copy:

- Title: `This page is not available yet`
- Body: `The page you are looking for is still being prepared. Please check back soon, or contact the person who sent you this link.`
- No SC number, no offering, no rep name, no stage, no field names. Same panel for a
  malformed or unknown id is unchanged (already fails closed).

Fail open on a check error, as `checkActiveStatus` does today. Server enforcement of
guest data is the empty payload, not the client message.

## 9. Workstreams (disjoint files)

| WS | Scope | Files (owns) | Est. |
|---|---|---|---|
| A | Apex readiness helper + tests | `classes/GtmLinkReadiness.cls`(+meta), `classes/GtmLinkReadinessTest.cls`(+meta) | 3 h |
| B | Universe method for drafts | `GtmSavedConfigurationController.cls` (`getMyLinksWithDrafts` only), `GtmSavedConfigurationControllerTest.cls` | 1.5 h |
| C | Pages list pill, column, Readiness filter | `lwc/gtmRepLinkFinder/gtmRepLinkTableModel.js`, `gtmRepLinkFilterModel.js`, related `__tests__` | 4 h |
| D | Pages detail banner, empty-state preview, actions | `lwc/gtmRepLinkFinder/gtmRepLinkFinder.js/.html/.css` and its `__tests__` | 5 h |
| E | Wizard resume (deep link, hydrate, step) | `lwc/gtmConfigWizard/*`, `lwc/gtmOverview/gtmOverview.js/.html` | 7 h (highest risk: state hydration) |
| F | Prospect message | `GtmConfigurationReader.cls` (+Test), `lwc/gtmConfigurator/gtmConfigurator.js/.html` (inactive panel only) | 3 h |

Sequencing: A first (contract), then B/F/C/D/E in parallel against section 3.3's `Readiness`
shape. C and D both need `getReadinessAura`; D and C do not share files (`gtmRepLinkFinder.js`
is D only; C touches the two model modules; a one-line import in the finder for the column
is coordinated by D). Total about 24 h across 2 developers.

No permission-set changes (no new object/field/tab). `GtmLinkReadiness` needs class access
for reps: add it to `GTM_Offering_User` and `GTM_Offering_Admin` `classAccesses`
(same change, not a follow-up). Guest path uses the existing reader classes only.

## 10. Test plan

- Apex A: table-driven, one test per row of 3.3 (Rep_Direct, Sent, Assessment, In_Review,
  Draft/null with each single missing field, all missing, complete Draft); `missing` order;
  `resumeStep` per key and the minimum rule; Sent with missing fields stays SENT; bulk 200
  rows with 1 query; unreadable id absent (rep A cannot evaluate rep B's link).
- Apex F: guest calls `getPublicConfiguration` for INVALID draft -> `available=false`, no
  company/payload; complete Draft, Sent, In_Review, Rep_Direct -> available; inactive
  unchanged.
- Jest C/D: pill text and tone per state; "Draft: needs an account and a contact before it
  can be sent" exact string; more-than-two "and N more"; INVALID detail does not mount
  `c-gtm-configurator`; DRAFT does; `Continue editing` navigate args (cfg id, step,
  offering); readiness filter param round-trip `c__pready`; existing Active/Inactive
  filter tests unchanged; no drafts in `c__stage` filtered list.
- Jest E: wizard with `resumeRecordId` hydrates and lands on `resumeStep`; save passes the
  same recordId; bad id shows the fallback message and step 1.
- Seed: add a synthetic INVALID row (Draft, Contact blank) to
  `data/seed/synthetic-demo.saved-configurations.json` for QA; Is_Synthetic = true.
- QA (browser, per house rule, every dependent surface): Pages table, filters, detail,
  preview, wizard resume and finish (same SC number), Overview funnel counts unchanged,
  Assessments tab unchanged, prospect URL in a private window for INVALID vs complete
  Draft vs Sent vs inactive.
- Deploy: `sf ... --dry-run` first (the `-c` flag is not a dry run). gtm-dev is production;
  hold other deploys while this is verified.

## 11. Out of scope

Persisting a "wizard completed" marker (would be the only way to tell an abandoned
complete-looking draft from a finished one), auto-promoting Draft to Sent, Path, email
reminders for stale drafts, related-list readiness.

## 12. Open questions for the coordinator (max 3)

1. In prod, how do wizard-built links leave `Draft` today (is `gtmStageActions` mounted for
   reps)? Please run a count of `GTM_Saved_Configuration__c` by `Presentation_Stage__c`.
   Default used here: assume many complete links are `Draft`, show them as DRAFT (not
   hidden), and never block them for prospects.
2. Should complete DRAFT rows appear on Pages by default (this doc: yes, with `Draft`
   pill), which changes the current "drafts are hidden" behaviour reps may be used to?
3. Related lists (Account/Opportunity): accept no change now, or approve a persisted
   readiness field (needs permission-set grants across the five sets)? Default: no change.
