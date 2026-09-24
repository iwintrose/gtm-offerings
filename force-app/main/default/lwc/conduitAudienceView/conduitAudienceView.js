import { LightningElement, api, track } from 'lwc';
import getAudiences from '@salesforce/apex/ConduitPlanController.getAudiences';

const KIND_LABELS = {
    static_list:      'Static List',
    filtered_segment: 'Filtered Segment',
    object_audience:  'Object Audience',
    all_subscribers:  'All Subscribers',
};

export default class ConduitAudienceView extends LightningElement {
    @api recordId;

    @track audienceData = null;
    @track isLoading    = false;
    @track error        = null;

    riskFilter = 'all';
    kindFilter = 'all';

    connectedCallback() { this.handleLoad(); }

    // Called by the dashboard when the active CMM changes. Re-fetches so the
    // tab reflects the new CMM's audiences.
    @api refresh() { this.handleLoad(); }

    get showInitial() { return !this.isLoading && !this.audienceData && !this.error; }
    get hasData()     { return !!this.audienceData && !this.isLoading; }

    get subtitle() {
        const src = this._displayName(this.audienceData?.sourcePlatform);
        const tgt = this._displayName(this.audienceData?.targetPlatform);
        if (src && tgt) {
            return `All audiences in your ${src} estate — static lists, filtered segments, and object audiences — scored by migration complexity and flagged where ${tgt} rebuild will require rework.`;
        }
        if (src) {
            return `All audiences in your ${src} estate — static lists, filtered segments, and object audiences — scored by migration complexity and flagged where target-platform rebuild will require rework.`;
        }
        return 'All audiences in the estate — static lists, filtered segments, and object audiences — scored by migration complexity and flagged where rebuild will require rework.';
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

    get filteredAudiences() {
        if (!this.audienceData) return [];
        return this.audienceData.audiences.filter(a => {
            const riskOk = this.riskFilter === 'all' || a.riskLevel === this.riskFilter;
            const kindOk = this.kindFilter === 'all' || a.kind === this.kindFilter;
            return riskOk && kindOk;
        });
    }

    get riskFilters() {
        const s  = this.audienceData?.summary ?? {};
        const br = s.byRisk ?? {};
        const active = this.riskFilter;
        return [
            { value: 'all',    label: 'All (' + (s.total ?? 0) + ')',       cls: 'filter-btn' + (active === 'all'    ? ' filter-active' : '') },
            { value: 'high',   label: 'High (' + (br.high ?? 0) + ')',      cls: 'filter-btn' + (active === 'high'   ? ' filter-active' : '') },
            { value: 'medium', label: 'Medium (' + (br.medium ?? 0) + ')',  cls: 'filter-btn' + (active === 'medium' ? ' filter-active' : '') },
            { value: 'low',    label: 'Low (' + (br.low ?? 0) + ')',        cls: 'filter-btn' + (active === 'low'    ? ' filter-active' : '') },
        ];
    }

    get kindFilters() {
        const s  = this.audienceData?.summary ?? {};
        const bk = s.byKind ?? {};
        const active = this.kindFilter;
        return [
            { value: 'all',              label: 'All',                                             cls: 'filter-btn' + (active === 'all'              ? ' filter-active' : '') },
            { value: 'static_list',      label: 'Static Lists (' + (bk.static_list ?? 0) + ')',   cls: 'filter-btn' + (active === 'static_list'      ? ' filter-active' : '') },
            { value: 'filtered_segment', label: 'Segments (' + (bk.filtered_segment ?? 0) + ')',  cls: 'filter-btn' + (active === 'filtered_segment' ? ' filter-active' : '') },
            { value: 'object_audience',  label: 'Objects (' + (bk.object_audience ?? 0) + ')',    cls: 'filter-btn' + (active === 'object_audience'  ? ' filter-active' : '') },
        ];
    }

    async handleLoad() {
        this.isLoading = true;
        this.error = null;
        try {
            const raw  = await getAudiences({ assessmentId: this.recordId });
            const data = JSON.parse(raw);
            data.audiences = (data.audiences ?? []).map(a => ({
                ...a,
                kindLabel:    KIND_LABELS[a.kind] ?? a.kind,
                kindClass:    'kind-badge kind-' + a.kind.split('_').join('-'),
                riskClass:    'risk-pill risk-' + a.riskLevel,
                sizeLabel:    a.sizeEstimate != null ? Number(a.sizeEstimate).toLocaleString() : '—',
                complexLabel: a.filterComplexity.conditionCount > 0
                                ? a.filterComplexity.conditionCount + ' cond., depth ' + a.filterComplexity.depth
                                : '—',
                hasGap: !!a.gap,
            }));
            this.audienceData = data;
        } catch (err) {
            this.error = err?.body?.message ?? err?.message ?? 'Failed to load audiences';
        } finally {
            this.isLoading = false;
        }
    }

    handleRiskFilter(event) { this.riskFilter = event.currentTarget.dataset.filter; }
    handleKindFilter(event) { this.kindFilter = event.currentTarget.dataset.filter; }
}