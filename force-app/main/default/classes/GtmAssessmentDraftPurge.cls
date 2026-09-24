/**
 * Deletes expired and long-submitted questionnaire drafts.
 *
 * WHY A JOB AT ALL, when expiry is already enforced in the WHERE clause of
 * every read. Because "unreachable" and "gone" are different things, and only
 * one of them is a retention story. An expired draft that is merely
 * unresolvable still holds a stranger's half-finished answers -- including
 * whatever contact details they had typed before they walked away -- in a table
 * any internal user with the object permission could query. The token stops
 * working on time whether or not this job runs; this job is what makes the data
 * stop existing.
 *
 * SCOPED TO Draft_Type__c = 'Assessment'. GTM_Form_Draft__c also holds the
 * Booking population (GtmFormDraftController), which has no expiry model at
 * all and is intentionally left untouched here -- see the class's own
 * comment for why (append-only, unbounded by design, a separate retention
 * decision for the product owner if one is ever wanted).
 *
 * WHAT IT DELETES:
 *   - any row past its own Expires_At__c, whatever its Status__c. Every row
 *     appended for one questionnaire session carries the SAME (original)
 *     Expires_At__c -- see GtmAssessmentDraftController -- so this alone
 *     removes every row for a session once the session's link has expired.
 *   - EVERY row belonging to a token whose most recent (terminal) row is
 *     Submitted and older than SUBMITTED_GRACE_DAYS. Only the terminal row
 *     GtmAssessmentRequestController.closeDraft appends carries
 *     Status__c = 'Submitted'; the session's earlier save rows do not, and
 *     would otherwise sit until the full TTL. This two-query start() finds
 *     those tokens first so the whole session -- not just its terminal row --
 *     goes at grace, giving a submitted session the fast cleanup path the
 *     un-appended design had.
 *
 * Schedule it daily. See docs/runbooks/questionnaire-resume.md.
 */
public with sharing class GtmAssessmentDraftPurge implements Database.Batchable<SObject>, Schedulable {

    /** Days a submitted session's rows are kept after the terminal (closeDraft)
     *  row was created. */
    @TestVisible
    private static final Integer SUBMITTED_GRACE_DAYS = 7;

    /** Cron expression this job is scheduled on by GtmScheduledJobsController
     *  (issue #184-purge-batch-autoschedule), matching the manual
     *  anonymous-Apex snippet in docs/runbooks/questionnaire-resume.md:
     *  daily at 3:00 AM. */
    @TestVisible
    private static final String CRON_EXPRESSION = '0 0 3 * * ?';

    /** CronTrigger job name GtmScheduledJobsController schedules/aborts this
     *  class under, matching the name used in the runbook's manual
     *  System.schedule(...) snippet. */
    @TestVisible
    private static final String JOB_NAME = 'MA Assessment Draft Purge';

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new GtmAssessmentDraftPurge(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime now    = System.now();
        Datetime cutoff = now.addDays(-SUBMITTED_GRACE_DAYS);

        // Tokens whose terminal row is Submitted and past grace -- every row
        // for these tokens is purged, not just the terminal one. Selecting
        // just the token, never Draft_JSON__c: this job has no business
        // reading prospect answers, and a query that does not select the
        // field cannot accidentally log it.
        Set<String> submittedTokensPastGrace = new Set<String>();
        for (GTM_Form_Draft__c row : [
            SELECT Resume_Token__c
            FROM GTM_Form_Draft__c
            WHERE Draft_Type__c = 'Assessment'
            AND Status__c = 'Submitted'
            AND Submitted_Request__c != null
            AND LastModifiedDate < :cutoff
        ]) {
            if (String.isNotBlank(row.Resume_Token__c)) {
                submittedTokensPastGrace.add(row.Resume_Token__c);
            }
        }

        // Selecting Id only: this job has no business reading Draft_JSON__c,
        // and a query that does not select it cannot accidentally log it.
        return Database.getQueryLocator([
            SELECT Id
            FROM GTM_Form_Draft__c
            WHERE Draft_Type__c = 'Assessment'
            AND (Expires_At__c < :now
                 OR Resume_Token__c IN :submittedTokensPastGrace)
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        // allOrNone false: one undeletable row (a lock, a future validation
        // rule) must not strand the rest of the batch. Failures are counted,
        // not logged with their record's contents.
        Database.delete(scope, false);
    }

    public void finish(Database.BatchableContext bc) {
        // Nothing. A purge that emails a summary is a purge that eventually
        // emails a record id someone then goes and looks up.
    }
}
