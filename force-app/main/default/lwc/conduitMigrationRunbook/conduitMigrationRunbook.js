import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMigrationRunbook from '@salesforce/apex/ConduitPlanController.getMigrationRunbook';
import getStoredPlanData   from '@salesforce/apex/ConduitPlanController.getStoredPlanData';
import listTargetConfigs   from '@salesforce/apex/ConduitMigrationController.listTargetConfigs';
import listRuns            from '@salesforce/apex/ConduitMigrationController.listRuns';
import listStepOutcomes    from '@salesforce/apex/ConduitMigrationController.listStepOutcomes';
import executeRun          from '@salesforce/apex/ConduitMigrationController.executeRun';

const ACTION_ORDER = { create: 0, update: 1, skip: 2 };

export default class ConduitMigrationRunbook extends NavigationMixin(LightningElement) {
    @api recordId;

    @track runbook   = null;   // full API response — waves, summary, markdown, etc.
    @track isLoading = false;
    @track error     = null;

    // Filters
    waveFilter       = 'all';   // 'all' | wave name
    actionFilter     = 'all';   // 'all' | 'create' | 'update' | 'skip'
    resultFilter     = 'all';   // 'all' | 'not_run' | 'applied' | 'failed' | 'skipped'
    confidenceFilter = 0;        // 0-100; hide steps below this
    searchTerm       = '';

    // Most-recent outcome per source canonicalId across all prior runs. Used
    // to badge each runbook step so the SA sees what's been done vs still
    // pending, and can filter to "only failures" to re-execute.
    @track stepOutcomes = {};   // canonicalId -> { status, runId, runName, errorMessage }

    // Explicit checkbox selection. Keyed on step.order; when non-empty, this
    // OVERRIDES the filter-based selection so the SA can hand-pick steps.
    @track checkedSteps = {};

    // Execution state
    @track targetConfigs        = [];      // available Conduit_Target_SFMC__mdt records
    @track selectedTargetConfig = null;    // developer name of chosen config
    @track showConfirmDialog    = false;
    @track rollbackEnabled      = false;
    @track isExecuting          = false;
    @track executionResult      = null;    // { runId, success, error?, summary? }

    // Recent runs strip (top-of-tab quick-links to prior runs)
    @track recentRuns = [];

    _wiredStoredData;
    _wiredRuns;
    _wiredOutcomes;

    // Hydrate from the last-stored runbook on the latest Conduit_Audit__c row
    // so page reloads don't lose it. Same pattern used by conduitGapDetail /
    // conduitRationalization / conduitMigrationPlan.
    @wire(getStoredPlanData, { assessmentId: '$recordId' })
    wiredStoredData(result) {
        this._wiredStoredData = result;
        if (result.data && result.data.Migration_Runbook__c && !this.runbook) {
            try { this.runbook = JSON.parse(result.data.Migration_Runbook__c); }
            catch { /* stored value unparseable — user can regenerate */ }
        }
    }

    @wire(listRuns, { assessmentId: '$recordId' })
    wiredRuns(result) {
        this._wiredRuns = result;
        if (result.data) {
            this.recentRuns = result.data.slice(0, 3).map(r => this._decorateRun(r));
        }
    }

    // Rows come ordered by run.Started_At DESC then step order — so the FIRST
    // occurrence of any canonicalId is the most recent outcome. We reduce
    // to a map, ignoring later (older) rows for the same entity.
    @wire(listStepOutcomes, { assessmentId: '$recordId' })
    wiredOutcomes(result) {
        this._wiredOutcomes = result;
        if (result.data) {
            const map = {};
            for (const row of result.data) {
                const cid = row.sourceCanonicalId;
                if (!cid || map[cid]) continue;
                map[cid] = {
                    status:       row.status,
                    runId:        row.runId,
                    runName:      row.runName,
                    errorMessage: row.errorMessage,
                };
            }
            this.stepOutcomes = map;
        }
    }

    // ── Visibility ──────────────────────────────────────────────────────────
    get showInitial() { return !this.isLoading && !this.runbook && !this.error; }
    get hasRunbook()  { return !!this.runbook && !this.isLoading; }
    get hasRecentRuns() { return this.recentRuns.length > 0; }

