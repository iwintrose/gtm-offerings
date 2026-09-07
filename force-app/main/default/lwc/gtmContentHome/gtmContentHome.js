import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeSummary from '@salesforce/apex/MaPageContentController.getHomeSummary';

const TEMPLATE_LABELS = {
    story: 'Story',
    configurator: 'Configurator',
    'offerings-listing': 'Offerings Listing',
    'industry-chooser': 'Industry Chooser'
};

// Every template the picklist allows, so the home can show what an offering
// has NOT built yet rather than only what it has.
const ALL_TEMPLATES = ['story', 'configurator', 'industry-chooser', 'offerings-listing'];

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

    get cards() {
        return this.offerings.map((o) => {
            const built = o.pages.filter((p) => (p.sectionCount || 0) > 0);
            const byType = {};
            o.pages.forEach((p) => { byType[p.templateType] = p; });
            return {
                key: o.offeringKey,
                label: o.label,
                builtCount: built.length,
                fieldTotal: o.pages.reduce((n, p) => n + (p.fieldCount || 0), 0),
                summary: built.length === 1
                    ? '1 page ready to edit'
                    : `${built.length} pages ready to edit`,
                pages: ALL_TEMPLATES.map((t) => {
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
                        // "Not editable" was wrong: an empty page is exactly
                        // where you go to build it. It has nothing in it, which
                        // is a different thing from being closed.
                        badge: isBuilt ? '' : 'Empty',
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

    // ─── new page ─────────────────────────────────────────────────────────────
    // Building a page for an offering belongs here, with the pages, rather
    // than on the GTM Offerings overview — that page is a rep's, and its
    // create action starts the configurator wizard, not a CMS page.

    get offeringOptions() {
        return this.offerings.map((o) => ({ label: o.label, value: o.offeringKey }));
    }

    get templateOptions() {
        return ALL_TEMPLATES.map((t) => ({ label: TEMPLATE_LABELS[t] || t, value: t }));
    }

    get npDisabled() { return !this.npOffering || !this.npTemplate; }

    get npHint() {
        if (this.npDisabled) return 'Both are needed to open the editor on the right page.';
        return 'The editor opens on this page. If it has no sections yet, add the first one there.';
    }

    handleOpenNewPage() {
        this.newPageOpen = true;
        this.npOffering = this.offerings.length === 1 ? this.offerings[0].offeringKey : '';
        this.npTemplate = 'story';
    }

    handleCloseNewPage() { this.newPageOpen = false; }
    handleNpOffering(event) { this.npOffering = event.detail.value; }
    handleNpTemplate(event) { this.npTemplate = event.detail.value; }

    handleGoToPage() {
        if (this.npDisabled) return;
        this.newPageOpen = false;
        this.openEditor(this.npOffering, this.npTemplate);
    }

    // This page already lives in the Content Manager app, so the editor is a
    // tab away rather than an app away; navItemPage keeps the app shell.
    openEditor(offeringKey, templateType) {
        const state = { c__offering: offeringKey };
        if (templateType) state.c__template = templateType;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Content_Manager' },
            state
        });
    }

    handleRefresh() { this.load(); }
    handleDismissError() { this.loadError = ''; }
}
