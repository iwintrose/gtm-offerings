import { LightningElement, api, track } from 'lwc';
import getStoryContent from '@salesforce/apex/MaStoryContentController.getStoryContent';

const FONTS_HREF =
    'https://fonts.googleapis.com/css2?family=Sora:wght@500;600;700;800&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap';

const OFFERING_KEY = 'migration-accelerator';

export default class ChooseIndustry extends LightningElement {
    /** Back link target. Set in Experience Builder. */
    @api offeringsUrl = '/';
    /** Configurator page. Industry is appended as ?industry=<key>. */
    @api configuratorUrl = '/configurator';

    @track theme = null;
    @track _industries = [];

    get rootClass() {
        if (this.theme === 'dark') return 'ci-root dark';
        if (this.theme === 'light') return 'ci-root light';
        return 'ci-root';
    }

    get industries() {
        const base = this.configuratorUrl || '/configurator';
        const joiner = base.indexOf('?') === -1 ? '?' : '&';
        return this._industries.map((ind) => ({
            key: ind.industryKey,
            label: ind.industryLabel,
            desc: ind.pickerBlurb,
            href: `${base}${joiner}industry=${encodeURIComponent(ind.industryKey)}`
        }));
    }

    connectedCallback() {
        this.loadFonts();
        getStoryContent({ offeringKey: OFFERING_KEY })
            .then((data) => { this._industries = (data && data.industries) || []; })
            // eslint-disable-next-line no-console
            .catch((err) => { console.error('[chooseIndustry] getStoryContent:', JSON.stringify(err)); });
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
