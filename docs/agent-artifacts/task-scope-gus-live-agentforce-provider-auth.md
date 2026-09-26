# TASK SCOPE — ISSUE #gus-live-agentforce-provider-auth

## 0. Origin & split rationale (Architect decision)

Split from `docs/agent-artifacts/task-scope-gus-live-agentforce-provider.md`
(BA branch `ba-scope/issue-gus-live-agentforce-provider`) by the Architect,
per that doc's own closing instruction to use judgment on whether the issue
needs further splitting given the session-based Agent API vs. today's
stateless proxy shape, plus the "secret must never land in a committed
file" constraint.

Two sub-issues:

- **`gus-live-agentforce-provider-auth`** (this doc): stand up the actual
  OAuth/Agent API plumbing in `gtm-staging` — an artifact that can be
  smoke-tested with a real callout — and record the confirmed API shape.
  No changes to `GtmAgentProxyController.runLoop()`'s dispatch behavior.
- **`gus-live-agentforce-provider-runtime`** (sibling doc): once this
  issue's Named Credential + confirmed API shape exist, adapt `runLoop()`
  to actually call it when `Chat_Provider__c = 'Agentforce'`.

Rationale for splitting rather than one Developer worktree: the two halves
have different verification substrates (org Setup + a live smoke callout,
vs. `Test.setMock`-based Apex unit tests) and different blast radii (org
configuration/secret handling vs. code review of a shared dispatch path
used by every GUS surface). Bundling them risks a Developer either
fabricating the API shape to keep the Apex-only half moving, or stalling
entirely on org access. `runtime` should not start coding against assumed
request/response shapes — it must read this issue's completed addendum to
`docs/architecture/gus-chat-provider-settings.md` §5 first.

## 1. Requirements Breakdown

