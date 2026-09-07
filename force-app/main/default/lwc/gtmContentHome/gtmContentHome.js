import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createPage from '@salesforce/apex/GtmPageSectionController.createPage';
import { starterFor, templatesFor, TEMPLATE_LABELS } from 'c/gtmPageLayouts';
import getHomeSummary from '@salesforce/apex/GtmPageContentController.getHomeSummary';
import renameOffering from '@salesforce/apex/GtmPageContentController.renameOffering';
import createOffering from '@salesforce/apex/GtmPageContentController.createOffering';


// Every template the picklist allows, so the home can show what an offering
// has NOT built yet rather than only what it has.

// D8: framework templateTypes that are a setting, not a page -- something
// this app has one fixed instance of, not something a BA composes or a
// prospect ever sees end to end. They stay registered in FRAMEWORK_TEMPLATES
// (the editor, the breadcrumb and "what templateTypes exist" all need to know
// about them) but this view keeps them out of the pages list and the "New
// framework page" picker, and surfaces them through their own Settings link
// instead.
const SETTINGS_TEMPLATES = ['assistant'];

// A page reads as what it is before its name is read.
const PAGE_ICONS = {
    'story': 'utility:socialshare',
    'configurator': 'utility:setup',
    'offerings-listing': 'utility:tile_card_list',
    'offerings-page': 'utility:apps',
    'industry-chooser': 'utility:company',
    'faq-bd': 'utility:knowledge_base',
    'faq-content-manager': 'utility:knowledge_base'
};

export default class GtmContentHome extends NavigationMixin(LightningElement) {
    @track offerings = [];
    @track activity = [];

    // new page
    @track newPageOpen = false;
    @track npOffering = '';
    @track npTemplate = 'story';
    @track isLoading = false;
    @track loadError = '';
    @track searchTerm = '';

    // rename
    @track renamingKey = '';
    @track renameValue = '';

    // new offering
    @track newOfferingOpen = false;
    @track newOfferingName = '';

    connectedCallback() { this.load(); }

    load() {
        this.isLoading = true;
        this.loadError = '';
        getHomeSummary()
            .then((data) => {
                this.offerings = (data && data.offerings) || [];
                this.activity = (data && data.activity) || [];
            })
            .catch((err) => {
                this.loadError = (err && err.body && err.body.message)
                    || err.message || 'The content summary could not be loaded.';
            })
            .finally(() => { this.isLoading = false; });
    }

    get headerMeta() {
        const offerings = this.offerings.filter((o) => !o.isFramework).length;
        const pages = this.offerings.reduce(
            (n, o) => n + (o.pages || []).filter((p) => (p.sectionCount || 0) > 0).length, 0);
        const noun = offerings === 1 ? 'offering' : 'offerings';
        return `Framework · ${offerings} ${noun} · ${pages} pages`;
    }

