# Content Manager IA — implementation plan

**Author:** Architect agent (session `session_018UJzwgTCCMdESELzYMeWAZ`)
**Date:** 2026-09-07
**Status:** For Dev implementation, then QA verification against this plan and the live `gtm-dev` org. This is an implementation spec, not the code — Dev still has to write it. Design only; nothing in this plan has been deployed.
**Scope guard:** Does not touch offering-creation flow internals (sibling Architect's bug-fix lane) or the Instrument Editor screen. Where this plan depends on the offering-creation fix landing first, it says so.

---

## 0. Repo grounding (what I actually read)

`gtmContentManager.js`/`.html`, `gtmContentHome.js`/`.html`, `gtmPageLayouts.js` (the shared layout/template contract), `gtmFieldEditor.js`/`.html`, `gtmPagePreview.js`/`.html`, `gtmConfigurator.html` (GUS wiring), `gtmConfigWizard.js` (swatches/sizePresets read path), `GtmPageSectionController.cls` (`createSection`, `createPage`, `VALUE_TYPES`), `GtmPageContentController.cls` (`createOffering`), `GTM_Page_Section__c`/`GTM_Page_Content__c` field inventories, `Css_Class__c`/`Inline_Style__c` field-meta, `gtmStory.css`/`gtmConfigurator.css`.

Key facts that shape every design below:

- **`offering-defaults` (the "Configurator defaults" section) is never rendered on the public page.** `grep` of `gtmConfigurator.js` for `'defaults'`/`offering-defaults` returns nothing — the rep-facing prospect page has no branch for it. It is read only by `gtmConfigWizard.js` (`c['defaults::swatches']`, `c['defaults::sizePresets']`), the rep's link-configuration tool. It lives under `Template_Type__c = 'configurator'` purely because it was seeded alongside the configurator's chapters in `STARTER_PAGES.configurator` (`gtmPageLayouts.js:347`) — not because the renderer needs it there.
- **`GtmPageSectionController.createSection` has no server-side layout/template gating today** — `layoutType` is accepted as any string for any `templateType`; `TEMPLATE_LAYOUTS` (`gtmPageLayouts.js`) is a client-only allow-list. `createPage`, by contrast, already refuses to re-seed a page that has sections (`GtmPageSectionController.cls:585-593`) — that guard is real and already correct; the gap is purely in the "New Offering Page" modal's UX, not the data layer.
- **GUS (`c-gtm-agent-bubble`) is wired unconditionally into `gtmConfigurator.html`** (lines 439, 478) — the configurator renderer, not any one offering's content. `gtmPagePreview.js`'s `isConfigurator` branch renders `c-gtm-configurator` for any offering's Configurator page, so GUS always appears in that preview regardless of which offering or which section is being edited. `gtmPagePreview.js` already has a `previewNote` mechanism (`.pv-note`, rendered above the stage) used today for the offerings-listing and configurator previews — the natural hook for a GUS caption.
- **No per-offering theme/token layer exists.** `gtmStory.css` (1045 lines) and `gtmConfigurator.css` (1424 lines) are single, shared stylesheets with ~150-200 raw color/`var()` declarations each, used by every offering that renders through those components. The only per-offering visual levers today are (a) `swatches` — a JSON list of preset colors offered to a **rep** at link-configuration time, not a page-wide theme, and (b) `Css_Class__c`/`Inline_Style__c`/`Html_Id__c` on `GTM_Page_Content__c` — a raw, per-field CSS/inline-style escape hatch exposed in `gtmFieldEditor.html`'s "Advanced" panel (lines 181-204), already fully offering-scoped since every content row carries `Offering_Key__c`.

---

## 1. "Settings" as its own surface (not a content section)

### 1.1 The two complaints, mapped to code

1. `sizePresets`/`swatches` (layout type `offering-defaults`, section key `defaults`, label "Configurator defaults") sits in `gtmContentManager`'s ordinary `railSections` list (`gtmContentManager.html:160-206`) next to "Cover," "Path," and every other chapter — same rail, same `<div class="sec">` row, same icon treatment (`SECTION_ICONS['offering-defaults'] = 'utility:settings'` is the only hint it's different, and it's easy to miss).
2. The offering card's **Settings** button (`gtmContentHome.html:132-138`) calls `handleOpenSettings` → `openEditor(key, 'configurator')` (`gtmContentHome.js:409-412`) — this opens the **whole** Configurator page editor, landing wherever `activeKey` last was (usually the first chapter, "Cover"), not the defaults section. That is exactly "the default non-customized page for the configurator."

### 1.2 Why not a new `Template_Type__c`

The obvious "real" fix is to give `offering-defaults` its own template type (mirroring how `assistant` already got promoted to a Framework-level template — see `gtmPageLayouts.js:321-329`, D8). I looked at this and am **not** recommending it: `gtmConfigWizard.js` and `GtmHomeSnapshotController.cls` both hardcode `templateType = 'configurator'` when reading `defaults::swatches`/`defaults::sizePresets`, and `gtmConfigWizard` is the rep-facing tool that builds real prospect links on `gtm-dev` (production). Moving the data to a new `Template_Type__c` means a data migration (`GTM_Page_Section__c.Template_Type__c` + every affected `GTM_Page_Content__c.Content_Address__c`/`Template_Type__c` for the one offering that has it built, Migration Accelerator) *and* changing the read path in a component that drives live prospect-facing configuration — real risk for an IA cleanup. **Recommendation: keep the data exactly where it is (`Template_Type__c = 'configurator'`, `Section_Key__c = 'defaults'`) and separate the *surface*, not the *storage*.** Zero backend risk, zero migration, zero change to `gtmConfigWizard`/`GtmHomeSnapshotController`.

### 1.3 Design

**`gtmContentManager.js`:**
- Add `get contentSections()` — `this.sections.filter(s => s.layoutType !== 'offering-defaults')` — and use it everywhere `railSections`/`sectionCount`/`hasSections`/`noSections` currently read `this.sections` for rail display and the add/reorder/delete flows. The rail (and its "Add section" flow) never shows or offers `offering-defaults` again.
- Add `get settingsSection()` — `this.sections.find(s => s.layoutType === 'offering-defaults')`.
- Add `@track settingsOpen = false`. A new toolbar affordance (in `gcm-bar`, beside the page combobox, not inside the rail) — "Customizer settings ⚙" — sets `activeKey` to `settingsSection.sectionKey` and `settingsOpen = true`.
- When `settingsOpen` is true, `gtmContentManager.html` renders a visually distinct header ("Customizer settings — {offeringLabel}") above `c-gtm-field-editor`, replaces the normal rail with a slim "← Back to page content" control (no drag/reorder/delete chrome — this is one fixed section, not a list), and passes a new `settings-mode` boolean into `c-gtm-page-preview` so its preview note can say "These values configure the rep's link wizard — they are not drawn on this page" instead of the generic configurator note. Toggling `settingsOpen` off returns to the normal rail with `activeKey` reset to the first content section.
- `capturePageRef` gains a third state key, `c__panel` (`'settings'` or absent), read alongside `c__offering`/`c__template`, so a deep link can land straight in settings mode.

**`gtmContentHome.js`:**
- `openEditor(offeringKey, templateType)` gains an optional third arg, `panel`, appended to the navigation `state` as `c__panel` when present.
- `handleOpenSettings` (currently `openEditor(key, template)`) becomes `openEditor(key, template, 'settings')` for offerings (`settingsTemplate` stays `'configurator'` — the data address is unchanged, only the panel changes). The Framework's Settings (→ `assistant`) is untouched — it already opens a dedicated template type and has no "content sections" list to separate from.

**`gtmPageLayouts.js`:** no changes to `TEMPLATE_LAYOUTS`/`STARTER_PAGES` — `offering-defaults` stays exactly where it is structurally; only the editor's *presentation* of it moves.

### 1.4 The "for GUS" line in the PO's quote

Read literally, "settings should take me to the customizer as a stand-alone page for GUS from my perspective" doesn't parse against anything in this codebase named "GUS" in this context (the assistant is addressed separately in Finding 2, and nothing GUS-related lives in the customizer/defaults section). Treating it as a dictation artifact for "for us" — i.e., "as its own stand-alone page, from my perspective" — is the only reading that's actionable and consistent with the rest of the quote and with Finding 2's separate, explicit GUS complaint. Flagging this rather than silently assuming it, per this pipeline's own standard of not leaving ambiguity unstated.

---

## 2. GUS's chat bubble in offering-scoped preview

### 2.1 What's happening

`gtmPagePreview.html`'s `isConfigurator` branch (`gtmPagePreview.js:73`) renders `c-gtm-configurator`, which unconditionally includes `c-gtm-agent-bubble` (`gtmConfigurator.html:439-446, 478-487`). Editing Migration Accelerator's Configurator content shows the live GUS bubble in the preview pane exactly as a prospect would see it — correct behavior for a "what will a prospect see" preview, but with **no label saying that's what it is**, which is why the PO couldn't tell if it was "reference" or an expected editable thing.

### 2.2 Design

`gtmPagePreview.js`'s existing `previewNote` getter (`.pv-note`, already rendered above the stage at `gtmPagePreview.html:34-36`) gets a new branch:

```js
get previewNote() {
    if (this.templateType === 'offerings-listing') { ... }        // unchanged
    if (this.templateType === 'configurator') {
        return 'Shown as a prospect sees it, using the first industry on this page. '
             + 'The "Ask Gus" bubble is configured at the Framework level, not here — '
             + 'see the Framework card’s Settings to change its name, tone or opening line.';
    }
    return '';
}
```

This is copy-only — one string, in the one place `gtmPagePreview` already explains what the preview is showing. No new component, no new field. It directly answers the PO's question ("is it just reference?") in the UI itself, not in a doc nobody reading the editor will see.

**Secondary, optional affordance** (recommended, low cost): make the note's "Framework card's Settings" a real link. `gtmPagePreview` doesn't have `NavigationMixin` today; adding it plus a `handleGusLinkClick` that calls `openEditor`-equivalent navigation to `('gtm', 'assistant')` turns the caption into a one-click fix rather than just an explanation. Given this component doesn't currently do any navigation (`gtmPagePreview.js` deliberately swallows clicks — see the `handlePreviewClick` comment about not navigating away from the editor), Dev should scope this as a small separate control outside the swallowed-click preview frame (e.g., a `<button>` in the `.pv-note` bar itself, which sits above `.pv-stage` and is not inside the click-capture region) rather than a link inside the rendered `c-gtm-configurator`.

---

## 3. Creation and rename guardrails

Four sub-findings, in increasing order of touch surface.

### 3.1 "New Offering Page" modal — only offer what doesn't exist yet

**Current:** `gtmContentHome.js`'s `templateOptions` getter (`gtmContentHome.js:236-238`) returns *every* template `templatesFor(offeringKey)` knows about (minus `SETTINGS_TEMPLATES`), built or not. Picking an already-built one and clicking "Open in the editor" is already safe server-side (`npIsExisting` skips `createPage` and just opens the editor — `gtmContentHome.js:334-337`; and `createPage` itself refuses to re-seed a page that has sections, `GtmPageSectionController.cls:585-593`), but the modal presents built and unbuilt pages identically, which is the actual complaint — a "New Offering Page" modal shouldn't be where you go to *open* an existing page.

**Design:**
- Change `templateOptions` to filter to genuinely creatable pages only:
  ```js
  get templateOptions() {
      const offering = this.offerings.find((o) => o.offeringKey === this.npOffering);
      const builtTypes = new Set((offering?.pages || [])
          .filter((p) => (p.sectionCount || 0) > 0)
          .map((p) => p.templateType));
      return this.pageTemplatesFor(this.npOffering)
          .filter((t) => !builtTypes.has(t))
          .map((t) => ({ label: TEMPLATE_LABELS[t] || t, value: t }));
  }
  ```
- `npIsExisting` becomes dead code once the dropdown can never carry a built value — remove it and the "This page already exists" branch of `npHint` (a defensive `createPage`-refusal message can stay as the `.catch` fallback, since the Apex guard remains the real backstop).
- When every one of an offering's (or the Framework's) templates is already built, `templateOptions` is empty. Disable the combobox and change `npHint`/`npDisabled` to say so plainly: *"{offeringLabel} has no pages left to create — every page it can have is already built."* For the Framework specifically (all four of `offerings-page`/`industry-chooser`/`faq-bd`/`faq-content-manager` ship pre-seeded — confirm with QA, §6.6), this means **Framework selected in this modal will show that message immediately**, which is the literal fix for *"Should not be able to add new offering from the framework once it's built... Title is misleading — this is a framework piece only."* Rather than hide the Framework option from `offeringOptions` entirely (which would also hide it from the legitimate "open an existing framework page" use case this modal still serves for a not-yet-built framework template, if one is ever added later), keep Framework selectable but let the empty-dropdown state say why nothing is offered.

