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
