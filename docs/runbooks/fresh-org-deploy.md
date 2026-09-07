# Runbook — rebuilding this solution in a fresh Salesforce org

The org this was built in is a Developer Edition org and it expires. When it
does, this repo is the only copy of the work. This runbook is the path from a
clean clone to a working org, written for a competent Salesforce admin who was
not in any of the conversations that produced it.

**Read this end to end before starting.** Roughly a third of the solution is
org state rather than metadata — Experience Cloud sites, guest profiles, queue
membership, an API key — and several of those steps have to happen *before* the
deploy, not after. Doing them in the wrong order means a failed deploy, not a
missing feature.

> **Nothing in this repo has ever been deployed to a fresh org.** Everything
> below is derived from the source tree and from what the dev org needed. The
> static checks in `scripts/check-references.py` are thorough and they pass, but
> a passing static check is not a successful deploy. Treat the first run of this
> runbook as the test, and correct this file as you go — a runbook that omits a
> step is worse than one that lists ten.

### Two things that will cost you a failed deploy if you skip ahead

1. **The two Experience Cloud sites must exist in the target org before you
   deploy.** This repo contains the *pages* of those sites, not the sites. See
   **§3.3** — it is a pre-deploy step, and pass 8 fails without it.
2. **Twenty-five custom metadata records have a `DeveloperName` containing two
   consecutive underscores, which Salesforce documents as illegal, and nobody
   knows whether it is enforced here.** The "existing precedent" this spelling
   was justified by was written in the same never-deployed batch and proves
   nothing in either direction, so **your first deploy is the first test of it**.
   Read **§9** before you run pass 4 — it is one command to fix and a confusing
   half-hour if you meet it cold.

---

## 1. What you are deploying

| | |
|---|---|
| **Custom objects** | `GTM_Assessment_Request__c`, `GTM_Readout__c`, `GTM_Readout_Version__c`, `GTM_Saved_Configuration__c`, `GTM_Page_Content__c`, `GTM_Page_Content_Version__c`, `GTM_Page_Section__c`, `GTM_CMS_Content_Index__c`, `GTM_Link_Event__c` |
| **Custom setting** | `GTM_Agent_Settings__c` (hierarchy) — holds the Claude API key |
| **Platform event** | `GTM_Config_Update__e` |
| **Additions to standard objects** | `Opportunity.Engagement_Link__c`, `Opportunity.Engagement_Link_Info__c`, `Case.Readout__c`, `Lead.GTM_Account__c` |
| **Custom metadata types** | `GTM_Assessment_Question__mdt`, `GTM_Assessment_Pair__mdt`, `GTM_Assessment_Dimension_Override__mdt`, `GTM_Assessment_Supplement__mdt`, `GTM_Assessment_Gate__mdt`, `GTM_Migration_Platform__mdt`, `GTM_Migration_Pair__mdt`, `GTM_Offering__mdt`, `GTM_Assessment_Config__mdt` |
| **Custom metadata records** | 57 under `force-app/main/default/customMetadata/`, 45 of them **generated** from `migration-accelerator/instrument/` by `scripts/build-instrument.py` — edit the YAML, never the XML |
| **Apex** | 59 classes (25 of them tests) plus `GtmReadoutApprovalSync.trigger` |
| **LWC** | 28 bundles |
| **UI** | 3 flexipages, 11 tabs, 2 apps, 6 layouts, 5 managed content types |
| **Automation** | `GTM_Readout_Approval` approval process, its 3 workflow field updates, the `GTM_Readout_Triage` queue, `GTM_Config_Send_To_Client` flow |
| **Access** | `GTM_Config_Manager`, `GTM_Config_View_All`, `GTM_Assessment_Guest`, `GTM_Story_Guest`, `GTM_Platform_Visibility` |
| **Sites** | `GTM_Accelerator1` (`/gtmaccelerator`) and `GTM_Story1` (`/gtmstory`) — **ExperienceBundle only, see §3** |
| **Callouts** | `Anthropic_API` and five other remote site settings; 2 CSP trusted sites |
| **Optional** | `bots/` + `genAiPlugins/` (need Agentforce), `profiles/` (see §7) |

Seed data lives outside `force-app/`: `data/seed/*.json` (10 section records and
39 content records, in `sf data tree` format) and
`scripts/seed-ma-page-content.apex`.

