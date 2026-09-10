# Contentful for GTM page/story content — decision and (conditional) plan

**Status: NOT AUTHORITATIVE.** This is agent output under
`docs/agent-artifacts/`, which `CLAUDE.md` §2 defines as ephemeral and
requiring explicit human promotion before it counts as source of truth. It is
deliberately **not** an ADR and does not claim ADR status: two of its three
decisive inputs are a procurement approval and a product-owner design fork,
neither of which an agent can settle. It is written in ADR shape (Context /
Decision / Consequences) so that a human can promote it verbatim once those
gates clear — `docs/architecture/adr/` currently ends at `0008`, so **`0009-`
is the next free slot**. The precedent for that path already exists in this
tree: `docs/agent-artifacts/per-offering-instrument-plan.md` preceded
`adr/0007-assessment-instrument-becomes-per-offering.md`.

**Author:** Developer agent, issue #18. **Scope of this pass:** this file
only. No `force-app/`, `migration-accelerator/`, `scripts/` or `data/` change,
and no org operation of any kind was performed.

---

## 1. Decision

**Do not migrate GTM page/story content to Contentful.** Not the whole model,
and not a subset — including the long-form story/FAQ content that looks most
CMS-shaped, because that is precisely the content on the guest render path.

Content stays in `GTM_Page_Content__c` / `GTM_Page_Section__c` /
`GTM_Page_Content_Version__c`, read through `GtmPageContentReader`, authored
through `gtmContentManager`. The three problems that motivated the question —
editing ergonomics, weak versioning, no real preview — are **real**, and §7
redirects each to in-org work already sized in `docs/backlog.md` rather than
to a vendor.

This is a technical recommendation. It does **not** pre-empt the three human
gates in §8; those are the only things that could overturn it, and none of
them is mine to call. §6 carries the conditional plan that would apply if a
human overturns it anyway, so the recommendation is falsifiable rather than
merely negative.

### Why, in four facts that are properties of this tree

1. **There is no external content dependency at guest read time today, and
   introducing one is a one-way door.** Every one of `GtmPageContentReader`'s
   five entry points (`getPageContent`, `getPageLayout`, `getOfferingTiles`,
   `getIndustryProfiles`, `getSiteInfo`) is `@AuraEnabled(cacheable=true)` and
   backed by SOQL. A prospect's page render currently cannot fail because of
   somebody else's uptime.
2. **This project already adopted a CMS and could not fully exit it.** See §2.
3. **The org is production and the content has already been damaged once.**
   See §8.3.
4. **The GUS coupling is worse than the issue assumes.** The page-content read
   sits inside the agent's system prompt, which is re-evaluated on every
   iteration of the tool loop. See §5.

---

## 2. Context — prior art this decision has to answer to

`docs/backlog.md`'s "Done this session" list records **B4: "the retired CMS
content (records deleted by Don, the 5 dead `managedContentType` definitions
removed)."** The story used to be authored as Salesforce CMS managed content —
`scripts/data/remove-retired-story-cms.apex` names the five retired types
(`ma_story_body`, `ma_faq_item`, `ma_industry_story`, `ma_story_setting`,
`ma_story_page`) — and that whole path was replaced by the custom objects in
use today. So the current model is not the naive default that nobody
questioned; it is the *second* answer, adopted after the first was abandoned.

The most instructive detail is in that script's own header:

> `// THIS SCRIPT CANNOT RUN. ManagedContent is not deletable by Apex DML, and`
> `// no ConnectApi delete exists in this API version -- both were tried. It is`
> `// kept as the record of exactly what has to go and how to find it.`

The exit from the last content home **could not be automated** and degraded
into a documented sequence of manual Setup clicks. That is the honest cost
model for adopting a third content home: entry is a project, exit is an
unbudgeted manual one. A recommendation to adopt Contentful would have to say
what is different this time, and the candid answer is "Contentful's export API
is better than `ManagedContent`'s" — which is an argument about how the *next*
migration goes, not about whether this one is worth doing.

### Debris still in the tree from the last attempt (cleanup either way)

None of this is blocked on the Contentful decision; all of it should be
removed regardless of which way §1 goes.

