# Salesforce org setup and GTM Offerings installation

A generic, start-to-finish install of GTM Offerings into any Salesforce org.
Replace `<org-alias>` with the alias you give the org in the Salesforce CLI. No
org is assumed. Deep detail (why each pass exists, the reference table behind the in-app Setup rows,
the consecutive-underscore risk, the verification checklist) lives in
[`fresh-org-deploy.md`](fresh-org-deploy.md); this page is the path through it
and does not repeat it. Contracts: `docs/architecture/blank-install.md` and
`docs/architecture/site-shell-metadata.md`.

> **Status of the site step.** Pass 9 deploys the Aura site shell (Network +
> CustomSite) and the ExperienceBundle in one combined deployment. That pattern
> has not yet been proven against a live org. Validate with `--check-only` first
> and expect to read the troubleshooting section below.

---

## 1. Prerequisites and toggles

Do these in the target org before deploying.

| Item | Where | Notes |
|---|---|---|
| Edition | - | Must support Experience Cloud, custom objects, custom metadata, Apex, approval processes (Developer, Enterprise, Unlimited, Performance). |
| Security Contact | Setup, the prompt that appears on first login | Some new orgs force you to enter a Security Contact before you can use Setup. Complete it; the CLI login can otherwise stall on the same screen. |
| My Domain | Setup > My Domain | Deploy it to users and let it finish. Digital Experiences will not enable without it, and it changes every URL in the org, so do it first. |
| Digital Experiences check | Setup > Digital Experiences > Settings | The deploy enables it (pass 8), but check the feature is available in this org. A demo-type org without it fails pass 8. Enabling it by hand first is harmless and irreversible. |
| Chatter | Setup > Chatter Settings | Required by the site template. |
| Dev Hub | Setup > Dev Hub | Only if you will create scratch orgs or packages. Not needed for a plain deploy. |

Tooling on your machine: the Salesforce CLI (`sf`), Python 3.8+, and a clone of
this repository. `npm install` only if you will run the LWC tests.

## 2. Authorize the org

```bash
sf org login web --alias <org-alias>
sf org list        # confirm the alias is present and Connected
```

Never deploy without an explicit alias: the scripts refuse to guess one.

## 3. Deploy

Run from the repository root.

```bash
python3 scripts/check-references.py                      # static audit; must exit 0
./scripts/deploy-fresh-org.sh <org-alias> --check-only   # dry run: validates, changes nothing
./scripts/deploy-fresh-org.sh <org-alias>                # real deploy, framework only
```

Notes:

- `--check-only` is a Salesforce validation (`--dry-run`), not the `-c` flag. In
  the `sf` CLI `-c` means `--ignore-conflicts`; never use it as a dry run.
- The script stops at the first failing pass. Read the error; do not just re-run.
- **Site sender address.** Pass 9 needs a Network `emailSenderAddress`. By
  default the script uses the email of the authorized user (the admin running the
  deploy), read from the target org with one org-info call and one query. To
  override, set `GTM_SITE_SENDER_EMAIL=<address>` first. The address is only
  shown masked, is injected into a temp package that is deleted on exit, and is
  never written into the repo. Salesforce may send a verification email to it;
  the admin may need to click the link before the sender is active.
- **Publish the site** after the deploy, because a deploy only updates the draft:

  ```bash
  sf community publish --name "GTM" --target-org <org-alias>
  ```

  The site is named `GTM` (Network and CustomSite); its bundle is `GTM1`.
  Activate it too: Setup > Digital Experiences > All Sites.

Other flags: `--with-profiles`, `--with-agent` (only if Agentforce is
provisioned), `--run-tests` (see section 5).

## 4. The blank default and Test Offering

The default install is the **framework only**: schema, code, UI, automation,
access and the site shell. It has **no offering, no instrument and no data**.

To prove a blank install works, add the Test Offering pack:

```bash
./scripts/deploy-fresh-org.sh <org-alias> --with-offering test-offering
```

This installs one offering labelled `Test Offering` (key `test-offering`, no
instrument) and one page row reading `TEST RECORD - safe to delete`. Delete it
when you are done. It is kept outside `force-app/` so the incremental
`scripts/deploy.sh` can never ship it to a production org.

`--with-offering` is repeatable and **re-runnable**: seed rows that already exist
are skipped ("already loaded, skipping"), never overwritten, so the same command
is safe to run again. A partly loaded seed is reported and skipped, not
duplicated. `--with-demo-data` is skipped when demo rows exist. Add `--with-demo-data` to also load synthetic
demo records (separate from any pack).

## 5. Optional: the Migration Accelerator pack

```bash
./scripts/deploy-fresh-org.sh <org-alias> --with-offering migration-accelerator
```

