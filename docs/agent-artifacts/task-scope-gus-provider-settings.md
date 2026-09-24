# TASK SCOPE — ISSUE #gus-provider-settings

## 1. Requirements Breakdown

- **Target Objective:** GUS (the app's chat assistant) is currently hardcoded 100% to Anthropic's Messages API inside `GtmAgentProxyController`. Add support for OpenAI's Chat Completions API as a second, peer HTTP provider, selectable by an admin via a generic "Chat provider" setting on the existing `GTM_Offerings_Settings` tab. Anthropic remains the default and must behave identically to today when selected (back-compat is mandatory, not best-effort). Agentforce is explicitly out of scope for this issue (see below) — the abstraction must not preclude adding it later, but no Agentforce code, stub, or placeholder should be written now.

  This is confirmed as a real, user-directed decision set, not an assumption on my part:
  1. Scope Anthropic + OpenAI only, as peer HTTP-callout providers. Agentforce is a native platform agent invocation (no HTTP callout from this class), architecturally different, and is deferred to a distinct future platform-integration phase.
  2. Provider selection, API key(s), and any per-surface model override live on the real `GTM_Offerings_Settings` tab (via a new/modified LWC section rendered by `gtmOfferingsSettings`), not a new tab. Admin-only, matching the current Claude API key's visibility (`GTM_Offering_Admin` permission set only — confirmed via existing FLS grants below).
  3. The setting/label must be generic — "Chat provider" with "Anthropic" / "OpenAI" as named options — not "Claude-branded," since the same seam is meant to support other tools/models later.

  **Ambiguity flagged for the Architect, not resolved here:** the user's brief says "provider-specific API key storage (likely two separate protected custom-setting fields, one per provider, so switching doesn't require re-entering a key)" — "likely" signals this is not fully locked. The existing `GTM_Agent_Settings__c` custom setting is a Hierarchy custom setting with plain `Text` fields (not `EncryptedText` — note the *current* Claude key field is stored as a 255-char `Text` field, not `EncryptedText`, despite being described elsewhere as "protected"). The Architect must explicitly decide and document: (a) whether the new OpenAI key field should be `EncryptedText` (arguably more correct, but a real UX/behavior change from today's convention) or plain `Text` (matches existing precedent, keeps the pattern consistent), and (b) confirm field-level security alone — not platform encryption — is accepted as the protection boundary for both keys, since that is the status quo for `Claude_API_Key__c` today. Do not silently pick one; call it out in the architecture doc.

