# Task Scope — Issue #39: Migration Accelerator Design Overhaul (PS Branding)

**Role:** Business Analyst
**Issue:** [#39](https://github.com/iwintrose/gtm-offerings/issues/39) — "Migration Accelerator: overhaul story, offering, industry-variant, and configurator design (PS branding)"
**Related:** [#35](https://github.com/iwintrose/gtm-offerings/issues/35) — Story has zero real CMS content rows (accounted for below)
**Deliverable type:** Scoping only — no code/config changes. For owner review before Architect stage.

---

## Cross-Cutting Summary

Migration Accelerator is the only fully-built offering in this repo, and every one of its four public-facing surfaces shows the same pattern: **the rendering engines are more mature than the content behind them.** Story and Configurator are both driven by a generic, reusable CMS layout engine (`GTM_Page_Section__c` / `GTM_Page_Content__c`, read via `GtmPageContentReader.getPageLayout`), which is genuinely good infrastructure — but for Migration Accelerator specifically, that engine is fed almost entirely by hardcoded JS fallback objects rather than real content rows. There is no PS brand style guide anywhere in the repo (confirmed — see Configurator section); brand identity today is a handful of ad-hoc rules embedded in component CSS/tests (e.g. the two-tone lowercase "publicis"/"sapient" wordmark asserted in `brand.test.js`).

The four surfaces are not siloed — they overlap in ways a redesign has to respect:
- Story and Configurator share the **same layout engine and the same section-variant mechanism** for industries (`GTM_Page_Section__c`/`GTM_Page_Content__c`), but Configurator *also* runs a second, older, unrelated `getIndustryProfiles` flat industry-profile mechanism that Story does not use. A redesign that "adds an industry to the story" and expects it to show up in the configurator (or vice versa) will not work without reconciling these two mechanisms — see the Industry section below.
- The Offering metadata record (`GTM_Offering__mdt`) is thin by design (7 fields, positioning/targets only) and is not where "positioning" content actually lives — that's a documentation gap worth closing as part of this overhaul, not a schema problem.
- The GUS/Agentforce configurator bot is mid-migration (Einstein Copilot Studio path superseded by Agent Script) and its instructions already assume the configurator surface it's narrating; bot-instruction copy should be treated as a Configurator sub-deliverable, not a separate surface.

**Recommended sequencing for the eventual build:** Story base content (closing #35) must land before Story industry variants are touched (they overlay on top of it), and the Industry section's proposed reconciliation should be decided before either Story or Configurator variant copy is rewritten, since it changes which object(s) that copy is authored into.

---

## 1. Story (`gtmStory` LWC)

### Current State

- **Files:** `force-app/main/default/lwc/gtmStory/gtmStory.js` (778 lines), `.html` (1116 lines), content model `data/seed/migration-accelerator.story.sections.json` / `.story.records.json`.
- **Content pipeline:** `GtmPageContentReader.getPageLayout({offeringKey, templateType: 'story', industryKey: null})` returns `{content, sections, fieldMeta}`. If it returns nothing (or errors), the page falls back to hardcoded JS.
- **The #35 finding, confirmed:** Zero `GTM_Page_Section__c`/`GTM_Page_Content__c` rows exist for `migration-accelerator`'s `story` template. Every section renders from `DEFAULTS` (gtmStory.js:16–102) and `SECTION_FALLBACKS` (gtmStory.js:108–172), with `DEFAULT_SECTIONS` (gtmStory.js:176–188) supplying the fallback structure/order. The component's own comment says the plainest part: this is meant to be "the floor" — "the page still renders if the org has no content rows at all" — but for Migration Accelerator it has never been anything but the floor.
- **11 sections today, in order:** `header` (page-header) → `hero` → `problem` (lede-chips) → `mechanism` (route-proof) → `pivot` (statement) → `capabilities` (card-grid) → `clientProfile` (stat) → `bd` (use-pitch, "For Business Development and Industry Leaders") → `faq` → `closing` → `footer`.
- **What's data-driven vs hardcoded today:** The *rendering* is fully data-driven (layout type, field keys, presentation, ordering all come from `GTM_Page_Section__c`/`GTM_Page_Content__c` when present) — the *content* is 100% hardcoded JS. This is an important distinction: no LWC/Apex rework is required to put real content in; only content authoring is.
- **Content model shape:** flat `section::field` string map (`_cms`), JSON-encoded lists/objects per field, five field-type buckets (`text`, `rich`, `json`, `icontext`, `enum`) declared per layout in `c/gtmPageLayouts`. An "extras" mechanism renders any undeclared field generically, so the schema is editor-extensible without code changes.
- **The `bd` section is presently addressed to "Business Development and Industry Leaders"** but its content (`bdUseCases`: Presales / Delivery / "The pitch") is generic sales-enablement copy, not industry-specific — despite living right next to the industry-variant-bearing `clientProfile`/`capabilities`/`problem` sections.
- **Existing brand hooks:** `ps-scope`, `ps-band`, `ps-display`, `ps-grid`, `ps-eyebrow` CSS class families throughout — a PS visual system exists at the CSS layer, just undocumented centrally (see Configurator section — no style guide file exists anywhere in-repo).

### Proposed Design

Two work-streams, sequenced:

**A. Close #35 first, but don't just port the copy verbatim.** Author real `GTM_Page_Section__c`/`GTM_Page_Content__c` rows for all 11 base sections using the field-key shape #35 already specifies (`lede/chips/close`, `eyebrow/head/cards/bonusCard`, `statBig/statDesc/note`, `items`, etc.) so the already-written industry-variant seed script's upserts land correctly. This is necessary infrastructure regardless of what the copy says — take it as a given, not an open question.

**B. Restructure the narrative, not just re-skin it.** The current story is written as an internal positioning memo that happens to be public ("Internal positioning · GTM buy-in" is literally the hero eyebrow today) — it reads like a pitch to the practice, not to a prospect or a BD rep about to walk into a room. Proposed section structure, in order:

1. **Hero** — keep the "decade nobody documented, read in an afternoon" hook (it's genuinely strong, evidence-forward, on-brand), but drop the "Internal positioning" eyebrow; replace with a PS-branded offering eyebrow (e.g. "Publicis Sapient · Marketing Automation Migration").
2. **Problem** (unchanged position) — stays as the entry point; industry variants already cover this well.
3. **Mechanism** (`route-proof`) — keep the live proof panel (objects/deps/health gauge); it's the single best piece of evidence-forward interactive content on the page and should anchor the whole redesign's tone.
4. **NEW: Evidence/Trust section** — a section this page currently lacks entirely: named client outcomes, a health-score sample report, or a before/after object count from a real (or anonymized) engagement. Nothing on the page today gives a prospect third-party proof; it's all first-person claims. This is the single highest-leverage addition for BD credibility.
5. **Capabilities** (unchanged) — keep card-grid; industry variants already work well here.
6. **Client Profile** (unchanged) — keep; this is the qualification section ("who this fits") and is doing real work today.
7. **RENAMED: "For BD"** → **"How to run this"** — collapse the vague "Presales / Delivery / The pitch" three-card structure into a single, sharper BD playbook: what to bring to a discovery call, what the assessment proves in the room, and the exact ask (book the live assessment). Make this section itself a lead-gen surface with a direct CTA into the Configurator, not just prose about the pitch.
8. **FAQ** (unchanged, strong as-is — objection-handling content already does real work).
9. **Closing** — replace "The next step is putting a name and an industry behind it" (reads as an internal note-to-self, not a prospect-facing close) with a direct CTA to the Configurator, matching the "How to run this" section's ask.

**Tradeoff:** Adding a new Evidence/Trust section means either real client data (a brand/confidentiality risk — needs a named approved reference or anonymization) or a synthetic "sample report" framed explicitly as illustrative. Recommend the synthetic-sample path now, with a fast-follow to swap in a real reference once one is cleared — don't block the redesign on legal/reference approval.

### Open Question
Is there an approved reference client (or anonymized dataset) PS can cite for an Evidence/Trust section, or should launch content be explicitly illustrative/synthetic? This is a business decision, not a content-writing one.

---

## 2. Offering (`GTM_Offering__mdt` / `GTM_Offering.Migration_Accelerator.md-meta.xml`)

### Current State

`GTM_Offering__mdt` is a deliberately thin 7-field object; Migration Accelerator's record populates 6 of them:

| Field | Value | Role |
|---|---|---|
| `Offering_Key__c` | `migration-accelerator` | Slug used throughout the codebase as the join key |
| `Label__c` | `Migration Accelerator` | Display label |
| `Monthly_Target__c` | `20000` | Quota/target tracking |
| `Annual_Target__c` | `250000` | Default Opportunity Amount fallback |
| `CMS_Channel_Id__c` | *blank* | **Vestigial** — points to a retired Salesforce-CMS story path; the class that read it has been deleted. Explicitly flagged in-file as dead, pending removal (separate cleanup, not this issue). |
| `Site_Path__c` | `gtmaccelerator/story` | Experience Cloud URL prefix |
| `Has_Conduit__c` | `true` | Enables the migration-planning "Conduit" tab in the readout workspace |

This object has no positioning, targets-segment, or narrative-structure fields at all — "positioning/targets/structure" as described in the issue's ask doesn't actually live on this metadata type; positioning lives in Story content, targets-segment lives in `clientProfile`'s stat copy, structure lives in the section-order arrays. `GTM_Offering__mdt` is closer to a routing/config record than a content record.

### Proposed Design

Don't add "positioning" fields to `GTM_Offering__mdt` — that would duplicate the Story/Configurator CMS content model and create two sources of truth for the same claims. Instead:

1. **Remove `CMS_Channel_Id__c`** as part of this overhaul (it's already flagged dead; this is a good moment to fold that into the broader cleanup rather than leaving it for yet another pass — flag to Architect, not a BA decision to force).
2. **Add one field:** `Practice__c` or `Segment__c` (short picklist/text) — currently there's no metadata-level tag distinguishing which PS practice/GTM segment owns an offering, which matters the moment a second offering exists and someone wants to filter/report by practice. Low-risk, additive.
3. Treat `GTM_Offering__mdt` as staying thin by design — the actual "positioning/targets/structure" overhaul the issue asks for happens in Story/Configurator content, not here. State this explicitly in the Architect handoff so the build doesn't get redirected into speculative metadata schema work.

**Tradeoff:** Keeping this object thin is right architecturally (single source of truth stays in CMS content) but means this surface's "massive overhaul" is really "a light touch plus documentation," which may read as underwhelming next to the other three surfaces — worth flagging to the owner so expectations are set correctly before Architect scopes it as equal-sized work to the other three.

---

## 3. Industry (variant overlay system)

### Current State

**Two separate, non-interoperating industry mechanisms exist for Migration Accelerator today** — this is the most important current-state fact for this surface:

**Mechanism 1 — Story's section-variant model** (`docs/architecture/industry-variants-core.md`, seeded by `scripts/data/seed-migration-accelerator-industry-variants.apex`, 2696 lines, staging-only): a variant is a first-class `GTM_Page_Section__c` row, not a flag or per-field override. `Section_Key__c` = `<baseKey>--<industrySlug>` (e.g. `problem--consumer-products`), resolved server-side by `GtmPageContentReader.variantSectionsByBase()` as a **whole-section swap** when `Status__c='Published'` and `Active__c=true`. Only 4 of Story's 11 sections get variants: `problem`, `capabilities`, `clientProfile`, `faq` — hero, mechanism, pivot, bd, closing, header, footer stay generic by explicit design choice (`TASK_SCOPE.md` for that prior task). 9 industries are seeded: Consumer Products, Energy & Commodities, Financial Services, Health, Public Sector, Retail, Telecom/Media/Tech, Transportation & Mobility, Travel & Hospitality — 36 rows total (9 × 4).

**Mechanism 2 — Configurator's flat industry-profile model** (`getIndustryProfiles`, inside `gtmConfigurator.js`): a completely separate, older, per-configurator-page set of industry rows (problem/useCase/solution/proofLine/whyLine/uniquePoints/demoRoot/demoDeps per industry) that has no relationship to the `GTM_Page_Section__c` variant rows above. The component's own comment states the design intent plainly: "one section per industry on this configurator page... the framework owns only the list of industries, not what we say to them" — i.e. this was built independently, on the assumption the configurator's industry needs were different in shape from the story's.

Both mechanisms key off the same 9 industry slugs (must match `seed-industry-chooser-industries.apex`), so the *industry list* is consistent — but the *content* an editor writes for "Financial Services" on the Story page and the "Financial Services" content shown in the Configurator are two unrelated data structures maintained in two unrelated places, with no shared authoring surface and no way for a content editor to know that changing one doesn't change the other.

### Proposed Design

1. **Reconcile the two mechanisms onto Mechanism 1's section-variant model.** It's the newer, better-documented, whole-section-swap pattern, and it's already what Story uses. Migrate Configurator's `getIndustryProfiles` flat rows into `GTM_Page_Section__c`/`GTM_Page_Content__c` variant rows on the `configurator` template, using the same `Section_Key__c = <baseKey>--<industrySlug>` addressing. This turns "industry content" into one authoring surface across both Story and Configurator instead of two, and it's the single highest-leverage structural change in this whole overhaul — it directly enables a content editor to maintain one industry story instead of two disconnected ones.
2. **Expand variant coverage on Story's side to match the new Evidence/Trust section (§1) and the renamed "How to run this" section**, if those are approved — an industry-specific proof point/evidence bullet is exactly the kind of content this mechanism is built for.
3. **On the Configurator side**, extend variant coverage to the `challenge` and `why` chapters, which the current code already hints support industry overrides ("an industry variant can replace the lede," "industry can override heading") but which aren't populated with real content behind the flat mechanism.

**Tradeoff:** Migrating mechanism 2 into mechanism 1's shape is a schema/data migration, not just a content-authoring task — it touches `GtmPageContentReader` call sites in `gtmConfigurator.js` and is Architect/Developer work, not BA scope. Flagging it here because it changes how much of "the Configurator's industry content" is actually new authoring vs. structural migration, which affects sizing.

### Open Question
Should industry coverage expand beyond the current 9, or is 9 the fixed set for this overhaul? (Affects seed-script sizing and whether the reconciliation in proposal #1 should be designed to make adding an industry trivial vs. just correct for the current 9.)

---

## 4. Configurator (`gtmConfigurator` LWC + Experience Cloud wiring)

### Current State

- **Files:** `gtmConfigurator.js` (2177 lines), `.html` (723 lines), `.css` (1539 lines), 8 Jest test files, `gtmConfiguratorCopy/gtmConfiguratorCopy.js` (188 lines — a copy-data module imported by the main component, not a duplicate LWC), `experiences/GTM1/routes/configurator.json`, `experiences/GTM1/views/configurator.json`, `bots/GTM_Configurator_Assistant/`.
- **This is the largest and most complex of the four surfaces** — it's not just a content page, it bundles: chapter rendering, a password gate, a preview-token bypass, an assessment-submission state machine, and a readout (Draft/Approved/Published) state machine, all in one component.
- **9 chapters, fixed order** (`CHAPTERS` in `gtmConfiguratorCopy.js`): `cover` (has live `{client}`/`{source}`/`{industry}` token substitution) → `partner` → `challenge` → `approach` → `proof` (the live counting/gauge demo panel — the same mechanism as Story's `route-proof`) → `deliverables` → `engagement` (4-phase model) → `why` ("Why Publicis Sapient") → `closing`.
- **Content pipeline:** same `GtmPageContentReader.getPageLayout` pattern as Story, plus a second independent call for the `assistant` (GUS persona) template — content today is fallback-driven the same way Story's is, via `CHAPTER_DEFAULTS`.
- **Offering resolution is deliberately conservative:** 3-tier priority (saved-record's linked offering → URL param → Experience Builder default), and if none resolves, the page shows *only* an "unconfigured" notice — it will never silently default to Migration Accelerator content. This is a real architectural guardrail (tested in `offeringRouting.test.js`, referenced as backlog item B11) that any redesign must preserve, since it's what makes this component safe to reuse for a second offering.
- **Brand identity today:** no external style guide; the only asserted brand rule is `brand.test.js`'s check that the top wordmark renders as two-tone lowercase "publicis"/"sapient" spans, plus Inter font loading. Brand hex handling in the bot instructions refers to the *prospect's* brand color lookup, not PS's own.
- **Bot status:** `GTM_Configurator_Assistant`'s `AGENT_INSTRUCTIONS.md` is explicitly flagged **superseded** — Einstein Copilot Studio was retired on gtm-staging in favor of Agent Script in Agentforce Builder; the existing instructions are being reused as a starting draft, not a live spec.
- **Route/view wiring:** `urlPrefix: "configurator"`, mounts via `forceCommunity:section`; notably `offeringKey`/`accentColor` are *not* set in the Experience Builder view JSON, so the page always relies on runtime resolution, never a page-level default — consistent with the B11 guardrail above.

### Proposed Design

1. **Restructure the 9 chapters into a narrower, sharper flow** — 9 sequential full chapters is a lot for a presentation a rep drives live in a client room. Proposed consolidation to 6:
   - `cover` (unchanged — token substitution is good)
   - `challenge` (merge `partner`+`challenge`: lead with the problem, not "how we work with you," which is generic agency boilerplate better suited to a footer credential than an opening beat)
   - `proof` (unchanged — this is the component's best asset, keep it central)
   - `approach` + `engagement` merged into one: "how we get there," combining the 3-card approach with the 4-phase model into a single visual timeline instead of two separate card layouts saying similar things
   - `deliverables` (unchanged — concrete and useful)
   - `why` + `closing` merged: end on the differentiation argument immediately followed by the ask, rather than a "why us" chapter and then a separate closing chapter that repeats momentum-loss risk between them
2. **Close the industry-content gap described in §3** — today `challenge`/`why` can technically be overridden per-industry but aren't populated; once the Story/Configurator variant mechanisms are reconciled, author real industry copy for these two chapters as part of this surface's overhaul, not as a follow-on.
3. **Formalize the brand wordmark/accent-color rule** the tests already assert into an actual short PS-brand reference doc under `docs/architecture/` (e.g. `docs/architecture/ps-brand-basics.md`) — wordmark treatment, accent-color contrast rule, font stack — so it's documented once instead of re-derived from test assertions. This is small and cheap and directly closes the "no style guide exists" gap found in this research for all four surfaces, not just Configurator.
4. **Leave the state machines (password gate, assessment submission, readout) structurally alone** — they're working infrastructure unrelated to "design," and the B11 offering-resolution guardrail must not regress.

**Tradeoff:** Consolidating 9 chapters to 6 is a content and possibly template-schema change (fewer `GTM_Page_Section__c` rows, different `layoutType` combinations) — cheaper than it sounds since the underlying engine already supports arbitrary section counts/order, but it does mean re-authoring chapter copy rather than just re-skinning existing chapters, consistent with the issue's explicit "not a tack-on" instruction.

### Open Questions
- Is there PS-approved brand asset availability (logo files, exact hex values, approved font licensing) to formalize into the proposed brand reference doc, or does this overhaul have to proceed with the wordmark/color rules as currently inferred from code?
- Should the Agentforce bot instructions be rewritten now to match the new chapter structure, or held until the Agent Script migration is further along (it's already mid-migration per the "superseded" flag)?
