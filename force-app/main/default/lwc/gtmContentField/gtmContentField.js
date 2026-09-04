import { LightningElement, api, track } from 'lwc';
import saveContentRecord from '@salesforce/apex/MaPageContentController.saveContentRecord';
import deleteContentRecord from '@salesforce/apex/MaPageContentController.deleteContentRecord';

const JSON_SHAPE = {
    STRING_LIST: 'stringList',
    OBJECT_LIST: 'objectList',
    RAW: 'raw'
};

export default class GtmContentField extends LightningElement {
    @api record;

    @track isSaving = false;
    @track saveLabel = 'Save';
    @track saveError = '';
    @track jsonError = '';
    @track showRawJson = false;

    _jsonShape = JSON_SHAPE.RAW;
    @track _stringItems = [];
    @track _objectItems = [];
    _objectKeys = [];
    _itemSeq = 0;

    connectedCallback() {
        this._parseJson();
    }

    get fieldClass() {
        return 'gcf' + (this.record && !this.record.active ? ' gcf--inactive' : '');
    }

    get displayLabel() {
        return (this.record && (this.record.displayLabel || this.record.fieldKey)) || '';
    }

    get displayHelp() { return this.record && this.record.displayHelp; }
    get hasHelp() { return !!this.displayHelp; }

    get isText() { return !this.record || this.record.fieldType === 'text'; }
    get isRich() { return this.record && this.record.fieldType === 'rich'; }
    get isJson() { return this.record && this.record.fieldType === 'json'; }

    get isStringList() { return this.isJson && this._jsonShape === JSON_SHAPE.STRING_LIST && !this.showRawJson; }
    get isObjectList() { return this.isJson && this._jsonShape === JSON_SHAPE.OBJECT_LIST && !this.showRawJson; }
    get isRawJson() { return this.isJson && (this._jsonShape === JSON_SHAPE.RAW || this.showRawJson); }
    get showRawToggle() { return this.isJson && this._jsonShape !== JSON_SHAPE.RAW; }
    get rawToggleLabel() { return this.showRawJson ? 'Use list editor' : 'Edit as raw JSON'; }

    get stringItemsForTemplate() { return this._stringItems; }
    get objectItemsForTemplate() { return this._objectItems; }

    // ---------------------------------------------------------------- parse

    _parseJson() {
        if (!this.isJson) return;
        const raw = this.record && this.record.jsonValue;
        let parsed;
        try {
            parsed = raw && raw.trim() ? JSON.parse(raw) : [];
        } catch (e) {
            this._jsonShape = JSON_SHAPE.RAW;
            return;
        }
        if (!Array.isArray(parsed)) {
            this._jsonShape = JSON_SHAPE.RAW;
            return;
        }
        if (parsed.length === 0) {
            // Nothing to infer a shape from yet -- default to the simpler,
            // more common editor so "+ Add item" has somewhere to start.
            this._jsonShape = JSON_SHAPE.STRING_LIST;
            this._stringItems = [];
            return;
        }
        if (parsed.every((item) => typeof item === 'string')) {
            this._jsonShape = JSON_SHAPE.STRING_LIST;
            this._stringItems = parsed.map((v) => this._newStringItem(v));
            return;
        }
        if (parsed.every((item) => item && typeof item === 'object' && !Array.isArray(item))) {
            this._jsonShape = JSON_SHAPE.OBJECT_LIST;
            this._objectKeys = Object.keys(parsed[0]);
            this._objectItems = parsed.map((obj) => this._newObjectItem(obj));
            return;
        }
        this._jsonShape = JSON_SHAPE.RAW;
    }

    _newStringItem(value) {
        this._itemSeq += 1;
        return { key: `s${this._itemSeq}`, value: value || '' };
    }

    _newObjectItem(obj) {
        this._itemSeq += 1;
        const fields = this._objectKeys.map((k) => {
            const v = obj ? obj[k] : '';
            const isBoolean = typeof v === 'boolean';
            return { field: k, value: isBoolean ? '' : (v || ''), isBoolean, boolValue: !!v };
        });
        return { key: `o${this._itemSeq}`, fields };
    }

    // ------------------------------------------------------------- sync out

    _syncStringItemsToRecord() {
        const arr = this._stringItems.map((i) => i.value);
        this.record = { ...this.record, jsonValue: JSON.stringify(arr) };
    }

    _syncObjectItemsToRecord() {
        const arr = this._objectItems.map((item) => {
            const obj = {};
            item.fields.forEach((f) => {
                obj[f.field] = f.isBoolean ? f.boolValue : f.value;
            });
            return obj;
        });
        this.record = { ...this.record, jsonValue: JSON.stringify(arr) };
    }

    // -------------------------------------------------------- string list

    handleStringItemChange(event) {
        const key = event.currentTarget.dataset.key;
        const value = event.target.value;
        this._stringItems = this._stringItems.map((i) => (i.key === key ? { ...i, value } : i));
        this._syncStringItemsToRecord();
    }

    handleStringItemRemove(event) {
        const key = event.currentTarget.dataset.key;
        this._stringItems = this._stringItems.filter((i) => i.key !== key);
        this._syncStringItemsToRecord();
    }

    handleStringItemAdd() {
        this._stringItems = [...this._stringItems, this._newStringItem('')];
        this._syncStringItemsToRecord();
    }

    // -------------------------------------------------------- object list

    handleObjectFieldChange(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        const fieldName = event.currentTarget.dataset.field;
        const isCheckbox = event.target.type === 'checkbox';
        const value = isCheckbox ? event.target.checked : event.target.value;
        this._objectItems = this._objectItems.map((item) => {
            if (item.key !== itemKey) return item;
            return {
                ...item,
                fields: item.fields.map((f) => {
                    if (f.field !== fieldName) return f;
                    return f.isBoolean ? { ...f, boolValue: value } : { ...f, value };
                })
            };
        });
        this._syncObjectItemsToRecord();
    }

    handleObjectItemRemove(event) {
        const itemKey = event.currentTarget.dataset.itemKey;
        this._objectItems = this._objectItems.filter((i) => i.key !== itemKey);
        this._syncObjectItemsToRecord();
    }

    handleObjectItemAdd() {
        this._objectItems = [...this._objectItems, this._newObjectItem(null)];
        this._syncObjectItemsToRecord();
    }

    // ------------------------------------------------------------ raw toggle

    handleToggleRaw() {
        this.showRawJson = !this.showRawJson;
    }

    // ------------------------------------------------------------- existing

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
        this._parseJson();
    }

    async handleSave() {
        if (this.isRawJson && this.jsonError) return;
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
        if (!confirm(`Delete "${this.displayLabel}"? This cannot be undone.`)) return;
        try {
            await deleteContentRecord({ recordId: this.record.id });
            this.dispatchEvent(new CustomEvent('contentdeleted', { detail: { record: this.record }, bubbles: true }));
        } catch (e) {
            this.saveError = (e && e.body && e.body.message) ? e.body.message : 'Delete failed';
        }
    }
}
