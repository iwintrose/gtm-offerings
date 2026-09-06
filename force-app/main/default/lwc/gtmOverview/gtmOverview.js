import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSnapshot from '@salesforce/apex/MaHomeSnapshotController.getSnapshot';
import getRecentNewAssessmentRequests from '@salesforce/apex/MaHomeSnapshotController.getRecentNewAssessmentRequests';
import getHomeSummary from '@salesforce/apex/MaPageContentController.getHomeSummary';
// Owned by the prospect-page-wizard branch, which is deployed to this org.
// Do not add a local copy of MaSavedConfigurationController without merging
// that branch first — this branch's copy of that class is far behind it.
import getSiteHomePageUrl from '@salesforce/apex/MaSavedConfigurationController.getSiteHomePageUrl';

const TEMPLATE_LABELS = {
    story: 'Story',
    configurator: 'Configurator',
    'offerings-listing': 'Offerings Listing',
    'industry-chooser': 'Industry Chooser'
};

/**
 * The app's landing page.
 *
 * Three columns because the three things have different jobs: the numbers are
 * read down the left, the work waiting on someone sits in the middle, and the
 * one action you came here to start is on the right where it cannot be missed.
 * Offerings sit underneath, each linking to its own public story rather than
 * to an industry chooser — the story is what a colleague is actually sent.
 */
export default class GtmOverview extends NavigationMixin(LightningElement) {
    @track snapshot;
    @track requests = [];
    @track offerings = [];
    @track loadError = '';
    @track requestsLoaded = false;
    @track offeringsLoaded = false;

    @track navBusy = false;

    @wire(getSnapshot)
    wiredSnapshot({ data, error }) {
        if (data) this.snapshot = data;
        else if (error) this.loadError = this.messageFrom(error) || 'The snapshot could not be loaded.';
    }

    @wire(getRecentNewAssessmentRequests)
    wiredRequests({ data, error }) {
        if (data) {
            this.requests = data.map((r) => ({
                key: r.recordId,
                url: `/lightning/r/MA_Assessment_Request__c/${r.recordId}/view`,
                name: r.requesterName || r.name,
                meta: [r.company, r.platform].filter(Boolean).join(' · '),
                date: r.createdDate ? new Date(r.createdDate).toLocaleDateString() : ''
            }));
        } else if (error) {
            this.loadError = this.messageFrom(error) || 'Requests could not be loaded.';
        }
        this.requestsLoaded = true;
    }

    // getHomeSummary is deliberately not cacheable — it has to reflect an edit
    // made a moment ago — so it is called rather than wired. @wire refuses a
    // method that is not cacheable, which is what left this page's offerings
    // empty behind a platform error.
    connectedCallback() {
        // NavigationMixin contributes its own connectedCallback; overriding it
        // without chaining leaves the navigation context unwired, which fails
        // at connect rather than at the click that needs it.
        if (super.connectedCallback) super.connectedCallback();
        try {
            this.loadOfferings();
        } catch (e) {
            // A landing page that cannot load its offerings should say so, not
            // take the whole page down with it.
            this.loadError = (e && e.message) || 'Offerings could not be loaded.';
            this.offeringsLoaded = true;
        }
    }

