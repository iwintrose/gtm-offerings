import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getReadout from '@salesforce/apex/GtmReadoutController.getReadout';
import saveDraftContent from '@salesforce/apex/GtmReadoutController.saveDraftContent';
import submitForApproval from '@salesforce/apex/GtmReadoutController.submitForApproval';
import recallApproval from '@salesforce/apex/GtmReadoutController.recallApproval';
import publishReadout from '@salesforce/apex/GtmReadoutController.publishReadout';
import unpublishReadout from '@salesforce/apex/GtmReadoutController.unpublishReadout';
import returnToDraft from '@salesforce/apex/GtmReadoutController.returnToDraft';
// Reused rather than re-derived: this is the same Apex method gtmOverview
// already calls to find the site's home page, so the public link this editor
// shows is built from the same site the rest of the app links to.
import getSiteHomePageUrl from '@salesforce/apex/GtmSavedConfigurationController.getSiteHomePageUrl';

/**
 * The editor for a single readout, opened by gtmReadoutsOverview via a
 * standard__navItemPage deep-link into the GTM_Readouts_Manager tab (mirrors
 * gtmContentManager's CurrentPageReference deep-link pattern).
 *
 * Draft: content is editable, Save Draft and Send for approval are available.
 * Pending Approval: content is read-only and the record is locked by the
 * approval process; the only action is Recall request, and the banner names
 * who it is sitting with. There is no Approve button anywhere in this
 * component — approving happens on the platform (the approval email, the bell,
 * the Approval History related list, the mobile app), which is the whole point
 * of moving it there: a rep cannot approve their own readout from their own
 * editor.
 * Approved: content is read-only (the approved snapshot, not the working
 * draft), Publish appears, and Return to draft reopens it for editing.
 * Published: content is read-only, the live public link is shown, Unpublish
 * appears. Return to draft is deliberately absent here — the server refuses
 * Published -> Draft outright, because the link is live with the prospect, so
 * offering the action would only produce an error toast. Unpublishing first
 * revokes the token and lands on Approved, where the action is available.
 *
 * Publish stays its own action in the Approved state and is never reached by
 * approving. A manager approving must not, by itself, put a live link in a
 * prospect's inbox.
 */
export default class GtmReadoutReview extends LightningElement {
    @track readoutId = '';
    @track readout = null;
    @track draftValue = '';

    @track isLoading = true;
    @track isSaving = false;
    @track loadError = '';

    /**
     * Whether the editor is showing the readout as the recipient will see it.
     *
     * This is not a nicety. The numbers, band ladders and provenance chips a
     * prospect reads are rendered from Readout_Data__c, not from the prose in
     * the box below — so a rep or an approver looking only at the prose is
     * looking at half the document. Approval has to mean "I saw this", and the
     * only way it can is if the whole thing is on screen.
     *
     * Editing stays the default view: the preview is a check, not the surface
     * work is done on.
     */
    @track showPreview = false;

    /**
     * True while the inline "this discards the approval" confirmation is
     * showing. Returning to draft throws away the approved lock and the
     * approver stamp, so it is the one action here that asks twice.
     *
     * An inline two-step rather than window.confirm(): confirm() is
     * synchronous and blocking, is not available in every Lightning container,
     * and cannot be exercised in jsdom, so a confirmation built on it is a
     * confirmation no test can prove exists. This renders in the component's
     * own error/notice bar style, which is what the rest of this file already
     * uses to say something out of band.
     */
    @track isConfirmingReturn = false;

    /**
     * Set when GUS has proposed content the rep has not yet saved. It is a
     * notice, not a state: the proposal is already in draftValue (and therefore
     * in the editor) and is discarded by any refetch, exactly like anything else
     * the rep typed and did not save.
     */
    @track hasUnsavedProposal = false;

    // Site base for the public link, e.g. "https://<domain>/gtmaccelerator/s/".
    // getSiteHomePageUrl() resolves the GTM Accelerator site's own URL, so the
    // link a rep copies here points at the same site the rest of the app does.
    @track _siteBaseUrl = '';

