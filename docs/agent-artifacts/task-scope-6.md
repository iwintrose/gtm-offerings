# TASK SCOPE — ISSUE #6

## 1. Requirements Breakdown

- **Target Objective:** Issue #6 asks to "Implement Content Manager IA plan," pointing at
  `docs/agent-artifacts/content-manager-ia-plan.md` (status: "For Dev implementation, then QA
  verification against this plan and the live org... nothing in this plan has been deployed").
  **That premise is stale.** Direct code inspection (evidence below) shows every build item in
  the plan's §1-§4 is already present in `main` at commit `2077c90` ("Initial import: current
  state of GTM Offerings main") — the same commit that introduced the plan document itself. The
  plan and its implementation were imported together as one snapshot; the issue was filed against
  the plan's stated status text, not against the actual repository. **This is a genuine
  ambiguity a human/Architect should resolve, not one I am guessing past:** it is unclear whether
  (a) the import already includes Dev's completed work and issue #6 is now purely a QA-verification
  task, or (b) the import's "IA plan" file is documentation-only and a parallel, not-yet-merged
  Dev branch was supposed to carry the real implementation and got lost/omitted from the import.
  I found no such branch (`git branch -a` on origin lists none referencing this plan or IA/content-manager
  work). Given the code matches the plan section-by-section including its exact recommended
  copy strings and backlog wording, (a) is far more likely, but this determination should be
  confirmed explicitly before closing #6, not silently assumed.
  **Revised objective for this task, given the evidence:** treat #6 as a QA-verification pass
  against the plan's own §6 checklist (23 items), plus closing two concrete gaps found during
  verification (see §3 below), rather than a from-scratch Dev build.
- **System Component Impacted:** LWC (`gtmContentManager`, `gtmContentHome`, `gtmPagePreview`,
  `gtmFieldEditor`, `gtmPageLayouts`), no Apex changes, no Custom Metadata/YAML changes, no new
  Salesforce objects/fields.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO** — `c-gtm-agent-bubble`/GUS itself is untouched; only a
      caption string in `gtmPagePreview.js`'s `previewNote` getter references it (confirmed
      present, see evidence). Zero-DML rule in AGENTS.md §1 not implicated (no new DML anywhere
      in this plan).
- [ ] Altering Custom Metadata? **NO** — nothing in this plan touches `Template_Type__c`,
      `migration-accelerator/` YAML, or any `GTM_Assessment_*` custom metadata. Confirmed by the
      plan's own §1.2 explicitly rejecting a new `Template_Type__c` (data stays put; only the
      editor's *presentation* changes), and by code inspection showing no such metadata edits.
- [ ] Introducing database fields? **NO** — no new fields, objects, or tabs. Confirmed via
      `git diff main -- force-app/main/default/permissionsets/` returning empty output (see
      evidence in §3), matching the plan's own §6 item 23 claim that no permission-set changes
      are required.

## 3. Plan Acceptance Criteria

**Evidence backing "already implemented" claim** (all commands run against current `main` /
`ba-scope/issue-6`, HEAD `e5a6215`):

- `gtmContentManager.js` already has `contentSections` (filters out `offering-defaults`,
  matches plan §1.3 verbatim: `get contentSections() { return this.sections.filter((s) =>
  s.layoutType !== 'offering-defaults'); }`), `settingsSection`, `@track settingsOpen`, and
  `capturePageRef` already reads `c__panel` (`const panel = ref.state.c__panel || '';`).
- `gtmContentHome.js`: `openEditor(offeringKey, templateType, isNew, panel)` already takes the
  extra `panel` arg; `handleOpenSettings` already calls `this.openEditor(key, template, false,
  'settings')`; `templateOptions` already filters to `builtTypes` exactly per the plan's §3.1
  code sample (byte-for-byte equivalent logic).
- `gtmPagePreview.js`: `previewNote` already contains the exact GUS clarification sentence from
  plan §2.2 ("The "Ask Gus" bubble is configured at the Framework level, not here...") plus an
  additional `settingsMode` branch not explicit in the plan's original snippet but consistent
  with its intent.
- `gtmPageLayouts.js`: `'industry-chooser': []` (line 217, matches plan §3.5) and
  `LOCKED_JSON_ITEMS = new Set(['faq::items'])` (line 315, matches plan §3.4) are both present.
- `gtmFieldEditor.html`/`.js`: the "+ Add item" button is already wrapped in
  `<template if:false={f.itemsLocked}>`, and `itemsLocked` is computed exactly per plan §3.4.
