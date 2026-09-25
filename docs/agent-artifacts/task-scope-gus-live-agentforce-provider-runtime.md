# TASK SCOPE — ISSUE #gus-live-agentforce-provider-runtime

## 0. Series Context & Hard Dependency (read before anything else)

This is the sibling/follow-on of `gus-live-agentforce-provider-auth`
(BA doc `docs/agent-artifacts/task-scope-gus-live-agentforce-provider-auth.md`,
itself split from `task-scope-gus-live-agentforce-provider.md`). That doc's
own §0 states the split explicitly: `auth` stands up the OAuth/Named
Credential plumbing and confirms the live API shape; `runtime` (this issue)
adapts `GtmAgentProxyController.runLoop()` to actually call it. `auth`'s own
non-goals list says verbatim: "No changes to `GtmAgentProxyController.runLoop()`,
`getProvider()`, or `resolveEffectiveProvider()`" — confirming those three
are exactly what this issue changes.

**Hard dependency, verified today, not yet satisfied:** all of the resolved
evidence (Named Credential, External Credential, the §5a "RESOLVED" live
200-with-sessionId proof) lives only on the unmerged, unpushed worktree
branch `agent/issue-gus-live-agentforce-provider-auth`, not on `main`:

```
$ cd /Users/isiwintr/Documents/Workbench/worktrees/issue-gus-live-agentforce-provider-auth
$ git status
On branch agent/issue-gus-live-agentforce-provider-auth
Your branch and 'origin/main' have diverged, and have 7 and 26 different
commits each, respectively.
nothing to commit, working tree clean

$ git log origin/agent/issue-gus-live-agentforce-provider-auth
fatal: ambiguous argument 'origin/agent/issue-gus-live-agentforce-provider-auth':
unknown revision or path not in the working tree.
```

There is no `origin/agent/issue-gus-live-agentforce-provider-auth` ref at
all — the branch has never been pushed. `main`'s copy of
`docs/architecture/gus-chat-provider-settings.md` has no `§5a` section
(confirmed: `git log --oneline -- docs/architecture/gus-chat-provider-settings.md`
on `main` shows only the original `gus-settings-provider-ui` history), and
`main`'s `force-app/` has no `namedCredentials/GTM_Agentforce_API` or
`externalCredentials/GTM_Agentforce_Credential` at all (confirmed via
`find force-app -iname 'GTM_Agentforce*'` on `main` returning nothing).

