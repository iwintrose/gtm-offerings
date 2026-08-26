# Moving this to another Salesforce org

Everything under `force-app/` is standard **Salesforce DX (SFDX) source
format** -- objects, fields, Apex, LWCs, permission sets, the Experience
Cloud site metadata, all of it. That's not a packaging choice made for this
handoff; it's how this whole build has been developed all along, deployed
straight from this git repo with the `sf` CLI every time. Moving it to a
different org, or bringing it back after this Developer Edition org expires,
is the same operation as every deploy already done tonight -- there's no
separate "export" step.

## Quick start

```bash
sf org login web --alias my-new-org      # authenticate once
./scripts/deploy.sh my-new-org --run-tests
```

That deploys every object, field, permission set, Apex class, LWC, the
Experience Cloud site pages/theme, the CSP trusted site, and the seeded
custom metadata (`MA_Offering__mdt`) -- everything built this session --
into whatever org you point it at. See `scripts/deploy.sh` for the plain
`sf project deploy start` command it wraps, if you'd rather run it by hand
or drop it into a CI job.

The script deploys in two passes (everything, then the custom metadata
*records* separately) because bundling a custom metadata *type* and its
seed record in one transaction proved unreliable in testing -- and even
deployed on its own, that one record intermittently failed with a generic
`UNKNOWN_EXCEPTION` against identical content that had deployed cleanly
minutes earlier. Every time that happened tonight, a bare retry cleared it
within a couple of attempts, so pass 2 retries itself automatically (up to
4 attempts, 10s apart) rather than making you notice a failure and re-run
a command by hand -- you'll only see it surface as a real problem if all
of those fail, at which point it prints the exact 3 fields to punch into
Setup by hand (Custom Metadata Types → MA Offering → Manage Records → New),
which is faster than continuing to fight a flaky deploy for one record.
Everything else deployed reliably throughout tonight's build with no such
flakiness.

## What a deploy can't do for you

Metadata deploy moves configuration; it doesn't touch a handful of
org-specific things that only make sense to set up once you're looking at
the actual target org:

- **Permission set assignments** -- `MA_Config_Manager` (reps) and
  `MA_Config_View_All` (stackable, "see everyone's links") need assigning to
  actual users. `MA_Assessment_Guest` needs assigning to the target
  Experience Cloud site's **Guest User** profile specifically (Setup →
  Digital Experiences → your site → Administration → Pages, or via the
  guest user's own profile page).
- **Site activation** -- a freshly deployed Experience Cloud site starts
  inactive. Setup → Digital Experiences → All Sites → Activate, then
  Experience Builder → Publish.
- **Offering targets** -- `MA_Offering__mdt`'s seeded `Migration Accelerator`
  record ships with placeholder Monthly/Annual targets ($20k / $250k).
  Real numbers go in Setup → Custom Metadata Types → MA Offering → Manage
  Records.
- **My Domain** -- if the target org doesn't have My Domain enabled yet,
  enable it before deploying the Experience Cloud site (Salesforce
  requires it for Digital Experiences).
- **The GTM Offerings CMS Workspace** -- `force-app/main/default/managedContentTypes/`
  defines the *schema* for the offering's editorial content (five types:
  `ma_industry_story`, `ma_faq_item`, `ma_story_setting`, `ma_story_page`,
  `ma_story_body`), but a CMS **Workspace** to actually author content into
  (`ManagedContentSpace`) has no Metadata API representation at all, so it
  can never travel with `scripts/deploy.sh`. Run
  `./scripts/setup-cms-workspace.sh <org-alias>` after deploying -- it's
  idempotent (safe to re-run, does nothing if the Workspace already exists)
  and uses the Connect REST API directly since there's no metadata type to
  deploy. Once it exists, the 5 content types are immediately usable in it.
  Still manual either way: granting CMS Workspace access (Contributor/
  Publisher) to whoever authors this content -- that's its own permission
  system, separate from every Profile/PermissionSet grant elsewhere in this
  doc, and needs setting per person in Setup > Digital Experiences > CMS
  Workspaces > GTM Offerings > Access.

