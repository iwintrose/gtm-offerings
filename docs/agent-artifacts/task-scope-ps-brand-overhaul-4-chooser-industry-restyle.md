# TASK SCOPE — ISSUE #ps-brand-overhaul-4-chooser-industry-restyle

> Part 4 of 7 in the `ps-brand-overhaul` initiative. Depends on part 2
> (`ps-brand-overhaul-2-brand-tokens-shapes-type`) landing first. No
> dependency on part 1 or part 3 — this component has no per-industry
> scalar content fields and no client-accent theming (see §1, non-goals).

## 1. Requirements Breakdown

- **Target Objective:** Apply the shared brand tokens/shapes/type from
  part 2 to `offeringChooser` and `chooseIndustry`, restyling both from
  today's drifted palette/type to the correct 04.2026 system. Both
  components are confirmed structurally near-identical — same `.bar`
  (wordmark) / `.wrap` (eyebrow+h1+sub) / `.grid` of `.tile` cards /
  `footer.pf` skeleton, same drifted variable names at matching line
  numbers in both files (`--accent: #E90024` at lines 30/53/68/82 in both
  `offeringChooser.css` and `chooseIndustry.css`) — so this is genuinely
  one unit of restyling work, not two coincidentally-similar ones.
  Concrete per-view changes:
  - `--accent` (and any local alias) → `var(--ps-red)` (`#e90130`).
  - `.oc-root`/`.ci-root` font stack (`'Inter', -apple-system, 'Segoe UI',
    sans-serif`) → `var(--ps-font-body)`; `.mono`-classed elements
    (`'IBM Plex Mono', ui-monospace, monospace`, confirmed at
    `chooseIndustry.css:93,118,174,258,331` and matching lines in
    `offeringChooser.css`) → `var(--ps-font-mono)`; headline elements →
    `var(--ps-font-display)`.
  - `.tile` (currently plain `border-radius: 14px`) gets the
    `.ps-notched--tr` utility from part 2; `.tile-mark` gets a smaller
    matching notch variant.
  - CTA affordance (`.tile-go`, "Explore this offering →") stays a
    text/link treatment, not a red-filled button — matches both
    `gtmStory`'s existing "red is not a primary CTA color" doctrine and
    the live publicissapient.com pattern the brief cites. `.tile-accent-bar`
    (a decorative stripe, not a button) may legitimately stay `--ps-red`.
  - Both components today inject their font `<link>` imperatively in
    `connectedCallback` (`data-gtm-fonts="1"` href pointed at Inter) — swap
    the href to the shared Lexend Deca/Roboto/Roboto Mono URL string
    (copy `gtmStory.js`'s existing string verbatim so the browser reuses
    one cached font request across all four components on the same page
    load).
  **Open design question, not decided here** (flagged in the existing plan
  doc, re-confirmed, not resolved by this BA pass): should `chooseIndustry`
  tiles get a visually distinguishing notch/treatment from `offeringChooser`
  tiles, to help a user subconsciously track "which step of the flow am I
  on"? No existing convention answers this either way — Architect/design
  call.
- **System Component Impacted:** LWC only (`offeringChooser.css/.js`,
  `chooseIndustry.css/.js`, plus their respective `__tests__`). No Apex, no
  schema — this component reads only pre-existing `industry-tile`/offering
  content, already fully wired.
- **Non-goal, explicitly:** no client-accent theming and no per-industry
  scalar content fields apply here (those are `gtmConfigurator`-only
  concerns, per the brief's own framing: these two components "stay in the
  fixed PS visual system"). The coordinator's mid-task correction about
  "consume real data, not hardcoded per-instance values" is a
  `gtmConfigurator`-specific concern (part 6) — noting explicitly that I
  considered it here and it doesn't change this part's scope, since
  neither of these two components has an instance-specific theme today or
  in the mockup.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO.**
- [ ] Altering Custom Metadata? **NO.**
- [ ] Introducing database fields? **NO.**

## 3. Plan Acceptance Criteria

- **Success Metric:** both components render with correct tokens/fonts/
  notches at the two live routes that already exist and are reachable
  today (`force-app/main/default/experiences/GTM1/views/offeringChooser.json`
  and `.../industry.json` — both confirmed present, so this is a genuine
  live-guest-facing regression surface, not a preview-only one); zero
  `#E90024`/`Inter`/`IBM Plex Mono` remaining in either file; focus rings
  on notched `<a class="tile">` elements are not visually clipped by
  `clip-path` (QA to verify visually, per the shape system's own
  accessibility note); QA validates live in the browser at multiple
  viewport widths, per this project's standing QA convention, not just via
  Jest.
- **Target Test Target:** `lwc/offeringChooser/__tests__/offeringChooser.brand.test.js`
  and `lwc/chooseIndustry/__tests__/chooseIndustry.brand.test.js` (both
  from part 2), plus existing `offeringChooser.test.js`/`chooseIndustry.test.js`
  regression (must stay green — no IA/behavior change, styling only).
