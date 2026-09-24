# TASK SCOPE — ISSUE #gus-settings-provider-ui

## 1. Requirements Breakdown

- **Target Objective:** Make the GUS chat-provider settings form provider-aware and fix a latent runtime bug. (a) The provider dropdown lists vendor product names and the form shows ONLY the selected provider's inputs. (b) Add Gemini as a third HTTP provider adapter. (c) Add the missing Remote Site Settings, since the merged OpenAI provider (PR #215) will throw "Unauthorized endpoint" at runtime. (d) Add Agentforce as a selectable, saved-but-inactive provider.
- **System Component Impacted:** LWC `gtmOfferingsSettingsAgent` (GTM_Offerings_Settings tab); Apex `GtmAgentSettingsController`, `GtmAgentProxyController` and their tests; Hierarchy Custom Setting `GTM_Agent_Settings__c` (new Text fields); `remoteSiteSettings/` (new); `GTM_Offering_Admin` permission set. No YAML instrument impact. `GtmAgentToolSurface` interface is unchanged.

### Verified current state (read from code, not from specs)

- `GtmAgentSettingsController`: `VALID_CHAT_PROVIDERS = {'Anthropic','OpenAI'}`, and `setAgentSettings(apiKey, model, chatProvider, openAiApiKey, openAiModel)`. A blank key means "leave unchanged". `AgentSettingsDto` exposes only `hasApiKey`, `model`, `chatProvider`, `hasOpenAiApiKey`, `openAiModel`. Raw keys are never returned.
- `GtmAgentProxyController`: `runLoop()` picks the provider via `getProvider()`, defaulting to Anthropic when blank. It then calls `callOpenAi` or `callClaude`. `callOpenAi` translates tools through `openAiToolsFromToolDefinitions` and history through `openAiMessagesFromHistory`. `normalizeOpenAiResponse` maps the response back to `{stop_reason:'end_turn'|'tool_use'|..., content:[blocks]}`. History is always stored in Anthropic shape so providers can be switched mid-session. `getApiKey` and `getModel` branch on the provider. Any non-OpenAI value currently falls through to Claude.
- `force-app/main/default/remoteSiteSettings/` contains only `Anthropic_API`, three `Brand_Logo_*`, and `Conduit_Local`. **There is no `api.openai.com` entry (confirmed bug).**
- There are no `namedCredentials/` or `externalCredentials/` directories, so the repo does not use Named Credentials anywhere. Match the RemoteSiteSetting convention (`Anthropic_API.remoteSite-meta.xml`).
- `GTM_Agent_Settings__c` has 5 fields: `Chat_Provider__c`, `Claude_API_Key__c`, `Claude_Model__c`, `OpenAI_API_Key__c`, `OpenAI_Model__c`. All are Text, and all five have `fieldPermissions` on `GTM_Offering_Admin` only.
- Existing LWC: two flat key/model input groups, and only `isOpenAiSelected` exists. It has write-only key inputs, a `hasApiKey` status line, and a revert-on-save-failure pattern. Tests are in `lwc/gtmOfferingsSettingsAgent/__tests__/gtmOfferingsSettingsAgent.test.js`.
- `scripts/check-references.py` line ~1449 already validates `remoteSiteSettings`, so new files must be well formed. The runbook `docs/runbooks/fresh-org-deploy.md` (line 57) says "Anthropic_API and five other remote site settings", so the count there needs updating.

### Requirements

1. **Dropdown labels and stored values.** Stored values are in the second column; keep `Anthropic` and `OpenAI` unchanged.

   | Label | Stored `Chat_Provider__c` |
   |---|---|
   | Anthropic (Claude) | `Anthropic` |
   | OpenAI (GPT) | `OpenAI` |
   | Google (Gemini) | `Gemini` |
   | Agentforce (Salesforce) | `Agentforce` |

   Update `VALID_CHAT_PROVIDERS` and the error message. The check stays case-sensitive.
   - The BA had no web access in this run. The names below come from training knowledge, so **the Architect must confirm them against current vendor docs before finalizing**.
   - Gemini: the "Gemini Developer API" (Google AI for Developers). Endpoint is `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`, and auth is the `x-goog-api-key` header. Prefer the header over the `?key=` query param so the key never lands in URLs or logs. Model ids are `gemini-*` (e.g. `gemini-2.5-flash`, `gemini-2.5-pro`). Current model ids may have moved on by now, so pick the default from the docs.
   - OpenAI: the current adapter targets Chat Completions (`/v1/chat/completions`, default `gpt-4o`). OpenAI now positions the Responses API as the primary endpoint, but Chat Completions remains supported. Do NOT migrate in this issue. Just confirm that the default model id is still valid.
   - The Architect should also record the exact Gemini request and response shapes in the `docs/architecture/` contract (CLAUDE.md §4, contract first). Expected shape: request `{systemInstruction:{parts:[{text}]}, contents:[{role:'user'|'model', parts:[{text}|{functionCall:{name,args}}|{functionResponse:{name,response}}]}], tools:[{functionDeclarations:[{name,description,parameters}]}]}`. Response is `candidates[0].content.parts[]`, with `finishReason` `STOP` and so on.

