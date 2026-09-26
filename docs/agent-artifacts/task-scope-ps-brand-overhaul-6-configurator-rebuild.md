# TASK SCOPE — ISSUE #ps-brand-overhaul-6-configurator-rebuild

> Part 6 of 7 in the `ps-brand-overhaul` initiative — the largest and
> highest-regression-risk part. Depends on part 2 (tokens/shapes/type) AND
> part 3 (content schema + Case/Task Apex) landing first. This part
> renders what part 3 defines; it does not define new Apex/schema itself
> beyond whatever call signature the new "Get in touch" LWC form needs from
> part 3's controller (Contract First — that signature belongs in part 3's
> doc/`docs/architecture/`, not invented here).

## 1. Requirements Breakdown

- **Target Objective:** Rebuild `gtmConfigurator`'s visual system (tokens,
  shapes, type, nav pattern, photography, cover-stack scroll effect) while
  preserving every one of its existing 9 narrative chapters and its full
  overlay-state surface, fixing one wrong-attribution string, and wiring
  in part 3's new content fields, per-industry hero imagery, and the
  client-accent theme — as **real, consumed** data, not hardcoded per-
  instance values. This is a full functional-wiring task, not a template
  refresh — every sub-item below states what "real" means concretely,
  per the coordinator's explicit mid-task correction.

  **Confirmed exact chapter/section inventory** (so "must not be dropped"
  is checkable, not vague): `grep -noE 'data-section="[a-z-]+"'
  gtmConfigurator.html` returns, in document order: `header`, `cover`,
  `partner`, `challenge`, `approach`, `proof`, `deliverables`, `engagement`,
  `why`, `closing`, `assistant`, `footer` — i.e. the 9 narrative chapters
  the brief names (`cover` through `closing`) plus three non-chapter
  `data-section`s (`header`, `assistant`, `footer`). Beyond those,
  confirmed overlay states that carry **no** `data-section` attribute at
  all and must be independently tracked so they aren't lost in the
  restyle: `class="chap readout-gate"` (line 102), the assistant dock
  (`class="asst-dock"`, line 486, wraps `<c-gtm-agent-bubble>`), the
  readout-view modal (`role="dialog" ... class="scrim"`, line 572), the
  password gate (`pw-btn`/`passwordGateChecking`, line 626), the rep-direct
  questionnaire path (`showRepDirectQuestionnaire`, lines 669-684, a
  parallel unbranded rendering of `c-gtm-assessment-questionnaire` for
  `Presentation_Stage__c = 'Rep_Direct'` records — see `gtmConfigurator.js:157-171`),
  and the access-blocked states (`id="access-blocked-login-prompt"`,
  `access-blocked-login-link`, `access-blocked-plain`, `access-check-failed`).
  QA's acceptance test for this part should walk this exact list, not a
  paraphrase of it.

