/**
 * Backs the "Scheduled Jobs" section of the admin-only Settings tab
 * (issue #184-purge-batch-autoschedule). Gives an admin a click-driven,
 * Setup/Developer-Console-free way to see whether each of this app's two
 * purge jobs -- GTM_PurgeRecordsBatch and GtmAssessmentDraftPurge -- is
 * currently scheduled, and to schedule/reschedule either one.
 *
 * Generalizes the abort-then-reschedule pattern already live in
 * GtmAnalyticsSettingsController.abortExistingDigestJob() (issue #147),
 * parameterized here by job instead of hardcoded to one job: this class
 * queries CronTrigger by job name to derive status (no new Custom Setting
 * or object needed -- CronTrigger IS the state), and aborts any existing
 * CronTrigger for a job name before scheduling a fresh one, so re-clicking
 * "Schedule Now" is idempotent rather than throwing a duplicate-job error.
 *
 * Both jobs' cadence is fixed and hardcoded (not admin-configurable) --
 * per the Architect's decision, the cron expression for each job lives as
 * a @TestVisible constant on the job class itself (GTM_PurgeRecordsBatch,
 * GtmAssessmentDraftPurge). Those constants are private to their own
 * classes, so this controller carries its own matching copies keyed by
 * job, rather than reaching into another class's private state.
 *
 * `with sharing`: this class has no field-level data of its own to
 * protect (CronTrigger visibility is a platform concern, not FLS), but is
 * marked `with sharing` for consistency with every other Settings
 * controller in this app.
 */
public with sharing class GtmScheduledJobsController {

    /** Job keys this controller knows how to report on / schedule. Stable
     *  identifiers the LWC passes back on "Schedule Now" -- not the
     *  CronTrigger job name itself, so the UI never has to know the exact
     *  scheduled-job label. */
    @TestVisible
    private static final String JOB_KEY_PURGE_RECORDS_BATCH = 'purgeRecordsBatch';
    @TestVisible
    private static final String JOB_KEY_ASSESSMENT_DRAFT_PURGE = 'assessmentDraftPurge';

    /** CronTrigger job names -- must match GTM_PurgeRecordsBatch.JOB_NAME
     *  and GtmAssessmentDraftPurge.JOB_NAME exactly. */
    private static final String JOB_NAME_PURGE_RECORDS_BATCH = 'GTM Purge Records Batch';
    private static final String JOB_NAME_ASSESSMENT_DRAFT_PURGE = 'MA Assessment Draft Purge';

    /** Cron expressions -- must match GTM_PurgeRecordsBatch.CRON_EXPRESSION
     *  and GtmAssessmentDraftPurge.CRON_EXPRESSION exactly. Fixed per job,
     *  not admin-configurable. */
    private static final String CRON_PURGE_RECORDS_BATCH = '0 0 4 * * ?';
    private static final String CRON_ASSESSMENT_DRAFT_PURGE = '0 0 3 * * ?';

    /** Ordered so the LWC can render a stable row order without its own
     *  sorting logic. */
    @AuraEnabled(cacheable=true)
    public static List<JobStatus> getStatuses() {
        List<JobStatus> out = new List<JobStatus>();
        out.add(buildStatus(
            JOB_KEY_PURGE_RECORDS_BATCH,
            'GTM Purge Records Batch',
            JOB_NAME_PURGE_RECORDS_BATCH
        ));
        out.add(buildStatus(
            JOB_KEY_ASSESSMENT_DRAFT_PURGE,
            'MA Assessment Draft Purge',
            JOB_NAME_ASSESSMENT_DRAFT_PURGE
        ));
        return out;
    }

    /**
     * Schedules (or reschedules) the given job by key. Idempotent: any
     * existing CronTrigger for that job's name is aborted first, so
     * clicking "Schedule Now" repeatedly never throws a duplicate-job
     * exception and never leaves two active triggers for the same job.
     */
    @AuraEnabled
    public static JobStatus scheduleJob(String jobKey) {
        JobConfig config = configFor(jobKey);
        abortExistingJob(config.jobName);

        if (config.key == JOB_KEY_PURGE_RECORDS_BATCH) {
            System.schedule(config.jobName, config.cronExpression, new GTM_PurgeRecordsBatch());
        } else {
            System.schedule(config.jobName, config.cronExpression, new GtmAssessmentDraftPurge());
        }

        return buildStatus(config.key, config.label, config.jobName);
    }

    private static JobConfig configFor(String jobKey) {
        if (jobKey == JOB_KEY_PURGE_RECORDS_BATCH) {
            return new JobConfig(
                JOB_KEY_PURGE_RECORDS_BATCH,
                'GTM Purge Records Batch',
                JOB_NAME_PURGE_RECORDS_BATCH,
                CRON_PURGE_RECORDS_BATCH
            );
        }
        if (jobKey == JOB_KEY_ASSESSMENT_DRAFT_PURGE) {
            return new JobConfig(
                JOB_KEY_ASSESSMENT_DRAFT_PURGE,
                'MA Assessment Draft Purge',
                JOB_NAME_ASSESSMENT_DRAFT_PURGE,
                CRON_ASSESSMENT_DRAFT_PURGE
            );
        }
        throw new AuraHandledException('Unknown scheduled job: ' + jobKey);
    }

    /** Aborts the existing CronTrigger for the given job name, if one is
     *  currently scheduled. Idempotent -- safe to call whether or not a
     *  trigger currently exists. */
    private static void abortExistingJob(String jobName) {
        List<CronTrigger> existing = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            System.abortJob(existing[0].Id);
        }
    }

    private static JobStatus buildStatus(String key, String label, String jobName) {
        List<CronTrigger> existing = [
            SELECT Id, NextFireTime, CronExpression
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
            LIMIT 1
        ];

        JobStatus status = new JobStatus();
        status.jobKey = key;
        status.label = label;
        status.isScheduled = !existing.isEmpty();
        status.nextRunDescription = status.isScheduled
            ? describeNextRun(existing[0].NextFireTime)
            : 'Not scheduled.';
        return status;
    }

    private static String describeNextRun(Datetime nextFireTime) {
        if (nextFireTime == null) {
            return 'Scheduled.';
        }
        return 'Next run: ' + nextFireTime.format('MMM d, yyyy h:mm a') + ' (org time zone).';
    }

    private class JobConfig {
        String key;
        String label;
        String jobName;
        String cronExpression;

        JobConfig(String key, String label, String jobName, String cronExpression) {
            this.key = key;
            this.label = label;
            this.jobName = jobName;
            this.cronExpression = cronExpression;
        }
    }

    public class JobStatus {
        @AuraEnabled public String jobKey;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isScheduled;
        @AuraEnabled public String nextRunDescription;
    }
}