- `force-app/main/default/remoteSiteSettings/GTM_Offerings_Site_Public_CMS.remoteSite-meta.xml`
  — still `<isActive>true</isActive>`, and its `<description>` names
  `MaStoryContentController` as its consumer. That class **does not exist**
  anywhere under `force-app/main/default/classes/` (killed by the `Ma`→`Gtm`
  rename, `docs/backlog.md` D6). It is an active outbound-callout allowance for
  a dead caller. `scripts/check-references.py` already flags its committed
  org-specific URL as one of the 96 manual-step items.
- `force-app/main/default/remoteSiteSettings/GTM_Offerings_Org_Self_Callout.remoteSite-meta.xml`
  — same problem, same dead class named in its description. **Not previously
  noted; found while verifying the first one.**
- `force-app/main/default/objects/GTM_Offering__mdt/fields/CMS_Channel_Id__c.field-meta.xml`
  — a per-offering CMS Delivery Channel Id field whose description points at
  `MaStoryContentController` and at `scripts/setup-cms-workspace.sh`, a script
  that **no longer exists** in `scripts/`.
- `force-app/main/default/lwc/gtmConfigData/gtmConfigData.js` — its header
  comment still tells the reader that `INDUSTRIES`, `SWATCHES`, `DEFAULTS` and
  friends "are now authored in Salesforce CMS
  (`force-app/main/default/managedContentTypes/`) and read at runtime via
  `MaStoryContentController.getStoryContent()`." That directory is gone and
  that class is gone; the comment is actively misleading about where content
  lives.
- `docs/runbooks/fresh-org-deploy.md`'s deploy-pass table still lists
  `managedContentTypes/` as pass-5 metadata.

Four of those five artifacts each independently assert that story content is
served from a CMS. Anyone reading this repo cold gets the wrong answer about
where content lives, which is its own argument for cleaning up before adding a
third possible answer.

---

## 3. Context — what the content model actually is

The issue describes "one story + N pages + N sections per offering." The real
model is more structured than that in three ways that matter for any mapping.

### 3.1 Three objects, not two, and one of them is welded on

- `GTM_Page_Content__c` — 22 custom fields.
- `GTM_Page_Section__c` — 12 custom fields.
- `GTM_Page_Content_Version__c` — 4 fields (`Change_Summary__c`,
  `Content__c`, `Snapshot__c`, `Version_Number__c`), omitted entirely from the
  issue.

`Content__c` is a **Master-Detail** to `GTM_Page_Content__c`. `docs/backlog.md`'s
D6 stage-3 record is explicit that a master-detail "can't point at two object
types or be repointed after creation," which is why all three objects had to
move in a single rename stage. The same constraint applies in reverse to any
Contentful move: version rows are children of content rows, so the history
cannot be left behind in the org pointing at parents that no longer exist. It
migrates too, or it is deleted, and "delete the audit trail" is a decision
somebody has to actually take rather than discover.

### 3.2 The unit of content is an address, not a record

`GtmContentAddress` defines the whole contract in one class:

- `forField(offeringKey, templateType, sectionKey, fieldKey)` →
  `offering::template::section::field`
- `forSection(offeringKey, templateType, sectionKey)` →
  `offering::template::section`
- `normaliseKey(raw)` — lowercases, collapses every run of non-`[a-z0-9]` to a
  single hyphen, strips leading/trailing hyphens, returns `null` when nothing
  usable survives, and **truncates to 80 characters** (`cleaned.left(80)`).

That address is the external Id on `GTM_Page_Content__c`
(`Content_Address__c`) and the section↔field join
(`Section_Address__c`). A field-for-field port of the SObject schema into
Contentful content types would carry over the columns and throw away the
addressing scheme, which is the part that actually does the work. Note also
that `normaliseKey`'s 80-char truncation is silent and non-injective — two
long distinct keys can collide onto one address. That is a latent hazard
today and it becomes a *silent cross-system* hazard the moment the address is
also a Contentful entry lookup key.

### 3.3 Resolution is tiered — framework → offering → industry — and only partially so

`GtmPageContentController.FRAMEWORK_KEY = 'gtm'` is a real third tier above
offering, owning `industry-chooser`, `offerings-page`, `faq-bd` and
`assistant`. Below it, `GtmPageContentReader.getPageContent` resolves industry
overrides at read time:

```
WHERE Offering_Key__c = :offeringKey AND Template_Type__c = :templateType
  AND Active__c = true
  AND (Industry_Key__c = :industryKey OR Industry_Key__c = null OR Industry_Key__c = '')
ORDER BY Industry_Key__c NULLS LAST, Sort_Order__c ASC
```