**Do not trust the counts in that table — regenerate them.** They were true at
the commit that wrote this file and this solution is still being built. The
authoritative inventory is derived from the tree:

```bash
python3 scripts/check-references.py --inventory
```

That prints every object, every custom field count, every site route and every
seed record actually present. Run it before a deploy and, if it disagrees with
the table above, believe it and fix the table.

**A note on the readout's two halves**, because it is the newest part of the
schema and the reason several fields look redundant: `GTM_Readout__c` carries the
prose a human writes (`Draft_Content__c` → `Approved_Content__c`) *and*, next to
it, the measurement half nobody edits (`Readout_Data__c` → `Approved_Data__c`,
snapshotted to `GTM_Readout_Version__c.Data_Snapshot__c`). The second set exists
because a rich text field strips the markup a score staircase needs, and because
an approved readout has to keep meaning what it meant — band edges are frozen by
value at approval. All six fields must deploy; dropping the `*_Data__c` ones
leaves a readout that renders its prose and loses its scores.

---

## 2. Packaging strategy — and why

**Use an ordered metadata deploy from this repo (`scripts/deploy-fresh-org.sh`),
not an unlocked package or a scratch-org definition.**

The reasoning, so that a later decision to change it is an informed one:

- **An unlocked package is the wrong shape *today*, and a good shape later.**
  Packaging is how you distribute the same accelerator to many orgs with version
  history and an upgrade path, and this codebase would qualify with no
  restructuring. But it needs a Dev Hub, a namespace decision that is
  irreversible once made, and — the part that actually decides it — packages
  cannot contain the things this solution most depends on. `ExperienceBundle`,
  standard profiles, and the org state in §3 are all outside a package's
  boundary, so an unlocked package would move maybe 80% of this and leave the
  hard 20% as manual steps anyway. You would have paid the namespace cost and
  still be reading §6. Revisit when there is a *third* org, and the cost of
  re-running §6 by hand exceeds the cost of the namespace.
- **A scratch-org definition is not a substitute, it is a companion.** Scratch
  orgs are for CI and for throwaway feature work. The target here is a real org
  that will hold real prospect data and outlive the person who deployed it. A
  scratch-org definition file would be a genuinely useful addition for testing
  this runbook cheaply and repeatedly — it is not in this repo yet, and adding
  one is the single highest-value follow-up.
- **The ordered deploy is what the dependencies actually demand.** Custom
  metadata *records* need their types. Permission sets grant on classes,
  objects, fields, tabs and apps, so they must be last. The approval process
  names three workflow field updates by name and is rejected if they are not
  already there. Experience Cloud views draw LWCs. `scripts/deploy-fresh-org.sh`
  encodes that order in eight passes and stops at the first failure.

**To move to an unlocked package later** you would need: a Dev Hub org, a
namespace, `sfdx-project.json` extended with a package entry, the two
`profiles/` files removed from the package directory (packages cannot carry
standard profiles), and this runbook's §3 and §6 kept exactly as they are —
they do not get easier.

**Coexistence with an existing org.** This deploys cleanly into a dedicated org.
In a *shared* org, three things need care and are called out where they occur:
the four `Opportunity` layouts replace that org's own layouts (§7), the two
standard profiles change access for users who have nothing to do with this
solution (§7), and `GTM_Platform_Visibility` grants ~320 standard tabs it
inherited from being retrieved out of a Developer Edition org (§7).

---

## 3. Prerequisites — do these BEFORE deploying

### 3.1 Tooling

```bash
npm install -g @salesforce/cli     # sf
python3 --version                  # 3.8+ for the check and build scripts
npm install                        # only if you intend to run the LWC tests
```

### 3.2 Org toggles

| Toggle | Where | Why |
|---|---|---|
| **My Domain** | Setup → My Domain → deploy to users | Digital Experiences will not enable without it. Enabling it changes every URL in the org, so do it first and let it finish. |
| **Digital Experiences** | Setup → Digital Experiences → Settings → *Enable Digital Experiences* | Both sites and both guest permission sets depend on it. Irreversible. |
| **Chatter** | Setup → Chatter Settings | Required by the Experience Cloud template used here. |
| **Approval emails / user Manager field** | Setup → Users | The approval process routes to the record owner's **Manager**. A rep with no Manager set cannot submit at all — the platform refuses, and `GtmReadoutController.submitForApproval` surfaces that message rather than hiding it. |

