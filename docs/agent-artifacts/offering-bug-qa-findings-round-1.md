# QA round 1 — offering-creation bug fix (commit `7f73c75`)

**Reviewer:** QA agent (session `session_018UJzwgTCCMdESELzYMeWAZ`)
**Date:** 2026-09-07
**Scope:** `force-app/main/default/lwc/gtmContentHome/{gtmContentHome.js,gtmContentHome.html}`,
`force-app/main/default/classes/GtmPageContentController.cls`, plus the
`gtmContentManager` orientation-banner changes the plan (§4) required in
the same commit.
**Verdict: NOT APPROVED.**

---

## What was verified and is correct

1. **Reproduced the original bug.** Pre-fix `handleCreateOffering()`
   (`git show 31be003:.../gtmContentHome.js`, lines 275-291) clears
   `isLoading` only inside `.catch()` — confirmed exactly as the plan
   describes; the success path never resets the spinner flag.
2. **Client-side spinner fix is correct and traced end-to-end.** Current
   `gtmContentHome.js` (lines 276-301) moves `isLoading = false` into a
   single `.finally()` covering both branches, fires a success
   `ShowToastEvent` before navigating, and defers `openEditor()` one
   microtask (`Promise.resolve().then(...)`) past the modal-close writes —
   matching `handleGoToPage()`'s working shape as the plan specifies. This
   fix **is** live in `gtm-dev` (retrieved the deployed
   `gtmContentHome.js`; it matches the git source exactly, including the
   `ShowToastEvent` import and `Promise.resolve()` deferral).
3. **Orientation banner (`gtmContentManager`).** `c__new` is plumbed through
   `openEditor()` → `capturePageRef()` → `isNewOffering` → the
   `gcm-new-hint` block in `gtmContentManager.html` (placed correctly,
   after `gcm-error`, before the loading spinner), dismiss handler wired,
   CSS class present. The "don't reappear on later navigation" guard (the
   existing `if (offering === this._requestedOffering && template ===
   this._requestedTemplate) return;`) is real and does hold for the
   dropdown-switch-and-back case in the QA checklist (`handleOfferingChange`
   sets `selectedOffering` directly and never touches `NavigationMixin`, so
   the wire never re-fires). Not independently browser-verified (no
   browser available) — flagging that explicitly per the task's own
   instruction, but the code paths are sound.
4. **Scope is clean.** `git show --stat 7f73c75` touches exactly the 5
   files the plan calls for (`GtmPageContentController.cls`,
   `gtmContentHome.js`, `gtmContentManager.{js,html,css}`) — no collision
   with the concurrent Content Manager IA work (`6c75bae` touches only
   `gtmInstrumentAuthor`, an unrelated component).
5. **Jest:** `npm test` → 317 passed, 2 skipped, 0 failed. (No test exists
   yet for `gtmContentHome`, per plan §6.12 that was optional, not
   required — not a blocker.)
6. **Apex test suite:** `sf apex run test --target-org gtm-dev` → **541
   tests, 100% pass, 0 fail.** (No new Apex test for the
   discovered-offering fallback was added — also optional per the plan.)
7. **Permission sets:** confirmed untouched (`git show --stat 7f73c75`
   shows no `permissionsets/` files) — correct, this change adds no new
   object/field/tab.

---

## Ticket 1 — BLOCKER: the `GtmPageContentController.getOfferings()` fix is not actually deployed to `gtm-dev`

**Severity: Blocker.** The bug this fix targets (missing dropdown entry
for a freshly created offering) **is still live in production right now**,
despite the commit's own message claiming it was fixed and verified.

**How I found it (task item 3 — functional verification, not structural):**

Ran a real create through the actual Apex path, then called the actual
Apex read path, via `sf apex run` against `gtm-dev`:

```apex
String key = GtmPageContentController.createOffering('QA Verify Offering 9f3k');
List<GtmPageContentController.OfferingOption> opts = GtmPageContentController.getOfferings();
// ... check for key in opts
```

