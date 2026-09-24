# GTM Instrument Schema Rebuild — Architecture Contract

Status: sub-issue 01 of 4 (`assessment-instrument-rebuild-01-schema`), schema
+ permission sets only. This document is the Contract-First deliverable
(CLAUDE.md §4) for the `assessment-instrument-rebuild` umbrella and is
binding on sub-issues 02 (`assessment-instrument-rebuild-02-submission`), 03
(`...-03-rule-engine-migration`), and 04 (`...-04-editor-lwc-wiring`). Do not
re-derive field names/types/JSON shapes from scratch in those sub-issues —
treat this file as the source of truth and update it here first if a shape
needs to change.

## 0. Supersession

This document **supersedes the schema section (§2) of
`docs/architecture/gtm-instrument-editor.md`** for the rebuild effort. That
prior document's `GTM_Instrument__c` / `GTM_Instrument_Question__c` objects,
`GtmInstrumentController`, and the grandfather/opt-out availability rule
remain deployed and functionally live (they are not deleted by this
sub-issue — see §6), but no new work should target them. Per explicit user
decision, this is a rebuild, not an extension:

- The "grandfather YAML" opt-out described in `gtm-instrument-editor.md` §4.2
  is **not** carried forward to the new schema's availability semantics
  (sub-issue 02 defines the new rule against `GTM_Instrument_Definition__c`).
- The standalone `GTM_Instrument_Author` tab (visible today to
  `GTM_Content_Manager`/`GTM_Content_Admin`) is being retired in favor of
  authoring flows wired into the existing GTM Content Manager app
  (sub-issue 04) — this sub-issue does not remove the tab metadata yet (see
  §6), only stops adding permission-set grants for it on the new objects.

Sub-issues 02/03/04 must treat `gtm-instrument-editor.md` as historical
background only, not a binding contract, once this document lands.

## 1. Purpose

Replaces the additive `GTM_Instrument__c` / `GTM_Instrument_Question__c`
model (and, longer-term, the YAML+CustomMetadata `GTM_Assessment_*__mdt`
path once sub-issue 03 migrates it) with a richer Salesforce-native
instrument-definition schema that supports:

- Multiple question input types (single-select, multi-select, dropdown,
  numeric/maturity scale, matrix/grid, short text, long text), each with
  per-option points.
- Inline branching-rule storage, JSON shape carried forward unchanged from
  `GTM_Instrument_Question__c.Rules_JSON__c` (§3.2).
- A new **Outcome Mapping** construct: score range → result tier / readout
  template, author-configurable per instrument, replacing the fixed
  `Assessment_Tier__c` picklist used by the legacy YAML/CMDT path.
- A new lightweight per-instrument theme/style custom metadata type for
  guest-facing branding.

This sub-issue is **schema-only**: no Apex business logic, no LWC. Sub-issues
02/03/04 build against these objects.

## 2. Schema

### 2.1 `GTM_Instrument_Definition__c`

One record per Offering (or per variant, if an offering ever needs more than
one — nothing in this schema enforces one-per-offering beyond the unique
`Offering_Key__c`, matching the existing `GTM_Instrument__c` convention).
Linked to `GTM_Offering__mdt` by `Offering_Key__c` matching
`GTM_Offering__mdt.Offering_Key__c` — plain text convention, no formal
relationship field (ADR-0009), same pattern as `GTM_Instrument__c`,
`GTM_Assessment_*__mdt`, and `GTM_Saved_Configuration__c.Offering__c`.

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `Name` | Text (standard) | — | — | Instrument display name, entered by the Content Manager. |
| `Offering_Key__c` | Text(100) | Yes, unique | — | Matches `GTM_Offering__mdt.Offering_Key__c`. Case-insensitive unique. |
| `Status__c` | Picklist (restricted): `Draft` / `Active` / `Archived` | Yes | `Draft` | Only `Active` counts toward the guest-facing availability check sub-issue 02 defines. |
| `Version__c` | Number(18,0) | Yes | `1` | Bumped by the publish action (sub-issue 02) on each publish. |
| `Theme_Key__c` | Text(100) | No | — | Matches `GTM_Instrument_Theme__mdt.DeveloperName` — plain text convention, no formal metadata relationship. Blank = default/unthemed rendering. |

`Offering_Key__c`, `Status__c`, and `Version__c` are required fields — per
CLAUDE.md §6, required fields cannot take explicit `fieldPermissions`
entries; they are implicitly visible to anyone with object-level access.
`Theme_Key__c` is optional and does get an explicit grant (§6).

### 2.2 `GTM_Instrument_Question_Definition__c`