Edition and licences: this needs a Salesforce edition that supports Experience
Cloud, custom objects, custom metadata types, Apex and approval processes.
Developer, Enterprise, Unlimited and Performance all qualify; Professional does
not (no Apex). Each site needs Experience Cloud licences for any *authenticated*
members, but the prospect-facing flows in this solution are all **guest** — no
per-prospect licence.

### 3.3 Create the two Experience Cloud sites BY HAND

**This is the step most likely to be missed, and it fails the deploy if it is.**

`force-app/main/default/experiences/` contains `ExperienceBundle` metadata: the
pages, routes, views, theme and branding *of* a site. It does not contain the
site. There is no `Network` or `CustomSite` metadata anywhere in this repo, so
a deploy into an org with no site of that name has nothing to attach to.

Setup → Digital Experiences → All Sites → **New**, twice, using the **Build Your
Own (LWR)** template, and matching these exactly:

| Site name | URL path prefix | Must match |
|---|---|---|
| `GTM Accelerator` | `gtmaccelerator` | `GTM_Accelerator1.site-meta.xml` (`urlPathPrefix: gtmaccelerator/s`) |
| `GTM Story` | `gtmstory` | `GTM_Story1.site-meta.xml` (`urlPathPrefix: gtmstory/s`) |

The API name Salesforce assigns must come out as `GTM_Accelerator1` and
`GTM_Story1` — that is what the folders in `experiences/` are named, and a
mismatch is a deploy error naming a site that does not exist. If Salesforce
gives you a different suffix, rename the folders in this repo to match and
commit that.

---

## 4. Deploy

**Before you run this: §3.3 must be done, and you should have read §9.** The
first is a hard prerequisite; the second is the one failure mode in this deploy
whose error message will not tell you what to do about it.

```bash
git clone <this repo> && cd gtm-offerings
sf org login web --alias new-org

python3 scripts/check-references.py --inventory   # what is about to be deployed
python3 scripts/check-references.py               # static audit; must exit 0
./scripts/deploy-fresh-org.sh new-org --check-only   # validate, change nothing
./scripts/deploy-fresh-org.sh new-org --run-tests
```

`--check-only` runs the whole eight-pass order as a Salesforce *validation*:
the org checks every component and commits none of it. It is the closest thing
to a rehearsal that exists, and on a first deploy into an unfamiliar org it is
worth the extra ten minutes. It will not catch §3.3 or §9 for you — a validation
of pass 8 still needs the sites to exist, and pass 4's DeveloperName check is
part of the same validation, which is exactly why it is a useful rehearsal.

The eight passes and why each is where it is:

| Pass | Contents | Depends on |
|---|---|---|
| 1 | `objects/` — objects, fields, custom settings, platform events, **CMDT types** | nothing |
| 2 | `remoteSiteSettings/`, `cspTrustedSites/` | nothing |
| 3 | `classes/`, `triggers/`, `lwc/` | pass 1 (Apex compiles against the schema) |
| 4 | `customMetadata/` — the records | pass 1 (their types) |
| 5 | `managedContentTypes/`, `flexipages/`, `tabs/`, `applications/`, `layouts/` | passes 1 and 3 |
| 6 | `workflows/`, `approvalProcesses/`, `queues/`, `flows/` | pass 1; and the approval process needs the workflow field updates, in that order |
| 7 | `permissionsets/` (and `profiles/` only with `--with-profiles`) | passes 1, 3, 5 |
| 8 | `experiences/` | pass 3, and **§3.3** |

**Pass 4 is the one to watch.** It retries up to four times, and that is not
superstition: bundling custom metadata records with the rest has been observed
failing with a generic `UNKNOWN_EXCEPTION` on content that deploys cleanly on
its own, and a bare retry cleared it. But there is a second, quite different
failure hiding behind the same pass, so **read the error before retrying**:

- error names a **field** or a **type** → a genuine mismatch;
  `python3 scripts/check-references.py` should have caught it, and if it did not,
  that is a gap in the checker worth fixing.
- error names a **DeveloperName**, or mentions underscores → this is §9. Stop
  retrying; retrying cannot fix it. Go and read §9, run the four commands, come
  back.

