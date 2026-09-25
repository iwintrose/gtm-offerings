# GUS Chat Provider Settings (contract)

Issue: gus-settings-provider-ui. Source of truth for the settings form, the
Apex wrapper, the Gemini adapter and the Agentforce placeholder. Extends the
provider seam introduced with the OpenAI adapter (PR #215).

## 1. Providers

| Dropdown label | Stored `Chat_Provider__c` | Runtime |
|---|---|---|
| Anthropic (Claude) | `Anthropic` | `callClaude` |
| OpenAI (GPT) | `OpenAI` | `callOpenAi` (Chat Completions, unchanged) |
| Google Gemini | `Gemini` | `callGemini` (`generateContent`) |
| Salesforce Agentforce | `Agentforce` | Never called. Saved config only; `runLoop` falls back (section 5) |

The allow-list is case-sensitive. A blank value saves as `Anthropic`. Any
other value throws `AuraHandledException` before DML.

## 2. Schema: `GTM_Agent_Settings__c` (Hierarchy Custom Setting)

Text fields only (no Picklist, no EncryptedText). FLS is on
`GTM_Offering_Admin` only (readable + editable).

Existing: `Chat_Provider__c`, `Claude_API_Key__c`, `Claude_Model__c`,
`OpenAI_API_Key__c`, `OpenAI_Model__c`.

New:

| Field | Length | Notes |
|---|---|---|
| `Gemini_API_Key__c` | 175 | Secret. Write-only, never returned |
| `Gemini_Model__c` | 100 | Default `gemini-2.5-flash` if blank (convenience only, may go stale) |
| `Agentforce_Agent_Id__c` | 50 | Not a secret; returned in the DTO |
| `Agentforce_My_Domain_URL__c` | 255 | Not a secret; must start `https://`, trailing slash stripped |
| `Agentforce_Client_Id__c` | 255 | OAuth consumer KEY (identifier, not secret); returned in the DTO |

There is deliberately NO Agentforce consumer secret field. The secret will be
captured via a Named Credential / External Credential in the later
integration phase. Nothing in the LWC accepts a secret for Agentforce.

## 3. Apex contract: `GtmAgentSettingsController`

```apex
public class AgentSettingsInput {
    @AuraEnabled public String chatProvider;
    @AuraEnabled public String apiKey;          // Claude key
    @AuraEnabled public String model;           // Claude model
    @AuraEnabled public String openAiApiKey;
    @AuraEnabled public String openAiModel;
    @AuraEnabled public String geminiApiKey;
    @AuraEnabled public String geminiModel;
    @AuraEnabled public String agentforceAgentId;
    @AuraEnabled public String agentforceMyDomainUrl;
    @AuraEnabled public String agentforceClientId;
}
@AuraEnabled public static void setAgentSettings(AgentSettingsInput input)
```

LWC calls `setAgentSettings({ input: { ... } })`.

`AgentSettingsDto` fields: `hasApiKey, model, chatProvider, hasOpenAiApiKey,
openAiModel, hasGeminiApiKey, geminiModel, agentforceAgentId,
agentforceMyDomainUrl, agentforceClientId`. No raw key or secret is ever
returned.

Save semantics:

- Blank/whitespace API key = leave the stored key unchanged (each provider).
- Blank/whitespace MODEL = leave the stored model unchanged, for ALL providers
  (Claude and OpenAI included; this replaces the old unconditional
  assignment). A model cannot be cleared via the form.
- Agentforce fields: trimmed. Blank input leaves the stored value unchanged.
  A non-blank My Domain URL not starting with `https://` throws
  `AuraHandledException`; a trailing `/` is stripped.
- A null `input` is treated as an empty input (provider defaults to Anthropic,
  nothing else changes).

## 4. Gemini adapter (`GtmAgentProxyController`)

Constants: `GEMINI_BASE_URL = 'https://generativelanguage.googleapis.com'`,
endpoint `GEMINI_BASE_URL + '/v1beta/models/' + model + ':generateContent'`,
`DEFAULT_GEMINI_MODEL = 'gemini-2.5-flash'`.

Note: Google labels `generateContent` as "legacy" (the Interactions API is the
new default) but it remains supported. Migration is a follow-up.

Request (`POST`, headers `Content-Type: application/json` and
`x-goog-api-key: <key>`; the key is never in the URL, body, or an error
message):

```json
{
  "systemInstruction": { "parts": [ { "text": "<surface.systemPrompt>" } ] },
  "contents": [
    { "role": "user",  "parts": [ { "text": "..." } ] },
    { "role": "model", "parts": [ { "text": "..." }, { "functionCall": { "name": "...", "args": {} } } ] },
    { "role": "user",  "parts": [ { "functionResponse": { "name": "...", "response": { "result": "<tool result string>" } } } ] }
  ],
  "tools": [ { "functionDeclarations": [ { "name": "...", "description": "...", "parameters": { } } ] } ],
  "generationConfig": { "maxOutputTokens": <surface.maxTokens> }
}
```

`tools` is omitted when there are no tool definitions.

Schema rules for `functionDeclarations[].parameters` (derived from the
Anthropic `input_schema`):

- Keep only OpenAPI-subset keys; strip `additionalProperties` (recursively).
- Omit `required` when empty.
- Omit `parameters` entirely when `properties` is empty/missing.

History stays Anthropic-shaped; translation happens only when building the
request. Assistant -> `model`; user -> `user`. `tool_use` -> `functionCall`;
`tool_result` -> `functionResponse`, with `name` resolved by finding the
earlier `tool_use` block whose `id` equals the `tool_result.tool_use_id`.
Tool result string is wrapped as `response: { result: <string> }`.

Response: `candidates[0].content.parts[]` (text parts, `functionCall` parts)
and `candidates[0].finishReason`. Normalised to `{stop_reason, content}`:

- any `functionCall` part -> `stop_reason 'tool_use'`, one `tool_use` block per
  call with synthesised id `gemini_<n>` (per-response counter from 0) and
  `input = args`.
- else `finishReason == 'STOP'` -> `end_turn` (text parts concatenated into one
  text block if non-blank).
- else `gemini_<finishReason>`; no candidates (or a `promptFeedback` block with
  no candidate) -> `gemini_no_candidates`. Never throws an NPE.

Non-200: `CalloutException('Gemini API returned <status>: <body>')`. The request
(and therefore the key) is not logged or echoed.

Zero-DML holds: the adapter only builds HTTP requests; tools run only via
`GtmAgentToolSurface.executeTool` (interface and surfaces unchanged).

## 5. Agentforce fallback (stateless) — until `runtime` issue ships

`resolveEffectiveProvider(settings)` is used by `runLoop`, `getApiKey` and
`getModel`. If the stored provider is `Agentforce`, the effective provider is
Anthropic if it has a key, else OpenAI if it has a key, else Gemini if it has a
key, else Anthropic (surfacing the existing "Claude API key not configured"
error, which is pre-existing behaviour). Any other stored value passes
through (unknown values behave as before: Claude). Never throws on the
provider value. Agentforce is never called.

Form notice, shown only when Agentforce is selected: "Saved for the upcoming
Agentforce integration — GUS will keep using the first configured provider
until it ships." Help text: the Agent API needs an External Client App with
client-credentials OAuth, and does not support agents of type "Agentforce
(Default)". Note: "The consumer secret is not stored here. It will be captured
via a Named Credential in the later integration phase."

This section (5) describes the CURRENT runtime behavior and is unchanged by
`gus-live-agentforce-provider-auth`. `runLoop` still never calls Agentforce —
that switch-over is `gus-live-agentforce-provider-runtime`'s job, gated on
§5a below being fully filled in with live-verified facts, not assumptions.

## 5a. Agentforce live activation (issue `gus-live-agentforce-provider-auth`)

> STATUS: Credential chain confirmed live and metadata reconciled against a
> real `sf project retrieve` (2026-09-25). **The Agent API endpoint itself
> is still NOT smoke-tested end-to-end** — see "Open item" at the end of
> this section. Do not let `runtime` start coding against the request/
> response shape below as final; it is still unconfirmed.

### Activation path chosen

CONFIRMED (coordinator, live gtm-staging Setup, 2026-09-24/25): the org has
moved to Agent Script / Agentforce Builder as the only creation path for a
first agent (Setup → Agentforce Studio → Agentforce Agents → "New Agent" →
"Create Agents in the New Agentforce Builder" → `AgentAuthoring/agentAuthoringBuilder.app`;
zero pre-existing agents; legacy Bot Builder not offered as a path for a new
agent). This supersedes the BA's three-way ambiguity in task-scope §1.1
(Agent API vs. Invocable Action API wrapper vs. embedded
`<einstein-copilot-chat>`): the *creation* tooling is Agent Script, not
legacy Bot Builder, so `GTM_Configurator_Assistant.bot-meta.xml` is
superseded (see `force-app/main/default/bots/GTM_Configurator_Assistant/SUPERSEDED.md`).

The chosen call path remains the session-based **Agent API**, server-side
via `GtmAgentProxyController`-style proxying (consistent with the "no LWC
changes" non-goal) — confirmed still viable because the created agent's
type is not "Agentforce (Default)" (see Agent identity table below).

### Agent identity

| Field | Value |
|---|---|
| Agent display name | CONFIRMED: "GTM Configurator Assistant" |
| Agent API / developer name | CONFIRMED: `GTM_Configurator_Assistant` |
| Agent type (must not be "Agentforce (Default)") | CONFIRMED not "Agentforce (Default)" — evidenced indirectly via its auto-created default agent user being an "EinsteinServiceAgent User" (`gtm_configurator_assistant@00dgk00000apl69236326146.ext`), which is Salesforce's documented marker for an Agentforce-Builder-created agent, distinct from the legacy "Agentforce (Default)" type. No separate "Type" field was surfaced directly in Setup by the coordinator; treat this as strong-but-indirect confirmation, not a literal UI field read |
| Topic(s)/Actions wired | CONFIRMED: none. No topics/actions were wired — description and the full `AGENT_INSTRUCTIONS.md` body were pasted into Agent-Level Instructions and saved. Action-wiring (reusing the `sessionToken`/`configId` variable shape from the superseded bot-meta) is explicitly deferred to the `runtime` issue, per this issue's non-goals |

### External Client App / OAuth

| Field | Value |
|---|---|
| External Client App name | CONFIRMED: "GTM Agentforce Integration", API name `GTM_Agentforce_Integration` |
| Consumer Key (client ID) | NOT recorded here — the coordinator confirmed it exists on the ECA's Settings > OAuth Settings > Consumer Key and Secret page but did not paste the literal value into chat, and it was not retrievable via `sf project retrieve` of the ExternalCredential (client ID lives on the Principal, not the definition — see below). If a literal value is needed for `GTM_Agent_Settings__c.Agentforce_Client_Id__c`, that's a manual Setup-UI copy/paste step for whoever configures that custom setting, not something this file needs to store |
| Consumer Secret | NEVER recorded here or anywhere in this repo. Lives only in gtm-staging Setup (External Client App / External Credential Principal `GTM_Agentforce_Principal`) |
| OAuth flow | CONFIRMED: Client Credentials with Client Secret Flow (`ClientCredentialsClientSecretBasic` per the retrieved ExternalCredential's `AuthProtocolVariant` parameter) |
| Run-As user | CONFIRMED: the agent's own EinsteinServiceAgent user (`gtm_configurator_assistant@00dgk00000apl69236326146.ext`) |
| Scopes | CONFIRMED via retrieve: `sfap_api api` (single space-delimited `Scope` AuthParameter value) — matches "Access the Salesforce API Platform (sfap_api)" + "Manage user data via APIs (api)" as shown in the wizard |
| Callback/redirect URL | CONFIRMED required by the wizard even for client-credentials-only: `https://pu1789790920110.my.salesforce.com/services/oauth2/callback`. Coordinator confirms it is never used at runtime for this flow |
| Pre-existing ECA in this org | CONFIRMED: none existed; this one was created fresh |

### Named Credential / External Credential mapping

Metadata shells RECONCILED against a live `sf project retrieve -o gtm-staging`
of the real records (2026-09-25) — the first draft's element names were
wrong (drafted from memory) and have been replaced with the actual shape:

- `force-app/main/default/externalCredentials/GTM_Agentforce_Credential.externalCredential-meta.xml`
  — `authenticationProtocol=Oauth`, `AuthProtocolVariant=ClientCredentialsClientSecretBasic`,
    `Scope=sfap_api api`, `AuthProviderUrl=https://pu1789790920110.my.salesforce.com/services/oauth2/token`,
    Principal `GTM_Agentforce_Principal` (`NamedPrincipal`, sequence 1).
    Confirmed secret-free: grepped the retrieved XML for `secret`/`password`;
    zero matches (the one `secret` substring hit is the flow-type name
    `ClientCredentialsClientSecretBasic`, not a value).
  - `force-app/main/default/namedCredentials/GTM_Agentforce_API.namedCredential-meta.xml`
  — `Url=https://pu1789790920110.my.salesforce.com` (org's My Domain base),
    `ExternalCredential=GTM_Agentforce_Credential`, `generateAuthorizationHeader=true`,
    `allowMergeFieldsInBody/Header=false`, `namedCredentialType=SecuredEndpoint`.

| `GTM_Agent_Settings__c` field | Maps to |
|---|---|
| `Agentforce_My_Domain_URL__c` | Matches the Named Credential's `Url` parameter value (`https://pu1789790920110.my.salesforce.com`), confirmed live — not a placeholder anymore |
| `Agentforce_Client_Id__c` | The ECA's Consumer Key; not stored in the ExternalCredential definition metadata (lives on the Principal in Setup only) — this custom-setting field is a separate, admin-facing display copy, not something the Named Credential reads from |
| `Agentforce_Agent_Id__c` | Not part of the Named/External Credential; intended to be consumed directly by the `runtime` issue's Apex call as the Agent API's agent identifier (`GTM_Configurator_Assistant`, confirmed above) — no new field needed |

No new `GTM_Agent_Settings__c` field is required. No FLS change needed
beyond what's already granted (task-scope §1.3 confirms the existing grant
in `GTM_Offering_Admin` only, lines 401/406/411, is correct/unchanged).

**Environment-specific URLs, flagged by `check-references.py` (0
deploy-blocking, correctly categorized as "needs a manual step"):** both
committed metadata files hardcode `pu1789790920110.my.salesforce.com` —
gtm-staging's actual My Domain host — in the `AuthProviderUrl` and `Url`
parameters. This is consistent with this repo's existing pattern for
org-specific values (same category as the pre-existing
`GtmSavedConfigurationControllerTest.cls` / `offeringChooser.test.js`
warnings), but it means **deploying this metadata to `gtm-prod` as-is would
point the Named Credential at gtm-staging's org**, not prod's. Before any
`gtm-prod` deploy of this metadata, both the `AuthProviderUrl` and `Url`
values need to be repointed to prod's own My Domain host as a post-deploy
(or pre-deploy metadata-override) configuration step — do not copy these
files verbatim into a prod deploy.

### Confirmed request/response shape (Agent API)

**NOT YET CONFIRMED — open item, blocking this issue's closure.** See
"Open item" below.

### Smoke-test evidence

**Attempted, did not succeed — open item.** Ran a minimal anonymous Apex
callout (`sf apex run -o gtm-staging`) as the Developer's own admin CLI
user:

```apex
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:GTM_Agentforce_API/services/data/v62.0/');
req.setMethod('GET');
Http h = new Http();
HttpResponse res = h.send(req);
```

Result: `System.CalloutException: We couldn't access the credential(s). You
might not have the required permissions, or the external credential
"GTM_Agentforce_Credential" might not exist.` The External Credential does
exist (confirmed via `sf project retrieve`, above) — this is a **Principal
Access** gap: no permission set currently maps the calling user (or any
user) to the `GTM_Agentforce_Principal` on `GTM_Agentforce_Credential` via
Setup > External Credentials > GTM_Agentforce_Credential > Permission Set
Mappings. That mapping is a required, separate Setup step from creating the
credential itself, and was not part of this issue's original click-list.

### Open item (blocks calling this issue done)

Two things remain unverified before `runtime` can safely build against this:

1. **Principal Access mapping.** Someone with Setup access needs to add a
   Permission Set Mapping for `GTM_Agentforce_Principal` on
   `GTM_Agentforce_Credential` (Setup > External Credentials >
   GTM_Agentforce_Credential > Permission Set Mappings > New), assigned to
   whichever permission set the Apex context that will make this call runs
   under (for a manual smoke test, this can be a temporary grant to the
   admin's own permission set; for the eventual `runtime` code path, this
   should be `GTM_Offering_Admin`, consistent with this repo's existing
   pattern of gating Agentforce integration config to that permission set —
   confirm with the coordinator/Architect before assuming that's correct
   for a service-to-service credential, since it's a different access
   pattern than a UI-visible field).
2. **Agent API endpoint path.** Once Principal Access is granted, re-run a
   smoke test against the actual Agent API session-start endpoint (not the
   generic `/services/data/v62.0/` probe used above, which only proved the
   named-credential auth chain resolves — it does not prove the Agent API
   path itself). The task-scope explicitly warns the Agent API surface
   "changed materially over 2025"; do not assume
   `callout:GTM_Agentforce_API/einstein/ai-agent/v1/agents/<agentId>/sessions`
   is correct without observing a real response. Needs either: (a) the
   coordinator granting Principal Access live and this Developer re-running
   the anonymous Apex smoke test against the real endpoint, or (b) the
   coordinator running the smoke test directly and reporting the literal
   request/response back.

This issue's original acceptance criteria (task-scope §3) requires "the
live smoke-test response/log from §1.4" as evidence — that is not yet
satisfied. Recommend the coordinator treat this issue as **not yet done**
until the two items above close, rather than merging on the credential
scaffolding alone.

### Secret-handling confirmation

Grepped the full diff (metadata shells + this doc) for secret-shaped
strings: `git diff --stat` below plus a manual review of both retrieved and
committed XML for `secret`/`password`/a bare Consumer Secret value — none
present. The only match for the substring `secret` is the OAuth flow-type
name `ClientCredentialsClientSecretBasic`, confirmed not a credential
value.

## 6. LWC contract: `gtmOfferingsSettingsAgent`

- Combobox options exactly the four in section 1.
- Only the selected provider's inputs are in the DOM (`lwc:if`/`if:true`).
- API key inputs (Claude/OpenAI/Gemini) are password type, never prefilled;
  `hasKey` status line per provider. Agentforce Agent ID / My Domain URL /
  Consumer Key are ordinary text inputs, prefilled from the DTO.
- All values are held in component state and all are sent on Save
  (blank key/model = unchanged in Apex). Switching the dropdown never clears
  another provider's values. One Save button. Revert on save failure.

## 7. Remote Site Settings

New files (active, `disableProtocolSecurity` false):
`OpenAI_API.remoteSite-meta.xml` -> `https://api.openai.com`;
`Google_Gemini_API.remoteSite-meta.xml` -> `https://generativelanguage.googleapis.com`.
These must match the host of `OPENAI_URL` and `GEMINI_BASE_URL`. The OpenAI one
fixes a latent "Unauthorized endpoint" bug from PR #215. Named Credentials are a
noted follow-up. No Remote Site is added for Agentforce (nothing calls out).

## 8. Verification limits

Mocked tests cannot prove a Remote Site Setting exists; a live callout smoke
test against `gtm-prod` (Production) is a deferred, human-gated step.
