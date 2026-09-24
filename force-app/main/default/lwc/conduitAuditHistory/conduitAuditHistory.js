import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getAuditHistory from '@salesforce/apex/ConduitPlanController.getAuditHistory';

export default class ConduitAuditHistory extends LightningElement {
    @api recordId;

    auditRuns = [];
    error     = null;
    _wiredHistory;

    @wire(getAuditHistory, { assessmentId: '$recordId' })
    wiredHistory(result) {
        this._wiredHistory = result;
        if (result.data)  { this.auditRuns = result.data; this.error = null; }
        if (result.error) { this.error = result.error?.body?.message ?? 'Failed to load history'; }
    }

    // Called by the dashboard when a sibling (audit panel) finishes a new run,
    // so the history list picks up the freshly-inserted Conduit_Audit__c row.
    @api async refresh() {
        try { await refreshApex(this._wiredHistory); }
        catch (err) { this.error = err?.body?.message ?? 'Failed to refresh history'; }
    }

    get hasHistory() { return this.auditRuns.length > 0; }
    get isEmpty()    { return !this.error && this.auditRuns.length === 0; }

    get hasTrend() { return this.auditRuns.length >= 2; }

    get trend() {
        if (!this.hasTrend) return null;
        const latest = this.auditRuns[0].Health_Score__c ?? 0;
        const oldest = this.auditRuns[this.auditRuns.length - 1].Health_Score__c ?? 0;
        const delta  = latest - oldest;
        return {
            direction: delta > 0 ? 'improved' : delta < 0 ? 'declined' : 'unchanged',
            points:    Math.abs(delta),
            arrow:     delta > 0 ? '▲' : delta < 0 ? '▼' : '—',
        };
    }

    get trendBannerClass() {
        const t = this.trend;
        if (!t) return 'trend-banner';
        return 'trend-banner trend-' + (t.direction === 'improved' ? 'up' : t.direction === 'declined' ? 'down' : 'flat');
    }

    get historyWithDelta() {
        return this.auditRuns.map((run, i) => {
            const score    = run.Health_Score__c ?? 0;
            const prev     = i < this.auditRuns.length - 1 ? (this.auditRuns[i + 1].Health_Score__c ?? 0) : null;
            const delta    = prev !== null ? score - prev : null;
            const hasDelta = delta !== null && i < this.auditRuns.length - 1;
            return {
                ...run,
                runAtFormatted:  run.Run_At__c ? new Date(run.Run_At__c).toLocaleString() : '—',
                confidencePct:   run.Migration_Confidence__c != null ? Math.round(run.Migration_Confidence__c * 100) : '—',
                scoreClass:      this._scoreClass(score),
                itemClass:       'history-item history-item-' + this._scoreTier(score),
                hasDelta,
                deltaLabel:      hasDelta ? (delta > 0 ? '▲ ' + delta + ' pts' : delta < 0 ? '▼ ' + Math.abs(delta) + ' pts' : '— ') : '',
                deltaClass:      hasDelta ? ('delta-badge delta-' + (delta > 0 ? 'up' : delta < 0 ? 'down' : 'flat')) : '',
            };
        });
    }

    _scoreClass(s) {
        if (s >= 70) return 'score-badge score-good';
        if (s >= 40) return 'score-badge score-warn';
        return 'score-badge score-bad';
    }
    _scoreTier(s) {
        if (s >= 70) return 'good';
        if (s >= 40) return 'warn';
        return 'bad';
    }
}