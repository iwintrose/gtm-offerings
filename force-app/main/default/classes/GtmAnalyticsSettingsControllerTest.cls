/**
 * Coverage for GtmAnalyticsSettingsController, issue #147.
 */
@IsTest
private class GtmAnalyticsSettingsControllerTest {

    @IsTest
    static void getSettingsReturnsSafeDefaultsWhenNeverSaved() {
        Test.startTest();
        GtmAnalyticsSettingsController.Settings s = GtmAnalyticsSettingsController.getSettings();
        Test.stopTest();

        System.assertEquals(false, s.digestEnabled);
        System.assertEquals('MON', s.digestDayOfWeek);
        System.assertEquals(8, s.digestHour);
        System.assertEquals('Analytics email is off.', s.nextRunDescription);
    }

    @IsTest
    static void savingEnabledSchedulesTheDigestJob() {
        Test.startTest();
        GtmAnalyticsSettingsController.Settings s =
            GtmAnalyticsSettingsController.saveSettings(true, 'wed', 14);
        Test.stopTest();

        System.assertEquals(true, s.digestEnabled);
        System.assertEquals('WED', s.digestDayOfWeek, 'day is normalized to uppercase');
        System.assertEquals(14, s.digestHour);
        System.assert(s.nextRunDescription.contains('Wednesday'));
        System.assert(s.nextRunDescription.contains('2:00 PM'));

        List<CronTrigger> jobs = [
            SELECT Id, CronExpression FROM CronTrigger
            WHERE CronJobDetail.Name = :GtmAnalyticsSettingsController.DIGEST_JOB_NAME
        ];
        System.assertEquals(1, jobs.size());
        System.assertEquals('0 0 14 ? * WED', jobs[0].CronExpression);
    }

    @IsTest
    static void savingDisabledAbortsAnExistingSchedule() {
        Test.startTest();
        GtmAnalyticsSettingsController.saveSettings(true, 'MON', 8);
        GtmAnalyticsSettingsController.Settings s =
            GtmAnalyticsSettingsController.saveSettings(false, 'MON', 8);
        Test.stopTest();

        System.assertEquals(false, s.digestEnabled);
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :GtmAnalyticsSettingsController.DIGEST_JOB_NAME
        ];
        System.assertEquals(0, jobs.size(), 'disabling must abort the existing job, not leave it running');
    }

    @IsTest
    static void resavingWhileEnabledReplacesRatherThanDuplicatesTheSchedule() {
        Test.startTest();
        GtmAnalyticsSettingsController.saveSettings(true, 'MON', 8);
        GtmAnalyticsSettingsController.saveSettings(true, 'FRI', 17);
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id, CronExpression FROM CronTrigger
            WHERE CronJobDetail.Name = :GtmAnalyticsSettingsController.DIGEST_JOB_NAME
        ];
        System.assertEquals(1, jobs.size(), 'exactly one active schedule, not two');
        System.assertEquals('0 0 17 ? * FRI', jobs[0].CronExpression);
    }

    @IsTest
    static void rejectsAnInvalidDayOfWeek() {
        Test.startTest();
        Boolean threw = false;
        try {
            GtmAnalyticsSettingsController.saveSettings(true, 'FUNDAY', 8);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @IsTest
    static void rejectsAnInvalidHour() {
        Test.startTest();
        Boolean threw = false;
        try {
            GtmAnalyticsSettingsController.saveSettings(true, 'MON', 24);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }
}
