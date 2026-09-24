@isTest
private class GtmReadoutApprovalSettingsControllerTest {

    @isTest
    static void defaultsToDisabledWhenNeverConfigured() {
        Test.startTest();
        Boolean enabled = GtmReadoutApprovalSettingsController.getSelfApprovalEnabled();
        Test.stopTest();

        Assert.isFalse(enabled, 'Manager-approval mode is the default until an admin turns this on');
    }

    @isTest
    static void setSelfApprovalEnabledPersistsTheOrgDefault() {
        Test.startTest();
        GtmReadoutApprovalSettingsController.setSelfApprovalEnabled(true);
        Boolean enabled = GtmReadoutApprovalSettingsController.getSelfApprovalEnabled();
        Test.stopTest();

        Assert.isTrue(enabled, 'The toggle should read back true after being set');
    }

    @isTest
    static void setSelfApprovalEnabledCanBeToggledBackOff() {
        GtmReadoutApprovalSettingsController.setSelfApprovalEnabled(true);

        Test.startTest();
        GtmReadoutApprovalSettingsController.setSelfApprovalEnabled(false);
        Boolean enabled = GtmReadoutApprovalSettingsController.getSelfApprovalEnabled();
        Test.stopTest();

        Assert.isFalse(enabled, 'The toggle must be able to flip back to manager mode');
    }
}
