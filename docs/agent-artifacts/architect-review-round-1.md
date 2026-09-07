# Architect review of QA round-1 findings

**Reviewer:** Architect agent (session `session_018UJzwgTCCMdESELzYMeWAZ`)
**Date:** 2026-09-07
**Scope:** Review of `docs/agent-artifacts/qa-findings-round-1.md` (commit `8cc9546`) against the plan (`architecture-doc-plan.md`) and the coordinator's independent org-level follow-up on Ticket 1.
**Verdict:** All 4 QA tickets confirmed as real, correctly-diagnosed issues. Ticket 1's fix is broadened per the coordinator's finding. One new ADR added to the rework scope. Nothing pushed back on.

I re-verified each ticket independently (not taking QA's or the coordinator's word) before endorsing: read `overview.md`'s diagram directly, grepped `CLAUDE.md`/ADR-0002 for the object-name drift, confirmed `HANDOVER.md`'s dropped content via `git show`, and — for the deepened Ticket 1 — confirmed `force-app/main/default/experiences/GTM1/{routes,views}/` has only `configurator.json` (plus Experience Cloud boilerplate: `login`, `search`, `error`, etc.) and no `assessment`/`readout`/`story`/`industry`, that `GTM_Accelerator1/routes/` has all four, and that `GTM1/views/configurator.json`'s only real component is `c:gtmConfigurator`. This matches the coordinator's report exactly.

---

## Ticket 1 — BLOCKING — ENDORSED, scope broadened

Confirmed exactly as filed: `overview.md` line 23 labels `GTM_Accelerator1` (`DownForMaintenance`) as *the* live guest site; the actually-live one is `GTM1` (`Live`, `gtm/s`), which currently has no assessment/readout/story/industry routes at all — only `/configurator`.

The coordinator's follow-up changes what "fixed" means here, and I agree with their read: **swapping the label from `GTM_Accelerator1` to `GTM1` in the same diagram shape would still be wrong.** The diagram currently implies one site hosts the whole prospect journey (story → questionnaire → readout). No site currently does that as a live, browsable set of routes — `GTM1` has only the configurator route, and whatever the prospect experiences beyond that is (per the coordinator's grep of `gtmConfigurator.js` finding no navigation to the other routes) self-contained inline on that one page, not a separate site journey. That's a materially different picture than the diagram currently draws, not a relabeling.

**Rework required, both parts in the same change:**