**This means the Architect cannot simply run
`scripts/agent-workspace.sh create gus-live-agentforce-provider-runtime`
against `main` and expect the credential metadata or the confirmed request
shape to be there.** Before Developer work starts, either (a) the `auth`
branch must be pushed and merged to `main` first (it is described as "secret
free by design" and its own QA/PR step was apparently never run), or (b) the
Architect must explicitly provision the `runtime` worktree from
`agent/issue-gus-live-agentforce-provider-auth` as its base rather than
`main`. Flagging this as a blocking sequencing decision rather than
guessing — it is exactly the kind of cross-branch state a BA agent cannot
resolve on its own (BA has read-only, no-commit access to other agents'
branches).

## 1. Requirements Breakdown

- **Target Objective:** Make `Chat_Provider__c = 'Agentforce'` a genuinely
  live, working GUS provider path — `GtmAgentProxyController.runLoop()`
  should route to a real Agent API session against the "GTM Configurator
  Assistant" agent (BotDefinition Id `0XxgK000002MowHSAS`) instead of
  silently falling back to Claude/OpenAI/Gemini
  (`resolveEffectiveProvider`, current behavior documented in
  `gus-chat-provider-settings.md` §5, confirmed unchanged today: `grep -n
  "Agentforce is never called" docs/architecture/gus-chat-provider-settings.md`
  → line 155 in the worktree copy, same text present verbatim in `main`'s
  copy at line ~154).

- **System Component Impacted:** Apex only —
  `force-app/main/default/classes/GtmAgentProxyController.cls`
  (`runLoop()`, `getProvider()`, `resolveEffectiveProvider()`, plus a new
  `callAgentforce`-style adapter method alongside the existing
  `callClaude`/`callOpenAi`/`callGemini` peers). No LWC change is required
  for the MVP described below (see §3's design-fork discussion for the one
  scenario that WOULD need an LWC/DTO change). No new
  `GTM_Agent_Settings__c` fields or permission-set grants are needed — the
  three existing Agentforce fields (`Agentforce_Agent_Id__c`,
  `Agentforce_My_Domain_URL__c`, `Agentforce_Client_Id__c`) and their
  existing `GTM_Offering_Admin`-only FLS grants (confirmed:
  `grep -n Agentforce force-app/main/default/permissionsets/GTM_Offering_Admin.permissionset-meta.xml`
  → lines 401/406/411) already cover everything the `auth` issue's
  reconciliation identified as needed.

### Open design fork — the Architect must resolve this, not guess

Confirmed by direct evidence in the `auth` branch's own addendum
(`docs/architecture/gus-chat-provider-settings.md` §5a, "Agent identity"
table, worktree lines 191-199): **the live agent has zero topics/actions
wired** — "No topics/actions were wired — description and the full
`AGENT_INSTRUCTIONS.md` body were pasted into Agent-Level Instructions and
saved. Action-wiring ... is explicitly deferred to the `runtime` issue."
Combined with `GtmAgentToolSurface.toolDefinitions()`'s own doc comment
(`force-app/main/default/classes/GtmAgentToolSurface.cls` line 39: "Anthropic
tool definitions") — there is no Agent-API-shaped equivalent of "pass tool
defs on this call" the way Claude/OpenAI/Gemini accept them per-request.
Agentforce topics/actions are configured server-side in Agentforce Studio,
not sent in the Start Session/Send Message body. Two structural
consequences fall out of this that the Architect needs to decide between,
not the Developer mid-build:

1. **Tool-calling parity is not achievable in this issue as scoped.** Today
   `runLoop()`'s `apply_gtm_config_update`/`get_gtm_config_state` tools (the
   configurator's actual "GUS edits the page for you" capability) have no
   Agent-API analog until someone separately wires
   `GTMGetConfigState`/`GTMApplyConfigUpdate` `genAiPlugins` (which already
   exist in `force-app/main/default/genAiPlugins/` for the *superseded*
   `EinsteinCopilot` bot model, per
   `force-app/main/default/bots/GTM_Configurator_Assistant/SUPERSEDED.md`)
   as Topics/Actions on the new Agent-Script-authored agent — a Setup/
   agent-authoring task, not an Apex change. **Recommend this issue's MVP
   scope is conversational-text-only when Agentforce is selected**: the
   agent replies in the chat, but `apply_gtm_config_update` cannot fire
   through it, so `changes` returned to the LWC is always empty on the
   Agentforce path. That is a real, user-visible capability gap versus the
   Claude/OpenAI/Gemini paths and should be called out in the Settings tab
   help text (a small, in-scope LWC copy change — not new UI) so an admin
   who flips to Agentforce today understands GUS on the configurator screen
   will talk but not click any buttons for them yet.
2. **One agent, one system prompt, three different surfaces.** Chat_Provider__c
   is a single org-wide hierarchy setting; if Agentforce is selected, ALL
   THREE of GUS's current entry points (`chat`/configurator,
   `chatOnReadout`/readout editor, `chatOnApp`/utility bar) would route to
   the SAME single agent, whose Agent-Level Instructions were authored
   specifically for the configurator persona (confirmed:
   `AGENT_INSTRUCTIONS.md` content was "reused as the basis for the real
   Agent Script agent's instructions" per SUPERSEDED.md, and Agent API has
   no per-call system-prompt override the way `surface.systemPrompt(toneClause)`
   gives the other three providers). A readout-editing or app-utility-bar
   conversation routed to this agent would get configurator-flavored
   replies. Options: (a) scope Agentforce to the configurator surface only
   for this issue, and have `chatOnReadout`/`chatOnApp` keep falling back to
   `resolveEffectiveProvider()`'s existing Claude/OpenAI/Gemini behavior
   when Chat_Provider__c is Agentforce (asymmetric, but ships something
   real without a second agent); (b) block on provisioning two more
   Agentforce agents (a Setup task, out of this Apex issue's reach); (c)
   research whether Agent API's Start Session body supports a per-session
   variables/context mechanism that could carry a role hint (unconfirmed —
   the old, superseded Bot Builder model had "sessionToken/configId
   conversation variables," but that is explicitly the legacy model this
   org's agent was NOT built with, so it should not be assumed to carry
   over to Agent Script/Agent API without independent verification). This
   scope doc recommends (a) as the pragmatic default but flags it as an
   Architect decision, not a settled fact.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? Partially — `runLoop()`,
      `getProvider()`/`resolveEffectiveProvider()` change (dispatch logic),
      but `GtmAgentToolSurface` the interface, `ConfigSurface`,
      `GtmReadoutAgentSurface`, and `GtmAppAgentSurface` are NOT touched
      (per the design-fork note above, the Agentforce path does not call
      `surface.executeTool` at all in the recommended MVP — it has no tool
      results to feed back). Zero-DML rule (AGENTS.md §1) is unaffected:
      the new adapter is callouts only, exactly like `callClaude`/
      `callOpenAi`/`callGemini`, and executes before any client-side DML
      exactly the same way.
- [ ] Altering Custom Metadata? No. No `GTM_Assessment_*` or other Custom
      Metadata Type change of any kind — this issue never touches
      `migration-accelerator/instrument/` or `scripts/build-instrument.py`.
- [ ] Introducing database fields? No — confirmed the three existing
      `Agentforce_*` fields on `GTM_Agent_Settings__c` are sufficient (see
      §1). If the Architect/Developer later decide a session-id-threading
      mechanism needs a NEW field or object (see §3.2 below — the
      recommended approach avoids this by piggy-backing on the existing
      `historyJson` envelope), that would require the mandatory Permission
      Set mapping per CLAUDE.md §6 before merge, not as a follow-up.

## 3. Detailed Scope

### 3.1 Session lifecycle — what's proven vs. what's still assumed

**PROVEN (live, `gtm-staging`, 2026-09-25):** Start Session. Exact request
body, headers, and a real 200 response with `sessionId` are reproduced
verbatim in `docs/architecture/gus-chat-provider-settings.md` §5a's
"RESOLVED" subsection (worktree lines 557-616) — cite that block directly
in code comments at the new call site per that section's own explicit
instruction: "worth a code comment at the call site, not just here."

```
POST https://api.salesforce.com/einstein/ai-agent/v1/agents/{AGENT_ID}/sessions
Content-Type: application/json
Authorization: Bearer {ACCESS_TOKEN}   (handled by the Named Credential)

{
  "externalSessionKey": "{RANDOM_UUID}",
  "instanceConfig": { "endpoint": "https://{MY_DOMAIN_URL}/" },
  "streamingCapabilities": { "chunkTypes": ["Text"] },
  "bypassUser": true
}
```

Response (live, confirmed): `{"sessionId":"01a0dadb-...", ..., "messages":
[{"type":"Inform","message":"Hi, I'm an AI assistant. How can I help
you?", ...}]}` — note the Start Session response itself already contains
an agent-generated message. That has a real implication for turn 1 of a
conversation: it is not yet proven whether the rep's actual first typed
message should be sent as part of Start Session somehow, or whether Start
Session is always a parameterless handshake and the rep's first message is
always a separate, subsequent Send Message call. Do not assume — this is
listed as unverified below.

**NOT PROVEN — Send a Message and End a Session.** No live smoke test in
`auth`'s evidence trail exercises either. This BA session independently
attempted to fetch Salesforce's official Agent API reference pages (both
via a raw `curl` with a browser User-Agent, mirroring the one thing that is
documented to have worked for the coordinator and for the `auth`
Developer) and got HTTP 403 bot-protection on every URL tried, e.g.:

```
$ curl -s -A "Mozilla/5.0 ..." \
  "https://developer.salesforce.com/docs/ai/agentforce/references/agent-api" \
  -o out.html -w "HTTP_STATUS:%{http_code} SIZE:%{size_download}\n"
HTTP_STATUS:403 SIZE:2436
$ curl -s -A "Mozilla/5.0 ..." \
  "https://developer.salesforce.com/docs/ai/agentforce/guide/agent-api-get-started.html" \
  -o out.html -w "HTTP_STATUS:%{http_code} SIZE:%{size_download}\n"
HTTP_STATUS:403 SIZE:2436
```

(repeated for `agent-api-examples`, `agent-api-agent-id`,
`agent-api-considerations`, `agent-api-errors` — all 403, all a 2436-byte
XHTML "error" stub body.) This confirms the block is not WebFetch-tool-
specific; it is IP/session/bot-fingerprint-specific, and a BA agent's Bash
session hits the same wall the Developer's did in the `auth` issue. **The
Architect/Developer must plan for a browser-based fetch** (the one channel
this session's own instructions say worked for the coordinator) to pin the
exact Send-Message and End-Session request/response shapes, OR a second
live smoke test cycle analogous to `auth`'s Attempt 1-4/RESOLVED sequence,
before writing the adapter code as if the shape were settled. Publicly
documented Agent API conventions (general knowledge, NOT verified this
session, present it to the Developer as a hypothesis to confirm, not a
fact to build blind against) commonly follow a
`POST /sessions/{sessionId}/messages` (synchronous) and
`DELETE /sessions/{sessionId}` shape, with a `/messages/stream` SSE
variant for streaming — but treat every one of those paths as unconfirmed
until either doc text or a live 200 proves it, exactly as Start Session
required five rounds of live iteration before it worked.

**Trailing-slash requirement — hard, must be in the code, not just this
doc.** `docs/architecture/gus-chat-provider-settings.md` §5a "RESOLVED"
(worktree lines 583-611) is explicit: `instanceConfig.endpoint` MUST end
with a trailing `/` or the call 404s in a way that is byte-for-byte
indistinguishable from an anonymous/unauthenticated request (this was the
actual root cause hunted across four attempts). The new adapter method
must construct this value as `myDomainUrl + '/'` (or equivalent) with a
comment citing `gus-chat-provider-settings.md` §5a RESOLVED by name, and a
unit test should assert the trailing slash is present in the constructed
request body — this is exactly the kind of detail a future refactor could
silently drop.

### 3.2 Session state — the actual biggest gap, confirmed by reading the code

`runLoop()` today is per-call stateless: every Apex invocation
(`chat`/`chatOnReadout`/`chatOnApp`) receives the FULL conversation replayed
as `historyJson`, appends the new user turn, and returns the updated
`historyJson` for the LWC to hold and resend next turn. Confirmed by
reading `gtmAgentChat.js` directly:

```
// force-app/main/default/lwc/gtmAgentChat/gtmAgentChat.js
historyJson = '';                                    // line 88, component instance state only
...
this.historyJson = parsed.historyJson || '';          // line 154, overwritten every turn
...
return chat({ sessionToken: ..., configId: ..., userMessage: text, historyJson: this.historyJson });  // line 200-205
```

There is no `sessionId` field anywhere in `GtmAgentProxyController`'s
return envelope (`{text, historyJson, changes}`), the LWC's component
state, or `GTM_Agent_Settings__c`. `sessionToken` (the one session-shaped
name that DOES exist) is explicitly documented as unrelated: the class
header comment calls it "LWC session token (routes empApi events; passed
through for logging only in proxy mode)" — a UI/event-routing id, not an
Agent-API session.

Real Agent API sessions are stateful server-side objects (a `sessionId`
minted by Start Session must be reused on every subsequent Send Message
call in the same conversation). The pattern that fits this codebase's
existing conventions with the LEAST structural change: thread the
Agent-API `sessionId` through the exact same channel `historyJson` already
uses — i.e., add a new key to the JSON envelope
(`{text, historyJson, changes, agentSessionId}`) that the LWC holds
verbatim and resends, mirroring `historyJson`'s own lifecycle exactly
(reset to blank on `reset()`, per-component-instance, never persisted
server-side). This needs a Developer decision on exactly where in
`runLoop()` this branches, since `runLoop()`'s current signature
(`GtmAgentToolSurface surface, String userMessage, String historyJson`)
has no session-id parameter today, and the Agentforce path (per §1's
design fork) likely needs to skip the generic `surface`/tool-loop
machinery entirely rather than reuse it. **Do not conflate this
`agentSessionId` with `sessionToken`** — keep them as two distinct fields;
they answer different questions (which browser tab / which tool-surface
event stream, vs. which Agent-API conversation).

**End Session is a genuinely open question, not just an unproven
endpoint shape.** Today `gtmAgentChat.js`'s `reset()` (the host's "New
chat") is 100% client-side — it clears local arrays and calls no Apex
method at all. Wiring a real End Session call would need either (a) a new
Apex method + a new LWC call on `reset()`, or (b) relying on the Agent
API's own idle-session timeout and never calling End Session explicitly
(simpler, but leaves orphaned sessions accumulating server-side until they
expire on their own — acceptable or not is a product/architecture call,
not an Apex-mechanics one). Flag this for the Architect rather than
picking silently.

### 3.3 `bypassUser: true`

Confirmed correct and already proven (RESOLVED section, §3.1 above) —
keep it. No evidence anywhere in this codebase of a caller-scoped/
interactive-user variant being needed; this org's Agentforce setup is
client-credentials-only (Run-As user is the agent's own
`EinsteinServiceAgent` user), matching `bypassUser: true`'s documented
behavior of routing through the agent's own assigned user rather than the
token's user. Do not add a per-caller branch unless a concrete future
requirement demands one.

### 3.4 Error handling

Current pattern, confirmed identical across all three existing adapters
(`callClaude` line 466-470, `callOpenAi` line 516-520, `callGemini` line
723-727 in `GtmAgentProxyController.cls`): a non-200 response throws
`CalloutException('<Provider> API returned ' + status + ': ' + body)`,
uncaught by `runLoop()` itself — it propagates out of the `@AuraEnabled`
method and is caught client-side by `gtmAgentChat.js`'s
`.catch(err => this._addMessage('assistant', err?.body?.message || ...))`,
i.e. today's UX for ANY provider failure is a generic apology bubble, with
no code-specific branching. Recommend the Agentforce adapter follow the
exact same shape (`CalloutException('Agentforce Agent API returned ' +
status + ': ' + body)`) for consistency rather than inventing a bespoke
per-status-code taxonomy — this issue's own item 5 lists 400/401/403/404/
422/423/429/503 as documented Agent API codes, but this BA pass could not
independently verify their exact semantics (same 403 doc-fetch block as
§3.1) and general knowledge of what each likely means should be treated as
a hypothesis for the Developer to confirm against a live error response
(e.g. deliberately supply an invalid agent ID or an expired session id
during testing) rather than hard-coded as fact. The one exception worth
flagging as probably-real-and-worth-a-distinct-message: 401/403 on this
path most likely mean the Named Credential's cached token expired or the
JWT-issuance checkbox got flipped off again (the exact failure mode §5a's
RESOLVED section root-caused) — that is arguably worth a clearer
admin-facing message than "Agentforce Agent API returned 401: ...", but
leave that UX call to the Architect/Developer rather than deciding it
here.

### 3.5 Testing — no live agent calls in CI

`force-app/main/default/classes/GtmAgentProxyControllerTest.cls` already
has exactly the right pattern to extend, confirmed by reading it directly:
a `SequencedMock implements HttpCalloutMock` (lines 11-25) that returns
`responses[0], responses[1], ...` across successive callouts in the SAME
test method and repeats the last entry once exhausted. `Test.setMock`
intercepts ALL outbound HTTP callouts in a test context regardless of
whether the real request used a raw URL (today's three adapters) or a
`callout:NamedCredentialName/...` endpoint (what the new Agentforce
adapter will use, per the proven smoke-test syntax
`req.setEndpoint('callout:GTM_Agentforce_API/einstein/ai-agent/v1/agents/.../sessions')`
in `gus-chat-provider-settings.md` §5a) — this is standard, documented Apex
test behavior, and the existing `SequencedMock` needs no rework to support
it. A new test class (or a new section of `GtmAgentProxyControllerTest`)
can therefore simulate "Start Session returns 200 with sessionId, then
Send Message returns 200 with a reply" as two queued mock responses in one
test method, exactly like the multi-round tool-use tests already do for
Claude. Note: this is the FIRST provider adapter in this codebase to use a
Named Credential rather than a raw hardcoded URL + Remote Site Setting
(`Anthropic_API`/`OpenAI_API`/`Google_Gemini_API` are all
`remoteSite-meta.xml`, confirmed via `ls force-app/main/default/remoteSiteSettings/`
— no Agentforce entry exists there and none is needed for a Named
Credential) — flag this as a new pattern for the Developer, not a
copy-paste of an existing adapter's test setup.

## 4. Non-Goals (this issue)

- **No new UI.** The chat surfaces (`gtmAgentChat`, `gtmGusUtility`,
  `gtmReadoutAssist`) are unchanged in shape; at most, Settings-tab help
  text gains a sentence about the tool-calling gap (§1's design-fork item
  1) if the Architect accepts that MVP framing.
- **Not Content Manager's "Draft with AI" feature** — already shipped,
  unrelated (`GtmAgentContentDraftController`/`GtmContentDraftAgentSurface`,
  `docs/architecture/industry-variants-agentforce-draft.md`). Do not touch.
- **Not Data Cloud personalization** — separate, explicitly parked track
  per the plan referenced in the issue prompt.
- **Not agent-authoring / Topics-Actions wiring in Agentforce Studio.**
  That is a Setup-UI task (per §1's design-fork item 1), not an Apex
  change, and is out of this issue's reach even if the Architect decides
  it is eventually necessary — it would be its own follow-up issue.
- **Not provisioning additional Agentforce agents** for the readout-editor
  or app-wide surfaces (§1's design-fork item 2, option (b)) — out of
  scope unless the Architect explicitly picks that option and splits it
  out.
- **No changes to the Claude/OpenAI/Gemini adapters** — `callClaude`/
  `callOpenAi`/`callGemini` and their normalization helpers are unchanged;
  this issue only adds a fourth peer and changes the dispatch that
  currently short-circuits Agentforce to one of the other three.

## 5. Plan Acceptance Criteria

- **Success Metric:** With `GTM_Agent_Settings__c.Chat_Provider__c =
  'Agentforce'` and the `auth` issue's Named Credential/External
  Credential/agent live in the target org, a rep sending a message through
  `gtmAgentChat` on the configurator screen receives a real reply
  generated by the live "GTM Configurator Assistant" agent (not a
  Claude/OpenAI/Gemini fallback) — verified via a real `sessionId` and
  agent-authored `message` text in the Send-Message response, threaded
  correctly across at least 2 consecutive turns in the same browser
  session (proving the session-id-threading mechanism in §3.2 actually
  persists conversation continuity, not just a one-shot Start Session
  call). Provider failure (a forced non-200, e.g. an expired/garbage
  Named Credential token in a `gtm-staging` test) degrades to the same
  generic apology-bubble UX every other provider failure already produces
  — no uncaught exception, no blank/broken chat panel. Switching
  `Chat_Provider__c` back to `Anthropic`/`OpenAI`/`Gemini` continues to
  work exactly as before (no regression to `resolveEffectiveProvider`'s
  existing fallback logic for those three).
- **Target Test Target:** New/extended Apex tests in
  `GtmAgentProxyControllerTest.cls` (or a new
  `GtmAgentProxyControllerAgentforceTest.cls`, Developer's call on
  file-split) covering: Start-Session-then-Send-Message happy path via
  `SequencedMock` (§3.5), the mandatory trailing-slash construction on
  `instanceConfig.endpoint` (§3.1), a non-200 response producing the same
  `CalloutException` shape the other three adapters use (§3.4), and
  `resolveEffectiveProvider`/`getProvider` actually returning/dispatching
  to Agentforce's real path instead of silently falling back (the
  opposite of today's `resolveEffectiveProvider_agentforce...` tests,
  which currently assert the FALLBACK behavior this issue is intentionally
  changing — those existing tests will need to be updated, not just added
  to; run `grep -n Agentforce force-app/main/default/classes/GtmAgentProxyControllerTest.cls`
  to find them before starting). No test may perform a real callout to
  `api.salesforce.com` — `Test.setMock` throughout, per AGENTS.md §2.A/C
  org-request discipline (agents never do real deploys or uncontrolled org
  calls). A `sf project deploy validate --target-org gtm-staging`
  (check-only) plus targeted `sf apex run test` against the changed
  classes is QA's job per the standard workflow, not something scoped
  here.
