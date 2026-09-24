# Overview sales dashboard, piece C: Offerings (Row 3 left) and Assessment results (Row 3 right)

Status: Architect addendum (issue `overview-sales-dashboard-3-offerings-results`).
Scope: `docs/agent-artifacts/task-scope-overview-sales-dashboard-3-offerings-results.md`.
Builds on piece A (`overview-sales-dashboard-1-layout-funnel.md`), `gtm-assessments-table.md`
(`GtmAssessmentListController.getAssessmentPage`, `gtmAssessmentsTableModel`) and `GtmLinkStageService`
(all on main). Rows 1-2, funnel, deals table, Act-today tiles are NOT touched.

## Salesforce-native-first evaluation (recorded)

| Need | Native option | Verdict |
|---|---|---|
| Ranked assessment list | `lightning-datatable` | ADOPT, same pattern as the Assessments tab. Native column types (`button`, `text` with `cellAttributes` class/icon, `number`); `key-field="recordId"`, `hide-checkbox-column`, fixed-height scroll wrapper, no sorting (server order is the ranking). Row open = the `button` cell via `onrowaction` (datatable has no whole-row click; same decision as the tab). |
| Ranked list, alternative | Standard list view / related list / report | Rejected. Cannot express the explicit tier-rank, then score, then coalesced-date sort (picklist sorts by definition order), nor the shared server predicate. |
| Offering cards | none (story + feedback panel are bespoke and unchanged) | Stay as is. Only two count lines added. |
| Counts | Report / rollup | Rejected. Owner-scoped grouped aggregates in one small Apex method keep one definition of "live link" (stage-service universe) and the OWD scoping. |

## Decisions on the forks

1. **Live link** = stage-service universe (`Presentation_Stage__c` not null, not `Draft`, not `Rep_Direct`; owner-scoped unless view-all on `GTM_Saved_Configuration__c`) AND `Active__c = true`. `GtmLinkStageService` does NOT filter on `Active__c`, so this is deliberately a NARROWER definition than the Pages tab / funnel. State it in the UI (card footnote: "Live links = sent, active links; Draft and Rep_Direct are not counted.") and in the PR. Consequence: a card's live count can be lower than the Pages tab total for that offering; that is intended.
2. **Results source**: REUSE `GtmAssessmentListController.getAssessmentPage({ pageSize: 25 })`, no filters, no sortBy (default `best-fit`). NO interim ranker, NO client-side re-sort, NO rank map in JS. Rows arrive already ranked (Fast-Track 4 > Accelerator-Ready 3 > Prep Required 2 > Discovery First 1 > null 0 last, then score desc, then coalesce(submittedAt, createdDate) desc, Id desc). Ranking tests live in `GtmAssessmentListControllerTest` (re-run it); the Overview spec asserts the component preserves server order and shows null tier as an em dash, not that it sorts. `getAssessmentPage` already carries the class access on both sets (verified on main).
3. **Datatable**: yes, see table. REUSE `gtmAssessmentsTableModel`: import `mapRow` and pick `tierLabel`, `score`, `requestStatus` column definitions from `COLUMNS` by `fieldName` (spread with `sortable: false`, drop `initialWidth` where it hurts the compact card). Add ONE local first column in `gtmOverview.js`: `{ label: 'Company', type: 'button', fieldName: 'openLabel', typeAttributes: { label: { fieldName: 'openLabel' }, name: 'open', variant: 'base', title: 'Open assessment' } }` with `openLabel = row.companyLabel || row.contactLabel || row.name`. No extraction into the model (the shared pieces are already exported; extraction is not needed). Do not modify the model's exports' behaviour.
4. **Links under the card title**: "View all assessments" -> `{ type:'standard__navItemPage', attributes:{apiName:'GTM_Assessments'} }` (no state, tab default best-fit sort; that is the same set the card ranks) AND a separate quick link "Ready to book" -> same with `state: { c__apreset: 'ready-to-book' }`. `assessments-tab-filter` has merged, so no degrade path and no guard constant. Real anchors/`lightning-button variant="base"` (SLDS-2 button-compliance tests must still pass).
5. **Submitted counts**: NOT N calls. New class `GtmOverviewOfferingCounts` (below), one grouped aggregate per object. Note: `getAssessmentPage` also adds queue-orphan requests (readouts owned by a queue) for non-view-all users via an elevated read; the aggregate is plain `with sharing` owner-scoped, so for a rep the card count can be lower than the Assessments tab by those orphans. Accepted, documented, not compensated (no `without sharing` in the new class). The list total is NOT used for counts.
6. **Height**: the Assessment-results card uses the existing `var(--ov-row2-h)` (470px) with internal scroll; NO new height property. The Offerings card is auto-height (grows with cards). Row 3 is a grid `minmax(0, 7fr) minmax(0, 5fr)` (Developer may tune), `align-items: start`. Below 1100px it collapses to one column and the results card KEEPS 470px (as piece A decided), Offerings stays auto-height. Reuse piece A's media query; do not add a second breakpoint.
7. **No time window**: all-time top 25 by best fit, list scrolls internally. No average-score line, no bar chart, no "How ready are the prospects who submitted?" text anywhere.

