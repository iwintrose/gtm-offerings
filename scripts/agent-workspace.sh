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
  git -C "$REPO_ROOT" worktree add -b "$branch" "$dir" "$BASE_BRANCH"

  if [[ -f "$REPO_ROOT/.env" ]]; then
    ln -s "$REPO_ROOT/.env" "$dir/.env"
    echo "linked $REPO_ROOT/.env -> $dir/.env"
  fi

  # Deliberately NOT named CLAUDE.md: this worktree is a full checkout of
  # $BASE_BRANCH and already has the real, tracked CLAUDE.md in it. Writing
  # to that filename here would clobber it (found by the roster's own QA
  # step during the issue-13 test run -- see git log for the incident).
  cat > "$dir/WORKTREE_SCOPE.md" <<EOF
# WORKTREE_SCOPE.md — agent worktree constraint (issue-$id)

This worktree is scoped to issue **$id** only. Before writing any code:

- Read \`TASK_SCOPE.md\` at this worktree's root (copied in below from the
  BA agent's version, not the branch's stale one) — it is the boundary of
  what this issue covers. Work outside that scope belongs to a different
  issue/worktree, not this one.
- Follow the main repo's \`CLAUDE.md\` and \`AGENTS.md\` (§2) for working
  rules, GUS's tool-surface contract, and the roster hand-off protocol —
  this file only adds the scope constraint above, it doesn't replace those.
- On completion, hand off to QA via:
  \`$REPO_ROOT/scripts/agent-workspace.sh complete $id\`
EOF

  # TASK_SCOPE.md lives at the repo root and is NOT carried into a new
  # worktree by `git worktree add` unless it was already committed on
  # $BASE_BRANCH -- a worktree branches from the committed tree, not from
  # whatever the BA agent just wrote uncommitted in this checkout. Copy the
  # live version in explicitly rather than relying on the Architect step to
  # remember to (found missing in the issue-13 test run).
  if [[ -f "$REPO_ROOT/TASK_SCOPE.md" ]]; then
    cp "$REPO_ROOT/TASK_SCOPE.md" "$dir/TASK_SCOPE.md"
    echo "copied current TASK_SCOPE.md into $dir"
  else
    echo "warning: no TASK_SCOPE.md at $REPO_ROOT -- BA step must write one before this worktree is used" >&2
  fi

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
