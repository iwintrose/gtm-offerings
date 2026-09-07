# QA round 1 — Content Manager IA plan implementation (commit `1f152d7`)

**Reviewer:** QA agent (session `session_018UJzwgTCCMdESELzYMeWAZ`)
**Date:** 2026-09-07
**Scope:** `gtmContentManager.{js,html,css}`, `gtmContentHome.{js,html,css}`,
`gtmFieldEditor.{js,html}`, `gtmPageLayouts.js`, `gtmPagePreview.js`,
`docs/backlog.md` (D12/D13) — implementing
`docs/agent-artifacts/content-manager-ia-plan.md`.

**Verdict: APPROVED.**

---

## Independent re-verification performed this pass

Every claim below was checked directly against source and/or the live
`gtm-dev` org — none accepted on Dev's or the Architect's word alone.

**1. Settings surface separation.**
`gtmContentManager.js`'s `contentSections` getter filters
`layoutType !== 'offering-defaults'` and is used everywhere the rail reads
`this.sections` (`railSections`, `sectionCount`, `hasSections`, `noSections`).
`settingsSection`/`handleOpenSettingsPanel` land on the one fixed section via
a new "Customizer settings" toolbar button (`gtmContentManager.html`), which
renders a slim back-only panel in settings mode — no add/reorder/delete
chrome, as the plan specified. `git diff` confirms `Template_Type__c` is
untouched anywhere in this commit.

Ran the actual functional round-trip myself (not reused from an earlier
session's data): via `GtmPageContentController.saveDrafts` +
`publishPage` + `GtmPageContentReader.getPageContent` (the exact controller
+ reader pair `gtmConfigWizard`'s `getPageLayout` depends on) —
1. Wrote a distinct test value to `migration-accelerator::configurator::
   defaults::sizePresets` and published it.
2. Read it back through `GtmPageContentReader.getPageContent` — matched the
   test value exactly:
   `[{"key":"QA2","label":"QA Round 2","sub":"content-manager-ia QA distinct
   value",...}]`.
3. Restored the original three presets (S/M/L) and re-queried
   `JSON_Value__c` directly — confirmed byte-for-byte restored.

Confirms the read/write path this feature depends on is unaffected by the
UI reorganization, and confirms storage genuinely didn't move.

**2. The `c__panel` nav-state parameter.**
Read `gtmContentHome.js`'s `openEditor(offeringKey, templateType, isNew,
panel)`. Traced every call site:
- `handleCreateOffering` → `openEditor(key, 'offerings-listing', /*isNew*/
  true)` — 3rd arg only, no `panel`.
- `handleOpenSettings` → `openEditor(key, template, false, 'settings')` —
  4th arg only, 3rd explicitly `false` so `c__new` is never set.
- `handleOpenPage`/`handleOpenRecent`/`handleGoToPage` → neither arg.

Confirmed against `git show 7f73c75` (the sibling offering-creation-fix
commit): it introduced `isNew` as the 3rd argument first; this commit added
`panel` as the 4th on top of it. No collision — the two one-shot request
kinds (`c__new`, `c__panel`) coexist correctly in `capturePageRef`.

**3. GUS preview caption.**
`gtmPagePreview.js`'s `previewNote` getter has both branches: the ordinary
configurator case and, ahead of it, the `settingsMode` case (checked in that
order, so settings mode's caption wins when both are true). Wording is
accurate: attributes GUS to "the Framework level, not here," pointing to the
Framework card's Settings — does not imply GUS is uneditable, matching
§2.2's requirement.

**4. Creation guardrails.**
- `templateOptions` in `gtmContentHome.js` filters to templates whose
  matching page has `sectionCount === 0` — traced end to end; the combobox
  is `disabled` when the result is empty and `npHint` states why.
- `GtmPageSectionController.createPage` (lines 585-593, unmodified — no
  Apex touched in this diff) genuinely throws
  `'That page already has sections. Open it and add to it instead.'` when a
  page already has section rows. Read directly, not taken on the plan's
  word.
- `LOCKED_JSON_ITEMS = new Set(['faq::items'])` — single entry. In
  `gtmFieldEditor.html`, only the "+ Add item" button (line 174-179) is
  wrapped in `if:false={f.itemsLocked}`; item move (131-136) and delete
  (137-138) are untouched, confirmed by reading the surrounding markup.
- `TEMPLATE_LAYOUTS['industry-chooser']` is `[]` (was `['industry-tile']`).
  `noLayoutsReason` in `gtmContentManager.js` has an `industry-chooser`
  branch explaining why. This diff touches nothing in the rail's
  move/toggle/delete handlers, which read from `this.sections` independent
  of `TEMPLATE_LAYOUTS` — existing `industry-tile` sections stay fully
  editable.

**5. Onboarding.**
`nextStepHintFor()` in `gtmContentHome.js` traced for all three states:
0 built → names every template; 1 of N built → names the remaining N-1;
all built → `unbuilt.length === 0` → returns `''`, and the HTML only renders
`.off-nextstep` `if:true={o.nextStepHint}` — confirmed it disappears cleanly
when everything is built. `stripNewFromUrl()` deletes only the `c__new`
query param via `history.replaceState` (no navigation, so the wire doesn't
re-fire) — wrapped in try/catch, correctly scoped to a no-op on failure.

**6. Backlog entries.**
D12 and D13 each appear exactly once (`grep -c` = 1 for both), immediately
after D11 with no numbering collision. D12 accurately describes the
`industry-chooser` closure and states it's not urgent with one offering
live. D13 matches the Architect's plan §5.3 recommendation exactly: defer,
not decide against, with the stated trigger ("the moment a second offering
is being onboarded with a genuinely different visual identity").

**7. Test suites and diff scope.**
- Jest: **317 passed**, 0 failed (own run, not reused) — matches claim.
- Apex (`RunLocalTests`, full org suite): **541/541, 100%** — matches claim.
- `scripts/check-references.py`: **5 deploy-blocking**, all
  `00DgK00000XZieHUAT` org-id mentions in `AGENTS.md`/`CLAUDE.md`/three
  `docs/agent-artifacts/*.md` files — none in this commit's file list.
- `git diff --name-only 1f152d7~1 1f152d7`: exactly the 11 files the commit
  message claims (5 LWC bundles' js/html/css + `docs/backlog.md`). No Apex,
  no permission sets, no `gtmStory.css`/`gtmConfigurator.css` changes.

## Test-data cleanup

The one live-org mutation made this pass (the `sizePresets` round-trip
write) was restored to its exact original value before this report was
written; re-queried `JSON_Value__c` directly to confirm. No records were
created or left behind.

---

## Verdict

**APPROVED.** All seven checklist items independently re-verified against
source and the live `gtm-dev` org, including a live write/read/restore
round-trip through the real Apex path — not accepted on Dev's report alone.
No discrepancies found.
