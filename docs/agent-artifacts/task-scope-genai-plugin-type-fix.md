# TASK SCOPE — ISSUE #genai-plugin-type-fix

## 1. Requirements Breakdown

- **Target Objective:** `./scripts/deploy.sh gtm-dev --run-tests` currently fails Pass 1 on 3 pre-existing components, blocking every full deploy to `gtm-dev`. This issue fixes the two parts that are actually fixable from the repo:
  - **(A)** `force-app/main/default/genAiPlugins/GTMApplyConfigUpdate.genAiPlugin-meta.xml` and `GTMGetConfigState.genAiPlugin-meta.xml` both declare `<pluginType>Invocable</pluginType>`, which is not a legal value for the `GenAiPlugin.pluginType` field and fails deploy with `'Invocable' is not a valid value for the enum 'PluginType'`.
  - **(B)** `scripts/deploy.sh` has no opt-out for `bots/`/`genAiPlugins/`, so even after (A) is fixed, the `GTM_Configurator_Assistant` bot still fails every standard deploy with "Not available for deploy for this organization" (Agentforce/Bots is not provisioned on `gtm-dev` — an org-licensing gap, not a code defect, confirmed out of scope for code fixes). `scripts/deploy-fresh-org.sh` already solves the equivalent problem for itself via an opt-in `--with-agent` flag (default OFF, deploys `bots` + `genAiPlugins` only when passed). `deploy.sh` needs the mirrored flag so a standard deploy can exclude those two directories by default without a human remembering to type `EXCLUDE_DIRS=bots,genAiPlugins` by hand every time.
  - **Out of scope:** actually provisioning Agentforce/Einstein Copilot on `gtm-dev` (an org-admin/licensing action, not a repo change). Any change to `GtmAgentToolSurface.cls`, `GtmAgentProxyController.cls`, or the live custom-Apex GUS chat loop — per `AGENTS.md` §1, that dormant Agentforce scaffold is explicitly NOT the live agent path and must not be "wired up" as a side effect of this fix.

- **System Component Impacted:** Metadata (`GenAiPlugin` custom metadata type under `force-app/main/default/genAiPlugins/`) + deployment tooling (`scripts/deploy.sh`, a bash script, not force-app source).

### 1a. Research finding — confirmed correct `pluginType` value

Verified against the Salesforce Metadata API's own `GenAiPlugin` schema (local copy found at
`~/.vscode/extensions/salesforce.salesforcedx-einstein-gpt-4.33.0-darwin-arm64/dist/skills/platform-metadata-api-context-get/assets/metadata_api/GenAiPlugin.json`,
also mirrored under `~/Library/Application Support/Code/User/globalStorage/salesforce.salesforcedx-einstein-gpt/...`).
The WSDL segment in that file defines:

```xsd
<xsd:simpleType name="PluginType">
  <xsd:restriction base="xsd:string">
    <xsd:enumeration value="Topic"/>
    <xsd:enumeration value="APICustomTopic"/>
  </xsd:restriction>
</xsd:simpleType>
```

`pluginType` has exactly two legal values: `Topic` and `APICustomTopic`. There is no
`Invocable` value anywhere in the schema — confirming the issue's hypothesis that this
was a scaffolding mistake (conflating the plugin/topic's own type with
`invocableActionType`, a *different*, correctly-set field on `GenAiFunction`/action
definitions, whose own enum — `PlannerFunctionInvocableTargetType` — does legitimately
include `apex` as a value). Both of these two files represent an agent Topic (a category
of actions for a job-to-be-done), not a custom external API topic, so the correct value
for **both files** is:

```xml
<pluginType>Topic</pluginType>
```

### 1b. Additional discrepancy found during research (flag only, not authorized to fix here)

The Metadata API schema's `GenAiPlugin` complex type does **not** have top-level
`invocableActionType` / `invocableActionName` elements at all — those aren't part of the
real schema. The schema's mechanism for wiring a Topic (`GenAiPlugin`) to backing Apex
actions is a child `<genAiFunctions><functionName>...</functionName></genAiFunctions>`
list, where each `functionName` refers to a separately-deployed `GenAiFunction` metadata
component (directory `genAiFunctions/`, which does not exist anywhere in this repo today).
Neither `GTMApplyConfigUpdate.genAiPlugin-meta.xml` nor `GTMGetConfigState.genAiPlugin-meta.xml`
has a `genAiFunctions` block or any `GenAiFunction` component backing it — they use
`invocableActionType`/`invocableActionName`/a free-text `genAiPluginInstructions` block
instead, none of which match the current schema's structure. This may be a Metadata API
version drift artifact (this repo pins API 62.0 per `sfdx-project.json`; the schema
reference found locally may reflect a newer/different API version), or these two fields
may simply be silently ignored/tolerated by the deploy validator rather than rejected
outright, the way `pluginType=Invocable` was not.

**This is explicitly flagged, not resolved, here** — fixing `pluginType` to `Topic` is
confirmed correct and in scope; whether the `invocableActionType`/`invocableActionName`
fields also need restructuring into a `genAiFunctions`/`GenAiFunction` pair to fully
deploy cleanly could not be determined without an actual `sf project deploy start
--dry-run` against `gtm-dev` (BA agent has no org access and does not execute deploys).
**The Architect/Developer must run a `--dry-run` deploy of just `genAiPlugins/` after
applying the `pluginType` fix, before assuming Part A is fully done** — if the dry-run
still errors on `invocableActionType`/`invocableActionName`, that's a second, related but
distinct defect requiring its own decision (out of this issue's stated scope, but
adjacent enough that silently leaving it unfixed would reopen the same deploy-blocking
symptom under a different error message).

