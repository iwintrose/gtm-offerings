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
> real `sf project retrieve` (2026-09-25). Request shape confirmed correct
> against current official docs (re-verified independently a second time,
> see "Attempt 4" below); OAuth scope gap found and fixed live; a genuinely
> separate gap (`GTM_Agent_Settings__c` had zero rows — the custom setting
> was never populated) found and fixed live. **None of that changed the
> outcome: the Agent API endpoint still returns a bare 404 indistinguishable
> from an anonymous, unauthenticated request** — this remains an org
> entitlement/infra question, not a request-shape, scope, or settings
> problem. See "Open item" at the end of this section. Do not let `runtime`
> start coding against the request/response shape below as final; it is
> still unconfirmed end-to-end.

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
| Run-As user (`clientCredentialsFlowUser`) | CONFIRMED via `sf project retrieve` of `ExtlClntAppOauthConfigurablePolicies`: the agent's own EinsteinServiceAgent user (`gtm_configurator_assistant@00dgk00000apl69236326146.ext`); `isClientCredentialsFlowEnabled=true` |
| Scopes | **CONFIRMED WRONG, live root-cause candidate for the open 404 — see below.** Live `sf project retrieve` of `ExtlClntAppOauthSettings.commaSeparatedOauthScopes` returns `Api, SFApiPlatform` only (i.e. `api` + `sfap_api`). Current official docs (fetched live 2026-09-25, developer.salesforce.com/docs/ai/agentforce/guide/agent-api-get-started.html) list **four** required scopes for an Agent-API-capable ECA: "Manage user data via APIs (api)", "Perform requests at any time (refresh_token, offline_access)", **"Access chatbot services (chatbot_api)"**, and "Access the Salesforce API Platform (sfap_api)". This org's ECA is missing `chatbot_api` and the refresh-token/offline-access scope entirely. `chatbot_api` in particular is a strong root-cause candidate for the 404s described below, since the Agent API is documented as backed by the chatbot service |
| Callback/redirect URL | CONFIRMED required by the wizard even for client-credentials-only: `https://pu1789790920110.my.salesforce.com/services/oauth2/callback`. Coordinator confirms it is never used at runtime for this flow |
| Pre-existing ECA in this org | CONFIRMED: none existed; this one was created fresh |

### Named Credential / External Credential mapping

Metadata RE-RECONCILED against a **second** live `sf project retrieve
-o gtm-staging` (2026-09-25), after the coordinator made two live fixes:
cleared the External Credential's `Scope` parameter (it caused a real
token-issuance failure, `invalid_request: scope parameter not supported`,
against this org's own `/services/oauth2/token` endpoint — that parameter
does not belong on a first-party org's own OAuth token endpoint the way it
would on a third-party IdP), and changed the Named Credential's `Url` from
the org's My Domain to `https://api.salesforce.com`, which matches current
docs (see below).

- `force-app/main/default/externalCredentials/GTM_Agentforce_Credential.externalCredential-meta.xml`
  — `authenticationProtocol=Oauth`, `AuthProtocolVariant=ClientCredentialsClientSecretBasic`,
    `AuthProviderUrl=https://pu1789790920110.my.salesforce.com/services/oauth2/token`,
    Principal `GTM_Agentforce_Principal` (`NamedPrincipal`, sequence 1). No
    `Scope` parameter (removed live; confirmed gone on re-retrieve).
    Confirmed secret-free on both retrieves: grepped for `secret`/`password`;
    zero matches (the one `secret` substring hit both times is the
    flow-type name `ClientCredentialsClientSecretBasic`, not a value).
- `force-app/main/default/namedCredentials/GTM_Agentforce_API.namedCredential-meta.xml`
  — `Url=https://api.salesforce.com` (confirmed live-changed from the
    prior My Domain value), `ExternalCredential=GTM_Agentforce_Credential`,
    `generateAuthorizationHeader=true`, `allowMergeFieldsInBody/Header=false`,
    `namedCredentialType=SecuredEndpoint`.

**Host resolved via live docs, not more guessing:** fetched
developer.salesforce.com/docs/ai/agentforce/guide/agent-api-get-started.html,
.../agent-api-examples.html, .../agent-api-agent-id.html, and
.../agent-api-considerations.html live (2026-09-25). Confirmed: the Agent
API base host is `api.salesforce.com` (`api.gov.salesforce.com` on
Government Cloud) — NOT the org's My Domain. The My Domain URL is instead
required **inside** the Start Session POST body as
`instanceConfig.endpoint`. So `api.salesforce.com` (the coordinator's live
change) is correct per docs; the earlier `pu1789790920110.my.salesforce.com`
Named Credential `Url` value was wrong for this purpose specifically
(though it's still the right value for the ExternalCredential's
`AuthProviderUrl`, since token issuance itself IS against the org's own My
Domain `/services/oauth2/token`).

