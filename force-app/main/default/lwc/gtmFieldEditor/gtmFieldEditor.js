import { LightningElement, api, track } from 'lwc';
import createField from '@salesforce/apex/MaPageSectionController.createField';
import deleteField from '@salesforce/apex/MaPageSectionController.deleteField';
import restoreField from '@salesforce/apex/MaPageSectionController.restoreField';
import saveFieldOrder from '@salesforce/apex/MaPageSectionController.saveFieldOrder';
import { fieldsFor } from 'c/gtmPageLayouts';

// Which value column each field type resolves from. Mirrors
// MaPageContentController.resolveValue.
const COLUMN = { text: 'textValue', rich: 'richValue', json: 'jsonValue' };

/**
 * The middle column: the fields of one section, and everything that changes
 * the shape of that section's schema.
 *
 * Split from c/gtmContentManager on the line between values and structure.
 * This component owns how a field is presented and what fields exist; the
 * parent owns the working copy of their values, because that copy also feeds
 * the preview and the autosave. So an edit leaves here as an event, while
 * adding, reordering and removing fields are handled here and announced when
 * they land.
 */
export default class GtmFieldEditor extends LightningElement {
    @api records = [];
    @api activeKey = '';
    @api sectionLabel = '';
    @api sectionHelp = '';
    @api sectionAddress = '';
    @api layoutType = '';
    @api offeringKey = '';
    @api templateType = '';
    @api busy = false;

    @track addFieldOpen = false;
    @track nfLabel = '';
    @track nfKey = '';
    @track nfType = 'text';
    @track nfHelp = '';
    @track nfKeyTouched = false;

    get isSaving() { return this.busy; }

