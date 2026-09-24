import { LightningElement, track } from 'lwc';
import getStatuses from '@salesforce/apex/GtmScheduledJobsController.getStatuses';
import scheduleJob from '@salesforce/apex/GtmScheduledJobsController.scheduleJob';

// Display-only. The Apex label / CronTrigger job name stays as-is so live
// schedules are not orphaned.
const JOB_LABEL_OVERRIDES = {
    assessmentDraftPurge: 'Assessment Draft Purge'
};

/**
 * "Scheduled Jobs" section (issue #184-purge-batch-autoschedule) of the
 * GTM_Offerings_Settings shell tab (per ADR-0010 -- one tab, many sections,
 * each a self-contained child component; see gtmAnalyticsNotificationSettings
 * for the sibling section this one matches the shape of).
 *
 * Lists both of this app's purge jobs (GTM_PurgeRecordsBatch,
 * GtmAssessmentDraftPurge), each with its own scheduled/not-scheduled
 * status and a "Schedule Now" action. Clicking that action is what
 * actually schedules or reschedules the job -- see
 * GtmScheduledJobsController's header for why that side effect belongs
 * behind an admin's own click, not anything automatic.
 */
export default class GtmScheduledJobsSettings extends LightningElement {
    @track jobs = [];
    @track isLoading = true;
    @track loadError = '';
    @track schedulingJobKey = '';

    connectedCallback() {
        this.load();
    }

    load() {
        this.isLoading = true;
        this.loadError = '';
        return getStatuses()
            .then((statuses) => {
                this.jobs = statuses;
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'Scheduled job status could not be loaded.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleScheduleNow(event) {
        const jobKey = event.currentTarget.dataset.jobKey;
        if (!jobKey) {
            return;
        }
        this.schedulingJobKey = jobKey;
        this.loadError = '';
        return scheduleJob(jobKey)
            .then(() => this.load())
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'Could not schedule the job.';
            })
            .finally(() => {
                this.schedulingJobKey = '';
            });
    }

    get rows() {
        return this.jobs.map((job) => ({
            ...job,
            label: JOB_LABEL_OVERRIDES[job.jobKey] || job.label,
            isScheduling: this.schedulingJobKey === job.jobKey,
            buttonLabel: job.isScheduled ? 'Reschedule' : 'Schedule Now',
            statusClass: job.isScheduled ? 'slds-text-color_success' : 'slds-text-color_weak'
        }));
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }
}
