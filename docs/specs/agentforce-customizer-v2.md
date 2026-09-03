# Tier 2 Spec — Agentforce Conversational Customize Panel (v2)

**Status:** Draft for review  
**Offering:** Migration Accelerator  
**Replaces:** `maConfigCustomize` form-based panel (v1)  
**Requires:** Agentforce (Einstein Copilot Studio) provisioned on the GTM Offerings org

---

## 1. Problem statement

The v1 Customize panel is a form. A BD rep opens it, fills in a company name, picks an industry, sets proof numbers, and saves a link. That's fine for basic personalization, but it forces the rep to already know what the page should say. Richer personalization — matching tone and emphasis to a specific client's situation — requires judgment the form can't guide.

The v2 panel replaces the form with an embedded Agentforce conversation. The rep describes the prospect in natural language; the agent extracts the relevant configuration values, applies them live, and explains what it changed and why. The save and link-generation flow stays unchanged.

---

## 2. Scope

**In scope:**
- Conversational UI embedded in `maConfigCustomize` as an Agentforce iframe/channel slot
- Custom Agentforce actions for reading and writing configurator state
- Extraction of: company name, industry, accent color (by brand name), proof numbers (objects, deps, health), and section-level emphasis flags
- Auto-save after the agent applies changes (reuses existing `scheduleAutoSave` path)
- Fallback to v1 form (accessible via an "Advanced / manual" toggle)

**Out of scope:**
- Contact search and Sales Cloud linking (stays in v1 advanced section)
- FAQ content edits (managed via GTM Content Manager)
- Section reordering (v2.1 — requires `sections` key in `Config_Payload__c`)
- Multi-offering support beyond migration-accelerator

---

## 3. Agentforce agent definition

**Agent name:** `GTM Configurator Assistant`  
**Channel:** Experience Cloud / LWC embedding  
**Model:** Einstein (default; no custom model required for MVP)  
**Persona:** Internal PS Sapient tool — not customer-facing; frank, efficient, no pleasantries

### 3.1 System prompt (base instructions)

```
You are a configuration assistant embedded in a client-facing page builder
for the Publicis Sapient Migration Accelerator GTM offering.

Your job: help a BD rep or Industry Leader quickly personalize the page for
a specific prospect. When they describe the client, extract the relevant
config values and apply them. Confirm what you changed, briefly.

Config fields you can read and set:
- company (string): prospect company name, shown on the page
- industry (string): one of the org-defined industry keys
- accent (hex string): brand color, applied to buttons and accents
- objectsCount (integer): MA proof stat — estimated objects in their platform
- depsCount (integer): MA proof stat — estimated dependencies
- healthScore (integer 0-100): MA proof stat — estimated migration health
- note (string): a short client-specific note shown in the closing section

You do NOT manage contact, CRM linkage, password, or expiry — those are in
the advanced form below the chat.

Keep responses short. One short paragraph max. After applying changes,
list what changed as a bullet list (field: new value). If the rep gives
you something ambiguous (like a company name that maps to multiple industries),
ask one clarifying question, then apply.
```

---

## 4. Custom Agentforce actions

Two invocable Apex actions expose configurator state to the agent. Both are annotated `@InvocableMethod` and declared in `MaAgentConfigActions.cls`.

### 4.1 `getConfiguratorState`

Returns the current configuration values for the open session.

**Input:**
```apex
public class GetStateInput {
    @InvocableVariable(required=true) public String configId; // MA_Saved_Configuration__c Id, or blank for unsaved
}
```

**Output:**
```apex
public class GetStateOutput {
    @InvocableVariable public String company;
    @InvocableVariable public String industry;
    @InvocableVariable public String accent;
    @InvocableVariable public Integer objectsCount;
    @InvocableVariable public Integer depsCount;
    @InvocableVariable public Integer healthScore;
    @InvocableVariable public String note;
    @InvocableVariable public List<String> availableIndustries; // for the agent's context
}
```

**Implementation notes:**
- If `configId` is blank, return defaults (company='', industry='', etc.).
- `availableIndustries` is fetched from `getStoryContent` and passed to the agent so it knows valid values.
- Cached — the agent should call this once at conversation start.

