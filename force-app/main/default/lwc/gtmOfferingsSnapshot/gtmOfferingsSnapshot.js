import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getSnapshot from '@salesforce/apex/MaHomeSnapshotController.getSnapshot';

export default class GtmOfferingsSnapshot extends LightningElement {
    snapshot;
    error;
    @track wizardOpen = false;
    _wiredSnapshotResult;

    @wire(getSnapshot)
    wiredSnapshot(result) {
        this._wiredSnapshotResult = result;
        const { data, error } = result;
        if (data) {
            this.snapshot = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.snapshot = undefined;
        }
    }

    handleOpenWizard() {
        this.wizardOpen = true;
    }

    handleCloseWizard() {
        this.wizardOpen = false;
    }

    /** A link built in the wizard should show up in this tile row (Active
     * Links) without the rep having to navigate away and back. */
    handleWizardSaved() {
        if (this._wiredSnapshotResult) refreshApex(this._wiredSnapshotResult);
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
