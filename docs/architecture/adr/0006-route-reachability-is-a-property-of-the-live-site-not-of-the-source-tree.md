# ADR-0006 — Route reachability is a property of the live site, not of the source tree

**Status:** Accepted

## Context

`GTM_Accelerator1` (`Network.Status = DownForMaintenance`) has the full
built story/questionnaire/readout/industry Experience Cloud routes in
source, deployed, and passing every static check
(`scripts/check-references.py`, `scripts/check-content-contract.py`).
`GTM1` (`Network.Status = Live`, `urlPathPrefix: gtm`) — the site a real
prospect actually reaches — has none of them: its `routes/`/`views/`
contain only `/configurator` (plus Experience Cloud boilerplate:
`login`, `search`, `error`, and similar). This is not hypothetical — it is
the exact gap this documentation rebuild's own container diagram got
backwards in round 1 (see the "Known gap" callout in
`docs/architecture/overview.md`), and it is already independently tracked,
unresolved, in `docs/backlog.md` D9 ("The Industry Chooser isn't reachable
anywhere live... Not started").

The failure mode: a route, page, or LWC existing under
`force-app/main/default/experiences/`, deploying cleanly, and even being
wired into a specific site's `views`/`routes` JSON is not evidence a real,
unauthenticated visitor can reach it today. Reachability depends on which
`ExperienceBundle` the route lives on *and* whether that specific site's
`Network.Status` is `Live` — two facts that live outside `force-app/`
metadata (`Network.Status` is org state, not source-controlled, per
`DEPLOYMENT.md`'s "What a deploy can't do for you") and have to be checked
against the org directly, not inferred from the repo.

This rhymes with ADR-0002 (a field/object/tab can exist in metadata and
still be invisible without the matching permission-set grant) but the root
cause is different — ADR-0002 is about FLS; this one is about which site a
route is deployed to and that site's live/down status.

## Decision

Before claiming — in documentation, in a status report, or in code that
constructs a URL — that a route or page is live and reachable by a real
prospect, verify **both**:

1. The target site's `Network.Status` is `Live`:
   `sf data query -q "SELECT Name, Status, UrlPathPrefix FROM Network" --target-org <org>`.
2. The specific route/page actually exists on *that* site's
   `ExperienceBundle` (`force-app/main/default/experiences/<Site>/routes/`
   and `.../views/`), not merely on some site in the repo.

A route existing in source, or even being confirmed via static analysis
(`check-references.py`), answers a different question — "is this
deployed and internally consistent" — not "can a prospect reach it right
now." Don't conflate the two.

## Consequences

- A "confirmed live" claim now costs a live-org query, not just a
  source/deploy check — more verification work per claim, worth it given
  this exact gap already produced an inverted-picture container diagram
  once (round 1 of this documentation effort).
- `GtmSavedConfigurationController.getSiteHomePageUrl()` (used by
  `gtmOverview`'s "New engagement link" button and by `gtmReadoutReview`)
  is a live example of code that returns a URL-shaped string without
  verifying the resulting page is actually reachable on a `Live` site —
  worth a comment at that call site pointing at this ADR. Changing the
  method's behavior is out of scope here; this ADR documents the gap, it
  doesn't close it.
- Closing the underlying gap (building the missing routes onto `GTM1`) is
  an application change tracked separately as `docs/backlog.md` D9 — not
  something this ADR, or the documentation set it lives in, resolves.
