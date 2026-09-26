# TASK SCOPE — ISSUE #ps-brand-overhaul-5-story-restyle

> Part 5 of 7 in the `ps-brand-overhaul` initiative. Depends on part 2
> (`ps-brand-overhaul-2-brand-tokens-shapes-type`) landing first, but is a
> much smaller consumer of it than parts 4/6 — `gtmStory` is already
> token/type-correct.

## 1. Requirements Breakdown

- **Target Objective:** `gtmStory` needs **no** color or font remediation —
  confirmed (see part 2's evidence) it already carries the correct
  `--ps-red: #e90130` token block and Lexend Deca/Roboto/Roboto Mono, and
  its headline selectors genuinely consume `--ps-font-display` (9 confirmed
  usages, not just declared-and-unused). This part's scope is **shape-
  system-only**: apply the part-2 notch utility classes to `gtmStory`'s
  hero and section panels, and migrate its own local `:host` token block
  to *consume* the new shared `gtmBrandTokens` module instead of declaring
  its own copy — since `gtmStory.css` is literally the source the shared
  module is extracted from, this component becomes the first real proof
  that the extraction preserves byte-for-byte identical rendering.
  - Confirmed zero `clip-path`/notch usage anywhere in `gtmStory.css`
    today — this is genuinely new, not a variant of something existing.
  - Confirmed no wrong-attribution text in `gtmStory.js`/`.html` — the only
    "marketing automation" hits in this file are legitimate, generic
    industry-description copy ("Automatic, for any major marketing
    automation platform," "objects is where this offering's advantage is
    largest... migrating between major marketing automation platforms") —
    these describe the *prospect's* marketing-automation estate being
    migrated, not a mis-attribution of *who delivers* the offering. Do
    **not** touch this copy as part of any "Marketing Automation practice
    → Salesforce Practice" fix (that fix is scoped entirely in part 6,
    where the actual wrong attribution lives — see that doc).
  - Exact panel/selector targets for the notch treatment (hero container,
    quote blocks, inline story-section cards) were not enumerated in this
    BA pass beyond what the existing plan doc names generically ("hero and
    section panels... inline content cards/quote blocks") — Architect
    should confirm exact selectors against the live `gtmStory.html`
    structure before implementation, per that plan doc's own note that
    this wasn't yet isolated in detail.
- **System Component Impacted:** LWC only (`gtmStory.css`, minor
  `gtmStory.html` class additions for notch targeting). No Apex, no
  schema, no content change.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO.**
- [ ] Altering Custom Metadata? **NO.**
- [ ] Introducing database fields? **NO.**

## 3. Plan Acceptance Criteria

- **Success Metric:** `gtmStory`'s rendered colors/fonts are pixel-identical
  to today's (this is a refactor of *where* the tokens live, not a redesign
  of the component) after migrating to the shared `gtmBrandTokens` module;
  notch shapes appear on the specified panels at multiple viewport widths,
  including the narrow/phone-width case the plan doc flags as the one that
  broke a similar effort previously; existing `gtmStory.test.js` and
  `lwc/gtmStory/__tests__/preview.test.js` (both confirmed to exist) stay
  green with no assertion changes needed beyond whatever the token-source
  refactor mechanically requires.
- **Target Test Target:** `lwc/gtmStory/__tests__/preview.test.js`,
  `lwc/gtmStory/__tests__/gtmStory.test.js` (confirm exact filename in
  Architect phase), and `lwc/gtmReadoutView/__tests__/gtmReadoutDesign.test.js`
  (flagged by the existing plan doc as sharing the configurator's palette
  and needing a read-through, not yet done in this BA pass — Architect to
  confirm whether its assertions are gtmStory-adjacent or purely
  gtmConfigurator-adjacent and file it under the correct part accordingly).
