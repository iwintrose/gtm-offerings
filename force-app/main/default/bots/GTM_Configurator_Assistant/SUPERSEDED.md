# SUPERSEDED — do not deploy or activate this bot

Confirmed live in `gtm-staging` Setup (issue `gus-live-agentforce-provider-auth`,
2026-09-24): this org has fully moved to the new Agentforce Builder / Agent
Script model. Setup → Agentforce Studio → Agentforce Agents → "New Agent"
goes directly into the Agent Script builder
(`AgentAuthoring/agentAuthoringBuilder.app`), with UI text stating "Agents
are now created using the new Agentforce Builder... Existing agents remain
available in the legacy builder." This org has zero existing agents
(0 `GenAiPlannerDefinition` records via CLI; empty Agentforce Agents list in
Setup), so there is no "existing legacy agent" for this bot-meta to be. It
was authored against the older `EinsteinCopilot`/Bot Builder model, which is
not the activation path for a first agent in this org.

**Decision:** keep this directory in the repo (not deleted) as a reference
for its content — the agent description, the invocable-action wiring
(`sessionToken`/`configId` conversation variables), and especially
`AGENT_INSTRUCTIONS.md`'s behavioral instructions, which are still
substantively valid and are being reused as the basis for the real Agent
Script agent's instructions (see the click-list handed to the coordinator
for this issue). Deleting it would lose that authored content for no
benefit; deploying it as-is would create a legacy-model Bot record this org
setup no longer surfaces a path to activate via Setup UI.

**Do not:**
- Deploy `GTM_Configurator_Assistant.bot-meta.xml` expecting it to produce
  a usable Agentforce agent in `gtm-staging`.
- Point new work at the `<einstein-copilot-chat agent-api-name="...">`
  embedded-LWC path described in this bot-meta's header comment — that path
  was one of three activation options under evaluation before the coordinator's
  live check, and Agent Script/Agent API (server-side, via
  `GtmAgentProxyController`-style proxying) is the path this issue is
  building toward instead, consistent with the "no LWC changes" non-goal
  in `docs/agent-artifacts/task-scope-gus-live-agentforce-provider-auth.md`.

**If this ever needs to be un-superseded:** that would require Salesforce
re-exposing the legacy Bot Builder as the creation path for a first agent in
this org, which contradicts what Setup showed live. Treat that as new
information requiring re-verification, not a reason to revert this file on
its own.
