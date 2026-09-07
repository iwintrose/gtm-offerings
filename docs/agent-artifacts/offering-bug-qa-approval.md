# QA round 2 — offering-creation bug fix (commit `7f73c75`) — re-verification

**Reviewer:** QA agent (session `session_018UJzwgTCCMdESELzYMeWAZ`)
**Date:** 2026-09-07
**Scope:** same as round 1 — `gtmContentHome.{js,html}`,
`GtmPageContentController.cls`, plus the `gtmContentManager`
orientation-banner changes.
**Verdict: APPROVED.**

---

## Why round 1 said NOT APPROVED

Round 1 (`docs/agent-artifacts/offering-bug-qa-findings-round-1.md`)
retrieved the live `GtmPageContentController` class from `gtm-dev` and
found the discovered-offering fallback block absent, and confirmed it
functionally: `createOffering()` → `getOfferings()` returned 2 results,
missing the just-created offering. That was a real, reproducible read at
the time — not a misread on my part.

The Architect's read of the deploy timing (`LastModifiedDate` landing
between the fix commit and my findings commit) is consistent with what I
saw: I most likely retrieved the class mid-deploy, in the narrow window
between the org accepting a newer version and it fully taking effect for
subsequent Apex execution context, or I raced an in-flight redeploy. I
did not independently re-derive the timing mechanism (Setup UI /
Apex-class version history is not something I pulled for this pass) — I
am not vouching for the *explanation*, only for the fact that my original
observation is no longer reproducible, checked below independently, not
taken on the Architect's or Dev's word.

## Independent re-verification performed this pass

1. **Re-retrieved the live class from `gtm-dev`** (fresh
   `sf project retrieve start --metadata "ApexClass:GtmPageContentController"
   --target-org gtm-dev`, not reusing the earlier retrieve). Diffed
   against git `HEAD`'s `force-app/main/default/classes/
   GtmPageContentController.cls`: **identical** (only a trailing-newline
   difference). The discovered-offering fallback block (`known` set +
   `GROUP BY Offering_Key__c` over `GTM_Page_Section__c`) is present and
   matches source exactly.

2. **Re-ran the functional scenario myself, with my own new test
   offering** (not reusing Dev's or the Architect's data, so this isn't
   just re-reading someone else's result):
   ```
   String key = GtmPageContentController.createOffering('QA Reverify Offering 7c2m');
   List<GtmPageContentController.OfferingOption> opts = GtmPageContentController.getOfferings();
   ```
   Result:
   ```
   CREATED_KEY=qa-reverify-offering-7c2m
   OFFERINGS_COUNT=4
   FOUND_IN_GETOFFERINGS=true
   FOUND_LABEL=qa-reverify-offering-7c2m
   PO_MY_TEST_OFFERING_FOUND=true
   ```
   The new offering is found immediately, no hard refresh, label falls
   back to the key as designed (no CMDT record for it, matches the
   documented fallback convention). The PO's original `my-test-offering`
   (from the bug report, left in the org — not mine to touch) **also**
   now surfaces correctly through the same fallback, confirming Dev's
   re-test account.

3. **Duplicate check.** Listed all 4 returned offerings by key/label —
   `gtm` (framework), `migration-accelerator` (CMDT-backed, real label),
   `qa-reverify-offering-7c2m` (mine, fallback label), `my-test-offering`
   (PO's, fallback label). No key appears twice — confirms the
   `known`-set dedupe still holds correctly with a CMDT-backed offering
   and two discovered-only offerings coexisting.

## Test-data cleanup

Deleted my own test offering (`qa-reverify-offering-7c2m`) via
`sf apex run`: 3 `GTM_Page_Content__c` rows + 1 `GTM_Page_Section__c` row
removed, confirmed 0 remaining. Confirmed the PO's `my-test-offering`
rows were left untouched (1 section row still present after my cleanup
ran) — that record is not mine to delete.

## Everything else from round 1 stands unchanged

Spinner fix, toast, deferred navigation, orientation banner, Jest (317
passed), full Apex suite (541 passed, 100%), clean diff scope (only the 5
files the plan calls for), and no permission-set changes — all previously
verified and unaffected by this re-check.

---

## Verdict

**APPROVED.** The Apex fallback is confirmed live in `gtm-dev` right now,
independently re-verified with fresh source retrieval and a fresh
functional test — not accepted on the Architect's or Dev's report alone.
