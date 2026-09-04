import { LightningElement, api, track } from 'lwc';
import getStoryContent from '@salesforce/apex/MaStoryContentController.getStoryContent';

const FONTS_HREF =
    'https://fonts.googleapis.com/css2?family=Sora:wght@500;600;700;800&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap';

const OFFERING_KEY = 'migration-accelerator';

function buildBuilderUrl(orgUrl) {
    // The previous per-site deep link (/apex/networkbranding) pointed at a
    // page that does not exist in this org. Digital Experiences > All Sites
    // is the one Setup route guaranteed to exist; from there "Builder" opens
    // the right site in one more click.
    if (!orgUrl) return '#';
    return `${orgUrl}/lightning/setup/SetupNetworks/home`;
}

export default class OfferingChooser extends LightningElement {
    /** Where the Migration Accelerator tile points. Set in Experience Builder. */
    @api industryUrl = '/choose-industry';

    @track theme = null;
    @track _tileDescription = null;
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

    get tileDescription() {
        return this._tileDescription ||
            'Reads a client\'s marketing platform directly, turns it into an audited plan, and where it applies, a finished migration.';
    }

    get builderUrl() { return buildBuilderUrl(this._orgUrl); }

    connectedCallback() {
        this.loadFonts();
        this._editModeHandler = (evt) => { this._editMode = evt.detail.active; };
        window.addEventListener('maadminedit', this._editModeHandler);
        getStoryContent({ offeringKey: OFFERING_KEY })
            .then((data) => {
                if (data && data.setting) this._tileDescription = data.setting.offeringTileDescription;
                this._orgUrl = (data && data.orgUrl) || '';
                this._lightningUrl = (data && data.lightningUrl) || '';
                this._sites = (data && data.sites) || [];
            })
            // eslint-disable-next-line no-console
            .catch((err) => { console.error('[offeringChooser] getStoryContent:', JSON.stringify(err)); });
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