Result:
```
CREATED_KEY=qa-verify-offering-9f3k
OFFERINGS_COUNT=2
FOUND_IN_GETOFFERINGS=false
FOUND_IN_HOMESUMMARY=true
```

`getOfferings()` returned only 2 entries (framework + whatever
`GTM_Offering__mdt` already has) and **did not include the freshly
created offering** — the exact symptom the fix was supposed to resolve.
`getHomeSummary()` correctly found it (`FOUND_IN_HOMESUMMARY=true`),
confirming the *bug* reproduction is real and the *Home tab* half of the
app is fine — it's specifically the editor dropdown's data source that's
still broken live.

**Root cause, confirmed independently two ways:**

1. Live behavior above (2 results, offering missing).
2. Retrieved the actual deployed class from the org
   (`sf project retrieve start --metadata "ApexClass:GtmPageContentController"
   --target-org gtm-dev`) and diffed it against git `HEAD`
   (`force-app/main/default/classes/GtmPageContentController.cls`). **The
   deployed `getOfferings()` is the old, pre-fix version** — it ends at
   `return out;` right after the `GTM_Offering__mdt` loop (line 234 in the
   retrieved file). The entire "discovered offering" fallback block (the
   `known` set + `GROUP BY Offering_Key__c` query over
   `GTM_Page_Section__c`, ~25 lines) that exists in git `HEAD` is **absent**
   from what's live in the org.

The git source is correct (verified in the section above — it matches the
plan). The LWC half of this same commit (`gtmContentHome.js`) **is**
correctly deployed and live. Only the Apex class change from `7f73c75`
never made it to `gtm-dev` — i.e., this looks like a partial/incomplete
deploy after the commit, not a code defect. I did not attempt to diagnose
or fix why (out of QA's remit, and I was told not to fix issues myself),
but the fix is `git`-correct and functionally not live: `./scripts/deploy.sh
gtm-dev` (or at minimum `sf project deploy start --source-dir
force-app/main/default/classes/GtmPageContentController.cls
--target-org gtm-dev`) needs to actually run before this can be
re-verified and approved.

**Recommendation:** Deploy the class, then re-run the same `sf apex run`
functional check above (create → `getOfferings()` → confirm the new key
appears, 3 results not 2) before resubmitting for QA.

---

## Minor / non-blocking observation (not a ticket, worth Dev's awareness)

`isNewOffering` in `gtmContentManager.js` is a flat boolean, not scoped to
a specific offering key. If a user creates an offering (banner shows,
undismissed) and then picks a *different, pre-existing* offering from the
dropdown without dismissing the banner first, `handleOfferingChange()`
only sets `selectedOffering` — it doesn't touch `NavigationMixin` or
`capturePageRef`, so `isNewOffering` stays `true` and the "Offering
created" banner keeps showing against the wrong offering. This does not
break anything the QA checklist explicitly tests (dismiss-then-navigate
does behave correctly), and the plan's own bar ("a simple prompt beats
silence") is still met, so this is not blocking — flagging only so it
doesn't surprise anyone later.

---

## Test-data cleanup

Created one test offering via `sf apex run`
(`createOffering('QA Verify Offering 9f3k')` → key
`qa-verify-offering-9f3k`) purely to exercise the real Apex path per task
item 3. Deleted afterward via `sf apex run`: 3 `GTM_Page_Content__c` rows
+ 1 `GTM_Page_Section__c` row removed, confirmed 0 remaining for that key.
No `GTM_Offering__mdt` record was ever created for it (consistent with
§1 of the plan — CMDT is never written by `createOffering()`), so no
metadata cleanup was needed.

---

## Verdict

**NOT APPROVED.** Bug 1 (stuck spinner) and the orientation banner are
correctly fixed and live. Bug 2 (missing dropdown entry) is correctly
fixed *in source* but **not deployed** — the exact symptom PO reported is
still reproducible in `gtm-dev` right now. Send back to Dev to deploy the
class (or re-run the full pipeline's deploy step) and resubmit; QA will
re-run the same functional check.
