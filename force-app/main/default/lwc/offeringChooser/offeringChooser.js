import { LightningElement, api, track } from 'lwc';
import getSiteInfo from '@salesforce/apex/GtmPageContentReader.getSiteInfo';
import getPageLayout from '@salesforce/apex/GtmPageContentReader.getPageLayout';
import getOfferingTiles from '@salesforce/apex/GtmPageContentReader.getOfferingTiles';
import { FRAMEWORK_KEY } from 'c/gtmPageLayouts';
import { injectBrandTokens } from 'c/gtmBrandTokens';

// Same family list as gtmStory's FONTS_HREF (the proven-correct reference
// implementation) -- this used to request Inter, which nothing on this page
// is styled with anymore now that offeringChooser.css consumes --ps-font-*.
const FONTS_HREF =
    'https://fonts.googleapis.com/css2?family=Lexend+Deca:wght@300;400;500;600&family=Roboto:wght@300;400;500;700&family=Roboto+Mono:wght@300;400;500;700&display=swap';

function buildBuilderUrl(orgUrl) {
    // The previous per-site deep link (/apex/networkbranding) pointed at a
    // page that does not exist in this org. Digital Experiences > All Sites
    // is the one Setup route guaranteed to exist; from there "Builder" opens
    // the right site in one more click.
    if (!orgUrl) return '#';
    return `${orgUrl}/lightning/setup/SetupNetworks/home`;
}

// What this page says when no records exist yet — the floor, so the page is
// never blank while content is being written.
const DEFAULTS = {
    brandLabel: 'Publicis Sapient',
    brandTag: '/ GTM Offerings',
    eyebrow: 'Step 1 of 2',
    headline: 'Choose your offering.',
    subhead: "Pick the practice offering you're presenting. Next, you'll tell us who "
        + "it's for, and the story reframes around them.",
    footerLeft: 'gtm-offerings — shared front door',
    footerRight: 'Publicis Sapient · internal',
    placeholder: 'Space reserved for the next practice offering added to this framework.',
    // Empty, deliberately: no offering has been configured yet is a real,
    // explicit state ("No offerings are configured yet" — see the empty
    // state rendered in the .html when tiles is []), not an invitation to
    // invent a second hardcoded generic tile.
    cards: []
};

/** Initials, so an offering without a mark of its own still gets a badge. */
function markFor(name) {
    if (!name) return '';
    return String(name)
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 2)
        .map((w) => w.charAt(0).toUpperCase())
        .join('');
}

export default class OfferingChooser extends LightningElement {
    // No default -- this page is framework-level (see templateType below);
    // an offeringKey design attribute value is not consumed for identity
    // here, only forwarded on each tile's own href via tile.offeringKey.
    @api offeringKey = '';

    /**
     * This page sits above offerings and lists them, so its own content is
     * framework-level, not offering-level. The tiles come from each offering's
     * offerings-listing page instead.
     */
    @api templateType = 'offerings-page';

    /** Where the Migration Accelerator tile points. Set in Experience Builder. */
    @api industryUrl = '/choose-industry';

    // Preview mode. The GTM Content Manager hands this component the draft it
    // is editing and this renders that, so the editor previews through the
    // real page rather than a second implementation of it that can drift.
    _preview = false;

    @api
    get previewContent() { return this._cms; }
    set previewContent(value) {
        if (!value || !Object.keys(value).length) return;
        this._preview = true;
        this._cms = value;
    }

    /**
     * One offering's draft tile, when the tile itself is what is being edited.
     * It replaces that offering's published tile in the grid, so an
     * offerings-listing edit is previewed where it actually appears.
     */
    @api
    get previewTile() { return this._previewTile; }
    set previewTile(value) {
        if (!value) return;
        this._preview = true;
        this._previewTile = value;
    }

    /** Where each section sits, so the editor's rail and this stay in step. */
    @api
    getSectionRects() {
        const out = [];
        this.template.querySelectorAll('[data-section]').forEach((el) => {
            const r = el.getBoundingClientRect();
            const pos = window.getComputedStyle(el).position;
            out.push({
                sectionKey: el.dataset.section,
                top: r.top,
                bottom: r.bottom,
                pinned: pos === 'sticky' || pos === 'fixed'
            });
        });
        return out;
    }

    _previewTile = null;

    @track _loadError = '';
    @track theme = null;
    // GTM_Page_Content__c flat map: 'section::field' -> resolved string.
    @track _cms = {};
    @track _tiles = [];
    _orgUrl = '';
    _lightningUrl = '';
    _sites = [];

    get rootClass() {
        if (this.theme === 'dark') return 'oc-root dark';
        if (this.theme === 'light') return 'oc-root light';
        return 'oc-root';
    }

    // ─── CMS resolution ───────────────────────────────────────────────────────
    // Records first, then the built-in default. Same precedence and the same
    // reader as the story page: one place decides what a page says.

    _ct(key) { return this._cms[key] || null; }
    _cj(key) {
        const raw = this._cms[key];
        if (!raw) return null;
        try { return JSON.parse(raw); } catch (e) { return null; }
    }

    get brandLabel() { return this._ct('header::brandLabel') || DEFAULTS.brandLabel; }
    // Two-tone wordmark split: "publicis" (black) + "sapient" (red), matching
    // the live publicissapient.com pattern. brandLabel is CMS-editable text,
    // not always literally "Publicis Sapient", so this splits generically on
    // the first word rather than hardcoding the two brand words.
    get brandLabelFirstWord() {
        return String(this.brandLabel || '').trim().split(/\s+/)[0] || '';
    }
    get brandLabelRest() {
        const parts = String(this.brandLabel || '').trim().split(/\s+/);
        return parts.slice(1).join(' ');
    }
    get brandTag() { return this._ct('header::brandTag') || DEFAULTS.brandTag; }
    get eyebrow() { return this._ct('intro::eyebrow') || DEFAULTS.eyebrow; }
    get headline() { return this._ct('intro::headline') || DEFAULTS.headline; }
    get subhead() { return this._ct('intro::subhead') || DEFAULTS.subhead; }
    get footerLeft() { return this._ct('footer::footerLeft') || DEFAULTS.footerLeft; }
    get footerRight() { return this._ct('footer::footerRight') || DEFAULTS.footerRight; }