| `GTM_Agent_Settings__c` field | Maps to |
|---|---|
| `Agentforce_My_Domain_URL__c` | Maps to the `AuthProviderUrl` (token issuance) AND to the `instanceConfig.endpoint` value the `runtime` issue's Apex must include in every Start Session request body — NOT to the Named Credential's `Url`, which is the Agent API host (`api.salesforce.com`), a fixed constant rather than an org-specific value. This is a correction to the first reconciliation pass, which conflated the two |
| `Agentforce_Client_Id__c` | The ECA's Consumer Key; not stored in the ExternalCredential definition metadata (lives on the Principal in Setup only) — this custom-setting field is a separate, admin-facing display copy, not something the Named Credential reads from |
| `Agentforce_Agent_Id__c` | Not part of the Named/External Credential; intended to be consumed directly by the `runtime` issue's Apex call as the Agent API's agent identifier. CONFIRMED via live SOQL (`SELECT Id, DeveloperName FROM BotDefinition WHERE DeveloperName = 'GTM_Configurator_Assistant'`) that the correct value for the Agent API's `{AGENT_ID}` path segment is the **BotDefinition record Id** (`0XxgK000002MowHSAS`), not the developer name string — confirmed by official docs' "Get the Agent ID for an Agent" page, which explicitly says for agents built in the new Agentforce Builder, "you need the bot ID from the Bot metadata type or the BotDefinition standard object. The bot ID represents the agent ID in this case." No new field needed, but `Agentforce_Agent_Id__c` should store the BotDefinition **Id**, not the developer name, when `runtime` wires this up |

No new `GTM_Agent_Settings__c` field is required. No FLS change needed
beyond what's already granted (task-scope §1.3 confirms the existing grant
in `GTM_Offering_Admin` only, lines 401/406/411, is correct/unchanged).

**Environment-specific URLs, flagged by `check-references.py` (0
deploy-blocking, correctly categorized as "needs a manual step"):** the
ExternalCredential still hardcodes `pu1789790920110.my.salesforce.com` in
`AuthProviderUrl` (correctly — that's org-specific token issuance). The
NamedCredential's `Url` is now the fixed `api.salesforce.com` constant, not
an org-specific value, so it does NOT need to change per environment. Only
`AuthProviderUrl` (and the `GTM_Agent_Settings__c.Agentforce_My_Domain_URL__c`
value `runtime` will read for `instanceConfig.endpoint`) need to be
repointed to prod's own My Domain host before any `gtm-prod` deploy — do
not copy the ExternalCredential file verbatim into a prod deploy.

### Confirmed request/response shape (Agent API) — request confirmed, response still failing

**Request shape CONFIRMED from current official docs** (same four pages
fetched live above). Start Session:

```
POST https://api.salesforce.com/einstein/ai-agent/v1/agents/{AGENT_ID}/sessions
Content-Type: application/json
Authorization: Bearer {ACCESS_TOKEN}

{
  "externalSessionKey": "{RANDOM_UUID}",
  "instanceConfig": { "endpoint": "https://{MY_DOMAIN_URL}" },
  "streamingCapabilities": { "chunkTypes": ["Text"] },
  "bypassUser": true
}
```

`{AGENT_ID}` = the BotDefinition Id (`0XxgK000002MowHSAS` for this org's
agent, confirmed live). `bypassUser: true` routes the call through the
agent's own assigned user rather than the token's user — matches this
org's client-credentials setup (Run-As user is the agent's own
EinsteinServiceAgent user).

**Response shape: NOT YET CONFIRMED — still an open item.** A real Apex
callout built exactly to this shape (see Smoke-test evidence below) still
returns `404` with an empty body, even after the host/path/body were
corrected to match docs. The most likely remaining cause, per the OAuth
scope gap found above, is the missing `chatbot_api` scope on the ECA —
not yet proven, since re-testing requires a live Setup change this
Developer cannot make (see Open item).

### Smoke-test evidence

**Two attempts. First succeeded at proving the credential chain resolves;
second attempt (this pass) proved the request reaches the org but still
404s — still not a full pass.**

Attempt 1 (`services/data/v62.0/` probe, before Principal Access was
granted): `System.CalloutException: We couldn't access the credential(s)`
— root-caused to a missing Permission Set Mapping, which the coordinator
then granted live (`GTM_Agentforce_Principal` access added to the System
Administrator profile).

