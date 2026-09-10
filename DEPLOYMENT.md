# Moving this to another Salesforce org

Everything under `force-app/` is standard **Salesforce DX (SFDX) source
format** -- objects, fields, Apex, LWCs, permission sets, the Experience
Cloud site metadata, all of it. That's not a packaging choice made for this
handoff; it's how this whole build has been developed all along, deployed
straight from this git repo with the `sf` CLI every time. Moving it to a
different org, or bringing it back after this Developer Edition org expires,
is the same operation as every deploy already done tonight -- there's no
separate "export" step.

**This runbook covers an org that already has its Experience Cloud sites and
base setup** — the path actually run against `gtm-dev` every time so far. For
a genuinely from-zero org, see `docs/runbooks/fresh-org-deploy.md` instead —
it's far more detailed, but less battle-tested; read its own caveat before
relying on it.

**Current status (D6 `MA_` → `GTM_` rename):** Complete. All five stages are
done and the repo is purely `GTM_`-only -- `MA_Saved_Configuration__c`, its
flow, and every permission-set/profile reference to it have been deleted.
The handful of already-distributed guest URLs that predate the rename keep
working through `GtmLegacyConfigId.resolve()`, which falls back to a
`Legacy_Id__c` lookup on `GTM_Saved_Configuration__c` -- it does not depend
on the old object existing. `scripts/data/migrate-saved-configuration-to-
gtm.apex` is kept as a historical record of the one-time data migration,
matching the convention for every other stage's migration script; it is not
part of a fresh-org deploy path and doesn't need to be run again.

## Quick start

```bash
sf org login web --alias my-new-org      # authenticate once
./scripts/deploy.sh my-new-org --run-tests
```

That deploys every top-level folder under `force-app/main/default/` --
objects, fields, permission sets, Apex, LWCs, flows, flexipages, bots,
profiles, remote site settings, the Experience Cloud site pages/theme, the
CSP trusted site, and the seeded custom metadata (`GTM_Offering__mdt`) --
into whatever org you point it at. It builds that folder list by scanning
the directory rather than hand-listing it, specifically so a new metadata
type added to the repo later can't silently drop out of the deploy the way
an earlier, hand-maintained version of this script did. See
`scripts/deploy.sh` for the plain `sf project deploy start` command it
wraps, if you'd rather run it by hand or drop it into a CI job.

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
Setup by hand (Custom Metadata Types → GTM Offering → Manage Records → New),
which is faster than continuing to fight a flaky deploy for one record.
Everything else deployed reliably throughout tonight's build with no such
flakiness.

## What a deploy can't do for you

Metadata deploy moves configuration; it doesn't touch a handful of
org-specific things that only make sense to set up once you're looking at
the actual target org:

- **Permission set assignments** -- `GTM_Config_Manager` (reps) and
  `GTM_Config_View_All` (stackable, "see everyone's links") need assigning to
  actual users. `GTM_Assessment_Guest` needs assigning to the target
  Experience Cloud site's **Guest User** profile specifically (Setup →
  Digital Experiences → your site → Administration → Pages, or via the
  guest user's own profile page).
- **The Claude API key** -- `GTM_Agent_Settings__c.Claude_API_Key__c` backs
  the GTM Configurator AI assistant (`GtmAgentProxyController`) and is
  deliberately never committed to source. Set it per org: Setup → Custom
  Settings → GTM Agent Settings → Manage → New.
- **Site activation** -- a freshly deployed Experience Cloud site starts
  inactive. Setup → Digital Experiences → All Sites → Activate, then
  Experience Builder → Publish.
- **Offering targets** -- `GTM_Offering__mdt`'s seeded `Migration Accelerator`
  record ships with placeholder Monthly/Annual targets ($20k / $250k).
  Real numbers go in Setup → Custom Metadata Types → GTM Offering → Manage
  Records.
- **Page content records** -- the public offering pages read their editorial
  copy from `GTM_Page_Content__c` / `GTM_Page_Section__c` /
  `GTM_Page_Content_Version__c` rows (schema only -- these are regular
  custom objects, so the schema itself travels with `scripts/deploy.sh`
  like any other object, but the actual content rows are data and don't).
  `scripts/seed-ma-page-content.apex` seeds a baseline set; run it with
  `sf apex run --file scripts/seed-ma-page-content.apex --target-org
  my-new-org` after the metadata deploy.
- **My Domain** -- if the target org doesn't have My Domain enabled yet,
  enable it before deploying the Experience Cloud site (Salesforce
  requires it for Digital Experiences).
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

## Sample / demo data

A fresh deploy carries schema and the one seeded `GTM_Offering__mdt` record
(the product's own real offering copy -- not sample data, that's what
every org running this app is actually selling) but no client-shaped
records: no engagement links, no accounts tied to this app, nothing to
demo with. Two scripts fill that gap, both built entirely through this
app's own real Apex entry points (`saveConfiguration`, `submitRequest`) so
they can't drift out of sync with real validation, scoring, or FLS:

- **`scripts/data/reset-accelerator-demo.apex`** -- four fictional clients
  (`Northlight Media Group (Demo)`, `Ashford Capital Bank (Demo)`, `Solara
  Health Systems (Demo)`, `Harborline Transit Authority (Demo)`, clearly
  labeled as such), spread across industries and source
  platforms, three converted to a scored assessment request and one that
  opened the link and dropped off -- a deliberately non-uniform, realistic
  spread rather than four identical "perfect" records. Safe to keep, edit
  the `spec` list for your own demo needs, or delete -- delete-then-rebuild,
  matched by name, and touches nothing else in the org.

```bash
sf apex run --file scripts/data/reset-accelerator-demo.apex --target-org my-new-org
```

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
