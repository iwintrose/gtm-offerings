# TASK SCOPE — ISSUE #gus-settings-section-rename

## 1. Requirements Breakdown

- **Target Objective:** Rename the stale "Claude / GUS" nav-section label inside the `GTM_Offerings_Settings` tab (the `gtmOfferingsSettings` LWC's vertical nav rail) to a name that no longer reads as Claude-specific, since GUS now also supports OpenAI and Agentforce as providers (per `docs/architecture/gus-chat-provider-settings.md` §1 and PR #34, merged today). Recommended label: **"GUS Configuration"** — matches the user's own wording, matches this file's existing noun-phrase, title-case, no-slash convention (`Approval Routing`, `Analytics Notifications`, `Scheduled Jobs`, `Recycle Bin`), and drops the Claude branding without inventing new terminology. "GUS Settings" is an acceptable fallback if the Developer/Architect prefers it; either satisfies the user's ask ("GUS configurations or something to that effect").

  This is confirmed via direct code read — `force-app/main/default/lwc/gtmOfferingsSettings/gtmOfferingsSettings.js` line 36:
  ```
  { id: 'claude-gus', label: 'Claude / GUS' },
  ```
  This is the **only** place the label text is defined; `gtmOfferingsSettings.html` renders it via `{section.label}` binding (`grep -n "Claude / GUS" force-app/main/default/lwc/gtmOfferingsSettings/gtmOfferingsSettings.html` returns no hits), so the HTML template itself needs no edit.

- **System Component Impacted:** LWC only (`gtmOfferingsSettings`). No Apex, no Custom Metadata, no schema, no permission sets.

### Decision: leave the internal `id: 'claude-gus'` unchanged — do not rename it

Verified via `grep -rn "claude-gus"` across the repo, the id is a load-bearing internal routing key, not a label, referenced in:
- `force-app/main/default/lwc/gtmOfferingsSettings/gtmOfferingsSettings.js` line 36 (`SECTIONS` array) and line 83 (`isClaudeGusSelected` getter compares `this.selectedSectionId === 'claude-gus'`).
- `force-app/main/default/lwc/gtmSetupChecklist/gtmSetupChecklist.js` line 38 — `SETTINGS_SECTION_BY_KEY = { ..., ai_keys: 'claude-gus', ... }`, which drives the Setup checklist's deep-link `selectsection` event into this exact section.
- `force-app/main/default/lwc/gtmOfferingsSettings/__tests__/gtmOfferingsSettings.test.js` line 255 (`it.each` id list) and `force-app/main/default/lwc/gtmSetupChecklist/__tests__/gtmSetupChecklist.test.js` line 282 (asserts the fired `sectionId` equals `'claude-gus'`).
- Three architecture docs (`docs/architecture/guided-setup.md`, `docs/architecture/guided-setup-implementation-plan.md`, `docs/architecture/adr/0010-gtm-offerings-settings-tab-is-one-tab-with-sections.md`) that document this id as part of the deep-link contract.

Renaming the id touches functional routing code (`gtmSetupChecklist.js`) plus two Jest assertions plus three docs, for zero user-visible benefit (ids are never displayed). Recommendation: **change only the `label` string; leave `id: 'claude-gus'` and the `isClaudeGusSelected` getter name exactly as-is.** This is the minimal, reversible change per CLAUDE.md §4 "Plan Before Action."

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO** — this does not touch `GtmAgentToolSurface`, `GtmAgentProxyController`, or any tool-execution path. AGENTS.md §1 zero-DML rule is not implicated.
- [ ] Altering Custom Metadata? **NO** — no `GTM_Assessment_*` metadata, no `migration-accelerator/` YAML involved.
- [ ] Introducing database fields? **NO** — no new fields, objects, or schema. No permission-set mapping is needed. Confirmed by reading `gtmOfferingsSettings.js` in full: the `SECTIONS` array only holds a static `id`/`label` pair per row; nothing here reads or writes org data.

This is a pure UI label-text change with no schema, Apex, or permission-set implications.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. `force-app/main/default/lwc/gtmOfferingsSettings/gtmOfferingsSettings.js` line 36's `label` value changes from `'Claude / GUS'` to the new label (e.g. `'GUS Configuration'`); `id: 'claude-gus'` and the `isClaudeGusSelected` getter are untouched.
  2. The stale JSDoc line in the same file (line 17: `"Claude / GUS" (Unit 2 of ADR-0010) exposes...`) is optionally updated for accuracy, at the Developer's discretion — it is a comment, not functional, and not required to pass CI.
  3. Every hardcoded `'Claude / GUS'` string assertion in `force-app/main/default/lwc/gtmOfferingsSettings/__tests__/gtmOfferingsSettings.test.js` is updated to the new label so the suite fails loudly instead of silently passing on stale text. Confirmed occurrences via `grep -n "Claude / GUS"`:
     - Line 76: `it('renders a nav rail with all seven sections: ..., Claude / GUS, ...')` — description text, update for accuracy.
     - Line 88: `expect(navItems[3].textContent).toBe('Claude / GUS');`
     - Line 184: `it('switches to the Claude / GUS section child on nav click', ...)` — description text.
     - Line 199: `expect(activeItem.textContent).toBe('Claude / GUS');`
     - Line 255: the `it.each` row `['claude-gus', 'c-gtm-offerings-settings-agent', 'Claude / GUS']` — only the third (label) element changes; the first element (`'claude-gus'`, the id) stays.
  4. `GtmAgentSettingsController.cls` line 2's comment (`... backing the "Claude / GUS" ...`) may optionally be updated for consistency; it is a code comment with no functional effect, so not required for this issue to pass.
  5. Architecture docs that describe this label historically (ADR-0010, `guided-setup.md`, `guided-setup-implementation-plan.md`, `docs/backlog.md` #169 entry) are **not** required to change — ADRs and backlog entries are point-in-time historical records per this repo's convention, not live UI copy. Leave them as-is unless a human later promotes an update.
  6. No other LWC, Apex, or test file references the string `'Claude / GUS'` or the id `'claude-gus'` beyond what is listed above — confirmed exhaustively via repo-wide `grep -rn "claude-gus"` and `grep -rn "Claude / GUS"`.
  7. No in-progress worktree/branch conflicts with this change: verified `git diff main agent/issue-gus-live-agentforce-provider-auth -- .../gtmOfferingsSettings.js .../gtmOfferingsSettings.html` and the same for `agent/issue-gus-live-agentforce-provider-runtime` — both return empty diffs, so neither active Agentforce branch touches this file.

- **Target Test Target:** `force-app/main/default/lwc/gtmOfferingsSettings/__tests__/gtmOfferingsSettings.test.js` (run via `npm test`). No Apex test is affected (no Apex code changes).
