# TASK SCOPE — ISSUE #site-shell-metadata

## 1. Requirements Breakdown

- **Target Objective:** A second org, `gtm-staging` (alias already authorized; demo-type Developer org), needs the full GTM Offerings solution deployed WITHOUT hand-building the Experience Cloud site. Today the repo holds only the ExperienceBundle (`force-app/main/default/experiences/GTM1` + `GTM1.site-meta.xml`, type `ChatterNetworkPicasso`, prefix `gtm/s`), and `docs/runbooks/fresh-org-deploy.md` §3.3 tells an admin to create the site by hand. Deliverables:
  1. Add the site shell as deployable metadata: `Network:GTM1`, `CustomSite:GTM1`, guest-user Profile wiring, and `CommunitiesSettings` (`enableNetworks`, so Digital Experiences is enabled by the deploy itself). Verified: no `networks/`, `sites/`, or `communitiesSettings` dir exists under `force-app/main/default/` today; only `profiles/Standard*.profile-meta.xml` exist.
  2. Add a pass in `scripts/deploy-fresh-org.sh` before the current pass 8 (Experience Cloud content) and renumber the "N/8" labels and header comments. The shell must land before `experiences`.
  3. Correct runbook §3.3 (and the pass table/§4 text referencing it). It currently says "Build Your Own (LWR)"; CLAUDE.md §3 says Aura on `ChatterNetworkPicasso`, NOT LWR.
  4. Keep `scripts/check-references.py` green. It already checks `experiences/` and at ~line 542-548 emits a warning that "there is no Network/CustomSite metadata in this repo"; that warning becomes false and must be updated. `Network` and `Site` also appear in its ~line 105 list, so check that new metadata does not trip it.
  5. Validate with `./scripts/deploy-fresh-org.sh gtm-staging --check-only`, then do a real deploy to `gtm-staging`.
- **Hard constraints (record and enforce):**
  - `gtm-dev` is treated as PRODUCTION. NEVER deploy to it. A read-only retrieve from `gtm-dev` is acceptable, but it costs API requests against a quota that has been exhausted before, so do exactly ONE batched retrieve (Network, CustomSite, CommunitiesSettings, the guest Profile, SiteDotCom/related in a single manifest) into the scratchpad/temp dir, not into the source tree unreviewed.
  - Deploy only to `gtm-staging`. Never use `-c` (it means `--ignore-conflicts`); use `--dry-run` / `--check-only`.
  - No org IDs, usernames, instance URLs, or secrets committed. Any org-specific value in retrieved XML (site guest username, domain, `siteAdmin`/`siteGuestRecordDefaultOwner` usernames, email addresses) must be scrubbed or replaced by a deploy-time value, per runbook §8.
  - New fields: none planned, so no permission-set changes. If any field/object/tab is added, the five permission sets in CLAUDE.md §6 need grants.
  - Contract-first: if any contract changes (deploy pass order, site shell definition), document it in `docs/architecture/` before implementing.
- **OPEN QUESTION (settle from retrieved metadata, do not guess):** Aura (`ChatterNetworkPicasso`) vs LWR. Repo evidence (`GTM1.site-meta.xml` type, CLAUDE.md §3) says Aura; runbook §3.3 says LWR. The single gtm-dev retrieve of `Network:GTM1` / `CustomSite:GTM1` / the ExperienceBundle `type` is authoritative. If gtm-dev is Aura, the Network shell must be the Aura variant, and the runbook is wrong. If it is LWR, the bundle and CLAUDE.md conflict and a human must resolve it. Escalate; do not choose silently.
- **Other ambiguity:** `GTM_Story1` is named in the deploy script and runbook but has no `experiences/GTM_Story1` folder (pre-existing drift, out of scope per runbook §3.3). Only GTM1 is in scope; do not add a GTM_Story1 shell.
- **System Component Impacted:** Experience Cloud site shell metadata (new `networks/`, `sites/`, `communitiesSettings/` (or settings) files, guest Profile), `scripts/deploy-fresh-org.sh`, `scripts/check-references.py`, `docs/runbooks/fresh-org-deploy.md`, and possibly `docs/architecture/`. No Apex, LWC, or YAML instrument changes.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO. No Apex/GUS tool changes, so the zero-DML rule in AGENTS.md §1 is not touched.
- [ ] Altering Custom Metadata? NO. No `GTM_Assessment_*` or instrument YAML changes. Note, however, that deploy pass 4 (custom metadata records) carries the runbook §9 double-underscore/consecutive-underscore DeveloperName risk. Expect it to fail on `gtm-staging`; follow the §9 remedy (four commands) rather than retrying, and do not hand-edit generated XML.
- [ ] Introducing database fields? NO. No new fields/objects/tabs, so no Permission Set mapping is needed. (Guest Profile wiring is a Profile/Network change, not FLS on a new field; verify `GTM_Guest` permission set assignment stays a documented manual step in runbook §6.)

