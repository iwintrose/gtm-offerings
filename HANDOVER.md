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

_Last verified against the org on 2026-09-04. The three items that used to sit
here (deploy the contrast fix, fix a `/gtmstory/s/` CTA, verify public access)
are done or moot — the CTA they named no longer exists in the code._

### 1. ~~Delete the GTM Framework site~~ — resolved; the method is worth keeping

Salesforce **never** deletes an Experience Cloud site: `destructiveChanges` on
the bundle returns *"You can't delete an Experience Cloud site."* Archiving is
not enough either — an archived site keeps a **published snapshot**, and a
component referenced by that snapshot cannot be deleted.

What actually clears it, when a component has to go:

1. Unarchive the site (UI only — there is no API path: `Network` is not
   updatable from Apex, and `PATCH /connect/communities/{id}` returns
   `METHOD_NOT_ALLOWED`).
2. Deploy the site's `Network` metadata with `<status>UnderConstruction</status>`.
   `Live` is rejected with a misleading *"still active … before you archive"*;
   `UnderConstruction` is accepted.
3. Deploy the edited `ExperienceBundle` so the Development instance no longer
   references the component.
4. `sf community publish --name "<site>"` — this is what replaces the published
   snapshot. It fails with `INSUFFICIENT_ACCESS` while the site is inactive.
5. Run the destructive deploy. It now succeeds.
6. Put the site back with `<status>DownForMaintenance</status>`.

### 2. Duplicate FlexiPages in the org
The org has three `Assessment_Request_Record_Page` FlexiPages (`_1`, `_2` are
duplicates); this repo has one. Harmless, but the extras should be deleted so
the org and the branch agree.

### 3. Match Gus to the Betty/Dex character sheet
`c/gtmMascot` is built from chibi principles rather than from the existing
character designs, because those were not available. Line weight, eye shape and
palette should be reconciled against them.

---

## Why a rep sees the rep experience on the public site

Two things have to be true, and both were false at different times:

**1. The site must authenticate internal users.** `Network.allowInternalUserLogin`
was `false` on GTM Accelerator and GTM Story, so an internal user opening a
`my.site.com` link was served as the site's **guest user** even while logged
into the org. Everything gated on "is this a rep" then failed closed: Gus and
the saved links bar were hidden, and a prospect link demanded its password from
the person who created it. It is `true` on both sites now.

This is org configuration and is deliberately **not** in this repo — a full
`Network` file would replace live site settings on any future deploy, which is
the drift problem that has already cost this project real UI. To change it:

```bash
sf project retrieve start --metadata "Network:GTM Accelerator" --target-metadata-dir /tmp/n
# edit allowInternalUserLogin, then deploy that one file back
```

**2. The page must be able to ask who is looking.** See `MaViewerContext.isRep()`
— an internal Salesforce user is a rep, the site guest user is not. It lives in
its own class because Apex access is granted per class: asking this through
`MaSavedConfigurationController` would have exposed `saveConfiguration`,
`deleteConfiguration` and `searchContacts` to the public.

---

## Before deleting any component

`scripts/check-references.py` scans **this branch**. Experience Builder keeps
page layouts in the org, and they do not reliably round-trip through the site
bundles in source — `maAdminBar` and `gtmAppShell` both read as orphans here
while the org had them on four live pages. Confirm against the org first
(the script prints the commands), or let the destructive deploy refuse: it
names the exact pages, which is the authoritative answer.

## Key Working Agreement

1. **Edit in cloud, commit to GitHub, deploy via `sf`** — never edit files only locally
2. **LWC source lives on `lwc-scaffold-import`** — static HTML on `main`
3. **Read screenshots carefully** — field names, API names, exact values matter
4. **Verify before claiming success** — grep/cat after edits
5. **Never brute-force retries** — diagnose root cause first
6. **Salesforce CLI auth** — always run the `sfdx-url-stdin` command first
