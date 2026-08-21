import { LightningElement, api, track } from 'lwc';

const FONTS_HREF =
    'https://fonts.googleapis.com/css2?family=Sora:wght@500;600;700;800&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap';

export default class OfferingChooser extends LightningElement {
    /** Where the Migration Accelerator tile points. Set in Experience Builder. */
    @api industryUrl = '/choose-industry';

    @track theme = null; // null = follow system

    get rootClass() {
        if (this.theme === 'dark') return 'oc-root dark';
        if (this.theme === 'light') return 'oc-root light';
        return 'oc-root';
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