…then `if (!result.containsKey(mapKey))` lets the first row for an address
win. So an industry-scoped row overrides an offering-wide default for the same
address. This is a resolution **algorithm**, not a content type; Contentful
has no native equivalent and it would have to be reimplemented on whichever
side of the wire the read happens.

Two things about that algorithm that are not obvious and are not recorded
anywhere else I could find:

- **`GTM_Page_Section__c` has no `Industry_Key__c` field at all.** Only
  *fields* are industry-tiered; *sections* — the page's structure — are not.
  Page structure is per-offering-per-template and shared across every
  industry. Any Contentful model that makes "an industry variant of a page" a
  first-class entry would be modelling something the current system cannot
  express, and would quietly widen the product.
- The `WHERE` clause admits `Industry_Key__c = ''` alongside `null`, but
  `NULLS LAST` only moves `null` to the end — an **empty-string** industry key
  sorts *before* any real key ascending, so a blank-string row would beat the
  industry-specific row it was meant to fall back to. No such row is known to
  exist; the point is that the fallback semantics are subtler than they read,
  and porting them by eye is how you lose them.

### 3.4 Draft/publish is a first-class in-org workflow, not just storage

`GTM_Page_Content__c` carries `Status__c`, `Draft_Value__c`,
`Pending_Delete__c`, `Version_Number__c`, `Last_Published_Date__c`;
`GTM_Page_Section__c` carries `Status__c` and `Draft_State__c`.
`GtmPageContentController` exposes `saveDrafts`, `publishPage`,
`discardDrafts`, `savePresentation`.

`publishPage` is where the semantics live, and it is doing four distinct
things in a specific order:

1. `publishSections()` then `publishFieldDeletes()` **first** — with a source
   comment explaining why: publishing a pending section delete removes that
   section's content rows, so drafts gathered beforehand would reference rows
   that no longer exist.
2. Selects `Status__c = 'Draft'` rows, then filters "has a draft" **in Apex**,
   because `Draft_Value__c` is a long-text-area and SOQL cannot filter on one.
3. Inserts a `GTM_Page_Content_Version__c` row per field holding the
   **outgoing** value as `Snapshot__c` — the version object records what was
   replaced, not what was published.
4. Copies `Draft_Value__c` into whichever of `Text_Value__c` / `Rich_Value__c`
   / `JSON_Value__c` matches `Field_Type__c`, nulls the draft, sets
   `Status__c = 'Published'`, bumps `Version_Number__c`, stamps
   `Last_Published_Date__c`.

Meanwhile `getPageLayout` filters sections to `Status__c = 'Published'` and
carries an explicit source comment that `Draft_State__c` is deliberately *not*
read — so a pending reorder, hide or delete can never leak to a guest.

Mapped against Contentful's own draft/published model:

| In-org concept | Contentful equivalent | Verdict |
|---|---|---|
| `Status__c` Draft/Published on a content row | entry draft vs published state | **maps**, roughly |
| `Draft_Value__c` — a per-field draft living *alongside* the live value on the same row | none. Contentful drafts the whole entry | **lost**, unless every field becomes its own entry (see §6.1) |
| `Draft_State__c` on a section (pending reorder/hide) | none | **lost** |
| `Pending_Delete__c` — publish-gated deletion | none. Unpublish/delete is immediate | **lost** |
| `publishPage(offeringKey, templateType)` — atomic page-scoped publish across sections *and* fields | Contentful publishes per entry; bulk publish is best-effort, not transactional | **lost.** A partial publish is currently impossible and would become possible |
| `discardDrafts` | revert to published version | **maps** |
| `GTM_Page_Content_Version__c` + `Snapshot__c` + `Change_Summary__c` | entry version history | **maps, and is genuinely better** — this is the one place Contentful clearly wins |
| `Last_Published_Date__c` | `sys.publishedAt` | **maps** |

Five of nine either have no equivalent or lose a transactional guarantee. The
one clear win, versioning, is also the one that is reachable without a vendor:
`GTM_Page_Content_Version__c` already exists and is already written on every
publish — it simply has **no reader**. Nothing in `force-app/` surfaces
version history to an editor. That is a UI gap, not a storage gap.

---

## 4. Answers to the six open questions

### Q1 — Guest read path