## 3. Plan Acceptance Criteria

- **Success Metric:**
  - Repo contains deployable `Network` GTM1, `CustomSite` GTM1, guest-profile wiring, and `CommunitiesSettings` with `enableNetworks` true, scrubbed of org-specific values, matching the template type the gtm-dev retrieve confirms.
  - `deploy-fresh-org.sh` has a new site-shell pass ordered before the experiences pass; all pass labels and comments are consistent.
  - Runbook §3.3 no longer instructs manual creation and no longer says LWR; pass table and §4 cross-references are updated; the Aura-vs-LWR question is resolved in the text.
  - `python3 scripts/check-references.py` exits green, with the stale "no Network/CustomSite" warning removed or corrected.
  - `./scripts/deploy-fresh-org.sh gtm-staging --check-only` succeeds through the new pass (report the first failing pass otherwise; do not proceed to a real deploy on failure).
  - A real deploy to `gtm-staging` completes, and `sf community publish -n "GTM1"` is run so the site is live (CLAUDE.md §5). Zero commands target `gtm-dev` other than the single read-only retrieve. No org ID/username/secret appears in `git diff`.
  - Risks handled and reported: (a) guest Profile/domain failures on first deploy (site guest user is created by the platform on Network/CustomSite deploy; domain/`subdomain`/`urlPathPrefix` and `siteAdmin`/guest-owner username values can fail in a fresh org; Profile name for a new guest user is `GTM1 Profile`, so wiring must not reference a profile that does not yet exist); (b) the §9 underscore risk in pass 4; (c) the enableNetworks setting must deploy before the Network in the same or an earlier pass; (d) demo-type org licence/feature limits on Digital Experiences; (e) API quota exhaustion.
- **Target Test Target:** No Apex or LWC changes, so no Apex class or Jest spec is the gate. Run `python3 scripts/check-references.py` (must be green), `npm test` (regression only, must remain green), and `./scripts/deploy-fresh-org.sh gtm-staging --check-only`, followed by the real deploy to `gtm-staging`. QA must also validate live in a browser on the `gtm-staging` site and every dependent surface (guest landing pages load, the site URL prefix `gtm/s` resolves), per the QA browser-validation rule.

## 4. Architect Review and Decisions

- **Compliance:** Scope passes (no Apex/GUS, no custom metadata, no fields, so no permission-set work; gtm-staging only; no `-c`; no org values committed).
- **Aura vs LWR (settled):** gtm-dev ExperienceBundle GTM1 retrieved as `ChatterNetworkPicasso`, prefix `gtm/s`, brandingSet/theme `buildYourOwn`. It is Aura, matching CLAUDE.md and the repo bundle. Runbook §3.3 "LWR" is wrong; fix it. No conflict, no human decision needed on this.
- **Single retrieve result:** `Settings:Communities` retrieved (`enableNetworksEnabled=true`). `Network:GTM1`, `CustomSite:GTM1`, `Profile:GTM1 Profile` returned NOTHING: those member names do not exist in gtm-dev. The real Network/site/profile names differ from the bundle name. Retrieve is at `docs/agent-artifacts/retrieve-gtm-dev/` (untracked, excluded via .git/info/exclude, never commit; delete when done).
- **BLOCKER for Developer:** need the true Network/CustomSite name (likely `GTM`, from label "GTM", profile likely `GTM Profile`). One more read-only gtm-dev retrieve (wildcards `*` for Network, CustomSite; Profile by name) needs explicit approval given the quota rule. Alternative: `sf org list metadata` is also an API call, so equivalent.
- **Drift found:** retrieved gtm-dev bundle differs from repo for routes/views `industry`, `offeringChooser`, `readout`, `recoverLink`. Out of scope; do not overwrite repo bundle. Flag to human.
- **Decisions:** (1) New files: `force-app/main/default/settings/Communities.settings-meta.xml`, `networks/<Name>.network-meta.xml`, `sites/<Name>.site-meta.xml`, plus guest profile wiring only if the site's Profile can deploy after the Network (Network must precede profile; the profile is platform-created, so do not ship a Profile that references a nonexistent one; prefer documenting GTM_Guest assignment as manual, runbook §6). (2) Settings pass first, then network+site pass, both before experiences pass; renumber N/8 to N/9 in `scripts/deploy-fresh-org.sh`. (3) Update `scripts/check-references.py` (~lines 105, 542-548 stale warning). (4) Runbook §3.3, pass table, §4. (5) Contract: add `docs/architecture/` note on site shell + pass order before implementing.
- **Scrub list (from Network/CustomSite once retrieved):** `siteAdmin`, `siteGuestRecordDefaultOwner`, guest username, `subdomain`/domain, `emailSenderAddress`, `caseSubjectOption`-linked emails, `changePasswordTemplate`/`forgotPasswordTemplate` EmailTemplate refs (must exist in repo or be dropped), `selfRegProfile`, any org ID/instance URL. Replace with omission or deploy-time value; never commit usernames. Communities.settings has no org-specific values; safe as retrieved (prune to `enableNetworksEnabled` plus needed keys).

