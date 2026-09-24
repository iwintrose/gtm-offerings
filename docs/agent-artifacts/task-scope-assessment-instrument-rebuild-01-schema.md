# TASK SCOPE — ISSUE #assessment-instrument-rebuild-01-schema

> **Supersession notice:** This is sub-issue 01 of a new 4-part umbrella
> effort (`assessment-instrument-rebuild-01..04`) that **supersedes**
> `docs/architecture/gtm-instrument-editor.md` and its old sub-issue
> numbering (01 schema / 02 Apex / 03 rule engine / 04 LWC). That prior
> effort's sub-issues 01/02/03 are already merged (`GTM_Instrument__c` /
> `GTM_Instrument_Question__c` schema, `GtmInstrumentController`,
> `gtmRuleEngine`), but per explicit user decision this new effort rebuilds
> the model rather than extending it — the "grandfather YAML" opt-out and
> the standalone Instrument Author tab are being removed, not preserved.
> The Architect/Developer for this and the following three sub-issues must
> **not** treat `gtm-instrument-editor.md` as still binding; a new contract
> doc replacing it is part of this sub-issue's deliverable (see §3).
>
> Umbrella slug: `assessment-instrument-rebuild`. Sub-issues, run
> sequentially, each its own worktree/branch/PR:
> - **01-schema** (this doc) — new instrument-definition objects, Outcome
>   Mapping, theme metadata, permission sets.
> - **02-submission** — generalize `GTM_Assessment_Request__c` into the
>   Salesforce-native submission model with `Offering__c` lookup.
> - **03-rule-engine-migration** — carry `gtmRuleEngine` forward onto the
>   new schema, write and run the YAML→new-schema migration script for
>   Migration Accelerator, retire `scripts/build-instrument.py` path.
> - **04-editor-lwc-wiring** — rebuilt `gtmInstrumentAuthor` editor (inline
>   Logic Jump, per-option points, Outcome Mapping tab, flow-map preview)
>   and the offering-card "Assessment" action wiring in `gtmOverview.js`.
>
> Each sub-issue's scope doc is independently gate-checkable; 02/03/04
> depend on 01 landing first (schema must exist before Apex/LWC can target
> it). Do not start 02 until 01's objects are deployed to `gtm-staging`.

## 1. Requirements Breakdown

- **Target Objective:** Design and deploy the new Salesforce-native
  instrument-definition schema (superseding `GTM_Instrument__c` /
  `GTM_Instrument_Question__c`) that supports: multiple input types
  (single/multi-select, dropdown, numeric/maturity scale, matrix/grid,
  short/long text) with per-option points; inline branching-rule storage
  (JSON shape carried forward from the existing schema, unchanged); a new
  Outcome Mapping construct (score range → result tier/readout template,
  author-configurable, replacing the fixed `Assessment_Tier__c` picklist);
  and a new lightweight per-instrument theme/style custom metadata type.
  This is a **schema-only** sub-issue: no Apex business logic, no LWC. It
  also must produce the new architecture contract doc (`docs/architecture/
  gtm-instrument-schema.md` or similar) that 02/03/04 treat as binding,
  per CLAUDE.md §4 Contract First.
- **System Component Impacted:** Apex/Schema (custom objects, custom
  metadata types) + `docs/architecture/` (new contract doc). No LWC, no
  YAML instrument content in this sub-issue.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No — this sub-issue does not touch any
      GUS-facing Apex-invocable action or tool surface.
- [ ] Altering Custom Metadata? Yes — introduces a new theme/style custom
      metadata type (author-configured branding per instrument). This is
      new metadata, not the existing `GTM_Assessment_*__mdt` YAML-compiled
      metadata, so there is no `migration-accelerator/` YAML to update for
      *this* type. Do not hand-edit `GTM_Assessment_*__mdt` XML — that
      remains governed by `scripts/build-instrument.py` until sub-issue 03
      retires it.
- [ ] Introducing database fields? Yes — new custom objects/fields for
      instrument definitions, questions, and outcome mapping. Mapping to
      the 5 core permission sets (`GTM_Content_Manager`/`Admin` authoring
      CRUD+FLS, `GTM_Guest` read access, `GTM_Offering_User`/`Admin`
      unaffected) is mandatory and in scope for this sub-issue — see
      CLAUDE.md §6. Required/master-detail fields get no explicit
      `fieldPermissions` entries.

## 3. Plan Acceptance Criteria

- **Success Metric:** New instrument-definition objects (instrument,
  question, outcome-mapping range) plus the theme custom metadata type
  deploy cleanly (`--dry-run` then real deploy) to `gtm-staging`; the 5
  core permission sets are updated per CLAUDE.md §6 with no required/MD
  field carrying an explicit `fieldPermissions` entry; a new
  `docs/architecture/` contract doc exists documenting field names/types/
  JSON shapes for §2.1–2.3 style tables (matching the level of detail in
  the superseded `gtm-instrument-editor.md`), explicitly marked as
  superseding that file, and is committed before any 02/03/04 work starts.
  QA passes if: metadata deploys with zero errors on `gtm-staging`, and a
  System Administrator + a user holding only `GTM_Content_Manager` can be
  manually confirmed (via Setup > Field-Level Security or a quick record
  create) to have the expected CRUD/FLS on every new object.
- **Target Test Target:** No Apex/LWC test target for this sub-issue
  (schema-only); verification is a `sf project deploy validate --dry-run
  --target-org gtm-staging` run plus manual FLS confirmation as described
  above. Sub-issue 02 is the first to require Apex test coverage.
