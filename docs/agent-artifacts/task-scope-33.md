# TASK SCOPE — ISSUE #33

**Title:** Rewire GUS runtime onto real Agentforce (`GtmAgentProxyController.runLoop`)
**BA pass run:** 2026-09-26, against `main` (clean) and `gtm-staging` (live queries, read-only).

---

## 0. READ THIS FIRST — a near-duplicate scope already exists, unreconciled

Before any Architect work starts on issue #33, a sequencing/identity
question needs a human answer. This is the single highest-impact finding
of this BA pass and it is **not** one BA can resolve alone.

**Independently confirmed:** a fully-written, already-pushed BA scope doc
covering effectively the same follow-on work already exists, on a branch
that predates issue #33's own creation:

```
$ git log --format="%H %ad %s" --date=iso -1 \
    origin/ba-scope/issue-gus-live-agentforce-provider-runtime -- \
    docs/agent-artifacts/task-scope-gus-live-agentforce-provider-runtime.md
9e3c47b529f639b2f51c33fe22029a0b894ab4db 2026-09-25 19:25:46 -0400 docs(scope): scope issue
  #gus-live-agentforce-provider-runtime — wire live Agent API into
  GtmAgentProxyController.runLoop()

$ gh issue view 33 --json createdAt
{"createdAt":"2026-09-26T03:07:40Z"}   # = 2026-09-25 23:07:40 -0400
```

That scope doc was committed **~3h42m before issue #33 was filed**, targets
the exact same objective ("adapt `GtmAgentProxyController.runLoop()` to
actually call" the Agent API, same `PROVIDER_AGENTFORCE` toggle, same
BotDefinition Id `0XxgK000002MowHSAS`), and is itself the sibling/follow-on
of an even earlier split (`gus-live-agentforce-provider` →
`gus-live-agentforce-provider-auth` + `gus-live-agentforce-provider-runtime`,
committed 2026-09-24/25). It already contains a 432-line detailed scope
covering session lifecycle (Start Session proven live, Send
Message/End Session unproven), the `bypassUser: true` finding, error
handling, testing approach, an explicit MVP recommendation (configurator
surface only, text-only, no tool-calling in v1), and the same "zero
topics/actions wired" finding this pass re-confirms independently below
(§2.3) via a fresh live Tooling API query, not by trusting that doc's own
claim.

**What's still open even in that doc, confirmed still true today by this
pass, independently re-run:**

```
$ git branch -a | grep -i "provider-auth"
+ agent/issue-gus-live-agentforce-provider-auth        # local worktree only

$ git branch -a | grep "remotes/origin.*provider-auth"
(no output — never pushed)

$ find force-app -iname "*GTM_Agentforce*"
(no output — main has zero Named/External Credential metadata for this)

$ git log --oneline -- docs/architecture/gus-chat-provider-settings.md
2077c908 Initial import: current state of GTM Offerings main   # only commit
$ grep -n "5a\|RESOLVED" docs/architecture/gus-chat-provider-settings.md
(no output — main's copy has no §5a "RESOLVED" section)
```

