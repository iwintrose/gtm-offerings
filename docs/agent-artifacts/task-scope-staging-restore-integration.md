# TASK SCOPE — ISSUE #staging-restore-integration

## 1. Requirements Breakdown

- **Target Objective:** Restore `gtm-staging` to its true latest state (2026-09-20 ~20:06-20:23 UTC builds, replaced on 2026-09-21 by a plain `main` deploy) by cutting ONE integration branch `agent/issue-staging-restore-integration` from `origin/main` that merges all unmerged UI work (all backed up as `agent/issue-*` on origin, nothing may be lost), then deploying it to `gtm-staging` only, and later promoting through normal QA/PR. Read-only analysis below; a trial merge in a throwaway worktree (discarded) was used to find conflicts. No code or org was touched.
- **System Component Impacted:** LWC (gtmFilterBar, gtmRepLinkFinder, gtmReadoutsOverview, gtmAssessmentsTableModel, gtmOverview, gtmContentHome, PageHeader, gtmSetupChecklist/gtmSetupItem, Settings shell, Industry Chooser add-industry modal), Apex (GtmAssessmentListController, GtmAssessmentRequestController, GtmReadoutController, GtmSetupChecklistController, GtmSetupActionController), app/flexipage metadata, docs. No YAML instrument change.

### 1.1 Integration set (verified against origin/main; no branch is an ancestor of another)

The two big tips differ by one commit each: `sc-links-to-pages` = `link-draft-state` minus docs commit 0a619b2 (link readiness contract) plus 87e378c (app-level View override). Merging both gives the full set. Both contain the whole filters chain (assessments-row-open, compact-filters-r1b, filters-integrated, filters-r2-pages, filters-r3-assessments, industry-filter-source, pages-columns-links), so those need no separate merge.

