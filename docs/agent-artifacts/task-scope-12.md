# TASK SCOPE — ISSUE #12

## 1. Requirements Breakdown

- **Target Objective:** Issue #12 asks for the Content Manager "Add industry" modal (LWC) that calls the already-built `GtmPageContentController.createIndustry(label, fields)`. **Verified finding: this is already fully implemented on `main` and should NOT be re-built.** Evidence:
  - `force-app/main/default/classes/GtmPageContentController.cls:727` — `createIndustry` method exists, matching the contract in `docs/architecture/add-industry.md` §2.
  - `force-app/main/default/classes/GtmPageContentReader.cls:297-319` — `getIndustryProfiles` already has the two-query Published/Active join described in `docs/architecture/add-industry.md` §3 (comment in the code literally references "exactly as `getPageLayout` decides").
  - `force-app/main/default/lwc/gtmContentManager/gtmContentManager.html:251,255,371` and `gtmContentManager.js:14,858,884` — the rail-foot "Add industry" button (swapped in on the Industry Chooser page), the modal, `handleOpenAdd`, and the `createIndustry` Apex import/call are all present, matching `docs/architecture/add-industry.md` §5 including the exact `.then/.catch/.finally` chain in §5's Call block.
  - `force-app/main/default/lwc/gtmContentManager/__tests__/gtmContentManager.test.js`, describe block `"c-gtm-content-manager: Add industry (issue add-industry)"` — 10 tests covering every acceptance criterion in `docs/architecture/add-industry.md` §5 and §9 (button swap, modal states, 71-char slug cap, duplicate refusal, similar-label warning, success and server-error paths). Ran locally: **10 passed, 0 failed** (`npx jest .../gtmContentManager.test.js -t industry`).
  - History: `git log --oneline -- force-app/main/default/classes/GtmPageContentController.cls` shows only `2077c90 Initial import: current state of GTM Offerings main` — i.e. this landed as part of the repo's reconstructed history, not as new work still to do. `git log --all --oneline` shows a `merge: add-industry into staging-restore-integration` commit (`da92243`), which was folded into `main` via `f815a2e Merge pull request #251 from ps-salesforce/agent/issue-staging-restore-integration` (`git merge-base --is-ancestor` confirms PR #251's tree is on `main`).

- **PR #240 blocker — verified stale, not a real blocker.** `gh pr view 240 --repo iwintrose/gtm-offerings` returns `Could not resolve to a PullRequest with the number of 240`. However `git log --all --oneline` finds the actual commit that PR referenced: `daf2aba fix(lwc): browser-followups Part A - instrument header, job label, Content Manager hint (#240)`, on `origin/agent/issue-browser-followups`. `git merge-base --is-ancestor daf2aba HEAD` returns **false** — that specific browser-followups branch/commit is NOT on `main` today. So: PR #240 (as a live GitHub PR object) is gone/renumbered in this reconstructed repo, but the change it made (Part A: instrument header, job label, Content Manager Framework-only hint) is a *different* feature entirely from add-industry, and it never overlapped with the add-industry LWC code path in a way that blocked it — the add-industry work is already merged into `main` regardless of #240's status. **Conclusion: whatever #240 was meant to unblock is moot — the LWC modal this issue asks for already exists and already passes its tests.** There is no live blocker to resolve.

- **System Component Impacted:** None — no code change is required for the literal ask in issue #12. The only impacted "component" is the GitHub issue's own state (should be closed as already-done) and this scope doc.

- **Ambiguity / decision the human owns:** Since the LWC modal is already built and tested, this scope doc recommends **closing issue #12 as already resolved**, rather than routing it to an Architect/Developer for a rebuild. That is a judgment call (closing an issue vs. leaving it open pending a formal QA sign-off) that the coordinator/owner should confirm before closing on GitHub — I have not closed the issue myself, only documented the evidence.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **No.** `createIndustry` is confirmed not called by any GUS tool (`docs/architecture/add-industry.md` §2 explicitly notes "Not called by any GUS tool ... zero-DML surface untouched"); nothing in this scope adds a GUS tool call.
- [ ] Altering Custom Metadata? **No.** No YAML/metadata changes are proposed.
- [ ] Introducing database fields? **No.** No new fields/objects; the existing implementation added no schema per `docs/architecture/add-industry.md` §2 ("No object, field or permission-set change").