The script prints the §9 remedy itself when it exhausts its retries, so you do
not have to remember this.

`bots/` and `genAiPlugins/` are skipped unless you pass `--with-agent`; they
need Agentforce provisioned and fail outright otherwise. Nothing else in the
solution depends on them.

---

## 5. Seed the data

```bash
# Custom metadata records already went in as pass 4 of the deploy.
# Story page content (GTM_Page_Section__c + GTM_Page_Content__c):
sf data import tree --target-org new-org \
  --files data/seed/migration-accelerator.story.sections.json
sf data import tree --target-org new-org \
  --files data/seed/migration-accelerator.story.records.json

# Verify the content contract still holds (every rendered field has a record):
python3 scripts/check-content-contract.py
```

Sections must be imported **before** records — the records address sections by
`Section_Address__c`.

---

## 6. Manual steps — the complete list, in the order they must happen

Nothing here can be deployed. Every item is org state.

**Before the deploy** (§3): My Domain, Digital Experiences, Chatter, and the two
Experience Cloud sites created by hand.

**After the deploy:**

| # | Step | Where | Skip it and… |
|---|---|---|---|
| 1 | **Activate** both sites | Setup → Digital Experiences → All Sites → Activate | every public URL 404s |
| 2 | **Publish** both sites | Experience Builder → Publish | the deploy only updated the *draft*. Guests see the previous version, or nothing. **Do this after every future deploy that touches `experiences/`** |
| 3 | Assign `GTM_Assessment_Guest` to the **GTM Accelerator** site's guest user profile | Builder → ⚙ Settings → General → Guest User Profile → Permission Set Assignments | the questionnaire and the `/readout` page both fail for anonymous visitors. Guest profiles are created per site by Salesforce and are not in source |
| 4 | Assign `GTM_Story_Guest` to the **GTM Story** site's guest user profile | same, on the other site | the story page fails for anonymous visitors |
| 5 | Confirm **Page Access** on `/readout`, `/assessment`, `/configurator`, `/industry` reads *Public — inherited from site* | Builder → ⚙ Settings → Pages | a login screen instead of the page. `pageAccess: "UseParent"` deploys as this, but check it |
| 6 | Assign `GTM_Config_Manager` to every rep; `GTM_Config_View_All` to whoever should see everyone's links | Setup → Permission Sets → Manage Assignments | reps cannot open the readout editor |
| 7 | Assign `GTM_Platform_Visibility` if you have Standard Platform User licences | same | those users see no tabs |
| 8 | **Add members to the `Unassigned Readouts` queue** | Setup → Queues → Unassigned Readouts → Queue Members | `GTM_Readout__c` is Private and queue-owned readouts are then visible to **nobody**. Direct bookings land here. Queue membership is data, not metadata |
| 9 | Add every rep profile as a **site member** of GTM Accelerator | Builder → ⚙ Settings → *Members* (or Setup → Digital Experiences → site → Administration → Members) | an authenticated rep hits the site as if logged out, no matter what else is granted. This is `NetworkMemberGroup`, a record, not metadata |
| 10 | Set the **Manager** field on every user who will submit a readout | Setup → Users | they cannot submit for approval at all |
| 11 | Review the approval process's approver | Setup → Approval Processes → MA Readout Approval | it routes to the owner's manager, which is the one assignment that deploys the same into every org. Change `assignedApprover` if you want a queue or a named approver; no Apex depends on who it is |
| 12 | **Put the Claude API key in** Setup → Custom Settings → **MA Agent Settings** → Manage → New (org default) → `Claude_API_Key__c` | Setup | every AI-assisted drafting surface fails. **The key is not in this repo and must never be committed** |
| 13 | Point the two self-callout remote sites at **this** org's My Domain | Setup → Remote Site Settings → `GTM_Offerings_Org_Self_Callout`, `GTM_Offerings_Site_Public_CMS` | they still carry the old dev org's URLs; the callouts fail. See §8 |
| 14 | Run `./scripts/setup-cms-workspace.sh new-org` | terminal | `ManagedContentSpace` has no metadata representation at all; the five deployed content types have no workspace to live in. Idempotent |
| 15 | Author + **publish** CMS content, then insert one `GTM_CMS_Content_Index__c` row per record | Setup → Digital Experiences → CMS Workspaces | `gtmStory` falls back to its built-in DEFAULTS — a working page with placeholder copy |
| 16 | Set `GTM_Offering__mdt.Migration_Accelerator.CMS_Channel_Id__c` to this org's channel id (`0ap…`) | Setup → Custom Metadata Types | the index rows are never read. Deliberately blank in source — see §8 |
| 16b | Set every URL-shaped field on `GTM_Assessment_Config__mdt.Default` to **this** org's site base URL | Setup → Custom Metadata Types → MA Assessment Config → Manage Records | anything that builds a link for a prospect (a resume link, a callback) points at an org that no longer exists. Run `python3 scripts/check-references.py --inventory` to see which fields the type currently has — this config record is where per-org values are meant to live, and it grows |
| 17 | Replace the placeholder Monthly/Annual targets on the same record | same | the overview reports against $20k / $250k placeholders |
| 18 | Grant CMS Workspace access (Contributor/Publisher) to content authors | Setup → Digital Experiences → CMS Workspaces → Access | its own permission system, separate from every profile and permission set above |

