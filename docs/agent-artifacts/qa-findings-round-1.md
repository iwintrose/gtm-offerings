# QA findings — round 1

**Reviewer:** QA agent (session `session_018UJzwgTCCMdESELzYMeWAZ`)
**Date:** 2026-09-07
**Scope:** Independent re-verification of `docs/agent-artifacts/architecture-doc-plan.md` §7 against the real repo at commit `f9e3eb8` (branch `claude/gtm-offerings-ma-deploy-vtf5vl`) and the live `gtm-dev` org (`00DgK00000XZieHUAT`).
**Verdict:** NOT APPROVED — see tickets below.

Every check below was independently re-run against the repo (`grep`/`ls`/`git log`/`git diff`/`git show`) or the live org (`sf data query`), not taken on the Dev completion report's word. Passing checks are summarized at the end; failing checks are filed as tickets here.

---

## Ticket 1 — BLOCKING: `docs/architecture/overview.md`'s container diagram names the wrong site as the live guest-facing one

**Where:** `docs/architecture/overview.md` line 23 (`subgraph site["Experience Cloud: GTM Accelerator site (gtmaccelerator/s)"]`), and the whole `site` subgraph beneath it (lines 23-27).

**What's wrong:** The diagram — the single "what talks to what" map this whole documentation effort is meant to anchor — presents `GTM_Accelerator1` (`urlPathPrefix: gtmaccelerator/s`) as *the* guest-facing Experience Cloud site, hosting the Story/Configurator pages, the assessment questionnaire, and the published readout. That site is not the live one. The live site is `GTM1` (`urlPathPrefix: gtm/s`), and it currently has **no assessment, readout, story, or industry routes deployed to it at all**.

**How I verified it, independently, three ways:**

1. **Live org query** (`sf data query -q "SELECT Id, Name, Status, UrlPathPrefix FROM Network" --target-org gtm-dev`):
   ```
   Name              Status              UrlPathPrefix
   GTM               Live                gtm
   GTM Accelerator   DownForMaintenance  gtmaccelerator
   ```
2. **`docs/backlog.md` itself, in the repo's own words** — D3 (line 51): *"One public site at `/gtm`... **Don deactivates GTM Accelerator**, then reseeding."* D9 (line 517-518): *"`GTM_Accelerator1` — the legacy site, now `DownForMaintenance`... `GTM1` (the live `/gtm` site)..."*
3. **The metadata itself** — `force-app/main/default/experiences/GTM1/routes/` has no `assessment.json`, `readout.json`, `story.json`, or `industry.json`; `force-app/main/default/experiences/GTM_Accelerator1/routes/` has all four. The questionnaire/readout LWCs the diagram cites (`gtmAssessmentQuestionnaire`, `gtmReadoutView`) are wired only into `GTM_Accelerator1/views/assessment.json` and `.../readout.json` (`grep -l` confirms), never into `GTM1`.

**Why this matters beyond a wrong label:** this isn't cosmetic — it means the diagram (and, by extension, this whole doc-rebuild's flagship "explanation" artifact) describes the marquee assessment/readout/approval feature as reachable through a site that is currently down for maintenance in the org QA has live access to, while saying nothing about the fact that the actually-live site has none of these pages built onto it yet. A cold reader — human or agent — walks away with an inverted picture of what a real prospect can reach today.

**Relation to Dev's self-reported deviation #3:** Dev's correction ("one guest site, not two — it's `GTM_Accelerator1`") fixed the plan's "two sites" framing but picked the *wrong* single site. There is exactly one currently-live guest site, and it's `GTM1`, not `GTM_Accelerator1`.

**Also relevant, not newly introduced by Dev but worth flagging since the Architect's plan certified it "accurate" without catching this:** `docs/runbooks/readout-public-link.md` and `docs/runbooks/questionnaire-resume.md` (both "keep as-is" in the plan, both pre-date this task) reference `/gtmaccelerator/s/...` throughout as the guest URL, with the same site-status gap. The plan's §1 audit asserted these were "read in full; accurate... No changes needed" — that assertion doesn't hold up against the live org. I'm not asking Dev to rewrite these two runbooks in this pass (out of the scoped task), but `CLAUDE.md`/`overview.md` should not silently inherit and amplify a stale assumption these runbooks already had.

