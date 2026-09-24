/**
 * Admin-only accessor for GTM_Notification_Settings__c, backing the
 * "Notifications" section of the GTM_Offerings_Settings tab /
 * gtmOfferingsSettingsNotifications LWC (ADR-0010 Unit 3).
 *
 * Parallel in shape to GtmReadoutApprovalSettingsController /
 * GtmAgentSettingsController: org-default row only, admin-gated
 * getOrgDefaults()/upsert pair, no row-level access model beyond
 * object-level FLS.
 *
 * All seven lifecycle wiring points (Unit 3b: GtmReadoutController.
 * submitForApproval / recallApproval / publishReadout / returnToDraft,
 * GtmReadoutApprovalHandler.stampApproval, and
 * GtmAssessmentRequestController.postInsertBestEffort's new-request path)
 * read the setting through getOrgDefaults() below rather than querying
 * GTM_Notification_Settings__c directly, so null-handling/defaulting logic
 * lives in exactly one place.
 *
 * `with sharing`: internal admin config surface; the Custom Setting itself
 * has no row-level sharing to enforce.
 */
public with sharing class GtmNotificationSettingsController {

    private static final Set<String> VALID_PUBLISHED_MODES =
        new Set<String>{ 'None', 'Bell Only', 'Bell + Task' };

    public static final String MODE_NONE = 'None';
    public static final String MODE_BELL_ONLY = 'Bell Only';
    public static final String MODE_BELL_AND_TASK = 'Bell + Task';

    public class NotificationSettingsDto {
        @AuraEnabled public Boolean notifyOnSubmitForApproval;
        @AuraEnabled public Boolean autoCloseSubmitTasks;
        @AuraEnabled public Boolean notifyOnApproved;
        @AuraEnabled public Boolean autoCloseApprovedTasks;
        @AuraEnabled public String publishedNotificationMode;
        @AuraEnabled public Boolean autoClosePublishedTasks;
        @AuraEnabled public Boolean notifyOnNewAssessmentRequest;
        @AuraEnabled public Boolean autoCloseNewRequestTasks;
        @AuraEnabled public Boolean notifyOnReturnedToDraft;
    }

    /**
     * Read-through helper used by both the LWC (@AuraEnabled) and by every
     * Apex lifecycle wiring point (plain static call -- no Apex-class-access
     * check needed there since it's an internal server-side call, not a
     * client one). Never returns null: an unconfigured org defaults every
     * checkbox to false and the mode to 'None', which is exactly today's
     * hardcoded pre-Unit-3 behavior (nothing fires), so shipping this object
     * with an empty org-default row is a safe, silent no-op.
     */
    @AuraEnabled(cacheable=true)
    public static NotificationSettingsDto getOrgDefaults() {
        GTM_Notification_Settings__c settings = GTM_Notification_Settings__c.getOrgDefaults();
        NotificationSettingsDto dto = new NotificationSettingsDto();
        dto.notifyOnSubmitForApproval = settings != null && settings.Notify_On_Submit_For_Approval__c;
        dto.autoCloseSubmitTasks = settings != null && settings.Auto_Close_Submit_Tasks__c;
        dto.notifyOnApproved = settings != null && settings.Notify_On_Approved__c;
        dto.autoCloseApprovedTasks = settings != null && settings.Auto_Close_Approved_Tasks__c;
        dto.publishedNotificationMode = (settings != null && String.isNotBlank(settings.Published_Notification_Mode__c))
            ? settings.Published_Notification_Mode__c
            : MODE_NONE;
        dto.autoClosePublishedTasks = settings != null && settings.Auto_Close_Published_Tasks__c;
        dto.notifyOnNewAssessmentRequest = settings != null && settings.Notify_On_New_Assessment_Request__c;
        dto.autoCloseNewRequestTasks = settings != null && settings.Auto_Close_New_Request_Tasks__c;
        dto.notifyOnReturnedToDraft = settings != null && settings.Notify_On_Returned_To_Draft__c;
        return dto;
    }

    /**
     * Writes the org default row (Id == null on the Hierarchy setting's
     * org-wide row), same "change it for everyone" semantics as
     * GtmAgentSettingsController.setAgentSettings.
     */
    @AuraEnabled
    public static void setNotificationSettings(NotificationSettingsDto input) {
        if (input == null) {
            input = new NotificationSettingsDto();
        }
        String mode = input.publishedNotificationMode;
        if (String.isNotBlank(mode) && !VALID_PUBLISHED_MODES.contains(mode)) {
            throw new AuraHandledException('Invalid publishedNotificationMode "' + mode
                + '" -- must be "None", "Bell Only" or "Bell + Task".');
        }

        GTM_Notification_Settings__c settings = GTM_Notification_Settings__c.getOrgDefaults();
        if (settings == null || settings.Id == null) {
            settings = new GTM_Notification_Settings__c();
        }
        settings.Notify_On_Submit_For_Approval__c = input.notifyOnSubmitForApproval == true;
        settings.Auto_Close_Submit_Tasks__c = input.autoCloseSubmitTasks == true;
        settings.Notify_On_Approved__c = input.notifyOnApproved == true;
        settings.Auto_Close_Approved_Tasks__c = input.autoCloseApprovedTasks == true;
        settings.Published_Notification_Mode__c = String.isBlank(mode) ? MODE_NONE : mode;
        settings.Auto_Close_Published_Tasks__c = input.autoClosePublishedTasks == true;
        settings.Notify_On_New_Assessment_Request__c = input.notifyOnNewAssessmentRequest == true;
        settings.Auto_Close_New_Request_Tasks__c = input.autoCloseNewRequestTasks == true;
        settings.Notify_On_Returned_To_Draft__c = input.notifyOnReturnedToDraft == true;
        upsert settings;
    }
}