    get cards() {
        return this.offerings.map((o) => {
            const built = o.pages.filter((p) => (p.sectionCount || 0) > 0);
            const byType = {};
            o.pages.forEach((p) => { byType[p.templateType] = p; });
            return {
                key: o.offeringKey,
                label: o.label,
                isFramework: o.isFramework === true,
                canRename: o.canRename === true,
                isEditing: this.renamingKey === o.offeringKey,
                icon: o.isFramework ? 'standard:hierarchy' : 'standard:product',
                // The rail on the card and the icon are the same colour on
                // purpose: one signal for "what kind of thing is this".
                subtitle: o.isFramework
                    ? 'Sits above every offering'
                    : o.offeringKey,
                cardClass: o.isFramework
                    ? 'slds-card off off--framework'
                    : 'slds-card off',
                badgeClass: built.length
                    ? 'slds-badge slds-badge_lightest off-stat'
                    : 'slds-badge off-stat',
                addLabel: o.isFramework ? 'New framework page' : 'New page for this offering',
                // Settings is a direct line into one templateType, bypassing
                // the pages list, for the same reason on both kinds of card:
                // what it points to is not a beat of a page a prospect reads
                // top to bottom, it's a fixed thing this card's owner
                // configures once. An offering's is the Configurator's
                // "defaults" section (swatches, default source/target
                // platform, demo numbers) -- content on that offering's own
                // configurator page, buried inside a big multi-section
                // editor. The Framework's is Gus (D8): one assistant shared
                // by every offering's configurator, addressed
                // gtm::assistant::assistant rather than any one offering's
                // page, and deliberately absent from the pages list below
                // for the same reason -- it isn't one.
                showSettings: true,
                settingsTemplate: o.isFramework ? 'assistant' : 'configurator',
                settingsHint: o.isFramework
                    ? 'Gus: the name, role, greeting and prompts of the assistant every offering’s configurator shares'
                    : 'Swatches, default platforms and demo numbers for this offering’s links',
                builtCount: built.length,
                fieldTotal: o.pages.reduce((n, p) => n + (p.fieldCount || 0), 0),
                summary: built.length === 1
                    ? '1 page ready to edit'
                    : `${built.length} pages ready to edit`,
                // Settings templateTypes (currently just 'assistant') are
                // registered with templatesFor() so the editor and breadcrumb
                // know what they are, but they are not a page in the sequence
                // this list is for -- they get their own Settings link below.
                pages: templatesFor(o.offeringKey)
                    .filter((t) => SETTINGS_TEMPLATES.indexOf(t) === -1)
                    .map((t) => {
                        const p = byType[t];
                        const sections = p ? (p.sectionCount || 0) : 0;
                        const fields = p ? (p.fieldCount || 0) : 0;
                        const isBuilt = sections > 0;
                        return {
                            id: `${o.offeringKey}-${t}`,
                            templateType: t,
                            offeringKey: o.offeringKey,
                            label: TEMPLATE_LABELS[t] || t,
                            isBuilt,
                            detail: isBuilt
                                ? `${sections} sections · ${fields} fields`
                                : 'No sections yet — open it to build the first one',
                            // "Not editable" was wrong: an empty page is
                            // exactly where you go to build it. It has
                            // nothing in it, which is a different thing from
                            // being closed.
                            badge: isBuilt ? '' : 'Empty',
                            icon: PAGE_ICONS[t] || 'utility:page',
                            rowClass: isBuilt ? 'pg' : 'pg pg--unbuilt'
                        };
                    })
            };
        });
    }

    /**
     * Page-level activity: what happened to a page, not which box someone
     * typed in. A publish is an event; an autosaved keystroke is not.
     */
    // Substring match against the offering name/key and its page names, so
    // typing "story" finds an offering by what it has, not just what it's
    // called. There are only ever a handful of offerings each with four
    // fixed pages, so this stays a plain client-side filter over data
    // that's already loaded — no server round-trip needed.
    get filteredCards() {
        const q = (this.searchTerm || '').trim().toLowerCase();
        if (!q) return this.cards;
        return this.cards.filter((c) =>
            c.label.toLowerCase().includes(q)
            || c.key.toLowerCase().includes(q)
            || c.pages.some((p) => p.label.toLowerCase().includes(q))
        );
    }

    get hasFilteredCards() { return this.filteredCards.length > 0; }
    get showNoSearchResults() {
        return !this.isLoading && this.searchTerm.trim() && this.hasOfferings && !this.hasFilteredCards;
    }

    handleSearch(event) {
        this.searchTerm = event.detail.value || '';
    }

    get activityRows() {
        return this.activity.map((a, i) => ({
            id: `${a.offeringKey}-${a.templateType}-${i}`,
            offeringKey: a.offeringKey,
            templateType: a.templateType,
            what: a.summary,
            where: TEMPLATE_LABELS[a.templateType] || a.templateType,
            when: a.occurred ? new Date(a.occurred).toLocaleString() : ''
        }));
    }

    get hasActivity() { return this.activity.length > 0; }

    get hasOfferings() { return !this.isLoading && this.offerings.length > 0; }
    get isEmpty() { return !this.isLoading && this.offerings.length === 0; }