2. **Conditional form.** Render only the inputs for the selected provider. Use `if:true`/`lwc:if` or a getter-driven section, not CSS hiding, so that hidden inputs are not in the DOM.
   - Anthropic: key and model. OpenAI: key and model. Gemini: key and model.
   - Agentforce: see item 5.
   - API key inputs are never prefilled. Keep the `hasKey` status line for each provider. Keep a single Save.
   - Switching the dropdown must not clear or overwrite another provider's saved values. Keep all values in component state and always send them all to Apex, where a blank key means "unchanged". The existing pattern already sends the non-selected provider's model as-is, so keep that. The Architect must confirm that a model field for an unselected provider that was never edited is not blanked to null on save. Note that the current Apex assigns `settings.Claude_Model__c = model` unconditionally, so a null or blank value wipes a saved model. Decide whether to keep that or treat blank as "unchanged" for models too.
   - `AgentSettingsDto` gains the new fields (`hasGeminiApiKey`, `geminiModel`, and the Agentforce fields). Still no raw key or secret in any DTO.
   - `setAgentSettings` already takes 5 positional args. The signature must grow, so the Architect should consider a single `AgentSettingsInput` `@AuraEnabled` wrapper class instead of ~10 positional params. The LWC and every existing test call site change either way.

3. **Gemini adapter.** Add `callGemini()`, `normalizeGeminiResponse()`, `geminiToolsFromToolDefinitions()` and `geminiContentsFromHistory()` in `GtmAgentProxyController`, mirroring the OpenAI peer methods.
   - History stays Anthropic-shaped; the translation happens only at request time.
   - Gemini roles are `user` and `model`.
   - Tool results become `functionResponse` parts.
   - Gemini function calls carry no call id, so the Architect must decide how to synthesize `tool_use` ids (e.g. `gemini_<index>`). This must round-trip through history: `tool_result` → `functionResponse` needs a `name` lookup from the matching earlier `tool_use` block.
   - Gemini's function-declaration schema is an OpenAPI subset. Confirm that the current tool `input_schema`s from the surfaces only use supported keywords, and strip unsupported ones such as `additionalProperties` if present.
   - Normalized `stop_reason`: `STOP` → `end_turn`; when any `functionCall` part is present → `tool_use`; anything else → `gemini_<finishReason>`, mirroring OpenAI. Handle an empty candidate or a `promptFeedback` block without throwing a NullPointerException.
   - Non-200 responses throw with a status and body, like `callOpenAi`. Take care that the error body never echoes the key.
   - `getApiKey`, `getModel`, and the missing-key error message in `runLoop` get a Gemini branch. Default model constant, e.g. `DEFAULT_GEMINI_MODEL`.
   - Zero-DML holds: the adapter only builds HTTP requests, and tools still run only through `GtmAgentToolSurface.executeTool`. `GtmAgentToolSurface` is unchanged.

4. **Remote Site Settings (real bug).** Add `OpenAI_API.remoteSite-meta.xml` (`https://api.openai.com`) and `Google_Gemini_API.remoteSite-meta.xml` (`https://generativelanguage.googleapis.com`). Each has `isActive` true, `disableProtocolSecurity` false, and a description matching the Anthropic file's style.
   - Named Credentials are the Salesforce-recommended modern pattern. Nothing in this repo uses them, and Anthropic's key is read from the Custom Setting, so a Named Credential would mean re-plumbing key storage. Recommendation: RemoteSiteSetting now, and note the Named Credential migration as a follow-up. There is no strong reason to deviate.
   - Update the runbook count and its callout list, and `AGENTS.md` §1 (which says only Anthropic is authorized). Doc updates are for the Developer.
   - Mocked Apex tests cannot catch a missing Remote Site Setting. QA must do a live callout smoke test after deploy, and the deploy step needs the remoteSiteSettings pass (both `deploy.sh` and `deploy-fresh-org.sh` already deploy that directory; the Architect should confirm).