### 3.2 Structural page titles cannot be renamed — confirm the negative

There is currently **no** UI or Apex path that renames a `Layout_Type__c`/`TEMPLATE_LABELS` page title (Offerings Page, Industry Chooser, BD App Help FAQ, Content Manager Help FAQ, Story, Configurator, Offerings Listing) — `TEMPLATE_LABELS` (`gtmPageLayouts.js:392-401`) is a hardcoded JS constant with no corresponding Apex mutator. This already matches what the PO wants ("should not be able to rename the pages either") — **no change needed here**, only confirm QA checks it stays true (§6.9) rather than something a future change accidentally exposes (e.g., don't let `Label__c` on the page's own top-level section double as a "page title" editable field — verify `sectionLabel` in `gtmFieldEditor.html:5` is scoped to one section, not the page).

### 3.3 Offering name rename — already correct, no change

`handleStartRename`/`handleSaveRename` (`gtmContentHome.js:363-394`) → `renameOffering` Apex already does exactly what's wanted: only the offering's own display name, nothing structural. No change.

### 3.4 FAQ entry titles — allow rename, block add

**Current:** `faq` is a plain `json` field (`items`), rendered by `gtmFieldEditor`'s generic list-of-objects editor (`gtmFieldEditor.js:163-224`, `buildItems`) — the same generic mechanism used for `cards`, `chips`, `phases`, and every other JSON array field in the app. That generic editor already supports renaming an existing entry's `question`/`answer` text in place (`handleItemChange`, `gtmFieldEditor.js:301-308`) — **renaming an existing FAQ entry already works today**, no change needed there. What's also generic, and shouldn't be for FAQ specifically, is `handleItemAdd`/the "+ Add item" button (`gtmFieldEditor.html:174-177`).

