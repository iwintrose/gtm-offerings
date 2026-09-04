import { LightningElement, api, track } from 'lwc';
import getStoryContent from '@salesforce/apex/MaStoryContentController.getStoryContent';
import getPageLayout from '@salesforce/apex/MaPageContentReader.getPageLayout';
import getOfferingTiles from '@salesforce/apex/MaPageContentReader.getOfferingTiles';
import { FRAMEWORK_KEY } from 'c/gtmPageLayouts';

const FONTS_HREF =
    'https://fonts.googleapis.com/css2?family=Sora:wght@500;600;700;800&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap';

// Default only. The offering is set on the page in Experience Builder, so a
// second offering is a page assignment rather than a code change.
const DEFAULT_OFFERING_KEY = 'migration-accelerator';

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
    cards: [
        {
            offeringKey: 'migration-accelerator',
            mark: 'MA',
            name: 'Migration Accelerator',
            description: "Reads a client's marketing platform directly, turns it into an "
                + 'audited plan, and where it applies, a finished migration.',
            isLive: true
        }
    ]
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
    @api offeringKey = DEFAULT_OFFERING_KEY;

    /**
     * This page sits above offerings and lists them, so its own content is
     * framework-level, not offering-level. The tiles come from each offering's
     * offerings-listing page instead.
     */
    @api templateType = 'offerings-page';

    /** Where the Migration Accelerator tile points. Set in Experience Builder. */
    @api industryUrl = '/choose-industry';

    @track _loadError = '';
    @track theme = null;
    @track _tileDescription = null;
    // MA_Page_Content__c flat map: 'section::field' -> resolved string.
    @track _cms = {};
    @track _tiles = [];
    @track _editMode = false;
    _orgUrl = '';
    _lightningUrl = '';
    _sites = [];
    _editModeHandler;

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
        const source = this._tiles.length ? this._tiles : DEFAULTS.cards;
        return source.map((c, i) => {
            const live = c.isLive === true;
            return {
                id: `${i}-${c.offeringKey || c.name || ''}`,
                mark: c.mark || markFor(c.name) || '?',
                name: c.name || 'Next offering',
                description: c.description || DEFAULTS.placeholder,
                isLive: live,
                // A placeholder gets no href, so it is not a link.
                href: live ? this.industryUrl : undefined,
                tileClass: live ? 'tile live' : 'tile soon'
            };
        });
    }

    // Kept for the legacy CMS path, which still feeds the industry page.
    get tileDescription() {
        return this._tileDescription || DEFAULTS.cards[0].description;
    }

    get builderUrl() { return buildBuilderUrl(this._orgUrl); }

    connectedCallback() {
        this.loadFonts();
        this._editModeHandler = (evt) => { this._editMode = evt.detail.active; };
        window.addEventListener('maadminedit', this._editModeHandler);

        getOfferingTiles()
            .then((rows) => { if (rows) this._tiles = rows; })
            .catch((err) => {
                // eslint-disable-next-line no-console
                console.error('[offeringChooser] getOfferingTiles failed:', JSON.stringify(err));
            });

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

        getStoryContent({ offeringKey: this.offeringKey })
            .then((data) => {
                if (data && data.setting) this._tileDescription = data.setting.offeringTileDescription;
                this._orgUrl = (data && data.orgUrl) || '';
                this._lightningUrl = (data && data.lightningUrl) || '';
                this._sites = (data && data.sites) || [];
            })
            .catch((err) => {
                this._loadError = 'Offering content could not be loaded; showing built-in defaults.';
                // eslint-disable-next-line no-console
                console.error('[offeringChooser] getStoryContent:', JSON.stringify(err));
            });
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

    disconnectedCallback() {
        if (this._editModeHandler) {
            window.removeEventListener('maadminedit', this._editModeHandler);
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