    @wire(CurrentPageReference)
    capturePageRef(ref) {
        const id = ref && ref.state ? ref.state.c__readout : '';
        if (id && id !== this.readoutId) {
            this.readoutId = id;
            this.loadReadout();
        }
    }

    connectedCallback() {
        getSiteHomePageUrl()
            .then((url) => { this._siteBaseUrl = url || ''; })
            .catch(() => { /* the public link falls back to showing just the token */ });
    }

    loadReadout() {
        if (!this.readoutId) return;
        this.isLoading = true;
        this.loadError = '';
        // A pending confirmation is about the state we are replacing, so it
        // must not survive a refetch onto a different status.
        this.isConfirmingReturn = false;
        this.hasUnsavedProposal = false;
        getReadout({ readoutId: this.readoutId })
            .then((data) => {
                this.readout = data;
                this.draftValue = (data && data.draftContent) || '';
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'The readout could not be loaded.';
            })
            .finally(() => { this.isLoading = false; });
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // ─── derived state ──────────────────────────────────────────────────────

    get hasReadout() { return !!this.readout; }
    get status() { return this.readout ? (this.readout.status || '') : ''; }

    /**
     * The platform's view of the approval, not the picklist's. Status__c is set
     * by a workflow field update — a consequence of the approval rather than
     * the approval itself — so a field update that failed to fire would leave
     * the record labelled Draft while the platform has it locked and pending.
     * Reading ProcessInstance (approvalState, from Apex) means the buttons stay
     * right even then, and `isLocked` is the belt-and-braces third source: a
     * locked record cannot be edited whatever the label says.
     */
    get approvalState() { return this.readout ? (this.readout.approvalState || 'None') : 'None'; }
    get isPendingApproval() {
        if (this.status === 'Approved' || this.status === 'Published') {
            // Both final actions unlock the record, so an approved or published
            // readout is never pending — and treating it as such would render
            // two states at once.
            return false;
        }
        return this.approvalState === 'Pending'
            || this.status === 'Pending Approval'
            || (!!this.readout && this.readout.isLocked === true);
    }

    get isDraft() { return this.status === 'Draft' && !this.isPendingApproval; }
    get isApproved() { return this.status === 'Approved'; }
    get isPublished() { return this.status === 'Published'; }

    /**
     * "Pending Approval" is a two-word status, so the modifier is slugified
     * rather than lower-cased — `status-badge--pending approval` is two class
     * names, one of which is `approval`.
     */
    get statusClass() {
        const slug = (this.isPendingApproval ? 'Pending Approval' : this.status)
            .toLowerCase()
            .replace(/\s+/g, '-');
        return `status-badge status-badge--${slug}`;
    }

    get statusLabel() {
        return this.isPendingApproval ? 'Pending Approval' : this.status;
    }

    // ─── approval + case detail ─────────────────────────────────────────────

    get pendingApproverLine() {
        const who = this.readout && this.readout.pendingApprover;
        return who
            ? `Waiting on ${who}. Approvers act from the approval request — the email, the bell, or the Approval History on this record.`
            : 'Waiting on an approver. Approvers act from the approval request — the email, the bell, or the Approval History on this record.';
    }

    get hasApprovalStamp() {
        return this.isApproved || this.isPublished
            ? !!(this.readout && (this.readout.approverName || this.readout.approvalDate))
            : false;
    }

    get approvalStampLine() {
        if (!this.readout) return '';
        const who = this.readout.approverName;
        const when = this.readout.approvalDate
            ? new Date(this.readout.approvalDate).toLocaleDateString()
            : '';
        if (who && when) return `Approved by ${who} on ${when}`;
        if (who) return `Approved by ${who}`;
        return when ? `Approved on ${when}` : '';
    }

    get hasCase() { return !!(this.readout && this.readout.caseId); }
    get caseLabel() {
        const number = this.readout && this.readout.caseNumber;
        return number ? `Review case ${number}` : 'Review case';
    }
    /**
     * The Case is where the recipient's comments land and where the rep replies
     * — natively, on the record. This link exists so a rep does not have to go
     * looking for it; there is deliberately no comment UI in this component.
     */
    get caseUrl() {
        const id = this.readout && this.readout.caseId;
        return id ? `/lightning/r/Case/${id}/view` : '';
    }

    get title() {
        if (!this.readout) return 'Readout';
        return this.readout.assessmentRequestName || this.readout.company || 'Readout';
    }

    get approvedContent() { return this.readout ? (this.readout.approvedContent || '') : ''; }

    // ─── preview ─────────────────────────────────────────────────────────

    get previewLabel() { return this.showPreview ? 'Back to editing' : 'Preview as recipient'; }

    /**
     * The prose the preview renders: the WORKING draft while editing, so a rep
     * sees unsaved words in place, and the approved copy once there is one,
     * because from approval onwards that is the document.
     */
    get previewContent() {
        return this.isDraft ? this.draftValue : (this.approvedContent || this.draftValue);
    }

    /**
     * The measurement half, matching the same rule. Approved_Data__c is what
     * publishes, so once a readout is approved the preview must render that
     * copy and not the generation-time one — otherwise the preview could show
     * numbers the published page will not.
     */
    get previewData() {
        if (!this.readout) return '';
        const approved = this.readout.approvedDataJson;
        return this.isDraft ? (this.readout.dataJson || '') : (approved || this.readout.dataJson || '');
    }

    handleTogglePreview() { this.showPreview = !this.showPreview; }

    get isEditing() { return !this.showPreview; }

    /**
     * The link a rep copies and sends. It must be the *canonical* shape, not
     * merely a shape gtmReadoutView happens to tolerate.
     *
     * GTM_Accelerator1 is an Aura Experience Builder site, where a custom page
     * routes on a fixed urlPrefix only — there is no path-parameter route for a
     * standalone custom page (see experiences/GTM_Accelerator1/routes/readout.json,
     * urlPrefix "readout", and docs/runbooks/readout-public-link.md). So the
     * token travels as a query param:
     *
     *   https://<site-domain>/gtmaccelerator/s/readout?token=<token>
     *
     * gtmReadoutView does parse a trailing "/readout/<token>" path segment, but
     * that is an explicitly-labelled last-resort fallback for rewrite rules and
     * old hand-built links — a `/readout/<token>` URL would 404 at the site
     * router before any component rendered, so it is not something to hand a
     * prospect.
     */
    get publicUrl() {
        const token = this.readout ? this.readout.publicLinkToken : '';
        if (!token) return '';
        if (!this._siteBaseUrl) return token;
        const base = this._siteBaseUrl.replace(/\/+$/, '');
        return `${base}/readout?token=${encodeURIComponent(token)}`;
    }

    get canSave() { return this.isDraft && !this.isSaving; }
    get canSubmit() { return this.isDraft && !this.isSaving; }
    get canRecall() { return this.isPendingApproval && !this.isSaving; }
    get canPublish() { return this.isApproved && !this.isSaving; }
    get canUnpublish() { return this.isPublished && !this.isSaving; }
    get canReturnToDraft() { return this.isApproved && !this.isSaving; }

    // ─── editing ─────────────────────────────────────────────────────────────

    handleDraftChange(event) {
        this.draftValue = event.target.value;
    }

    /**
     * GUS proposed new readout content.
     *
     * It lands in the editor and nowhere else. The server does not write the
     * record — it returns a delta, the same pattern the configurator assistant
     * uses — so the rep reads the proposal, edits it if they want, and clicks
     * Save Draft. That save goes through GtmReadoutController.saveDraftContent
     * with every state check intact, which is why the human-in-the-loop gate
     * survives GUS being here at all.
     *
     * Guarded on isDraft as well: the server already refuses to propose an edit
     * to anything else, and this is the second lock on the same door.
     */
    handleDraftProposed(event) {
        if (!this.isDraft) return;
        const proposed = event.detail && event.detail.draftContent;
        if (typeof proposed !== 'string' || !proposed) return;
        this.draftValue = proposed;
        this.hasUnsavedProposal = true;
        this.toast(
            'GUS updated the draft',
            'Review it and click Save Draft — nothing has been saved yet.',
            'info'
        );
    }

    handleDismissProposalNotice() {
        this.hasUnsavedProposal = false;
    }

    handleSaveDraft() {
        if (!this.canSave) return;
        this.isSaving = true;
        saveDraftContent({ readoutId: this.readoutId, content: this.draftValue })
            .then(() => {
                this.hasUnsavedProposal = false;
                this.toast('Draft saved', '', 'success');
                return this.loadReadout();
            })
            .catch((err) => {
                this.toast('Draft could not be saved', this.messageFrom(err), 'error');
            })
            .finally(() => { this.isSaving = false; });
    }

    handleSubmitForApproval() {
        if (!this.canSubmit) return;
        this.isSaving = true;
        // Submitting locks the record, so what is on screen has to be what the
        // approver reads. The working edit is saved first rather than silently
        // dropped — and it has to go first, because once the approval request
        // exists the save would be refused.
        saveDraftContent({ readoutId: this.readoutId, content: this.draftValue })
            .then(() => submitForApproval({ readoutId: this.readoutId }))
            .then(() => {
                this.toast(
                    'Sent for approval',
                    'The readout is locked while an approver reviews it.',
                    'success'
                );
                return this.loadReadout();
            })
            .catch((err) => {
                this.toast('Could not send for approval', this.messageFrom(err), 'error');
            })
            .finally(() => { this.isSaving = false; });
    }

    handleRecall() {
        if (!this.canRecall) return;
        this.isSaving = true;
        recallApproval({ readoutId: this.readoutId })
            .then(() => {
                this.toast('Approval request recalled', 'The readout is editable again.', 'success');
                return this.loadReadout();
            })
            .catch((err) => {
                this.toast('Could not recall the request', this.messageFrom(err), 'error');
            })
            .finally(() => { this.isSaving = false; });
    }

    handlePublish() {
        if (!this.canPublish) return;
        this.isSaving = true;
        publishReadout({ readoutId: this.readoutId })
            .then(() => {
                this.toast('Readout published', '', 'success');
                return this.loadReadout();
            })
            .catch((err) => {
                this.toast('Publish failed', this.messageFrom(err), 'error');
            })
            .finally(() => { this.isSaving = false; });
    }

    handleUnpublish() {
        if (!this.canUnpublish) return;
        this.isSaving = true;
        unpublishReadout({ readoutId: this.readoutId })
            .then(() => {
                this.toast('Readout unpublished', '', 'success');
                return this.loadReadout();
            })
            .catch((err) => {
                this.toast('Unpublish failed', this.messageFrom(err), 'error');
            })
            .finally(() => { this.isSaving = false; });
    }

    // ─── return to draft ─────────────────────────────────────────────────────

    /** First click: ask. Nothing is sent to the server here. */
    handleReturnToDraftRequest() {
        if (!this.canReturnToDraft) return;
        this.isConfirmingReturn = true;
    }

    handleCancelReturnToDraft() {
        this.isConfirmingReturn = false;
    }

    /** Second click: actually revert. */
    handleConfirmReturnToDraft() {
        if (!this.canReturnToDraft) return;
        this.isSaving = true;
        returnToDraft({ readoutId: this.readoutId })
            .then(() => {
                this.isConfirmingReturn = false;
                this.toast('Returned to draft', 'The approval was saved to version history.', 'success');
                return this.loadReadout();
            })
            .catch((err) => {
                // The confirmation stays open on failure so the rep can retry
                // without hunting for the button again.
                this.toast('Could not return to draft', this.messageFrom(err), 'error');
            })
            .finally(() => { this.isSaving = false; });
    }

    handleRefresh() { this.loadReadout(); }
    handleDismissError() { this.loadError = ''; }
}
