import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getOfferings from '@salesforce/apex/MaPageContentController.getOfferings';
import getTemplateSummary from '@salesforce/apex/MaPageContentController.getTemplateSummary';
import getEditorSections from '@salesforce/apex/MaPageContentController.getEditorSections';
import getAllContent from '@salesforce/apex/MaPageContentController.getAllContent';
import saveContentRecords from '@salesforce/apex/MaPageContentController.saveContentRecords';
import saveSectionOrder from '@salesforce/apex/MaPageContentController.saveSectionOrder';
import setSectionActive from '@salesforce/apex/MaPageContentController.setSectionActive';

// Which value column each field type resolves from. Mirrors
// MaPageContentController.resolveValue.
const COLUMN = { text: 'textValue', rich: 'richValue', json: 'jsonValue' };

const TEMPLATE_LABELS = {
    story: 'Story',
    configurator: 'Configurator',
    'offerings-listing': 'Offerings Listing',
    'industry-chooser': 'Industry Chooser'
};

const SECTION_ICONS = {
    'page-chrome': 'utility:page',
    hero: 'utility:brand_engagement',
    'lede-chips': 'utility:warning',
    'route-proof': 'utility:flow',
    'card-grid': 'utility:tile_card_list',
    stat: 'utility:metrics',
    'use-pitch': 'utility:announcement',
    faq: 'utility:question',
    closing: 'utility:success'
};

export default class GtmContentManager extends LightningElement {
    // Kept so the component can still be pinned to one offering on an App Page.
    // Blank means "let the user choose", which is the default on the tab.
    @api offeringKey = '';

    @track offerings = [];
    @track templates = [];
    @track selectedOffering = '';
    @track selectedTemplate = '';

    @track sections = [];
    @track records = [];
    @track activeKey = '';

    @track isLoading = false;
    @track isSaving = false;
    @track loadError = '';
    @track saveMessage = '';
    @track reorderMode = false;
    // Preview is a toggle so it can be turned off without a deploy, and so a
    // narrow window can reclaim the column.
    @track previewOn = true;
    @track dirtyKeys = [];

    _dragKey = '';
    _saveTimer;

    // Set when the home page deep-links into a specific page. Without this the
    // editor would always open on its own guess, which is the "landed somewhere
    // I didn't choose" problem the home page exists to fix.
    _requestedOffering = '';
    _requestedTemplate = '';

    @wire(CurrentPageReference)
    capturePageRef(ref) {
        if (!ref || !ref.state) return;
        this._requestedOffering = ref.state.c__offering || '';
        this._requestedTemplate = ref.state.c__template || '';
    }

    // ─── lifecycle ────────────────────────────────────────────────────────────

