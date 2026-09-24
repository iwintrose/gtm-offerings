# GTM Instrument Editor Rework — Architecture Contract

Status: sub-issue 01 of 4 (schema + permission sets). This document is the
Contract-First deliverable for the umbrella `issue-instrument-editor-rework`
and is binding on sub-issues 02 (Apex controller/gate), 03 (`gtmRuleEngine`),
and 04 (`gtmInstrumentAuthor` LWC / `gtmOverview`). Do not re-derive field
names/types/shapes from scratch in those sub-issues — treat this file as the
source of truth and update it here first if a shape needs to change.

## 1. Purpose

Replaces YAML+CustomMetadata-authored assessment instruments with
live-editable custom objects, so non-technical Content Managers can author
questionnaires directly in the GTM Content Manager app, without a deploy.

This is additive, not a migration: Migration Accelerator's existing
YAML/CMDT-driven instrument (`GTM_Assessment_*__mdt`) is untouched and stays
live throughout. New offerings can opt into the new model by creating a
`GTM_Instrument__c` row; offerings that never create one keep working exactly
as they do today (see §4, grandfather rule).

## 2. Schema

### 2.1 `GTM_Instrument__c`

One record per Offering. Linked to `GTM_Offering__mdt` by
`Offering_Key__c` matching `GTM_Offering__mdt.Offering_Key__c` — a plain text
convention, **no formal relationship field**, matching how the rest of the
codebase (`GTM_Assessment_*__mdt`, `GTM_Saved_Configuration__c.Offering__c`)
already references offerings (ADR-0009).

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `Name` | Text (standard) | — | — | Instrument display name, entered by the Content Manager. |
| `Offering_Key__c` | Text(100) | Yes, unique | — | Matches `GTM_Offering__mdt.Offering_Key__c`. Case-insensitive unique. |
| `Status__c` | Picklist (restricted): `Draft` / `Active` / `Archived` | Yes | `Draft` | Only `Active` counts toward `isAssessmentAvailable` (§4). |
| `Version__c` | Number(18,0) | Yes | `1` | Bumped by `GtmInstrumentController.publishInstrument` on each publish. |

`Offering_Key__c`, `Status__c`, and `Version__c` are all required fields —
per CLAUDE.md §6, required fields cannot take explicit `fieldPermissions`
entries; they are implicitly visible to anyone with object-level access.

### 2.2 `GTM_Instrument_Question__c`

Child of `GTM_Instrument__c` via **Master-Detail** (`sharingModel:
ControlledByParent`, cascade-deletes with the parent, rollup-summary-capable
if ever needed).

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `Name` | AutoNumber (`IQ-{0000}`) | — | — | Standard name field, not meaningful to authors. |
| `GTM_Instrument__c` | Master-Detail → `GTM_Instrument__c` | Yes (implicit) | — | Parent instrument. No explicit `fieldPermissions` entry (master-detail). |
| `Slot_Order__c` | Number(18,0) | Yes | — | Authoring/display order within the parent instrument. |
| `Question_Text__c` | Long Text Area (32,768) | No | — | Prompt shown to the guest. |
| `Options_JSON__c` | Long Text Area (32,768) | No | — | JSON array of answer options — see §3.1. |
| `Rules_JSON__c` | Long Text Area (32,768) | No | — | JSON array of branching rules — see §3.2. |
| `Required__c` | Checkbox | No | `false` | Can be flipped true at runtime by a `MAKE_REQUIRED` rule even when authored false. |
| `Question_Key__c` | Text(100) | No | — | Stable slug, referenced by other questions' `Rules_JSON__c` `field`/`target` values — survives record recreation/reordering, unlike record Id. |

`GTM_Instrument__c` (master-detail) and `Slot_Order__c` (required) get no
explicit `fieldPermissions` entries, per the same CLAUDE.md §6 rule.

## 3. JSON Shapes

Both `Options_JSON__c` and `Rules_JSON__c` are opaque `LongTextArea` fields
from Salesforce's point of view — validation of these shapes happens in
Apex (sub-issue 02) and/or the LWC (sub-issue 04), not via a formula/
validation rule on the field.

### 3.1 `Options_JSON__c`

Array of option objects:

```json
[
  { "label": "Yes", "value": "yes", "points": 10 },
  { "label": "No", "value": "no", "points": 0 }
]
```

- `label` (string, required): guest-facing option text.
- `value` (string, required): stable value stored on the response and
  referenced by `Rules_JSON__c` conditions' `value`.
- `points` (number, required): score contribution when this option is
  selected.

Empty/blank `Options_JSON__c` means a free-text question (no fixed option
set) — sub-issue 04's editor must treat `null`/`""`/`"[]"` as "no options
authored yet", not an error state.

