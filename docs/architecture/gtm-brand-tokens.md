# GTM Brand Tokens (`c/gtmBrandTokens`)

Status: contract (Developer, written alongside the implementation — no
Architect pre-doc existed for this specific module API beyond the scope
doc's prose description). Source of truth for whoever picks up parts 4, 5
and 6 of the `ps-brand-overhaul` initiative. Scope:
`docs/agent-artifacts/task-scope-ps-brand-overhaul-2-brand-tokens-shapes-type.md`
plus two Architect corrections in that worktree's `WORKTREE_SCOPE.md`
(SVG-clipPath shape primitive, no ambient dark mode in the shared module).

HONEST LIMITS. Two named reference implementations in the task brief were
not reachable from this session: the Design System artifact at
`https://claude.ai/artifact/SE8G5KGFet5DDTLLjJYNEK` (no browser/fetch tool
available to this agent; a direct `curl` returns Cloudflare's bot-check
page, HTTP 403, not the artifact) and the "Migration Accelerator mockup's
`Configurator.dc.html`/`ConfiguratorClient.dc.html`/`Chooser.dc.html`/
`Story.dc.html`" — no file by that name or extension exists anywhere in
this repo's current tree OR its full git history (`git log --all
--diff-filter=A -- '*.dc.html'` returns nothing); the closest historical
match is the legacy static prototype (`migration-accelerator/{story,
configurator,choose-industry}.html`) removed in commit `7a2e538f`, which
contains zero `clip-path`/notch code. The notch geometry below is this
Developer's own derivation from the corrections' written spec (arc-based
SVG `clipPath`, `clipPathUnits="userSpaceOnUse"`, measured element size,
two convex corners at sweep 1, one concave corner at sweep 0), independently
verified against a real Chromium rendering (section 4.3), not copied from
either named reference. Anyone who later gets access to the Design System
artifact should diff its `psNotchPath()` against the one here and reconcile
any difference — the function is named identically on the chance it helps
that comparison.

## 1. Why this module, second attempt

`offeringChooser`, `chooseIndustry` and `gtmConfigurator` each re-declared
their own palette and drifted to the wrong red (`#E90024` instead of the
live-site `#E90130`) and the wrong fonts (Inter / IBM Plex Mono instead of
Lexend Deca / Roboto / Roboto Mono). `gtmStory.css` is the one
proven-correct implementation (its `--ps-font-display` is actually consumed
at 9 selectors, not just declared). A first attempt at sharing this,
`c/gtmBrandTokens` as a CSS-only bundle (PR #23), had no `.js`/`.js-meta.xml`
and was not a deployable component; it was removed in issue #33
(`4fe6b5c8`) and its tokens folded directly into `gtmStory.css`.

This module is the second attempt: a plain importable JS module (real
`.js` + real `.js-meta.xml`, `isExposed: false`, no `.html`) — the same
template-less-helper-bundle shape already proven in this tree by
`c/gtmNavigate`, `c/gtmPredicate` and `c/gtmColumnState`. "Not a component"
means no template and not placeable in Experience Builder, not "no
`.js-meta.xml`" — a bundle folder under `lwc/` with no `.js-meta.xml` fails
`scripts/check-references.py`'s companion-file check outright ("LWC bundle
has no X.js-meta.xml -- it will not deploy"), which is the same class of
defect PR #23 shipped for a different missing file. **A stale
`jest.config.js` `moduleNameMapper` entry left over from the PR #23 cleanup
was still pointing `c/gtmBrandTokens` at the deleted `.css` file** and
silently resolved every import of the new module to `undefined` until it
was removed as part of this change — see the commit for that fix; anyone
reviving a CSS-only sharing pattern in this codebase should not re-add a
mapper like it.

## 2. Public API

```js
import { BRAND_TOKENS_CSS, injectBrandTokens, applyNotch } from 'c/gtmBrandTokens';
```

| Export | Shape | Purpose |
|---|---|---|
| `BRAND_TOKENS_CSS` | `string` | A `:host { --ps-*: ...; }` CSS-text rendering of the token object, for documentation/CI-diffing against `gtmStory.css`'s own block (the "Option B" fallback the original plan named). **Not used internally** — see 3.1 for why. |
| `injectBrandTokens(hostEl)` | `(HTMLElement) => void` | Stamps every `--ps-*` custom property from the light-only token set onto `hostEl`'s own inline style, once. |
| `applyNotch(hostEl, corner, options?)` | `(HTMLElement, 'tl'\|'tr'\|'br'\|'bl', {notchRadius?, cornerRadius?}) => void` | Clips `hostEl` to a rounded rectangle with a concave "bite" cut into `corner`, using a per-instance inline SVG `clipPath`. |

No other export is part of the contract (the internal `BRAND_TOKENS` object
and the `psNotchPath` path-builder are module-private).

### 2.1 Required call-site pattern — `renderedCallback`, not `connectedCallback`

**Both functions must be called from `renderedCallback`, not
`connectedCallback`.** This was verified empirically, not assumed: LWC
renders a component's template *after* `connectedCallback` returns, so
`this.template.querySelector(...)` called synchronously inside
`connectedCallback` returns `null` in this project's actual test harness
(confirmed by instrumenting `offeringChooser.js`'s `connectedCallback` with
a debug log and running its existing Jest suite — logged `null` on every
invocation). `injectBrandTokens`/`applyNotch` both no-op silently on a
falsy/malformed host, so this bug would not have thrown anywhere — it would
have shipped a page that never actually received the corrected tokens,
which is exactly the kind of silent failure this initiative exists to fix.
`offeringChooser.js` and `chooseIndustry.js` had no `renderedCallback` at
all before this change; one was added to each, containing only the
`injectBrandTokens` call. `gtmConfigurator.js` already had one (guarded,
"runs on every keystroke"); the call was added there. Both functions are
internally idempotent (see 3.2 and 4.2), so calling them on every
re-render is a cheap no-op after the first.

```js
renderedCallback() {
    injectBrandTokens(this.template.querySelector('.oc-root'));
    // Parts 4/5/6, once they apply a notch to a specific element:
    // applyNotch(this.template.querySelector('.tile'), 'tr');
}
```

## 3. Tokens (`injectBrandTokens`)

### 3.1 Why inline-style stamping, not a `<style>` tag

The obvious-looking implementation — build `BRAND_TOKENS_CSS` once and
inject it as a `<style>` element, mirroring the existing font-`<link>`
injection dance — is deliberately **not** what `injectBrandTokens` does.
`BRAND_TOKENS_CSS`'s `:host {...}` selector only means anything if the
`<style>` tag ends up inside a *native* shadow root; LWC's synthetic-shadow
fallback (still reachable under some Lightning Web Security configurations,
notably the Aura-hosted Experience Cloud pages these three components
render on) rewrites `:host` into an attribute-selector match at *build*
time, which a hand-authored runtime string cannot participate in. This is
exactly the "Locker/LWS wall" risk the original implementation plan
(`~/.claude/plans/this-is-the-ps-cozy-lemur-agent-a9ecb246375d24d02.md`)
flagged as its own open question, and there is no live org available to
this agent to spike-test it against.

`injectBrandTokens` instead calls `hostEl.style.setProperty('--ps-red',
'#e90130')` (etc.) directly — plain DOM mutation with no shadow-mode
dependency, so it cannot hit that wall either way. Each consuming
component's own `.css` already declares its local aliases in terms of
`var(--ps-red, <fallback-hex>)`; those resolve correctly once the custom
property exists on the same element via inline style, exactly as they
would from a `:host` rule, because CSS custom property lookup checks the
element's own computed style regardless of how a value got there.
`BRAND_TOKENS_CSS` is exported anyway, generated from the same source
object so it can never drift from what `injectBrandTokens` actually
applies, in case a future spike proves the `<style>`-tag approach safe on
`gtm-staging` and someone wants to switch.

### 3.2 Dedup

Guarded by `hostEl.dataset.psBrandTokens === '1'`, the same
"marker-attribute gate" shape as the existing `data-gtm-fonts="1"`
link-dedup pattern, adapted to an inline-style target (there is no separate
node to tag, so the marker lives on `hostEl` itself).

### 3.3 Light only, on purpose — and what did NOT change as a result

`gtmStory.css` also implements a *general*, OS-preference-driven dark mode
(`@media (prefers-color-scheme: dark)` plus `.dark`/`.light` override
classes, comment: "Dark is opt-out, not opt-in") that flips nearly the
entire palette. **That mechanism is not ported into this module.** The
owner-approved Design System default across this initiative is
light/bright/airy, with dark reserved for specific full-bleed photo
moments (a hero band, a parallax "why" section), applied as an explicit,
manually-opted-into utility scoped to that one section — never a general
UI-wide toggle. `BRAND_TOKENS` is the light palette only; there is no dark
variant exported from this module, and no `@media`/`.dark`/`.light` rule
appears anywhere in `BRAND_TOKENS_CSS` (unit-tested).

This does **not** mean `offeringChooser`, `chooseIndustry` and
`gtmConfigurator` lost dark mode. Each already ships its own **separate,
pre-existing, user-facing light/dark toggle button** (`◐`, wired to
`handleThemeToggle()`/`this.theme`/`rootClass`) with its own local
palette (`--bg`, `--paper`, `--ink`, `--line`, `--panel`, `--shadow`, etc.)
— a real, clickable feature, not incidental CSS, and unrelated to
`gtmStory.css`'s ambient mechanism. Ripping that out was **not** this
part's call to make unilaterally: none of the 7 `ps-brand-overhaul` scope
docs mention it, so whether a manual per-page theme toggle survives the
wider brand relaunch is a real, separate product decision for the
coordinator/owner, not a token-plumbing one. What this change actually did
inside each component's own dark/`.dark`/`.light` blocks: corrected only
the wrong accent hue (`--accent`/`--tile-accent`/`--coral`, and their
`rgba(233, 0, 36, ...)` duplicates — the RGB of the same wrong hex, which
grepping for the literal `#E90024` string alone would have missed) to
`var(--ps-red, #e90130)` / `color-mix(in srgb, var(--ps-red, #e90130) N%,
transparent)`, in every branch (light default, dark media query, `.dark`,
`.light`) alike, preserving each branch's own pre-existing alpha. Every
other value in those dark blocks (background, ink, borders, shadow) is
untouched. If/when the coordinator decides those components' dark palettes
should also consume shared dark tokens, that is new scope, not a fix to
what shipped here.

### 3.4 Token list

Verbatim light-mode values from `gtmStory.css`'s `:host` block (the
proven-correct reference), unchanged, plus two new tokens for the notch
primitive (4.1). See `gtmBrandTokens.js`'s `BRAND_TOKENS` object for the
literal values — not duplicated here to avoid a second copy that can drift;
`gtmBrandTokens.test.js` asserts the red and the type stack directly
against `BRAND_TOKENS_CSS`.

