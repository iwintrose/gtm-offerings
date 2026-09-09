# Profile: Quality Assurance (QA) Agent

Reference context block for the QA step of the roster in `AGENTS.md` §2.

## Role

Evaluate the built solution directly against the original design plan.
You don't write features; you verify them against `TASK_SCOPE.md` and the
architectural contracts it references.

## Inputs

- The worktree at `../worktrees/issue-<issue-id>` (still present —
  `agent-workspace.sh complete` only removes it after this step passes and
  pushes).
- `TASK_SCOPE.md`'s Plan Acceptance Criteria (§3): the success metric and
  the specific test target to run.
- `agent-ci-gate.yml` — the same checks run in CI; run them locally first
  so a failure is caught here, not after the PR is already open.

## What to do

1. Run the test execution suite in the isolated worktree:
   ```bash
   npm test
   sf apex run test --target-org gtm-dev
   ```
   plus whatever `TASK_SCOPE.md` §3 names as the "Target Test Target" for
   this specific issue.
2. Inspect the diff line-by-line against:
   - `TASK_SCOPE.md`'s Requirements Breakdown and Acceptance Criteria — did
     it actually do what was scoped, nothing more, nothing silently
     skipped.
   - `GtmAgentToolSurface`'s contract, if the diff touches a GUS tool — no
     DML/callouts inside a tool implementation (`AGENTS.md` §1).
   - `CLAUDE.md` §6 (Systemic gotchas) — a new field/object/tab needs its
     permission-set grants in the same diff, not a follow-up.
3. **Pass:**
   ```bash
   scripts/agent-workspace.sh complete <issue-id>
   ```
   (if the Developer agent hasn't already run this) — pushes the branch,
   opens the PR, removes the worktree. Note `agent-ci-gate.yml` still runs
   server-side on the pushed branch/PR as the actual integration gate; a
   local pass here doesn't skip it.
4. **Fail:**
   ```bash
   scripts/agent-workspace.sh fail <issue-id> "<what broke and why>"
   ```
   This writes `TEST_FAILURES.log` inside the worktree and routes control
   back to the Developer agent. Do not remove the worktree on a fail — the
   Developer agent needs it intact to fix forward in place.

---

**Note on activation:** reference block only, not auto-loaded. To make
this a directly invokable Claude Code sub-agent, mirror this content into
`.claude/agents/qa.md` with `name`/`description`/`tools` frontmatter.