## 2. Code Dependency Checklist

- [x] **Modifying GUS Tool Surface? (If YES, verify zero-DML rule in AGENTS.md §1)** — **Flag for Architect, does not touch `GtmAgentToolSurface.cls` directly.** This issue edits `GTMApplyConfigUpdate.genAiPlugin-meta.xml` / `GTMGetConfigState.genAiPlugin-meta.xml`, which are the dormant Agentforce-side wiring for the *same* Apex actions (`GtmAgentApplyConfigUpdate.cls`, `GtmAgentGetConfigState.cls`) that also serve the live custom Claude tool-use loop today (per `AGENTS.md` §1: "These double as the dormant Agentforce invocable actions... so changing their signatures affects both paths"). This issue changes neither Apex class's signature nor any DML/callout behavior — it only fixes an XML enum value and adds a deploy-script opt-out flag — so the zero-DML tool contract in `GtmAgentToolSurface.cls`/`AGENTS.md` §1 is not touched. The Architect should still explicitly re-confirm this at design time: no change here should cause `GtmAgentApplyConfigUpdate.execute()` / `GtmAgentGetConfigState.execute()` to be modified, and nothing in this issue should "wire up" the dormant bot/plugin path per the `AGENTS.md` §1 warning against accidentally activating it.
- [ ] Altering Custom Metadata? — No. `GenAiPlugin` components are their own first-class metadata type deployed from `force-app/main/default/genAiPlugins/`, not `Custom Metadata Type` (`__mdt`) records under `force-app/main/default/customMetadata/`. CLAUDE.md §2's "Do Not Hand-Edit Metadata" rule is scoped to the generated `GTM_Assessment_*` CMDT XML built by `scripts/build-instrument.py` — it does not apply to `genAiPlugins/`, which is hand-authored, versioned scaffolding per `AGENTS.md` §1.
- [ ] Introducing database fields? — No new object/field/schema change in either part of this issue.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. Both `GTMApplyConfigUpdate.genAiPlugin-meta.xml` and `GTMGetConfigState.genAiPlugin-meta.xml` have `<pluginType>Topic</pluginType>` (not `Invocable`), and a `sf project deploy start --source-dir force-app/main/default/genAiPlugins --target-org gtm-dev --dry-run` no longer reports the `PluginType` enum error (see §1b caveat — if a new/different error surfaces there, that is a follow-up, not a silent pass/fail of this issue).
  2. `scripts/deploy.sh` gains an opt-in flag (mirroring `deploy-fresh-org.sh`'s `--with-agent`, default OFF) that excludes `bots/` and `genAiPlugins/` from Pass 1's `SOURCE_DIRS` unless the flag is explicitly passed, so a plain `./scripts/deploy.sh gtm-dev --run-tests` no longer fails on the Bot's "Not available for deploy for this organization" error. The script's existing `EXCLUDE_DIRS` escape hatch and its usage/comment block should stay consistent with the new flag rather than duplicating unrelated logic — Architect's call on the cleanest way to reconcile the two (e.g. flag internally sets `EXCLUDE_DIRS`, or a parallel opt-in list), but the end-user-visible behavior must be: default run excludes `bots`/`genAiPlugins`, an explicit opt-in (name it consistently with `--with-agent` for parity with `deploy-fresh-org.sh`) includes them.
  3. `docs/runbooks/fresh-org-deploy.md` and any deploy-related doc referencing this behavior should stay accurate — Architect should confirm whether the runbook needs an update noting `deploy.sh` now also supports the agent opt-out/opt-in, or whether that's out of scope for this issue (a doc-only follow-up is acceptable either way, but should not be silently forgotten).
  4. `./scripts/deploy.sh gtm-dev --run-tests` (Part B's flag left at its default/OFF) reaches Pass 2 without failing on any of the 3 originally-reported components.

- **Target Test Target:** No Apex/LWC Jest unit exists for either change (this is a metadata-value fix and a bash deploy script). Verification is deploy-time, not unit-test-time:
  - `sf project deploy start --source-dir force-app/main/default/genAiPlugins --target-org gtm-dev --dry-run` — must pass cleanly (or surface only the §1b follow-up, not the original `PluginType` error).
  - Manual/scripted run of `./scripts/deploy.sh gtm-dev` (no `--with-agent`-equivalent flag) against a real or sandbox-equivalent `gtm-dev`-like org — Pass 1 must not attempt `bots/` or `genAiPlugins/` and must succeed; a second run with the new flag passed must attempt those two directories (expected to still fail there with the Agentforce-not-provisioned error, which is correctly out of scope, not a regression).
  - If any existing Apex tests reference `GtmAgentApplyConfigUpdate`/`GtmAgentGetConfigState` (`GtmAgentApplyConfigUpdateTest.cls`, `GtmAgentGetConfigStateTest.cls`), re-run those via `sf apex run test` as a regression check even though this issue shouldn't touch their Apex — confirms part A truly left the live Apex path untouched.
