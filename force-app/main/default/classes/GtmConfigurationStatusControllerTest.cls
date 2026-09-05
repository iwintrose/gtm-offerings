@IsTest
private class MaConfigurationStatusControllerTest {
    @IsTest
    static void activeRecordReturnsTrue() {
        MA_Saved_Configuration__c rec = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator',
            Active__c = true
        );
        insert rec;

        System.assertEquals(true, MaConfigurationStatusController.isActive(rec.Id));
    }

    @IsTest
    static void inactiveRecordReturnsFalse() {
        MA_Saved_Configuration__c rec = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator',
            Active__c = false
        );
        insert rec;

        System.assertEquals(false, MaConfigurationStatusController.isActive(rec.Id));
    }

    @IsTest
    static void blankIdIsTreatedAsActive() {
        System.assertEquals(true, MaConfigurationStatusController.isActive(null));
        System.assertEquals(true, MaConfigurationStatusController.isActive(''));
    }

    @IsTest
    static void malformedIdIsTreatedAsActive() {
        System.assertEquals(true, MaConfigurationStatusController.isActive('not-a-real-id'));
    }

    @IsTest
    static void nonexistentRecordReturnsFalse() {
        MA_Saved_Configuration__c rec = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert rec;
        Id deletedId = rec.Id;
        delete rec;

        System.assertEquals(false, MaConfigurationStatusController.isActive(deletedId));
    }
}
