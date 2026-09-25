# TASK SCOPE — ISSUE #7

## 1. Requirements Breakdown

- **Target Objective:** Implement the D11 resolution plan (`docs/agent-artifacts/d11-resolution-plan.md`,
  companion to ADR-0008 —
  `docs/architecture/adr/0008-the-guest-assessment-is-hosted-by-the-engagement-link-not-by-a-standalone-route.md`):
  make the live `GTM1` `/configurator` surface send real, scored assessment
  answers by replacing the booking modal (`gtmConfigBooking`) with the
  questionnaire (`gtmAssessmentQuestionnaire`) hosted inside `gtmConfigurator`,
  while touching zero files under `force-app/main/default/experiences/`.

- **CRITICAL FINDING — verify-before-build changes the shape of this task.**
  I read the full plan (all 7 phases + QA protocol) and then checked the
  *current* codebase against every phase's file-by-file claim. **Every phase
  of the plan is already implemented on `main`, and its own tests pass.**
  Concrete evidence, each independently re-run by me:

  | Plan phase | Claim | Verification run | Result |
  |---|---|---|---|
  | 1 (restore lost test) | `gtmConfigurator.readout.test.js` recovered under `gtmConfigurator/__tests__/` | `ls force-app/main/default/lwc/gtmConfigurator/__tests__/` | File present: `gtmConfigurator.readout.test.js` (alongside 7 other suites) |
  | 2.1 | `@api embedded = false;` + `rootClass` on `gtmAssessmentQuestionnaire.js` | `grep -n "embedded" .../gtmAssessmentQuestionnaire.js` | `@api embedded = false;` at line 324, `rootClass` getter present |
  | 2.3 | `gtmConfigurator.js` tracks `linkOfferingKey` / `effectiveOfferingKey`, link wins over page property | `grep -n "linkOfferingKey\|effectiveOfferingKey" .../gtmConfigurator.js` | `@track linkOfferingKey` (line 187), `if (rec.offering) this.linkOfferingKey = rec.offering;` (line 813), `effectiveOfferingKey()` returns `this.linkOfferingKey \|\| this.urlOfferingKey \|\| this.offeringKey` (line 1179) |
  | 3 (BD context fields) | a `bdContext` step, chunked, optional, isolated from `answers`/`supplementAnswers` | `grep -n "bdContext" .../gtmAssessmentQuestionnaire.js` | `@track bdContext`, `isBdContext`, `bdContextPages()`, snapshot/restore round-trip all present |
  | 4 (resubmit guard) | server-side one-request-per-link check before DML; `GtmConfigurationStatusController.hasSubmittedAssessment` | `grep -n "already.isEmpty\|ONE SUBMITTED" GtmAssessmentRequestController.cls`; `grep -n hasSubmittedAssessment GtmConfigurationStatusController.cls` | Both present verbatim, including the `ONE SUBMITTED ASSESSMENT PER ENGAGEMENT LINK (ADR-0008 section 4)` comment |
  | 5.3 (calendar CTA) | `hasBookingUrl` / "Pick a time in our calendar →" surfaces inside the questionnaire's `q-done` panel | `grep -n "hasBookingUrl\|Pick a time" .../gtmAssessmentQuestionnaire.html` | Present |
  | 6 (the swap) | `gtmConfigBooking` deleted; `gtmConfigurator.html` hosts `<c-gtm-assessment-questionnaire>` instead | `ls force-app/main/default/lwc/ \| grep -i booking` → empty; `grep -n "c-gtm-assessment-questionnaire\|c-gtm-config-booking" gtmConfigurator.html` | `gtmConfigBooking` bundle is gone from the tree; `gtmConfigurator.html` embeds `<c-gtm-assessment-questionnaire>` (two call sites, lines ~551 and ~671), zero references to `c-gtm-config-booking` |
  | 7.1 (resume-link carries the link) | `gtmConfigurator.js` reads `?resume=`, auto-opens overlay | `grep -n "resume\b\|resumeToken" .../gtmConfigurator.js` | `@track resumeToken`, `readUrlParams()` reads `resume` param, ADR-0008-referencing comment in place |
  | Guardrail | zero `experiences/` changes | `git log --oneline -- force-app/main/default/experiences/` | Only the single "Initial import" commit ever touched that directory — no D11-related commit exists there |
  | Regression check | `check-references.py` shows no dangling reference to the deleted `gtmConfigBooking` | ran `python3 scripts/check-references.py` | `0 deploy-blocking` (the 60 "needing a manual step" items are all unrelated pre-existing metadata-introspection SOQL warnings, e.g. `EntityDefinition`, `ObjectPermissions`, `SetupEntityAccess` — none mention `gtmConfigBooking`) |
  | Regression check | restored/extended test suite is green | ran `npx jest .../gtmConfigurator/__tests__/gtmConfigurator.readout.test.js .../gtmAssessmentQuestionnaire` | `Test Suites: 2 passed, 1 skipped` / `Tests: 71 passed, 1 skipped, 72 total` |

  I also checked `docs/backlog.md`'s D11 entry (lines 475–540+): it is still
  worded **"decided, planned, not yet implemented — ADR-0008"** and has not
  been updated to reflect that the code landed. This is real drift between
  docs and code — the code is ahead of the backlog note, not behind it — and
  is exactly the kind of "docs predate what's really there" gap `AGENTS.md`
  warns about, just in the opposite direction from usual (implementation
  ahead of its own paper trail, most likely landed under an earlier
  differently-scoped/differently-numbered issue or session and never looped
  back to close #7 or update the backlog/overview docs).

- **What is NOT yet true and is the actual remaining, in-scope work for
  issue #7**, per Phase 7.4's own doc checklist, all still stale:
  1. `docs/backlog.md` D11 entry still reads "not yet implemented" — needs
     to be marked resolved, pointing at ADR-0008 and the plan file, per
     Phase 7.4.
  2. `docs/architecture/overview.md` — checked: the container-diagram text
     and the "Known gap" callout **already read as post-fix**
     (`grep` at line 85: *"GTM1 (Live Site): Only the `/configurator` route
     is functional. It renders `c:gtmConfigurator`, which handles both guest
     assessments (`c:gtmAssessmentQuestionnaire`) and the published-readout
     view..."*) — this file does **not** need a further update; flag this
     explicitly since Phase 7.4 assumed it would still be stale and it is
     not.
  3. `docs/runbooks/questionnaire-resume.md` — checked: already describes
     the post-fix `?cfgId=...&resume=...` flow on `/gtm/s/configurator` and
     explicitly calls out `gtmaccelerator` as the wrong, `DownForMaintenance`
     site — also **already current**, no further edit needed.
  4. `CLAUDE.md` §5/§7 topology sentences the plan flagged as needing an
     update — checked the live file: there is no `§5.7` in the current
     `CLAUDE.md` (section numbering has clearly shifted since the plan was
     written) and I found no sentence describing `GTM1` as having "only a
     `/configurator` route served by a booking component" anywhere in the
     current file. This claim in the plan is stale; no `CLAUDE.md` edit is
     needed for D11 specifically.
  5. `GtmFormDraftController` / `Draft_Type__c = 'Booking'` retirement —
     the plan explicitly deferred this to "a separate decision for a
     separate session" (§6.3, open call #2). **Out of scope for #7.**
  6. **QA verification protocol (the plan's own §"QA verification
     protocol")** has, as far as I can tell from the repo alone, never been
     run and reported: there is no QA artifact, backlog entry, or commit
     referencing a live-browser run of the headline test (real anonymous
     submission scoring for real, resubmission blocked four ways, button
     state machine walked in a real browser, cleanup of QA fixture data).
     This is the one piece of the plan that is code-unverifiable from a BA
     pass — it requires a real browser and real `gtm-staging`/`gtm-prod`
     queries, which is QA-agent, not BA-agent, work.

- **System Component Impacted:** Documentation only
  (`docs/backlog.md`), plus QA verification (browser + org queries against
  `gtm-staging`, per this repo's promotion flow — `gtm-prod` only on the
  owner's explicit go-ahead). **No LWC, Apex, or Experience Cloud route code
  changes are in scope for issue #7** — that code is already merged to
  `main` and its own tests already pass. Re-implementing any of Phases 1–7
  would be redundant, is very likely to reintroduce accidental drift
  against already-verified live behavior, and is explicitly not needed.

- **Ambiguity a human should resolve, not a BA guess:** it is unclear from
  the repo alone *which* prior commit/session actually merged all seven
  phases (there is no single commit whose message matches any of the plan's
  seven `Commit:` lines verbatim, and the most recent commit on `main`
  before this scoping pass, `b3975d1`, is an unrelated issue-#11 fix). I did
  not find a paper trail (PR, backlog entry, or ADR update) recording when
  and by whom D11 was actually implemented. Before an Architect/Developer
  step is spun up to "implement issue #7," the coordinator/owner should
  confirm: (a) that this already-implemented code is in fact intended to be
  the final resolution (not a different, unrelated experiment that happens
  to satisfy the same file paths), and (b) whether QA has already run the
  live-browser protocol somewhere untracked in git. If neither is true, the
  only real remaining "implementation" work for #7 is documentation +
  QA verification, not code.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **No.** This task touches no
      `Gtm*Tool*`/GUS surface; not applicable, zero-DML rule N/A.
- [ ] Altering Custom Metadata? **No.** No `GTM_Assessment_*` custom
      metadata XML or `instrument/<offering-key>/` YAML change is required;
      the plan's own §0.5/§0.6 findings (re-verified above) show the server
      already resolves `Offering__c` correctly and needs no new plumbing.
- [ ] Introducing database fields? **No new fields.** The eleven BD-context
      fields (`Budget_Range__c`, `Pain_Points__c`, `Migration_Goals__c`,
      etc.) already exist on `GTM_Assessment_Request__c` and are already
      mapped to `GTM_Offering_User` / `GTM_Offering_Admin` permission sets
      (confirmed by `grep` — `Budget_Range__c`, `Pain_Points__c`,
      `Migration_Goals__c` all present in both permission-set XML files).
      **One permission-set observation worth recording, not fixing:** the
      guest-facing `GTM_Guest` permission set has **zero** explicit
      `fieldPermissions` entries for any `GTM_Assessment_Request__c` field
      (verified: `grep -c "GTM_Assessment_Request__c\." GTM_Guest...xml` →
      `0`), even though these BD fields are not `required` (`required:
      false` confirmed on `Budget_Range__c.field-meta.xml` and
      `Pain_Points__c.field-meta.xml`) and per CLAUDE.md §6 a non-required
      field with no explicit grant is normally invisible/unwritable under
      FLS. This is **not a live bug**: `GtmAssessmentRequestController` is
      declared `without sharing` and performs classic (non-`USER_MODE`,
      non-`stripInaccessible`) DML (confirmed by reading the class header
      and DML calls), so guest FLS is not enforced on this write path,
      matching the plan's own §7.2 conclusion that "no new class grant is
      expected." Flagging only so a future permission-set audit doesn't
      mistake this gap for an oversight — it is a known, deliberate
      byproduct of the `without sharing` design, but if that Apex trust
      boundary ever changes (e.g. a future refactor adds `with sharing` or
      `AccessLevel.USER_MODE`), these grants would need to be added in that
      same commit per ADR-0002.

## 3. Plan Acceptance Criteria

- **Success Metric:** Issue #7 closes when (a) `docs/backlog.md`'s D11 entry
  is edited to state the fix is implemented and verified (not "planned, not
  yet implemented"), citing ADR-0008 and this plan file, and (b) the plan's
  own "QA verification protocol" section has actually been executed against
  `gtm-staging` by a QA pass — real anonymous submission scores for real,
  resubmission is blocked all four ways, the button state machine is walked
  live, and nothing regressed (existing readouts still render, rep surfaces
  unchanged, `GTM Accelerator` untouched and still `DownForMaintenance`) —
  with its findings recorded (in a QA artifact or the backlog), each claim
  backed by the actual query/browser step used, per this plan's own closing
  standard ("say how it was proven — not that it was"). No code changes
  should be needed to reach this state, since the implementation already
  exists and its unit tests are green.
- **Target Test Target:** `npx jest force-app/main/default/lwc/gtmConfigurator/__tests__/gtmConfigurator.readout.test.js force-app/main/default/lwc/gtmAssessmentQuestionnaire` (already passing: 71 passed, 1 skipped) for the unit-level regression baseline; `GtmAssessmentRequestControllerTest.cls` for the server-side resubmit-guard Apex tests; and, as the actual acceptance gate per the plan's own protocol, a live-browser QA pass against `gtm-staging` following `d11-resolution-plan.md`'s "QA verification protocol" section 1–9 verbatim (not a re-read of the diff).