So issue #33's own Context section is factually accurate (the auth branch
*did* prove the transport works, the 404 root cause *was* found and fixed
in Setup) but incomplete in a way that materially affects any Architect
who runs `scripts/agent-workspace.sh create` against `main` for this
issue: **the Named Credential, External Credential, and the only working
proof of the Agent API request/response shape exist solely on the local,
unpushed worktree branch `agent/issue-gus-live-agentforce-provider-auth`.**
A fresh worktree cut from `main` today gets none of it and would have to
re-discover the entitlement fix and the trailing-slash gotcha from
scratch — exactly the kind of cross-branch state a BA pass cannot fix
(read-only, no commit access to another agent's branch).

**Recommendation, not a decision this doc makes unilaterally:** before
provisioning a worktree for issue #33, the owner/Architect should decide
one of:
1. Treat issue #33 as continuing `gus-live-agentforce-provider-runtime`
   (same scope, arguably more complete already) rather than starting a
   third parallel scoping/build effort under a fourth branch name — push
   and merge `agent/issue-gus-live-agentforce-provider-auth` first, or
   provision the runtime worktree from that branch directly instead of
   `main`.
2. Explicitly supersede the older scope doc with this one and say so in
   both places, if issue #33 is meant to be the canonical, GitHub-tracked
   version of the same work going forward.
3. Close one as a duplicate of the other on GitHub/in the backlog, so a
   future session doesn't find three overlapping `task-scope-*` files for
   one piece of work.

This doc does not pick one of these for the Architect — that is a
sequencing/ownership call, not an architecture-of-the-code call, and BA
has no authority to close or merge another agent's branch.

---

## 1. Requirements Breakdown

- **Target Objective:** Replace, for the `Agentforce` value of
  `GTM_Agent_Settings__c.Chat_Provider__c`, GUS's silent fallback to
  Anthropic/OpenAI/Gemini with a real, working call path to Salesforce's
  Agent API against the live `GTM_Configurator_Assistant` agent
  (BotDefinition `0XxgK000002MowHSAS`, GenAiPlannerBundle
  `GTM_Configurator_Assistant_v1`), so a rep who selects Agentforce in
  Settings actually talks to that agent instead of unknowingly still
  talking to whichever of Claude/OpenAI/Gemini happens to have a key
  configured.

- **System Component Impacted:** Apex (`GtmAgentProxyController.cls` —
  `runLoop()`, `getProvider()`/`resolveEffectiveProvider()`, a new
  `callAgentforce`-shaped adapter alongside `callClaude`/`callOpenAi`/
  `callGemini`) as the core of it. Whether any of `GtmAgentToolSurface`,
  `GtmAppTool`, or the 4 concrete tool surfaces are touched is exactly the
  "tool parity" open question (§3.2) — genuinely undecided, not something
  this doc resolves.

### Genuinely undecided — explicitly not resolved here (per the issue's own framing and this session's instruction not to guess)

The issue lists 5 open questions. This pass does not answer them; it
verifies the facts each one turns on, so the Architect is deciding from
confirmed ground truth rather than the issue's own unverified summary.
Where the pre-existing `gus-live-agentforce-provider-runtime` scope doc
already reasoned through one of these in detail, that is noted — as a
recommendation for the Architect to ratify or reject, not as a settled
fact this BA pass is asserting.

1. **Provider-swap vs. rebuild** — confirmed a swap of `runLoop()`'s HTTP
   target is not drop-in (see §2.1-2.2: request/response shape, stop
   reasons, and session model all differ). The prior scope doc's
   recommendation (add a 4th adapter, same `{stop_reason, content}`
   normalization pattern `callOpenAi`/`callGemini` already use, rather
   than a parallel second loop) is architecturally consistent with how
   OpenAI and Gemini were added and is worth the Architect's serious
   consideration, but is still a design choice, not verified fact.
2. **Tool/action parity** — **now conclusively answered as a factual
   question** (not "unverified" as the issue frames it): the live agent
   has **zero** actions of any kind wired today. See §2.3 — this was
   proven this pass via a live Tooling API query returning 0 rows from
   `GenAiPluginFunctionDef`, not inferred. What the Architect still must
   decide is what to *do* about that (ship text-only first vs. build
   action wiring first) — that remains open.
3. **Session lifecycle** — confirmed real: `historyJson` is pure
   client-side, in-memory-only LWC component state with zero server-side
   or browser-storage persistence (§2.5). Agent API sessions are
   server-side stateful objects keyed by `sessionId`. These are
   incompatible primitives and something has to bridge them — the prior
   scope doc's proposal (thread `sessionId` through the same JSON envelope
   `historyJson` already uses, as a new sibling key) is one workable
   answer, not the only one; still an Architect decision.
4. **Provider fallback/rollback safety** — confirmed the toggle mechanism
   already exists and already works exactly as a safe rollout gate:
   `resolveEffectiveProvider()` only takes the Agentforce branch when
   `Chat_Provider__c == 'Agentforce'` literally, and 3 existing passing
   tests lock in today's fallback-only behavior (§2.2) — those tests
   would need to be *changed*, not merely added to, once Agentforce is
   genuinely wired, since they currently assert the opposite of what this
   issue ships.