    /**
     * The offering tiles. A card that is not marked coming-soon is a live
     * offering and links onward; the rest are placeholders. Which is which is
     * content, not code, so adding the second offering is an edit.
     */
    /**
     * One tile per offering, each supplied by that offering. An offering with
     * no tile copy yet still appears, as a placeholder — the page shows the
     * shape of what is coming rather than hiding it.
     */
    get tiles() {
        let source = this._tiles.length ? this._tiles : DEFAULTS.cards;
        const draft = this._previewTile;
        if (draft) {
            const key = draft.offeringKey;
            const hit = source.findIndex((c) => c.offeringKey === key);
            source = source.slice();
            if (hit >= 0) source[hit] = { ...source[hit], ...draft };
            else source = source.concat([draft]);
        }
        return source.map((c, i) => {
            const live = c.isLive === true;
            return {
                id: `${i}-${c.offeringKey || c.name || ''}`,
                mark: c.mark || markFor(c.name) || '?',
                name: c.name || 'Next offering',
                description: c.description || DEFAULTS.placeholder,
                isLive: live,
                // A placeholder gets no href, so it is not a link.
                // Live tile hrefs forward this tile's own offeringKey as
                // ?offering=, same style/precedence as the cfgId forwarding
                // already here — this is the front door's only way of
                // telling chooseIndustry/gtmConfigurator which offering was
                // picked before any saved record exists (B11 amendment §1b).
                href: live ? (() => {
                    const cfgId = new URLSearchParams(window.location.search).get('cfgId');
                    const params = [];
                    if (c.offeringKey) params.push(`offering=${encodeURIComponent(c.offeringKey)}`);
                    if (cfgId) params.push(`cfgId=${encodeURIComponent(cfgId)}`);
                    if (!params.length) return this.industryUrl;
                    const joiner = this.industryUrl.indexOf('?') === -1 ? '?' : '&';
                    return `${this.industryUrl}${joiner}${params.join('&')}`;
                })() : undefined,
                tileClass: live ? 'tile live' : 'tile soon',
                // The tile is this offering's own Offerings Listing section,
                // so the editor can scroll to the thing it is editing.
                sectionKey: 'tile'
            };
        });
    }

    /** True when no offering tiles resolved at all -- CMS returned none and
     * there is no hardcoded generic tile to fall back to (see DEFAULTS.cards
     * above). Rendered as an explicit "No offerings are configured yet"
     * message rather than a blank grid. */
    get hasNoTiles() {
        return this.tiles.length === 0;
    }

    get builderUrl() { return buildBuilderUrl(this._orgUrl); }

    connectedCallback() {
        this.loadFonts();

        getOfferingTiles()
            .then((rows) => { if (rows) this._tiles = rows; })
            .catch((err) => {
                // eslint-disable-next-line no-console
                console.error('[offeringChooser] getOfferingTiles failed:', JSON.stringify(err));
            });

        // In preview the parent owns the copy; fetching would overwrite the
        // draft with what is published and the preview would stop being live.
        if (this._preview) return;

        getPageLayout({
            offeringKey: FRAMEWORK_KEY,
            templateType: this.templateType,
            industryKey: null
        })
            .then((layout) => {
                if (layout && layout.content) this._cms = layout.content;
            })
            .catch((err) => {
                // Surfaced rather than swallowed: a silent failure here is how
                // the story page rendered built-in defaults for months without
                // anyone noticing.
                this._loadError = 'Page content could not be loaded; showing built-in defaults.';
                // eslint-disable-next-line no-console
                console.error('[offeringChooser] getPageLayout failed:', JSON.stringify(err));
            });

        // Org URL and site list drive the edit-mode deep links only. The tile
        // description they used to carry is content now, on each offering's own
        // offerings-listing page.
        getSiteInfo()
            .then((info) => {
                if (!info) return;
                this._orgUrl = info.orgUrl || '';
                this._lightningUrl = info.lightningUrl || '';
                this._sites = info.sites || [];
            })
            .catch(() => {
                // Deep links are progressive enhancement.
            });
    }

    renderedCallback() {
        // this.template is still empty during connectedCallback (LWC renders
        // after it returns), so the one-time --ps-* stamp has to happen here
        // instead -- injectBrandTokens is dataset-marker-guarded, so repeat
        // calls on every re-render are a cheap no-op after the first.
        injectBrandTokens(this.template.querySelector('.oc-root'));
    }

    loadFonts() {
        try {
            if (document.querySelector('link[data-gtm-fonts="1"]')) return;
            const link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = FONTS_HREF;
            link.setAttribute('data-gtm-fonts', '1');
            document.head.appendChild(link);
        } catch (e) {
            // Fonts are progressive enhancement; CSS fallback stack covers it.
        }
    }


    handleThemeToggle() {
        if (this.theme === 'dark') {
            this.theme = 'light';
            return;
        }
        if (this.theme === 'light') {
            this.theme = 'dark';
            return;
        }
        const systemDark =
            window.matchMedia &&
            window.matchMedia('(prefers-color-scheme: dark)').matches;
        this.theme = systemDark ? 'light' : 'dark';
    }
}