## 5. Architect Update: second retrieve resolved (supersedes the BLOCKER and scrub list in section 4)

Second read-only gtm-dev retrieve (Network:*, CustomSite:*, Profile:GTM Profile) at `docs/agent-artifacts/retrieve-gtm-dev/out2/unpackaged/` (untracked, excluded; do not commit; delete when done). Metadata API does not support partial wildcards, so `Profile:*Guest*` was not used and no bulk profile pull was made.

**Real names (BA/runbook assumption "GTM1 Profile" and Network/CustomSite "GTM1" were wrong)**
- Network: `GTM` (`picassoSite` = `GTM1`, the ExperienceBundle name; `site` = `GTM`; `urlPathPrefix` = `gtm`; status Live).
- CustomSite: `GTM` (`siteType` ChatterNetwork, `urlPathPrefix` = `gtm`, `enableAuraRequests` true). Aura confirmed again.
- Guest Profile: `GTM Profile` (userLicense `Guest User License`, custom, empty body: no class/object grants). Real access comes from the `GTM_Guest` permission set assigned in Setup.
- Ignore `ZZ_DELETE_GTM_Accelerator` and `ZZ_DELETE_old_retired_site` (retired sites; never migrate).
- Note ExperienceBundle `urlPathPrefix` is `gtm/s`; the Network/site prefix is `gtm`.

**Files for the Developer (all under `force-app/main/default/`)**
- `networks/GTM.network-meta.xml` (from `GTM.network`), `sites/GTM.site-meta.xml` (from `GTM.site`), `settings/Communities.settings-meta.xml` (from out/unpackaged/settings/Communities.settings; trim to `enableNetworksEnabled` and `enableCommunityWorkspaces`).
- Do NOT add `profiles/GTM Profile.profile` (platform creates it with the site; body is empty anyway).
- Also edit `scripts/deploy-fresh-org.sh`, `scripts/check-references.py`, `docs/runbooks/fresh-org-deploy.md`, and add a `docs/architecture/` contract note (contract first). Runbook profile name is `GTM Profile`, not `GTM1 Profile`.

**Scrub list against real XML**
- Site: REMOVE `siteAdmin` and `siteGuestRecordDefaultOwner` (contain a real username; platform defaults to the deploying user if omitted, else set at deploy time, never committed).
- Network: REMOVE `emailSenderAddress` (real email; set post-deploy, runbook step) and `recaptchaSecretKey` (encrypted secret; remove the field, keep other auth API settings).
- Network: REMOVE `networkMemberGroups` entries `devedapp__Developer_Edition` and `sfdcInternalInt__sfdc_scrt2` permission sets (managed/internal to gtm-dev, absent in a fresh org) and pin remaining refs: keep only profiles that exist everywhere (`admin`, `standard`, `minimum access - salesforce`); `Experience_Profile_Manager` and `standardaul` and `salesforce api only system integrations` need verification or removal in the staging check-only. Leave the guest profile out of this list, as retrieved.
- Network: template refs `unfiled$public/Community*EmailTemplate` are standard org templates; keep, verify on check-only. `emailSenderName` "GTM Story" is not sensitive; keep.
- No org ID, instance URL or domain appeared in either file.