Today, in full: `GTM1` (`urlPathPrefix: gtm`) has exactly one non-boilerplate
route, `configurator.json`, whose view renders `c:gtmConfigurator`. That LWC
imports `getPageLayout`, `getIndustryProfiles` and `getSiteInfo` from
`@salesforce/apex/GtmPageContentReader.*` — i.e. the content read is
**server-side Apex invoked over the Aura endpoint**, never a client-side fetch.
`GtmPageContentReader` is `without sharing` (its header explains why: content
rows are owned by the authoring admin, so a guest running with sharing
resolves zero rows), and guest access is granted by exactly one line in
`GTM_Story_Guest.permissionset-meta.xml`:
`<apexClass>GtmPageContentReader</apexClass>`. The write-bearing
`GtmPageContentController` is granted **only** in `GTM_Config_Manager`.
`GTM_Assessment_Guest` grants no page-content class at all. The reader's own
header states the reason the class exists: Apex class access is per class, not
per method, so a read-only class is the only way to keep `saveContentRecord` /
`saveContentRecords` / `deleteContentRecord` off anonymous traffic.

Per ADR-0006, "reachable" is a property of the live site, not the source tree.
`gtmStory` and `chooseIndustry` live on `GTM_Accelerator1`, which
`docs/architecture/overview.md` records as `DownForMaintenance`; that status is
org state and must be re-verified with a `Network` query before anyone claims
those pages are or aren't live. This document does not run that query.

Under Contentful, the read has to stay Apex-side for exactly the reason the
reader class exists. That means an outbound HTTP call from a guest-context
Apex class, which means **the token has to live somewhere a guest-context
transaction can reach but a guest's browser cannot.** This repo has never
solved that problem: there is **no `force-app/main/default/namedCredentials/`
directory**. The only outbound-auth precedent is
`GTM_Agent_Settings__c.Claude_API_Key__c` — a custom setting whose object
metadata declares `<visibility>Public</visibility>` — plus a
`remoteSiteSettings` entry. A Public hierarchy custom setting is readable from
any Apex context, including a guest's. **Reusing that pattern for a Contentful
token would be a security downgrade and must be rejected.** The correct answer
is a Named Credential — a metadata type this repo has never deployed, so
adopting Contentful means adopting Named Credentials as a prerequisite, with
its own deploy/verify learning curve on an org that is production. Under no
option does the guest's browser receive a token; it receives Apex-rendered
content, as it does today.

Also worth stating because it is easy to get wrong: `GtmPageContentReader` is
not the only content consumer. Eight LWCs import from it —
`gtmConfigurator`, `gtmConfigWizard`, `chooseIndustry`, `offeringChooser`,
`gtmStory` (all `getPageLayout`), `gtmFaqPanel` (`getPageContent`),
`gtmSavedLinksBar` (`getIndustryProfiles`), and several of the above also take
`getSiteInfo` / `getOfferingTiles`.

### Q2 — Per-offering modelling

The mapping is **not** "one story + N pages + N sections per offering." It is:

```
framework 'gtm'                        (GtmPageContentController.FRAMEWORK_KEY)
  └── template  (industry-chooser | offerings-page | faq-bd | assistant)
        └── section
              └── field                → gtm::assistant::assistant::tone
<offering-key>                         (matches GTM_Offering__mdt.Offering_Key__c)
  └── template  (story | configurator | …)
        └── section  (NOT industry-scoped — no Industry_Key__c on the object)
              └── field  (industry-scoped via Industry_Key__c, override wins)
```

Any Contentful model has to carry (a) the four-part address as the lookup key,
not an entry Id, (b) the framework tier as a peer of an offering rather than a
special offering, (c) field-level-but-not-section-level industry override, and
(d) the resolution order in §3.3. `GTM_Offering__mdt.Offering_Key__c` remains
the authoritative offering registry either way — Contentful entries would have
to reconcile against it, and nothing about that CMDT changes.

### Q3 — Editing UX

Two options, both real, and the choice is **not mine** (§8.2). Costs:

