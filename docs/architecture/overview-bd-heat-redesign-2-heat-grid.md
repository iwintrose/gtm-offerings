# "Who's hot right now" heat grid — data contract

Status: Accepted (issue `overview-bd-heat-redesign-2-heat-grid`, slice 2 of 4
of `ba-scope/issue-overview-bd-heat-redesign`)

## Problem

A rep opening the Overview needs "who should I call today", ranked by how
recently and how strongly each Account has engaged, not a flat list of
individual links or events. This slice adds a read-only per-Account/per-day
aggregation (Apex) and a heat-grid LWC that renders one row per Account,
sorted hottest first, each row showing a 14-day shaded activity strip, the
current tier, and a state-appropriate next action.

## Dependency status (checked at build time, 2026-09-22)

`agent/issue-overview-bd-heat-redesign-1-layout-toggle` has **not** merged to
`main` (only its scope-file commit exists on that branch). Per the Architect's
fallback instruction, the heat grid ships in this slice as a **self-contained
component** (`c/gtmHeatGrid`), not wired into `gtmOverview.html`. It is built
against the existing (pre-toggle) `GTM_Saved_Configuration__c` field shape so
slice 1's Today view can mount `<c-gtm-heat-grid>` directly once it merges,
with no contract changes expected. Integrating it into `gtmOverview` is a
follow-up step once slice 1 lands.

## Apex: `GtmLinkStageService.getHeatGrid()`

Lands as a new method (plus supporting inner classes) on the existing
`GtmLinkStageService`, reusing its `LinkFacts`-style tier vocabulary rather
than re-deriving tiers from scratch. `with sharing`, no DML, no callouts,
same owner/view-all scoping and `UNIVERSE_LIMIT` cap pattern already used by
`compute()`.

```apex
public class HeatDay {
    @AuraEnabled public Date day;         // trailing-14-day bucket, oldest first
    @AuraEnabled public String tier;      // 'none' | 'engaged' | 'started' | 'submitted'
    @AuraEnabled public Integer intensity; // 0-3, see "Intensity" below
}

public class HeatRow {
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public Id contactId;
    @AuraEnabled public String contactName;
    @AuraEnabled public Id opportunityId;
    @AuraEnabled public String opportunityStage;   // real Opportunity.StageName
    @AuraEnabled public List<HeatDay> days;        // always 14 entries, oldest -> newest
    @AuraEnabled public String latestSignal;       // e.g. "Assessment started 2 days ago"
    @AuraEnabled public Datetime latestSignalAt;
    @AuraEnabled public String currentTier;        // strongest tier reached in the window
    @AuraEnabled public Decimal heatScore;          // sort key, see "Sort order" below
    @AuraEnabled public String nextAction;          // 'call_now' | 'follow_up' | 'nudge' | 'schedule'
}

public class HeatGridResult {
    @AuraEnabled public Boolean truncated = false;
    @AuraEnabled public List<HeatRow> rows = new List<HeatRow>();
}

public static HeatGridResult getHeatGrid()
@AuraEnabled(cacheable=false) public static HeatGridResult getHeatGridAura()
```

### Universe

Same owner/view-all-scoped `GTM_Saved_Configuration__c` universe as
`compute()` (`Presentation_Stage__c` not null / not Draft / not Rep_Direct),
joined to `Account__c` (a config with no Account is excluded — a heat-grid
row is always a real Account, never a link/Company__c string). Multiple
configs/links for the same Account roll into ONE row; Contact and Opportunity
are the most-recently-created config's Contact/Opportunity among that
Account's configs (ties broken by config Id) — a rep works one relationship,
not one link.

### Per-day bucket shape (14-day trailing window)

- Window: `[today - 13, today]` inclusive, in the running user's time zone
  via `Date.today()` — 14 calendar-day buckets, oldest first, newest
  (today) last. `today` is `Date.today()` unless `nowOverride`
  (`@TestVisible`, mirrors `GtmLinkStageService.nowOverride`) is set.
- Edge behavior: a `GTM_Link_Event__c.CreatedDate` on day `today - 13` IS
  included (day 14 back, inclusive); a row from `today - 14` is NOT (day 15
  back, excluded) — this is the boundary the Apex test asserts explicitly.
- Each day buckets that day's events (scoped to the Account's configs) into
  the same tier vocabulary `LinkFacts` already uses:
  - `submitted` — a `Form Submitted` event that day, or a
    `GTM_Assessment_Request__c` created that day for one of the Account's
    configs.
  - `started` — a `Form Opened` or `Form Resumed` event that day (and not
    already `submitted` that day).
  - `engaged` — a `Page View` event that day (and not already `started`/
    `submitted` that day).
  - `none` — no matching event that day for this Account.
- `intensity` (0-3) is `tier` mapped to an ordinal (`none`=0, `engaged`=1,
  `started`=2, `submitted`=3) — the LWC's only job is picking a CSS shade per
  `intensity`, it does not re-derive tier ranking.

