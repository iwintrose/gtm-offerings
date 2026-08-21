import { LightningElement, api, track } from 'lwc';

const FONTS_HREF =
    'https://fonts.googleapis.com/css2?family=Sora:wght@500;600;700;800&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap';

const INDUSTRIES = [
    {
        key: 'fintech',
        label: 'Financial Services',
        desc: 'Consent, disclosures, and audit trails, under the regulator’s eye.'
    },
    {
        key: 'medtech',
        label: 'MedTech',
        desc: 'MLR-approved content and HCP/patient lines that can’t blur.'
    },
    {
        key: 'lifesci',
        label: 'Life Sciences',
        desc: 'Regulated content, global markets, approval lineage.'
    },
    {
        key: 'media',
        label: 'Media & Entertainment',
        desc: 'Many brands, millions of subscribers, daily cadence.'
    },
    {
        key: 'transport',
        label: 'Transportation & Logistics',
        desc: 'Operational, real-time, triggered comms people rely on.'
    },
    {
        key: 'government',
        label: 'Government & Public Sector',
        desc: 'Accessible, secure, plain-language citizen comms.'
    },
    {
        key: 'municipal',
        label: 'Municipal & Civic',
        desc: 'Alerts and services across departments, on lean teams.'
    }
];

export default class ChooseIndustry extends LightningElement {
    /** Back link target. Set in Experience Builder. */
    @api offeringsUrl = '/';
    /** Configurator page. Industry is appended as ?industry=<key>. */
    @api configuratorUrl = '/configurator';

    @track theme = null; // null = follow system

    get rootClass() {
        if (this.theme === 'dark') return 'ci-root dark';
        if (this.theme === 'light') return 'ci-root light';
        return 'ci-root';
    }

    get industries() {
        const base = this.configuratorUrl || '/configurator';
        const joiner = base.indexOf('?') === -1 ? '?' : '&';
        return INDUSTRIES.map((ind) => ({
            key: ind.key,
            label: ind.label,
            desc: ind.desc,
            href: `${base}${joiner}industry=${encodeURIComponent(ind.key)}`
        }));
    }

    connectedCallback() {
        this.loadFonts();
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
