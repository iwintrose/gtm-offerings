import { LightningElement, api, track, wire } from 'lwc';
import getStageContext from '@salesforce/apex/GtmStageActionsController.getStageContext';
import advanceStage   from '@salesforce/apex/GtmStageActionsController.advanceStage';

const STAGE_LABELS = {
    Assessment : 'Assessment received',
    In_Review  : 'In review',
    Draft      : 'Draft ready',
    Sent       : 'Sent to client'
};

const CLIENT_MSGS = {
    Assessment : "Your brief is with our team — we'll email you when your proposal is ready.",
    In_Review  : "Your brief is with our team — we'll email you when your proposal is ready.",
    Draft      : "Your proposal is almost ready — we'll email you shortly."
};

export default class GtmStageActions extends LightningElement {
    @api configId      = '';
    @api isConfigManager = false;

    @track _ctx      = null;
    @track sending   = false;
    @track errorMsg  = '';

    @wire(getStageContext, { configId: '$configId' })
    wiredCtx({ data, error }) {
        if (data)  this._ctx = data;
        if (error) this.errorMsg = 'Could not load stage information.';
    }

    // ── Visibility ────────────────────────────────────────────────────────────

    get stage()     { return this._ctx?.stage || ''; }
    get showRail()  { return !!this.stage; }

    get showStartProposal() { return this.stage === 'Assessment'; }
    get showSaveDraft()     { return this.stage === 'In_Review'; }
    get showPreview()       { return this.stage === 'Draft'; }
    get showSend()          { return this.stage === 'Draft'; }
    get showRevise()        { return this.stage === 'Sent'; }
    get showViewAssessment(){ return !!this._ctx?.assessmentId && this.stage !== 'Sent'; }

    // ── Labels / display ──────────────────────────────────────────────────────

    get stageLabel()       { return STAGE_LABELS[this.stage] || this.stage; }
    get stagePillClass()   { return `sa-pill sa-pill--${(this.stage || '').toLowerCase().replace('_', '-')}`; }
    get railClass()        { return `sa-rail sa-rail--${(this.stage || '').toLowerCase().replace('_', '-')}`; }
    get sendLabel()        { return this.sending ? 'Sending…' : 'Send to client'; }
    get hasRequester()     { return !!this._ctx?.requesterName; }
    get requesterName()    { return this._ctx?.requesterName || ''; }
    get requesterCompany() { return this._ctx?.requesterCompany || ''; }
    get assessmentUrl()    {
        const id = this._ctx?.assessmentId;
        return id ? `/lightning/r/MA_Assessment_Request__c/${id}/view` : '#';
    }
    get clientStatusMessage() { return CLIENT_MSGS[this.stage] || ''; }

    // ── Actions ───────────────────────────────────────────────────────────────

    handleStartProposal() { this._advance('In_Review'); }
    handleSaveDraft()     { this._advance('Draft'); }
    handleRevise()        { this._advance('In_Review'); }

    handlePreview() {
        this.dispatchEvent(new CustomEvent('previewclient', { bubbles: false }));
    }

    handleSend() {
        if (this.sending) return;
        const email = this._ctx?.requesterEmail;
        const who   = email ? ` to ${email}` : '';
        // eslint-disable-next-line no-alert
        if (!confirm(`Send the proposal${who}?\n\nThis will email the client their link and mark this as sent.`)) return;
        this.sending = true;
        this._advance('Sent').finally(() => { this.sending = false; });
    }

    async _advance(newStage) {
        this.errorMsg = '';
        try {
            await advanceStage({ configId: this.configId, newStage });
            // Re-fetch context by invalidating the cache via a track update
            this._ctx = null;
            const result = await getStageContext({ configId: this.configId });
            this._ctx = result;

            if (newStage === 'Sent') {
                this.dispatchEvent(new CustomEvent('stagesent', {
                    detail   : { requesterEmail: result?.requesterEmail },
                    bubbles  : false
                }));
            }
        } catch (err) {
            this.errorMsg = err?.body?.message || err?.message || 'Could not update stage.';
        }
    }
}
