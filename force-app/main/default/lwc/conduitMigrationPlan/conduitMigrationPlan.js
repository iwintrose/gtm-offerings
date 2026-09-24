import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getMigrationPlan  from '@salesforce/apex/ConduitPlanController.getMigrationPlan';
import runScopeEstimate  from '@salesforce/apex/ConduitPlanController.runScopeEstimate';
import runWaveNotes      from '@salesforce/apex/ConduitPlanController.runWaveNotes';
import getStoredPlanData from '@salesforce/apex/ConduitPlanController.getStoredPlanData';

const WAVE_COLORS = ['wave-card-blue', 'wave-card-green', 'wave-card-orange'];
const WAVE_BADGE  = ['badge-blue', 'badge-green', 'badge-orange'];

export default class ConduitMigrationPlan extends LightningElement {
    @api recordId;

    @track planData           = null;
    @track scopeEstimate      = null;
    @track waveNotes          = null;
    @track isLoadingPlan      = false;
    @track isLoadingScope     = false;
    @track isLoadingWaveNotes = false;
    @track error              = null;
    @track expandedWaves      = {};

    _wiredStoredData;

    connectedCallback() { this.handleLoadPlan(); }

    // Called by the dashboard when the active CMM changes. The main plan re-
    // fetches against the new CMM. Stored AI results (scope estimate, wave
    // notes) refresh their wire but reflect the previous run — user must click
    // regenerate to update those against the new CMM.
    @api async refresh() {
        await this.handleLoadPlan();
        if (this._wiredStoredData) { try { await refreshApex(this._wiredStoredData); } catch { /* ignore */ } }
    }

    @wire(getStoredPlanData, { assessmentId: '$recordId' })
    wiredStoredData(result) {
        this._wiredStoredData = result;
        if (result.data) {
            if (result.data.Scope_Estimate__c) {
                try {
                    const raw = JSON.parse(result.data.Scope_Estimate__c);
                    this.scopeEstimate = {
                        ...raw,
                        waves: (raw.waves ?? []).map(w => ({ ...w, riskClass: 'risk-' + (w.riskLevel ?? 'medium') })),
                    };
                } catch { /* ignore */ }
            }
            if (result.data.Wave_Notes__c) {
                try { this.waveNotes = JSON.parse(result.data.Wave_Notes__c); } catch { /* ignore */ }
            }
        }
    }

    // ── Visibility ──────────────────────────────────────────────────────────
    get showInitial() { return !this.isLoadingPlan && !this.planData && !this.error; }

    // ── Dynamic subtitle ────────────────────────────────────────────────────
    // Before the plan loads, generic text. After load, references the actual
    // resolved source + target platforms from the API response.
    get planSubtitle() {
        const src = this.planData?.sourcePlatform;
        const tgt = this.planData?.targetPlatform;
        if (src && tgt) {
            return `Organizes your ${this._displayName(src)} estate into sequenced ${this._displayName(tgt)} migration waves — Foundation, Audiences, and Content — with per-step confidence scores, structural gap flags, and an optional AI scope and wave notes estimate.`;
        }
        return `Organizes your marketing estate into sequenced migration waves — Foundation, Audiences, and Content — with per-step confidence scores, structural gap flags, and an optional AI scope and wave notes estimate.`;
    }

    get initialCta() {
        const tgt = this.planData?.targetPlatform;
        const label = tgt ? this._displayName(tgt) : 'target';
        return `Load the ${label} migration wave plan: entity-by-entity steps organized into Foundation, Audiences, and Content waves — with confidence scores and gap flags.`;
    }

    _displayName(id) {
        switch (id) {
            case 'sfmc':   return 'SFMC';
            case 'pardot': return 'Pardot';
            case 'eloqua': return 'Eloqua';
            case 'figma':  return 'Figma';
            default:       return id;
        }
    }

    // ── Wave display ────────────────────────────────────────────────────────
    get wavesWithMeta() {
        if (!this.planData) return [];
        const notesByName = {};
        if (this.waveNotes?.waves) {
            for (const wn of this.waveNotes.waves) notesByName[wn.name] = wn;
        }
        return (this.planData.waves ?? []).map((wave, i) => {
            const wn = notesByName[wave.name] ?? null;
            return {
                ...wave,
                cardClass:      'wave-card ' + (WAVE_COLORS[i] ?? 'wave-card-blue'),
                badgeClass:     'wave-badge ' + (WAVE_BADGE[i] ?? 'badge-blue'),
                expanded:       !!this.expandedWaves[wave.index],
                steps:          (wave.steps ?? []).map(s => ({ ...s, actionClass: 'action-badge action-' + s.action })),
                waveNote:       wn?.notes ?? null,
                watchPoints:    wn?.watchPoints ?? [],
                keyDecision:    wn?.keyDecision ?? null,
                hasWaveNote:    !!wn,
                hasWatchPoints: (wn?.watchPoints?.length ?? 0) > 0,
                hasKeyDecision: !!wn?.keyDecision,
            };
        });
    }

    // ── Scope estimate ──────────────────────────────────────────────────────
    get hasScopeEstimate()     { return !!this.scopeEstimate; }
    get hasScopeRisks()        { return (this.scopeEstimate?.topRisks?.length ?? 0) > 0; }
    get scopeButtonLabel()     { return this.hasScopeEstimate ? 'Regenerate Scope Estimate' : 'Generate AI Scope Estimate'; }

    // ── Wave notes ──────────────────────────────────────────────────────────
    get hasWaveNotes()         { return !!this.waveNotes; }
    get hasOverallGuidance()   { return !!this.waveNotes?.overallGuidance; }
    get waveNotesButtonLabel() { return this.hasWaveNotes ? 'Regenerate Wave Notes' : 'Generate Wave Notes'; }

    // ── Actions ─────────────────────────────────────────────────────────────
    async handleLoadPlan() {
        this.isLoadingPlan = true;
        this.error = null;
        try {
            const raw = await getMigrationPlan({ assessmentId: this.recordId });
            this.planData = JSON.parse(raw);
        } catch (err) {
            this.error = err?.body?.message ?? err?.message ?? 'Unknown error loading plan';
        } finally {
            this.isLoadingPlan = false;
        }
    }

    async handleScopeEstimate() {
        this.isLoadingScope = true;
        try {
            const raw    = await runScopeEstimate({ assessmentId: this.recordId });
            const result = JSON.parse(raw);
            this.scopeEstimate = {
                ...result,
                waves: (result.waves ?? []).map(w => ({ ...w, riskClass: 'risk-' + (w.riskLevel ?? 'medium') })),
            };
            await refreshApex(this._wiredStoredData);
        } catch (err) {
            this.error = err?.body?.message ?? err?.message ?? 'Scope estimate failed';
        } finally {
            this.isLoadingScope = false;
        }
    }

    async handleWaveNotes() {
        this.isLoadingWaveNotes = true;
        try {
            const raw = await runWaveNotes({ assessmentId: this.recordId });
            this.waveNotes = JSON.parse(raw);
            await refreshApex(this._wiredStoredData);
        } catch (err) {
            this.error = err?.body?.message ?? err?.message ?? 'Wave notes generation failed';
        } finally {
            this.isLoadingWaveNotes = false;
        }
    }

    handleToggleWave(event) {
        const idx = Number(event.currentTarget.dataset.index);
        this.expandedWaves = { ...this.expandedWaves, [idx]: !this.expandedWaves[idx] };
    }
}