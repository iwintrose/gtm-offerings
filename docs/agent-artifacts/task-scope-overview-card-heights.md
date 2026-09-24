# TASK SCOPE — ISSUE #overview-card-heights

## 1. Requirements Breakdown

- **Target Objective:** User requirement: "on the Overview page the sections without information have such big heights. They should grow with information and then cap at a limit that makes sense, not grow past that." Every Overview section must size to its CONTENT (empty state compact: card header plus the empty message), grow as rows arrive, and stop at a CAP after which the card body scrolls inside the card (the page never grows past the cap). Must hold side by side and stacked (<=1100px).
- **System Component Impacted:** LWC only: `force-app/main/default/lwc/gtmOverview/gtmOverview.css` (primary) and, only if needed, small edits to `gtmOverview.html`. The Home FlexiPage `GTM_Offerings_Home` and the old Overview tab both host this same component, so both are fixed together. No Apex, no Experience Cloud route, no YAML instrument.

### Verified current state (origin/main)

- `.ov-cols { --ov-row2-h: 470px; display:grid; grid-template-columns: 5fr 7fr; align-items: stretch }` and `.ov-row2-card { height: var(--ov-row2-h); min-height: 0; }`. Fixed height is applied to THREE cards, not two: funnel (`.ov-funnel-card`) and follow-up (`.ov-deals`) in Row 2 (html ~L109-169), and Assessment results (`.ov-results`, html ~L317) in Row 3, which reuses `.ov-cols` and `.ov-row2-card` (`.ov-row3` sets `align-items: start`, so Offerings `.ocard` tiles are already auto height and the results card is fixed beside them).
- The 1100px breakpoint only changes `grid-template-columns`; the fixed height is kept when stacked (deliberate, and asserted by a test).
- Funnel: `.ov-funnel-body` and `.fs-list` are flex columns with `min-height:0`; `.fs-row { flex: 1 1 0; min-height:0; max-height:92px }`. Rows divide the fixed height. With an auto-height parent, `flex-basis:0` rows collapse to nothing, so this MUST change.
- Scroll bodies: `.ov-deals-body` and `.ov-results-body` are `min-height:0; overflow-y:auto; padding-top:0` (also carry `slds-scrollable_y` in the html); `.ov-sticky` is `position:sticky; top:0` inside them.
- Other fixed-ish values in gtmOverview.css: `min-height: 3rem` (L25, L155) and `.ocard` `min-height: 4.5rem` (L400). These are small floors, not the problem.
- Salesforce-first evaluation: the cards are already `slds-card`; scroll bodies already use `slds-scrollable_y`. SLDS has no utility for "grow then cap" (`slds-scrollable_y` needs a bounded height; SLDS has no max-height utilities), so the smallest correct fix is a small custom CSS rule (max-height on a flex-column card) rather than JS measurement or a new component. Justified: no native list view/report replaces these bespoke dashboard cards.

### Recommended fix (smallest correct; for the Architect to confirm)