Installs the Migration Accelerator offering, its questions, pairs, gates,
supplements, platforms and story seed (from `instrument/migration-accelerator/`,
generated by `scripts/build-instrument.py`; never hand-edit the generated
records). If a custom metadata pass fails on a DeveloperName, read
`fresh-org-deploy.md` section 9 before retrying.

**`--run-tests` needs this pack.** Thirty-eight Apex test classes read its custom
metadata, so `--run-tests` on a framework-only or Test-Offering-only org is
expected to fail in those classes.

## 6. Post-install steps

Open the **GTM Offerings** app > **Settings** tab > **Setup** (the first, default
section). It checks the org, shows what is done and what is not, and does what it
can in one click (assign permission sets, create the empty framework pages,
schedule the two purge jobs). Each row says what it is for; nothing is relayed
by hand and nothing is seeded for you: you add your own industries and offerings
through the app. Re-check re-reads the org; the checklist never remembers a
"done", so it cannot drift.

Only if the deploying user cannot see the Settings tab (no GTM permission set
yet), assign them `GTM_Offering_Admin` in Setup > Permission Sets > Manage
Assignments, then open Setup. When a seed ran (`--with-offering` or
`--with-demo-data`) the script already assigned `GTM_Offering_Admin` and
`GTM_Content_Admin` to the deploying user, so this is rarely needed.

**AI keys are optional.** Only the GUS chat assistant uses one; it appears in Setup
as an optional, collapsed row and never counts as unfinished. Keys are entered in
the Settings tab, never in source or a chat.

Two things are still outside Setup by nature: publishing the site after a deploy
touching `experiences/` (section 3) and the verification walk (section 7).
`fresh-org-deploy.md` section 6 keeps the reference table behind each Setup row.

**Remote sites.** Earlier notes said to point two "org-self-callout" remote sites
at this org's My Domain. Checked against source: there are none. The seven remote
sites in `force-app` all point at external hosts, and no Apex calls the org's own
domain (`URL.getOrgDomainUrl()` is only used to build links, not to call out).
Nothing to configure. (`Conduit_Local` points at a developer tunnel URL; it is
irrelevant unless you use the Conduit tooling.)

**Sharing logs.** The script masks the sender address, but the `sf` CLI's own
output is not redacted: it prints the org username in its "Deploying ... to
<username>" and "Permsets Assigned" lines. Whoever (human or agent) shares a
deploy log should redact the username first. Do not treat the script's output as
fully username-free.

## 7. Verify

Walk `fresh-org-deploy.md` section 10 in full, in a private window wherever it
says unauthenticated. Static checks passing is not proof it works. With only
Test Offering installed, expect the offering chooser and home summary to list
`Test Offering` without errors; parts that depend on an instrument (the
questionnaire, readouts) need the Migration Accelerator pack.

## 8. Opportunity layouts and the incremental deploy

The four `Opportunity-*` layouts are complete layouts for a standard object, so a
deploy replaces the target org's own. They ship with five foreign fields
stripped, and a foreign custom link removed, so they deploy to fresh orgs. `scripts/deploy.sh` (the incremental
script) refuses to deploy those four layouts to the one org this project
treats as Production, and deploys every other layout. The guard and its
limits are recorded in `docs/architecture/blank-install.md` section 6.
`deploy-fresh-org.sh` is for fresh orgs and deploys the layouts.

## 8a. Related lists on Account, Contact and Opportunity layouts

The GTM record pages show Assessment Requests and Engagement Links only if both lists are on the object's assigned page layout (contract: `docs/architecture/gtm-related-lists.md` sections 4-5). Never deploy a layout from the repo or from another org for this; patch the target org's own layout:

```bash
# scratch SFDX project OUTSIDE the repo
mkdir -p "$SCRATCH/lay/force-app" && cd "$SCRATCH/lay"
echo '{"packageDirectories":[{"path":"force-app","default":true}],"sourceApiVersion":"62.0"}' > sfdx-project.json
sf project retrieve start -o <alias> -m "Layout:Account-Account Layout" -m "Layout:Contact-Contact Layout" -m "Layout:Opportunity-Opportunity Layout"
cd force-app/main/default/layouts
python3 <repo>/scripts/patch-related-lists-layouts.py --object Account <file>.layout-meta.xml            # prints the diff, writes nothing
python3 <repo>/scripts/patch-related-lists-layouts.py --object Account <file>.layout-meta.xml --in-place  # write
cd "$SCRATCH/lay" && sf project deploy start --dry-run -o <alias> -d force-app                              # validate-only
```

The tool inserts only the two `<relatedLists>` blocks (idempotent; a re-run prints "already up to date"), prints a diff that must show only those additions, and refuses (exit 2, writes nothing) if anything else would change. Real deploy only after the owner's explicit go-ahead; never to gtm-prod without it. Use the file name prefix (Account-/Contact-/Opportunity-) or `--object`. Patch every layout the GTM profiles are assigned in that org (prod: the three stock layouts; staging: the SDO layouts too). Layout content is shared: reps in other apps also see the two lists.

