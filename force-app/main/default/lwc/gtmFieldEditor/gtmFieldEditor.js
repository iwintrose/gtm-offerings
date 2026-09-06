import { LightningElement, api, track } from 'lwc';
import createField from '@salesforce/apex/MaPageSectionController.createField';
import deleteField from '@salesforce/apex/MaPageSectionController.deleteField';
import restoreField from '@salesforce/apex/MaPageSectionController.restoreField';
import saveFieldOrder from '@salesforce/apex/MaPageSectionController.saveFieldOrder';
import { fieldsFor, CTA_ICONS } from 'c/gtmPageLayouts';

// Which value column each field type resolves from. Mirrors
// MaPageContentController.resolveValue.
const COLUMN = {
    text: 'textValue',
    rich: 'richValue',
    json: 'jsonValue',
    // A button is a label and an icon, so it needs somewhere to keep two
    // things: the JSON column, same as a list.
    icontext: 'jsonValue'
};

const VALUE_COLUMN_LABEL = {
    text: 'Text_Value__c',
    rich: 'Rich_Value__c',
    json: 'JSON_Value__c',
    icontext: 'JSON_Value__c'
};

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
    // Which fields have their presentation panel open. Per field, not global:
    // opening one to check a class should not open all of them.
    @track advOpen = new Set();

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
                    isIconText: type === 'icontext',
                    typeTitle: `Field_Type__c — ${VALUE_COLUMN_LABEL[type] || 'Text_Value__c'}`,
                    advOpen: this.advOpen.has(r.id),
                    advClass: this.advOpen.has(r.id) ? 'fa fa--on' : 'fa',
                    cssClass: r.cssClass || '',
                    htmlId: r.htmlId || '',
                    inlineStyle: r.inlineStyle || '',
                    isTextLong: type === 'text' && r.renderLong === true,
                    isTextShort: type === 'text' && r.renderLong !== true,
                    isRich: type === 'rich',
                    isJson: type === 'json',
                    statusClass: r.isDraft ? 'fld-status fld-status--draft' : 'fld-status',
                    statusLabel: r.isDraft ? 'Draft' : ''
                };
                if (base.isJson) base.items = this.buildItems(r.id, value);
                if (base.isIconText) base.button = this.buildButton(value);
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

    /**
     * Turns a JSON payload into editable items.
     *
     * The shape is read from the data, not configured: a list of strings is one
     * input per entry; two string keys are a labelled pair side by side; three
     * or more put the first two side by side and give the rest room to breathe.
     * Boolean keys are flags on the item rather than fields in it, so they sit
     * in the item's header where flags belong. A first column whose values are
     * all a few characters long is a badge, and gets a badge-sized box.
     *
     * Nothing here knows what a capability card or an FAQ entry is, which is
     * what lets the same editor handle a payload it has never seen.
     */
    buildItems(recordId, raw) {
        let parsed;
        try { parsed = JSON.parse(raw); } catch (e) { parsed = null; }
        if (!Array.isArray(parsed)) return [];

        const objectRows = parsed.filter((e) => typeof e === 'object' && e !== null);
        const stringKeys = objectRows.length
            ? Object.keys(objectRows[0]).filter((k) => typeof objectRows[0][k] !== 'boolean')
            : [];
        const badgeKey = stringKeys.length > 2 && objectRows.every(
            (e) => String(e[stringKeys[0]] || '').length <= 3
        ) ? stringKeys[0] : null;

        return parsed.map((entry, index) => {
            const isScalar = typeof entry !== 'object' || entry === null;
            const base = {
                id: `${recordId}-${index}`,
                recordId,
                index,
                position: index + 1,
                isFirst: index === 0,
                isLast: index === parsed.length - 1,
                isScalar,
                value: isScalar ? String(entry) : '',
                flags: [],
                pair: [],
                rest: []
            };
            if (isScalar) return base;

            Object.keys(entry).forEach((k) => {
                if (typeof entry[k] === 'boolean') {
                    base.flags.push({
                        key: k,
                        label: this.humanise(k),
                        checked: entry[k] === true,
                        toggleClass: entry[k] === true ? 'hi-toggle hi-toggle--on' : 'hi-toggle'
                    });
                }
            });

            stringKeys.forEach((k, ki) => {
                const text = String(entry[k] == null ? '' : entry[k]);
                const cell = {
                    key: k,
                    label: this.humanise(k),
                    value: text,
                    isBadge: k === badgeKey,
                    // The last column of a three-part item is the prose one, so
                    // it gets a textarea whatever it currently happens to hold.
                    isLong: ki >= 2 || text.length > 70,
                    inputClass: k === badgeKey ? 'ctl tiny badge-in' : 'ctl tiny'
                };
                if (base.pair.length < 2 && !cell.isLong) base.pair.push(cell);
                else base.rest.push(cell);
            });
            base.hasPair = base.pair.length > 0;
            base.hasRest = base.rest.length > 0;
            base.hasFlags = base.flags.length > 0;
            return base;
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

    // ─── rich text ────────────────────────────────────────────────────────────
    // A contenteditable rather than a stock editor, because the toolbar this
    // page needs includes an accent command that tints a selection with the
    // page's own colour — not something a general-purpose editor offers.

    handleRichChange(event) {
        this.emitValue(event.currentTarget.dataset.id, event.currentTarget.innerHTML);
    }

    // Toolbar buttons steal focus on mousedown, which collapses the selection
    // before the command can act on it. Suppressing the default keeps it.
    handleRtGuard(event) { event.preventDefault(); }

    handleRtCommand(event) {
        const { id, cmd } = event.currentTarget.dataset;
        const box = this.template.querySelector(`.rt-in[data-id="${id}"]`);
        if (!box) return;
        box.focus();
        if (cmd === 'bold' || cmd === 'italic') {
            document.execCommand(cmd, false, null);
        } else if (cmd === 'br') {
            document.execCommand('insertHTML', false, '<br>');
        } else if (cmd === 'clear') {
            document.execCommand('removeFormat', false, null);
        } else if (cmd === 'accent') {
            const sel = window.getSelection();
            const text = sel && String(sel);
            if (!text) return;
            document.execCommand('insertHTML', false, `<span class="accent">${text}</span>`);
        }
        this.emitValue(id, box.innerHTML);
    }

    /**
     * contenteditable is written to once per field rather than bound, because
     * re-rendering it from its own value on every keystroke moves the caret to
     * the end of the box. lwc:dom="manual" is what makes that legal.
     */
    renderedCallback() {
        this.template.querySelectorAll('.rt-in').forEach((box) => {
            const id = box.dataset.id;
            const field = this.activeFields.find((f) => f.id === id);
            if (!field) return;
            if (box === this.template.activeElement) return;
            if (box.innerHTML !== field.value) box.innerHTML = field.value || '';
        });
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


    /**
     * A call-to-action button: its label, and which icon sits after it. Stored
     * as one JSON object rather than two records because they are one thing on
     * the page, and a label without its icon is a half-edited button.
     */
    buildButton(raw) {
        let v = {};
        try { const parsed = JSON.parse(raw); if (parsed && typeof parsed === 'object') v = parsed; }
        catch (e) { v = { label: raw || '' }; }
        return {
            label: v.label || '',
            icons: CTA_ICONS.map((i) => ({
                ...i,
                isNone: !i.value,
                pickClass: (v.icon || '') === i.value ? 'pick pick--on' : 'pick'
            }))
        };
    }

    handleButtonLabel(event) {
        this.writeButton(event.currentTarget.dataset.id, { label: event.target.value });
    }

    handleButtonIcon(event) {
        this.writeButton(event.currentTarget.dataset.id, { icon: event.currentTarget.dataset.icon });
    }

    writeButton(recordId, patch) {
        const rec = this.records.find((r) => r.id === recordId);
        if (!rec) return;
        const raw = rec.isDraft ? (rec.draftValue || '{}') : (rec.jsonValue || '{}');
        let current = {};
        try { const parsed = JSON.parse(raw); if (parsed && typeof parsed === 'object') current = parsed; }
        catch (e) { current = {}; }
        this.emitValue(recordId, JSON.stringify({ ...current, ...patch }));
    }

    // ─── per-field presentation ───────────────────────────────────────────────

    handleToggleAdv(event) {
        const id = event.currentTarget.dataset.id;
        const next = new Set(this.advOpen);
        if (next.has(id)) { next.delete(id); } else { next.add(id); }
        this.advOpen = next;
    }

    handleAdvChange(event) {
        this.dispatchEvent(new CustomEvent('presentationchange', {
            detail: {
                recordId: event.currentTarget.dataset.id,
                key: event.currentTarget.dataset.adv,
                value: event.target.value
            }
        }));
    }

    // ─── add a field ──────────────────────────────────────────────────────────
    // Unlike "add section", this is not limited to what a layout declares: the
    // renderer draws fields it does not recognise generically, so an editor can
    // put something on a page that nobody designed a slot for.

    get fieldTypeOptions() {
        return [
            { label: 'Plain text', value: 'text' },
            { label: 'Rich text', value: 'rich' },
            { label: 'List', value: 'json' },
            { label: 'Button (label + icon)', value: 'icontext' }
        ];
    }

    get nfTypeHint() {
        if (this.nfType === 'rich') return 'A formatted paragraph, with bold, italic and links.';
        if (this.nfType === 'icontext') {
            return 'A call-to-action button: its text, and which icon sits after it.';
        }
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

        // busy and saveMessage belong to the parent (@api busy / its own
        // saveMessage), not this component — announceChange is the existing
        // event this component already uses to hand a result back to it.
        saveFieldOrder({ recordIds: reordered.map((r) => r.id) })
            .then(() => { this.announceChange('Field order saved'); })
            .catch((err) => { this.raise(err, 'The field order could not be saved.'); });
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