## Apex contract (new)

```apex
public with sharing class GtmOverviewOfferingCounts {
    public class OfferingCount {
        @AuraEnabled public String offeringKey;
        @AuraEnabled public String offeringLabel;
        @AuraEnabled public Integer liveLinkCount;
        @AuraEnabled public Integer submittedAssessmentCount;
    }
    @AuraEnabled(cacheable=false)
    public static List<OfferingCount> getOfferingCounts()
}
```

- One row per `GTM_Offering__mdt` (label `Label__c`, key `Offering_Key__c`) with zero counts by default, PLUS one row for any key present in the data but not in the mdt (label = raw key). Never drops an offering. Sorted by label then key.
- Live links: `SELECT Offering__c k, COUNT(Id) c FROM GTM_Saved_Configuration__c WHERE Presentation_Stage__c != null AND Presentation_Stage__c != 'Draft' AND Presentation_Stage__c != 'Rep_Direct' AND Active__c = true [AND OwnerId = :currentUserId] GROUP BY Offering__c` (dynamic SOQL, as `GtmLinkStageService`). Keep the existing dynamic handling/comment style for `Saved_Configuration__c`-type lookups; this query does not need the lookup.
- Submitted: `SELECT Offering_Key__c k, COUNT(Id) c FROM GTM_Assessment_Request__c [WHERE OwnerId = :currentUserId] GROUP BY Offering_Key__c`. All statuses, all time.
- Blank/null keys are skipped (or summed into no row); document which in the Apex header.
- View-all: PRIVATE COPY of `hasViewAllRecords(String sobjectApiName)` (ObjectPermissions/PermissionSetAssignment probe, exactly as `GtmLinkStageService`), checked per object (`GTM_Saved_Configuration__c`, `GTM_Assessment_Request__c`). NOT `GtmHomeSnapshotController.isAdmin()`. Add the same "TODO de-duplicate onto the shared helper" note.
- Zero DML, zero callouts. Grouped aggregate queries have no row cap concern (aggregate result rows = distinct keys); do not add LIMIT that could silently truncate keys beyond 2,000.
- Permission sets: `classAccesses` for `GtmOverviewOfferingCounts` on `GTM_Offering_User` and `GTM_Offering_Admin` ONLY. No fields, objects or tabs are added, so no `fieldPermissions`. Not in Content sets, not `GTM_Guest`.
- Test class `GtmOverviewOfferingCountsTest` (self-created data, `@TestSetup`, `System.runAs`; never touch live data): live count excludes Draft, Rep_Direct, null stage and `Active__c=false`; submitted count includes all statuses; zero-count mdt offering appears with 0; unknown key gets raw-key label; two reps see only their own; admin with view-all sees all; both counts scoped; assert no DML statements executed (`Limits.getDmlStatements()` unchanged around the call). Avoid data-dependence on existing org mdt records (assert on keys you create, or on presence of your own key).

