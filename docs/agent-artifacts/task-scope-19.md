# TASK SCOPE — ISSUE #19

## 1. Requirements Breakdown

- **Target Objective:** `GtmAgentGetConfigState.buildOutput()` (the Apex
  invocable action backing GUS's "Get GTM Configurator State" tool) must stop
  reporting Draft-status industries in its `availableIndustries` output. Today
  it queries `GTM_Page_Content__c` for `industry-%` section keys filtered only
  on `Active__c = true` (force-app/main/default/classes/GtmAgentGetConfigState.cls,
  lines 92-100):

  ```apex
  List<GTM_Page_Content__c> iRecs = [
      SELECT Section_Key__c
      FROM   GTM_Page_Content__c
      WHERE  Offering_Key__c  = :GtmPageContentController.FRAMEWORK_KEY
      AND    Template_Type__c = :INDUSTRY_TEMPLATE
      AND    Section_Key__c LIKE 'industry-%'
      AND    Active__c = true
      LIMIT  200
  ];
  ```

  This has no join to `GTM_Page_Section__c.Status__c`, so an industry whose
  section is still Draft (created but not yet Published in the industry
  chooser) leaks into GUS's tool-surface data, letting the assistant tell a
  rep an unreleased industry is available.

  `GtmPageContentReader.getIndustryProfiles()` in the same repo
  (force-app/main/default/classes/GtmPageContentReader.cls, lines 440-507)
  already solves this exact problem correctly, for the same
  `industry-<key>` section-key convention. Its pattern (lines 450-463):

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
  ]) {
      liveKeys.add(sec.Section_Key__c);
  }
  if (liveKeys.isEmpty()) return out;
  // ... GTM_Page_Content__c query below adds: AND Section_Key__c IN :liveKeys
  ```

  i.e. it first builds a `liveKeys` set from `GTM_Page_Section__c` filtered on
  `Active__c = true AND Status__c = 'Published'`, then only reads
  `GTM_Page_Content__c` rows whose `Section_Key__c` is in that live set.

  **The fix is to replicate this exact two-step pattern (query
  `GTM_Page_Section__c` for `Active__c = true AND Status__c = 'Published' AND
  Section_Key__c LIKE 'industry-%'` under the same `Offering_Key__c =
  GtmPageContentController.FRAMEWORK_KEY` / `Template_Type__c =
  INDUSTRY_TEMPLATE` scope, collect the live `Section_Key__c` set, then add
  `AND Section_Key__c IN :liveKeys` to the existing `GTM_Page_Content__c`
  query) inside `GtmAgentGetConfigState.buildOutput()`.** No new object,
  field, or LWC is involved. This is confirmed to be a small, well-bounded
  fix — mirroring one already-correct query pattern from
  `GtmPageContentReader` into a second class that reads the same taxonomy
  under the same section-key convention. It is not being over-scoped beyond
  that.

  Note for the Architect/Developer: `GtmPageContentReader.getIndustryProfiles`
  takes `offeringKey`/`templateType` as parameters, while
  `GtmAgentGetConfigState` hardcodes `GtmPageContentController.FRAMEWORK_KEY`
  and the local `INDUSTRY_TEMPLATE` constant — the new
  `GTM_Page_Section__c` query in `GtmAgentGetConfigState` should use those
  same two hardcoded values (not introduce parameters), to stay consistent
  with how the rest of that method already scopes its `GTM_Page_Content__c`
  query.

- **System Component Impacted:** Apex (`GtmAgentGetConfigState.cls`) — the
  GUS Tool Surface / Agentforce invocable-action layer. No LWC, Experience
  Cloud route, or YAML instrument is touched.

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? **YES.** `GtmAgentGetConfigState` is the
  `@InvocableMethod` class backing GUS's "Get GTM Configurator State" tool
  (both the custom-proxy path via `GtmAgentConfigActions`/tool registration
  and the native Agentforce path via this invocable method). Verified against
  AGENTS.md §1's zero-DML/zero-callout rule
  (`GtmAgentToolSurface.cls` comment: "No DML or callouts inside a tool
  implementation — tools read/propose, they don't write directly"; AGENTS.md
  line 105: "The Propose-vs-Commit Contract... no-DML/no-callout-inside-a-tool
  contract"). The fix is a read-only SOQL query addition (a second
  `GTM_Page_Section__c` SELECT, same shape as the existing
  `GTM_Page_Content__c` SELECT already in this method) — it introduces no
  DML and no HTTP callout, so it is compliant by construction. No change to
  the class's `with sharing` declaration, its `@InvocableMethod` signature,
  or its `Input`/`Output` shape is needed.
- [ ] Altering Custom Metadata? No. This method reads `GTM_Page_Content__c`
  and `GTM_Page_Section__c` custom **objects** (standard SObjects backing the
  Content Manager's authoring UI), not Custom Metadata Types. No YAML
  instrument or `force-app/main/default/customMetadata/GTM_Assessment_*`
  file is touched.
- [ ] Introducing database fields? No. `GTM_Page_Section__c.Status__c` and
  `.Active__c` already exist and are already readable by whatever profile can
  currently execute `GtmAgentGetConfigState` (Agentforce runs as the
  automated process/bot user; the custom-proxy path runs as the invoking
  rep, same as today's `GTM_Page_Content__c` query on the same object
  family). No permission-set mapping change is required — this only adds a
  second read of a field family already exposed to the same users this class
  already serves.

## 3. Plan Acceptance Criteria

- **Success Metric:** With a `GTM_Page_Section__c` industry section whose
  `Status__c = 'Draft'` (Active__c = true) present alongside Published
  industries under `Offering_Key__c = GtmPageContentController.FRAMEWORK_KEY`
  / `Template_Type__c = 'industry-chooser'`, calling
  `GtmAgentGetConfigState.execute()` must return `availableIndustries` that
  excludes the Draft industry's key and includes only Published-and-Active
  industry keys — matching what `GtmPageContentReader.getIndustryProfiles()`
  would independently report as "live" for the same taxonomy. A Published
  industry must still appear (no over-filtering / no regression to zero
  results).
- **Target Test Target:** A new or extended Apex test method in the test
  class covering `GtmAgentGetConfigState` (confirm/create
  `GtmAgentGetConfigStateTest.cls` under
  `force-app/main/default/classes/`) asserting `availableIndustries` excludes
  a Draft-status industry section and includes a Published one, given seeded
  `GTM_Page_Section__c` + `GTM_Page_Content__c` records for both. Run via
  `sf apex run test --class-names GtmAgentGetConfigStateTest` (validate-only
  against `gtm-staging`; no `gtm-prod` deploy without the owner's explicit
  go-ahead, per CLAUDE.md §5 and AGENTS.md's promotion flow).
