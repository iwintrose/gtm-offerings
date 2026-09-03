import { LightningElement, api, track } from 'lwc';
import getAllContent from '@salesforce/apex/MaPageContentController.getAllContent';
import { sectionMeta } from 'c/gtmContentSchema';

const TEMPLATE_TYPE_OPTIONS = [
    { label: 'Configurator', value: 'configurator' },
    { label: 'Story', value: 'story' },
    { label: 'Offerings Listing', value: 'offerings-listing' },
    { label: 'Industry Chooser', value: 'industry-chooser' }
];

export default class GtmContentManager extends LightningElement {
    @api offeringKey = 'migration-accelerator';

    @track templateType = 'story';
    @track _allRecords = [];
    @track _draftRecords = [];
    @track isLoading = false;
    @track loadError = '';
    @track newSectionOpen = false;
    @track newSectionKey = '';
    @track _pendingStubs = [];
    @track dividerPos = 60;
    @track isDraggingDivider = false;
    @track showVersionHistory = false;
    @track isSaving = false;
    @track saveMessage = '';

    templateTypeOptions = TEMPLATE_TYPE_OPTIONS;

    connectedCallback() {
        this.loadContent();
        document.addEventListener('mousemove', this.handleMouseMove.bind(this));
        document.addEventListener('mouseup', this.handleMouseUp.bind(this));
    }

    disconnectedCallback() {
        document.removeEventListener('mousemove', this.handleMouseMove.bind(this));
        document.removeEventListener('mouseup', this.handleMouseUp.bind(this));
    }

