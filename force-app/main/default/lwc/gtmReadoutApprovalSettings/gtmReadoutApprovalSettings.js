import { LightningElement, track } from 'lwc';
import getSelfApprovalEnabled from '@salesforce/apex/GtmReadoutApprovalSettingsController.getSelfApprovalEnabled';
import setSelfApprovalEnabled from '@salesforce/apex/GtmReadoutApprovalSettingsController.setSelfApprovalEnabled';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

/**
 * "Approval Routing" section, rendered inside the admin-only
 * GTM_Offerings_Settings shell tab (c-gtm-offerings-settings). Toggles
 * GTM_Readout_Approval_Settings__c.Self_Approval_Enabled__c org-wide: the
 * routing mode for every GTM_Readout__c approval going forward.
 *
 * Manager mode (off, the default): the existing GTM_Readout_Approval
 * ApprovalProcess is the only way to approve a readout.
 * Self-approve mode (on): a readout's own owner can approve it directly from
 * gtmReadoutReview, and GtmReadoutController.selfApproveReadout logs the
 * action to GTM_Readout_Approval_Log__c as the audit trail.
 *
 * Imperative Apex rather than @wire, matching gtmAnalytics's own convention
 * for a single-consumer admin surface -- there is exactly one save action
 * here, not a reactive filter to re-run.
 */
export default class GtmReadoutApprovalSettings extends LightningElement {
    @track selfApprovalEnabled = false;
    @track isLoading = true;
    @track isSaving = false;
    @track loadError = '';

    connectedCallback() {
        this.load();
    }

    load() {
        this.isLoading = true;
        this.loadError = '';
        getSelfApprovalEnabled()
            .then((value) => {
                this.selfApprovalEnabled = !!value;
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'The setting could not be loaded.';
            })
            .finally(() => { this.isLoading = false; });
    }

    handleToggle(event) {
        const enabled = event.target.checked;
        this.isSaving = true;
        setSelfApprovalEnabled({ enabled })
            .then(() => {
                this.selfApprovalEnabled = enabled;
                this.toast(
                    'Saved',
                    enabled
                        ? 'Reps can now self-approve their own readouts.'
                        : 'Readouts now route to the owner\'s manager for approval.',
                    'success'
                );
            })
            .catch((err) => {
                // Revert the visual toggle state on failure so the UI never
                // shows a setting that did not actually save.
                event.target.checked = this.selfApprovalEnabled;
                this.toast('Could not save', this.messageFrom(err), 'error');
            })
            .finally(() => { this.isSaving = false; });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }
}
