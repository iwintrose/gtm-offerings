import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSnapshot from '@salesforce/apex/MaHomeSnapshotController.getSnapshot';
import getRecentNewAssessmentRequests from '@salesforce/apex/MaHomeSnapshotController.getRecentNewAssessmentRequests';
import getDeals from '@salesforce/apex/MaHomeSnapshotController.getDeals';
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
    @track deals = [];
    @track dealsLoaded = false;
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

    /**
     * The deals, and what each recipient did with the page sent for them.
     *
     * A request tells you someone asked; the funnel tells you how they got
     * there and, more usefully, who got close and stopped. Reading them on one
     * row is the point: "opened, never submitted" is invisible in either list
     * on its own.
     */
    @wire(getDeals)
    wiredDeals({ data, error }) {
        if (data) {
            this.deals = data.map((d) => {
                const stage = dealStage(d);
                return {
                    key: d.configId,
                    url: `/lightning/r/Opportunity/${d.opportunityId}/view`,
                    linkUrl: `/lightning/r/MA_Saved_Configuration__c/${d.configId}/view`,
                    requestUrl: d.requestId ? `/lightning/r/MA_Assessment_Request__c/${d.requestId}/view` : '',
                    name: d.opportunityName,
                    account: d.accountName || d.company || '',
                    industry: d.industryLabel || '',
                    crmStage: d.stageName || '',
                    close: d.closeDate ? new Date(d.closeDate).toLocaleDateString() : '',
                    views: d.views || 0,
                    viewsLabel: `${d.views || 0} view${(d.views || 0) === 1 ? '' : 's'}`,
                    hasRequest: !!d.requestId,
                    requestName: d.requestName || '',
                    requestStatus: d.requestStatus || '',
                    stageLabel: stage.label,
                    stageClass: `pill pill--${stage.tone}`,
                    lastLabel: d.lastActivity ? new Date(d.lastActivity).toLocaleDateString() : 'no activity yet',
                    inactive: d.linkActive === false
                };
            });
        } else if (error) {
            this.loadError = this.messageFrom(error) || 'Deals could not be loaded.';
        }
        this.dealsLoaded = true;
    }

    get hasDeals() { return this.deals.length > 0; }
    get showEmptyDeals() { return this.dealsLoaded && !this.hasDeals; }

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
                // The framework is authoring scaffolding, not an offering a
                // rep sells. It belongs in the Content Manager, which is the
                // BA's app; showing it here asks a BD person to reason about
                // the CMS to find the thing they actually came for.
                this.offerings = ((data && data.offerings) || [])
                    .filter((o) => o.isFramework !== true)
                    .map((o) => {
                    const built = (o.pages || []).filter((p) => (p.sectionCount || 0) > 0);
                    const fields = (o.pages || []).reduce((n, p) => n + (p.fieldCount || 0), 0);
                    const story = built.find((p) => p.templateType === 'story');
                    return {
                        offeringKey: o.offeringKey,
                        label: o.label,
                        // A story link only appears when the page is modelled
                        // and the offering has a live site; a dead link is
                        // worse than no link.
                        hasStory: !!story && !!o.storyUrl,
                        storyUrl: o.storyUrl || '',
                        summary: built.length
                            ? `${built.length} page${built.length === 1 ? '' : 's'} built · ${fields} fields`
                            : 'No pages modelled yet'
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
            // The only tile that names work nobody is doing, so it is the only
            // one that gets to shout. It replaced "submissions this month",
            // which counted the same act as "new requests" and told a BD
            // nothing the row above it had not already said.
            {
                key: 'stalled',
                label: 'Opened, never submitted',
                value: fmt(s.stalledCount),
                icon: 'utility:warning',
                valueClass: s.stalledCount > 0 ? 'tile-value tile-value--warn' : 'tile-value'
            }
        ];
    }

    // ─── middle column ────────────────────────────────────────────────────────

    get hasRequests() { return this.requests.length > 0; }
    get showEmptyRequests() { return this.requestsLoaded && !this.hasRequests; }

    // ─── header ───────────────────────────────────────────────────────────────

    /** What this page is, in one line under the title. */
    get headerMeta() {
        const offerings = this.offerings.length;
        const waiting = this.requests.length;
        const parts = [offerings === 1 ? '1 offering' : `${offerings} offerings`];
        parts.push(waiting === 1 ? '1 request waiting' : `${waiting} requests waiting`);
        return parts.join(' · ');
    }

    get showEmptyOfferings() { return this.offeringsLoaded && !this.offerings.length; }

    
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

/**
 * Where a deal has got to, said once.
 *
 * The funnel is ordered, so the furthest thing that happened is the whole
 * story: a submitted form makes an earlier drop-off history, and a drop-off
 * with no submission is the one state worth chasing.
 */
function dealStage(d) {
    if (d.requestId || d.formSubmitted) return { label: 'Request received', tone: 'good' };
    if (d.droppedOff)                   return { label: 'Started, then left', tone: 'warn' };
    if (d.formOpened)                   return { label: 'Opened the form', tone: 'warn' };
    if (d.views > 0)                    return { label: 'Read the page', tone: 'info' };
    return { label: 'Not opened yet', tone: 'quiet' };
}

function fmt(value) {
    return Number(value || 0).toLocaleString('en-US');
}