    connectedCallback() {
        this.isLoading = true;
        getOfferings()
            .then((rows) => {
                this.offerings = rows || [];
                // Priority: what the home page asked for, then a pinned page
                // property, then the only offering if there is exactly one.
                const preset = this._requestedOffering
                    || this.offeringKey
                    || (this.offerings.length === 1 ? this.offerings[0].offeringKey : '');
                if (preset) {
                    this.selectedOffering = preset;
                    return this.loadTemplates();
                }
                return null;
            })
            .catch((err) => { this.loadError = this.messageFrom(err) || 'Offerings could not be loaded.'; })
            .finally(() => { this.isLoading = false; });
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    // ─── offering / page selection ────────────────────────────────────────────

    get offeringOptions() {
        return this.offerings.map((o) => ({ label: o.label, value: o.offeringKey }));
    }

    get hasOffering() { return !!this.selectedOffering; }
    get hasTemplate() { return !!this.selectedTemplate; }

    get offeringLabel() {
        const o = this.offerings.find((x) => x.offeringKey === this.selectedOffering);
        return o ? o.label : this.selectedOffering;
    }

    handleOfferingChange(event) {
        this.selectedOffering = event.detail.value;
        this.selectedTemplate = '';
        this.sections = [];
        this.records = [];
        this.activeKey = '';
        this.loadTemplates();
    }

    loadTemplates() {
        this.isLoading = true;
        this.loadError = '';
        return getTemplateSummary({ offeringKey: this.selectedOffering })
            .then((rows) => {
                this.templates = (rows || []).map((t) => ({
                    ...t,
                    label: TEMPLATE_LABELS[t.templateType] || t.templateType,
                    isBuilt: (t.sectionCount || 0) > 0,
                    summary: (t.sectionCount || 0) > 0
                        ? `${t.sectionCount} sections · ${t.fieldCount || 0} fields`
                        : `${t.fieldCount || 0} fields · no sections modelled yet`,
                    cardClass: (t.sectionCount || 0) > 0 ? 'pg-card' : 'pg-card pg-card--unbuilt'
                }));
                // Open the page the home page asked for. Otherwise show the
                // picker, unless exactly one page is built.
                const built = this.templates.filter((t) => t.isBuilt);
                const asked = built.find((t) => t.templateType === this._requestedTemplate);
                if (asked) {
                    this._requestedTemplate = '';
                    this.selectedTemplate = asked.templateType;
                    return this.loadPage();
                }
                if (built.length === 1) {
                    this.selectedTemplate = built[0].templateType;
                    return this.loadPage();
                }
                return null;
            })
            .catch((err) => { this.loadError = this.messageFrom(err) || 'Pages could not be loaded.'; })
            .finally(() => { this.isLoading = false; });
    }

    handlePickTemplate(event) {
        const t = event.currentTarget.dataset.template;
        const chosen = this.templates.find((x) => x.templateType === t);
        if (!chosen || !chosen.isBuilt) return;
        this.selectedTemplate = t;
        this.activeKey = '';
        this.loadPage();
    }

    handleBackToPages() {
        this.selectedTemplate = '';
        this.sections = [];
        this.records = [];
        this.activeKey = '';
    }

    loadPage() {
        this.isLoading = true;
        this.loadError = '';
        return Promise.all([
            getEditorSections({ offeringKey: this.selectedOffering, templateType: this.selectedTemplate }),
            getAllContent({ offeringKey: this.selectedOffering, templateType: this.selectedTemplate })
        ])
            .then(([sections, records]) => {
                this.sections = (sections || []).map((s) => ({ ...s }));
                this.records = (records || []).map((r) => ({ ...r }));
                if (this.sections.length) this.activeKey = this.sections[0].sectionKey;
                this.dirtyKeys = [];
            })
            .catch((err) => { this.loadError = this.messageFrom(err) || 'Content could not be loaded.'; })
            .finally(() => { this.isLoading = false; });
    }

    // ─── rail ─────────────────────────────────────────────────────────────────

    get railSections() {
        return this.sections.map((s, i) => ({
            ...s,
            icon: SECTION_ICONS[s.layoutType] || 'utility:record',
            isDirty: this.dirtyKeys.indexOf(s.sectionKey) > -1,
            fieldCount: this.records.filter((r) => r.sectionKey === s.sectionKey).length,
            itemClass: 'sec'
                + (s.sectionKey === this.activeKey ? ' sec--active' : '')
                + (s.active === false ? ' sec--off' : ''),
            isFirst: i === 0,
            isLast: i === this.sections.length - 1,
            toggleLabel: s.active === false ? 'Show on page' : 'Hide from page'
        }));
    }

    get sectionCount() { return this.sections.length; }

    handleSelectSection(event) { this.activeKey = event.currentTarget.dataset.key; }

    handleToggleReorder() { this.reorderMode = !this.reorderMode; }

    get reorderLabel() { return this.reorderMode ? 'Done' : 'Rearrange'; }
    get reorderVariant() { return this.reorderMode ? 'brand' : 'neutral'; }
    get railHint() {
        return this.reorderMode
            ? 'Drag a section, or use the arrows. Order here is the order on the page.'
            : 'Order here is the order on the page.';
    }

    handleMoveUp(event) { this.move(event.currentTarget.dataset.key, -1); }
    handleMoveDown(event) { this.move(event.currentTarget.dataset.key, 1); }

    move(key, delta) {
        const from = this.sections.findIndex((s) => s.sectionKey === key);
        const to = from + delta;
        if (from < 0 || to < 0 || to >= this.sections.length) return;
        const next = [...this.sections];
        next.splice(to, 0, next.splice(from, 1)[0]);
        this.sections = next;
        this.persistOrder();
    }

    handleDragStart(event) { this._dragKey = event.currentTarget.dataset.key; }
    handleDragOver(event) { event.preventDefault(); }
    handleDrop(event) {
        event.preventDefault();
        const target = event.currentTarget.dataset.key;
        if (!this._dragKey || this._dragKey === target) return;
        const from = this.sections.findIndex((s) => s.sectionKey === this._dragKey);
        const to = this.sections.findIndex((s) => s.sectionKey === target);
        if (from < 0 || to < 0) return;
        const next = [...this.sections];
        next.splice(to, 0, next.splice(from, 1)[0]);
        this.sections = next;
        this._dragKey = '';
        this.persistOrder();
    }

    persistOrder() {
        this.isSaving = true;
        this.saveMessage = 'Saving order…';
        saveSectionOrder({ sectionIds: this.sections.map((s) => s.id) })
            .then(() => { this.saveMessage = 'Order saved'; })
            .catch((err) => { this.loadError = this.messageFrom(err) || 'The new order could not be saved.'; })
            .finally(() => { this.isSaving = false; });
    }

    handleToggleActive(event) {
        const key = event.currentTarget.dataset.key;
        const section = this.sections.find((s) => s.sectionKey === key);
        if (!section) return;
        const next = !(section.active !== false);
        this.isSaving = true;
        setSectionActive({ sectionId: section.id, active: next })
            .then(() => {
                this.sections = this.sections.map((s) =>
                    s.sectionKey === key ? { ...s, active: next } : s);
                this.saveMessage = next ? 'Section shown' : 'Section hidden';
            })
            .catch((err) => { this.loadError = this.messageFrom(err) || 'The section could not be updated.'; })
            .finally(() => { this.isSaving = false; });
    }

    // ─── field editor ─────────────────────────────────────────────────────────

    get activeSection() { return this.sections.find((s) => s.sectionKey === this.activeKey); }
    get activeSectionLabel() { const s = this.activeSection; return s ? (s.label || s.sectionKey) : ''; }
    get activeSectionHelp() { const s = this.activeSection; return s ? (s.helpText || '') : ''; }
    get activeAddress() {
        return `${this.selectedOffering}::${this.selectedTemplate}::${this.activeKey}`;
    }

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
                const value = r[COLUMN[type]] || '';
                const base = {
                    ...r,
                    value,
                    displayLabel: r.label || r.fieldKey,
                    hasHelp: !!r.helpText,
                    column: COLUMN[type],
                    isText: type === 'text',
                    isRich: type === 'rich',
                    isJson: type === 'json'
                };
                if (base.isJson) base.items = this.buildItems(r.id, value);
                return base;
            });
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
        this.writeValue(event.currentTarget.dataset.id, event.currentTarget.dataset.column, event.target.value);
    }

    handleRichChange(event) {
        this.writeValue(event.currentTarget.dataset.id, 'richValue', event.target.value);
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
        try {
            const parsed = JSON.parse(rec.jsonValue || '[]');
            return Array.isArray(parsed) ? parsed : null;
        } catch (e) { return null; }
    }

    commitJson(recordId, list) {
        this.writeValue(recordId, 'jsonValue', JSON.stringify(list));
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

    writeValue(recordId, column, value) {
        this.records = this.records.map((r) =>
            r.id === recordId ? { ...r, [column]: value } : r);
        const rec = this.records.find((r) => r.id === recordId);
        if (rec && this.dirtyKeys.indexOf(rec.sectionKey) === -1) {
            this.dirtyKeys = [...this.dirtyKeys, rec.sectionKey];
        }
        this.scheduleSave();
    }

    scheduleSave() {
        this.saveMessage = 'Editing…';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        clearTimeout(this._saveTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._saveTimer = setTimeout(() => { this.saveDraft(); }, 900);
    }

    saveDraft() {
        const dirty = this.records.filter((r) => this.dirtyKeys.indexOf(r.sectionKey) > -1);
        if (!dirty.length) return;
        this.isSaving = true;
        this.saveMessage = 'Saving…';
        saveContentRecords({ payloads: dirty })
            .then(() => { this.saveMessage = 'Saved'; this.dirtyKeys = []; })
            .catch((err) => {
                this.saveMessage = '';
                this.loadError = this.messageFrom(err) || 'Changes could not be saved.';
            })
            .finally(() => { this.isSaving = false; });
    }

    handleRefresh() {
        if (this.selectedTemplate) this.loadPage();
        else if (this.selectedOffering) this.loadTemplates();
    }

    handleDismissError() { this.loadError = ''; }

    // What the embedded page renders: the draft, not what is saved. Only
    // sections that are switched on, in current rail order.
    get previewSections() {
        return this.sections
            .filter((s) => s.active !== false)
            .map((s) => ({
                sectionKey: s.sectionKey,
                label: s.label,
                layoutType: s.layoutType,
                width: s.width
            }));
    }

    get previewContent() {
        const map = {};
        this.records.forEach((r) => {
            const type = r.fieldType || 'text';
            map[`${r.sectionKey}::${r.fieldKey}`] = r[COLUMN[type]] || '';
        });
        return map;
    }

    handleTogglePreview() { this.previewOn = !this.previewOn; }

    get previewToggleLabel() { return this.previewOn ? 'Hide preview' : 'Show preview'; }
    get previewToggleIcon() { return this.previewOn ? 'utility:preview' : 'utility:hide'; }

    // Only render the embedded page when there is something for it to draw.
    // Passing an empty list would put maStory into preview mode with no
    // sections, and it would sit there showing nothing.
    get showLivePreview() {
        return this.previewOn
            && this.selectedTemplate === 'story'
            && this.sections.length > 0
            && this.records.length > 0;
    }

    get livePageUrl() { return '/gtmstory/s/'; }
    get hasSections() { return !this.isLoading && this.sections.length > 0; }
    get showPagePicker() { return this.hasOffering && !this.hasTemplate && !this.isLoading; }
    get showEditor() { return this.hasOffering && this.hasTemplate && !this.isLoading; }
    get noSections() { return this.showEditor && this.sections.length === 0; }
}
