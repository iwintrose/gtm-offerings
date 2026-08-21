import { LightningElement, wire } from 'lwc';
import getSnapshot from '@salesforce/apex/MaHomeSnapshotController.getSnapshot';

export default class GtmOfferingsSnapshot extends LightningElement {
    snapshot;
    error;

    @wire(getSnapshot)
    wiredSnapshot({ data, error }) {
        if (data) {
            this.snapshot = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.snapshot = undefined;
        }
    }

    get hasError() {
        return !!this.error;
    }

    get tiles() {
        if (!this.snapshot) return [];
        return [
            {
                key: 'active-value',
                label: 'Active Engagement Value',
                value: formatCurrency(this.snapshot.activeEngagementValue)
            },
            {
                key: 'active-count',
                label: 'Active Engagement Links',
                value: formatCount(this.snapshot.activeEngagementCount)
            },
            {
                key: 'new-assessments',
                label: 'New Assessment Requests',
                value: formatCount(this.snapshot.newAssessmentCount)
            },
            {
                key: 'open-pipeline',
                label: 'Open Pipeline (from GTM)',
                value: formatCurrency(this.snapshot.openPipelineAmount)
            }
        ];
    }
}

function formatCurrency(value) {
    const n = Number(value) || 0;
    return '$' + Math.round(n).toLocaleString('en-US');
}

function formatCount(value) {
    return Number(value || 0).toLocaleString('en-US');
}
