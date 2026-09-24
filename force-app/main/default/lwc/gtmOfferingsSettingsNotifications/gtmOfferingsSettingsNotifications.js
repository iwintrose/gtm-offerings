import { LightningElement, track } from 'lwc';
import getOrgDefaults from '@salesforce/apex/GtmNotificationSettingsController.getOrgDefaults';
import setNotificationSettings from '@salesforce/apex/GtmNotificationSettingsController.setNotificationSettings';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const MODE_OPTIONS = [
    { label: 'None', value: 'None' },
    { label: 'Bell Only', value: 'Bell Only' },
    { label: 'Bell + Task', value: 'Bell + Task' }
];

/**
 * "Notifications" section (ADR-0010 Unit 3), rendered inside the
 * admin-only GTM_Offerings_Settings shell tab. Edits
 * GTM_Notification_Settings__c org-wide: nine fields gating six existing
 * readout/assessment-request lifecycle Apex trigger points. Imperative
 * Apex, matching gtmOfferingsSettingsAgent/gtmReadoutApprovalSettings'
 * convention for a single-consumer admin surface. This component owns its
 * own load/save pair -- no shared abstraction across sections
 * (ADR-0010 explicitly rejects that generalization).
 */
export default class GtmOfferingsSettingsNotifications extends LightningElement {
    @track notifyOnSubmitForApproval = false;
    @track autoCloseSubmitTasks = false;
    @track notifyOnApproved = false;
    @track autoCloseApprovedTasks = false;
    @track publishedNotificationMode = 'None';
    @track autoClosePublishedTasks = false;
    @track notifyOnNewAssessmentRequest = false;
    @track autoCloseNewRequestTasks = false;
    @track notifyOnReturnedToDraft = false;

    @track isLoading = true;
    @track isSaving = false;
    @track loadError = '';

    modeOptions = MODE_OPTIONS;

    connectedCallback() {
        this.load();
    }

    load() {
        this.isLoading = true;
        this.loadError = '';
        getOrgDefaults()
            .then((dto) => {
                this.notifyOnSubmitForApproval = !!(dto && dto.notifyOnSubmitForApproval);
                this.autoCloseSubmitTasks = !!(dto && dto.autoCloseSubmitTasks);
                this.notifyOnApproved = !!(dto && dto.notifyOnApproved);
                this.autoCloseApprovedTasks = !!(dto && dto.autoCloseApprovedTasks);
                this.publishedNotificationMode = (dto && dto.publishedNotificationMode) || 'None';
                this.autoClosePublishedTasks = !!(dto && dto.autoClosePublishedTasks);
                this.notifyOnNewAssessmentRequest = !!(dto && dto.notifyOnNewAssessmentRequest);
                this.autoCloseNewRequestTasks = !!(dto && dto.autoCloseNewRequestTasks);
                this.notifyOnReturnedToDraft = !!(dto && dto.notifyOnReturnedToDraft);
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'The setting could not be loaded.';
            })
            .finally(() => { this.isLoading = false; });
    }

    get isBellAndTaskMode() {
        return this.publishedNotificationMode === 'Bell + Task';
    }

    handleNotifyOnSubmitForApprovalChange(event) {
        this.notifyOnSubmitForApproval = event.target.checked;
    }

    handleAutoCloseSubmitTasksChange(event) {
        this.autoCloseSubmitTasks = event.target.checked;
    }

    handleNotifyOnApprovedChange(event) {
        this.notifyOnApproved = event.target.checked;
    }

    handleAutoCloseApprovedTasksChange(event) {
        this.autoCloseApprovedTasks = event.target.checked;
    }

    handlePublishedNotificationModeChange(event) {
        this.publishedNotificationMode = event.detail.value;
    }

    handleAutoClosePublishedTasksChange(event) {
        this.autoClosePublishedTasks = event.target.checked;
    }

    handleNotifyOnNewAssessmentRequestChange(event) {
        this.notifyOnNewAssessmentRequest = event.target.checked;
    }

    handleAutoCloseNewRequestTasksChange(event) {
        this.autoCloseNewRequestTasks = event.target.checked;
    }

    handleNotifyOnReturnedToDraftChange(event) {
        this.notifyOnReturnedToDraft = event.target.checked;
    }

    handleSave() {
        const input = {
            notifyOnSubmitForApproval: this.notifyOnSubmitForApproval,
            autoCloseSubmitTasks: this.autoCloseSubmitTasks,
            notifyOnApproved: this.notifyOnApproved,
            autoCloseApprovedTasks: this.autoCloseApprovedTasks,
            publishedNotificationMode: this.publishedNotificationMode,
            autoClosePublishedTasks: this.autoClosePublishedTasks,
            notifyOnNewAssessmentRequest: this.notifyOnNewAssessmentRequest,
            autoCloseNewRequestTasks: this.autoCloseNewRequestTasks,
            notifyOnReturnedToDraft: this.notifyOnReturnedToDraft
        };

        this.isSaving = true;
        setNotificationSettings({ input })
            .then(() => {
                this.toast('Saved', 'Notification settings were updated.', 'success');
            })
            .catch((err) => {
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