## 3. Plan Acceptance Criteria

- **Success Metric:** No new Developer work is required for the LWC modal itself. Before this issue is closed, the following must be confirmed on `gtm-staging` (per `docs/architecture/add-industry.md` §6, the mandatory pre-check gate before any `gtm-prod` deploy — copy the three read-only `sf data query` commands from that section, run Q1-Q3 against `gtm-staging`, and require Q1 to return zero rows and every Q3 group to appear in Q2 before any `gtm-prod` deploy of this reader behavior is considered):
  1. `npm test` passes for `gtmContentManager` (already verified locally: 10/10 industry-specific tests pass).
  2. The QA gate in `docs/architecture/add-industry.md` §13 (class-access / `FieldSeed` deserialization check for a GTM_Offering_Admin-only user) has not yet been recorded as run on `gtm-staging` — this is the one open item blocking a confident "fully done" sign-off, not missing code. Whoever closes this issue should confirm §13 step 2 has been executed, or explicitly accept the documented interim limit ("LWC part may merge for Content Manager and Content Admin users only" until step 2 is recorded).
- **Target Test Target:** `force-app/main/default/lwc/gtmContentManager/__tests__/gtmContentManager.test.js` (describe: "Add industry (issue add-industry)"), and `force-app/main/default/classes/GtmPageContentControllerTest.cls` for the Apex side of the contract. No new test target needs to be created for this issue.

## 4. Follow-up gap decision — GtmAgentGetConfigState Draft-industry leak

**Verified still present and NOT fixed by the current implementation.** `force-app/main/default/classes/GtmAgentGetConfigState.cls` lines ~92-99 query `GTM_Page_Content__c` directly for `industry-%` section keys with only `Active__c = true`, with **no join to `GTM_Page_Section__c.Status__c`**:

```apex
List<GTM_Page_Content__c> iRecs = [
    SELECT Section_Key__c
    FROM   GTM_Page_Content__c
    WHERE  Offering_Key__c  = :GtmPageContentController.FRAMEWORK_KEY
    AND    Template_Type__c = :INDUSTRY_TEMPLATE
    AND    Section_Key__c LIKE 'industry-%'
    AND    Active__c = true
    LIMIT  200
];
```

This is exactly the gap `docs/architecture/add-industry.md` F5 flags as "UNVERIFIED... out of scope" for the original add-industry task, and the issue #12 body explicitly calls it a "known follow-up gap." Consequence: a brand-new, unpublished (Draft) industry — created via the now-confirmed-working "Add industry" modal but never Published — will leak into `GtmAgentGetConfigState.availableIndustries`, so GUS can offer/reference an industry the public site does not yet show.

**Decision: this is a separate follow-up, not in scope for issue #12.** Reasoning:
- Issue #12's own body scopes it as "the LWC modal," and the modal is done; the config-state fix touches a different class (`GtmAgentGetConfigState.cls`) with a different call path (GUS agent tool, not the Content Manager LWC), a different owner/reviewer concern (GUS tool-surface changes get extra scrutiny per `AGENTS.md` §1's zero-DML rule — this read-only fix doesn't add DML, but it does change what a GUS-facing tool returns, which warrants its own scope doc and its own Architect/Developer/QA pass rather than folding it in silently).
- Trade-off of NOT fixing it now: the leak persists a while longer, and if content editors are actively drafting new industries, GUS could recommend/reference an industry a prospect can't yet see on the public page (a can't-click-nonexistent-tile inconsistency, not a data-integrity or security issue).
- Trade-off of fixing it in-issue: would silently expand issue #12's blast radius beyond what it was filed for, and risks conflating "LWC modal done" with "closed" when a genuinely separate defect still needs its own test plan (a query/join or filter fix in `GtmAgentGetConfigState`, mirroring the same Published/Active join pattern now proven in `GtmPageContentReader.getIndustryProfiles`).

**Recommendation:** file a new, separate follow-up issue for the `GtmAgentGetConfigState` Draft filter (suggested title: "GtmAgentGetConfigState.availableIndustries leaks Draft industries to GUS"), scoped by a fresh BA pass, rather than reopening or expanding #12.
