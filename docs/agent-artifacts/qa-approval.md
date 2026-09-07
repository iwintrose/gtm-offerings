# QA approval — round 2

**Reviewer:** QA agent (session `session_018UJzwgTCCMdESELzYMeWAZ`)
**Date:** 2026-09-07
**Scope:** Independent re-verification of `docs/agent-artifacts/qa-findings-round-1.md`'s 4 tickets, as reworked per `docs/agent-artifacts/architect-review-round-1.md`'s ruling, at commit `e3b381e`. Full fresh pass of plan §7 (`architecture-doc-plan.md`), not just the 4 tickets — full change surface confirmed via `git diff 8cc9546..HEAD --stat` (7 files: `CLAUDE.md`, `architect-review-round-1.md`, ADR-0005, new ADR-0006, `overview.md`, `questionnaire-resume.md`, `readout-public-link.md`; nothing else touched).
**Verdict:** APPROVED.

Every claim below was independently re-run against the live repo and the live `gtm-dev` org (`00DgK00000XZieHUAT`) — none taken on Dev's commit message or the Architect's review on their word alone.

---

## Ticket 1 (blocking, broadened) — verified fixed

- **Live org state, re-queried fresh:** `sf data query -q "SELECT Id, Name, Status, UrlPathPrefix FROM Network"` against `gtm-dev` — unchanged since round 1: `GTM` = `Live` (`gtm`), `GTM Accelerator` = `DownForMaintenance` (`gtmaccelerator`).
- **`docs/architecture/overview.md`'s container diagram** now shows `GTM1` (labeled `Live`) with only a `/configurator` route feeding `c:gtmConfigurator`, which in turn feeds two inline elements (`gtmConfigBooking` embedded modal, inline readout modal) — no fabricated `/story`/`/industry`/`/assessment`/`/readout` routes on the live site. `GTM_Accelerator1` is shown separately, visually dashed (`classDef notLive`), holding the full route set. I independently confirmed the underlying source claims, not just the diagram text:
  - `force-app/main/default/experiences/GTM1/routes/` still has only `configurator.json` + Experience Cloud boilerplate (no story/industry/assessment/readout) — re-listed fresh.
  - `grep` of `gtmConfigurator.js` for `NavigationMixin`/`generateUrl`/`.navigate(` → zero matches (only `window.location` reads for query params) — confirms "no navigation call to any other route."
  - `gtmConfigurator.html` embeds `<c-gtm-config-booking>` directly, and `gtmConfigBooking.js` imports and calls `GtmAssessmentRequestController.submitRequest` — confirms the "assessment intake is inline" claim.
  - `gtmConfigurator.js` itself imports and calls `getPublishedReadout`, and `gtmConfigurator.html` has an inline `modal--readout` dialog gated on `readoutViewOpen` — confirms the "inline readout modal" claim.
  - The diagram/prose correctly hedges: confirmed from source, explicitly **not** confirmed by an actual browser load (browser automation genuinely unavailable in this environment) — appropriately calibrated, not overclaimed.
