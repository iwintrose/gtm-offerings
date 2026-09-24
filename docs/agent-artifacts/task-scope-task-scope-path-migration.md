# TASK SCOPE — ISSUE #task-scope-path-migration

## 1. Requirements Breakdown

- **Target Objective:** Eliminate the two recurring collision seams on `TASK_SCOPE.md` in the BA→Architect→Developer→QA workflow by moving the per-task scope artifact from a single shared root-level `TASK_SCOPE.md` to a unique per-task path, `docs/agent-artifacts/task-scope-<id>.md`. Concretely:
  - **Seam 1 (stale root copy):** the root `TASK_SCOPE.md` gets overwritten by whichever issue's BA step ran most recently, so a task read after the fact can see the wrong content. `agent-workspace.sh create` already guards this via `ba-scope/issue-<id>` branch lookup + header hard-fail, but the underlying single-shared-filename design stays fragile.
  - **Seam 2 (branch-merge conflict):** every `agent/issue-*` branch commits its own `TASK_SCOPE.md` at the same path with different content; merging two such branches (or one into `main`) produces a real git conflict at that path, currently resolved by hand every time.
  - Moving to a per-task filename removes both seams structurally: no single mutable "current scope" file to go stale, and no shared path for two task branches to collide on.
  - This is **meta/infra work on the agent workflow tooling itself** — no Salesforce metadata, LWC, or Apex product changes are in scope.
  - Full approved design is recorded at `/Users/isiwintr/.claude/plans/hi-spicy-boot.md`; treat it as authoritative for implementation details not repeated below (e.g. exact fallback ordering, verification script shapes).
  - **Deferred item (post-conflict-resolution note):** step 7 ("Remove the root artifact" — `git rm TASK_SCOPE.md` from `main`) is explicitly **out of scope for this PR**. A concurrent branch (`assessment-list-row-navigation`) committed a legitimate content update to root `TASK_SCOPE.md` after this branch forked, so deleting it here would both fight that merge and violate the plan's own migration-window guidance (root removal belongs to a *separate follow-up PR* once the grace period ends and no pre-cutover worktrees remain). This branch restores/keeps root `TASK_SCOPE.md` untouched and relies solely on the new per-task path plus the CI gate's legacy fallback for in-flight branches.
  - **Ambiguity/human-judgment flag:** the migration-window dual-path fallback (accepting the legacy root `TASK_SCOPE.md` from `ba-scope` branches and in CI) is explicitly temporary scaffolding meant to be removed in a *separate follow-up PR* "after a grace period (e.g. once `agent-workspace.sh list` shows no pre-cutover worktrees, or after ~2 weeks)." This PR must implement the fallback but should **not** attempt to decide or hardcode when that grace period ends — that's a human call for whoever ships the follow-up cleanup PR. Flag this rather than silently picking a date.

- **System Component Impacted:** Coding-agent workflow tooling and its documentation — none of `force-app/`, `instrument/`, or `data/seed/`. Specifically:
  - `scripts/agent-workspace.sh` (shell script, `cmd_create`)
  - `.claude/agents/gtm-ba.md`, `gtm-architect.md`, `gtm-developer.md`, `gtm-qa.md` (agent role definitions)
  - `.github/workflows/agent-ci-gate.yml` (CI gate)
  - `.github/workflows/agent-roster-dispatch.yml` (unattended dispatch prompts)
  - `AGENTS.md` §2 (workflow documentation)
  - Root `TASK_SCOPE.md` (removed from `main` via `git rm` in this same change)

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? — **No.** This work does not touch `GtmAgentToolSurface`, any Apex tool implementation, or DML/callout logic. N/A.
- [ ] Altering Custom Metadata? — **No.** Nothing under `force-app/main/default/customMetadata/` or `instrument/<offering-key>/` is touched; `migration-accelerator/` YAML is unaffected. N/A.
- [ ] Introducing database fields? — **No.** No Salesforce objects, fields, or schema are introduced; no Permission Set mapping is required. N/A.