### 4.2 `applyConfiguratorUpdate`

Applies one or more field changes to the configurator state. Does NOT persist to the server — that remains the LWC's responsibility.

**Input:**
```apex
public class ApplyUpdateInput {
    @InvocableVariable public String sessionToken; // opaque; identifies the LWC instance
    @InvocableVariable public String updatesJson;  // JSON object: { field: newValue, ... }
}
```

**Output:**
```apex
public class ApplyUpdateOutput {
    @InvocableVariable public Boolean success;
    @InvocableVariable public String appliedJson;  // echo of what was applied
    @InvocableVariable public String errorMessage;
}
```

**Implementation notes:**
- The `sessionToken` is generated by the LWC on mount (random UUID) and passed to the Agentforce channel on init. The action validates it against an in-memory (Platform Cache, short TTL) map of active sessions.
- The actual state mutation happens via a platform event (`MA_Config_Update__e`) the action publishes; the LWC subscribes via `empApi` and applies the delta to `_state` and dispatches `statechange` to the parent exactly as the v1 form handlers do.
- `updatesJson` accepts a partial object — only the fields present are changed.

**Supported field names in `updatesJson`:**

| Field | Type | Validation |
|---|---|---|
| `company` | string | max 120 chars |
| `industry` | string | must be in `availableIndustries` |
| `accent` | string | must match `#[0-9a-fA-F]{6}` |
| `objectsCount` | integer | 0–999999 |
| `depsCount` | integer | 0–999999 |
| `healthScore` | integer | 0–100 |
| `note` | string | max 500 chars |

---

## 5. LWC integration contract

`maConfigCustomize` v2 adds an Agentforce messaging slot alongside the existing form. The form remains accessible behind the "Advanced / manual" toggle (the v1 Sales Cloud section toggle, promoted to cover the full form).

### 5.1 Component state changes

```js
// New properties
@track _agentMode = true;      // false = show v1 form instead of chat
@track _sessionToken = '';     // generated on connectedCallback, passed to agent

connectedCallback() {
    this._sessionToken = crypto.randomUUID();
    // existing getStoryContent call retained
    // subscribe to platform event for agent-driven updates
    subscribe('/event/MA_Config_Update__e', -1, (msg) => {
        const delta = JSON.parse(msg.data.payload.Updates_JSON__c);
        this._applyDelta(delta);
        this.scheduleAutoSave();
    });
}

_applyDelta(delta) {
    // mirrors handleFieldInput/handleIndustryChange/handleAccentInput logic
    if ('company'      in delta) { this.company = delta.company; }
    if ('industry'     in delta) { this.industry = delta.industry; }
    if ('accent'       in delta) { this.accent = delta.accent; }
    if ('objectsCount' in delta) { /* dispatch to parent via statechange */ }
    // ... etc
    this.dispatchEvent(new CustomEvent('statechange', { detail: { state: this._buildState() } }));
}
```

### 5.2 Agent channel embedding

```html
<!-- inside maConfigCustomize.html, replacing the form body when _agentMode=true -->
<template if:true={_agentMode}>
  <div class="agent-slot">
    <einstein-copilot-chat
      agent-api-name="GTM_Configurator_Assistant"
      session-variables={agentSessionVars}
    ></einstein-copilot-chat>
  </div>
</template>
```

`agentSessionVars` getter returns:
```js
get agentSessionVars() {
    return [
        { name: 'sessionToken', value: this._sessionToken },
        { name: 'configId',     value: this.knownRecordId || '' }
    ];
}
```

The agent uses `sessionToken` and `configId` to seed `getConfiguratorState` on conversation start.

### 5.3 Mode toggle

A "Switch to form" / "Switch to assistant" toggle at the top of the scroll area sets `_agentMode`. Default is `true` (agent) after the feature is GA; in initial rollout default to `false` with a "Try the assistant" CTA.

---

## 6. Platform event

`MA_Config_Update__e` (new Custom Platform Event):