- **Sub-item: brand tokens/shapes/type.** Apply part 2's shared module.
  `.cover` chapter hero panel gets the large double-notch treatment (the
  single highest-visual-impact change, per the existing plan doc, since
  it's the first full-screen moment a prospect sees); `band`-class chapters
  (`challenge`, `proof`, `engagement`, `closing`) get one notched panel
  each, sparingly, not every card; overlay/modal chrome (`readout-gate`,
  `asst-dock`, `scrim`, password gate, access-blocked states) stays plain
  rounded rects — functional UI, not brand storytelling, matching part 2's
  "don't notch everything" principle. `--teal`/`--good` and any gold usage
  (confirmed present in `gtmConfigurator.css` — the earlier, unmerged
  `ps-brand-configurator` scope doc's own audit found `#0e7c74`/`#2e7d5b`;
  Architect should re-grep `gtmConfigurator.css` directly rather than trust
  that audit's line numbers, since that doc predates this initiative's
  color spec) get re-homed as explicit `--ps-status-*` semantic tokens
  (functional, not brand-accent, colors) or removed — document the
  decision in code comments either way, matching this file's existing
  high-quality comment style.

- **Sub-item: wrong delivering-team attribution — confirmed, exact
  location.**
  ```
  $ grep -n "Marketing Automation practice" gtmConfigurator.js
  1355: || 'Migration Accelerator, prepared with the Publicis Sapient Marketing Automation practice.';
  ```
  Fix to "Salesforce Practice" (per
  https://www.publicissapient.com/partners/salesforce, the actual
  delivering team). This is the **only** hit for this exact phrase
  anywhere in `force-app/`/`docs/` (checked both directories) — no sibling
  instances found elsewhere in the codebase for this task to also fix.

- **Sub-item: nav pattern — confirmed net new.** `grep -n
  "IntersectionObserver|scrollY|sticky|navHidden|subNav" gtmConfigurator.js`
  shows `IntersectionObserver` already in use, but only for the
  interaction/dwell-tracking "sitemap" (section-view attribution, lines
  ~1912/2121) — there is no existing hide-on-scroll main nav or sticky
  sub-nav pill-tab bar. Build both as described in the brief, and **reuse**
  the existing `IntersectionObserver` section-tracking instance for the
  sub-nav's active-tab highlighting rather than standing up a second
  observer — the sections it already watches are the same `data-section`
  elements the sub-nav would jump to.

- **Sub-item: cover-stack scroll effect and duotone photography.** Net new
  (confirmed no `position: sticky`-driven stacking or `mix-blend-mode`
  duotone treatment exists in `gtmConfigurator.css` today beyond this
  BA pass's non-exhaustive check — Architect to confirm before assuming a
  clean slate). Progressive enhancement via `animation-timeline: view()`,
  degrading gracefully, per the brief.

- **Sub-item: client-accent theming must consume real data — confirmed
  gap, this is the coordinator's correction's central finding for this
  part.** A per-link accent color is already captured today — three real,
  live call sites:
  ```
  $ grep -n "this\.accent\s*=" gtmConfigurator.js
  712: if (accentParam) this.accent = accentParam;        (URL ?accent= param)
  827: if (saved.ACCENT) this.accent = saved.ACCENT;      (saved Config_Payload__c)
  1488: this.accent = event.detail.value;                 (Customize panel color picker)
  ```
  But it is **never applied to any rendered CSS** — confirmed:
  `grep -n "accent" gtmConfigurator.css` finds only a plain `.accent`
  utility class (colored inline text span, e.g. the "an afternoon."
  span in the cover headline) and `.proof-foot .accent`, neither of which
  reads `this.accent`'s value; there is no `template.host.style.setProperty`,
  no inline `style=` binding keyed off `accent`, anywhere in
  `gtmConfigurator.js`/`.html`. So today, a rep can pick a client brand
  color in the wizard, it gets saved, it gets read back into `this.accent`
  on load — and then nothing happens with it. This is exactly the "hardcoded
  per-instance values" failure mode the coordinator flagged, already
  present before this redesign even starts, not something the redesign
  would newly introduce — but the redesign must not carry it forward. This
  part's Definition of Done includes **actually wiring `this.accent` into
  a live CSS custom property override** (e.g. an inline
  `style="--ps-red: {accentStyleValue}"` on the component's root element,
  computed via a getter, following the same one-time-per-render-cycle
  discipline the component already uses elsewhere) so the Retail/PS-red and
  Financial-Services/client-blue example themes in the mockup are two
  renders of one real mechanism, not two hand-built one-off states. The
  `@api accentColor` property (line 75, already marked `// deprecated`)
  should be formally removed as part of this work, not left as dead,
  confusing surface area alongside the real mechanism.
  **Logo-misuse guardrail** (from the brief, must not regress): whatever
  mechanism applies `this.accent` must **not** touch the "Sapient" wordmark
  color — that stays hardcoded `--ps-red` regardless of client theme.
  Confirm the wordmark markup/CSS selector is not accidentally scoped
  under whatever wrapper the new accent override applies to.

- **Sub-item: hero image must consume real per-industry data.** Depends on
  part 3's `heroImageUrl` field (or whatever mechanism the Architect
  accepts there). No hardcoded per-instance image; the duotone
  `mix-blend-mode: multiply` tint recolors automatically per the accent
  variable above, so only the grayscale source image itself needs to vary
  by industry, not a separately-tinted asset per industry per theme.

