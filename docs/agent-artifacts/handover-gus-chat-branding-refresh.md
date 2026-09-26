# Handover — GUS Chat Branding Refresh

**Status as of 2026-09-26:** BA scoping pass 1 is committed and pushed. BA
pass 2 (folding in 5 owner decisions below) was started and then
deliberately stopped mid-work by the owner before it committed anything —
so **the committed scope doc does NOT yet reflect the decisions in this
note**. Whoever picks this up should treat this note as the authoritative
record of those decisions until they're folded into the doc.

This is a documentation-only handover note, uncommitted, sitting locally in
the `main` working tree next to the actual scope doc. Not pushed anywhere.

## 1. Where things are

- Branch: `ba-scope/issue-gus-chat-branding-refresh` (pushed to origin,
  commit `9ed79a9c`).
- Scope doc: `docs/agent-artifacts/task-scope-gus-chat-branding-refresh.md`
  (531 lines, on that branch — not on `main`).
- This repo's multi-agent lifecycle (BA → Architect → Developer → QA, git
  worktree isolation) is defined in `AGENTS.md` §2 and `CLAUDE.md`. No
  feature code should be written directly in the main workspace — the next
  step is `gtm-architect` provisioning an isolated worktree via
  `scripts/agent-workspace.sh create gus-chat-branding-refresh`, which pulls
  the scope file from the branch above.

## 2. Original request

App owner, in chat, not a filed GitHub issue: *"GUS's Agentforce chat
window looks stock — redesign it considering Sapient branding."*

## 3. What GUS actually is (already verified, not in question)

GUS ("Go-To-Market Utility Sidekick") is a **fully custom LWC chat UI**, not
a native Salesforce Agentforce/Embedded Service widget. Backend is
`GtmAgentProxyController.cls`, calling Anthropic/OpenAI/Gemini directly —
per `docs/architecture/gus-chat-provider-settings.md` §5, "Agentforce is
never called" (that provider option is a saved-but-unused placeholder). So
this is a normal CSS/branding task on fully-controlled components, not a
Salesforce branding-config exercise. A separate, dormant Agentforce bot
scaffold exists (`force-app/main/default/bots/GTM_Configurator_Assistant/`,
`genAiPlugins/GTMApplyConfigUpdate*`) tied to an unrelated draft spec
(`docs/specs/agentforce-customizer-v2.md`) — not GUS, stays out of scope.

**Three surfaces share one chat engine** (`gtmAgentChat`, which itself has
138 lines of unbranded, stock SLDS-blue (`#0070d2`) CSS):
- `gtmGusUtility` — internal-only, Lightning Utility Bar host. Plain white
  panel, default SLDS styling. This is almost certainly the "stock" look
  the owner means.
- `gtmAgentBubble` — floating chat bubble on Experience Cloud/configurator
  (prospect-facing) pages. Already has legacy brand styling (see §5 below).
- `gtmReadoutAssist` — the readout editor's GUS panel. Previously unnamed in
  the original ask; also mounts the same stock `gtmAgentChat` engine, and
  currently uses a generic `utility:einstein` SLDS icon instead of GUS's own
  mascot.
- `gtmMascot` — GUS's SVG mascot, themed via CSS custom properties (e.g.
  `--gus-accent: var(--coral, #E90024)`).

## 4. Brand source of truth

Official guidelines: Google Drive, **"PS Brand Guidelines 04.2026.pdf"**
(file ID `1BdrIdgDlrHOKiFLaZsNUSCqDOmP1Daaf`, readable via the Google Drive
MCP connector). Key facts pulled from it:
- **Radiant Red `#E90130`** (RGB 233,1,48, PMS 199) is the current brand
  red — the old red was explicitly retired in this revision.
- Color philosophy: lead with black (`#000000`)/white (`#FFFFFF`), use red
  "with intention" as an accent/signal, not a dominant fill.