- **Target Objective:** In `gtm-staging` only (CLAUDE.md §5; Agentforce is
  licensed there, confirmed live in Setup — Agentforce toggle On, zero
  agents currently deployed):
  1. Resolve BA ambiguity #2: verify hands-on in `gtm-staging` Setup
     whether deploying + activating the existing `EinsteinCopilot`-type
     `GTM_Configurator_Assistant` bot (`force-app/main/default/bots/GTM_Configurator_Assistant/`)
     produces an agent callable via the **Agent API**. Per Salesforce's own
     docs (developer.salesforce.com/docs/ai/agentforce/guide/agent-api.html),
     **"Agent API isn't supported for agents of type 'Agentforce
     (Default)'"** — `EinsteinCopilot` is not documented as excluded, but
     this repo has not verified it in-org. If it is unusable for the Agent
     API, evaluate the BA's noted alternative: a custom REST-annotated
     Apex method wrapping the Invocable Action API, OR the bot-meta file's
     own documented `<einstein-copilot-chat agent-api-name="...">` embedded
     LWC component path (found in the bot-meta XML's header comment during
     this review) — that is a third, client-side activation route,
     architecturally different from both the Agent API and Invocable
     Action API paths, and would mean the chat UI embeds Agentforce
     directly rather than `GtmAgentProxyController` proxying it server-side.
     Pick one path and document why in the addendum required by §3 below;
     do not leave this ambiguous for the `runtime` issue.
  2. Configure the OAuth 2.0 **client-credentials** flow: an External
     Client App with the `sfap_api` scope AND "Manage user data via APIs
     (API)" scope (per the Salesforce Developers blog on invoking agents
     from Apex/Flow — both scopes are required; the second is easy to miss
     and its absence produces a token that cannot call REST API endpoints
     at all). The consumer secret is generated and stored **only** in the
     External Client App's Setup UI / the org's Named Credential
     Principal — never written to any file under `force-app/` or
     committed anywhere in this repo (per
     `docs/architecture/gus-chat-provider-settings.md` §2's existing "no
     secret field" design).
  3. Add deployable-but-secret-free source metadata for the Named
     Credential / External Credential (the credential *definition* and
     its non-secret settings — endpoint, auth protocol, scope — are safe
     to check in; the Principal's secret value is entered directly in
     `gtm-staging` Setup post-deploy, same pattern as the org already
     uses elsewhere). Confirm the three existing
     `GTM_Agent_Settings__c` fields (`Agentforce_Agent_Id__c`,
     `Agentforce_My_Domain_URL__c`, `Agentforce_Client_Id__c`) are
     sufficient to parameterize this, or document precisely what's
     missing (e.g., a Named Credential developer-name constant) — if a
     genuinely new field is needed, it must ship with the matching FLS
     grant in `GTM_Offering_Admin` only (the existing pattern for these
     three fields, confirmed via
     `grep -n Agentforce force-app/main/default/permissionsets/GTM_Offering_Admin.permissionset-meta.xml`
     → lines 401/406/411, absent from the other four permission sets —
     that's correct/intentional since these are admin-only integration
     config, not something reps need FLS on).
  4. Smoke-test: prove a real HTTP callout from `gtm-staging` (Workbench,
     Anonymous Apex, or Postman against the Named Credential) can start an
     Agent API session against the activated agent and get a real
     response. This is the "observable signal that could only come from
     the live agent" the parent issue's acceptance criteria require —
     capture it (session/transcript log or response body) as evidence in
     the addendum.
- **Non-goals (belongs to `runtime`, not here):** No changes to
  `GtmAgentProxyController.runLoop()`, `getProvider()`, or
  `resolveEffectiveProvider()`. No changes to the Anthropic/OpenAI/Gemini
  code paths. No LWC changes unless the embedded `<einstein-copilot-chat>`
  path is chosen (see 1.1) — in which case flag that explicitly in the
  addendum, since it would change the shape of the `runtime` issue
  significantly (client-side embed vs. server-side proxy call) and the
  Architect should be looped back in before `runtime` starts.

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? No changes to `GtmAgentToolSurface`,
      `executeTool`, or any surface class. Only bot/GenAiPlugin/
      GenAiFunction activation state and new Named Credential/External
      Credential metadata. Zero-DML/zero-callout-inside-a-tool contract
      (AGENTS.md §1, `GtmAgentToolSurface.cls`) is unaffected — this issue
      doesn't touch tool implementation classes.
- [ ] Altering Custom Metadata? No. Bot/GenAiPlugin/GenAiFunction and
      Named Credential/External Credential are standard Metadata API
      types under `force-app/`, not Custom Metadata Type records governed
      by the `migration-accelerator/instrument/` YAML rule.
- [ ] Introducing database fields? Likely no (see §1.3) — confirm before
      closing; if yes, FLS grant in `GTM_Offering_Admin` ships in the same
      change, not a follow-up (CLAUDE.md §6.1).

## 3. Plan Acceptance Criteria

- **Deliverable:** An addendum to
  `docs/architecture/gus-chat-provider-settings.md` §5 (replacing today's
  "Agentforce fallback (stateless) ... Agentforce is never called" text)
  documenting: the chosen activation path (Agent API / Invocable Action
  API wrapper / embedded `<einstein-copilot-chat>`) and why; the confirmed
  session-create / message-send / session-end request/response shapes as
  observed live against `gtm-staging` (not copied from docs without
  verification, since the BA flagged Salesforce's Agent API surface
  "changed materially over 2025"); the Named Credential/External
  Credential developer names and what each `GTM_Agent_Settings__c` field
  maps to; and explicit confirmation the consumer secret lives only in
  `gtm-staging` Setup, never in a committed file (grep the diff for
  anything matching a secret pattern before calling this done).
- **Evidence required:** the live smoke-test response/log from §1.4,
  referenced (not necessarily pasted verbatim if it contains any
  sensitive token) in the addendum.
- **Target org:** `gtm-staging` only. Never `gtm-prod`.
