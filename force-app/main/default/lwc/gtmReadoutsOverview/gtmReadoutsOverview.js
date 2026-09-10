import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getReadoutsForReview from '@salesforce/apex/GtmReadoutController.getReadoutsForReview';

/**
 * Cards view of the readouts a rep still has work on: Draft (needs writing
 * or approving) and Approved (ready to publish). Published readouts drop off
 * this list — once live, the record itself is the source of truth and there
 * is nothing further for the rep to action here.
 *
 * Mirrors gtmOverview's card layout and NavigationMixin deep-link pattern so
 * a rep moving between the two overview pages sees the same shape twice.
 */
export default class GtmReadoutsOverview extends NavigationMixin(LightningElement) {
    @track readouts = [];
    @track loadError = '';
    @track isLoading = true;

    connectedCallback() {
        this.loadReadouts();
    }

    loadReadouts() {
        this.isLoading = true;
        this.loadError = '';
        return getReadoutsForReview()
            .then((rows) => {
                this.readouts = (rows || []).map((r) => ({
                    key: r.id,
                    id: r.id,
                    name: r.name || r.assessmentRequestName || 'Readout',
                    company: r.company || '',
                    statusLabel: r.status || '',
                    // Slugified, not just lower-cased: "Pending Approval"
                    // would otherwise produce two class names, the second of
                    // which ("approval") styles nothing.
                    statusClass: `badge badge--${(r.status || '').toLowerCase().replace(/\s+/g, '-')}`,
                    meta: [r.assessmentRequestName, r.company].filter(Boolean).join(' · '),
                    modified: r.lastModifiedDate ? new Date(r.lastModifiedDate).toLocaleDateString() : ''
                }));
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'Readouts could not be loaded.';
            })
            .finally(() => { this.isLoading = false; });
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    get hasReadouts() { return this.readouts.length > 0; }
    get showEmpty() { return !this.isLoading && !this.hasReadouts && !this.loadError; }

    handleOpenReadout(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Readouts_Manager' },
            state: { c__readout: id }
        });
    }

    handleRefresh() { this.loadReadouts(); }
}