## 9. Troubleshooting

Each entry is a failure seen on a real fresh-org deploy, with the fix.

| Symptom | Cause | Fix |
|---|---|---|
| Pass 5 fails on an Opportunity layout: a field such as `MainCompetitors__c` or `OrderNumber__c` not found | Those layouts named sample fields that exist only in some orgs; a fresh org has none of them | Fixed in source: the five fields are stripped and `check-references.py` now blocks any `__c` on a layout that source does not define. If it recurs, run `python3 scripts/check-references.py`; it names the layout and field. |
| Deploying the Network alone: `PicassoSite - no SiteDotCom named GTM1 found` | The Network points at a SiteDotCom that only the ExperienceBundle creates | Never deploy the Network alone. Pass 9 deploys Network, CustomSite and ExperienceBundle as one package. |
| Deploying the ExperienceBundle alone: `Network - no Network named GTM found` | The bundle needs the Network, which needs the bundle | Same fix: use pass 9's combined deployment; do not deploy `experiences/` on its own into a fresh org. |
| Network deploy rejected for a missing `emailSenderAddress` | The Network requires one on create, and none is committed | Pass 9 injects it. If it could not find one, set `GTM_SITE_SENDER_EMAIL`, or make sure the authorized user has an email in the org, or run from a terminal to be prompted. |
| Pass 9 fails under `--check-only` but the real run might not | A validation cannot create the SiteDotCom or enable Digital Experiences | Record the exact error and which pass failed; do not assume either way. If the combined package itself is rejected, see the fallback ladder in `docs/architecture/site-shell-metadata.md` section 3 before changing anything. |
| Pass 8 fails: Digital Experiences unavailable (or the ExperienceBundle setting is rejected) | Demo/limited org without the feature, or My Domain not deployed | Deploy My Domain first (section 1); if the feature is still missing, use an edition that has Experience Cloud. |
| A custom metadata pass fails naming a DeveloperName | Consecutive-underscore risk | `fresh-org-deploy.md` section 9: `python3 scripts/rename-pair-keys.py --apply`, then `python3 scripts/build-instrument.py`, then rerun. Do not keep retrying. The script only suggests this when the error mentions a DeveloperName. |
| A custom metadata pass fails with `The string "--" is not permitted within comments` (or another XML parse error) | A `--` inside an XML comment in a record | The rename above will NOT help. Reword the comment; `check-references.py` now catches this before deploy. |
| Pass 5: `In field: customLink - no WebLink named Opportunity.DeliveryStatus found` | A layout placed a custom link that only exists in some orgs | Fixed in source (link removed); `check-references.py` blocks any undefined `customLink`/`customButtons`. |
| Pass 9: `ExperienceBundle GTM1: GTM wasn't deployed because ExperienceBundle isn't enabled for Aura sites` | `enableExperienceBundleMetadata` was off | Pass 8 now deploys `ExperienceBundleSettings`; if you deployed pass 9 by hand, deploy `settings/` first. |
| Re-run fails: `Tree import errors: ... DUPLICATE_VALUE duplicate value found: Section_Address__c ...` then `Data Import failed` | A manual `sf data import tree` of rows that already exist (the script no longer does this) | Use the script: it checks first and skips loaded seeds. A file reported as only PARTLY loaded needs a human comparison; the script will not create the missing rows. |
| Seed import fails: `FlsError: you don't have access to Label__c on GTM_Page_Section__c` | The importing user holds none of the GTM permission sets | The script now assigns `GTM_Offering_Admin` and `GTM_Content_Admin` to the deploying user before any seed. If you seed by hand, assign them first, then rerun (imports of sections then records are safe to retry only if the first attempt inserted nothing; check for duplicates). |
| A custom metadata pass fails with a bare `UNKNOWN_EXCEPTION` | Flaky when bundled with other components | The script retries four times on its own; only investigate if all four fail. |
| Guests see a login screen or nothing after deploy | The site is unpublished, inactive, or `GTM_Guest` is not on `GTM Profile` | Publish (section 3), activate, and assign `GTM_Guest`; the Setup checklist rows for the site and guest access show which is missing. |
| A rep cannot submit a readout for approval | No Manager on the user | Set the Manager field (Setup shows this as a recommended row while self-approval is off). |
| The GUS chat assistant does not answer | No chat provider key set (optional; only GUS uses it) | GTM Offerings app > Settings tab: choose the provider and enter its key. Everything else works without one. |
| `--run-tests` fails in many classes on a blank org | The tests read Migration Accelerator custom metadata | Install the pack (section 5), then rerun. |
