# UAT — GUS Chat Branding Refresh

**Date:** 2026-09-26
**PR:** https://github.com/iwintrose/gtm-offerings/pull/51
**Branch:** `agent/issue-gus-chat-branding-refresh` (commit `8c4b0277`)
**Scope doc:** `docs/agent-artifacts/task-scope-gus-chat-branding-refresh.md`

## Original ask

App owner, in chat: "GUS's Agentforce chat window looks stock — redesign it considering Sapient branding."

## What was verified live on `gtm-staging` (real deploy `0AfgK00000UbfHSSAZ`)

| Surface | Verified | Evidence |
|---|---|---|
| `gtmGusUtility` (internal Lightning Utility Bar) | ✅ | Opened the panel directly; mascot renders, panel white/branded, name label correct. |
| `gtmAgentChat` (shared chat engine, exercised via the Utility Bar) | ✅ | Sent a test message; computed style of the resulting `.bubble` element (read across shadow roots via JS) is `rgb(233,1,48)` = exactly `#E90130` — not the old deprecated red `#E90024`, not stock SLDS blue `#0070d2`. `font-family` resolves to `Roboto`, not `Inter`. A `link[href*="fonts.googleapis.com/css2"]` tag is present in the DOM, confirming the new `c/gtmBrandFonts` module's CDN injection actually ran. |
| `gtmReadoutAssist` (readout editor panel) | ✅ | Opened a real readout record (AR-7498, demo account "[DEMO] Northwind Apparel Group"); confirmed via accessibility-tree search that the GUS mascot image (`c-gtm-mascot`) is present in the panel, replacing the old generic `utility:einstein` icon. |
| `gtmAgentBubble` (Experience Cloud / configurator floating bubble) | ⚠️ not live-verified | The `GTM1` site's registered custom domain (`pu1789790920110.my.site.com/gtm`, confirmed via Setup > Digital Experiences > All Sites) redirects to the real public `publicissapient.com` marketing site instead of resolving to this sandbox's Experience Cloud site — reproduced identically via direct URL entry and via Setup's own link-click. This is a pre-existing domain/DNS misconfiguration in `gtm-staging`, independent of this diff. Logged as a follow-up in `docs/backlog.md`. |

## Indirect evidence for the unverified surface

- `git diff main -- force-app/main/default/lwc/gtmAgentBubble/gtmAgentBubble.css` shows the `#E90024` → `#E90130` change is textually scoped only to the intended rules (fill + `:focus-visible` outline), independently confirmed by both Developer and QA.
- `sf project deploy validate` against `gtm-staging` accepted `ExperienceBundle:GTM1`'s branding-set JSON schema change cleanly (0 component errors).

## Verdict

**UAT PASS**, with one known, tracked gap that is not a defect in this change: 3 of 4 named GUS chat surfaces are live-confirmed correct (brand red, brand fonts, mascot icon). The 4th (`gtmAgentBubble` on Experience Cloud) is blocked by an unrelated, pre-existing site-domain issue that should be fixed as its own follow-up so `/configurator` becomes testable in `gtm-staging` again — this affects any future task touching that route, not just this one.

## Before any deploy to `gtm-prod`

- Owner's explicit go-ahead required (per `CLAUDE.md` promotion flow — this is currently only merged/deployed to `gtm-staging` scope, not `main`/`gtm-prod`).
- Recommend fixing the `GTM1` site domain issue first (or at minimum acknowledging it) so the 4th surface can be confirmed before or shortly after prod promotion.
- The separately-flagged follow-up (3 stale `Inter` font-loader copies in `gtmConfigurator.js`/`chooseIndustry.js`/`offeringChooser.js`) is explicitly out of scope for this PR and should be filed as its own issue.