Attempt 2 (this pass, after Principal Access granted, Scope cleared, Url
fixed to `api.salesforce.com`, and the agent Committed + Activated to
"Version 1 (Active)"), run via `sf apex run -o gtm-staging`:

```apex
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:GTM_Agentforce_API/einstein/ai-agent/v1/agents/0XxgK000002MowHSAS/sessions');
req.setMethod('POST');
req.setHeader('Content-Type', 'application/json');
String randomKey = String.valueOf(Crypto.getRandomInteger()) + '-' + String.valueOf(Datetime.now().getTime());
String bodyJson = '{'
    + '"externalSessionKey":"' + randomKey + '",'
    + '"instanceConfig":{"endpoint":"https://pu1789790920110.my.salesforce.com"},'
    + '"streamingCapabilities":{"chunkTypes":["Text"]},'
    + '"bypassUser":true'
    + '}';
req.setBody(bodyJson);
Http h = new Http();
HttpResponse res = h.send(req);
System.debug('STATUS=' + res.getStatusCode());
System.debug('BODY=' + res.getBody());
```

Result: `STATUS=404`, `BODY=` (empty). This now exactly matches the
documented request shape (host, path, headers, body), which rules out
"wrong URL/host" and "wrong body shape" as the cause — narrowing the
remaining candidates to (a) the missing `chatbot_api` OAuth scope on the
ECA (the leading hypothesis, since Salesforce's docs list it as required
and it's absent from this org's live `ExtlClntAppOauthSettings` record),
or (b) something about the agent/session-start flow this Developer cannot
observe further without either a Setup-UI scope change or a different
diagnostic (e.g. inspecting Agent API request logs in Setup, which needs
Setup access this Developer doesn't have via CLI).

**Attempt 3 (this pass): scope fix applied, re-tested, STILL 404 — and a
new diagnostic isolates the failure further.** Coordinator added
`chatbot_api` and `refresh_token, offline_access` to the ECA live;
re-retrieved `ExtlClntAppOauthSettings` and confirmed
`commaSeparatedOauthScopes = Api, RefreshToken, Chatbot, SFApiPlatform` —
all four documented scopes now present. Re-ran the exact same Apex smoke
test (twice, ~1 minute apart, in case of scope-propagation delay): both
runs `STATUS=404`, `BODY=` (empty) — unchanged.

To isolate further, ran three additional diagnostics:

1. Same request with a deliberately invalid `AGENT_ID` (`INVALID_AGENT_ID`
   instead of the real BotDefinition Id): still `404`, empty body, no
   `WWW-Authenticate` header. Per the docs' own troubleshooting page, an
   invalid agent ID should produce an HTTP 400 with `"{VALUE} is not a
   valid agent ID"` in the body — getting 404 instead means the request
   isn't reaching the Agent API's own validation logic at all.
2. Dumped every response header via `res.getHeaderKeys()`: only `date`,
   `content-length: 0`, `connection: close` — no Salesforce-specific
   tracing/error headers, consistent with an edge/gateway-level 404
   rather than an application-level one.
3. **Sent the identical request unauthenticated, straight from this
   Developer's shell via plain `curl` (no token, no org context
   whatsoever)** to `https://api.salesforce.com/einstein/ai-agent/v1/agents/TEST/sessions`:
   also `HTTP/2 404`, empty body, same minimal header set (`date` only).
   **The authenticated, correctly-scoped, correctly-shaped request from
   this org and the fully anonymous public request are byte-for-byte
   indistinguishable.** That is strong evidence the failure is not (or
   is no longer) a scope/token/body/path problem on our side — a request
   this well-formed, if it were reaching real Agent API request-validation
   logic with a valid bearer token, should differ from an anonymous
   request in *some* observable way (a 401, a different error body, a
   trace header). It doesn't.

**Attempt 4 (follow-up pass, 2026-09-25): investigated a coordinator-raised
hypothesis that the 404s were actually caused by a blank/missing agent ID
rather than an entitlement gap — disproven, but a real, separate bug was
found and fixed along the way.**

The coordinator found via direct SOQL that `GTM_Agent_Settings__c` (the
custom setting `GtmAgentSettingsController` reads/writes, field
`Agentforce_Agent_Id__c`) had **zero rows** in `gtm-staging` — confirmed
independently here:

```
$ sf data query -q "SELECT Id, Agentforce_Agent_Id__c, Agentforce_My_Domain_URL__c, Agentforce_Client_Id__c, Chat_Provider__c FROM GTM_Agent_Settings__c" -o gtm-staging
Total number of records retrieved: 0.
```

