# TASK SCOPE — ISSUE #106-sso-resume

> **Status: Architect scope (resume).** This is a resume/re-provisioning of
> already-debugged, real work from the abandoned `agent/issue-106-sso`
> branch (3 commits, diverged from `main` 167 commits ago; no PR was ever
> opened — it fell through the cracks). A prior read-only audit confirmed
> the diagnosis is sound and the code applies cleanly against current
> `main` (verified again at resume time: no commits on `main` since the
> branch's merge-base touched `GtmEmployeeSsoRegHandler`'s dependencies —
> `GtmViewerContext.cls`, `experiences/GTM1/views/login.json`,
> `force-app/main/default/authproviders/`, or
> `force-app/main/default/connectedApps/`). This document is the original
> branch's own `TASK_SCOPE.md` (§1–§6 below, content unchanged) migrated to
> the current per-issue path convention
> (`docs/agent-artifacts/task-scope-<id>.md`), per
> `docs/agent-artifacts/*` / `AGENTS.md` §2. GitHub issue reference: #106
> ("Internal reps forced to re-login on GTM Experience Cloud site
> mid-workflow").

## 1. Requirements Breakdown

- **Target Objective:** A rep already authenticated in the internal org
  (`*.lightning.force.com`) who reaches the `GTM1` Experience Cloud site
  (`/gtm/s/...`, `my.site.com` domain) should not have to type credentials
  again. They should land authenticated, or at most click one official
  "Login with Salesforce" button — never a second username/password form —
  and `GtmViewerContext.isRep()` should immediately read `true`.
- **System Component Impacted:** Experience Cloud site auth configuration
  for `GTM1` (`force-app/main/default/experiences/GTM1/`), plus new
  Connected App / Auth Provider / registration-handler metadata. No change
  to `GtmViewerContext.isRep()`'s contract, no change to guest/prospect
  Configurator behavior.

## 2. Investigation Findings (root cause — confirmed)

- `force-app/main/default/experiences/GTM1/views/login.json`'s
  `salesforceIdentity:employeeLoginLink2` (id
  `56d5bd60-25b2-4e9b-8842-cb8af71123e2`) has only an
  `employeeLoginLinkLabel` attribute — no `authProvider`/SSO reference.
  `salesforceIdentity:socialLogin2` (`useCommunityDomainSso: true`) sits next
  to it and is the component that would render SSO buttons, but has nothing
  to render.
- No `force-app/main/default/authproviders/`, no `samlssoconfigs/`, no
  `*.connectedApp-meta.xml`, no network-branding metadata exist in source.
  `sf data query --query "SELECT Id FROM AuthProvider" -o gtm-dev` →
  `totalSize: 0` live. There is no auth bridge of any kind today beyond a
  dead link.
- `GtmViewerContext.isRep()` = `UserInfo.getUserType() == 'Standard'` — "rep"
  strictly means authenticated *on the site itself* as the internal user.
  The two domains do not share a session by default.
- Five prior attempts (URL/session-token bridging — `frontdoor.jsp`-style
  hacks) have already failed live and are not to be repeated.

## 3. Architect Decision: Option (a) — Same-org Salesforce Auth Provider

**Chosen.** Configure a standard, Salesforce-supported "Login with
Salesforce" Auth Provider (`providerType: Salesforce`) backed by a Connected
App in the *same* org, wired to the site's existing `socialLogin2`/
`employeeLoginLink2` components. This is the documented, supported
mechanism for exactly this scenario (an internal user SSO-ing into an
Experience Cloud site of the same org) and is ~90% deployable as metadata.

### Why the alternatives were rejected

- **(b) Apex REST + JWT Bearer session-minting, rejected.** There is no
  supported Apex API to mint a genuine authenticated Experience Cloud
  session for *another* user's browser from server-side code — every path
  there (constructing a session id / `frontdoor.jsp` token programmatically)
  is the same class of session/URL-bridging hack as the 5 already-failed
  attempts, just with a JWT dressing. It would add a new custom
  auth-bypass surface (a digital certificate + Apex REST endpoint capable of
  authenticating as arbitrary users) to a **production** org with no
  staging to rehearse it in — the opposite of "minimal, reversible"
  (`CLAUDE.md` §4). Standard Auth Provider metadata is a well-trodden,
  auditable Salesforce feature; a bespoke session-minting endpoint is not.
- **(c) Not needed.** Per the investigation, the only non-deployable pieces
  are (i) revealing/copying one Consumer Secret and (ii) a possible
  one-checkbox spot-check in Experience Builder's Login & Registration
  panel — bounded to the "at most one or two manual steps" bar for option
  (a), so there is no reason to fall back to a manual-heavy design.

### Files/metadata to add or change (all in `force-app/main/default/`)

1. `connectedApps/GTM_Employee_SSO.connectedApp-meta.xml` — OAuth enabled;
   callback URL `https://<mydomain>.my.salesforce.com/services/authcallback/GTM_Employee_SSO`;
   scopes `api`, `web`, `refresh_token`; **"All users may self-authorize"**
   (avoids needing a permission-set grant for Connected App access — internal
   users only, no prospect/guest exposure since guests never hold an
   internal session to bridge).
2. `authproviders/GTM_Employee_SSO.authprovider-meta.xml` —
   `providerType: Salesforce`; `authorizeUrl`/`tokenUrl` pointed at this
   same org's own `/services/oauth2/authorize` and `/services/oauth2/token`;
   `consumerKey`/`consumerSecret` as placeholders (`REPLACE_AFTER_DEPLOY`,
   never a real secret committed — see manual step 1); `registrationHandler`
   → new class below; `sendAccessTokenInHeader: true`.
3. `classes/GtmEmployeeSsoRegHandler.cls` (+ `-meta.xml`) — implements
   `Auth.RegistrationHandler`. **Maps to an existing internal user only**
   (match on Username or Federation Id); `createUser()` throws
   (`Auth.RegHandlerException`) rather than auto-provisioning — fail closed,
   since every legitimate rep already has an internal user record and
   silent user creation on a production identity surface is unacceptable.
4. `experiences/GTM1/views/login.json` — no structural change expected;
   `socialLogin2` auto-discovers configured Auth Providers. Left as-is
   pending the live spot-check in manual step 3; only touched if that check
   shows the button doesn't appear.
5. Permission sets: **no grants needed** given "self-authorize" above. If a
   later hardening pass switches the Connected App to "Admin approved users
   are pre-authorized," `GTM_Offering_User` and `GTM_Offering_Admin` would
   each need the Connected App added to their assigned-app list — flagged,
   not done now, to keep this change minimal.

### Manual Setup UI steps remaining (exactly two)

1. **Retrieve the Consumer Secret.** After deploying the Connected App:
   Setup → **App Manager** → find "GTM Employee SSO" → dropdown → **View**
   → **Manage Consumer Details** (re-verify identity if prompted) → copy
   **Consumer Key** and **Consumer Secret**. Paste both into
   `authproviders/GTM_Employee_SSO.authprovider-meta.xml` locally, then
   redeploy just that file. Treat the secret as a live credential: it should
   not sit in the repo long-term in plaintext — a follow-up hardening task
   (out of scope here) should move it to a protected custom
   setting/rotation process matching the existing GUS Claude API key
   pattern in `GTM_Offering_Admin`, if Salesforce's AuthProvider metadata
   type allows an indirection; if not, document it as a deliberately
   Setup-managed field excluded from routine diffs.
2. **Spot-check the Login page shows the button.** Setup → **Digital
   Experiences** → **All Sites** → `GTM1` → **Builder** → gear icon /
   **Administration** → **Login & Registration** → confirm "GTM Employee
   SSO" (or "Login with Salesforce") now appears as an authentication
   service option for the Login page, and that it is enabled. If it does
   not auto-populate, enable it here by hand — this is the one checkbox the
   investigation could not confirm has a metadata surface.

### Live verification plan (QA — must run in the real browser per project memory)

1. As a real internal rep account, log into the internal org normally
   (lightning.force.com).
2. In the same browser, navigate to the `GTM1` site login page
   (`/gtm/s/login`). Click the "Login with Salesforce" / employee-login
   button.
3. **Pass condition:** lands on the site fully authenticated with zero
   re-typed credentials (first-time OAuth consent screen click is
   acceptable; a password field is not). `GtmViewerContext.isRep()`-gated UI
   (Gus, saved links bar, wizard) renders immediately.
4. Repeat from a cold browser (no prior internal-org session) to confirm no
   redirect loop and a sane fallback to normal login.
5. **Regression check (per "QA browser validation" project rule — verify
   every dependent surface, not just the changed one):** confirm the
   unauthenticated guest/prospect Configurator flow is completely unchanged
   — no login prompt, no behavior change, `loginForm2` still present and
   working for any prospect/non-SSO internal path.
6. Confirm no change to `GtmViewerContext.isRep()`'s Apex logic and no
   change to any Custom Metadata / instrument YAML.

## 4. Explicit Out of Scope

- Rotating/storing the Consumer Secret via a protected custom
  setting (flagged as a follow-up, not blocking this fix).
- Auto-provisioning new users via the registration handler — deliberately
  unsupported; only existing internal users can SSO in.
- Any change to `GtmViewerContext.isRep()`, guest/prospect Configurator
  behavior, Custom Metadata, or instrument YAML.
- Switching the Connected App to "Admin approved users are pre-authorized"
  (would need permission-set grants) — left as self-authorize for now.

## 5. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No.
- [ ] Altering Custom Metadata? No.
- [ ] Introducing database fields? No. New setup-only metadata types
      (`connectedApps`, `authproviders`) — not schema, not a Permission Set
      field-grant case per `CLAUDE.md` §6, since Connected App access is via
      "self-authorize" rather than profile/permission-set assignment.

## 6. Plan Acceptance Criteria

- **Success Metric:** matches §3 verification plan steps 3–6 above.
- **Test Target:** an Apex test on `GtmEmployeeSsoRegHandler` asserting
  existing-user lookup succeeds and `createUser()` throws for an unknown
  identity (no live-secret dependency, so this is unit-testable without
  hitting the real OAuth flow); plus the mandatory live QA walkthrough in
  §3 — no staging environment exists to rehearse this in first.

## 7. Resume-Specific Additions (Architect, 2026-09-17)

- **Re-verified against current `main`:** merge-base is `5382e3c`
  ("fix(permissions): grant reps Apex class access and surface isRep wire
  failures (issue-99) (#100)"). No commit on `main` since that merge-base
  has touched `GtmViewerContext.cls`, `experiences/GTM1/views/login.json`,
  `force-app/main/default/authproviders/`, or
  `force-app/main/default/connectedApps/`. The branch's 3 real commits
  (auth provider, connected app, reg handler + test, plus the
  `isPkceEnabled` and callback-URL-domain fixes already baked into commit
  `6adf73a`) apply and are expected to compile cleanly.
- **Conflict note:** the old branch's own root `TASK_SCOPE.md` is
  superseded by this file at the new path and is discarded on merge —
  cosmetic only, no functional file is lost.
- **Deploy gate (do not skip):** this touches production identity/auth
  (Auth Provider + Connected App) with no staging environment. The
  Developer may write/run Apex tests locally and via `--check-only` /
  `--dry-run` validation freely, but must **not** run a live, activating
  deploy of the `authproviders/` or `connectedApps/` metadata to `gtm-dev`
  without first looping the user in through the coordinator — this is a
  live identity-surface change on a production org, distinct from ordinary
  Apex/test-only deploys.
- **Manual steps cannot be automated** (Consumer Secret retrieval, Login &
  Registration panel spot-check) — both require live Setup UI verification
  after deploy; flag both explicitly to QA/coordinator rather than treating
  them as done once metadata is deployed.
