# "+ New offering" create flow — bug plan

**Author:** Architect agent (session `session_018UJzwgTCCMdESELzYMeWAZ`)
**Date:** 2026-09-07
**Status:** For Dev implementation, then QA verification against this plan and the live `gtm-dev` org. This is an implementation spec, not the code — Dev still has to write it.

---

## 0. What actually happened, restated precisely

PO clicked "+ New offering" on the **GTM Content Manager Home** tab (`gtmContentHome`), named it "My Test Offering". The page hung on a spinner forever, with an uncaught client-side `TypeError` in a minified platform bundle (`et.reportAllChanges` / `n.timeout` — no app frames, no source map). A hard refresh afterward showed the offering *had* been created server-side: `GTM_Page_Section__c`/`GTM_Page_Content__c` rows existed, keyed `my-test-offering`, Offerings Listing pre-built with 1 section. Landing on that offering's editor afterward, the offering-selector combobox still read the placeholder "Choose an offering" instead of showing the new offering selected, and there was no guidance on what to build next.

Two independent, root-caused bugs, both in `force-app/main/default/`:

1. **Client-side create flow wedges itself** — `gtmContentHome.js`'s `handleCreateOffering()`.
2. **The editor's offering list doesn't know about page-only offerings** — `GtmPageContentController.getOfferings()`.

Plus one orientation gap the PO called out that isn't a "bug" so much as missing UX: no next-step guidance after landing.

---

## 1. What "offering" means at creation time (per task item 3)

Confirmed by reading `createOffering()` (`GtmPageContentController.cls:456-517`): it **never touches `GTM_Offering__mdt`**. It only:
- Inserts one `GTM_Page_Section__c` (the `offerings-listing` "tile" section, `Section_Address__c = <key>::offerings-listing::tile`).
- Inserts three `GTM_Page_Content__c` rows under that section (`name`, `mark`, `description`).

A `grep -rln "Metadata.DeployContainer\|Metadata.Operations\|CustomMetadata" force-app/main/default/classes/*.cls` across the whole class directory returns **nothing** — no code anywhere in this repo enqueues a Metadata API deploy for `GTM_Offering__mdt`. The doc comment above `createOffering()` ("the metadata row is enqueued for the site path") is aspirational, not actual: nothing enqueues it. A `GTM_Offering__mdt` record for this offering (which is what would carry `Site_Path__c`, i.e. the public site URL) only ever gets created if a human adds one later via Setup/metadata deploy. This is correct as far as it goes — CMDT can't be inserted via runtime DML, and the app is right not to try — but it means "an offering," at creation time, is **only** the `GTM_Page_Section__c`/`GTM_Page_Content__c` rows. This is exactly the fact that both bugs below turn on: some server code (`getHomeSummary`) already knows how to treat that as a real offering, and some (`getOfferings`) doesn't.

This is a pre-existing, intentional gap (no auto-CMDT-deploy), not something this plan proposes fixing — it's out of scope. Flagging it here only because the task asked whether the flow does something Salesforce natively supports well: it does, by design (page-record-only offerings, not CMDT inserts), but the two read paths need to agree that a page-record-only offering counts.

---

## 2. Bug 1 — client-side create flow (the stuck spinner + console TypeError)

**File:** `force-app/main/default/lwc/gtmContentHome/gtmContentHome.js`
**Method:** `handleCreateOffering()`, lines 275-291:

```js
handleCreateOffering() {
    const name = (this.newOfferingName || '').trim();
    if (!name) return;
    this.isLoading = true;
    createOffering({ name })
        .then((key) => {
            this.newOfferingOpen = false;
            this.newOfferingName = '';
            this.openEditor(key, 'offerings-listing');
        })
        .catch((err) => {
            this.loadError = this.messageFrom(err) || 'The offering could not be created.';
            this.isLoading = false;
        });
}
```

### 2.1 The deterministic part: `isLoading` never clears on success

