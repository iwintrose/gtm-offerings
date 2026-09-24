# TASK SCOPE — ISSUE #159-instrument-version-comparison

## 1. Requirements Breakdown

- **Target Objective:** Give a content/GTM admin a way to see, per offering, how different `Instrument_Version__c` editions of the assessment (within the same `Instrument_Pair__c` pack) compare in outcomes — i.e. is a newer instrument version converting better or worse than the one it replaced. This is the deferred "instrument-version comparison" piece explicitly called out in `GtmAnalyticsTeamController`'s class doc as a follow-up to #139/#145, and is now unblocked (no new schema, no design forks — GitHub issue #159 explicitly frames the remaining choices, new method vs. sibling class, response shape, new panel vs. toggle, as normal Architect-level calls).
- **System Component Impacted:** Apex (new `@AuraEnabled` method, most naturally added to `GtmAnalyticsTeamController` alongside `getRepLeaderboard()` since it shares the same access boundary/class-doc note, or a sibling class if the Architect judges the controller is getting too large) + LWC (`gtmAnalyticsTeam` — extend with a second panel/section, following the existing "Leaderboard" panel pattern in `gtmAnalyticsTeam.html`/`.js`). No Experience Cloud or YAML instrument changes; no new Custom Metadata.

### Concrete data/shape proposal (grounded in what actually exists today)

Verified via `GtmAssessmentScoring.cls` (score() persisting `pack.pairKey`/`pack.version` into `out.instrumentPairKey`/`out.instrumentVersion`) and the `GTM_Assessment_Request__c` field metadata:

- `Instrument_Pair__c` (Text 80) — DeveloperName of the `GTM_Assessment_Pair__mdt` pack (e.g. `hubspot__mcn`). This is the grouping key that identifies "the same instrument" across versions.
- `Instrument_Version__c` (Text 40) — the edition of that pack at scoring time. This is the comparison axis within a pair.
- `Assessment_Score__c` (Number, already used by `getRepLeaderboard`'s `avgScore` rollup) and `Assessment_Tier__c` (restricted Picklist: Discovery First / Prep Required / Accelerator-Ready / Fast-Track) — both nullable per `Score`'s own doc comment (null when unscored or when the unsupported-pair gate suppresses banding), so any rollup must treat "no score/tier" as its own bucket, not silently drop those rows or coerce to zero.
- `GTM_Readout__c.Status__c = 'Published'` joined via `Assessment_Request__c`, exactly as `publishedCountFor()` already does — this is the existing "conversion" signal (submitted → published) and should be reused rather than re-derived.

Proposed new method: `getInstrumentVersionComparison(Date rangeStart, Date rangeEnd)` returning `List<InstrumentVersionRow>`, one row per distinct `(Instrument_Pair__c, Instrument_Version__c)` combination seen on `GTM_Assessment_Request__c` records whose `CreatedDate` falls in the range (same windowing convention as `getRepLeaderboard`, i.e. `[rangeStart 00:00, rangeEnd+1 00:00)`), each row carrying:

- `pairKey` (String) — `Instrument_Pair__c`, or a literal sentinel such as `'(unset)'` for legacy/pre-pack rows where it is null, so those rows are visible rather than silently excluded.
- `version` (String) — `Instrument_Version__c`, same null-handling as above.
- `submitted` (Integer) — count of requests in that group (mirrors `RequestRollup.submitted`'s "submitted = request exists" semantics per issue #138).
- `avgScore` (Decimal, nullable) — average of non-null `Assessment_Score__c` in the group, `.setScale(1)`, same as `getRepLeaderboard`; null (not 0) when every row in the group is unscored, to keep "not assessed" distinguishable from "assessed at the floor" per the `Score` class doc.
- `tierCounts` (Map<String, Integer> keyed by the four tier labels plus an `'Unscored'`/advisory bucket) — so the UI can show a tier distribution per version, not just an average.
- `published` (Integer) — count of `GTM_Readout__c` with `Status__c = 'Published'` linked to requests in the group, reusing `publishedCountFor()`.
- `publishRate` (Decimal, nullable) — `published / submitted` as a percentage, null when `submitted = 0` (should not occur given the row only exists because requests were found, but guard anyway).

Sort: by `pairKey` then `version` descending (newest first) so an admin reading top-to-bottom sees the newest edition of each pair first, adjacent to the version(s) it replaced.

UI: extend `gtmAnalyticsTeam` with a second `panel table-panel` block below (or beside, via a toggle) the existing leaderboard, titled e.g. "Instrument versions, by pair" with columns Pair | Version | Submitted | Avg. score | Tier mix | Published | Publish rate. Reuse the existing `rangeKey`/`currentRange()` control already on the component rather than adding a second date picker — Architect should confirm whether the two panels share one range control or get independent ones.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No — this is the admin analytics rollup (`GtmAnalyticsTeamController`/`gtmAnalyticsTeam`), not the GUS chat tool surface. If the Architect chooses to add a new sibling Apex class, it still must remain a pure read-only SOQL/AggregateResult rollup with **zero DML**, matching the existing class's own "No DML anywhere" guarantee (AGENTS.md §1 zero-DML rule applies to any GUS-adjacent tool surface; this class is not GUS-facing but the no-DML discipline should be preserved regardless).
- [ ] Altering Custom Metadata? No — `Instrument_Version__c`/`Instrument_Pair__c`/`Instrument_Branch_Path__c` already exist and are already populated; this issue is pure aggregation/read logic against existing data. No `migration-accelerator/` YAML changes, no XML metadata edits.
- [ ] Introducing database fields? No — no new schema. Because no new field/object is introduced, no new Permission Set field mapping is required. Access continues to ride on the existing `hasTeamAccess()` gate (`GTM_Offering_Admin` assignment) and that permission set's existing `viewAllRecords=true` grants on `GTM_Assessment_Request__c`/`GTM_Readout__c` — the same boundary `getRepLeaderboard()` already relies on. No permission set file changes are expected unless the Architect decides the new method needs a distinct Apex class requiring its own class-access grant, in which case that grant (not a field) is the only permission-set touchpoint to check.

## 3. Plan Acceptance Criteria

- **Success Metric:** An admin user (assigned `GTM_Offering_Admin`) viewing the Team analytics surface can select a date range and see, per `(Instrument_Pair__c, Instrument_Version__c)` combination active in that range, submitted count, average score, tier distribution, and publish rate — allowing a visual/numeric comparison between a newer instrument version and the one it replaced for the same pair. A non-admin user does not see this panel (same `hasTeamAccess()` gate as the existing leaderboard). Groups with null `Instrument_Pair__c`/`Instrument_Version__c` (legacy rows) are visible under an explicit "(unset)" bucket rather than silently dropped. An empty range/no data shows the same empty-state pattern the leaderboard panel already uses, not an error.
- **Target Test Target:** `GtmAnalyticsTeamControllerTest.cls` (extend with new test methods covering: multiple pairs/versions grouped correctly, null-pair/version rows bucketed as "(unset)" rather than dropped, unscored requests handled without corrupting `avgScore`, publish-rate computation, and the `hasTeamAccess()` gate applied to the new method) and `force-app/main/default/lwc/gtmAnalyticsTeam/__tests__/gtmAnalyticsTeam.test.js` (extend with Jest coverage for the new panel's render/empty/error states, run via `npm test`).
