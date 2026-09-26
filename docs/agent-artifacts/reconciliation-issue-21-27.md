# Reconciliation: issue-21 + issue-27 (GtmPageContentController.cls)

## Why this exists

`agent/issue-21` and `agent/issue-27` both forked from the same commit
(`500c2112`) and both modified `GtmPageContentController.cls` +
`GtmPageContentControllerTest.cls`:

- **issue-21** — `renamePage()` gains a `STRUCTURAL_TEMPLATE_TYPES` block-list
  so the eight fixed page types (Offerings Page, Industry Chooser, both FAQs,
  Assistant, Story, Configurator, Offerings Listing) can never be renamed,
  server-side, closing the direct-Apex/API gap the LWC-only guard could not.
- **issue-27** — `setOfferingStatus()` gains an `unbuiltRequiredPages()` /
  `publishBlockedError()` guard so Draft -> Published is refused (naming the
  missing pages) unless Story, Configurator and Offerings Listing each have
  `sectionCount > 0 AND fieldCount > 0`. Draft and Archive stay unconditional.

These are independent concerns on the same file, both needed in production —
not alternatives to pick between.

## How they were combined

`git rebase agent/issue-21` was run inside the `agent/issue-27` worktree.
issue-27's changes live in `setOfferingStatus`/`unbuiltRequiredPages` (near
the bottom of the class, around line 930+) and issue-21's in `renamePage`
(around line 582+) — non-overlapping regions of the file — so the rebase
replayed issue-27's three commits on top of issue-21's three commits with
**zero textual conflicts**. No manual conflict resolution was needed; both
diffs applied cleanly in sequence.

Verified after rebase (not assumed from the clean rebase alone):
- `grep -n "STRUCTURAL_TEMPLATE_TYPES\|REQUIRED_PAGE_LABELS\|unbuiltRequiredPages\|publishBlockedError"`
  against the post-rebase `GtmPageContentController.cls` shows all four
  identifiers present exactly once each.
- Both test suites' methods are present in `GtmPageContentControllerTest.cls`
  with no name collisions: issue-21's `renamePage_*` methods (lines ~732-820)
  and issue-27's `setOfferingStatus_*`/`seedBuiltPage` additions (lines
  ~37, ~480-624).
- `npm test` — 1299 passed, 3 skipped (pre-existing, unrelated), 0 failed.
- `python3 scripts/check-references.py` — exit 0, 0 deploy-blocking.
- `python3 scripts/build-instrument.py --check` — exit 1, but the failure set
  is identical (byte-for-byte `diff`) to running the same script against
  `main` HEAD (`43856354`): all findings are pre-existing
  `migration-accelerator/` reference-material gaps (ADR-0009, needs
  `MA_MIGRATOR_ROOT`), unrelated to this change.

## Canonical branch decision

**`agent/issue-27` is canonical** and now contains both fixes. `agent/issue-21`
should be treated as superseded — no separate PR should be opened from it.

Reasoning:
- issue-27 is the larger, production-logic change (~96 lines vs. issue-21's
  ~37, mostly test-focused); rebasing the smaller/simpler change's history
  underneath the larger one keeps the more consequential diff's own commit
  as the visible tip, which is what a reviewer most needs to scrutinize.
- The rebase was run *in* the issue-27 worktree/branch by design (per the
  reconciliation task), so `agent/issue-27`'s branch ref is what already
  moved forward (rewritten to `d7c4799c`) to include issue-21's commits
  underneath it. `agent/issue-21` (`b6bf92cc`) was left untouched and is now
  a strict subset of `agent/issue-27`'s history.
- Both `task-scope-21.md` and `task-scope-27.md` are present in the combined
  tree, so a future reader has both issues' full context regardless of which
  branch name shipped.

## Not touched

`agent/issue-19`, `agent/issue-31`, `agent/issue-38` and their worktrees were
not read, referenced, or modified by this reconciliation.

One pre-existing, unrelated commit already sat on `agent/issue-27` before this
reconciliation started: `fcb7b442` / originally `138c3104`, "fix(app): capture
GUS utility bar in source so deploys stop wiping it" (refs #10). It does not
touch `GtmPageContentController.cls`, was not part of either issue-21 or
issue-27's scope, and was carried through the rebase unchanged. Flagging it
here rather than silently shipping it under the issue-21/27 banner: whoever
opens the PR for `agent/issue-27` should know that commit is riding along and
is a separate, already-complete fix for issue #10, not new work from this
reconciliation.