    // ── Header / subtitle ───────────────────────────────────────────────────
    get subtitle() {
        const src = this._displayName(this.runbook?.sourcePlatform);
        const tgt = this._displayName(this.runbook?.targetPlatform);
        if (src && tgt) {
            return `Step-by-step migration runbook from your ${src} estate to ${tgt}. Every planned step with per-entity preview text, confidence, and a downloadable Markdown document ready to paste into an SoW or share with the customer.`;
        }
        return 'Step-by-step migration runbook. Every planned step with per-entity preview text, confidence, and a downloadable Markdown document.';
    }

    get generatedLabel() {
        if (!this.runbook?.generatedAt) return '';
        return new Date(this.runbook.generatedAt).toLocaleString();
    }

    get buttonLabel() {
        return this.hasRunbook ? 'Regenerate Runbook' : 'Generate Runbook';
    }

    // ── Summary tiles ───────────────────────────────────────────────────────
    get summary() { return this.runbook?.summary ?? {}; }
    get hasBlockers() { return (this.summary?.blockers ?? 0) > 0; }

    // ── Wave-level display, with filters + checkbox state applied ───────────
    get filteredWaves() {
        if (!this.runbook) return [];
        const search = this.searchTerm.trim().toLowerCase();

        return (this.runbook.waves ?? [])
            .filter(w => this.waveFilter === 'all' || w.name === this.waveFilter)
            .map(w => {
                const steps = (w.steps ?? []).filter(s => {
                    if (this.actionFilter !== 'all' && s.action !== this.actionFilter) return false;
                    if (s.confidence < this.confidenceFilter) return false;
                    if (search && !s.entityName.toLowerCase().includes(search) && !s.preview.toLowerCase().includes(search)) return false;
                    if (this.resultFilter !== 'all') {
                        const outcome = this.stepOutcomes[s.sourceCanonicalId];
                        const resultKey = this._resultKey(outcome);
                        if (this.resultFilter !== resultKey) return false;
                    }
                    return true;
                });
                const sortedSteps = [...steps].sort((a, b) => {
                    const ao = ACTION_ORDER[a.action] ?? 3;
                    const bo = ACTION_ORDER[b.action] ?? 3;
                    if (ao !== bo) return ao - bo;
                    return a.order - b.order;
                });
                const decorated = sortedSteps.map(s => {
                    const outcome = this.stepOutcomes[s.sourceCanonicalId];
                    const resultKey = this._resultKey(outcome);
                    return {
                        ...s,
                        actionClass:      'action-pill action-' + s.action,
                        confidenceClass:  this._confidenceClass(s.confidence),
                        checked:          !!this.checkedSteps[s.order],
                        // Non-skip steps are the only ones eligible for execution;
                        // skips have no callout to make, so disable the checkbox.
                        checkDisabled:    s.action === 'skip',
                        resultKey,
                        resultLabel:      this._resultLabel(resultKey),
                        resultClass:      'result-pill result-' + resultKey,
                        resultTooltip:    outcome?.runName
                            ? `Last outcome from ${outcome.runName}${outcome.errorMessage ? ' — ' + outcome.errorMessage : ''}`
                            : 'Not yet migrated in any run',
                    };
                });
                const eligibleCount = decorated.filter(s => !s.checkDisabled).length;
                const checkedInWave = decorated.filter(s => s.checked).length;
                return {
                    ...w,
                    filteredSteps: decorated,
                    visibleCount: sortedSteps.length,
                    hasFilteredSteps: sortedSteps.length > 0,
                    hasHiddenSteps:   sortedSteps.length < (w.steps?.length ?? 0),
                    hiddenCount:      (w.steps?.length ?? 0) - sortedSteps.length,
                    allEligibleChecked: eligibleCount > 0 && checkedInWave === eligibleCount,
                };
            })
            .filter(w => w.hasFilteredSteps || (w.gaps?.length ?? 0) > 0);
    }