- **CMS content records + `MA_CMS_Content_Index__c` rows** -- the LWC story
  page reads editorial copy entirely from CMS. Deploying the schema and
  Workspace isn't enough: someone has to create the actual content records,
  **publish** each to the GTM Offerings Channel, and then insert one
  `MA_CMS_Content_Index__c` row per record so the Apex controller can find
  them (the CMS delivery API has no "list by type" query, so the index object
  is the bridge). A blank org gets the hardcoded DEFAULTS fallbacks in
  `maStory.js` until those records exist and are indexed. The seeding process:

  1. In Setup → Digital Experiences → CMS Workspaces → GTM Offerings → Content,
     create records for each type using the Salesforce UI or the Connect REST
     authoring API (`POST /services/data/v66.0/connect/cms/contents`).
     The body must include both a top-level `title` field and `title` inside
     `contentBody` (the NAMEFIELD), plus `contentSpaceOrFolderId`.
  2. Publish each record to the **GTM Offerings Channel** (the delivery API
     only serves published content -- draft records return 404).
  3. For each published record, insert one `MA_CMS_Content_Index__c` row:
     ```bash
     sf data create record --target-org <alias> --sobject MA_CMS_Content_Index__c \
       --values "CMS_Record_Id__c=<managedContentId> Content_Type__c=<type> \
                 Offering_Key__c=migration-accelerator Display_Order__c=1 Active__c=true"
     ```
  4. Set `MA_Offering__mdt.CMS_Channel_Id__c` to the channel's ID (find it via
     `GET /services/data/v66.0/connect/cms/delivery/channels` or the Workspace
     API -- it's an 18-character ID starting with `0ap`). Without this the
     Apex controller throws before ever touching the index.

  The PATCH endpoint for updating a published CMS record's `contentBody` is
  not exposed (`GET, HEAD` only) -- to update an existing record, create a new
  one with the corrected content, publish it, and point the index row at the
  new `managedContentId`.
- **Experience Cloud site membership** -- separate from every permission
  above, and easy to miss: a profile also needs to be an explicit *member*
  of the site (Setup → Digital Experiences → your site → Administration →
  Members) before a user on that profile can log into it as an
  authenticated member at all. Object/tab/Apex/app access alone isn't
  enough -- without site membership they'll hit the site as if logged out,
  no matter what else is granted. This bit us directly: `Standard` and
  `Standard Platform User` had full object/Apex access before being added
  as site members, and users on those profiles still saw the guest
  experience until the membership itself was added. It's a **data**
  record (`NetworkMemberGroup`), not metadata, so it does NOT travel with
  `scripts/deploy.sh` or show up in `git diff` -- it has to be set on
  every target org separately. Quick check/fix via the CLI once you know
  the site's Network Id and the profile's Id:
  ```bash
  sf data query --query "SELECT Id, Name, UrlPathPrefix FROM Network" --target-org my-new-org
  sf data query --query "SELECT ParentId FROM NetworkMemberGroup WHERE NetworkId='<network id>'" --target-org my-new-org
  sf data create record --sobject NetworkMemberGroup \
    --values "NetworkId='<network id>' ParentId='<profile id>'" --target-org my-new-org
  ```

None of these are things a script should guess at on your behalf --
wrong values here are org-specific judgment calls, not defaults to bake in.

## If this needs to go to *many* orgs, not just one

Everything here already qualifies to become a proper **unlocked package**
(`sf package create` + `sf package version create`) with no restructuring --
that's the standard way Salesforce partners/ISVs distribute exactly this
kind of "reusable accelerator" across multiple client orgs, with version
history and upgrade paths instead of re-running a deploy script by hand
each time. It needs a Dev Hub-enabled org and a namespace decision, which
is a real choice (not free, and not reversible for a namespace once
picked) -- worth doing deliberately when you actually have a second or
third org to install into, not preemptively for a single Developer Edition
org. The `sf` CLI, this same `force-app/` tree, and this same deploy
workflow are the on-ramp either way.