5. **Agentforce (saved but inactive).** The dropdown lists it, and the form shows the Setup-side configuration an integration needs. Working assumption from training knowledge, **which the Architect must verify against Salesforce docs (Agent API)** per the memory rule "check Salesforce docs before custom-building":
   - Calling an agent from outside uses the Agentforce Agent API. Roughly: create a session with `POST https://api.salesforce.com/einstein/ai-agent/v1/agents/{agentId}/sessions`, send messages to `.../sessions/{sessionId}/messages`, and end the session.
   - Auth is an OAuth 2.0 client-credentials flow against the org's My Domain, using an External Client App (or legacy Connected App) with the `chatbot_api` / `sfap_api` scopes and the client-credentials flow enabled.
   - So the settings needed are: Agent ID (18-char, of the published agent), My Domain URL, and consumer key and secret. The alternative is a Named Credential and External Credential holding the consumer key and secret, which would avoid storing the secret in the Custom Setting.
   - New Text fields (working names): `Agentforce_Agent_Id__c`, `Agentforce_My_Domain_URL__c`, `Agentforce_Client_Id__c`, `Agentforce_Client_Secret__c`. Secrets follow the same write-only/never-prefill/has-flag rule as the API keys, and each has FLS on `GTM_Offering_Admin`. **The Custom Setting cannot encrypt them.**
   - The form shows the inline notice: "Saved for the upcoming Agentforce integration — GUS still uses the previously active provider until that ships."
   - `runLoop()` must NOT call Agentforce. If `Chat_Provider__c == 'Agentforce'`, resolve to a working provider and never throw because of the provider value. Fallback rule (see fork 2): Anthropic if it has a key, else the first of OpenAI or Gemini with a key, else the existing "Claude API key not configured" error. That last case is the pre-existing missing-key behaviour and is not a new failure mode.
   - No Remote Site Setting for `api.salesforce.com` or the My Domain is needed yet, because nothing calls out. That belongs to the later phase.
   - AGENTS.md §1 says the dormant bot and genAiPlugin metadata must not be wired up by accident. This issue does not touch the `bots/` or `genAiPlugins/` metadata.

6. **Tests.** See §3.

### Open design forks (Architect to resolve, not guessed here)