    // Opening the editor carries the choice with it, so nobody lands on a page
    // they did not pick.
    handleOpenPage(event) {
        // An empty page opens too. It is where its first section gets built,
        // and refusing to open it was why the only way to model a page was in
        // code.
        const { offering, template } = event.currentTarget.dataset;
        this.openEditor(offering, template);
    }

    handleOpenRecent(event) {
        const { offering, template } = event.currentTarget.dataset;
        this.openEditor(offering, template);
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    // ─── new page ─────────────────────────────────────────────────────────────
    // Building a page for an offering belongs here, with the pages, rather
    // than on the GTM Offerings overview — that page is a rep's, and its
    // create action starts the configurator wizard, not a CMS page.

    get offeringOptions() {
        return this.offerings.map((o) => ({ label: o.label, value: o.offeringKey }));
    }

    // Settings templateTypes are excluded here too: "New page" builds a page
    // from a starter shape, and a settings templateType is not one -- it has
    // exactly one instance, already migrated in, reachable through its own
    // Settings link rather than through "new".
    get templateOptions() {
        return this.pageTemplatesFor(this.npOffering).map((t) => ({ label: TEMPLATE_LABELS[t] || t, value: t }));
    }

    pageTemplatesFor(offeringKey) {
        return templatesFor(offeringKey).filter((t) => SETTINGS_TEMPLATES.indexOf(t) === -1);
    }

    get npDisabled() { return !this.npOffering || !this.npTemplate; }


    // ─── a new offering ───────────────────────────────────────────────────────
    // "New page" was the wrong question at this level. A page belongs to an
    // offering, and every card already offers its own "New page for this
    // offering"; what the header could not do was start the offering itself.

    handleOpenNewOffering() {
        this.newOfferingOpen = true;
        this.newOfferingName = '';
    }

    handleCloseNewOffering() { this.newOfferingOpen = false; }
    handleNewOfferingInput(event) { this.newOfferingName = event.target.value; }
    handleNewOfferingKey(event) {
        if (event.key === 'Enter') this.handleCreateOffering();
        if (event.key === 'Escape') this.handleCloseNewOffering();
    }

    get createOfferingDisabled() { return !(this.newOfferingName || '').trim(); }

    get newOfferingHint() {
        const name = (this.newOfferingName || '').trim();
        if (!name) return 'The name is what reps see on the offerings page.';
        const key = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
        return key
            ? `Creates its entry on the offerings page, keyed ${key}. Its pages come next.`
            : 'That name needs at least one letter or number.';
    }

    handleCreateOffering() {
        const name = (this.newOfferingName || '').trim();
        if (!name) return;
        this.isLoading = true;
        createOffering({ name })
            .then((key) => {
                this.newOfferingOpen = false;
                this.newOfferingName = '';
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Offering created',
                    message: `"${name}" is ready. Its Offerings Listing page already has a starting section.`,
                    variant: 'success'
                }));
                // Straight into the new offering's own listing page, which is
                // the only page it has and the one that needs writing. Deferred
                // a microtask past the modal-close writes above so the
                // NavigationMixin dispatch doesn't land in the same tick as
                // those reactive writes — the same shape handleGoToPage() below
                // already uses (its Apex round-trip separates the two).
                return Promise.resolve().then(() => this.openEditor(key, 'offerings-listing', /* isNew */ true));
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'The offering could not be created.';
            })
            .finally(() => { this.isLoading = false; });
    }

    handleOpenNewPage() {
        this.newPageOpen = true;
        this.npOffering = this.offerings.length === 1 ? this.offerings[0].offeringKey : '';
        this.npTemplate = this.npOffering ? (this.pageTemplatesFor(this.npOffering)[0] || '') : 'story';
    }

    handleCloseNewPage() { this.newPageOpen = false; }
    handleNpOffering(event) {
        this.npOffering = event.detail.value;
        // The framework and an offering own different pages, so a template
        // chosen under one is not necessarily offered by the other.
        const allowed = this.pageTemplatesFor(this.npOffering);
        if (allowed.indexOf(this.npTemplate) === -1) this.npTemplate = allowed[0] || '';
    }
    handleNpTemplate(event) { this.npTemplate = event.detail.value; }

    // A page that already has sections is opened, not rebuilt. A page that
    // does not is created first — otherwise "new page" meant "open the editor
    // and hope", which is why every page but the story was empty.
    get npIsExisting() {
        const offering = this.offerings.find((o) => o.offeringKey === this.npOffering);
        if (!offering) return false;
        const page = (offering.pages || []).find((p) => p.templateType === this.npTemplate);
        return !!(page && page.isBuilt);
    }

    get npHint() {
        if (this.npDisabled) return 'Both are needed to open the editor on the right page.';
        if (this.npIsExisting) return 'This page already exists. The editor will open on it.';
        const n = starterFor(this.npTemplate).length;
        return n
            ? `Creates ${n} starting sections you can rename, reorder or remove. Nothing is public until you publish.`
            : 'This page has no starting shape defined yet.';
    }

    handleGoToPage() {
        if (this.npDisabled) return;
        const offeringKey = this.npOffering;
        const templateType = this.npTemplate;
        this.newPageOpen = false;

        if (this.npIsExisting) {
            this.openEditor(offeringKey, templateType);
            return;
        }
        this.isLoading = true;
        createPage({ offeringKey, templateType, sections: starterFor(templateType) })
            .then(() => { this.openEditor(offeringKey, templateType); })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'The page could not be created.';
            })
            .finally(() => { this.isLoading = false; });
    }

    // This page already lives in the Content Manager app, so the editor is a
    // tab away rather than an app away; navItemPage keeps the app shell.
    openEditor(offeringKey, templateType, isNew) {
        const state = { c__offering: offeringKey };
        if (templateType) state.c__template = templateType;
        if (isNew) state.c__new = '1';
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Content_Manager' },
            state
        });
    }

    // ─── renaming an offering ─────────────────────────────────────────────────
    // The name is the one on the offering's own tile, so renaming it here
    // renames it on the offerings page in the same move.

    handleStartRename(event) {
        event.stopPropagation();
        const key = event.currentTarget.dataset.key;
        const hit = this.offerings.find((o) => o.offeringKey === key);
        this.renamingKey = key;
        this.renameValue = hit ? hit.label : '';
    }

    handleRenameInput(event) { this.renameValue = event.target.value; }

    handleRenameKey(event) {
        if (event.key === 'Enter') this.handleSaveRename();
        if (event.key === 'Escape') this.handleCancelRename();
    }

    handleCancelRename() { this.renamingKey = ''; this.renameValue = ''; }

    handleSaveRename() {
        const offeringKey = this.renamingKey;
        const name = (this.renameValue || '').trim();
        if (!offeringKey || !name) return;
        this.isLoading = true;
        renameOffering({ offeringKey, name })
            .then(() => {
                this.handleCancelRename();
                this.load();
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'The offering could not be renamed.';
                this.isLoading = false;
            });
    }

    // The create action on a card already knows which offering it is under, so
    // it opens the dialog with that answer filled in.
    handleNewPageFor(event) {
        const key = event.currentTarget.dataset.key;
        this.newPageOpen = true;
        this.npOffering = key;
        this.npTemplate = this.pageTemplatesFor(key)[0] || '';
    }

    // Straight into the settings templateType this card carries -- an
    // offering's Configurator "defaults" section, or the Framework's
    // assistant. Opens the same editor the pages list would, on a
    // templateType that list deliberately does not show.
    handleOpenSettings(event) {
        const { key, template } = event.currentTarget.dataset;
        this.openEditor(key, template);
    }

    // Reads the org again. Page counts and the activity feed change when
    // someone else publishes, and this view does not listen for that -- so
    // this is how you find out without leaving and coming back.
    handleDismissError() { this.loadError = ''; }
}
