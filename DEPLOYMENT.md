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
minutes earlier. Retrying it 2-3 times cleared it every time it happened;
if it doesn't, it's a single record with three fields and is faster to
create by hand in Setup than to keep debugging (the script tells you how
when it fails). Everything else deployed reliably throughout tonight's
build with no such flakiness.

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
