# AGENTS.md — GTM Offerings

This file is about **agents**, not the repo in general — see `CLAUDE.md` for
that. Two different kinds of agent touch this codebase and they should not be
confused with each other:

1. **GUS** — the AI agent *inside* the product, talking to reps and
   prospects.
2. **Coding agents** — Claude Code or similar, operating *on* this codebase.

This file was previously a symlink to `CLAUDE.md`. It no longer is — GUS is a
real, load-bearing system with its own architecture, and conflating "agent
instructions for the repo" with "how the product's agent works" was hiding
that.

## 1. GUS (GTM Utility Sidekick / Service)

**What it is today: a custom Apex→Anthropic Claude tool-use loop, not
Agentforce.** Agentforce metadata exists in the repo but is unwired
scaffolding for a future migration — don't treat it as the live path, and
don't "fix" the custom Apex agent by pointing at Agentforce components
without reading this section first.

### Live path (what actually runs)

- **`GtmAgentProxyController.cls`** — the engine. Calls
  `https://api.anthropic.com/v1/messages` directly via `HttpRequest`, model
  `claude-sonnet-5` by default (overridable via
  `GTM_Agent_Settings__c.Claude_Model__c`), API key from
  `GTM_Agent_Settings__c.Claude_API_Key__c`. One shared `runLoop()` (max 5
  tool-call rounds) serves two surfaces: `chat()` for the GTM Configurator
  panel and `chatOnReadout()` for the readout editor.
- **`GtmAgentToolSurface.cls`** — the interface contract every tool surface
  implements: system prompt + Anthropic tool definitions + `executeTool`.
  **No DML or callouts inside a tool implementation** — tools read/propose,
  they don't write directly.
- **`GtmReadoutAgentSurface.cls`** — GUS's system prompt for the readout
  editor ("You are GUS, the GTM Utility Service...") and its 3 tools:
  read-only context/file access plus a non-persisting
  `update_readout_draft` proposal tool. The rep still clicks Save — GUS
  proposes, it doesn't commit.
- **`GtmAgentGetConfigState.cls` / `GtmAgentApplyConfigUpdate.cls` /
  `GtmAgentConfigActions.cls`** — tool implementations for the configurator
  screen. These double as the dormant Agentforce invocable actions (see
  below), so changing their signatures affects both paths.
- Supporting classes: `GtmAgentTone.cls` (tone config),
  `GtmReadoutAgentContext.cls` / `GtmReadoutAgentFiles.cls` /
  `GtmReadoutAgentEdit.cls` (read/file/edit tool logic for the readout
  surface), `GtmViewerContext.cls` (rep-vs-guest identity, shared with the
  rest of the app — see CLAUDE.md §6.6).
- **UI**: `lwc/gtmAgentChat`, `lwc/gtmAgentBubble`, `lwc/gtmReadoutAssist`,
  `lwc/gtmMascot` (the Gus avatar) call `GtmAgentProxyController` via `@wire`
  / imperative Apex. None of them reference `<einstein-copilot-chat>`.
- **`force-app/main/default/remoteSiteSettings/Anthropic_API.remoteSite-meta.xml`**
  authorizes the outbound callout to Anthropic — required for the proxy
  controller to function in any org.

### Dormant Agentforce scaffold (not live — don't wire it up by accident)

- `force-app/main/default/bots/GTM_Configurator_Assistant/*.bot-meta.xml` —
  an `EinsteinCopilot` bot definition.
- `force-app/main/default/bots/GTM_Configurator_Assistant/AGENT_INSTRUCTIONS.md`
  — instructions meant to be pasted into Agentforce Studio when this
  migration actually happens, not consumed by any code today.
- `force-app/main/default/genAiPlugins/GTMGetConfigState.genAiPlugin-meta.xml`
  and `GTMApplyConfigUpdate.genAiPlugin-meta.xml` — wire the same
  `GtmAgentGetConfigState`/`GtmAgentApplyConfigUpdate` Apex to Agentforce's
  invocable-action format, in anticipation of the swap.
- The bot-meta.xml's own header says this **requires Agentforce to be
  provisioned** in the org before it can do anything, and that
  `<einstein-copilot-chat>` is **not currently wired into any LWC**.
- **The intended migration** (per `GtmAgentProxyController`'s own header
  comment): once Agentforce is provisioned, replace the custom chat LWCs
  with `<c-ma-agent-chat>` (or equivalent) bound to the Agentforce bot, and
  retire `GtmAgentProxyController`. Until that happens, treat the bot/plugin
  metadata as inert and the Apex/Anthropic path as the only one to debug or
  extend.
- Related spec: `docs/specs/agentforce-customizer-v2.md` — pre-migration
  design notes, verify against current code before trusting details (same
  caveat as other `docs/specs/` files per CLAUDE.md §9).

### Working on GUS — rules

- If a bug report is "GUS said/did X," start in `GtmAgentProxyController`
  and the relevant surface class (`GtmReadoutAgentSurface` or the config
  tool classes) — not in the `bots`/`genAiPlugins` metadata, which isn't
  executing.
- Changing GUS's behavior on the readout editor means editing the system
  prompt in `GtmReadoutAgentSurface.cls`, not a Setup-UI prompt template —
  there isn't one live.
- A new tool needs: (1) the tool implementation class, no DML/callouts
  inside it (`GtmAgentToolSurface` contract), (2) registration in the
  relevant surface class's tool-definition list, (3) if it should also work
  post-Agentforce-migration, a matching `genAiPlugin` wired to the same
  Apex.
- The 5-round tool-loop cap in `runLoop()` is a real ceiling, not
  decorative — a tool chain that needs more rounds will silently truncate;
  design tools to resolve in fewer round-trips rather than raising the cap
  first.
- API key and model live in `GTM_Agent_Settings__c` (custom setting), not
  hardcoded — check there before assuming a model/key value from code.

## 2. Coding agents (Claude Code and similar) working on this repo

Per CLAUDE.md §3, **this repo has no custom Claude Code sub-agents under
`.claude/agents/`** — no sub-agent roster to coordinate here. If that
changes, document the roster and hand-off points in this section rather
than in CLAUDE.md, so agent-to-agent coordination stays separate from
general repo/working rules.

Until then, the operative coordination rules for a single coding agent
working this repo are in `CLAUDE.md` §4 (Working rules) — contract-first,
parallel LWC/Apex threads against the same doc, continuous debug loops, plan
before schema changes. Follow those; this file doesn't duplicate them.

One rule specific to *this* repo's agent-on-agent boundary: **a coding agent
modifying GUS's tool surfaces is bound by the same no-DML/no-callout-inside-
a-tool contract GUS's own tools follow** (`GtmAgentToolSurface`) — don't add
a "convenience" DML statement inside a tool implementation to save a round
trip; it breaks the separation between "propose" and "commit" that lets a
rep review GUS's readout edits before they persist.