Child of `GTM_Instrument_Definition__c` via **Master-Detail**
(`sharingModel: ControlledByParent`, cascade-deletes with the parent).

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `Name` | AutoNumber (`IQD-{0000}`) | — | — | Standard name field, not meaningful to authors. |
| `GTM_Instrument_Definition__c` | Master-Detail → `GTM_Instrument_Definition__c` | Yes (implicit) | — | Parent instrument definition. No explicit `fieldPermissions` entry (master-detail). |
| `Slot_Order__c` | Number(18,0) | Yes | — | Authoring/display order within the parent instrument. |
| `Question_Text__c` | Long Text Area (32,768) | No | — | Prompt shown to the guest. |
| `Question_Type__c` | Picklist (restricted): `Single_Select` / `Multi_Select` / `Dropdown` / `Numeric_Scale` / `Matrix_Grid` / `Short_Text` / `Long_Text` | Yes | `Single_Select` | Drives how `Options_JSON__c` is shaped/interpreted — see §3.1. |
| `Options_JSON__c` | Long Text Area (32,768) | No | — | JSON payload of answer options and per-option points — see §3.1. |
| `Rules_JSON__c` | Long Text Area (32,768) | No | — | JSON array of branching rules — see §3.2 (unchanged shape from `GTM_Instrument_Question__c`). |
| `Required__c` | Checkbox | No | `false` | Can be flipped to true at runtime by a `MAKE_REQUIRED` rule even when authored false. |
| `Question_Key__c` | Text(100) | No | — | Stable slug, referenced by other questions' `Rules_JSON__c` `field`/`target` values — survives record recreation/reordering, unlike record Id. |
| `Min_Value__c` | Number(18,2) | No | — | `Numeric_Scale` only: lower bound of the scale. Ignored for other types. |
| `Max_Value__c` | Number(18,2) | No | — | `Numeric_Scale` only: upper bound of the scale. Ignored for other types. |
| `Points_Per_Unit__c` | Number(18,2) | No | — | `Numeric_Scale` only: score = selected value × this multiplier. Non-`Numeric_Scale` types score via per-option `points` in `Options_JSON__c` instead. |

`GTM_Instrument_Definition__c` (master-detail) and `Slot_Order__c` (required)
get no explicit `fieldPermissions` entries, per the same CLAUDE.md §6 rule.
`Question_Type__c` is required and also gets no explicit entry.

### 2.3 `GTM_Instrument_Outcome_Range__c`

Child of `GTM_Instrument_Definition__c` via **Master-Detail**
(`sharingModel: ControlledByParent`, cascade-deletes with the parent). This
is the new Outcome Mapping construct: each row maps a contiguous score range
to a result tier and (optionally) a readout template key.

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `Name` | AutoNumber (`OR-{0000}`) | — | — | Standard name field, not meaningful to authors. |
| `GTM_Instrument_Definition__c` | Master-Detail → `GTM_Instrument_Definition__c` | Yes (implicit) | — | Parent instrument definition. No explicit `fieldPermissions` entry (master-detail). |
| `Min_Score__c` | Number(18,2) | Yes | — | Inclusive lower bound of the total instrument score this range covers. |
| `Max_Score__c` | Number(18,2) | Yes | — | Inclusive upper bound of the total instrument score this range covers. |
| `Tier_Label__c` | Text(100) | No | — | Author-configurable result tier name (e.g. "Low Readiness", "High Readiness") — replaces the fixed `Assessment_Tier__c` picklist for instruments authored on this schema. |
| `Readout_Template_Key__c` | Text(100) | No | — | Free-text key identifying the readout content/template to use for a submission landing in this range. Resolution logic is a sub-issue 02/03 concern. |
| `Sort_Order__c` | Number(18,0) | No | — | Authoring/display order of this range within the parent instrument's outcome mapping list. |

`GTM_Instrument_Definition__c` (master-detail), `Min_Score__c`, and
`Max_Score__c` (required) get no explicit `fieldPermissions` entries, per
CLAUDE.md §6.

This sub-issue does not enforce non-overlapping ranges or full score-space
coverage at the schema layer (no validation rule) — sub-issue 02/04 own that
validation, at save time and/or in the author UI.

### 2.4 `GTM_Instrument_Theme__mdt` (new Custom Metadata Type)

Per-instrument branding/style, resolved via `GTM_Instrument_Definition__c
.Theme_Key__c` matching this type's `DeveloperName` — same plain-text
convention as `Offering_Key__c` (ADR-0009), no formal metadata relationship
field (custom objects cannot be the target of a CMDT relationship field).
This is new metadata, distinct from and unrelated to the existing
YAML-compiled `GTM_Assessment_*__mdt` types (`scripts/build-instrument.py`
does not touch it).

