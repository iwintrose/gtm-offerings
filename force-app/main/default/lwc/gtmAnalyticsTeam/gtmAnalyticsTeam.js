import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRepLeaderboard from '@salesforce/apex/GtmAnalyticsTeamController.getRepLeaderboard';
import getFlaggedRequests from '@salesforce/apex/GtmAnalyticsTeamController.getFlaggedRequests';
import getInstrumentVersionComparison from '@salesforce/apex/GtmAnalyticsTeamController.getInstrumentVersionComparison';

const RANGE_PRESETS = { '30': 30, '90': 90, '180': 180 };
const DEFAULT_RANGE = '90';

function isoDate(d) {
    return d.toISOString().slice(0, 10);
}

/**
 * Admin-only, cross-rep leaderboard (issue #139, v2 first pass). Visible
 * only via the GTM_Analytics_Team tab, granted only on GTM_Offering_Admin
 * -- see TASK_SCOPE.md for why the sharing story is intentionally
 * different from the rep-scoped gtmAnalytics tab.
 */
export default class GtmAnalyticsTeam extends NavigationMixin(LightningElement) {
    @track rows = [];
    @track isLoading = true;
    @track loadError = '';
    @track flaggedRows = [];
    @track flaggedHasMore = false;
    @track flaggedReturnedCount = 0;
    @track flaggedLoading = true;
    @track flaggedError = '';
    @track versionRows = [];
    @track versionIsLoading = true;
    @track versionLoadError = '';
    rangeKey = DEFAULT_RANGE;

    get rangeOptions() {
        return [
            { label: 'Last 30 days', value: '30' },
            { label: 'Last 90 days', value: '90' },
            { label: 'Last 180 days', value: '180' }
        ];
    }

    connectedCallback() {
        this.load();
        this.loadVersionComparison();
    }

    handleRangeChange(event) {
        this.rangeKey = event.detail.value;
        this.load();
        this.loadVersionComparison();
    }

    handleRefresh() {
        this.load();
        this.loadVersionComparison();
    }

    load() {
        this.isLoading = true;
        this.loadError = '';
        const { rangeStart, rangeEnd } = this.currentRange();

        const leaderboardPromise = getRepLeaderboard({ rangeStart, rangeEnd })
            .then((rows) => {
                this.rows = (rows || []).map((r) => ({
                    key: r.repId,
                    repName: r.repName,
                    links: r.links,
                    submitted: r.submitted,
                    avgScore: r.avgScore != null ? r.avgScore.toFixed(0) : '—',
                    published: r.published
                }));
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'Team analytics could not be loaded.';
            })
            .finally(() => { this.isLoading = false; });

        const flaggedPromise = this.loadFlagged(rangeStart, rangeEnd);

        return Promise.all([leaderboardPromise, flaggedPromise]);
    }

    loadFlagged(rangeStart, rangeEnd) {
        this.flaggedLoading = true;
        this.flaggedError = '';

        return getFlaggedRequests({ rangeStart, rangeEnd })
            .then((result) => {
                const rows = (result && result.rows) || [];
                this.flaggedRows = rows.map((r) => ({
                    key: r.requestId,
                    requestName: r.requestName,
                    repName: r.repName,
                    createdDate: r.createdDate ? new Date(r.createdDate).toLocaleDateString() : '—',
                    advisory: r.advisory,
                    reasons: this.reasonsFor(r)
                }));
                this.flaggedHasMore = !!(result && result.hasMore);
                this.flaggedReturnedCount = (result && result.returnedCount) || 0;
            })
            .catch((err) => {
                this.flaggedError = this.messageFrom(err) || 'Flagged assessments could not be loaded.';
            })
            .finally(() => { this.flaggedLoading = false; });
    }

    reasonsFor(row) {
        const reasons = [];
        if (row.advisory) {
            reasons.push(row.advisoryReason || 'Advisory (unsupported source/target pair)');
        }
        if (row.flagMessages && row.flagMessages.length) {
            reasons.push(...row.flagMessages);
        }
        return reasons.length ? reasons.join('; ') : '—';
    }

    handleFlaggedRowClick(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'GTM_Assessment_Request__c',
                actionName: 'view'
            }
        });
    }

    loadVersionComparison() {
        this.versionIsLoading = true;
        this.versionLoadError = '';
        const { rangeStart, rangeEnd } = this.currentRange();

        return getInstrumentVersionComparison({ rangeStart, rangeEnd })
            .then((rows) => {
                this.versionRows = (rows || []).map((r, idx) => ({
                    key: `${r.pairKey}::${r.version}::${idx}`,
                    pairKey: r.pairKey,
                    version: r.version,
                    submitted: r.submitted,
                    avgScore: r.avgScore != null ? r.avgScore.toFixed(1) : '—',
                    tierMix: this.tierMixLabel(r.tierCounts),
                    published: r.published,
                    publishRate: r.publishRate != null ? `${r.publishRate.toFixed(1)}%` : '—'
                }));
            })
            .catch((err) => {
                this.versionLoadError = this.messageFrom(err) || 'Instrument version comparison could not be loaded.';
            })
            .finally(() => { this.versionIsLoading = false; });
    }

    tierMixLabel(tierCounts) {
        if (!tierCounts) return '';
        return Object.keys(tierCounts)
            .filter((label) => tierCounts[label] > 0)
            .map((label) => `${label}: ${tierCounts[label]}`)
            .join(', ');
    }

    currentRange() {
        const days = RANGE_PRESETS[this.rangeKey] || RANGE_PRESETS[DEFAULT_RANGE];
        const end = new Date();
        const start = new Date();
        start.setDate(end.getDate() - (days - 1));
        return { rangeStart: isoDate(start), rangeEnd: isoDate(end) };
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    get hasData() { return !this.isLoading && !this.loadError; }
    get showEmpty() { return this.hasData && this.rows.length === 0; }
    get hasRows() { return this.hasData && this.rows.length > 0; }

    get flaggedHasData() { return !this.flaggedLoading && !this.flaggedError; }
    get showFlaggedEmpty() { return this.flaggedHasData && this.flaggedRows.length === 0; }
    get hasFlaggedRows() { return this.flaggedHasData && this.flaggedRows.length > 0; }

    get flaggedMoreMessage() {
        return `Showing ${this.flaggedReturnedCount} of possibly more — narrow your date range.`;
    }

    get versionHasData() { return !this.versionIsLoading && !this.versionLoadError; }
    get versionShowEmpty() { return this.versionHasData && this.versionRows.length === 0; }
    get versionHasRows() { return this.versionHasData && this.versionRows.length > 0; }
}
