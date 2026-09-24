/**
 * Coverage for GtmScheduledJobsController, issue #184-purge-batch-autoschedule.
 */
@IsTest
private class GtmScheduledJobsControllerTest {

    @IsTest
    static void getStatusesReportsBothJobsUnscheduledByDefault() {
        Test.startTest();
        List<GtmScheduledJobsController.JobStatus> statuses = GtmScheduledJobsController.getStatuses();
        Test.stopTest();

        System.assertEquals(2, statuses.size());
        for (GtmScheduledJobsController.JobStatus s : statuses) {
            System.assertEquals(false, s.isScheduled);
            System.assertEquals('Not scheduled.', s.nextRunDescription);
        }
    }

    @IsTest
    static void schedulingPurgeRecordsBatchIsReflectedInStatus() {
        Test.startTest();
        GtmScheduledJobsController.JobStatus scheduled =
            GtmScheduledJobsController.scheduleJob('purgeRecordsBatch');
        Test.stopTest();

        System.assertEquals(true, scheduled.isScheduled);
        System.assert(scheduled.nextRunDescription.startsWith('Next run:'));

        List<CronTrigger> jobs = [
            SELECT Id, CronExpression FROM CronTrigger
            WHERE CronJobDetail.Name = 'GTM Purge Records Batch'
        ];
        System.assertEquals(1, jobs.size());
        System.assertEquals('0 0 4 * * ?', jobs[0].CronExpression);

        List<GtmScheduledJobsController.JobStatus> statuses = GtmScheduledJobsController.getStatuses();
        Boolean found = false;
        for (GtmScheduledJobsController.JobStatus s : statuses) {
            if (s.jobKey == 'purgeRecordsBatch') {
                found = true;
                System.assertEquals(true, s.isScheduled);
            }
        }
        System.assert(found);
    }

    @IsTest
    static void schedulingAssessmentDraftPurgeIsReflectedInStatus() {
        // An expired draft row so the scheduled batch actually has scope to
        // execute over once Test.stopTest() runs it synchronously -- this
        // is what exercises GtmAssessmentDraftPurge.execute()/finish(), not
        // just start(), giving this controller's own coverage a genuine
        // end-to-end run of the job it schedules (not a logic change to
        // GtmAssessmentDraftPurge itself).
        insert new GTM_Form_Draft__c(
            Draft_Type__c    = 'Assessment',
            Resume_Token__c  = 'expired-token-for-purge-coverage',
            Draft_JSON__c    = '{}',
            Status__c        = 'Open',
            Expires_At__c    = System.now().addDays(-1),
            Last_Saved_At__c = System.now()
        );

        Test.startTest();
        GtmScheduledJobsController.JobStatus scheduled =
            GtmScheduledJobsController.scheduleJob('assessmentDraftPurge');
        Test.stopTest();

        System.assertEquals(true, scheduled.isScheduled);

        List<CronTrigger> jobs = [
            SELECT Id, CronExpression FROM CronTrigger
            WHERE CronJobDetail.Name = 'MA Assessment Draft Purge'
        ];
        System.assertEquals(1, jobs.size());
        System.assertEquals('0 0 3 * * ?', jobs[0].CronExpression);
    }

    @IsTest
    static void reschedulingIsIdempotentAndDoesNotDuplicateTheTrigger() {
        Test.startTest();
        GtmScheduledJobsController.scheduleJob('purgeRecordsBatch');
        GtmScheduledJobsController.scheduleJob('purgeRecordsBatch');
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = 'GTM Purge Records Batch'
        ];
        System.assertEquals(1, jobs.size(), 'exactly one active schedule, not two, after re-scheduling');
    }

    @IsTest
    static void reschedulingBothJobsIndependentlyIsAlsoIdempotent() {
        Test.startTest();
        GtmScheduledJobsController.scheduleJob('purgeRecordsBatch');
        GtmScheduledJobsController.scheduleJob('assessmentDraftPurge');
        GtmScheduledJobsController.scheduleJob('purgeRecordsBatch');
        GtmScheduledJobsController.scheduleJob('assessmentDraftPurge');
        Test.stopTest();

        System.assertEquals(1, [
            SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = 'GTM Purge Records Batch'
        ]);
        System.assertEquals(1, [
            SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = 'MA Assessment Draft Purge'
        ]);
    }

    @IsTest
    static void unknownJobKeyThrows() {
        Test.startTest();
        Boolean threw = false;
        try {
            GtmScheduledJobsController.scheduleJob('notARealJob');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }
}