- **"Known gap" callout** in `overview.md` cites `docs/backlog.md` D9 by name and quotes it — present and accurate (D9's text matches what's quoted).
- **`docs/architecture/adr/0006-route-reachability-is-a-property-of-the-live-site-not-of-the-source-tree.md`** exists, and its content matches the Architect's ruling: Context/Decision/Consequences in Nygard shape, states the two-part verification rule (`Network.Status` + route-on-that-bundle), names `GtmSavedConfigurationController.getSiteHomePageUrl()` as a live example. I verified its supporting factual claims independently: `getSiteHomePageUrl()` exists at line 482 of `GtmSavedConfigurationController.cls` and is called from both `gtmOverview.js` and `gtmReadoutReview.js`; `scripts/check-content-contract.py` exists.
- **Both runbook caveats** (`readout-public-link.md`, `questionnaire-resume.md`) — present, verbatim as the Architect specified, and `git diff` shows each runbook's change is *only* that one 3-line addition — no other edits snuck in under cover of this ticket.
- **Both Mermaid diagrams re-rendered by me, independently, from the round-2 file** with `@mermaid-js/mermaid-cli` (not trusting Dev's or my own round-1 render) — both produce valid, non-trivial SVG output with no errors.

## Ticket 2 — verified fixed

`CLAUDE.md` line 89 now reads `GTM_Page_Content__c`/`GTM_Page_Section__c` — `git diff` confirms this is the only change to that line. Matches ADR-0002 (unchanged, already correct) and the real object names in `force-app/main/default/objects/`.

## Ticket 3 — verified fixed, and independently checked for truth, not just presence

`CLAUDE.md` §5 gotcha #6 exists with the `Network.allowInternalUserLogin`/`GtmViewerContext.isRep()` content. I did not stop at confirming the text exists — I re-verified the claims themselves against the live org and current code, fresh:

- **`allowInternalUserLogin=true` on both sites, live, right now:** retrieved `Network:GTM` and `Network:GTM Accelerator` from `gtm-dev` via `sf project retrieve start` and grepped the retrieved `.network` files directly — both show `<allowInternalUserLogin>true</allowInternalUserLogin>`. Matches the gotcha's "It's `true` on both sites today" claim exactly.
- **`GtmViewerContext.isRep()`** — read the class directly: `return UserInfo.getUserType() == 'Standard';`. Matches the gotcha's description exactly.
- **The "why its own class" reasoning** (guest Apex access would otherwise have to go through `GtmSavedConfigurationController`, exposing `saveConfiguration`/`deleteConfiguration`/`searchContacts`) is consistent with that controller's actual method set (confirmed present in earlier passes).

**Dev's self-reported deviation (a) — gtmTokens/@import, re-verified:** `grep -rl "gtmTokens" force-app/main/default/lwc/` and a `find ... -iname "*gtmTokens*"` both return nothing — the component and every `@import 'c/gtmTokens'` reference genuinely no longer exist in the current LWC tree. Dev's claim that the pattern is gone (and its choice to skip the Architect's optional note rather than write a now-false one) is correct.

## Ticket 4 — verified fixed

ADR-0005 line 12 now reads `` `"Self-Estimated"` `` with the opening quote restored. `git diff` shows this is the only change to that file this round.

## Gotcha #5 addition and the live real-company Account records — independently re-verified

**Dev's self-reported deviation (b), re-verified against `gtm-dev` right now:** `sf data query` for `Account` `Name` in (`MUCH Music`, `TD Bank`, `Medtronic`, `LA Metro`) → zero records. Broadened to a `LIKE '%...%'` wildcard search on all four names → still zero records. Dev's claim that these four specific records no longer exist in the org is correct, and its choice to write a general caution in gotcha #5 rather than restate the Architect's now-false specific claim was the right call — writing the Architect's literal sentence would have put a false statement into `CLAUDE.md`. The sentence Dev did add is accurate and appropriately general.

## Full fresh pass of plan §7 (not limited to the 4 tickets)

Re-ran, from scratch, the checks that don't depend on this round's diff (files this round didn't touch, to catch incidental drift):

- **Structural:** `AGENTS.md` still a real symlink to `CLAUDE.md`; `HANDOVER.md` still absent; `docs/runbooks/experience-site-lifecycle.md` still present; `README.md` still clean of "Phase 1"/"Phase 2"/"ma-migrator"; both specs still carry their staleness banners.
- **Untouched-file guarantee, re-checked across the full history including this round:** `git diff 59566e8..HEAD --stat` on `MAINTAINERS.md`, `docs/backlog.md`, `docs/runbooks/assessment-instrument.md`, `docs/agent-artifacts/readout-lifecycle-walkthrough.html`, `index.html`, `migration-accelerator/` — zero changes on all of them, through both rounds.
- **Core facts still hold:** all 5 guest/rep Apex classes still exist; all 5 permission sets still exist (`ls` recount = 5).

No new issues found anywhere in the round-2 diff or in a fresh sweep of the previously-passing checks.

## What I could not independently verify (unchanged from round 1)

- End-to-end success of `deploy.sh`/`check-references.py`/a full Apex test run against `gtm-dev` — not executed (out of scope for a docs QA pass; declined to run `--run-tests` against the production-treated org unprompted).
- Actual browser-rendered behavior of `GTM1`'s `/configurator` page (the inline-embedding claim is source-verified, not browser-verified) — `overview.md` itself states this limitation accurately rather than overclaiming, which is the correct way to handle it, not a gap in my review.
- Org state (`Network.Status`, the Account records, `allowInternalUserLogin`) reflects 2026-09-07 at time of this check; it can change after this review closes.
