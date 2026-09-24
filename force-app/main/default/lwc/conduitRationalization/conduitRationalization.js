import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getRationalization from '@salesforce/apex/ConduitPlanController.getRationalization';
import getStoredPlanData  from '@salesforce/apex/ConduitPlanController.getStoredPlanData';

export default class ConduitRationalization extends LightningElement {
    @api recordId;

    @track rationalizationData = null;
    @track isLoading           = false;
    @track error               = null;

    _wiredStoredData;

    get showInitial() { return !this.isLoading && !this.rationalizationData && !this.error; }
    get hasData()     { return !!this.rationalizationData && !this.isLoading; }

    get hasRetire()      { return (this.rationalizationData?.retire?.length ?? 0) > 0; }
    get hasConsolidate() { return (this.rationalizationData?.consolidate?.length ?? 0) > 0; }
    get hasReview()      { return (this.rationalizationData?.review?.length ?? 0) > 0; }
    get hasAiData()      { return !!this.rationalizationData?.aiPrioritization?.summary; }
    get aiData()         { return this.rationalizationData?.aiPrioritization ?? null; }

    @wire(getStoredPlanData, { assessmentId: '$recordId' })
    wiredStoredData(result) {
        this._wiredStoredData = result;
        if (result.data && result.data.Rationalization_Items__c) {
            try {
                const data = JSON.parse(result.data.Rationalization_Items__c);
                this.rationalizationData = this._enrich(data);
            } catch { /* ignore — user can re-run */ }
        }
    }

    // Called by the dashboard when the active CMM changes. Refreshes the wire
    // that pulls stored rationalization — display still shows the last run's
    // items until user clicks Analyse Real Estate against the new CMM.
    @api async refresh() {
        if (this._wiredStoredData) { try { await refreshApex(this._wiredStoredData); } catch { /* ignore */ } }
    }

    async handleAnalyze() {
        this.isLoading = true;
        this.error     = null;
        this.rationalizationData = null;
        try {
            const raw = await getRationalization({ assessmentId: this.recordId });
            this.rationalizationData = this._enrich(JSON.parse(raw));
        } catch (err) {
            this.error = err?.body?.message ?? err?.message ?? 'Rationalization failed';
        } finally {
            this.isLoading = false;
        }
    }

    _enrich(data) {
        if (data.consolidate) {
            data.consolidate = data.consolidate.map(g => ({
                ...g,
                namesStr: (g.names ?? []).join(' / '),
            }));
        }
        if (data.aiPrioritization?.prioritized) {
            data.aiPrioritization.prioritized = data.aiPrioritization.prioritized.map(item => ({
                ...item,
                assetNamesStr: (item.assetNames ?? []).join(', '),
                actionClass: 'action-badge action-' + item.action,
            }));
        }
        return data;
    }
}