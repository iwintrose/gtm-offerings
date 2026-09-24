import { LightningElement, api, track } from 'lwc';
import getAssets from '@salesforce/apex/ConduitPlanController.getAssets';

const TYPE_LABELS      = { email: 'Email', landing_page: 'Landing Page', snippet: 'Snippet' };
const FRESHNESS_LABELS = { active: 'Active', recent: 'Recent', stale: 'Stale', abandoned: 'Abandoned' };

export default class ConduitAssetExplorer extends LightningElement {
    @api recordId;

    @track assets          = [];
    @track summary         = { total: 0, active: 0, recent: 0, stale: 0, abandoned: 0, byType: { email: 0, landing_page: 0, snippet: 0 } };
    @track sourcePlatform  = null;
    @track isLoadingAssets = false;
    @track error           = null;

    typeFilter      = 'all';
    freshnessFilter = 'all';

    connectedCallback() { this.handleLoadAssets(); }

    // Called by the dashboard when the active CMM changes (new upload or
    // manual Set Active). Re-fetches so the tab reflects the new CMM's assets.
    @api refresh() { this.handleLoadAssets(); }

    get hasAssets() { return !this.isLoadingAssets && !this.error && this.assets.length > 0; }

    get subtitle() {
        const p = this._displayName(this.sourcePlatform);
        if (!p) return 'Catalogues all content assets in the estate — emails, landing pages, and snippets — with freshness tags showing what is actively used, recently modified, going stale, or effectively abandoned.';
        return `Catalogues all content assets in your ${p} estate — emails, landing pages, and snippets — with freshness tags showing what is actively used, recently modified, going stale, or effectively abandoned.`;
    }

    _displayName(id) {
        switch (id) {
            case 'sfmc':   return 'SFMC';
            case 'pardot': return 'Pardot';
            case 'eloqua': return 'Eloqua';
            case 'figma':  return 'Figma';
            default:       return null;
        }
    }

    get filteredAssets() {
        return this.assets.filter(a => {
            const typeOk      = this.typeFilter === 'all'      || a.type === this.typeFilter;
            const freshnessOk = this.freshnessFilter === 'all' || a.freshnessTag === this.freshnessFilter;
            return typeOk && freshnessOk;
        });
    }

    get typeFilters() {
        const s = this.summary;
        const bt = s.byType ?? {};
        const active = this.typeFilter;
        return [
            { value: 'all',          label: 'All (' + s.total + ')',                       cls: 'filter-btn' + (active === 'all'          ? ' filter-active' : '') },
            { value: 'email',        label: 'Emails (' + (bt.email ?? 0) + ')',            cls: 'filter-btn' + (active === 'email'        ? ' filter-active' : '') },
            { value: 'landing_page', label: 'Landing Pages (' + (bt.landing_page ?? 0) + ')', cls: 'filter-btn' + (active === 'landing_page' ? ' filter-active' : '') },
            { value: 'snippet',      label: 'Snippets (' + (bt.snippet ?? 0) + ')',        cls: 'filter-btn' + (active === 'snippet'      ? ' filter-active' : '') },
        ];
    }

    get freshnessFilters() {
        const s = this.summary;
        const active = this.freshnessFilter;
        return [
            { value: 'all',       label: 'All',                       cls: 'filter-btn' + (active === 'all'       ? ' filter-active' : '') },
            { value: 'active',    label: 'Active (' + s.active + ')',    cls: 'filter-btn' + (active === 'active'    ? ' filter-active' : '') },
            { value: 'recent',    label: 'Recent (' + s.recent + ')',    cls: 'filter-btn' + (active === 'recent'    ? ' filter-active' : '') },
            { value: 'stale',     label: 'Stale (' + s.stale + ')',      cls: 'filter-btn' + (active === 'stale'     ? ' filter-active' : '') },
            { value: 'abandoned', label: 'Abandoned (' + s.abandoned + ')',cls: 'filter-btn' + (active === 'abandoned' ? ' filter-active' : '') },
        ];
    }

    handleTypeFilter(event) {
        this.typeFilter = event.currentTarget.dataset.filter;
    }

    handleFreshnessFilter(event) {
        this.freshnessFilter = event.currentTarget.dataset.filter;
    }

    async handleLoadAssets() {
        this.isLoadingAssets = true;
        this.error = null;
        try {
            const raw  = await getAssets({ assessmentId: this.recordId });
            const data = JSON.parse(raw);
            this.summary        = data.summary;
            this.sourcePlatform = data.sourcePlatform ?? null;
            this.assets         = (data.assets ?? []).map(a => this._enrichAsset(a));
        } catch (err) {
            this.error = err?.body?.message ?? err?.message ?? 'Failed to load assets';
        } finally {
            this.isLoadingAssets = false;
        }
    }

    _enrichAsset(a) {
        return {
            ...a,
            typeLabel:            TYPE_LABELS[a.type] ?? a.type,
            typeClass:            'type-badge type-' + a.type,
            freshnessLabel:       FRESHNESS_LABELS[a.freshnessTag] ?? a.freshnessTag,
            freshnessClass:       'freshness-pill freshness-' + a.freshnessTag,
            lastModifiedFormatted: a.lastModified ? new Date(a.lastModified).toLocaleDateString() : '—',
            lastCampaignFormatted: a.lastCampaignUse ? new Date(a.lastCampaignUse).toLocaleDateString() : 'None',
        };
    }
}