/**
 * Publicis Sapient shared brand primitives -- tokens, font loading contract,
 * and the notched-panel clip-path shape. Pure importable module, no template,
 * not a placeable component (see .js-meta.xml: isExposed false, no targets).
 * Contract: docs/architecture/gtm-brand-tokens.md.
 *
 * WHY THIS EXISTS. offeringChooser, chooseIndustry and gtmConfigurator each
 * re-declared their own copy of the brand palette and drifted to the wrong
 * red (#E90024 instead of #E90130) and the wrong fonts (Inter / IBM Plex Mono
 * instead of Lexend Deca / Roboto / Roboto Mono) -- gtmStory.css is the one
 * proven-correct implementation. This module is the second attempt at a
 * shared source of truth; the first (c/gtmBrandTokens as a CSS-only bundle,
 * PR #23) had no .js/.js-meta.xml, was not a deployable component, and was
 * removed in issue #33. This bundle avoids that failure mode by shipping a
 * real .js entry point AND a real .js-meta.xml, exactly like the other
 * template-less helper bundles already in this tree (c/gtmNavigate,
 * c/gtmPredicate, c/gtmColumnState) -- "not a component" means no .html
 * template and isExposed=false, not "no metadata file". A bundle folder
 * under lwc/ with no .js-meta.xml fails scripts/check-references.py's
 * companion-file check outright ("LWC bundle has no X.js-meta.xml -- it
 * will not deploy"), which is the same class of defect PR #23 shipped.
 *
 * LIGHT ONLY, ON PURPOSE. gtmStory.css also carries a general, ambient
 * `@media (prefers-color-scheme: dark)` flip plus `.dark`/`.light` override
 * classes that swap nearly the whole palette. That mechanism is NOT ported
 * here: the owner-approved Design System default across this initiative is
 * light/bright/airy, with dark reserved for specific full-bleed photo
 * moments (a hero band, a parallax "why" section) applied as an explicit,
 * manually-opted-into utility on that one section -- never a general
 * OS-preference-driven UI-wide toggle. BRAND_TOKENS below is the light
 * palette only; there is no dark variant exported from this module. (Note:
 * offeringChooser/chooseIndustry/gtmConfigurator each already ship their own
 * separate, pre-existing, user-facing light/dark toggle button + palette --
 * unrelated to gtmStory.css's mechanism, not part of this shared module, and
 * out of scope to redesign here. Only the specific wrong-red/wrong-font
 * VALUES inside those components' own blocks were corrected, in every
 * branch they appear, light and dark alike -- see docs/architecture/
 * gtm-brand-tokens.md section 5.)
 */

