import { LightningElement, api, track } from 'lwc';
import saveContentRecord from '@salesforce/apex/MaPageContentController.saveContentRecord';
import deleteContentRecord from '@salesforce/apex/MaPageContentController.deleteContentRecord';

export default class GtmContentField extends LightningElement {
    @api record;

    @track isSaving = false;
    @track saveLabel = 'Save';
    @track saveError = '';
    @track jsonError = '';

    get fieldClass() {
        return 'gcf' + (this.record && !this.record.active ? ' gcf--inactive' : '');
    }

    get isText() { return !this.record || this.record.fieldType === 'text'; }
    get isRich() { return this.record && this.record.fieldType === 'rich'; }
    get isJson() { return this.record && this.record.fieldType === 'json'; }

    handleTextChange(event) {
        this.record = { ...this.record, textValue: event.target.value };
    }

    handleRichChange(event) {
        this.record = { ...this.record, richValue: event.target.value };
    }

    handleJsonChange(event) {
        this.jsonError = '';
        const raw = event.target.value;
        try {
            if (raw && raw.trim()) JSON.parse(raw);
        } catch (e) {
            this.jsonError = 'Invalid JSON — ' + e.message;
        }
        this.record = { ...this.record, jsonValue: raw };
    }

    async handleSave() {
        if (this.isJson && this.jsonError) return;
        this.isSaving = true;
        this.saveError = '';
        this.saveLabel = 'Saving…';
        try {
            const newId = await saveContentRecord({ payload: this.record });
            this.record = { ...this.record, id: newId };
            this.saveLabel = 'Saved ✓';
            this.dispatchEvent(new CustomEvent('contentsaved', { detail: { record: this.record }, bubbles: true }));
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => { this.saveLabel = 'Save'; }, 2000);
        } catch (e) {
            this.saveError = (e && e.body && e.body.message) ? e.body.message : 'Save failed';
            this.saveLabel = 'Save';
        } finally {
            this.isSaving = false;
        }
    }

    async handleDelete() {
        if (!this.record || !this.record.id) return;
        // eslint-disable-next-line no-alert
        if (!confirm(`Delete "${this.record.fieldKey}"? This cannot be undone.`)) return;
        try {
            await deleteContentRecord({ recordId: this.record.id });
            this.dispatchEvent(new CustomEvent('contentdeleted', { detail: { record: this.record }, bubbles: true }));
        } catch (e) {
            this.saveError = (e && e.body && e.body.message) ? e.body.message : 'Delete failed';
        }
    }
}
