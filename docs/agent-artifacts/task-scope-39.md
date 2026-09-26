# Task Scope — Issue #39: Migration Accelerator Design Overhaul (PS Branding)

**Role:** Business Analyst
**Issue:** [#39](https://github.com/iwintrose/gtm-offerings/issues/39) — "Migration Accelerator: overhaul story, offering, industry-variant, and configurator design (PS branding)"
**Related:** [#35](https://github.com/iwintrose/gtm-offerings/issues/35) — Story has zero real CMS content rows (accounted for below)
**Deliverable type:** Scoping only — no code/config changes. For owner review before Architect stage.
**Revision note:** Updated per owner feedback to make the Story (internal, reps/BD-facing) vs. Configurator (client-facing) audience split the explicit organizing principle for both sections — see Cross-Cutting Summary and §1/§4 below.

---

## Cross-Cutting Summary

Migration Accelerator is the only fully-built offering in this repo, and every one of its four public-facing surfaces shows the same pattern: **the rendering engines are more mature than the content behind them.** Story and Configurator are both driven by a generic, reusable CMS layout engine (`GTM_Page_Section__c` / `GTM_Page_Content__c`, read via `GtmPageContentReader.getPageLayout`), which is genuinely good infrastructure — but for Migration Accelerator specifically, that engine is fed almost entirely by hardcoded JS fallback objects rather than real content rows. There is no PS brand style guide anywhere in the repo (confirmed — see Configurator section); brand identity today is a handful of ad-hoc rules embedded in component CSS/tests (e.g. the two-tone lowercase "publicis"/"sapient" wordmark asserted in `brand.test.js`).

**Audience is the organizing principle for this overhaul, most consequentially for Story and Configurator, and every proposal below is filtered through it:**
- **Story is internal** — it's reps/BD prep material, not something a prospect sees. Because of that, it can be candid, name real clients by name (e.g. Medtronic, the one client that has actually used Migration Accelerator specifically), surface built-vs-in-flight status honestly, flag gotchas/watch-outs, and run longer than a polished pitch would. It can also draw on the firm's broader migration track record (many migrations done historically, beyond just Migration Accelerator) for proof content — legitimate, not overreaching, as long as claims about what Migration Accelerator itself has delivered stay scoped to Medtronic.
- **Configurator is client-facing** — a prospect or client sees this directly. It must stay polished and rooted only in what's confirmed/deliverable — no fibbing, and no attributing the firm's general migration history to Migration Accelerator by name unless it's actually Migration Accelerator work. It can still gesture at forward-looking possibility ("here's where this is headed," blue-sky but not fabricated) because showing a client what's possible is part of what closes deals — this is a deliberate stylistic contrast with Story's candor, not the same tone dialed down.
- Internal, self-aware positioning language about how the firm operates (e.g. "PS is an engineering firm, we spend our time figuring it out") belongs only on Story, if anywhere — it must never appear on Configurator.

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

**Story is internal — reps/BD prep, not a prospect-facing page.** That changes what "restructuring the narrative" means: the goal isn't to polish this into a pitch deck, it's to make it the sharpest possible internal reference a rep opens before walking into a room. The existing "Internal positioning · GTM buy-in" hero eyebrow was actually the right instinct for this surface — the earlier draft's plan to strip it out and PS-brand the eyebrow was based on treating Story as prospect-facing, which the owner corrected. Keep the internal framing; just make the content underneath it earn its keep.

Two work-streams, sequenced:

**A. Close #35 first, but don't just port the copy verbatim.** Author real `GTM_Page_Section__c`/`GTM_Page_Content__c` rows for all 11 base sections using the field-key shape #35 already specifies (`lede/chips/close`, `eyebrow/head/cards/bonusCard`, `statBig/statDesc/note`, `items`, etc.) so the already-written industry-variant seed script's upserts land correctly. This is necessary infrastructure regardless of what the copy says — take it as a given, not an open question.

**B. Restructure around the internal-use case, leaning into candor rather than away from it.** Proposed section structure, in order:

1. **Hero** — keep the internal-positioning eyebrow (this page is explicitly for reps, not prospects); keep the "decade nobody documented, read in an afternoon" hook, it's genuinely strong and evidence-forward.
2. **Problem** (unchanged position) — stays as the entry point; industry variants already cover this well.
3. **Mechanism** (`route-proof`) — keep the live proof panel (objects/deps/health gauge); best piece of interactive content on the page and should anchor the redesign's tone.
4. **NEW: Positioning & proof** — how to position the offering in a room, plus proof content. Because this is internal, it can be candid and name Medtronic directly as the one client that has actually used Migration Accelerator, and it can also draw on the firm's broader migration-delivery track record (many migrations done historically, not just through this offering) as supporting evidence — clearly labeled which claims are "Migration Accelerator has done this" (Medtronic) vs. "the firm's migration practice has done this" (broader history). No synthetic/illustrative data needed here; real, named material is appropriate for an internal audience.
5. **NEW: Built vs. in-flight** — a straight status view of what's actually shipped in the product today versus what's still being built, so a rep never oversells something that isn't live yet. This is new content this page doesn't have anywhere today.
6. **Capabilities** (unchanged) — keep card-grid; industry variants already work well here.
7. **Client Profile** (unchanged) — keep; this is the qualification section ("who this fits") and is doing real work today.
8. **RENAMED: "For BD"** → **"How to run this"** — collapse the vague "Presales / Delivery / The pitch" three-card structure into a sharper BD playbook: what to bring to a discovery call, what the assessment proves in the room, and the exact ask (book the live assessment via Configurator).
9. **NEW: Gotchas / watch-outs** — candid, internal-only content flagging known limitations, edge cases, or things that have tripped up past engagements — the kind of thing that's actively wrong to put in front of a client but exactly what a rep needs before a call.
10. **NEW: Sample documents & collateral** — a section where reps can find or pull sample deliverables (e.g. a sample health-score report, assessment output, or engagement artifact) to reference or attach when prepping a pitch. This didn't exist in the original scoping pass and directly serves the "internal prep" purpose of the page.
11. **FAQ** (unchanged, strong as-is — objection-handling content already does real work).
12. **Closing** — replace "The next step is putting a name and an industry behind it" with a direct internal call-to-action: send the rep into the Configurator to build the client-facing version for their prospect.

**Tradeoff:** Naming Medtronic and drawing on broader migration history makes Story materially more useful to reps, but it also means Story now carries real client/engagement detail that must never leak into Configurator's client-facing content verbatim — anyone doing content authoring or the eventual industry-variant reconciliation (§3) needs to keep the two surfaces' source content clearly separated, not just differently worded.

### Open Question
For the Positioning & Proof and Sample Documents sections: is there an existing internal repository (Box/Drive/wherever collateral currently lives) this page should link out to, or does content need to be authored fresh into the CMS rows? Affects whether this is a content-authoring task or a linking/reference task.

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
2. **Expand variant coverage on Story's side to match the new Positioning & Proof and "How to run this" sections (§1)**, if approved — an industry-specific proof point or positioning note is exactly the kind of content this mechanism is built for. Since Story is internal, these variants can carry the same candid, named-client texture as the base content.
3. **On the Configurator side**, extend variant coverage to the `challenge` and `why` chapters, which the current code already hints support industry overrides ("an industry variant can replace the lede," "industry can override heading") but which aren't populated with real content behind the flat mechanism. **Because Configurator is client-facing, industry-variant copy authored here must stay within confirmed/deliverable claims** — it is not a place to carry over Story's named-client or broader-migration-history material verbatim; any proof-flavored content in these chapters needs its own client-safe wording, reviewed separately from the Story variant copy even where the two are authored against the same reconciled mechanism.

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

**Configurator is client-facing — a prospect or client sees this directly, often with a rep presenting live.** Every proposal below assumes that lens: polished, confirmed-only claims, no internal self-talk, but with room for a forward-looking "here's where this is headed" beat, since showing a client what's possible is part of what closes deals.

1. **Restructure the 9 chapters into a narrower, sharper flow** — 9 sequential full chapters is a lot for a presentation a rep drives live in a client room. Proposed consolidation to 6:
   - `cover` (unchanged — token substitution is good)
   - `challenge` (merge `partner`+`challenge`: lead with the problem, not "how we work with you," which is generic agency boilerplate better suited to a footer credential than an opening beat). **Visual treatment (new, proposed):** this is one of two merged chapters (the other is `approach`+`engagement` below) proposed to carry a distinct, contained interaction pattern — a parallax-scroll effect where content cards appear to scroll over/stack on top of one another as the visitor scrolls, presented inside a glass-like (frosted/translucent, glassmorphism-style) frame. This is a new pattern for this codebase (confirmed: no existing parallax or glassmorphism CSS in `gtmConfigurator` or `gtmStory`), proposed specifically because these two chapters are newly-merged and the owner wants them to stand out from the rest of the flow. Scoping is deliberate and important: the effect and its supporting code must live entirely inside these two chapters' own sections — it is not a page-wide treatment, and `cover`, `proof`, `deliverables`, and `why`+`closing` should keep their current flat, non-parallax presentation. Left to Architect/Developer to design the actual mechanism (e.g. CSS scroll-driven animation or an IntersectionObserver-based approach, `backdrop-filter` for the glass effect, etc.) — this doc is describing the desired effect and its scoping, not prescribing the implementation.
   - `proof` (unchanged — this is the component's best asset, keep it central; per the confirmed-only rule, this chapter should state plainly what's been delivered (Medtronic, by name, is fine here since it's a real confirmed engagement); forward-looking capability must stay honest and clearly distinguishable in substance from what's actually shipped, but should read as a confident, narratively-woven part of the story rather than being called out with an explicit "roadmap"/"in progress" label or disclaimer — the distinction is compliance-accuracy, not visible hedging, and that's a real difference worth Architect/Developer understanding: the rule is about what the copy claims, not about tagging it)
   - `approach` + `engagement` merged into one: "how we get there," combining the 3-card approach with the 4-phase model into a single visual timeline instead of two separate card layouts saying similar things. **Shares the parallax/glass visual treatment described under `challenge` above** — same scoping rule applies: contained to this chapter's own section, not bleeding into neighboring chapters.
   - `deliverables` (unchanged — concrete and useful)
   - `why` + `closing` merged: end on the differentiation argument immediately followed by the ask, rather than a "why us" chapter and then a separate closing chapter that repeats momentum-loss risk between them. **The "why" argument here must stay client-facing** — positioning language framed as internal self-talk about how PS operates (e.g. "we're an engineering firm, we spend our time figuring it out") belongs on Story only, if anywhere, and must not be drafted into this chapter; the client-safe version of "why us" leads with delivered outcomes and confirmed capability. Forward-looking material here follows the same substance-over-labeling approach as `proof`: it stays truthful and distinguishable from delivered work, but is woven confidently into the differentiation narrative rather than set off as a flagged "where this is headed" beat.
2. **Close the industry-content gap described in §3, with the client-facing constraint carried through** — today `challenge`/`why` can technically be overridden per-industry but aren't populated; once the Story/Configurator variant mechanisms are reconciled, author real industry copy for these two chapters as part of this surface's overhaul. That copy needs to be written fresh for a client audience (confirmed claims plus clearly-labeled forward-looking framing), not lifted from Story's more candid industry-variant content.
3. **Formalize the brand wordmark/accent-color rule** the tests already assert into an actual short PS-brand reference doc under `docs/architecture/` (e.g. `docs/architecture/ps-brand-basics.md`) — wordmark treatment, accent-color contrast rule, font stack — so it's documented once instead of re-derived from test assertions. This is small and cheap and directly closes the "no style guide exists" gap found in this research for all four surfaces, not just Configurator.
4. **Leave the state machines (password gate, assessment submission, readout) structurally alone** — they're working infrastructure unrelated to "design," and the B11 offering-resolution guardrail must not regress.

**Tradeoff:** Consolidating 9 chapters to 6 is a content and possibly template-schema change (fewer `GTM_Page_Section__c` rows, different `layoutType` combinations) — cheaper than it sounds since the underlying engine already supports arbitrary section counts/order, but it does mean re-authoring chapter copy rather than just re-skinning existing chapters, consistent with the issue's explicit "not a tack-on" instruction. The confirmed-only-claims constraint also means Configurator copy can't simply reuse Story's forthcoming Positioning & Proof content (§1) even where the underlying facts overlap — it needs its own client-safe pass. The proposed parallax/glass treatment on `challenge` and `approach`+`engagement` is presentational only — it doesn't loosen the confirmed-claims rule above, doesn't touch offering resolution (item 4 below, the B11 guardrail), and doesn't touch the state machines; it's scoped narrowly enough that Architect should be able to design it without those other constraints coming into play.

### Open Questions
- Is there PS-approved brand asset availability (logo files, exact hex values, approved font licensing) to formalize into the proposed brand reference doc, or does this overhaul have to proceed with the wordmark/color rules as currently inferred from code?
- Should the Agentforce bot instructions be rewritten now to match the new chapter structure, or held until the Agent Script migration is further along (it's already mid-migration per the "superseded" flag)?