1. Rename semantics, not structure: keep one custom property but make it a CAP. `.ov-cols { --ov-row2-cap: 470px; }` (rename from `--ov-row2-h` so nobody reads it as a fixed height; single property still drives all three cards so they cannot diverge).
2. `.ov-row2-card { display:flex; flex-direction:column; height:auto; max-height: var(--ov-row2-cap); min-height:0; }` and the scroll bodies `flex: 1 1 auto; min-height:0; overflow-y:auto`. The card header (and the funnel's footer note) stay `flex: none`. Card shrinks to content when empty, grows with rows, and clamps at the cap with the body scrolling inside.
3. Side-by-side alignment: the grid keeps `align-items: stretch`. Grid track height = the taller item's content height (each clamped by `max-height`), and the shorter card stretches to match. Stretch still works with `max-height` on the items (max-height only clamps the used height; stretch is applied within it). So when the deals table has 10 rows and the funnel has 4, both cards are 470px; when both are short, both are the height of the taller one. No JS.
4. Funnel rows: replace `flex: 1 1 0; max-height: 92px` with a content-driven row: `flex: 0 0 auto; min-height: 56px` (propose 64px; Architect to confirm against the funnel-shape clip-path, which reads row height), keep `max-height` removal so rows do not stretch. 4 stages x ~64px plus header and note is well under the cap, so the funnel never needs to scroll at the cap in practice, but `.fs-list` should still get `overflow-y:auto` as a safety net. Empty funnel state (no `.fs-row` rendered, existing test) is just the empty message.
5. Row 3: Offerings stays auto height (`align-items:start`). Results card gets the same cap behaviour. Open question below on whether the two Row 3 cards should stretch to match when both have content.
6. Breakpoint: at <=1100px stacked, every card is independently content-sized up to the same cap (no fixed height retained). The existing rule "stacked keeps the shared fixed height" is intentionally reversed. Do not add a second breakpoint.

### Proposed values (per card; user to confirm)

| Card | Min (empty) | Cap |
|---|---|---|
| Funnel "From link to assessment" | header + empty message (~120px, natural) ; with 4 rows ~ natural (~350px) | 470px |
| Opportunities to follow up on | header + empty message (natural, ~120px) ; sticky column head + rows | 470px |
| Assessment results | header + empty message (natural) | 470px |
| Offerings tiles | natural (already auto), no cap requested | none |

At narrow widths (320/480/768) the cap should be `min(470px, 70vh)` so a short phone landscape viewport does not trap a 470px scroll region larger than the screen; Architect to decide whether `70vh` is wanted or plain 470px suffices (open question). No min-height beyond natural content, apart from the existing 3rem floors.

### Other fixed-height patterns found (fix only Overview here; follow-ups)

- gtmOverview.css: only the three `.ov-row2-card` uses above plus 3rem/4.5rem min-height floors (in scope or harmless).
- gtmContentHome.css (Content Manager Home): no fixed `height` and no `--...-h` custom property. Only `min-height: 100%` (L21), `.home-loading { min-height: 160px }` (L37; spinner container, acceptable), and `min-height: 4.5rem` (L100, L148 off-head). Nothing to fix; not a follow-up.
- Repo-wide grep of `height:` px values in other LWC css (chooseIndustry, gtmAgentBubble, gtmAnalytics `height:150px` L125, gtmConfigurator, gtmConfigWizard, gtmAssessmentQuestionnaire) shows only decorative bars/dots/avatars/inputs, except `gtmAnalytics.css:125 height:150px`, which is worth a follow-up glance (chart area; likely intended). Listed as a follow-up only, not touched.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? NO. No Apex or GUS tool change; zero-DML rule (AGENTS.md §1) not engaged.
- [ ] Altering Custom Metadata? NO. No custom metadata, no migration-accelerator/ YAML change.
- [ ] Introducing database fields? NO. No fields, objects or tabs; no permission-set impact (the 5 permission sets are untouched).

Also: LWC CSS (and possibly tiny html) only; no org IDs, usernames or secrets committed. `gtm-dev` is Production and NOT a deploy target for this work; `gtm-staging` is the test org. Do not touch the worktrees/branches of the in-progress compact-filters, add-industry and guided-setup work.

## 3. Plan Acceptance Criteria

- **Success Metric:** Verified live in a browser on gtm-staging (real input, the locked single tab), on BOTH the empty org and the org with the opt-in synthetic demo data loaded:
  1. Total height of the empty Home recorded before and after; after must drop substantially from the ~1934px baseline (empty state is roughly header + section headers + empty messages; the ~350px blank under "No links sent yet" is gone).
  2. For each of funnel, follow-up table and Assessment results, record the height with 0 rows, with N (a few) rows, and with many rows: 0 rows is compact; N rows grows; many rows stops at the cap (470px, or the agreed value) and the body scrolls inside the card while the page height stops growing.
  3. Side-by-side cards (Row 2, and Row 3 as agreed) have equal heights at 1101px and wider, both when one has more content and when both are empty; at <=1100px they stack, each content-sized and capped.
  4. Funnel stage rows neither collapse to zero nor stretch to fill; funnel shape (clip-path) renders correctly; stage rows still clickable and keyboard focusable.
  5. No clipped content, sticky column header still sits flush at the top of the scroll body and does not leave a gap rows scroll through.
  6. Checked at 320, 480, 768, 1078 and 1440px widths, on the Home FlexiPage (GTM_Offerings_Home) AND the old Overview tab route (same component).
  7. Dependent surfaces checked: Act today tiles, header actions, Offerings tiles, filter/wizard modals launched from Overview. Config wizard (`gtmConfigWizard.js` ~L358) measures its OWN host `getBoundingClientRect` for chrome offset; confirm launching it from Overview is unaffected by the shorter page (page height no longer fixed).
  8. `npm test` passes with updated specs; deploy pipeline `./scripts/deploy.sh gtm-staging --run-tests`; publish not needed (no Experience Cloud change).
- **Target Test Target:** Jest (`npm test`, sfdx-lwc-jest) specs under `force-app/main/default/lwc/gtmOverview/__tests__/`. Static-CSS assertions that WILL break and must be rewritten to the new cap semantics: `gtmOverview.funnel.test.js` ~L110-116 (asserts `--ov-row2-h: 470px`, `.ov-row2-card { height: var(--ov-row2-h) }` and no `height:` in the 1100px media block) and `gtmOverview.row3.test.js` ~L173-176 (asserts `.ov-row2-card` height var). Class assertions to keep green: `.ov-row2-card` on the three cards, `.ov-funnel-card`, `.ov-deals`, `slds-scrollable_y` on `.ov-deals-body` and `.ov-results-body`, `.ov-sticky`. Also confirm `gtmOverview.actToday.test.js` L203-205 CSS-slice test (hex palette, slices by comment markers `/* Row 1: "Act today"` and `.ov-col {`) and `gtmOverview.funnel.test.js` L306 (slices `/* ── The funnel` ... `/* ── Offering feedback`) still pass: do not remove or reorder those marker comments and add no new hex colours. Add new assertions: cap property present, `.ov-row2-card` has `max-height` and no fixed `height`, `.fs-row` has no `flex-basis:0`. Jest cannot verify layout (jsdom); browser validation above is the real gate.

### Risks

- Funnel `.fs-row` flex model: leaving `flex: 1 1 0` under auto height collapses rows; the clip-path shape depends on row height, so the min row height needs a visual check.
- `max-height` on a grid item with `align-items: stretch`: confirm in the browser that the shorter card stretches (expected) and that the body scrolls (needs `min-height:0` down the flex chain).
- Sticky header inside scroll bodies: changing the card from fixed height to a flex column with `max-height` must not move the scroll container; keep `padding-top:0`.
- Old tab route renders the same component: any regression shows in both places; test both.
- Wizard chrome-offset measurement reads its own host position, not the Overview; low risk, verify anyway.
- Page height now varies with data, so anything below (footers, utility bar) may shift; verify no overlap.
- Sequencing: hold this if an unexplained regression is open; do not stack production deploys (memory: deploy sequencing).

### Open questions for the user

1. Cap value: is 470px right for all three cards (recommended), or different per card (for example a shorter cap for Assessment results)?
2. Narrow widths: plain 470px cap, or `min(470px, 70vh)`?
3. Row 3: should Offerings and Assessment results stretch to equal height when both have content (switch `.ov-row3` to `align-items: stretch`), or stay top-aligned as today (recommended: keep top-aligned; only Row 2 was asked to match)?
4. Empty funnel: compact message only (recommended), or keep the four grey placeholder stages so the shape is visible?