- **Sub-item: new content fields render in their chapters.** `partnerLine`/
  `approachLine`/`engagementLine`/`closingLine` as pull-quotes in chapters
  01/03/06/08 respectively; `deliverableExtra` as a 5th card in chapter 05
  alongside the existing 4 (confirmed today's chapter-05 `deliverables`
  content is generic/offering-level, not industry-varied — this is a net
  new per-industry addition, not a modification of existing cards);
  `assetCount`/`healthScore`/`dependencyCount` feed the existing
  `numberFrom('ASSET_COUNT', 4128)` etc. call sites (`gtmConfigurator.js:1395-1397`)
  ahead of the generic CMS-token tier, per part 3's three-tier resolution
  design.

- **Sub-item: "Get in touch" form is real, not a static mockup.** New LWC
  markup/JS in `gtmConfigurator` (or a small new child component) calling
  part 3's guest-callable Apex method imperatively, with real loading/
  success/error states — not a form that only looks wired. "Book an
  environment assessment" is **not** new work here: verify/preserve the
  existing `handleOpenBooking` → `c-gtm-assessment-questionnaire` wiring
  through every markup change in this part (regression risk, not a build
  task — see part 3's evidence that this route is already real and live).

- **System Component Impacted:** LWC (`gtmConfigurator.css/.js/.html` —
  confirmed sizes: 2176 lines JS, largest of the four components), plus
  whatever new small child component the "Get in touch" form needs.
  Consumes Apex from part 3 (no new Apex of its own beyond wiring an
  imperative call).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **Partially, visual-only.** The GUS
      chat launcher's markup/CSS (`<c-gtm-agent-bubble>`, the assistant
      dock `.asst-dock`) gets the token/color pass like everything else.
      No Apex-backed GUS tool logic changes, no DML — the zero-DML rule in
      AGENTS.md §1 is not triggered by this part.
- [ ] Altering Custom Metadata? **NO.**
- [ ] Introducing database fields? **NO new fields from this part directly**
      (consumes part 3's); if the "Get in touch" form's Apex signature
      needs anything part 3 didn't anticipate, that's a part-3 doc
      amendment, not a new field introduced silently here.

## 3. Plan Acceptance Criteria

- **Success Metric:** every chapter and overlay state enumerated in §1
  renders with zero regressions — the existing
  `gtmConfigurator.readout.test.js` suite (cited in `docs/backlog.md`'s
  ADR-0008 resolution as covering the recipient state machine, resubmit
  guard, and button-flip behavior) stays green unmodified in behavior
  (assertion updates for new class names/tokens are fine; behavior
  assertions must not need to change); tokens/shapes/fonts/nav
  pattern/cover-stack/duotone all present and correct; wrong attribution
  fixed at the one confirmed location; `this.accent` demonstrably drives a
  real rendered color change (QA test: set two different saved
  configurations with two different accent values, screenshot both, colors
  differ and the wordmark does not); hero image varies by industry; new
  content fields render in their chapters; "Get in touch" creates a real
  Case+Task in a `gtm-staging` smoke test; "Get an environment assessment"
  still opens the unmodified assessment questionnaire.
- **Target Test Target:** `lwc/gtmConfigurator/__tests__/gtmConfigurator.brand.test.js`
  (rewritten per part 2), `gtmConfigurator.readout.test.js` (regression,
  must stay green), new tests for the accent-theming getter and the "Get in
  touch" form, `lwc/gtmReadoutView/__tests__/gtmReadoutDesign.test.js` if
  part 5's read-through assigns it here instead.
