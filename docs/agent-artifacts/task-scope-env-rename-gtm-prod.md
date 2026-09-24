# TASK SCOPE — ISSUE #env-rename-gtm-prod

## 1. Requirements Breakdown

- **Target Objective:** The Salesforce org alias `gtm-dev` is renamed `gtm-prod` (it IS production: live prospect data). `gtm-staging` stays. "dev" means local worktrees only. Sweep docs/scripts/CI so nothing still calls production "dev". Rules: replace the ORG ALIAS `gtm-dev` with `gtm-prod` where it means the live org; leave hostnames like `orgfarm-...-dev-ed...` and historical wording naming a past event untouched (e.g. "confirmed live in gtm-dev on 2026-09-07" may stay or be reworded at Architect discretion); never commit org IDs, usernames, or secrets. Do NOT match `gtm-developer` (agent name).
  - Add a short "Environments" section to CLAUDE.md: local worktrees = dev; gtm-staging = rehearsal and test package versions (big API quota); gtm-prod = live. Promotion flow: build in worktree -> QA validate-only against gtm-staging -> merge -> deploy main to staging for owner review -> deploy to prod only on explicit owner go-ahead. `deploy.sh` takes an explicit alias; there is no default target-org.
  - Update Developer/QA agent prompts: validate-only test runs target gtm-staging, not prod; note gtm-staging needs `EXCLUDE_DIRS=networks,sites` with deploy.sh.
- **System Component Impacted:** Docs, shell/Python/Apex-comment scripts, CI workflow, agent prompts. No LWC, Apex logic, Experience Cloud route, or YAML instrument change.

### Occurrence inventory (`gtm-dev` excluding `gtm-developer`; ~303 total in 96 files)

**Live-behavior sites (functional, must change):**
- scripts/deploy.sh: 4 (line 104 `case ... gtm-dev) IS_PROD_ALIAS=1` is a HARD-CODED GUARD; must become `gtm-prod`; lines 72/98/125 comments)
- scripts/check-org-drift.py: 1 (default `SF_TARGET_ORG` fallback `"gtm-dev"`)
- scripts/check-all.sh: 1 (default `SF_TARGET_ORG:-gtm-dev`)
- scripts/backfill-link-owner.py: 2 (line 910 is a test fixture string `org="gtm-dev"` in a self-check of confirm-org rejection; docstring line 17)
- .claude/settings.local.json: 1 (`Bash(./scripts/deploy.sh gtm-dev *)` permission rule; untracked/local, owner already added alias; update rule)
- .github/workflows/agent-ci-gate.yml: 1 (step name "Authenticate to gtm-dev (JWT)"; label only, secrets untouched)
- scripts/seed-synthetic-data.py: 7 (warnings/help text)

**Docs/agent prompts:** CLAUDE.md 2 (+ new Environments section); .claude/agents/gtm-ba.md 1; .claude/agents/gtm-qa.md 2 (line 18 `sf apex run test --target-org gtm-dev` must become gtm-staging); gtm-developer.md 0 (add staging validate-only + EXCLUDE_DIRS note); AGENTS.md 0 (check §2 for alias-free wording); README.md 0; DEPLOYMENT.md 1; TASK_SCOPE.md 1 (tracked stray file, historical); docs/backlog.md 9; docs/runbooks: rep-ownership-backfill 9, fresh-org-deploy 5, questionnaire-resume 2; docs/architecture: overview 1, app-home-pages 5, gtm-analytics-v1 2, gtm-page-header-layout 3, gtm-assessments-table 2, blank-install 3, offering-archive-cascade 1, add-industry 6, gus-chat-provider-settings 1, overview-card-heights 1, overview-sales-dashboard-3-offerings-results 1, gus-utility-bar-host 2, gtm-filter-bar 7, site-shell-metadata 1; adr/0007 1, adr/0008 3, adr/0009 3, adr/0010 2.

**Scripts (comments/run-usage lines):** build-instrument.py 2, check-references.py 2, probe-guest-update.apex 2, offerings/test-offering.manifest 1, and 10 scripts/data/*.apex files with 1 each ("Run via ... -o gtm-dev"; these usage lines should now say gtm-prod, or staging for rehearsal).

**Tests / code paths (flagged; NO functional use, comments only):** 
- LWC Jest: gtmAnalytics.test.js 1, preview.test.js 1
- Apex: GtmAssessmentRequestController 1, GtmReadoutController 3, GtmPageContentController 1, GTM_PurgeRecordsBatch 1, GtmReadoutPublishNotificationTest 2, GtmAssessmentRequestControllerTest 2, GtmReadoutControllerTest 3
- Metadata XML comments: GTM_Assessment_Config.Default.md-meta.xml 1, GTM_Offering_User.permissionset-meta.xml 4, test-fixtures GTM_Offering.Test_Offering.md-meta.xml 1
These are comment-only; editing them touches Apex/metadata files and would force a deploy to prod. **Recommendation: leave force-app/ and test-fixtures comments untouched** (no runtime effect; avoids a production deploy). Owner to confirm.

**docs/agent-artifacts/ (45 files, 172 occurrences):** ephemeral, historical scope/plan docs. Recommend leaving as-is (historical record); artifacts are not authoritative.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO. No Apex tool or DML change (AGENTS.md §1 zero-DML rule not engaged).
- [ ] Altering Custom Metadata? NO. Recommend not touching customMetadata XML comment either.
- [ ] Introducing database fields? NO. No permission-set mapping needed.

## 3. Plan Acceptance Criteria

- **Success Metric:** `grep -rIP "gtm-dev(?!eloper)"` returns only the deliberate leftovers (agent-artifacts history, force-app/test-fixtures comments if the owner keeps them, hostnames). deploy.sh treats `gtm-prod` as the prod alias (guard fires for `gtm-prod`, no longer for `gtm-dev`), and check-org-drift.py / check-all.sh defaults are resolved (see open questions). CLAUDE.md has the Environments section and promotion flow; gtm-developer.md and gtm-qa.md direct validate-only runs at gtm-staging with `EXCLUDE_DIRS=networks,sites`. No org IDs, usernames, or secrets are added.
- **Target Test Target:** No Apex/Jest change. Run `npm test` (Jest) and `python3 scripts/check-references.py` plus the `--check` self-tests of `scripts/backfill-link-owner.py` and `scripts/seed-synthetic-data.py`; `bash -n scripts/deploy.sh scripts/check-all.sh`; and a `deploy.sh` dry check confirming IS_PROD_ALIAS=1 for `gtm-prod`.

## Open questions for owner

1. Default alias fallbacks in check-org-drift.py and check-all.sh: change to `gtm-prod`, or remove the default and require an explicit alias (consistent with "no default target-org")?
2. Edit comments in force-app/ and test-fixtures (needs a prod deploy) or leave?
3. Rewrite historical artifacts or leave?
4. Should the `deploy.sh` prod guard also cover a `gtm-dev` alias during a transition window?
5. agent-ci-gate.yml: rename label only, confirm secrets unchanged.
