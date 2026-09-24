# Overview card heights: grow with content, then cap (overview-card-heights)

Status: contract for the Developer. LWC CSS only (`gtmOverview.css`); `gtmOverview.html` is untouched.
No Apex, no permission-set change, no schema or custom-metadata change, no GUS tool change.

## Problem

`.ov-cols { --ov-row2-h: 470px }` plus `.ov-row2-card { height: var(--ov-row2-h) }` gave three cards
(funnel, follow-up table in Row 2; Assessment results in Row 3) a FIXED 470px height, so empty cards
leave large blank areas. Offerings tiles are already content-sized and are not touched.

## Contract

Custom property (renamed, semantics changed from height to cap): `--ov-row2-cap`, declared on `.ov-cols`
(the Row 3 grid reuses `.ov-cols`, so one property caps all three cards). Value `470px`.
The old name `--ov-row2-h` is removed; nothing else may reference it.

```css
.ov-cols { --ov-row2-cap: 470px; /* display:grid; columns; gap; align-items: stretch unchanged */ }
.ov-row2-card { height: auto; max-height: var(--ov-row2-cap); min-height: 0; }   /* .ov-card already is display:flex column */
.ov-deals-body, .ov-results-body { flex: 1 1 auto; min-height: 0; overflow-y: auto; padding-top: 0; }
.ov-funnel-body { flex: 1 1 auto; min-height: 0; }           /* stays a flex column */
.fs-list { flex: 1 1 auto; min-height: 0; overflow-y: auto; } /* safety net, never expected to scroll */
.fs-row { flex: 0 0 auto; min-height: 64px; }                 /* no flex-basis:0, no max-height:92px */
@media (max-width: 1100px) {
  .ov-cols { grid-template-columns: minmax(0, 1fr); --ov-row2-cap: min(470px, 70vh); }
}
```

`.ov-row3` keeps `align-items: start` (Offerings tiles and Assessment results stay top-aligned; only
the results card is capped). Existing 3rem/4.5rem min-height floors stay. Card header stays `flex: none`
(`.ov-card-h` is already a non-growing flex child); the funnel footer note `.fs-note` stays outside the scroll area.

Rules and rationale:

1. Grow then cap: with `height:auto` a card is as tall as its content; `max-height` clamps it; the
   scroll body (flex 1 1 auto, `min-height:0`, `overflow-y:auto`) then absorbs the overflow. `min-height:0`
   must stay on every flex ancestor down to the scroll body or the body will not shrink.
2. Side by side (>1100px, Row 2): the grid keeps `align-items: stretch`. The row track is the taller
   card's clamped content height, and the shorter card stretches to it. `max-height` on a stretched item
   only bounds the used size, so both cards are equal. Both empty: both are the taller of the two empty
   heights (the funnel empty message vs the follow-up empty message), so effectively compact and equal.
3. Stacked (<=1100px): no fixed height remains. Each card is content-sized and capped on its own.
   The cap is `min(470px, 70vh)` here only, so a short landscape phone viewport cannot trap a scroll
   region taller than the screen. Above 1100px it is a plain 470px. `min()` in a custom property is valid
   and resolves at the point of use (`max-height`). No second breakpoint.