    // ── Filter chip data ────────────────────────────────────────────────────
    get waveFilters() {
        if (!this.runbook) return [];
        const active = this.waveFilter;
        const all = [{ value: 'all', label: `All waves (${this.runbook.summary?.totalSteps ?? 0})` }];
        for (const w of this.runbook.waves ?? []) {
            all.push({ value: w.name, label: `${w.name} (${w.stats?.total ?? 0})` });
        }
        return all.map(f => ({ ...f, cls: 'filter-btn' + (active === f.value ? ' filter-active' : '') }));
    }

    get actionFilters() {
        const s = this.summary;
        const active = this.actionFilter;
        return [
            { value: 'all',    label: `All (${s.totalSteps ?? 0})` },
            { value: 'create', label: `Create (${s.create ?? 0})` },
            { value: 'update', label: `Update (${s.update ?? 0})` },
            { value: 'skip',   label: `Skip (${s.skip ?? 0})` },
        ].map(f => ({ ...f, cls: 'filter-btn' + (active === f.value ? ' filter-active' : '') }));
    }

    get resultFilters() {
        // Counts drawn from actual runbook × outcomes join, not from prior runs
        // alone — so "Not run" counts every step that has no matching outcome.
        const active = this.resultFilter;
        const counts = { all: 0, not_run: 0, applied: 0, failed: 0, skipped: 0 };
        for (const w of (this.runbook?.waves ?? [])) {
            for (const s of (w.steps ?? [])) {
                counts.all += 1;
                counts[this._resultKey(this.stepOutcomes[s.sourceCanonicalId])] += 1;
            }
        }
        return [
            { value: 'all',     label: `All (${counts.all})` },
            { value: 'not_run', label: `Not yet run (${counts.not_run})` },
            { value: 'applied', label: `Applied (${counts.applied})` },
            { value: 'failed',  label: `Failed (${counts.failed})` },
            { value: 'skipped', label: `Skipped (${counts.skipped})` },
        ].map(f => ({ ...f, cls: 'filter-btn' + (active === f.value ? ' filter-active' : '') }));
    }

    get confidenceLabel() { return `Min confidence: ${this.confidenceFilter}%`; }

    // ── @api hook (for the cross-tab CMM refresh pattern) ───────────────────
    @api async refresh() {
        // Wipe local state so switching CMMs and coming back doesn't show
        // stale data. User clicks Generate to build against the new CMM.
        // Also refresh the wire so a stale persisted runbook doesn't rehydrate.
        this.runbook = null;
        this.error = null;
        this.checkedSteps = {};
        if (this._wiredStoredData) { try { await refreshApex(this._wiredStoredData); } catch { /* ignore */ } }
        if (this._wiredRuns)       { try { await refreshApex(this._wiredRuns); }       catch { /* ignore */ } }
        if (this._wiredOutcomes)   { try { await refreshApex(this._wiredOutcomes); }   catch { /* ignore */ } }
    }

    // ── Actions ─────────────────────────────────────────────────────────────
    async handleGenerate() {
        this.isLoading = true;
        this.error = null;
        this.checkedSteps = {};
        try {
            const raw = await getMigrationRunbook({ assessmentId: this.recordId });
            this.runbook = JSON.parse(raw);
            // Refresh the wire so the newly-persisted row is what a page reload
            // would see (matters if user navigates away then back without reload).
            if (this._wiredStoredData) { try { await refreshApex(this._wiredStoredData); } catch { /* ignore */ } }
        } catch (err) {
            this.error = err?.body?.message ?? err?.message ?? 'Failed to generate runbook';
        } finally {
            this.isLoading = false;
        }
    }

    handleWaveFilter(e)   { this.waveFilter = e.currentTarget.dataset.value; }
    handleActionFilter(e) { this.actionFilter = e.currentTarget.dataset.value; }
    handleResultFilter(e) { this.resultFilter = e.currentTarget.dataset.value; }
    handleSearch(e)       { this.searchTerm = e.target.value ?? ''; }
    handleConfidence(e)   { this.confidenceFilter = Number(e.target.value ?? 0); }

