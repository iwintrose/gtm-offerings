# Claude Code Handover — Salesforce GTM Story & Accelerator Deployment

**Session Date:** 2026-08-26
**Status:** Active — day/night theme bug fixed, Salesforce CLI auth configured.

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

### 1. Delete the GTM Framework site (manual)
`gtmframework` is `DownForMaintenance`, and its published Home page still
carries `c:gtmAppShell`. That pins the component: the org refuses to delete
`gtmAppShell` while a published instance references it, and the site cannot be
published to clear it while it is deactivated. Delete the site in Setup →
Digital Experiences → All Sites, then:

```bash
# destructiveChanges.xml naming LightningComponentBundle gtmAppShell
sf project deploy start --metadata-dir <dir>
```

### 2. Duplicate FlexiPages in the org
The org has three `Assessment_Request_Record_Page` FlexiPages (`_1`, `_2` are
duplicates); this repo has one. Harmless, but the extras should be deleted so
the org and the branch agree.

### 3. Match Gus to the Betty/Dex character sheet
`c/gtmMascot` is built from chibi principles rather than from the existing
character designs, because those were not available. Line weight, eye shape and
palette should be reconciled against them.

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
