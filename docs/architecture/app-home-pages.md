# App Home pages (GTM Offerings and GTM Content Manager)

Status: contract, written before implementation (CLAUDE.md sec 4). Slug: `app-landing-page`.
Scope: `docs/agent-artifacts/task-scope-app-landing-page.md`.

## 1. Decisions (user-chosen defaults, do not weaken)

1. Each app lands on an EXTENDED STANDARD HOME: a Lightning Home FlexiPage
   (`type` HomePage) assigned as the App Default for that app only. No custom
   home tab.
2. Each Home shows ONLY our component (one component, in the `top` (header) region of `home:desktopTemplateHeaderThreeColumns`; the other regions stay empty). No standard
   reports, list views, Tasks, Events or Assistant.
3. Custom tabs `GTM_Offerings_Overview` and `GTM_Content_Home` are retired in
   TWO steps (sec 5). Delete-from-org is a separate step, gtm-staging only
   unless the user confirms otherwise. No destructive change is ever planned
   against gtm-prod.
4. GUS "Overview" navigation moves to the standard `home` named page (sec 4).
5. `isNavPersonalizationDisabled` and the app `default` flags are UNCHANGED.
6. STOP CONDITION (user reserved): if the App Default assignment does not
   round-trip as app-level `actionOverrides` on `standard-home` (no per-profile
   `profileActionOverrides` entries), stop and report. Fallback needs a user
   decision. Do not fall back on your own.

## 2. Home assignment design

Metadata: shape TAKEN FROM THE ORG (assigned once as App Default through
App Builder on gtm-staging, then retrieved; the action name is `Tab`, not
`View`). Only `<tabs>standard-home</tabs>` remains unproven (sec 9):

```xml
<!-- inside CustomApplication, alphabetical position per sf retrieve order -->
<actionOverrides>
    <actionName>Tab</actionName>
    <content>GTM_Offerings_Home</content>
    <formFactor>Large</formFactor>
    <skipRecordTypeSelect>false</skipRecordTypeSelect>
    <type>Flexipage</type>
    <pageOrSobjectType>standard-home</pageOrSobjectType>
</actionOverrides>
<tabs>standard-home</tabs>   <!-- first tab -->
```

- New FlexiPages: `GTM_Offerings_Home` and `GTM_Content_Home` (FlexiPage names
  are a separate namespace from tabs, so the second name is legal; if the org
  rejects it, use `GTM_Content_Manager_Home`). `type` HomePage, template `home:desktopTemplateHeaderThreeColumns` (regions `top`, `left`,
  `middle`, `right`; `top` is the header region, expected to span the full page
  width), one `componentInstance` (`gtmOverview` / `gtmContentHome`) in `top`,
  the other three regions empty. Region names taken from a retrieved real-org
  page that uses this template. (`home:desktopTemplate` was tried first: its
  `top` region is only the LEFT column, about 660-700px of 1078px, which
  squeezed Content Home; superseded.) Earlier fallback: create the page once in Lightning App Builder on gtm-staging (New
  > Home Page), assign it as App Default, then RETRIEVE it and commit that
  retrieved XML rather than hand-guessing the template.
- LWC exposure: add `<target>lightning__HomePage</target>` to
  `gtmOverview.js-meta.xml` and `gtmContentHome.js-meta.xml`. Keep
  `lightning__AppPage` and `lightning__Tab` through step 1; `lightning__Tab` is
  removed in step 2 only if nothing else uses it (`GTM_Readouts_Overview` uses
  AppPage, unaffected).
- No new Apex, schema, or classAccess. Rep scoping stays in
  `GtmHomeSnapshotController` (`with sharing` + running-user owner filter).
- `gtmConfigWizard._measureChromeOffset` assumes the wizard sits at the top of
  the page; QA must verify on the Home shell (scroll 0 and 500px).
- Other apps' Home must be unchanged (App Default, never Org Default).

## 3. Verified facts (Architect, against source and a read-only gtm-staging retrieve)

- Source and gtm-staging match for both apps: neither contains `standard-home`,
  and neither has `actionOverrides` or `profileActionOverrides`. Differences
  are only default-valued attributes the org echoes back (`shouldOverrideOrgTheme`,
  `isNavTabPersistenceDisabled`, `isOmniPinnedViewEnabled`,
  `isNavAutoTempTabsDisabled`). So the "Home" a rep sees on staging is NOT from
  app metadata. Most likely cause (UNVERIFIED): per-user nav personalization
  (`isNavPersonalizationDisabled` is false) or a user opening the org Home
  outside the app. Not fixable by metadata; it is why the Home FlexiPage must be
  assigned as App Default.
