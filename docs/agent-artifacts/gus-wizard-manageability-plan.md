# GUS tone + Offering wizard config — manageability implementation plan

**Author:** Architect agent (session `session_018UJzwgTCCMdESELzYMeWAZ`)
**Date:** 2026-09-07
**Status:** For Dev implementation, then QA verification against this plan and the live `gtm-dev` org. This is an implementation spec, not the code — Dev still has to write it.

---

## 0. The standard this plan holds itself to

Tonight's assessment/readout walkthrough was thorough on "does the code technically support X" and never checked "can a business user (content author, BD rep — not a developer) actually configure or manage this without someone editing Apex and redeploying." Every design below is judged against that second question, not the first. Where an existing mechanism already clears that bar, this plan says so and reuses it rather than inventing a new one — the least new surface area, per the product owner, is a design goal, not a nice-to-have.

---

## 1. Repo grounding (what I actually read)

`GtmAgentProxyController.cls`, `GtmReadoutAgentSurface.cls`, `gtmPageLayouts.js`, `gtmContentManager.js`/`.html`, `gtmFieldEditor.js`/`.html`, `GtmPageContentReader.cls`, `GtmPageContentController.cls`, `GtmPageSectionController.cls`, `GTM_Page_Content__c`'s field metadata (all fields), `gtmConfigurator.js` (assistant-content wiring), `gtmConfigWizard.js` (full file), `gtmConfigBooking.js`, `gtmReadoutAssist.js`/`.html`, `GtmAgentGetConfigState.cls`, `docs/specs/prospect-page-wizard.md` (confirmed stale — names `MA_Saved_Configuration__c`, `MaConfigWizard`, `maConfigCustomize`, none of which exist; the real thing is `gtmConfigWizard` + `GTM_Saved_Configuration__c`, exactly as the doc pipeline's own findings already said).

Key fact that shapes both designs: **`GTM_Page_Content__c` is a fully generic content row** — `(Offering_Key__c, Template_Type__c, Section_Key__c, Field_Key__c, Industry_Key__c) → (Field_Type__c: text|rich|json|icontext, value in Text_Value__c|Rich_Value__c|JSON_Value__c)`, with a draft/publish workflow (`Draft_Value__c`, `Status__c`, `Active__c`) already built and already the thing `gtmContentManager` edits. Adding a *new field key* under an *existing* section/template costs zero new custom fields, zero new objects, and (confirmed below) zero new permission-set grants — it's a data-model reuse, not a schema change. Both designs below lean on this as hard as possible.

---

## 2. GUS tone setting

### 2.1 Where it lives

A new `Field_Key__c = 'agentTone'` row under the **existing** Framework `assistant` page: `Offering_Key__c = 'gtm'` (== `FRAMEWORK_KEY` in `gtmPageLayouts.js`), `Template_Type__c = 'assistant'`, `Section_Key__c = 'assistant'` — the exact same section that already carries `assistantName`, `assistantRole`, `fabLabel`, `greeting`, `inputPlaceholder`. This satisfies the product owner's "whole part of the framework" requirement literally: it's edited on the same page, in the same editor, by the same content author, right next to the assistant's other properties. No new tab, no new object, no Setup-only Custom Setting screen (the existing `Claude_API_Key__c`/`Claude_Model__c` Custom Setting stays sysadmin-only, correctly, since those are secrets/ops config — tone is content).

### 2.2 A new Field_Type__c: `enum`

Field type must not be free text — the product owner explicitly asked for a bounded set. `GTM_Page_Content__c.Field_Type__c` is a restricted picklist with `text | rich | json | icontext`. Add a fifth value, `enum`, in `force-app/main/default/objects/GTM_Page_Content__c/fields/Field_Type__c.field-meta.xml`:

```xml
<value>
    <fullName>enum</fullName>
    <default>false</default>
    <label>Choice (bounded set)</label>
</value>
```

This is a picklist-*value* addition on an already-granted field — not a new field, so **no permission-set change is required** (§5.1 of the repo's `CLAUDE.md` gotcha doesn't apply: FLS is granted per field, not per picklist value; `GTM_Config_Manager` already has CRUD/FLS on `Field_Type__c` and `Text_Value__c`). QA should confirm this rather than assume it (checklist §6.19).

