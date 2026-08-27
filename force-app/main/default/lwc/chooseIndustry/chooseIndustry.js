import { LightningElement, api, track } from 'lwc';
import getStoryContent from '@salesforce/apex/MaStoryContentController.getStoryContent';

const FONTS_HREF =
    'https://fonts.googleapis.com/css2?family=Sora:wght@500;600;700;800&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap';

const OFFERING_KEY = 'migration-accelerator';

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
        'Citizen communication programs run on accessibility, consent, and multi-channel reach. Migration here is governance work as much as technical work.',
    municipal:
        'Service notifications, public engagement campaigns, and resident segmentation each carry their own compliance posture — the configurator maps it before the work begins.'
};

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
            desc: ind.pickerBlurb || PICKER_BLURBS[ind.industryKey] || '',
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
