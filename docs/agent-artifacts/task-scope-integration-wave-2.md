# TASK SCOPE — ISSUE #integration-wave-2

## 1. Requirements Breakdown

- **Target Objective:** Preserve all work from six remaining unmerged branches (agent/issue-110, 130, 177, 54, 55, 56) by joining each into main with a real `git merge --no-ff` (never squash/rebase/reset/delete). Archive tags exist on origin (`archive/agent-issue-{110,130,177,54,55,56}`) as the safety net. Excluded by owner decision, left tagged: old #99 wizard, overview-redesign-funnel-shape/-drilldown, 106-sso, test-efficiency, app-landing-page step 2, B14, #249/piece 4.
- **System Component Impacted:** LWC (gtmAnalytics, gtmAnalyticsTeam, gtmAssessmentSubmissionView, conduit*, gtmReadoutReview, gtmContentHome, gtmOverview tests), Apex (GtmAnalyticsController/Team, GtmReadoutController, GtmPageContentController + tests), tabs, permission sets, flexipage, check-references.py.

### Key finding (verified read-only, `git diff origin/main...branch`, `git cherry`, content greps against origin/main f815a2e)
`git cherry` marks every commit "+" (unmerged) but nearly all CONTENT already landed in main via squash PRs under different SHAs (e.g. #178 = issue-177; #145/#146/#163 analytics; #239/#179). The branches are stale; a --no-ff merge adds ancestry (which is the owner's goal) but the content diff is mostly already present, so conflicts must be resolved TAKING MAIN.

Per branch:
- **110**: GTM_Analytics tab, app entry, GtmAnalyticsController(+Test), gtmAnalytics LWC, User permset tab are all already in main. Genuinely new: only the check-references.py AGG regex for SOQL date functions (main already has CALENDAR_YEAR, count 2, so likely also present), docs/architecture/gtm-analytics-v1.md, TASK_SCOPE.md/CLAUDE.local.md noise. Conflicts: add/add on gtmAnalytics.css/.html/.js (take main). Non-destructive.
- **130**: marker dots (`toMarkers`, opensMarkers) already in main. Branch uses `startedMarkers` where main uses `submittedMarkers`; taking branch would regress main. Conflicts in gtmAnalytics js/html/css/test: take main.
- **177**: consolidation already in main via #178; GTM_Analytics_Team tab is already absent in main. Conflicts: GtmAnalyticsTeamController and its Test (main has later #159/#160/#206 work: take main). DESTRUCTIVE-LOOKING items are already applied in main: removal of `GTM_Analytics_Team` tab, Admin permset tab grant.
- **54**: gtmAssessmentSubmissionView list-first nav (listColumns) and conduitDashboard wiring are already in main; ConduitPlanController and Conduit_Audit__c objects/fields exist in main (26 field files). The two "retrieve" commits (e3ce790 objects, 4f5f9b0 controller) are adds, not deletes; no file deletions in the three-dot diff. Real risk: two-dot diff shows branch's copy of conduitGapDetail/conduitMigrationPlan/conduitRationalization/ConduitPlanController is OLDER than main (main has Migration_Runbook__c persistence the branch lacks). Conflicts: submissionView html/js/test, conduitRationalization.js (add/add): take main.
- **55**: getReadoutByRequest (+tests), AR record flexipage, gtmReadoutReview changes are already in main; main renamed tab GTM_Readouts_Manager to GTM_Assessments (#250). Conflicts: modify/delete on GTM_Assessments.tab (branch deletes the old tab name) and GtmReadoutControllerTest. Merging blindly would DELETE the live GTM_Assessments tab.
- **56**: getOfferingSummary default 'Draft' and showManage already in main. Conflicts: TASK_SCOPE.md, gtmContentHome test, gtmOverview.test.js (+81 lines; main has since split gtmOverview tests into actToday/funnel/repDirect/row3 files, so re-check if these +81 lines are unique before keeping).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO. None touch GUS tools or agent actions; zero-DML rule (AGENTS.md §1) not engaged.
- [ ] Altering Custom Metadata? NO. No GTM_Assessment_* XML or instrument YAML touched.
- [ ] Introducing database fields? NO net-new (54's Conduit_Audit__c fields already in main). If a conflict resolution accidentally takes a branch-side field/tab, permset mapping (User/Admin) is mandatory.

### Destructive items (every one)
1. **agent/issue-55 `force-app/main/default/destructiveChanges/destructiveChanges.xml`**: CustomTab `GTM_Readouts_Manager`. Would delete that tab from an org. Tab no longer exists in main (renamed GTM_Assessments, #250), so it is stale. Recommendation: EXCLUDE (do not bring the file into main). Also do NOT take the branch's deletion of `tabs/GTM_Readouts_Manager` / GTM_Assessments.tab (would remove the live Assessments tab). If owner wants the old tab removed from gtm-prod, do it as a separate, explicitly approved manual `sf project deploy start --manifest package.xml --post-destructive-changes destructiveChanges.xml`. deploy.sh has no destructive step, so nothing runs automatically. Note the path `force-app/main/default/destructiveChanges/` would be inside the source tree; keep it out of force-app.
2. **agent/issue-177 removals**: `tabs/GTM_Analytics_Team.tab-meta.xml`, `<tabs>` grant on GTM_Offering_Admin permset, `<tabs>GTM_Analytics_Team</tabs>` line in GTM_Offerings app. Already applied in main (#178). Source-format removal alone does not delete from org; org still holds the tab until a destructive deploy. Recommend: no action in this wave; DEFER org cleanup, owner-approved destructive deploy only.
3. **agent/issue-54, 110, 130, 56**: none.
Wrongly-resolved conflicts (taking branch side of stale files) are the real deletion risk; see per-branch.

## 3. Plan Acceptance Criteria

- **Success Metric:** Recommended decisions and merge order (all merges `--no-ff`, resolving conflicts to origin/main content, one merge commit per branch, one PR):
  1. 110 INCLUDE (ancestry/docs only; take main on gtmAnalytics)
  2. 130 INCLUDE (take main; keep only genuinely new tests after diff-check)
  3. 177 INCLUDE-WITHOUT-DESTRUCTIVE-PART (take main; tab removal already applied)
  4. 56 INCLUDE (verify the +81 gtmOverview tests are not duplicates and pass)
  5. 54 INCLUDE (take main for all conduit*/submissionView conflicts)
  6. 55 INCLUDE-WITHOUT-DESTRUCTIVE-PART (drop destructiveChanges.xml; keep GTM_Assessments tab)
  Order rationale: analytics trio first (same files, 110 then 130 then 177), then independent branches; 55 last since it has the most hazardous conflict. TASK_SCOPE.md and CLAUDE.local.md in branches must not overwrite main's (drop those hunks). Pass criteria: (a) `npm test` green; (b) `python3 scripts/check-references.py` adds zero new deploy-blocking findings vs current main (run on main first for baseline); (c) `sf project deploy start --dry-run` validate-only to gtm-staging passes (never gtm-dev/gtm-prod); (d) no tab, permset entry, or file present in main is removed by the merge (`git diff origin/main..HEAD --diff-filter=D --name-only` must be empty except intentionally listed); (e) all six archive tags still resolve.
- **Target Test Target:** `npm test` (Jest: gtmAnalytics, gtmAnalyticsTeam, gtmAssessmentSubmissionView, conduitDashboard, gtmReadoutReview, gtmContentHome, gtmOverview.*). Apex on gtm-staging after real deploy: GtmAnalyticsControllerTest, GtmAnalyticsTeamControllerTest, GtmReadoutControllerTest, GtmPageContentControllerTest (verify exact class name exists), plus ConduitPlanController's test if one exists.

### Owner questions (recommendation in brackets)
1. Accept that content is already in main and wave 2 is ancestry-preserving, resolving all conflicts to main? [Yes.]
2. Delete stale GTM_Readouts_Manager (and GTM_Analytics_Team) tabs from gtm-prod via a separate approved destructive deploy? [Defer; verify on gtm-staging first.]
3. Any branch-only unique code worth cherry-keeping (e.g. 130's `startedMarkers`)? [No; main is newer.]

## 4. Developer Delta Record (executed)

Merges were done `--no-ff -s ours` in order 110, 130, 177, 56, 54, 55 (tree kept at main; a plain `-X ours` merge was tried first and produced duplicate `classAccesses`/`tabSettings` entries in GTM_Offering_User, so it was aborted). All six branch tips are now ancestors of HEAD. Deltas were then evaluated line-by-line against main:

| Branch | Delta | Decision |
|---|---|---|
| 110 | gtm-analytics-v1.md field tables | SKIPPED: main's doc is newer (#138 "submitted" contract, v2/v3 sections); branch tables describe the obsolete started/completed metrics. Controller/html/js/tests: superseded, main lacks nothing. |
| 130 | `.trend-dot--started` / `startedMarkers` | SKIPPED: superseded by main's `submittedMarkers`. |
| 177 | 9 header comment lines (hasTeamAccess doc) | SKIPPED: main's class header already carries the fuller text (incl. #159/#160) and hasTeamAccess is documented in main. Tab/permset removals already applied in main. |
| 56 | gtmOverview 'status and archive filtering (issue #56)' tests | PORTED (adapted to main's mocks) into gtmOverview.test.js; no equivalent existed, behavior exists in main. |
| 56 | gtmContentHome `showManage: true` + test; controller default 'Published'->'Draft' | SKIPPED, POSSIBLE REGRESSION NOTE: main deliberately hides Manage on the framework card (`!o.isFramework`, tested); branch reverses this. Controller default already 'Draft' in main. |
| 54 | ConduitPlanController `/api/sf/assets`, `/api/sf/audiences`, Gap_Detail__c; conduit*/submissionView | SKIPPED: main already POSTs with assessment context and persists Gap_Detail__c/Migration_Runbook__c; branch is an older GET form. Remaining html diffs are older description copy. |
| 55 | destructiveChanges.xml, GTM_Readouts_Manager tab deletion | EXCLUDED (destructive; GTM_Assessments tab kept). No other delta. |

Gap: no Apex test class exists for ConduitPlanController / ConduitAuditController / ConduitMigrationController / ConduitCmmController.