## LWC contract (`gtmOverview`)

State: `offeringCounts` (map by key), `countsError`, `assessmentRows`, `assessmentsLoading`, `assessmentsError`.

- `getOfferingCounts` imperative call from `connectedCallback`, INDEPENDENT of `getHomeSummary`. Failure sets `countsError`, cards still render with no count lines (no toast-blank). `offeringCards` getter merges by `offeringKey`: adds `liveLinkCount`, `submittedAssessmentCount`, `hasCounts`. Card text unchanged otherwise: story button, Feedback button, open-feedback badge, panel; their SLDS-2 button-compliance tests stay unchanged and green.
- Assessment list call: `getAssessmentPage({ query: { pageSize: 25 } })` imperative in `connectedCallback`, own loading/error/empty states. Empty: friendly "No assessments submitted yet" (no chart, no error). Error: existing error-banner idiom, card only. Rows mapped with `mapRow` (+ `openLabel`); order preserved as received.
- Row action: `handleAssessmentRowAction(event)` on `onrowaction`, `event.detail.action.name === 'open'`, navigates `standard__navItemPage` `GTM_Assessments` `state: { c__assessmentRequestId: row.recordId }` (same idiom as `handleAssessmentClick`).
- Row 3 markup replaces the bottom Offerings block (remove it from the bottom entirely; `showEmptyOfferings` state moves with it). Wrap the datatable in a container with `slds-scrollable_y` and a fixed height so the header row scrolls with the card body; card height `var(--ov-row2-h)`.
- No new hex colours; tier/status colouring comes from `mapRow` SLDS utility classes.

## Deploy-order / dependency notes

- `link-event-owner-fix`: this piece reads only `GTM_Saved_Configuration__c` and `GTM_Assessment_Request__c` (links, stage, owner, active; requests, tier, score, status). It does NOT read `GTM_Link_Event__c` (the prospect-generated, guest-owned events), so it is NOT affected by that issue and has no ordering dependency on it. The piece-A funnel is the surface that depends on it.
- Parallel piece B (`-2-act-today`) also edits `gtmOverview.js/.html/.css`; expect merge conflicts in those files, resolve by keeping both sides. Rebase on main before opening the PR.

## Test plan

Jest: `npx sfdx-lwc-jest -- force-app/main/default/lwc/gtmOverview force-app/main/default/lwc/gtmAssessmentsTableModel`, new spec `__tests__/gtmOverview.row3.test.js` (header `ISSUE #overview-sales-dashboard-3-offerings-results`): Offerings in Row 3 and absent from the bottom; counts shown, zero shown, counts-error degrades; datatable receives server-ordered rows unchanged, em dash for null tier; requested with `pageSize: 25`; row action and both links navigate with the exact states; empty and error states; no chart/average text; scroll wrapper class; card uses `--ov-row2-h`; footnote states live-link definition. Existing repDirect/funnel/test specs still pass. Full `npm test`.

Apex: `GtmOverviewOfferingCountsTest` plus re-run `GtmAssessmentListControllerTest`, `GtmLinkStageServiceTest`.

## Live deployment (STANDING)

Live deploy to `gtm-prod` (Production) is NOT authorised for Developer or QA. Permitted: validate-only check-only deploy WITH specified tests (executes and rolls back), e.g. `sf project deploy start --dry-run --test-level RunSpecifiedTests --tests GtmOverviewOfferingCountsTest --tests GtmAssessmentListControllerTest --tests GtmLinkStageServiceTest ...`. Never use `-c` (that is `--ignore-conflicts`). Developers must avoid Apex reserved words as identifiers (e.g. `limit`, `offset` as variable names, `group`, `end`, `select`, `count`, `order`, `type`, `date` in unsafe positions); use `rowLimit`, `startIdx`, `keyName`, etc.
