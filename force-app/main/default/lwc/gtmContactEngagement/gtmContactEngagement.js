import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getEngagementSummaries from '@salesforce/apex/GtmContactEngagementController.getEngagementSummaries';
import { openAssessment, openEngagementLink } from 'c/gtmNavigate';

const PAGE_SIZE = 25;

const SCOPE_OPTIONS = [
    { label: 'My links', value: 'mine' },
    { label: 'My team', value: 'team' },
    { label: 'All', value: 'all' }
];

/**
 * Two mount points, one component (issue-102-1-engagement-links-landing --
 * task-scope's own instruction: extend gtmContactEngagement, do not fork a
 * second component):
 *
 *  - Contact record page (`recordId` auto-populated by the platform):
 *    every link for that one contact. No scope toggle, no queue chrome --
 *    the record page has already scoped the audience.
 *  - "Engagement Links" landing tab (`recordId` absent -- Tabs never
 *    auto-populate it): the full D1/D6/D8/D13 queue -- [My links | My team
 *    | All] scope toggle (default My links), ranked, grouped by contact.
 *    A drill-in from gtmOverview's Account/Contact click-through
 *    (`c__rlfAccountId` / `c__rlfContactId`, the SAME state param names
 *    that navigation used when it pointed at the Pages tab) narrows the
 *    audience the same way `recordId` does on the record page, and hides
 *    the scope toggle -- the click already picked who's in view.
 *
 * Ranking/state/action are entirely server-computed (GtmContactEngagement
 * Controller) -- this component only renders what it is given; the D8
 * "grouped by contact" shape is the one thing built here, and it is a pure
 * display transform over the already rank-sorted flat list (see `groups`).
 */
export default class GtmContactEngagement extends NavigationMixin(LightningElement) {
    /** Contact Id -- set by the platform on the Contact record page mount
     *  only. Never set on the Tab mount. */
    @api recordId;

    items = [];
    totalCount = 0;
    truncated = false;
    loading = false;
    error;
    scope = 'mine';
    pageNumber = 1;
    pageSize = PAGE_SIZE;
    scopeOptions = SCOPE_OPTIONS;

    _drillAccountId = '';
    _drillContactId = '';
    _pageRefCaptured = false;

    @wire(CurrentPageReference)
    capturePageRef(pageRef) {
        // The record-page mount already has its audience (recordId); it
        // never reads drill-in state off the URL.
        if (this.recordId) {
            return;
        }
        const state = (pageRef && pageRef.state) || {};
        const accountId = state.c__rlfAccountId || '';
        const contactId = state.c__rlfContactId || '';
        const changed = accountId !== this._drillAccountId || contactId !== this._drillContactId;
        this._drillAccountId = accountId;
        this._drillContactId = contactId;
        if (!this._pageRefCaptured || changed) {
            this._pageRefCaptured = true;
            this.pageNumber = 1;
            this.load();
        }
    }

    connectedCallback() {
        // Record-page mount: no CurrentPageReference drill-in state will
        // ever apply, so load immediately rather than waiting on the wire.
        if (this.recordId) {
            this.load();
        }
    }

    get isLandingMode() {
        return !this.recordId;
    }

    get isDrilledIn() {
        return this.isLandingMode && !!(this._drillAccountId || this._drillContactId);
    }

    get showScopeToggle() {
        return this.isLandingMode && !this.isDrilledIn;
    }

    load() {
        this.loading = true;
        this.error = undefined;
        const effectiveContactId = this.recordId || this._drillContactId || null;
        const effectiveAccountId = effectiveContactId ? null : (this._drillAccountId || null);
        getEngagementSummaries({
            contactId: effectiveContactId,
            accountId: effectiveAccountId,
            scopeKey: this.scope,
            pageNumber: this.pageNumber,
            pageSize: this.pageSize
        })
            .then((result) => {
                this.items = (result && result.items) || [];
                this.totalCount = (result && result.totalCount) || 0;
                this.truncated = !!(result && result.truncated);
            })
            .catch((e) => {
                this.error = e;
                this.items = [];
                this.totalCount = 0;
                this.truncated = false;
            })
            .finally(() => {
                this.loading = false;
            });
    }

    handleScopeChange(event) {
        this.scope = event.detail.value;
        this.pageNumber = 1;
        this.load();
    }

    handleRefresh() {
        this.load();
    }

    handleNextPage() {
        if (!this.hasNextPage) {
            return;
        }
        this.pageNumber += 1;
        this.load();
    }

    handlePrevPage() {
        if (!this.hasPrevPage) {
            return;
        }
        this.pageNumber -= 1;
        this.load();
    }

