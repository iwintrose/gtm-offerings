# TASK SCOPE — ISSUE #ps-brand-overhaul-1-default-industry-key

> Part 1 of 7 in the `ps-brand-overhaul` initiative (PS 04.2026 brand redesign
> of `offeringChooser`/`chooseIndustry`/`gtmStory`/`gtmConfigurator` +
> industry-personalization content fields). This part is the smallest and is
> a sequencing prerequisite for part 3 (`ps-brand-overhaul-3-content-schema-case-fls`).
> Siblings: `ps-brand-overhaul-2-brand-tokens-shapes-type`,
> `ps-brand-overhaul-3-content-schema-case-fls`,
> `ps-brand-overhaul-4-chooser-industry-restyle`,
> `ps-brand-overhaul-5-story-restyle`, `ps-brand-overhaul-6-configurator-rebuild`,
> `ps-brand-overhaul-7-industry-content-authoring`.

## 0. Correction to the coordinator's brief — read before scoping this further

The coordinator's brief cites this decision ("the industry-personalization
'Default'/no-industry-selected state should become a first-class
`Industry_Key__c` row... decided in principle by the user, coordinated
between 'gtm-offerings-a1' and 'gtm-industry-content-variants'") as **"Issue
#35."** I checked this directly rather than taking the citation at face
value, per this repo's own evidence-first convention:

```
$ gh issue view 35
title: Author base content for Migration Accelerator's Story page (currently 100% hardcoded JS fallback)
state:  OPEN
...
## Finding
Zero rows exist in `GTM_Page_Section__c`/`GTM_Page_Content__c` for
`migration-accelerator`'s `story` template — confirmed live via direct SOQL
against gtm-staging (2026-09-26). Every section on the Migration Accelerator
Story page ... renders exclusively from the hardcoded `DEFAULTS`/
`SECTION_FALLBACKS` objects in `gtmStory.js`...
## Scope
Port the existing hardcoded copy in gtmStory.js's DEFAULTS/SECTION_FALLBACKS
into real GTM_Page_Section__c/GTM_Page_Content__c rows for
migration-accelerator's story template, covering all 11 sections, with **no
Industry_Key__c**/Base_Section_Key__c (these are the generic/base rows the
variant rows are meant to override)...
```

The real, filed GitHub issue #35 is about authoring `gtmStory`'s 11
base (non-industry) sections — a different component, a different content
gap, and (notably) it explicitly perpetuates a **blank** `Industry_Key__c`
as "the base/default row," which is the exact opposite of what this task's
brief says was decided. I also ran `gh issue list --state all --limit 300`
and `gh issue list --search "Industry_Key"` / `"Default row"` across every
issue in the tracker (1–38) — nothing else matches the "Default" row
decision described in the brief either. **There is no filed issue backing
this decision.** Per my role's instructions, I'm not guessing an answer
here: I'm proceeding to scope the work itself, since the brief states it
was decided in principle and asks me to proceed on that assumption, but the
Architect/coordinator should either (a) file a real issue for this decision
and stop citing #35 for it, or (b) confirm the decision was made verbally/
elsewhere and accept this doc as its first written record.

## 1. Requirements Breakdown

- **Target Objective:** Today, a viewer with no industry selected (or an
  `Industry_Key__c` that resolves to nothing) is handled by a **null-key
  special case** in the read path, not a real row — confirmed:
  `gtmConfigurator.js`'s industry-scoped getters all read
  `this.industry ? this.industry.coverSub : ''` (same pattern at
  `coverSub`/`problem`/`useCase`/`solution`/`proofLine`/`whyLine`/`whyHead`/
  `demoRoot`/`uniquePoints` — `force-app/main/default/lwc/gtmConfigurator/gtmConfigurator.js:1304-1369`),
  i.e. "no industry" today means an **empty string**, not a real fallback
  authored anywhere. The objective is to replace that empty-string special
  case with a real `Industry_Key__c = 'Default'` `GTM_Page_Section__c`/
  `GTM_Page_Content__c` row (framework's `industry-tile` pattern already
  proves the mechanism — see `GtmPageContentReader.cls:396-440`'s
  `IndustryProfile` class and its surrounding comment on the
  `industry-<key>` addressing convention), so a real Content Manager author
  can set sensible fallback copy for "no industry picked" the same way they
  set copy for any real industry, and so part 3's new fields
  (`partnerLine`, `approachLine`, etc.) have a real row to attach a
  fallback to instead of a second, parallel empty-string special case.