**Design:**
- Add a small exported constant to `gtmPageLayouts.js`, alongside `LAYOUT_FIELDS`: `const LOCKED_JSON_ITEMS = new Set(['faq::items']);` (keyed `${layoutType}::${fieldKey}`, so it can grow to other json-array fields later without a new mechanism).
- In `gtmFieldEditor.js`'s `activeFields` mapper, add `itemsLocked: base.isJson && LOCKED_JSON_ITEMS.has(\`${this.layoutType}::${r.fieldKey}\`)`.
- In `gtmFieldEditor.html`, wrap the "+ Add item" button (line 174-177) in `<template if:false={f.itemsLocked}>`. Leave the per-item delete (line 137-138) and reorder (131-136) controls untouched — the PO's quote only says "should not be able to make new ones," not that existing entries can never be retired or reordered; scope the block to creation only, per the literal ask.
- **Server-side backstop:** `createField`/the JSON-array append path in `GtmPageSectionController.cls` has no equivalent gate today (same pattern as §3.5 below — client-only enforcement, called out explicitly rather than silently assumed safe). Given `handleItemAdd` mutates the JSON blob client-side and saves through the ordinary `saveDrafts` path (not a distinct "add array item" Apex method), there is no single Apex entry point to gate — the array shape is opaque to the server. Flag this to Dev as an accepted, documented gap (an API/data-loader write could still append an FAQ entry) rather than a silent one; a real server-side fix would mean `GtmPageSectionController.saveDrafts` parsing and diffing JSON array lengths per `layoutType::fieldKey`, which is a larger change than this pass's scope. **Recommendation: ship the UI gate now, note the gap in `docs/backlog.md`.**