`isLoading` is set `true` at line 278. It is reset to `false` **only inside `.catch()`** (line 289). The success `.then()` (lines 280-286) never resets it. The spinner (`gtmContentHome.html:31-32`, `<template if:true={isLoading}><lightning-spinner ...>`) is bound directly to that flag — so on the success path it is *guaranteed* to spin forever regardless of what navigation does afterward. This alone fully explains "the page hung on a loading spinner indefinitely," independent of the console error.

Compare the two other async-then-navigate handlers in the same file, both of which get this right:
- `load()` (lines 55-68): `.finally(() => { this.isLoading = false; })`.
- `handleGoToPage()` (lines 328-345): `.finally(() => { this.isLoading = false; })`.

`handleCreateOffering()` is the one place in this file missing the `.finally()`.

### 2.2 The likely trigger for the console TypeError

Also compare `handleGoToPage()`'s shape to `handleCreateOffering()`'s more closely — it's the app's own working precedent for "create something, then navigate to it":

```js
// handleGoToPage(), lines 328-345
handleGoToPage() {
    if (this.npDisabled) return;
    const offeringKey = this.npOffering;
    const templateType = this.npTemplate;
    this.newPageOpen = false;              // <- modal-closing write happens HERE,
                                            //    synchronously, before the async call starts
    if (this.npIsExisting) {
        this.openEditor(offeringKey, templateType);
        return;
    }
    this.isLoading = true;
    createPage({ offeringKey, templateType, sections: starterFor(templateType) })
        .then(() => { this.openEditor(offeringKey, templateType); })   // <- navigate is the ONLY
        .catch((err) => { ... })                                       //    thing in this .then()
        .finally(() => { this.isLoading = false; });
}
```

In `handleGoToPage()`, the modal-closing reactive write is separated from the navigation call by an entire async gap (the Apex round-trip). In `handleCreateOffering()`, by contrast, **two reactive property writes and a `NavigationMixin.Navigate` dispatch are batched together in the same microtask**, immediately after the Apex promise resolves — `newOfferingOpen = false` (closes/unmounts the modal, `gtmContentHome.html:196`), `newOfferingName = ''`, then synchronously `this.openEditor(key, ...)` → `this[NavigationMixin.Navigate](...)` (`gtmContentHome.js:349-357`), all while the component is mid-rerender from the first two writes.

The console stack (`et.reportAllChanges`, called from `n.timeout` — a `setTimeout` callback, no app frames, minified Aura/LWS instrumentation) is consistent with Lightning's own render/interaction telemetry losing track of a component's timing marks when a batch of reactive writes and a page-navigation dispatch land in the same tick. It is **not** something our `.then()/.catch()` chain could ever catch even today — a synchronous throw inside `.then()` would flow into the trailing `.catch()`, but this fires later, off a `setTimeout`, in a separate stack. That also explains why the modal never showed an error: the exception is real but unreachable from app code.