`enum` resolves and saves through the exact same code path as `text` today — every `resolveValue()` in `GtmPageContentReader.cls` / `GtmPageContentController.cls` already falls through to `Text_Value__c` for anything that isn't `rich`/`json`/`icontext`, so **no changes are needed in either resolver**. The only two Apex touch points:

- `GtmPageSectionController.cls` `VALUE_TYPES` (line ~467) — add `'enum'` to the set, or `createField`/`saveDrafts` will reject it with "A field type must be one of: ...".
- No column-init special case needed (the `if (row.Field_Type__c == 'json') …` / `'icontext'` branches near lines 208, 350, 633 are additive; `enum` needs no equivalent — it's a plain string in `Text_Value__c`, same as `text`).

### 2.3 Client side: `gtmPageLayouts.js`

- `LAYOUT_FIELDS.assistant` gains an `enum: ['agentTone']` array (the layout-field vocabulary loop in `fieldsFor()` already iterates `['text','rich','json','icontext']` — extend it to include `'enum'`).
- A new exported constant, parallel to `CTA_ICONS`, e.g. `AGENT_TONE_OPTIONS`, listing the same bounded set the Apex allow-list uses (§2.5) as `{ value, label }` pairs for the dropdown. **This list must stay in lockstep with the Apex `TONE_CLAUSES` map's keys** — there is no shared source of truth across Apex/JS in this codebase (same as every other cross-language constant here), so leave an explicit comment in both files pointing at the other, and QA should diff the two key sets (checklist §6.3).
- `LAYOUT_HINTS.assistant` gets a short addition noting the new field.

### 2.4 Client side: `gtmFieldEditor.js` / `.html`

- Add `isEnum: type === 'enum'` next to the existing `isTextShort`/`isTextLong`/`isRich`/`isJson`/`isIconText` flags (~line 106-116).
- In the template, a new `<template if:true={f.isEnum}>` block rendering `<lightning-combobox variant="label-hidden" value={f.value} options={f.options} data-id={f.id} onchange={handleTextChange}>` — reuses the existing `handleTextChange` handler and `textValue` column unchanged; the only new work is populating `f.options` from `AGENT_TONE_OPTIONS` keyed by `f.fieldKey` when building each field's view model.
- `gtmContentManager.js`'s `COLUMN` map (`{ text: 'textValue', rich: 'richValue', json: 'jsonValue' }`) needs `enum: 'textValue'` added, or a field of type `enum` reads as `undefined` when the page loads (`r[COLUMN[r.fieldType || 'text']]`).
- **Deliberately do not add `enum` to `fieldTypeOptions`** (the type combobox in the ad-hoc "Add a field" modal, ~gtmFieldEditor.html:244). That modal is for free-form fields a content author invents on the spot; an enum type only makes sense when a curated option list exists for that exact field key. `agentTone` is created instead through the existing "missing fields" quick-add affordance (`gcm-missing-add`, driven by `fieldsFor(layoutType)` — since `agentTone` is now declared in `LAYOUT_FIELDS.assistant`, it will appear there automatically with the correct type, no manual type selection possible or needed).

### 2.5 Server side: a new `GtmAgentTone` class

```apex
public without sharing class GtmAgentTone {
    private static final String FRAMEWORK_KEY  = 'gtm';       // mirrors gtmPageLayouts.FRAMEWORK_KEY
    private static final String TEMPLATE_TYPE  = 'assistant';
    private static final String CONTENT_ADDR   = 'assistant::agentTone';
    public  static final String DEFAULT_KEY    = 'professional-concise';

    // Keys here MUST match AGENT_TONE_OPTIONS in gtmPageLayouts.js exactly.
    // The value is the ONLY text that ever reaches the prompt — the field
    // itself only ever selects a key; it never supplies prompt text.
    private static final Map<String,String> TONE_CLAUSES = new Map<String,String>{
        'professional-concise' => 'Professional and concise. One or two sentences per response.',
        'warm-consultative'    => 'Warm and consultative, like a trusted advisor speaking with a peer. Two to three sentences; more conversational than clipped.',
        'direct-executive'     => 'Direct and efficient, addressing a senior executive audience. One sentence where possible — no filler, no hedging.',
        'technical-precise'    => 'Precise and technically fluent. Prefer exact field, object and platform names over general language.'
    };

    /** The one thing callers use. Never throws, never returns free text
     *  that didn't come from the map above. */
    public static String clause() {
        Map<String,String> content =
            GtmPageContentReader.getPageContent(FRAMEWORK_KEY, TEMPLATE_TYPE, null);
        String key = content.get(CONTENT_ADDR);
        return TONE_CLAUSES.containsKey(key) ? TONE_CLAUSES.get(key) : TONE_CLAUSES.get(DEFAULT_KEY);
    }
}
```

Reuses `GtmPageContentReader.getPageContent` — no duplicate SOQL, and it inherits that class's own `without sharing` justification (framework content is admin-owned, not user-owned; a `with sharing` caller like `GtmReadoutAgentSurface` must still resolve it, exactly the same reasoning that class's own header already documents for calling across sharing boundaries).