| Branch | Verdict | Notes |
|---|---|---|
| link-draft-state | INCLUDE (first) | 28 ahead; filters chain + link readiness doc. Trial: clean vs main. |
| sc-links-to-pages | INCLUDE | Adds 87e378c; clean after the above. |
| guided-setup-integrated | INCLUDE | gsetup-a..e, guided-setup, guided-setup-plan (Settings tab / Setup checklist). Adds GtmSetupChecklistController, GtmSetupActionController + tests. Clean. |
| home-responsive | INCLUDE | Header bar / responsive Overview + ContentHome + PageHeader. Clean. |
| related-lists | INCLUDE | CONFLICT: GTM_Offerings.app-meta.xml. |
| overview-card-heights | INCLUDE | CONFLICT: docs/architecture/overview-card-heights.md (docs only; resolve by taking branch text). |
| add-industry | INCLUDE | CONFLICT: docs/architecture/add-industry.md, docs/backlog.md (docs; keep both). Guided-setup contract depends on it. |
| browser-followups, density, table-columns (PR #246 open), submit-atomic-startover, industry-empty-state, overview-request-links-to-page, rep-initiated-assessment-no-page-3-readout-link-confirmation | INCLUDE | All clean. |
| demo-seed-fix | INCLUDE | CONFLICT: scripts/seed-synthetic-data.py (take branch, main has older seed script; verify no main-only edits lost). Has gtm-dev refusal guard, good. |
| test-efficiency | INCLUDE, low priority | CONFLICT: .claude/agents/gtm-qa.md, .github/workflows/agent-ci-gate.yml, scripts/check-all.sh, scripts/check-org-drift.py. Tooling only, not a UI need; merge last, hand-merge, or defer to its own PR if resolution is risky. |
| compact-filters-docs-c10 | INCLUDE DOCS ONLY | Its code (older gtmFilterBar/gtmAssessmentsTableModel, earlier filter trials) is superseded by the chain in link-draft-state; taking it would regress to the "earlier filter trials" the owner sees. On merge, resolve gtmFilterBar.* and gtmAssessmentsTableModel.js to the link-draft-state versions; keep docs/architecture/gtm-filter-bar.md union. Only its TEMP-DIAG add/revert pair is unmerged code noise. |
| filter-data-tie-audit | INCLUDE (docs) | Docs only; CONFLICT gtm-filter-bar.md, keep union. |
| assessments-account-filters-apex | ALREADY-IN-MAIN | Squash-merged as #245 (cherry shows ahead only because of squash). Conflicts in GtmAssessmentListController.cls: main wins. Confirm eb4e05d (approved-sent readout key fix) is contained in main; the file already contains "approved" so likely yes, verify by diff before skipping. |
| site-shell-metadata | ALREADY-IN-MAIN | Squash #238. Skip. |
| 106-sso-resume | EXCLUDE-WITH-REASON (flag) | ACTIVATING change: new Auth Provider, Connected App, registration handler that changes how employees authenticate. Not UI, not part of the restore. Also conflicts on WORKTREE_SCOPE.md. Keep on its own branch; separate approval. |
| app-landing-page | HOLD / owner decision | Step 1 (Home FlexiPages) is already in main; unmerged step 2 (de5d79f, 09-19) retires the Overview and Content Home tabs and edits both app-meta files (CONFLICT GTM_Offerings.app-meta.xml, app-home-pages.md). It changes navigation for reps, and home-responsive/overview work targets those same components. See owner Q1. |

Other origin `agent/issue-*` tips also show unique cherry commits (e.g. overview-sales-dashboard-*, page-header-*, gus-*, rep-ownership-lockdown-3/4, settings-*, wizard-*, gsetup-*). The owner list did not name them; the Architect should run `git cherry`/diff for each against the integration result and report any that are neither in main nor in the set (most are likely squash-merged predecessors). Not verified here except gsetup-*/filters chain.

### 1.2 Recommended merge order

1. link-draft-state, 2. sc-links-to-pages, 3. guided-setup-integrated, 4. home-responsive, 5. browser-followups, density, table-columns, submit-atomic-startover, industry-empty-state, overview-request-links-to-page, rep-initiated-assessment-no-page-3-readout-link-confirmation (all clean), 6. add-industry, overview-card-heights (docs conflicts), 7. related-lists (app-meta conflict), 8. compact-filters-docs-c10 (docs only, see above), filter-data-tie-audit, 9. demo-seed-fix, 10. test-efficiency (optional), 11. app-landing-page step 2 only if owner says yes.

### 1.3 Conflict hot-spots

- `force-app/main/default/applications/GTM_Offerings.app-meta.xml` (related-lists, app-landing-page): union nav items and actionOverrides; sc-links-to-pages already adds a View override, so check for duplicates.
- `gtmFilterBar.*`, `gtmAssessmentsTableModel.js`, `gtmFilterBar.test.js`, `docs/architecture/gtm-filter-bar.md`: the filters chain wins over compact-filters-docs-c10.
- `GtmAssessmentListController.cls`: main wins (#245).
- `GtmAssessmentRequestController.cls`, `GtmReadoutController.cls` (+tests), `GtmReadoutPublishNotificationTest.cls`: changed by the branches; merged cleanly in trial but review for ownership regressions.
- Ownership pieces (#247/#248/#250): the trial merge of the core set left GtmStageActionsController, GtmArCasePanelController, GtmAgentGetConfigState, GtmAgentProxyController, GtmLinkEventController, GtmLinkOwnerStamp byte-identical to main. Rule: main's version of these must win in any conflict; after merging, `git diff origin/main --stat -- '*.cls'` must show none of them, and no `gtm-dev`/`gtm-prod` rename string reverted (#250).
- Docs: docs/backlog.md, add-industry.md, overview-card-heights.md, app-home-pages.md, gtm-assessments-table.md (union, no deletions).
- Scripts/CI: seed-synthetic-data.py, check-all.sh, check-org-drift.py, agent-ci-gate.yml, gtm-qa.md.
- Scope files: many branches carry `docs/agent-artifacts/task-scope-*.md` and WORKTREE_SCOPE.md; the integration branch needs its own scope file (this one); do not keep other WORKTREE_SCOPE.md content.

### 1.4 TEMP-DIAG commits (keep for staging; revert before ANY production promotion)

- 6543fae "chore(gtmReadoutsOverview): TEMP-DIAG [GTMRO] live diagnostics, revert before any PR"
- 09cba1f "TEMP-DIAG: log payload and rows"
- c572bf6 "remove TEMP-DIAG [GTMRO] logging" reverts the above inside filters-integrated, so on link-draft-state tips the net diagnostics are removed. Verify with `git grep -n "TEMP-DIAG\|\[GTMRO\]"` on the integrated tree; anything found must be listed in the PR and removed before promotion.
- a35decc TEMP-DIAG in gtmFilterBar (compact-filters chain) is reverted by 6d570f8. Also confirm.
Recommendation: keep whatever remains for staging debugging only, and add a pre-promotion grep gate.

### 1.5 Branch and worktree state gaps

- All worktrees under /Users/isiwintr/Documents/Workbench/worktrees/ are clean except issue-site-shell-metadata (untracked TEST_FAILURES.log, throwaway) and gsetup-d (node_modules only). Nothing uncommitted found.
- Local vs origin: `issue-106-sso-resume` behind main by 77; `compact-filters-r1b` local worktree branch is named issue-compact-filters (r1b tip 73b6d5c); several local branches have [gone] upstreams (old, merged). Confirm every local-only commit exists on origin (`git for-each-ref` ahead/behind) before deleting any worktree.
- Staging's 20:06-20:23 UTC 2026-09-20 deploys "small ones matching newest branch tips": newest commits found are 16:09-16:23 local time (related-lists a0a8d85, link-draft-state 0a619b2); timezone of git dates not verified. If staging ran a state NOT captured by any pushed tip (e.g. an uncommitted worktree deploy), it cannot be recovered from git; owner should check `sf project deploy report`/org metadata history.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? (NO new change authored; if gus-* branches join the set, verify zero-DML rule in AGENTS.md §1)
- [ ] Altering Custom Metadata? (NO; no instrument/YAML change. Do not touch GTM_Assessment_* XML)
- [ ] Introducing database fields? (NO new fields authored by this task; guided-setup/add-industry/related-lists were checked only for merge, Architect should confirm any field they add is mapped to Permission Sets)

## 3. Plan Acceptance Criteria

- **Success Metric:** (a) One branch cut from origin/main containing every INCLUDE item, no commit lost (`git branch -r --no-merged` for each INCLUDE branch shows it merged). (b) `npm test` passes (Jest). (c) `python3 scripts/check-references.py` yields no new deploy-blocking findings vs main. (d) main's ownership Apex classes are untouched by the integration (git diff vs origin/main empty for the six named classes). (e) Deploy to `gtm-staging` only (never gtm-dev/prod) succeeds with the deployment set below, then `sf community publish` if experiences change; owner confirms header bar, Settings > Setup checklist, and filter UI are back. (f) TEMP-DIAG grep list recorded. Deploy set: LWCs gtmFilterBar, gtmRepLinkFinder, gtmReadoutsOverview, gtmAssessmentsTableModel, gtmOverview, gtmContentHome, PageHeader, gtmSetupChecklist, gtmSetupItem, Settings shell, Industry Chooser + modal, related record-page flexipages; Apex GtmAssessmentListController, GtmAssessmentRequestController, GtmReadoutController, GtmSetupChecklistController, GtmSetupActionController and their tests, plus tabs/apps/flexipages/permission-set changes from related-lists and guided-setup.
- **Target Test Target:** Jest: `npm test` (specs incl. gtmFilterBar, gtmRepLinkFinder, gtmReadoutsOverview, gtmSetupChecklist, gtmSetupItem, settings shell). Apex on gtm-staging: GtmAssessmentListControllerTest, GtmAssessmentRequestControllerTest, GtmReadoutControllerTest, GtmReadoutPublishNotificationTest, GtmSetupChecklistControllerTest, GtmSetupActionControllerTest, plus the ownership tests for GtmStageActionsController, GtmArCasePanelController, GtmAgentGetConfigState, GtmAgentProxyController, GtmLinkEventController, GtmLinkOwnerStamp, and the Industry Chooser controller test for createIndustry.

## 4. Open Owner Questions (with recommendations)

1. app-landing-page step 2 (retire Overview and Content Home tabs): include? Recommend NO for the restore (not in the reported missing work); ship later as its own PR.
2. 106-sso-resume: recommend keep out of this branch; it changes authentication, needs its own approval, and must not be deployed on the restore.
3. test-efficiency (CI/QA tooling): recommend defer to its own PR to keep this branch UI-only, unless owner wants it.
4. Was the staging state ever deployed from an uncommitted tree? Recommend owner/coordinator check staging deploy history; unknown here.
5. Unlisted branches with unique commits (overview-sales-dashboard-*, page-header-*, gus-*, settings-*): recommend Architect diff each against the integration result and report before deploy.
6. Recommend deploying with a `--dry-run` validation to gtm-staging first, and an org-backup retrieve of current staging before overwriting again.
