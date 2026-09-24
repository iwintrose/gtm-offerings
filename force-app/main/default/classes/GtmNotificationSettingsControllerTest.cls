@isTest
private class GtmNotificationSettingsControllerTest {

    @isTest
    static void defaultsToAllOffAndModeNoneWhenNeverConfigured() {
        Test.startTest();
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            GtmNotificationSettingsController.getOrgDefaults();
        Test.stopTest();

        Assert.isFalse(dto.notifyOnSubmitForApproval);
        Assert.isFalse(dto.autoCloseSubmitTasks);
        Assert.isFalse(dto.notifyOnApproved);
        Assert.isFalse(dto.autoCloseApprovedTasks);
        Assert.areEqual('None', dto.publishedNotificationMode);
        Assert.isFalse(dto.autoClosePublishedTasks);
        Assert.isFalse(dto.notifyOnNewAssessmentRequest);
        Assert.isFalse(dto.autoCloseNewRequestTasks);
        Assert.isFalse(dto.notifyOnReturnedToDraft);
    }

    @isTest
    static void setNotificationSettingsPersistsAllNineFields() {
        GtmNotificationSettingsController.NotificationSettingsDto input =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        input.notifyOnSubmitForApproval = true;
        input.autoCloseSubmitTasks = true;
        input.notifyOnApproved = true;
        input.autoCloseApprovedTasks = true;
        input.publishedNotificationMode = 'Bell + Task';
        input.autoClosePublishedTasks = true;
        input.notifyOnNewAssessmentRequest = true;
        input.autoCloseNewRequestTasks = true;
        input.notifyOnReturnedToDraft = true;

        Test.startTest();
        GtmNotificationSettingsController.setNotificationSettings(input);
        Test.stopTest();

        GtmNotificationSettingsController.NotificationSettingsDto dto =
            GtmNotificationSettingsController.getOrgDefaults();
        Assert.isTrue(dto.notifyOnSubmitForApproval);
        Assert.isTrue(dto.autoCloseSubmitTasks);
        Assert.isTrue(dto.notifyOnApproved);
        Assert.isTrue(dto.autoCloseApprovedTasks);
        Assert.areEqual('Bell + Task', dto.publishedNotificationMode);
        Assert.isTrue(dto.autoClosePublishedTasks);
        Assert.isTrue(dto.notifyOnNewAssessmentRequest);
        Assert.isTrue(dto.autoCloseNewRequestTasks);
        Assert.isTrue(dto.notifyOnReturnedToDraft);

        GTM_Notification_Settings__c settings = GTM_Notification_Settings__c.getOrgDefaults();
        Assert.areEqual('Bell + Task', settings.Published_Notification_Mode__c);
    }

    @isTest
    static void blankModeDefaultsToNoneOnSave() {
        GtmNotificationSettingsController.NotificationSettingsDto input =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        input.publishedNotificationMode = '';

        Test.startTest();
        GtmNotificationSettingsController.setNotificationSettings(input);
        Test.stopTest();

        Assert.areEqual('None', GTM_Notification_Settings__c.getOrgDefaults().Published_Notification_Mode__c);
    }

    @isTest
    static void invalidPublishedNotificationModeIsRejected() {
        GtmNotificationSettingsController.NotificationSettingsDto input =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        input.publishedNotificationMode = 'Loud Noise';

        Test.startTest();
        Boolean threw = false;
        try {
            GtmNotificationSettingsController.setNotificationSettings(input);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'An invalid publishedNotificationMode must be rejected');
        GTM_Notification_Settings__c settings = GTM_Notification_Settings__c.getOrgDefaults();
        Assert.isTrue(settings == null || String.isBlank(settings.Published_Notification_Mode__c),
            'Rejected before any DML');
    }

    @isTest
    static void nullInputSavesAllFalseAndModeNone() {
        Test.startTest();
        GtmNotificationSettingsController.setNotificationSettings(null);
        Test.stopTest();

        GtmNotificationSettingsController.NotificationSettingsDto dto =
            GtmNotificationSettingsController.getOrgDefaults();
        Assert.isFalse(dto.notifyOnSubmitForApproval);
        Assert.areEqual('None', dto.publishedNotificationMode);
    }
}
