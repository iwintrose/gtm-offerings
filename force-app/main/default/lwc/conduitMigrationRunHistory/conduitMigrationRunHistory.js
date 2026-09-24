import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import listRuns from '@salesforce/apex/ConduitMigrationController.listRuns';

// Compact history view for the assessment's Conduit_Migration_Run__c records.
// Purpose: SA opens the tab, sees every prior run's outcome at a glance
// (status pill, counts, target, timestamp), can click into any run for full
// step-level detail on the record page.
//
// Deliberately does NOT re-render step tables inline — the run record page is
// canonical for that. This LWC is a router / dashboard.

export default class ConduitMigrationRunHistory extends NavigationMixin(LightningElement) {
    @api recordId;                 // GTM_Assessment_Request__c Id
    @track runs      = [];
    @track isLoading = true;
    @track loadError = null;

    _wired;

    @wire(listRuns, { assessmentId: '$recordId' })
    wired(result) {
        this._wired = result;
        this.isLoading = false;
        if (result.error) {
            this.loadError = result.error?.body?.message ?? 'Failed to load migration runs.';
            this.runs = [];
            return;
        }
        this.loadError = null;
        this.runs = (result.data ?? []).map(r => this._decorate(r));
    }

    get hasRuns()  { return !this.isLoading && this.runs.length > 0; }
    get isEmpty()  { return !this.isLoading && !this.loadError && this.runs.length === 0; }

    get summary() {
        if (!this.runs.length) return null;
        const s = { total: 0, applied: 0, failed: 0, skipped: 0, runs: this.runs.length };
        for (const r of this.runs) {
            s.total   += r.total   ?? 0;
            s.applied += r.succeeded ?? 0;
            s.failed  += r.failed  ?? 0;
            s.skipped += r.skipped ?? 0;
        }
        return s;
    }

    async handleRefresh() {
        this.isLoading = true;
        try { await refreshApex(this._wired); }
        finally { this.isLoading = false; }
    }

    handleOpenRun(e) {
        const runId = e.currentTarget.dataset.runId;
        if (!runId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: runId,
                objectApiName: 'Conduit_Migration_Run__c',
                actionName: 'view',
            },
        });
    }

    // ── @api hook for the dashboard's cross-tab refresh pattern ────────────
    @api async refresh() {
        if (this._wired) { try { await refreshApex(this._wired); } catch { /* ignore */ } }
    }

    // ── Helpers ────────────────────────────────────────────────────────────
    _decorate(r) {
        const status = r.Status__c ?? 'Unknown';
        const started = r.Started_At__c ? new Date(r.Started_At__c) : null;
        const completed = r.Completed_At__c ? new Date(r.Completed_At__c) : null;
        const durationMs = started && completed ? completed - started : null;
        // First N error lines from the joined error summary — enough to spot
        // patterns without opening the record.
        const errorLines = (r.Error_Summary__c ?? '')
            .split('\n').filter(l => l.trim().length > 0).slice(0, 3);

        const skip = this._parseSkipSummary(r.Skip_Summary__c);

        return {
            id:              r.Id,
            name:            r.Name,
            status,
            statusClass:     'run-pill run-status-' + status.toLowerCase().replace(/\s+/g, '-'),
            startedLabel:    started ? started.toLocaleString() : '—',
            duration:        durationMs != null ? this._formatDuration(durationMs) : '—',
            startedBy:       r.Started_By__r?.Name ?? '—',
            targetConfig:    r.Target_Config__c ?? '—',
            rollbackEnabled: r.Rollback_Enabled__c === true,
            total:           r.Total_Steps__c ?? 0,
            succeeded:       r.Steps_Succeeded__c ?? 0,
            failed:          r.Steps_Failed__c ?? 0,
            skipped:         r.Steps_Skipped__c ?? 0,
            hasErrors:       (r.Steps_Failed__c ?? 0) > 0 && errorLines.length > 0,
            errorLines:      errorLines.map((line, i) => ({ key: i, text: line })),
            skipBreakdown:   skip.chips,
            hasSkipBreakdown: skip.chips.length > 0,
            haltNote:        skip.haltNote,
        };
    }

    // Skip_Summary__c is a JSON blob written by the Apex controller — shape:
    //   { "byCategory": { "halted": 2, "already_exists": 4 },
    //     "haltCause":  { "order": 8, "entityName": "..." } | null }
    // Old runs (before the field existed) return null / empty → no chips shown.
    _parseSkipSummary(raw) {
        if (!raw) return { chips: [], haltNote: null };
        let parsed;
        try { parsed = JSON.parse(raw); }
        catch { return { chips: [], haltNote: null }; }

        const byCat = parsed?.byCategory ?? {};
        const chips = [];
        // Fixed display order (severity/salience desc) so the chip row reads
        // consistently across runs — halts first (they block work), then
        // Phase-A limits (persistent gaps), then already_exists (benign).
        const order = [
            { key: 'halted',                label: 'Halted',                 cls: 'skip-chip skip-halted' },
            { key: 'unknown_entity_type',   label: 'Unknown entity',         cls: 'skip-chip skip-unknown' },
            { key: 'phase_a_content_asset', label: 'Content asset (Phase B)',cls: 'skip-chip skip-phase-a' },
            { key: 'plan_marked_skip',      label: 'Plan-level skip',        cls: 'skip-chip skip-plan' },
            { key: 'already_exists',        label: 'Already existed',        cls: 'skip-chip skip-exists' },
        ];
        for (const o of order) {
            const n = byCat[o.key] ?? 0;
            if (n > 0) chips.push({ key: o.key, label: `${o.label} ${n}`, cls: o.cls });
        }

        const halt = parsed?.haltCause;
        const haltNote = halt
            ? `Halted after step ${halt.order} (${halt.entityName}) failed.`
            : null;

        return { chips, haltNote };
    }

    _formatDuration(ms) {
        const s = Math.round(ms / 1000);
        if (s < 60) return `${s}s`;
        const m = Math.floor(s / 60);
        const rs = s - m * 60;
        return `${m}m ${rs}s`;
    }
}