Steps 1–8 are the minimum for the verification checklist in §10 to pass.
Steps 12 and 14–18 are needed for the AI drafting and the story page.

---

## 7. Things that are safe in a dedicated org and dangerous in a shared one

- **`profiles/`** — `Standard` and `StandardAul` are *standard* profiles that
  exist in every org and that the target org's own users already sit on. A
  profile deploy is a merge into live access for people unrelated to this
  solution. `deploy-fresh-org.sh` therefore skips `profiles/` unless you pass
  `--with-profiles`. Everything the two profiles grant is also available through
  `GTM_Config_Manager` + `GTM_Platform_Visibility`; prefer that.
- **The four `Opportunity` layouts** exist only to place
  `Engagement_Link_Info__c` on the page. Deploying them **replaces** the target
  org's Opportunity layouts wholesale. In a shared org, drop
  `layouts/Opportunity-*` from the deploy and add the two fields to the existing
  layout by hand.
- **`GTM_Platform_Visibility`** was retrieved from the dev org and arrived
  carrying that org's whole tab list — around 320 `standard-*` grants that have
  nothing to do with this solution. Five Developer-Edition package tabs
  (`devedapp__*`) have been removed because they would fail every deploy into a
  normal org. The remaining `standard-*` grants are nav visibility only: any one
  of them belonging to a feature the target org has not licensed (Data Cloud,
  DevOps Center, Loyalty, Commerce…) will also be rejected. If a deploy names
  one, **delete that `tabSettings` block** — nothing depends on it.
  `scripts/check-references.py` lists every grant it considers licence-gated.

---

## 8. Secrets and org-specific values

The repo carries **no** API keys, tokens, passwords, org ids or usernames.
`scripts/check-references.py` §12 scans for all of them on every run and fails
the build on a hit, so this stays true rather than being true once.

Two values *are* org-specific and are handled as configuration:

| Value | How it is handled |
|---|---|
| The Anthropic API key | Never in source. `GTM_Agent_Settings__c.Claude_API_Key__c`, set per org — §6 step 12. The only committed value is a test fixture that says `sk-ant-test-key-not-real` |
| `GTM_Offering__mdt.CMS_Channel_Id__c` | Was a committed dev-org id (`0apgK0000…`). Now deliberately blank, with a comment saying why — §6 step 16. Blank is safe: `GtmStoryContentController` finds no index rows and `gtmStory` renders its DEFAULTS |

Two remote site settings still carry the dev org's My Domain
(`GTM_Offerings_Org_Self_Callout`, `GTM_Offerings_Site_Public_CMS`). A remote
site setting has to name a literal URL, so there is nowhere else to put it —
these are a **post-deploy edit**, §6 step 13. The checker reports them as
warnings on every run so they cannot be forgotten.

`HANDOVER.md` in the repo root is a historical session note that names the dev
org's username and site URL. It is not read by anything and it describes an org
that is expiring; treat it as an artefact of the build, not as configuration.

---

## 9. The consecutive-underscore risk — read this before pass 4

Twenty-five custom metadata records have a `DeveloperName` containing two
consecutive underscores: the migration pairs, spelled `source__target`
(`hubspot__mcn`, `any__mcn`, `sfmc__mcn`, `eloqua__sfmc`, the six
`GTM_Migration_Pair` records, and the `GTM_Assessment_Dimension_Override` records
derived from them).