### 3.5 Industry Chooser — no new sections from the generic editor

**Current:** `TEMPLATE_LAYOUTS['industry-chooser'] = ['industry-tile']` (`gtmPageLayouts.js:207`) — the *only* thing addable on this page today is a new industry, via the fully generic "Add a section" modal (any heading text, becomes the industry's `Section_Key__c`). This is, today, the sole way a new industry gets created anywhere in the app — there's no purpose-built "Add industry" form with its own validation (duplicate industry names, a real key rather than a slugified heading).

**Design — literal read of the PO's "I can click in, I can add — should not be able to," taken at face value:**
- Set `TEMPLATE_LAYOUTS['industry-chooser'] = []` (matching the existing `offerings-page` pattern at `gtmPageLayouts.js:206`), so `addableLayouts('industry-chooser')` returns `[]`, `hasLayoutOptions` is false, and the "Add section" button/modal reuses the existing `noLayoutsReason` messaging path (`gtmContentManager.js:650-654`) — add an `industry-chooser`-specific branch there: *"Industries aren't added from this generic editor. Edit an existing industry's tile to change what it says."*
- Existing `industry-tile` sections stay fully editable (rename, reorder, hide, delete) — only *creation* is blocked, matching "I can click in, I can add" (the complaint is about add, not edit).

**Explicit trade-off, stated rather than hidden:** this closes the *only* current path to adding a brand-new industry through the UI. The PO's own phrasing — "only this page should have the Industry builder or update" (i.e., there should be exactly one true home for industry management, and it should be a real builder) — reads as confirming industries are meant to be managed somewhere, just not through the generic "any layout, any label" modal being used as a stand-in for one. **Recommendation:** ship the block now (it's what was explicitly asked for and it's one line), and log a follow-up in `docs/backlog.md`: *"Industry Chooser has no way to add a new industry after this pass closed the generic Add-section path. A purpose-built 'Add industry' flow (validated key, duplicate check, seeded field set) is needed before this becomes a real gap — not urgent while Migration Accelerator is the only offering in the org, but blocking the moment a second industry needs to be added."* This is a real, near-term functional gap this pass creates, not a hypothetical — surfacing it beats letting Dev or QA discover it by trying to add an industry and finding no way to.
- Separately, per bullet 3.1: "Industry Chooser" (like the other three Framework pages) will already stop appearing in the "New Offering Page" modal's dropdown for the Framework once it's built, addressing *"Industry also should not be new either... this is a framework piece only"* through the same generic already-built filter — no industry-specific modal logic needed.

---

## 4. Onboarding after creating something new

### 4.1 What already works — confirm, don't rebuild

The empty-state pattern the PO referenced ("This page has no sections yet — open it to build the first one") is `gtmContentManager.html`'s `noSections` block (lines 147-158) — it is generic over `templateType`/`offeringKey` (gated only on `this.sections.length === 0`), so it already fires consistently for **every** unbuilt page, not just the one the PO happened to screenshot. **No change needed to make it "consistent" — it already is.** QA should confirm this rather than take the claim on faith (§6.13).

### 4.2 What's actually thin — the two real gaps

1. **A newly created offering never lands on a truly empty page**, so the existing empty-state banner never fires for it at all. `createOffering` (`GtmPageContentController.cls:456-527`) seeds the `offerings-listing` tile section with real content (name/mark/description) before `gtmContentHome.js`'s `handleCreateOffering` navigates straight into that already-built page. A brand-new offering has zero orientation about the fact that it has two more pages (Story, Configurator) still to build — it looks, at a glance, like a normal already-set-up offering with one section.
2. **No offering-level "what's left" signal exists anywhere in the home grid**, only a raw count (`"N pages ready to edit"`, `gtmContentHome.js:122-124`) that doesn't say what's *missing*.

### 4.3 Design

**A. Post-creation welcome banner (`gtmContentManager.js`/`.html`):**
- `gtmContentHome.js`'s `handleCreateOffering` calls `this.openEditor(key, 'offerings-listing', 'new')` — reusing the same `panel` state param added in §1.3, with `c__panel=new` distinguishing this from `c__panel=settings`.
- `gtmContentManager.js`'s `capturePageRef` sets `@track showWelcome = true` when it reads `c__panel === 'new'` (and clears the query param's effect after first read, so a refresh doesn't re-show it).
- `gtmContentManager.html` renders a dismissible banner above the rail when `showWelcome` is true: *"{offeringLabel} is live on the offerings page. Next: build its Story and Configurator pages — use “New page for this offering” from the Content home, or the page picker above."* A "Got it" button sets `showWelcome = false`.

**B. Steady-state "what's left" hint on the home grid (`gtmContentHome.js`/`.html`):**
- Extend the `cards` getter: `get nextStepHint()` per card — `built.length < o.pages.length` → join the unbuilt pages' labels: *"Still to build: Story, Configurator."* Render this as a second line under the existing `summary` badge (`gtmContentHome.html`, inside `off-head`, near `o.badgeClass`/`o.summary`). Offerings with everything built show nothing (same zero-cost-when-clean principle as `KnownGapsBanner` elsewhere in this codebase's sibling project's conventions, applied here on the same reasoning — no noise on a finished offering's card).

