import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getOfferings from '@salesforce/apex/GtmPageContentController.getOfferings';
import getTemplateSummary from '@salesforce/apex/GtmPageContentController.getTemplateSummary';
import getEditorSections from '@salesforce/apex/GtmPageSectionController.getEditorSections';
import getAllContent from '@salesforce/apex/GtmPageContentController.getAllContent';
import saveDrafts from '@salesforce/apex/GtmPageContentController.saveDrafts';
import publishPage from '@salesforce/apex/GtmPageContentController.publishPage';
import discardDrafts from '@salesforce/apex/GtmPageContentController.discardDrafts';
import savePresentation from '@salesforce/apex/GtmPageContentController.savePresentation';
import saveSectionOrder from '@salesforce/apex/GtmPageSectionController.saveSectionOrder';
import setSectionActive from '@salesforce/apex/GtmPageSectionController.setSectionActive';
import createSection from '@salesforce/apex/GtmPageSectionController.createSection';
import createIndustry from '@salesforce/apex/GtmPageContentController.createIndustry';
import deleteSection from '@salesforce/apex/GtmPageSectionController.deleteSection';
import restoreSection from '@salesforce/apex/GtmPageSectionController.restoreSection';
// One definition of what a layout is made of, shared with the renderer.
import { addableLayouts, fieldsFor, templatesFor, TEMPLATE_LABELS, LAYOUT_LABELS, FRAMEWORK_KEY } from 'c/gtmPageLayouts';

// Which value column each field type resolves from. Mirrors
// GtmPageContentController.resolveValue.
const COLUMN = { text: 'textValue', rich: 'richValue', json: 'jsonValue', enum: 'textValue' };

// The preview renders the real page component at a fixed desktop width and
// scales the whole thing down to whatever the pane can give it. Scaling rather
// than narrowing is deliberate: it keeps the proportions of the published page
// instead of showing a tablet breakpoint and calling it a preview.
const PREVIEW_WIDTH = 1280;

