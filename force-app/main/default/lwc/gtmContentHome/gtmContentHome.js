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
    @track isLoading = false;
    @track loadError = '';

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