### 3.2 `Rules_JSON__c`

Array of branching-rule objects, each evaluated independently in document
order by sub-issue 03's `gtmRuleEngine`:

```json
[
  {
    "logic": "AND",
    "conditions": [
      { "field": "q1", "operator": "EQUALS", "value": "yes" },
      { "field": "q2", "operator": "GREATER_THAN", "value": "5" }
    ],
    "action": "SHOW",
    "target": "q3"
  }
]
```

- `logic`: `AND` | `OR` — how `conditions` combine.
- `conditions`: array of `{ field, operator, value }`.
  - `field`: the `Question_Key__c` of the question supplying the answer
    being tested (not a record Id).
  - `operator`: one of `EQUALS`, `NOT_EQUALS`, `CONTAINS`, `GREATER_THAN`,
    `LESS_THAN`, `IS_EMPTY`, `IS_NOT_EMPTY`. `value` is ignored/optional for
    `IS_EMPTY`/`IS_NOT_EMPTY`.
  - `value`: string comparison operand (numeric comparisons for
    `GREATER_THAN`/`LESS_THAN` are done on the parsed numeric value of the
    stored answer).
- `action`: one of `SHOW`, `HIDE`, `SKIP_TO_SECTION`, `MAKE_REQUIRED`.
- `target`: the `Question_Key__c` (or section identifier, for
  `SKIP_TO_SECTION`) the action applies to.

Empty/blank `Rules_JSON__c` means the question has no branching behavior —
always shown, in authored `Slot_Order__c` order.

## 4. Apex Surface (sub-issue 02 implements against this)

### 4.1 `GtmInstrumentController` (new class)

```apex
public with sharing class GtmInstrumentController {
    @AuraEnabled(cacheable=true)
    public static InstrumentDto getInstrumentForOffering(String offeringKey) { }

    @AuraEnabled
    public static InstrumentDto createInstrument(String offeringKey, String name) { }

    @AuraEnabled
    public static void saveInstrument(Id instrumentId, String name, String status) { }

    @AuraEnabled
    public static void saveQuestions(Id instrumentId, List<QuestionDto> questions) { }

    @AuraEnabled
    public static void publishInstrument(Id instrumentId) { }

    @AuraEnabled
    public static void archiveInstrument(Id instrumentId) { }
}
```

- `getInstrumentForOffering` returns the instrument (if any) plus its
  ordered questions for a given `offeringKey`, for the `gtmInstrumentAuthor`
  LWC to hydrate.
- `createInstrument` inserts a new `GTM_Instrument__c` in `Draft` status,
  `Version__c = 1`. Content Manager UX (sub-issue 04) must warn before this
  call for offerings with zero prior instrument rows, per §5's grandfather
  inversion.
- `saveInstrument` / `saveQuestions` are plain field updates — no DML inside
  a GUS tool implementation is required here since this controller is not a
  GUS tool-surface class; the "no DML/callouts inside a tool implementation"
  rule (CLAUDE.md/AGENTS.md §1) applies specifically to GUS's own tool
  classes, not this Content Manager-facing controller.
- `publishInstrument` sets `Status__c = 'Active'` and increments
  `Version__c`.
- `archiveInstrument` sets `Status__c = 'Archived'`.

Exact DTO field names are sub-issue 02's call, but must map 1:1 onto the
schema in §2 (i.e. `QuestionDto` carries `slotOrder`, `questionText`,
`optionsJson`, `rulesJson`, `required`, `questionKey`).

### 4.2 `GtmAssessmentQuestions.isAssessmentAvailable` (new method on existing class)

Added to the existing `GtmAssessmentQuestions.cls` — **not** a new class,
and **not** a method on `GtmAssessmentInstrument.cls` (that class is
migration-platform-pair-specific and explicitly protected by the umbrella
scope). Rationale: `GtmAssessmentQuestions.cls` is already the
offering-generic, `offeringKey`-parameterized class called from
`gtmAssessmentQuestionnaire.js`'s `connectedCallback` (~line 416) alongside
`GtmAssessmentInstrument.getPlatforms()`.

```apex
@AuraEnabled(cacheable=true)
public static Boolean isAssessmentAvailable(String offeringKey) { }
```

- Runs with whatever sharing model the rest of the class already uses
  (confirm at implementation time; must remain guest-safe).
