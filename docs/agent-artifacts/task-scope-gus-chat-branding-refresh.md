# TASK SCOPE — ISSUE #gus-chat-branding-refresh

Chat-originated request from the app owner ("GUS's Agentforce chat window
looks stock — redesign it considering Sapient branding"), not a filed GitHub
issue. Per this repo's BA convention for non-ticketed requests (precedent:
`docs/agent-artifacts/task-scope-gus-utility-bar-host.md`,
`task-scope-gus-stage-filter-tool.md`,
`task-scope-102-e-gus-file-extraction.md` — all scoped under a descriptive
slug rather than a numeric id), this is scoped as **`gus-chat-branding-refresh`**.
Branch: `ba-scope/issue-gus-chat-branding-refresh`. File: this one.

> **Correction to the incoming brief, found by reading the actual code
> rather than trusting the summary handed to this BA pass:** a full,
> already-correct-against-current-brand-guidelines color/type/shape token
> block already exists in this repo (`gtmStory.css`, quoted below in full),
> independently derived from the *live* publicissapient.com stylesheet, not
> from the brand PDF the requester read. It agrees with the requester's PDF
> on the two facts that matter most (the red hex and the three font
> families) via a completely independent source. Do not re-derive brand
> values from scratch or from the PDF — copy the relevant `--ps-*` tokens
> out of `gtmStory.css`. Separately, the "font files are a real dependency"
> concern in the brief is real but **already solved once** in this codebase
> (a working, CSP-approved Google-Fonts-CDN loader for exactly these three
> fonts already exists and runs inside Lightning Experience today) — it is
> a reuse task, not a from-scratch infrastructure build. And there are
> **three** GUS chat mounts sharing one engine, not two — a third,
> previously unnamed surface (`gtmReadoutAssist`) also renders the same
> shared `gtmAgentChat` component and looks at least as "stock" as the two
> named surfaces. All of this is evidenced below with exact file/line
> citations.

## 1. Requirements Breakdown

- **Target Objective:** Give GUS's chat UI — currently a mix of default
  SLDS styling and a stale (pre-rename) color/font treatment — a visual
  identity that matches Publicis Sapient's current brand guidelines: the
  corrected brand red, true black/white as the dominant surfaces, and the
  Lexend Deca / Roboto / Roboto Mono type system, applied consistently
  across every place GUS's chat renders. This is a **presentation-only**
  change: CSS, template markup, and (for fonts) a font-loading mechanism.
  No change to GUS's behavior, tools, backend, persona, or copy.
- **System Component Impacted:** LWC (CSS/HTML only, no new `@api`/wire
  contracts) across the four components listed in §1.2, plus one Experience
  Cloud branding-set config file (JSON, not a route, not Custom Metadata),
  plus a font-loading dependency that is either a metadata-free JS/CSS
  change (CDN reuse, recommended) or a new `staticresources` entry
  (self-hosting, fallback). **No Apex. No YAML Instrument. No new
  Experience Cloud route. No custom metadata.**

### 1.1 Evidence tiers (read this before trusting any specific number below)

- **Tier A — verified directly by this BA pass this session** (Read/Grep/git
  on the actual working tree): every file path, line number, CSS/JS/JSON
  literal, and doc quote cited in this file.
