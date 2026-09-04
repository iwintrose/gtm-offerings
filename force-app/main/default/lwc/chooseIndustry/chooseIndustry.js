import { LightningElement, api, track } from 'lwc';
import getPageLayout from '@salesforce/apex/MaPageContentReader.getPageLayout';
import getIndustryProfiles from '@salesforce/apex/MaPageContentReader.getIndustryProfiles';
import getSiteInfo from '@salesforce/apex/MaPageContentReader.getSiteInfo';
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

const PICKER_BLURBS = {
    fintech:
        'For banks and insurers, a migration is a compliance event as much as a technology one. The configurator pre-loads the consent, audit, and data-residency guardrails your team will need.',
    medtech:
        'Device-adjacent messaging means PHI boundaries and regulatory review cycles shape every campaign decision. Start here to scope what "migration-ready" actually means for your stack.',
    lifesci:
        'Regulated promotional content, HCP segmentation, and multi-step approval workflows define what a clean migration looks like in life sciences.',
    media:
        'Subscriber churn, real-time triggers, and IP-level segmentation are the metrics that matter most when moving a media and entertainment marketing stack.',
    transport:
        'Operational messaging blends with marketing in logistics. Route alerts, delivery triggers, and loyalty programs all need clean separation before any data moves.',
    government:
        'Citizen communication programs run on accessibility, consent, and multi-channel reach. Migration here is governance work as much as technical work.'
};

// Fallback industry list used when the CMS callout fails (e.g. guest users
// on an org whose public-channel configuration blocks unauthenticated API
// calls). Keys and labels mirror the seeded CMS records exactly so the
// ?industry= URL param still resolves correctly on the configurator page.
const HARDCODED_INDUSTRIES = [
    { industryKey: 'fintech',    industryLabel: 'Financial Services' },
    { industryKey: 'medtech',    industryLabel: 'MedTech' },
    { industryKey: 'lifesci',    industryLabel: 'Life Sciences' },
    { industryKey: 'media',      industryLabel: 'Media & Entertainment' },
    { industryKey: 'transport',  industryLabel: 'Transportation & Logistics' },
    { industryKey: 'government', industryLabel: 'Government & Public Sector' }
];

// The floor: what the page says before any record exists.
const CHROME_DEFAULTS = {
    brandLabel: 'Migration Accelerator',
    brandTag: '/ choose your industry',
    eyebrow: 'Step 2 of 2',
    headline: 'Choose your industry.',
    subhead: 'Migrations look different in every sector. Pick one and the '
        + 'client-facing page reframes around what actually matters for that '
        + 'business, not a generic pitch.',
    footerLeft: 'migration-accelerator — offering-scoped',
    footerRight: 'Publicis Sapient · internal'
};

export default class ChooseIndustry extends LightningElement {
    /** Which modelled page this reads. One template, many offerings. */
    @api templateType = 'industry-chooser';

    // MA_Page_Content__c flat map: 'section::field' -> resolved string.
    @track _cms = {};
    @api offeringKey = DEFAULT_OFFERING_KEY;

    /** Back link target. Set in Experience Builder. */
    @api offeringsUrl = '/';
    /** Configurator page. Industry is appended as ?industry=<key>. */
    @api configuratorUrl = '/configurator';

    // Preview mode: the GTM Content Manager hands over the draft it is editing
    // and this renders that, so the editor previews the real page.
    _preview = false;

