# Blank install and opt-in offering packs (contract)

Issue: site-shell-metadata (same PR, user request). Governs what
`scripts/deploy-fresh-org.sh` installs by default and how offering content is
added.

## 1. Rule

The default install is the FRAMEWORK ONLY: schema, code, UI, automation, access,
site shell. It contains no offering, no assessment/instrument data, no records.
Offering content is an explicit opt-in: `--with-offering <key>` (repeatable).

## 2. Offering packs

An offering pack is a manifest `scripts/offerings/<key>.manifest` listing
(a) customMetadata record files to deploy and (b) `data/seed/*.json` files to
load with `sf data tree import`. Pass 4 deploys only framework records by
default; each `--with-offering` adds that pack's files as a separate step after
pass 9 (records depend on schema only, so order is free, but they must follow
pass 7 access).

| Pack | customMetadata | Seed |
|---|---|---|
| framework (always, pass 4) | `GTM_Assessment_Config.Default` only | none |
| `migration-accelerator` | `GTM_Offering.Migration_Accelerator`, all `GTM_Assessment_Question/Pair/Dimension_Override/Supplement/Gate.*`, `GTM_Migration_Platform.*`, `GTM_Migration_Pair.*` (generated ones come from `instrument/migration-accelerator/`; never hand-edit them) | `data/seed/migration-accelerator.story.*.json`; `synthetic-demo.*.json` only behind a separate `--with-demo-data` |
| `test-offering` | `GTM_Offering.Test_Offering` | one clearly labeled test record |

Developer must confirm the framework/MA split by grepping each record's
references (e.g. that `Assessment_Config.Default` is not MA-specific).

## 3. Test Offering (proves the install)

- One `GTM_Offering__mdt` record, label `Test Offering`, key `test-offering`, no
  instrument. One `GTM_Page_Content__c`/`GTM_Page_Section__c` seed row keyed
  `test-offering`, text labeled `TEST RECORD - safe to delete`.
- Location: `test-fixtures/test-offering/main/default/...`, added to
  `sfdx-project.json` as a second, NON-default `packageDirectories` entry.
  Reason: `scripts/deploy.sh` (which reaches `gtm-prod`, treated as Production)
  builds its source list from `force-app/main/default/*`, so a test offering
  under `force-app` would ship to Production. Outside `force-app` it cannot.
- `check-references.py` must scan `test-fixtures/` too, so refs stay checked.

## 4. Zero-offering audit (Architect static findings, Developer to prove)

Static read: the Apex is largely offering-driven (`GtmPageContentController.
getOfferings()` returns the framework plus whatever `GTM_Offering__mdt` and page
rows exist; `isAssessmentAvailable` returns true with no instrument). Known
Migration Accelerator assumptions to verify or guard:
- `GtmAssessmentFrames.MIGRATION_ACCELERATOR` and the blank-key/"direct booking"
  fallback to `migration-accelerator` (`GtmAssessmentRequestController` ~1388,
  `GtmAssessmentScoring` ~420, `GtmEstateComplexity` ~198, `GtmReadoutModel`
  ~671): a blank/absent key resolves to an offering that will not exist.
- LWC `gtmStory.js` hardcodes `OFFERING_KEY = 'migration-accelerator'`.
- Apex tests that read MA custom metadata will fail on a blank org
  (`--run-tests`); the runbook must say tests need the MA pack, or tests are
  made self-contained. Developer reports which.
Acceptance: with only the framework and `test-offering` installed, the home
summary, offering chooser, page editor and a rep opening the app throw no error
and show `Test Offering`. Any hard failure is fixed or documented as a known gap,
not hidden.

## 5. Validating a blank install on gtm-staging (options; NO action taken)

gtm-staging already holds the MA custom metadata records from QA pass 4, so it
is not blank. Options for the human to choose:
- A. Fresh org (recommended): a new Developer/scratch org, alias `<new-alias>`.
  Cleanest, and it also proves the full fresh-org path end to end (incl. the site
  shell), which gtm-staging can no longer do because Network/site may already
  exist.
- B. Destructive change on gtm-staging removing the MA `customMetadata` records
  (`sf project deploy start --manifest package.xml --post-destructive-changes
  destructiveChangesPost.xml`, staging only, after the human OKs it). Faster, but
  the org is no longer a true fresh org; CMDT delete can also be blocked by
  dependencies, and it does not prove the site shell.
- C. Both: A for the acceptance proof, B skipped.