- Typography: **Lexend Deca SemiBold** (headlines), **Roboto Regular**
  (body), **Roboto Mono Medium** (sparingly — labels/eyebrows/timestamps).
  `Inter` is not part of the current system.
- Logo: the PS shorthand mark is internal-use-only without Global Brand
  Help Desk approval. Accessibility: WCAG AA, ≥4.5:1 contrast.

**Independent corroboration already inside this repo**, found while
scoping: `force-app/main/default/lwc/gtmStory/gtmStory.css` (lines 33-112)
already has a full, dated Publicis Sapient token block (`--ps-red:
#e90130`, `--ps-font-display: "Lexend Deca"`, `--ps-font-body: "Roboto"`,
`--ps-font-mono: "Roboto Mono"`, plus radius/shadow/dark-mode), whose own
header comment says it was derived from the **live publicissapient.com
stylesheet**, independently of the PDF. Two independent sources agree on
the red hex and the three font families. **Copy these tokens from
`gtmStory.css` — do not re-derive brand values from scratch or from the
PDF.**

## 5. The brand-drift problem this task exists to fix

The existing "branded" surfaces are themselves stale against the current
system above:
- `gtmAgentBubble.css`, `gtmConfigurator.css`, `offeringChooser.css`,
  `gtmMascot`, and `force-app/main/default/experiences/GTM1/brandingSets/
  buildYourOwn.json` (`ActionColor`/`LinkColor`) all still use the
  deprecated red `#E90024`.
- `buildYourOwn.json`'s `PrimaryFont`/`HeaderFonts` is `Inter`.
- **Font-loading duplication (found during scoping, sharper than first
  thought):** `gtmConfigurator.js`, `chooseIndustry.js`, and
  `offeringChooser.js` **each have their own separate `FONTS_HREF` constant
  still pointing at Google Fonts Inter** — stale. Only `gtmStory.js` already
  has the correct loader (`Lexend+Deca:wght@300;400;500;600&family=
  Roboto:wght@300;400;500;700&family=Roboto+Mono:...`). That's **4**
  independent copy-pasted "inject a Google Fonts `<link>`" implementations
  already in the codebase, 3 of them wrong. Strengthens the case to extract
  one shared JS module now (repo has precedent for shared JS-only LWC
  modules, e.g. `c/gtmNavigate`) rather than adding a 5th inline copy for
  GUS's surfaces.