We cannot fully prove the platform mechanism (it's uninstrumented, minified Salesforce-owned code) — but the fix below doesn't depend on proving it. It defensively fixes the guaranteed bug (2.1) and removes the same-tick batching that is the one concrete difference between this handler and the codebase's own working pattern (2.2), which is the standard, low-risk way to defuse a render/navigation race without needing to root-cause a vendor bundle.

### 2.3 Fix — `handleCreateOffering()`

```js
import { ShowToastEvent } from 'lightning/platformShowToastEvent'; // add to imports, top of file

handleCreateOffering() {
    const name = (this.newOfferingName || '').trim();
    if (!name) return;
    this.isLoading = true;
    createOffering({ name })
        .then((key) => {
            this.newOfferingOpen = false;
            this.newOfferingName = '';
            this.dispatchEvent(new ShowToastEvent({
                title: 'Offering created',
                message: `"${name}" is ready. Its Offerings Listing page already has a starting section.`,
                variant: 'success'
            }));
            // Let this render settle before firing NavigationMixin — see plan
            // §2.2: batching the modal-close writes and the navigate dispatch
            // in the same tick is the one concrete difference from the
            // working handleGoToPage() pattern this mirrors.
            return Promise.resolve().then(() => this.openEditor(key, 'offerings-listing', /* isNew */ true));
        })
        .catch((err) => {
            this.loadError = this.messageFrom(err) || 'The offering could not be created.';
        })
        .finally(() => { this.isLoading = false; });
}
```

Notes for Dev:
- The toast fires **before** navigation, so the user gets confirmation the create worked even if the deferred navigation has any further hiccup — satisfies "give clear success feedback... not requiring a manual hard refresh."
- `.finally()` now unconditionally clears `isLoading`, on both branches — this alone fixes the literal stuck-spinner symptom regardless of the navigation theory.
- `openEditor` gains a third param (`isNew`) — see §4, this is what drives the orientation banner.
- Do not also set `isLoading = false` inside `.catch()` anymore (redundant now that `.finally()` covers it) — keep the diff minimal, one place clears it.

---

## 3. Bug 2 — offering-selector dropdown doesn't pre-select the new offering

**File:** `force-app/main/default/classes/GtmPageContentController.cls`
**Method:** `getOfferings()`, lines 212-235:

```apex
@AuraEnabled(cacheable=true)
public static List<OfferingOption> getOfferings() {
    List<OfferingOption> out = new List<OfferingOption>();
    ...
    for (GTM_Offering__mdt off : [
        SELECT Offering_Key__c, Label__c, Site_Path__c FROM GTM_Offering__mdt
        ORDER BY Label__c ASC
    ]) { ... }
    return out;
}
```

This queries `GTM_Offering__mdt` **only**. Per §1, a freshly created offering has no `GTM_Offering__mdt` record — so `getOfferings()` never returns it.

`gtmContentManager.js` calls `getOfferings()` imperatively in `connectedCallback()` (line 147), and its `offeringOptions` getter (lines 181-183) maps the result straight into the combobox's `options`. Even though `selectedOffering` gets correctly set to the new key (via `_requestedOffering` from the nav state, `connectedCallback` lines 152-157), the combobox (`gtmContentManager.html:12-20`) has `value={selectedOffering}` with `options={offeringOptions}` — when `value` doesn't match any entry in `options`, `lightning-combobox` falls back to its `placeholder="Choose an offering"`. That is the exact behavior reported.

**This codebase already solved this exact problem once.** `getHomeSummary()` (same class, lines 352-444) — the method that powers the Home tab where the offering *does* show up correctly — has a "discovered offering" fallback (lines 381-393) with its own comment explaining precisely this scenario:

> "An offering that has pages but no metadata row yet is a real offering: custom metadata only deploys asynchronously, so one created a moment ago would otherwise vanish from its own app until the deployment landed."

`getOfferings()` has no equivalent. That asymmetry — one read path (`getHomeSummary`) treats page-only offerings as real, the other (`getOfferings`) doesn't — is the actual root cause, and it isn't specific to the dropdown: `getOfferings()` is the only offering-list source for the entire Content Manager editor (confirmed: it's the only caller, `grep -rn getOfferings force-app/main/default/lwc` returns only `gtmContentManager.js`), so anything else keyed off that list (templates, page counts inside the editor) is quietly working around a list that's missing the offering the whole tab was just navigated to.

### 3.1 Fix — port the discovered-offering fallback into `getOfferings()`

Add, after the existing `GTM_Offering__mdt` loop and before `return out;`:

```apex
Set<String> known = new Set<String>();
for (OfferingOption o : out) known.add(o.offeringKey);

for (AggregateResult ar : [
    SELECT Offering_Key__c o FROM GTM_Page_Section__c
    WHERE Active__c = true GROUP BY Offering_Key__c
]) {
    String key = (String) ar.get('o');
    if (known.contains(key)) continue;
    OfferingOption o = new OfferingOption();
    o.offeringKey = key;
    o.label       = key;      // same fallback-to-key convention getHomeSummary uses
    o.publicUrl   = '';       // no Site_Path__c exists yet — leave blank, don't fabricate one
    out.add(o);
    known.add(key);
}
```

Notes for Dev:
- Match `getHomeSummary()`'s dedupe-by-key pattern (its `byKey` map) so an offering that has **both** a CMDT record and page rows appears once, not twice.
- Consider whether the "discovered" branch's label should later also read the offerings-listing `name` content row the way `getHomeSummary()` does (lines 426-436, the "the name an offering goes by is the name on the tile" loop) for full parity — not required to fix this bug (the combobox will still show a readable label, just the raw key rather than the display name, until a `GTM_Offering__mdt` record exists), but flag it as a nice-to-have so the two methods don't drift further apart. Don't scope-creep this into the current fix unless it's trivial to add alongside.
- `getOfferings()` is called **imperatively** (`gtmContentManager.js:147`, a plain function call, not `@wire`) — `cacheable=true` governs `@wire`/offline caching behavior, not this imperative call path, so this fix should not be blocked by stale client caching. QA should still verify a fresh navigation shows the new offering without a hard refresh (checklist §6.3) since this is exactly the symptom being fixed.

---

## 4. Orientation guidance (task item 2c)

PO's words: *"it also just lands the person here but they don't know what they need to build."* Per the task, "even a simple 'Start with your Story page' prompt beats silence" is sufficient — keep this lightweight, don't redesign the landing flow.

`gtmPageLayouts.js:374` — `OFFERING_TEMPLATES = ['story', 'configurator', 'offerings-listing']` — confirms `story` is the first/primary page for a normal offering, so "Story page" is the right, codebase-consistent thing to point at next.

### 4.1 Plumb a "just created" flag through navigation

`gtmContentHome.js` — `openEditor()` (lines 349-357):

```js
openEditor(offeringKey, templateType, isNew) {
    const state = { c__offering: offeringKey };
    if (templateType) state.c__template = templateType;
    if (isNew) state.c__new = '1';
    this[NavigationMixin.Navigate]({
        type: 'standard__navItemPage',
        attributes: { apiName: 'GTM_Content_Manager' },
        state
    });
}
```

(Called with `isNew = true` only from `handleCreateOffering()`, per §2.3 — every other caller of `openEditor` is unaffected, `isNew` defaults falsy.)

### 4.2 Capture and surface it in `gtmContentManager.js`

`@wire(CurrentPageReference) capturePageRef(ref)` (lines 115-131) already reads `ref.state.c__offering`/`c__template`. Add:

```js
const isNew = ref.state.c__new === '1';
...
this._requestedOffering = offering;
this._requestedTemplate = template;
if (isNew) this.isNewOffering = true;
```

Add a `@track isNewOffering = false;` field and a dismiss handler:

```js
handleDismissNewOfferingHint() { this.isNewOffering = false; }
```

### 4.3 Banner markup

`gtmContentManager.html`, right after the existing `gcm-error` block (after line 102, before the `isLoading` spinner block):

```html
<template if:true={isNewOffering}>
  <div class="gcm-hint" role="status">
    <lightning-icon icon-name="utility:success" size="x-small" variant="success"></lightning-icon>
    <span>Offering created. Its Offerings Listing page already has a starting section — start with the <b>Story</b> page next to give it a front door.</span>
    <button class="gcm-hint-x" onclick={handleDismissNewOfferingHint} title="Dismiss" aria-label="Dismiss">&times;</button>
  </div>
</template>
```

`gtmContentManager.css`: add `.gcm-hint`/`.gcm-hint-x` — reuse the existing `.gcm-error` box model (padding/border-radius/icon-gap) with a success color token instead of the warning one, so it reads as "good news," not an error.

Notes for Dev:
- This is a **one-time** nudge tied to the creation event, not a persistent "you haven't built Story yet" banner — it should go away on dismiss and should **not** reappear on a later, unrelated navigation back to the same offering (e.g., switching away via the dropdown and back). Since `isNewOffering` is only ever set `true` by the `c__new=1` state key, and `capturePageRef` only reacts when `ref.state` actually changes (`gtmContentManager.js:120`, the early-return guard), a later navigation to the same offering *without* `c__new` in the state won't re-trigger it — confirm this holds in QA (§6.5) rather than assuming.
- A "Go to Story" action button is a nice-to-have, not required — the task's own bar is "a simple prompt beats silence." Skip it if it adds meaningful complexity to the deferred-navigation change in §2.3; the text alone satisfies the requirement.

---

## 5. Permission sets / FLS (CLAUDE.md §5.1 check)

No new object, field, or tab is introduced by this fix — `c__new` is a navigation state key (client-side only, like the existing `c__offering`/`c__template`), not a schema change; the Apex change is a new query inside an existing method. **No permission-set changes should be required.** QA should still confirm this holds (checklist §6.10) rather than take it on faith, per the repo's own standing instruction that this gap has bitten the project multiple times.

---

## 6. QA verification checklist

1. **Reproduce the original bug first**, against the pre-fix code (or note if this step is being run post-merge, skip to step 2): on the GTM Content Manager Home tab, click "+ New offering," type a unique name (e.g. "QA Repro Offering"), submit. Confirm: page spins forever, devtools console shows an uncaught `TypeError: Cannot read properties of undefined (reading 'startTime')` from a minified bundle. Hard-refresh the tab; confirm the offering *did* get created (appears on Home with 1 built page, Offerings Listing).
2. **Post-fix, repeat the same create action:**
   a. Spinner clears within a normal Apex round-trip — no hang.
   b. No uncaught exception appears in the console during the create → navigate transition.
   c. A success toast appears confirming creation, before/without needing a hard refresh.
   d. The app lands automatically on the new offering's Offerings Listing editor (no manual click needed).
3. **Dropdown pre-selection:** immediately after landing (no refresh), the offering-selector combobox at the top of `gtmContentManager` shows the new offering's name/key selected — not the "Choose an offering" placeholder.
4. **Hard-refresh survival:** fully reload the browser tab (not an SPA nav) on the same URL. Confirm the dropdown *still* shows the new offering selected, and the Offerings Listing page still shows its 1 pre-built section — state must be correct with or without a refresh, matching what the PO originally observed server-side only after refreshing.
5. **Guidance banner:** confirm the "start with your Story page" hint appears on first landing; dismiss it; navigate away (e.g., pick a different offering) and back to the same offering via the dropdown — confirm the hint does **not** reappear (it's a one-time creation nudge, not persistent).
6. **Regression — existing working flow:** `handleGoToPage()` / "New page for this offering" (`handleNewPageFor`) still behaves exactly as before — this is the pattern §2.3 mirrors; must not be touched or broken.
7. **Regression — rename:** `handleSaveRename()` still works; confirm the new `ShowToastEvent` import/toast in `handleCreateOffering()` doesn't collide with or affect the rename path.
8. **Duplicate-name failure path:** create an offering whose slugged key collides with an existing one. Confirm the Apex `AuraHandledException` ("An offering called "..." already exists.") still surfaces via `loadError` in the modal, and `isLoading` still clears (via `.finally()`) on this failure branch too — not just on success.
9. **`getOfferings()` fix — no dupes, no regression:** an offering that has *both* a `GTM_Offering__mdt` record and page rows appears exactly once in the dropdown, not twice. An org with only CMDT-backed offerings (no page-only ones) shows the same list as before the fix.
10. **Permission sets:** confirm no permission-set edits were needed/made for this change (§5) — sanity check against `force-app/main/default/permissionsets/`.
11. **Deploy validation:**
    ```
    sf project deploy start --source-dir force-app/main/default/classes --source-dir force-app/main/default/lwc --target-org gtm-dev --dry-run
    ./scripts/deploy.sh gtm-dev --run-tests
    python3 scripts/check-references.py
    ```
    All clean.
12. **Tests:** `npm test` green. If Dev adds/updates a Jest test for `handleCreateOffering` (isLoading resets on both success and failure) or an Apex test for `getOfferings()`'s discovered-offering fallback, confirm they're present and passing — not required to already exist, but called out here so it isn't silently skipped.
