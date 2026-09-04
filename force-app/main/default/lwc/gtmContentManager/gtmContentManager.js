import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getOfferings from '@salesforce/apex/MaPageContentController.getOfferings';
import getTemplateSummary from '@salesforce/apex/MaPageContentController.getTemplateSummary';
import getEditorSections from '@salesforce/apex/MaPageSectionController.getEditorSections';
import getAllContent from '@salesforce/apex/MaPageContentController.getAllContent';
import saveDrafts from '@salesforce/apex/MaPageContentController.saveDrafts';
import publishPage from '@salesforce/apex/MaPageContentController.publishPage';
import discardDrafts from '@salesforce/apex/MaPageContentController.discardDrafts';
import saveSectionOrder from '@salesforce/apex/MaPageSectionController.saveSectionOrder';
import setSectionActive from '@salesforce/apex/MaPageSectionController.setSectionActive';
import createSection from '@salesforce/apex/MaPageSectionController.createSection';
import deleteSection from '@salesforce/apex/MaPageSectionController.deleteSection';
import restoreSection from '@salesforce/apex/MaPageSectionController.restoreSection';
// One definition of what a layout is made of, shared with the renderer.
import { addableLayouts, fieldsFor } from 'c/gtmPageLayouts';

// Which value column each field type resolves from. Mirrors
// MaPageContentController.resolveValue.
const COLUMN = { text: 'textValue', rich: 'richValue', json: 'jsonValue' };

// The preview renders the real page component at a fixed desktop width and
// scales the whole thing down to whatever the pane can give it. Scaling rather
// than narrowing is deliberate: it keeps the proportions of the published page
// instead of showing a tablet breakpoint and calling it a preview.
const PREVIEW_WIDTH = 1280;

// A one-line input clips anything past its width with no scrollbar and no
// hint that there is more, so a value this long gets a box it fits in.
const LONG_TEXT_CHARS = 48;

const TEMPLATE_LABELS = {
    story: 'Story',
    configurator: 'Configurator',
    'offerings-listing': 'Offerings Listing',
    'industry-chooser': 'Industry Chooser'
};