5. **Cost/latency/entitlement** — not independently investigable by a BA
   pass with read-only SOQL access; flagged as-is for the Architect/owner,
   consistent with the issue's own framing. No new evidence found either
   way this pass.

---

## 2. Verified Facts (every claim below has the command/output that proves it)

### 2.1 `GtmAgentProxyController.runLoop()` — actual current behavior

Read in full: `force-app/main/default/classes/GtmAgentProxyController.cls`
(960 lines). Confirmed:

- `PROVIDER_AGENTFORCE = 'Agentforce'` (line 42) is a recognized constant
  string value only. `runLoop()`'s provider dispatch (lines 250-261) has
  exactly 3 real branches — `PROVIDER_OPENAI` → `callOpenAi`,
  `PROVIDER_GEMINI` → `callGemini`, everything else (including, in
  principle, a raw `'Agentforce'` string) → `callClaude`. The code comment
  at line 258 states this plainly: *"'Agentforce' never reaches here:
  getProvider() resolves it to a real provider."*
- `getProvider()` (line 912) calls `resolveEffectiveProvider()`, whose own
  doc comment (line 911) reads: *"The provider runLoop() will actually
  call (never 'Agentforce')."*
- `resolveEffectiveProvider(GTM_Agent_Settings__c s)` (lines 923-932):
  blank provider → Anthropic; any non-`'Agentforce'` value passes through
  unchanged; `'Agentforce'` specifically resolves, in order, to Anthropic
  (if it has a key) → OpenAI (if it has a key) → Gemini (if it has a key)
  → Anthropic (surfacing the pre-existing "no key configured" error).
  **There is no code path today that ever issues an HTTP callout to any
  Salesforce Agent API endpoint.** `GtmAgentProxyController.cls` contains
  zero references to `einstein/ai-agent`, `sessions`, or any Agentforce
  callout — confirmed by grep, zero matches.
