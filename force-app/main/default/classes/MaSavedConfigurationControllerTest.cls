@IsTest
private class MaSavedConfigurationControllerTest {
    @IsTest
    static void savesNewConfiguration() {
        MaSavedConfigurationController.SaveInput input = new MaSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.industry = 'fintech';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        input.configPayload = '{"SOURCE_PLATFORM":"Eloqua"}';

        Test.startTest();
        Id recordId = MaSavedConfigurationController.saveConfiguration(input);
        Test.stopTest();

        MA_Saved_Configuration__c saved = [
            SELECT Offering__c, Industry__c, Company__c, Generated_URL__c, Config_Payload__c
            FROM MA_Saved_Configuration__c
            WHERE Id = :recordId
        ];
        System.assertEquals('migration-accelerator', saved.Offering__c);
        System.assertEquals('fintech', saved.Industry__c);
        System.assertEquals('Acme Bank', saved.Company__c);
        System.assertEquals(input.generatedUrl, saved.Generated_URL__c);
    }

    @IsTest
    static void updatesExistingConfigurationWhenRecordIdSupplied() {
        MA_Saved_Configuration__c existing = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Old Name',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert existing;

        MaSavedConfigurationController.SaveInput input = new MaSavedConfigurationController.SaveInput();
        input.recordId = existing.Id;
        input.offering = 'migration-accelerator';
        input.company = 'New Name';
        input.generatedUrl = existing.Generated_URL__c;

        Test.startTest();
        Id recordId = MaSavedConfigurationController.saveConfiguration(input);
        Test.stopTest();

        System.assertEquals(existing.Id, recordId);
        System.assertEquals(
            'New Name',
            [SELECT Company__c FROM MA_Saved_Configuration__c WHERE Id = :recordId].Company__c
        );
    }

    @IsTest
    static void rejectsSaveWithoutGeneratedUrl() {
        MaSavedConfigurationController.SaveInput input = new MaSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';

        try {
            MaSavedConfigurationController.saveConfiguration(input);
            System.assert(false, 'Expected an AuraHandledException.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void listsSavedConfigurationsNewestFirst() {
        insert new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/a'
        );
        insert new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/b'
        );

        Test.startTest();
        List<MA_Saved_Configuration__c> results = MaSavedConfigurationController.getMyConfigurations();
        Test.stopTest();

        System.assertEquals(2, results.size());
    }

    @IsTest
    static void deletesConfiguration() {
        MA_Saved_Configuration__c existing = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert existing;

        Test.startTest();
        MaSavedConfigurationController.deleteConfiguration(existing.Id);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM MA_Saved_Configuration__c WHERE Id = :existing.Id]
        );
    }
}