    // ── Checkbox handlers ──────────────────────────────────────────────────
    // We assign a NEW object rather than mutate so the @track reactivity kicks in.
    handleStepCheck(e) {
        const order = Number(e.target.dataset.order);
        const next = { ...this.checkedSteps };
        if (e.target.checked) next[order] = true;
        else delete next[order];
        this.checkedSteps = next;
    }

    handleWaveSelectAll(e) {
        const waveName = e.target.dataset.wave;
        const wave = this.filteredWaves.find(w => w.name === waveName);
        if (!wave) return;
        const next = { ...this.checkedSteps };
        if (e.target.checked) {
            for (const s of wave.filteredSteps) if (!s.checkDisabled) next[s.order] = true;
        } else {
            for (const s of wave.filteredSteps) delete next[s.order];
        }
        this.checkedSteps = next;
    }

    handleClearSelection() { this.checkedSteps = {}; }

    get hasExplicitSelection() { return Object.keys(this.checkedSteps).length > 0; }
    get selectionLabel() {
        const n = Object.keys(this.checkedSteps).length;
        return n === 0 ? '' : `${n} step${n === 1 ? '' : 's'} selected`;
    }

    // Bound to the download anchor in the template. Data URL bypasses the Locker
    // Service restrictions on document.createElement / body.appendChild that made
    // the programmatic-click approach silently fail inside LWC.
    get downloadHref() {
        if (!this.runbook?.markdown) return '#';
        return 'data:text/markdown;charset=utf-8,' + encodeURIComponent(this.runbook.markdown);
    }
    get downloadFilename() { return this._filename(); }
    get downloadDisabled() { return !this.runbook?.markdown; }

    // Fires a toast alongside the browser's native download so the SA gets
    // visual confirmation. Don't preventDefault — let the anchor do its job.
    handleDownloadClick() {
        if (!this.runbook?.markdown) return;
        this.dispatchEvent(new ShowToastEvent({
            variant: 'success',
            title: 'Downloaded',
            message: 'Migration runbook saved as ' + this._filename(),
        }));
    }

    // ── Execution ───────────────────────────────────────────────────────────
    @wire(listTargetConfigs)
    wiredTargets({ data, error }) {
        if (data) {
            this.targetConfigs = data;
            if (!this.selectedTargetConfig && data.length > 0) {
                this.selectedTargetConfig = data[0].developerName;
            }
        }
        if (error) { /* leave configs empty; the LWC surfaces this in the confirm dialog */ }
    }

    get canExecute() {
        return this.hasRunbook && !this.isExecuting
            && this.filteredWaves.some(w => w.filteredSteps.length > 0)
            && this.targetConfigs.length > 0;
    }

    get executeButtonLabel() {
        return this.isExecuting ? 'Executing…' : 'Execute Migration';
    }

    // If the user has ticked any boxes, execute exactly that set. Otherwise
    // fall back to "every non-skip step currently visible under the filters",
    // which was the pre-checkbox behavior.
    get selectedStepOrders() {
        if (this.hasExplicitSelection) {
            return Object.keys(this.checkedSteps).map(Number);
        }
        const orders = [];
        for (const w of this.filteredWaves) {
            for (const s of w.filteredSteps) {
                if (s.action !== 'skip') orders.push(s.order);
            }
        }
        return orders;
    }

    get selectedStepCount() { return this.selectedStepOrders.length; }
    get hasNoTargetConfigs() { return this.targetConfigs.length === 0; }

    get targetConfigOptions() {
        return this.targetConfigs.map(t => ({
            label: t.description ? `${t.label} — ${t.description}` : t.label,
            value: t.developerName,
        }));
    }

    get selectionModeLabel() {
        return this.hasExplicitSelection
            ? 'Executing hand-picked selection.'
            : 'No boxes ticked — will execute every non-skip step matching the current filters.';
    }

    handleTargetConfigChange(e) { this.selectedTargetConfig = e.detail.value; }
    handleRollbackChange(e)     { this.rollbackEnabled = e.target.checked; }