// ── token source of truth ───────────────────────────────────────────────────
// Verbatim light-mode values from gtmStory.css's :host block (the proven,
// live-referenced implementation), minus its dark-mode branches. Two new
// tokens are added at the end for the notch primitive below; everything else
// is unchanged from gtmStory.css.
const BRAND_TOKENS = {
    // brand
    '--ps-red': '#e90130',
    '--ps-red-hover': '#be0128',
    '--ps-red-on-grey': '#be0128',
    '--ps-red-soft': 'rgba(233, 1, 48, 0.09)',
    '--ps-red-ring': 'rgba(233, 1, 48, 0.28)',
    '--ps-on-red': '#ffffff',

    // ink
    '--ps-ink': '#000000',
    '--ps-ink-strong': '#444444',
    '--ps-ink-muted': '#666666',
    '--ps-ink-disabled': '#949494',

    // surfaces
    '--ps-white': '#ffffff',
    '--ps-surface-50': '#fafafa',
    '--ps-surface-100': '#f5f5f5',
    '--ps-surface-alt': '#f6f6f6',

    // borders
    '--ps-border-subtle': '#eeeeee',
    '--ps-border': '#dddddd',
    '--ps-border-strong': '#000000',

    // functional
    '--ps-focus': '#0c63ea',
    '--ps-error': '#e90130',
    '--ps-good': '#2e7d5b',
    '--ps-good-ring': 'rgba(46, 125, 91, 0.25)',
    '--ps-warn': '#8c6a1a',

    // type
    '--ps-font-display': '"Lexend Deca", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
    '--ps-font-body': '"Roboto", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif',
    '--ps-font-mono': '"Roboto Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',

    '--ps-fw-light': '300',
    '--ps-fw-regular': '400',
    '--ps-fw-medium': '500',
    '--ps-fw-semibold': '600',
    '--ps-fw-bold': '700',

    '--ps-tracking-display': '-0.033em',
    '--ps-tracking-eyebrow': '0.025em',

    // shape
    '--ps-radius-card': '0.625rem',
    '--ps-radius-panel': '1rem',
    '--ps-radius-pill': '9999px',

    // motion
    '--ps-duration': '0.15s',
    '--ps-duration-wipe': '0.3s',
    '--ps-ease': 'cubic-bezier(0.4, 0, 0.2, 1)',
    '--ps-ease-out': 'cubic-bezier(0, 0, 0.2, 1)',
    '--ps-focus-offset': '3px',

    // elevation
    '--ps-shadow': '0 16px 40px -20px rgba(0, 0, 0, 0.18)',
    '--ps-shadow-soft': '0 6px 18px -10px rgba(0, 0, 0, 0.14)',

    // inverted band
    '--ps-invert-bg': '#000000',
    '--ps-invert-fg': '#ffffff',
    '--ps-invert-fg-muted': '#a8a8a8',
    '--ps-invert-border': '#333333',

    // notch primitive (new -- see applyNotch below). Plain px, not rem: read
    // back via getComputedStyle().getPropertyValue() and parsed with
    // parseFloat(), which resolves a "28px" string cleanly without needing
    // the root-font-size lookup a rem value would require.
    '--ps-notch-radius': '28px',
    '--ps-notch-corner-radius': '16px'
};

/**
 * CSS-text rendering of BRAND_TOKENS, wrapped in a :host rule. Exported for
 * documentation and CI-diffing against gtmStory.css's own block (the
 * "Option B" fallback the original plan named) -- NOT used internally by
 * injectBrandTokens, see the comment on that function for why.
 */
export const BRAND_TOKENS_CSS =
    ':host {\n' +
    Object.entries(BRAND_TOKENS)
        .map(([name, value]) => `  ${name}: ${value};`)
        .join('\n') +
    '\n}\n';

const TOKENS_MARKER = 'psBrandTokens';

/**
 * Stamp every --ps-* custom property in BRAND_TOKENS onto hostEl's own
 * inline style, once. Every component's .css already declares its local
 * aliases in terms of var(--ps-*) (e.g. `--accent: var(--ps-red);`); once
 * this runs, those resolve correctly because a CSS custom property set via
 * an element's inline style is visible to any rule -- inherited or
 * same-element -- that consumes it with var().
 *
 * Deliberately NOT implemented as "inject a <style> tag containing
 * BRAND_TOKENS_CSS's `:host {...}` text", even though that would look more
 * like the existing font-link injection dance. A runtime-created <style>
 * element's `:host` selector only means anything if it ends up inside a
 * NATIVE shadow root; LWC's synthetic-shadow fallback mode (still reachable
 * in some Lightning Web Security / older-browser configurations, notably
 * the Aura-hosted Experience Cloud pages these three components render on)
 * rewrites `:host` at BUILD time into an attribute-selector match, which a
 * hand-authored runtime string can't participate in -- exactly the
 * "Locker/LWS wall" risk the original implementation plan flagged as its
 * own open question. Setting inline custom properties directly on hostEl is
 * plain DOM mutation with no shadow-mode dependency at all, so it can't hit
 * that wall; this repo has no live org to spike-test the <style>-tag
 * approach against, so the mechanism that can't fail either way is the
 * safer default. See docs/architecture/gtm-brand-tokens.md section 3.
 *
 * Dedup mirrors the existing data-gtm-fonts="1" link pattern used for font
 * injection in these same components, adapted to an inline-style target
 * (which has no separate node to tag, so the marker lives on hostEl itself).
 *
 * @param {HTMLElement} hostEl - the component's own root element, e.g.
 *   `this.template.querySelector('.oc-root')`. Call once from
 *   connectedCallback, same place loadFonts() is already called.
 */
