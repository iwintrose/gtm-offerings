import { LightningElement, api, track } from 'lwc';
import { fieldMeta } from 'c/gtmContentSchema';

const FIELD_TYPE_OPTIONS = [
    { label: 'Text', value: 'text' },
    { label: 'Rich Text', value: 'rich' },
    { label: 'JSON (Structured)', value: 'json' }
];

export default class GtmContentSection extends LightningElement {
    @api sectionKey;
    @api sectionLabel;
    @api sectionHelp;
    @api offeringKey;
    @api templateType;
    @api records = [];

    @track open = true;
    @track addOpen = false;
    @track newFieldKey = '';
    @track newFieldType = 'text';
    @track newIndustryKey = '';

    fieldTypeOptions = FIELD_TYPE_OPTIONS;

    get displayLabel() { return this.sectionLabel || this.sectionKey; }
    get recordCount() { return `${this.records ? this.records.length : 0} field(s)`; }
    get toggleIcon() { return this.open ? '▲' : '▼'; }

    get fieldsWithMeta() {
        return (this.records || []).map((rec) => {
            const meta = fieldMeta(this.templateType, this.sectionKey, rec.fieldKey);
            return { ...rec, displayLabel: meta.label, displayHelp: meta.help };
        });
    }

    handleToggle() {
        this.open = !this.open;
    }

    handleSaved(event) {
        this.dispatchEvent(new CustomEvent('contentsaved', { detail: event.detail, bubbles: true }));
    }

    handleDeleted(event) {
        this.dispatchEvent(new CustomEvent('contentdeleted', { detail: event.detail, bubbles: true }));
    }

    handleAddOpen() { this.addOpen = true; }
    handleAddCancel() {
        this.addOpen = false;
        this.newFieldKey = '';
        this.newFieldType = 'text';
        this.newIndustryKey = '';
    }

    handleNewFieldKeyChange(event) { this.newFieldKey = event.target.value; }
    handleNewFieldTypeChange(event) { this.newFieldType = event.detail.value; }
    handleNewIndustryKeyChange(event) { this.newIndustryKey = event.target.value; }

    handleAddConfirm() {
        if (!this.newFieldKey || !this.newFieldKey.trim()) return;
        const stub = {
            id: null,
            offeringKey: this.offeringKey,
            templateType: this.templateType,
            sectionKey: this.sectionKey,
            fieldKey: this.newFieldKey.trim(),
            fieldType: this.newFieldType,
            textValue: null,
            richValue: null,
            jsonValue: null,
            industryKey: this.newIndustryKey.trim() || null,
            sortOrder: this.records ? this.records.length : 0,
            active: true,
            contentAddress: `${this.offeringKey}::${this.templateType}::${this.sectionKey}::${this.newFieldKey.trim()}`
        };
        this.dispatchEvent(new CustomEvent('fieldcreate', { detail: { record: stub }, bubbles: true }));
        this.handleAddCancel();
    }
}
