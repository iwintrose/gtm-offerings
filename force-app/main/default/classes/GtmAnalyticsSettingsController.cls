/**
 * Backs the admin-only "Settings" tab's Analytics Notifications section
 * (issue #147). Currently one tenant: the weekly Analytics email
 * (GtmAnalyticsDigestJob, issue #140).
 *
 * This is the one class in the Analytics family that legitimately has
 * side effects -- every other controller here (GtmAnalyticsController,
 * GtmAnalyticsTeamController) is deliberately read-only reporting. This
 * one exists specifically so an admin's own click on Save is what
 * schedules or aborts GtmAnalyticsDigestJob, rather than an agent or a
 * deploy step doing that unilaterally -- see TASK_SCOPE.md for issue #147
 * for why that boundary matters here.
 *
 * `with sharing`, but a Hierarchy Custom Setting's org-default row is
 * writable by design through this controller regardless of the running
 * user's own record-level sharing -- that is what "org default" means for
 * a Custom Setting, not a sharing bypass this class introduces.
 */
public with sharing class GtmAnalyticsSettingsController {

    /** The single scheduled-job name this controller ever creates or aborts. */
    @TestVisible
    private static final String DIGEST_JOB_NAME = 'GTM Weekly Analytics Digest';

    private static final Set<String> VALID_DAYS =
        new Set<String>{ 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN' };

    @AuraEnabled(cacheable=true)
    public static Settings getSettings() {
        GTM_Analytics_Settings__c row = GTM_Analytics_Settings__c.getOrgDefaults();

        Settings out = new Settings();
        out.digestEnabled = row.Notify_Weekly_Digest__c == true;
        out.digestDayOfWeek = String.isNotBlank(row.Digest_Day_Of_Week__c) ? row.Digest_Day_Of_Week__c : 'MON';
        out.digestHour = row.Digest_Hour__c != null ? Integer.valueOf(row.Digest_Hour__c) : 8;
        out.nextRunDescription = describeNextRun(out);
        return out;
    }

    /**
     * Saves the toggle/day/hour, then makes the schedule match it:
     * aborts any existing DIGEST_JOB_NAME CronTrigger, and if `enabled`,
     * schedules a fresh one at the chosen day/hour. Re-saving while
     * already enabled still aborts-then-reschedules, so a day/hour change
     * takes effect immediately rather than waiting for the old trigger to
     * fire once more on the stale schedule.
     */
    @AuraEnabled
    public static Settings saveSettings(Boolean enabled, String dayOfWeek, Integer hour) {
        String day = validateDayOfWeek(dayOfWeek);
        Integer validHour = validateHour(hour);

        GTM_Analytics_Settings__c row = GTM_Analytics_Settings__c.getOrgDefaults();
        if (row.Id == null) {
            row = new GTM_Analytics_Settings__c();
        }
        row.Notify_Weekly_Digest__c = enabled == true;
        row.Digest_Day_Of_Week__c = day;
        row.Digest_Hour__c = validHour;
        upsert row;

        abortExistingDigestJob();
        if (enabled == true) {
            String cron = '0 0 ' + validHour + ' ? * ' + day;
            System.schedule(DIGEST_JOB_NAME, cron, new GtmAnalyticsDigestJob());
        }

        return getSettings();
    }

    private static String validateDayOfWeek(String dayOfWeek) {
        String day = String.isBlank(dayOfWeek) ? '' : dayOfWeek.trim().toUpperCase();
        if (!VALID_DAYS.contains(day)) {
            throw new AuraHandledException(
                'Day must be one of MON, TUE, WED, THU, FRI, SAT, SUN.'
            );
        }
        return day;
    }

    private static Integer validateHour(Integer hour) {
        if (hour == null || hour < 0 || hour > 23) {
            throw new AuraHandledException('Hour must be between 0 and 23.');
        }
        return hour;
    }

    /** Aborts the existing digest CronTrigger, if one is currently scheduled. Idempotent. */
    private static void abortExistingDigestJob() {
        List<CronTrigger> existing = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :DIGEST_JOB_NAME
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            System.abortJob(existing[0].Id);
        }
    }

    private static String describeNextRun(Settings s) {
        if (s.digestEnabled != true) {
            return 'Analytics email is off.';
        }
        return 'Weekly on ' + dayLabel(s.digestDayOfWeek) + ' at ' + hourLabel(s.digestHour) + ' (org time zone).';
    }

    private static String dayLabel(String day) {
        Map<String, String> labels = new Map<String, String>{
            'MON' => 'Monday', 'TUE' => 'Tuesday', 'WED' => 'Wednesday', 'THU' => 'Thursday',
            'FRI' => 'Friday', 'SAT' => 'Saturday', 'SUN' => 'Sunday'
        };
        return labels.containsKey(day) ? labels.get(day) : day;
    }

    private static String hourLabel(Integer hour) {
        Integer h = hour == null ? 8 : hour;
        String suffix = h < 12 ? 'AM' : 'PM';
        Integer display = Math.mod(h, 12) == 0 ? 12 : Math.mod(h, 12);
        return display + ':00 ' + suffix;
    }

    public class Settings {
        @AuraEnabled public Boolean digestEnabled;
        @AuraEnabled public String digestDayOfWeek;
        @AuraEnabled public Integer digestHour;
        @AuraEnabled public String nextRunDescription;
    }
}