1. **Agentforce secret storage.** The consumer secret in a plain-Text Hierarchy Custom Setting is readable by anyone with the setting's field access, and by any Apex code. Options: (A) store it in plain Text like the API keys today, and accept that; (B) keep only Agent ID and My Domain in the setting and defer the secret to a Named Credential and External Credential in the later phase. The user asked to "include the Agentforce configs needed from Setup". Recommendation: B for the secret, plus a note in the form that the secret is configured in Setup, but this is a human/Architect call.
2. **"Last working provider" fallback.** The requirement says to fall back to the "previously active" provider, but `Chat_Provider__c` is overwritten with `Agentforce` on save, so the previous value is lost. Options: (A) a stateless fallback, i.e. Anthropic, then other providers that have keys; (B) add a `Previous_Chat_Provider__c` Text field that is set on save when the provider changes to `Agentforce`. Recommendation: A, since it needs no new field. Then the inline notice should say "GUS uses the first configured provider (Anthropic by default)" rather than "previously active".
3. **`setAgentSettings` signature.** Positional args vs an input wrapper (see item 2). It affects all Apex and Jest call sites.
4. **Model blanking semantics** (see item 2).
5. **Vendor names and model defaults.** Verify them, since the BA had no web access.

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? YES, but only indirectly. The Gemini adapter consumes `GtmAgentToolSurface` tool definitions and does not change the interface or any surface class. The zero-DML rule in AGENTS.md §1 must hold: no DML or callouts inside `executeTool`, and the callout happens only in `runLoop`. Add an explicit test assertion, e.g. `Limits.getDmlStatements() == 0` around a Gemini chat turn that includes a tool call. The settings save in `GtmAgentSettingsController` does DML by design (admin config), and that is not the GUS tool path.
- [ ] Altering Custom Metadata? NO. `GTM_Agent_Settings__c` is a Hierarchy Custom Setting, not `__mdt`, and no `migration-accelerator/` or instrument YAML is touched. (Note that `migration-accelerator/` does not exist in this repo; the layout is `instrument/<offering-key>/`.)
- [x] Introducing database fields? YES. New Text-only fields on `GTM_Agent_Settings__c`: `Gemini_API_Key__c`, `Gemini_Model__c`, `Agentforce_Agent_Id__c`, `Agentforce_My_Domain_URL__c`, `Agentforce_Client_Id__c`, `Agentforce_Client_Secret__c` (final list per the Architect and fork 1). No Picklist or EncryptedText, per PR #221. Each needs `fieldPermissions` (readable and editable) in `GTM_Offering_Admin.permissionset-meta.xml`. The custom setting is admin-only by design, so `GTM_Offering_User`, the Content sets and `GTM_Guest` get nothing. Also add new `remoteSiteSettings` files. Run `python3 scripts/check-references.py` and confirm it passes.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. The dropdown shows exactly four options with the labels above. Selecting a provider renders only that provider's inputs. No key or secret input is ever prefilled, and the `hasKey` status lines are correct.
  2. Switching providers back and forth without saving, and saving one provider, never alters another provider's stored key or model.
  3. `setAgentSettings` accepts `Anthropic`, `OpenAI`, `Gemini` and `Agentforce`, blank (defaults to Anthropic), and rejects anything else, including wrong-case values.
  4. With `Gemini` selected, `runLoop` sends the correct request (URL, `x-goog-api-key` header, model in the path, `systemInstruction`, `functionDeclarations`) and handles both a plain-text response and a `functionCall` → `functionResponse` → final-text multi-round exchange. It returns the same `{stop_reason, content}` shape as the other adapters, with zero DML.
  5. With `Agentforce` selected, chat does not throw because of the provider and does not call Agentforce. It falls back per the Architect's fork-2 decision.
  6. `OpenAI_API` and `Google_Gemini_API` remote sites exist, and `check-references.py` passes.
  7. Live smoke test in `gtm-dev`, which is treated as Production (per CLAUDE.md), so do this only with the human's go-ahead. Before deploying to gtm-dev, confirm that a real OpenAI or Gemini callout is not blocked as "Unauthorized endpoint". QA must also verify the Settings tab in the browser and every other dependent surface (`gtmAgentChat`, `gtmReadoutAssist`) still works on the default Anthropic provider (memory: QA validates live in the browser).
  8. No key or secret appears in any DTO, toast, log or error message.
- **Target Test Target:**
  - Apex: `GtmAgentSettingsControllerTest` (allow-list including `Gemini` and `Agentforce` and a rejected value, blank-key-unchanged for each provider, and no raw key or secret in the DTO). `GtmAgentProxyControllerTest` (new Gemini tests using an `HttpCalloutMock` that asserts endpoint, header, request body and function-call round trip, a non-200 error test, a zero-DML assertion, and an Agentforce-selected fallback test). Also run `GtmAgentProxyControllerReadoutTest`, to confirm the readout surface still works after the `runLoop` changes.
    - `sf apex run test --class-names GtmAgentSettingsControllerTest,GtmAgentProxyControllerTest,GtmAgentProxyControllerReadoutTest --result-format human --synchronous`. Use the dev org only with human approval, since `gtm-dev` is Production. The repo's `deploy.sh --run-tests` is the same risk.
  - LWC Jest: `npx jest force-app/main/default/lwc/gtmOfferingsSettingsAgent`, i.e. the `__tests__/gtmOfferingsSettingsAgent.test.js` spec. Cases: exactly four dropdown options and labels; only the selected provider's inputs in the DOM; API key inputs empty after load even when `hasKey` is true; switching provider and back keeps the typed model values; the Agentforce notice is visible only when Agentforce is selected; the save payload contains all values; revert on save failure.
  - Static: `python3 scripts/check-references.py`, plus `npm test` for the full Jest suite.

---

## 4. Architect Addendum (resolves open forks; authoritative over sections 1-3 where they differ)

Review result: scope has no placeholders. Checklist verified: tool surface unchanged (zero-DML/zero-callout-in-tool holds; the callout stays in `runLoop`); no `__mdt`/instrument YAML touched; new fields need `GTM_Offering_Admin` grants only (custom setting is admin-only). `deploy.sh` (dynamic top-level folder list) and `deploy-fresh-org.sh` (pass 2 lists `remoteSiteSettings`) both already deploy the new RemoteSiteSetting files. No Named Credentials are used in the repo today.