- The `Admin` profile on staging has `GTM_Offerings_Overview` tab Hidden and both
  apps not visible (profile-level, not permission-set-level, grants).
- `site-shell-metadata` branch diff touches no `applications/`, `tabs/`, `lwc/`,
  `flexipages/`, `permissionsets/` or `profiles/` files. No overlap.

## 4. GUS navigation contract change

Replaces the `GTM_Offerings_Overview` entry in
`docs/architecture/gus-utility-bar-host.md` sec 5.

- `ALLOWED_NAVIGATION` key `GTM_Offerings_Overview` is REPLACED by key `home`
  (permitted state keys: none).
- `_validatedTarget` unchanged in policy (allow-list, `c__` state, <= 200 chars).
- `handleAgentAction` builds the reference from the key: `home` becomes
  `{ type: 'standard__namedPage', attributes: { pageName: 'home' } }`; every
  other key stays `standard__navItemPage` with `apiName`.
- `pageContext` (wire): unchanged shape. On the Home page the reference type is
  `standard__namedPage`, so `pageType` is sent and `tabApiName` is absent (this
  is the existing behaviour for non navItem pages). No new context key.
- No server tool emits `GTM_Offerings_Overview` today (verified by grep), so no
  Apex tool change. `GtmStageFilterAppToolTest` fixture
  `{"tabApiName":"GTM_Offerings_Overview"}` (line ~485) becomes
  `{"tabApiName":"GTM_Pages"}` in step 2 (any existing tab is fine; the test
  asserts on the pageEffect, not the context).
- Jest (`gtmGusUtility.test.js`): add cases for `home` accepted with empty state,
  `home` with any state rejected, the named-page reference shape on Navigate,
  and that `GTM_Offerings_Overview` is now rejected.
- Zero-DML/zero-callout tool contract (AGENTS.md sec 1) is untouched.

## 5. Two-step tab retirement

Step 1 (with the Home pages, deploys to staging first):
- Remove `<tabs>GTM_Offerings_Overview</tabs>` and `<tabs>GTM_Content_Home</tabs>`
  from the apps; add `<tabs>standard-home</tabs>` first; add the `actionOverrides`.
- Keep tab files and every `<tab>` grant so rollback is a one-line app change.
- Do the GUS allow-list change + tests + doc here (the allow-list key becoming
  `home` does not depend on the tab file).

Step 2 (only after QA passes on staging):
- Delete `tabs/GTM_Offerings_Overview.tab-meta.xml` and
  `tabs/GTM_Content_Home.tab-meta.xml`.
- Remove `<tab>` grants: `GTM_Offering_User` (line ~908), `GTM_Offering_Admin`
  (~1078), `GTM_Content_Manager` (~308), `GTM_Content_Admin` (~304).
- ALSO remove `GTM_Offerings_Overview` `tabVisibilities` from
  `profiles/Standard.profile-meta.xml` and `profiles/StandardAul.profile-meta.xml`
  (missed by the BA scope; a deploy that deletes the tab while a profile still
  references it fails).
- Update doc references: `docs/specs/prospect-page-wizard.md` (lines ~79, ~203),
  `docs/architecture/adr/0002-...md` (line ~20, historical, add a note only),
  `docs/architecture/adr/0010-...md` (line ~27).
- Org deletion needs a destructive-changes manifest: gtm-staging ONLY. It is
  not part of this PR's default deploy and is NEVER run against gtm-prod.

## 6. Permission-set review (CLAUDE.md sec 6.1; no fields or objects added)

| Set | Change |
|-----|--------|
| GTM_Offering_User | step 2: remove `GTM_Offerings_Overview` tab grant. Nothing added (standard-home needs no grant; classAccess exists). |
| GTM_Offering_Admin | step 2: same. |
| GTM_Content_Manager | step 2: remove `GTM_Content_Home` tab grant. |
| GTM_Content_Admin | step 2: same. |
| GTM_Guest | none (guest sites unaffected). |
| profiles Standard, StandardAul | step 2: remove `GTM_Offerings_Overview` tabVisibility. |

Content sets must not gain rep/GUS grants as a side effect.

## 7. Gate order

1. Contract (this note) committed. Done before code.
2. Developer builds Home FlexiPages, meta targets, app edits, GUS change and
   tests (step 1 only). `npm test` green.
3. QA on gtm-staging, gate 1: deploy, activate/verify the App Default, retrieve,
   and confirm app-level `actionOverrides` on `standard-home` round-trips with
   no per-profile entries. If not, STOP and report to the user.