(All three items are inapplicable — this issue is entirely shell script, GitHub Actions YAML, and Markdown agent-instruction changes, not Salesforce schema or Apex.)

## 3. Plan Acceptance Criteria

- **Success Metric:** Definition of done, per the approved plan:
  1. `scripts/agent-workspace.sh` `cmd_create` reads the BA scope from `docs/agent-artifacts/task-scope-<id>.md` on the `ba-scope/issue-<id>` branch (local then `origin/`), `mkdir -p`s the target directory in the new worktree, and writes it there — keeping the existing header-match hard-fail guard, now checked against the new path.
  2. During the migration window, `cmd_create` also accepts the legacy root `TASK_SCOPE.md` from the `ba-scope` branch if the new path isn't present there yet (dual-path fallback, not a silent no-op).
  3. The base-ref bug is fixed alongside: new worktrees branch explicitly from `origin/main`, not local `main` (since `git fetch` does not advance local branch refs).
  4. `WORKTREE_SCOPE.md`'s generated text references the new path.
  5. `.claude/agents/gtm-ba.md` names `docs/agent-artifacts/task-scope-<id>.md` as the BA's sole Write target and `git add` target (no more root `TASK_SCOPE.md` references).
  6. `.claude/agents/gtm-architect.md`, `gtm-developer.md`, `gtm-qa.md` have all root-`TASK_SCOPE.md` references replaced with the new path.
  7. `.github/workflows/agent-ci-gate.yml` computes `SCOPE_FILE="docs/agent-artifacts/task-scope-${ISSUE_ID}.md"` dynamically from the branch's issue id (not a hardcoded `TASK_SCOPE.md`), retains the placeholder/header checks against `$SCOPE_FILE`, and falls back to legacy root `TASK_SCOPE.md` if the new path isn't found, marked with a `TODO(remove after in-flight branches merge)` comment.
  8. `.github/workflows/agent-roster-dispatch.yml`'s unattended BA/Architect prompt instructions reference the new path.
  9. `AGENTS.md` §2's BA/Architect/QA bullets name the new path instead of root `TASK_SCOPE.md`.
  10. Root-level `TASK_SCOPE.md` is removed from `main` (`git rm`) in this same PR; already-in-flight `agent/issue-*` branches' own legacy-path copies are left untouched and must keep passing CI via the fallback until they merge.
  11. Two synthetic `ba-scope/issue-TEST1` / `issue-TEST2` branches, each with their own `docs/agent-artifacts/task-scope-<id>.md`, can be run through `agent-workspace.sh create` and merged sequentially into a scratch `main` with zero file conflicts at the scope-file path.
  12. The CI gate's shell logic, run locally against a correct branch, passes; run against a deliberately mismatched header, fails — proving the header cross-check still works against the new path.
  13. `cmd_fail` / `cmd_complete` in `agent-workspace.sh` are confirmed unaffected (they don't reference the scope file).
  14. A synthetic legacy-path-only branch still passes the CI gate during the migration window (fallback works); this scope does not require proving the *post-cleanup* removal (that belongs to the follow-up PR called out in the ambiguity flag above), but the fallback path itself must be demonstrated working now.

- **Target Test Target:** No Apex class or LWC Jest spec applies (no product code changed). QA must instead:
  - Manually/locally exercise `scripts/agent-workspace.sh create` against the two synthetic `ba-scope/issue-TEST1`/`TEST2` branches described in the approved plan's Verification section, confirming correct, uncontaminated per-task scope files land in each worktree and that merging both resulting branches into a scratch `main` produces zero conflicts.
  - Extract and run `agent-ci-gate.yml`'s scope-file shell logic locally (or via `act`/a scratch workflow run) against (a) a correctly-named/headed new-path branch — expect pass, (b) a deliberately mismatched header — expect fail, (c) a legacy-root-only branch during the migration window — expect pass via fallback.
  - Confirm `shellcheck` (if already run in CI on `agent-workspace.sh`) still passes after edits, and that YAML lint/syntax on both touched workflow files is valid.