- **Why `#E90024`/Inter exist at all:** commit `79dd8c88`, "agent/issue ps
  brand configurator (#128)" (merged 2026-09-13), deliberately branded
  `gtmConfigurator`/`chooseIndustry`/`offeringChooser`/`gtmAgentBubble`/
  `gtmMascot` to what it called "the confirmed Publicis Sapient palette
  (#E90024/white/black/#E6E6E6)" at the time. Nobody made an error — the
  brand system was updated since. That same commit also touched a second
  Experience Cloud site, `GTM_Accelerator1/brandingSets/buildYourOwn.json`,
  which has since been decommissioned (see branches
  `ba-scope/issue-decommission-gtm-accelerator1` /
  `issue-cleanup-gtm-accelerator1`) — **only `GTM1`'s branding set exists in
  the repo today.**
- `gtmAgentBubble.css`'s `.ab-fab` (lines 20-38) is a solid circular red
  button (`background: #E90024`, white icon), and its own code comment
  (lines 14-19) explicitly documents this as a deliberate **"Live-site
  pattern"** — a copy of publicissapient.com's actual launcher button from
  the same #128 commit, not an arbitrary/stock choice. The panel
  (`.ab-panel`) is already dark (`#1c1a18`) with off-white text
  (`#f2efe9`) — so the overall existing design is already "dark-led with a
  red accent launcher," structurally consistent with the brand philosophy.

## 6. Owner decisions — resolve these 5 items (not yet in the committed doc's §4 Open Forks)

The committed scope doc's Open Fork numbering (`F1`–`F8`) is in
`docs/agent-artifacts/task-scope-gus-chat-branding-refresh.md` §4. Mapping:

1. **F1 — FAB fill strategy: RESOLVED.** Keep `gtmAgentBubble`'s solid Radiant
   Red circular fill exactly as structured today — **do not** restructure to
   a black/white-led design. Just correct the hex `#E90024` → `#E90130`
   (also its `:focus-visible` outline on the same rule, and recompute any
   derived shades like `_ActionColorDarker`/`_ActionColorTrans`-style values
   wherever they appear). Rationale: the owner asked to check prior art
   first; the solid-red circular FAB is confirmed-intentional prior art
   (see §5 above), not a stock default in need of redesign.
2. **F4 + F5 — `gtmReadoutAssist`: RESOLVED, include it.** Bring it into this
   pass. Swap its generic `utility:einstein` icon for `c-gtm-mascot` — the
   owner confirmed GUS's icon/mascot already exists and should be reused,
   not rebuilt.
3. **F6 — `buildYourOwn.json` scope: RESOLVED, but broader than the doc's
   current "minimal 2-value" framing.** The owner wants the fix **reusable
   across any current or future GTM Offerings Experience Cloud site**, not
   a single-file patch — this is a refinement of "minimal," not a vote for
   the doc's "full site-chrome rebrand" alternative (that alternative is
   still out of scope; don't touch nav bar grays, login page, etc.). Do
   both: (a) fix `GTM1`'s `ActionColor`/`LinkColor` `#E90024`→`#E90130`
   (plus derived shades), and (b) write the exact field/value table up as a
   clear, reusable reference (in this scope doc or an architecture doc) so
   any future site's branding set is a copy-paste — mirroring however
   issue #128's "Architect addendum's field table" did this the last time a
   second site needed the same sync (worth digging up in that PR's history
   if it still exists). **Open question the doc doesn't answer yet:**
   whether `PrimaryFont`/`HeaderFonts` (`Inter`) should also be corrected in
   the same pass — since Experience Builder chrome here is Aura-rendered
   with no LWC-style JS hook to inject a font `<link>` (per the doc's own
   §1.5 note), verify whether the branding-set `PrimaryFont` field even
   accepts an arbitrary font name or only a fixed platform list before
   assuming this is a trivial value swap.
4. **F7 — Logo mark: RESOLVED, skip.** Matches the doc's existing default
   recommendation. No literal PS mark anywhere; `gtmGusUtility` keeps
   `c-gtm-mascot` + its existing "GUS" text label.
5. **F2 — Font-loading mechanism: sharpened, still open.** The doc hedged at
   "2-3" duplicate loader implementations; it's actually **4** (§5 above),
   3 of them shipping the wrong font live today. This strengthens (doesn't
   settle) the recommendation to extract one shared JS module (e.g.
   `c/gtmBrandFonts`) now rather than add a 5th copy. Still open for the
   Architect: (a) confirm shared-module extraction, and (b) decide whether
   to fast-follow-fix the 3 stale Inter consumers
   (`gtmConfigurator`/`chooseIndustry`/`offeringChooser`) in this same pass
   or file separately — recommend separately, since those are configurator
   pages, not GUS chat surfaces, and folding them in expands blast radius
   beyond what was actually asked for.

**Untouched, still open exactly as the committed doc states (no owner input
yet):** F3 (how much of `gtmStory.css`'s token set to copy per component)
and F8 (whether `gtmMascot`'s shape should shift toward the brand's
"architectural/grid-driven" language — soft note only, not a mandate).

## 7. Next step

Hand to `gtm-architect`: fold the 5 resolutions above into
`task-scope-gus-chat-branding-refresh.md` §4/§1.5 on the
`ba-scope/issue-gus-chat-branding-refresh` branch, then provision the
worktree. From there, `gtm-developer` implements inside the isolated
worktree (never in the main workspace) and `gtm-qa` validates against the
updated scope doc before a PR is opened. Real deploys to `gtm-staging`/
`gtm-prod` stay gated on the owner's explicit go-ahead per `CLAUDE.md`,
same as every other change in this repo.