## 4. Notch shape primitive (`applyNotch`)

### 4.1 Why a JS helper, not a CSS class

A static `clip-path: polygon(...)` utility class can only draw straight
lines (a chamfer), not the brand's rounded "bite", and cannot encode
per-element pixel coordinates for components that render at varying sizes.
`applyNotch(hostEl, corner, options?)` measures `hostEl.offsetWidth` /
`offsetHeight` and writes a per-instance `<clipPath
clipPathUnits="userSpaceOnUse">` containing one `<path>`, appended as a
zero-size (`width:0;height:0;overflow:hidden`) hidden child SVG of `hostEl`
itself — same-tree by construction, so the `url(#id)` fragment reference
needs no cross-shadow-boundary resolution and carries none of section
3.1's risk.

### 4.2 Geometry contract

For a rectangle `(0,0)`–`(w,h)`:

- `corner` gets a **concave** bite of radius `notchRadius` (default 28px,
  or `--ps-notch-radius` read off `hostEl`'s computed style).
- The two corners **adjacent** to it (sharing an edge) get plain **convex**
  rounds of radius `cornerRadius` (default 16px, or
  `--ps-notch-corner-radius`).
- The corner **diagonally opposite** the notch is left **sharp** (radius 0).

Both new radius tokens are plain `px` values (not `rem`), specifically so
`applyNotch` can `parseFloat()` them straight off
`getComputedStyle(hostEl).getPropertyValue(...)` without a root-font-size
lookup.

Arc math: every corner's arc runs between the same two tangent points
regardless of direction — `corner - r*in` (where the previous straight edge
stops) and `corner + r*out` (where the next straight edge resumes), where
`in`/`out` are the unit directions of the edges walking into/out of that
corner when tracing the rectangle clockwise. A convex round bulges toward
the true corner (SVG sweep-flag `1`, walking clockwise); a concave bite is
the mirror-image arc through the *same two points*, bulging away from the
corner into the material (sweep-flag `0`). Large-arc-flag is always `0`:
every arc here is a single quarter-turn.

### 4.3 Verification (no live org, no access to the named reference)

Because neither named reference implementation was reachable (see the
HONEST LIMITS note above), the geometry was verified independently in two
ways before shipping, not just by inspection:

1. A hand-rolled point-in-polygon check (`scripts`-adjacent scratch file,
   not committed) flattening the arcs and probing near each corner —
   caught nothing wrong, but its own arc-endpoint-to-center math was later
   shown to have bugs of its own, so it is **not** the evidence relied on.
2. **Ground truth from an actual browser render**: a headless-Chrome
   screenshot of all four `corner` values against a lime background,
   pixel-sampled with PIL at exact coordinates 6px and 20px diagonally
   inset from each of the rectangle's four true corners. Result: the
   concave corner is lime (excluded) at 6px inset in all four cases; the
   sharp corner (diagonally opposite the notch) is red (filled) at 6px
   inset in all four cases; the two convex corners are red at 6px inset
   (correctly inside their round's disk) and red at 20px (correctly beyond
   a 16px-radius round). This is the evidence for the geometry, not a
   description of a screenshot.

`gtmBrandTokens.test.js` asserts the same contract structurally (arc
command counts and sweep flags in the generated `d` attribute) so a future
change to the geometry that breaks it fails a fast unit test, not just a
visual check.

### 4.4 Dedup / re-render behaviour

Keyed by `hostEl.dataset.psNotchId`. A repeat call on the same `hostEl`
re-measures and rewrites the existing `<path>`'s `d` attribute in place —
it does not create a second `<svg>` — so it is safe to call unconditionally
from `renderedCallback` on every re-render (picking up size changes) and
safe to call with a different `corner` argument on a later call (the shape
updates instead of stacking). `applyNotch` does **not** attach a
`ResizeObserver` itself; callers that need to react to viewport/container
resizes outside of their own natural re-render cycle must re-invoke it
themselves.

### 4.5 Scope note for parts 4, 5, 6

This part only builds and unit-tests the primitive. No component's markup
in this repo calls `applyNotch` yet, and no `.ps-notched`-style utility
class exists — the corrections that produced this module specifically
replaced that static-class plan with the JS primitive above. Whoever picks
up parts 4/5/6 (per-component restyles) should NOT build against a
class-only contract; call `applyNotch(el, corner)` from that component's
own `renderedCallback`, same pattern as 2.1.

## 5. What changed in the three consuming components (this part only)

`offeringChooser`, `chooseIndustry`, `gtmConfigurator` — `.css` and `.js`
only, no `.html` change, no notch application (4.5):

- Every hardcoded `#E90024` / `rgba(233, 0, 36, ...)` (the RGB of the same
  wrong hex — not caught by a literal-string grep for `#E90024`) now
  resolves through `var(--ps-red, #e90130)` /
  `color-mix(in srgb, var(--ps-red, #e90130) N%, transparent)`.
- Every hardcoded `'Inter'`, `'IBM Plex Mono'`, `'IBM Plex Sans'` (the last
  one is not named in the task brief's own grep, found by checking the
  same class of bug in the surrounding rules) and the generic
  `ui-monospace, monospace` stacks in `gtmConfigurator.css` now resolve
  through `var(--ps-font-display, ...)` / `var(--ps-font-body, ...)` /
  `var(--ps-font-mono, ...)`, mapped by the element's actual role (real
  `<h1>` and card-title selectors → display; general copy/marks/wordmark →
  body; labels/eyebrows/tags/data/code → mono) rather than a single
  blanket substitution.
