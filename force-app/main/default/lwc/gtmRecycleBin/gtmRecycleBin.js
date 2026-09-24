import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getArchivedItems from '@salesforce/apex/GTM_RecycleBinController.getArchivedItems';
import restoreRecord from '@salesforce/apex/GTM_RecycleBinController.restoreRecord';
import restoreRecords from '@salesforce/apex/GTM_RecycleBinController.restoreRecords';
import deleteRecords from '@salesforce/apex/GTM_RecycleBinController.deleteRecords';

const COLUMNS = [
    { label: 'Name', fieldName: 'recordName', type: 'text', wrapText: true },
    { label: 'Type', fieldName: 'objectTypeLabel', type: 'text' },
    { label: 'Offering', fieldName: 'offeringKey', type: 'text' },
    { label: 'Archived Date', fieldName: 'archivedDate', type: 'date',
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
    { label: 'Archived By', fieldName: 'archivedBy', type: 'text' },
    { label: 'Offering Tile', fieldName: 'isOfferingTile', type: 'boolean' },
    {
        type: 'action',
        typeAttributes: { rowActions: [{ label: 'Restore', name: 'restore' }] }
    }
];

const OBJECT_TYPE_LABELS = {
    GTM_Page_Section__c: 'Section',
    GTM_Page_Content__c: 'Content'
};

/**
 * Recycle-bin front end for GTM_RecycleBinController (issue #184, part 3 of
 * 5). Lists every archived GTM_Page_Section__c/GTM_Page_Content__c row, with
 * row-level restore, checkbox-driven bulk restore, and a two-step-confirmed
 * bulk permanent delete ("Delete Selected Permanently") over whatever rows
 * are currently checked -- there is no separate no-selection "nuke
 * everything" action, per TASK_SCOPE.md's own resolution of that ambiguity.
 *
 * No server-side pagination/filtering exists on getArchivedItems() (hard
 * LIMIT 1000 per object) -- client-side search only, same shape
 * gtmContentHome already uses over getHomeSummary()'s full payload.
 */
export default class GtmRecycleBin extends LightningElement {
    @track items = [];
    @track selectedIds = [];
    @track isLoading = true;
    @track loadError = '';
    @track searchTerm = '';

    @track isRestoringBulk = false;
    @track isDeleting = false;

    // Delete Selected Permanently two-step confirm
    @track deleteConfirmStep = 0; // 0 = no modal, 1 = step one, 2 = step two

    columns = COLUMNS;

    connectedCallback() {
        this.load();
    }

    load() {
        this.isLoading = true;
        this.loadError = '';
        return getArchivedItems()
            .then((data) => {
                this.items = (data || []).map((item) => this.toRow(item));
                // Drop selections for rows no longer present (e.g. just
                // restored/deleted) rather than leaving stale ids selected.
                const validIds = new Set(this.items.map((r) => r.recordId));
                this.selectedIds = this.selectedIds.filter((id) => validIds.has(id));
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'The recycle bin could not be loaded.';
            })
            .finally(() => { this.isLoading = false; });
    }

    toRow(item) {
        return {
            recordId: item.recordId,
            objectType: item.objectType,
            objectTypeLabel: OBJECT_TYPE_LABELS[item.objectType] || item.objectType,
            recordName: item.recordName,
            offeringKey: item.offeringKey,
            archivedDate: item.archivedDate,
            archivedBy: item.archivedBy,
            isOfferingTile: !!item.isOfferingTile
        };
    }

    handleRefresh() {
        this.load();
    }

    handleSearch(event) {
        this.searchTerm = event.detail.value || '';
    }

    get filteredItems() {
        const q = (this.searchTerm || '').trim().toLowerCase();
        if (!q) return this.items;
        return this.items.filter((r) =>
            (r.recordName || '').toLowerCase().includes(q)
            || (r.offeringKey || '').toLowerCase().includes(q)
            || (r.objectTypeLabel || '').toLowerCase().includes(q)
        );
    }

    get selectionMeta() {
        const count = this.items.length;
        return `${count} archived item${count === 1 ? '' : 's'}${this.hasSelection ? ` · ${this.selectionCount} selected` : ''}`;
    }

    get hasItems() { return this.items.length > 0; }
    get hasFilteredItems() { return this.filteredItems.length > 0; }
    get hasSelection() { return this.selectedIds.length > 0; }
    get selectionCount() { return this.selectedIds.length; }
    get headerActions() {
        return [
            { name: 'refresh', label: 'Refresh', iconName: 'utility:refresh', disabled: this.isLoading },
            { name: 'restore-selected', label: 'Restore selected', iconName: 'utility:undo', disabled: this.restoreSelectedDisabled },
            { name: 'delete-selected', label: 'Delete Selected Permanently', iconName: 'utility:delete', variant: 'destructive', disabled: this.emptyTrashDisabled }
        ];
    }

    // Delete only opens the existing two-step confirm modal.
    handleHeaderAction(event) {
        switch (event.detail.name) {
            case 'refresh': this.handleRefresh(); break;
            case 'restore-selected': this.handleBulkRestore(); break;
            case 'delete-selected': this.handleAskEmptyTrash(); break;
            default: break;
        }
    }

    get restoreSelectedDisabled() { return !this.hasSelection || this.isRestoringBulk; }
    get emptyTrashDisabled() { return !this.hasSelection || this.isDeleting; }

    // ─── Row-level restore ──────────────────────────────────────────────

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        if (action.name === 'restore') {
            this.restoreOne(row.recordId);
        }
    }

    restoreOne(recordId) {
        this.isRestoringBulk = true;
        restoreRecord({ recordId })
            .then(() => {
                this.toast('Restored', 'The record was restored.', 'success');
                return this.load();
            })
            .catch((err) => {
                this.toast('Could not restore', this.messageFrom(err), 'error');
            })
            .finally(() => { this.isRestoringBulk = false; });
    }

    // ─── Bulk selection ─────────────────────────────────────────────────

    handleRowSelection(event) {
        this.selectedIds = (event.detail.selectedRows || []).map((r) => r.recordId);
    }

    // ─── Bulk restore ───────────────────────────────────────────────────

    handleBulkRestore() {
        if (!this.hasSelection) return;
        const recordIds = [...this.selectedIds];
        this.isRestoringBulk = true;
        restoreRecords({ recordIds })
            .then((results) => {
                this.reportBulkResults(results, 'restored');
                return this.load();
            })
            .catch((err) => {
                this.toast('Could not restore', this.messageFrom(err), 'error');
            })
            .finally(() => { this.isRestoringBulk = false; });
    }

    reportBulkResults(results, verb) {
        const list = results || [];
        const succeeded = list.filter((r) => r.success);
        const failed = list.filter((r) => !r.success);
        if (failed.length === 0) {
            this.toast('Success', `${succeeded.length} record${succeeded.length === 1 ? '' : 's'} ${verb}.`, 'success');
        } else if (succeeded.length === 0) {
            this.toast('Could not ' + verb.replace(/d$/, ''), this.summarizeFailures(failed), 'error');
        } else {
            this.toast(
                'Partial success',
                `${succeeded.length} ${verb}, ${failed.length} could not be ${verb}: ${this.summarizeFailures(failed)}`,
                'warning'
            );
        }
    }

    summarizeFailures(failed) {
        return failed.map((r) => r.message || 'Unknown error').join('; ');
    }

    // ─── Delete Selected Permanently (permanent delete over the current selection) ─────

    handleAskEmptyTrash() {
        if (!this.hasSelection) return;
        this.deleteConfirmStep = 1;
    }

    handleDeleteStepNext() {
        this.deleteConfirmStep = 2;
    }

    handleCancelDelete() {
        this.deleteConfirmStep = 0;
    }

    get showDeleteStepOne() { return this.deleteConfirmStep === 1; }
    get showDeleteStepTwo() { return this.deleteConfirmStep === 2; }
    get showDeleteModal() { return this.deleteConfirmStep > 0; }

    handleConfirmDelete() {
        if (!this.hasSelection) return;
        const recordIds = [...this.selectedIds];
        this.isDeleting = true;
        this.deleteConfirmStep = 0;
        deleteRecords({ recordIds })
            .then((results) => {
                this.reportBulkResults(results, 'deleted');
                return this.load();
            })
            .catch((err) => {
                this.toast('Could not delete', this.messageFrom(err), 'error');
            })
            .finally(() => { this.isDeleting = false; });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }
}