This covers both the one-time (just created) and steady-state (came back later, still incomplete) orientation gaps without inventing a new onboarding framework — both reuse getters/patterns already in these two files.

---

## 5. "Look and feel" scoping — recommendation: **defer**, with a stated trigger and seam

### 5.1 What "look and feel" is, concretely, today

Three distinct things answer to that name in this codebase, at three different levels:

| Level | Mechanism | Scope today |
|---|---|---|
| Per-field escape hatch | `Css_Class__c`/`Inline_Style__c`/`Html_Id__c` on `GTM_Page_Content__c`, edited via `gtmFieldEditor`'s "Advanced" panel | Already fully offering-scoped (every row carries `Offering_Key__c`) — a content author can already nudge one field's presentation per offering, today, with zero new work |
| Rep-facing color choice | `swatches` (JSON list under `offering-defaults`) | Already fully offering-scoped — each offering defines its own swatch set, read by `gtmConfigWizard` when a rep configures a link |
| Base visual system | `gtmStory.css` (1045 lines) / `gtmConfigurator.css` (1424 lines) — typography, spacing, the ~150-200 raw colors and layout rules that make the page look like the page | **Shared** — one stylesheet per renderer component, used by every offering that renders through it. No CSS custom-property/token indirection exists for per-offering overrides; changing "the look" today means editing these files directly, which changes it for every offering at once |

