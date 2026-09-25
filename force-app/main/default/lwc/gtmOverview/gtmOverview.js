import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { openEngagementLink, openAssessment } from 'c/gtmNavigate';
import getSnapshot from '@salesforce/apex/GtmHomeSnapshotController.getSnapshot';
import getStageCountsAura from '@salesforce/apex/GtmLinkStageService.getStageCountsAura';
import getActToday from '@salesforce/apex/GtmActTodayController.getActToday';
import getDeals from '@salesforce/apex/GtmHomeSnapshotController.getDeals';
import getHomeSummary from '@salesforce/apex/GtmPageContentController.getHomeSummary';
import getFeedbackFor from '@salesforce/apex/GtmFeedbackController.getFeedbackFor';
import submitFeedback from '@salesforce/apex/GtmFeedbackController.submitFeedback';
import getOfferingCounts from '@salesforce/apex/GtmOverviewOfferingCounts.getOfferingCounts';
import getAssessmentPage from '@salesforce/apex/GtmAssessmentListController.getAssessmentPage';
import { TEMPLATE_LABELS } from 'c/gtmPageLayouts';
import { COLUMNS as ASSESSMENT_COLUMNS, mapRow as mapAssessmentRow } from 'c/gtmAssessmentsTableModel';

/** Assessment-results card: the tier/score/status column definitions come from
 *  the Assessments tab's model (unsortable here: server order IS the ranking),
 *  with one local first column that opens the assessment.
 *
 *  The Company column used to be `type: 'button'`, which lightning-datatable
 *  renders via `lightning-button` -- centered, no truncation/ellipsis on
 *  overflow, unlike the plain-text columns beside it (issue #274: one row
 *  visibly wrapped/centered while every other row stayed left-aligned single
 *  line). It now reuses the same `gtmLink` custom cell type
 *  (`c-gtm-link-datatable` / `c-gtm-link-cell`) the Assessments tab's own
 *  Account/Contact columns already use (`gtmAssessmentsTableModel.COLUMNS`)
 *  -- a plain left-aligned, truncating text cell that still dispatches a
 *  `rowaction` on click, so all four columns render through the identical
 *  text-cell path. See handleAssessmentRowAction below for why the
 *  dispatched row only carries `recordId` and the full row is re-looked-up
 *  there. */
const RESULTS_PAGE_SIZE = 25;
const RESULT_FIELDS = ['tierLabel', 'score', 'requestStatus'];
const RESULT_COLUMNS = [
    {
        label: 'Company',
        fieldName: 'openLabel',
        type: 'gtmLink',
        typeAttributes: {
            label: { fieldName: 'openLabel' },
            name: 'open',
            title: { fieldName: 'openLabel' },
            targetId: { fieldName: 'recordId' },
            idField: 'recordId'
        }
    },
    ...RESULT_FIELDS.map((f) => {
        const col = ASSESSMENT_COLUMNS.find((c) => c.fieldName === f);
        const { initialWidth, ...rest } = col; // eslint-disable-line no-unused-vars
        return { ...rest, sortable: false, ...(f === 'score' ? { initialWidth: 80 } : {}) };
    })
];

/**
 * The app's landing page.
 *
 * A Today/Offerings toggle in the header splits the page into two views
 * (issue overview-bd-heat-redesign-1-layout-toggle). Today is the BD's daily
 * triage surface: "Needs attention today" and the grouped follow-up table of
 * opportunities waiting on a rep. Offerings holds the per-offering
 * content/performance card, so the two are never blended together again. The
 * former "Pipeline health" 7-node funnel card that used to sit in Row 2 was
 * removed outright, not migrated -- GtmLinkStageService.getStageCountsAura is
 * still called because the "Came back"/"Went quiet" tiles in "Needs attention
 * today" read its counts, but nothing renders the funnel shape any more.
 */
/** Where each "Act today" tile goes (values per gtm-assessments-table.md and
 *  the gtmPageBrowser c__stage contract; multi values are one comma-separated
 *  param). */
