# TASK SCOPE — ISSUE #gus-live-agentforce-provider

## 0. Series Context & Relationship to `industry-variants-agentforce-draft`

Independent of, not dependent on, `docs/agent-artifacts/task-scope-industry-variants-agentforce-draft.md`
(branch `ba-scope/issue-industry-variants-agentforce-draft`). Confirmed by
reading that doc directly (`git show
ba-scope/issue-industry-variants-agentforce-draft:docs/agent-artifacts/task-scope-industry-variants-agentforce-draft.md`):
that issue is Track A of a 4-issue Content Manager series, explicitly scoped
to **reuse the existing proxy pattern** ("This is explicitly scoped to reuse
the *existing* proxy-based GUS pattern (`GtmAgentProxyController.cls`), not a
live Agentforce/Data Cloud integration") and explicitly defers any live
Agentforce work ("Track B ... is out of scope for building in this or any of
the other three issues in this series"). That series also touches a
*different* bot/topic it proposes to create (`GTM_Content_Drafting_Assistant`,
gated on unresolved decision F4 for Content Manager access to GUS at all —
see that doc's §1 ambiguity note) and a different LWC host
(`gtmContentManager`), not the configurator/readout/app-wide GUS surfaces this
issue covers.

**Sequencing recommendation:** these two issues can proceed in parallel —
they touch disjoint Apex classes (this issue never touches
`GtmAgentGetSectionContent`/`GtmAgentDraftSectionVariant`, which don't exist
yet) and disjoint bots (`GTM_Configurator_Assistant` vs. the not-yet-created
`GTM_Content_Drafting_Assistant`). The one shared surface is
`GtmAgentProxyController.runLoop()`'s provider dispatch — if both land, the
later one should rebase, since this issue is the one adding an `Agentforce`
branch to `runLoop()`/`getProvider()`, and the sibling issue's F4 ambiguity
(whether Content Manager gets GUS access at all) is still unresolved by an
owner, independent of this issue's progress. There is no hard blocking
dependency either direction. If the Architect wants a single order, do this
issue (GUS live-agent runtime) first, since it retires the fallback logic in
`GtmAgentProxyController` the sibling issue's own doc treats as the "existing
proxy pattern" template — but nothing here structurally requires that order.

## 1. Requirements Breakdown

- **Target Objective:** Make GUS's `Agentforce` provider option a real,
  live Agentforce (Einstein Copilot / Agent API) runtime instead of the
  current silent fallback, while leaving the Anthropic/OpenAI/Gemini
  provider choice in the GUS settings tab fully intact and unregressed.
  Concretely:
  1. Deploy and activate the existing `GTM_Configurator_Assistant`
     `EinsteinCopilot` bot (`force-app/main/default/bots/GTM_Configurator_Assistant/`)
     in `gtm-staging` as a real, invokable Agentforce agent, with the two
     existing `GenAiPlugin`/`GenAiFunction` pairs (`GTMApplyConfigUpdate`
     → `GtmAgentApplyConfigUpdate.cls`, `GTMGetConfigState` →
     `GtmAgentGetConfigState.cls`) actually attached to and callable from
     it.
  2. Wire `GtmAgentProxyController.runLoop()` (or a new sibling code path)
     so that when `Chat_Provider__c = 'Agentforce'`, it genuinely invokes
     the live agent via the correct Salesforce API surface — not the
     current `resolveEffectiveProvider()` fallback that silently
     substitutes Anthropic/OpenAI/Gemini and never calls Agentforce at
     all.
  3. Preserve, unmodified in user-facing behavior, the existing ability to
     select Anthropic/OpenAI/Gemini instead, via the same
     `Chat_Provider__c` setting and the same `gtmOfferingsSettingsAgent`
     settings-tab UI.
- **System Component Impacted:** Apex (`GtmAgentProxyController.cls` —
  provider dispatch only, no change to the three proxy providers' code
  paths; a new Agentforce-invocation code path), Bot metadata
  (`GTM_Configurator_Assistant.bot-meta.xml`, currently undeployed
  scaffolding), `GenAiPlugin`/`GenAiFunction` metadata (already exist,
  currently unattached to any activated agent — activation status must be
  verified in-org, not assumed from the XML alone), possibly a new Named
  Credential / External Credential for the Agent API's OAuth
  client-credentials flow (see §2 and §3), and — only if research in §3
  shows the settings-tab notice text or Agentforce field set needs to
  change — `gtmOfferingsSettingsAgent` LWC and
  `GtmAgentSettingsController.cls`.

### Ambiguity flagged for the Architect/owner — not resolved here

1. **Which exact Salesforce API surface to call from Apex is not yet
   confirmed against Salesforce documentation.** The two live candidates
   are the standalone **Agent API** (REST, OAuth client-credentials via an
   External Client App — consistent with the settings doc's existing help
   text, see §3) and invoking the bot in-org via **Conversation
   Messaging / Bot API**. `docs/architecture/gus-chat-provider-settings.md`
   §5 already anticipates the Agent API path ("the Agent API needs an
   External Client App with client-credentials OAuth, and does not support
   agents of type 'Agentforce (Default)'") but this is prior BA/Architect
   guidance already captured in the settings contract, not something this
   scope doc re-derives or newly confirms — the Architect step must verify
   current Salesforce documentation for the Agent API (session creation,
   message send, streaming vs. sync response shape) before a Developer
   builds the callout, since Salesforce's Agentforce API surface has
   changed materially over 2025 and an outdated shape will silently fail
   integration tests that only assert against mocks.
2. **Whether "Agentforce (Default)" vs. a different agent type matters
   for `GTM_Configurator_Assistant`.** The existing settings-doc help text
   explicitly warns the Agent API "does not support agents of type
   'Agentforce (Default)'." The bot-meta type is `EinsteinCopilot`, not
   `Agentforce (Default)` — but this repo has not verified in-org whether
   activating an `EinsteinCopilot`-type bot in the now-provisioned
   `gtm-staging` org produces an agent invokable via the Agent API, or
   whether Agentforce Studio's newer "Agentforce Builder" (referenced in
   the coordinator's Setup screenshot notes) expects a different metadata
   shape entirely. This must be verified hands-on in Setup before the
   Developer starts, not assumed from the XML comment's 2025-era
   instructions.
3. **No consumer secret is stored anywhere in this repo by design**
   (`gus-chat-provider-settings.md` §2: "There is deliberately NO
   Agentforce consumer secret field... The secret will be captured via a
   Named Credential / External Credential in the later integration
   phase"). This issue is very likely that "later integration phase," so
   creating the actual Named Credential / External Credential / External
   Client App metadata (or documenting that it must be configured directly
   in the target org's Setup UI rather than deployed as source, since
   External Client App consumer secrets cannot be safely stored in a
   git-tracked repo) is in scope for the Architect to design explicitly —
   this scope doc does not prescribe which mechanism, only flags that one
   is required and that the consumer secret itself must never land in
   `force-app/` or any committed file.
4. **This touches `gtm-staging`, not `gtm-prod`.** Per CLAUDE.md §5 and
   the coordinator's own investigation, Agentforce is licensed in
   `gtm-staging` (verified live in Setup — Agentforce toggle On, "access to
   Agentforce Coworker" banner) with zero agents currently deployed there.
   Nothing here should target `gtm-prod`; activation, testing, and any
   live agent creation belongs in `gtm-staging` only, per the existing
   promotion flow (worktree → QA validate-only against staging → merge →
   staging → owner go-ahead → prod).

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? Only the provider-dispatch layer in
      `GtmAgentProxyController.runLoop()`/`getProvider()`/`resolveEffectiveProvider()`
      (confirmed present at `force-app/main/default/classes/GtmAgentProxyController.cls`
      lines 203–246, 897–918). The `GtmAgentToolSurface` interface, the
      three existing surfaces (`ConfigSurface`, `GtmReadoutAgentSurface`,
      `GtmAppAgentSurface`), and `executeToolCall`/`executeGetState`/
      `executeApplyUpdate` are NOT touched by this issue — the Agentforce
      path reaches the same underlying data via the already-built
      `GtmAgentGetConfigState.cls`/`GtmAgentApplyConfigUpdate.cls`
      invocable actions (confirmed: these already do zero DML on the
      request path — `GtmAgentApplyConfigUpdate.execute()` only validates
      and calls `EventBus.publish`, a platform event publish, not object
      DML; `GtmAgentGetConfigState` is read-only). The Developer/Architect
      must re-read AGENTS.md §1's zero-DML rule verbatim before writing
      any new Agentforce-invocation code in `GtmAgentProxyController`,
      since this scope doc does not restate its exact current wording.
- [ ] Altering Custom Metadata? NO — no `GTM_Assessment_*` or other
      Custom Metadata Type records are touched. (Bot/GenAiPlugin/
      GenAiFunction are Metadata API types, not Custom Metadata Type
      records governed by the migration-accelerator YAML rule; they are
      standard `force-app/` source, already checked into this repo.)
- [x] Introducing database fields? Likely YES, conditionally. If the
      Architect's API-surface research (§1 ambiguity #1) concludes the
      Agent API needs a session/agent identifier or endpoint URL beyond
      what `GTM_Agent_Settings__c` already stores (`Agentforce_Agent_Id__c`,
      `Agentforce_My_Domain_URL__c`, `Agentforce_Client_Id__c` — all three
      already exist per `docs/architecture/gus-chat-provider-settings.md`
      §2 and are already confirmed present in
      `GTM_Offering_Admin.permissionset-meta.xml` lines 401, 406, 411),
      any additional field follows the same rule as every other schema
      addition in this repo: it needs FLS mapped into
      `GTM_Offering_Admin` (the only permission set with FLS on this
      object today, confirmed via grep) before Definition of Done. Most
      likely no *new* field is needed — the three Agentforce fields
      already anticipate this work — but the Developer must not assume
      that without checking the Agent API's actual auth/session
      requirements first.

## 3. Plan Acceptance Criteria

- **Success Metric:** With `Chat_Provider__c = 'Agentforce'` set in
  `gtm-staging`'s GTM Agent Settings, a rep using GUS on the configurator
  panel (`gtmAgentChat` in `mode='config'`) sends a message, and the reply
  is genuinely generated by the deployed `GTM_Configurator_Assistant`
  Agentforce agent — verified by an observable signal that could only come
  from the live agent (e.g., Agentforce Studio's session/transcript log
  for that agent showing the turn, or a response that could not be
  produced by the Anthropic/OpenAI/Gemini fallback, such as a
  distinguishing marker in Agentforce's own response metadata) — not by
  the absence of an error. Separately, with `Chat_Provider__c` set to each
  of `Anthropic`, `OpenAI`, and `Gemini`, GUS must continue to behave
  exactly as it does today (regression check, not new behavior) — this is
  the non-goal-to-break stated in §1.
- **Target Test Target:** New/updated Apex tests on
  `GtmAgentProxyControllerTest` (existing test class — confirm exact name
  via `find force-app -iname "GtmAgentProxyController*Test*"` at
  Architect/Developer time) covering: (a) `resolveEffectiveProvider`'s
  behavior changes — once Agentforce is live, does `Agentforce` still fall
  back when unconfigured (e.g., missing agent id / my-domain URL), and
  does it now actually branch to a new Agentforce call path when
  configured; (b) the new Agentforce HTTP-callout method, using
  `Test.setMock` the same way `callOpenAi`/`callGemini` are presumably
  already tested (confirm existing mock pattern before writing new tests);
  (c) that Anthropic/OpenAI/Gemini code paths are provably unchanged
  (existing passing tests continue to pass with zero modification, or any
  modification is justified and reviewed). No LWC Jest changes are
  expected unless `gtmOfferingsSettingsAgent`'s Agentforce notice text
  changes (§1 — only if API research changes the field set).