### 4.1 Vendor facts (coordinator web-verified 2026-09-19)

- Dropdown labels (final, replaces the table in 1.1): "Anthropic (Claude)", "OpenAI (GPT)", "Google Gemini", "Salesforce Agentforce". Stored `Chat_Provider__c`: `Anthropic`, `OpenAI`, `Gemini`, `Agentforce` (case-sensitive allow-list).
- Gemini Developer API: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`, auth header `x-goog-api-key` (never the `?key=` param). Google labels `generateContent` "legacy" (the Interactions API is the new default) but it remains supported; this issue uses `generateContent`. Record that note in the contract doc. Migration to Interactions is a follow-up, not this issue.
- Gemini model id is a free-text admin field (`Gemini_Model__c`) with a default constant `DEFAULT_GEMINI_MODEL` the admin can override. Model names change often, so never make the default the only option; put a comment saying the default is a convenience and may go stale. Developer picks a currently valid default (`gemini-2.5-flash` was the BA's suggestion; use it unless the Developer has newer confirmed information from the coordinator).
- OpenAI stays on Chat Completions. Remote Site host `api.openai.com` is currently MISSING (runtime "Unauthorized endpoint" bug from PR #215). Add it.
- Agentforce Agent API needs an External Client App with client-credentials OAuth (consumer key + secret), the org My Domain URL, and the agent ID. The Agent API does not support agents of type "Agentforce (Default)". Show that last point as help text on the form.

### 4.2 Fork decisions

1. **Agentforce secret storage: option B.** Custom setting gets ONLY `Agentforce_Agent_Id__c`, `Agentforce_My_Domain_URL__c`, `Agentforce_Client_Id__c` (consumer KEY; it is an identifier, not a secret, and is stored as ordinary Text, and it may be returned in the DTO). NO `Agentforce_Client_Secret__c` field and no secret input anywhere in the LWC. The form shows a note: "The consumer secret is not stored here. It will be captured via a Named Credential in the later integration phase." Agent ID, My Domain URL and consumer key are visible (prefilled) values, not write-only, since none is a secret. Validation: trim; My Domain URL, if non-blank, must start with `https://`, otherwise AuraHandledException; strip a trailing slash.
2. **Agentforce selected: stateless fallback (option A).** No `Previous_Chat_Provider__c`. Add a helper `resolveEffectiveProvider(settings)` used by `runLoop`, `getApiKey`, `getModel`: if provider is `Agentforce`, effective = Anthropic if it has a key, else OpenAI if it has a key, else Gemini if it has a key, else Anthropic (so the existing "Claude API key not configured" message surfaces; that is pre-existing behaviour, not a new failure). Never throws on the provider value. Agentforce is never called. Inline notice, exact text: "Saved for the upcoming Agentforce integration — GUS will keep using the first configured provider until it ships." Shown only when Agentforce is selected.
3. **Signature: input wrapper.** Replace the positional method with:
   `@AuraEnabled public static void setAgentSettings(AgentSettingsInput input)` where `AgentSettingsInput` is a public `with sharing`-neutral inner class with `@AuraEnabled public String` members: `chatProvider, apiKey, model, openAiApiKey, openAiModel, geminiApiKey, geminiModel, agentforceAgentId, agentforceMyDomainUrl, agentforceClientId`. The LWC calls `setAgentSettings({ input: { ... } })` (Apex param name `input` is the wrapper key). `AgentSettingsDto` gains: `hasGeminiApiKey`, `geminiModel`, `agentforceAgentId`, `agentforceMyDomainUrl`, `agentforceClientId`. No raw key or secret in any DTO.
   Call sites that MUST change (complete list from grep):
   - Apex: `/force-app/main/default/classes/GtmAgentSettingsController.cls` line 73 (definition).
   - Apex tests in `GtmAgentSettingsControllerTest.cls`, all `setAgentSettings(` calls at lines 19, 41, 45, 60, 81, 82, 86, 102, 114, 134. Note line 114 (`invalidChatProviderIsRejected`) uses `'Gemini'` as its INVALID value; Gemini is now valid, so change it to an unlisted value such as `'Grok'`. Line 134 (case-sensitivity) stays as lowercase `'anthropic'`.
   - LWC: `lwc/gtmOfferingsSettingsAgent/gtmOfferingsSettingsAgent.js` line 128 (`setAgentSettings({ apiKey, model, chatProvider, openAiApiKey, openAiModel })`).
   - Jest: `lwc/gtmOfferingsSettingsAgent/__tests__/gtmOfferingsSettingsAgent.test.js`, the `toHaveBeenCalledWith` assertions at lines 88 and 152, plus any at ~163+ (re-grep). Also `lwc/gtmOfferingsSettings/__tests__/gtmOfferingsSettings.test.js` line 20 only mocks the module (no signature dependence); verify it still passes, no edit expected.
   - Re-run `grep -rn setAgentSettings force-app` before finishing to confirm zero stale call sites.