| Field | Type | Required | Notes |
|---|---|---|---|
| `MasterLabel` / `DeveloperName` | Standard CMDT fields | Yes | `DeveloperName` is the key matched by `Theme_Key__c`. |
| `Primary_Color__c` | Text(20) | No | Hex color for the primary brand accent. No format validation at the metadata layer. |
| `Secondary_Color__c` | Text(20) | No | Hex color for secondary/supporting brand elements. |
| `Accent_Color__c` | Text(20) | No | Hex color for interactive/highlight elements (buttons, progress indicators). |
| `Logo_URL__c` | Text(255) | No | Absolute URL to a logo image. Blank falls back to default site branding. |
| `Font_Family__c` | Text(255) | No | CSS `font-family` value. Blank falls back to the site's default font stack. |

All fields are optional — a theme record with everything blank is
functionally equivalent to no theme at all, which the rendering LWC
(sub-issue 04) must treat as "use default styling," not an error state.

## 3. JSON Shapes

Both `Options_JSON__c` and `Rules_JSON__c` are opaque `LongTextArea` fields
from Salesforce's point of view — validation of these shapes happens in Apex
(sub-issue 02) and/or the LWC (sub-issue 04), not via a formula/validation
rule on the field.

### 3.1 `Options_JSON__c`

Shape depends on `Question_Type__c`.

**`Single_Select` / `Multi_Select` / `Dropdown`** — array of option objects:

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
  selected. For `Multi_Select`, points from every selected option sum.