The PO's question — "what if a new user wants to update look and feel for a new offering, or even edit the accelerator one" — is squarely about the third row. The first two are already solved.

### 5.2 The actual build cost of the third row

To let a content author change "the look" of one offering without touching the other's requires introducing a real theme/token layer: CSS custom properties (`--gtm-brand-primary`, etc.) threaded through two ~1,000-1,400-line stylesheets that currently hardcode values directly, a source for those values (a new json field, most naturally sitting beside `swatches` — reusing the exact "settings, not content" surface this plan just built in §1), and a way to apply them per-offering at render time (a wrapper class or inline custom-property block on the host element, following the same pattern `Inline_Style__c` already uses). That is a multi-file, cross-cutting CSS refactor — categorically bigger than any of the four build items above, all of which are single- or few-file, additive, low-risk changes.

### 5.3 Recommendation: defer, don't leave open

**Build now:** nothing beyond what §1-4 already deliver (the per-field/per-offering levers that exist today are real and already sufficient for the one offering currently live).
**Defer:** a real per-offering theme/token layer for `gtmStory.css`/`gtmConfigurator.css`.

**Reasoning:**
1. There is exactly one built-out offering in the org today (Migration Accelerator). A theming system justified by "what if a second offering wants a different look" has no second offering to validate against yet — building it now is speculative, not demand-driven, and this pipeline's own precedent tonight (per this brief's own instruction) is to decide scoping calls from what's actually needed, not what might be.
2. The existing per-field `Css_Class__c`/`Inline_Style__c` hatch is a real, already-offering-scoped release valve for the *specific* case the PO raised second — "edit the accelerator one we've built so far" — a content author can already override one element's color/spacing per offering today, without waiting on anything from this plan.
3. Sizing against everything else in this plan: items 1-4 are all bounded, few-file changes with clear before/after states. A theme layer is not — it is a cross-cutting CSS architecture change to the two largest, most heavily-styled components in the app, exactly the kind of thing that needs its own spec and its own build/QA pass, not a line item riding inside an IA cleanup plan.