    handleOpenConfirm() {
        this.executionResult = null;
        this.showConfirmDialog = true;
    }
    handleCancelConfirm() { this.showConfirmDialog = false; }

    async handleConfirmExecute() {
        this.showConfirmDialog = false;
        this.isExecuting = true;
        this.executionResult = null;
        try {
            const runId = await executeRun({
                assessmentId:     this.recordId,
                stepOrders:       this.selectedStepOrders,
                rollbackEnabled:  this.rollbackEnabled,
                targetConfigName: this.selectedTargetConfig,
            });
            this.executionResult = { runId, success: true };
            // Refresh the recent-runs strip AND per-step outcomes so badges
            // update in-place without a page reload.
            if (this._wiredRuns)     { try { await refreshApex(this._wiredRuns); }     catch { /* ignore */ } }
            if (this._wiredOutcomes) { try { await refreshApex(this._wiredOutcomes); } catch { /* ignore */ } }
            this.checkedSteps = {};
            this.dispatchEvent(new ShowToastEvent({
                variant: 'success',
                title: 'Migration executed',
                message: 'Migration Run created. Click the link below the summary to open it.',
            }));
        } catch (err) {
            const msg = err?.body?.message ?? err?.message ?? 'Unknown error';
            this.executionResult = { success: false, error: msg };
            this.dispatchEvent(new ShowToastEvent({
                variant: 'error',
                title: 'Migration failed',
                message: msg,
                mode: 'sticky',
            }));
        } finally {
            this.isExecuting = false;
        }
    }

    // ── Navigation ──────────────────────────────────────────────────────────
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

    handleOpenLastRun() {
        if (this.executionResult?.runId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.executionResult.runId,
                    objectApiName: 'Conduit_Migration_Run__c',
                    actionName: 'view',
                },
            });
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────────
    _filename() {
        const src = this.runbook?.sourcePlatform ?? 'source';
        const tgt = this.runbook?.targetPlatform ?? 'target';
        const stamp = new Date().toISOString().slice(0, 10);
        return `conduit-runbook-${src}-to-${tgt}-${stamp}.md`;
    }

    _confidenceClass(pct) {
        if (pct >= 80) return 'conf-badge conf-high';
        if (pct >= 50) return 'conf-badge conf-mid';
        return 'conf-badge conf-low';
    }

    // Normalizes an outcome record to one of the five badge states used by
    // both the row pills and the result-filter chips. `null` outcome = never
    // touched by any run; matching statuses come from the Apex controller
    // (Applied / Failed / Skipped, title-cased) or the runbook itself when
    // the step is always-skip.
    _resultKey(outcome) {
        if (!outcome) return 'not_run';
        const s = (outcome.status || '').toLowerCase();
        if (s === 'applied') return 'applied';
        if (s === 'failed')  return 'failed';
        if (s === 'skipped') return 'skipped';
        return 'not_run';
    }

    _resultLabel(key) {
        switch (key) {
            case 'applied': return 'Migrated';
            case 'failed':  return 'Failed';
            case 'skipped': return 'Skipped';
            default:        return 'Not run';
        }
    }

    _decorateRun(r) {
        const status = r.Status__c ?? 'Unknown';
        const when   = r.Started_At__c ? new Date(r.Started_At__c).toLocaleString() : '';
        return {
            id:              r.Id,
            name:            r.Name,
            status,
            statusClass:     'run-pill run-status-' + status.toLowerCase().replace(/\s+/g, '-'),
            when,
            total:           r.Total_Steps__c ?? 0,
            succeeded:       r.Steps_Succeeded__c ?? 0,
            failed:          r.Steps_Failed__c ?? 0,
            skipped:         r.Steps_Skipped__c ?? 0,
            targetConfig:    r.Target_Config__c ?? '',
        };
    }

    _displayName(id) {
        switch (id) {
            case 'sfmc':   return 'SFMC';
            case 'pardot': return 'Pardot';
            case 'eloqua': return 'Eloqua';
            case 'hubspot':return 'HubSpot';
            case 'figma':  return 'Figma';
            default:       return null;
        }
    }
}