**`Numeric_Scale`** — `Options_JSON__c` is typically empty; scoring instead
uses `Min_Value__c`/`Max_Value__c`/`Points_Per_Unit__c` (§2.2). An author may
still optionally supply labeled anchor points as an array of
`{ "value": <number>, "label": "<string>" }` objects (no `points` — those
come from the multiplier), purely for UI display (e.g. labeling 1 = "Not
started", 5 = "Fully mature").

**`Matrix_Grid`** — object with `rows` and `columns` arrays, each shaped like
the select-option array above, plus a `cellPoints` lookup:

```json
{
  "rows": [ { "label": "Data Migration", "value": "data_migration" } ],
  "columns": [ { "label": "Not Started", "value": "not_started", "points": 0 },
               { "label": "Complete", "value": "complete", "points": 10 } ],
  "cellPoints": { "data_migration": { "not_started": 0, "complete": 10 } }
}
```

- `rows`/`columns`: `{ label, value }` (rows carry no `points` of their own).
- `cellPoints`: optional override map keyed `rowValue -> columnValue ->
  points`, for when a cell's score isn't simply the column's own `points`.
  Absent `cellPoints` (or an absent cell within it) falls back to the
  matching column's `points`.

**`Short_Text` / `Long_Text`** — `Options_JSON__c` is empty/blank; there is
no fixed option set and no per-option points (free text is not
independently scored by this schema — an outcome mapping can still use the
instrument's total score from other questions).

Empty/blank `Options_JSON__c` on `Single_Select`/`Multi_Select`/`Dropdown`
means "no options authored yet" (not an error state) — same rule as the
prior schema's `GTM_Instrument_Question__c.Options_JSON__c`.

### 3.2 `Rules_JSON__c`

Unchanged from `GTM_Instrument_Question__c.Rules_JSON__c`
(`gtm-instrument-editor.md` §3.2) — restated here verbatim as the binding
shape for this schema. Array of branching-rule objects, each evaluated
independently in document order by `gtmRuleEngine` (carried forward onto
this schema by sub-issue 03):

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

## 4. Outcome Mapping Resolution (informative — sub-issue 02/03 owns the Apex)

Given a computed total score for a submission against an instrument, the
resolving outcome range is the `GTM_Instrument_Outcome_Range__c` row on that
instrument where `Min_Score__c <= score <= Max_Score__c`. This schema does
not guarantee ranges are non-overlapping or cover the full possible score
space (see §2.3) — sub-issue 02's resolution method must define and document
its own tie-break (e.g. lowest `Sort_Order__c` wins) and no-match fallback
behavior; this is explicitly deferred, not decided here.

## 5. Apex/LWC Surface (out of scope here — sub-issues 02/03/04)

No Apex classes or LWCs are introduced by this sub-issue. For reference,
future sub-issues are expected to need at minimum:

- A controller (sub-issue 02) analogous to `GtmInstrumentController` but
  targeting `GTM_Instrument_Definition__c` / `_Question_Definition__c` /
  `_Outcome_Range__c`, plus an outcome-resolution method per §4.
- `gtmRuleEngine` (sub-issue 03) carried forward unchanged against
  `Rules_JSON__c` on the new question object (shape is identical, §3.2).
- A rebuilt `gtmInstrumentAuthor` LWC (sub-issue 04) with inline Logic Jump
  editing, per-option points, an Outcome Mapping tab, and a flow-map
  preview, plus `gtmOverview.js` wiring for the offering-card "Assessment"
  action.

This document defines the schema those sub-issues build against; it does not
prescribe their DTO field names beyond requiring a 1:1 mapping onto §2's
field names (matching the discipline `gtm-instrument-editor.md` §4.1 applied
to the prior schema).

## 6. Permission Sets

Per CLAUDE.md §6, mapped across the 5 core permission sets.

| Object / CMDT | `GTM_Content_Manager` | `GTM_Content_Admin` | `GTM_Offering_Admin` / `GTM_Offering_User` | `GTM_Guest` |
|---|---|---|---|---|
| `GTM_Instrument_Definition__c` | CRUD, no viewAll/modifyAll | Full CRUD + viewAll/modifyAll | No access (unaffected — unchanged from the existing `GTM_Instrument__c` grant pattern) | No access |
| `GTM_Instrument_Question_Definition__c` | CRUD, no viewAll/modifyAll | Full CRUD + viewAll/modifyAll | No access | No access |
| `GTM_Instrument_Outcome_Range__c` | CRUD, no viewAll/modifyAll | Full CRUD + viewAll/modifyAll | No access | No access |
| `GTM_Instrument_Theme__mdt` | Read (customMetadataTypeAccesses) | Read (customMetadataTypeAccesses) | No access | Read (customMetadataTypeAccesses) |

FLS: `GTM_Content_Manager` and `GTM_Content_Admin` both grant explicit
`fieldPermissions` (readable + editable) on every non-required,
non-master-detail field:

- `GTM_Instrument_Definition__c.Theme_Key__c` (only non-required,
  non-master-detail field on that object — `Offering_Key__c`, `Status__c`,
  `Version__c` are required and get no explicit entry).
- `GTM_Instrument_Question_Definition__c.Question_Text__c`,
  `Options_JSON__c`, `Rules_JSON__c`, `Required__c`, `Question_Key__c`,
  `Min_Value__c`, `Max_Value__c`, `Points_Per_Unit__c` (`Slot_Order__c` and
  `Question_Type__c` are required and get no explicit entry;
  `GTM_Instrument_Definition__c` is master-detail and gets no explicit
  entry).
- `GTM_Instrument_Outcome_Range__c.Tier_Label__c`,
  `Readout_Template_Key__c`, `Sort_Order__c` (`Min_Score__c`/`Max_Score__c`
  are required and get no explicit entry; `GTM_Instrument_Definition__c` is
  master-detail and gets no explicit entry).

Custom Metadata Type field grants: consistent with every other `__mdt` type
in these permission sets (e.g. `GTM_Assessment_Config__mdt`), only the
object-level `customMetadataTypeAccesses` grant is set — no individual
`fieldPermissions` entries are added for `GTM_Instrument_Theme__mdt`'s
fields, matching existing repo convention.

Guests reach instrument definition/question/outcome content only through an
Apex controller (sub-issue 02/03), never direct object CRUD — mirroring the
`GTM_Instrument__c`/`_Question__c` pattern in `gtm-instrument-editor.md` §6.
`GTM_Guest` gets no grant on `GTM_Instrument_Definition__c`,
`GTM_Instrument_Question_Definition__c`, or `GTM_Instrument_Outcome_Range__c`
in this pass. `GTM_Guest` does get read access to `GTM_Instrument_Theme__mdt`
directly (object-level `customMetadataTypeAccesses` only, no field grants
per the convention above) since branding is presentation-only, non-sensitive
data, matching how other `__mdt` types are exposed directly to guests
elsewhere in this permission set.

`GTM_Offering_User` / `GTM_Offering_Admin` are unaffected by this sub-issue —
no grants added, consistent with those sets never having been granted access
to `GTM_Instrument__c`/`_Question__c` either.

## 7. Explicitly Out of Scope (this sub-issue)

- No Apex classes, trigger, or LWC changes (sub-issues 02/03/04).
- No `GTM_Offering__mdt` relationship field on any new object —
  `Offering_Key__c`/`Theme_Key__c` stay plain text (ADR-0009).
- No migration/seed/backfill of `GTM_Instrument_Definition__c` (or sibling
  object) rows for any existing offering — all four new metadata
  types/objects start empty.
- No deletion of `GTM_Instrument__c` / `GTM_Instrument_Question__c` or their
  Apex/LWC consumers (`GtmInstrumentController`, `gtmInstrumentAuthor`, the
  `GTM_Instrument_Author` tab). Those stay deployed and functionally live
  until a later sub-issue explicitly retires them once 02/03/04 land and the
  new model is proven — deleting them now, before any consumer exists for
  the new schema, would take down the current (if unused) authoring path
  with nothing yet replacing it. Tracking that retirement is out of this
  sub-issue's acceptance criteria.
- No changes to `GTM_Assessment_*__mdt` (the YAML-compiled legacy path) or
  `scripts/build-instrument.py` — sub-issue 03's job.
