# TASK SCOPE — ISSUE #industry-variants-content-load

## 0. Series Context & Dependency

Issue 3 of 4 in the "Industry-Specific Section Variants" series (product
owner isiah@eawpublications.com approved). **Hard dependency:**
`docs/agent-artifacts/task-scope-industry-variants-core.md` (needs the
variant object model and `createSection`/`createField` industry params to
exist as a load target). **Soft dependency:**
`docs/agent-artifacts/task-scope-industry-variants-visibility-nav.md` is
not required to load the content, but its rail Industry-view mode is the
easiest way to QA the loaded content across all 9 industries (plan's
Verification step 7) — recommend sequencing this issue after #2 even though
it isn't strictly blocked by it.

## 1. Requirements Breakdown

- **Target Objective:** Populate real, industry-tailored copy for Migration
  Accelerator across the 9 active industries defined in
  `scripts/data/seed-industry-chooser-industries.apex` (confirmed present
  at that path), for the four prioritized sections (`problem`,
  `capabilities`, `clientProfile`, `faq`), using the research briefs
  (tone/lead-use-case/terminology) already gathered and given in the
  approved plan. `hero`, `mechanism`, `pivot`, `bd`, `closing`, `header`,
  `footer` stay generic for now — explicitly out of scope for copy
  drafting in this issue.
- **System Component Impacted:** Data load only — either through the
  Content Manager UI's "+ Industry variant" flow (built by the core issue)
  performed 9 x 4 = 36 times, or a one-time Apex data script mirroring
  `scripts/data/seed-industry-chooser-industries.apex`'s pattern. No new
  LWC or Apex class code is anticipated by this issue; if the Developer
  finds the UI-flow path impractical at this volume and writes a script,
  that script is a `scripts/data/` addition, following the existing
  seed-script pattern, not a new object/schema change.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO.
- [ ] Altering Custom Metadata? NO — this issue writes `GTM_Page_Section__c`/
      `GTM_Page_Content__c` **data records** (via UI or an Apex data
      script), not Custom Metadata Type XML and not YAML instrument files
      under `instrument/`. Migration Accelerator's instrument YAML
      (`instrument/migration-accelerator/`) is unrelated to this issue —
      this is page/section content, not assessment questions.
- [ ] Introducing database fields? NO — this issue only writes data into
      fields already created by the core issue (`Industry_Key__c`,
      `Base_Section_Key__c`) and the pre-existing
      `GTM_Page_Content__c.Industry_Key__c`. No new fields, so no new FLS
      grants are needed beyond what the core issue already added.

## 3. Detailed Scope

### Industries and briefs (source of truth: approved plan, reproduced here
verbatim so this scope doc stands alone)

| Industry | Tone | Lead use case | Terminology |
|---|---|---|---|
| Consumer Products | Growth/speed, always-on urgency | Preserve DTC + loyalty + trade-promo data unification through cutover | DTC, customer 360, trade promotion, loyalty tiers |
| Energy & Commodities | Operational, compliance-first, understated | Zero-gap regulated notice/alert delivery during migration | rate case, demand response, NERC/FERC, C&I accounts |
| Financial Services | Regulatory-cautious, risk-mitigation | Full audit-trail/record-retention preservation through migration | FINRA/SEC/GLBA, suitability, book of record, KYC/AML |
| Health | Clinically careful, compliance-assumed | HIPAA-safe PHI/consent migration with BAA validated pre-cutover | PHI, BAA, minimum necessary, patient journey |
| Public Sector | Mission/constituent-trust framing | Zero-disruption migration of accessible, multilingual constituent comms | constituent engagement, Section 508/ADA, records retention |
| Retail | Fast, ROI/urgency, competitive | Peak-season-safe migration with zero personalization latency regression | omnichannel, peak readiness, real-time activation |
| Telecom/Media/Tech | Data-driven, technical, pragmatic | Migrate churn-prediction/retention automation without a data gap | churn/retention, ARPU, subscriber lifecycle |
| Transportation & Mobility | B2B-pragmatic, ABM-native | Preserve long-cycle ABM nurture/attribution through migration | ABM, shippers/carriers, RFP/procurement cycle |
| Travel & Hospitality | Experience/emotion-forward, guest-journey | Migrate loyalty tier/points data without integrity loss near peak season | guest journey, loyalty tiers, direct booking, PMS |

These 9 must match exactly what's seeded by
`scripts/data/seed-industry-chooser-industries.apex` — Developer must diff
the industry slugs in that script against this table before drafting, and
flag to the coordinator/owner if they've drifted (e.g. renamed or
reordered) rather than silently picking one or the other.

### Content drafting
- Actual field-level copy for all 9 industries x 4 sections is drafted
  during implementation (not pre-written in this scope doc — the plan
  explicitly leaves the literal copy to implementation time, only the
  briefs are fixed).
- Loaded either via the "+ Industry variant" Content Manager flow built in
  the core issue, or via a one-time Apex data script mirroring
  `scripts/data/seed-industry-chooser-industries.apex`'s pattern. If a
  script is used it must be staged-only — run against `gtm-staging`, never
  directly against `gtm-prod` (CLAUDE.md "no default target-org," and the
  memory note on no casual prod writes).

## 4. Non-Goals (this issue)

- No hide/reorder logic or Industry-view rail nav —
  `task-scope-industry-variants-visibility-nav.md`.
- No Agentforce drafting assistance — this issue's copy is hand-drafted
  during implementation, not AI-generated (the AI-assist tool is issue 4
  and is optional tooling, not a dependency for this issue).
- No other offering besides Migration Accelerator gets industry copy in
  this issue, even though the underlying capability (issue 1) is general.
- Does not touch `hero`, `mechanism`, `pivot`, `bd`, `closing`, `header`,
  `footer` sections.

## 5. Plan Acceptance Criteria

- **Success Metric:** Migration Accelerator's `problem`, `capabilities`,
  `clientProfile`, `faq` sections each have a published variant for all 9
  industries with copy that reflects that industry's tone/use-case/
  terminology from the brief table above; loading a Migration Accelerator
  prospect page tagged with any of the 9 industries renders the tailored
  copy, and an untagged/other-industry visit falls back to generic content
  unchanged.
- **Target Test Target:** No new automated test class is expected purely
  from data-loading; if a loader script is written it should have a
  smoke-check (row-count assertion per industry x section) run against
  staging. Primary verification is manual QA per the approved plan's
  Verification step 7: spot-check drafted copy on staging for 3+
  industries — one compliance-heavy (e.g. Financial Services or Health),
  one urgency-driven (e.g. Retail or Consumer Products), one B2B (e.g.
  Transportation & Mobility) — for tone/terminology/relevance.