**Severity:** Blocking. This is exactly the "factual drift" risk the plan's own §0 names as the thing that matters most, in the document whose entire purpose is being the accurate map.

---

## Ticket 2 — SHOULD-FIX: `CLAUDE.md`'s FLS-gap gotcha drops the `GTM_` prefix on two object names, drifting from ADR-0002

**Where:** `CLAUDE.md` line 89: `` grant gap on `Page_Content__c`/`Page_Section__c` found during the ``

**What's wrong:** No object named `Page_Content__c` or `Page_Section__c` exists in this repo. The real objects are `GTM_Page_Content__c` and `GTM_Page_Section__c`.

**How I verified it:**
- `ls force-app/main/default/objects/ | grep -i "Page_Content\|Page_Section"` → `GTM_Page_Content_Version__c`, `GTM_Page_Content__c`, `GTM_Page_Section__c`. No unprefixed variants exist.
- `docs/architecture/adr/0002-...md` (the very ADR `CLAUDE.md` points to for this fact) gets it right: `` `GTM_Page_Content__c`/`GTM_Page_Section__c` ``.
- `docs/backlog.md` line 359, the original source of this fact, also uses the `GTM_`-prefixed names.

This is the exact failure mode the plan's own §7.3 checklist asks QA to catch: *"ADR-0002 (FLS gaps) and `CLAUDE.md`'s systemic-gotchas section name the *same* 5 instances — no drift between the two."* There is drift — one of the five named instances has a different (wrong, non-existent) object name in `CLAUDE.md` than in the ADR it's supposed to match.

**Severity:** Should-fix. A future agent grepping `force-app/` for `Page_Content__c` (as written) will find nothing and may waste time before checking the ADR for the real name.

---

## Ticket 3 — SHOULD-FIX: a genuinely load-bearing gotcha from `HANDOVER.md` was silently dropped, contrary to the plan's own disposition for it

**Where:** Nowhere in the new docs. Was previously in `HANDOVER.md`'s "Why a rep sees the rep experience on the public site" section (deleted at `f9e3eb8`).

**What's wrong:** `HANDOVER.md` documented a real, non-obvious, deliberately-undeployed-config gotcha: `Network.allowInternalUserLogin` (a Setup-only field, intentionally excluded from the metadata deploy to avoid clobbering live site settings — see the file's own text) governs whether a logged-in internal Salesforce user is served the site's **guest** experience instead of the rep experience when they open a site URL, and `GtmViewerContext.isRep()` is the code-side half of that story. The plan's own disposition table for `HANDOVER.md` (§3) explicitly says this content should land in one of three places: *"(a) is already captured better in `docs/backlog.md`'s D-numbered entries, (b) belongs in `CLAUDE.md`'s gotchas section (§4) or a new runbook, or (c) is genuinely dead."* It is none of (a) or (c) — it's current, real, and not duplicated elsewhere — and it did not land in (b) either.

**How I verified it:**
- `git show f9e3eb8^:HANDOVER.md` recovers the full pre-deletion content (224 lines) — the section is real and specific (env var, exact API used, exact class/method).
- `grep -rln "allowInternalUserLogin\|isRep()\|GtmViewerContext" docs/ CLAUDE.md` → no matches anywhere in the new/kept doc tree (the class `GtmViewerContext.cls` itself still exists in `force-app/`, confirming this is current code, not dead).
- `grep -n "allowInternalUserLogin" docs/backlog.md` → no matches — not already captured there either.

`CLAUDE.md` §5 (systemic gotchas) has exactly 5 numbered items, none of which is this one.