## 6. Implementation record (Developer, round 2)

- Packs: `scripts/offerings/migration-accelerator.manifest` and
  `scripts/offerings/test-offering.manifest`. Line kinds: `cmdt: <file or glob>`
  and `seed: <file>`. Pass 4 deploys only `GTM_Assessment_Config.Default`. Its
  `Lead_Source__c` value is the text "Migration Accelerator": a stored string,
  not a reference, so it is left in the framework.
- `--with-demo-data` runs `scripts/seed-synthetic-data.py --load`, separate from
  any pack; skipped under `--check-only`, as are all seed imports.
- Test fixture: `test-fixtures/` is a second, non-default `packageDirectories`
  entry; `check-references.py` scans it and fails if `scripts/deploy.sh` ever
  names it.

### Idempotent seeds

`sf data import tree` cannot upsert. `seed_import` in `deploy-fresh-org.sh` runs
`scripts/seed-precheck.py` first: one SOQL query per seed file on the object's
unique key (`Section_Address__c`, `Content_Address__c`). All present: skip, exit
0. None: import. Partial: warn and skip (no duplicates; missing rows not
created). Existing rows are never overwritten. Demo data is skipped when any
`Is_Synthetic__c` saved configuration exists. `check-references.py` requires
every seeded object to be in `UNIQUE_KEYS`, every row to carry a distinct key,
and the field to be unique in source.

### Production guard for layouts (user decision)

The four `Opportunity-*` layouts ship with the package with the five foreign
fields (`MainCompetitors__c`, `CurrentGenerators__c`, `OrderNumber__c`,
`TrackingNumber__c`, `DeliveryInstallationStatus__c`) stripped;
`Engagement_Link_Info__c` and all other placements are kept. The foreign
`<customLink>DeliveryStatus</customLink>` (an org-only WebLink; its "Custom
Links" section held nothing else) is removed from all four layouts, and
`check-references.py` blocks any `customLink`/`customButtons` that source does
not define. No other layout in `force-app` had a custom link or button; the
quick/platform actions on them are all standard names. A standard-object
layout REPLACES the target's own, so deploying the stripped files to `gtm-prod`
(Production) would remove those fields from its live layouts.
`scripts/deploy.sh` therefore skips the four `Opportunity-*` layouts when the
target alias is `gtm-prod` (case-insensitive, by alias as typed; a raw username
is not recognised) and deploys every other layout. `check-references.py` treats
any `__c` on any layout that source does not define as a blocker (no allowance
list).

### Zero-offering audit results (static; nothing was run against an org)

No hard failure was found, so no Apex/LWC was changed. Each item fails open:

| Assumption | Finding |
|---|---|
| `GtmAssessmentRequestController.resolveOfferingKey` (~1399) returns `migration-accelerator` for a blank offering | Returns a string only. Downstream resolution (`GtmAssessmentInstrument.resolve*`, `GtmAssessmentFrames.frameFor`) catches exceptions and falls back to a base pack or null frame. The pair-eligibility gate returns an inert verdict for any non-MA key. A direct booking with no offering records key `migration-accelerator`, an offering that is absent on a blank org: wrong label, no exception. Known gap; not a blocker. |
| `GtmAssessmentScoring` (~420), `GtmEstateComplexity` (~198) treat blank key as MA | Compiled MA dimensions/bands apply to a blank key only; a `test-offering` key gets neutral scale and no MA dimensions by design (ADR-0007). No throw. |
| `GtmReadoutModel.offeringKeyOf` (~660) falls back to MA for rows without a key | Used only when `Offering_Key__c` is blank on a stored request; a blank org has none. |
| `gtmStory` `OFFERING_KEY = 'migration-accelerator'` | Only the default of the `@api offeringKey`; the page sets it in Builder. With no MA rows `getPageLayout` returns nothing and the component keeps its built-in default sections. Renders, but with MA default text; a page for another offering must set `offeringKey`. Documented, not changed. |
| `GtmPageContentController.getOfferings()` | Framework plus every `GTM_Offering__mdt` and every page-only key: shows Test Offering. |
| Apex tests | 38 test classes reference MA custom metadata or MA types. `--run-tests` on a blank or Test-Offering-only org is expected to fail in those; runbook now says install the MA pack first. Not made self-contained (out of scope, large). |

Not verified: everything above is from reading code. Whether the home summary,
chooser and page editor render with only Test Offering has not been exercised in
an org; that is a QA check.
