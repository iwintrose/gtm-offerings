# TASK SCOPE — ISSUE #ps-brand-overhaul-7-industry-content-authoring

> Part 7 of 7 in the `ps-brand-overhaul` initiative. Depends on part 3's
> schema (`ps-brand-overhaul-3-content-schema-case-fls`) being finalized —
> specifically the field *shape*, not the Case/FLS half of that doc. Can
> run in parallel with parts 4/5/6 (visual work) once that field contract
> is settled, since authoring content rows and restyling components touch
> the same records/UI but not the same code paths. This is explicitly an
> editorial/content-ops workstream, not an engineering one — flagged by
> the coordinator's brief as likely to run separately from/after the
> engineering parts, and I agree with that framing based on its nature.

## 1. Requirements Breakdown

- **Target Objective:** Author real, persona-grounded per-industry copy for
  all fields on `IndustryProfile` — the 9 pre-existing fields
  (`coverSub`, `problem`, `useCase`, `solution`, `proofLine`, `whyLine`,
  `whyHead`, `demoRoot`, `uniquePoints`) plus part 3's new ones
  (`partnerLine`, `approachLine`, `deliverableExtra`, `engagementLine`,
  `closingLine`, `assetCount`, `healthScore`, `dependencyCount`, and
  `heroImageUrl` if part 3 accepts that recommendation) — across all 9
  industries the framework's Industry Chooser models. Confirmed current
  authoring state: only 2 of 9 have full persona-grounded drafts (Financial
  Services — persona "Priya," Director of Marketing Technology &
  Operations at a regional bank, FINRA/SEC compliance angle; Retail —
  persona "Jordan," Director of Marketing Operations, peak-season-
  readiness angle), per the content Artifact this task scopes from. The
  other 7 (Consumer Products, Energy & Commodities, Public Sector, Health,
  Telecom/Media/Tech, Transportation & Mobility, Travel & Hospitality) are
  placeholders needing the same persona-plus-research authoring pass — this
  is real, non-trivial research/writing work per industry, not a
  fill-in-the-blank exercise, and should be resourced/estimated as such
  rather than folded into an engineering estimate.
  For `heroImageUrl` specifically: this part also owns sourcing an actual
  approved image per industry from Publicis Sapient's photo library (per
  the brief's explicit "approved asset library, not AI-generated, not
  generic stock" constraint) — an asset-sourcing dependency, not a writing
  one, and worth flagging separately since it may have a different owner/
  timeline than the copy itself.
- **System Component Impacted:** Content authoring via the GTM Content
  Manager app (`GTM_Page_Content__c`/`GTM_Page_Section__c` records,
  `industry-<key>` addressed, `industry-profile` templateType) — **not**
  an LWC/Apex code change. Landing the content should reuse this repo's
  existing idempotent seed-script convention (confirmed real prior art:
  issue #35's real body describes `scripts/data/seed-migration-accelerator-industry-variants.apex`'s
  "idempotent upsert-on-external-id pattern," `Section_Address__c`/
  `Content_Address__c` keyed) rather than 9 industries' worth of manual
  UI data entry per environment — so this part does produce one script
  artifact (Apex, following that existing pattern), even though its
  primary output is copy decks, not code logic.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO.**
- [ ] Altering Custom Metadata? **NO.**
- [ ] Introducing database fields? **NO** — rides entirely on part 3's
      field shape; if part 3's fields aren't finalized before this starts,
      this part is blocked, not free to guess a different shape.

## 3. Plan Acceptance Criteria

- **Success Metric:** all 9 industries have complete, non-generic,
  non-placeholder copy for every `IndustryProfile` field (existing +
  part 3's new ones); Financial Services and Retail match the already-
  drafted Priya/Jordan personas exactly as specified in the source content
  Artifact (no re-drafting of the 2 already-approved industries); the other
  7 read as equivalently researched (real industry pain points, plausible
  persona, no generic-consulting-speak — matching the voice checklist
  already named in the existing brand plan doc §5: no "leverage/innovate/
  holistic," first-person "we/you," real numbers not vague claims); the
  seed script is idempotent and re-runnable against both `gtm-staging` and
  (later, on the owner's go-ahead) `gtm-prod` without duplicating rows.
- **Target Test Target:** no Apex/Jest unit test is the primary gate here
  (this is content, not logic) — the existing content-contract verification
  tooling is the right check: `scripts/check-live-page-contract.mjs` and
  `scripts/check-page-order.mjs` (both confirmed to exist in `scripts/`),
  run against `gtm-staging` after the seed script, plus a manual Content
  Manager QA pass per industry (a human or QA-agent browser walkthrough,
  not a script, for tone/accuracy).
