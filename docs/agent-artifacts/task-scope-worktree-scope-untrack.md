# TASK SCOPE — ISSUE #worktree-scope-untrack

## 1. Requirements Breakdown

- **Target Objective:** Stop `scripts/agent-workspace.sh`'s `cmd_create` from
  `git add`ing/committing `WORKTREE_SCOPE.md` on every `agent/issue-*`
  branch. That file is a fixed-root-path, per-issue-stamped, worktree-local
  reminder for whichever Developer agent works in that worktree session —
  it carries no cross-role hand-off information (unlike
  `docs/agent-artifacts/task-scope-<id>.md`, which BA -> Architect ->
  Developer -> QA all genuinely read across the branch's lifetime). Because
  every branch independently commits a same-path file with different
  stamped content, it has produced a textual merge conflict on every PR
  merge so far this session (#169, #193, #196, #194) — always the same
  trivial "keep our own branch's text" resolution, pure friction for a file
  nobody needs in git history. Fix: write it to the worktree exactly as
  today (content/behavior unchanged), but treat it like `.env` — present on
  disk, symlinked/generated locally, never staged or committed — and
  gitignore it so it can't be swept in by a future `git add -A`.
  Confirmed while investigating: `WORKTREE_SCOPE.md` is *currently tracked
  in `main`* (a stray copy from a prior branch's merge, `git ls-files
  WORKTREE_SCOPE.md` returns it) — see Code Dependency Checklist below for
  what to do about that existing tracked copy; it is not itself the
  ongoing-conflict source (that's `cmd_create`'s repeated per-branch
  commits), but it should not survive this fix as the one committed
  instance frozen on `main`.
- **System Component Impacted:** `scripts/agent-workspace.sh` (bash
  tooling script, not LWC/Apex/Experience Cloud/YAML instrument — this is
  pure agent-workflow tooling under §2 of `AGENTS.md`/`CLAUDE.md`). Also
  touches root `.gitignore` and `AGENTS.md` §2 prose.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No — this issue never touches
      `GtmAgentToolSurface`/Apex/LWC/DML at all. N/A, AGENTS.md §1 zero-DML
      rule does not apply.
- [ ] Altering Custom Metadata? No — no `migration-accelerator/` YAML or
      `force-app/main/default/customMetadata/GTM_Assessment_*` XML is
      touched. N/A.
- [ ] Introducing database fields? No — no Salesforce schema/object/field
      is introduced, so no Permission Set mapping is required. N/A.

Concrete implementation notes for the Developer (not code, but scoping the
change precisely since this task is script/tooling-only):

1. In `cmd_create` (`scripts/agent-workspace.sh`), the `cat > "$dir/WORKTREE_SCOPE.md" <<EOF ... EOF` heredoc block that generates the file must stay exactly as-is (Developer instructions in `.claude/agents/gtm-developer.md:19` tell the Developer agent to "read the worktree's own `WORKTREE_SCOPE.md`" — that still works unmodified as long as the file physically exists on disk in the worktree; only its git-tracking status changes).
2. The line `git -C "$dir" add "$scope_rel" WORKTREE_SCOPE.md` must drop `WORKTREE_SCOPE.md` from the `add` list, leaving only `git -C "$dir" add "$scope_rel"`. The subsequent commit message ("chore: set $scope_rel for issue #$id (provisioned by architect)") should likewise stop mentioning `WORKTREE_SCOPE.md`, since it will no longer be part of that commit.
3. Confirmed via full read of `scripts/agent-workspace.sh`: `WORKTREE_SCOPE.md` is referenced nowhere else in the script — not in `cmd_complete` (pushes branch + opens PR, no file reference), not in `cmd_fail` (only writes `TEST_FAILURES.log`), not in `cmd_cleanup` (just removes the worktree), not in `cmd_list`. It is safe to stop committing it without touching any other `cmd_*` function.
4. Add `WORKTREE_SCOPE.md` to the root `.gitignore` (already exists at repo root, currently lists `.sf/`, `.sfdx/`, `.claude/worktrees/`, `node_modules/`, `coverage/`, `__pycache__/`, `.env`) — add it as its own line, ideally near `.env` since it now follows the same "generated locally into a worktree, never committed" pattern.
5. Existing tracked copy: `git ls-files WORKTREE_SCOPE.md` currently returns a hit — a stamped copy (issue-settings-units-2-3) is tracked on `main` right now from a prior branch's merge. Per point 4 of the migration note below, the Developer should `git rm WORKTREE_SCOPE.md` (untrack it, do not just gitignore-and-leave, since a tracked+gitignored file will keep showing as tracked and diverging) as part of this same change, so `main` stops carrying a stale stamped-for-one-issue copy going forward.
6. `AGENTS.md` §2, Architect Agent action item 3, currently reads: "Symlinks essential `.env` variables and drops a custom local `CLAUDE.md` constraint template into the new worktree directory root." This mislabels the file as `CLAUDE.md` (the script explicitly avoids that name, per its own in-script comment, to prevent clobbering the worktree's real tracked `CLAUDE.md`) — it should say `WORKTREE_SCOPE.md`, and should note it is generated locally and not committed. Update this line for both accuracy (wrong filename) and to reflect the new not-committed behavior.
7. `.claude/agents/gtm-architect.md:38` also references `WORKTREE_SCOPE.md` (correct filename there) as something the Architect "drops" — verify after the script change that this doc's wording doesn't imply it gets committed; if it does, adjust similarly to point 6.

## 3. Plan Acceptance Criteria

- **Success Metric:** After the fix, provisioning two synthetic worktrees
  for two different issue ids via `scripts/agent-workspace.sh create
  <id-a>` and `create <id-b>` (each needs a corresponding
  `ba-scope/issue-<id>` branch with a valid
  `docs/agent-artifacts/task-scope-<id>.md` to satisfy the existing
  hard-fail check — reuse the BA flow or hand-construct a minimal one for
  the test) produces a `WORKTREE_SCOPE.md` file on disk in each worktree
  (content present, script behavior unchanged) but `git status` in each
  worktree shows `WORKTREE_SCOPE.md` as ignored/untracked-and-ignored, not
  staged, and it does NOT appear in `git log`/`git show` for either
  branch's new commit. Merging both branches into a disposable scratch
  `main` (do not do this against the real `main`) must produce zero merge
  conflicts attributable to `WORKTREE_SCOPE.md` specifically. Also confirm
  `git -C <repo-root> status` shows the pre-existing tracked
  `WORKTREE_SCOPE.md` removed (via the `git rm` in point 5 above) with no
  other unrelated files touched.
  This is a go-forward fix only: in-flight or historical branches that
  already committed a stamped `WORKTREE_SCOPE.md` before this change do
  **not** need retroactive git-history cleanup or rebasing — git history
  is immutable and that's an acceptable, expected artifact of the
  pre-fix behavior. The Developer should not attempt to rewrite history
  on old branches to remove it.
- **Target Test Target:** No Apex class or LWC Jest spec applies (bash
  tooling script, no Salesforce metadata changed). The verification is the
  manual `scripts/agent-workspace.sh create` dry run described above
  (two synthetic worktrees + scratch-branch merge), plus `git diff
  --stat` review of the script/`.gitignore`/`AGENTS.md` changes to confirm
  no unrelated lines were touched. If the repo's CI includes a shell-lint
  step (e.g. `shellcheck scripts/agent-workspace.sh`), run that too as a
  basic sanity check on the edited script.