- Read-only SOQL against `GTM_Instrument__c` only — no DML, no callouts.
- **Grandfather/opt-in rule** (binding, resolves umbrella ambiguity #2):

  ```
  isAssessmentAvailable(offeringKey):
      instruments = SELECT Status__c FROM GTM_Instrument__c
                    WHERE Offering_Key__c = :offeringKey
      if instruments.isEmpty():
          return true   // legacy/ungated offering (e.g. Migration
                         // Accelerator today) — defer entirely to the
                         // existing YAML/CMDT guest path.
      return instruments.any(i -> i.Status__c == 'Active')
          // offering has opted in (>=1 row exists): gate for real.
          // False only when every row is Draft/Archived.
  ```

- **Important inversion for sub-issue 04's UX copy:** the moment an
  offering's *first* `GTM_Instrument__c` row is created (even in `Draft`),
  it silently opts that offering out of the "always available" legacy
  default and into real gating — before anything is published. A Content
  Manager who creates a Draft instrument for an already-live offering (e.g.
  Migration Accelerator) takes its live guest flow down until they publish.
  Sub-issue 04's create-flow must warn about this; sub-issue 02's method
  contract must not be redesigned to paper over it.
- Test matrix (binding on sub-issue 02): no offering / no instrument rows /
  Draft only / Archived only / Active / Active+Archived mixed /
  deleted-then-recreated.

### 4.3 Wiring (sub-issue 04's job, not 02's)

`isAssessmentAvailable` is called from `gtmAssessmentQuestionnaire.js`'s
existing `Promise.all` in `connectedCallback`, alongside
`GtmAssessmentInstrument.getPlatforms()` and
`GtmAssessmentQuestions.getQuestionnaire({ offeringKey })`. Sub-issue 02
only builds and unit-tests the method; it does not touch the LWC.

## 5. LWC Data Contract — `gtmInstrumentAuthor` (sub-issue 04)

`gtmInstrumentAuthor` (and its summary consumer `gtmOverview`) consume the
`GtmInstrumentController` DTOs described in §4.1. Expected shape (exact
casing/nesting to be finalized in sub-issue 04's own contract note, but must
carry these fields at minimum):

```js
// InstrumentDto
{
  id: '<record Id>',
  offeringKey: 'migration-accelerator',
  name: 'Migration Accelerator Assessment',
  status: 'Draft' | 'Active' | 'Archived',
  version: 1,
  questions: [ /* QuestionDto[] */ ]
}

// QuestionDto
{
  id: '<record Id or null for unsaved>',
  slotOrder: 1,
  questionText: 'How many source systems are in scope?',
  optionsJson: '[{"label":"1-2","value":"1-2","points":10}, ...]', // string, parsed client-side
  rulesJson: '[{"logic":"AND","conditions":[...],"action":"SHOW","target":"q3"}]', // string, parsed client-side
  required: true,
  questionKey: 'q1'
}
```

- `optionsJson`/`rulesJson` travel as JSON-encoded strings end-to-end
  (matching the underlying `LongTextArea` fields) — the LWC is responsible
  for `JSON.parse`/`JSON.stringify` at the edges, matching the shapes in §3.
- `gtmOverview`'s summary view only needs `offeringKey`, `name`, `status`,
  `version`, and a question count — it does not need full `Options_JSON__c`/
  `Rules_JSON__c` payloads.

## 6. Permission Sets

| Object | `GTM_Content_Manager` | `GTM_Content_Admin` | `GTM_Offering_Admin` / `GTM_Offering_User` / `GTM_Guest` |
|---|---|---|---|
| `GTM_Instrument__c` | CRUD, no viewAll/modifyAll | Full CRUD + viewAll/modifyAll | No access |
| `GTM_Instrument_Question__c` | CRUD, no viewAll/modifyAll | Full CRUD + viewAll/modifyAll | No access |

FLS: both permission sets grant explicit `fieldPermissions` (readable +
editable) on every non-required, non-master-detail field:
`GTM_Instrument__c.Status__c` is **not** granted explicitly (it's required —
see §2.1); `Question_Text__c`, `Options_JSON__c`, `Rules_JSON__c`,
`Required__c`, `Question_Key__c` are granted explicitly on
`GTM_Instrument_Question__c`. `Offering_Key__c`, `Version__c`,
`GTM_Instrument__c` (master-detail), and `Slot_Order__c` are required/
master-detail fields and get no explicit entries (implicit visibility per
CLAUDE.md §6).

Guests reach availability status only through
`GtmAssessmentQuestions.isAssessmentAvailable` (§4.2) — never direct object
CRUD. `GTM_Guest` gets no grant on either object in this pass.

## 7. Explicitly Out of Scope (this sub-issue)

- No Apex classes, trigger, or LWC changes (sub-issues 02/03/04).
- No `GTM_Offering__mdt` relationship field — `Offering_Key__c` stays plain
  text.
- No migration/seed/backfill of `GTM_Instrument__c` rows for Migration
  Accelerator or any existing offering — both new objects start empty.