export function injectBrandTokens(hostEl) {
    if (!hostEl || !hostEl.style || typeof hostEl.style.setProperty !== 'function') return;
    try {
        if (hostEl.dataset && hostEl.dataset[TOKENS_MARKER] === '1') return;
        Object.entries(BRAND_TOKENS).forEach(([name, value]) => {
            hostEl.style.setProperty(name, value);
        });
        if (hostEl.dataset) hostEl.dataset[TOKENS_MARKER] = '1';
    } catch (e) {
        // Tokens are progressive enhancement over each component's own CSS
        // fallback values; never let injection break the page.
    }
}

// ── notch shape primitive ───────────────────────────────────────────────────
// A CSS clip-path: polygon() utility class can only draw straight lines, so
// it produces a chamfered corner, not the brand's rounded "bite". Drawing
// the bite needs an SVG <clipPath> with an arc segment, and the arc's
// coordinates depend on the target element's actual rendered size, which a
// static class cannot encode -- hence a JS helper that measures the element
// and writes a per-instance <clipPath>.

const NOTCH_MARKER = 'psNotchId';
let notchCounter = 0;
const CORNER_ORDER = ['tl', 'tr', 'br', 'bl'];
// Per-corner point, plus the unit direction of the edge walking INTO (in) and
// OUT OF (out) that corner when tracing the rectangle clockwise tl->tr->br->
// bl->tl. Purely a function of rectangle geometry -- same four vectors,
// rotated, at every corner.
const CORNER_GEOMETRY = {
    tl: { point: (w, h) => [0, 0], in: [0, -1], out: [1, 0] },
    tr: { point: (w, h) => [w, 0], in: [1, 0], out: [0, 1] },
    br: { point: (w, h) => [w, h], in: [0, 1], out: [-1, 0] },
    bl: { point: (w, h) => [0, h], in: [-1, 0], out: [0, -1] }
};

function parsePx(value, fallback) {
    const n = parseFloat(value);
    return Number.isFinite(n) && n >= 0 ? n : fallback;
}

/**
 * Build the `d` attribute for a rounded rectangle (0,0)-(w,h) where one
 * named corner is a concave "bite" of radius notchRadius, the two corners
 * adjacent to it are plain convex rounds of radius cornerRadius, and the
 * corner diagonally opposite the notch is left sharp (radius 0).
 *
 * Geometry: every corner's arc runs between the same two tangent points
 * regardless of direction -- `corner - r*in` (where the previous straight
 * edge stops) and `corner + r*out` (where the next straight edge resumes).
 * A convex round bulges toward the true corner (sweep-flag 1 when walking
 * clockwise); a concave bite is the mirror-image arc through the same two
 * points, bulging away from the corner into the material (sweep-flag 0).
 * Large-arc-flag is always 0: every arc drawn here is a single quarter-turn
 * (<= 90 degrees) regardless of radius.
 *
 * Verified against a real browser rendering, not just by inspection: see
 * the Developer handback for issue-ps-brand-overhaul-2-brand-tokens-shapes-
 * type for the pixel-sampled proof (ground-truth screenshot + PIL probe
 * points at each corner, confirming sharp/convex/concave regions land where
 * this comment says they do).
 */
function psNotchPath(w, h, notchCorner, notchRadius, cornerRadius) {
    const notchIdx = CORNER_ORDER.indexOf(notchCorner);
    const oppositeCorner = CORNER_ORDER[(notchIdx + 2) % 4];

    const radiusFor = (c) => {
        if (c === notchCorner) return notchRadius;
        if (c === oppositeCorner) return 0;
        return cornerRadius;
    };

    const corners = {};
    CORNER_ORDER.forEach((c) => {
        const geo = CORNER_GEOMETRY[c];
        const [cx, cy] = geo.point(w, h);
        const r = radiusFor(c);
        corners[c] = {
            r,
            concave: c === notchCorner,
            arcStart: [cx - r * geo.in[0], cy - r * geo.in[1]],
            arcEnd: [cx + r * geo.out[0], cy + r * geo.out[1]]
        };
    });

    // Walk starting right after tl's own arc, so the path both opens and
    // closes on tl -- an arbitrary but consistent choice of seam.
    const start = corners.tl.arcEnd;
    const walkOrder = ['tr', 'br', 'bl', 'tl'];
    let d = `M ${start[0]},${start[1]} `;
    walkOrder.forEach((c) => {
        const info = corners[c];
        d += `L ${info.arcStart[0]},${info.arcStart[1]} `;
        if (info.r > 0) {
            const sweep = info.concave ? 0 : 1;
            d += `A ${info.r},${info.r} 0 0 ${sweep} ${info.arcEnd[0]},${info.arcEnd[1]} `;
        }
    });
    return `${d}Z`;
}