4. Funnel shape preserved: `.fs-shape` clip-path polygon uses horizontal percentages of the row WIDTH
   (`--fs-top`, `--fs-bottom`, set inline from `funnelSegments`) and vertical 0% and 100% of the row
   HEIGHT. It therefore has no dependency on a specific pixel height: any row height yields the same
   stacked-trapezoid silhouette, and continuity (each segment's top edge = the previous bottom edge)
   holds as long as the rows are butted together with no row gap. `.fs-list` has no gap, so add none.
   Row height is set to `min-height: 64px` (the count is 20px and the name plus drop-off note is about
   two 12px lines, about 40px of text, so 64px leaves padding and a clear slope). Four rows are 256px plus
   the card header and the note, about 350px, under the 470px cap at every width above roughly 360px;
   the `overflow-y:auto` on `.fs-list` is a safety net for very short viewports (cap `70vh`).
   If a drop-off note wraps on a narrow width, that one row grows past 64px; the polygon still renders
   correctly (it scales with the row), only the slope of that row is taller. Accepted.
5. Empty funnel: the html already renders no `.fs-row` when there are no counts (asserted by
   funnel.test.js ~L237/250/260), only the empty message. The card is then header plus message. No
   placeholder stages (coordinator default 4).
6. Sticky header: `.ov-sticky` is `position:sticky; top:0` inside `.ov-deals-body` / `.ov-results-body`,
   and those elements remain the scroll containers with `padding-top:0`. Changing the card from fixed height
   to max-height does not move the scroll container, so the sticky header stays flush. The one change
   is that when content is shorter than the cap there is no scrolling and the sticky rule is inert.
7. Salesforce first: the cards are already `slds-card`, and the bodies already carry `slds-scrollable_y`
   (which sets `overflow-y:auto` but needs a bounded height). SLDS has no max-height or "grow then cap"
   utility (unverified against live SLDS docs: no web or doc tool was available in this session; this rests on
   the SLDS utility set as known and on the BA's grep of the repo), and a list view or report cannot replace these
   bespoke dashboard cards. The smallest correct fix is one custom property and a few declarations.

## Value table (per card)

| Card | Empty | With rows | Cap | Cap when stacked |
|---|---|---|---|---|
| Funnel "From link to assessment" | header + message | ~350px with 4 stages | 470px | min(470px, 70vh) |
| Opportunities to follow up on | header + message | header + sticky columns + rows | 470px | min(470px, 70vh) |
| Assessment results | header + message | header + sticky columns + rows (page size 25) | 470px | min(470px, 70vh) |
| Offerings tiles | natural | natural | none (unchanged) | none |

## Jest contract (static CSS checks are meaningful only as guards; jsdom cannot lay out)

Marker comments MUST stay verbatim and in order, and no new hex colour may be added, because these tests slice the CSS:
`/* Row 1: "Act today"` to `.ov-col {` (actToday.test.js ~L204, hex palette), `/* ── The funnel` to
`/* ── Offering feedback` (funnel.test.js ~L307), and `/* ── Row 3` to end (row3.test.js ~L232).
Update the comment TEXT (not the marker prefix) in `.ov-cols`'s header and the Row 3 header to say "cap" not "fixed height".

`gtmOverview.funnel.test.js`, replace the test at ~L110-116
("drives both card heights from one custom property, kept when stacked") with:

```js
it('caps the card height with one custom property and lets cards size to content', () => {
    const css = fs.readFileSync(path.join(__dirname, '..', 'gtmOverview.css'), 'utf8');
    expect(css).toMatch(/--ov-row2-cap:\s*470px/);
    expect(css).not.toMatch(/--ov-row2-h\b/);
    const rule = css.match(/\.ov-row2-card\s*\{([^}]*)\}/)[1];
    expect(rule).toMatch(/max-height:\s*var\(--ov-row2-cap\)/);
    expect(rule).toMatch(/height:\s*auto/);
    expect(rule).not.toMatch(/(^|[;\s])height:\s*var\(/);
    expect(css).toMatch(/\.ov-deals-body[^{]*\{[^}]*overflow-y:\s*auto/);
});

it('narrows the cap to min(470px, 70vh) when stacked and sets no fixed height there', () => {
    const css = fs.readFileSync(path.join(__dirname, '..', 'gtmOverview.css'), 'utf8');
    const mq = css.slice(css.indexOf('@media (max-width: 1100px)'));
    const block = mq.slice(0, mq.indexOf('}\n}') + 3);
    expect(block).toMatch(/--ov-row2-cap:\s*min\(470px,\s*70vh\)/);
    expect(block).not.toMatch(/(^|[;\s{])(min-|max-)?height\s*:/);
});

it('funnel rows are content-sized with a floor, not divided from a fixed height', () => {
    const css = fs.readFileSync(path.join(__dirname, '..', 'gtmOverview.css'), 'utf8');
    const section = css.slice(css.indexOf('/* ── The funnel'), css.indexOf('/* ── Offering feedback'));
    const row = section.match(/\.fs-row\s*\{([^}]*)\}/)[1];
    expect(row).toMatch(/flex:\s*0 0 auto/);
    expect(row).toMatch(/min-height:\s*64px/);
    expect(row).not.toMatch(/flex:\s*1 1 0/);
    expect(row).not.toMatch(/max-height/);
    expect(section).toMatch(/\.fs-list\s*\{[^}]*overflow-y:\s*auto/);
});
```

Careful with the media-block assertion: `--ov-row2-cap` contains no `height :` token with a colon, but the
regex above would still match the substring `height:` inside a name only if written `x-height:`; the custom property name ends in `cap`, so it is safe. The block slice
uses the FIRST 1100px media query (the `.ov-cols` one at ~L52); keep it the first one in the file.

`gtmOverview.row3.test.js`, in the test at ~L168-179 (rename to "lives in a capped scroll container that
shares the Row 2 cap, kept content-sized when stacked"): keep the class assertions on L173-174, and replace
L176-178 with:

```js
expect(css).toMatch(/--ov-row2-cap:\s*470px/);
expect(css).toMatch(/\.ov-row2-card\s*\{[^}]*max-height:\s*var\(--ov-row2-cap\)/);
expect(css).toMatch(/\.ov-results-body[^{]*\{[^}]*overflow-y:\s*auto/);
const mqs = css.split('@media (max-width: 1100px)').slice(1).map((s) => s.slice(0, s.indexOf('}\n}') + 3));
mqs.forEach((m) => expect(m).not.toMatch(/(^|[;\s{])(min-|max-)?height\s*:/));
```

Also add (row3.test.js) a guard that Row 3 stays top-aligned: `expect(css.slice(css.indexOf('/* ── Row 3'))).toMatch(/\.ov-row3\s*\{[^}]*align-items:\s*start/)`.
Existing DOM assertions (`.ov-row2-card` on three cards, `.ov-funnel-card`, `.ov-deals`, `slds-scrollable_y`, `.ov-sticky`,
the four `.fs-row` when data exists, none when empty) stay unchanged and must stay green.

## Developer file list

Modify:
- `force-app/main/default/lwc/gtmOverview/gtmOverview.css` (the rules above; update comments at the `.ov-cols`, `.ov-deals-body`, and Row 3 headers to "cap" wording; keep marker comments)
- `force-app/main/default/lwc/gtmOverview/__tests__/gtmOverview.funnel.test.js` (~L110-116 replaced by the three tests above)
- `force-app/main/default/lwc/gtmOverview/__tests__/gtmOverview.row3.test.js` (~L168-179 as above, plus the align-items guard)
- Comment-only: the "Row 2 is two cards at one fixed height" JSDoc near `gtmOverview.js` L37 (optional; no logic change)

Do not touch: `gtmOverview.html`, any Apex, permission sets, objects, `customMetadata/GTM_Assessment_*`, `instrument/` YAML,
`gtmContentHome.css` (verified no fixed height), `gtmAnalytics.css:125` (`height:150px`, look-only follow-up, not here).

Check: `npx sfdx-lwc-jest -- force-app/main/default/lwc/gtmOverview` then `npm test`.
Deploy target: gtm-staging only (`./scripts/deploy.sh gtm-staging --run-tests`). gtm-prod is Production and is NOT a target. No publish needed.
Deploy target: gtm-staging only (`./scripts/deploy.sh gtm-staging --run-tests`). gtm-dev is Production and is NOT a target. No publish needed.