// A one-line input clips anything past its width with no scrollbar and no
// hint that there is more, so a value this long gets a box it fits in.
const LONG_TEXT_CHARS = 48;

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
    closing: 'utility:success',
    'offering-tile': 'utility:apps',
    'offering-defaults': 'utility:settings',
    'industry-tile': 'utility:office',
    'industry-profile': 'utility:knowledge_base',
    assistant: 'utility:chat',
    'chapter-cards': 'utility:tile_card_list',
    'chapter-lede': 'utility:display_text',
    'chapter-proof': 'utility:metrics',
    'chapter-phases': 'utility:steps',
    'chapter-close': 'utility:success'
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

    // True from the first paint, not from the first fetch. It used to start
    // false and only flip once connectedCallback got as far as calling Apex,
    // so the very first frame drew neither the spinner nor the editor -- which
    // is the blank panel you see before the editor appears.
    @track isLoading = true;
    @track isSaving = false;
    @track loadError = '';
    @track saveMessage = '';
    // One-time orientation nudge for a just-created offering — see
    // capturePageRef() for how it's set and why it doesn't reappear on a
    // later, unrelated navigation back to the same offering.
    @track isNewOffering = false;
    @track reorderMode = false;
    @track exitOpen = false;
    @track dirtyKeys = [];

    // Whether the customizer-settings surface (the offering-defaults section,
    // presented apart from the ordinary rail) is showing instead of the
    // normal content editor. See settingsSection/contentSections below.
    @track settingsOpen = false;

    _dragKey = '';
    _saveTimer;
    _presentationTimer;
    _fitObserver;
    _syncTimer;
    _intentTimer;
    _suppressScrollSync = false;
    _scrollQueued = false;
    _previewDriven = false;
    @track _scalePct = 100;
    @track _changesOpen = false;

    // add / delete section
    @track addOpen = false;
    @track addLayout = '';
    @track addLabel = '';
    @track deleteTarget = null;

    // add industry (Framework > Industry Chooser only)
    @track industryOpen = false;
    @track industryName = '';
    @track industryError = '';

    // column splitter
    @track fieldsWidth = 0;

    // Set when the home page deep-links into a specific page. Without this the
    // editor would always open on its own guess, which is the "landed somewhere
    // I didn't choose" problem the home page exists to fix.
    _requestedOffering = '';
    _requestedTemplate = '';
    // A one-shot mode request riding the same navigation as offering/template
    // -- 'settings' today, from the offering card's Settings button. Consumed
    // and cleared the moment it is applied (see applyRequestedPanel), so
    // requesting it again (even for the same offering/page) fires again.
    _requestedPanel = '';

    /** True once the offering list has loaded, so a later request can act. */
    _ready = false;

    @wire(CurrentPageReference)
    capturePageRef(ref) {
        if (!ref || !ref.state) return;
        const offering = ref.state.c__offering || '';
        const template = ref.state.c__template || '';
        const panel = ref.state.c__panel || '';
        if (offering === this._requestedOffering
            && template === this._requestedTemplate
            && panel === this._requestedPanel) return;

        this._requestedOffering = offering;
        this._requestedTemplate = template;
        this._requestedPanel = panel;
        // A one-time creation nudge, not a persistent "you haven't built
        // Story yet" banner: only set when the home page's create flow
        // stamped c__new on this navigation, and this whole handler only
        // reacts when offering/template actually changed (guard above) — so
        // switching away and back to the same offering without a fresh
        // c__new never re-triggers it.
        const isNew = ref.state.c__new === '1';
        if (isNew) {
            this.isNewOffering = true;
            // A one-time nudge, not a persistent banner: c__new stays in the
            // browser's address bar/history after this navigation (Lightning
            // encodes navItemPage state as URL params), so an F5 on this same
            // URL would otherwise hand the wire the identical state and show
            // the banner again. Scrubbing it from the visible URL (a cosmetic
            // history replace, not a navigation -- it does not requery the
            // wire) is what makes a refresh actually a no-op here.
            this.stripNewFromUrl();
        }

        // connectedCallback runs once. Coming back from the home page a second
        // time reuses this component, so only this wire fires -- and it used
        // to record the request and stop there, leaving whatever page was
        // already open on screen. That is why every page but the first one
        // opened looked like it went somewhere else.
        if (this._ready && offering) this.openRequestedPage();
    }

    /** Open the page the home page asked for, on an already-live editor. */
    openRequestedPage() {
        this.selectedOffering = this._requestedOffering;
        this.selectedTemplate = '';
        this.sections = [];
        this.records = [];
        this.activeKey = '';
        this.settingsOpen = false;
        this.loadTemplates();
    }

    /**
     * Apply a one-shot panel request once the page it targets has finished
     * loading -- 'settings' lands the editor straight on the customizer
     * settings surface instead of the ordinary first section. Consumed here
     * (cleared to '') so it does not linger and reapply on an unrelated
     * later load.
     */
    applyRequestedPanel() {
        const panel = this._requestedPanel;
        this._requestedPanel = '';
        if (panel === 'settings' && this.settingsSection) {
            this.activeKey = this.settingsSection.sectionKey;
            this.settingsOpen = true;
        }
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
            .finally(() => {
                this.isLoading = false;
                this._ready = true;
                // The wire can land before this promise settles, in which case
                // the request arrived while there was nothing to apply it to.
                if (this._requestedOffering && this._requestedOffering !== this.selectedOffering) {
                    this.openRequestedPage();
                }
            });
    }

    /** Best-effort only -- a failure here just means a refresh could re-show
     * the welcome hint, not a broken page, so it is never allowed to throw. */
    stripNewFromUrl() {
        try {
            if (typeof window === 'undefined' || !window.history || !window.history.replaceState) return;
            const url = new URL(window.location.href);
            if (!url.searchParams.has('c__new')) return;
            url.searchParams.delete('c__new');
            window.history.replaceState(window.history.state, '', url.toString());
        } catch (e) {
            // Nothing to do -- see the comment above.
        }
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
    get hasOnlyFramework() {
        const list = this.offerings || [];
        return list.length > 0 && list.every((o) => o.offeringKey === FRAMEWORK_KEY);
    }
    get hasTemplate() { return !!this.selectedTemplate; }

    get offeringLabel() {
        const o = this.offerings.find((x) => x.offeringKey === this.selectedOffering);
        return o ? o.label : this.selectedOffering;
    }

    // ─── shared header bar ─────────────────────────────────────────────────────

    get headerMeta() {
        if (!this.hasOffering) return 'Choose an offering to begin';
        if (this.hasTemplate) return `${this.offeringLabel} · ${this.selectedTemplateLabel}`;
        return this.offeringLabel;
    }

    handleOfferingChange(event) {
        this.selectedOffering = event.detail.value;
        this.selectedTemplate = '';
        this.sections = [];
        this.records = [];
        this.activeKey = '';
        this.settingsOpen = false;
        this.loadTemplates();
    }

    loadTemplates() {
        this.isLoading = true;
        this.loadError = '';
        return getTemplateSummary({ offeringKey: this.selectedOffering })
            .then((rows) => {
                this.templates = (rows || []).map((t) => ({
                    ...t,
                    label: t.pageTitle || TEMPLATE_LABELS[t.templateType] || t.templateType,
                    isBuilt: (t.sectionCount || 0) > 0,
                    summary: (t.sectionCount || 0) > 0
                        ? `${t.sectionCount} sections · ${t.fieldCount || 0} fields`
                        : 'Empty — open it to add the first section',
                    cardClass: (t.sectionCount || 0) > 0 ? 'pg-card' : 'pg-card pg-card--unbuilt'
                }));
                // Open the page the home page asked for. Otherwise show the
                // picker, unless exactly one page is built.
                const built = this.templates.filter((t) => t.isBuilt);
                // A deep link opens whatever page it names, built or not: an
                // empty page is where its first section gets added.
                const asked = this.templates.find((t) => t.templateType === this._requestedTemplate);
                if (asked) {
                    this._requestedTemplate = '';
                    this.selectedTemplate = asked.templateType;
                    return this.loadPage().then(() => this.applyRequestedPanel());
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
        if (!chosen) return;
        this.selectedTemplate = t;
        this.activeKey = '';
        this.settingsOpen = false;
        this.loadPage();
    }

    handleBackToPages() {
        this.selectedTemplate = '';
        this.sections = [];
        this.records = [];
        this.activeKey = '';
        this.settingsOpen = false;
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
                // The selected section belongs to the page you just left. Keep
                // it only if this page has one by that name, or the fields
                // column renders an address that no longer exists.
                const stillHere = this.sections.some((x) => x.sectionKey === this.activeKey);
                if (!stillHere) {
                    this.activeKey = this.sections.length ? this.sections[0].sectionKey : '';
                }
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
                this.dirtyKeys = [];
            })
            .catch((err) => { this.loadError = this.messageFrom(err) || 'Content could not be loaded.'; })
            .finally(() => { this.isLoading = false; });
    }

    // ─── rail ─────────────────────────────────────────────────────────────────

    get railSections() {
        // offering-defaults never shows here -- see contentSections. It stays
        // present in this.sections (the model everything else, including
        // move()/persistOrder(), operates on) so hiding it from the rail
        // changes nothing about its stored position.
        const rows = this.contentSections;
        return rows.map((s, i) => {
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
                // The rail said "page-header" and "industry-profile" -- the
                // keys the code addresses layouts by, not names anybody would
                // choose. The same module already carries the human ones.
                layoutLabel: LAYOUT_LABELS[s.layoutType] || s.layoutType,
                isDirty: this.dirtyKeys.indexOf(s.sectionKey) > -1,
                fieldCount: this.records.filter((r) => r.sectionKey === s.sectionKey).length,
                itemClass: 'sec'
                    + (s.sectionKey === this.activeKey ? ' sec--active' : '')
                    + (s.active === false ? ' sec--off' : '')
                    + (s.isDeleted ? ' sec--doomed' : '')
                    + (s.isDraft ? ' sec--pending' : ''),
                isFirst: i === 0,
                isLast: i === rows.length - 1,
                toggleLabel: s.active === false ? 'Show on page' : 'Hide from page',
                pendingLabel: pending,
                hasPending: !!pending,
                canDelete: !s.isDeleted,
                canRestore: s.isDeleted === true
            };
        });
    }

    get sectionCount() { return this.contentSections.length; }

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
        clearTimeout(this._presentationTimer);
        // A drag left in progress when this component unmounts would otherwise
        // leave these listening on window forever, each closing over stale DOM.
        if (this._splitMove) window.removeEventListener('pointermove', this._splitMove);
        if (this._splitUp) window.removeEventListener('pointerup', this._splitUp);
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
            .then((draftedIds) => {
                this.saveMessage = 'Order saved as a draft';
                // A new order is an unpublished change like any other. Without
                // this the rail reordered, Apex wrote the draft, and the header
                // still said there was nothing to publish.
                this.markDrafted(draftedIds);
            })
            .catch((err) => { this.loadError = this.messageFrom(err) || 'The new order could not be saved.'; })
            .finally(() => { this.isSaving = false; });
    }

    /**
     * Mark exactly the sections Apex says are now unpublished.
     *
     * Apex returns the ids rather than the editor guessing, because a section
     * moved back to where it started has no draft to publish and should not
     * claim one.
     */
    markDrafted(draftedIds) {
        const drafted = new Set(draftedIds || []);
        this.sections = this.sections.map((s) => ({ ...s, isDraft: drafted.has(s.id) }));
    }

    handleToggleActive(event) {
        const key = event.currentTarget.dataset.key;
        const section = this.sections.find((s) => s.sectionKey === key);
        if (!section) return;
        const next = !(section.active !== false);
        this.isSaving = true;
        setSectionActive({ sectionId: section.id, active: next })
            .then((isDraft) => {
                this.sections = this.sections.map((s) =>
                    s.sectionKey === key ? { ...s, active: next, isDraft: isDraft === true } : s);
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

    /**
     * What is actually pending, named. A count alone tells you something is
     * unpublished without telling you what, which is the one thing you need
     * before deciding whether to publish.
     */
    get pendingChanges() {
        const bySection = new Map(this.sections.map((x) => [x.sectionKey, x.label || x.sectionKey]));
        const out = [];
        this.sections.forEach((sec) => {
            if (!sec.isDraft) return;
            let what = 'moved';
            if (sec.isDeleted) what = 'delete on publish';
            else if (sec.isNew) what = 'new section';
            else if (sec.isHidden) what = sec.active === false ? 'hide on publish' : 'show on publish';
            out.push({
                id: `sec-${sec.sectionKey}`,
                where: sec.label || sec.sectionKey,
                what,
                kindClass: 'chg chg--structure'
            });
        });
        this.records.forEach((r) => {
            if (!r.isDraft && !r.pendingDelete) return;
            out.push({
                id: `fld-${r.id}`,
                where: bySection.get(r.sectionKey) || r.sectionKey,
                what: r.pendingDelete ? `${r.label || r.fieldKey} — delete on publish` : (r.label || r.fieldKey),
                kindClass: r.pendingDelete ? 'chg chg--doomed' : 'chg'
            });
        });
        return out;
    }

    get changesOpen() { return this._changesOpen && this.hasDrafts; }
    handleToggleChanges() { this._changesOpen = !this._changesOpen; }
    handleCloseChanges() { this._changesOpen = false; }

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
        this.settingsOpen = false;
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

    handleDismissNewOfferingHint() { this.isNewOffering = false; }

    // ─── add / delete sections ────────────────────────────────────────────────

    get layoutOptions() {
        // Scoped to the page being edited: a layout this page's renderer
        // cannot draw would save and then show nothing.
        return addableLayouts(this.selectedTemplate).map((l) => ({
            ...l,
            icon: SECTION_ICONS[l.value] || 'utility:record',
            fieldLabel: `${l.fieldCount} field${l.fieldCount === 1 ? '' : 's'}`,
            cardClass: l.value === this.addLayout ? 'card card--on' : 'card'
        }));
    }

    /* The breadcrumb showed 'offerings-listing' -- the key the code addresses a
     * template by, not a name anyone would say out loud. */
    get selectedTemplateLabel() {
        const t = (this.templates || []).find((x) => x.templateType === this.selectedTemplate);
        if (t && t.label) return t.label;
        return TEMPLATE_LABELS[this.selectedTemplate] || this.selectedTemplate;
    }

    /**
     * The framework ships configured.
     *
     * Its two pages -- the offerings front door and the industry chooser --
     * are the shape of the product, not content a BA composes per engagement.
     * Their words are entirely editable and their sections can be reordered;
     * what is closed is adding and removing sections, because a section added
     * to the offerings page has no renderer behind it and a section removed
     * takes a structural part of the product with it.
     */
    get isFrameworkPage() { return this.selectedOffering === FRAMEWORK_KEY; }

    /**
     * What ships fixed on the framework is the set of PAGES, not the sections.
     *
     * An earlier pass locked sections too, which took away editing the thing
     * the framework is mostly made of. Its two pages cannot be added to or
     * removed -- they come from templatesFor(), so there is no route to a third
     * one -- and everything inside them is edited like anywhere else.
     */
    get canChangeStructure() { return true; }

    get hasLayoutOptions() { return this.layoutOptions.length > 0; }

    get noLayoutsReason() {
        if (this.selectedTemplate === 'offerings-page') {
            return 'This page draws its tiles from the offerings themselves, so there is nothing to add here. Edit an offering\u2019s Offerings Listing page to change its tile.';
        }
        if (this.selectedTemplate === 'industry-chooser') {
            return 'Industries aren\u2019t added from this generic editor. Edit an existing industry\u2019s tile to change what it says.';
        }
        return 'This page has no layouts to add. Its content comes from elsewhere.';
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

    slugify(raw, max = 80) {
        const cut = String(raw || '')
            .trim()
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-+|-+$/g, '')
            .slice(0, max);
        // A shorter cap can land on a dash; the server strips it, so do the same.
        return max < 80 ? cut.replace(/-+$/g, '') : cut;
    }

    // ─── add industry ─────────────────────────────────────────────────────────
    // The Industry Chooser page owns the industry list, so it gets a purpose-built
    // name-only flow instead of the generic section modal (which stays closed
    // there). The key is generated; the server is authoritative on duplicates.

    get isIndustryPage() {
        return this.selectedOffering === FRAMEWORK_KEY && this.selectedTemplate === 'industry-chooser';
    }

    // 'industry-' is 9 characters and Section_Key__c is Text(80): 71 for the slug.
    get industrySlug() { return this.slugify(this.industryName, 71); }
    get industryKeyPreview() { return this.industrySlug ? `industry-${this.industrySlug}` : ''; }
    get industryAddressPreview() {
        return this.industrySlug
            ? `${FRAMEWORK_KEY}::industry-chooser::industry-${this.industrySlug}` : '';
    }

    get _industryDuplicate() {
        const key = this.industryKeyPreview;
        return !!key && (this.sections || []).some((x) => x.sectionKey === key);
    }

    // Nothing shown until the user types, so the modal does not open in an error.
    get industryValidation() {
        const raw = String(this.industryName || '');
        if (!raw) return '';
        const name = raw.trim();
        if (!name) return 'Give the industry a name.';
        if (!this.industrySlug) return 'That name has no letters or numbers to build a key from.';
        if (this._industryDuplicate) {
            return `An industry called "${name}" already exists. Edit it instead.`;
        }
        return '';
    }

    get industryWarning() {
        const name = String(this.industryName || '').trim().toLowerCase();
        if (!name || !this.industrySlug || this._industryDuplicate) return '';
        const similar = (this.sections || []).some((x) =>
            String(x.sectionKey || '').startsWith('industry-')
            && String(x.label || '').trim().toLowerCase() === name);
        return similar ? 'There is already an industry with a similar name.' : '';
    }

    get canAddIndustryDisabled() {
        return !this.industrySlug || this._industryDuplicate || this.isSaving;
    }

    handleOpenIndustry() {
        this.industryOpen = true;
        this.industryName = '';
        this.industryError = '';
    }

    handleCloseIndustry() { this.industryOpen = false; }

    handleIndustryNameChange(event) {
        this.industryName = event.target.value;
        this.industryError = '';
    }

    handleCreateIndustry() {
        if (this.canAddIndustryDisabled) return;
        this.isSaving = true;
        this.saveMessage = 'Adding industry…';
        this.industryError = '';
        let sectionKey = '';
        createIndustry({ label: this.industryName.trim(), fields: fieldsFor('industry-tile') })
            .then((key) => {
                sectionKey = key;
                this.industryOpen = false;
                this.saveMessage = 'Industry added';
                this.activeKey = key;
                return this.loadPage();
            })
            .then(() => {
                this.activeKey = sectionKey;
                this.scrollRailTo(sectionKey);
            })
            .catch((err) => {
                // A failed create keeps the modal open with the name intact so it
                // can be fixed; a failed reload after a successful create does not.
                this.saveMessage = '';
                const text = this.messageFrom(err);
                if (sectionKey) {
                    this.loadError = text || 'Content could not be loaded.';
                } else {
                    this.industryError = text || 'The industry could not be created.';
                }
            })
            .finally(() => { this.isSaving = false; });
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
            this._splitMove = undefined;
            this._splitUp = undefined;
        };
        this._splitMove = move;
        this._splitUp = up;
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

    // Presentation changes how a field is drawn, not what it says, so they
    // save straight away: holding one back would mean a draft you cannot see
    // in the preview it exists for.
    handleFieldPresentationChange(event) {
        const { recordId, key, value } = event.detail;
        this.records = this.records.map((r) => (r.id === recordId ? { ...r, [key]: value } : r));
        clearTimeout(this._presentationTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._presentationTimer = setTimeout(() => {
            savePresentation({ recordId, key, value })
                .then(() => { this.saveMessage = 'Saved'; })
                .catch((err) => { this.loadError = this.messageFrom(err) || 'That could not be saved.'; });
        }, 600);
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
    /**
     * The offering's pages, as a picker.
     *
     * Switching offering was one click on a combobox; switching page meant
     * going back to the page list and choosing again. They are the same kind of
     * move, so they now look and cost the same.
     */
    get pageOptions() {
        return this.templates.map((t) => ({
            label: t.isBuilt ? t.label : `${t.label} — empty`,
            value: t.templateType
        }));
    }

    handlePageChange(event) {
        const next = event.detail.value;
        if (!next || next === this.selectedTemplate) return;
        if (!this.templates.find((t) => t.templateType === next)) return;
        this.selectedTemplate = next;
        this.activeKey = '';
        this.settingsOpen = false;
        this.loadPage();
    }

    // ─── customizer settings surface ─────────────────────────────────────────
    // offering-defaults (sizePresets/swatches -- what a configurator shows
    // before a rep customises it) is real, offering-scoped content, but it is
    // not a beat of the page the way Cover or a chapter is: it never renders
    // on the public page (only c/gtmConfigWizard, the rep's link tool, reads
    // it) and burying it in the ordinary rail next to actual page content is
    // what made "Settings" hard to find. contentSections is what the rail
    // shows and counts; settingsSection is the one row this panel edits.
    // Neither changes where the data lives (still
    // <offeringKey>::configurator::defaults::*) -- only how it is reached.

    get contentSections() {
        return this.sections.filter((s) => s.layoutType !== 'offering-defaults');
    }

    get settingsSection() {
        return this.sections.find((s) => s.layoutType === 'offering-defaults');
    }

    get hasSettingsSection() { return !!this.settingsSection; }

    handleOpenSettingsPanel() {
        const sec = this.settingsSection;
        if (!sec) return;
        this.activeKey = sec.sectionKey;
        this.settingsOpen = true;
    }

    handleCloseSettingsPanel() {
        this.settingsOpen = false;
        const first = this.contentSections[0];
        this.activeKey = first ? first.sectionKey : '';
    }

    get hasSections() { return !this.isLoading && (this.contentSections.length > 0 || this.settingsOpen); }
    // The Rearrange affordance only makes sense over the ordinary rail --
    // the settings panel is one fixed section, not a reorderable list.
    get canReorder() { return this.hasSections && !this.settingsOpen; }
    get showPagePicker() { return this.hasOffering && !this.hasTemplate && !this.isLoading; }
    get showEditor() { return this.hasOffering && this.hasTemplate && !this.isLoading; }
    get noSections() { return this.showEditor && this.contentSections.length === 0 && !this.settingsOpen; }
}