- **Option A — `gtmContentManager` becomes a thin proxy into Contentful.**
  `gtmContentManager.js` is **1,063 lines** wired to **13 imperative Apex
  imports**: `getOfferings`, `getTemplateSummary`, `getAllContent`,
  `saveDrafts`, `publishPage`, `discardDrafts`, `savePresentation` (from
  `GtmPageContentController`) and `getEditorSections`, `saveSectionOrder`,
  `setSectionActive`, `createSection`, `deleteSection`, `restoreSection` (from
  `GtmPageSectionController`). Every one of those 13 has to be reimplemented
  against the Contentful Management API — which is a *different* API from the
  delivery API the guest path uses, with a different token, so this option
  needs two credentials, not one. Four of the 13 (`saveDrafts`, `publishPage`,
  `discardDrafts`, `setSectionActive`) encode semantics §3.4 marks as lost.
  Editors keep one tool; the team keeps all the surface area and adds a
  vendor.
- **Option B — editors leave Salesforce entirely.** Retire most of
  `gtmContentManager`, plus `gtmContentHome`, `gtmFieldEditor`, and the
  Content Manager app's navigation. Editors get a genuinely better authoring
  UI immediately. The cost is that the content and the offering registry
  (`GTM_Offering__mdt`) live in two systems that no longer share a create
  flow, and the "create an offering" journey — which today runs through
  `GtmPageContentController.createOffering` and seeds page content — has to be
  split across the boundary or rebuilt.

A fact that belongs in this decision: **there is no Jest spec for
`gtmContentManager`, `gtmContentHome` or `gtmStory`.** `npm test` runs 10
suites (`gtmAssessmentQuestionnaire`, `gtmConfigurator.readout`,
`gtmInstrumentAuthor`, `gtmPredicate`, `gtmReadoutAssist`, `gtmReadoutReview`,
`gtmReadoutDesign`, `gtmReadoutView`, `preview`, `gtmReadoutsOverview`) and
not one covers a content surface. So Option A's "reimplement 13 methods" has
no regression net at the LWC layer, and Option B's "delete a lot of it" has no
way to prove nothing was lost. That cuts weakly *for* Option B and strongly
against attempting either quickly.

### Q4 — Migration

Volumes, from `docs/backlog.md` D6 stage 3 (measured at rename time):
**206 `Page_Content` rows, 39 `Page_Section` rows, 16 `Page_Content_Version`
rows.** Small enough that the risk is entirely about correctness, not scale.

The in-repo precedent for a content move is
`scripts/data/migrate-page-content-to-gtm.apex` (alongside
`migrate-assistant-to-framework.apex` and
`migrate-saved-configuration-to-gtm.apex`) — a one-time, idempotent Apex
script run against the live org. That is the shape any export would take, and
the D6 record shows it working. It also shows what it cost: rewiring
`GtmPageContentController`, `GtmPageSectionController`,
`GtmPageContentReader`, `GtmAgentGetConfigState`, `GtmContentAddress`, their
test classes, one hardcoded LWC literal in `gtmConfigurator.js`, and three dev
scripts (`check-live-page-contract.mjs`, `check-page-order.mjs`,
`fix-field-order.mjs`) that would otherwise have started validating frozen
data.

Constraints any migration inherits:
- The `GTM_Page_Content_Version__c` master-detail (§3.1) — history moves with
  its parents or is destroyed.
- `Rich_Value__c` is rich text and `JSON_Value__c` is structured; Contentful's
  RichText is a document AST, not HTML, so this is a lossy transform in both
  directions unless rich content is stored as opaque long text — which forfeits
  most of the reason to use Contentful for it.
- It must be **export-first and reversible**, and it is a separate,
  human-gated phase, not part of a code deploy. See §8.3.

### Q5 — Caching and outage behaviour

Today: a guest hitting `GTM1`'s `/configurator` gets `getPageLayout` served
from SOQL inside the org. There is no external dependency, so there is no
outage mode beyond "the org is down," in which case the page was never served
anyway.

The only cache in the system today is the Lightning client-side cache implied
by `@AuraEnabled(cacheable=true)`, which all five reader entry points declare.
There is **no `force-app/main/default/cachePartitions/` directory and no
`Cache.Org` / `Cache.Session` / Platform Cache usage anywhere in
`force-app/`** — I checked. So a Contentful-backed read has nothing to fall
back to that already exists.

`cacheable=true` also constrains the obvious fix: a `cacheable=true` method
may not perform DML, so "fetch from Contentful and write through to a
projection object" cannot happen inside `getPageLayout` itself. A write-through
cache needs a separate non-cacheable path or an async job.

