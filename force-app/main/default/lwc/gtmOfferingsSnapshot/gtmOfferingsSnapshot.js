import { LightningElement, wire, track } from 'lwc';
import getSnapshot from '@salesforce/apex/MaHomeSnapshotController.getSnapshot';
import getSiteHomePageUrl from '@salesforce/apex/MaSavedConfigurationController.getSiteHomePageUrl';

export default class GtmOfferingsSnapshot extends LightningElement {
    snapshot;
    error;
    @track _navBusy = false;

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

    get newButtonLabel() {
        return this._navBusy ? 'Opening…' : '+ New Prospect Page';
    }

    /** Sends the rep to the live site's "Choose your industry" page rather
     * than opening a wizard inline here -- picking an industry there (or
     * skipping) is what actually opens the wizard, on the configurator
     * page itself. New tab, so the rep doesn't lose this Lightning tab.
     *
     * Apex now returns a ready-to-use absolute URL on the org's own My
     * Domain -- open as-is (see MaSavedConfigurationController.getConfiguratorPageUrl
     * for the four approaches tried before this one). */
    async handleNewProspectPage() {
        this._navBusy = true;
        try {
            const url = await getSiteHomePageUrl();
            if (url) {
                window.open(url, '_blank', 'noopener');
            }
        } catch (e) {
            // Best-effort -- nothing else this button can usefully do if
            // the site URL can't be resolved.
        } finally {
            this._navBusy = false;
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
