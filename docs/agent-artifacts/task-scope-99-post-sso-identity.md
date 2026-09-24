# TASK SCOPE — ISSUE #99 (post-#106 re-scope)

> **Status: BA re-scope.** #106 ("Internal reps forced to re-login on GTM
> Experience Cloud site mid-workflow") has landed and merged this session
> (`issue-106-sso-resume`, PR #258). #99's live sign-off (AC1/AC6/AC7) was
> explicitly blocked on #106 landing (see #99's own thread, last comment).
> This document re-scopes what remains on #99 now that the blocker is gone,
> per direct instruction. It supersedes the "Status__c lifecycle + rotatable
> token" design as the *required* fix for the wizard access gate
> specifically — see §1 and §3 for why, and what of that design survives as
> separate, still-legitimate work.

## 1. Requirements Breakdown

- **Target Objective:** Confirm whether the shipped #106 SSO flow actually
  fixes the root cause #99 diagnosed (`isRep()` structurally cannot return
  `true` for a rep on the `my.site.com` guest-user context), and scope
  whatever is left to make the wizard usable by a rep end to end.
- **System Component Impacted:** Experience Cloud LWC (`gtmConfigurator`,
  `chooseIndustry`, `gtmConfigWizard`) under
  `force-app/main/default/lwc/`. No Apex class or CMDT change identified as
  required (see finding below). **No YAML instrument change.**

### Finding 1 — SSO genuinely resolves the identity problem (verified, not guessed)

Traced precisely, not inferred:

1. `force-app/main/default/authproviders/GTM_Employee_SSO.authprovider-meta.xml`
   is `providerType: Salesforce` (the built-in same-org type) with
   `registrationHandler: GtmEmployeeSsoRegHandler`.
2. `GtmEmployeeSsoRegHandler.createUser()` (`force-app/main/default/classes/GtmEmployeeSsoRegHandler.cls:42-50`)
   returns an **existing internal `User` row** found by `findExistingUser()`
   (match on `Username`, then `FederationIdentifier`, both `IsActive = true`
   only) — it never creates a Contact-backed portal/external user, and
   throws if no match exists (fail-closed, by design, per its own header
   comment and TASK_SCOPE.md §3 item 3).
3. Because the registration handler resolves to an **existing internal
   `User`** rather than provisioning a new site-scoped external user, the
   authenticated site session *is* that internal user's own session — the
   same `User` row, same `UserType`, that the rep already has in
   `lightning.force.com`. This is the standard, Salesforce-documented
   "employee access to an Experience Cloud site via internal license"
   pattern, not a hack: the built-in Auth Provider `providerType=Salesforce`
   + a registration handler that links to (rather than creates) a user is
   exactly what makes that pattern work.
4. `GtmViewerContext.isRep()` (`force-app/main/default/classes/GtmViewerContext.cls:29-31`)
   is `UserInfo.getUserType() == 'Standard'`. An internal user's `UserType`
   is `'Standard'` regardless of which domain the request came in on. Once
   the rep is running as that user on `my.site.com`, `isRep()` legitimately
   returns `true` there — nothing about the guest-user architecture blocks
   this, because after a successful SSO login the rep is **not** the guest
   user anymore for that session.
