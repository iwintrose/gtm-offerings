import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import uploadAndIngest from '@salesforce/apex/ConduitCmmController.uploadAndIngest';
import activateVersion from '@salesforce/apex/ConduitCmmController.activateVersion';
import listVersions   from '@salesforce/apex/ConduitCmmController.listVersions';

const STATUS_CLASSES = {
    Ready:     'status-pill status-ready',
    Ingesting: 'status-pill status-progress',
    Uploaded:  'status-pill status-progress',
    Failed:    'status-pill status-failed',
};

export default class ConduitDataExtract extends LightningElement {
    @api recordId;

    @track versions = [];
    @track error    = null;
    @track isBusy   = false;

    _wiredVersions;

    @wire(listVersions, { assessmentId: '$recordId' })
    wired(result) {
        this._wiredVersions = result;
        if (result.data)  { this.versions = this._enrichVersions(result.data); this.error = null; }
        if (result.error) { this.error = result.error?.body?.message ?? 'Failed to load versions'; }
    }

    // ── Derived UI ──────────────────────────────────────────────────────────
    get hasVersions()   { return this.versions.length > 0; }
    get isEmpty()       { return !this.error && !this.hasVersions && !this.isBusy; }
    get activeVersion() { return this.versions.find(v => v.Is_Active__c) ?? null; }

    get uploadLabel() {
        if (this.isBusy) return 'Uploading…';
        return this.hasVersions ? 'Upload New Version' : 'Upload Platform Extract';
    }

    // Accept only .zip files.
    get acceptedFormats() { return ['.zip']; }

    // ── Actions ─────────────────────────────────────────────────────────────
    async handleUploadFinished(event) {
        const files = event.detail.files;
        if (!files || files.length === 0) return;
        const uploaded = files[0];

        this.isBusy = true;
        this.error = null;
        try {
            const created = await uploadAndIngest({
                assessmentId:   this.recordId,
                zipContentDocId: uploaded.documentId,
            });
            await refreshApex(this._wiredVersions);

            if (created.Status__c === 'Ready') {
                this._toast('success', 'CMM Ready', 'Version ' + created.Version__c + ' is now active.');
                this._notifyCmmActivated();
            } else if (created.Status__c === 'Failed') {
                this._toast('error', 'Ingest failed', created.Error_Message__c ?? 'Unknown error', 'sticky');
            } else {
                this._toast('warning', 'Ingest in progress', 'Version ' + created.Version__c + ' recorded — status: ' + created.Status__c);
            }
        } catch (err) {
            const msg = err?.body?.message ?? err?.message ?? 'Upload failed';
            this.error = msg;
            this._toast('error', 'Upload failed', msg, 'sticky');
        } finally {
            this.isBusy = false;
        }
    }

    async handleActivate(event) {
        const cmmId = event.currentTarget.dataset.id;
        if (!cmmId) return;
        this.isBusy = true;
        try {
            await activateVersion({ cmmId });
            await refreshApex(this._wiredVersions);
            this._toast('success', 'Activated', 'That version is now the active CMM.');
            this._notifyCmmActivated();
        } catch (err) {
            const msg = err?.body?.message ?? err?.message ?? 'Activate failed';
            this._toast('error', 'Could not activate', msg);
        } finally {
            this.isBusy = false;
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────────
    _enrichVersions(rows) {
        return rows.map(r => ({
            ...r,
            uploadedAtFormatted: r.Uploaded_At__c ? new Date(r.Uploaded_At__c).toLocaleString() : '—',
            uploadedByName:      r.Uploaded_By__r?.Name ?? '—',
            statusClass:         STATUS_CLASSES[r.Status__c] ?? 'status-pill',
            activateClass:       r.Is_Active__c ? 'action-btn action-active' : 'action-btn',
            activateLabel:       r.Is_Active__c ? 'Active' : 'Set Active',
            activateDisabled:    r.Is_Active__c || r.Status__c !== 'Ready',
            hasError:            r.Status__c === 'Failed' && !!r.Error_Message__c,
            rowClass:            'version-row' + (r.Is_Active__c ? ' version-row-active' : ''),
        }));
    }

    _toast(variant, title, message, mode = 'dismissable') {
        this.dispatchEvent(new ShowToastEvent({ variant, title, message, mode }));
    }

    // Signals sibling tabs (Estate, Migration Plan, etc.) that the active CMM
    // for this assessment has changed and they should re-fetch. Dashboard
    // (parent) listens for oncmmactivated and calls refresh() on every child
    // that exposes it.
    _notifyCmmActivated() {
        this.dispatchEvent(new CustomEvent('cmmactivated', { bubbles: true, composed: true }));
    }
}