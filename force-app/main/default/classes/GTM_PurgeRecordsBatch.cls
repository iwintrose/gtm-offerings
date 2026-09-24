/**
 * Permanently deletes archived GTM_Page_Section__c and GTM_Page_Content__c
 * rows once they have sat past their retention window (issue #184, part 5:
 * the time-based, automatic equivalent of GTM_RecycleBinController's
 * manual "permanently delete" action).
 *
 * WHAT IT DELETES: any row on either object where Archived__c = true AND
 * Archived_Date__c is older than PURGE_AFTER_DAYS. Archived_Date__c is the
 * retention clock the #187 schema slice added specifically to support this
 * purge (see docs/architecture/offering-archive-cascade.md); LastModifiedDate
 * is deliberately not used, since any incidental edit to an already-archived
 * row would otherwise reset an unrelated clock.
 *
 * TILE VS. NON-TILE ROWS: unlike the cascade trigger
 * (GtmOfferingArchiveCascadeHandler), which treats an offering's tile row
 * (Section_Key__c='tile', Template_Type__c='offerings-listing') as the
 * parent whose state drives its siblings, this batch does NOT special-case
 * tile vs. non-tile rows. Purge is a terminal delete, not a restore, so
 * there is no "parent still archived" hazard to protect against the way
 * GTM_RecycleBinController.restoreRecords() has to for restores -- a tile
 * row and its already-restored-or-still-archived siblings are each
 * independently eligible purely by their own Archived_Date__c. This is an
 * intentional design decision, not a dropped cascade.
 *
 * Mirrors GtmAssessmentDraftPurge's shape (with sharing, Batchable +
 * Schedulable, a named @TestVisible retention constant, allOrNone=false
 * delete, empty finish()) for consistency with the codebase's one other
 * purge job.
 *
 * ACTIVATION: shipping this class does not, by itself, make the purge run
 * on any cadence. See docs/architecture/offering-archive-cascade.md for the
 * manual one-time System.schedule(...) anonymous-Apex step a human must run
 * post-deploy in gtm-dev -- there is no CMDT-based auto-scheduling
 * mechanism in this codebase (same gap documented for GtmAssessmentDraftPurge
 * in docs/runbooks/questionnaire-resume.md).
 */
public with sharing class GTM_PurgeRecordsBatch implements Database.Batchable<SObject>, Schedulable {

    /** Days an archived row is kept before it becomes eligible for permanent
     *  deletion, keyed off Archived_Date__c. */
    @TestVisible
    private static final Integer PURGE_AFTER_DAYS = 30;

    /** Cron expression this job is scheduled on by GtmScheduledJobsController
     *  (issue #184-purge-batch-autoschedule), matching the manual-activation
     *  snippet this class's own header previously pointed admins to: daily
     *  at 4:00 AM. */
    @TestVisible
    private static final String CRON_EXPRESSION = '0 0 4 * * ?';

    /** CronTrigger job name GtmScheduledJobsController schedules/aborts this
     *  class under. */
    @TestVisible
    private static final String JOB_NAME = 'GTM Purge Records Batch';

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new GTM_PurgeRecordsBatch(), 200);
    }

    public List<SObject> start(Database.BatchableContext bc) {
        Datetime cutoff = System.now().addDays(-PURGE_AFTER_DAYS);

        List<SObject> scope = new List<SObject>();
        scope.addAll((List<SObject>) [
            SELECT Id
            FROM   GTM_Page_Section__c
            WHERE  Archived__c = true
            AND    Archived_Date__c < :cutoff
        ]);
        scope.addAll((List<SObject>) [
            SELECT Id
            FROM   GTM_Page_Content__c
            WHERE  Archived__c = true
            AND    Archived_Date__c < :cutoff
        ]);
        return scope;
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        // allOrNone false: one undeletable row (a lock, a validation rule)
        // must not strand the rest of the batch.
        Database.delete(scope, false);
    }

    public void finish(Database.BatchableContext bc) {
        // Nothing. A purge that emails a summary is a purge that eventually
        // emails a record id someone then goes and looks up.
    }
}