4. QA browser check on staging across every dependent surface: both apps
   (Home first, components fully functional, wizard on-screen at scroll 0 and
   500px), rep vs admin scoping, Content Manager and Content Admin users, Sales
   app Home unchanged, GUS "Overview" navigation, Experience Cloud sites.
5. Step 2 (tab deletion, grants, profiles, docs) on staging, re-run QA, then
   destructive change on staging only.
6. gtm-prod deploy ONLY with the user's explicit authorization for THIS change.
   Before it: QA snapshots current gtm-prod application, tab and profile
   metadata (read-only retrieve, kept outside the repo, for rollback), runs
   `--dry-run` first, then deploys once in a single batched run (dev API quota
   has been exhausted before). Never `-c`. No org IDs, usernames or secrets in
   any committed file.

## 8. Salesforce-first evaluation

- Lightning Home page as App Default: native. Chosen per user preference.
- Custom parts remaining: the two LWCs (already exist) and one allow-list edit.
- Sources UNVERIFIED (no web/doc tool): `actionOverrides` shape, HomePage
  template name, `lightning__HomePage` target behaviour for full-page LWCs. QA
  proves all three on gtm-staging in gate 3.

## 9. Step 1 implementation notes and assumption status (Developer)

1. Template (REVISED after live check of 906d407): `home:desktopTemplate`
   rendered the component in a left column only. Both pages now use
   `home:desktopTemplateHeaderThreeColumns`, component in `top`, empty `left`,
   `middle`, `right`. Template and region names come from a real org page;
   that this template deploys with our component and that `top` renders FULL
   WIDTH are both UNPROVEN (header-spans-full-width is inferred from the
   template name and Salesforce's layout, not seen). If `top` is not full width
   no other HomePage template is known to be available; options for the user
   then: (a) accept a partial-width Home, (b) a custom HomePage template
   component (not chosen, needs design), (c) land the app on the existing
   custom tab instead (the fallback in item 4). Not chosen by the Developer.
2. FlexiPage names: PROVEN. Pages deployed under 906d407.
3. `actionOverrides` (`Tab`, app level, no profile entries): shape from the org,
   deployed under 906d407 and the Home showed in the browser.
4. `<tabs>standard-home</tabs>` first: deployed under 906d407; QA to confirm
   round-trip on retrieve. Fallback if it ever fails: leave it out of `<tabs>`
   and keep the custom tab first (decision needed).
5. Wizard chrome offset (`gtmConfigWizard._measureChromeOffset`): UNVERIFIED in
   the header region; check scroll 0 and 500px.
6. `lightning__HomePage` target: renders (seen live); full-width behaviour is
   item 1.
7. Session caching: the first App Launcher launch after a deploy may show the
   old shell until a reload. This is not a defect in the metadata.
8. Stale copy: "Overview tab" wording in gtmRepLinkFinder, gtmAnalytics (empty
   states), a gtmConfigWizard comment and a GtmSavedConfigurationController
   comment now says Home page. Tab files and the GUS allow-list are unchanged.
9. Tab files and grants untouched (step 2); Apex fixture unchanged until step 2.

## 10. Step 2 implemented (Developer)

Done in source: tab files `GTM_Offerings_Overview` and `GTM_Content_Home`
deleted; `<tabSettings>` grants removed from `GTM_Offering_User`,
`GTM_Offering_Admin` (Overview), `GTM_Content_Manager`, `GTM_Content_Admin`
(Content Home); `<tabVisibilities>` for Overview removed from `Standard` and
`StandardAul` profiles; `GtmStageFilterAppToolTest` fixture now uses
`GTM_Pages`; doc references updated (`prospect-page-wizard.md`, ADR-0010, a
historical note in ADR-0002). `scripts/check-references.py` section 17 now
fails if a permission set, profile, app `<tabs>` list or the GUS allow-list
still names either retired tab (proven by injecting fake references, reverted).
The FlexiPage `GTM_Content_Home` is a different metadata type and is not
matched. Step 1 was proven on gtm-staging (layout ~97% width, gate 1 passed).

Destructive change: the manifest is prepared, NOT run, in
`docs/agent-artifacts/app-landing-page-destructive/` (`destructiveChanges.xml`
listing exactly the two `CustomTab` members, plus an empty `package.xml`). It
runs on gtm-staging ONLY. The user has NOT authorized any destructive change
on gtm-prod; none may be run there without a fresh, explicit instruction for
that org.
