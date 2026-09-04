import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getOfferings from '@salesforce/apex/MaPageContentController.getOfferings';
import getTemplateSummary from '@salesforce/apex/MaPageContentController.getTemplateSummary';
import getEditorSections from '@salesforce/apex/MaPageContentController.getEditorSections';
import getAllContent from '@salesforce/apex/MaPageContentController.getAllContent';
import saveDrafts from '@salesforce/apex/MaPageContentController.saveDrafts';
import publishPage from '@salesforce/apex/MaPageContentController.publishPage';
import discardDrafts from '@salesforce/apex/MaPageContentController.discardDrafts';
import saveSectionOrder from '@salesforce/apex/MaPageContentController.saveSectionOrder';
import setSectionActive from '@salesforce/apex/MaPageContentController.setSectionActive';
import createSection from '@salesforce/apex/MaPageContentController.createSection';
import deleteSection from '@salesforce/apex/MaPageContentController.deleteSection';
import createField from '@salesforce/apex/MaPageContentController.createField';
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

    handleSelectSection(event) {
        this.activeKey = event.currentTarget.dataset.key;
        // Picking a section in the rail moves the preview to it. Without this
        // the two halves of the editor describe the same page but never agree
        // on where you are in it.
        this.scrollPreviewTo(this.activeKey);
    }

    // ─── rail ↔ preview sync ──────────────────────────────────────────────────

    scrollPreviewTo(sectionKey) {
        const pane = this.template.querySelector('.gcm-preview-body');
        const story = this.template.querySelector('c-ma-story');
        if (!pane || !story || typeof story.getSectionRects !== 'function') return;
        const paneTop = pane.getBoundingClientRect().top;
        const hit = story.getSectionRects().find((r) => r.sectionKey === sectionKey);
        // Page chrome renders around the page rather than in the sequence, so
        // it has no rect of its own; the top of the page is where it lives.
        const target = hit ? pane.scrollTop + (hit.top - paneTop) - 8 : 0;
        // A scroll this code started is not the reader scrolling. Clearing the
        // intent flag as well as suppressing matters for the last section,
        // where the pane cannot scroll far enough to honour the request and
        // settles at its maximum — which the scroll-spy would otherwise read
        // as "you are looking at the section above".
        this._previewDriven = false;
        this._suppressScrollSync = true;
        pane.scrollTo({ top: Math.max(0, target), behavior: 'smooth' });
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        clearTimeout(this._syncTimer);
        // Released once the smooth scroll has settled, so the scroll it just
        // caused does not bounce the rail selection back.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._syncTimer = setTimeout(() => { this._suppressScrollSync = false; }, 500);
    }

    // Only a scroll the reader caused moves the rail. Typing re-renders the
    // preview, which reflows it, which fires scroll — and syncing on that
    // reassigned the active section mid-keystroke and took the cursor with it.
    // A wheel, a drag or a key on the preview is the reader; a reflow is not.
    handlePreviewIntent() {
        this._previewDriven = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        clearTimeout(this._intentTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._intentTimer = setTimeout(() => { this._previewDriven = false; }, 1200);
    }

    handlePreviewScroll() {
        if (!this._previewDriven) return;
        if (this._suppressScrollSync || this._scrollQueued) return;
        this._scrollQueued = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            this._scrollQueued = false;
            this.syncRailToPreview();
        });
    }

    syncRailToPreview() {
        const pane = this.template.querySelector('.gcm-preview-body');
        const story = this.template.querySelector('c-ma-story');
        if (!pane || !story || typeof story.getSectionRects !== 'function') return;
        const rects = story.getSectionRects();
        if (!rects.length) return;

        // The last section can never cover the top of the pane: the pane runs
        // out of scroll while the section before it is still up there. Reading
        // the top alone therefore made the final section unselectable and
        // snapped the rail back to the one above it. At the bottom of the
        // scroll, the last section is what you are looking at.
        const atBottom = pane.scrollTop + pane.clientHeight >= pane.scrollHeight - 4;
        let current = atBottom ? rects[rects.length - 1].sectionKey : '';

        if (!current) {
            const paneTop = pane.getBoundingClientRect().top;
            // Otherwise: the last section whose top has passed the pane's top.
            rects.forEach((r) => {
                if (r.top - paneTop <= 24) current = r.sectionKey;
            });
        }
        if (current && current !== this.activeKey) {
            this.activeKey = current;
            this.scrollRailTo(current);
        }
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
        this.writeValue(event.currentTarget.dataset.id, event.target.value);
    }

    handleRichChange(event) {
        this.writeValue(event.currentTarget.dataset.id, event.target.value);
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
        this.writeValue(recordId, JSON.stringify(list));
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
    get hasDrafts() { return this.draftCount > 0; }
    get draftSummary() {
        const n = this.draftCount;
        return n === 1 ? '1 unpublished change' : `${n} unpublished changes`;
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
        return addableLayouts();
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
    handleAddLayoutChange(event) { this.addLayout = event.detail.value; }
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
                this.scrollPreviewTo(key);
            })
            .catch((err) => {
                this.saveMessage = '';
                this.loadError = this.messageFrom(err) || 'The section could not be added.';
            })
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
            fieldCount: this.records.filter((r) => r.sectionKey === section.sectionKey).length
        };
    }

    get deleteOpen() { return !!this.deleteTarget; }

    get deleteSummary() {
        if (!this.deleteTarget) return '';
        const n = this.deleteTarget.fieldCount;
        return `"${this.deleteTarget.label}" and its ${n} field${n === 1 ? '' : 's'}`;
    }

    handleCancelDelete() { this.deleteTarget = null; }

    handleConfirmDelete() {
        const target = this.deleteTarget;
        if (!target) return;
        this.deleteTarget = null;
        this.isSaving = true;
        this.saveMessage = 'Deleting…';
        deleteSection({ sectionId: target.id })
            .then((removed) => {
                this.saveMessage = removed === 1
                    ? 'Section and 1 field deleted'
                    : `Section and ${removed} fields deleted`;
                if (this.activeKey === target.sectionKey) this.activeKey = '';
                return this.loadPage();
            })
            .catch((err) => {
                this.saveMessage = '';
                this.loadError = this.messageFrom(err) || 'The section could not be deleted.';
            })
            .finally(() => { this.isSaving = false; });
    }

    // ─── missing fields ───────────────────────────────────────────────────────
    // A field the layout declares but the section has no record for. The page
    // falls back to a built-in default for these, which looks like content
    // nobody can edit; offering them here is how that gets fixed.

    get missingFields() {
        const section = this.activeSection;
        if (!section) return [];
        const present = new Set(
            this.records
                .filter((r) => r.sectionKey === this.activeKey)
                .map((r) => r.fieldKey)
        );
        return fieldsFor(section.layoutType)
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
        this.isSaving = true;
        this.saveMessage = 'Adding field…';
        createField({
            offeringKey: this.selectedOffering,
            templateType: this.selectedTemplate,
            sectionKey: this.activeKey,
            fieldKey: spec.fieldKey,
            fieldType: spec.fieldType,
            label: spec.label
        })
            .then(() => { this.saveMessage = 'Field added'; return this.loadPage(); })
            .catch((err) => {
                this.saveMessage = '';
                this.loadError = this.messageFrom(err) || 'The field could not be added.';
            })
            .finally(() => { this.isSaving = false; });
    }

    // ─── live preview ─────────────────────────────────────────────────────────
    // The preview is the real <c-ma-story> renderer fed from this component's
    // working copy, not a second implementation of the page. It is driven by
    // getters, so every keystroke that lands in `records` redraws it — the
    // draft is visible here before it is visible to anyone else.

    get previewSections() {
        return this.sections
            .filter((s) => s.active !== false)
            .map((s) => ({
                sectionKey: s.sectionKey,
                layoutType: s.layoutType,
                width: s.width || 'standard',
                label: s.label || ''
            }));
    }

    /**
     * The flat `sectionKey::fieldKey` map the renderer resolves against, built
     * from the working copy: draft value where one exists, published value
     * otherwise. Same shape MaPageContentReader.getPageLayout returns, so the
     * preview and the live page agree by construction.
     */
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

    get previewScaleLabel() { return `${this._scalePct}% of 1280px`; }

    fitPreview() {
        const pane = this.template.querySelector('.gcm-preview-body');
        const stage = this.template.querySelector('.gcm-stage');
        const shell = this.template.querySelector('.gcm-stage-shell');
        if (!pane || !stage || !shell) return;
        // clientWidth includes the pane's padding, so read the real value
        // rather than assuming it: the padding tightens at narrow widths, and
        // a stale constant here would push the scaled page under the scrollbar.
        const cs = window.getComputedStyle(pane);
        const pad = (parseFloat(cs.paddingLeft) || 0) + (parseFloat(cs.paddingRight) || 0);
        const available = pane.clientWidth - pad;
        if (available <= 0) return;
        const scale = Math.min(1, available / PREVIEW_WIDTH);
        stage.style.transform = `scale(${scale})`;
        // transform does not affect layout, so the shell has to be told what
        // the scaled page now occupies or the pane scrolls to the wrong height.
        shell.style.width = `${Math.round(PREVIEW_WIDTH * scale)}px`;
        shell.style.height = `${Math.round(stage.scrollHeight * scale)}px`;
        const pct = Math.round(scale * 100);
        if (pct !== this._scalePct) this._scalePct = pct;
    }

    renderedCallback() {
        this.fitPreview();
        if (this._fitObserver || typeof ResizeObserver === 'undefined') return;
        const pane = this.template.querySelector('.gcm-preview-body');
        const stage = this.template.querySelector('.gcm-stage');
        if (!pane || !stage) return;
        // Two things change the fit: the pane resizing with the window, and the
        // page itself growing or shrinking as content is edited.
        this._fitObserver = new ResizeObserver(() => { this.fitPreview(); });
        this._fitObserver.observe(pane);
        this._fitObserver.observe(stage);
    }

    disconnectedCallback() {
        if (this._fitObserver) {
            this._fitObserver.disconnect();
            this._fitObserver = undefined;
        }
        clearTimeout(this._saveTimer);
        clearTimeout(this._syncTimer);
        clearTimeout(this._intentTimer);
    }

    // Resolved by Apex from the offering's configured site path, not built
    // here: a relative link would resolve against the Lightning domain, where
    // Experience Cloud sites do not exist.
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