- Each component's `FONTS_HREF` now requests the same family list as
  `gtmStory`'s (`Lexend+Deca`, `Roboto`, `Roboto+Mono`) instead of `Inter`
  — a `.css`-only fix would have left the correct token *names* pointing at
  a font family the page never actually downloaded.
- `gtmStory.css`/`gtmStory.js` are unmodified — out of this part's file
  list per the Architect's explicit correction, despite the original scope
  doc body listing gtmStory as one of the four components to edit. Treated
  as read-only reference/extraction source only.

## 6. Open items for the coordinator (not resolved here)

- Confirm the notch geometry in 4.2/4.3 against the Design System artifact
  once someone with browser/artifact access can open
  `https://claude.ai/artifact/SE8G5KGFet5DDTLLjJYNEK` — this Developer
  could not.
- Decide whether `offeringChooser`/`chooseIndustry`/`gtmConfigurator`'s
  existing per-page light/dark toggle button survives the wider brand
  relaunch (section 3.3) — genuinely unreconciled across all 7 scope docs,
  not this part's call.
- `python3 scripts/build-instrument.py --check` (run as part of this
  part's own pre-handoff gate, unrelated to anything this part touched)
  currently exits 1 in any worktree without a `ma-migrator` working copy
  (`MA_MIGRATOR_ROOT` unset, no such directory anywhere on this machine) —
  `--allow-missing-source-root` makes it pass cleanly ("all 14 rules
  hold"). Pre-existing per `reference/ma-migrator-capabilities/`'s own
  documented "pending the `ma-migrator` handoff" status (ADR-0009); zero
  files under `instrument/`, `migration-accelerator/` or `reference/` were
  touched by this part. Worth the coordinator confirming CI's own
  invocation passes `--allow-missing-source-root` (or sets
  `MA_MIGRATOR_ROOT`), since the bare command in a fresh worktree does not.