const ACT_TODAY_NAV = {
    new: { apiName: 'GTM_Assessments', state: { c__astatus: 'new' } },
    hot: { apiName: 'GTM_Pages', state: { c__stage: 'hot' } },
    quiet: { apiName: 'GTM_Pages', state: { c__stage: 'quiet' } },
    readout: { apiName: 'GTM_Assessments', state: { c__areadout: 'pending,approved-unsent' } }
};

export default class GtmOverview extends NavigationMixin(LightningElement) {
    @track snapshot;
    @track deals = [];
    @track dealsLoaded = false;
    /** Today/Offerings page-header toggle (issue
     *  overview-bd-heat-redesign-1-layout-toggle). Defaults to Today; not
     *  persisted across loads. Today keeps "Needs attention today" and the
     *  follow-up table; Offerings holds only the per-offering content card. */
    @track currentView = 'today';
    /** The stage counts, independent of getDeals() (issue
     *  overview-sales-dashboard-1-layout-funnel). Counts come from
     *  GtmLinkStageService.getStageCountsAura, never from the deals table.
     *  The former funnel card that rendered these counts as a trapezoid was
     *  removed outright (issue overview-bd-heat-redesign-1-layout-toggle);
     *  this call survives only because the "Came back"/"Went quiet" tiles in
     *  "Needs attention today" still read funnelCounts.hot/quiet below. */
    @track funnelCounts = null;
    @track funnelLoading = true;
    @track funnelError = '';
    /** "Act today" strip (issue overview-sales-dashboard-2-act-today):
     *  New requests / Readout waiting counts and all four tiles' names. The
     *  Came back / Went quiet COUNTS come from funnelCounts above (one
     *  getStageCountsAura call feeds both), never from this payload. */
    @track actToday = null;
    @track actTodayLoading = true;
    @track actTodayError = '';
    @track offerings = [];
    /** Per-offering counts by key; loaded independently of getHomeSummary. A
     *  failure leaves countsError set and the cards render without counts. */
    @track offeringCounts = {};
    @track countsError = '';
    @track assessmentRows = [];
    @track assessmentsLoading = true;
    @track assessmentsError = '';
    assessmentColumns = RESULT_COLUMNS;
    @track loadError = '';
    @track offeringsLoaded = false;

    // Page-title overrides from renamePage(), keyed "<offeringKey>::<templateType>".
    pageTitles = {};

    /**
     * The link wizard, hosted here in Lightning rather than on the site.
     *
     * wizardOffering is what makes the open savable: Offering__c is required
     * and saveConfiguration() rejects a blank one, so the wizard is only ever
     * opened from somewhere an offering key is actually in hand.
     */
    @track wizardOpen = false;
    @track wizardOffering = '';
    /** One line under the header when the header button cannot decide which
     *  offering the rep means. Not an error, so not loadError. */
    @track wizardHint = '';

    /** The "New assessment (no page)" picker (issue
     *  rep-initiated-assessment-no-page) -- same mount-only-while-open
     *  reasoning as the wizard above. */
    @track repDirectOpen = false;
    @track repDirectOffering = '';

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

    /**
     * The funnel counts. Imperative because the service is cacheable=false
     * (a wired call would be refused, and a cached count would be the stale
     * state the Refresh button used to paper over).
     */
    loadFunnel() {
        this.funnelLoading = true;
        return getStageCountsAura()
            .then((data) => {
                this.funnelCounts = data || null;
                this.funnelError = '';
            })
            .catch((e) => {
                this.funnelCounts = null;
                this.funnelError = this.messageFrom(e) || 'The link counts could not be loaded.';
            })
            .finally(() => { this.funnelLoading = false; });
    }

