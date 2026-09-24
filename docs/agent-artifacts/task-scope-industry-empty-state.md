# TASK SCOPE — ISSUE #industry-empty-state

## 1. Requirements Breakdown

- **Target Objective:** On a blank install the public page `/gtm/s/choose-industry` shows "The industry list could not be loaded. Please retry." That is false: nothing failed, no industries have been entered yet. Make the page tell EMPTY apart from FAILED. Empty (a normal state on a new install) shows a calm, true message and keeps the working "Continue without one" / skip tile. The retry message stays for real failures only. The user decided industries are content an admin ENTERS in-app (Content Manager > Framework > Industry Chooser page), never seeded; default/first-run things belong in a setup portion of the app.
- **System Component Impacted:** LWC only. `force-app/main/default/lwc/chooseIndustry/` (`chooseIndustry.js`, `chooseIndustry.html`, optionally `chooseIndustry.css`, and `__tests__/chooseIndustry.test.js`). **No Apex, no metadata, no Experience site JSON change.**

### Verified against origin/main (fetched at scope time)

- `chooseIndustry.js` `connectedCallback` (~lines 227-242): the `.then` of `getIndustryProfiles({ offeringKey: FRAMEWORK_KEY, templateType })` sets `_industries = []` and `_loadError = 'The industry list could not be loaded. Please retry.'` when `rows` is empty, the identical string to the `.catch` branch. This is the bug. Confirmed.
- `chooseIndustry.html` renders `_loadError` in a `role="status"` `.load-error` div at the top of the page. The skip tile ("Skip for now" / "Continue without one →") is always rendered, so the escape hatch already works.
- The existing Jest test `renders zero tile-wrap elements and a load-error on an empty result` (`chooseIndustry.test.js` ~line 167) ENCODES the bug: it asserts `.load-error` is present for an empty result. It must be changed, not just added to.
- Apex `GtmPageContentReader.getIndustryProfiles` returns an empty list (no exception) when no active `GTM_Page_Content__c` rows match. So empty vs failed is distinguishable purely client-side: resolved `[]` / null vs rejected promise. No Apex change needed.
- Secondary quirk to be aware of: the `getPageLayout` `.catch` in the same method also assigns `_loadError` (a different message), so two failures can overwrite each other. Not part of this fix; the new empty state must use its OWN state field so it cannot collide with `_loadError`.

### Recommended smallest fix

1. Add a separate tracked flag (e.g. `_industriesEmpty`), set true only in the resolved-empty branch. Leave `_loadError` unset there.
2. In the HTML, render a distinct, non-error notice when `_industriesEmpty` is true (use a neutral class, not `.load-error`, so it is not styled as an error). Keep `role="status"`.
3. Leave the `.catch` branch and its retry wording exactly as-is (real failure).
4. Keep the skip tile untouched.
5. Do not show the empty notice in preview mode (the early `return` on `_preview` already precedes the fetch; keep it that way).

### Wording and audience

Audience check: project memory says the offering/industry chooser is internal rep tooling, not prospect-facing. However the page is served on the public Experience site and the GTM_Guest fix exists so it loads unauthenticated, so the wording must make sense to a guest and must NOT instruct an admin inside a public page. Suggested copy (Architect may polish): "No industries have been set up yet, so you can continue without one." Avoid "contact your admin", "go to Content Manager", "retry", and "error". Open question 1 covers whether the Skip tile copy ("Start from the generic version and pick an industry later...") still reads well beside the notice (it should).

### Relationship to the setup work (no scope overlap)

The user's larger point (admin enters industries in-app; setup surfaces what is missing) is owned by the parallel task `docs/agent-artifacts/task-scope-guided-setup.md` (branch `ba-scope/issue-guided-setup`). That checklist should list "Add at least one industry" with a link to Content Manager > Framework > Industry Chooser. THIS task must NOT seed any industries (no `data/seed/` rows, no Apex, no scripts) and must NOT add any setup UI. Coordination note: the Architect for guided-setup should be told that the empty-state text on `/choose-industry` is intentionally neutral and that the admin nudge lives in setup, not on the public page.

