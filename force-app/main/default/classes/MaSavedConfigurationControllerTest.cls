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

    @IsTest
    static void togglesActiveWithoutDeletingOrHiding() {
        MA_Saved_Configuration__c existing = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert existing;

        Test.startTest();
        MaSavedConfigurationController.setActive(existing.Id, false);
        Test.stopTest();

        MA_Saved_Configuration__c updated = [
            SELECT Active__c FROM MA_Saved_Configuration__c WHERE Id = :existing.Id
        ];
        System.assertEquals(false, updated.Active__c);
        System.assertEquals(1, MaSavedConfigurationController.getMyConfigurations().size());
    }

    @IsTest
    static void savingResolvesAccountAndContactAutomatically() {
        MaSavedConfigurationController.SaveInput input = new MaSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.industry = 'fintech';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        input.clientContactName = 'Jordan Lee';
        input.clientContactEmail = 'jordan.lee@acmebank.example.com';
        input.estimatedValue = '$120,000';

        Test.startTest();
        Id recordId = MaSavedConfigurationController.saveConfiguration(input);
        Test.stopTest();

        MA_Saved_Configuration__c saved = [
            SELECT Account__c, Contact__c, Estimated_Value__c,
                   Account__r.Name, Contact__r.FirstName, Contact__r.LastName, Contact__r.Email
            FROM MA_Saved_Configuration__c
            WHERE Id = :recordId
        ];
        Assert.isNotNull(saved.Account__c, 'An Account should be created from the company name');
        Assert.areEqual('Acme Bank', saved.Account__r.Name);
        Assert.isNotNull(saved.Contact__c, 'A Contact should be created from the client contact fields');
        Assert.areEqual('Jordan', saved.Contact__r.FirstName);
        Assert.areEqual('Lee', saved.Contact__r.LastName);
        Assert.areEqual('jordan.lee@acmebank.example.com', saved.Contact__r.Email);
        Assert.areEqual(120000, saved.Estimated_Value__c);
    }

    @IsTest
    static void savingReusesExistingAccountByExactNameMatch() {
        Account existing = new Account(Name = 'Acme Bank');
        insert existing;

        MaSavedConfigurationController.SaveInput input = new MaSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';

        Test.startTest();
        Id recordId = MaSavedConfigurationController.saveConfiguration(input);
        Test.stopTest();

        MA_Saved_Configuration__c saved = [
            SELECT Account__c FROM MA_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.areEqual(existing.Id, saved.Account__c, 'Should reuse the existing Account, not duplicate it');
        Assert.areEqual(1, [SELECT COUNT() FROM Account WHERE Name = 'Acme Bank']);
    }

    @IsTest
    static void savingWithoutClientContactEmailLeavesContactBlank() {
        MaSavedConfigurationController.SaveInput input = new MaSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';

        Test.startTest();
        Id recordId = MaSavedConfigurationController.saveConfiguration(input);
        Test.stopTest();

        MA_Saved_Configuration__c saved = [
            SELECT Contact__c FROM MA_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.isNull(saved.Contact__c, 'No email means no Contact should be guessed at');
    }

    @IsTest
    static void resavingWithBlankContactAndValueDoesNotWipeThemOut() {
        MaSavedConfigurationController.SaveInput first = new MaSavedConfigurationController.SaveInput();
        first.offering = 'migration-accelerator';
        first.company = 'Acme Bank';
        first.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        first.clientContactName = 'Jordan Lee';
        first.clientContactEmail = 'jordan.lee@acmebank.example.com';
        first.estimatedValue = '90000';
        Id recordId = MaSavedConfigurationController.saveConfiguration(first);

        // Simulates reopening this link for editing: the Customize panel
        // doesn't reload Contact/Estimated Value from the record, so a
        // resave sends them blank unless the rep retypes them.
        MaSavedConfigurationController.SaveInput second = new MaSavedConfigurationController.SaveInput();
        second.recordId = recordId;
        second.offering = 'migration-accelerator';
        second.company = 'Acme Bank';
        second.generatedUrl = first.generatedUrl;

        Test.startTest();
        MaSavedConfigurationController.saveConfiguration(second);
        Test.stopTest();

        MA_Saved_Configuration__c saved = [
            SELECT Contact__c, Estimated_Value__c FROM MA_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.isNotNull(saved.Contact__c, 'A blank resend should not wipe out the Contact set on the first save');
        Assert.areEqual(90000, saved.Estimated_Value__c, 'A blank resend should not wipe out the Estimated Value');
    }

    @IsTest
    static void wrapsDmlFailureOnSaveAsFriendlyError() {
        MA_Saved_Configuration__c existing = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert existing;
        Id staleId = existing.Id;
        delete existing;

        MaSavedConfigurationController.SaveInput input = new MaSavedConfigurationController.SaveInput();
        input.recordId = staleId;
        input.offering = 'migration-accelerator';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator';

        try {
            MaSavedConfigurationController.saveConfiguration(input);
            System.assert(false, 'Expected an AuraHandledException, not a raw DmlException.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void wrapsDmlFailureOnDeleteAsFriendlyError() {
        MA_Saved_Configuration__c existing = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert existing;
        Id staleId = existing.Id;
        delete existing;

        try {
            MaSavedConfigurationController.deleteConfiguration(staleId);
            System.assert(false, 'Expected an AuraHandledException, not a raw DmlException.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void wrapsDmlFailureOnSetActiveAsFriendlyError() {
        MA_Saved_Configuration__c existing = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert existing;
        Id staleId = existing.Id;
        delete existing;

        try {
            MaSavedConfigurationController.setActive(staleId, false);
            System.assert(false, 'Expected an AuraHandledException, not a raw DmlException.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
