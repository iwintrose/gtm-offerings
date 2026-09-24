#!/usr/bin/env bash
# Provisions/tears down the isolated Git Worktree workspaces used by the
# BA -> Architect -> Developer -> QA coding-agent roster in AGENTS.md §2.
#
# Usage:
#   scripts/agent-workspace.sh create   <issue-id>            # Architect step
#   scripts/agent-workspace.sh complete <issue-id>             # QA pass: push, open PR, remove worktree
#   scripts/agent-workspace.sh fail     <issue-id> "<message>" # QA fail: log failure, keep worktree for Developer
#   scripts/agent-workspace.sh cleanup  <issue-id>             # abandon: remove worktree without pushing
#   scripts/agent-workspace.sh list                            # show active agent worktrees
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKTREES_DIR="$(cd "$REPO_ROOT/.." && pwd)/worktrees"
BASE_BRANCH="main"

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

require_issue_id() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    echo "error: missing <issue-id>" >&2
    usage
  fi
  if [[ ! "$id" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: issue-id '$id' has characters outside [A-Za-z0-9._-]" >&2
    exit 1
  fi
  echo "$id"
}

worktree_path() {
  echo "$WORKTREES_DIR/issue-$1"
}

branch_name() {
  echo "agent/issue-$1"
}

cmd_create() {
  local id branch dir
  id="$(require_issue_id "${1:-}")"
  branch="$(branch_name "$id")"
  dir="$(worktree_path "$id")"

  if [[ -e "$dir" ]]; then
    echo "error: worktree already exists at $dir" >&2
    exit 1
  fi

  mkdir -p "$WORKTREES_DIR"
  git -C "$REPO_ROOT" fetch origin main
  # Branch explicitly from origin/main, not the local $BASE_BRANCH ref --
  # `git fetch origin main` updates origin/main but does NOT advance the
  # local main branch, so branching off local main can silently fork from
  # a stale commit.
  git -C "$REPO_ROOT" worktree add -b "$branch" "$dir" "origin/$BASE_BRANCH"

  if [[ -f "$REPO_ROOT/.env" ]]; then
    ln -s "$REPO_ROOT/.env" "$dir/.env"
    echo "linked $REPO_ROOT/.env -> $dir/.env"
  fi

  # Deliberately NOT named CLAUDE.md: this worktree is a full checkout of
  # $BASE_BRANCH and already has the real, tracked CLAUDE.md in it. Writing
  # to that filename here would clobber it (found by the roster's own QA
  # step during the issue-13 test run -- see git log for the incident).
  local scope_rel="docs/agent-artifacts/task-scope-$id.md"
  mkdir -p "$dir/docs/agent-artifacts"

  cat > "$dir/WORKTREE_SCOPE.md" <<EOF
# WORKTREE_SCOPE.md — agent worktree constraint (issue-$id)

This worktree is scoped to issue **$id** only. Before writing any code:

- Read \`$scope_rel\` in this worktree (copied in below from the
  BA agent's version, not any stale root copy) — it is the boundary of
  what this issue covers. Work outside that scope belongs to a different
  issue/worktree, not this one.
- Follow the main repo's \`CLAUDE.md\` and \`AGENTS.md\` (§2) for working
  rules, GUS's tool-surface contract, and the roster hand-off protocol —
  this file only adds the scope constraint above, it doesn't replace those.
- On completion, commit your work with a Conventional Commit and stop.
  Do NOT push, open a PR, or run \`agent-workspace.sh complete\` yourself —
  that is QA's step, run only after QA verifies the change against the
  scope file above.
EOF

  # Scope file: prefer the BA's branch (ba-scope/issue-$id) over any
  # working-tree copy, which may hold a different issue's scope. Read from
  # the new per-task path docs/agent-artifacts/task-scope-$id.md first;
  # during the migration window, fall back to the legacy root TASK_SCOPE.md
  # on that same ba-scope branch if the new path isn't there yet.
  # TODO(remove after in-flight branches merge): drop the legacy fallback.
  local ba_branch="ba-scope/issue-$id"
  local ref=""
  if git -C "$REPO_ROOT" rev-parse --verify "refs/heads/$ba_branch" &>/dev/null; then
    ref="$ba_branch"
  elif git -C "$REPO_ROOT" rev-parse --verify "refs/remotes/origin/$ba_branch" &>/dev/null; then
    ref="origin/$ba_branch"
  fi

  if [[ -n "$ref" ]] && git -C "$REPO_ROOT" show "$ref:$scope_rel" &>/dev/null; then
    git -C "$REPO_ROOT" show "$ref:$scope_rel" > "$dir/$scope_rel"
    echo "copied $scope_rel from $ref into $dir"
  elif [[ -n "$ref" ]] && git -C "$REPO_ROOT" show "$ref:TASK_SCOPE.md" &>/dev/null; then
    git -C "$REPO_ROOT" show "$ref:TASK_SCOPE.md" > "$dir/$scope_rel"
    echo "warning: $scope_rel not found on $ref — copied legacy TASK_SCOPE.md into $dir/$scope_rel (migration-window fallback)" >&2
  elif [[ -f "$REPO_ROOT/$scope_rel" ]] && grep -qF "ISSUE #$id" "$REPO_ROOT/$scope_rel"; then
    # Fallback only accepted if the working-tree file actually mentions
    # THIS issue's id -- otherwise it's near-certainly a different task's
    # scope left over in a shared root file (the exact collision that
    # bit issues #99-done-nav/#landing-view-enrich/#account-contact-confirm:
    # each got a mismatched header silently baked into its worktree here,
    # not caught until CI's gate or a human QA pass hours later). Failing
    # loudly now, at provisioning time, is far cheaper than a Developer
    # round-trip after the fact.
    cp "$REPO_ROOT/$scope_rel" "$dir/$scope_rel"
    echo "warning: ba-scope/issue-$id not found — copied working-tree $scope_rel (mentions this issue, but may still be stale in other ways)" >&2
  else
    git -C "$REPO_ROOT" worktree remove --force "$dir" >/dev/null 2>&1 || rm -rf "$dir"
    git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
    git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
    echo "error: no ba-scope/issue-$id branch (checked $scope_rel and legacy TASK_SCOPE.md), and no working-tree $scope_rel mentioning 'ISSUE #$id' -- it almost certainly belongs to a different in-flight task or doesn't exist yet. Have the BA agent commit this issue's scope to $scope_rel on a ba-scope/issue-$id branch (preferred) before re-running create." >&2
    exit 1
  fi

  git -C "$dir" add "$scope_rel"
  git -C "$dir" commit -m "chore: set $scope_rel for issue #$id (provisioned by architect)"

  echo "worktree ready: $dir (branch: $branch)"
  echo "next: Developer agent works in $dir"
}

cmd_complete() {
  local id branch dir
  id="$(require_issue_id "${1:-}")"
  branch="$(branch_name "$id")"
  dir="$(worktree_path "$id")"

  if [[ ! -d "$dir" ]]; then
    echo "error: no worktree at $dir" >&2
    exit 1
  fi

  git -C "$dir" push -u origin "$branch"

  if command -v gh >/dev/null 2>&1; then
    (cd "$dir" && gh pr create --fill --base "$BASE_BRANCH" --head "$branch") || \
      echo "warning: gh pr create failed — open the PR manually for $branch" >&2
  else
    echo "warning: gh CLI not found — open the PR manually for $branch" >&2
  fi

  git -C "$REPO_ROOT" worktree remove "$dir"
  echo "removed worktree $dir after pushing $branch"
}

cmd_fail() {
  local id dir message
  id="$(require_issue_id "${1:-}")"
  message="${2:-}"
  dir="$(worktree_path "$id")"

  if [[ ! -d "$dir" ]]; then
    echo "error: no worktree at $dir" >&2
    exit 1
  fi
  if [[ -z "$message" ]]; then
    echo "error: missing failure message" >&2
    usage
  fi

  printf '%s\n' "$message" > "$dir/TEST_FAILURES.log"
  echo "wrote $dir/TEST_FAILURES.log — routing back to Developer agent"
}

cmd_cleanup() {
  local id dir
  id="$(require_issue_id "${1:-}")"
  dir="$(worktree_path "$id")"

  if [[ ! -d "$dir" ]]; then
    echo "error: no worktree at $dir" >&2
    exit 1
  fi

  git -C "$REPO_ROOT" worktree remove --force "$dir"
  echo "removed worktree $dir (abandoned, nothing pushed)"
}

cmd_list() {
  git -C "$REPO_ROOT" worktree list | grep -F "$WORKTREES_DIR" || echo "no active agent worktrees"
}

case "${1:-}" in
  create)   shift; cmd_create "$@" ;;
  complete) shift; cmd_complete "$@" ;;
  fail)     shift; cmd_fail "$@" ;;
  cleanup)  shift; cmd_cleanup "$@" ;;
  list)     shift; cmd_list "$@" ;;
  *)        usage ;;
esac