Concretely, with a naive delivery-API-backed reader, a cold-cache guest page
load becomes a synchronous outbound HTTP round trip on first paint, and
Contentful being slow or down means a prospect — a named prospect, on a
password-protected page a rep sent them — sees an error or an empty page. That
is a new failure mode on the highest-stakes surface in the product, traded for
an authoring convenience. If any migration ever proceeds, the read path must
be an in-org projection refreshed asynchronously (§6.2), so that a Contentful
outage degrades to *stale content*, never to *no content*. A design that
serves guests directly from Contentful should be rejected on this question
alone.

### Q6 — Cost and vendor approval

Not answerable by this agent, and not deferred quietly — see §8.1. What can be
stated: Contentful would be this repo's **first paid third-party runtime
dependency**. `remoteSiteSettings/` today contains Anthropic (an existing paid
dependency, but internal-facing — GUS is used by reps, not by prospects), three
brand-logo image hosts, and the two dead CMS entries from §2. Contentful would
be the first third party in the *prospect-facing* render path. Beyond licence
cost, that pulls in a third-party data-processing review, because the content
in question is shown to named prospects on client engagements. Costs are also
asymmetric: §2 establishes that leaving a content home is more expensive than
entering it, and that cost lands after the licence is already sunk.

---

## 5. The GUS coupling — the issue's exclusion is wrong

The issue states GUS "is unrelated to page/story content" and puts it out of
scope. At the code level that is false in three places, and one of them
reaches a surface the issue also declares out of scope.

- **`GtmAgentTone.cls`** — `clause()` calls
  `GtmPageContentReader.getPageContent(FRAMEWORK_KEY, TEMPLATE_TYPE, null)`,
  i.e. `getPageContent('gtm', 'assistant', null)`, and uses the returned value
  as a key into a hardcoded `TONE_CLAUSES` map. GUS's persona is page content,
  living at `gtm::assistant::assistant::*` (where `docs/backlog.md` D8 put it).
  Note the safety design: the content row only ever *selects* a key; the prompt
  text itself is compiled into the map and never comes from content. Any
  Contentful design must preserve that — content selects, it never supplies
  prompt text.
- **`GtmAgentGetConfigState.cls`** — a live GUS **tool implementation** — runs
  a direct SOQL query against `GTM_Page_Content__c` for the framework's
  `industry-%` rows under `Template_Type__c = 'industry-chooser'`, to build
  `availableIndustries`.
- **`GtmHomeSnapshotController.cls`** queries `GTM_Page_Section__c`.

### 5.1 Scope correction: the readout surface is coupled too

`GtmReadoutAgentSurface`'s `systemPrompt()` ends with
`'TONE: ' + GtmAgentTone.clause();`. Since `GtmAgentTone.clause()` reads page
content, **the readout-drafting surface — which the issue declares out of
scope — is coupled to page content via tone.** `GtmAgentProxyController`'s own
`configSystemPrompt()` ends the same way. This is a documentation correction
only; no code change is proposed or made. It means the blast radius of a
storage change is "every GUS surface," not "the configurator surface."

It remains true that the **assessment instrument** (`migration-accelerator/`
YAML and the `GTM_Assessment_*` CMDT pipeline) is genuinely unaffected. The
only false premise is "GUS never touches page content."

### 5.2 The callout collision — precisely, and without overstating it

`GtmAgentToolSurface.cls` states the contract in source, at the top of the
interface file:

> `executeTool contract: NEVER throw, NEVER do DML, NEVER do a callout.`

There are **two distinct paths** by which a Contentful backend would collide
with that, and they are not equally bad.

**Path A — inside a tool.** `GtmAgentGetConfigState.buildOutput` SOQLs
`GTM_Page_Content__c`, and is reached from `executeTool`. Behind Contentful
that read becomes an HTTP callout **inside a tool implementation**, which the
written contract forbids in as many words. This is a written-contract
violation, and it is the one the issue would have anticipated.

**Path B — inside the system prompt. Worse, and not covered by the contract's
letter.** `GtmAgentProxyController.configSystemPrompt()` ends with
`GtmAgentTone.clause()`. `ConfigSurface.systemPrompt()` returns
`configSystemPrompt()`. And `systemPrompt()` is evaluated **inside
`callClaude`**, in the request-body map — not once at the start of the
conversation:

```
'system'     => surface.systemPrompt(),
```