1. **Redraw the container diagram** to reflect current live topology accurately:
   - `GTM1` (Live, `gtm/s`) — only `/configurator` → `c:gtmConfigurator`. Note in the diagram or its prose that the assessment/readout experience, if reachable at all from here, is embedded inline within that one component — not a separate routed page — and that this has been confirmed from source (`gtmConfigurator.js` has no navigation to `assessment`/`readout`/`story`/`industry` routes) but **not** confirmed by actually loading the live page in a browser (browser automation is blocked in this environment — say so, don't imply more certainty than exists).
   - `GTM_Accelerator1` (`DownForMaintenance`, `gtmaccelerator/s`) — still shown, but clearly marked not-currently-live, as the site that *does* have the full built-out story/questionnaire/readout/industry routes. Don't delete it from the picture; a reader needs to know that code exists and where it lives, just not that it's reachable today.
   - Do not state or imply the assessment/questionnaire/readout feature is fully unreachable — that's not established either. State precisely what's verified (routes/components in source, no outbound navigation calls) versus what isn't (actual page load).
2. **Add a short "known gap" callout in `overview.md` prose**, near the diagram, pointing at `docs/backlog.md` D9 by name ("The Industry Chooser isn't reachable anywhere live... Not started") as the existing tracking for this, so a reader isn't left thinking the docs rebuild discovered a brand-new problem — it didn't; it inherited an already-tracked one and (correctly, per Ticket 1) had been describing it backwards.
3. **New ADR-0006** (see "New ADR" section below) — the general lesson, not just this one instance.
4. **One-line caveats on the two runbooks QA flagged as collateral** (`docs/runbooks/readout-public-link.md`, `docs/runbooks/questionnaire-resume.md`) — I'm overriding the plan's original "no changes needed" call for these two specifically, but keeping it narrow: **do not rewrite either runbook.** Their content about how the feature works (URL shape, security posture, token handling) is still accurate — it's describing real, deployed code. Add one sentence near the top of each: "This describes the `GTM_Accelerator1` site, which is not the currently-live site (`GTM1`) — see ADR-0006 and `docs/backlog.md` D9." That's the same banner-only treatment already established for the two stale specs in this doc set — consistent, not novel.

**Do not** fold this into a same-diff fix for D9 itself (building the missing routes onto `GTM1`) — that's an application change, not a docs change, and is explicitly out of scope for this pipeline. Documenting the gap accurately is in scope; closing it is not.

---

## Ticket 2 — SHOULD-FIX — ENDORSED, no reframing

Confirmed: `CLAUDE.md` line 89 says `Page_Content__c`/`Page_Section__c`; the real objects (confirmed against `force-app/main/default/objects/` and ADR-0002 itself, which gets it right) are `GTM_Page_Content__c`/`GTM_Page_Section__c`. Trivial, unambiguous fix — add the two missing `GTM_` prefixes. No judgment call involved.

---

## Ticket 3 — SHOULD-FIX — ENDORSED, no reframing

Confirmed: the plan's own `HANDOVER.md` disposition table (§3) committed to one of three fates for every durable fact in that file, and the `allowInternalUserLogin`/`GtmViewerContext.isRep()` gotcha landed in none of them — verified it's genuinely absent from `docs/`, `CLAUDE.md`, and `docs/backlog.md` via the same greps QA ran, and that `GtmViewerContext.cls` still exists (current code, not dead).

**Rework:** add as systemic gotcha #6 in `CLAUDE.md` §5 (after the sample-data one), pointing to the exact mechanism: `Network.allowInternalUserLogin` — deliberately excluded from the metadata deploy (a full `Network` file would clobber live site settings) — governs whether a logged-in internal user is served the site's guest experience instead of the rep experience; `GtmViewerContext.isRep()` is the code-side check. One sentence on the fix pattern (retrieve just that one field, edit, deploy back), since that's the actionable part.

**On QA's lower-confidence addendum** (the `gtmTokens`/`@import` CSS convention): I agree with QA's own instinct that this is lower-confidence *in-scope* material — it's a component-authoring convention, not an architecture/deploy gotcha, and the plan's `HANDOVER.md` disposition table didn't name it the way it named the `allowInternalUserLogin` fact. I'm not adding it to `CLAUDE.md`'s gotchas list. But it's cheap and real, so: if Dev is already touching `CLAUDE.md` §5 for gotcha #6, a single added sentence noting "shared `--gtm-*` CSS custom properties: `@import 'c/gtmTokens';`, don't redefine locally — they don't cross shadow-DOM boundaries between sibling LWCs" costs nothing and closes a real gap. Optional, not required for approval.

---

## Ticket 4 — NICE-TO-HAVE — ENDORSED, no reframing

Confirmed: ADR-0005 line 12 is missing an opening quote mark. Trivial typo, verified the underlying factual claim is correct (checked against `GtmAssessmentRequestController.cls`). Fix the quote; nothing else needed.

---

## New ADR-0006 — required for this ticket batch to close

**Title:** Route reachability is a property of the live site, not of the source tree.

**Context:** `GTM_Accelerator1` (down for maintenance) has the full built story/questionnaire/readout/industry Experience Cloud routes in source, deployed, and passing every static check (`check-references.py`, `check-content-contract.py`). `GTM1` (the actually-live site) has none of them. This isn't hypothetical: it's the exact gap this doc rebuild's own flagship diagram (Ticket 1) got backwards, and it's already independently tracked in `docs/backlog.md` as D9, unresolved. It rhymes with ADR-0002 (a field/object/tab can exist in metadata and still be invisible without the matching permission-set grant) but the root cause is different — this one is about which `ExperienceBundle` a route lives on and whether that site's `Network.Status` is `Live`, not about FLS.

**Decision:** A route, page, or component existing in `force-app/main/default/experiences/`, deploying cleanly, and even being wired into a specific site's views/routes is **not** evidence it's reachable by a real prospect. Before claiming (in docs, in a status report, or in code like `getSiteHomePageUrl()`) that a URL is live, verify **both** that the target site's `Network.Status` is `Live` (`sf data query -q "SELECT Name, Status, UrlPathPrefix FROM Network"`) **and** that the specific route exists on *that* site's `ExperienceBundle`, not just on some site.

**Consequences:** A "confirmed live" claim in a status report or a docs artifact now needs a live-org route check, not just a code/deploy check, before it's trusted — this is more verification work per claim, and worth it given this exact gap already produced an inverted-picture diagram once. `GtmSavedConfigurationController.getSiteHomePageUrl()` (used by `gtmOverview`'s "New engagement link" button and `gtmReadoutReview`) is a live example of code that returns a URL-shaped string without verifying the resulting page is actually reachable — worth a comment at that call site pointing here, though changing the method's behavior is out of scope for a docs ADR.

**Wire it in:** cite from `CLAUDE.md` gotcha #6 (or #7, after the `allowInternalUserLogin` one from Ticket 3 — Dev's call on ordering) and from `overview.md`'s D9 callout (Ticket 1, item 2 above).

---

## On the live real-company Account records (MUCH Music / TD Bank / Medtronic / LA Metro, no "(Demo)" suffix)

Not a doc-architecture bug and not something this pipeline should touch — agreed with the coordinator's call to escalate directly to the user rather than have Dev remediate org data unilaterally. It does earn one small addition, though: gotcha #5 in `CLAUDE.md` (sample data must be verifiably non-real) currently reads as a closed, past-tense lesson ("an earlier version used real names by mistake... don't reintroduce"). That's slightly misleading given there's a live, unremediated instance of exactly that problem sitting in `gtm-dev` right now, predating the fix. Add one sentence to gotcha #5: "As of 2026-09-07, `gtm-dev` still has four pre-existing Account records using real company names with no `(Demo)` suffix (`MUCH Music`, `TD Bank`, `Medtronic`, `LA Metro`, predating this fix) — flagged to the user, not yet remediated. Don't assume the org's data is already clean because the seed script is fixed." This is a nice-to-have, batch it with Ticket 4/2's small edits — not blocking, and Dev should not attempt to clean up those records as part of closing this.

---

## Summary handed to Dev

Fix, in one pass:
1. Ticket 1 (blocking) — redraw the diagram + D9 callout + runbook one-line caveats, per the broadened scope above.
2. Ticket 2 (should-fix) — `Page_Content__c`/`Page_Section__c` → `GTM_Page_Content__c`/`GTM_Page_Section__c` in `CLAUDE.md`.
3. Ticket 3 (should-fix) — new gotcha #6 (`allowInternalUserLogin`/`isRep()`), optionally the CSS token note.
4. New ADR-0006 (required to close Ticket 1 properly, not optional).
5. Ticket 4 (nice-to-have) — quote mark in ADR-0005.
6. Nice-to-have — one sentence on the live real-company Account records in gotcha #5.

Re-submit to QA for round 2 against this list — QA should re-verify Ticket 1's fix particularly carefully, since it's the one with the broadened scope and the new ADR.