    loadOfferings() {
        return getHomeSummary()
            .then((data) => {
                this.offerings = ((data && data.offerings) || []).map((o) => {
                    const pages = o.pages || [];
                    const built = pages.filter((p) => (p.sectionCount || 0) > 0);
                    const story = built.find((p) => p.templateType === 'story');
                    // Business-facing readiness by named page, not a page/field
                    // count only an admin would parse.
                    const readiness = Object.keys(TEMPLATE_LABELS)
                        .filter((type) => pages.some((p) => p.templateType === type))
                        .map((type) => {
                            const ready = pages.some((p) => p.templateType === type && (p.sectionCount || 0) > 0);
                            return `${TEMPLATE_LABELS[type]} ${ready ? 'ready' : 'not started'}`;
                        });
                    return {
                        offeringKey: o.offeringKey,
                        label: o.label,
                        // A story link only appears when the page is modelled
                        // and the offering has a live site; a dead link is
                        // worse than no link.
                        hasStory: !!story && !!o.storyUrl,
                        storyUrl: o.storyUrl || '',
                        summary: readiness.length ? readiness.join(' · ') : 'No pages started yet'
                    };
                });
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'Offerings could not be loaded.';
            })
            .finally(() => { this.offeringsLoaded = true; });
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    // ─── left column ──────────────────────────────────────────────────────────

    get tiles() {
        const s = this.snapshot;
        if (!s) return [];
        return [
            { key: 'links', label: 'Active links', value: fmt(s.activeEngagementCount), icon: 'utility:link', valueClass: 'tile-value' },
            { key: 'new', label: 'New requests', value: fmt(s.newAssessmentCount), icon: 'utility:inbox', valueClass: 'tile-value' },
            { key: 'views', label: 'Page views (7 days)', value: fmt(s.recentViews), icon: 'utility:preview', valueClass: 'tile-value' },
            // The one number that means something went right gets to say so.
            { key: 'subs', label: 'Submissions this month', value: fmt(s.submissionsThisMonth), icon: 'utility:check', valueClass: 'tile-value tile-value--good' }
        ];
    }

    // ─── middle column ────────────────────────────────────────────────────────

    get hasRequests() { return this.requests.length > 0; }
    get showEmptyRequests() { return this.requestsLoaded && !this.hasRequests; }

    // ─── right column ─────────────────────────────────────────────────────────

    get contentManagerUrl() { return '/lightning/n/GTM_Content_Home'; }

    get showEmptyOfferings() { return this.offeringsLoaded && !this.offerings.length; }

    /**
     * The rep's entry point, and the reason this button is on this page: it
     * sends them to the site's own "Choose your industry" page with ?wizard=1,
     * so picking an industry drops them straight into the configurator wizard.
     * Building a page for an offering is a different job for a different
     * person, and lives in the Content Manager.
     */
    handleNewProspectPage() {
        if (this.navBusy) return;
        this.navBusy = true;
        getSiteHomePageUrl()
            .then((url) => {
                if (!url) {
                    this.loadError = 'The Accelerator site could not be found, so the wizard cannot be opened.';
                    return;
                }
                const sep = url.indexOf('?') > -1 ? '&' : '?';
                this[NavigationMixin.Navigate]({
                    type: 'standard__webPage',
                    attributes: { url: `${url}${sep}wizard=1` }
                });
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'The wizard could not be opened.';
            })
            .finally(() => { this.navBusy = false; });
    }

    handleDismissError() {
        this.loadError = '';
    }

    handleEditOffering(event) {
        this.openEditor(event.currentTarget.dataset.offering, '');
    }

    // Deep-links the editor rather than dropping you on its first page, which
    // is the "landed somewhere I did not choose" problem the home page exists
    /**
     * Opens the editor in the Content Manager app, in this tab.
     *
     * standard__navItemPage stays inside the current app, so it landed the
     * editor as a stranded tab here. standard__webPage crosses apps but opens
     * a browser tab, which is worse. standard__app is the one that does both:
     * switch app, stay put, and carry the deep link through as a nested page
     * reference so the editor still opens on the page that was asked for.
     */
    openEditor(offeringKey, templateType) {
        const state = { c__offering: offeringKey };
        if (templateType) state.c__template = templateType;
        this[NavigationMixin.Navigate]({
            type: 'standard__app',
            attributes: { appTarget: 'c__GTM_Content_Manager' },
            state: {
                pageRef: JSON.stringify({
                    type: 'standard__navItemPage',
                    attributes: { apiName: 'GTM_Content_Manager' },
                    state
                })
            }
        });
    }
}

function fmt(value) {
    return Number(value || 0).toLocaleString('en-US');
}
