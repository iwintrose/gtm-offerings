# TASK SCOPE — ISSUE #industry-variants-agentforce-draft

## 0. Series Context & Dependency

Issue 4 of 4 in the "Industry-Specific Section Variants" series (product
owner isiah@eawpublications.com approved). **Hard dependency:**
`docs/agent-artifacts/task-scope-industry-variants-core.md` — the
"+ Industry variant" modal this issue adds a "Draft with AI" option to is
built there, and the drafting action needs the core issue's field-editor
`industryKey` plumbing to hand a proposed draft to the field editor as an
editable draft. Not dependent on issues 2 or 3.

## 1. Requirements Breakdown

- **Target Objective:** Give a content editor an AI-assisted first draft
  when creating an industry variant — Track A only. This is explicitly
  scoped to reuse the *existing* proxy-based GUS pattern
  (`GtmAgentProxyController.cls`), not a live Agentforce/Data Cloud
  integration. Track B (live Data Cloud personalization at page-load, i.e.
  an LLM writing copy per-visitor in real time) is **out of scope for
  building** in this or any of the other three issues in this series — it
  is design-and-stub-only and gated on Data Cloud go-live.
- **System Component Impacted:** Apex (two new invocable actions,
  `GTM_Agent_Settings__c`/`GtmAgentProxyController` extension), Bot
  metadata (`GenAiPlugin`/`Topic`), LWC (`gtmContentManager` modal
  addition).
- **Ambiguity flagged for the Architect/owner, not resolved here:** the
  plan says this issue must "lift the F4 exclusion for this one scoped use
  case only" — confirmed real via
  `grep -n "F4\|Content Manager" docs/architecture/gus-utility-bar-host.md`,
  which shows (line 12): `- **GTM Content Manager app is EXCLUDED (owner
  decision F4, pending).**`. The word "pending" in that doc means F4 itself
  has not been finalized as a closed decision independent of this plan.
  Before the Developer implements the provider-seam change, the Architect
  step should re-confirm with the owner that this plan's approval is also
  read as resolving F4's "pending" status for this one scoped action —
  the BA is not treating that as self-evidently settled just because the
  overall plan was approved.

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? YES, but narrowly. Confirmed
      `force-app/main/default/classes/GtmAgentToolSurface.cls` exists
      alongside the invocable-action pattern this issue extends
      (`GtmAgentGetConfigState.cls`, `GtmAgentApplyConfigUpdate.cls`,
      `GtmAgentConfigActions.cls`, `GtmAgentProxyController.cls`, and bot
      `force-app/main/default/bots/GTM_Configurator_Assistant/` all
      confirmed present via `ls force-app/main/default/classes/ | grep -i
      GtmAgent` and `ls force-app/main/default/bots/`). CLAUDE.md §1's
      "zero-DML rule" for the GUS tool surface must be verified by the
      Architect/Developer against the current text of AGENTS.md §1 before
      writing `GtmAgentGetSectionContent`/`GtmAgentDraftSectionVariant` —
      this scope doc does not restate that rule's exact wording since it
      may have changed; the Developer must re-read AGENTS.md §1 directly.
      Both new actions must be read-only/proposal-only: they return
      proposed field values, never write `GTM_Page_Content__c`/
      `GTM_Page_Section__c` rows themselves (that stays on the existing
      Draft->Publish path built in the core issue).
- [ ] Altering Custom Metadata? NO.
- [ ] Introducing database fields? NO — this issue extends
      `GTM_Agent_Settings__c`'s existing provider seam (confirmed as an
      existing object based on `GtmAgentSettingsController.cls` being
      present), not adding new fields. If implementation reveals a new
      field is actually needed on `GTM_Agent_Settings__c`, that triggers
      the same FLS-mapping requirement as any other new field and the
      Developer must not skip it just because this box was checked NO at
      scope time.

## 3. Detailed Scope