- `docs/backlog.md` already contains the two required backlog entries: the "Add industry" gap
  (§3.5's required follow-up) and **D13 — Per-offering "look and feel" (theming) — deferred, not
  decided against**, matching plan §5.3's required wording and trigger condition verbatim.
- Onboarding (§4) is implemented, but via a **different mechanism than the plan specified**: the
  plan's §4.3.A calls for a `c__panel=new` query param and a `showWelcome` track var with a
  dismissible banner. The actual code instead uses a separate `c__new='1'` param, an
  `isNewOffering` track var, a `stripNewFromUrl()` history-scrub method, and
  `handleDismissNewOfferingHint()`. Functionally equivalent (one-time nudge, refresh-safe,
  dismissible), so this is **not a defect**, but it means Dev/QA should verify against actual
  behavior, not the plan's literal variable names.
- `python3 scripts/check-references.py` run: **0 deploy-blocking** (60 pre-existing "needing a
  manual step" items unrelated to this plan — standard object test-class references, per
  runbook), matching plan §6 item 22's target.
- `git diff main -- force-app/main/default/permissionsets/` returned no output — confirms plan
  §6 item 23 (no permission-set changes required) is currently true.
- `git log --oneline -- force-app/main/default/lwc/gtmContentManager ... gtmPageLayouts` shows
  only one commit touching all these files: `2077c90 Initial import`. No separate Dev commit or
  branch implementing this plan exists in `git branch -a` on origin.

**Two real gaps found during this verification pass** (neither is "nothing built" — both are
narrow, single-file loose ends against the plan's own stated intent):

1. Plan §3.4 flags an accepted, *documented* gap: no server-side backstop on `saveDrafts`
   against a client bypassing the FAQ "Add item" UI gate. Confirmed present in code (comment at
   `gtmFieldEditor.js` line ~134 references this) but **not yet logged as its own line item in
   `docs/backlog.md`** the way D13 and the industry-add gap are — I could not find a distinct
   backlog entry for it via `grep -n -i "faq.*add\|json array" docs/backlog.md`. This is a
   one-line docs gap, not code — flag for the Developer step to add, not to build around.
2. The onboarding banner's actual param name (`c__new`) vs. the plan's spec'd name (`c__panel=new`)
   is undocumented drift between spec and implementation. Low risk, but the plan is meant to be
   QA's ground truth (per the plan's own header) — QA running §6 item 16-18 literally against
   `c__panel=new` would fail to find it. Developer step should note this correction inline in the
   plan doc or in `docs/backlog.md` so QA doesn't file a false regression.

**Is this too large for one worktree?** No — given the finding that all code is already built,
the remaining work is: (a) confirm/resolve the ambiguity in §1 with the issue owner/Architect,
(b) add the missing FAQ-backstop backlog line, (c) correct the onboarding param-name
documentation mismatch, and (d) run the plan's own 23-item §6 QA checklist end-to-end
(11 items marked [UI-only] need a live-browser QA pass against `gtm-staging`, not just code
review). This is a single-worktree, single-issue scope — it does **not** need splitting into
sub-issues. If the ambiguity in §1 resolves to "(b)" (a real Dev branch was lost), scope would
need to be re-opened at that point, but nothing found here suggests that.

**Native Salesforce component check:** Nothing in this plan introduces new UI needing a
custom-vs-native decision — it exclusively edits existing custom LWCs (`gtmContentManager`,
`gtmContentHome`, `gtmPagePreview`, `gtmFieldEditor`) that already reasonably exist as custom
components (they implement app-specific instrument authoring, not a generic list/detail/report
use case a standard Salesforce component would cover). No native-component alternative applies.

- **Success Metric:** All 23 items in `docs/agent-artifacts/content-manager-ia-plan.md` §6
  QA verification checklist pass against the live `gtm-staging` org (validate-only; no deploy
  needed since code already exists on `main`), the two documentation gaps above are closed in
  `docs/backlog.md`/the plan doc, and the Architect/issue-owner has explicitly confirmed the §1
  ambiguity (plan-vs-build already merged, not lost) before #6 is closed.
- **Target Test Target:** No new Apex or Jest specs are introduced by this plan (confirmed:
  plan §6 item 21 states "this plan adds no new Apex classes and changes no existing Apex method
  signatures"). Existing regression targets: `sf apex run test --target-org gtm-staging`
  (Apex, plan §6 item 21) and `npm test` (Jest, full suite — no LWC test file names are called
  out in the plan, so run the full `@salesforce/sfdx-lwc-jest` suite for
  `gtmContentManager`, `gtmContentHome`, `gtmPagePreview`, and `gtmFieldEditor` specifically).
