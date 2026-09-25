# Industry Variants — Agentforce-Assisted Drafting (Track A)

Issue: `industry-variants-agentforce-draft` (4 of 4 in the "Industry-Specific
Section Variants" series — see
`docs/agent-artifacts/task-scope-industry-variants-agentforce-draft.md`).
Depends on `docs/architecture/industry-variants-core.md` (the "+ Industry
variant" modal and `industryKey` field-editor plumbing this issue builds on).

This is the Contract-First artifact required by `CLAUDE.md` §4. Track A only
(proxy-based GUS, reused pattern). Track B (live Data Cloud personalization)
is explicitly not designed or stubbed here.

## 1. Reuse decision: the "research brief"

The BA flagged an open question — are per-industry research briefs
hardcoded, config, or reused from already-loaded variant copy? Confirmed by
reading `GtmPageContentReader.getIndustryProfiles`
(`force-app/main/default/classes/GtmPageContentReader.cls`): industry briefs
already exist as `IndustryProfile` rows (`industryLabel`, `pickerBlurb`,
`coverSub`, `problem`, `useCase`, `solution`, `proofLine`, `whyLine`,
`whyHead`, `uniquePoints`) read from the framework's `industry-chooser`
taxonomy (`Offering_Key__c = 'gtm'`, `Template_Type__c = 'industry-chooser'`),
loaded by the `industry-variants-content-load` issue. **Decision: reuse this
directly.** No new storage, no hardcoded brief table in Apex.

## 2. Apex Contracts

### `GtmAgentGetSectionContent` (new invocable action, read-only)

Modeled on `GtmAgentGetConfigState`. Zero DML, zero callout.

```apex
public class Input {
    @InvocableVariable(required=true)  public String offeringKey;
    @InvocableVariable(required=true)  public String templateType;
    @InvocableVariable(required=true)  public String sectionKey;   // the VARIANT's own section key
}

public class Output {
    @InvocableVariable public String sectionLabel;
    @InvocableVariable public String layoutType;
    @InvocableVariable public String industryKey;
    @InvocableVariable public String industryLabel;
    @InvocableVariable public String baseSectionKey;
    @InvocableVariable public List<FieldSnapshot> fields;       // fieldKey, fieldType, label, currentValue
    @InvocableVariable public String industryBriefJson;         // serialized IndustryProfile for industryKey, or "{}" if none
}
```

Behavior:
- Looks up the `GTM_Page_Section__c` row for `(offeringKey, templateType,
  sectionKey)`. Missing row -> all-blank output (never throws — same
  fail-quiet convention `GtmAgentGetConfigState` uses).
- Only proceeds if the resolved row has a non-blank `Industry_Key__c` (i.e.
  it actually is a variant row) — a `sectionKey` for an ordinary section
  returns blank `fields`/`industryBriefJson`, so the tool cannot be pointed
  at non-variant content even if a confused model tries.
- `fields` = the variant's own `GTM_Page_Content__c` rows (`Active__c =
  true`), `fieldType` in `{text, rich}` only (json/icontext/enum fields are
  omitted — see §5 non-goals).
- `industryBriefJson` = `JSON.serialize(GtmPageContentReader.getIndustryProfiles(
  GtmPageContentController.FRAMEWORK_KEY, 'industry-chooser'))`, filtered to
  the one profile matching the row's `Industry_Key__c` (or `{}` if the
  industry has no live/published profile yet).

### `GtmAgentDraftSectionVariant` (new invocable action, propose-only)

Modeled on `GtmAgentApplyConfigUpdate` / `GtmReadoutAgentSurface.updateDraft`.
Zero DML, zero callout. **Never writes `GTM_Page_Content__c`.**

```apex
public class Input {
    @InvocableVariable(required=true) public String offeringKey;
    @InvocableVariable(required=true) public String templateType;
    @InvocableVariable(required=true) public String sectionKey;      // the VARIANT's own section key
    @InvocableVariable(required=true) public String fieldValuesJson; // {"fieldKey": "proposed copy", ...}
}

public class Output {
    @InvocableVariable public Boolean success;
    @InvocableVariable public String  appliedJson;    // the validated subset of fieldValuesJson
    @InvocableVariable public String  errorMessage;
}
```

Behavior:
- Re-resolves the section (same lookup as `GtmAgentGetSectionContent`) and
  re-derives its actual field list server-side — a key in `fieldValuesJson`
  that is not one of the section's own `text`/`rich` fields is dropped
  silently (not an error; the model may over-propose), same
  strip-unknown-keys convention `GtmAgentApplyConfigUpdate` uses.
- Per-field length guard: 8000 characters (matches `Rich_Value__c`'s LWC
  field-editor practical ceiling; longer values are rejected with an
  `errorMessage`, not truncated).
- Returns `success=false` if the section cannot be resolved, is not a
  variant row (`Industry_Key__c` blank), or nothing valid survives
  filtering.
- On success, the caller (the surface, not this action) is responsible for
  landing `appliedJson` into `accumulatedChanges` — this action itself does
  not know about the delta bag, keeping it a pure, independently-testable
  validator (this is the one deliberate divergence from
  `GtmAgentApplyConfigUpdate`, which does know about `accumulatedChanges`;
  here validation is reused by both the tool-use surface and, if ever
  needed, a non-chat caller).

## 3. The surface: `GtmContentDraftAgentSurface`

New class implementing `GtmAgentToolSurface`. `with sharing` (content
editors' own CRUD/FLS applies — this is not configurator page state).
Modeled most closely on `GtmReadoutAgentSurface`: **no tool accepts a
sectionKey argument.** The section is constructor state
(`offeringKey`/`templateType`/`sectionKey`), taken from the LWC's page
context at session start, so there is no shape of tool call — confused model
or prompt injection — that can reach a different section's content.

Tools exposed: `get_section_content`, `draft_section_variant`. System prompt
constrains GUS to: read the base fields + industry brief first, propose
copy that reads like it was written for that industry (using the brief's
`problem`/`useCase`/`solution`/`proofLine` language), never fabricate facts
the brief doesn't support, and state explicitly in its final reply that
nothing is saved yet — the editor reviews it in the field editor and
publishes (or doesn't) through the existing lifecycle.

`draft_section_variant`'s executor wraps `GtmAgentDraftSectionVariant`,
puts its `appliedJson` map into `accumulatedChanges['proposedFields']` (a
map, not a flat overwrite of `accumulatedChanges` itself, since a future
multi-field turn may accumulate proposals across several tool calls before
the model's final reply — `putAll`-merging the new keys into whatever
`proposedFields` map already exists this turn).

## 4. Entry point: `GtmAgentContentDraftController`

New, separate Apex class (deliberately **not** a new method added to
`GtmAgentProxyController`, and deliberately not exposing that whole class to
Content Manager users — see §6). One `@AuraEnabled` method:

```apex
public with sharing class GtmAgentContentDraftController {
    @AuraEnabled
    public static String chat(String offeringKey, String templateType, String sectionKey,
                              String userMessage, String historyJson) {
        // validates inputs, then:
        return GtmAgentProxyController.runLoop(
            new GtmContentDraftAgentSurface(offeringKey, templateType, sectionKey),
            userMessage, historyJson);
    }
}
```

Requires `GtmAgentProxyController.runLoop` to go from `private static` to
`public static` (same class, same behavior — a visibility change only, not a
new code path). This is the actual "provider seam" extension the scope doc
references: **not** a class-access grant on `GtmAgentProxyController` itself
(that would hand Content Manager users the configurator/readout/app entry
points too, which is the general F4 lifting the scope doc explicitly rules
out) but a second, narrow entry-point class that internally reuses the one
shared loop. Content Manager's permission sets get class access to
`GtmAgentContentDraftController` only; `GtmAgentProxyController` stays
ungranted for `GTM_Content_Manager`/`GTM_Content_Admin`, so `chat`,
`chatOnReadout` and `chatOnApp` remain unreachable from that app exactly as
F4 requires. (Apex class-access permission gates the entry point a client
directly invokes, not classes that entry point calls into server-side, so
this narrowing is real, not cosmetic — `GtmAgentContentDraftController` can
call `GtmAgentProxyController.runLoop` without the calling user needing
class access to `GtmAgentProxyController`.)

Provider/API key resolution (`GTM_Agent_Settings__c`) is unchanged — the
same org default key configured for the GTM_Offerings app's GUS is reused,
because Track A is explicitly "the existing proxy-based GUS pattern," not a
second key/provider surface.

## 5. LWC Contract

### `gtmContentManager.js`/`.html`

- The existing "+ Industry variant" modal is unchanged for section
  *creation*. A new **"Draft with AI"** action becomes available once a
  variant section exists and is the active section in the rail (i.e. after
  `handleCreateVariant` completes, or when navigating to any existing
  variant row) — a small button/affordance near the field editor header,
  visible only when `activeSection.industryKey` is non-blank.
- `handleOpenDraftWithAi()` opens a lightweight modal: a single free-text
  prompt box ("What should GUS know about this industry variant?", optional
  — blank is fine, GUS still has the brief) plus a "Draft" button.
- `handleDraftWithAi()` calls
  `chat({ offeringKey, templateType, sectionKey: activeKey, userMessage, historyJson: this.draftHistoryJson })`
  (imperative Apex import of
  `GtmAgentContentDraftController.chat`), shows a busy state, and on
  success reads `changes.proposedFields` (a `fieldKey -> proposed value`
  map) from the parsed response.
- For each `fieldKey` in `proposedFields`, finds the matching record in
  `this.records` (`sectionKey === activeKey && fieldKey === key`) and calls
  **the existing `this.writeValue(record.id, value)`** — the exact same
  method manual field edits already use. This is the regression guard: it
  sets `draftValue`/`isDraft = true`/`status = 'Draft'` and schedules
  `saveDrafts` (still `Draft` status) — never `publishPage`. There is no new
  write path; "Draft with AI" is a different way to call the function that
  already exists for typing into a field.
- The modal shows GUS's reply text and closes; the editor lands back on the
  field editor, which now shows the proposed copy as an editable draft
  exactly like it would after typing it in by hand. Nothing publishes.
- `draftHistoryJson` (per-section chat history) resets whenever `activeKey`
  changes, so a "Draft with AI" turn on one variant never leaks its history
  into another.

### `gtmFieldEditor.js`/`.html`

No contract change. "Draft with AI" writes into the same `records` array
`gtmFieldEditor` already renders `draftValue` from — the field editor has no
idea the value came from GUS rather than a keystroke, by design (it is not
supposed to know; that would be a second content-provenance concept the
Draft/Publish lifecycle doesn't otherwise have).

## 6. GenAiPlugin / Topic / Bot metadata (scaffolding, mirrors existing pattern)

Mirrors `GTM_Configurator_Assistant` + `GTMGetConfigState`/
`GTMApplyConfigUpdate` — unwired scaffolding until Agentforce is
provisioned on the org, same as the existing pair:

- `force-app/main/default/genAiFunctions/GtmAgentGetSectionContent/` — backs
  `GtmAgentGetSectionContent.execute()`.
- `force-app/main/default/genAiFunctions/GtmAgentDraftSectionVariant/` —
  backs `GtmAgentDraftSectionVariant.execute()`.
- `force-app/main/default/genAiPlugins/GTMGetSectionContent.genAiPlugin-meta.xml`
- `force-app/main/default/genAiPlugins/GTMDraftSectionVariant.genAiPlugin-meta.xml`
- `force-app/main/default/bots/GTM_Content_Drafting_Assistant/` — new Bot,
  `pluginType`/topic scoped to Content Manager's surface only (never wired
  into the GTM_Offerings app's utility bar or configurator bubble).

## 7. Permission sets (CLAUDE.md §6)

Confirmed by reading the existing grants: `GTM_Offering_User`/
`GTM_Offering_Admin` only grant `classAccesses` on `GtmAgentProxyController`
itself — `GtmAgentGetConfigState`/`GtmAgentApplyConfigUpdate` (the invocable
actions it calls server-side) have **no** `classAccesses` entry anywhere,
because Apex class-access permission only gates the class a client directly
invokes (the LWC's imperative Apex import), not classes that class calls
into internally. The same rule applies here, so only one class needs a new
grant:

| Class | GTM_Offering_User | GTM_Offering_Admin | GTM_Content_Manager | GTM_Content_Admin | GTM_Guest |
|---|---|---|---|---|---|
| `GtmAgentContentDraftController` | no | no | yes | yes | no |
| `GtmAgentGetSectionContent` | no | no | no *(called internally only)* | no *(called internally only)* | no |
| `GtmAgentDraftSectionVariant` | no | no | no *(called internally only)* | no *(called internally only)* | no |
| `GtmContentDraftAgentSurface` | no | no | no *(called internally only)* | no *(called internally only)* | no |

`GtmAgentContentDraftController` is not granted to
`GTM_Offering_User`/`GTM_Offering_Admin` — this is Content Manager's tool,
not GTM Offerings'. This intentionally inverts the usual `GtmAgent*` grant
pattern (`GtmAgentProxyController` is granted to `GTM_Offering_User`/
`GTM_Offering_Admin` only, never Content Manager) — that asymmetry *is* the
F4 boundary, preserved narrowly rather than erased.

No new fields, so the Architect's "`GTM_Offering_Admin` strict superset for
`GTM_Page_Section__c`-adjacent fields" pattern does not apply here — there is
nothing added to `GTM_Page_Section__c`/`GTM_Page_Content__c` to be a superset
of. Confirmed by re-reading the Code Dependency Checklist's "Introducing
database fields? NO" line against the implementation above: still true.

`GTM_Content_Admin` is a superset of `GTM_Content_Manager`'s object/field
access per the existing pattern in this codebase; the four `classAccesses`
grants above are mirrored identically on both for the same reason (an admin
who can do everything a manager can, including this).

## 8. Non-Goals (restated)

- No Data Cloud, no `NamedCredential`, no live per-visitor generation.
- No general GUS access expansion to Content Manager beyond the four classes
  above.
- `json`/`icontext`/`enum` typed fields are not draftable by this action
  (only `text`/`rich`). An editor can still type those by hand as today.
- No change to `chat`/`chatOnReadout`/`chatOnApp` on
  `GtmAgentProxyController` beyond `runLoop`'s visibility.
