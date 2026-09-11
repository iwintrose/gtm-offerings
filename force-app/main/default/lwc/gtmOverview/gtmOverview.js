import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSnapshot from '@salesforce/apex/GtmHomeSnapshotController.getSnapshot';
import getRecentNewAssessmentRequests from '@salesforce/apex/GtmHomeSnapshotController.getRecentNewAssessmentRequests';
import getDeals from '@salesforce/apex/GtmHomeSnapshotController.getDeals';
import getHomeSummary from '@salesforce/apex/GtmPageContentController.getHomeSummary';
import getFeedbackFor from '@salesforce/apex/GtmFeedbackController.getFeedbackFor';
import submitFeedback from '@salesforce/apex/GtmFeedbackController.submitFeedback';
import getSiteHomePageUrl from '@salesforce/apex/GtmSavedConfigurationController.getSiteHomePageUrl';
import { TEMPLATE_LABELS } from 'c/gtmPageLayouts';

/**
 * The app's landing page.
 *
 * Two columns because the two things have different jobs: the numbers are
 * read down the left, the work waiting on someone sits in the middle. The
 * one action you came here to start lives in the page header instead of a
 * third column of its own. Offerings sit underneath, each linking to its own
 * public story rather than to an industry chooser — the story is what a
 * colleague is actually sent.
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
    // Page-title overrides from renamePage(), keyed "<offeringKey>::<templateType>".
    pageTitles = {};

    @track navBusy = false;

    /** Which offering's panel is open, and what is being typed into it. */
    @track openOffering = '';
    @track feedback = [];
    @track draft = '';
    @track sending = false;

    /**
     * Everything this page shows is "what has happened lately", so it is read
     * on mount rather than wired.
     *
     * A cacheable @wire hands a freshly mounted component whatever Lightning
     * already had, which on a tab you navigate back to is the state before you
     * left. That staleness is what the Refresh button existed to work around;
     * reading on load removes the need for the button and the wait.
     */
    loadSnapshot() {
        return getSnapshot()
            .then((data) => { this.snapshot = data; })
            .catch((e) => { this.loadError = this.messageFrom(e) || 'The snapshot could not be loaded.'; });
    }

    loadRequests() {
        return getRecentNewAssessmentRequests()
            .then((data) => {
                this.requests = (data || []).map((r) => ({
                    key: r.recordId,
                    url: `/lightning/r/GTM_Assessment_Request__c/${r.recordId}/view`,
                    name: r.requesterName || r.name,
                    meta: [r.company, r.platform].filter(Boolean).join(' · '),
                    date: r.createdDate ? new Date(r.createdDate).toLocaleDateString() : ''
                }));
            })
            .catch((e) => { this.loadError = this.messageFrom(e) || 'Requests could not be loaded.'; })
            .finally(() => { this.requestsLoaded = true; });
    }

    /**
     * The deals, and what each recipient did with the page sent for them.
     *
     * A request tells you someone asked; the funnel tells you how they got
     * there and, more usefully, who got close and stopped. Reading them on one
     * row is the point: "opened, never submitted" is invisible in either list
     * on its own.
     */
    loadDeals() {
        return getDeals()
            .then((data) => {
                this.deals = (data || []).map((d) => {
                    const stage = dealStage(d);
                    return {
                        key: d.configId,
                        url: `/lightning/r/Opportunity/${d.opportunityId}/view`,
                        linkUrl: `/lightning/r/GTM_Saved_Configuration__c/${d.configId}/view`,
                        requestUrl: d.requestId ? `/lightning/r/GTM_Assessment_Request__c/${d.requestId}/view` : '',
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
                        opened: (d.views || 0) > 0,
                        started: d.formOpened === true,
                        converted: !!d.requestId || d.formSubmitted === true,
                        lastLabel: d.lastActivity ? new Date(d.lastActivity).toLocaleDateString() : 'no activity yet',
                        inactive: d.linkActive === false
                    };
                });
            })
            .catch((e) => { this.loadError = this.messageFrom(e) || 'Deals could not be loaded.'; })
            .finally(() => { this.dealsLoaded = true; });
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
            this.loadSnapshot();
            this.loadRequests();
            this.loadDeals();
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
                this.pageTitles = (data && data.pageTitles) || {};
                const pt = this.pageTitles;
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
                        // The story is read in the app now, so the only thing
                        // that gates the button is whether the page has been
                        // built. It used to also require a live public site —
                        // which would have hidden the button the moment that
                        // site was retired, for a page that no longer needs it.
                        hasStory: !!story,
                        summary: built.length
                            ? `${built.length} page${built.length === 1 ? '' : 's'} built · ${fields} fields`
                            : 'No pages modelled yet',
                        // Named pages rather than a count: "Story, Configurator"
                        // tells a BD what exists to read; "2 pages" does not.
                        // pageTitles override wins over the hardcoded TEMPLATE_LABELS.
                        pageList: built
                            .map((p) => pt[o.offeringKey + '::' + p.templateType]
                                || TEMPLATE_LABELS[p.templateType]
                                || p.templateType)
                            .join(' · '),
                        configuratorUrl: o.configuratorUrl || '',
                        hasConfigurator: !!o.configuratorUrl,
                        isOpen: false,
                        toggleLabel: 'Feedback',
                        panelClass: 'ocard-panel'
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

    /**
     * The funnel, derived from the deals table rather than counted separately.
     *
     * The four numbers that used to sit here were not a funnel and could not be
     * made into one: they mixed three units (links, requests, events) and two
     * time windows (all-time, last 7 days), and "new requests" was a status
     * filter rather than a stage -- a request already marked Contacted has
     * still converted, so counting only New made the last step shrink as the
     * team worked it.
     *
     * These four are a fallout funnel in the Adobe sense: how many of one
     * population reached each step, every stage a strict subset of the one
     * before, one unit, one window. Deriving them from the rows below means the
     * funnel and the table can never disagree.
     */
    get funnel() {
        const deals = this.deals;
        const stages = [
            { key: 'sent',      label: 'Page sent',   hint: 'An engagement link prepared for a deal',   n: deals.length },
            { key: 'opened',    label: 'Opened it',   hint: 'The recipient read the page',           n: deals.filter((d) => d.opened).length },
            { key: 'started',   label: 'Started the form', hint: 'They began the assessment',        n: deals.filter((d) => d.started).length },
            { key: 'requested', label: 'Asked for the assessment', hint: 'A request came back',      n: deals.filter((d) => d.converted).length }
        ];
        const top = stages[0].n || 0;
        // The biggest single drop is the only part of a funnel worth acting on,
        // so it is the only part that gets emphasis.
        let worst = 0;
        stages.forEach((st, i) => { if (i > 0 && stages[i - 1].n - st.n > worst) worst = stages[i - 1].n - st.n; });

        return stages.map((st, i) => {
            const prev = i === 0 ? st.n : stages[i - 1].n;
            const lost = prev - st.n;
            return {
                ...st,
                pct: top ? Math.round((st.n / top) * 100) : 0,
                barStyle: `width: ${top ? Math.max(4, (st.n / top) * 100) : 0}%`,
                showDrop: i > 0 && lost > 0,
                dropLabel: `${lost} did not`,
                dropClass: lost > 0 && lost === worst ? 'fn-drop fn-drop--worst' : 'fn-drop',
                barClass: i === stages.length - 1 ? 'fn-bar fn-bar--end' : 'fn-bar'
            };
        });
    }

    get funnelReady() { return this.dealsLoaded && this.deals.length > 0; }

    /* Two numbers that are context, not stages: they are measured over a
     * different window and a different population, so putting them in the
     * funnel would have been the mistake the funnel replaced. */
    get asides() {
        const s = this.snapshot;
        if (!s) return [];
        return [
            { key: 'views', label: 'Page views, last 7 days', value: fmt(s.recentViews), icon: 'utility:preview', valueClass: 'aside-v' },
            {
                key: 'stalled',
                label: 'Opened, never submitted',
                value: fmt(s.stalledCount),
                icon: 'utility:warning',
                valueClass: s.stalledCount > 0 ? 'aside-v aside-v--warn' : 'aside-v'
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

    /**
     * The offerings section, as something to read rather than a row of links.
     *
     * It listed each offering and a link to its story. A BD person could go and
     * read what the offering says and had nowhere to say "that claim does not
     * survive a CFO" — so the only route back to whoever writes it was a
     * conversation nobody recorded. Each card now says what the offering has,
     * and opens a panel to say something about it.
     */
    get offeringCards() {
        return this.offerings.map((o) => {
            const open = o.offeringKey === this.openOffering;
            const mine = open ? this.feedback : [];
            return {
                ...o,
                isOpen: open,
                toggleLabel: open ? 'Close' : 'Feedback',
                panelClass: open ? 'ocard-panel ocard-panel--on' : 'ocard-panel',
                openCount: (o.openFeedback || 0),
                openLabel: (o.openFeedback || 0) > 0
                    ? `${o.openFeedback} open` : '',
                notes: mine
            };
        });
    }

    /**
     * The story opens in the app, not on the public site.
     *
     * It used to be an external link to /s/story. Nobody outside the firm ever
     * reads it, and sending a rep to the site domain is what left them a guest
     * — the sign-in loop they kept hitting. Same renderer, inside Lightning,
     * where they are already themselves.
     */
    handleReadStory(event) {
        const offering = event.currentTarget.dataset.offering;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Pages' },
            state: { c__offering: offering, c__template: 'story' }
        });
    }

    handleToggleFeedback(event) {
        const key = event.currentTarget.dataset.offering;
        if (this.openOffering === key) { this.openOffering = ''; this.feedback = []; return; }
        this.openOffering = key;
        this.draft = '';
        this.feedback = [];
        getFeedbackFor({ offeringKey: key })
            .then((rows) => { this.feedback = (rows || []).map((r) => this.shapeNote(r)); })
            .catch((e) => { this.loadError = this.messageFrom(e) || 'Feedback could not be loaded.'; });
    }

    /** One note, as it reads to the person looking at it. */
    shapeNote(r) {
        const answered = !!r.response;
        return {
            key: r.recordId,
            name: r.name,
            body: r.body,
            who: r.isMine ? 'You' : (r.submittedBy || 'Someone'),
            when: r.createdDate ? new Date(r.createdDate).toLocaleDateString() : '',
            status: r.status,
            statusClass: `note-pill note-pill--${(r.status || 'New').toLowerCase().replace(/\s+/g, '-')}`,
            page: r.templateType
                ? (this.pageTitles[r.offeringKey + '::' + r.templateType]
                    || TEMPLATE_LABELS[r.templateType]
                    || r.templateType)
                : '',
            hasResponse: answered,
            response: r.response,
            // The one state that needs the reader to do something.
            needsYou: r.status === 'Needs More Info' && r.isMine
        };
    }

    handleDraftChange(event) { this.draft = event.target.value; }

    get sendDisabled() { return this.sending || !this.draft.trim(); }

    handleSendFeedback() {
        const body = (this.draft || '').trim();
        if (!body || !this.openOffering) return;
        this.sending = true;
        submitFeedback({ offeringKey: this.openOffering, templateType: '', body })
            .then((row) => {
                if (row) this.feedback = [this.shapeNote(row), ...this.feedback];
                this.draft = '';
            })
            .catch((e) => { this.loadError = this.messageFrom(e) || 'That could not be saved.'; })
            .finally(() => { this.sending = false; });
    }

    get showEmptyOfferings() { return this.offeringsLoaded && !this.offerings.length; }

    /**
     * The rep's entry point, and the reason this button is on this page: it
     * sends them to the site's own "Choose your industry" page with ?wizard=1,
     * so picking an industry drops them straight into the configurator wizard.
     * Building a page for an offering is a different job for a different
     * person, and lives in the Content Manager.
     */
    handleNewEngagementLink() {
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