    emitValue(recordId, value) {
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { recordId, value }
        }));
    }

    // Adding, removing or reordering a field changes what the page is made of,
    // so the parent reloads rather than trying to patch its copy.
    announceChange(message) {
        this.dispatchEvent(new CustomEvent('fieldschanged', { detail: { message } }));
    }

    raise(err, fallback) {
        const message = (err && err.body && err.body.message) || (err && err.message) || fallback;
        this.dispatchEvent(new CustomEvent('error', { detail: { message } }));
    }

    // ─── field editor ─────────────────────────────────────────────────────────


    /**
     * Builds the editable shape for each field. JSON payloads become repeaters:
     * the item shape is read from the data itself, so a list of strings gets one
     * input per entry and a list of objects gets one labelled input per key.
     * Nothing here knows what a capability card or an FAQ entry is.
     */
    get activeFields() {
        return this.records
            .filter((r) => r.sectionKey === this.activeKey)
            .map((r) => {
                const type = r.fieldType || 'text';
                // Show the working copy where one exists; the published value
                // otherwise. The live page always reads the published column.
                const value = r.isDraft ? (r.draftValue || '') : (r[COLUMN[type]] || '');
                const base = {
                    ...r,
                    value,
                    displayLabel: r.label || r.fieldKey,
                    hasHelp: !!r.helpText,
                    column: COLUMN[type],
                    isText: type === 'text',
                    isTextLong: type === 'text' && r.renderLong === true,
                    isTextShort: type === 'text' && r.renderLong !== true,
                    isRich: type === 'rich',
                    isJson: type === 'json',
                    statusClass: r.isDraft ? 'fld-status fld-status--draft' : 'fld-status',
                    statusLabel: r.isDraft ? 'Draft' : ''
                };
                if (base.isJson) base.items = this.buildItems(r.id, value);
                return base;
            })
            .map((f, i, all) => ({
                ...f,
                isFirst: i === 0,
                isLast: i === all.length - 1,
                statusClass: f.pendingDelete
                    ? 'fld-status fld-status--doomed'
                    : (f.isDraft ? 'fld-status fld-status--draft' : 'fld-status'),
                statusLabel: f.pendingDelete ? 'Delete on publish' : (f.isDraft ? 'Draft' : ''),
                fieldClass: f.pendingDelete ? 'fld fld--doomed' : 'fld'
            }));
    }

    buildItems(recordId, raw) {
        let parsed;
        try { parsed = JSON.parse(raw); } catch (e) { parsed = null; }
        if (!Array.isArray(parsed)) return [];
        return parsed.map((entry, index) => {
            const isScalar = typeof entry !== 'object' || entry === null;
            const fields = isScalar
                ? [{ key: '__value', label: 'Value', value: String(entry), isLong: String(entry).length > 60 }]
                : Object.keys(entry).map((k) => ({
                    key: k,
                    label: this.humanise(k),
                    value: typeof entry[k] === 'boolean' ? String(entry[k]) : (entry[k] || ''),
                    isBool: typeof entry[k] === 'boolean',
                    checked: entry[k] === true,
                    isLong: !(typeof entry[k] === 'boolean') && String(entry[k] || '').length > 60
                }));
            return {
                id: `${recordId}-${index}`,
                recordId,
                index,
                position: index + 1,
                isFirst: index === 0,
                isLast: index === parsed.length - 1,
                isScalar,
                fields
            };
        });
    }

    humanise(key) {
        return key
            .replace(/([A-Z])/g, ' $1')
            .replace(/^./, (c) => c.toUpperCase())
            .trim();
    }

    get fieldCountLabel() {
        const n = this.activeFields.length;
        return `${n} field${n === 1 ? '' : 's'}`;
    }


    // ─── edits ────────────────────────────────────────────────────────────────

    handleTextChange(event) {
        this.emitValue(event.currentTarget.dataset.id, event.target.value);
    }

    handleRichChange(event) {
        this.emitValue(event.currentTarget.dataset.id, event.target.value);
    }

    handleItemChange(event) {
        const { id, key, index } = event.currentTarget.dataset;
        const raw = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.mutateJson(id, Number(index), (entry) => {
            if (key === '__value') return raw;
            return { ...entry, [key]: raw };
        });
    }

    handleItemMove(event) {
        const { id, index, dir } = event.currentTarget.dataset;
        const from = Number(index);
        const to = from + (dir === 'up' ? -1 : 1);
        this.reorderJson(id, from, to);
    }

    handleItemDelete(event) {
        const { id, index } = event.currentTarget.dataset;
        this.spliceJson(id, Number(index));
    }

    handleItemAdd(event) {
        const id = event.currentTarget.dataset.id;
        this.appendJson(id);
    }

    // JSON helpers — each reads the record, edits the parsed array, writes back.

    parseOf(recordId) {
        const rec = this.records.find((r) => r.id === recordId);
        if (!rec) return null;
        const raw = rec.isDraft ? (rec.draftValue || '[]') : (rec.jsonValue || '[]');
        try {
            const parsed = JSON.parse(raw);
            return Array.isArray(parsed) ? parsed : null;
        } catch (e) { return null; }
    }

    commitJson(recordId, list) {
        this.emitValue(recordId, JSON.stringify(list));
    }

    mutateJson(recordId, index, fn) {
        const list = this.parseOf(recordId);
        if (!list || index < 0 || index >= list.length) return;
        list[index] = fn(list[index]);
        this.commitJson(recordId, list);
    }

    reorderJson(recordId, from, to) {
        const list = this.parseOf(recordId);
        if (!list || to < 0 || to >= list.length) return;
        list.splice(to, 0, list.splice(from, 1)[0]);
        this.commitJson(recordId, list);
    }

    spliceJson(recordId, index) {
        const list = this.parseOf(recordId);
        if (!list || list.length <= 1) return;
        list.splice(index, 1);
        this.commitJson(recordId, list);
    }

    appendJson(recordId) {
        const list = this.parseOf(recordId);
        if (!list) return;
        const template = list.length && typeof list[0] === 'object' && list[0] !== null
            ? Object.keys(list[0]).reduce((acc, k) => {
                acc[k] = typeof list[0][k] === 'boolean' ? false : '';
                return acc;
            }, {})
            : '';
        list.push(template);
        this.commitJson(recordId, list);
    }

    // ─── add a field ──────────────────────────────────────────────────────────
    // Unlike "add section", this is not limited to what a layout declares: the
    // renderer draws fields it does not recognise generically, so an editor can
    // put something on a page that nobody designed a slot for.

    get fieldTypeOptions() {
        return [
            { label: 'Plain text', value: 'text' },
            { label: 'Rich text', value: 'rich' },
            { label: 'List', value: 'json' }
        ];
    }

    get nfTypeHint() {
        if (this.nfType === 'rich') return 'A formatted paragraph, with bold, italic and links.';
        if (this.nfType === 'json') {
            return 'A repeating list. Its shape is read from what you put in it: '
                 + 'plain entries become chips, two-part entries a titled paragraph, '
                 + 'three-part entries cards.';
        }
        return 'A single line or paragraph of unformatted text.';
    }

    get nfAddress() {
        const key = this.camelKey(this.nfKey || this.nfLabel);
        return key
            ? `${this.offeringKey}::${this.templateType}::${this.activeKey}::${key}`
            : '';
    }

    get addFieldDisabled() {
        return !this.camelKey(this.nfKey || this.nfLabel) || !this.nfLabel.trim() || this.isSaving;
    }

    /**
     * A field key is an address segment, so it has to survive being joined and
     * split on "::". camelCase rather than hyphens, to match the keys the
     * layouts already use.
     */
    camelKey(raw) {
        const words = String(raw || '').trim().toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
        if (!words.length) return '';
        return words
            .map((w, i) => (i === 0 ? w : w.charAt(0).toUpperCase() + w.slice(1)))
            .join('')
            .slice(0, 60);
    }

    handleOpenAddField() {
        if (!this.activeKey) return;
        this.addFieldOpen = true;
        this.nfLabel = '';
        this.nfKey = '';
        this.nfType = 'text';
        this.nfHelp = '';
        this.nfKeyTouched = false;
    }

    handleCloseAddField() { this.addFieldOpen = false; }

    handleNfLabel(event) {
        this.nfLabel = event.target.value;
        // The key follows the label until someone edits the key themselves;
        // after that it is theirs and we stop overwriting it.
        if (!this.nfKeyTouched) this.nfKey = this.camelKey(this.nfLabel);
    }

    handleNfKey(event) {
        this.nfKeyTouched = true;
        this.nfKey = event.target.value;
    }

    handleNfType(event) { this.nfType = event.detail.value; }
    handleNfHelp(event) { this.nfHelp = event.target.value; }

    handleCreateField() {
        const key = this.camelKey(this.nfKey || this.nfLabel);
        if (!key) return;
        this.addFieldOpen = false;
        this.addField(key, this.nfType, this.nfLabel.trim(), this.nfHelp.trim() || null);
    }

    /**
     * One code path for both ways a field gets created: chosen from the
     * layout's own vocabulary, or invented in the modal. They differ in where
     * the arguments come from, not in what happens.
     */
    addField(fieldKey, fieldType, label, helpText) {
        createField({
            offeringKey: this.offeringKey,
            templateType: this.templateType,
            sectionKey: this.activeKey,
            fieldKey,
            fieldType,
            label,
            helpText
        })
            .then(() => { this.announceChange('Field added'); })
            .catch((err) => { this.raise(err, 'The field could not be added.'); });
    }

    // ─── field order and removal ──────────────────────────────────────────────

    handleFieldUp(event) { this.moveField(event.currentTarget.dataset.id, -1); }
    handleFieldDown(event) { this.moveField(event.currentTarget.dataset.id, 1); }

    /**
     * Field order is the order of the boxes in this editor. The renderer
     * resolves a layout's fields by name, not position, so this changes nothing
     * on the page and needs no publish — which is why it saves straight away
     * while section order does not.
     */
    moveField(recordId, delta) {
        const inSection = this.records.filter((r) => r.sectionKey === this.activeKey);
        const from = inSection.findIndex((r) => r.id === recordId);
        const to = from + delta;
        if (from < 0 || to < 0 || to >= inSection.length) return;
        const reordered = [...inSection];
        reordered.splice(to, 0, reordered.splice(from, 1)[0]);

        saveFieldOrder({ recordIds: reordered.map((r) => r.id) })
            .then(() => { this.saveMessage = 'Field order saved'; })
            .catch((err) => { this.raise(err, 'The field order could not be saved.'); })
            .finally(() => { this.isSaving = false; });
    }

    handleFieldDelete(event) {
        deleteField({ recordId: event.currentTarget.dataset.id })
            .then((removedNow) => {
                this.announceChange(removedNow
                    ? 'Field removed'
                    : 'Marked for deletion — publish to remove it');
            })
            .catch((err) => { this.raise(err, 'The field could not be deleted.'); });
    }

    handleFieldRestore(event) {
        restoreField({ recordId: event.currentTarget.dataset.id })
            .then(() => { this.announceChange('Delete undone'); })
            .catch((err) => { this.raise(err, 'The field could not be restored.'); });
    }


    // ─── missing fields ───────────────────────────────────────────────────────
    // A field the layout declares but the section has no record for. The page
    // falls back to a built-in default for these, which looks like content
    // nobody can edit; offering them here is how that gets fixed.

    get missingFields() {
        if (!this.layoutType) return [];
        const present = new Set(
            this.records
                .filter((r) => r.sectionKey === this.activeKey)
                .map((r) => r.fieldKey)
        );
        return fieldsFor(this.layoutType)
            .filter((f) => !present.has(f.fieldKey))
            .map((f) => ({ ...f, id: `${this.activeKey}-${f.fieldKey}` }));
    }

    get hasMissingFields() { return this.missingFields.length > 0; }

    get missingSummary() {
        const n = this.missingFields.length;
        return n === 1
            ? '1 field this layout supports has no record yet.'
            : `${n} fields this layout supports have no record yet.`;
    }

    handleAddField(event) {
        const fieldKey = event.currentTarget.dataset.field;
        const spec = this.missingFields.find((f) => f.fieldKey === fieldKey);
        if (!spec) return;
        this.addField(spec.fieldKey, spec.fieldType, spec.label, null);
    }

    // Resolved by Apex from the offering's configured site path, not built
    // here: a relative link would resolve against the Lightning domain, where
    // Experience Cloud sites do not exist.
}