    @api
    get previewContent() { return this._cms; }
    set previewContent(value) {
        if (!value || !Object.keys(value).length) return;
        this._preview = true;
        this._cms = value;
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

    @track theme = null;
    @track _loadError = '';
    @track _industries = [];
    @track _editMode = false;
    @track _openEditId = null;
    @track _orgUrl = '';
    _lightningUrl = '';
    _sites = [];

    get rootClass() {
        if (this.theme === 'dark') return 'ci-root dark';
        if (this.theme === 'light') return 'ci-root light';
        return 'ci-root';
    }

    /** Every tile here (an industry, or "Skip for now") is a rep starting
     * a brand-new page -- wizard=1 tells maConfigurator to open the wizard
     * immediately instead of landing on a bare configurator with no clear
     * next step. A prospect clicking a link a rep already built and shared
     * carries its own cfgId/company params instead and never passes through
     * this page at all, so this never fires for them. */
    get skipHref() {
        return this._withWizardParam(this.configuratorUrl || '/configurator');
    }

    _withWizardParam(url) {
        const joiner = url.indexOf('?') === -1 ? '?' : '&';
        return `${url}${joiner}wizard=1`;
    }

    _ct(key) { return this._cms[key] || null; }

    get brandLabel() { return this._ct('header::brandLabel') || CHROME_DEFAULTS.brandLabel; }
    get brandTag() { return this._ct('header::brandTag') || CHROME_DEFAULTS.brandTag; }
    get eyebrow() { return this._ct('intro::eyebrow') || CHROME_DEFAULTS.eyebrow; }
    get headline() { return this._ct('intro::headline') || CHROME_DEFAULTS.headline; }
    get subhead() { return this._ct('intro::subhead') || CHROME_DEFAULTS.subhead; }
    get footerLeft() { return this._ct('footer::footerLeft') || CHROME_DEFAULTS.footerLeft; }
    get footerRight() { return this._ct('footer::footerRight') || CHROME_DEFAULTS.footerRight; }

    /**
     * In preview the profiles are rebuilt from the draft content map, so
     * editing an industry's blurb changes its tile as you type. Published
     * profiles come from the reader instead.
     */
    get _profiles() {
        if (!this._preview) return this._industries;
        const byKey = {};
        Object.keys(this._cms || {}).forEach((addr) => {
            const cut = addr.indexOf('::');
            if (cut < 0) return;
            const section = addr.substring(0, cut);
            if (section.indexOf('industry-') !== 0) return;
            const key = section.substring(9);
            if (!byKey[key]) byKey[key] = { industryKey: key };
            byKey[key][addr.substring(cut + 2)] = this._cms[addr];
        });
        const drafted = Object.keys(byKey).map((k) => byKey[k]);
        return drafted.length ? drafted : this._industries;
    }

    get industries() {
        const base = this._withWizardParam(this.configuratorUrl || '/configurator');
        const joiner = '&';
        const orgUrl = this._orgUrl;
        return this._profiles.map((ind) => {
            const key = ind.industryKey;
            const href = `${base}${joiner}industry=${encodeURIComponent(key)}`;
            // Industry copy is edited in the GTM Content Manager now that the
            // CMS content index is gone.
            const cmsUrl = orgUrl
                ? `${orgUrl}/lightning/n/GTM_Content_Manager`
                : '#';
            const indexUrl = cmsUrl;
            const builderUrl = this.builderUrl;
            const isOpen = this._openEditId === key;
            return {
                key,
                sectionKey: `industry-${key}`,
                label: ind.industryLabel || key,
                desc: ind.pickerBlurb || PICKER_BLURBS[key] || '',
                href,
                contentId: ind.contentId || '',
                address: `gtm::industry-chooser::industry-${key}`,
                cmsUrl,
                indexUrl,
                builderUrl,
                wrapClass: 'tile-wrap' + (this._editMode ? ' tile-wrap--edit' : ''),
                popClass: 'tile-pop' + (isOpen ? ' open' : '')
            };
        });
    }

    get builderUrl() { return buildBuilderUrl(this._orgUrl); }

    connectedCallback() {
        this.loadFonts();
        this._editModeHandler = (evt) => {
            this._editMode = evt.detail.active;
            this._openEditId = null;
        };
        this._winClickHandler = () => { this._openEditId = null; };

        // Industries are a shared taxonomy, so this page and the profiles
        // behind it belong to the framework, not to one offering.
        window.addEventListener('maadminedit', this._editModeHandler);
        window.addEventListener('click', this._winClickHandler);

        // Org URL and site list drive the edit-mode chrome only. This used to
        // come from getStoryContent, which also returned an industry list from
        // the retired CMS index and resolved late enough to overwrite the real
        // profiles below with it.
        getSiteInfo()
            .then((info) => {
                if (!info) return;
                this._orgUrl = info.orgUrl || '';
                this._lightningUrl = info.lightningUrl || '';
                this._sites = info.sites || [];
            })
            .catch(() => {
                // Deep links are progressive enhancement; the page works without them.
            });

        // In preview the parent owns the content, so fetching would replace the
        // draft with what is published.
        if (this._preview) return;

        getIndustryProfiles({ offeringKey: FRAMEWORK_KEY, templateType: this.templateType })
            .then((rows) => {
                this._industries = (rows && rows.length) ? rows : HARDCODED_INDUSTRIES;
            })
            .catch((err) => {
                this._loadError = 'Industry content could not be loaded; showing built-in defaults.';
                this._industries = HARDCODED_INDUSTRIES;
                // eslint-disable-next-line no-console
                console.error('[chooseIndustry] getIndustryProfiles failed:', JSON.stringify(err));
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
                this._loadError = 'Page content could not be loaded; showing built-in defaults.';
                // eslint-disable-next-line no-console
                console.error('[chooseIndustry] getPageLayout failed:', JSON.stringify(err));
            });
    }

    disconnectedCallback() {
        if (this._editModeHandler) {
            window.removeEventListener('maadminedit', this._editModeHandler);
        }
        if (this._winClickHandler) {
            window.removeEventListener('click', this._winClickHandler);
        }
    }

    handleChipClick(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        this._openEditId = this._openEditId === id ? null : id;
    }

    handlePopClick(event) {
        event.stopPropagation();
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