`callClaude` is invoked from inside `while (rounds < MAX_TOOL_ROUNDS)`, where
`MAX_TOOL_ROUNDS = 5`. So the page-content read executes **up to five times
per conversation turn**, interleaved with five Anthropic callouts, on every
surface (`ConfigSurface` and `GtmReadoutAgentSurface` alike). Today that is
five cheap SOQL queries. Behind Contentful it is five extra outbound HTTP
round trips per turn, and no tool-contract audit would catch it, because
`systemPrompt()` is not `executeTool()`.

**Why this is actually a problem — the accurate version:**

1. **The written contract.** Path A violates it explicitly. That matters
   independently of whether the platform enforces it, because the contract is
   how this codebase keeps one loop and one callout path coherent
   (`AGENTS.md` §1).
2. **Per-transaction callout budget.** Salesforce caps callouts per
   transaction. A five-round loop already spends five; adding up to five more
   halves the remaining headroom for no functional gain.
3. **Cumulative callout timeout.** The 120-second per-transaction cumulative
   callout limit is shared across *all* callouts in the transaction. Anthropic
   responses are the slow ones; every Contentful round trip is subtracted from
   the same budget, making a long agent turn more likely to die on a limit.
4. **Latency, multiplied by five.** Even a fast Contentful read, five times per
   turn, is user-visible added latency in a chat UI.

**What is NOT true, and should not be claimed:** Apex does not hard-block a
second callout in a transaction. The hard platform block is **DML before a
callout** (`You have uncommitted work pending`), which is exactly why
`GtmAgentToolSurface`'s contract forbids DML in tools and routes writes
through `accumulatedChanges` for client-side application afterwards. A
Contentful read inside the loop would most likely *work*; it would be a
contract violation and a limits/latency problem, not an immediate runtime
error. Overstating it as "impossible" would make the argument easy to dismiss.

**Both resolutions remain valid** if a migration ever proceeds:

- **(a) Pre-`runLoop()` hydration.** Read tone and industry keys once, before
  the loop starts, and pass them into the surface (e.g. via the surface's
  constructor, the way `ConfigSurface(configId)` already takes state). One
  read per turn instead of up to five, and no callout inside `executeTool`.
  This is the smaller change and it is worth doing on its own merits even
  under the don't-migrate verdict — see §7.
- **(b) An in-org projection read by SOQL.** Tools and `systemPrompt()` keep
  querying local rows; a separate async job syncs them from Contentful. This
  is the same mechanism §4-Q5 requires for the guest path, so the two problems
  have one answer.

Note that raising `MAX_TOOL_ROUNDS` is **not** an available workaround for any
of this; `AGENTS.md` §1 fixes the cap at 5.

---

## 6. The conditional plan (only if a human overturns §1)

Recorded so the recommendation is falsifiable, not as a proposal.

1. **Model.** One Contentful content type per *template*, with entries keyed
   by `Content_Address__c` as a unique external key, `offeringKey` as a
   validated field reconciled against `GTM_Offering__mdt.Offering_Key__c`, and
   `industryKey` optional and present only on field-level entries (§3.3:
   sections are not industry-scoped). Per-field entries — not per-page — are
   required if `Draft_Value__c`'s per-field draft semantics are to survive at
   all; accept the entry-count explosion or accept the loss, explicitly.
2. **Read path.** Contentful is **never** on the guest's synchronous path.
   Keep `GtmPageContentReader`'s signatures and `cacheable=true` exactly as
   they are and have them read an in-org projection, refreshed by a scheduled
   or webhook-triggered async job. Outage degrades to stale, never to blank
   (§4-Q5). This also resolves §5.2 for GUS with the same mechanism.
3. **Credentials.** A Named Credential per API (delivery, and management if
   Option A). Not a Public custom setting. Adding the first
   `namedCredentials/` metadata to this repo is a prerequisite task with its
   own deploy risk, not a footnote.
4. **Cleanup first.** Remove the §2 debris *before* adding anything, so the
   tree has one answer to "where does content live" at every moment.
5. **Migration.** Export-first, idempotent, reversible, in the shape of
   `scripts/data/migrate-page-content-to-gtm.apex`, run as a separate
   human-approved phase after a full data export — never inside a code deploy
   (§8.3).
6. **Permission sets.** Per `CLAUDE.md` §6 and ADR-0002, any new field (a
   `Contentful_Entry_Id__c` correlation field, a projection object) is
   invisible until mapped across all five sets in
   `force-app/main/default/permissionsets/` — `GTM_Config_Manager`,
   `GTM_Config_View_All`, `GTM_Assessment_Guest`, `GTM_Story_Guest`,
   `GTM_Platform_Visibility` — in the *same commit* as the field. Standing
   caveat: guest sets grant **class access only**; they must not receive
   object or field permissions on content read through Apex.

