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
                key: 'active-links',
                label: 'Active Links',
                value: fmt(this.snapshot.activeEngagementCount),
                icon: 'utility:link'
            },
            {
                key: 'new-requests',
                label: 'New Requests',
                value: fmt(this.snapshot.newAssessmentCount),
                icon: 'utility:inbox'
            },
            {
                key: 'views-7d',
                label: 'Page Views (7d)',
                value: fmt(this.snapshot.recentViews),
                icon: 'utility:preview'
            },
            {
                key: 'submissions',
                label: 'Submissions This Month',
                value: fmt(this.snapshot.submissionsThisMonth),
                icon: 'utility:check'
            }
        ];
    }
}

function fmt(value) {
    return Number(value || 0).toLocaleString('en-US');
}