| Field | API name | Type | Description |
|---|---|---|---|
| Session token | `Session_Token__c` | Text(36) | Matches LWC's `_sessionToken` |
| Updates JSON | `Updates_JSON__c` | LongTextArea(4096) | JSON delta from the agent action |

The LWC subscribes with `empApi` and processes only events whose `Session_Token__c` matches `this._sessionToken`, so parallel open sessions don't cross-contaminate.

---

## 7. Brand color lookup integration

The agent can accept natural-language brand color descriptions ("use their brand red" / "look up Metrolinx's color"). The `applyConfiguratorUpdate` action delegates this to `MaBrandLookupController.fetchLogoDataUri` (already built), extracts the dominant hex, and includes it in the applied delta. No additional Apex is needed.

---

## 8. Conversation design

### 8.1 Opening context injection

On conversation start, the agent calls `getConfiguratorState` and primes itself:

> "I've loaded the current config. Company is set to [X], industry is [Y]. What do you want to customize?"

If company is blank:
> "This page isn't personalized yet. Who's the prospect?"

### 8.2 Primary flow — describe the prospect

Rep: *"This is for Metrolinx — Canadian transit authority, probably public sector, they're on SFMC moving to Marketing Cloud Next"*

Agent applies:
- company → "Metrolinx"
- industry → "Public Sector" (or nearest available industry key)
- note → "SFMC → Marketing Cloud Next migration"

Agent replies: 
> Applied:
> - Company: Metrolinx
> - Industry: Public Sector
> - Note: SFMC → Marketing Cloud Next migration
>
> Proof numbers are defaults — want to set objects, dependencies, or health score?

### 8.3 Secondary flow — proof numbers

Rep: *"They have around 800 objects, healthy environment"*

Agent applies: objectsCount → 800, healthScore → 85 (inferred), depsCount → (unchanged)

### 8.4 Fallback

If the agent can't parse a request or the action fails, it responds:
> "I couldn't apply that — try the form instead (Advanced / manual below)."

---

## 9. Acceptance criteria

- [ ] `MaAgentConfigActions.cls` with both invocable methods, unit tests ≥90% coverage
- [ ] `MA_Config_Update__e` platform event created and deployed
- [ ] `GTM_Configurator_Assistant` agent created in Einstein Copilot Studio with the base prompt and both actions registered
- [ ] LWC subscribes to the platform event and applies deltas without page reload
- [ ] Agent-driven changes trigger `scheduleAutoSave` — server save happens within 1.5s
- [ ] v1 form accessible via mode toggle in the same panel (no separate URL or page)
- [ ] Multi-session isolation: two reps editing different links simultaneously don't cross-contaminate
- [ ] No client data written to AgentLoom or any external knowledge provider (egress boundary per ADR-0029)
- [ ] Unit tests cover: partial delta application, invalid field names in delta, session token mismatch (no-op), brand color lookup delegation

---

## 10. Developer checklist

- [ ] Create `MA_Config_Update__e` in Salesforce — add to `customMetadata` or `objects/` in the SFDX project
- [ ] Build `MaAgentConfigActions.cls` (two `@InvocableMethod` classes), wire up Platform Cache for session token map (or use a transient SOQL-backed alternative if Platform Cache isn't provisioned)
- [ ] Register both actions in Einstein Copilot Studio
- [ ] Add `einstein-copilot-chat` LWC to `maConfigCustomize.html` behind `_agentMode` flag; wire session variables
- [ ] Add `empApi` subscription in `maConfigCustomize.js`; route `MA_Config_Update__e` payloads through `_applyDelta`
- [ ] Add mode toggle (agent / manual form) to panel header area
- [ ] Guest/Experience Cloud access: ensure the platform event subscription works from the public site guest profile; if `empApi` requires authenticated session, consider a polling alternative for the guest path (the configurator is primarily used by internal BDs in authenticated Lightning, so this may be a non-issue)
- [ ] Write tests for `MaAgentConfigActions` (both happy path and error cases)
- [ ] QA: open two browser sessions simultaneously with different `cfgId` params; confirm changes in one don't appear in the other
