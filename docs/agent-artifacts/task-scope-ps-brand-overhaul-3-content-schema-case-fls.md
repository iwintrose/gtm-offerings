# TASK SCOPE — ISSUE #ps-brand-overhaul-3-content-schema-case-fls

> Part 3 of 7 in the `ps-brand-overhaul` initiative. Depends on part 1
> (`ps-brand-overhaul-1-default-industry-key`) landing first, or explicitly
> documents the temporary fallback if sequenced after it (see §1). Feeds
> part 6 (`ps-brand-overhaul-6-configurator-rebuild`), which renders these
> fields, and part 7 (`ps-brand-overhaul-7-industry-content-authoring`),
> which writes the real per-industry copy into them.

## 1. Requirements Breakdown

- **Target Objective, part A — new per-industry content fields.** Add to
  `GtmPageContentReader.IndustryProfile` (`force-app/main/default/classes/GtmPageContentReader.cls:396-410`,
  currently: `industryKey, industryLabel, pickerBlurb, coverSub, problem,
  useCase, solution, uniquePoints[], proofLine, whyLine, whyHead, demoRoot,
  demoDeps[]`) six new fields: `partnerLine`, `approachLine`,
  `deliverableExtra` (`{title, body}`), `engagementLine`, `closingLine`
  (all pull-quotes/a 5th card for `gtmConfigurator`'s chapters 01/03/05/06/08),
  and three integers — `assetCount`, `healthScore`, `dependencyCount` —
  that make the section-04 live-demo gauge's numbers real per-industry data
  instead of one universal fallback. Confirmed today's actual mechanism,
  not assumed:
  ```
  $ grep -n "numberFrom\|ASSET_COUNT\|DEPENDENCY_COUNT\|HEALTH_SCORE" gtmConfigurator.js
  1395: const assets = this.numberFrom('ASSET_COUNT', 4128);
  1396: const deps   = this.numberFrom('DEPENDENCY_COUNT', 9640);
  1397: const health = this.numberFrom('HEALTH_SCORE', 62);
  2048: numberFrom(key, fallback) {
  2049:   const parsed = parseFloat(this.tokenValue(key).replace(/[^0-9.]/g, ''));
  2050:   return isNaN(parsed) ? fallback : Math.round(parsed);
  2051: }
  ```
  So 4128/62/9640 are **JS fallback literals** inside a generic three-tier
  CMS-token resolver (`numberFrom`/`tokenValue`), not unconditionally
  hardcoded — but there is no per-*industry* override today, only one
  generic override path shared by every industry. This task adds the
  per-industry layer on top: `IndustryProfile.assetCount` etc. take
  priority over the generic token when an industry is selected, falling
  through to the existing `numberFrom` fallback only when neither exists.

- **Target Objective, part A2 — these fields must be real, authorable
  content, not just an Apex/LWC data contract.** (Coordinator correction,
  addressed explicitly, not left implicit.) Confirmed the actual mechanism
  that makes `coverSub`/`problem`/etc. editable today, so the new fields
  can be wired the same way rather than needing new editor UI:
  ```
  $ grep -n "'industry-profile'" gtmPageLayouts.js
  102: 'industry-profile': {
  103:     text: ['whyHead', 'demoRoot'],
  104:     rich: ['coverSub', 'problem', 'useCase', 'solution', 'proofLine', 'whyLine'],
  105:     json: ['uniquePoints', 'demoDeps']
  106: }
  ```
  This `text`/`rich`/`json` registry (part of a larger `FIELD_TYPES`-shaped
  const covering every layout in the app, e.g. `chapter-proof`,
  `industry-tile`, at neighboring lines 75-106) is what
  `gtmFieldEditor.js`/the Content Manager's generic section editor reads to
  decide what input control to render for each field key — it is the
  *entire* mechanism, already proven, already working for a
  non-engineer editor today. This task's Definition of Done explicitly
  includes:
  1. Registering `partnerLine`, `approachLine`, `engagementLine`,
     `closingLine` into the `rich` (or `text` — Architect's call on which
     reads better as a single-line pull-quote vs. rich block) array of
     `industry-profile`.
  2. `deliverableExtra` (`{title, body}`) does not fit the existing
     `text`/`rich`/`json` taxonomy cleanly — `json` today renders a
     repeatable *array of strings* (`uniquePoints`, `demoDeps`), not an
     object with named sub-fields. **Recommend**: flatten to two ordinary
     scalar fields, `deliverableExtraTitle` (text) and `deliverableExtraBody`
     (rich), assembled into `{title, body}` only at the Apex
     `IndustryProfile` boundary. This needs **zero** `gtmFieldEditor.js`
     changes — it reuses the existing editor exactly as-is. Flag the
     alternative (a real object-shaped JSON editor) as a larger, editor-
     code-touching option the Architect can choose instead, not the
     default.
  3. `assetCount`/`healthScore`/`dependencyCount` are integers, and there
     is no numeric field-type bucket in this registry today (only
     `text`/`rich`/`json`). **Recommend**: store them as `text` fields
     (free-text input) and parse/coerce to a number in Apex using the
     exact same pattern already proven at `gtmConfigurator.js:2048-2051`
     (`parseFloat(...).replace(/[^0-9.]/g, '')`, ported server-side or kept
     client-side as today) — this is the lowest-risk option and needs zero
     editor UI changes. Flag the alternative (a real number-input field
     type added to `gtmFieldEditor.js`) as a nice-to-have the Architect can
     choose to invest in instead.
  4. `scripts/check-configurator-bindings.mjs` (confirmed to exist) is
     described, in `gtmConfiguratorCopy.js`'s own header comment — see note
     below — as asserting that chapter field order and editor-rail order
     agree; it must be updated for any new field key this task adds, or it
     will start failing CI for a reason unrelated to its actual purpose.

- **Target Objective, part A3 — hero image, industry-configurable.** The
  visual spec (part of the coordinator's brief, and repeated in the
  coordinator's mid-task correction: "the approved photo library" must be
  "real data," not hardcoded) asks for a per-industry hero image; the
  content-schema spec's field list (§ above) does **not** include an image
  field at all. This is a real gap between the two source Artifacts that I
  am reconciling here, not silently picking a side on: **recommend** adding
  a seventh new field, `heroImageUrl` (text — a Static Resource name or
  external asset URL, editable via the exact same `text`-bucket mechanism
  as everything else above), rather than a naming-convention-only lookup
  (e.g. "look up a static resource named after the industry key" with no
  stored field) — a convention-only approach would still leave a non-
  engineer unable to change which image an industry uses without a
  metadata deploy, which fails the coordinator's "actually editable by a
  content author" bar. Flag for Architect confirmation, since it's my
  addition to the field list, not something either source Artifact
  specified outright.

- **Target Objective, part B — "Get in touch" Case + Task.** A guest on
  `gtmConfigurator` needs a lightweight contact/question path, distinct
  from the full scored assessment. Confirmed this does **not** exist today
  in any form — `grep -n "Get in touch\|gtmContactEngagement"
  gtmConfigurator.html gtmConfigurator.js` returns nothing. (`gtmContactEngagement`
  is a real, different LWC — the internal, rep-facing "Engagement Links"
  tab, currently slated for retirement per open issue #31 "Retire
  'Engagement Links' tab..." — do not confuse the two; nothing here reuses
  or touches that component.) New work: a guest-callable Apex method
  creates a `Case` (a new Record Type — exact API name TBD, Architect
  decision; brief calls it "GTM-Inquiry-flavored" — `Origin = 'Web'`) and a
  `Task` on the related Opportunity/Contact.

  For the Task, reuse the already-proven, already-live pattern rather than
  inventing a new one:
  ```
  $ grep -n "WhatId\|Subject" GtmLifecycleNotificationService.cls
  12: * on GTM_Readout__c/GTM_Assessment_Request__c. Instead, Task.WhatId points
  17: * Subject is therefore a LOAD-BEARING EXACT-MATCH KEY, not display text.
  ```
  `Task.WhatId` → Account/Contact/Opportunity, with a per-stage constant
  `Subject` as the exact-match open/close key. Issue #31 (open, unrelated
  feature — "fire real Tasks for engagement follow-ups," reuses this same
  service) is independent prior art confirming this is the house style, not
  something to duplicate. New Task-firing for "Get in touch" should extend
  `GtmLifecycleNotificationService` with a new Subject constant, not build
  a second Task-creation mechanism.

  Separately, the **existing** "Book an environment assessment" CTA is
  **not** new work and must not be treated as a placeholder to build from
  scratch — confirmed live and wired today:
  ```
  $ grep -n "handleOpenBooking\|environment assessment" gtmConfigurator.html
  66:  <button class="cta" onclick={handleOpenBooking}>
  67:    <span class="cta-long">Get an</span>environment assessment →
  438: <button class="cta" onclick={handleOpenBooking}>{chClosing.ctaLabel}</button>
  450: Thanks — your environment assessment request is with our team.
  ```
  and per `docs/backlog.md` ADR-0008, `handleOpenBooking` opens
  `c-gtm-assessment-questionnaire` inline — the real, scored, submission-
  producing assessment flow (`gtmConfigBooking`, the old separate booking
  component, was already retired). Part 6 must verify/preserve this
  wiring through the redesign, not re-invent a "booking modal." The two
  flows map to genuinely different backends, exactly as the brief states:
  assessment submission → `GtmAssessmentRequestController` (existing,
  unchanged); "Get in touch" → the new Case/Task Apex this part defines.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **Verify, don't assume no.** Check
      whether `GtmAgentGetConfigState` (the config tool surface Gus reads)
      needs the new `IndustryProfile` fields added to whatever allow-list
      it exposes to Gus's context — a read-only concern, no DML risk
      either way, but worth an explicit Architect check rather than a
      silent gap. The new Case/Task Apex is **not** a GUS tool surface at
      all (no tool registration, no `GtmAgentToolSurface` implementation
      implied) — it's a plain guest-callable controller, same shape as
      `GtmAssessmentRequestController`.