/**
 * Measure hostEl and clip it to a rounded rectangle with a single concave
 * "bite" cut into the named corner, using a per-instance inline SVG
 * <clipPath clipPathUnits="userSpaceOnUse"> (a static CSS clip-path class
 * cannot encode per-element pixel coordinates). Safe to call repeatedly
 * (e.g. from renderedCallback, so it re-measures after layout changes) --
 * the same SVG/clipPath/path nodes are reused and their `d` attribute is
 * just recomputed, not recreated, keyed off hostEl.dataset.psNotchId.
 *
 * Requires hostEl to already be laid out (a real offsetWidth/offsetHeight);
 * call from renderedCallback, not connectedCallback. Corners with 0 width
 * or height (not yet rendered) are a silent no-op -- caught on the next
 * renderedCallback pass instead of clipping to a degenerate 0x0 path.
 *
 * @param {HTMLElement} hostEl - the element to clip, e.g. a `.tile` node
 *   from `this.template.querySelector(...)`.
 * @param {'tl'|'tr'|'br'|'bl'} corner - which corner gets the concave bite;
 *   the two corners sharing an edge with it become plain convex rounds, the
 *   corner diagonally opposite is left sharp.
 * @param {{notchRadius?: number, cornerRadius?: number}} [options] - pixel
 *   overrides. Default to --ps-notch-radius / --ps-notch-corner-radius read
 *   off hostEl's computed style, falling back to 28 / 16 if unset.
 */
export function applyNotch(hostEl, corner, options) {
    if (!hostEl || !CORNER_GEOMETRY[corner]) return;
    try {
        const w = hostEl.offsetWidth;
        const h = hostEl.offsetHeight;
        if (!w || !h) return;

        const cs = window.getComputedStyle ? window.getComputedStyle(hostEl) : null;
        const opts = options || {};
        const notchRadius = parsePx(
            opts.notchRadius != null ? opts.notchRadius : cs && cs.getPropertyValue('--ps-notch-radius'),
            28
        );
        const cornerRadius = parsePx(
            opts.cornerRadius != null ? opts.cornerRadius : cs && cs.getPropertyValue('--ps-notch-corner-radius'),
            16
        );

        const d = psNotchPath(w, h, corner, notchRadius, cornerRadius);

        let id = hostEl.dataset && hostEl.dataset[NOTCH_MARKER];
        let pathEl = id ? hostEl.querySelector(`clipPath#${id} path`) : null;

        if (!pathEl) {
            notchCounter += 1;
            id = `ps-notch-${notchCounter}`;
            const svgNs = 'http://www.w3.org/2000/svg';
            const svg = document.createElementNS(svgNs, 'svg');
            svg.setAttribute('width', '0');
            svg.setAttribute('height', '0');
            svg.setAttribute('aria-hidden', 'true');
            svg.style.position = 'absolute';
            svg.style.width = '0';
            svg.style.height = '0';
            svg.style.overflow = 'hidden';
            const clipPath = document.createElementNS(svgNs, 'clipPath');
            clipPath.setAttribute('id', id);
            clipPath.setAttribute('clipPathUnits', 'userSpaceOnUse');
            pathEl = document.createElementNS(svgNs, 'path');
            clipPath.appendChild(pathEl);
            svg.appendChild(clipPath);
            hostEl.appendChild(svg);
            if (hostEl.dataset) hostEl.dataset[NOTCH_MARKER] = id;
        }

        pathEl.setAttribute('d', d);
        hostEl.style.clipPath = `url(#${id})`;
    } catch (e) {
        // Shape is progressive enhancement; a plain rectangle is an
        // acceptable fallback, never worth breaking the page over.
    }
}
