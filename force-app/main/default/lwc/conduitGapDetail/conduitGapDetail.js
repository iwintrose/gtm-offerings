import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getGapDetail      from '@salesforce/apex/ConduitPlanController.getGapDetail';
import getStoredPlanData from '@salesforce/apex/ConduitPlanController.getStoredPlanData';

export default class ConduitGapDetail extends LightningElement {
    @api recordId;

    @track gapData        = null;
    @track isLoading      = false;
    @track error          = null;

    severityFilter = 'all';
    _wiredStoredData;

    @wire(getStoredPlanData, { assessmentId: '$recordId' })
    wiredStoredData(result) {
        this._wiredStoredData = result;
        if (result.data && result.data.Gap_Detail__c) {
            try { this.gapData = this._enrich(JSON.parse(result.data.Gap_Detail__c)); } catch { /* ignore */ }
        }
    }

    // Called by the dashboard when the active CMM changes. Refreshes the wire
    // that pulls stored gap-detail — the display still shows the last run's
    // findings until user clicks Re-analyze Gaps against the new CMM.
    @api async refresh() {
        if (this._wiredStoredData) { try { await refreshApex(this._wiredStoredData); } catch { /* ignore */ } }
    }

    get showInitial()   { return !this.isLoading && !this.gapData && !this.error; }
    get hasData()       { return !!this.gapData && !this.isLoading; }
    get hasSummary()    { return !!this.gapData?.summary; }
    get buttonLabel()   { return this.gapData ? 'Re-analyze Gaps' : 'Run Gap Analysis'; }

    get subtitle() {
        // platformMatch carries effectiveId for both sides (from resolvePlatforms).
        const src = this._displayName(this.gapData?.platformMatch?.source?.effectiveId);
        const tgt = this._displayName(this.gapData?.platformMatch?.target?.effectiveId);
        if (src && tgt) {
            return `Every structural gap between your ${src} estate and ${tgt} — blockers, warnings, and notes — with Claude-generated remediation guidance for each one.`;
        }
        return 'Every structural gap between your source estate and the target platform — blockers, warnings, and notes — with Claude-generated remediation guidance for each one.';
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

    get filteredGaps() {
        if (!this.gapData) return [];
        if (this.severityFilter === 'all') return this.gapData.gaps;
        return this.gapData.gaps.filter(g => g.severity === this.severityFilter);
    }

    get severityFilters() {
        const d = this.gapData;
        const bs = d?.bySeverity ?? {};
        const active = this.severityFilter;
        return [
            { value: 'all',     label: 'All (' + (d?.total ?? 0) + ')',              cls: 'filter-btn' + (active === 'all'     ? ' filter-active' : '') },
            { value: 'blocker', label: 'Blockers (' + (bs.blocker ?? 0) + ')',       cls: 'filter-btn' + (active === 'blocker' ? ' filter-active' : '') },
            { value: 'warning', label: 'Warnings (' + (bs.warning ?? 0) + ')',       cls: 'filter-btn' + (active === 'warning' ? ' filter-active' : '') },
            { value: 'info',    label: 'Info (' + (bs.info ?? 0) + ')',              cls: 'filter-btn' + (active === 'info'    ? ' filter-active' : '') },
        ];
    }

    async handleRunGapDetail() {
        this.isLoading = true;
        this.error = null;
        try {
            const raw = await getGapDetail({ assessmentId: this.recordId });
            this.gapData = this._enrich(JSON.parse(raw));
            await refreshApex(this._wiredStoredData);
        } catch (err) {
            this.error = err?.body?.message ?? err?.message ?? 'Gap analysis failed';
        } finally {
            this.isLoading = false;
        }
    }

    handleSeverityFilter(event) {
        this.severityFilter = event.currentTarget.dataset.filter;
    }

    _enrich(data) {
        return {
            ...data,
            gaps: (data.gaps ?? []).map(g => ({
                ...g,
                severityClass:  'gap-severity gap-' + g.severity,
                hasRemediation: !!g.remediation,
            })),
        };
    }
}