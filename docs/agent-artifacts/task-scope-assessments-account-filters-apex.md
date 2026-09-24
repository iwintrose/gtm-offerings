# TASK SCOPE — ISSUE #assessments-account-filters-apex

Provisioned by the Architect from `docs/architecture/gtm-filter-bar.md` Addendum C.10.3 (Release 3, Apex half). Authoritative contract: that addendum (on branch `agent/issue-compact-filters-docs-c10` until merged). This file is the Apex-only slice so the Developer can start before Release 1 finishes.

## 1. Requirements Breakdown

- **Target Objective:** the Assessments tab is folding "By Account or Contact" into its filters (user decision). Account and Contact become ordinary filters served by the server, because Assessments is server-paged (50 rows per fetch, cap 10,000) so the filter must be part of the Apex query. Options and search results may only ever contain accounts and contacts that have at least one assessment request visible to the user. The user approved this Apex change ("yes yes fold into full apex"), to be batched with the add-industry Apex change in one full-test-run deploy.
- **System Component Impacted (Apex ONLY in this worktree):** `force-app/main/default/classes/GtmAssessmentListController.cls` and `GtmAssessmentListControllerTest.cls`, plus a short addendum in `docs/architecture/gtm-assessments-table.md`. NOT in this worktree: `gtmReadoutsOverview`, `gtmAssessmentsTableModel`, `gtmFilterBar` (built later on top of Release 1's bar changes), and nothing under `gtmRepLinkFinder`.

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? NO tool is changed. `GtmActTodayController` (Overview tiles) and its test call `getAssessmentPage`; they must keep passing unchanged (the new `AssessmentQuery` members are optional/null-safe). Zero DML, zero callouts stays true for everything touched (AGENTS.md section 1 not triggered).
- [ ] Altering Custom Metadata? NO.
- [ ] Introducing database fields? NO. `Account__c`, `Contact__c`, `Company__c`, `Requester_Name__c`, `OwnerId` already exist on `GTM_Assessment_Request__c` and are already read. No permission-set change: `GtmAssessmentListController` is already listed in `GTM_Offering_Admin` and `GTM_Offering_User` (`apexClass` entries, line 86 of each), so new `@AuraEnabled` methods on it need no grant. Verify again before finishing.

## 3. Apex contract (exact)

### 3.1 `AssessmentQuery` and `Filters`
1. `AssessmentQuery` gains `@AuraEnabled public List<String> accountIds;` and `@AuraEnabled public List<String> contactIds;` (strings from the LWC).
2. `Filters` gains `List<Id> accountIds`, `List<Id> contactIds`. `normalise` converts each string with `Id.valueOf` inside `try/catch`; keeps only ids whose `getSobjectType()` is `Account` (respectively `Contact`); de-duplicates; keeps at most the first 50.
3. RULE (differs from status/tier, which drop unknown values then ignore the filter): if the input list is NON-EMPTY but yields NO valid id, set `f.impossible = true` (zero rows). A corrupted deep link must never show an unfiltered list under an "active" filter. A null or empty input list means no filter.
4. `filterSql` adds `Account__c IN :accountVals` and `Contact__c IN :contactVals` (ANDed with everything else; account and contact are ANDed with each other; values within each are ORed).
5. MANDATORY bind-variable discipline (the class comment already states it): `accountVals` and `contactVals` MUST be declared as locals with exactly these names in `queryVisible` AND in `ElevatedReads.queryOrphans`. A missing local is a runtime SOQL bind error, not a compile error. No user text is ever concatenated into SOQL.
6. Ownership and scope are UNCHANGED: `with sharing`, `OwnerId = :me` for non view-all users, the queue-orphan arm, view-all sees all. The new filters are extra conditions INSIDE the same predicate, never a replacement, so filtering by an account can never reveal another rep's request.

### 3.2 New options method
```apex
public class FilterOption {
    @AuraEnabled public String value;      // Id
    @AuraEnabled public String label;      // account name, or contact name
    @AuraEnabled public String sublabel;   // contact: company; account: null
}
@AuraEnabled   // NOT cacheable: options must reflect current data and scope
public static List<FilterOption> getAssessmentFilterOptions(String kind, String searchTerm, List<String> includeIds)
```
- `kind` is a whitelist: `'account'` or `'contact'`, mapped to CONSTANT field/relationship names; anything else returns an empty list. Field names are never built from user text.
- Scope: the SAME viewAll / `OwnerId = :me` / queue-orphan predicate as `getAssessmentPage`, via a private helper SHARED with it (extract the scope computation, do not copy it). The orphan arm reads only the Account/Contact ids of orphan requests through `ElevatedReads` (the only `without sharing` code), bounded by the orphan id set. `getAssessmentPage`'s behaviour must not change.
- ONLY parties with at least one visible request: aggregate over `GTM_Assessment_Request__c WHERE Account__c != null` (respectively `Contact__c != null`) plus the scope predicate, `GROUP BY Account__c, Account__r.Name` (respectively `Contact__c, Contact__r.Name, Company__c`), `ORDER BY` name, `LIMIT 50` (constant `FILTER_OPTION_LIMIT`). Grouping by a parent name is believed valid but UNVERIFIED offline; tested fallback: `GROUP BY Account__c` (or `Contact__c`) plus a bound `SELECT Id, Name FROM Account WHERE Id IN :ids` under `with sharing`, falling back to `Company__c` / `Requester_Name__c` when the name is not readable. NEVER list an account or contact that has no request.
- `searchTerm`: trimmed, at most 80 characters (truncate); blank returns the first 50 alphabetically. Applied as a BIND variable (`Account__r.Name LIKE :likeTerm OR Company__c LIKE :likeTerm` for accounts; contact name / company for contacts) where `likeTerm = '%' + escaped + '%'` and `%`, `_` and `\` in the term are escaped with `\` so a user cannot widen the match; a quote or SOQL fragment is inert text.
- `includeIds`: up to 50 ids from the URL. Also return those that are visible (unioned with the search hits, de-duplicated) so the LWC can label restored deep-link values; ids that are not visible or not of the right type are simply absent.
- Labels come from `Account__r.Name` / `Contact__r.Name` exactly as `toRow` already does, with the same `Company__c` / `Requester_Name__c` fallbacks (sharing and FLS parity with the rows).
- `AssessmentPage`, `AssessmentRow`, `offeringOptions` are unchanged.

## 4. Apex tests (`GtmAssessmentListControllerTest`; hermetic)

Create their own Account, Contact, requests and readouts inside the test; NO Migration Accelerator or other offering data; must pass with zero offerings and must not depend on org data. Reuse the existing helpers (`req`, `seed`, `createRep`, `ensureTriageQueue`, `query`, `ids`). Cases: account filter includes only matching rows; contact filter; account AND contact; AND with status and with a date range; several values OR within a filter; invalid ids dropped; all-invalid NON-EMPTY input returns zero rows while null/empty input is unfiltered; a wrong-type id (a Contact id in `accountIds`) is invalid; the 50-id cap; a rep never sees another rep's request through the new filters and never gets another rep's account/contact in the options (two users via `System.runAs`); a view-all user sees all; the queue-orphan arm for rows and for options; `getAssessmentFilterOptions`: returns ONLY accounts/contacts with a visible request (create an Account with no request and assert it is absent; same for a Contact); search match and no-match; `%` and `_` escaped (a term of `%` does not match everything); an injection string (`x' OR Name != '`) returns an empty list without an exception; LIMIT respected (seed more than 50 accounts); `includeIds` returns visible ones only and skips invalid/foreign ids; unknown `kind` returns empty; blank term returns alphabetical first 50; `getAssessmentPage` results for all existing tests are unchanged. `GtmActTodayControllerTest` must pass unmodified.

## 5. Plan Acceptance Criteria

- All new and existing tests in `GtmAssessmentListControllerTest` and `GtmActTodayControllerTest` pass; then the FULL local test run passes on `gtm-staging` (a deploy to the production-type `gtm-dev` runs every local test in the org, so every test must be self-contained, including the add-industry tests batched in the same deploy).
- `python3 scripts/check-references.py` not regressed; no permission-set, object, field or metadata change in the diff (`git diff --stat` shows only the two classes plus the docs addendum); no org IDs, usernames or secrets committed.
- **Test classes to run on gtm-staging:** `GtmAssessmentListControllerTest`, `GtmActTodayControllerTest`; then the full local suite (`--test-level RunLocalTests`) before any `gtm-dev` deploy.

## 6. Deployment rules

Never deploy from the worktree without the coordinator. `gtm-staging` first with `sf project deploy start --dry-run` (never `-c`) then the real deploy and the tests above; `gtm-dev` is Production and only under direct user authorisation, batched with the add-industry Apex change. The LWC half of Release 3 is a separate later branch.
