# Pages Industry filter source (gtm-industry-filter-source)

Status: contract, LWC-only change. Rep job: narrow my prospect pages by industry using the same names the Content Manager defined.

## Decisions

1. Options = industries DEFINED via the Add industry flow (`docs/architecture/add-industry.md`): Published + Active `industry-*` sections on framework `gtm` / `industry-chooser`. `value` = industry key (section key minus `industry-`; the value stored in `GTM_Saved_Configuration__c.Industry__c`), `label` = the industry's `industryLabel` (falls back to the key). Sorted by label.
2. Read: reuse `GtmPageContentReader.getIndustryProfiles('gtm', 'industry-chooser')` (`@AuraEnabled(cacheable=true)`, the same call `chooseIndustry` makes). The reader class is granted to all five permission sets including GTM_Offering_User (add-industry.md F/section 1), so any rep can call it. No new Apex, no schema or permission change. Industry definitions are shared framework config, so this is not filtered by owner; the LINKS stay owner-scoped by `getMyConfigurations`.
3. Undefined values: links whose `Industry__c` matches no defined industry are NOT their own options. A single option `Other` (value `__other__`) appears only when the filter has definitions and at least one link has a non-blank industry that matches none. Selecting Other matches exactly those links. Blank-industry links are never Other. Choice rationale: reps must still be able to find legacy or free-text links, without the raw lowercase codes returning.
4. No definitions (empty list, or the read failed): options are empty, so the existing hide-when-fewer-than-two-options rule in `gtmFilterBar` hides the filter. Nothing is invented; no Other.
5. Industry column (`industryLabel`): defined label when the value matches, else the raw `Industry__c`. `Industry_Label__c` is no longer used by this table.
6. Deep links: while the definitions have not returned (`industryProfiles === null`), raw `c__pindustry` values stay selectable so URL state is not dropped by the first sync. After load, options are only the defined ones; a stale deep-linked value not defined simply matches no link (or `__other__`).

## Contract

- `gtmRepLinkFilterModel.js`: `industryMap`, `industryDisplay`, `industryOptions(links, profiles, pendingRaw)`, `INDUSTRY_OTHER`; `buildExtraFilters(ctx.industries)`; `matchesExtra`/`filterLinks` take an optional trailing `industries`.
- `gtmRepLinkTableModel.js`: `buildRows(links, stats, industries)`.
- `gtmRepLinkFinder.js`: imperative `getIndustryProfiles` in `connectedCallback`, failure = empty list.

## Platform behaviour relied on (docs)

- `@AuraEnabled(cacheable=true)` methods can be called from LWC via `import x from '@salesforce/apex/Class.method'`: https://developer.salesforce.com/docs/platform/lwc/guide/apex-wire-method.html and https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_classes_annotation_AuraEnabled.htm
- Fetch status: both URLs returned HTTP 200 but are client-rendered pages, so page text could not be read here. The claims above are UNVERIFIED against the docs text; they match the existing in-repo pattern (`chooseIndustry` calls this same method).
- Class access is governed by permission-set Apex class access (repo check: the five sets list the reader).

## Tests

Jest: `gtmRepLinkFilterModel.test.js` (options, Other, none, label fallback, matching), `gtmRepLinkFinder.pagesFilters.test.js` (defined labels in options and column, Other filtering, empty, read failure).