---

## 7. Consequences of deciding not to migrate

The three motivating pains are real and are not dismissed. Each has an in-org
answer already visible in this repo:

- **Versioning.** `GTM_Page_Content_Version__c` is written on every publish
  and **read by nothing**. Building a "history / restore" panel in
  `gtmContentManager` is a UI task against data that already exists, with no
  vendor, no token, and no migration.
- **Editing ergonomics.** `docs/backlog.md` B6 ("page names should be editable
  by the Content/BA role") is already scoped as needing a content-model
  decision, and B1 (the CMS-editable FAQ widget) is the pattern it should
  follow. That is the concrete next increment.
- **Preview.** `gtmPagePreview` exists; the missing piece is a
  draft-rendering mode, which is reachable because `Draft_Value__c` already
  sits alongside the live value on the same row — a property §3.4 shows
  Contentful would *take away*.

Costs and risks accepted by this verdict:

- Editors keep a Salesforce-shaped authoring UI, which is worse than a
  dedicated CMS. That is a real, ongoing cost, not a neutral outcome.
- The content LWCs stay untested at the Jest layer (§4-Q3). Not caused by this
  decision, but not fixed by it either, and it should be tracked.
- The §2 debris removal is now the only content-related cleanup with no
  blocker at all; it should be raised as its own backlog item regardless.
- **Recommended regardless of the verdict:** apply §5.2(a) — hoist
  `GtmAgentTone.clause()` out of `systemPrompt()` and hydrate it once before
  `runLoop()`. Today it costs four redundant SOQL queries per conversation
  turn per surface. That is cheap enough to have gone unnoticed, and it is
  exactly the coupling that would become expensive under any future storage
  change. **Not done in this pass** — this pass is documentation only.

**Re-open trigger.** This verdict should be revisited if any of the following
becomes true: content editors materially outnumber the current small group;
content needs to be consumed by a surface outside this org; or the guest
render path is redesigned such that a projection/cache layer exists anyway for
other reasons — in which case §6.2's main cost is already paid.

---

## 8. Human gates — unresolved, owner-attributed

None of these is decided by this document, and §1's verdict does not resolve
any of them. They are recorded so that nobody mistakes an agent's silence for
an answer.

### 8.1 Procurement / vendor approval — **owner: budget owner + whoever runs third-party data-processing review. UNRESOLVED.**

Contentful is a new paid SaaS dependency and would be the first third party in
the prospect-facing render path (§4-Q6). No agent in this chain can approve
procurement, confirm a budget owner, or clear a data-processing review for
content shown to named prospects on client engagements. Everything in §6 is
conditional on this and is void without it.

### 8.2 The editing-UX fork — **owner: product owner. UNRESOLVED.**

Option A (proxy) versus Option B (editors leave Salesforce), §4-Q3. There is
no technically correct answer; it is a product decision about where content
editors work. §4-Q3 states both costs against the real 1,063-line, 13-Apex-import
surface and stops there. Under §1's verdict the fork is **deferred, not
answered** — if §8.1 ever clears, this still has to be decided before any code
is written.

### 8.3 `gtm-dev` is production and the content is live — **owner: Don (data owner), with the deploy owner. UNRESOLVED.**

`CLAUDE.md` §1: `gtm-dev` is treated as production and there is no staging
org. The content in question is live, prospect-facing copy. `docs/backlog.md`
records two standing items that make this concrete:

- **R1** — the **72 migrated industry rows** on the framework's Industry
  Chooser are "moved but never reviewed," with the warning that "everything
  industry-related now reads from these. If the migration mangled any copy,
  every configurator inherits it." A second migration would layer on top of an
  unverified first one.
- **R2** — content already destroyed by an earlier automated pass
  (BOA / SC-0012 lost its payload during a backfill; two of eight were
  recovered from pasted URLs, one was not, no field history). The backlog
  labels it "Data Claude destroyed. Not recoverable without you."

Therefore: any export/import is a **destructive operation on live
prospect-facing copy with a documented prior incident**. If it ever happens it
must be a separate, human-gated, export-first, reversible phase — never
bundled into a code deploy. **No export, import, seed script or `sf` write was
run in this pass.**