### "Latest signal" and current tier

`latestSignal` is the single most recent event across the whole trailing
14-day window (not just today), phrased as `"<Tier action> <relative day>"`,
e.g. `"Assessment submitted today"`, `"Page viewed 3 days ago"`. `currentTier`
is the strongest tier reached by that same most-recent event's day (ties
broken toward the stronger tier if two events land the same day).

### Sort order — "hottest first"

`heatScore` combines recency and strength: `tierWeight(currentTier) * 100 -
daysSinceLatestSignal`, where `tierWeight` is `submitted=3, started=2,
engaged=1, none=0`. Rows sort by `heatScore` descending, ties broken by
`latestSignalAt` descending, then `accountName` ascending. A submitted signal
from 5 days ago outranks a page view from today (strength beats raw
recency), but a page view from today outranks a page view from 10 days ago
(recency breaks ties within the same tier) — this is what "recency +
strength" means operationally.

### `nextAction`

Derived from `currentTier` + how stale `latestSignalAt` is:

- `currentTier == 'none'` or `engaged` and cold (no event in the trailing
  window, or oldest available signal) -> `call_now`.
- `currentTier == 'started'` (opened/resumed the form, has not submitted) ->
  `follow_up`.
- `currentTier == 'submitted'` and no readout sent yet -> `nudge` (OUT OF
  SCOPE this slice — see below).
- A row whose only feasible action would be a readout-schedule deep link ->
  `schedule` (OUT OF SCOPE this slice — see below).

`nudge` and `schedule` are real enum values the Apex method already returns
(so the follow-up ticket does not need an Apex contract change), but the LWC
renders BOTH as visibly disabled buttons with a tooltip citing
`gus-nudge-tool-and-readout-viewed-tracking`. No `GtmAppTool` is implemented
here.

### Test coverage (`GtmLinkStageServiceTest.cls`, new methods)

- 14-day window boundary: an event on `today - 13` is included; an event on
  `today - 14` is excluded (both asserted from the same seeded data set via
  `nowOverride`).
- Each tier bucket (`none`/`engaged`/`started`/`submitted`) resolves per-day
  independently of neighboring days.
- Multiple configs for one Account roll into one `HeatRow`.
- A config with no Account is excluded from the grid entirely.
- Sort order: a `submitted` row from several days ago outranks a same-day
  `engaged`-only row.

## LWC: `c/gtmHeatGrid`

Self-contained (no parent-supplied data): calls `getHeatGridAura()` itself on
`connectedCallback`, same imperative-not-wired pattern as
`GtmActTodayController.getActToday()` (time-dependent, `cacheable=false`).

- Account and Contact columns use `<c-gtm-link-cell>` directly (the shared
  cell component from PR #260), one instance per cell in a custom per-row
  markup — NOT a `<c-gtm-link-datatable>` `lightning-datatable` subclass,
  because the day-strip and action-button cells have no equivalent
  `lightning-datatable` base type and inventing custom `customTypes` entries
  for them would still need bespoke templates; reusing `gtmLinkCell`
  directly for exactly the two columns PR #260 governs keeps that one
  visual/behavioral contract (interactive vs. static styling, `rowaction`
  dispatch) without adding a parallel cell-type mechanism, satisfying "no
  reintroduction of the `type:'button'`-with-data-driven-`disabled`
  pattern" while still allowing the non-tabular parts of the row (heat
  strip, action button) to render as plain markup.
- Opportunity Stage renders the real `HeatRow.opportunityStage` value.
- The 14 day cells render `HeatDay.intensity` (0-3) as one of four CSS
  shade classes (`heat-cell--0` .. `heat-cell--3`); each cell's `title`
  states the date and tier for accessibility/hover.
- "Call now": opens the native Log a Call quick action
  (`lightning__quickAction` navigation, `Task.NewCall`), pre-filled with
  `WhoId` = Contact and `WhatId` = Opportunity from the row. No new Apex.
- "Follow up": calls a new, minimal Apex helper that inserts one `Task`
  (`WhatId` = Opportunity) — grepped first for an existing helper (only
  `GtmReadoutController.fileFollowUpTask` and
  `GtmAssessmentRequestController`'s Task inserts exist, both scoped to
  Assessment Requests, not Opportunities/heat-grid rows, so a new small
  helper method is added rather than reused/duplicated logic).
- "Nudge" (submitted rows) and the readout-schedule portion of "Book the
  call" (out of Apex `nextAction` scope for this slice's schedule case)
  render `lightning-button disabled` with `title`/`alternative-text`
  pointing at `gus-nudge-tool-and-readout-viewed-tracking` — always visible,
  never silently absent.

Jest specs (`c/gtmHeatGrid/__tests__/gtmHeatGrid.test.js`) cover: row
mapping from `HeatGridResult`, intensity-to-class mapping, disabled-nudge
tooltip rendering, and the Call now/Follow up action wiring.
