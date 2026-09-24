# AGENTS.md — GTM Offerings & Coding AI Process

This file defines and governs the two distinct agent systems operating within this repository:

1. **GUS (Name TBD)** — The end-user AI agent *inside* the product, interacting with sales reps and prospects.
2. **Git Worktree Development Agents** — The automated AI coding agents (Claude Code or multi-agent tools) operating *on* this codebase across a sequential 4-stage role workflow.

These are two entirely different domain models. Never conflate the architecture and runtime rules of the product's AI agent (GUS) with the development workflow rules of the AI agents building the codebase.

---

## 1. GUS (Name TBD) — Product AI Agent Architecture

> **Note on Naming:** "(Name TBD)" indicates that the agent's official product name will be updated at a future date. It is a temporary placeholder tag, not part of the actual agent name or brand identity.

**What it is today:** A multi-engine agent system that interfaces with the GTM Offerings App. GUS (Name TBD) can be powered by **custom Apex proxy callouts (Anthropic Claude, Google Gemini, OpenAI) OR Salesforce Agentforce**, selected via configuration settings.

### Engine Architecture & Paths

GUS (Name TBD) operates across two primary execution paths depending on `GTM_Agent_Settings__c.Chat_Provider__c` (`Anthropic`, `OpenAI`, `Gemini`, or `Agentforce`):

#### Custom Apex Proxy Path (Anthropic / OpenAI / Gemini)