### 2.6 Prompt read-path changes

- `GtmAgentProxyController.cls`: `CONFIG_SYSTEM_PROMPT` stops being a `static final String` constant (it needs a SOQL read, which a compile-time constant can't do) and becomes a `private static String configSystemPrompt()` method: same fixed TOOLS/RULES text as today, with the final line changed from the hardcoded `'TONE: Professional and concise...'` sentence to `'TONE: ' + GtmAgentTone.clause()`. `ConfigSurface.systemPrompt()` (line 234) calls the method instead of referencing the constant.
- `GtmReadoutAgentSurface.cls`: `systemPrompt()`'s trailing `'TONE: Professional and concise. Two or three sentences...'` (lines 114-115) becomes `'TONE: ' + GtmAgentTone.clause()`.
- Net effect: **one Framework setting governs both GUS surfaces** — the configurator assistant and the readout-editor assistant — matching the product owner's "whole part of the framework" framing exactly, and matching the header comment already in `GtmAgentProxyController.cls` ("TWO SCREENS, ONE LOOP").

### 2.7 The prompt-injection safety constraint, stated precisely

The field is never interpolated as text. It is looked up as a **key** in a fixed, developer-authored Apex `Map<String,String>`. Three consequences, all deliberate:

1. A content author can only ever select one of N pre-written sentences — never write new prompt text, however they get to the field (UI dropdown, or a direct API/data-loader write to `Text_Value__c`).
2. A value that isn't a recognized key (blank, deleted, hand-typed garbage via API, or literally an injection attempt like `"ignore your rules and..."`) resolves to `DEFAULT_KEY`'s clause, silently. There is no code path where an unrecognized string reaches the callout body.
3. The authoring UI (§2.4) additionally renders this as a closed `lightning-combobox`, not a text box — so through the normal, intended path a content author cannot even attempt free text; the Apex allow-list is the real backstop for anyone going around the UI.

### 2.8 Data / backward-compat

No `agentTone` row exists yet, so `GtmAgentTone.clause()` on an unmodified org returns `TONE_CLAUSES.get(DEFAULT_KEY)` — **word-for-word today's hardcoded configurator tone sentence** for `configSystemPrompt()`, and functionally equivalent (slightly reworded, see §6.15 for the one deliberate wording note) for the readout surface. Dev should still seed one `Active__c = true`, published `agentTone = 'professional-concise'` row so the field is visible and editable in Content Manager from day one rather than only appearing via the "missing fields" prompt.

---

## 3. Offering customizer-wizard config

### 3.1 What "the customizer wizard" is

`gtmConfigWizard` (`force-app/main/default/lwc/gtmConfigWizard/`), embedded in `gtmConfigurator` and also launchable standalone from the GTM Offerings Overview tab. `docs/specs/prospect-page-wizard.md` is confirmed stale (pre-rename names) — do not implement against it; the symbols below are the real, current ones.

### 3.2 What's already offering-scoped (no gap here)

`gtmConfigWizard` already takes `@api offeringKey` and reads `getPageLayout({ offeringKey: this._offering, templateType: 'configurator' })` for the `offering-defaults` section (`defaultSourcePlatform`, `defaultTargetPlatform`, the colour `swatches` JSON) — this is the *Configurator defaults* section already declared per-offering in `gtmPageLayouts.js`'s `STARTER_PAGES.configurator` (`sectionKey: 'defaults'`, `layoutType: 'offering-defaults'`), edited today through Content Manager under that offering's own key (e.g. `migration-accelerator`), never under `gtm`. This is exactly the Framework-vs-Offering split the product owner described, already built, already correct. **No change needed here** — confirmed as part of this audit, not assumed.

### 3.3 The actual gap

`SIZE_PRESETS` (`gtmConfigWizard.js`, module-level `const`, lines ~24-28) — the S/M/L "environment size" presets (label, sub-label, asset count, dependency count, health score) a rep picks in the wizard's Environment step — is a **hardcoded object, identical for every offering, with no Content Manager path to it at all**. This is the concrete instance of the pattern the product owner named: once a second offering exists with a genuinely different typical estate size, there is no way for a content author to give it its own presets without a developer editing this constant and redeploying.

### 3.4 Design

Extend the *existing* `offering-defaults` JSON vocabulary — do not create a new section, layout type, or object:

- `gtmPageLayouts.js`: `LAYOUT_FIELDS['offering-defaults'].json` gains `'sizePresets'` (currently `['genericDemoDeps', 'genericChips', 'swatches']`).
- Shape (array of objects, same "repeatable item" shape `gtmFieldEditor.js`'s `buildItems()` already renders generically for `swatches`/`cards`/`phases` — **zero new editor UI code needed**, it derives its columns from the object's own keys):
  ```json
  [
    { "key": "S", "label": "Small",  "sub": "Under 1,000 assets", "assetCount": 800,   "dependencyCount": 1400,  "healthScore": 78 },
    { "key": "M", "label": "Medium", "sub": "~4,000 assets",      "assetCount": 4128,  "dependencyCount": 9640,  "healthScore": 62 },
    { "key": "L", "label": "Large",  "sub": "10,000+ assets",     "assetCount": 12400, "dependencyCount": 26800, "healthScore": 45 }
  ]
  ```
- `gtmConfigWizard.js`: in `connectedCallback()`'s `getPageLayout` `.then()`, alongside the existing `swatches` parse, add `let sizePresets; try { sizePresets = JSON.parse(c['defaults::sizePresets'] || '[]'); } catch (e) { sizePresets = []; }`, store on `this._sizePresets` (a new `@track` array), **falling back to the current hardcoded S/M/L object when the parsed array is empty or malformed** — this is the backward-compat guarantee: an offering with no authored presets behaves exactly as today.
- `sizeCards` getter and `handleSizePick(event)` (lines ~645-665) change from iterating `Object.keys(SIZE_PRESETS)` to iterating `this._sizePresets` (resolved array, CMS-or-fallback), keyed by each item's own `key`.

### 3.5 UI location

Content Manager → pick the offering (e.g. `migration-accelerator`) → **Configurator** page → **Configurator defaults** section (already exists) → new **Size Presets** field, edited with the same repeatable-item JSON editor already used for **Swatches** on the same section — same screen, same pattern, zero new navigation.

### 3.6 Seed data

Dev must insert one `GTM_Page_Content__c` row — `Offering_Key__c = 'migration-accelerator'`, `Template_Type__c = 'configurator'`, `Section_Key__c = 'defaults'`, `Field_Key__c = 'sizePresets'`, `Field_Type__c = 'json'`, `Active__c = true`, published — carrying the **exact historical values** shown in §3.4, so the cutover changes nothing observable. The JS fallback is a defensive backstop for a future second offering that hasn't authored presets yet, not the primary path for Migration Accelerator once this ships.

### 3.7 Deliberately out of scope (and why)

- **Step count/flow** (`TOTAL_STEPS = 8`, the `stepDots` label array `['Company','Industry','Colour','Environment','Note','Contact','Password','Review']`) — this is wizard *chrome*, not business content. Making the step sequence itself per-offering-configurable is a materially larger change (new layout type, renderer work) the product owner didn't ask for and that isn't required to unblock a second offering having its own presets/defaults. Flag as future work only if a second offering needs a genuinely different step flow.
- **`PS_RED`** (PS-brand accent fallback used only when a rep gives no website to auto-detect from) and the **`'migration-accelerator'`** string literal in `get _offering()`'s fallback — both are reasonable single-offering-today defaults; not business content a content author would expect to touch. Revisit once a second offering actually ships.

### 3.8 A bug found in the same surface, recommended to fix alongside

`GtmAgentGetConfigState.buildOutput()` (`force-app/main/default/classes/GtmAgentGetConfigState.cls:74-81`) — the tool GUS calls to read configurator state — hardcodes `WHERE Offering_Key__c = 'migration-accelerator'` **and** `Template_Type__c = 'story'` when collecting `availableIndustries`. Two problems: (1) once a second offering exists, GUS will report Migration Accelerator's industry keys regardless of which offering the rep is actually configuring — neither the `configId` nor any parameter threads the real offering key into this method; (2) industries are declared as living under the Framework's `industry-chooser` template per `gtmPageLayouts.js`'s own comment ("Industries are a shared taxonomy... belong to the framework"), not under a per-offering `story` template, so this may already be reading the wrong template type today. **Recommend build now** — it's small, contained, and directly blocks correct GUS behavior the moment a second offering exists, which is the exact scenario item 2 exists to prepare for. Not scope creep; it's the same gap under a different filename.

---

## 4. Broader manageability audit — full findings list

| # | Finding | Severity | Recommendation |
|---|---|---|---|
| A | `GtmAgentGetConfigState` hardcodes `Offering_Key__c='migration-accelerator'`, wrong `Template_Type__c` for industries (§3.8) | High — silently wrong once a 2nd offering exists, possibly already wrong | **Build now**, bundled with item 2 |
| B | GUS tone hardcoded in two Apex classes, no content-author path (item 1) | High — named directly by the product owner | **Build now** |
| C | Wizard `SIZE_PRESETS` hardcoded, no content-author path (item 2) | High — named directly by the product owner | **Build now** |
| D | `gtmReadoutAssist` (readout-editor GUS panel) hardcodes its own "GUS" name and all status/error copy in `.js`/`.html`, entirely disconnected from the Framework `assistant::assistantName`/`greeting` content that `gtmAgentBubble` (configurator GUS) already reads live. Renaming the assistant character via Content Manager today only rebrands the configurator bubble — the readout panel silently keeps saying "GUS." | Medium — inconsistent, surprising, but cosmetic; the readout surface still functions correctly | **Defer.** Contained fix later: wire `gtmReadoutAssist` to `GtmPageContentReader.getPageLayout('gtm','assistant',null)` the same way `gtmAgentBubble` already does. Out of scope for tonight's two named asks. |
| E | `gtmConfigBooking.js` hardcodes `PLATFORMS`/`SIZES`/`TIMELINES` picklists for the guest-facing "book a call" qualification form — no CMS backing, a content author cannot add/remove an option (e.g. add "SFMC Next," drop "Adobe/Pardot") without a deploy | Medium — generic lead-qualification copy, not core narrative | **Defer.** Would follow the same `enum` field-type pattern built for item 1 once that exists; low urgency since MVP adapter matrix doesn't require this exact list. |
| F | `PS_RED` accent fallback, `'migration-accelerator'` offeringKey string fallback in `gtmConfigWizard.js` | Low — reasonable single-offering defaults today | **Defer** until a second offering ships and needs its own fallback. |
| G | `GtmAssessmentInstrument.UNDECIDED_TARGET_NOTE`, `GtmAssessmentScoring.HIGH_REBUILD_RATIO_MESSAGE` — hardcoded Apex strings that do appear in reader-facing readout annotations | Low, by design | **No action.** Tightly coupled to the specific scoring gates/bands they describe (unlike the fully author-owned instrument YAML) — treat as engineering-owned diagnostic labels, not content. Documented here as a deliberate call, not an oversight. |
| H | Configurator "offering-defaults" (swatches, default platforms, baseline asset/dep/health, generic demo root/deps/chips) | — | **Confirmed OK, no gap.** Already offering-scoped and content-author-editable; verified as part of this audit (§3.2). |

---

## 5. Verification checklist for QA

### Source / static

1. `GTM_Page_Content__c/fields/Field_Type__c.field-meta.xml` contains a picklist value `enum`.
2. `GtmPageSectionController.cls` `VALUE_TYPES` set includes `'enum'`.
3. `gtmPageLayouts.js`: `LAYOUT_FIELDS.assistant` includes `enum: ['agentTone']`; an options export (e.g. `AGENT_TONE_OPTIONS`) exists. **Diff its key set against `GtmAgentTone.TONE_CLAUSES`'s keys in Apex — they must match exactly.**
4. `gtmFieldEditor.js`/`.html`: a field with `fieldType === 'enum'` renders a `lightning-combobox`, not a text input; `fieldTypeOptions` (the ad-hoc "Add a field" modal's type list) does **not** offer `'enum'` as a manually-creatable type.
5. `gtmContentManager.js`'s `COLUMN` map includes `enum: 'textValue'`.
6. `GtmAgentTone.cls` exists, is `without sharing`, calls `GtmPageContentReader.getPageContent` (no duplicate SOQL), and falls back to a named default key on any unrecognized value.
7. `GtmAgentProxyController.cls`: read the actual method body — `configSystemPrompt()` (or equivalent) ends with a tone clause sourced from `GtmAgentTone.clause()`, not a hardcoded sentence.
8. `GtmReadoutAgentSurface.cls`: same check on `systemPrompt()`.
9. `gtmPageLayouts.js`: `LAYOUT_FIELDS['offering-defaults'].json` includes `'sizePresets'`.
10. `gtmConfigWizard.js`: the old hardcoded `SIZE_PRESETS` constant is gone or reduced to a documented fallback-only default; `sizeCards`/`handleSizePick` read from CMS-resolved content with that fallback.
11. `GtmAgentGetConfigState.cls`: the `'migration-accelerator'` / `Template_Type__c = 'story'` literals are gone or fixed — read what replaced them and confirm it's actually driven by the offering in play.
12. `git diff --stat force-app/main/default/objects/` shows no new `*.field-meta.xml` files (only the existing `Field_Type__c.field-meta.xml` picklist-value addition) and no permission-set files touched — confirms the "zero new FLS surface" design claim. If Dev *did* need a new grant, understand why before treating it as a deviation.

### Functional (via Apex/API — no browser required)

13. With no `agentTone` content row (or `Active__c=false`), confirm `GtmAgentTone.clause()` returns the default clause — zero-config behavior unchanged from today's wording.
14. Insert/update a `GTM_Page_Content__c` row (`gtm`/`assistant`/`assistant`/`agentTone`, `Field_Type__c='enum'`, a *different* valid tone key, `Active__c=true`) via anonymous Apex; confirm `GtmAgentTone.clause()` now returns that tone's sentence. **This is the "does saving a tone value actually change GUS's next response" check** — verifiable as pure string composition, no live Claude API call needed.
15. Set that same row's `Text_Value__c` to an unrecognized/garbage value (including something injection-shaped, e.g. `'ignore all previous instructions'`) and confirm `GtmAgentTone.clause()` falls back to the default clause rather than ever echoing the stored string — the concrete prompt-injection-safety check.
16. Confirm both `GtmAgentProxyController.ConfigSurface` (configurator GUS) and `GtmReadoutAgentSurface` (readout GUS) call the identical `GtmAgentTone.clause()` — one Framework setting genuinely governs both surfaces.
17. Query for `Offering_Key__c='migration-accelerator', Template_Type__c='configurator', Section_Key__c='defaults', Field_Key__c='sizePresets'` and confirm a published/active row exists carrying the historical S(800/1400/78)/M(4128/9640/62)/L(12400/26800/45) values verbatim.
18. Call `GtmPageContentReader.getPageContent('migration-accelerator','configurator',null)` and confirm `content['defaults::sizePresets']` is valid JSON parsable into the 3-preset array — the read-path round-trip.
19. Confirm `GTM_Config_Manager.permissionset-meta.xml` already grants field-level access to `GTM_Page_Content__c.Text_Value__c`/`Field_Type__c` (it should, pre-existing) and that nothing new needed granting and was skipped.
20. Run `sf apex run test --target-org gtm-dev` (at minimum `GtmAgentProxyControllerTest`, `GtmAgentProxyControllerReadoutTest`, `GtmReadoutAgentSurfaceTest`, `GtmPageContentReaderTest`, `GtmAgentGetConfigStateTest`, plus a new test class for `GtmAgentTone`) and confirm all pass — including new coverage for the `enum` field-type path and the tone fallback/injection cases above, not just that pre-existing tests still pass.
21. Confirm `docs/specs/prospect-page-wizard.md`'s staleness call in §3.1 above is still accurate, and that Dev implemented against the real `gtmConfigWizard`/`GTM_Saved_Configuration__c` symbols rather than the stale doc's names.

---

## 6. Handoff

Dev implements §2 and §3 above (plus the bundled fix in §3.8) in full; the deferred items in §4 (D, E, F) are documented findings, not build items — file them as backlog notes rather than implementing tonight unless the product owner says otherwise. QA validates against §5 once Dev reports done, same two-round pattern as the docs pipeline (`architect-review-round-1.md`, `qa-approval.md`).
