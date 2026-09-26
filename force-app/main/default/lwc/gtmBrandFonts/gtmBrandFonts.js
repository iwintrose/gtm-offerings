/**
 * Shared Google-Fonts CDN loader for GUS's chat surfaces.
 *
 * Extracted from the working, CSP-approved pattern already proven in
 * `c/gtmStory` (`FONTS_HREF` + `loadFonts()`, gtmStory.js lines ~7-8 and
 * ~634-645) rather than re-derived: same three families (Lexend Deca /
 * Roboto / Roboto Mono), same CSS2 API URL, same de-duplication approach.
 * Appends a <link> to the *document* head (not a shadow root), which is why
 * one call here makes the fonts available by family name to every GUS
 * shadow tree on the page, regardless of which component actually calls it.
 *
 * docs/agent-artifacts/task-scope-gus-chat-branding-refresh.md §1.4 / Open
 * Fork F2: this module intentionally serves GUS's surfaces only
 * (gtmAgentChat, gtmAgentBubble, gtmGusUtility, gtmReadoutAssist).
 * gtmConfigurator.js / chooseIndustry.js / offeringChooser.js keep their own
 * separate (currently stale, still-'Inter') loaders — fixing those is
 * explicitly out of scope for this task; filed as a follow-up.
 */
const FONTS_HREF =
    'https://fonts.googleapis.com/css2?family=Lexend+Deca:wght@300;400;500;600&family=Roboto:wght@300;400;500;700&family=Roboto+Mono:wght@300;400;500;700&display=swap';

const MARKER_ATTR = 'data-gtm-brand-fonts';

/**
 * Injects the shared brand font stylesheet into the document head, once.
 * Safe to call from every GUS surface's connectedCallback: subsequent calls
 * are a no-op once the marked <link> exists. Font loading is progressive
 * enhancement -- any failure here is swallowed and the CSS font-family
 * fallback stack still renders.
 */
export function loadBrandFonts() {
    try {
        if (document.querySelector(`link[${MARKER_ATTR}="1"]`)) return;
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = FONTS_HREF;
        link.setAttribute(MARKER_ATTR, '1');
        document.head.appendChild(link);
    } catch (e) {
        // Fonts are progressive enhancement; fall back to the CSS stack.
    }
}
