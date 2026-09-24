import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getReadout from '@salesforce/apex/GtmReadoutController.getReadout';
import getAllReadouts from '@salesforce/apex/GtmReadoutController.getAllReadouts';
import { openReadout } from 'c/gtmNavigate';

const LIST_COLUMNS = [
    {
        label: 'Name',
        fieldName: 'name',
        type: 'button',
        typeAttributes: { label: { fieldName: 'name' }, name: 'open', variant: 'base' }
    },
    { label: 'Status',  fieldName: 'status',  type: 'text' },
    { label: 'Company', fieldName: 'company', type: 'text' },
    {
        type: 'action',
        typeAttributes: { rowActions: [{ label: 'Open', name: 'open' }] }
    }
];

/**
 * The consolidated "Assessment" view (issue #29, extended issue #54).
 *
 * List-first navigation: when no c__readout state param is present the
 * component fetches all readouts (getAllReadouts) and shows a datatable.
 * Clicking a row navigates to the same page with c__readout set, loading
 * the tabbed detail view.
 *
 * Detail view: three tabs — Readout (gtmReadoutReview), Assessments
 * (gtmAssessmentDetail), and Migration Accelerator (conduitDashboard).
 * Both Assessments and Migration Accelerator are conditioned on
 * hasAssessmentRequest; orphan readouts (no Assessment Request) see the
 * same explicit notice in each tab.
 */
export default class GtmAssessmentSubmissionView extends NavigationMixin(LightningElement) {
    @track readoutId = '';
    @track assessmentRequestId = '';
    @track title = '';
    @track isLoading = false;
    @track loadError = '';

    // List view state
    @track readouts = [];
    @track listLoading = false;

    listColumns = LIST_COLUMNS;

    @wire(CurrentPageReference)
    capturePageRef(ref) {
        const id = ref && ref.state ? ref.state.c__readout : '';
        if (id && id !== this.readoutId) {
            this.readoutId = id;
            this.loadSummary();
        } else if (!id && this.readoutId !== '') {
            // Navigated back to list (no param)
            this.readoutId = '';
            this.assessmentRequestId = '';
            this.loadError = '';
        }
        if (!id) {
            this.loadList();
        }
    }

    loadSummary() {
        if (!this.readoutId) return;
        this.isLoading = true;
        this.loadError = '';
        getReadout({ readoutId: this.readoutId })
            .then((data) => {
                this.assessmentRequestId = (data && data.assessmentRequestId) || '';
                this.title = (data && (data.assessmentRequestName || data.company)) || 'Readout';
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'This readout could not be loaded.';
            })
            .finally(() => { this.isLoading = false; });
    }

    loadList() {
        this.listLoading = true;
        getAllReadouts()
            .then((data) => {
                this.readouts = (data || []).map(r => ({
                    id:      r.id,
                    name:    r.name,
                    assessmentRequestId: r.assessmentRequestId || '',
                    offeringKey: r.offeringKey || '',
                    status:  r.status,
                    company: r.company || r.assessmentRequestName || '—'
                }));
            })
            .catch(() => {
                // Non-fatal: list just stays empty, no blocking error banner
            })
            .finally(() => { this.listLoading = false; });
    }

    handleRefresh() {
        this.loadList();
    }

    handleRowAction(event) {
        const row = event.detail.row;
        if (!row || !row.id) return;
        // A readout only exists inside its assessment: open the parent assessment
        // workspace with this readout focused (never a GTM_Readout__c record page).
        openReadout(this, row.id, row.assessmentRequestId, row.offeringKey);
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    get hasAssessmentRequest() { return !!this.assessmentRequestId; }
    get hasReadouts()          { return this.readouts.length > 0; }

    /**
     * List-mode header meta line: "N submissions" (list mode only, per
     * issue B14b3 — the detail/record header further down is out of scope).
     */
    get submissionCountMeta() {
        const count = this.readouts.length;
        return `${count} submission${count === 1 ? '' : 's'}`;
    }

    /**
     * Show the list when no readout Id is resolved from the page ref.
     */
    get showList() { return !this.readoutId; }

    /**
     * Orphan readout: no Assessment Request lookup at all. Both the Assessments
     * tab and Migration Accelerator tab must say so plainly rather than
     * rendering blank. The Readout tab still works normally.
     */
    get showOrphanNotice() { return !this.isLoading && !this.loadError && !this.hasAssessmentRequest; }
}
