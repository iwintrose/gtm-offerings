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

## 5. Agentforce fallback (stateless)

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
