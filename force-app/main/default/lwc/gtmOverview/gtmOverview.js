import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSnapshot from '@salesforce/apex/MaHomeSnapshotController.getSnapshot';
import getRecentNewAssessmentRequests from '@salesforce/apex/MaHomeSnapshotController.getRecentNewAssessmentRequests';
import getHomeSummary from '@salesforce/apex/MaPageContentController.getHomeSummary';

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

    @track newPageOpen = false;
    @track npOffering = '';
    @track npTemplate = '';

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

    @wire(getHomeSummary)
    wiredHome({ data, error }) {
        if (data) {
            this.offerings = (data.offerings || []).map((o) => {
                const built = (o.pages || []).filter((p) => (p.sectionCount || 0) > 0);
                const story = built.find((p) => p.templateType === 'story');
                const fields = (o.pages || []).reduce((n, p) => n + (p.fieldCount || 0), 0);
                return {
                    offeringKey: o.offeringKey,
                    label: o.label,
                    // A story link only appears when the page is actually
                    // modelled and the offering has a live site; a dead link
                    // is worse than no link.
                    hasStory: !!story && !!o.storyUrl,
                    storyUrl: o.storyUrl || '',
                    summary: built.length
                        ? `${built.length} page${built.length === 1 ? '' : 's'} built · ${fields} fields`
                        : 'No pages modelled yet'
                };
            });
        } else if (error) {
            this.loadError = this.messageFrom(error) || 'Offerings could not be loaded.';
        }
        this.offeringsLoaded = true;
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

    get offeringOptions() {
        return this.offerings.map((o) => ({ label: o.label, value: o.offeringKey }));
    }

    get templateOptions() {
        return Object.keys(TEMPLATE_LABELS).map((k) => ({ label: TEMPLATE_LABELS[k], value: k }));
    }

    get npDisabled() { return !this.npOffering || !this.npTemplate; }

    get npHint() {
        if (this.npDisabled) return 'Both are needed to open the editor on the right page.';
        return 'The Content Manager opens on this page. If it has no sections yet, add the first one there.';
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
        this.newPageOpen = false;
        this.openEditor(this.npOffering, this.npTemplate);
    }

    handleEditOffering(event) {
        this.openEditor(event.currentTarget.dataset.offering, '');
    }

    // Deep-links the editor rather than dropping you on its first page, which
    // is the "landed somewhere I did not choose" problem the home page exists
    // to avoid.
    openEditor(offeringKey, templateType) {
        const state = { c__offering: offeringKey };
        if (templateType) state.c__template = templateType;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Content_Manager' },
            state
        });
    }
}

function fmt(value) {
    return Number(value || 0).toLocaleString('en-US');
}