**The concrete trigger, so this isn't deferred into silence:** build the token layer the moment a **second** offering is being onboarded with a genuinely different visual identity from Migration Accelerator's. At that point, the seam is already known — introduce CSS custom properties at the top of `gtmStory.css`/`gtmConfigurator.css`, sourced from a new json field beside `swatches` in the (now-separated, per §1) customizer settings surface, applied via the same per-offering scoping mechanism `Inline_Style__c` already establishes. Log this as a `docs/backlog.md` entry now (open item, not a closed decision) so it isn't re-litigated cold the next time it comes up.

---

## 6. QA verification checklist

Numbered to match the sections above. Each item says how to check it. Items marked **[UI-only]** cannot be confirmed without a browser and should be reported as such, not claimed verified, per the standing instruction in this repo's agent pipeline.

**§1 — Settings surface**
1. `offering-defaults`/"Configurator defaults" section no longer appears in `gtmContentManager`'s Sections rail for Migration Accelerator's Configurator page — query `GTM_Page_Section__c` for that section's `Id`, confirm `railSections`/`contentSections` logic excludes it (code-level: confirm the filter is present and correct; **[UI-only]** for confirming the rail visually omits it).
2. Migration Accelerator's offering card → Settings button lands directly on the customizer settings view, not the Cover/first-chapter content. **[UI-only]**
3. `sizePresets`/`swatches` are still readable and editable through the new surface — edit one, save, confirm the draft persists via `getAllContent` for `offeringKey='migration-accelerator', templateType='configurator'` (data-layer check, not UI-only).
4. `gtmConfigWizard` still reads `defaults::swatches`/`defaults::sizePresets` correctly after this change — since `Template_Type__c` was deliberately left unchanged, this should be a no-op; confirm by loading the rep-facing wizard for Migration Accelerator and checking swatches/sizes render as before. **[UI-only]** for the wizard render; the "`Template_Type__c` unchanged" claim is a code-level fact QA should also confirm directly (`git diff` shows no `Template_Type__c` change).

**§2 — GUS preview caption**
5. The `.pv-note` caption above the Configurator preview now includes the GUS clarification sentence when editing any offering's Configurator page. **[UI-only]**
6. The caption's wording doesn't claim the offering-scoped preview is non-editable for GUS's *content* — it should point to the Framework Settings, not imply GUS can't be changed at all. Read-review of the exact copy shipped, against §2.2's suggested text.