Also independently confirmed (matches coordinator's SOQL exactly):

```
$ sf data query -q "SELECT Id, DeveloperName, MasterLabel, Type, BotUserId FROM BotDefinition" -o gtm-staging
0XxgK000002MowHSAS | GTM_Configurator_Assistant | GTM Configurator Assistant | ExternalCopilot | <this org's EinsteinServiceAgent User Id, redacted here -- a User Id is org-bound identity per check-references.py §12 and would be wrong in any other org; matches the BotUserId already cited elsewhere in this section by its username, gtm_configurator_assistant@00dgk00000apl69236326146.ext>

$ sf data query -q "SELECT Id, BotDefinitionId, DeveloperName, Status, VersionNumber FROM BotVersion" -o gtm-staging
0X9gK000003vlYLSAY | 0XxgK000002MowHSAS | v1 | Active | 1
```

**This is a real, confirmed-empty setting — but it was never the cause of
Attempts 1-3's 404s.** Checked via `git log -p` on this file: every prior
smoke-test Apex snippet (Attempts 1, 2, and 3, and the invalid-agent-ID
diagnostic within Attempt 3) hardcoded the literal, correct BotDefinition
Id (`0XxgK000002MowHSAS`) directly in `req.setEndpoint(...)` — none of them
read `GTM_Agent_Settings__c.Agentforce_Agent_Id__c` at all, because that
plumbing belongs to the `runtime` issue (task-scope's own non-goals list:
"No changes to `GtmAgentProxyController.runLoop()`"), which hasn't started.
So a blank custom setting could not have produced Attempts 1-3's 404s —
those requests were never blank; they used the correct real ID the whole
time. This corrects the coordinator's stated diagnosis before building on
top of it (per this session's own verify-before-trusting instruction): the
empty setting is a real latent gap worth fixing (the `runtime` issue will
depend on it), but it is not an explanation for the observed 404 pattern.

Fixed anyway, since it's required regardless and is part of this issue's
own acceptance criteria (task-scope §1.3 confirms the three
`GTM_Agent_Settings__c` fields are the intended parameterization). No
browser tool is available in this Developer session (tool list is
Read/Write/Edit/Bash/SubagentHandback only — no navigate/screenshot
capability), so per this task's explicit fallback instruction, the value
was written through the real `GtmAgentSettingsController.setAgentSettings`
Apex contract method (the same code path the `gtmOfferingsSettingsAgent`
LWC/Settings-tab UI calls on Save) rather than a raw SOQL/Tooling insert
and rather than a live browser click — flagged explicitly rather than
silently claimed as a UI-verified change:

```apex
GtmAgentSettingsController.AgentSettingsInput input = new GtmAgentSettingsController.AgentSettingsInput();
input.agentforceAgentId = '0XxgK000002MowHSAS';
GtmAgentSettingsController.setAgentSettings(input);
```

Confirmed written (`sf apex run -o gtm-staging`):

```
SAVED_AGENT_ID=0XxgK000002MowHSAS
SAVED_CHAT_PROVIDER=Anthropic
SAVED_ID=a1RgK000004fO0rUAE
```

Re-ran the smoke test, this time sourcing the agent ID dynamically from
the now-populated setting (`GTM_Agent_Settings__c.getOrgDefaults()`)
instead of a hardcoded literal, to make the "populated real agent ID" path
genuinely load-bearing in the test:

```
USING_AGENT_ID_FROM_SETTINGS=0XxgK000002MowHSAS
STATUS=404
BODY=
HEADER_KEYS=(date, content-length, connection)
HEADER date = Fri, 25 Sep 2026 21:49:35 GMT
HEADER content-length = 0
HEADER connection = close
```

**Identical to every prior attempt** — same status, same empty body, same
three-header signature, no change.

**Independently re-verified the Agent-ID doc claim and the request/response
shape against live Salesforce docs a second time** (this Developer has no
WebFetch/WebSearch tool in this session, but does have outbound internet
access via Bash, so fetched the actual pages with `curl` rather than
relying on the prior session's paraphrase — flagging that distinction
since the task asked to say which method was used):
`developer.salesforce.com/docs/ai/agentforce/guide/agent-api-agent-id.html`
confirms verbatim: "...the `Bot` metadata type or the `BotDefinition`
standard object. The bot ID represents the agent ID in this case... The
`Id` field in the query result is your agent ID" — matches
`0XxgK000002MowHSAS`, reproducing the prior session's citation
independently rather than trusting it. The live curl/response examples on
`agent-api-get-started.html` match this branch's request shape byte-for-byte
(host `api.salesforce.com`, path
`/einstein/ai-agent/v1/agents/{AGENT_ID}/sessions`, body keys
`externalSessionKey`/`instanceConfig.endpoint`/`streamingCapabilities`/`bypassUser`).

New information found on `agent-api-troubleshooting.html` not previously
cited in this doc: "If you receive an HTTP 404 response, verify that
you're using the correct token and that you're using the correct
endpoint" (generic — Salesforce's own docs don't enumerate an entitlement
cause specifically), versus "If you receive an HTTP 400 response... Message
field in response contains '{VALUE} is not a valid agent ID'" for a bad
agent ID. This directly confirms the prior session's Attempt 3 diagnostic
#1 reasoning was correctly applied: a request with a deliberately invalid
agent ID that should produce a 400 per Salesforce's own docs, but instead
produces the identical 404 as a request with the correct agent ID, means
the request is not reaching the Agent API's request-validation logic —
consistent with "wrong/unrecognized token" or a request that never reaches
the Agent API application layer at all (edge/gateway-level), not with
"config is subtly wrong." `agent-api-considerations.html` and
`agent-api-get-started.html` were also checked for any documented
demo/trial-org entitlement caveat; none exists in the current docs — the
demo-org theory remains a plausible but *undocumented* hypothesis, not a
docs-confirmed one.

### Open item (blocks calling this issue done)

The scope gap (prior leading hypothesis) is now ruled out — confirmed
fixed and re-tested, no change in outcome. The blank-`GTM_Agent_Settings__c`
hypothesis raised in Attempt 4 is also now ruled out — it was never the
actual input to any smoke test, and populating it plus sourcing the ID
from it live produced an identical 404. The remaining open item is
larger than a single Setup click and needs either org-entitlement
verification or an out-of-Apex diagnostic this Developer cannot run
without further org access:

1. **Check org entitlement for the Agent API / unified `api.salesforce.com`
   gateway specifically**, not just "Agentforce enabled with an active
   agent" (which is confirmed true here). This org's username
   (`isiah.wintrose@gmail.com2026_09_19_0-2-55.demo`) suggests a demo/trial
   provisioning, and demo orgs are a plausible candidate for missing a
   separate Agent-API-specific entitlement/add-on even when Agentforce
   Studio itself is fully functional in Setup. Check Setup > Company
   Information or Feature/Permission Set Licenses for anything
   Agent-API- or `sfap_api`-platform-specific that might not be
   provisioned, and consider opening a Salesforce support case if nothing
   is found, since "authenticated request behaves identically to
   anonymous request" is a strong signal for an infra/entitlement issue
   rather than a config mistake at this point.
2. **Get one real, out-of-Apex data point with a manually-minted token.**
   This Developer cannot mint a token (the consumer secret is intentionally
   never available to this Developer). If the coordinator or an admin
   mints a token directly (Workbench, Postman, or a manual curl using the
   consumer key/secret from Setup) and calls
   `https://api.salesforce.com/einstein/ai-agent/v1/agents/0XxgK000002MowHSAS/sessions`
   with a real `Authorization: Bearer` header outside of Apex/Named
   Credential entirely, that isolates whether the Named Credential/Apex
   callout path itself is the problem (e.g. the Authorization header isn't
   actually being attached the way `generateAuthorizationHeader=true`
   implies) versus the endpoint genuinely 404ing for everyone regardless of
   auth. Salesforce's own Agent API Postman Collection
   (postman.com/salesforce-developers/salesforce-developers/collection/gwv9bjy/agent-api)
   is the fastest way to do this with real request/response visibility.

This issue's original acceptance criteria (task-scope §3) requires "the
live smoke-test response/log from §1.4" showing a real agent response —
that is not yet satisfied (still 404, not a session ID, across four
attempts and five rounds of live config fixes, the last of which —
populating `GTM_Agent_Settings__c` — was investigated specifically because
it looked like a plausible alternate root cause and was ruled out with
evidence rather than assumed). Recommend the coordinator treat this issue
as **not yet done**, and specifically not assume any further guessed
configuration or data change will fix it — the next productive step is
entitlement verification or a non-Apex request with a manually-minted
token, not another metadata or data edit.

### Secret-handling confirmation

Grepped the full diff (metadata shells + this doc) for secret-shaped
strings across both reconciliation passes: manual review of all retrieved
and committed XML for `secret`/`password`/a bare Consumer Secret or
Consumer Key value — none present. The only match for the substring
`secret` is the OAuth flow-type name `ClientCredentialsClientSecretBasic`,
confirmed not a credential value.

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