    loadContent() {
        this.isLoading = true;
        this.loadError = '';
        this._pendingStubs = [];
        getAllContent({ offeringKey: this.offeringKey, templateType: this.templateType })
            .then((records) => {
                this._allRecords = records || [];
                // Initialize draft records from loaded content (or from draft status)
                this._draftRecords = JSON.parse(JSON.stringify(this._allRecords));
            })
            .catch((err) => {
                this.loadError = (err && err.body && err.body.message) ? err.body.message : 'Failed to load content.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleMouseDown() {
        this.isDraggingDivider = true;
    }

    handleMouseMove(event) {
        if (!this.isDraggingDivider) return;
        const gcm = this.template.querySelector('.gcm-split');
        if (!gcm) return;
        const rect = gcm.getBoundingClientRect();
        const newPos = ((event.clientX - rect.left) / rect.width) * 100;
        if (newPos > 40 && newPos < 80) {
            this.dividerPos = newPos;
        }
    }

    handleMouseUp() {
        this.isDraggingDivider = false;
    }

    get hasContent() {
        return (this._allRecords.length + this._pendingStubs.length) > 0;
    }

    get draftSections() {
        const combined = [...this._draftRecords, ...this._pendingStubs];
        const map = new Map();
        combined.forEach((rec) => {
            const sk = rec.sectionKey;
            if (!map.has(sk)) map.set(sk, []);
            map.get(sk).push(rec);
        });
        const result = [];
        map.forEach((records, sectionKey) => {
            const meta = sectionMeta(this.templateType, sectionKey);
            result.push({ sectionKey, records, label: meta.label, help: meta.help, order: meta.order });
        });
        result.sort((a, b) => (a.order - b.order) || a.sectionKey.localeCompare(b.sectionKey));
        return result;
    }

    get editorStyle() {
        return `width: ${this.dividerPos}%;`;
    }

    get previewStyle() {
        return `width: ${100 - this.dividerPos}%;`;
    }

    get hasDraftChanges() {
        // Simple comparison: check if draft differs from published
        return JSON.stringify(this._draftRecords) !== JSON.stringify(this._allRecords);
    }

    get sections() {
        const combined = [...this._allRecords, ...this._pendingStubs];
        const map = new Map();
        combined.forEach((rec) => {
            const sk = rec.sectionKey;
            if (!map.has(sk)) map.set(sk, []);
            map.get(sk).push(rec);
        });
        const result = [];
        map.forEach((records, sectionKey) => {
            const meta = sectionMeta(this.templateType, sectionKey);
            result.push({ sectionKey, records, label: meta.label, help: meta.help, order: meta.order });
        });
        // Known sections in their real page order first; anything not in the
        // schema yet falls to the back, alphabetically, instead of breaking.
        result.sort((a, b) => (a.order - b.order) || a.sectionKey.localeCompare(b.sectionKey));
        return result;
    }

    handleTemplateChange(event) {
        this.templateType = event.detail.value;
        this.loadContent();
    }

    handleRefresh() {
        this.loadContent();
    }

    handleContentSaved(event) {
        const saved = event.detail.record;
        // Update draft records immediately for live preview
        const draftIdx = this._draftRecords.findIndex(
            (r) => r.contentAddress === saved.contentAddress || (saved.id && r.id === saved.id)
        );
        if (draftIdx >= 0) {
            const updated = [...this._draftRecords];
            updated[draftIdx] = saved;
            this._draftRecords = updated;
        } else {
            this._draftRecords = [...this._draftRecords, saved];
        }

        // Replace matching record in _allRecords (or add if new).
        const idx = this._allRecords.findIndex(
            (r) => r.contentAddress === saved.contentAddress || (saved.id && r.id === saved.id)
        );
        if (idx >= 0) {
            const updated = [...this._allRecords];
            updated[idx] = saved;
            this._allRecords = updated;
        } else {
            this._allRecords = [...this._allRecords, saved];
        }
        // Remove any matching pending stub
        this._pendingStubs = this._pendingStubs.filter(
            (s) => s.contentAddress !== saved.contentAddress
        );
    }

    handleContentDeleted(event) {
        const deleted = event.detail.record;
        this._allRecords = this._allRecords.filter((r) => r.id !== deleted.id);
        this._pendingStubs = this._pendingStubs.filter(
            (s) => s.contentAddress !== deleted.contentAddress
        );
    }

    handleFieldCreate(event) {
        const stub = event.detail.record;
        // Show optimistically while the user edits and saves via gtmContentField.
        const exists = this._allRecords.some((r) => r.contentAddress === stub.contentAddress)
            || this._pendingStubs.some((s) => s.contentAddress === stub.contentAddress);
        if (!exists) {
            this._pendingStubs = [...this._pendingStubs, stub];
        }
    }

    handleNewSection() {
        this.newSectionOpen = true;
    }

    handleNewSectionKeyChange(event) {
        this.newSectionKey = event.target.value;
    }

    handleNewSectionConfirm() {
        const sk = (this.newSectionKey || '').trim();
        if (!sk) return;
        // Create a stub field so the section renders immediately.
        const stub = {
            id: null,
            offeringKey: this.offeringKey,
            templateType: this.templateType,
            sectionKey: sk,
            fieldKey: 'default',
            fieldType: 'text',
            textValue: null,
            richValue: null,
            jsonValue: null,
            industryKey: null,
            sortOrder: 0,
            active: true,
            contentAddress: `${this.offeringKey}::${this.templateType}::${sk}::default`
        };
        this._pendingStubs = [...this._pendingStubs, stub];
        this.handleNewSectionCancel();
    }

    handleNewSectionCancel() {
        this.newSectionOpen = false;
        this.newSectionKey = '';
    }

    handleSaveDraft() {
        this.isSaving = true;
        this.saveMessage = 'Saving draft…';
        // In a real implementation, this would mark all draft records with Status='Draft'
        // and save them to Salesforce. For now, just confirm locally.
        setTimeout(() => {
            this.isSaving = false;
            this.saveMessage = '✓ Draft saved';
            setTimeout(() => {
                this.saveMessage = '';
            }, 2000);
        }, 500);
    }

    handlePublish() {
        this.isSaving = true;
        this.saveMessage = 'Publishing…';
        // In a real implementation:
        // 1. Create version history records for current published state
        // 2. Mark all draft records with Status='Published'
        // 3. Update Version_Number and Last_Published_Date
        // 4. Save to Salesforce
        setTimeout(() => {
            this._allRecords = JSON.parse(JSON.stringify(this._draftRecords));
            this.isSaving = false;
            this.saveMessage = '✓ Published';
            setTimeout(() => {
                this.saveMessage = '';
            }, 2000);
        }, 500);
    }

    handleToggleVersionHistory() {
        this.showVersionHistory = !this.showVersionHistory;
    }
}
