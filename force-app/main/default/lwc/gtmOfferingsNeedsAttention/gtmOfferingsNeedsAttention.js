import { LightningElement, wire } from 'lwc';
import getRecentNewAssessmentRequests from '@salesforce/apex/MaHomeSnapshotController.getRecentNewAssessmentRequests';

export default class GtmOfferingsNeedsAttention extends LightningElement {
    rows = [];
    loaded = false;

    @wire(getRecentNewAssessmentRequests)
    wiredRequests({ data }) {
        if (data) {
            this.rows = data.map((r) => ({
                key: r.recordId,
                url: `/lightning/r/MA_Assessment_Request__c/${r.recordId}/view`,
                label: r.company ? `${r.requesterName} · ${r.company}` : r.requesterName,
                date: r.createdDate ? new Date(r.createdDate).toLocaleDateString() : ''
            }));
        }
        this.loaded = true;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get showEmpty() {
        return this.loaded && !this.hasRows;
    }
}
