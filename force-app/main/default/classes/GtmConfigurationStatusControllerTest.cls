@IsTest
private class GtmConfigurationStatusControllerTest {
    @IsTest
    static void activeRecordReturnsTrue() {
        GTM_Saved_Configuration__c rec = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator',
            Active__c = true
        );
        insert rec;

        System.assertEquals(true, GtmConfigurationStatusController.isActive(rec.Id));
    }

    @IsTest
    static void inactiveRecordReturnsFalse() {
        GTM_Saved_Configuration__c rec = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator',
            Active__c = false
        );
        insert rec;

        System.assertEquals(false, GtmConfigurationStatusController.isActive(rec.Id));
    }

    @IsTest
    static void blankIdIsTreatedAsActive() {
        System.assertEquals(true, GtmConfigurationStatusController.isActive(null));
        System.assertEquals(true, GtmConfigurationStatusController.isActive(''));
    }

    @IsTest
    static void malformedIdIsTreatedAsInactive() {
        // Folded into the same "false" case as a nonexistent record now that
        // GtmLegacyConfigId.resolve() can't tell "malformed" apart from "a
        // legacy id with no mapping" -- fail closed is the safer default for
        // either. See the comment on GtmConfigurationStatusController.isActive.
        System.assertEquals(false, GtmConfigurationStatusController.isActive('not-a-real-id'));
    }

    @IsTest
    static void nonexistentRecordReturnsFalse() {
        GTM_Saved_Configuration__c rec = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert rec;
        Id deletedId = rec.Id;
        delete rec;

        System.assertEquals(false, GtmConfigurationStatusController.isActive(deletedId));
    }
}
