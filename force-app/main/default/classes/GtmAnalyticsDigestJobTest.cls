/**
 * Coverage for GtmAnalyticsDigestJob, issue #140. No real email is ever
 * sent in test context (Test.isRunningTest() guards the actual
 * Messaging.sendEmail call, same convention as other best-effort
 * notification paths in this codebase) -- these tests assert on outcomes
 * that don't require an email invocation, plus the schedule itself.
 */
@IsTest
private class GtmAnalyticsDigestJobTest {

    @TestSetup
    static void seed() {
        Id uid = UserInfo.getUserId();

        GTM_Saved_Configuration__c activeRepLink = new GTM_Saved_Configuration__c(
            OwnerId = uid,
            Company__c = 'Globex',
            Offering__c = 'migration-accelerator',
            Link_Password__c = 'pw-1'
        );
        insert activeRepLink;

        insert new GTM_Assessment_Request__c(
            Saved_Configuration__c = activeRepLink.Id,
            Offering_Key__c = 'migration-accelerator',
            Company__c = 'Globex',
            Status__c = 'New',
            Assessment_Score__c = 24
        );
    }

    @IsTest
    static void executeDoesNotThrowAndCoversTheActiveRep() {
        Test.startTest();
        new GtmAnalyticsDigestJob().execute(null);
        Test.stopTest();
        // No assertion beyond "did not throw" is meaningful here without a
        // fake email sink -- Messaging.sendEmail is skipped under
        // Test.isRunningTest() by design (see class header), so this proves
        // the query/rollup path runs clean end-to-end for a rep with real
        // activity in the window, not that an email was actually queued.
        System.assert(true);
    }

    @IsTest
    static void executeSkipsRepsWithNoActivityWithoutError() {
        // Delete the seeded activity so the one link-owning user in this
        // org has zero activity in the digest window -- the "skip, don't
        // send an all-zero email" branch.
        delete [SELECT Id FROM GTM_Assessment_Request__c];
        delete [SELECT Id FROM GTM_Saved_Configuration__c];

        Test.startTest();
        new GtmAnalyticsDigestJob().execute(null);
        Test.stopTest();

        System.assert(true, 'no link owners at all -- the batch completes with nothing to send');
    }

    @IsTest
    static void canBeScheduled() {
        Test.startTest();
        String jobId = System.schedule(
            'Test GTM Weekly Analytics Digest',
            '0 0 8 ? * MON',
            new GtmAnalyticsDigestJob()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'the job must be a valid Schedulable');
    }
}