    /** The "Act today" names and request/readout counts (server-side, one call). */
    loadActToday() {
        this.actTodayLoading = true;
        return getActToday()
            .then((data) => {
                this.actToday = data || null;
                this.actTodayError = '';
            })
            .catch((e) => {
                this.actToday = null;
                this.actTodayError = this.messageFrom(e) || 'The "Act today" tiles could not be loaded.';
            })
            .finally(() => { this.actTodayLoading = false; });
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
                        configId: d.configId,
                        url: `/lightning/r/Opportunity/${d.opportunityId}/view`,
                        name: d.opportunityName,
                        opportunityName: d.opportunityName,
                        accountId: d.accountId || '',
                        account: d.accountName || d.company || '',
                        contactId: d.contactId || '',
                        contactName: d.contactName || '',
                        configName: d.configName || '',
                        offeringLabel: d.offeringLabel || '',
                        industry: d.industryLabel || '',
                        crmStage: d.stageName || '',
                        crmStageClass: `pill pill--${crmStageTone(d.stageName)}`,
                        close: formatDateOnly(d.closeDate),
                        views: d.views || 0,
                        viewsLabel: `${d.views || 0} view${(d.views || 0) === 1 ? '' : 's'}`,
                        hasRequest: !!d.requestId,
                        requestId: d.requestId || '',
                        requestName: d.requestName || '',
                        requestStatus: d.requestStatus || '',
                        requestSubmittedLabel: d.requestSubmittedAt
                            ? new Date(d.requestSubmittedAt).toLocaleDateString() : '',
                        stageLabel: stage.label,
                        stageClass: `pill pill--${stage.tone}`,
                        opened: (d.views || 0) > 0,
                        started: d.formOpened === true,
                        converted: !!d.requestId || d.formSubmitted === true,
                        lastLabel: d.lastActivity ? new Date(d.lastActivity).toLocaleDateString() : 'no activity yet',
                        engagementLabel: (d.views || 0) > 0
                            ? `${d.views} view${d.views === 1 ? '' : 's'}${d.lastActivity ? ` · last ${new Date(d.lastActivity).toLocaleDateString()}` : ''}`
                            : 'Not opened yet',
                        engagementClass: (d.views || 0) > 0 ? 'eng-chip eng-chip--seen' : 'eng-chip'
                    };
                });
            })
            .catch((e) => { this.loadError = this.messageFrom(e) || 'Deals could not be loaded.'; })
            .finally(() => { this.dealsLoaded = true; });
    }

    get hasDeals() { return this.deals.length > 0; }
    get showEmptyDeals() { return this.dealsLoaded && !this.hasDeals; }

    /**
     * The deals table, grouped Account -> Contact -> link/page row (issue
     * opportunities-table-redesign-v2, reusing the grouping engine built on
     * the now-superseded `agent/issue-overview-redesign-table-nav` branch).
     *
     * A rep works an account, not a flat list of links -- the same page can
     * have been sent to three people at the same company, and that only
     * reads as one relationship once the rows are grouped by who it went to.
     * Grouping happens here, client-side, from the flat getDeals() rows. The
     * funnel does NOT read these rows -- it has its own server-side counts.
     *
     * A config with no Account__c collects in a single trailing "(No
     * account)" pseudo-group, non-clickable, rather than being silently
     * dropped. A config with an Account but no Contact nests the same way
     * one level down, under a "(No contact)" sub-row.
     */
    get dealGroups() {
        const accounts = new Map(); // accountId -> { accountId, accountName, contacts: Map }
        const NO_ACCOUNT = '__no_account__';
        const NO_CONTACT = '__no_contact__';

        this.deals.forEach((d) => {
            const accKey = d.accountId || NO_ACCOUNT;
            if (!accounts.has(accKey)) {
                accounts.set(accKey, {
                    accountId: d.accountId || '',
                    accountName: d.accountId ? d.account : '',
                    contacts: new Map()
                });
            }
            const acc = accounts.get(accKey);
            const conKey = d.contactId || NO_CONTACT;
            if (!acc.contacts.has(conKey)) {
                acc.contacts.set(conKey, {
                    accountId: d.accountId || '',
                    contactId: d.contactId || '',
                    contactName: d.contactId ? d.contactName : '',
                    deals: []
                });
            }
            acc.contacts.get(conKey).deals.push(d);
        });

        const toGroup = (accKey, acc, isNoAccount) => ({
            key: accKey,
            accountId: acc.accountId,
            accountLabel: isNoAccount ? '(No account)' : (acc.accountName || '(Unnamed account)'),
            headClass: isNoAccount ? 'deal deal-group-head deal-group-head--static' : 'deal deal-group-head',
            contacts: Array.from(acc.contacts.entries()).map(([conKey, con]) => ({
                key: `${accKey}::${conKey}`,
                accountId: con.accountId,
                contactId: con.contactId,
                contactLabel: conKey === NO_CONTACT ? '(No contact)' : (con.contactName || '(Unnamed contact)'),
                deals: con.deals
            }))
        });

        const groups = [];
        accounts.forEach((acc, accKey) => {
            if (accKey === NO_ACCOUNT) return;
            groups.push(toGroup(accKey, acc, false));
        });
        if (accounts.has(NO_ACCOUNT)) {
            groups.push(toGroup(NO_ACCOUNT, accounts.get(NO_ACCOUNT), true));
        }
        return groups;
    }

    /**
     * dealGroups flattened into one row per renderable line, each
     * tagged with its own `type` ('account' | 'contact' | 'deal').
     *
     * A single for:each over one flat list, branching by `type` in the
     * template, is what LWC's template compiler actually supports for a
     * variable-depth grouping like this -- <template key=...> wrapping
     * multiple sibling roots per iteration is not a supported directive
     * here, so the Account -> Contact -> link nesting is flattened once,
     * in JS, rather than expressed as nested for:each blocks in the markup.
     */
    get dealRows() {
        const rows = [];
        this.dealGroups.forEach((grp) => {
            rows.push({
                type: 'account',
                isAccount: true,
                key: `acc::${grp.key}`,
                accountId: grp.accountId,
                accountLabel: grp.accountLabel,
                headClass: grp.headClass
            });
            grp.contacts.forEach((con) => {
                rows.push({
                    type: 'contact',
                    isContact: true,
                    key: `con::${con.key}`,
                    accountId: con.accountId,
                    contactId: con.contactId,
                    contactLabel: con.contactLabel
                });
                con.deals.forEach((d) => {
                    rows.push({ type: 'deal', isDeal: true, key: d.key, deal: d });
                });
            });
        });
        return rows;
    }

    /**
     * Account name click -> that Account record's native Activity tab
     * (issue #31: the Engagement Links landing tab this used to route to
     * is retired). The FlexiPage side of "lands on Activity, not Related"
     * is handled by the `active` flag flip on GTM_Account_Record_Page, not
     * by anything this NavigationMixin call can express.
     */
    handleAccountClick(event) {
        const accountId = event.currentTarget.dataset.accountId;
        if (!accountId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: accountId, objectApiName: 'Account', actionName: 'view' }
        });
    }

    /**
     * Contact name click -> that Contact record's native Activity tab
     * (issue #31: the Engagement Links landing tab this used to route to
     * is retired -- mirrors handleAccountClick's exact mechanism, just
     * targeting Contact instead of Account). The FlexiPage side is the
     * `active` flag flip on GTM_Contact_Record_Page.
     */
    handleContactClick(event) {
        const accountId = event.currentTarget.dataset.accountId;
        const contactId = event.currentTarget.dataset.contactId;
        if (!accountId || !contactId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: contactId, objectApiName: 'Contact', actionName: 'view' }
        });
    }

    /**
     * Column 1 identity click -> the Pages tab, scoped to that specific
     * saved configuration -- same c__template:'link' pattern
     * handleWizardDone already uses for the "just saved this link" deep
     * link.
     */
    handleLinkRowClick(event) {
        const recordId = event.currentTarget.dataset.configId;
        if (!recordId) return;
        const deal = (this.deals || []).find((d) => d.configId === recordId) || {};
        openEngagementLink(this, recordId, deal.accountId, deal.contactId);
    }

    /**
     * Column 3 (Assessment) click -> the Assessments tab, drilled into that
     * specific request -- same c__assessmentRequestId idiom
     * gtmReadoutsOverview.js already consumes.
     */
    handleAssessmentClick(event) {
        // Nested inside a link row that navigates on its own click (see
        // handleLinkRowClick) -- stop this from also firing that second,
        // conflicting navigation.
        event.stopPropagation();
        const requestId = event.currentTarget.dataset.requestId;
        if (!requestId) return;
        openAssessment(this, requestId);
    }

    /**
     * The Opportunity-name anchor inside a link row navigates via its own
     * href -- stop the click from also bubbling to any ancestor row click
     * handler, which would fire a second, conflicting navigation.
     */
    handleOpportunityClick(event) {
        event.stopPropagation();
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
            this.loadSnapshot();
            this.loadDeals();
            this.loadFunnel();
            this.loadActToday();
            this.loadOfferings();
            this.loadOfferingCounts();
            this.loadAssessmentResults();
        } catch (e) {
            // A landing page that cannot load its offerings should say so, not
            // take the whole page down with it.
            this.loadError = (e && e.message) || 'Offerings could not be loaded.';
            this.offeringsLoaded = true;
        }
    }

    loadOfferingCounts() {
        return getOfferingCounts()
            .then((rows) => {
                const byKey = {};
                (rows || []).forEach((r) => { byKey[r.offeringKey] = r; });
                this.offeringCounts = byKey;
                this.countsError = '';
            })
            .catch((e) => {
                this.offeringCounts = {};
                this.countsError = this.messageFrom(e) || 'The offering counts could not be loaded.';
            });
    }

    /** Server-ranked (best fit first, default sort, no filters). NO re-sort here. */
    loadAssessmentResults() {
        this.assessmentsLoading = true;
        return getAssessmentPage({ query: { pageSize: RESULTS_PAGE_SIZE } })
            .then((page) => {
                this.assessmentRows = ((page && page.rows) || []).map((r) => {
                    const row = mapAssessmentRow(r);
                    // mapRow's companyLabel is the em-dash placeholder when the
                    // row has no company; that must not beat contact/name.
                    const company = row.companyLabel === '—' ? '' : row.companyLabel;
                    return { ...row, openLabel: company || row.contactLabel || row.name };
                });
                this.assessmentsError = '';
            })
            .catch((e) => {
                this.assessmentRows = [];
                this.assessmentsError = this.messageFrom(e) || 'The assessments could not be loaded.';
            })
            .finally(() => { this.assessmentsLoading = false; });
    }

    get hasAssessmentRows() { return this.assessmentRows.length > 0; }
    get showAssessmentsEmpty() {
        return !this.assessmentsLoading && !this.assessmentsError && !this.assessmentRows.length;
    }

    /**
     * The `gtmLink` cell type (see RESULT_COLUMNS above) dispatches a
     * synthetic row containing only the one `idField` it was told about
     * (`{ recordId: <id> }`) -- it has no notion of this table's other
     * fields. `readoutId`/`offeringKey` still matter for the deep link
     * (assessmentRef pre-selects the readout/offering), so the full row is
     * looked back up here from `assessmentRows` by `recordId` rather than
     * trusting the event's row shape.
     */
    handleAssessmentRowAction(event) {
        const action = event.detail && event.detail.action;
        const row = event.detail && event.detail.row;
        if (!action || action.name !== 'open' || !row || !row.recordId) return;
        const full = this.assessmentRows.find((r) => r.recordId === row.recordId) || row;
        openAssessment(this, full.recordId, full.readoutId, full.offeringKey);
    }

    handleViewAllAssessments() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' }
        });
    }

    handleReadyToBook() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: { c__apreset: 'ready-to-book' }
        });
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
                    .filter((o) => o.isFramework !== true && o.offeringStatus !== 'Draft' && o.archived !== true)
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
                })
                .filter((o) => o.pageList !== '');
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

    // ─── Act today (Row 1) ────────────────────────────────────────────────────

    /** Always rendered (a '–' count while loading) so the layout does not jump. */
    get showActTodayRow() { return true; }
    get showActTodayError() { return !this.actTodayLoading && !!this.actTodayError; }

    /**
     * Four tiles in a fixed order. Counts: New requests / Readout waiting from
     * getActToday (the Assessments list's own totalCount); Came back / Went
     * quiet from the funnel's getStageCountsAura call. "+" when the source
     * says the count is capped/truncated. Zero shows "0" and "All caught up"
     * and stays clickable.
     */
    get actTodayTiles() {
        const a = this.actToday || {};
        const fc = this.funnelCounts;
        const req = a.newRequests || {};
        const ro = a.readoutWaiting || {};
        const defs = [
            {
                key: 'new', label: 'New requests', hint: 'Assessment requests awaiting a response',
                n: this.actToday ? req.count : null, plus: req.capped === true, names: req.names
            },
            {
                key: 'hot', label: 'Came back', hint: 'Viewed again in the last 48 hours',
                n: fc ? fc.hot : null, plus: !!fc && fc.truncated === true, names: a.cameBackNames
            },
            {
                key: 'quiet', label: 'Went quiet', hint: 'Opened the form, never submitted',
                n: fc ? fc.quiet : null, plus: !!fc && fc.truncated === true, names: a.wentQuietNames
            },
            {
                key: 'readout', label: 'Readout waiting', hint: 'Pending approval or approved and not yet sent',
                n: this.actToday ? ro.count : null, plus: ro.capped === true, names: ro.names
            }
        ];
        return defs.map((d) => {
            const known = d.n !== null && d.n !== undefined;
            const n = known ? d.n : 0;
            const countLabel = known ? `${n}${d.plus ? '+' : ''}` : '–';
            const names = (d.names || []).slice(0, 3).map((name, i) => ({ key: `${d.key}-${i}`, name }));
            const zero = known && n === 0;
            const hint = zero ? 'All caught up' : d.hint;
            return {
                key: d.key,
                label: d.label,
                countLabel,
                hint,
                names,
                hasNames: names.length > 0,
                tileClass: `at-tile at-tile--${d.key}${zero ? ' at-tile--zero' : ''}`,
                ariaLabel: `${d.label}: ${countLabel}. ${hint}`
            };
        });
    }

    /** Click, Enter or Space on a tile opens the matching pre-filtered tab. */
    handleActTodayActivate(event) {
        if (event.type === 'keydown') {
            if (event.key !== 'Enter' && event.key !== ' ' && event.key !== 'Spacebar') return;
            // Space would otherwise scroll the page.
            event.preventDefault();
        }
        const key = event.currentTarget.dataset.key;
        const target = ACT_TODAY_NAV[key];
        if (!target) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: target.apiName },
            state: { ...target.state }
        });
    }

    // ─── Today/Offerings toggle ─────────────────────────────────────────────

    get isTodayView() { return this.currentView !== 'offerings'; }
    get isOfferingsView() { return this.currentView === 'offerings'; }
    get todayToggleClass() {
        return `ov-toggle-btn${this.isTodayView ? ' ov-toggle-btn--active' : ''}`;
    }
    get offeringsToggleClass() {
        return `ov-toggle-btn${this.isOfferingsView ? ' ov-toggle-btn--active' : ''}`;
    }

    handleViewToggle(event) {
        const view = event.currentTarget.dataset.view;
        if (view) this.currentView = view;
    }

    // ─── header ───────────────────────────────────────────────────────────────

    get headerActions() {
        return [
            { name: 'new-engagement-link', label: 'New engagement link', iconName: 'utility:new', variant: 'brand' },
            { name: 'new-rep-direct-assessment', label: 'New assessment (no page)', iconName: 'utility:identity' },
            { name: 'browse-links', label: 'Find a link you sent', iconName: 'utility:search' },
            { name: 'see-assessments', label: 'See Assessments', iconName: 'utility:preview' }
        ];
    }

    handleHeaderAction(event) {
        switch (event.detail.name) {
            case 'new-engagement-link': this.handleNewEngagementLink(); break;
            case 'new-rep-direct-assessment': this.handleNewRepDirectAssessment(); break;
            case 'browse-links': this.handleBrowseLinks(); break;
            case 'see-assessments': this.handleSeeAssessments(); break;
            default: break;
        }
    }

    /** What this page is, in one line under the title. The waiting count is
     *  the "Act today" New requests count (getActToday), null-safe, not capped
     *  at the old 5-row list. */
    get headerMeta() {
        const offerings = this.offerings.length;
        const waiting = (this.actToday && this.actToday.newRequests && this.actToday.newRequests.count) || 0;
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
            const counts = this.offeringCounts[o.offeringKey];
            return {
                ...o,
                hasCounts: !!counts,
                liveLinkCount: counts ? counts.liveLinkCount || 0 : 0,
                submittedAssessmentCount: counts ? counts.submittedAssessmentCount || 0 : 0,
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

    /**
     * The persistent "browse my links" entry point.
     *
     * Unlike handleReadStory and handleWizardDone above, this isn't a deep
     * link into one specific record -- it's the general Account -> Contact ->
     * Link drill-down gtmRepLinkFinder already implements (see D7). A rep
     * needs this at any time, not just right after finishing the wizard, to
     * look up someone they engaged previously. Same standard__navItemPage
     * mechanism, but with an explicit c__template=browse so gtmPageBrowser's
     * state fork treats it as its own case rather than falling through
     * whatever the "no state" default happens to be today.
     */
    handleBrowseLinks() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Pages' },
            state: { c__template: 'browse' }
        });
    }

    /**
     * The Overview -> Assessments hand-off.
     *
     * Same standard__navItemPage mechanism as handleBrowseLinks above, just
     * pointed at the consolidated Assessments tab (built on
     * gtmReadoutsOverview) rather than Pages.
     */
    handleSeeAssessments() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' }
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
     * The rep's entry point — and it stays inside Lightning.
     *
     * It used to hand the rep an external link to the Experience Cloud site
     * with ?wizard=1. On that domain the rep is the site's guest user, not
     * themselves, so the configurator answered "This page needs a link." and
     * the journey ended there. Same move the story button already made: the
     * wizard renders here, in the app, where the rep is a Standard user.
     *
     * This is the ONLY entry point to the wizard. The offering cards
     * deliberately carry no "New link" button of their own — one trigger, at
     * the top of the page, is the agreed shape.
     *
     * The button has no offering of its own, and a link cannot be saved
     * without one (Offering__c is required; saveConfiguration throws on a
     * blank). So it only opens the wizard when there is exactly one offering
     * to mean. Building a page for an offering is a different job for a
     * different person, and lives in the Content Manager.
     *
     * Note on the two branches: the org has exactly one offering today
     * (migration-accelerator), so the single-offering branch is the live path
     * and the wizardHint branch below is currently UNREACHABLE. It is kept as
     * the honest fallback — with several offerings there is no defensible way
     * to guess which one a rep means, and silently picking offerings[0] would
     * write a link against the wrong offering. Do not read the hint branch as
     * exercised behaviour; it is insurance for the day a second offering
     * lands, and it will need a real chooser then.
     */
    handleNewEngagementLink() {
        if (this.offerings.length === 1) {
            this.openWizardFor(this.offerings[0].offeringKey);
            return;
        }
        this.wizardHint = 'Choose an offering below to start a link.';
    }

    openWizardFor(offeringKey) {
        if (!offeringKey) return;
        this.wizardHint = '';
        this.wizardOffering = offeringKey;
        this.wizardOpen = true;
    }

    handleWizardClose() {
        this.wizardOpen = false;
        this.wizardOffering = '';
    }

    /**
     * Opens the "New assessment (no page)" picker -- the supported
     * replacement for the accidental bare-/configurator-URL path (see
     * gtmConfigurator.js's accessBlocked). Offering__c is required
     * schema-wide on GTM_Saved_Configuration__c, so this mirrors
     * handleNewEngagementLink's single-offering gate above: with exactly
     * one offering in the org there is no ambiguity to ask about.
     */
    handleNewRepDirectAssessment() {
        if (this.offerings.length === 1) {
            this.repDirectOffering = this.offerings[0].offeringKey;
            this.repDirectOpen = true;
            return;
        }
        this.wizardHint = 'Choose an offering below to start a link before starting an assessment.';
    }

    handleRepDirectClose() {
        this.repDirectOpen = false;
        this.repDirectOffering = '';
    }

    /**
     * A pageless assessment record was created. Same follow-up shape as
     * handleWizardDone: close the panel and deep-link so the rep can see
     * (and fill in / share) what was just started, rather than being
     * dropped back on an unchanged Overview page with no sign anything
     * happened.
     *
     * Lands on the GTM_Assessments tab with the questionnaire open in a
     * modal -- NOT the raw GTM_Saved_Configuration__c record page. A
     * Saved_Configuration__c record is a Pages-tab concept (it represents
     * an engagement link/page); landing a rep there for a pageless
     * assessment they just created broke that mental model (QA feedback,
     * TEST_FAILURES.log). Same standard__navItemPage + c__ state mechanism
     * handleWizardDone/handleBrowseLinks/handleSeeAssessments already use --
     * gtmReadoutsOverview reads c__repDirectId the same way it already
     * reads c__assessmentRequestId, and renders the modal.
     */
    handleRepDirectCreated(event) {
        const { recordId } = (event && event.detail) || {};
        this.handleRepDirectClose();
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: { c__repDirectId: recordId }
        });
    }

    /**
     * The rep clicked Done on the wizard's own Done screen (not the
     * "x"/backdrop early exit -- that stays on the plain `close` event and
     * handleWizardClose above, unchanged).
     *
     * A wizard that just disappears leaves a rep not knowing to go check the
     * Pages tab for what they just built. This closes the panel exactly as
     * handleWizardClose does, then deep-links the GTM_Pages tab straight to
     * the specific link just saved -- same standard__navItemPage + state
     * mechanism handleReadStory already uses for the Story deep link.
     */
    handleWizardDone(event) {
        const { recordId, generatedUrl, company } = (event && event.detail) || {};
        this.handleWizardClose();
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Pages' },
            state: {
                c__template: 'link',
                c__recordId: recordId,
                c__generatedUrl: generatedUrl || '',
                c__company: company || ''
            }
        });
    }

    /**
     * A link was written. The funnel and the deals table are both counted from
     * saved links, so they are now one record out of date.
     *
     * Deliberately does not close the wizard: the wizard fires this on every
     * autosave as well as on the final save, and the rep is still mid-form.
     */
    handleWizardSaved() {
        this.loadSnapshot();
        this.loadDeals();
        this.loadFunnel();
        this.loadActToday();
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

    /**
     * The offering card's "Assessment" action -- the rebuilt
     * gtmInstrumentAuthor editor's primary entry point
     * (assessment-instrument-rebuild-04-editor-lwc-wiring), replacing the
     * standalone GTM_Instrument_Author tab as the one reps/content managers
     * are expected to use day to day. Same standard__app / navItemPage /
     * c__offering state-passing shape as openEditor() above, just landed on
     * the GTM_Instrument_Author tab instead of GTM_Content_Manager -- the
     * instrument editor is its own tab in the same app, not a panel inside
     * gtmContentManager.
     */
    handleOpenAssessment(event) {
        const offeringKey = event.currentTarget.dataset.offering;
        if (!offeringKey) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__app',
            attributes: { appTarget: 'c__GTM_Content_Manager' },
            state: {
                pageRef: JSON.stringify({
                    type: 'standard__navItemPage',
                    attributes: { apiName: 'GTM_Instrument_Author' },
                    state: { c__offering: offeringKey }
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

/**
 * An Apex Date arrives as "yyyy-mm-dd". new Date("yyyy-mm-dd") is UTC
 * midnight, which prints the previous day west of UTC, so build a local date
 * from the parts instead.
 */
function formatDateOnly(value) {
    if (!value) return '';
    const [y, m, day] = String(value).slice(0, 10).split('-').map(Number);
    if (!y || !m || !day) return '';
    return new Date(y, m - 1, day).toLocaleDateString();
}

/**
 * Opportunity CRM stage, as a tone -- Column 2's stage pill (issue
 * opportunities-table-redesign-v2) reuses the same 4 tones the funnel/
 * request pills already use (`.pill--good/--warn/--info/--quiet` in
 * gtmOverview.css), no new colors. A closed-won deal is the good outcome, a
 * closed-lost one is done and inert (quiet), the late stages that need a
 * push are warn, and everything earlier is just in-progress (info).
 */
function crmStageTone(stageName) {
    const s = (stageName || '').toLowerCase();
    if (s.includes('closed won') || s === 'won') return 'good';
    if (s.includes('closed lost') || s === 'lost') return 'quiet';
    if (s.includes('negotiation') || s.includes('proposal') || s.includes('decision')) return 'warn';
    return 'info';
}
