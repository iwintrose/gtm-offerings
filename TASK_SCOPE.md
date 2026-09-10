# TASK SCOPE — ISSUE #18

## 1. Requirements Breakdown

- **Target Objective:** Produce a written decision — migrate, don't
  migrate, or migrate a subset — on moving GTM Offerings' page/story
  content (currently `GTM_Page_Content__c` / `GTM_Page_Section__c`,
  authored via `gtmContentManager`, read via `GtmPageContentController` /
  `GtmPageContentReader`) to Contentful, a headless CMS. **This is an
  exploratory/research issue.** The deliverable is a decision document and,
  if migrating, a plan — not a working integration. No code should be
  written against this issue without a separate follow-up issue scoping
  the actual implementation.
- **System Component Impacted:**
  - `force-app/main/default/lwc/gtmContentManager/` — the in-org content
    authoring UI; a decision to migrate changes or replaces this.
  - `GtmPageContentController.cls` / `GtmPageContentReader.cls` — the read
    path both the guest Experience Cloud site and the internal app use
    today.
  - `GTM_Page_Content__c` / `GTM_Page_Section__c` — the current storage;
    real, live content exists here today (per `docs/backlog.md`'s D-series
    offering-content entries) that would need a migration plan, not a
    greenfield schema.
  - Explicitly OUT of scope, per the issue itself: the assessment
    instrument (`migration-accelerator/instrument/`, CMDT — separate
    system, tracked in issue #16) and GUS / readout tool surfaces
    (`AGENTS.md` §1).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? No — explicitly out of scope per the
      issue body.
- [ ] Altering Custom Metadata? Not for this issue's deliverable (a
      decision/plan). A follow-up implementation issue would need to
      answer this once the plan exists.
- [ ] Introducing database fields? Not for this issue's deliverable. A
      migration plan may propose schema changes, but none are made here.

## 3. Plan Acceptance Criteria

- **Success Metric:** A written decision plus, if migrating, a plan that
  concretely answers all six open questions in the issue: guest read-path
  auth/token exposure, per-offering Contentful content-type modeling,
  editing UX (proxy vs. leave-Salesforce), migration of existing live
  content, caching/outage behavior for the guest-facing site, and
  cost/procurement approval as a prerequisite separate from the technical
  plan. A plan that skips any of the six and calls itself complete does
  not meet this issue's acceptance bar.
- **Target Test Target:** N/A for this issue (no code change expected). If
  the plan proposes a spike/prototype, that becomes its own follow-up
  issue with its own test targets, not folded into this one.
