# Instrument Editor — orientation/context plan

Author: Architect agent (UX-clarity workstream), 2026-09-07.
Status: design only. A Dev agent implements this plan; a QA agent validates
it against the checklist at the end. Do not implement from this session.

Scope: `force-app/main/default/lwc/gtmInstrumentAuthor/` (the "Instrument
Editor" tab). No changes to `GtmMigrationPairs.cls`, `GtmAssessmentInstrument.cls`,
or any custom metadata — see the wiring verdict below for why.

---

## 0. TL;DR

- The mechanism this screen edits (`GTM_Assessment_Pair__mdt`, resolved by
  `GtmAssessmentInstrument`) **is correctly wired end to end**, for the path
  that actually reaches it. No functional bug in scope for this screen.
- The product owner's specific belief — *"I think they have a way to enter
  the tool in the customizer... shouldn't this carry through to here"* — is
  **not correct today**. No such field exists. That belief is exactly the
  kind of thing this screen's orientation copy needs to correct, in plain
  language, not paper over.
- Separately, and **more consequential than anything in this screen**: the
  live guest site's booking form (`gtmConfigBooking`, embedded in the `/gtm`
  site's `/configurator` route) **never asks any of the eight scored
  questions this editor authors**, and the component that does
  (`gtmAssessmentQuestionnaire`) is only wired into a route on
  `GTM_Accelerator1`, which is `DownForMaintenance`. This is a real,
  previously-undocumented instance of the exact ADR-0006/route-reachability
  gap CLAUDE.md already flags for the Industry Chooser (backlog D9) — but
  for the assessment, not the industry chooser. It is **out of scope** for
  this design (it's not an Instrument Editor legibility problem, it's a
  live-flow wiring problem), but the orientation copy below says so
  explicitly, because an author editing this screen needs to know that
  today, nothing they change here reaches a real GTM1 prospect through the
  scored path. See §1.4 and the "flagged, not fixed" note at the end.

---

## 1. Wiring verification (with citations)

### 1.1 The chain this screen edits, confirmed correct

`gtmInstrumentAuthor.js` calls `GtmAssessmentInstrument.getPack(sourceName,
targetName)`
(`force-app/main/default/lwc/gtmInstrumentAuthor/gtmInstrumentAuthor.js:81-84`).

Server side, `GtmAssessmentInstrument.getPack`
(`force-app/main/default/classes/GtmAssessmentInstrument.cls:634-644`)
resolves free-text platform names to canonical keys via
`GtmMigrationPairs.resolvePlatformKey` and calls `resolve()`, which walks the
chain documented at the top of the class (lines 43-53):

```
exact pair (hubspot__mcn)
  -> source-family x target (inbound_suite__mcn)
    -> target-only (any__mcn)
      -> base
```

against `GTM_Assessment_Pair__mdt` / `GTM_Assessment_Dimension_Override__mdt`
(`GtmAssessmentInstrument.cls:698-790`, `matchRank` at 797-817). This is a
**different metadata pair table** from the one that gates whether the
accelerator supports a combination at all
(`GTM_Migration_Pair__mdt` / `GtmMigrationPairs.cls`, used only for the
unsupported-pair tier suppression). Both key off the same
`GTM_Migration_Platform__mdt` platform identity table, but they answer two
different questions:

| Table | Question it answers | Read by |
|---|---|---|
| `GTM_Migration_Pair__mdt` | "Can the accelerator process this pair at all?" | `GtmMigrationPairs.evaluate`, called from `GtmAssessmentRequestController.resolvePairEligibility` |
| `GTM_Assessment_Pair__mdt` + `GTM_Assessment_Dimension_Override__mdt` | "Which eight questions, worded and branched how, does this pair ask?" | `GtmAssessmentInstrument.resolve`, called from `getPack` — **this is what the Instrument Editor authors** |

This distinction is itself invisible on the current screen and is one
driver of "what am I building" — see §2.

### 1.2 The live resolution path (prospect → pack → score), confirmed correct

On the guest questionnaire (`gtmAssessmentQuestionnaire`), the respondent's
first step is routing (`routing.source` / `routing.target`), populated from
`GtmAssessmentInstrument.getPlatforms()` (reads `GTM_Migration_Platform__mdt`)
— `gtmAssessmentQuestionnaire.js:39, 141, 182`. Leaving that step calls
`getPack({ sourceName: this.routing.source, targetName: ... })` to resolve
the live pack (`gtmAssessmentQuestionnaire.js:261-270`), and the submission
payload sends `currentPlatform` / `targetPlatform` straight from those same
two fields (`gtmAssessmentQuestionnaire.js:919-923`).

Server side, `GtmAssessmentRequestController.submitRequest` **never trusts
the client's resolved pack** — it independently calls
`GtmAssessmentInstrument.getPack(input.currentPlatform, input.targetPlatform)`
again (`resolveInstrumentPack`,
`GtmAssessmentRequestController.cls:1152-1162`), applies branches from the
submitted answers (`applyBranches`, `.cls:534`), and scores against that
re-resolved pack (`.cls:536-540`). This is correct and is exactly the
"answer under a key the server did not ask for is simply never read"
allowlist property `GtmAssessmentInstrument.applyBranches`'s own header
comment describes (`GtmAssessmentInstrument.cls:964-989`). **The respondent's
own routing answer, re-verified server-side, is the sole and correct source
of which pack scores a submission.**

### 1.3 The product owner's specific belief, checked and refuted

Searched every rep-facing surface for a per-link source/target platform
field:

- `gtmConfigWizard.html` (the actual "customizer" — the multi-step sheet
  opened from "Customize" on a saved link): **no field, input, or step for
  source/target platform anywhere in the template.** Confirmed by grep —
  zero matches for `SOURCE_PLATFORM`/`TARGET_PLATFORM` in that file.
- `gtmConfigWizard.js` never sets `_state.SOURCE_PLATFORM` /
  `TARGET_PLATFORM` from any handler. The only place those keys get a value
  is `connectedCallback()` pulling `defaults::defaultSourcePlatform` /
  `defaultTargetPlatform` from the **offering's own CMS content**
  (`gtmConfigWizard.js:308-319`) — a single pair of values shared by every
  link of that offering, authored in GTM Content Manager, not entered by a
  BD per client.
- `gtmConfigurator.html:457-472` wires
  `<c-gtm-config-wizard onfieldchange={handleFieldChange}>`, and
  `handleFieldChange` (`gtmConfigurator.js:1132-1135`) would merge a
  `{key, value}` pair — including `SOURCE_PLATFORM`/`TARGET_PLATFORM` from
  `c/gtmConfigData`'s `FIELDS` list — into `tokenState`. **But
  `gtmConfigWizard.js` never dispatches a `fieldchange` event anywhere.**
  This is dead, unreachable wiring — almost certainly left over from an
  earlier single-panel field editor that predates the current 8-step
  wizard. It doesn't corrupt anything (nothing calls it), but it is exactly
  the kind of leftover that would make someone who's seen the codebase
  before believe a field like this exists.
- `SOURCE_PLATFORM`/`TARGET_PLATFORM` tokens, wherever they do get a value
  (CMS default, or the legacy `?src=&tgt=` URL params read in
  `gtmConfigurator.js:571-577`, from before `?cfgId=` links existed), are
  used **only to substitute story copy** ("moving from {SOURCE_PLATFORM}...")
  via `tokenValue()`. They are never read by `gtmAssessmentQuestionnaire`,
  which has no `prefillPlatform`-style `@api` prop at all and always starts
  its routing step blank (`gtmAssessmentQuestionnaire.js:141`) — the
  respondent answers Q0 themselves regardless of what a rep set upstream, by
  design (see §1.2).

**Verdict: the product owner's mental model of a customizer field that
"carries through" is false today.** There is no such field, and even the
tokens that superficially resemble one don't feed the assessment. This is
not a bug to fix — the design in §2 exists specifically to replace that
false belief with an accurate one, in the one place someone would form it.

### 1.4 A separate, real gap found in passing (flagged, not fixed here)

The **only** live component asking any of the eight scored questions this
editor authors is `gtmAssessmentQuestionnaire`. Searching every
`.html`/`.js`/`.cmp` for a reference to it (outside its own folder) finds
exactly one hit: the `GTM_Assessment_Guest` permission set. It is not
embedded in `gtmConfigurator` or anywhere else. Its only route is
`force-app/main/default/experiences/GTM_Accelerator1/routes/assessment.json`
→ `.../views/assessment.json` (`componentName: c:gtmAssessmentQuestionnaire`).

Confirmed live in `gtm-dev` (`sf data query ... FROM Network`):

| Network | Status |
|---|---|
| GTM (GTM1, `/gtm`) | **Live** |
| GTM Accelerator (GTM_Accelerator1) | **DownForMaintenance** |

The live site's booking modal is `gtmConfigBooking`
(`gtmConfigurator.html:490-503`) — a flat contact-info form with a
**hardcoded** `PLATFORMS` array (`gtmConfigBooking.js:39-48`, not sourced
from `GTM_Migration_Platform__mdt`/`getPlatforms()`) and, critically, **no
`answers` field in its submit payload at all**
(`gtmConfigBooking.js:348-374`). `GtmAssessmentRequestController` still
resolves and records a pack (`Instrument_Pair__c`) for whatever
`currentPlatform`/`targetPlatform` the rep-defaulted dropdown carries, but
`GtmAssessmentScoring.score()` runs against an empty answer map, so
`hasAnswers` is false (`GtmAssessmentScoring.cls:319`) and no real score or
tier is produced from a live GTM1 submission today.

This is the same class of issue as backlog D9 (Industry Chooser, route only
built on the decommissioned site), just a different route, and it is not
logged anywhere yet — `docs/runbooks/assessment-instrument.md:54` still
describes `gtmAssessmentQuestionnaire` as simply "guest-accessible,
`/assessment` on the Experience Cloud site" with no reachability caveat.
**Not addressed by this plan** — it's a live-flow/routing gap, not an
Instrument Editor legibility gap, and fixing it (rebuilding the `/assessment`
route on GTM1, or rewiring `gtmConfigBooking` to the real questionnaire) is
a materially bigger change than this workstream's brief. Flagged here so the
person reading this plan sees it before assuming the orientation copy below
is describing a fully-live path — the copy in §2 says so explicitly rather
than implying otherwise.

---

## 2. Orientation design for the Instrument Editor screen

Principle: this stays copy + a small amount of new template/JS, reusing
fields the `Pack` response already serializes (`resolutionChain`,
`resolutionNote`, `pairKey`, `version`) rather than inventing new Apex or a
new Instrument↔Offering relationship. No new custom metadata, no new
`@AuraEnabled` methods.

### 2.1 New: a persistent orientation panel

Insert directly after `</header>` (before the `error`/`loading` templates),
in `gtmInstrumentAuthor.html`:

```html
<template if:false={orientationCollapsed}>
  <div class="ia-orient">
    <p class="ia-orient-line">
      <strong>What this is:</strong> the eight scored questions a prospect
      answers for the <strong>{offeringLabel}</strong> assessment, and the
      branches and per-option scoring that adapt them by source and target
      platform.
    </p>
    <p class="ia-orient-line">
      <strong>What "Any source / Any target" means:</strong> the base pack —
      every pair falls back to this when nothing more specific overrides it.
      It's the right view for auditing the whole instrument, but it is
      <em>not</em> what any real prospect is asked. Pick a pair above to see
      exactly what that pair's respondent sees.
    </p>
    <p class="ia-orient-line">
      <strong>How a pack gets chosen for a real submission:</strong> the
      prospect names their own source and target platform as the first
      question of the assessment itself — nothing a rep sets earlier
      carries into it. That answer resolves live, and is re-resolved,
      independently, on the server when they submit — never trusted from
      the browser. There is currently no field in the engagement-link
      customizer for a rep to set this per client.
    </p>
    <template if:true={reachabilityCaveat}>
      <p class="ia-orient-line ia-orient-warn">
        <strong>Heads up:</strong> {reachabilityCaveat}
      </p>
    </template>
    <button type="button" class="ia-orient-dismiss" onclick={handleToggleOrientation}>
      Got it — hide this
    </button>
  </div>
</template>
<template if:true={orientationCollapsed}>
  <button type="button" class="ia-orient-reopen" onclick={handleToggleOrientation}>
    What is this screen? · {pairSummaryLabel}
  </button>
</template>
```

`gtmInstrumentAuthor.js` additions:

```js
const ORIENTATION_KEY = 'gtmInstrumentAuthor.orientationCollapsed';

@track orientationCollapsed = false;

// In connectedCallback, alongside the existing try/catch:
try {
    this.orientationCollapsed = window.localStorage.getItem(ORIENTATION_KEY) === '1';
} catch (e) {
    // Private browsing / storage blocked — default to shown.
}

handleToggleOrientation() {
    this.orientationCollapsed = !this.orientationCollapsed;
    try {
        window.localStorage.setItem(ORIENTATION_KEY, this.orientationCollapsed ? '1' : '0');
    } catch (e) {
        // Non-persistent this session; not worth failing over.
    }
}

get offeringLabel() {
    // No offering registry lookup exists on this screen today, and adding
    // one is out of proportion to this fix — the raw key is honest and
    // still answers "what offering is this" better than nothing.
    return this.offeringKey || 'migration-accelerator';
}

get pairSummaryLabel() {
    if (!this.pack) return '';
    const src = this.sourceKey ? this.labelForKey(this.sourceKey) : 'Any source';
    const tgt = this.targetKey ? this.labelForKey(this.targetKey) : 'Any target';
    return `${src} → ${tgt}`;
}

labelForKey(key) {
    const hit = this.platforms.find((p) => p.key === key);
    return hit ? hit.label : key;
}

/**
 * Static by design — this screen has no way to check live Network.Status
 * from Apex without adding a new privileged method, which is out of
 * proportion to an orientation fix. Kept as one line so it's cheap to
 * delete the day gtmConfigBooking is rewired onto the real questionnaire,
 * or the /assessment route is rebuilt on GTM1 — search this file for
 * "reachabilityCaveat" when that happens.
 */
get reachabilityCaveat() {
    return 'the guest questionnaire that asks these questions live only on '
        + 'the GTM Accelerator site, which is currently down for '
        + 'maintenance. The live GTM1 site’s booking form does not yet '
        + 'ask these questions, so editing a pack here does not change what '
        + 'a real prospect sees today.';
}
```

### 2.2 Resolution chain, made visible next to the existing pack tag

The header already shows `pack: {pairKey} · v{version}`
(`gtmInstrumentAuthor.html:24-26`). Extend it to show the chain that
produced it and the undecided-target note when present, both already on the
`Pack` response and currently unused by this component:

```html
<template if:true={pack}>
    <span class="ia-pack">pack: {pack.pairKey} · v{pack.version}</span>
    <template if:true={resolutionChainLabel}>
        <span class="ia-chain" title="Least specific first; the last one shown is what actually won.">
            resolved via {resolutionChainLabel}
        </span>
    </template>
    <template if:true={pack.resolutionNote}>
        <span class="ia-chain ia-chain--note">{pack.resolutionNote}</span>
    </template>
</template>
```

```js
get resolutionChainLabel() {
    const chain = this.pack && this.pack.resolutionChain;
    return chain && chain.length ? chain.join(' → ') : '';
}
```

`pack.resolutionNote` already carries `UNDECIDED_TARGET_NOTE`
(`GtmAssessmentInstrument.cls:99-103`) verbatim when target is blank — this
was computed server-side and simply never surfaced by the component before.

### 2.3 CSS

Add to `gtmInstrumentAuthor.css`, matching the existing SLDS-flavoured,
non-branded chrome (`#f3f3f3`/`#181818`, 13px, no PS accent color per the
file's own header comment):

```css
.ia-orient {
    background: #fff9e6;
    border-bottom: 1px solid #e8d98a;
    padding: 0.6rem 0.9rem;
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    font-size: 12.5px;
    line-height: 1.45;
    color: #3a3a2a;
}
.ia-orient-line { margin: 0; }
.ia-orient-warn { color: #7a4b00; }
.ia-orient-dismiss, .ia-orient-reopen {
    align-self: flex-start;
    font: inherit; font-size: 11.5px;
    background: none; border: 1px solid #c9b968; border-radius: 4px;
    padding: 0.15rem 0.5rem; color: #5a4a00; cursor: pointer;
}
.ia-orient-reopen {
    margin: 0; border-radius: 0; border: none; border-bottom: 1px solid #e5e5e5;
    background: #fafaf3; padding: 0.35rem 0.9rem; text-align: left; color: #6b5d1f;
}
.ia-chain {
    font-size: 11px; color: #747474;
}
.ia-chain--note { color: #8a6d00; }
```

### 2.4 Explicitly not changed

- No new relationship between `GTM_Assessment_Pair__mdt` and any Offering
  object — §1 found no real disconnect that would justify one.
- No change to `GtmMigrationPairs.cls`, `GtmAssessmentInstrument.cls`, or
  any `.mdt` metadata.
- No change to `gtmConfigWizard`, `gtmConfigurator`, `gtmConfigBooking`, or
  the Experience Cloud routes — those are the §1.4 finding, out of scope
  here.

---

## 3. QA checklist

### Apex-verifiable (run via `sf apex run test` / anonymous Apex against `gtm-dev`, no browser needed)

- [ ] `GtmAssessmentInstrumentTest` and `GtmMigrationPairsTest` still pass
      unmodified — this plan touches no Apex, so a red run here means
      something else regressed, not this change.
- [ ] Confirm the two-table split holds: `GTM_Migration_Pair__mdt` count vs
      `GTM_Assessment_Pair__mdt` count are independent
      (`sf data query --query "SELECT COUNT() FROM GTM_Migration_Pair__mdt"`
      and the same for `GTM_Assessment_Pair__mdt` — expect them to differ;
      if they're ever forced equal by a future change that'd suggest
      someone collapsed the two tables, which would invalidate §1.1).
- [ ] Anonymous Apex: call
      `GtmAssessmentInstrument.getPack('Eloqua', 'Salesforce Marketing Cloud')`
      (or whatever pair has authored overrides today) and confirm
      `resolutionChain` is non-empty and `pairKey` is not `'base'` — this is
      what `resolutionChainLabel` in §2.2 renders, so an empty chain there
      would mean the new UI silently shows nothing instead of the intended
      breadcrumb.
- [ ] Anonymous Apex: call `getPack(null, null)` and confirm
      `resolutionNote` is the `UNDECIDED_TARGET_NOTE` string
      (`GtmAssessmentInstrument.cls:99-103`) — confirms the note text §2.2
      surfaces actually exists on the base/Any-Any pack, matching the
      screenshot's default state.
- [ ] Confirm `GTM_Assessment_Guest` and any Config-Manager-facing
      permission set already grant read access to
      `GTM_Assessment_Pair__mdt`/`GTM_Assessment_Dimension_Override__mdt`
      fields this plan reads (`resolutionChain`, `resolutionNote`) — no new
      fields are added, so this should already be true, but confirm rather
      than assume per CLAUDE.md §5.1.

### UI-only — requires a browser, not verifiable from this session

- [ ] Load the Instrument Editor tab cold and confirm the orientation panel
      renders expanded by default (first visit, no localStorage entry yet).
- [ ] Dismiss it, reload the tab, confirm it stays collapsed (localStorage
      round-trip) and the reopen button shows the correct
      `{pairSummaryLabel}` for whatever pair is selected.
- [ ] Switch source/target via the existing pickers and confirm
      `ia-chain`/`resolutionChainLabel` updates to the newly resolved
      chain, and disappears/changes appropriately back to the
      undecided-target note when target is reset to "Any target."
- [ ] Visual check: the new banner doesn't crowd the existing
      `.ia-bar` pickers/tabs at narrow widths (the bar already
      `flex-wrap: wrap`s — confirm the banner sits cleanly below it rather
      than overlapping).
- [ ] Confirm the reachability caveat text is legible and not mistaken for
      an error (`.ia-orient-warn` should read as a note, not a failure,
      distinct from the existing `.ia-error` styling already in the file).
- [ ] Accessibility pass: dismiss/reopen buttons are reachable by keyboard
      and have accessible names (button text alone should suffice here,
      but confirm with a screen reader or axe pass).

### Explicitly not this QA pass's job

- The §1.4 finding (live GTM1 booking flow not asking scored questions) is
  informational, not something this change fixes — QA should confirm it
  is accurately described, not that it's resolved. If GTM_Accelerator1's
  `Network.Status` or `gtmConfigBooking`'s payload has changed since this
  was written, the `reachabilityCaveat` string in §2.1 is now stale and
  should be updated or removed, not left contradicting reality.