### Sibling surfaces audit (GtmPageContentReader callers and the offering chooser)

| Surface | Behaviour on empty vs failure | Misleads? |
|---|---|---|
| `offeringChooser` (`offeringChooser.js`/`.html`) | Tiles come from `getOfferingTiles`; a `.catch` only logs to console (no user message). Empty renders "No offerings are configured yet." via `hasNoTiles` in a `.load-error` div. A rejected `getOfferingTiles` leaves `_tiles` empty, so a real FAILURE also shows "No offerings are configured yet." (failure reported as empty: the inverse conflation). `getPageLayout` failure has its own separate message. | YES, mildly: failure is shown as "not configured", and the empty state is styled as an error. Different bundle from chooseIndustry and different Apex (`getOfferingTiles`). **Follow-up, not in this task.** |
| `gtmConfigWizard` | `getIndustryProfiles` empty becomes `[]`; failure only `console.warn`. No user-facing message. | No |
| `gtmConfigurator` | Empty ignored, failure only logs; uses built-in defaults. | No |
| `gtmSavedLinksBar` | Labels only; failure swallowed by design. | No |
| `gtmFaqPanel`, `gtmStory` (`getPageContent`/`getPageLayout`) | Fall back to built-in defaults; not reviewed in depth. | No misleading empty text found at scope time; Architect may spot-check |

Decision: fix ONLY `chooseIndustry`. The `offeringChooser` failure-shown-as-empty issue is a related but different bundle and different Apex call, so it is a listed follow-up (see Open Questions).

### Salesforce-first note

No native Salesforce component replaces a custom LWC on a public Aura Experience page whose content is CMS-driven; this change is a state-handling correction inside the existing component, not new custom functionality.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO. No GUS tool, no Apex, so the zero-DML rule in AGENTS.md §1 is not engaged (the fix is read-only display logic).
- [ ] Altering Custom Metadata? NO. No custom metadata, no `migration-accelerator/` or instrument YAML change.
- [ ] Introducing database fields? NO. No fields, objects or tabs, so no Permission Set mapping is needed. (Industry rows already live in `GTM_Page_Content__c`; the GTM_Guest read access already works.)

Files touched (expected, LWC and its Jest spec only):
- `force-app/main/default/lwc/chooseIndustry/chooseIndustry.js`
- `force-app/main/default/lwc/chooseIndustry/chooseIndustry.html`
- `force-app/main/default/lwc/chooseIndustry/chooseIndustry.css` (only if a neutral notice style is needed)
- `force-app/main/default/lwc/chooseIndustry/__tests__/chooseIndustry.test.js`

Confirmed NOT touched: any Apex class (an Apex deploy to production-type `gtm-dev` forces a full test run; keeping this LWC-only avoids that), `GtmPageContentReader`, permission sets, `force-app/main/default/experiences/`, `data/seed/`, `docs/architecture/` contracts (no contract changes; no Apex signature or data shape changes).

Deploy and publish:
- **Deploy target is `gtm-staging` only. `gtm-dev` is Production and is NOT a deploy target for this work.** No org IDs, usernames or secrets in any committed file.
- Experience republish after LWC deploy: UNVERIFIED. `CLAUDE.md` §5 says only changes under `experiences/` alter draft state and need `sf community publish`. This change touches no experience files, so a republish is expected NOT to be required, but on an Aura site LWC bundle updates can be served from cached/published site resources. QA should first load the page after deploy; if the old message persists, run `sf community publish -n "<site name>"` on gtm-staging and record the outcome so the answer becomes verified.
- Do not touch worktrees/branches of PRs #238, #239, #240, or the in-progress compact-filters and guided-setup work.

## 3. Plan Acceptance Criteria