- **System Component Impacted:** Apex (`GtmPageContentReader`'s industry
  resolution/query path — needs to decide whether "Default" is excluded
  from any user-facing "pick an industry" list while still resolving as
  the fallback join target) + LWC (`gtmConfigurator.js`'s
  `?industry ? this.industry.X : ''` getters become `this.industry ?? this.defaultIndustry`-style
  resolution, or equivalent — exact mechanism is an Architect call) + one
  new Content Manager data row (`Industry_Key__c = 'Default'`), not a
  schema change (see §2).

**Ambiguity flagged, not decided here:** whether `industryKey: 'Default'`
should be a reserved, code-recognized literal (a magic string the Apex/LWC
both special-case for "this is the fallback row," distinct from a normal
industry) or genuinely just another ordinary industry row that happens to
be first/unassigned in the UI. I did not find any existing convention in
this codebase for a reserved "Default" taxonomy value to model this on —
the closest analogue, `GTM_Assessment_Config.Default` (a customMetadata
record literally named `Default`, per `docs/backlog.md`'s Stage 2 notes),
is a different mechanism (CMDT record name, not a picklist/text field
value) and shouldn't be assumed to generalize here. Architect should decide
and document the exact resolution order (is "Default" tried only when no
industry is selected, or also when a selected industry has no row of its
own — i.e. does it double as a per-field fallback within a real industry's
sparse row?) before implementation.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **Verify, don't assume no.**
  `GtmAgentGetConfigState`'s `availableIndustries` list (the same field
  `GTM_Guest`-reachable `GtmAgentGetConfigState` exposes to Gus, and the
  same shape issue #19 already found buggy once — "GUS availableIndustries
  leaks Draft industries," open, unresolved) needs to explicitly exclude
  the new `Default` row from any list Gus or a human industry-picker
  renders as a *choice*, while still allowing it to resolve as a fallback.
  No DML is introduced by this work either way — this is a read-path/
  filter change, so the zero-DML rule in AGENTS.md §1 is not at risk, but
  the filter-gap pattern issue #19 already documents is exactly the kind
  of bug this change could reintroduce if the "Default" row isn't
  explicitly excluded from picker-facing queries.
- [ ] Altering Custom Metadata? **NO.** `GTM_Page_Section__c`/
      `GTM_Page_Content__c` are ordinary custom objects, not
      `GTM_Assessment_*` CMDT — the "don't hand-edit generated XML" rule
      does not apply to this work.
- [ ] Introducing database fields? **NO.** `Industry_Key__c` already exists
      as a plain `Text(80)`, not-required, not-unique field on both objects
      (`force-app/main/default/objects/GTM_Page_Content__c/fields/Industry_Key__c.field-meta.xml`,
      same on `GTM_Page_Section__c`) — this is a new **data row** with that
      field set to the literal string `Default`, not a new field. No
      Permission Set mapping is triggered by this task on its own (no new
      field/object); Content Manager roles already have standing access to
      these two objects.

## 3. Plan Acceptance Criteria

- **Success Metric:** A configurator or chooseIndustry render with no
  industry resolved reads its copy from a real, Content-Manager-editable
  `Industry_Key__c = 'Default'` row instead of an empty string; existing
  behavior for every currently-working real industry selection is
  byte-for-byte unchanged (regression, not a rewrite); the new row is
  excluded from any user/Gus-facing "choose an industry" list.
- **Target Test Target:** Apex — whichever existing test class covers
  `GtmPageContentReader.getIndustryProfiles`/the industry resolution path
  (exact class name to be confirmed by the Architect; not conclusively
  identified in this BA pass — grep `IndustryProfile` across
  `force-app/main/default/classes/*Test.cls` first). LWC —
  `lwc/gtmConfigurator/__tests__/` and `lwc/chooseIndustry/__tests__/
  chooseIndustry.test.js` (confirmed to exist) specs covering industry
  resolution/fallback behavior.