### Reality check (from the approved plan, confirmed against code)
- GUS today is a custom Claude/OpenAI/Gemini proxy
  (`GtmAgentProxyController.cls`), not a live Agentforce agent.
- A real `EinsteinCopilot` bot
  (`force-app/main/default/bots/GTM_Configurator_Assistant/`) and
  `GenAiPlugin`/`GenAiFunction` pairs (`GTMApplyConfigUpdate`,
  `GTMGetConfigState`) exist as unwired scaffolding — this issue follows
  that same scaffolding pattern rather than inventing a new one.
- Content Manager is explicitly excluded from GUS today per
  `docs/architecture/gus-utility-bar-host.md` decision F4 (pending) — see
  the flagged ambiguity above.
- Data Cloud has zero technical integration in this repo today (only
  assessment-questionnaire content mentions it) — reconfirm this with a
  grep before building anything Data-Cloud-adjacent; do not assume any
  Data Cloud plumbing already exists.

### Track A (build now)
- Two new invocable actions modeled on `GtmAgentGetConfigState`/
  `GtmAgentApplyConfigUpdate` as templates:
  - `GtmAgentGetSectionContent` — reads the base section's current fields
    plus the target industry's research brief (the brief table from
    `task-scope-industry-variants-content-load.md`, or wherever it ends up
    stored/referenced for this purpose — Developer to confirm with
    Architect whether briefs are hardcoded, config, or reused from
    already-loaded variant copy).
  - `GtmAgentDraftSectionVariant` — returns proposed field values for
    editor review. Must never auto-publish and must never directly write
    `GTM_Page_Content__c`.
- New `GenAiPlugin`/Topic `GTM_Content_Drafting_Assistant`, mirroring
  `GTM_Configurator_Assistant`'s bot-meta pattern, scoped only to Content
  Manager's surface (not general GUS/GTM_Offerings-app access).
- Extend `GTM_Agent_Settings__c`/`GtmAgentProxyController`'s provider seam
  so Content Manager can call it — scoped to this one use case, not a
  general lifting of the F4 exclusion (see ambiguity flag above).
- LWC: the core issue's "+ Industry variant" modal gets a "Draft with AI"
  option that calls the drafting action and returns the proposed copy as
  an editable draft into the field editor — never silently published,
  rides the existing Draft->Publish lifecycle built in the core issue.

### Track B (explicitly NOT built in this issue)
- No live Data Cloud calls, `NamedCredential`s, or ingestion mappings.
- If a future seam placeholder is wanted (e.g. a
  `resolveForVisitor`/`GtmDataCloudSignalProvider` stub returning `null`),
  that is a backlog note only — do not scope it as buildable work here, and
  the Developer must not build it even as a "harmless" stub unless a
  separate task-scope doc is written and approved for it later.

## 4. Non-Goals (this issue)

- No general GUS access expansion to Content Manager beyond this one
  scoped drafting action.
- No live per-visitor content generation anywhere in this feature.
- No hide/reorder/nav (issue 2) and no bulk industry copy loading beyond
  whatever an editor drafts interactively (issue 3 covers the bulk load).

## 5. Plan Acceptance Criteria

- **Success Metric:** From the "+ Industry variant" modal, an editor can
  click "Draft with AI," receive proposed copy for the selected section and
  industry, edit it in `gtmFieldEditor`, and publish through the existing
  lifecycle — with no code path that auto-publishes an AI draft without
  editor action.
- **Target Test Target:** New Apex tests for `GtmAgentGetSectionContent`
  and `GtmAgentDraftSectionVariant` (modeled on
  `GtmAgentGetConfigStateTest.cls`/`GtmAgentApplyConfigUpdateTest.cls`),
  asserting no DML occurs inside the drafting action itself; Jest spec
  coverage in `gtmContentManager`'s test suite for the "Draft with AI"
  button state and draft-not-published behavior; manual QA per the
  approved plan's Verification step 8 — confirm "Draft with AI" never
  auto-publishes.