* **`GtmAgentProxyController.cls`** — the engine. Calls LLM provider endpoints directly via `HttpRequest` (`claude-sonnet-5` by default, overridable via `GTM_Agent_Settings__c.Claude_Model__c`, API key from `GTM_Agent_Settings__c.Claude_API_Key__c`). One shared `runLoop()` (max 5 tool-call rounds) serves three surfaces: `chat()` for the GTM Configurator panel, `chatOnReadout()` for the readout editor, and `chatOnApp()` for the app-wide utility-bar GUS (Name TBD).
* **`GtmAgentToolSurface.cls`** — the interface contract every tool surface implements: system prompt + tool definitions + `executeTool`. **No DML or callouts inside a tool implementation** — tools read/propose, they don't write directly.
* **`GtmReadoutAgentSurface.cls`** — system prompt for the readout editor ("You are GUS, the GTM Utility Service...") and its 3 tools: read-only context/file access plus a non-persisting `update_readout_draft` proposal tool. The rep still clicks Save — GUS (Name TBD) proposes, it doesn't commit.
* **`GtmAgentGetConfigState.cls` / `GtmAgentApplyConfigUpdate.cls` / `GtmAgentConfigActions.cls**` — tool implementations for the configurator screen. These double as the invocable actions for Agentforce, so changing their signatures affects both paths.
* Supporting classes: `GtmAgentTone.cls` (tone config), `GtmReadoutAgentContext.cls` / `GtmReadoutAgentFiles.cls` / `GtmReadoutAgentEdit.cls` (read/file/edit tool logic for the readout surface), `GtmViewerContext.cls` (rep-vs-guest identity, shared with the rest of the app — see CLAUDE.md §6.6).
* **`GtmAppAgentSurface.cls` / `GtmAppTool.cls**` — the app-wide surface behind `chatOnApp()` (utility bar item in the GTM Offerings app, `lwc/gtmGusUtility`, `mode='app'` on `gtmAgentChat`). `with sharing`, no DML/callouts; registered tools today: `find_links_by_stage`. **New app-wide tools attach here**: write a `with sharing` class implementing `GtmAppTool` (`definitions()`, `handles()`, `execute()`, `promptFragment()`; same no-DML/no-callout/never-throw contract) and add ONE line to `GtmAppAgentSurface.registeredTools()`. A tool that should move the rep sets `changes.pageEffect` (navigate, validated by the host's `ALLOWED_NAVIGATION`).
* **`GtmStageFilterAppTool.cls`** — the first `GtmAppTool`: `find_links_by_stage` (`stage` enum = `GtmLinkStageService.STAGE_KEYS`), a thin `with sharing` wrapper over `GtmLinkStageService.getLinkIdsForStage`. Read-only, max 25 display-only rows with true `count` and `truncated`. Its `compactHistory()` strips returned `rows` from history after each `chatOnApp` turn.
* **UI**: `lwc/gtmGusUtility`, `lwc/gtmAgentChat`, `lwc/gtmAgentBubble`, `lwc/gtmReadoutAssist`, `lwc/gtmMascot` (the Gus avatar) call `GtmAgentProxyController` via `@wire` / imperative Apex.
* **`force-app/main/default/remoteSiteSettings/`** authorizes outbound callouts: `Anthropic_API` (`[https://api.anthropic.com](https://api.anthropic.com)`), `OpenAI_API` (`[https://api.openai.com](https://api.openai.com)`), and `Google_Gemini_API` (`[https://generativelanguage.googleapis.com](https://generativelanguage.googleapis.com)`).

#### Agentforce Path

* **Bot Definition:** `force-app/main/default/bots/GTM_Configurator_Assistant/*.bot-meta.xml` — `EinsteinCopilot` bot definition powering GUS (Name TBD) natively in Salesforce.
* **Agent Instructions:** `force-app/main/default/bots/GTM_Configurator_Assistant/AGENT_INSTRUCTIONS.md` — instructions used by Agentforce Studio when running via Agentforce.
* **Plugins & Invocable Actions:** `force-app/main/default/genAiPlugins/GTMGetConfigState.genAiPlugin-meta.xml` and `GTMApplyConfigUpdate.genAiPlugin-meta.xml` wire the same `GtmAgentGetConfigState`/`GtmAgentApplyConfigUpdate` Apex to Agentforce's invocable-action format.
* **UI Integration:** When Agentforce is activated, custom chat LWCs route through `<c-ma-agent-chat>` or standard Agentforce chat components bound to the Agentforce bot definition.

### Working on GUS (Name TBD) — rules

* Identify which agent engine is active by checking `GTM_Agent_Settings__c.Chat_Provider__c`.
* If debugging the Apex/Proxy path, start in `GtmAgentProxyController` and the relevant surface class (`GtmReadoutAgentSurface` or the config tool classes). If debugging Agentforce, check the bot definition metadata, `AGENT_INSTRUCTIONS.md`, and `genAiPlugins`.
* Changing GUS (Name TBD)'s system behavior on the custom proxy path means editing system prompts in surface classes (e.g. `GtmReadoutAgentSurface.cls`). Changing behavior on Agentforce requires updating `AGENT_INSTRUCTIONS.md` and the bot metadata.
* To keep tools dual-compatible across engines: (1) write the tool implementation class with no DML/callouts (`GtmAgentToolSurface` contract), (2) register it in the proxy surface class, and (3) expose/wire a matching `genAiPlugin` and `@InvocableMethod` for Agentforce.
* The 5-round tool-loop cap in `runLoop()` is a real ceiling for the proxy path — design tools to resolve in fewer round-trips.
* API key, active provider, and model live in `GTM_Agent_Settings__c` (custom setting), not hardcoded — check there before assuming a model/key value.

---

## 2. Git Worktree Development Agents & Multi-Agent Process

When automated coding agents (such as Claude Code or a multi-agent orchestration framework) are initialized to modify this repository, they must operate within a sequential, 4-stage logical role process. Work must always be **understood, designed, built, and reviewed** across isolated filesystems via Git Worktrees.

### A. The 4-Stage Logical Roster

#### 👤 Business Analyst (BA) Agent

* **Goal:** Deep understanding of the prompt/issue.
* **Action:** Gathers requirements, examines existing logic, and creates a markdown file at `docs/agent-artifacts/task-scope-[ID].md` (a unique per-task path). Commits and pushes it to a dedicated `ba-scope/issue-[ID]` branch — never leaves it as an uncommitted change on `main`.
* **Rule:** Never touches code or configuration assets.

#### 👤 Solution / Technical Architect Agent

* **Goal:** Design the implementation path & provision safe isolation.
* **Action:**
1. Reviews `docs/agent-artifacts/task-scope-[ID].md` for architectural compliance (e.g., ensuring no DML loops or violations of `GtmAgentToolSurface`).
2. Provisions a dedicated **Git Worktree** via `scripts/agent-workspace.sh create [ID]` (never raw `git worktree` commands) to isolate execution dependencies. It pulls `docs/agent-artifacts/task-scope-[ID].md` from the BA's `ba-scope/issue-[ID]` branch, and hard-fails rather than guessing if that branch is missing or the id doesn't match — treat that failure as "go back to BA," not something to work around by hand-copying a file in.
3. Symlinks essential `.env` variables and writes a scope-constraint note to `WORKTREE_SCOPE.md` in the new worktree directory root (not `CLAUDE.md`, which is already the real tracked file from the branch). `WORKTREE_SCOPE.md` is generated on disk only — gitignored, never staged or committed.



#### 👤 Developer Agent

* **Goal:** Construct and document the change.
* **Action:**
1. Switches context *strictly* to the isolated directory: `cd ../worktrees/issue-[ID]`.
2. Builds the features following the rules established in `CLAUDE.md` §4.
3. Finalizes the run with a clean, descriptive **Conventional Commit**:
`git commit -m "type(scope): precise descriptions matching issue-[ID]"`



#### 👤 Quality Assurance (QA) Agent

* **Goal:** Evaluate the built solution directly against the original design plan.
* **Action:**
1. Runs the test execution suite in the isolated worktree (`npm run test`;
for Apex, `sf project deploy validate --target-org gtm-staging` (checkOnly)
plus `sf apex run test --class-names <targeted classes> --target-org gtm-staging` when those classes are already live in the org; never a real
deploy and never `RunLocalTests`, see `docs/runbooks/api-request-budget.md`).
If genuine test-execution numbers require a real deploy (e.g. new test
classes not yet live), that is a blocker to hand back to the
coordinator/owner, not something QA runs itself.
2. Inspects modifications line-by-line against `docs/agent-artifacts/task-scope-[ID].md` and `GtmAgentToolSurface` contracts.
3. **Pass:** Pushes the target worktree branch to origin, opens a PR, and triggers cleaning: `git worktree remove ../worktrees/issue-[ID]`.
4. **Fail:** Drops a `TEST_FAILURES.log` block file inside the worktree workspace and routes control directly back to the Developer Agent.



### B. Agent-on-Agent Coding Boundaries

* **No Shared Filesystem Collisions:** Separate active sub-tasks must utilize distinct Git Worktree workspaces. Two sub-agents must never execute operations inside the same exact folder directory concurrently.
* **The Propose-vs-Commit Contract:** Any agent modifying GUS (Name TBD)'s tool surfaces is bound by the same no-DML/no-callout-inside-a-tool contract GUS (Name TBD)'s own tools follow (`GtmAgentToolSurface`) — don't add a "convenience" DML statement inside a tool implementation to save a round trip; it breaks the separation between "propose" and "commit" that lets a rep review GUS (Name TBD)'s readout edits before they persist.

### C. Org Request Discipline

* `gtm-dev` is locked (its API request limit was exceeded); repo scripts refuse it via `scripts/lib/sfx` unless both `--allow-production` and `GTM_ALLOW_PRODUCTION=1` are present. Do not set either while the lock stands.
* Agent org work targets `gtm-staging`, always with an explicit `--target-org`; the machine default org is never used.
* Run org-bound repo scripts (`deploy.sh`, `check-all.sh`, `check-org-drift.py`) as written; do not call `sf` around the wrapper.
* Follow `docs/runbooks/api-request-budget.md` (targeted tests, no needless retrieve-back or dry run, batch deploys).
* Report the `sf calls this run` summary in the QA log when a run touched an org.