// Every name here must exist in the SLDS utility set. An invalid one renders
// as blank space with no console error, which is how utility:brand_engagement
// — a name that does not exist — sat on the hero row unnoticed.
const SECTION_ICONS = {
    'page-header': 'utility:page',
    'page-footer': 'utility:anchor',
    hero: 'utility:display_text',
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
    @track exitOpen = false;
    @track dirtyKeys = [];

    _dragKey = '';
    _saveTimer;
    _fitObserver;
    _syncTimer;
    _intentTimer;
    _suppressScrollSync = false;
    _scrollQueued = false;
    _previewDriven = false;
    @track _scalePct = 100;

    // add / delete section
    @track addOpen = false;
    @track addLayout = '';
    @track addLabel = '';
    @track deleteTarget = null;

    // column splitter
    @track fieldsWidth = 0;

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
                // renderLong is decided here and never recomputed while typing.
                // Deriving it from the live value would swap an input for a
                // textarea the moment you crossed the threshold, taking focus
                // out of the box mid-word.
                this.records = (records || []).map((r) => {
                    const loaded = r.isDraft
                        ? (r.draftValue || '')
                        : (r[COLUMN[r.fieldType || 'text']] || '');
                    return { ...r, renderLong: loaded.length > LONG_TEXT_CHARS };
                });
                if (this.sections.length) this.activeKey = this.sections[0].sectionKey;
                this.dirtyKeys = [];
            })
            .catch((err) => { this.loadError = this.messageFrom(err) || 'Content could not be loaded.'; })
            .finally(() => { this.isLoading = false; });
    }

    // ─── rail ─────────────────────────────────────────────────────────────────

    get railSections() {
        return this.sections.map((s, i) => {
            // What is pending on this section, said in the words an editor
            // would use. A structural change is a draft like any other, so it
            // has to be visible before Publish, not only afterwards.
            let pending = '';
            if (s.isDeleted) pending = 'Delete on publish';
            else if (s.isNew) pending = 'New — not published';
            else if (s.isHidden) pending = s.active === false ? 'Hide on publish' : 'Show on publish';
            else if (s.isMoved) pending = 'Moved';

            return {
                ...s,
                icon: SECTION_ICONS[s.layoutType] || 'utility:record',
                isDirty: this.dirtyKeys.indexOf(s.sectionKey) > -1,
                fieldCount: this.records.filter((r) => r.sectionKey === s.sectionKey).length,
                itemClass: 'sec'
                    + (s.sectionKey === this.activeKey ? ' sec--active' : '')
                    + (s.active === false ? ' sec--off' : '')
                    + (s.isDeleted ? ' sec--doomed' : '')
                    + (s.isDraft ? ' sec--pending' : ''),
                isFirst: i === 0,
                isLast: i === this.sections.length - 1,
                toggleLabel: s.active === false ? 'Show on page' : 'Hide from page',
                pendingLabel: pending,
                hasPending: !!pending,
                canDelete: !s.isDeleted,
                canRestore: s.isDeleted === true
            };
        });
    }

    get sectionCount() { return this.sections.length; }

    // Picking a section in the rail moves the preview to it: c/gtmPagePreview
    // scrolls its canvas when activeKey changes, so setting it is the whole
    // binding. Without it the two halves of the editor describe the same page
    // but never agree on where you are in it.
    handleSelectSection(event) {
        this.activeKey = event.currentTarget.dataset.key;
    }

    // The reverse direction: the reader scrolled the preview, so follow.
    handlePreviewSectionChange(event) {
        const key = event.detail.sectionKey;
        if (!key || key === this.activeKey) return;
        this.activeKey = key;
        this.scrollRailTo(key);
    }

    // Keeps the highlighted section visible when the preview drives the
    // selection; otherwise the rail highlights a row that is scrolled off.
    scrollRailTo(sectionKey) {
        const row = this.template.querySelector(`.sec[data-key="${sectionKey}"]`);
        const body = this.template.querySelector('.gcm-rail-body');
        if (!row || !body) return;
        const rowRect = row.getBoundingClientRect();
        const bodyRect = body.getBoundingClientRect();
        if (rowRect.top < bodyRect.top) {
            body.scrollTop += rowRect.top - bodyRect.top - 4;
        } else if (rowRect.bottom > bodyRect.bottom) {
            body.scrollTop += rowRect.bottom - bodyRect.bottom + 4;
        }
    }

    disconnectedCallback() {
        clearTimeout(this._saveTimer);
    }


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

    // Edits land on draftValue, never on the published column, so the public
    // page is unaffected until Publish runs.
    writeValue(recordId, value) {
        this.records = this.records.map((r) =>
            r.id === recordId ? { ...r, draftValue: value, isDraft: true, status: 'Draft' } : r);
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
        const edits = this.records
            .filter((r) => r.isDraft)
            .map((r) => ({ id: r.id, value: r.draftValue || '' }));
        if (!edits.length) return;
        this.isSaving = true;
        this.saveMessage = 'Saving…';
        saveDrafts({ edits })
            .then(() => { this.saveMessage = 'Draft saved'; this.dirtyKeys = []; })
            .catch((err) => {
                this.saveMessage = '';
                this.loadError = this.messageFrom(err) || 'The draft could not be saved.';
            })
            .finally(() => { this.isSaving = false; });
    }

    // ─── publish ──────────────────────────────────────────────────────────────

    get draftCount() { return this.records.filter((r) => r.isDraft).length; }

    // Reordering, hiding and deleting are unpublished changes too. Counting
    // only field edits meant a page could be structurally rewritten and still
    // report nothing to publish.
    get structuralCount() { return this.sections.filter((s) => s.isDraft).length; }
    get totalChanges() { return this.draftCount + this.structuralCount; }
    get hasDrafts() { return this.totalChanges > 0; }

    get draftSummary() {
        const parts = [];
        const f = this.draftCount;
        const st = this.structuralCount;
        if (f) parts.push(f === 1 ? '1 field edited' : `${f} fields edited`);
        if (st) parts.push(st === 1 ? '1 section changed' : `${st} sections changed`);
        return parts.join(' · ') || 'No unpublished changes';
    }

    // The save state is a state, not a log line: a dot and a word that say
    // whether what you typed is safely on the server.
    get saveStateLabel() {
        if (this.isSaving) return 'Saving…';
        if (this.saveMessage) return this.saveMessage;
        return this.hasDrafts ? 'Draft saved' : 'All changes saved';
    }

    get saveStateClass() {
        if (this.isSaving) return 'gcm-savestate gcm-savestate--busy';
        return this.hasDrafts ? 'gcm-savestate gcm-savestate--draft' : 'gcm-savestate';
    }

    // Leaving with a draft is a normal outcome, not an escape hatch: the point
    // of drafts is that you can stop halfway and the live page is unaffected.
    handleSaveAndExit() {
        this.saveDraft();
        this.selectedTemplate = '';
        this.sections = [];
        this.records = [];
        this.activeKey = '';
        this.saveMessage = 'Draft kept — the live page is unchanged';
    }

    handleOpenExit() { this.exitOpen = true; }
    handleCloseExit() { this.exitOpen = false; }

    handlePublish() {
        this.isSaving = true;
        this.saveMessage = 'Publishing…';
        this.exitOpen = false;
        publishPage({ offeringKey: this.selectedOffering, templateType: this.selectedTemplate })
            .then((count) => {
                this.saveMessage = count === 1 ? '1 field published' : `${count} fields published`;
                return this.loadPage();
            })
            .catch((err) => {
                this.saveMessage = '';
                this.loadError = this.messageFrom(err) || 'Publish failed.';
            })
            .finally(() => { this.isSaving = false; });
    }

    handleDiscard() {
        this.isSaving = true;
        this.saveMessage = 'Discarding…';
        this.exitOpen = false;
        discardDrafts({ offeringKey: this.selectedOffering, templateType: this.selectedTemplate })
            .then(() => {
                this.saveMessage = 'Changes discarded';
                return this.loadPage();
            })
            .catch((err) => {
                this.saveMessage = '';
                this.loadError = this.messageFrom(err) || 'Changes could not be discarded.';
            })
            .finally(() => { this.isSaving = false; });
    }

    handleRefresh() {
        if (this.selectedTemplate) this.loadPage();
        else if (this.selectedOffering) this.loadTemplates();
    }

    handleDismissError() { this.loadError = ''; }

    // ─── add / delete sections ────────────────────────────────────────────────

    get layoutOptions() {
        return addableLayouts().map((l) => ({
            ...l,
            icon: SECTION_ICONS[l.value] || 'utility:record',
            fieldLabel: `${l.fieldCount} field${l.fieldCount === 1 ? '' : 's'}`,
            cardClass: l.value === this.addLayout ? 'card card--on' : 'card'
        }));
    }

    get addLayoutHint() {
        const chosen = this.layoutOptions.find((l) => l.value === this.addLayout);
        if (!chosen) return 'Pick a layout. It decides what the section can hold.';
        const n = chosen.fieldCount;
        return `${chosen.hint} Creates ${n} field${n === 1 ? '' : 's'}.`;
    }

    // The section key is derived from the label rather than asked for
    // separately: it is an address, not a name, and one fewer box to fill in
    // is one fewer way to create a section whose key says something different
    // from its heading.
    get addKeyPreview() {
        const key = this.slugify(this.addLabel);
        return key ? `${this.selectedOffering}::${this.selectedTemplate}::${key}` : '';
    }

    // The template binds the disabled attribute, so the negation lives here
    // rather than in markup, which cannot express it.
    get canAddSectionDisabled() {
        return !this.addLayout || !this.slugify(this.addLabel) || this.isSaving;
    }

    slugify(raw) {
        return String(raw || '')
            .trim()
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-+|-+$/g, '')
            .slice(0, 80);
    }

    handleOpenAdd() {
        this.addOpen = true;
        this.addLayout = '';
        this.addLabel = '';
    }

    handleCloseAdd() { this.addOpen = false; }
    handleAddLayoutChange(event) {
        this.addLayout = event.currentTarget.dataset.layout;
    }
    handleAddLabelChange(event) { this.addLabel = event.target.value; }

    handleCreateSection() {
        const key = this.slugify(this.addLabel);
        if (!this.addLayout || !key) return;
        this.isSaving = true;
        this.saveMessage = 'Adding section…';
        this.addOpen = false;
        createSection({
            offeringKey: this.selectedOffering,
            templateType: this.selectedTemplate,
            sectionKey: key,
            label: this.addLabel.trim(),
            layoutType: this.addLayout,
            width: 'standard',
            fields: fieldsFor(this.addLayout)
        })
            .then(() => {
                this.saveMessage = 'Section added';
                // Land on the new section: adding one and then having to hunt
                // for it in the rail is the kind of thing that makes an editor
                // feel like a database form.
                this.activeKey = key;
                return this.loadPage();
            })
            .then(() => {
                this.activeKey = key;
                // A section appended to a rail that already scrolls is created
                // below the fold; bring it into view rather than making the
                // editor hunt for what it just added.
                this.scrollRailTo(key);
            })
            .catch((err) => {
                this.saveMessage = '';
                this.loadError = this.messageFrom(err) || 'The section could not be added.';
            })
            .finally(() => { this.isSaving = false; });
    }

    handleRestore(event) {
        const key = event.currentTarget.dataset.key;
        const section = this.sections.find((s) => s.sectionKey === key);
        if (!section) return;
        this.isSaving = true;
        restoreSection({ sectionId: section.id })
            .then(() => { this.saveMessage = 'Delete undone'; return this.loadPage(); })
            .catch((err) => { this.loadError = this.messageFrom(err) || 'The section could not be restored.'; })
            .finally(() => { this.isSaving = false; });
    }

    handleAskDelete(event) {
        const key = event.currentTarget.dataset.key;
        const section = this.sections.find((s) => s.sectionKey === key);
        if (!section) return;
        this.deleteTarget = {
            id: section.id,
            sectionKey: section.sectionKey,
            label: section.label || section.sectionKey,
            isNew: section.isNew === true,
            fieldCount: this.records.filter((r) => r.sectionKey === section.sectionKey).length
        };
    }

    get deleteOpen() { return !!this.deleteTarget; }

    get deleteSummary() {
        if (!this.deleteTarget) return '';
        const n = this.deleteTarget.fieldCount;
        return `"${this.deleteTarget.label}" and its ${n} field${n === 1 ? '' : 's'}`;
    }

    // A section that was never published is removed outright; one that is on
    // the live page is only marked, and the dialog has to say which, or
    // "delete" looks like it did nothing.
    get deleteIsImmediate() { return !!(this.deleteTarget && this.deleteTarget.isNew); }
    get deleteConfirmLabel() {
        return this.deleteIsImmediate ? 'Delete section' : 'Mark for deletion';
    }

    handleCancelDelete() { this.deleteTarget = null; }

    handleConfirmDelete() {
        const target = this.deleteTarget;
        if (!target) return;
        this.deleteTarget = null;
        this.isSaving = true;
        this.saveMessage = 'Marking for deletion…';
        deleteSection({ sectionId: target.id })
            .then(() => {
                this.saveMessage = target.isNew
                    ? 'Section removed'
                    : 'Marked for deletion — publish to remove it';
                return this.loadPage();
            })
            .catch((err) => {
                this.saveMessage = '';
                this.loadError = this.messageFrom(err) || 'The section could not be deleted.';
            })
            .finally(() => { this.isSaving = false; });
    }

    // ─── column splitter ──────────────────────────────────────────────────────

    handleSplitDown(event) {
        event.preventDefault();
        const cols = this.template.querySelector('.gcm-cols');
        const fields = this.template.querySelector('.gcm-fields');
        if (!cols || !fields) return;
        const x0 = event.clientX;
        const w0 = fields.getBoundingClientRect().width;
        const move = (ev) => {
            // Bounded so neither column can be dragged out of usefulness: the
            // preview needs room to be a preview, the fields to be editable.
            const next = Math.max(280, Math.min(760, w0 + (ev.clientX - x0)));
            this.fieldsWidth = Math.round(next);
            cols.style.setProperty('--gcm-fieldw', `${this.fieldsWidth}px`);
        };
        const up = () => {
            window.removeEventListener('pointermove', move);
            window.removeEventListener('pointerup', up);
        };
        window.addEventListener('pointermove', move);
        window.addEventListener('pointerup', up);
    }

    // ─── field editor bridge ──────────────────────────────────────────────────
    // c/gtmFieldEditor owns how a field is presented and what fields exist.
    // The working copy of their values stays here, because it is what the
    // preview renders and what autosave writes.

    get activeSection() { return this.sections.find((s) => s.sectionKey === this.activeKey); }
    get activeSectionLabel() { const s = this.activeSection; return s ? (s.label || s.sectionKey) : ''; }
    get activeSectionHelp() { const s = this.activeSection; return s ? (s.helpText || '') : ''; }
    get activeLayoutType() { const s = this.activeSection; return s ? s.layoutType : ''; }
    get activeAddress() {
        return `${this.selectedOffering}::${this.selectedTemplate}::${this.activeKey}`;
    }

    handleFieldValueChange(event) {
        this.writeValue(event.detail.recordId, event.detail.value);
    }

    // Adding, removing or reordering a field changes what the page is made of,
    // so reload rather than trying to patch the copy held here.
    handleFieldsChanged(event) {
        if (event.detail.message) this.saveMessage = event.detail.message;
        this.loadPage();
    }

    handleChildError(event) {
        this.loadError = event.detail.message || 'Something went wrong.';
    }

    // ─── preview data ─────────────────────────────────────────────────────────
    // The preview renders from this component's working copy, so every
    // keystroke redraws it: the draft is visible here before anyone else sees
    // it. It is the published renderer, not a second implementation.

    get previewSections() {
        return this.sections
            .filter((s) => s.active !== false && !s.isDeleted)
            .map((s) => ({
                sectionKey: s.sectionKey,
                layoutType: s.layoutType,
                width: s.width || 'standard',
                label: s.label || ''
            }));
    }

    // Types and labels for every field, so the preview can draw fields no
    // layout declares. The flat content map carries values only, which is
    // enough to resolve a known field and not enough to draw an unknown one.
    get previewFieldMeta() {
        return this.records
            .filter((r) => r.active !== false && !r.pendingDelete)
            .map((r) => ({
                sectionKey: r.sectionKey,
                fieldKey: r.fieldKey,
                fieldType: r.fieldType || 'text',
                label: r.label || ''
            }));
    }

    get previewContent() {
        const map = {};
        this.records.forEach((r) => {
            if (r.active === false) return;
            const value = r.isDraft ? (r.draftValue || '') : (r[COLUMN[r.fieldType || 'text']] || '');
            if (!value) return;
            map[`${r.sectionKey}::${r.fieldKey}`] = value;
        });
        return map;
    }

    get livePageUrl() {
        const o = this.offerings.find((x) => x.offeringKey === this.selectedOffering);
        return (o && o.publicUrl) || '';
    }

    get hasLivePage() { return !!this.livePageUrl; }
    get hasSections() { return !this.isLoading && this.sections.length > 0; }
    get showPagePicker() { return this.hasOffering && !this.hasTemplate && !this.isLoading; }
    get showEditor() { return this.hasOffering && this.hasTemplate && !this.isLoading; }
    get noSections() { return this.showEditor && this.sections.length === 0; }
}
