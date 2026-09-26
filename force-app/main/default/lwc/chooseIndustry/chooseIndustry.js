import { LightningElement, api, track } from 'lwc';
import getPageLayout from '@salesforce/apex/GtmPageContentReader.getPageLayout';
import getIndustryProfiles from '@salesforce/apex/GtmPageContentReader.getIndustryProfiles';
import getSiteInfo from '@salesforce/apex/GtmPageContentReader.getSiteInfo';
import { FRAMEWORK_KEY } from 'c/gtmPageLayouts';
import { injectBrandTokens } from 'c/gtmBrandTokens';

// Same family list as gtmStory's FONTS_HREF (the proven-correct reference
// implementation) -- this used to request Inter, which nothing on this page
// is styled with anymore now that chooseIndustry.css consumes --ps-font-*.
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

// The floor: what the page says before any record exists. Generic on
// purpose -- this page is reached by every offering, not just Migration
// Accelerator (see brandLabel/footerLeft getters below).
const CHROME_DEFAULTS = {
    brandLabel: 'This Offering',
    brandTag: '/ choose your industry',
    eyebrow: 'Step 2 of 2',
    headline: 'Choose your industry.',
    subhead: 'This looks different in every sector. Pick one and the '
        + 'client-facing page reframes around what actually matters for that '
        + 'business, not a generic pitch.',
    footerRight: 'Publicis Sapient · internal'
};

export default class ChooseIndustry extends LightningElement {
    /** Which modelled page this reads. One template, many offerings. */
    @api templateType = 'industry-chooser';

    // GTM_Page_Content__c flat map: 'section::field' -> resolved string.
    @track _cms = {};
    // No default -- this page is framework-level (industries are a shared
    // taxonomy, see connectedCallback), not owned by any one offering. The
    // offering actually being routed through this page is the one forwarded
    // in the incoming ?offering= URL param (see urlOfferingKey below), not
    // this design attribute.
    @api offeringKey = '';

    /** Back link target. Set in Experience Builder. */
    @api offeringsUrl = '/';
    /** Configurator page. Industry is appended as ?industry=<key>. */
    @api configuratorUrl = '/configurator';

    /** The offering offeringChooser forwarded as ?offering=<key> (B11
     * amendment §1b). Read once, off this page's own incoming URL, and
     * forwarded onward unchanged to the configurator alongside ?industry=
     * and the conditional &cfgId=. Blank when this page was reached with no
     * offering context at all (e.g. a bookmarked/typed URL). */
    @track urlOfferingKey = '';

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
    // Resolved-empty result (no industries set up yet). Kept apart from
    // _loadError: the getPageLayout catch can overwrite that one.
    @track _industriesEmpty = false;
    @track _industries = [];
    @track _orgUrl = '';
    _lightningUrl = '';
    _sites = [];

    get rootClass() {
        if (this.theme === 'dark') return 'ci-root dark';
        if (this.theme === 'light') return 'ci-root light';
        return 'ci-root';
    }

    /** Every tile here (an industry, or "Skip for now") is a rep starting
     * a brand-new page -- wizard=1 tells gtmConfigurator to open the wizard
     * immediately instead of landing on a bare configurator with no clear
     * next step. A prospect clicking a link a rep already built and shared
     * carries its own cfgId/company params instead and never passes through
     * this page at all, so this never fires for them. */
    get skipHref() {
        let base = this._withWizardParam(this.configuratorUrl || '/configurator');
        const cfgId = new URLSearchParams(window.location.search).get('cfgId');
        if (this.urlOfferingKey) base += `&offering=${encodeURIComponent(this.urlOfferingKey)}`;
        return cfgId ? `${base}&cfgId=${encodeURIComponent(cfgId)}` : base;
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
    // No offering-scoped fallback line: 'migration-accelerator — offering-scoped'
    // was only ever true for the one offering that existed when this was
    // written. Omit the line entirely rather than guess at a generic one
    // when there is no CMS-authored value and no resolved offering.
    get footerLeft() {
        const cms = this._ct('footer::footerLeft');
        if (cms) return cms;
        return this.urlOfferingKey ? `${this.urlOfferingKey} — offering-scoped` : '';
    }
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
        const cfgId = new URLSearchParams(window.location.search).get('cfgId');
        const orgUrl = this._orgUrl;
        return this._profiles.map((ind) => {
            const key = ind.industryKey;
            let hrefBase = `${base}${joiner}industry=${encodeURIComponent(key)}`;
            if (this.urlOfferingKey) hrefBase += `&offering=${encodeURIComponent(this.urlOfferingKey)}`;
            const href = cfgId ? `${hrefBase}&cfgId=${encodeURIComponent(cfgId)}` : hrefBase;
            // Industry copy is edited in the GTM Content Manager now that the
            // CMS content index is gone.
            const cmsUrl = orgUrl
                ? `${orgUrl}/lightning/n/GTM_Content_Manager`
                : '#';
            const indexUrl = cmsUrl;
            const builderUrl = this.builderUrl;
            return {
                key,
                sectionKey: `industry-${key}`,
                label: ind.industryLabel || key,
                desc: ind.pickerBlurb || '',
                href,
                contentId: ind.contentId || '',
                address: `gtm::industry-chooser::industry-${key}`,
                cmsUrl,
                indexUrl,
                builderUrl,
                wrapClass: 'tile-wrap'
            };
        });
    }

    get builderUrl() { return buildBuilderUrl(this._orgUrl); }

    connectedCallback() {
        this.loadFonts();

        // Same raw URLSearchParams style already used for cfgId/industry
        // elsewhere on this page and on gtmConfigurator (consistency with
        // adjacent guest-facing community-page code, per the B11 amendment's
        // param-style recommendation).
        try {
            this.urlOfferingKey = new URLSearchParams(window.location.search).get('offering') || '';
        } catch (e) {
            this.urlOfferingKey = '';
        }

        // Industries are a shared taxonomy, so this page and the profiles
        // behind it belong to the framework, not to one offering.

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
                if (rows && rows.length) {
                    this._industries = rows;
                    this._industriesEmpty = false;
                    return;
                }
                // Resolved empty: nothing is set up yet. Not an error.
                this._industries = [];
                this._industriesEmpty = true;
            })
            .catch((err) => {
                this._industries = [];
                this._industriesEmpty = false;
                this._loadError = 'The industry list could not be loaded. Please retry.';
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

    renderedCallback() {
        // this.template is still empty during connectedCallback (LWC renders
        // after it returns), so the one-time --ps-* stamp has to happen here
        // instead -- injectBrandTokens is dataset-marker-guarded, so repeat
        // calls on every re-render are a cheap no-op after the first.
        injectBrandTokens(this.template.querySelector('.ci-root'));
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
