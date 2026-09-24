# TASK SCOPE — ISSUE #assessment-instrument-rebuild-04-editor-lwc-wiring

> Sub-issue 04 of 4 in the `assessment-instrument-rebuild` umbrella (see
> `task-scope-assessment-instrument-rebuild-01-schema.md` for the full
> sequencing note and supersession of `docs/architecture/
> gtm-instrument-editor.md`). Depends on 01 (schema), 02 (submission
> model), and 03 (rule engine + migration parity confirmed) all landing on
> `gtm-staging` first — this is the user-facing capstone and should not
> ship ahead of a validated data model underneath it.

## 1. Requirements Breakdown

- **Target Objective:** Two tied pieces of work: (a) rebuild
  `gtmInstrumentAuthor` (or its successor LWC) as the editor for the new
  01-schema instrument definitions, implementing: inline "Logic Jump"
  branching-rule editing (rule lives on the answer option being edited,
  not a separate rule list — Typeform pattern), per-option point fields,
  a new Outcome Mapping tab (score range → result tier/readout template),
  and a read-only flow-map preview view for QA (Outgrow-style); (b) add an
  "Assessment" action to the offering card in
  `force-app/main/default/lwc/gtmOverview/gtmOverview.js`, following the
  exact `openEditor`/`NavigationMixin` pattern already used for Pages
  (`standard__app` navigation into `GTM_Content_Manager` with `state: {
  c__offering: offeringKey }`, see `gtmOverview.js` line ~1005
  `openEditor(offeringKey, templateType)`), so this becomes the primary
  entry point into instrument authoring. Per the approved plan, this
  **replaces** the standalone "Instrument Author" tab as primary entry
  point — the old tab may be retired or left as a secondary/admin path at
  Architect discretion, but the offering-card action is the one reps and
  content managers are expected to use.
- **System Component Impacted:** LWC
  (`gtmInstrumentAuthor`/successor, `gtmOverview`) + Apex
  (`GtmInstrumentController.cls`, extended for Outcome Mapping CRUD if not
  already covered by 01/02) + `docs/architecture/gtm-instrument-editor.md`
  superseding contract doc (finalize/cross-link from 01's new doc if not
  already complete).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No expected GUS tool-surface change from
      this sub-issue's editor/navigation work — confirm no GUS action
      currently targets the old Instrument Author tab route before
      retiring it.
- [ ] Altering Custom Metadata? No — this sub-issue is LWC/Apex UI wiring
      against schema already delivered in 01/03; no new YAML or CMDT
      changes.
- [ ] Introducing database fields? Only if the editor surfaces a gap not
      already covered by 01 (e.g. a UI-state field). If so, flag it back
      to 01's contract doc rather than adding ad hoc fields, and the
      Permission Set mapping requirement from CLAUDE.md §6 still applies.

## 3. Plan Acceptance Criteria

- **Success Metric:** From the offering card on `gtm-staging`, clicking
  the new "Assessment" action opens the rebuilt editor scoped to that
  offering (same `c__offering` state-passing pattern as Pages); a Content
  Manager can add a question, set inline Logic Jump branching on an
  answer option, assign per-option points, define at least one Outcome
  Mapping range, publish, and see the flow-map preview reflect the
  authored branching; a guest can complete the resulting assessment
  end-to-end and the resulting `GTM_Assessment_Request__c` (per 02) shows
  correct CRM linkage and scoring tied to the authored Outcome Mapping.
  Manual browser QA per the user's standing QA rule (validate live in the
  browser, check every dependent surface — offering card, editor, guest
  submission flow, CRM record — not just the changed one) is required
  before this sub-issue is considered done.
- **Target Test Target:** Jest specs for `gtmInstrumentAuthor` (or its
  successor component's `__tests__/`) and `gtmOverview.test.js` (new
  "Assessment" action / navigation assertions); confirm exact spec file
  paths under `force-app/main/default/lwc/*/`__tests__/` at implementation
  time since the editor component may be renamed as part of the rebuild.