- 5-round tool-use cap (`MAX_TOOL_ROUNDS = 5`, line 45) applies to the
  existing Claude/OpenAI/Gemini loop only; whether/how it applies to an
  Agent-API-driven conversation (which has no per-call "tool defs in the
  request" concept — see §2.3) is part of the undecided design fork.

### 2.2 `runLoop()` call sites — the issue undercounts by one

The issue says "at least 3 places." **There are 4, confirmed by grep
across the whole classes directory:**

```
$ grep -rln "runLoop" force-app/main/default/classes/ | sort
force-app/main/default/classes/GtmAgentContentDraftController.cls
force-app/main/default/classes/GtmAgentContentDraftControllerTest.cls
force-app/main/default/classes/GtmAgentProxyController.cls
force-app/main/default/classes/GtmAgentProxyControllerTest.cls
force-app/main/default/classes/GtmAgentToolSurface.cls
force-app/main/default/classes/GtmReadoutAgentContext.cls
```

The 4 real call sites and what surface/context each is for:

| Call site | Entry point | Surface | Screen |
|---|---|---|---|
| `GtmAgentProxyController.chat()` (line 124) | `@AuraEnabled chat(sessionToken, configId, userMessage, historyJson)` | `ConfigSurface` (inner class, `without sharing`) | GTM Configurator panel — 2 tools: `get_gtm_config_state`, `apply_gtm_config_update` |
| `GtmAgentProxyController.chatOnReadout()` (line 156) | `@AuraEnabled chatOnReadout(readoutId, workingDraft, userMessage, historyJson)` | `GtmReadoutAgentSurface` (`with sharing`) | Readout editor (`gtmReadoutReview`) — 3 tools |
| `GtmAgentProxyController.chatOnApp()` (line 182) | `@AuraEnabled chatOnApp(pageContextJson, userMessage, historyJson)` | `GtmAppAgentSurface` (`with sharing`) | App-wide utility bar (`gtmGusUtility`) — 2 tools |
| `GtmAgentContentDraftController.chat()` (line 35 of that file) | `@AuraEnabled chat(offeringKey, templateType, sectionKey, userMessage, historyJson)`, calling `GtmAgentProxyController.runLoop(...)` directly (public method, separate class deliberately for Apex-class-access gating — see that class's own header) | `GtmContentDraftAgentSurface` (`with sharing`) | Content Manager "Draft with AI" modal (industry-variant section copy) — 2 tools |

This 4th call site is real production surface area (shipped feature,
`docs/architecture/industry-variants-agentforce-draft.md`), not a stub —
any "swap the provider under `runLoop()`" change affects it exactly as
much as the other 3, and it is `with sharing` content-authoring data, a
different trust boundary than the configurator's page state.

### 2.3 Tool surface enumeration — 4 surfaces, 9 tools total (all Claude-tool-use shaped)

Read in full: `GtmAgentToolSurface.cls` (the interface), `GtmAppTool.cls`
(the app-wide sub-interface), `GtmAppAgentSurface.cls`,
`GtmFilterByQueryAppTool.cls`, `GtmStageFilterAppTool.cls`,
`GtmReadoutAgentSurface.cls`, `GtmContentDraftAgentSurface.cls`, and the
inline `ConfigSurface` in `GtmAgentProxyController.cls`.

| Surface | Tools (Anthropic `tool_use` JSON schema) |
|---|---|
| `ConfigSurface` (configurator) | `get_gtm_config_state`, `apply_gtm_config_update` |
| `GtmReadoutAgentSurface` (readout editor) | `get_readout_context`, `get_rep_context`, `update_readout_draft` |
| `GtmAppAgentSurface` (utility bar) | `find_links_by_stage` (`GtmStageFilterAppTool`), `filter_by_query` (`GtmFilterByQueryAppTool`) |
| `GtmContentDraftAgentSurface` (Content Manager draft-with-AI) | `get_section_content`, `draft_section_variant` |

**Correction to `AGENTS.md` §1:** that file states the app-wide surface's
"registered tools today: `find_links_by_stage`" (singular). Confirmed
stale — `GtmAppAgentSurface.registeredTools()` (source, lines 38-44)
registers **two** tools: `GtmStageFilterAppTool` and
`GtmFilterByQueryAppTool` (the latter shipped 2026-09-24 per its own
class header, "owner-finalized"). `AGENTS.md` was not updated when the
second tool landed. Not this issue's job to fix, but the Architect should
not treat `AGENTS.md` §1's tool inventory as current when scoping tool
parity — use the table above.

None of these 9 tools have an Agent-API-shaped equivalent today. 4 of the
14 total tool-backing Apex methods across the whole surface set (2 for
config state, 2 for content-draft) already have a **declarative,
source-tracked Agentforce action wrapper** —
`force-app/main/default/genAiPlugins/GTMGetConfigState.genAiPlugin-meta.xml`,
`GTMApplyConfigUpdate.genAiPlugin-meta.xml`, `GTMGetSectionContent...`,
`GTMDraftSectionVariant...`, each pointing at a `genAiFunctions/*` wrapper
over the same `GtmAgentGetConfigState`/`GtmAgentApplyConfigUpdate`/
`GtmAgentGetSectionContent`/`GtmAgentDraftSectionVariant` Apex classes the
Claude tools already call. **But these were never deployed to
`gtm-staging`** — confirmed live:

```
$ sf org list metadata --target-org gtm-staging --metadata-type GenAiPlugin
Warning: No metadata found for type: GenAiPlugin in org: ...
```

So even the 4 tools that already have a written Agentforce-action
definition in source have zero live presence — they were authored for an
older `EinsteinCopilot`-type Bot model (see the `GTM_Configurator_Assistant.bot-meta.xml`
comment: *"REQUIRES: Agentforce (Einstein Copilot) provisioned on the
org... Before wiring this agent up, find (or add) the appropriate
insertion point... `<einstein-copilot-chat>`"* — that LWC integration was
never built either), which is architecturally distinct from the live
agent that actually exists in `gtm-staging` today (built via Agent
Builder/Agent Script, reached via the newer Agent API, with a default
4-subagent structure). The other 5 tools (readout's 3, the utility bar's
2) have no Agentforce-action definition of any kind, in source or live.

### 2.4 The live `GTM_Configurator_Assistant` agent — proven, not assumed, to have zero action wiring

This is the concrete answer to the issue's question #3 ("is tool parity a
small mapping task or a from-scratch build"). Verified with live,
read-only Tooling API SOQL against `gtm-staging` (not by trusting the
issue's own "unverified" framing):

```
$ sf org list metadata --target-org gtm-staging --metadata-type Bot
Bot: GTM_Configurator_Assistant, Id 0XxgK000002MowHSAS, Last Modified 2026-09-25
   (matches the Bot Id cited in issue #33's Context section exactly)

$ sf data query --target-org gtm-staging --use-tooling-api \
    --query "SELECT Id, DeveloperName, MasterLabel FROM GenAiPlannerDefinition"
16jgK000002CerlQAC | GTM_Configurator_Assistant_v1 | GTM Configurator Assistant
   (exactly one planner/agent bundle exists in the org — this is the only
   live agent; GTM_Content_Drafting_Assistant, the second Bot tracked in
   force-app source, has never been deployed/built in this org at all —
   confirmed: `sf org list metadata --metadata-type Bot` returns only the
   one row above)

$ sf data query --target-org gtm-staging --use-tooling-api \
    --query "SELECT Id, DeveloperName, MasterLabel, Description FROM GenAiPluginDefinition"
179gK000002RYyvQAG | agent_router_16jgK000002Cerl       | Agent Router
179gK000002RYywQAG | off_topic_16jgK000002Cerl          | Off Topic
179gK000002RYyxQAG | escalation_16jgK000002Cerl         | Escalation
179gK000002RYyyQAG | ambiguous_question_16jgK000002Cerl | Ambiguous Question
   (exactly the 4 default subagent topics the issue describes — Agent
   Router, Escalation, Off Topic, Ambiguous Question — all suffixed with
   this planner's own Id, confirming these belong to THIS agent)

$ sf data query --target-org gtm-staging --use-tooling-api \
    --query "SELECT Id, PlannerId, Plugin FROM GenAiPlannerFunctionDef"
4 rows: PlannerId=16jgK000002CerlQAC (this planner) linked 1:1 to each of
the 4 GenAiPluginDefinition Ids above (the 4 topics) — confirms the
planner→topic wiring exists, as expected for any agent.

$ sf data query --target-org gtm-staging --use-tooling-api \
    --query "SELECT FIELDS(ALL) FROM GenAiPluginFunctionDef LIMIT 5"
Total number of records retrieved: 0.
```

**`GenAiPluginFunctionDef` is the join object between a topic/plugin and
an actual invocable function/action.** It returned **zero rows in the
entire org** — not scoped to this agent, the *whole org* has no
topic-to-action wiring of any kind. This is direct, positive proof (not
an absence-of-evidence inference) that the live `GTM_Configurator_Assistant`
agent has exactly the 4 stock subagent topics Agent Builder creates by
default and **not one single action wired to any of them** — it cannot
read or write any GTM data today. The issue's own framing ("whether it
can reach the same GTM data... is unverified and is a real scope
question, not a given") undersells this: it is now verified, not merely
unverified. Tool parity is a from-scratch build, not a mapping exercise —
consistent with, and independently reproducing, the same finding the
pre-existing `gus-live-agentforce-provider-runtime` scope doc already
reached via a different route (its own citation of the `auth` branch's
`gus-chat-provider-settings.md` §5a addendum, which itself is not on
`main` — see §0).

Also worth the Architect's attention: an attempted Metadata API `retrieve`
of `Bot:GTM_Configurator_Assistant` or `GenAiPlannerBundle:GTM_Configurator_Assistant_v1`
against `gtm-staging` (both attempted, at `sourceApiVersion` 62.0 and
explicitly bumped to 65.0 in a scratch manifest) returned "Nothing
retrieved" with no error — the org's own `listMetadata` call enumerates
these components but a `retrieve()` call for them returns empty. This may
be a real limitation of Agent-Builder-authored (vs. legacy Bot Builder)
agents' retrievability via the classic Metadata API at this org's current
API version, or a transient/beta-feature gap — not chased further by this
pass since it does not change any factual answer above (the Tooling API
SOQL route above is conclusive on its own), but the Architect/Developer
should expect that this agent's configuration may not be capturable in
`force-app/` source the normal way, which has its own knock-on
implications for whether/how this repo's usual "metadata deploy, not
click-ops" discipline (CLAUDE.md §2 "Do Not Hand-Edit Metadata") can even
apply to future agent-authoring changes.

### 2.5 `historyJson` persistence — confirmed pure client-side, in-memory only (no sessionStorage, no server-side stash)

```
$ grep -n "historyJson" force-app/main/default/lwc/gtmAgentChat/gtmAgentChat.js
88:    historyJson = '';                       # component field, default blank
154:    this.historyJson = parsed.historyJson || '';   # overwritten every server reply
190/197/204: sent back to Apex on every send

$ grep -n "sessionStorage\|localStorage" force-app/main/default/lwc/gtmAgentChat/gtmAgentChat.js
(no output)

$ find force-app/main/default/objects -iname "*conversation*" -o -iname "*chat*" -o -iname "*history*"
force-app/main/default/objects/GTM_Agent_Settings__c/fields/Chat_Provider__c.field-meta.xml
(no dedicated object/field stores conversation history anywhere)
```

The issue's claim ("stateless-per-call history") is accurate and,
independently confirmed, actually understates the fragility slightly:
there is no `sessionStorage` fallback either (unlike, e.g., the
assessment-draft flow elsewhere in this app) — `historyJson` lives only
in the `gtmAgentChat` LWC's in-memory component state for the life of
that mounted instance, and is explicitly wiped by `reset()` ("New chat").
A real Agent API session (`sessionId`, stateful server-side, requiring an
explicit End Session call to close cleanly) has no natural home in this
model without adding a new field to the same JSON envelope (the
pre-existing runtime scope doc's proposal, §3.2 of that doc) or some
other bridging mechanism — a genuine, real architectural gap, not
overstated by the issue.

### 2.6 Cross-check against existing architecture docs — no contradiction found, one dependency to flag

- `docs/architecture/gus-chat-provider-settings.md` §5 states verbatim
  today: *"Agentforce is never called"* and documents the exact same
  fallback chain confirmed in §2.1 above. This issue is precisely the
  change that section describes as still pending — no contradiction, this
  issue is that doc's own explicitly-flagged follow-on.
- `docs/architecture/gus-utility-bar-host.md` §5 ("Salesforce-native
  evaluation") states: *"Custom parts that remain, and why: the chat LWC
  and the Apex tool loop (no native equivalent short of Agentforce;
  deferred by AGENTS.md sec 1...)"* — also consistent, not contradicted;
  this doc already anticipates Agentforce as the eventual native
  replacement for the custom loop on this surface specifically.
- Neither doc anticipates or blocks a *partial* rollout (Agentforce wired
  for one surface/call-site while the other 3 stay on Claude/OpenAI/
  Gemini) — if the Architect picks that shape (consistent with the prior
  scope doc's MVP recommendation, §1 item 3 above), `gus-utility-bar-host.md`
  and any readout/content-draft equivalent contract doc would need a
  one-line update noting the surface-specific provider split, since today
  they're written as if `Chat_Provider__c` is a single global switch with
  no surface exceptions. Small doc update, not a design blocker.
- 3 existing Apex tests
  (`chat_agentforceSelected_fallsBackToAnthropicWhenItHasAKey`,
  `chat_agentforceSelected_fallsBackToOpenAiThenGemini`,
  `chat_agentforceSelected_noKeysAnywhere_surfacesExistingMissingKeyError`,
  `GtmAgentProxyControllerTest.cls` lines 1058-1116) currently assert the
  fallback-only behavior as correct. Whichever phase actually wires a real
  Agentforce call path must change these, not just add new tests beside
  them — they will start failing (correctly) the moment `resolveEffectiveProvider`
  stops always resolving Agentforce away.

---

## 2. Code Dependency Checklist

- [x] **Modifying GUS Tool Surface?** Likely, but *how much* is exactly
      the undecided design fork (§1 item 2 / §2.3). At minimum
      `runLoop()`/`getProvider()`/`resolveEffectiveProvider()` change
      (dispatch logic) in every phasing option. If a later phase builds
      real tool-calling parity, `GtmAgentToolSurface`, one or more
      concrete surfaces, and/or new Agentforce-side actions all become
      in-scope too. **Zero-DML rule (AGENTS.md §1) applies unchanged**:
      whatever new adapter method is added must remain callout-only, no
      DML, mirroring `callClaude`/`callOpenAi`/`callGemini` exactly — this
      is a hard constraint regardless of which design-fork option is
      chosen.
- [ ] **Altering Custom Metadata?** No. This issue does not touch
      `instrument/<offering-key>/` YAML or
      `force-app/main/default/customMetadata/GTM_Assessment_*`.
      (Agentforce agent *configuration* itself — topics, actions,
      instructions — is a different metadata surface, `Bot`/
      `GenAiPlannerBundle`/`GenAiPlugin`, not the CLAUDE.md §2 "Custom
      Metadata Type" instrument pipeline; that constraint does not apply
      here, but see §2.4's retrieve-gap note for a related, real caveat
      on that different metadata surface.)
- [ ] **Introducing database fields?** Not required for a runtime-swap-only
      phase — the 3 existing `Agentforce_Agent_Id__c`/
      `Agentforce_My_Domain_URL__c`/`Agentforce_Client_Id__c` fields on
      `GTM_Agent_Settings__c` already exist and are already granted only
      on `GTM_Offering_Admin` (confirmed:
      `grep -n Agentforce force-app/main/default/permissionsets/GTM_Offering_Admin.permissionset-meta.xml`
      → lines 401/406/411). **If** a later phase adds a session-id field
      to persist across turns (§2.5), whether that's a new
      `GTM_Agent_Settings__c` field, a new object, or piggy-backed into
      the existing JSON envelope is an open design choice — if it ends up
      as a real new field/object, the CLAUDE.md §6 permission-set mapping
      requirement applies before merge, not as a follow-up.

---

## 3. Recommended Phasing — a decision for the Architect/owner, not pre-empted here

**This work should not be one Developer pass.** Reasoning:

- 4 real call sites (§2.2), 4 tool surfaces, 9 existing tools (§2.3), a
  live agent with zero action wiring to build against from scratch
  (§2.4), a session-model mismatch with no existing analog in this
  codebase (§2.5), and 3 existing tests that must be *changed*, not just
  extended (§2.6) — each of these is independently non-trivial, and
  several (tool-calling parity, especially) are plausibly bigger than the
  transport-swap itself.
- A precedent for phased/sequenced splitting of a single large piece of
  work already exists in this repo, in two forms **actually verified this
  pass** (see below for a correction to a different precedent cited when
  this BA task was assigned):
  - **ADR-0010** (`docs/architecture/adr/0010-gtm-offerings-settings-tab-is-one-tab-with-sections.md`)
    was explicitly narrowed by the Architect into sequenced Units:
    `d8f7609b chore: narrow TASK_SCOPE.md to Unit 1 per ADR-0010
    (Architect)`, followed by `issue-settings-units-2-3` (Units 2/3
    together, PR #169) and a further split of Unit 3 itself into
    `issue-notifications-unit-3` and `issue-notifications-unit-3b-lifecycle-wiring`.
  - **Issue #102** was split into `102-1-engagement-links-landing`,
    `102-d1-readout-link-fix`, and `102-e-gus-file-extraction` — 3
    separate `task-scope-102-*.md` files, confirmed present in
    `docs/agent-artifacts/`.

  **Correction:** the task that assigned this BA pass cited "issue #31's
  precedent of getting split into 3 phases by the Architect for a much
  smaller-scoped ticket" as the model to follow. That specific claim does
  not hold up: `git log --all --grep` and the issue-31 branch history
  (`ba-scope/issue-31` → a single scope doc → exactly 2 Developer commits,
  `d307e4d7`/`77368ae0`, on one branch, one PR) show issue #31 was built
  and landed as **one** pass, not three. The real, verifiable precedent
  for phased splitting is ADR-0010's Units and issue-102's sub-scopes
  above — cite those, not #31, when justifying a split to the owner.

- **A phasing shape worth the Architect's consideration** (not
  prescribed — the actual boundaries are an architecture decision,
  informed by whichever design-fork answers in §1 the Architect picks):
  1. **Transport + fallback-safety only**, scoped to the configurator
     surface (`chat()`/`ConfigSurface`) alone, conversational-text-only
     (no tool-calling), matching the MVP the pre-existing
     `gus-live-agentforce-provider-runtime` scope doc already worked out
     in detail (§3.1-3.5 of that doc: Start-Session-then-Send-Message,
     the `sessionId`-in-envelope threading proposal, trailing-slash
     requirement, error-handling shape, test approach) — contingent on
     resolving §0's branch-provenance question first, since that doc's
     own proven request/response shape lives only on the unpushed `auth`
     worktree.
  2. **Tool/action parity for the configurator's 2 tools** (the only pair
     that already has a written, if undeployed, `genAiPlugin`/
     `genAiFunction` declaration to build from — §2.3) — deploy those,
     wire them as real Actions on the live agent's topics (an
     Agentforce-Studio/Setup-UI task per the prior scope doc's own
     non-goals list, not an Apex change), and prove `apply_gtm_config_update`
     actually fires end-to-end through Agentforce.
  3. **Extend to the other 3 call sites** (readout editor, app-wide
     utility bar, Content Manager draft-with-AI) — each needs either its
     own Agentforce agent/topic set (since one agent's instructions are
     configurator-flavored per the prior scope doc's design-fork #2) or
     an explicit, documented decision that those 3 stay on
     Claude/OpenAI/Gemini indefinitely while only the configurator uses
     Agentforce. That asymmetry, if chosen, needs a one-line update to
     `gus-utility-bar-host.md` and any readout-surface contract doc
     (§2.6) so a future reader doesn't assume `Chat_Provider__c` is a
     single uniform switch.

  This mirrors, rather than duplicates, the phasing already proposed in
  the pre-existing runtime scope doc's own non-goals section (§4 of that
  doc explicitly excludes "agent-authoring/Topics-Actions wiring" and
  "provisioning additional Agentforce agents" from its own MVP) — the
  Architect reconciling §0 first likely means adopting that doc's Phase 1
  nearly as-is, then treating Phases 2/3 above as its natural sequels.

---

## 4. Plan Acceptance Criteria

- **Success Metric:** Contingent on which phase is authorized (§3) — for
  Phase 1 specifically: with `GTM_Agent_Settings__c.Chat_Provider__c =
  'Agentforce'` and the required Named/External Credential live in the
  target org, a rep sending a message through `gtmAgentChat` on the
  Configurator screen receives a real reply generated by the live "GTM
  Configurator Assistant" agent (verified via an actual `sessionId` and
  agent-authored message text, not a Claude/OpenAI/Gemini reply),
  threaded correctly across at least 2 consecutive turns in the same
  session. A forced provider failure (expired/garbage credential)
  degrades to the same generic apology-bubble UX every other provider
  failure already produces — no uncaught exception, no blank panel.
  Switching `Chat_Provider__c` back to Anthropic/OpenAI/Gemini continues
  to work with no regression to `resolveEffectiveProvider`'s existing
  logic for those three. The 3 existing fallback-assertion tests (§2.6)
  are updated to match the new, no-longer-always-falls-back behavior,
  not left contradicting the shipped code.
- **Target Test Target:** `GtmAgentProxyControllerTest.cls` (extended, or
  a new sibling `GtmAgentProxyControllerAgentforceTest.cls` — Developer's
  call), covering: the Agentforce adapter's happy path via
  `SequencedMock` (the existing `HttpCalloutMock` pattern already used for
  every other provider, confirmed reusable as-is at lines 11-25 of that
  test class), the mandatory trailing-slash construction on
  `instanceConfig.endpoint`, a non-200 response producing the same
  `CalloutException` shape the other 3 adapters use, and
  `resolveEffectiveProvider`/`getProvider` actually dispatching to the
  new path instead of unconditionally falling back. No test may perform a
  real callout to `api.salesforce.com` (`Test.setMock` throughout, per
  AGENTS.md §2.C org-request discipline). A
  `sf project deploy validate --target-org gtm-staging` (check-only) plus
  targeted `sf apex run test` against the changed classes is QA's job per
  the standard workflow, not scoped here.