- **Success Metric:** Checkable in a browser on the PUBLIC page `/gtm/s/choose-industry` on gtm-staging (QA must validate live, not only via Jest):
  1. Blank state (no active framework industry rows): page shows a calm notice that no industries have been set up yet and that the user can continue without one. It contains NO "retry", "could not be loaded" or "error" wording, and is not styled as an error.
  2. "Continue without one" is visible and works (navigates to the configurator, preserving `cfgId` and `?offering=` as today).
  3. With at least one active industry entered via Content Manager > Framework > Industry Chooser: tiles render, no empty notice, no error message. (Enter it via the UI on gtm-staging; do NOT seed.)
  4. A real failure (Jest-mocked rejection) still shows the retry message and zero tiles.
  5. Dependent surfaces unchanged: `/choose-offering`, the configurator, saved-links bar and site header still load; browser console shows no new errors.
  6. Guest/unauthenticated view checked, since the page is public.
- **Target Test Target:** LWC Jest spec `force-app/main/default/lwc/chooseIndustry/__tests__/chooseIndustry.test.js` (`npx jest force-app/main/default/lwc/chooseIndustry`, then full `npm test`). Changes required in the spec: (a) REWRITE the existing "empty result" test to assert the neutral empty notice is present, `.load-error` is absent, no retry text, and the skip tile is still rendered; (b) keep the rejection test asserting `.load-error` with the retry message; (c) add a test that the empty notice is absent when rows are returned. No Apex test class is applicable (no Apex change).

### Risks

- The old test encodes the buggy behaviour; forgetting to rewrite it will fail CI or, worse, get the assertion "fixed" back to the bug.
- Cached LWC on the Aura site may hide the fix after deploy (republish question above).
- Two error paths share `_loadError` (getPageLayout vs getIndustryProfiles); a late getPageLayout failure could overwrite the industries retry message. Pre-existing; keep the empty state on its own field.
- Wording that tells admins what to do would leak setup instructions to public guests; avoid.
- Deploy accidentally aimed at `gtm-dev` (Production). Not allowed for this work.

### Open Questions

1. Exact copy: is "No industries have been set up yet, so you can continue without one." acceptable, or does the user want different wording? (Wording is a product call; the Architect can finalise.)
2. Should the empty notice be styled as neutral info (recommended) or use the existing `.load-error` look? Recommendation: neutral.
3. Follow-up ticket for `offeringChooser`: a rejected `getOfferingTiles` currently shows "No offerings are configured yet." (failure displayed as empty) and the empty message uses the error style. Fix later as a separate, small task?
4. Guided-setup coordination: confirm the setup checklist task includes an "industries" item linking to Content Manager > Framework > Industry Chooser, since this task deliberately adds no admin guidance to the public page.
5. Republish requirement for LWC-only changes on this Aura site is unverified; QA to confirm on gtm-staging.

## 4. Architect Addendum

- Decisions: (1) copy approved: "No industries have been set up yet, so you can continue without one." shown as a neutral notice (no error styling, no retry wording, no admin instructions). (2) The `offeringChooser` failure-shown-as-empty conflation (rejected `getOfferingTiles` shows "No offerings are configured yet." styled as an error) is OUT OF SCOPE here and is a separate follow-up. (3) Confirmed: `ba-scope/issue-guided-setup` includes checklist row 13 "At least one industry added" deep-linking to Content Manager > Pages > Framework > Industry Chooser, and acceptance item 12 that covers this same public empty state. (4) Republish: probably not needed for an LWC-only change; QA confirms on gtm-staging and runs `sf community publish -n "GTM"` only if the old text persists, recording the outcome.
- Design: new `@track _industriesEmpty = false`, set true only in the resolved-empty branch (and false otherwise); `_loadError` is not set there. Neutral notice in `chooseIndustry.html` with `role="status"` and `aria-live="polite"` (never `role="alert"`); `.load-error` kept for real failures only; small `.empty-note` class in the CSS (neutral border, no warn colour). Skip tile untouched.
