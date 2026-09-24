import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRepNotes from '@salesforce/apex/GtmReadoutAgentContext.getRepNotes';
import saveRepNotes from '@salesforce/apex/GtmReadoutAgentContext.saveRepNotes';
import getFileList from '@salesforce/apex/GtmReadoutAgentFiles.getFileList';

/**
 * GUS on the readout editor: the rep's side of "what do you know that the
 * assessment doesn't".
 *
 * Three inputs, one output.
 *   Notes    — free text the rep types or pastes. Stored on
 *              GTM_Readout__c.Rep_Context_Notes__c, which is internal: it never
 *              becomes readout content and never reaches the prospect.
 *   Files    — lightning-file-upload against the readout, so the platform does
 *              the ContentVersion/ContentDocumentLink work and the rep's own
 *              record access governs it. Plain-text formats are read; PDFs and
 *              Word documents are listed to GUS as present-but-unreadable and
 *              it says so rather than guessing.
 *   Chat     — c-gtm-agent-chat in readout mode.
 *   Output   — a `draftproposed` event carrying the proposed readout HTML. This
 *              component never writes the readout; gtmReadoutReview puts the
 *              proposal in the editor and the rep still clicks Save Draft.
 *
 * The assistant is rendered in every status, not just Draft, on purpose: it is
 * useful for reading an approved readout back and drafting alternative wording
 * in chat. What changes with status is that the server refuses to propose an
 * edit and explains which action unlocks it — a refusal the rep can see and
 * act on beats a component that silently disappears.
 */
export default class GtmReadoutAssist extends LightningElement {
    @api readoutId = '';

    /** The rep's live editor content, passed through to the server each turn. */
    @api workingDraft = '';

    /** Status of the readout, for the "GUS cannot edit this" notice. */
    @api status = '';

    @track notes = '';
    @track savedNotes = '';
    @track isSavingNotes = false;
    @track isOpen = false;
    @track uploadedFiles = [];

    _loaded = false;
    _filesLoaded = false;

    connectedCallback() {
        this.loadNotes();
        this.loadFileList();
    }

    loadNotes() {
        if (!this.readoutId || this._loaded) return;
        this._loaded = true;
        getRepNotes({ readoutId: this.readoutId })
            .then((value) => {
                this.notes = value || '';
                this.savedNotes = this.notes;
                this.applyDefaultOpen();
            })
            .catch(() => {
                // Notes are an aid, not a prerequisite: a failed read leaves the
                // box empty and the chat still works.
            });
    }

    /**
     * Persists the file list across a panel toggle/reload instead of only
     * reflecting the current session's uploadedFiles array. Read-only and
     * cacheable — a failure here leaves the list empty and the upload widget
     * still works for new attachments.
     */
    loadFileList() {
        if (!this.readoutId || this._filesLoaded) return;
        this._filesLoaded = true;
        getFileList({ readoutId: this.readoutId })
            .then((rows) => {
                this.uploadedFiles = (rows || []).map((f) => ({
                    id: f.id,
                    name: f.title,
                    extension: f.extension,
                    sizeBytes: f.sizeBytes,
                    readable: f.readable
                }));
                this.applyDefaultOpen();
            })
            .catch(() => {
                // Same posture as notes: a failed read leaves the list empty.
            });
    }

    /**
     * The panel defaults open when the Draft already has rep notes or
     * existing attachments — otherwise it stays collapsed, matching current
     * behavior for readouts with no rep context. Only ever opens the panel
     * automatically; never closes one the rep already opened by hand.
     */
    applyDefaultOpen() {
        if (this.isOpen) return;
        if (String(this.savedNotes || '').trim() !== '' || this.uploadedFiles.length > 0) {
            this.isOpen = true;
        }
    }

    // ─── panel ───────────────────────────────────────────────────────────────

    get toggleLabel() {
        return this.isOpen ? 'Hide GUS' : 'Ask GUS';
    }

    handleToggle() {
        this.isOpen = !this.isOpen;
        if (this.isOpen) this.loadNotes();
    }

    // ─── status ──────────────────────────────────────────────────────────────

    get isDraft() {
        return this.status === 'Draft';
    }

    /**
     * Shown whenever GUS can read but not edit. The wording matches the server's
     * refusal (GtmReadoutAgentSurface.editabilityNote) so a rep is not told two
     * different things by the UI and the assistant.
     */
    get readOnlyNotice() {
        if (this.isDraft) return '';
        if (this.status === 'Pending Approval') {
            return 'This readout is locked while an approver has it. GUS can read it and suggest wording, but cannot change the draft — recall the approval request first.';
        }
        if (this.status === 'Approved') {
            return 'This readout has been approved. GUS will not edit approved content behind the approver’s back — use Return to draft first.';
        }
        if (this.status === 'Published') {
            return 'This readout is published and its link is live. GUS will not edit it — unpublish, then return it to draft.';
        }
        return 'GUS can read this readout but cannot edit it in its current state.';
    }

    get hasReadOnlyNotice() {
        return !!this.readOnlyNotice;
    }

    // ─── notes ───────────────────────────────────────────────────────────────

    get notesDirty() {
        return this.notes !== this.savedNotes;
    }

    get saveNotesDisabled() {
        return this.isSavingNotes || !this.notesDirty;
    }

    handleNotesChange(event) {
        this.notes = event.target.value;
    }

    handleSaveNotes() {
        if (this.saveNotesDisabled) return;
        this.isSavingNotes = true;
        saveRepNotes({ readoutId: this.readoutId, notes: this.notes })
            .then(() => {
                this.savedNotes = this.notes;
                this.toast('Context saved', 'GUS can read this now.', 'success');
            })
            .catch((err) => {
                this.toast('Context could not be saved', this.messageFrom(err), 'error');
            })
            .finally(() => {
                this.isSavingNotes = false;
            });
    }

    // ─── files ───────────────────────────────────────────────────────────────

    /**
     * No accept filter: the rep can attach anything, and GUS reports honestly
     * which files it could read. Silently rejecting a PDF at the picker would
     * be a worse lie than saying "I can see it, I cannot read it".
     */
    get uploadRecordId() {
        return this.readoutId;
    }

    get hasUploads() {
        return this.uploadedFiles.length > 0;
    }

    handleUploadFinished(event) {
        const files = (event.detail && event.detail.files) || [];
        this.uploadedFiles = [
            ...this.uploadedFiles,
            ...files.map((f) => ({ id: f.documentId, name: f.name }))
        ];
        this.toast(
            files.length === 1 ? 'File attached' : `${files.length} files attached`,
            'Ask GUS to read it. Plain text, CSV, JSON and Markdown can be read; PDF and Word cannot.',
            'success'
        );
    }

    // ─── chat delta ──────────────────────────────────────────────────────────

    /**
     * The server returns a proposal, never a write. Re-dispatched to the editor,
     * which puts it in the rich-text field and leaves Save Draft to the rep.
     */
    handleAgentDelta(event) {
        const changes = (event.detail && event.detail.changes) || {};
        if (typeof changes.draftContent !== 'string') return;
        this.dispatchEvent(
            new CustomEvent('draftproposed', {
                detail: { draftContent: changes.draftContent },
                bubbles: false,
                composed: false
            })
        );
    }

    // ─── util ────────────────────────────────────────────────────────────────

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
