# GTM Analytics tab — v1 contract

Issue: [ps-salesforce/gtm-offerings#110](https://github.com/ps-salesforce/gtm-offerings/issues/110).
BA plan: https://claude.ai/code/artifact/10d15df9-7a08-4def-8058-a8bc54d11204

**Updated for issue #138.** The original v1 "assessments completed" metric
and tier mix were filtered on `GTM_Assessment_Request__c.Status__c =
'Completed'`. That field is a rep follow-up pipeline status
(`New/Contacted/Scheduled/Completed/No Show`), not a signal about assessment
completion — score and tier are computed and the record inserted the
instant a prospect finishes the questionnaire, with `Status__c = 'New'` at
that same moment. Fixed by collapsing "started"/"completed" into one real
step, "submitted," computing tier mix over every tiered request regardless
of `Status__c`, and surfacing the rep pipeline as its own field. The tables
below reflect the corrected contract.

Written before implementation per root `CLAUDE.md` §4 ("Contract First").
This is the source of truth for the Apex/LWC boundary — a change to either
side that drifts from this file is a blocked defect, not a judgment call.

## Scope

Rep-scoped (v1 only), read-only rollup of the caller's own
`GTM_Saved_Configuration__c` records and everything that traces back to
them. No new objects or fields. No DML.

## Objects read

| Object | Purpose here |
|---|---|
| `GTM_Saved_Configuration__c` | engagement links — volume, offering grouping |
| `GTM_Link_Event__c` | opens (funnel step 1), weekly trend |
| `GTM_Assessment_Request__c` | submitted count, score, tier, rep follow-up status |
| `GTM_Readout__c` | published count, time-to-publish |

## Apex — `GtmAnalyticsController`

```
@AuraEnabled(cacheable=true)
AnalyticsSummary getSummary(Date rangeStart, Date rangeEnd, String offering)

@AuraEnabled(cacheable=true)
List<OfferingRow> getOfferingBreakdown(Date rangeStart, Date rangeEnd)
```

Both are `with sharing`, no DML, scoped to `OwnerId = UserInfo.getUserId()`
on `GTM_Saved_Configuration__c`.

### `AnalyticsSummary`

| Field | Type | Meaning |
|---|---|---|
| `linksCreated` / `linksCreatedPrior` | Integer | links in range / equal-length prior period |
| `linksOpened` | Integer | distinct links with ≥1 `Page View`/`Form Opened` event |
| `assessmentsSubmitted` / `...Prior` | Integer | requests that exist for those links — the only real prospect-side completion signal |
| `readoutsPublished` / `...Prior` | Integer | `Status__c = 'Published'`, traced via the request |
| `avgDaysToPublish` / `...Prior` | Decimal | `Published_Date__c` − `Submitted_At__c`, averaged |
| `tierMix` | `List<TierCount>` | `{tier, count, pct}` over **every** tiered request, not filtered by `Status__c` |
| `followUpStatusCounts` | `List<StatusCount>` | `{status, count}` — the rep's own follow-up pipeline breakdown (`New/Contacted/Scheduled/Completed/No Show`) |
| `trend` | `List<TrendPoint>` | `{year, week, opens, submitted}`, calendar-week bucketed |

### `OfferingRow` (from `getOfferingBreakdown`)

`{offering, links, submitted, avgScore, published, topTier}`, sorted by
`published` descending.

## Metric formulas (binding — see TASK_SCOPE.md §1 for the same list)

- Engagement rate = `linksOpened / linksCreated`
- Submission rate = `assessmentsSubmitted / linksOpened`
- Publish rate = `readoutsPublished / assessmentsSubmitted`
- Avg. time to publish = mean(`Published_Date__c − Submitted_At__c`)
- Tier mix = share of `Assessment_Tier__c` among **all** requests with a
  tier set

**"Submitted" has no dedicated status value.** `GTM_Assessment_Request__c`
is only ever created, already scored and tiered, once a prospect finishes
the questionnaire (confirmed against `GtmAssessmentRequestController`), so
existence of the row *is* completion from the prospect's side.
`Status__c` on that object (`New / Contacted / Scheduled / Completed / No
Show`) is a **rep follow-up pipeline stage** the rep updates manually — it
is unrelated to assessment completion and must never be used to filter a
prospect-facing metric. It is its own field (`followUpStatusCounts`)
instead. (Issue #138 — the original v1 shipped with "Completed" doing
exactly the wrong thing here.)

## LWC — `lwc/gtmAnalytics`

Single component, five sections in one template (KPI row, trend, funnel,
tier mix, offering table) — no sub-component split for v1, matching this
app's own `gtmReadoutsOverview` convention of one component per tab rather
than a design-system layer. State (`rangeKey`) lives in the component;
both Apex calls are imperative, re-invoked on range change or manual
refresh — same convention as `gtmReadoutsOverview.handleRefresh`, chosen
over `@wire` because there is exactly one consumer of this data and no
other component needs to react to it changing.

## Explicitly out of scope for v1

- Offering/stage filter dropdowns beyond the date-range picker (BA plan
  phasing pushes finer filtering to v2's admin view).
- Cross-rep rollup (`GTM_Offering_Admin`) — separate method, separate
  sharing story, not a flag on these two.
- Any new schema. If v1's aggregate SOQL ever proves too expensive against
  real `gtm-prod` link volume, that is a v2 rollup-object conversation, not
  a mid-flight change here.

## v2 — `GtmAnalyticsTeamController` (issue #139, consolidated in #177)

A separate class, not a flag on `GtmAnalyticsController`: deliberately NOT
`OwnerId`-scoped, relying on `GTM_Offering_Admin`'s existing
`viewAllRecords=true` grants. Originally shipped as its own standalone
`GTM_Analytics_Team` tab; issue #177 folded it into `gtmAnalytics` as a
"My Analytics" / "Team" view toggle instead — it's the same Analytics
concept at a wider data scope, not a distinct feature. `hasTeamAccess()`
(a `PermissionSetAssignment` check) gates the toggle itself, so a rep never
sees it rather than seeing it fail. First pass ships
`getRepLeaderboard(rangeStart, rangeEnd)` only — instrument-version
comparison and flagged-assessment drill-in are tracked separately (#159,
#160).

## v3 — `GtmAnalyticsDigestJob` (issue #140)

A weekly `Schedulable` that emails each rep their own trailing-7-day
numbers, computed via `GtmAnalyticsController.summaryForOwner(ownerId,
rangeStart, rangeEnd, offering)` — the `getSummary()` body, extracted so
the digest can never drift into a second, independent metric definition.
**Not scheduled by any deploy step** — activating `System.schedule(...)`
in `gtm-prod` is a standing, org-mutating decision left to a human; see that
issue's `TASK_SCOPE.md` §5 for the one-line activation command.
