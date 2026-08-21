# Claude Code Handover — Salesforce GTM Story & Accelerator Deployment

**Session Date:** 2026-08-20  
**Status:** Apex deployed successfully. One link fix remaining.

---

## What's Done

1. ✅ **Apex Backend** — MaAssessmentRequestController deployed
   - CMDT fields created and fixed (were named wrong initially: `Activity_Type_c_c` → `Activity_Type__c`)
   - Controller uses dynamic field access via `.get()` to work around compiler caching
   - Test class compiles
   - All permission sets configured for guest user

2. ✅ **LWC Components** — All 7 bundled built
   - maStory, offeringChooser, chooseIndustry
   - maConfigBooking, maConfigCustomize, maConfigurator, maConfigData
   - Ready to deploy

3. ✅ **Cloud Workflow Established**
   - gtm-offerings repo cloned to `/home/user/gtm-offerings`
   - Ready to make edits in cloud and push

---

## What's Left

### 1. Fix maStory CTA Link (BLOCKER)
**Issue:** maStory component has a CTA at the bottom that links to `/gtmstory/s/` but should link to `/gtmaccelerator`

**Location:** Find in user's local `/Users/isiwintr/Documents/Workbench/GTM_Ogfferings/MA_Migrator/ebikes-lwc-scaffold/force-app/main/default/lwc/maStory/`

**Action Required:**
- Have user search: `grep -r "gtmstory\|/s/" force-app/main/default/lwc/maStory/`
- Update the URL from `/gtmstory/s/` to `/gtmaccelerator`
- Redeploy LWC components

### 2. Deploy LWC Components
After link fix, deploy all LWCs to the org

### 3. Verify Public Access on maStory
- Activate site: Setup → Digital Experiences → All Sites → gtm-story → Activate
- Enable public: Experience Builder → Settings → General → "Public can access the site" ✓
- Publish site

---

## Key Working Agreement (CRITICAL)

**File:** `/home/user/gtm-offerings/.claude-memory.md`

**Most Important Rules:**
1. **Read every detail in screenshots** — Don't gloss over field names, API names, or values
2. **Verify before claiming success** — grep/cat the file after edits, not just "I fixed it"
3. **Never brute-force retries** — Diagnose root cause first
4. **Maintain working directory context** — User is on local Mac at `/Users/isiwintr/...`, NOT `/home/user/`
5. **Work in the cloud repo** — Clone, edit, commit, push so user can pull locally

---

## Repos & Branches

**ps-salesforce/ma-migrator** (backend platform)
- Branch: `claude/ma-migrator-prd-sqca8j`
- Status: Working agreement committed

**ps-salesforce/gtm-offerings** (marketing/offerings, includes Salesforce LWCs)
- Branch: `main` (or user's preferred branch)
- Status: Ready for ebikes-lwc-scaffold to be committed here

**User's Local Salesforce Project** (NOT in GitHub yet)
- Path: `/Users/isiwintr/Documents/Workbench/GTM_Ogfferings/MA_Migrator/ebikes-lwc-scaffold/`
- Contents: All Salesforce LWC + Apex from this session
- Action: Should be committed to gtm-offerings repo

---

## Salesforce Org Info

**Org:** `isiah.wint-rose.befef12c6b6c@agentforce.com`  
**CLI Auth:** Already configured locally  
**CMDT:** MA_Assessment_Config__mdt with 5 fields (all deployed)
- Activity_Type__c (Text 255)
- Create_Lead__c (Checkbox)
- Lead_Source__c (Text 255)
- Notify_Email__c (Email)
- Send_Email__c (Checkbox)

**Permission Set:** MA_Assessment_Guest (guest user access for booking form)

---

## Next Agent's Tasks

1. **Immediate:** Fix maStory CTA link (ask user to grep, provide exact change)
2. **Then:** Deploy all LWC components
3. **Then:** Test public access on maStory
4. **Then:** Commit ebikes-lwc-scaffold to gtm-offerings repo
5. **Stretch:** Any remaining config/customization

**REMEMBER:** Use the cloud repo workflow. Edit in cloud, commit, push, user pulls locally.