- **Tier B — independently corroborated**: the brand red `#E90130` and the
  three font families (Lexend Deca / Roboto / Roboto Mono) are asserted
  *twice*, from two unrelated sources — the requester's PDF read, and this
  repo's own `gtmStory.css` header comment, which says it derived its values
  from the *live* `publicissapient.com` stylesheet (`etc.clientlibs/ps-
  redesign/clientlibs/clientlib-site.css`), not a brand-aggregator site, and
  explicitly rules out the commonly-cited `#E4002B` ("appears ZERO times in
  the live PS CSS, while #E90130 appears 44 times"). Two independent sources
  agreeing on the same non-obvious value is real confidence — treat these
  two facts as settled.
- **Tier C — asserted only in the requester's chat summary of a Google
  Drive PDF this BA pass has no tool access to and did not open**: the
  exact WCAG contrast numbers beyond what `gtmStory.css` already computed
  for the same red (see §1.5), the logo minimum-size/clear-space rules, the
  Global Brand Help Desk approval nuance for the PS shorthand mark, and the
  "red is not the primary button color, lead with black/white" philosophy
  statement. These are plausible and directionally consistent with Tier B,
  but this BA pass cannot independently confirm them. The Architect/Developer
  should treat the PDF itself (or a human-confirmed excerpt) as the source
  of record for anything pixel/ratio-specific in this tier, not this
  document's restatement of a restatement.

### 1.2 Confirmed current state — the three surfaces, not two

The brief named two "inconsistent" surfaces. Reading the code turned up a
third that shares the same underlying engine and is at least as generic:

1. **`force-app/main/default/lwc/gtmGusUtility/`** — internal-only host,
   `lightning__UtilityBar` target only (`gtmGusUtility.js-meta.xml` line 8).
   `gtmGusUtility.css` (46 lines total): `.gus-panel { ... background:
   #ffffff; }` (line 10), `.gus-head { ... border-bottom: 1px solid
   #e5e7eb; }` (line 18), `.gus-role { opacity: 0.65; }` (line 35) — plain
   white panel, generic gray hairline, no brand color or brand font
   anywhere in the file. This is almost certainly the "stock" look the
   owner means. Confirmed via `Read`.
2. **`force-app/main/default/lwc/gtmAgentBubble/`** — the floating
   chat bubble (Experience Cloud `/configurator` route, live and docked
   preview). `gtmAgentBubble.css`: `.ab-root { font-family: 'Inter',
   -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }` (line 11);
   `.ab-fab { ... background: #E90024; ... }` (line 30) and
   `.ab-fab:focus-visible { outline: 2px solid #E90024; ... }` (line 40);
   `.ab-panel { ... background: #1c1a18; color: #f2efe9; ... }` (lines
   62-63). Already "designed," but on the deprecated red and a font not in
   the current system. Confirmed via `Read`.
3. **`force-app/main/default/lwc/gtmAgentChat/`** — **the brief said this
   component is "shared chat engine... not itself styled." That is
   incorrect** — it has 138 lines of real, opinionated CSS, and it is
   mounted by all three surfaces (see below), so its styling is the single
   highest-leverage (and highest-risk) file in this task.
   `gtmAgentChat.css`: `.message.user .bubble { background: #0070d2; color:
   #fff; ... }` (lines 42-46, stock SLDS blue, no brand relationship at
   all), `.messages { background: #f9fafb; border: 1px solid #e5e7eb; }`
   (lines 16-18), `.send-btn { ... background: var(--slds-g-color-brand-
   base-50, #0070d2); ... }` (lines 109-113). Confirmed via `Read`.
4. **`force-app/main/default/lwc/gtmReadoutAssist/`** — **not named in the
   brief at all.** This is the readout-editor's GUS panel
   ("Your deal context, folded into the readout"), and its
   `gtmReadoutAssist.html` mounts the exact same `c-gtm-agent-chat`
   component (`mode="readout"`, lines 64-69) inside its own chrome. Its
   header uses a generic `<lightning-icon icon-name="utility:einstein">`
   (line 4) and the text "GUS" — not `c-gtm-mascot` at all, a fourth
   inconsistency in how GUS is visually represented. `gtmReadoutAssist.css`:
   `.ra { border: 1px solid #e5e5e5; ... background: #fbfbfb; }` (lines
   4-7) — no brand color, no brand font. Confirmed via `Read` +
   `Bash grep`. **Because it shares `gtmAgentChat.css`, any restyle of that
   file changes this surface's appearance too, whether or not this task
   intends to.** See Open Fork F4.
5. **`force-app/main/default/lwc/gtmMascot/`** — GUS's SVG, themed via CSS
   custom properties. `gtmMascot.css`: `--gus-accent: var(--coral,
   #E90024);` (line 10, host block) and `.bead { fill: var(--gus-accent);
   }` (line 31). No component in the GUS-hosting chain (`gtmGusUtility`,
   `gtmAgentBubble`, `gtmReadoutAssist`) ever defines `--coral`, so this
   always resolves to the hardcoded `#E90024` fallback wherever the mascot
   renders inside GUS's chat surfaces today. Confirmed via `Read` + `Grep`.
6. Same `#E90024` literal is also present in
   `force-app/main/default/lwc/gtmConfigurator/gtmConfigurator.css` (5
   occurrences: lines 29, 64, 84, 103, 167), `offeringChooser/
   offeringChooser.css` (6 occurrences: lines 30, 53, 68, 82, 129, 248) and
   `chooseIndustry/chooseIndustry.css` (4 occurrences: lines 30, 53, 68,
   82) — confirmed via `Grep`. **These are the Configurator wizard's own
   surface, not "GUS's chat window," and are explicitly out of scope for
   this task** (see §1.10) — same drift, different component, flag as a
   follow-up rather than folding it in here.
7. **`force-app/main/default/experiences/GTM1/brandingSets/
   buildYourOwn.json`** — the live site's only branding set
   (`activeBrandingSetId` in the sibling `themes/buildYourOwn.json` matches
   its `id`): `"ActionColor" : "#E90024"` (line 7), `"LinkColor" :
   "#E90024"` (line 14), `"PrimaryFont" : "Inter"` (line 18), `"HeaderFonts"
   : "Inter"` (line 13), plus derived `_ActionColorDarker`/
   `_ActionColorTrans`/`_PrimaryAccentColor1-3` values all keyed off the old
   red. Confirmed via `Read`. See §1.7 for exactly how much of this is in
   scope.
8. **No `force-app/main/default/staticresources/` directory exists at all**
   in this repo (confirmed: `ls` returns "No such file or directory") and
   **no `@font-face` rule exists anywhere in `force-app/`** (confirmed:
   repo-wide `grep -rl "@font-face"` returns nothing). See §1.6 — this does
   **not** mean there's no working font mechanism, it means the working
   mechanism is a different one than "static resource."

### 1.3 Prior art the Architect must reuse: `gtmStory.css`'s brand-token block

`force-app/main/default/lwc/gtmStory/gtmStory.css` lines 1-177 contain a
full, dated, reasoned Publicis Sapient brand-token system (introduced in
commit `a89d7507` "feat(gtmStory): rework page layout rendering, add
Layout_Type__c, brand tokens", refined in `4fe6b5c8` issue #33 and
`825f9478` "fix(dark-mode): repair unreadable red wordmark contrast
(#148)"). Verified via `Read` and `git log`. Key excerpts:

```css
:host {
  --ps-red: #e90130;
  --ps-red-hover: #be0128;
  --ps-red-on-grey: #be0128;      /* 6.03:1 — use this on any tinted surface */
  --ps-red-soft: rgba(233, 1, 48, 0.09);
  --ps-red-ring: rgba(233, 1, 48, 0.28);
  --ps-on-red: #ffffff;

  --ps-ink: #000000;              /* TRUE black, no softened charcoal */
  --ps-ink-strong: #444444;
  --ps-ink-muted: #666666;
  --ps-ink-disabled: #949494;     /* 3.03:1 — must never carry text */

  --ps-white: #ffffff;
  --ps-surface-50: #fafafa;
  --ps-surface-100: #f5f5f5;
  --ps-surface-alt: #f6f6f6;

  --ps-font-display: "Lexend Deca", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --ps-font-body: "Roboto", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif;
  --ps-font-mono: "Roboto Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;

  --ps-radius-card: 0.625rem;
  --ps-radius-panel: 1rem;
  --ps-shadow: 0 16px 40px -20px rgba(0, 0, 0, 0.18);
  /* ...plus motion, elevation, and a full prefers-color-scheme dark block */
}
```

Its own comment already did the accessibility math this task needs: "`--ps-
red` on white is 4.65:1, which passes AA with only 0.15 of headroom. On any
grey surface it FAILS: 4.31:1 on `#F6F6F6`. Use `--ps-red-on-grey`
(`#BE0128`, 6.03:1) whenever red text sits on a tinted background." Reuse
that conclusion rather than re-deriving contrast ratios.

**Structural constraint the Developer must know:** LWC shadow DOM has no
`:root`, so this token block cannot simply be "imported" by `gtmGusUtility`/
`gtmAgentBubble`/`gtmReadoutAssist` — they are not descendants of
`gtmStory` in the DOM (separate component trees: Utility Bar item,
configurator/Experience-Cloud mount, readout editor mount), so CSS custom
property inheritance has no path between them regardless of shadow-DOM
rules. `gtmStory.css`'s own comment documents that a shared **CSS-only**
module (`c/gtmBrandTokens`) was tried and rejected: "a CSS-only bundle with
no `.js`/`.js-meta.xml` doesn't deploy as a component" — so the values were
folded directly into `gtmStory.css` instead, to be copied per-component.
**This scope's default is to follow that same precedent**: copy the needed
`--ps-*` subset into each GUS component's own `:host` block. Whether to
copy the full ~35-token set or only the handful actually used is Open Fork
F3.

### 1.4 Font-sourcing dependency — de-risked, not a blank blocker

The brief assumed self-hosting the three Google Fonts as new
`staticresources` + `@font-face` was required and flagged it as an open
blocker. That specific mechanism does not exist in this repo (confirmed,
§1.2 item 8) — but a **different, working mechanism for these exact three
fonts already does**, and it is already live/CSP-approved:

- `force-app/main/default/cspTrustedSites/Google_Fonts.cspTrustedSite-
  meta.xml`: `endpointUrl https://fonts.googleapis.com`, `context All`,
  `isApplicableToStyleSrc true`.
- `force-app/main/default/cspTrustedSites/Google_Fonts_Static
  .cspTrustedSite-meta.xml`: `endpointUrl https://fonts.gstatic.com`,
  `context All`, `isApplicableToFontSrc true`. Its own `description`:
  "Web fonts used by the Migration Accelerator story page. **Without this
  the page renders in fallback fonts inside Lightning Experience**, so the
  editor preview does not match the published page." — i.e. this exact CDN
  mechanism is already proven to work **inside Lightning Experience**, the
  same hosting context `gtmGusUtility` (Utility Bar) and `gtmReadoutAssist`
  (readout editor) run in, not just on the guest Experience Cloud site.
  Both are `context: All` (org-wide), not scoped to one site.
- `force-app/main/default/lwc/gtmStory/gtmStory.js` lines 7-8 define
  `FONTS_HREF = 'https://fonts.googleapis.com/css2?family=Lexend+Deca:
  wght@300;400;500;600&family=Roboto:wght@300;400;500;700&family=Roboto+
  Mono:wght@300;400;500;700&display=swap'` — the exact three families this
  task needs, already resolved to a working CSS2 API URL. Lines 634-645
  (`loadFonts()`) inject it once via `document.head.appendChild(link)`,
  de-duplicated with a `data-ma-story-fonts="1"` marker attribute, wrapped
  in a `try/catch` that treats font loading as "progressive enhancement."
  This appends to the *document* head (not the shadow root), which is why
  it works across every shadow boundary in the page — fonts registered via
  a document-level stylesheet are available to any shadow tree's CSS by
  family name, unlike custom properties or plain style rules.

**Recommendation (Architect to confirm, Open Fork F2):** reuse this exact
pattern rather than sourcing new font-file binaries. This turns the "real
dependency" the brief flagged into a ~15-line, already-precedented reuse,
not new infrastructure. Two things are still genuinely open and this BA
pass does not decide them:
1. **Duplicate vs. share the loader.** `gtmStory` is currently its only
   caller. With two or three new callers (`gtmGusUtility`, `gtmAgentBubble`,
   possibly `gtmReadoutAssist`), extracting `FONTS_HREF` + a `loadFonts()`
   helper into a new shared **JS-only** module is more justified than it
   was for one caller. Unlike the CSS-token case, this is genuinely
   possible here: this repo already has ten precedented JS-only,
   template-less LWC modules that deploy and are imported elsewhere
   (`c/gtmNavigate`, `c/gtmPredicate`, `c/gtmPageLayouts`,
   `c/gtmRuleEngine`, `c/gtmConfigData`, `c/gtmConfiguratorCopy`,
   `c/gtmColumnState`, `c/gtmFilterUrlState`, `c/gtmLinkDatatable`,
   `c/gtmAssessmentsTableModel` — confirmed by directory listing). A new
   `c/gtmBrandFonts`-style module is technically viable; whether to bother
   for 2-3 call sites is a judgment call for the Architect, not settled
   here.
2. **Live-org confirmation.** This BA pass verified the CSP Trusted Site
   metadata exists *in this repo's source tree*; it did not (cannot) verify
   the two CSP Trusted Sites are actually active in `gtm-staging`/`gtm-
   prod` today versus merely committed. QA must confirm live in the browser
   per the standing rule (font actually renders, not silently falling back
   to the CSS stack's fallback fonts) rather than assume deployment status
   from source alone.

Self-hosting via new `staticresources` + `@font-face` remains a documented
fallback only if the owner has a specific reason to avoid a third-party
network call from the internal Utility Bar (e.g. a stricter policy than
Experience Cloud already accepts) — flag, don't default to it, since it is
strictly more work for no proven benefit given the CDN path already works
in the same hosting context.

### 1.5 `buildYourOwn.json` (Experience Cloud branding set) — explicit line item

This file is **not** GUS-specific — it is the entire live `GTM1` site's
Experience Builder branding config (login page, nav bar, every standard
Aura/LWC-chrome color on every page of the site), so touching it has a
materially larger blast radius than "GUS's chat window," and it eventually
promotes to `gtm-prod` per the standard flow in `CLAUDE.md` §"Promotion
flow" (worktree → QA validate-only against `gtm-staging` → merge → deploy
`main` to `gtm-staging` for owner review → `gtm-prod` only on the owner's
explicit go-ahead). Recommendation (Open Fork F6): update **only** the two
literal color values that are provably the deprecated hex — `"ActionColor"`
and `"LinkColor"` from `"#E90024"` to `"#E90130"` — for consistency with a
rebranded bubble sitting on this same site, and leave every other key
(fonts, nav bar grays, login background, the `_`-prefixed derived colors)
untouched in this task. A full site-chrome rebrand (fonts via the sibling
`themes/buildYourOwn.json`'s `customCSS` field, which is the most likely
mechanism if that work is ever done, since Experience Builder chrome is
Aura-rendered and doesn't have an LWC-style JS hook to inject a `<link>`
the way `gtmStory.js` does) is real, separate work and should be its own
explicitly-scoped follow-up, not folded into a GUS chat-window task.

### 1.6 Logo

Per the requester's brand-guideline read (Tier C, §1.1): the PS shorthand
mark is usable internally without Global Brand Help Desk approval, so it
would be permissible on `gtmGusUtility` (internal Utility Bar) if a literal
mark is wanted there; `gtmAgentBubble` is prospect-facing and must keep
using the `c-gtm-mascot` character rather than any PS wordmark/shorthand,
to avoid needing that approval at all. **This scope does not mandate adding
a logo mark anywhere** — no such image asset exists in this repo today
(confirmed: no `staticresources` directory, no logo file found under
`force-app/`), and unlike fonts there is no freely-usable CDN fallback for
a company's proprietary logo artwork. If the owner wants a literal PS mark
on `gtmGusUtility`, an actual approved SVG/PNG file is a hard dependency
that must come from the owner/brand team — no coding agent can source or
fabricate a compliant brand-mark asset. Default for this task: no logo
asset added; `gtmGusUtility`'s header keeps `c-gtm-mascot` + the "GUS" text
label it already has. See Open Fork F7.

### 1.7 Mascot shape (soft note, not a mandate)

The requester's brand-guideline read describes the brand's shape system as
"architectural, schematic, grid-driven... system led, not symbolic... not
abstract AI motifs" (Tier C). `gtmMascot.html`'s chibi SVG character
(rounded head, circular eyes, curved smile — confirmed via `Read`) reads as
a soft, rounded, arguably "AI mascot" motif, which is in tension with that
language. **This task does not touch `gtmMascot.html`'s shape/paths** —
only its accent-color token (§1.2 item 5) — because the request was to
redesign the chat *window*, not the character, and `docs/backlog.md` D1/D8
already carries a separate, open thread about GUS's persona (see §1.10).
Flagging the tension for the owner's awareness only; do not act on it here.

### 1.8 Explicitly out of scope

- **GUS's persona, copy, tone, name, or role text.** Confirmed via `Grep`:
  `docs/backlog.md` D1 (line 31, "One Gus everywhere: same name, same
  voice...") and D8 (line 431, "Gus's persona... [is] stuck inside a page")
  are an existing, separate, already-tracked thread — do not fold voice/copy
  work into this visual-only scope.
- **The dormant Agentforce scaffold**: `force-app/main/default/bots/
  GTM_Configurator_Assistant/`, `genAiPlugins/GTMApplyConfigUpdate*.genAiPlugin-
  meta.xml`, `genAiPlugins/GTMGetConfigState.genAiPlugin-meta.xml`,
  `genAiFunctions/GtmAgentApplyConfigUpdate/`,
  `genAiFunctions/GtmAgentGetConfigState/` — all confirmed present via `ls`
  and all dormant/unwired per `AGENTS.md` §1 ("Agentforce is never called")
  and `docs/architecture/gus-chat-provider-settings.md` line 144 ("Agentforce
  is never called"), independently confirmed by this BA pass by reading
  both files directly. `docs/specs/agentforce-customizer-v2.md` (its own
  header: "Stale: written before the `MA_`→`GTM_` rename... verify current
  object/component names in code before treating this as ground truth")
  targets a *different* (Configurator) assistant and is unrelated to GUS's
  chat-window visuals. None of this scaffold is touched by this task.
- **`GtmAgentProxyController.cls` or any Apex/tool-surface class.** This
  task is presentation-only; confirmed no backend change is needed to
  achieve the objective.
- **`gtmConfigurator.css` / `offeringChooser.css` / `chooseIndustry.css`**'s
  own `#E90024`/Inter/IBM-Plex-Mono/IBM-Plex-Sans usage (§1.2 item 6) — same
  drift, different (wizard) surface, not "GUS's chat window." Recommend a
  separate follow-up ticket.
- **Any Experience Cloud site chrome beyond the two literal color values**
  in §1.5 (fonts, nav bar, login page).

## 2. Code Dependency Checklist

- [ ] **Modifying GUS Tool Surface?** **NO.** Zero Apex changes of any kind;
      `GtmAgentToolSurface`, `GtmAgentProxyController`, and every registered
      surface/tool class are untouched. The zero-DML rule in `AGENTS.md` §1
      is not implicated because no tool-surface code is touched at all.
- [ ] **Altering Custom Metadata?** **NO.** No `GTM_Assessment_*` custom
      metadata and no `instrument/<offering-key>/` YAML is touched.
      (`force-app/main/default/experiences/GTM1/brandingSets/
      buildYourOwn.json`, discussed in §1.5, is an Experience Bundle
      branding-set JSON — a different metadata type entirely from the
      `GTM_Assessment_*` custom-metadata-type records `CLAUDE.md`'s "Do Not
      Hand-Edit Metadata" rule is about — so this checkbox is correctly
      NO, but the file is real, in-scope, human-facing config; do not treat
      "not custom metadata" as "not risky.")
- [ ] **Introducing database fields?** **NO.** No new objects, fields, or
      schema of any kind. Consequently **no permission-set mapping is
      required for this task**: Salesforce does not gate static resources,
      CSP Trusted Sites, or LWC CSS/HTML via Field-Level Security or
      permission sets, so even the new font-loading dependency (§1.6,
      whichever mechanism is chosen) needs no entry in any of the five core
      permission sets in `force-app/main/default/permissionsets/`. Confirmed
      no existing static-resource-analogous entries exist in those files to
      contradict this.

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. `gtmGusUtility` (Utility Bar) and `gtmAgentBubble` (floating chat,
     live and docked-preview) render with the corrected Publicis Sapient
     identity: `#E90130` (not `#E90024`) wherever brand red appears, true
     black/white (`--ps-ink`/`--ps-white`) as the base surfaces, and
     Lexend Deca / Roboto / Roboto Mono actually rendering (verified live,
     not silently falling back to the CSS stack's fallback fonts) in both
     an internal Lightning Experience session and a guest Experience Cloud
     session.
  2. `gtmMascot`'s accent token resolves to the corrected red in every
     context it mounts within GUS's chat surfaces.
  3. No behavioral regression: `gtmGusUtility/__tests__/gtmGusUtility
     .test.js` and `gtmAgentChat/__tests__/gtmAgentChat.test.js` pass
     without logic changes. If any CSS class used by those specs is
     renamed, the same commit updates the assertions — specifically
     `.gus-new` (asserted at `gtmGusUtility.test.js` line 148),
     `.bubble` (asserted at `gtmAgentChat.test.js` line 59), `.send-btn`
     (via the `sendBtn()` helper, `gtmAgentChat.test.js` lines 31-33), and
     the raw `<textarea>` element (via the `textareaEl()` helper, lines
     27-29).
  4. The JS↔CSS class-string couplings this BA pass identified stay in
     sync: `gtmAgentBubble.js`'s `get rootClass()` (line 71, returns
     `'ab-root ab-root--docked'`/`'ab-root'`) and `get fabClass()` (line 76,
     returns `'ab-fab ab-fab--open'`/`'ab-fab'`); `gtmMascot.js`'s
     `get svgClass()` (lines 19-21, builds `` `gus gus--${size}
     gus--${mood}` ``); `gtmAgentChat.js`'s literal `cssClass` strings at
     lines 115 and 235-236 (`'message assistant'`, `` `message ${role}` ``,
     `` `message ${role} has-effect` ``). A CSS class rename with no
     matching JS-literal update will silently break open/closed, docked/
     floating, mood, or effect-button rendering.
  5. Any red-on-surface text or icon introduced meets WCAG AA (>= 4.5:1),
     using `--ps-red-on-grey` (not plain `--ps-red`) on any tinted
     background, per the contrast analysis already computed in
     `gtmStory.css`'s own header comment (§1.3) — not re-derived from
     scratch.
  6. Zero Apex, zero custom metadata, zero schema, and zero permission-set
     diffs appear in the change (per §2).
  7. If `buildYourOwn.json` is touched at all, the diff is limited to
     `ActionColor` and `LinkColor` (`#E90024` → `#E90130`); no other key in
     that file or in the sibling `themes/buildYourOwn.json` changes.
  8. QA visually validates in the browser (per the standing QA rule) on
     **every** mount of the shared chat engine, not just the two named in
     the request: the GTM Offerings app's Utility Bar (`gtmGusUtility`),
     the live `GTM1` Experience Cloud `/configurator` route's floating
     bubble, the same bubble docked inside the configurator's internal
     editor preview, and — if Open Fork F4 is resolved to include it — the
     readout editor's GUS panel (`gtmReadoutAssist`).
- **Target Test Target:**
  - Jest, existing (must stay green, logic unchanged):
    `force-app/main/default/lwc/gtmGusUtility/__tests__/gtmGusUtility.test.js`,
    `force-app/main/default/lwc/gtmAgentChat/__tests__/gtmAgentChat.test.js`.
  - Jest, new (these directories currently have no `__tests__` folder at
    all, confirmed via `ls`):
    `force-app/main/default/lwc/gtmAgentBubble/__tests__/gtmAgentBubble.test.js`
    (at minimum: `ab-fab`/`ab-fab--open`/`ab-root--docked` class toggling
    still matches the `rootClass`/`fabClass` getters; mood-to-mascot mapping
    unaffected; docked mode still skips the `empApi` subscription) and
    `force-app/main/default/lwc/gtmMascot/__tests__/gtmMascot.test.js`
    (at minimum: `svgClass` still composes `gus gus--{size} gus--{mood}` if
    any class renaming happens). If Open Fork F4/F5 is accepted, extend
    `gtmReadoutAssist`'s existing test suite (Developer to confirm its exact
    file name in the worktree) to cover the icon swap.
  - Run: `npx sfdx-lwc-jest -- gtmGusUtility gtmAgentChat gtmAgentBubble
    gtmMascot gtmReadoutAssist`, then the full `npm test`.
  - No Apex test target applies (zero Apex changed). If a new
    `staticresources` entry is added (fallback font path only, see §1.4),
    the only permitted org interaction is a validate-only `sf project
    deploy start --dry-run` against `gtm-staging` per `AGENTS.md` §2/§C
    org-request discipline — no `--run-tests` needed since no Apex changed.
    `scripts/check-references.py` should be run locally given new files are
    being introduced.

## 4. Open Forks for the Architect (not settled here)

- **F1 — FAB fill strategy.** Keep `gtmAgentBubble`'s solid-red circular
  fill and just correct the hex (`#E90024`→`#E90130`) vs. redesign to lead
  with black/white and use red as a smaller accent/ring, per the
  requester's "red is not the primary button colour" guidance (Tier C, not
  independently verified by this BA pass). Genuine visual-design fork, not
  guessed here.
- **F2 — Font-loading mechanism** (§1.4). Reuse `gtmStory`'s proven
  Google-Fonts-CDN link-injection pattern (recommended) vs. self-host as a
  new `staticresources` entry + `@font-face`. Also: extract a shared
  JS-only `c/gtmBrandFonts`-style module (precedented, viable) vs. duplicate
  the ~15-line loader 2-3 times (matches the existing CSS-token duplication
  precedent/reasoning in `gtmStory.css`).
- **F3 — Brand-token copy scope** (§1.3). Copy the full ~35-token
  `gtmStory.css` set into each GUS component's own `:host` block vs. copy
  only the subset actually used (red variants, ink, a couple of surfaces,
  the three font tokens). CSS custom properties cannot cross shadow
  boundaries between these sibling component trees either way, so some form
  of duplication is required regardless — the fork is only about how much.
- **F4 — Include `gtmReadoutAssist` in this pass?** (§1.2 item 4). Since it
  shares `gtmAgentChat.css`, restyling that file changes this surface's
  appearance regardless of intent. Recommended: yes, explicitly, since
  leaving it stock while its siblings get rebranded reintroduces the exact
  "inconsistent surfaces" problem this task exists to fix — but the brief
  never named it, so the Architect/owner should confirm rather than have it
  happen as an unannounced side effect.
- **F5 — `gtmReadoutAssist`'s `utility:einstein` icon → `c-gtm-mascot`.**
  Low-risk swap (no existing test references the icon, confirmed via
  `Grep`), bundle with F4 if accepted, otherwise skip.
- **F6 — `buildYourOwn.json` scope** (§1.5). Minimal 2-value color sync
  (recommended) vs. full site-chrome rebrand (fonts via `themes/
  buildYourOwn.json`'s `customCSS`, nav bar grays, login page). Recommend
  minimal; full chrome rebrand is separate, larger, higher-blast-radius work
  (touches every page of the live prod site) and should be its own scoped
  task.
- **F7 — Logo mark on `gtmGusUtility`** (§1.6). Add a PS shorthand mark
  (hard-blocked on the owner/brand team supplying an actual approved image
  asset — nothing to source in-code) vs. skip and keep `c-gtm-mascot` + text
  label only. Recommend skip by default; nothing in the request required a
  literal mark.
- **F8 — Mascot shape** (§1.7). No change (default, matches the request's
  literal scope: "the chat window," not the character) vs. some shape
  adjustment toward the brand's "architectural/grid-driven" language.
  Recommend no change; flagged for the owner's awareness only.

## 5. Ambiguities that only a human can resolve

- The specific brand-guideline claims in Tier C (§1.1) — exact contrast
  ratios beyond what `gtmStory.css` already computed, logo clear-space/
  minimum-size rules, the Global Brand Help Desk approval nuance, and the
  "red is not primary" philosophy — come only from the requester's own
  chat-summarized reading of a PDF this BA pass could not open. They are
  plausible and align with the two independently-corroborated facts (Tier
  B), but the Architect should treat the PDF itself as authoritative for
  anything this document did not independently re-derive, rather than this
  document's restatement of it.
- **F1 (FAB fill strategy)** is a genuine design fork between "correct the
  hex, keep the layout" and "restructure to lead with black/white" — a
  human call, not guessed here.
- **F7 (logo asset)** cannot be resolved by any coding agent regardless of
  decision — it requires a human-supplied, brand-approved image file that
  does not exist in this repo today.
- No production data is touched by this task (pure CSS/HTML/config), so the
  `gtm-prod` guest-data caution in this BA role's standing instructions does
  not apply in the data sense — but `buildYourOwn.json` (§1.5, F6) is
  live-site chrome config that does eventually promote to `gtm-prod` under
  the normal promotion flow, and any *real* deploy step remains gated on
  the owner's explicit go-ahead per `CLAUDE.md`, same as every other change.