**Bundle drift: gtm-dev vs repo `experiences/GTM1` (8 differing files of 46; Developer must not overwrite repo bundle)**
- `routes/industry`, `routes/offeringChooser`, `routes/readout`, `routes/recoverLink`: trailing-newline only (cosmetic, no content change).
- `views/readout`, `views/recoverLink`: trailing-newline only.
- `views/industry` and `views/offeringChooser`: real JSON differences (different `id` and structural layout ordering/format; both hold the same components: `c:chooseIndustry` and `c:offeringChooser` in the same section/seoAssistant structure). Likely Experience Builder re-save in gtm-dev vs repo; needs a human decision on which is authoritative.

## 6. Architect Update: QA failure on gtm-staging (supersedes pass order in sections 4 and 5)

Evidence: `TEST_FAILURES.log` (untracked; do not commit). Passes 1-4, 6, 7 OK on gtm-staging (pass 4 already loaded the MA custom metadata, so staging is NOT blank).

**A. Site shell (blocking).** Contract rewritten in `docs/architecture/site-shell-metadata.md` section 3: pass 8 = `settings`; pass 9 = ONE combined deploy of Network GTM + CustomSite GTM + ExperienceBundle GTM1 built as a temp mdapi package with `emailSenderAddress` injected from env `GTM_SITE_SENDER_EMAIL` (prompt if TTY, else error; never committed or logged). Fallback ladder documented; `sf community create` is last resort (name mismatch GTM vs GTM1). Not verified against a live doc fetch (no web tool) and nothing deployed: Developer proves it with `--check-only` on gtm-staging. Repo bundle `experiences/GTM1` stays authoritative, untouched.

**B. Pass 5 layouts.** Decision: STRIP the five foreign fields (`MainCompetitors__c`, `CurrentGenerators__c`, `OrderNumber__c`, `TrackingNumber__c`, `DeliveryInstallationStatus__c`) from all four `layouts/Opportunity-*.layout-meta.xml`; keep `Engagement_Link_Info__c`. Dropping the layouts would lose our field's placement. In `scripts/check-references.py`: delete the `ORG_PROVISIONED_FIELDS` allowance and make any `__c` on a standard-object layout that is not defined in source a blocker (`P`, not `W`), including the layouts' non-`field` places if any. HUMAN FLAG: stripping changes the layouts the repo would push to gtm-dev (Production) if anyone runs `deploy.sh` there; the fields vanish from dev's Opportunity layouts. Recommend nobody deploys layouts to gtm-dev without this being seen.

**C.** `scripts/deploy-fresh-org.sh` is 100644: `chmod +x` and commit the mode (`git update-index --chmod=+x`); verify with `git ls-files -s`.

**D. Blank install.** Contract in `docs/architecture/blank-install.md` (default = framework only; `--with-offering <key>` packs via `scripts/offerings/<key>.manifest`; `test-offering` fixture in a non-default `test-fixtures/` packageDirectory so `deploy.sh` never ships it to gtm-dev; zero-offering audit list; staging validation options A fresh org / B destructive change / C both, human decides).

**Developer file list**
- `scripts/deploy-fresh-org.sh` (chmod +x; pass 4 framework-only; pass 8/9 rewrite; `--with-offering`, optional `--with-demo-data`; usage/header comments)
- `scripts/offerings/migration-accelerator.manifest`, `scripts/offerings/test-offering.manifest` (new)
- `scripts/check-references.py` (layout blocker; scan `test-fixtures/`; stale shell warning ~542-548)
- `force-app/main/default/layouts/Opportunity-*.layout-meta.xml` (4 files, strip fields)
- `sfdx-project.json` (second non-default packageDirectory `test-fixtures`)
- `test-fixtures/test-offering/main/default/customMetadata/GTM_Offering.Test_Offering.md-meta.xml`, `data/seed/test-offering.*.json` (one labeled test record)
- `docs/runbooks/fresh-org-deploy.md` (§3.3 to match; pass table; §4; note tests need the MA pack)
- `docs/runbooks/gtm-offerings-install.md` (NEW, "Salesforce org setup and GTM Offerings installation"; generic `<org-alias>`; troubleshooting built from the real errors in `TEST_FAILURES.log`: Opportunity layout foreign fields, PicassoSite/SiteDotCom, Network-not-found, emailSenderAddress; link to fresh-org-deploy.md for deep sections, do not duplicate)
- Zero-offering fixes only if the audit in blank-install.md section 4 finds hard failures.

**Constraints:** never `gtm-dev`, never `-c`, no org IDs/usernames/emails/secrets committed (the `out/`, `out2/` retrieve dirs remain untracked), the Developer runs no real deploy until `--check-only` passes on gtm-staging.