5. `gtmConfigurator.js:295` sets `this.isConfigManager = !!data` directly
   from the `isRep` wire result (`@wire(isRep)` at line 273). The access
   gate, `get accessBlocked() { return !this.isConfigManager &&
   !this.savedRecordId; }` (line ~935-937 per #99's own prior audit), opens
   the instant `isConfigManager` is `true` — **no `cfgId`, no saved
   record, no token of any kind is required once `isRep()` is `true`.**

**Conclusion: SSO does change the runtime user context, not just the
identity data available.** The wizard access gate for a rep who completes
"Login with Salesforce" is, mechanically, already satisfiable today with
zero further Apex or LWC gate-logic changes. This confirms option (c) from
#99's decision history ("rep preview stays in a context where `isRep`
genuinely can be true") effectively arrived by a different, better route
than originally proposed — a real authenticated internal session on the
site itself, rather than moving the preview into Lightning.

### Finding 2 — the wizard has no login prompt for an unauthenticated visitor (the real remaining gap)

`force-app/main/default/lwc/chooseIndustry/chooseIndustry.js` (the
`?wizard=1` entry tile component) and `gtmConfigurator.js`'s
`maybeAutoOpenWizard()`/`accessBlocked` path have **zero rep/guest
awareness** — `grep` for `isRep|login|Login|guest|Guest` across
`chooseIndustry.js` returns nothing but an unrelated comment. A rep who has
not yet clicked "Login with Salesforce" and lands on
`/gtm/s/choose-offering?wizard=1` (e.g. a bookmarked link, or a fresh
browser) is, for that request, still the guest user. `isConfigManager`
resolves `false`, `accessBlocked` is `true` (no `savedRecordId` either),
and they see the same **"This page needs a link."** message a genuine
guest would — with nothing on screen telling them to log in, or a link to
the "Login with Salesforce" button that only lives on `/gtm/s/login`.

This is the actual remaining scope: **not** a new backend identity
mechanism (that's solved), but a **UI/UX handoff** so an unauthenticated
rep can discover and complete the SSO step before hitting a dead end.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No.
- [ ] Altering Custom Metadata? No.
- [ ] Introducing database fields? No.

## 3. Recommended Scope (concrete, not hedged)

**Small.** SSO already fixes the core problem. The remaining work is wizard
entry-state handling, not a new identity/lifecycle mechanism:

1. **Detect the blocked-but-possibly-a-rep state in `gtmConfigurator.js`.**
   When `accessBlocked` is true (no `savedRecordId`, `isConfigManager`
   resolved `false`) *and* the URL carries `?wizard=1` (i.e., this looks
   like a rep who followed an internal link, not a bare public URL), render
   a distinct prompt — "Log in with your Salesforce account to continue" —
   with a link to `/gtm/s/login`, instead of the generic guest message
   "This page needs a link." The existing `_isRepCheck` tri-state
   (`pending`/`resolved`/`error`, `gtmConfigurator.js:202`) already
   distinguishes "still loading" from "resolved false" from "wire error" —
   reuse it rather than adding new state.
2. **Do not weaken the gate.** The existing security concern flagged in
   #99's own history — `wizard=1` is an unauthenticated, guessable URL
   param, so it must never itself grant access — still holds and is
   unaffected by this change. The prompt only ever *tells* an unauthenticated
   visitor how to become a rep; it must not change `accessBlocked`'s logic
   or treat `wizard=1` as a trust signal.
3. **QA must now actually run the AC1/AC6/AC7 live verification #99's last
   comment flagged as blocked** — a rep completes "Login with Salesforce" on
   `gtm-staging`'s GTM1 site (or wherever #106 is deployed), then hits
   `?wizard=1`, and confirms the wizard renders with zero class-access
   console errors and `isConfigManager` genuinely `true`. This was the one
   piece #99 could never close before, and it is now unblocked.
4. **No change needed to `GtmViewerContext.isRep()`.** Its current
   implementation (`UserType == 'Standard'`) already correctly handles the
   authenticated-member case once #106's registration handler links the
   session to a real internal user — confirmed by tracing the mechanism in
   §1, not by assumption.

### What is explicitly NOT required to close #99

The `Status__c` lifecycle + rotatable link token design from #99's later
comments (Draft/Active/Archived states, `Public_Link_Token__c`-style
rotation on `GTM_Saved_Configuration__c`) was built to answer "how does a
permanently-guest rep see the configurator at all" — that premise no longer
holds. **It is not required to unblock a rep seeing the wizard.**

That said, it should **not be discarded** — re-reading #99's design
comments, the lifecycle problem it solves (a rep resuming an in-progress
link, demoting a live link to draft, archiving with immediate revocation,
duplicate-detection UX on Account/Contact collision) is a real,
independently-justified feature for the **prospect-facing engagement link**
itself, coupled to #102's Engagement Links queue. Recommend it be split out
as its own follow-up issue rather than carried as unfinished scope on #99,
since #99's own stated problem (rep visibility) is now solved by a much
smaller change.

## 4. Plan Acceptance Criteria

- **Success Metric:** A rep who has not yet completed "Login with
  Salesforce" and follows a `?wizard=1` link sees a clear login prompt
  (not the generic guest "needs a link" message); a rep who has completed
  SSO sees the wizard render immediately with `isConfigManager === true`
  and no console class-access errors. Guest/prospect Configurator behavior
  (no `wizard=1`, arriving via a real `cfgId` link) is provably unchanged.
- **Target Test Target:** `force-app/main/default/lwc/gtmConfigurator/__tests__/gtmConfigurator.test.js`
  (add/extend a case for the blocked-but-wizard-flagged prompt state) and
  the mandatory live browser QA walkthrough on `gtm-staging` per project
  memory (QA must validate live, every dependent surface) — completing the
  AC1/AC6/AC7 verification #99's thread left explicitly open.
