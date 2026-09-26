# TASK SCOPE — ISSUE #ps-brand-overhaul-2-brand-tokens-shapes-type

> Part 2 of 7 in the `ps-brand-overhaul` initiative. Foundation layer —
> parts 4, 5, and 6 (the per-component restyles) all depend on this landing
> first. Independent of parts 1 and 3 (data/schema work); can run in
> parallel with those.

## 1. Requirements Breakdown

- **Target Objective:** Replace three components' drifted, incorrect brand
  implementation with one shared, correct token/shape/type source, so
  `offeringChooser`, `chooseIndustry`, and `gtmConfigurator` match
  `gtmStory`'s already-correct 04.2026 Publicis Sapient brand implementation
  instead of an older/wrong palette and unrelated fonts. Verified directly,
  not assumed:

  ```
  $ grep -n "E90024\|E4002B" offeringChooser.css chooseIndustry.css gtmConfigurator.css
  offeringChooser.css:30,53,68,82,129,248:  #E90024 (--accent / .tile-accent / text color)
  chooseIndustry.css:30,53,68,82:           #E90024 (--accent)
  gtmConfigurator.css:29,64,84,103,167:     #E90024 (--coral / text color)
  ```
  `#E4002B` (the second "wrong" value the brief names) does not actually
  appear anywhere in these files — only `#E90024` does. Correcting the
  brief's claim here rather than repeating it uncritically.

  ```
  $ grep -n "font-family" chooseIndustry.css offeringChooser.css gtmConfigurator.css
  chooseIndustry.css / offeringChooser.css: 'Inter' (body/headings) AND
    'IBM Plex Mono' (labels/eyebrows/mono data) — both hardcoded, both wrong.
  gtmConfigurator.css:43:  font-family: 'Inter', -apple-system, ...  (body/headings — wrong)
  gtmConfigurator.css (mono declarations, lines 208/409/518/536/682/816/854/882/935/982/1062/1202):
    all read `ui-monospace, monospace` / `ui-monospace, 'SF Mono', monospace`
    — generic stacks, NOT literally "IBM Plex Mono" as the brief states.
  ```
  Correction: only `chooseIndustry.css`/`offeringChooser.css` hardcode "IBM
  Plex Mono" by name; `gtmConfigurator.css` uses generic monospace stacks.
  All three still need to move to `Roboto Mono` — the destination is the
  same, the starting point for `gtmConfigurator.css` specifically is a
  generic stack, not a named wrong font.

  `gtmStory.css` is confirmed correct and is the reference implementation:
  ```
  $ grep -n "ps-red\|ps-font" gtmStory.css
  41:  --ps-red: #e90130;         42: --ps-red-hover: #be0128;
  73:  --ps-font-display: "Lexend Deca", ui-sans-serif, system-ui, ...
  ... --ps-font-body (Roboto) / --ps-font-mono (Roboto Mono) also present
  ```
  and its real heading selectors do consume these tokens (re-verified
  myself rather than trusting the open question in the existing plan doc —
  `--ps-font-display` is applied at 9 separate selectors, lines 475, 619,
  872, 967, 1164, 1222, 1329, 1344, 1381 of `gtmStory.css`), so it is a
  proven, not just declared, reference implementation.

  A shared token/shape module must be built once and consumed by all four
  components, rather than re-copy-pasting `gtmStory`'s `:host` block a
  third time (which is exactly how the three lagging components drifted in
  the first place). This is a **second attempt** — `c/gtmBrandTokens` was
  already tried once and removed:
  ```
  $ git log --all --diff-filter=D -- .../lwc/gtmBrandTokens/gtmBrandTokens.css
  4fe6b5c8 fix(ci): zero out check-references.py debt ... (issue #33)
  "gtmBrandTokens was an orphaned half-finished LWC bundle from PR #23
  (CSS only, no .js/.js-meta.xml). Nothing imports it as a component --
  only gtmStory.css pulls it in via the CSS-only `@import 'c/gtmBrandTokens'`
  sharing pattern -- so its tokens are folded directly into gtmStory.css
  and the invalid bundle is removed..."
  ```
  The failure mode was specific and avoidable: a CSS-only LWC bundle (no
  `.js`/`.js-meta.xml`) isn't a deployable component and doesn't survive
  `check-references.py`. The existing implementation plan at
  `~/.claude/plans/this-is-the-ps-cozy-lemur-agent-a9ecb246375d24d02.md`
  (read in full — see note below on the file-naming discrepancy) already
  designed around this failure: `gtmBrandTokens` as a plain **importable JS
  module** (`gtmBrandTokens.js`, no template, no `.js-meta.xml` — a helper,
  not a component), exporting a CSS-text constant plus an
  `injectBrandTokens(hostEl)` helper that each component's existing
  `connectedCallback` (already does the identical dance for its font
  `<link>` injection, per component) calls once to inject a `<style>` tag
  into its own shadow root. This avoids the PR #23 failure mode entirely
  (no `.js-meta.xml`-less component bundle) and avoids cross-shadow-root
  CSS `@import`, which LWC doesn't support at runtime. Architect should
  treat this design as a strong starting point, not a settled spec — it
  explicitly names its own fallback (Option B: a duplicated-but-CI-diffed
  token block) if the injection mechanism hits a Locker/LWS wall in a
  spike.

  Also in scope: the notched-rectangle `clip-path` shape system (confirmed
  net new — zero `clip-path`/`notch` hits anywhere in `gtmStory.css` or
  `gtmConfigurator.css` today) as a small set of utility classes shipped
  inside the same shared module, and the typography swap. Per-view
  *application* of these utilities (which card gets which notch, where
  photography goes, etc.) is explicitly **out of scope here** — that's
  parts 4/5/6. This part only builds and unit-tests the shared primitives.

  **File-naming discrepancy to flag:** the coordinator's brief describes
  two plan files — a primary `this-is-the-ps-cozy-lemur.md` and a
  companion `this-is-the-ps-cozy-lemur-agent-a9ecb246375d24d02.md`, both in
  `~/.claude/plans/`. Only the second (`-agent-...` suffixed) file actually
  exists on disk — confirmed via `find ~/.claude/plans -iname '*lemur*'`,
  one result. I scoped this entire document from that one file, which is
  self-contained and appears complete (7 sections, file-by-file detail,
  phasing). If a separate, differently-scoped primary file was intended
  and never actually written, or exists somewhere else, this doc may be
  missing content it should have carried — Architect/coordinator should
  confirm.

  **A real, evidenced conflict to flag, not resolve unilaterally:** an
  earlier, substantive BA scope doc already exists for almost this exact
  surface — `ba-scope/issue-ps-brand-configurator` (`TASK_SCOPE.md` at
  repo root on that branch, dated 2026-09-13, never merged to `main`,
  confirmed via `git branch --merged main`, no output). Its own live-
  researched brand spec **directly contradicts** this initiative's:

  | | `ba-scope/issue-ps-brand-configurator` (Sept 13, unmerged) | This initiative (04.2026 PDF) |
  |---|---|---|
  | Red | `#E90024`, "primary/dominant, ~50% of palette" | `#E90130`, accent-only, never a button fill |
  | Headline font | Publicis Nouveau (no file in repo; needs sourcing) | Lexend Deca |
  | Body font | Hasköy (no file in repo; needs sourcing), Inter as fallback | Roboto |
  | Buttons | Solid red pill, white text, primary CTA | Never red; white/black pill or solid black |
  | GUS launcher | Solid red circular FAB | Not specified as circular; existing pill shape not called out for change |

  That branch was scoped but never built (no Developer worktree/branch, no
  merge — `git worktree list` and `git branch --merged main` both confirm).
  My read of the evidence: this initiative's spec (sourced from a dated
  04.2026 PDF) is the more current one, and `gtmStory`'s `#e90130`/Lexend-
  Deca/Roboto implementation — already treated as "the reference
  implementation" by this initiative's own source material, and pre-dating
  even the Sept 13 doc — corroborates it. But I am a BA, not the brand
  authority, and this is a real fork only a human should close out
  explicitly: **recommend the coordinator/owner formally mark
  `ba-scope/issue-ps-brand-configurator` superseded/archived** before an
  Architect or Developer stumbles on it and builds the wrong palette.
  Do not build anything from that branch's `TASK_SCOPE.md` as part of this
  initiative.

  Not in conflict: `ba-scope/issue-slds-button-audit` (also unmerged) is
  explicitly scoped to *internal* Lightning Experience screens pushing
  *toward* stock SLDS — the opposite surface and opposite direction from
  this guest-facing initiative. Its own scope doc says so explicitly
  ("Separate and unrelated to `ba-scope/issue-slds-button-audit`... do not
  merge the two"). No action needed, noted only to confirm no collision.

- **System Component Impacted:** LWC only — new
  `force-app/main/default/lwc/gtmBrandTokens/gtmBrandTokens.js` (module,
  not component) + `.css`/`.js` edits to `gtmStory`, `offeringChooser`,
  `chooseIndustry`, `gtmConfigurator` to consume it. No Apex, no schema, no
  CMDT.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO.** Pure CSS/JS styling module; no
      Apex, no tool surface, no DML/callouts anywhere in this scope.
- [ ] Altering Custom Metadata? **NO.**
- [ ] Introducing database fields? **NO.**

## 3. Plan Acceptance Criteria

- **Success Metric:** `grep -rn "#E90024\|#E4002B\|'Inter'\|IBM Plex Mono" force-app/main/default/lwc/{offeringChooser,chooseIndustry,gtmConfigurator}/*.css` returns zero matches; `gtmBrandTokens.js` exports the token CSS text and `injectBrandTokens()`, unit-tested to dedup (matching the existing `data-gtm-fonts="1"` link-dedup pattern already used for font injection) and to contain the correct red/fonts and NOT the retired ones; notch utility classes (`.ps-notched`, corner modifiers) exist and are unit-testable; existing `offeringChooser.brand.test.js` and `gtmConfigurator.brand.test.js` are **rewritten** (they currently assert the wrong, pre-redesign state — `expect(link.href).toContain('family=Inter')` — so relaxing them would hide a regression, not catch one) to assert Lexend Deca/Roboto/Roboto Mono and absence of `Inter`; a new `chooseIndustry.brand.test.js` is added (confirmed today there is no brand test file under `lwc/chooseIndustry/__tests__/` — only `chooseIndustry.test.js` exists). No visual application beyond whatever minimal proof-of-injection each component's own test needs — full per-view application is parts 4/5/6.
- **Target Test Target:** new `lwc/gtmBrandTokens/__tests__/gtmBrandTokens.test.js`; rewritten `lwc/offeringChooser/__tests__/offeringChooser.brand.test.js` and `lwc/gtmConfigurator/__tests__/gtmConfigurator.brand.test.js`; new `lwc/chooseIndustry/__tests__/chooseIndustry.brand.test.js`.