    get hasNextPage() {
        return this.pageNumber * this.pageSize < this.totalCount;
    }

    get hasPrevPage() {
        return this.pageNumber > 1;
    }

    get hasSummaries() {
        return this.items && this.items.length > 0;
    }

    get showEmptyState() {
        return !this.loading && !this.error && !this.hasSummaries;
    }

    get emptyStateMessage() {
        if (this.isLandingMode) {
            return this.scope === 'mine' && !this.isDrilledIn
                ? 'No engagement links yet -- links you send will show up here, ranked by what needs your attention first.'
                : 'No engagement links found for this scope.';
        }
        return 'No engagement links found for this contact.';
    }

    get prevDisabled() {
        return !this.hasPrevPage;
    }

    get nextDisabled() {
        return !this.hasNextPage;
    }

    get pagingLabel() {
        if (!this.totalCount) {
            return '';
        }
        const start = (this.pageNumber - 1) * this.pageSize + 1;
        const end = Math.min(this.pageNumber * this.pageSize, this.totalCount);
        return `${start}-${end} of ${this.totalCount}${this.truncated ? '+' : ''}`;
    }

    /**
     * Flat, already rank-sorted rows (GtmContactEngagementController --
     * D13) -> visually grouped by contact (D8). Purely a display transform:
     * clustering by first-occurrence over an already fully rank-sorted
     * array means a group's position is set by its own best-ranked row,
     * and rows keep their global rank order within a group, with zero
     * extra ranking logic needed here.
     */
    get groups() {
        const order = [];
        const byKey = new Map();
        (this.items || []).forEach((row) => {
            const key = row.contactId || `no-contact::${row.company || row.linkId}`;
            let group = byKey.get(key);
            if (!group) {
                group = {
                    key,
                    contactId: row.contactId,
                    contactName: row.contactName || 'No linked contact',
                    company: row.company,
                    rows: []
                };
                byKey.set(key, group);
                order.push(group);
            }
            group.rows.push(rowViewModel(row));
        });
        return order;
    }

    /** The link name always opens the engagement link's own Pages view --
     *  the one artifact that exists in every state, before and after a
     *  submission (mirrors gtmOverview's own column-1 identity click and
     *  gtmAssessmentDetail's "SC name" link, both of which use the same
     *  openEngagementLink utility). */
    handleLinkClick(event) {
        event.preventDefault();
        const linkId = event.currentTarget.dataset.linkId;
        const accountId = event.currentTarget.dataset.accountId;
        const contactId = event.currentTarget.dataset.contactId;
        if (!linkId) {
            return;
        }
        openEngagementLink(this, linkId, accountId, contactId);
    }

    /** The one primary action per row (D8 + D13) -- state-driven, computed
     *  server-side; this handler only dispatches on the action key it was
     *  given, it never re-derives state from raw fields. */
    handlePrimaryAction(event) {
        event.preventDefault();
        event.stopPropagation();
        const action = event.currentTarget.dataset.action;
        const recordId = event.currentTarget.dataset.recordId;
        const linkId = event.currentTarget.dataset.linkId;
        const accountId = event.currentTarget.dataset.accountId;
        const contactId = event.currentTarget.dataset.contactId;

        if (action === 'open_readout') {
            // A submission exists -- open it (D7: "Open the readout", never
            // "Generate", the Draft already exists by the time a BD sees
            // this row).
            openAssessment(this, recordId);
            return;
        }
        if (action === 'follow_up' || action === 'resend') {
            // No assessment request exists yet at these states (a request/
            // readout is only created at submit time) -- the engagement
            // link itself is the only real artifact to act on.
            openEngagementLink(this, linkId, accountId, contactId);
            return;
        }
        // 'send_disabled' is rendered disabled (see rowViewModel) and never
        // reaches here; 'none' renders no button at all.
    }
}

/** Adds the small set of template-only flags the row shape needs, without
 *  asking the server to encode presentation concerns (D13's own mandate is
 *  about STATE/rank, not about button disabled-ness/copy). */
function rowViewModel(row) {
    return {
        ...row,
        // Server-computed, "who's blocking" framing of state (see
        // GtmContactEngagementController.STATE_LABEL) -- falls back to the
        // raw state key only if an older/mocked payload omits stateLabel,
        // so the row never renders a blank cell.
        stateLabel: row.stateLabel || row.state,
        isOpenReadout: row.primaryAction === 'open_readout',
        isSendDisabled: row.primaryAction === 'send_disabled',
        isFollowUp: row.primaryAction === 'follow_up',
        isResend: row.primaryAction === 'resend',
        hasAction: row.primaryAction !== 'none'
    };
}
