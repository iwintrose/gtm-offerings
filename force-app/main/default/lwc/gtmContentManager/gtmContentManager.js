import { LightningElement, api, track } from 'lwc';
import getAllContent from '@salesforce/apex/MaPageContentController.getAllContent';

const TEMPLATE_TYPE_OPTIONS = [
    { label: 'Configurator', value: 'configurator' },
    { label: 'Story', value: 'story' },
    { label: 'Offerings Listing', value: 'offerings-listing' },
    { label: 'Industry Chooser', value: 'industry-chooser' }
];

export default class GtmContentManager extends LightningElement {
    @api offeringKey = 'ma-migrator';

    @track templateType = 'configurator';
    @track _allRecords = [];
    @track isLoading = false;
    @track loadError = '';
    @track newSectionOpen = false;
    @track newSectionKey = '';
    // Optimistic stub records pending save (fieldcreate events before the save happens).
    @track _pendingStubs = [];

    templateTypeOptions = TEMPLATE_TYPE_OPTIONS;

    connectedCallback() {
        this.loadContent();
    }

    loadContent() {
        this.isLoading = true;
        this.loadError = '';
        this._pendingStubs = [];
        getAllContent({ offeringKey: this.offeringKey, templateType: this.templateType })
            .then((records) => {
                this._allRecords = records || [];
            })
            .catch((err) => {
                this.loadError = (err && err.body && err.body.message) ? err.body.message : 'Failed to load content.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    get hasContent() {
        return (this._allRecords.length + this._pendingStubs.length) > 0;
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
            result.push({ sectionKey, records });
        });
        // Stable sort by section key alphabetically (records are already ORDER BY sectionKey from Apex)
        result.sort((a, b) => a.sectionKey.localeCompare(b.sectionKey));
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
}
