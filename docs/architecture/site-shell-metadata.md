# Experience Cloud site shell metadata (contract)

Issue: site-shell-metadata. Source of truth for what the repo carries of the
Experience Cloud site itself (as opposed to its pages) and where it sits in the
`scripts/deploy-fresh-org.sh` pass order.

## 1. Site identity (verified against the live site, Aura)

| Thing | Value |
|---|---|
| Template | Aura, `ChatterNetworkPicasso` (NOT LWR) |
| Network | `GTM` (`picassoSite` = `GTM1`, `urlPathPrefix` = `gtm`, status `Live`) |
| CustomSite | `GTM` (`siteType` `ChatterNetwork`, `urlPathPrefix` = `gtm`, `enableAuraRequests` true) |
| ExperienceBundle | `GTM1` (`urlPathPrefix` = `gtm/s`), unchanged by this issue |
| Guest profile | `GTM Profile` (Guest User License). Created by the platform when the site is created; NOT in source |

Network/CustomSite name (`GTM`) and bundle name (`GTM1`) differ on purpose: the
Network points at the bundle through `picassoSite`. The retired
`ZZ_DELETE_*` sites are never migrated.

## 2. Files

| File under `force-app/main/default/` | Metadata type |
|---|---|
| `settings/Communities.settings-meta.xml` | `CommunitiesSettings`; only `enableNetworksEnabled` and `enableCommunityWorkspaces` |
| `settings/ExperienceBundle.settings-meta.xml` | `ExperienceBundleSettings`; `enableExperienceBundleMetadata` = true |
| `networks/GTM.network-meta.xml` | `Network` |
| `sites/GTM.site-meta.xml` | `CustomSite` |

### Scrubbed (never committed)

- `CustomSite`: `siteAdmin`, `siteGuestRecordDefaultOwner` (usernames). Omitted;
  the platform defaults them to the deploying user.
- `Network`: `emailSenderAddress` (an email; set after deploy, runbook step),
  `recaptchaSecretKey` (encrypted secret).
- `Network.networkMemberGroups`: only profiles `admin`, `standard`,
  `minimum access - salesforce` are kept. Managed/internal permission sets and
  the profiles/permission set that do not exist in every org are dropped.
- No `profiles/GTM Profile.profile` is shipped. Guest access comes from the
  `GTM_Guest` permission set, assigned by hand (runbook section 6).

## 3. Deploy pass order (REVISED after QA failure on gtm-staging)

QA proved the original "shell (pass 8) then experiences (pass 9)" order cannot
work on a fresh org, because the dependency is circular:

- `Network GTM` deployed alone fails: `PicassoSite - no SiteDotCom named GTM1
  found` (the SiteDotCom is created by the ExperienceBundle).
- `ExperienceBundle GTM1` deployed alone fails: `Network - no Network named GTM
  found`.
- `Network` also refuses to create without `emailSenderAddress`.

### Decision: one combined deployment

Passes 1-7 unchanged. Pass 8 and 9 become:

| Pass | Contents | Notes |
|---|---|---|
| 8 | `settings` (CommunitiesSettings `enableNetworksEnabled` + ExperienceBundleSettings `enableExperienceBundleMetadata`) | own deploy; must finish first. Without the bundle setting, pass 9 is rejected: `ExperienceBundle GTM1: GTM wasn't deployed because ExperienceBundle isn't enabled for Aura sites` |
| 9 | ONE deployment containing `Network:GTM` + `CustomSite:GTM` + `ExperienceBundle:GTM1` (+ nothing else) | resolves the cycle: the platform creates SiteDotCom, Network, CustomSite together in one transaction. This is the documented Salesforce migration pattern for Experience Cloud (deploy ExperienceBundle with its Network and CustomSite in one package) |

**Proof status (QA round 2).** With `ExperienceBundleSettings` enabled (QA set it
in gtm-staging by hand), the combined pass 9 `--dry-run` SUCCEEDED. So the
single combined deployment is proven at the check-only level. A REAL deploy has
still to confirm it (a validation cannot create the SiteDotCom or publish), so
the fallback ladder below stays in force until then.

Why not `sf community create`: it works, but it names the Network/CustomSite
after the site (`GTM1`), not `GTM` as this repo's Network (`picassoSite` =
`GTM1`) has it, so every reference would need renaming; it is asynchronous, has
its own template-name and licence failure modes, and still needs the bundle
deployed afterwards. It is the FALLBACK only (see below).

Verification status: the docs pattern above is from the Architect's knowledge of
the Salesforce Metadata API guide; no web fetch tool was available to re-read
it, and NOTHING was deployed (Architect never deploys). The Developer must prove
it with `--check-only` on `gtm-staging` (never `gtm-prod`) before any real deploy.

Fallback ladder, stop at the first that validates (report which):
1. Combined deploy exactly as above.
2. Combined deploy with `picassoSite` removed from the Network in the temp
   package only (the bundle's type `ChatterNetworkPicasso` binds the site).
3. `sf community create --name GTM1 --url-path-prefix gtm ...` then deploy the
   bundle; record the name mismatch. This is a design change, escalate before
   committing to it.

### emailSenderAddress: supplied at deploy time, never committed

The committed `networks/GTM.network-meta.xml` stays without the field. The
script builds a TEMP package (`mktemp -d`, removed by `trap` on exit):

1. `sf project convert source` for `Network:GTM`, `CustomSite:GTM`,
   `ExperienceBundle:GTM1` into the temp dir (mdapi format).
2. Insert `<emailSenderAddress>` into the temp Network XML. Value precedence
   (user decision: the site sender defaults to the target org's default admin,
   i.e. the authorized user running the deploy; only needed for setup):
   1. env `GTM_SITE_SENDER_EMAIL` if set (override);
   2. else the authorized user's email: ONE `sf org display --json` (only
      `result.username` is read; the token in that output is never printed or
      stored) and ONE `sf data query` (`SELECT Email FROM User WHERE Username =
      '<that username>'`), no repeated org-info calls (API quota);
   3. else a hidden prompt on a TTY;
   4. else exit with an error.
   Required for `--check-only` too. The value is only ever displayed masked,
   never written under the repo, never logged. Salesforce may send a
   verification email to it; the admin may need to click the link.
3. `sf project deploy start --metadata-dir <tmp> --target-org <alias> --wait 60`
   (+ `--dry-run` for `--check-only`; never `-c`).

`siteAdmin`/`siteGuestRecordDefaultOwner` stay omitted (platform defaults to the
deploying user).

## 4. Failure modes

- Demo-type orgs may lack Digital Experiences: pass 8 fails; first failing pass
  reported, nothing later runs.
- Guest profile `GTM Profile` does not exist until the site does; no source file
  references it.
- Combined deploy fails on `networkMemberGroups`: retained profile/permission
  set names must exist in the target org; drop the offender in the source file
  (not the temp copy) and re-validate.

## 5. Post-deploy (manual, org state)

- Assign `GTM_Guest` to the `GTM Profile` guest profile.
- Publish the site (`sf community publish -n "GTM"`; site name is `GTM`, the
  bundle is `GTM1`).
- (The email sender address is now set by the deploy, not by hand; click the
  verification link Salesforce may send to it.)
