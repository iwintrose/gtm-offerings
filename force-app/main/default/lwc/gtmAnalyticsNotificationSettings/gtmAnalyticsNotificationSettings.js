import { LightningElement, track } from 'lwc';
import getSettings from '@salesforce/apex/GtmAnalyticsSettingsController.getSettings';
import saveSettings from '@salesforce/apex/GtmAnalyticsSettingsController.saveSettings';

/**
 * Analytics Notifications section (issue #147) of the GTM_Offerings_Settings
 * shell tab (per ADR-0010 -- one tab, many sections, each a self-contained
 * child component; see gtmOfferingsSettings for the shell and
 * gtmReadoutApprovalSettings for the sibling section this one matches the
 * shape of). Currently one setting: the weekly Analytics digest email
 * (issue #140). Saving here is what actually schedules or aborts
 * GtmAnalyticsDigestJob -- see GtmAnalyticsSettingsController's header for
 * why that side effect belongs behind this button, not anywhere automatic.
 */
export default class GtmAnalyticsNotificationSettings extends LightningElement {
    @track digestEnabled = false;
    @track digestDayOfWeek = 'MON';
    @track digestHour = 8;
    @track nextRunDescription = '';
    @track isLoading = true;
    @track isSaving = false;
    @track loadError = '';
    @track saveMessage = '';

    get dayOptions() {
        return [
            { label: 'Monday', value: 'MON' },
            { label: 'Tuesday', value: 'TUE' },
            { label: 'Wednesday', value: 'WED' },
            { label: 'Thursday', value: 'THU' },
            { label: 'Friday', value: 'FRI' },
            { label: 'Saturday', value: 'SAT' },
            { label: 'Sunday', value: 'SUN' }
        ];
    }

    get hourOptions() {
        const options = [];
        for (let h = 0; h < 24; h++) {
            const suffix = h < 12 ? 'AM' : 'PM';
            const display = h % 12 === 0 ? 12 : h % 12;
            options.push({ label: `${display}:00 ${suffix}`, value: String(h) });
        }
        return options;
    }

    connectedCallback() {
        this.load();
    }

    load() {
        this.isLoading = true;
        this.loadError = '';
        return getSettings()
            .then((s) => this.applySettings(s))
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'Settings could not be loaded.';
            })
            .finally(() => { this.isLoading = false; });
    }

    applySettings(s) {
        this.digestEnabled = s.digestEnabled;
        this.digestDayOfWeek = s.digestDayOfWeek;
        this.digestHour = s.digestHour;
        this.nextRunDescription = s.nextRunDescription;
    }

    handleToggle(event) {
        this.digestEnabled = event.target.checked;
    }

    handleDayChange(event) {
        this.digestDayOfWeek = event.detail.value;
    }

    handleHourChange(event) {
        this.digestHour = parseInt(event.detail.value, 10);
    }

    handleSave() {
        this.isSaving = true;
        this.saveMessage = '';
        this.loadError = '';
        return saveSettings({
            enabled: this.digestEnabled,
            dayOfWeek: this.digestDayOfWeek,
            hour: this.digestHour
        })
            .then((s) => {
                this.applySettings(s);
                this.saveMessage = 'Saved.';
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'Could not save settings.';
            })
            .finally(() => { this.isSaving = false; });
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    get hourValue() { return String(this.digestHour); }
}
