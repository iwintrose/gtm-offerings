# ADR-0004 — Dynamic Apex schema access in the instrument/scoring layer

**Status:** Accepted

## Context

Fields in and around the assessment/configuration layer get deleted and
recreated as the instrument and the underlying schema evolve — this is a
confirmed, ongoing pattern (see `docs/runbooks/assessment-instrument.md`'s
description of the YAML → custom-metadata build pipeline, and the `MA_` →
`GTM_` rename's own field-by-field churn in `docs/backlog.md`). A static
field reference (`cfg.Notify_Email__c`) fails to compile the moment that
field is renamed or removed, which blocks a deploy that would otherwise be
unrelated to that field entirely.

## Decision

`Schema.getGlobalDescribe()`/`newSObject()` and string-built `Database.query()`
are used deliberately in this layer instead of static field references,
trading compile-time safety for deploy resilience. Confirmed in the current
codebase via `grep -l "getGlobalDescribe\|Database.query(" force-app/main/default/classes/*.cls`:
`GtmAssessmentRequestController`, `GtmFormDraftController`, and
`GtmLinkEventController` (dynamic `SObject` construction via
`Schema.getGlobalDescribe()`), and `GtmFeedbackController`,
`GtmHomeSnapshotController`, `GtmLegacyConfigId`, and
`GtmStageActionsController` (string-built `Database.query()`). This list
will drift as the codebase changes — re-run that grep rather than trusting
this list verbatim.

## Consequences

- This code is harder to refactor with an IDE's "find references" — a
  rename of a field referenced only as a string literal in one of these
  classes will not show up as a usage anywhere else.
- A typo in a field API name inside one of these classes fails at runtime,
  not compile time, and only when that code path actually executes.
- This is a deliberate, scoped trade-off for this layer specifically — it is
  not a repo-wide pattern, and new Apex outside this layer should default to
  static field references unless it has the same "fields here churn" reason
  to do otherwise.