**Salesforce documents `DeveloperName` as disallowing consecutive underscores.**

`scripts/build-instrument.py` warns on each and describes the spelling as
matching "the existing `GTM_Migration_Pair` naming". **That precedent proves
nothing**: those six records were written in commit `994d296`, the same
unverified batch as the assessment work, and the build script's own comment says
"nothing here has been deployed to a real org yet". There is no evidence in
either direction, and the risk is real enough that it is worth a decision rather
than a shrug.

**The decision taken:** leave the names as they are, and make the fix one
command away rather than a rewrite under deadline. Renaming pre-emptively would
churn 25 files and every reference to them for a rule that may not be enforced
on this metadata type; not preparing for it at all would cost whoever picks this
up a failed first deploy with no obvious remedy. So:

```bash
python3 scripts/rename-pair-keys.py               # show the 10 renames
python3 scripts/rename-pair-keys.py --apply       # eloqua__sfmc -> eloqua_to_sfmc
python3 scripts/build-instrument.py               # regenerates all 25 records
python3 scripts/check-references.py               # confirms nothing dangles
./scripts/deploy-fresh-org.sh new-org
```

This has been run end to end against a scratch copy of the tree: 10 renames, 19
generated records rewritten and 19 stale ones removed, and the reference audit
clean afterwards. What has *not* been done — because there is no org and no `sf`
CLI in the environment this was written in — is a deploy either way.

The rename is safe because the pair key is data, not code: Apex never constructs
one (`GtmAssessmentInstrument` reads `DeveloperName` off the row;
`GtmMigrationPairs` matches on `Source_Key__c`/`Target_Key__c` and never looks at
`DeveloperName`), and the Apex tests build their own in-memory fixtures. The one
thing it does not carry is
`GTM_Assessment_Request__c.Instrument_Pair__c` on assessments already scored under
the old name — irrelevant in a fresh org, a deliberate decision in an org that
has history.

**If the first deploy's pass 4 fails on a `DeveloperName`, run the four commands
above and come back. Then delete this section's hedging and record what actually
happened.**

---

## 10. Verification checklist — proving it works end to end

Static checks pass ≠ the thing works. Walk this whole list, in order, on the
target org. Use a private/incognito window wherever it says *unauthenticated* so
you are genuinely not logged in.

### A. The deploy landed

| # | Do this | Expect |
|---|---|---|
| A1 | `sf apex run test --target-org new-org --test-level RunLocalTests` | all pass |
| A2 | `npx sfdx-lwc-jest` | all pass. 114 tests in 9 suites at the commit that wrote this; the number only ever goes up, so read it as "none failing" rather than as a target |
| A3 | `python3 scripts/check-references.py` | `0 deploy-blocking` |
| A4 | `python3 scripts/build-instrument.py --check --allow-missing-source-root` | "Instrument up to date", all 11 rules hold |
| A5 | Setup → Custom Metadata Types → MA Assessment Pair → Manage Records | 5 records. Then MA Migration Platform (5) and MA Migration Pair (6) — the questionnaire's first question is built from those, so an empty list here is a blank B2 |
| A6 | Setup → Approval Processes → MA Readout Approval | present and **Active** |
| A7 | Setup → Queues → Unassigned Readouts | exists, supports `Case` and `GTM_Readout__c`, **has members** |
| A8 | App Launcher → GTM Offerings | opens, six tabs |

### B. A prospect completes the questionnaire

| # | Do this | Expect |
|---|---|---|
| B1 | *Unauthenticated*, open `/gtmaccelerator/s/assessment` | the questionnaire renders — it is reading `GTM_Assessment_Question__mdt` through Apex, so a blank page here means step 3 of §6 was skipped |
| B2 | Pick a source and target platform | the platform list came from `GTM_Migration_Platform__mdt`; the eight questions change with the pair (`GTM_Assessment_Pair__mdt` resolution) |
| B3 | Answer all eight and submit | a thank-you, not an error |
| B4 | In Salesforce, open Assessment Requests | one new record, `Status__c` set, `Assessment_Score__c` and `Assessment_Tier__c` populated **server-side**, `Instrument_Pair__c` naming the pack that scored it |

### C. A Draft readout is generated and assigned