**§3.1 — New Page modal gating**
7. With Framework selected in "New Offering Page," the Page dropdown is empty (or shows the "nothing left to create" message) — query `GTM_Page_Section__c WHERE Offering_Key__c = 'gtm'` grouped by `Template_Type__c`, confirm all four (`offerings-page`, `industry-chooser`, `faq-bd`, `faq-content-manager`) already have sections in the live org before asserting the dropdown *should* be empty (if one is genuinely unbuilt today, the dropdown correctly should still offer it — confirm actual org state first, don't assume all four are built). **[UI-only]** for the dropdown rendering itself.
8. With Migration Accelerator selected, only genuinely unbuilt offering templates appear (cross-check against `getHomeSummary`'s per-offering `pages` array — a template with `sectionCount > 0` must not appear in the dropdown).
9. Confirm no rename affordance exists anywhere for a structural page title (Offerings Page / Industry Chooser / FAQ pages / Story / Configurator / Offerings Listing) — `grep` the LWC tree for any new rename-page handler introduced by mistake during this change; should find none.

**§3.4 — FAQ items**
10. On `faq-bd` or `faq-content-manager`'s FAQ section, the "+ Add item" button is hidden/absent. **[UI-only]**
11. An existing FAQ entry's question/answer text can still be edited and saved as a draft — exercise via the field editor, confirm `saveDrafts` persists the change (data-layer check).
12. Confirm delete and reorder controls on existing FAQ entries are unaffected (still present) — this was deliberately left unblocked per §3.4's scoping.

**§3.5 — Industry Chooser add-lock**
13. On the Industry Chooser page, "Add section" is disabled/shows the new `noLayoutsReason` message instead of the layout picker. **[UI-only]** for the message; code-level confirm `TEMPLATE_LAYOUTS['industry-chooser']` is `[]`.
14. Existing industry-tile sections remain fully editable, reorderable, hideable, and deletable — this pass should not have touched any of those paths; spot-check one industry's rename/reorder still works.
15. Confirm the backlog entry for "no way to add a new industry" (§3.5) actually landed in `docs/backlog.md`, not just this plan — QA should treat an undocumented gap as a finding against this plan's own completion, not silently accept it.

**§4 — Onboarding**
16. Creating a new offering (once the sibling bug-fix lane's creation defect is resolved — confirm with that lane's status before running this check, don't run it against a known-broken creation flow and misattribute a failure) shows the welcome banner on first landing on its `offerings-listing` page, and the banner does not reappear on a page refresh. **[UI-only]**
17. An offering with 1 of 3 pages built shows the correct "Still to build: ..." hint on its home card, naming the actual missing pages (not a stale/hardcoded list) — cross-check against `getHomeSummary`'s data for that offering.
18. An offering with all pages built shows no hint text (zero-cost-when-clean) — confirm for Migration Accelerator once/if its Story and Configurator are both built; if not yet fully built at QA time, confirm on whichever offering *is* fully built, or explicitly note none currently qualifies. **[UI-only]** for the visual absence.

**§5 — Look and feel (no build in this pass)**
19. Confirm no code changes were made under this plan that touch `gtmStory.css`/`gtmConfigurator.css`'s color/token structure — `git diff` on those two files should be empty for this change set.
20. Confirm the `docs/backlog.md` entry for the deferred theme-layer trigger (§5.3) actually landed, worded as an open item with the stated trigger condition, not as a closed decision.

**General, every section**
21. Every Apex change in this plan (none load-bearing beyond the existing `createSection`/`createPage`/`saveDrafts` paths, which are unchanged) still passes `sf apex run test --target-org gtm-dev` — this plan adds no new Apex classes and changes no existing Apex method signatures, so a clean test run is a real regression check, not a formality.
22. `python3 scripts/check-references.py` — 0 deploy-blocking, per repo convention — after all LWC/JS changes land.
23. No permission-set changes are required by this plan (no new fields, objects, or tabs are introduced — §1-5 are all reuses of existing `GTM_Page_Content__c`/`GTM_Page_Section__c` rows and existing Apex methods). QA should confirm this claim directly rather than take it on faith: `git diff` the change set against `force-app/main/default/permissionsets/` and confirm it's empty.
