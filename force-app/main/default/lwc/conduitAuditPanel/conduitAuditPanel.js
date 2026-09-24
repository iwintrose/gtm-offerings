import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import runAudit from '@salesforce/apex/ConduitAuditController.runAudit';
import getLastAudit from '@salesforce/apex/ConduitAuditController.getLastAudit';

export default class ConduitAuditPanel extends LightningElement {
    @api recordId;

    @track auditResult = null;
    @track isLoading   = false;
    @track error       = null;

    _wiredAudit;

    @wire(getLastAudit, { assessmentId: '$recordId' })
    wiredAudit(result) {
        this._wiredAudit = result;
        if (result.data) {
            this.auditResult = this._hydrateFromRecord(result.data);
            this.error = null;
        }
    }

    // Called by the dashboard when the active CMM changes. Refreshes the wire
    // that pulls the last stored audit — the panel keeps showing the previous
    // audit's findings until user clicks Re-run Analysis against the new CMM.
    @api async refresh() {
        if (this._wiredAudit) { try { await refreshApex(this._wiredAudit); } catch { /* ignore */ } }
    }

    // ── Visibility ──────────────────────────────────────────────────────────
    get showInitial() { return !this.isLoading && !this.auditResult && !this.error; }

    // ── Audit ───────────────────────────────────────────────────────────────
    get freshness() { return this.auditResult?.freshness ?? {}; }

    get scoreClass() {
        const s = this.auditResult?.healthScore ?? 0;
        const base = 'slds-text-heading_large stat-value score-number ';
        if (s >= 70) return base + 'slds-text-color_success';
        if (s >= 40) return base + 'score-warning';
        return base + 'slds-text-color_error';
    }

    get scoreLabel() {
        const s = this.auditResult?.healthScore ?? 0;
        if (s >= 70) return 'Good shape';
        if (s >= 40) return 'Needs attention';
        return 'Significant work required';
    }

    get severityRows() {
        const sum = this.auditResult?.summary ?? {};
        return [
            { label: 'High',   count: sum.high   ?? 0, cssClass: 'slds-text-heading_large slds-text-color_error' },
            { label: 'Medium', count: sum.medium  ?? 0, cssClass: 'slds-text-heading_large score-warning' },
            { label: 'Low',    count: sum.low     ?? 0, cssClass: 'slds-text-heading_large slds-text-color_weak' },
            { label: 'Info',   count: sum.info    ?? 0, cssClass: 'slds-text-heading_large slds-text-color_weak' },
        ];
    }

    // ── Migration plan ──────────────────────────────────────────────────────
    get hasMigrationPlan() { return !!this.auditResult?.migrationPlan; }

    get migrationPlan() { return this.auditResult?.migrationPlan ?? {}; }

    get confidencePct() {
        const c = this.auditResult?.migrationPlan?.averageConfidence ?? 0;
        return Math.round(c * 100);
    }

    // ── Gap analysis ────────────────────────────────────────────────────────
    get hasGapAnalysis() { return !!this.auditResult?.gapAnalysis?.summary; }

    get hasGapItems() { return (this.auditResult?.gapAnalysis?.items?.length ?? 0) > 0; }

    // ── Misc ────────────────────────────────────────────────────────────────
    get formattedRunAt() {
        if (!this.auditResult?.runAt) return '';
        return new Date(this.auditResult.runAt).toLocaleString();
    }

    get platformLabel() {
        const src = this.auditResult?.sourcePlatform;
        const tgt = this.auditResult?.targetPlatform;
        if (src && tgt) return `${src} → ${tgt}`;
        if (src) return `Source: ${src}`;
        return '';
    }

    // ── Platform-fallback warnings ─────────────────────────────────────────
    // Read from platformMatch (present only on fresh API responses; stored
    // Conduit_Audit__c records don't carry it, so hydrated views won't warn).
    get platformWarnings() {
        const pm = this.auditResult?.platformMatch;
        if (!pm) return [];
        const out = [];
        if (pm.source?.fellBack) {
            out.push({
                key: 'source',
                message: pm.source.reason
                    ?? `Source platform "${pm.source.raw ?? '(none)'}" isn't supported — analysis is using ${pm.source.effectiveId} defaults.`,
            });
        }
        if (pm.target?.fellBack) {
            out.push({
                key: 'target',
                message: pm.target.reason
                    ?? `Target platform "${pm.target.raw ?? '(none)'}" isn't supported — analysis is using ${pm.target.effectiveId} defaults.`,
            });
        }
        return out;
    }

    get hasPlatformWarnings() { return this.platformWarnings.length > 0; }

    // ── Actions ─────────────────────────────────────────────────────────────
    async handleRun() {
        this.isLoading = true;
        this.error = null;
        try {
            const raw = await runAudit({ assessmentId: this.recordId });
            this.auditResult = raw;
            await refreshApex(this._wiredAudit);
            // Notify siblings (audit history) that a new Conduit_Audit__c row exists.
            this.dispatchEvent(new CustomEvent('auditcomplete', { bubbles: true, composed: true }));
        } catch (err) {
            this.error = err?.body?.message ?? err?.message ?? 'Unknown error';
        } finally {
            this.isLoading = false;
        }
    }

    // Rebuild the API response shape from a stored Conduit_Audit__c record.
    _hydrateFromRecord(rec) {
        let gapItems = [];
        try { gapItems = rec.Gap_Analysis_Items__c ? JSON.parse(rec.Gap_Analysis_Items__c) : []; }
        catch { /* stored value unparseable — show summary only */ }

        let findingsByRule = {};
        try { findingsByRule = rec.Findings_Summary__c ? JSON.parse(rec.Findings_Summary__c) : {}; }
        catch { /* ignore */ }

        return {
            healthScore:      rec.Health_Score__c,
            sourcePlatform:   rec.Source_Platform__c,
            targetPlatform:   rec.Target_Platform__c ?? null,
            runAt:            rec.Run_At__c,
            totalAssets:      rec.Total_Assets__c,
            totalAudiences:   rec.Total_Audiences__c,
            totalDataObjects: rec.Total_Data_Objects__c,
            freshness: {
                active:    rec.Freshness_Active__c    ?? 0,
                recent:    rec.Freshness_Recent__c    ?? 0,
                stale:     rec.Freshness_Stale__c     ?? 0,
                abandoned: rec.Freshness_Abandoned__c ?? 0,
            },
            summary: findingsByRule,
            topFindings: [],
            migrationPlan: rec.Migration_Steps__c != null ? {
                toCreate:          rec.Migration_Steps__c,
                totalGaps:         rec.Migration_Gaps__c      ?? 0,
                blockers:          0,
                averageConfidence: rec.Migration_Confidence__c ?? 0,
            } : null,
            gapAnalysis: rec.Gap_Analysis_Summary__c ? {
                summary: rec.Gap_Analysis_Summary__c,
                items:   gapItems,
            } : null,
        };
    }
}