- [ ] Altering Custom Metadata? **NO.** `GTM_Page_Content__c`/
      `GTM_Page_Section__c` are ordinary objects; the new Case Record Type
      is standard-object metadata, not `GTM_Assessment_*` CMDT.
- [ ] Introducing database fields? **YES — Permission Set mapping is
      mandatory**, per `CLAUDE.md` §6, and there is a live, same-night
      precedent to follow exactly. Confirmed via the actual uncommitted
      diff sitting in this repo's main working tree as of this scoping
      pass (2026-09-26):
      ```
      GTM_Offering_Admin.permissionset-meta.xml (+11 lines):
        <fieldPermissions><field>Case.Readout__c</field>
          <readable>true</readable><editable>true</editable></fieldPermissions>
        comment: "A freshly-deployed custom field grants zero FLS to any
        profile/permission set by default (verified live 2026-09-26)..."
      GTM_Offering_User.permissionset-meta.xml: same field, editable=false
        (read-only for reps), same comment, referencing "the whole 'field
        doesn't exist' saga."
      ```
      This is a **different** Case field (`Readout__c`, backing the
      readout-review-Case thread) added for a **different** reason
      (tonight's live incident, see next paragraph) — but it is the exact
      same class of change this task needs for the new "GTM-Inquiry" Case
      Record Type and any new Case fields it needs, and it was added to
      `GTM_Offering_Admin`/`GTM_Offering_User` **only** — not to
      `GTM_Guest`. This confirms, from a live same-session example rather
      than just doc prose, the pattern this task must follow: rep-facing
      permission sets get explicit FLS grants (and, for a new Record Type,
      `recordTypeVisibilities` entries) on every new field/RT; the guest
      permission set gets none. Confirmed independently via
      `docs/architecture/overview.md`'s stated doctrine ("`GTM_Assessment_Guest`/
      `GTM_Story_Guest` grant no object or field permission on
      `GTM_Readout__c` or `Case`... access is class-level only") and via a
      direct query of the live file: `grep -c "Case"
      GTM_Guest.permissionset-meta.xml` → `0`. The new "Get in touch" Apex
      must run the same `without sharing`/system-mode pattern as
      `GtmReadoutController.fileReviewCase`/`GtmAssessmentRequestController`
      — no guest Case object/field grants, ever, on this object, in this org.
      (Note, for completeness, that `GTM_Guest` *does* carry real
      `allowCreate=true` object permissions on `Task`/`Contact`/`Opportunity`
      today, for pre-existing reasons unrelated to this task — Architect
      should confirm whether the new Task insert can run guest-side
      directly given that existing grant, or should also go through
      system-mode Apex for consistency with the Case-object doctrine above;
      flagging as an open decision, not presuming either answer.)

  **A must-check, not optional, dependency:** open issue **#38** ("Add
  Setup checklist detectors: Agentforce credential configured, known
  demo-org automation blocking Case," filed today) documents that a
  pre-existing demo-org flow, `SDO_Service_Case_Creation` ("SDO Service -
  Case - On Create"), was silently blocking **every** Case insert in
  `gtm-staging` tonight with `CANNOT_EXECUTE_FLOW_TRIGGER` — swallowed into
  a `System.debug` by `GtmReadoutController.fileReviewCase`'s try/catch,
  invisible to any user. It has been deactivated in `gtm-staging` for now,
  but #38 is the only place tracking making that permanent/detectable. The
  new "Get in touch" Case-insert path will hit the **exact same** Case
  object and is exposed to the exact same failure mode. The Architect/QA
  for this task must re-verify `SDO_Service_Case_Creation` (and sibling
  `SELECT Label FROM FlowDefinitionView WHERE Label LIKE '%SDO%' AND
  IsActive = true` results) are still inactive in `gtm-staging` before any
  real submission test, and should not assume issue #38 landing first
  makes this permanent — cross-check at QA time regardless of #38's status.

## 3. Plan Acceptance Criteria

- **Success Metric:** `IndustryProfile` returns all 7 new fields (or 8,
  including `heroImageUrl` if the Architect accepts §1's recommendation);
  every one of them is settable through the real Content Manager UI by a
  `GTM_Content_Manager` user with no engineering involvement (this is the
  literal acceptance bar for the coordinator's correction — test it by
  having QA, not just a script, open the Content Manager and edit one of
  each new field type); a "Get in touch" submission creates a real `Case`
  (correct Record Type, `Origin = 'Web'`) and a `Task` on the related
  Contact/Opportunity with a load-bearing exact-match `Subject`; all 5
  permission sets carry correct grants, with `GTM_Guest` excluded from any
  Case object/field permission; a `gtm-staging` validate-only deploy plus a
  live SDO-flow re-check both pass before any real Case-insert smoke test;
  the existing "Get an environment assessment" CTA still opens the
  unmodified `gtmAssessmentQuestionnaire` flow (regression-checked, not
  just left alone and assumed fine).
- **Target Test Target:** new Apex test class for the "Get in touch"
  controller (name TBD, Architect phase); whichever existing test class
  covers `GtmPageContentReader.IndustryProfile` (confirm exact name in
  Architect phase); `GtmLifecycleNotificationServiceTest.cls` (existing —
  extend for the new Subject constant); `gtmConfigurator.readout.test.js`
  (existing regression suite — must stay green, confirms the assessment
  flow is untouched).
