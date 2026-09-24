import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { openReadout } from 'c/gtmNavigate';
import getReadoutsAwaiting from '@salesforce/apex/GtmReadoutsAwaitingController.getReadoutsAwaiting';

/**
 * "Readouts awaiting response" widget (issue
 * overview-bd-heat-redesign-3-daily-widgets). Standalone, independently
 * testable LWC: it is NOT yet wired into gtmOverview.html because the
 * Today/Offerings toggle shell it belongs inside
 * (overview-bd-heat-redesign-1-layout-toggle) had not landed on main at
 * the time this was built. See that ticket's contract for final placement.
 *
 * COARSE PROXY ONLY -- GtmReadoutsAwaitingController surfaces Published
 * readouts with a sent date; there is no real viewed/replied signal. Copy
 * here MUST stay "sent N days ago, no update since" and must never say
 * "viewed" or "replied" as fact (task-scope doc, explicitly out-of-scope
 * section; deferred to gus-nudge-tool-and-readout-viewed-tracking).
 *
 * Each row is click/Enter/Space-activatable (issue
 * tasks-widget-row-navigation). A GTM_Readout__c has no page of its own
 * (docs/architecture/gtm-row-open-and-links.md -- "never a bare record
 * page"): it opens via c/gtmNavigate's openReadout, which lands on the
 * parent assessment's readout workspace. A readout with no parent
 * assessment request is a real, supported "orphan" state (routed to
 * GTM_Readout_Triage -- see GTM_Readout__c.Assessment_Request__c's field
 * comment); openReadout no-ops for those and the row is rendered
 * non-interactive rather than a dead click target.
 */
export default class GtmReadoutsAwaitingWidget extends NavigationMixin(LightningElement) {
    rows = [];
    isLoading = true;
    loadError = '';

    connectedCallback() {
        this.loadReadouts();
    }

    loadReadouts() {
        this.isLoading = true;
        this.loadError = '';
        let call;
        try {
            call = getReadoutsAwaiting();
        } catch (e) {
            call = Promise.reject(e);
        }
        return Promise.resolve(call)
            .then((rows) => {
                this.rows = (rows || []).map((r) => {
                    const openable = !!(r.assessmentRequestId && r.readoutId);
                    const proxyLabel = this.proxyLabel(r.daysSinceSent);
                    return {
                        ...r,
                        proxyLabel,
                        openable,
                        rowClass: `slds-item ov-row${openable ? ' ov-row--openable' : ''}`,
                        roleAttr: openable ? 'button' : null,
                        tabIndexAttr: openable ? '0' : null,
                        rowAriaLabel: openable
                            ? `${r.accountName || 'Unknown account'}${r.opportunityName ? ', ' + r.opportunityName : ''}, ${proxyLabel}`
                            : null
                    };
                });
                this.loadError = '';
            })
            .catch((err) => {
                this.rows = [];
                this.loadError = this.messageFrom(err) || 'Readouts could not be loaded.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    /** "sent N days ago, no update since" -- never "viewed"/"replied": the app
     *  has no such signal (see class doc comment). */
    proxyLabel(daysSinceSent) {
        if (daysSinceSent === null || daysSinceSent === undefined) return '';
        if (daysSinceSent <= 0) return 'sent today, no update since';
        if (daysSinceSent === 1) return 'sent 1 day ago, no update since';
        return `sent ${daysSinceSent} days ago, no update since`;
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    handleRetry() {
        this.loadReadouts();
    }

    /** Click, Enter or Space on a row opens the parent assessment's readout
     *  workspace (never a bare GTM_Readout__c record page). Orphan rows (no
     *  assessmentRequestId, so no data-assessment-request-id on the DOM node
     *  -- see openable in loadReadouts) are rendered non-focusable and
     *  openReadout's own `!arId` guard no-ops the rare stray click. */
    handleRowActivate(event) {
        if (event.type === 'keydown') {
            if (event.key !== 'Enter' && event.key !== ' ' && event.key !== 'Spacebar') return;
            // Space would otherwise scroll the page.
            event.preventDefault();
        }
        const { readoutId, assessmentRequestId, offeringKey } = event.currentTarget.dataset;
        openReadout(this, readoutId, assessmentRequestId, offeringKey);
    }

    get hasRows() { return this.rows.length > 0; }
    get showEmpty() { return !this.isLoading && !this.loadError && !this.hasRows; }
    get showRows() { return !this.isLoading && !this.loadError && this.hasRows; }
}