- **System Component Impacted:** Apex (`GtmAgentProxyController`, `GtmAgentSettingsController`, and a new provider-adapter class/seam), Custom Metadata/Custom Settings (`GTM_Agent_Settings__c` fields), LWC (`gtmOfferingsSettingsAgent`, rendered inside `gtmOfferingsSettings`), Permission Sets (`GTM_Offering_Admin`).

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? **NO** — `GtmAgentToolSurface` (interface: `systemPrompt`, `toolDefinitions`, `maxTokens`, `executeTool`) and its two implementations (`ConfigSurface` inline in `GtmAgentProxyController`, `GtmReadoutAgentSurface`) must NOT change their contract or shape. Provider swapping is confined to how `runLoop()`/`callClaude()` (or its renamed/refactored successor) makes the underlying chat-completion HTTP call and how it translates `toolDefinitions()`'s Anthropic-shaped tool defs into OpenAI's function-calling schema and normalizes the response back into Anthropic's `content`/`stop_reason` shape that `runLoop()` already expects (`tool_use` blocks, `text` blocks, `end_turn`/`tool_use` stop reasons). **This translation/normalization layer is the single biggest technical risk in this issue** — it must be isolated behind a clear seam (e.g., a small provider-strategy interface/class per provider, invoked from `runLoop()` in place of today's direct `callClaude()` call) and needs the heaviest test coverage of anything in this change, including edge cases: multi-tool-call turns, empty/partial content blocks, and provider-specific error/stop-reason shapes that don't map cleanly to Anthropic's. `executeToolCall` (zero-DML tool contract) stays wired into the surface exactly as today regardless of which provider produced the tool-call request — verify this explicitly during implementation and QA, not just assume it holds, since a naive OpenAI function-calling adapter could tempt a shortcut (e.g., DML slipped into a "helper" invoked mid-loop before all callouts finish). AGENTS.md §1's zero-DML rule for the tool surface stands unmodified.
- [x] Altering Custom Metadata? **NO custom metadata (`GTM_Assessment_*`) is touched.** This issue touches a **custom setting** (`GTM_Agent_Settings__c`, Hierarchy type), which is a different mechanism from the `migration-accelerator/` YAML-driven custom metadata described in CLAUDE.md §2 — that constraint does not apply here. New fields on `GTM_Agent_Settings__c` are ordinary SFDX field metadata, hand-authored the same way `Claude_API_Key__c`/`Claude_Model__c` already are.
- [x] Introducing database fields? **YES** — new fields on `GTM_Agent_Settings__c`:
  - `Chat_Provider__c` (Picklist: `Anthropic`, `OpenAI`; default `Anthropic` to preserve back-compat for orgs that never touch the new setting).
  - `OpenAI_API_Key__c` (field type per Architect decision above — `Text(255)` to match `Claude_API_Key__c` precedent, or `EncryptedText` if the Architect elects to tighten the pattern; document the choice).
  - Optionally `OpenAI_Model__c` (Text, mirroring `Claude_Model__c`) if a per-provider model override is scoped in by the Architect — the user's brief says "any per-tool/per-surface model override where relevant," which reads as optional/conditional, not mandatory; Architect should decide whether to include it in this issue or defer.
  - Mapping to Permission Sets is mandatory per CLAUDE.md §6: `GTM_Offering_Admin` must get `fieldPermissions` (readable+editable) on every new field, exactly matching the existing `Claude_API_Key__c`/`Claude_Model__c` grants. No other permission set should reference `GTM_Agent_Settings__c` (confirmed: today only `GTM_Offering_Admin` has `objectPermissions`/`fieldPermissions` on it).

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. With `Chat_Provider__c` left at its default/blank (Anthropic), `GtmAgentProxyController.chat()` and `.chatOnReadout()` behave byte-for-byte identically to pre-change behavior — same request shape to `api.anthropic.com/v1/messages`, same response parsing, same tool-use loop semantics, same error message on missing key. No regression for existing GUS users.
  2. With `Chat_Provider__c` set to `OpenAI` and a valid `OpenAI_API_Key__c` stored, both the configurator surface (`ConfigSurface`) and the readout surface (`GtmReadoutAgentSurface`) can complete a full multi-round tool-use conversation against OpenAI's Chat Completions API, with tool calls executed via the unchanged `GtmAgentToolSurface.executeTool()` contract and zero DML occurring between callouts.
  3. Admins (only) can view/set the provider picker and both providers' masked API key inputs from the `GTM_Offerings_Settings` tab's existing "Claude / GUS" section (relabeled generically, e.g. "GUS Chat Provider" or similar non-Claude-branded heading); non-admin profiles cannot see or edit these fields (FLS-enforced, consistent with current `Claude_API_Key__c` boundary).
  4. Switching providers does not require re-entering the previously-stored key for the provider not currently selected (each provider's key is stored/blanked independently, following the existing write-only/never-prefill UX pattern already implemented for the Claude key in `gtmOfferingsSettingsAgent.js`).
  5. All new and existing Apex/Jest tests pass; no plain-text secret appears in test assertions, logs, or committed fixtures (use dummy/mock keys only).

- **Target Test Target:**
  - Apex: `GtmAgentProxyControllerTest` (extend/add HTTP callout mock coverage for both the existing Anthropic path and the new OpenAI path — use `HttpCalloutMock` to simulate each provider's distinct response envelope, including a multi-round tool-use exchange for each), and `GtmAgentSettingsControllerTest` (extend for the new provider/key fields, covering read/write and the "blank key leaves stored key unchanged" semantics for both providers independently).
  - Jest: `force-app/main/default/lwc/gtmOfferingsSettingsAgent/__tests__/gtmOfferingsSettingsAgent.test.js` (extend for the provider picker control, per-provider key inputs, and independent blank-vs-unchanged save behavior per provider).

## 4. Architect Addendum — Ambiguity Resolutions

### 4.1 `OpenAI_API_Key__c` field type: **EncryptedText**

Decision: `OpenAI_API_Key__c` should be `EncryptedText`, not plain `Text(255)`.

Rationale:
- Verified in `GtmAgentSettingsController.cls`: the existing read/write pattern for `Claude_API_Key__c` is write-only from the client's perspective — `getSettings()` only ever returns `dto.hasApiKey = String.isNotBlank(settings.Claude_API_Key__c)` (a boolean), never the raw value, and `saveSettings()` treats a blank incoming value as "leave stored key unchanged." The LWC never prefills the key input.
- Apex is able to read the full, unmasked value of an `EncryptedText` field via SOQL/direct field access — encryption masking (showing only the last 4 chars) is a *UI-layer* restriction (List Views, standard page layouts, reports), not an Apex-layer one. `String.isNotBlank(settings.OpenAI_API_Key__c)` and `settings.OpenAI_API_Key__c = apiKey;` both continue to work unmodified. So EncryptedText introduces **no read-back limitation that would break the write-only/never-prefill UX pattern** — that pattern is already enforced at the controller/DTO boundary, not by the field type.
- EncryptedText gives platform-level encryption at rest plus automatic masking in any future ad hoc UI (Setup pages, list views, reports) that isn't mediated by this controller — a real hardening improvement with no functional downside given the confirmed controller pattern.
- Low risk to introduce for a brand-new field (no existing data, no migration needed).

**`Claude_API_Key__c` migration: explicitly deferred, NOT part of this issue.** Converting an existing `Text` field to `EncryptedText` is a destructive type change in Salesforce metadata terms — it is not a simple field-meta edit; it typically requires deleting and recreating the field (or a data-loss-risk conversion), which would blow away the currently-stored production Claude key on `gtm-dev` (Production, no staging — CLAUDE.md §1). That is out of proportion for this issue and must not be bundled in. Flagging as a separate, explicitly-scoped follow-up issue ("migrate Claude_API_Key__c to EncryptedText") so it gets its own deliberate rollout/re-entry plan, rather than silently breaking the stored prod key as a side effect of this change. This issue's `Claude_API_Key__c` field is untouched, type or otherwise — back-compat requirement (Success Metric #1) depends on that.

Net effect: the two provider key fields will have *different* field types (`Claude_API_Key__c` = Text, `OpenAI_API_Key__c` = EncryptedText) for the duration between this issue and the deferred follow-up. This is a knowingly-accepted, temporary inconsistency — documented here so it isn't mistaken for an oversight — in exchange for not risking prod data loss inside this issue's blast radius.

### 4.2 `OpenAI_Model__c` field: **in scope — include it**

Decision: yes, add `OpenAI_Model__c` (Text, mirroring `Claude_Model__c`) in this issue.

Rationale: it is a plain, low-cost `Text` field with no callout/DML/encryption complexity, directly symmetrical with the existing `Claude_Model__c` field, and the provider-adapter seam described in §2 already needs to resolve a model string per provider to build the outbound request. Leaving OpenAI without a model override while Claude has one would be an asymmetric, awkward half-implementation of "peer providers" — the issue's own stated goal. Include `OpenAI_Model__c` in the `GTM_Agent_Settings__c` field additions and in the `GTM_Offering_Admin` permission-set grant alongside `Chat_Provider__c` and `OpenAI_API_Key__c`.

### 4.3 Consolidated field list for this issue

New fields on `GTM_Agent_Settings__c` (all requiring `GTM_Offering_Admin` `fieldPermissions` grants per CLAUDE.md §6.1, in the same change):
- `Chat_Provider__c` — Picklist (`Anthropic`, `OpenAI`), default `Anthropic`.
- `OpenAI_API_Key__c` — **EncryptedText**, length 255 (max allowed for EncryptedText is 175 chars per Salesforce limits — verify OpenAI key length fits; if not, adjust length within EncryptedText's max and confirm real-world OpenAI `sk-...` key lengths fit before finalizing the field-meta).
- `OpenAI_Model__c` — Text(255), mirroring `Claude_Model__c`.

No other permission set should be touched — confirmed only `GTM_Offering_Admin` currently references `GTM_Agent_Settings__c`.

— Architect, provisioned via `scripts/agent-workspace.sh create gus-provider-settings`.
