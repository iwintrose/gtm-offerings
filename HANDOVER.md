# Claude Code Handover — Salesforce GTM Story & Accelerator Deployment

**Session Date:** 2026-09-06 (latest — see below for the 2026-08-26 session that follows)
**Status:** PR merged to `main`; **org deploy + browser verification still outstanding** (see "What's Still Outstanding" at the top).

---

## Session 2026-09-06 — GTM Offerings admin app audit & overhaul

**What this was:** a full audit + fix pass on the internal "GTM Offerings" Lightning app —
the admin/CMS tool (distinct from the public-facing Story/Accelerator/Configurator pages
covered by the 2026-08-26 session below). Three tabs: **Overview** (`gtmOverview`),
**Content Home** (`gtmContentHome`), **Content Manager** (`gtmContentManager` +
`gtmFieldEditor` + `gtmPagePreview`), shared shell/tokens in `gtmAppShell`.

**Branch:** `claude/gtm-offerings-audit-overhaul-amttpu` → merged to `main` via
[PR #6](https://github.com/ps-salesforce/gtm-offerings/pull/6). Read the PR description for
the full list of changes (real bugs fixed, cross-tab consistency, plain-language copy,
rep-facing loading/retry feedback, Content Home search, an SLDS `lightning-badge` swap).

**Process, if you need to trust-but-verify this work:** multi-persona audit (QA, functional
trace, Business Partner, Sales/BD rep, CX, and a UI/UX pass grounded in outside research on
Salesforce SLDS/CMS/sales-enablement conventions) → parallel implementation agents on
non-overlapping files → a human-journey trace + research-grounded UI/UX pass to catch
cross-agent drift → an adversarial code review of the full diff, which caught one real
regression before merge (see below) → a focused confirmation pass on that fix → merge.

**The one thing the review caught (now fixed, commit `ab70b91`):** the shared `--gtm-*`
CSS custom properties (text/border/surface/danger/radius/font-size tokens) were originally
defined only on `gtmAppShell`'s `:host`. But `gtmOverview`, `gtmContentHome`,
`gtmContentManager`, `gtmFieldEditor`, and `gtmPagePreview` each live on their own
Tab/FlexiPage in the org — they are **never** rendered as children of `gtmAppShell` (only
`offeringChooser`/`chooseIndustry`/`maConfigurator` are). CSS custom properties don't cross
separate shadow-DOM trees, so every `var(--gtm-*)` reference in those five components would
have resolved to nothing in the live org. Fixed with a CSS-only LWC module
(`force-app/main/default/lwc/gtmTokens/gtmTokens.css`, no `.js`/`.html`) that each component
now pulls in via `@import 'c/gtmTokens';` as the first line of its `.css` file — the standard
LWC pattern for sharing tokens across sibling component trees that aren't parent/child.
**If you add a new component that needs these tokens, add the same `@import` line — don't
redefine the hex values locally.**

**What was explicitly NOT done, and why (don't redo this without re-reading the reasoning
in the PR):**
- No search/filter added to Content Manager's offering/page picker — it's a
  `lightning-combobox` with at most 4 fixed template options, not a scrollable list.
- Did not convert Content Home's page list to `lightning-datatable` — each offering always
  renders exactly 4 fixed template rows grouped under its own card; datatable has no native
  per-group headers, and converting would trade the "scan one offering's readiness at a
  glance" layout (specifically praised by the Business Partner/CX review) for a generic flat
  table with no benefit at this fixed, small row count.
- No page-level published/draft status badge in Content Home's list — the backing Apex
  (`MaPageContentController.getHomeSummary`, uses `COUNT(Id)` GROUP BY queries) doesn't
  return that field today. Needs a backend change to `PageSummary`/`getHomeSummary` before
  it can be surfaced — flagged, not guessed at.

**What genuinely still needs a human (no Salesforce CLI/org auth was available in the
session that did this work):**
- Run `sf project deploy start --source-dir force-app/main/default/lwc` against a
  sandbox/dev org and confirm it deploys clean.
- Walk the PR's test plan checklist in-browser, in particular the CSS-token fix above (the
  fix was verified by static review — token names matching, `@import` ordering, the LWC
  reference-checker not flagging it as an orphan — but never actually rendered in a browser
  against the real org, since this session couldn't do that).
- If a page-level draft/published status badge is wanted later, that's a `backend-engineer`-
  style task: add the field to `MaPageContentController.getHomeSummary`'s query/return shape
  first, then surface it in `gtmContentHome.js`'s `cards` getter.

---

## Salesforce CLI Auth (CRITICAL — do this first every session)

The org auth URL is stored as environment variable `SFDX_AUTH_URL` in the CCR environment.
Run this at the start of every session before any `sf` commands:

```bash
echo "$SFDX_AUTH_URL" | sf org login sfdx-url --sfdx-url-stdin --set-default
```

Then deploy with:
```bash
git clone --depth 1 https://github.com/ps-salesforce/gtm-offerings /home/user/gtm-offerings  # if not already cloned
cd /home/user/gtm-offerings
git fetch origin lwc-scaffold-import
git checkout lwc-scaffold-import
sf project deploy start --source-dir force-app/main/default/lwc/<component>
```

**Org:** `isiah.wint-rose.befef12c6b6c@agentforce.com`
**Site URL:** `https://orgfarm-5c323065da-dev-ed.develop.my.site.com/gtmaccelerator`

---

## Repos & Branches

| Repo | Branch | Contains |
|---|---|---|
| `ps-salesforce/gtm-offerings` | `main` | Static HTML (index, story, configurator) |
| `ps-salesforce/gtm-offerings` | `lwc-scaffold-import` | Salesforce LWC source (`force-app/`) |
| `ps-salesforce/ma-migrator` | `claude/ma-migrator-prd-sqca8j` | Backend platform |

**LWC local path (user's Mac):** `/Users/isiwintr/Documents/Workbench/GTM_Ogfferings/MA_Migrator/ebikes-lwc-scaffold/`
Remote: `gtm-offerings` → `lwc-scaffold-import`

To pull latest from cloud and deploy locally:
```bash
cd /Users/isiwintr/Documents/Workbench/GTM_Ogfferings/MA_Migrator/ebikes-lwc-scaffold
git pull gtm-offerings lwc-scaffold-import
sf project deploy start --source-dir force-app/main/default/lwc/<component>
```

---

## What's Done

1. ✅ **Apex Backend** — MaAssessmentRequestController deployed
   - CMDT fields: Activity_Type__c, Create_Lead__c, Lead_Source__c, Notify_Email__c, Send_Email__c
   - Controller uses dynamic field access via `.get()` to work around compiler caching
   - Permission Set: MA_Assessment_Guest (guest user access for booking form)

2. ✅ **LWC Components** — All 7 built and committed to `lwc-scaffold-import`
   - maStory, offeringChooser, chooseIndustry
   - maConfigBooking, maConfigCustomize, maConfigurator, maConfigData

3. ✅ **Day/Night theme persistence** (2026-08-26)
   - Static HTML pages (index, story, configurator) now read/write `ps_theme` to localStorage
   - Theme survives page navigation; inline script sets it before CSS renders (no flash)
   - `configurator.html` dark media query fixed to use `:root:not([data-theme="light"])`
   - PR: https://github.com/ps-salesforce/gtm-offerings/pull/3

4. ✅ **Light brand color contrast fix** (2026-08-26)
   - `maConfigurator.js` `rootStyle` getter now computes WCAG luminance
   - Sets `--on-coral` (dark ink for light brands, white for dark), `--coral-soft` via rgba(),
     `--coral-ink` (darkened hover shade), `--coral-ring` (visible outline for near-white brands)
   - `.cobrand .cb-mono` uses `var(--on-coral)` + `var(--coral-ring)` — no more hardcoded `#fff`
   - LA Metro (`accent=ffffff`) now renders buttons/monogram/eyebrow visibly in day mode
   - Deployed to `lwc-scaffold-import`; user must `git pull` + `sf project deploy start`

---

## What's Still Outstanding

### 1. Deploy maConfigurator contrast fix to org
User ran `git pull gtm-offerings lwc-scaffold-import` and needs to deploy:
```bash
sf project deploy start --source-dir force-app/main/default/lwc/maConfigurator
```

### 2. Fix maStory CTA Link
**Issue:** Links to `/gtmstory/s/` — should be `/gtmaccelerator`
```bash
grep -r "gtmstory\|/s/" force-app/main/default/lwc/maStory/
```
Update the URL, commit to `lwc-scaffold-import`, push, deploy.

### 3. Verify Public Access on maStory
- Setup → Digital Experiences → All Sites → Activate
- Experience Builder → Settings → General → "Public can access the site" ✓
- Publish site

---

## Key Working Agreement

1. **Edit in cloud, commit to GitHub, deploy via `sf`** — never edit files only locally
2. **LWC source lives on `lwc-scaffold-import`** — static HTML on `main`
3. **Read screenshots carefully** — field names, API names, exact values matter
4. **Verify before claiming success** — grep/cat after edits
5. **Never brute-force retries** — diagnose root cause first
6. **Salesforce CLI auth** — always run the `sfdx-url-stdin` command first
