# TASK SCOPE — ISSUE #30

Source: `gh issue view 30 --repo iwintrose/gtm-offerings` ("GUS utility bar button
overlaps the native Help launcher; fold Help into GUS (Agentforce-powered)").
Relates to #10 (GUS utility bar host, now version-controlled per commit `138c310`,
contract at `docs/architecture/gus-utility-bar-host.md`).

## 1. Requirements Breakdown

- **Target Objective:** Two-tier. Tier 1 (ship first, small): stop the GUS
  utility-bar pill from visually colliding with a native floating "Help"
  launcher in the bottom-left corner of the **GTM Offerings** app. Tier 2
  (larger, architecture decision, NOT picked here): fold Help into GUS as one
  assistant surface, and decide what "Agentforce-powered" concretely means for
  this app.

  ---

  ### TIER 1 — the overlap fix

  **Confirmed in source (`git`/`grep`, read-only):**
  - `force-app/main/default/flexipages/GTM_Offerings_UtilityBar1.flexipage-meta.xml`
    sets `<template><name>one:utilityBarTemplateDesktop</name><properties>
    <name>isLeftAligned</name><value>true</value></properties></template>` —
    this is the utility-bar alignment lever the issue asks about, and it is
    already source-controlled (`docs/architecture/gus-utility-bar-host.md`
    §7 confirms this file only entered source on 2026-09-25, commit `138c310`).
    Flipping it to `false` would right-align every utility item including
    `gtmGusUtility`, moving the GUS pill to the bottom-right.
  - Grepped the whole `force-app/` tree for any metadata this repo could have
    added for a native help surface — `find force-app -iname "*prompt*" -o
    -iname "*guidance*" -o -iname "*embeddedService*" -o -iname "*helpMenu*"`
    returned zero relevant hits (only two unrelated files: a Jest spec named
    `...loginPrompt...` and a field called `Evidence_Prompt__c`). No
    `Prompt`, no `InAppGuidance`, no `embeddedServiceConfig` metadata exists
    anywhere in this repo. **This app did not build the native Help bubble** —
    whatever it is, it is either a Salesforce org-level default or something
    enabled by hand in Setup, not something version-controlled here.
  - This repo has already investigated the adjacent question once, for the
    Guided Setup checklist (`docs/architecture/guided-setup-implementation-plan.md`
    §0.1): *"Guidance Center / Setup Assistant: org-level Lightning Experience
    onboarding for standard Salesforce features; not a place a customer app
    contributes per-app, state-detecting steps. (U)"* and *"In-App Guidance
    (prompts, walkthroughs): ... org configuration, not source-deployable in
    this repo."* Both were marked `(U)` — unverified by an agent, confirmed
    only by a live QA browser/Setup pass — not asserted as settled fact.
  - The org this app runs in was independently confirmed to be a demo/trial
    provisioning (`agent/issue-gus-live-agentforce-provider-auth`, commit
    `699cc86`: *"This org's username (`isiah.wintrose@gmail.com2026_09_19_0-2-55.demo`)
    suggests a demo/trial provisioning"*). Salesforce demo/trial orgs commonly
    ship with onboarding/Guidance-Center-style floating launchers turned on by
    default, which is consistent with — but does not by itself prove — the
    "native Help bubble" being Guidance Center specifically rather than the
    classic Help Menu or something else.

  **Genuinely ambiguous — flagged, not guessed:** which exact native
  Salesforce feature the "? Help" bubble is (Guidance Center vs. the classic
  Lightning Help Menu vs. something else), and whether Setup exposes a
  per-app (rather than org-wide) toggle to disable or reposition it, **cannot
  be determined from source alone** — there is no metadata type for this repo
  to grep that would settle it, and this BA pass has no browser tool to drive
  the live UI. This needs a live Setup-UI check on `gtm-staging` (Setup search
  "Guidance Center", "Help Menu", "In-App Guidance") before the Architect
  commits to a specific disable/reposition mechanism. Do not build against a
  guessed Setup path.

  **A third collision the issue text does not mention, found by tracing the
  actual pages, not just the two components the issue names:** `gtmFaqPanel`
  — the existing CMS-editable "Help (FAQ)" panel from backlog item B1 — is
  *also* a bottom-left floating "Help" FAB, and it already sits on the same
  page as the GUS utility item:
  - `force-app/main/default/lwc/gtmFaqPanel/gtmFaqPanel.css` line 1-2, verbatim:
    `/* Bottom-left, so it never competes with the assistant bubble's
    bottom-right corner on the client-facing configurator pattern
    (c/gtmAgentBubble) even though neither of this panel's two hosts uses
    that component today. */` followed by `.fp-root { position: fixed; left:
    20px; bottom: 20px; z-index: 8000; ... }`.
  - `grep -rln "gtmFaqPanel" force-app/main/default/lwc --include="*.html"`
    returns exactly two hosts: `gtmOverview.html` (line 330:
    `<c-gtm-faq-panel template-type="faq-bd" fab-label="Help">`) and
    `gtmContentHome.html` (line 443: `template-type="faq-content-manager"`).
  - `gtmOverview` is embedded on `GTM_Offerings_Home.flexipage-meta.xml`
    (`grep componentName` → `gtmOverview`), which is the `standard-home` tab
    of the **GTM_Offerings** app — the exact same app `GTM_Offerings_UtilityBar1`
    (and `gtmGusUtility`) is attached to.
  - Net: on the GTM Offerings Home/Overview page today there are up to
    **three** bottom-left click targets stacked in the same corner — the
    native Help launcher, the GUS utility pill, and `gtmFaqPanel`'s own
    "Help" FAB (`fp-fab`, its own `z-index: 8000`) — not two. `gtmContentHome`
    (Content Manager app) only has `gtmFaqPanel`; it has no GUS utility item
    at all (see Tier 2 notes below), so it is not part of this particular
    collision.
  - This matters directly for the issue's own framing: the owner's direction
    is "fold the Help experience INTO the GUS bar, so there's one assistant
    surface." `gtmFaqPanel` **is** the existing Help experience on the BD app
    side (`faq-bd`) — the issue's own point 3 names `faq-bd` as one of the
    "help framework inputs" to fold in, not a separate widget to leave
    running side-by-side. A Tier 1 fix that only re-aligns or hides the
    *native* Help bubble and leaves `gtmFaqPanel` floating bottom-left next to
    the GUS pill has not actually removed the collision the owner is
    describing, and a fix that touches `gtmFaqPanel`'s visibility on
    `gtmOverview` starts to cross into Tier 2 territory (retiring/replacing it
    is naturally sequenced with folding its content into GUS). The Architect
    should treat "does Tier 1 touch `gtmFaqPanel` on the Overview page, or
    leave it for Tier 2" as an explicit decision point, not an oversight.
  - `gtmFaqPanel` has **no Jest test** today (`find
    force-app/main/default/lwc/gtmFaqPanel -iname "*.test.js"` → no results).
    Any change to its visibility/rendering is currently unprotected by any
    regression spec.

  **Small, ship-first candidate shape** (Architect's call, not decided here):
  a metadata-only change to `GTM_Offerings_UtilityBar1.flexipage-meta.xml`
  (alignment) and/or an owner Setup-UI click (disable/reposition the native
  widget for this app if such a toggle exists) — genuinely small if the live
  Setup check confirms a per-app toggle exists; genuinely NOT small (and no
  longer "Tier 1") if it turns out the only lever is hiding/retiring
  `gtmFaqPanel` on `gtmOverview`, which is Help-content-shaped work.

  ---

  ### TIER 2 — Agentforce-powered help (architecture decision, NOT picked here)

  **AGENTS.md §1 and `docs/architecture/gus-utility-bar-host.md` confirm, and
  this BA pass independently re-verified against `GtmAgentProxyController.cls`
  at HEAD, that GUS today is deliberately NOT Agentforce:**
  - `GtmAgentProxyController.cls` line 42: `static final String
    PROVIDER_AGENTFORCE = 'Agentforce';`, and lines 911-920: `getProvider()`
    — *"The provider runLoop() will actually call (never 'Agentforce')"* —
    `resolveEffectiveProvider` treats a stored `Agentforce` setting as
    *"saved-but-inactive (never called)"* and silently falls back to
    Anthropic/OpenAI/Gemini, whichever has a key.
  - `docs/architecture/gus-chat-provider-settings.md` §5 (current, on `main`):
    *"Salesforce Agentforce | `Agentforce` | Never called. Saved config only;
    `runLoop` falls back."*

  **This BA pass found an in-flight, unmerged branch directly relevant to
  option (b) below that the issue text does not mention, and it changes the
  Architect's risk picture materially:** `agent/issue-gus-live-agentforce-provider-auth`
  (4 commits, latest `699cc86`, NOT an ancestor of `main` —
  `git merge-base --is-ancestor a11b6e7 HEAD` returns false) is actively
  trying to wire a real Agentforce Agent API call into `GtmAgentProxyController`
  and is **currently blocked**, unrelated to Help specifically:
  - The org has a live Agentforce agent built via Agent Script/Agentforce
    Builder (`docs/architecture/gus-chat-provider-settings.md` §5a on that
    branch: *"CONFIRMED (coordinator, live gtm-staging Setup, 2026-09-24):
    the org has moved to Agent Script / Agentforce Builder as the only
    creation path for a first agent ... zero existing agents [via legacy Bot
    Builder]"* — i.e. Agentforce Studio is real and provisioned, matching the
    issue's own claim).
  - But every live smoke test of the session-start Agent API call returns
    `STATUS=404` with an empty body, across three attempts and four rounds of
    live config fixes (adding OAuth scopes, re-testing). The Developer on
    that branch isolated it further: an **unauthenticated `curl` to the same
    public Agent API endpoint from an entirely unrelated machine returns the
    identical 404** — "byte-for-byte indistinguishable" from the
    authenticated, correctly-scoped request from this org. Their own
    conclusion, quoted verbatim: *"Recommend the coordinator treat this issue
    as not yet done, and specifically not assume any further guessed
    configuration change will fix it — the next productive step is
    entitlement verification or a non-Apex request, not another metadata
    edit."*
  - Consequence for issue #30: a real Agentforce agent (option b below) is
    not just "an architecture decision" in the abstract — there is a **live,
    currently-blocked** attempt to get basic Agent API connectivity working
    at all, on a separate issue, with no confirmed resolution yet. Any Tier 2
    plan that assumes option (b) is readily buildable should first check
    whether `agent/issue-gus-live-agentforce-provider-auth` has landed and
    the entitlement/infra question is resolved.

  **Option (a) — GUS's existing custom loop answers from FAQ content.**
  Concretely: a new `GtmAppTool` implementation (same pattern as the two
  tools already registered in `GtmAppAgentSurface.registeredTools()` —
  confirmed by reading the class at HEAD: `registered.add(new
  GtmStageFilterAppTool()); registered.add(new GtmFilterByQueryAppTool());`)
  that reads FAQ content the same way `gtmFaqPanel` already does
  (`GtmPageContentReader.getPageContent` addressed at `gtm::faq-bd::faq::*` /
  `gtm::faq-content-manager::faq::*`) and answers from it inside the existing
  `chatOnApp` loop. This reuses an established, already-proven extension
  point (`GtmAppTool` interface, no-DML/no-callout contract, one registration
  line) with no new infra, no new credentials, and no dependency on the
  blocked Agent API work above. It does not touch Content Manager's app
  (which has no GUS utility item today — `gus-utility-bar-host.md` §1: *"GTM
  Content Manager app is EXCLUDED (owner decision F4, pending)"* — so a
  `faq-content-manager` tool answering inside the BD app's GUS, versus
  Content Manager's own `gtmFaqPanel`, is itself a design question the
  Architect needs to resolve, not assumed here).

  **Option (b) — a real Agentforce agent (Agentforce Studio / Agent API).**
  Matches the issue's literal "Agentforce-powered" wording most directly, but
  is currently blocked at the connectivity layer per the finding above, pulls
  in a parallel in-flight credential/infra effort, and (per
  `gus-utility-bar-host.md` §2 "F1") would likely mean a second chat surface
  or a provider-switch inside `gtmAgentChat`/`chatOnApp` rather than a small
  addition — a materially bigger, riskier lift than option (a) today.

  **Salesforce-first evaluation (repo standing rule):** the native-first
  question was already run once for the adjacent Guided Setup checklist
  (`guided-setup-implementation-plan.md` §0.1: Guidance Center, In-App
  Guidance, Path, Flow/Screen Flow — all rejected as unable to run Apex,
  detect per-app state, or take an action). The same reasoning applies here:
  neither Guidance Center nor In-App Guidance can answer a free-text question
  against this app's own FAQ/CMS content or call `GtmAppTool`s, so a native,
  zero-code "Help widget" cannot satisfy "answer from the FAQ content" either
  way. The live Salesforce-first fork that actually matters here is
  **within** "Agentforce-powered": native embedded Agentforce chat
  (`<einstein-copilot-chat>` / the Agent API) versus the custom proxy loop
  extended with a new tool. That fork is exactly what this scope defers to
  the Architect/owner — this BA pass supplies the evidence (blocked Agent API
  work; a working, low-risk `GtmAppTool` pattern already in the codebase) but
  does not pick one.

  **Prerequisite gap, confirmed live (not assumed from the issue text) —
  read-only `sf data query` against `gtm-staging`:**
  ```
  SELECT Template_Type__c, Section_Key__c, Field_Key__c, Field_Type__c
  FROM GTM_Page_Content__c
  WHERE Offering_Key__c='gtm' AND Template_Type__c IN ('faq-bd','faq-content-manager')
  → totalSize: 0

  SELECT Template_Type__c, Section_Key__c, Status__c, Active__c
  FROM GTM_Page_Section__c
  WHERE Offering_Key__c='gtm' AND Template_Type__c IN ('faq-bd','faq-content-manager')
  → totalSize: 0
  ```
  This is a stronger gap than "the FAQ content is empty" as the issue states
  — there are **zero sections of any kind** for either FAQ template in
  `gtm-staging` today, meaning the pages have never been created via the
  Content Manager's "New Offering Page" flow (or the Guided Setup
  `framework_pages` action). Confirmed by a companion query: `SELECT
  Template_Type__c, COUNT(Id) cnt FROM GTM_Page_Section__c WHERE
  Offering_Key__c='gtm' GROUP BY Template_Type__c` returns exactly one row —
  `industry-chooser: 5` — and nothing for `offerings-page`, `faq-bd`,
  `faq-content-manager`, or `assistant`. `GtmSetupChecklistController.cls` /
  `GtmSetupActionController.cls` (Guided Setup, `docs/architecture/guided-setup.md`
  §3A/§6, item key `framework_pages`) already exist on `main` and can create
  these page structures with one click, but that step has evidently not been
  run on `gtm-staging`, or was run before these two templates were added.
  Either way: regardless of which Tier 2 option the Architect picks, someone
  (the content/BA role, not this repo's code) must first run
  `framework_pages` and then actually author FAQ content before any
  "Agentforce-powered help answers from FAQ content" can return anything —
  today it would have nothing to read.

- **System Component Impacted:** Mixed — Tier 1 is Metadata (FlexiPage
  alignment property) plus possibly an owner-driven Setup UI click (no repo
  change at all if a per-app native toggle exists) plus, if the Architect
  decides `gtmFaqPanel`'s Overview placement is in scope for Tier 1, LWC.
  Tier 2 is Apex (a new `GtmAppTool` per option (a), or Apex + Named
  Credential/External Credential + LWC provider wiring per option (b)) and
  LWC (`gtmGusUtility`/`gtmAgentChat` if a second surface or mode is needed),
  plus Content authoring (non-code: filling `faq-bd`/`faq-content-manager`
  page content in the Content Manager app) as a hard prerequisite either way.
  No YAML Instrument or Experience Cloud route is impacted by either tier —
  this is entirely internal-app (`GTM_Offerings` / `GTM_Content_Manager`)
  scope; the guest-facing configurator, `gtmAgentBubble`, and the assessment
  instrument pipeline are untouched by anything in this issue.

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? **YES, for Tier 2 option (a) only.** A new
  `GtmAppTool` implementation must follow the existing zero-DML/zero-callout
  contract (`GtmAgentToolSurface`/`GtmAppTool`, AGENTS.md §1 and
  `gus-utility-bar-host.md` §4): "no DML or callouts inside a tool
  implementation — tools read/propose, they don't write directly," confirmed
  by the two existing tools (`GtmStageFilterAppTool`, `GtmFilterByQueryAppTool`)
  which are both thin, read-only wrappers. Registration is exactly one line
  in `GtmAppAgentSurface.registeredTools()`. Tier 1 and Tier 2 option (b) (if
  it stays purely inside the credential/Agent-API layer of the *other*
  in-flight issue) do not touch the tool surface.
- [ ] Altering Custom Metadata? **NO.** Nothing here touches
  `instrument/<offering-key>/` YAML or the generated
  `force-app/main/default/customMetadata/GTM_Assessment_*` XML — this issue
  is entirely about the app-shell Help surface and FAQ page content, not the
  assessment instrument. (`GTM_Page_Content__c`/`GTM_Page_Section__c` are
  ordinary custom objects, not Custom Metadata Types, and are already
  covered by the existing Guided Setup / Content Manager write paths.)
- [ ] Introducing database fields? **NO for Tier 1.** For Tier 2 option (b),
  likely **NO new fields either** — `GTM_Agent_Settings__c` already carries
  `Agentforce_Agent_Id__c`, `Agentforce_My_Domain_URL__c`, and
  `Agentforce_Client_Id__c` (added by `gus-settings-provider-ui`, already
  FLS-mapped to `GTM_Offering_Admin` only per
  `docs/architecture/gus-chat-provider-settings.md` §2) plus draft
  Named/External Credential shells on the in-flight branch. If the Architect
  finds a genuine new-field need (e.g. a per-tool-surface flag), the
  mandatory Permission Set mapping across the five sets in CLAUDE.md §6
  applies — none is anticipated by this scope.

## 3. Plan Acceptance Criteria

- **Success Metric:** Tier 1 — on the `GTM_Offerings` app's Home/Overview
  page (and every other page carrying the utility bar), a rep sees exactly
  one bottom-left assistant/help click target, not two or three; QA verifies
  this live in the browser on `gtm-staging` per this repo's standing QA rule
  (browser validation, every dependent surface, not just the changed one —
  specifically checking `gtmOverview`'s `gtmFaqPanel` FAB is not silently
  left stacked underneath). Tier 2 — deferred: whichever option the
  Architect/owner picks, success is that a rep can ask a help question in the
  GUS utility panel and get an answer sourced from the (by-then-authored)
  `faq-bd` content, with no regression to GUS's existing `find_links_by_stage`
  / `filter_by_query` tools or to the config/readout surfaces sharing
  `GtmAgentProxyController.runLoop()`.
- **Target Test Target:** Tier 1 —
  `force-app/main/default/lwc/gtmGusUtility/__tests__/gtmGusUtility.test.js`
  (existing spec, extend only if behavior changes) plus a **new** Jest spec
  for `gtmFaqPanel` if its visibility/placement changes (none exists today —
  confirmed by `find force-app/main/default/lwc/gtmFaqPanel -iname
  "*.test.js"` returning nothing), plus a live QA browser pass on
  `gtm-staging` (no automated test can catch a CSS z-index/position
  collision). Tier 2 — `GtmAppAgentSurfaceTest.cls` (exists on `main` today)
  extended with the new tool's registration/dispatch tests following the
  existing pattern for `GtmStageFilterAppTool`/`GtmFilterByQueryAppTool`, and
  a new `<NewTool>Test.cls`; if option (b) is chosen, coordinate explicitly
  with whatever lands from `agent/issue-gus-live-agentforce-provider-auth`
  rather than re-deriving Agent API request/response shapes from scratch.
