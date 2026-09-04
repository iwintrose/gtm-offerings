import { LightningElement, api, track } from 'lwc';
import getAllContent from '@salesforce/apex/MaPageContentController.getAllContent';
import getEditorSections from '@salesforce/apex/MaPageContentController.getEditorSections';
import saveContentRecords from '@salesforce/apex/MaPageContentController.saveContentRecords';
import saveSectionOrder from '@salesforce/apex/MaPageContentController.saveSectionOrder';
import setSectionActive from '@salesforce/apex/MaPageContentController.setSectionActive';

const TEMPLATE_TYPE_OPTIONS = [
    { label: 'Story', value: 'story' },
    { label: 'Configurator', value: 'configurator' },
    { label: 'Offerings Listing', value: 'offerings-listing' },
    { label: 'Industry Chooser', value: 'industry-chooser' }
];

// Which value column a field type resolves from. Mirrors
// MaPageContentController.resolveValue.
const COLUMN = { text: 'textValue', rich: 'richValue', json: 'jsonValue' };

export default class GtmContentManager extends LightningElement {
    @api offeringKey = 'migration-accelerator';

    @track templateType = 'story';
    @track sections = [];
    @track records = [];
    @track activeKey = '';
    @track isLoading = false;
    @track isSaving = false;
    @track loadError = '';
    @track saveMessage = '';
    @track reorderMode = false;
    @track dirtyKeys = [];

    templateTypeOptions = TEMPLATE_TYPE_OPTIONS;
    _dragKey = '';
    _saveTimer;

    // ─── lifecycle ────────────────────────────────────────────────────────────

    connectedCallback() {
        this.load();
    }

    load() {
        this.isLoading = true;
        this.loadError = '';
        Promise.all([
            getEditorSections({ offeringKey: this.offeringKey, templateType: this.templateType }),
            getAllContent({ offeringKey: this.offeringKey, templateType: this.templateType })
        ])
            .then(([sections, records]) => {
                this.sections = (sections || []).map((s) => ({ ...s }));
                this.records = (records || []).map((r) => ({ ...r }));
                if (!this.activeKey && this.sections.length) {
                    this.activeKey = this.sections[0].sectionKey;
                }
                this.dirtyKeys = [];
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'Content could not be loaded.';
            })
            .finally(() => { this.isLoading = false; });
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    // ─── rail ─────────────────────────────────────────────────────────────────

    get railSections() {
        return this.sections.map((s, i) => ({
            ...s,
            isActive: s.sectionKey === this.activeKey,
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

    handleSelectSection(event) {
        this.activeKey = event.currentTarget.dataset.key;
    }

    handleToggleReorder() {
        this.reorderMode = !this.reorderMode;
    }

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
            .catch((err) => {
                this.saveMessage = '';
                this.loadError = this.messageFrom(err) || 'The new order could not be saved.';
            })
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
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'The section could not be updated.';
            })
            .finally(() => { this.isSaving = false; });
    }

    // ─── field editor ─────────────────────────────────────────────────────────

    get activeSection() {
        return this.sections.find((s) => s.sectionKey === this.activeKey);
    }

    get activeSectionLabel() {
        const s = this.activeSection;
        return s ? (s.label || s.sectionKey) : '';
    }

    get activeSectionHelp() {
        const s = this.activeSection;
        return s ? (s.helpText || '') : '';
    }

    get activeAddress() {
        return `${this.offeringKey}::${this.templateType}::${this.activeKey}`;
    }

    get activeFields() {
        return this.records
            .filter((r) => r.sectionKey === this.activeKey)
            .map((r) => {
                const type = r.fieldType || 'text';
                const value = r[COLUMN[type]] || '';
                return {
                    ...r,
                    value,
                    isJson: type === 'json',
                    isLong: type === 'rich' || value.length > 80,
                    isShort: !(type === 'json') && !(type === 'rich' || value.length > 80),
                    column: COLUMN[type],
                    address: `${this.activeKey}::${r.fieldKey}`
                };
            });
    }

    get fieldCountLabel() {
        const n = this.activeFields.length;
        return `${n} field${n === 1 ? '' : 's'}`;
    }

    handleFieldChange(event) {
        const id = event.currentTarget.dataset.id;
        const column = event.currentTarget.dataset.column;
        const value = event.target.value;
        this.records = this.records.map((r) =>
            r.id === id ? { ...r, [column]: value } : r);
        if (this.dirtyKeys.indexOf(this.activeKey) === -1) {
            this.dirtyKeys = [...this.dirtyKeys, this.activeKey];
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
            .then(() => {
                this.saveMessage = 'Draft saved';
                this.dirtyKeys = [];
            })
            .catch((err) => {
                this.saveMessage = '';
                this.loadError = this.messageFrom(err) || 'Changes could not be saved.';
            })
            .finally(() => { this.isSaving = false; });
    }

    handleTemplateChange(event) {
        this.templateType = event.detail.value;
        this.activeKey = '';
        this.load();
    }

    handleRefresh() { this.load(); }

    handleDismissError() { this.loadError = ''; }

    // ─── preview ──────────────────────────────────────────────────────────────
    // Rendered by the real maStory component, driven from the draft. Nothing
    // about the page is reimplemented here, so the preview cannot drift from
    // what the site actually serves.

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

    get isStoryTemplate() { return this.templateType === 'story'; }

    get hasSections() { return !this.isLoading && this.sections.length > 0; }

    get isEmpty() { return !this.isLoading && this.sections.length === 0; }
}