| # | Do this | Expect |
|---|---|---|
| C1 | Open the new `GTM_Assessment_Request__c` | a related `GTM_Readout__c` exists, `Status__c = Draft` |
| C2 | Check its **Owner** | a rep if one was resolvable, otherwise **Unassigned Readouts** |
| C3 | Check the related **Case** | one review case, same owner, `Case.Readout__c` pointing back |
| C4 | If queue-owned: as a queue member, change Owner to yourself | the record becomes yours; the claim is the standard queue action |

### D. A rep edits, submits, approves

| # | Do this | Expect |
|---|---|---|
| D1 | As the owning rep, open the **Readout Editor** tab | the draft content, editable |
| D2 | Edit and save | saved; the editor is `GtmReadoutController.saveDraftContent` |
| D3 | **Submit for Approval** | `Status__c → Pending Approval`, and the record **locks** |
| D4 | Try to edit now | refused with an explanation, not a raw platform lock error |
| D5 | As the owner's **manager**, approve | `Status__c → Approved`, record unlocks, `Approved_By__c`/`Approved_Date__c` stamped, and **both** halves frozen: `Approved_Content__c` from `Draft_Content__c` (the prose) and `Approved_Data__c` from `Readout_Data__c` (the scores). One `GTM_Readout_Version__c` row is written carrying `Snapshot__c` **and** `Data_Snapshot__c` — if the data snapshot is empty, the approval froze half the readout and the scores can still drift |
| D6 | Confirm nothing published itself | `Public_Link_Token__c` still **empty**. Approval must never put a live link in a prospect's inbox |
| D7 | On a second readout, reject instead | `Status__c → Draft`, unlocked, editable again |

### E. Publish, and an unauthenticated recipient reads and comments

| # | Do this | Expect |
|---|---|---|
| E1 | As the rep, **Publish** the approved readout | `Public_Link_Token__c` is minted, `Published_Date__c` stamped |
| E2 | *Unauthenticated*, open `/gtmaccelerator/s/readout?token=<token>` | the readout prose, the **scores** (band ladder, per-dimension rows, provenance), and the rep's name/email/phone. Prose but no scores means `Approved_Data__c` did not survive D5 |
| E3 | Same URL, one character of the token changed | a generic "not found" panel |
| E4 | `/gtmaccelerator/s/readout` with no token at all | the **identical** panel, and no Apex call |
| E5 | Unpublish and reload E2's URL | the **identical** panel |
| E6 | Take a *Draft* readout's token and open it | the **identical** panel |
| E7 | On E2's page, pick a section and leave a comment | "Thanks — your comment has been sent…", and the comment lands on the review Case, prefixed with the section |
| E8 | Reply to that comment from the Case in Salesforce, reload the prospect page | your reply is **not** visible to the prospect |
| E9 | Send six comments inside ten minutes | the sixth is refused **in the same words** as E3 — no mention of a limit |

E3–E6 must be visually indistinguishable from each other. Anything that tells a
visitor *why* a token failed leaks that a readout is being prepared for a given
deal. `docs/runbooks/readout-public-link.md` has the fuller version of this test
(14 steps) and the reasoning behind each one.

### F. The story site

| # | Do this | Expect |
|---|---|---|
| F1 | *Unauthenticated*, open `/gtmstory/s/` | the story page renders |
| F2 | Before §6 steps 14–16 | placeholder DEFAULTS copy — correct, not an error |
| F3 | After them | the authored CMS content |

**The solution is not "deployed" until section E passes.** Everything before it
proves the metadata arrived; only E proves the thing the product owner actually
asked for — a prospect answering questions at one end and a client reading a
published readout at the other.

---

## 11. Related runbooks

- **`DEPLOYMENT.md` + `scripts/deploy.sh`** — the deploy path for an org that
  already has its Experience Cloud sites and base setup in place (this is
  what's actually been run against `gtm-dev`, and is battle-tested). Use
  that path instead of this runbook unless you're genuinely starting from a
  fresh org with none of this deployed yet.
- `docs/runbooks/readout-public-link.md` — the readout link, the triage queue,
  the review Case, the approval process, the guest security posture, and the
  14-step public-link smoke test. **The authority on anything readout-specific**;
  this runbook deliberately does not repeat it.
- `docs/runbooks/assessment-instrument.md` — what the instrument measures, the
  adaptive layer, and how to author a new pair.