**Related, same failure mode, lower confidence it was ever explicitly in scope:** the same `HANDOVER.md` also documented a real CSS convention — shared `--gtm-*` custom properties must be pulled in via `@import 'c/gtmTokens';` rather than redefined locally, because they don't cross shadow-DOM boundaries between sibling (non-parent/child) LWCs — with an explicit "if you add a new component that needs these tokens..." instruction aimed at exactly the kind of future agent `CLAUDE.md` exists to brief. This wasn't named in the plan's disposition table the way the `allowInternalUserLogin` gotcha was, so I'm not filing it as its own ticket, but it reinforces that the "everything durable is captured or dead" claim in the plan's `HANDOVER.md` row wasn't fully borne out.

**Severity:** Should-fix. The content is still recoverable via `git log -p -- HANDOVER.md`, so nothing is unrecoverably lost, but it is no longer discoverable from any doc a cold agent would actually read, which defeats the purpose of "durable facts get lifted out before the file is deleted."

---

## Ticket 4 — NICE-TO-HAVE: stray quote mark in ADR-0005

**Where:** `docs/architecture/adr/0005-scoring-and-readout-data-are-computed-server-side-only.md`, line 12: `` (downgraded to `Self-Estimated"`, since ``

**What's wrong:** Missing opening quote — should read `` `"Self-Estimated"` ``. The underlying claim is accurate (verified against `GtmAssessmentRequestController.cls` lines 104-110 and 1167-1177, which do describe `complexityBasis` as always downgraded to `"Self-Estimated"` server-side regardless of client input) — this is a pure transcription typo, not a factual error.

**Severity:** Nice-to-have.

---

## Checks performed that passed (no ticket filed)

Structural (plan §7.1): `AGENTS.md` is a real symlink to `CLAUDE.md`; `docs/architecture/overview.md` exists; `docs/architecture/adr/` has exactly 5 files numbered 0001-0005 with titles matching plan §5.2; `docs/runbooks/experience-site-lifecycle.md` exists and its 6-step procedure matches `HANDOVER.md`'s pre-deletion content (`git show f9e3eb8^:HANDOVER.md`) faithfully, plus its own "before deleting, confirm against the org" caveat; `HANDOVER.md` is gone; `README.md` has none of "Phase 1"/"Phase 2"/"ma-migrator"; both `docs/specs/*.md` files carry the rename staleness banner.

Factual (plan §7.2 + my own additional spot-checks): all 5 cited guest/rep Apex classes exist; all 5 permission sets exist and match by name; the approval process and `GTM_Readout_Triage` queue exist; `reset-accelerator-demo.apex` has the 4 new fictional names in its actual `DEMO_NAMES` set/seed data (old names appear only in an explanatory comment, as expected) and `DEPLOYMENT.md` no longer names the 4 real companies; `questionnaire-resume.md` had exactly 4 pre-fix occurrences of `GTM_Assessment_Draft__c` (confirmed via `git show 59566e8:...`), all 4 now read `GTM_Form_Draft__c`, and that object exists while `GTM_Assessment_Draft__c` does not; the `DuplicateRuleHeader.allowSave = true` line still exists in `reset-accelerator-demo.apex`; Dev's corrected dynamic-Apex-access class list (7 classes) exactly matches `grep -l "getGlobalDescribe\|Database.query(" force-app/main/default/classes/*.cls` (excluding `*Test.cls`), and the plan's originally-guessed classes (`GtmAssessmentQuestions`, `GtmMigrationPairs`) genuinely do **not** use either pattern — Dev's correction here is right; `sf project deploy start --dry-run` vs. `-c` is stated correctly; org Id `00DgK00000XZieHUAT` and the "gtm-dev is production" framing are both present in `CLAUDE.md` and match the live `sf org display` output exactly. Additional spot-checks beyond the plan's list: `sourceApiVersion: "62.0"` in `sfdx-project.json` matches `CLAUDE.md` §3; both Lightning app labels (`GTM Offerings`, `GTM Content Manager`) match their `.app-meta.xml` `<label>`; the `GTM_Config_Send_To_Client` flow exists; all 3 Content Manager tabs (`GTM_Content_Home`, `GTM_Content_Manager`, `GTM_Instrument_Author`) exist; the `Status__c` picklist on `GTM_Readout__c` has exactly the 4 values the state diagram uses (Draft, Pending Approval, Approved, Published); all 5 state-transition method names cited (`submitForApproval`, `recallApproval`, `publishReadout`, `unpublishReadout`, `returnToDraft`) exist on `GtmReadoutController.cls`, and I read `unpublishReadout`/`returnToDraft` in full to confirm the edges (including the "Published never reverts straight to Draft" rule) match the code, not just the names; the instrument's L0-L4 layer system and the 14-step public-link smoke test count both check out; `.claude/agents/` genuinely does not exist (only a gitignored `worktrees/` dir under `.claude/`); `scripts/check-references.py --inventory` and `scripts/build-instrument.py --check` are both real, implemented flags; `scripts/deploy.sh --run-tests` and `scripts/deploy-fresh-org.sh`'s four flags are all real.

**Mermaid syntax:** both diagrams in `docs/architecture/overview.md` were extracted and rendered with `@mermaid-js/mermaid-cli` (not just eyeballed) — both render without error. This does not affect Ticket 1's finding, which is about factual content, not syntax.

Internal consistency (plan §7.3): `DEPLOYMENT.md` → `fresh-org-deploy.md` cross-reference is genuinely mutual (`fresh-org-deploy.md` §11 now points back, confirmed via `git diff 59566e8..HEAD` showing only an addition, not a rewrite); `fresh-org-deploy.md`'s "never been deployed to a fresh org" caveat is untouched, confirmed by the same diff. "Leave untouched" list (`MAINTAINERS.md`, `docs/backlog.md`, `assessment-instrument.md`, `readout-public-link.md`, the HTML walkthrough, `index.html`, `migration-accelerator/`) — `git diff 59566e8..HEAD --stat` on all of them shows zero changes.

## Research validation (task §2)

- **CLAUDE.md/AGENTS.md length (2026):** current guidance is more aggressive toward brevity than the plan portrays — sources found range from "20-30 lines, add only when an agent keeps getting something wrong" to "under 150 lines," versus the plan's cited "~250 lines" target. `CLAUDE.md` as built is 191 lines — under the plan's own 250-350 line target, and within or just above even the stricter end of what I found. Given this repo's safety-critical gotchas (the `-c` flag trap that already caused a live-org incident, the FLS-gap pattern), I don't think the plan's "justified to run over the generic guideline" reasoning is wrong, but the plan somewhat overstated where the current 2026 consensus actually sits — it's more aggressive than "~250 lines," not less.
- **ADRs, Nygard format (2026):** confirmed still dominant — current sources describe it as "too small, too useful, and too well-adopted to be displaced," with MADR and Y-Statement as the only named alternatives worth knowing, neither displacing it. The plan's citation and adoption here are sound.
- **Diátaxis and `runbooks/` naming:** confirmed the plan's conclusion. Diátaxis's four-mode split is about document *shape* by reader need, not a prescribed directory-naming scheme; "how-to-" prefixing is one convention some teams use for Diátaxis how-to docs, but runbook-style naming (Google SRE/Atlassian/PagerDuty conventions: Purpose/Prerequisites/Procedure/Verification/Rollback) is a distinct, equally legitimate convention for the same "how-to" mode. Nothing in current guidance argues this repo's `docs/runbooks/` should be renamed to `how-to/`. The plan's reasoning holds up against my independent research.

## What I could not independently verify

- Whether `python3 scripts/check-references.py`, `scripts/deploy.sh gtm-dev --run-tests`, and `sf apex run test --target-org gtm-dev` complete cleanly end-to-end — I confirmed the flags are real and match the scripts' actual argument parsing, but did not execute a live deploy or full test run against `gtm-dev` (out of scope for a docs QA pass, and running `--run-tests` against a production-treated org without being asked is not something I'll do unilaterally).
- Whether `GTM1`'s current `DownForMaintenance`/`Live` statuses will still hold by the time this is read — org state can change after this review; Ticket 1 reflects the state at time of verification (2026-09-07, confirmed via live `sf data query`).