4. **Blank model on save = leave that provider's stored value unchanged**, for ALL providers including the existing Claude and OpenAI models (this changes the current unconditional `Claude_Model__c = model` assignment). A blank/whitespace model never nulls a stored value. Consequence: an admin cannot clear a model back to blank via the form (the runtime default constant applies only when unset); that is accepted. Add Apex tests asserting saving one provider with other models blank leaves those models intact.
5. **Vendor names/defaults:** resolved in 4.1.

### 4.3 Additional developer notes

- New fields (Text, admin-only, no Picklist/EncryptedText per PR #221): `Gemini_API_Key__c`, `Gemini_Model__c`, `Agentforce_Agent_Id__c`, `Agentforce_My_Domain_URL__c`, `Agentforce_Client_Id__c`. Add `fieldPermissions` (readable+editable) for each to `GTM_Offering_Admin.permissionset-meta.xml` in the same change. Match the length/description conventions of the existing five fields.
- Gemini tool schema: current schemas use only `type`, `properties`, `description`, `required`, `enum`. Some have an empty `properties` and empty `required` (GtmReadoutAgentSurface lines ~129-144; proxy lines 76-83). Gemini rejects empty `required` arrays and OBJECT types with empty `properties`, so in `geminiToolsFromToolDefinitions`: omit `required` when empty and omit `parameters` entirely when `properties` is empty; also strip `additionalProperties` defensively.
- Synthesize `tool_use` ids as `gemini_<n>` with a per-response counter; `geminiContentsFromHistory` resolves `functionResponse.name` by looking up the `tool_use` block whose id equals the `tool_result.tool_use_id` earlier in history. Wrap the tool result string as `response: {result: <string>}`.
- Gemini errors: throw with status and body only; never include the key (it is in a header, so do not log the request).
- Runbook `docs/runbooks/fresh-org-deploy.md` line 57 count (Anthropic + OpenAI + Gemini + 3 Brand_Logo + Conduit_Local) and `AGENTS.md` §1 (authorised callout hosts now Anthropic, OpenAI, Gemini) must be updated. Write the contract to `docs/architecture/` first (CLAUDE.md §4), including exact Gemini request/response shapes, the fallback rule, and the wrapper signature.
- Remote sites: `OpenAI_API.remoteSite-meta.xml` -> `https://api.openai.com`; `Google_Gemini_API.remoteSite-meta.xml` -> `https://generativelanguage.googleapis.com`. Follow the `Anthropic_API` file format exactly. Named Credential migration is a noted follow-up.

### 4.4 Testing and QA constraints (binding)

- A mocked Jest/Apex test CANNOT catch a missing Remote Site Setting. QA must therefore verify by inspection that exactly two new files exist, `force-app/main/default/remoteSiteSettings/OpenAI_API.remoteSite-meta.xml` and `Google_Gemini_API.remoteSite-meta.xml`, are `isActive` true, and that their `<url>` values match the host of `OPENAI_URL` and the new Gemini URL constant in `GtmAgentProxyController` (scheme + host, no path). Also run `python3 scripts/check-references.py`.
- Live provider callouts (OpenAI, Gemini, or anything else) against `gtm-dev` are NOT authorised. `gtm-dev` is Production; a real callout smoke test needs the human's own go-ahead. Developer and QA must not deploy to gtm-dev, run Apex tests there, or make live calls, and the "live smoke test" in acceptance item 7 is reduced to a deferred, human-gated step. QA verification is limited to Jest, the static checks, and code/metadata inspection unless the human grants access directly. Any Settings-tab browser check or org deploy likewise requires the human's direct approval.
