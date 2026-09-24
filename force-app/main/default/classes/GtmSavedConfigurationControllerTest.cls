@IsTest
private class GtmSavedConfigurationControllerTest {
    @IsTest
    static void savesNewConfiguration() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.industry = 'fintech';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        input.configPayload = '{"SOURCE_PLATFORM":"Eloqua"}';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Offering__c, Industry__c, Company__c, Generated_URL__c, Config_Payload__c
            FROM GTM_Saved_Configuration__c
            WHERE Id = :recordId
        ];
        System.assertEquals('migration-accelerator', saved.Offering__c);
        System.assertEquals('fintech', saved.Industry__c);
        System.assertEquals('Acme Bank', saved.Company__c);
        System.assertEquals(input.generatedUrl, saved.Generated_URL__c);
    }

    @IsTest
    static void updatesExistingConfigurationWhenRecordIdSupplied() {
        GTM_Saved_Configuration__c existing = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Old Name',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert existing;

        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.recordId = existing.Id;
        input.offering = 'migration-accelerator';
        input.company = 'New Name';
        input.generatedUrl = existing.Generated_URL__c;

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        System.assertEquals(existing.Id, recordId);
        System.assertEquals(
            'New Name',
            [SELECT Company__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId].Company__c
        );
    }

    @IsTest
    static void rejectsSaveWithoutGeneratedUrl() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';

        try {
            GtmSavedConfigurationController.saveConfiguration(input);
            System.assert(false, 'Expected an AuraHandledException.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void listsSavedConfigurationsNewestFirst() {
        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/a',
            Presentation_Stage__c = 'Sent'
        );
        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/b',
            Presentation_Stage__c = 'Sent'
        );

        Test.startTest();
        List<GTM_Saved_Configuration__c> results = GtmSavedConfigurationController.getMyConfigurations();
        Test.stopTest();

        System.assertEquals(2, results.size());
    }

    @IsTest
    static void returnsMoreThan200Links() {
        List<GTM_Saved_Configuration__c> manyLinks = new List<GTM_Saved_Configuration__c>();
        for (Integer i = 0; i < 205; i++) {
            manyLinks.add(new GTM_Saved_Configuration__c(
                Offering__c = 'migration-accelerator',
                Generated_URL__c = 'https://example.my.site.com/bulk' + i,
                Presentation_Stage__c = 'Sent'
            ));
        }
        insert manyLinks;

        Test.startTest();
        List<GTM_Saved_Configuration__c> results = GtmSavedConfigurationController.getMyConfigurations();
        Test.stopTest();

        System.assertEquals(205, results.size(), 'no LIMIT 200 cap on the Pages grid');
    }

    @IsTest
    static void deletesConfiguration() {
        GTM_Saved_Configuration__c existing = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert existing;

        Test.startTest();
        GtmSavedConfigurationController.deleteConfiguration(existing.Id);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM GTM_Saved_Configuration__c WHERE Id = :existing.Id]
        );
    }

    @IsTest
    static void togglesActiveWithoutDeletingOrHiding() {
        GTM_Saved_Configuration__c existing = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator',
            Presentation_Stage__c = 'Sent'
        );
        insert existing;

        Test.startTest();
        GtmSavedConfigurationController.setActive(existing.Id, false);
        Test.stopTest();

        GTM_Saved_Configuration__c updated = [
            SELECT Active__c FROM GTM_Saved_Configuration__c WHERE Id = :existing.Id
        ];
        System.assertEquals(false, updated.Active__c);
        System.assertEquals(1, GtmSavedConfigurationController.getMyConfigurations().size());
    }

    @IsTest
    static void savingResolvesAccountAndContactAutomatically() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.industry = 'fintech';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        input.clientContactName = 'Jordan Lee';
        input.clientContactEmail = 'jordan.lee@acmebank.example.com';
        input.estimatedValue = '$120,000';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Account__c, Contact__c, Estimated_Value__c,
                   Account__r.Name, Contact__r.FirstName, Contact__r.LastName, Contact__r.Email
            FROM GTM_Saved_Configuration__c
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

    // ------------------------------------------ account-contact-confirm

    /** Server-side backstop for the visible-confirm-or-create requirement:
     * a brand-new save with no accountId, no company, no contactId, and no
     * clientContactEmail gives saveConfiguration() nothing to resolve either
     * an Account or a Contact from at all -- this is the independent-of-the-
     * UI guard against a stale client bundle or a direct Apex caller. */
    @IsTest
    static void rejectsBrandNewSaveWithNoAccountOrContactSignalAtAll() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator';

        try {
            GtmSavedConfigurationController.saveConfiguration(input);
            System.assert(false, 'Expected an AuraHandledException when nothing is resolvable.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Saved_Configuration__c], 'No record should have been created.');
    }

    /** A company name alone is enough of an Account signal to pass the
     * backstop -- Contact stays null exactly as it already does when no
     * email is supplied (see savingWithoutClientContactEmailLeavesContactBlank),
     * this check is not a second, stricter Contact requirement layered on
     * top of that existing behaviour. */
    @IsTest
    static void allowsBrandNewSaveWithOnlyACompanyName() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        Assert.isNotNull(recordId);
    }

    /** A clientContactEmail alone (no company, no accountId) also satisfies
     * the backstop -- Quick Link's no-match branch sends exactly this shape
     * when the rep has confirmed only the prospect's email so far. */
    @IsTest
    static void allowsBrandNewSaveWithOnlyAClientContactEmail() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.clientContactEmail = 'prospect@example.com';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        Assert.isNotNull(recordId);
    }

    /** Resaving an EXISTING record (recordId supplied) with none of these
     * signals must NOT be rejected -- the Customize panel doesn't reload
     * Contact/Account onto every resave (see resavingWithBlankContactAndValue
     * DoesNotWipeThemOut just below), and this backstop is only meant to
     * catch a brand-new record with nothing resolvable, not to retroactively
     * block an edit to a link that already has its Account/Contact on file. */
    @IsTest
    static void doesNotRejectAResaveOfAnExistingRecordEvenWithNoNewSignal() {
        GTM_Saved_Configuration__c existing = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert existing;

        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.recordId = existing.Id;
        input.offering = 'migration-accelerator';
        input.generatedUrl = existing.Generated_URL__c;

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        Assert.areEqual(existing.Id, recordId);
    }

    @IsTest
    static void savingReusesExistingAccountByExactNameMatch() {
        Account existing = new Account(Name = 'Acme Bank');
        insert existing;

        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Account__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.areEqual(existing.Id, saved.Account__c, 'Should reuse the existing Account, not duplicate it');
        Assert.areEqual(1, [SELECT COUNT() FROM Account WHERE Name = 'Acme Bank']);
    }

    @IsTest
    static void savingWithoutClientContactEmailLeavesContactBlank() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Contact__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.isNull(saved.Contact__c, 'No email means no Contact should be guessed at');
    }

    @IsTest
    static void resavingWithBlankContactAndValueDoesNotWipeThemOut() {
        GtmSavedConfigurationController.SaveInput first = new GtmSavedConfigurationController.SaveInput();
        first.offering = 'migration-accelerator';
        first.company = 'Acme Bank';
        first.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        first.clientContactName = 'Jordan Lee';
        first.clientContactEmail = 'jordan.lee@acmebank.example.com';
        first.estimatedValue = '90000';
        Id recordId = GtmSavedConfigurationController.saveConfiguration(first).recordId;

        // Simulates reopening this link for editing: the Customize panel
        // doesn't reload Contact/Estimated Value from the record, so a
        // resave sends them blank unless the rep retypes them.
        GtmSavedConfigurationController.SaveInput second = new GtmSavedConfigurationController.SaveInput();
        second.recordId = recordId;
        second.offering = 'migration-accelerator';
        second.company = 'Acme Bank';
        second.generatedUrl = first.generatedUrl;

        Test.startTest();
        GtmSavedConfigurationController.saveConfiguration(second);
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Contact__c, Estimated_Value__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.isNotNull(saved.Contact__c, 'A blank resend should not wipe out the Contact set on the first save');
        Assert.areEqual(90000, saved.Estimated_Value__c, 'A blank resend should not wipe out the Estimated Value');
    }

    @IsTest
    static void wrapsDmlFailureOnSaveAsFriendlyError() {
        GTM_Saved_Configuration__c existing = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert existing;
        Id staleId = existing.Id;
        delete existing;

        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.recordId = staleId;
        input.offering = 'migration-accelerator';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator';

        try {
            GtmSavedConfigurationController.saveConfiguration(input);
            System.assert(false, 'Expected an AuraHandledException, not a raw DmlException.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void wrapsDmlFailureOnDeleteAsFriendlyError() {
        GTM_Saved_Configuration__c existing = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert existing;
        Id staleId = existing.Id;
        delete existing;

        try {
            GtmSavedConfigurationController.deleteConfiguration(staleId);
            System.assert(false, 'Expected an AuraHandledException, not a raw DmlException.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void searchContactsMatchesByNameOrEmail() {
        Account acc = new Account(Name = 'Acme Bank');
        insert acc;
        insert new Contact(FirstName = 'Jordan', LastName = 'Lee', Email = 'jordan.lee@acmebank.example.com', AccountId = acc.Id);
        insert new Contact(FirstName = 'Alex', LastName = 'Rivera', Email = 'alex.rivera@other.example.com');

        Test.startTest();
        List<GtmSavedConfigurationController.ContactSearchResult> byName =
            GtmSavedConfigurationController.searchContacts('Jordan');
        List<GtmSavedConfigurationController.ContactSearchResult> byEmail =
            GtmSavedConfigurationController.searchContacts('alex.rivera@');
        List<GtmSavedConfigurationController.ContactSearchResult> tooShort =
            GtmSavedConfigurationController.searchContacts('j');
        Test.stopTest();

        Assert.areEqual(1, byName.size(), 'Should match by name');
        Assert.areEqual('Acme Bank', byName[0].accountName, 'Should carry the Contact\'s own Account');
        Assert.areEqual(1, byEmail.size(), 'Should match by email');
        Assert.areEqual(0, tooShort.size(), 'A 1-character term should not search at all');
    }

    @IsTest
    static void searchContactsByAccountNameReturnsEveryContactOnThatAccount() {
        Account acme = new Account(Name = 'Acme Bank');
        insert acme;
        Account other = new Account(Name = 'Globex Corp');
        insert other;
        // Deliberately no name/email overlap with the search term -- the
        // only way either of these should surface is via the Account
        // name match, proving that path actually works and isn't just
        // piggybacking on a coincidental name/email hit.
        insert new Contact(FirstName = 'Priya', LastName = 'Natarajan', Email = 'pn@example.com', AccountId = acme.Id);
        insert new Contact(FirstName = 'Marcus', LastName = 'Webb', Email = 'mw@example.com', AccountId = acme.Id);
        insert new Contact(FirstName = 'Someone', LastName = 'Else', Email = 'se@example.com', AccountId = other.Id);

        Test.startTest();
        List<GtmSavedConfigurationController.ContactSearchResult> results =
            GtmSavedConfigurationController.searchContacts('Acme Bank');
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Should return every Contact on the matching Account, not just a name/email hit');
        for (GtmSavedConfigurationController.ContactSearchResult r : results) {
            Assert.areEqual('Acme Bank', r.accountName);
        }
    }

    @IsTest
    static void savingWithSelectedContactUsesItsRealAccountDirectly() {
        Account realAccount = new Account(Name = 'Acme Holdings, the actual real Account');
        insert realAccount;
        Contact realContact = new Contact(
            FirstName = 'Jordan',
            LastName = 'Lee',
            Email = 'jordan.lee@acmebank.example.com',
            AccountId = realAccount.Id
        );
        insert realContact;

        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        // Deliberately mismatched from the selected Contact's real Account
        // name -- proves the selection wins over Company-text resolution,
        // not just that it works when they happen to agree.
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        input.contactId = realContact.Id;
        input.accountId = realAccount.Id;

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Account__c, Contact__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.areEqual(realAccount.Id, saved.Account__c, 'Should use the selected Contact\'s own Account, not one resolved from Company text');
        Assert.areEqual(realContact.Id, saved.Contact__c, 'Should use the exact selected Contact, not a fuzzy match');
        Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE Name = 'Acme Bank'], 'The Company-text resolve path should never have run at all, so no Account by that name should exist');
    }

    @IsTest
    static void savingFallsBackToFuzzyResolveWhenContactIdIsGarbage() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        input.clientContactName = 'Jordan Lee';
        input.clientContactEmail = 'jordan.lee@acmebank.example.com';
        input.contactId = 'not-a-real-id';
        input.accountId = 'also-not-a-real-id';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Account__c, Contact__c, Account__r.Name, Contact__r.Email
            FROM GTM_Saved_Configuration__c
            WHERE Id = :recordId
        ];
        Assert.isNotNull(saved.Account__c, 'A garbage accountId should fall back to resolving from Company text');
        Assert.areEqual('Acme Bank', saved.Account__r.Name);
        Assert.isNotNull(saved.Contact__c, 'A garbage contactId should fall back to the fuzzy name/email resolve');
        Assert.areEqual('jordan.lee@acmebank.example.com', saved.Contact__r.Email);
    }

    // --------------------------------------------------- notify email

    @IsTest
    static void newConfigurationDefaultsNotifyEmailToCreatingUser() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Notify_Email__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.areEqual(
            UserInfo.getUserEmail(),
            saved.Notify_Email__c,
            'No override supplied -- should default to the creating user\'s own email'
        );
    }

    @IsTest
    static void newConfigurationHonorsExplicitNotifyEmailOverride() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        input.notifyEmail = 'sales-ops@example.com';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Notify_Email__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.areEqual(
            'sales-ops@example.com',
            saved.Notify_Email__c,
            'An explicit override should stick, not be replaced by the creating user\'s email'
        );
    }

    @IsTest
    static void resavingWithoutNotifyEmailDoesNotWipeOutAPriorOverride() {
        GtmSavedConfigurationController.SaveInput first = new GtmSavedConfigurationController.SaveInput();
        first.offering = 'migration-accelerator';
        first.company = 'Acme Bank';
        first.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        first.notifyEmail = 'sales-ops@example.com';
        Id recordId = GtmSavedConfigurationController.saveConfiguration(first).recordId;

        // Simulates an autosave/resave that doesn't carry the override
        // forward -- the wizard always resends the current value, but the
        // server-side rule must hold even if a caller doesn't.
        GtmSavedConfigurationController.SaveInput second = new GtmSavedConfigurationController.SaveInput();
        second.recordId = recordId;
        second.offering = 'migration-accelerator';
        second.company = 'Acme Bank';
        second.generatedUrl = first.generatedUrl;

        Test.startTest();
        GtmSavedConfigurationController.saveConfiguration(second);
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Notify_Email__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.areEqual(
            'sales-ops@example.com',
            saved.Notify_Email__c,
            'A blank resend should not wipe out a previously set override'
        );
    }

    @IsTest
    static void resavingCanReplaceThePreviousNotifyEmailOverride() {
        GtmSavedConfigurationController.SaveInput first = new GtmSavedConfigurationController.SaveInput();
        first.offering = 'migration-accelerator';
        first.company = 'Acme Bank';
        first.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        first.notifyEmail = 'sales-ops@example.com';
        Id recordId = GtmSavedConfigurationController.saveConfiguration(first).recordId;

        GtmSavedConfigurationController.SaveInput second = new GtmSavedConfigurationController.SaveInput();
        second.recordId = recordId;
        second.offering = 'migration-accelerator';
        second.company = 'Acme Bank';
        second.generatedUrl = first.generatedUrl;
        second.notifyEmail = 'other-team@example.com';

        Test.startTest();
        GtmSavedConfigurationController.saveConfiguration(second);
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Notify_Email__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.areEqual('other-team@example.com', saved.Notify_Email__c);
    }

    @IsTest
    static void malformedNotifyEmailOnNewRecordFallsBackToCreatingUser() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        input.notifyEmail = 'not-an-email';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Notify_Email__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.areEqual(
            UserInfo.getUserEmail(),
            saved.Notify_Email__c,
            'A malformed override should not be stored -- should fall back to the creating user'
        );
    }

    @IsTest
    static void wrapsDmlFailureOnSetActiveAsFriendlyError() {
        GTM_Saved_Configuration__c existing = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator'
        );
        insert existing;
        Id staleId = existing.Id;
        delete existing;

        try {
            GtmSavedConfigurationController.setActive(staleId, false);
            System.assert(false, 'Expected an AuraHandledException, not a raw DmlException.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    // ------------------------------------------- open-duplicate check (#32)

    private static Id makeOpenOpportunity(Id accountId, Id contactId, String offeringKey, Boolean isClosed) {
        Opportunity opp = new Opportunity(
            Name = 'Existing Deal',
            AccountId = accountId,
            StageName = isClosed ? 'Closed Won' : 'Prospecting',
            CloseDate = isClosed ? Date.today().addDays(-1) : Date.today().addDays(90),
            Offering_Key__c = offeringKey
        );
        insert opp;
        insert new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = contactId,
            Role = 'Decision Maker',
            IsPrimary = true
        );
        return opp.Id;
    }

    @IsTest
    static void blocksSaveWhenOpenDuplicateExistsForSameAccountContactOffering() {
        Account acc = new Account(Name = 'Acme Bank');
        insert acc;
        Contact con = new Contact(FirstName = 'Jordan', LastName = 'Lee', Email = 'jordan.lee@acmebank.example.com', AccountId = acc.Id);
        insert con;
        makeOpenOpportunity(acc.Id, con.Id, 'migration-accelerator', false);

        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        input.accountId = acc.Id;
        input.contactId = con.Id;

        try {
            GtmSavedConfigurationController.saveConfiguration(input);
            System.assert(false, 'Expected the open-duplicate block to throw.');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains('OPEN_DUPLICATE'),
                'Should throw the structured open-duplicate payload, not a generic error'
            );
        }
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Opportunity WHERE AccountId = :acc.Id],
            'No second Opportunity should have been created'
        );
    }

    @IsTest
    static void closedDuplicateProceedsWithNoPromptAndCreatesNewOpportunity() {
        Account acc = new Account(Name = 'Acme Bank');
        insert acc;
        Contact con = new Contact(FirstName = 'Jordan', LastName = 'Lee', Email = 'jordan.lee@acmebank.example.com', AccountId = acc.Id);
        insert con;
        makeOpenOpportunity(acc.Id, con.Id, 'migration-accelerator', true);

        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        input.accountId = acc.Id;
        input.contactId = con.Id;

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        Assert.isNotNull(recordId, 'A closed-only match should proceed with no prompt');
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Opportunity WHERE AccountId = :acc.Id],
            'A brand-new Opportunity should have been created alongside the closed one'
        );
    }

    @IsTest
    static void chosenOpportunityIdBypassesTheOpenDuplicateCheck() {
        Account acc = new Account(Name = 'Acme Bank');
        insert acc;
        Contact con = new Contact(FirstName = 'Jordan', LastName = 'Lee', Email = 'jordan.lee@acmebank.example.com', AccountId = acc.Id);
        insert con;
        Id existingOppId = makeOpenOpportunity(acc.Id, con.Id, 'migration-accelerator', false);

        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        input.accountId = acc.Id;
        input.contactId = con.Id;
        input.opportunityId = existingOppId;

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        Assert.isNotNull(recordId);
        GTM_Saved_Configuration__c saved = [SELECT Opportunity__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId];
        Assert.areEqual(existingOppId, saved.Opportunity__c, 'chosenOpportunityId reuse should not be blocked by the open-duplicate check');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Opportunity WHERE AccountId = :acc.Id],
            'No new Opportunity should have been created when reusing an explicit choice'
        );
    }

    @IsTest
    static void forceNewOpportunityBypassesTheBlockAndCreatesANewOpportunity() {
        Account acc = new Account(Name = 'Acme Bank');
        insert acc;
        Contact con = new Contact(FirstName = 'Jordan', LastName = 'Lee', Email = 'jordan.lee@acmebank.example.com', AccountId = acc.Id);
        insert con;
        makeOpenOpportunity(acc.Id, con.Id, 'migration-accelerator', false);

        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Acme Bank';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Acme';
        input.accountId = acc.Id;
        input.contactId = con.Id;
        input.forceNewOpportunity = true;

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        Assert.isNotNull(recordId, 'forceNewOpportunity should proceed past the open-duplicate block');
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Opportunity WHERE AccountId = :acc.Id],
            'Create new anyway should create a genuinely new Opportunity'
        );
    }

    // --------------------------------------------------- resend engagement link (#38)

    @IsTest
    static void resendEngagementLink_sendsEmail() {
        Account acc = new Account(Name = 'Acme Bank');
        insert acc;
        Contact con = new Contact(FirstName = 'Jordan', LastName = 'Lee', Email = 'jordan.lee@acmebank.example.com', AccountId = acc.Id);
        insert con;
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator?cfgId=abc',
            Contact__c = con.Id
        );
        insert cfg;

        Test.startTest();
        GtmSavedConfigurationController.resendEngagementLink(cfg.Id);
        Test.stopTest();

        // No exception thrown — the email was accepted by the test framework.
        System.assert(true, 'resendEngagementLink should complete without throwing when contact email and URL are present');
    }

    @IsTest
    static void resendEngagementLink_throwsWhenNoUrl() {
        Account acc = new Account(Name = 'Acme Bank');
        insert acc;
        Contact con = new Contact(FirstName = 'Jordan', LastName = 'Lee', Email = 'jordan.lee@acmebank.example.com', AccountId = acc.Id);
        insert con;
        // Generated_URL__c is left blank -- field is not required by schema but
        // the method must guard against it.
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Acme Bank',
            Generated_URL__c = 'placeholder',
            Contact__c = con.Id
        );
        insert cfg;
        // Blank out the URL directly via DML to bypass the saveConfiguration guard.
        update new GTM_Saved_Configuration__c(Id = cfg.Id, Generated_URL__c = '');

        try {
            Test.startTest();
            GtmSavedConfigurationController.resendEngagementLink(cfg.Id);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException when Generated_URL__c is blank');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void resendEngagementLink_throwsWhenNoContactEmail() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator?cfgId=abc'
            // Contact__c intentionally omitted -- no email to send to
        );
        insert cfg;

        try {
            Test.startTest();
            GtmSavedConfigurationController.resendEngagementLink(cfg.Id);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException when Contact__c (and its email) is blank');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void newOpportunityIsStampedWithOfferingKey() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Brand New Co';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Brand';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [SELECT Opportunity__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId];
        Assert.isNotNull(saved.Opportunity__c);
        Opportunity opp = [SELECT Offering_Key__c FROM Opportunity WHERE Id = :saved.Opportunity__c];
        Assert.areEqual('migration-accelerator', opp.Offering_Key__c);
    }

    // -------------------------------------------------- preview token (#108)

    @IsTest
    static void savingWithAPasswordReturnsAValidPreviewToken() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Token Co';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Token';
        input.linkPassword = 'S3cret!';

        Test.startTest();
        GtmSavedConfigurationController.SaveResult result =
            GtmSavedConfigurationController.saveConfiguration(input);
        Test.stopTest();

        Assert.isNotNull(result.recordId, 'A record should have been created.');
        Assert.isNotNull(result.previewToken, 'A preview token should be minted when a password is set.');
        Assert.isFalse(
            result.previewToken.contains('S3cret!'),
            'The token must never carry the plaintext password.'
        );
        Assert.isTrue(
            GtmLinkAuthController.validatePreviewToken(String.valueOf(result.recordId), result.previewToken),
            'The freshly minted token should validate against the record it was minted for.'
        );
    }

    @IsTest
    static void savingWithoutAPasswordReturnsNoPreviewToken() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'No Password Co';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=NoPw';

        Test.startTest();
        GtmSavedConfigurationController.SaveResult result =
            GtmSavedConfigurationController.saveConfiguration(input);
        Test.stopTest();

        Assert.isNotNull(result.recordId);
        Assert.isNull(result.previewToken, 'No password was set on this save, so no token should be minted.');
    }

    @IsTest
    static void resavingWithoutTouchingThePasswordReturnsNoNewToken() {
        GtmSavedConfigurationController.SaveInput createInput = new GtmSavedConfigurationController.SaveInput();
        createInput.offering = 'migration-accelerator';
        createInput.company = 'Resave Co';
        createInput.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Resave';
        createInput.linkPassword = 'FirstPass1';
        Id recordId = GtmSavedConfigurationController.saveConfiguration(createInput).recordId;

        GtmSavedConfigurationController.SaveInput editInput = new GtmSavedConfigurationController.SaveInput();
        editInput.recordId = recordId;
        editInput.offering = 'migration-accelerator';
        editInput.company = 'Resave Co Renamed';
        editInput.generatedUrl = createInput.generatedUrl;
        // linkPassword deliberately left blank -- an edit that doesn't touch
        // the password shouldn't mint a fresh token off nothing.

        Test.startTest();
        GtmSavedConfigurationController.SaveResult result =
            GtmSavedConfigurationController.saveConfiguration(editInput);
        Test.stopTest();

        Assert.isNull(result.previewToken);
    }

    // --------------------------------------------------- coverage: deal picker

    @IsTest
    static void getAccountDealsReturnsOpenAndClosedDealsWithLinkCounts() {
        Account acc = new Account(Name = 'Deal Co');
        insert acc;
        Opportunity openOpp = new Opportunity(
            Name = 'Open Deal', AccountId = acc.Id, StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        Opportunity closedOpp = new Opportunity(
            Name = 'Closed Deal', AccountId = acc.Id, StageName = 'Closed Won',
            CloseDate = Date.today().addDays(-30)
        );
        insert new List<Opportunity>{ openOpp, closedOpp };
        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/a',
            Account__c = acc.Id,
            Opportunity__c = openOpp.Id
        );

        Test.startTest();
        List<GtmSavedConfigurationController.DealOption> deals =
            GtmSavedConfigurationController.getAccountDeals(acc.Id);
        List<GtmSavedConfigurationController.DealOption> forGarbageId =
            GtmSavedConfigurationController.getAccountDeals('not-a-real-id');
        Test.stopTest();

        Assert.areEqual(2, deals.size(), 'Both the open and closed deal should be returned');
        Assert.isTrue(deals[0].isClosed != null, 'isClosed should be populated');
        Boolean sawOpenWithLink = false;
        for (GtmSavedConfigurationController.DealOption d : deals) {
            if (d.opportunityId == openOpp.Id) {
                Assert.areEqual(1, d.linkCount, 'The open deal has exactly one link');
                sawOpenWithLink = true;
            } else if (d.opportunityId == closedOpp.Id) {
                Assert.areEqual(0, d.linkCount, 'The closed deal has no links');
            }
        }
        Assert.isTrue(sawOpenWithLink, 'Should have found the open deal with a link');
        Assert.areEqual(0, forGarbageId.size(), 'A garbage accountId should return an empty list, not throw');
    }

    // --------------------------------------------------- coverage: findAccountByName

    @IsTest
    static void findAccountByNameMatchesExactlyBeforeFuzzy() {
        insert new Account(Name = 'Unique Fuzzy Co');

        Test.startTest();
        GtmSavedConfigurationController.AccountMatch exact =
            GtmSavedConfigurationController.findAccountByName('Unique Fuzzy Co');
        GtmSavedConfigurationController.AccountMatch fuzzy =
            GtmSavedConfigurationController.findAccountByName('Unique Fuzzy');
        GtmSavedConfigurationController.AccountMatch blank =
            GtmSavedConfigurationController.findAccountByName('');
        GtmSavedConfigurationController.AccountMatch none =
            GtmSavedConfigurationController.findAccountByName('Totally Nonexistent Co Name');
        Test.stopTest();

        Assert.isNotNull(exact, 'An exact name match should be found');
        Assert.isTrue(exact.isExact, 'Exact match should be flagged as exact');
        Assert.isNotNull(fuzzy, 'A single fuzzy LIKE match should be found');
        Assert.isFalse(fuzzy.isExact, 'A fuzzy match should not be flagged as exact');
        Assert.isNull(blank, 'A blank company should return no match');
        Assert.isNull(none, 'No matches at all should return null');
    }

    @IsTest
    static void findAccountByNameReturnsNullWhenFuzzyMatchIsAmbiguous() {
        insert new Account(Name = 'Ambiguous Fuzzy Co One');
        insert new Account(Name = 'Ambiguous Fuzzy Co Two');

        Test.startTest();
        GtmSavedConfigurationController.AccountMatch match =
            GtmSavedConfigurationController.findAccountByName('Ambiguous Fuzzy');
        Test.stopTest();

        Assert.isNull(match, 'Two fuzzy matches is ambiguous and should not be offered');
    }

    // --------------------------------------------------- coverage: password/token helpers

    @IsTest
    static void regeneratePasswordSetsANewPasswordOnTheRecord() {
        GTM_Saved_Configuration__c existing = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator',
            Link_Password__c = 'OldPass1'
        );
        insert existing;

        Test.startTest();
        String newPassword = GtmSavedConfigurationController.regeneratePassword(existing.Id);
        Test.stopTest();

        Assert.isNotNull(newPassword, 'A new password should be returned to the rep');
        Assert.areEqual(6, newPassword.length(), 'Passwords are generated as 6 characters');
        GTM_Saved_Configuration__c updated = [
            SELECT Link_Password__c FROM GTM_Saved_Configuration__c WHERE Id = :existing.Id
        ];
        Assert.areEqual(newPassword, updated.Link_Password__c);
    }

    @IsTest
    static void regeneratePasswordThrowsWithoutARecordId() {
        try {
            GtmSavedConfigurationController.regeneratePassword(null);
            System.assert(false, 'Expected an AuraHandledException.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void hasLinkPasswordReflectsWhetherAPasswordIsSet() {
        GTM_Saved_Configuration__c withPw = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/a',
            Link_Password__c = 'Secret1'
        );
        GTM_Saved_Configuration__c withoutPw = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/b'
        );
        insert new List<GTM_Saved_Configuration__c>{ withPw, withoutPw };

        Test.startTest();
        Boolean hasIt = GtmSavedConfigurationController.hasLinkPassword(withPw.Id);
        Boolean doesNotHaveIt = GtmSavedConfigurationController.hasLinkPassword(withoutPw.Id);
        Boolean unresolvable = GtmSavedConfigurationController.hasLinkPassword('garbage');
        Test.stopTest();

        Assert.isTrue(hasIt);
        Assert.isFalse(doesNotHaveIt);
        Assert.isFalse(unresolvable, 'An unresolvable id should degrade to false, not throw');
    }

    // ----------------------------------------------- coverage: getPassword (masked-with-reveal, landing-view-enrich)

    @IsTest
    static void getPasswordReturnsThePlaintextForAnExistingRecord() {
        GTM_Saved_Configuration__c existing = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator',
            Link_Password__c = 'Reveal1'
        );
        insert existing;

        Test.startTest();
        String password = GtmSavedConfigurationController.getPassword(existing.Id);
        Test.stopTest();

        Assert.areEqual('Reveal1', password, 'The current plaintext password should be returned on demand');
    }

    @IsTest
    static void getPasswordThrowsWithoutARecordId() {
        try {
            GtmSavedConfigurationController.getPassword(null);
            System.assert(false, 'Expected an AuraHandledException.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void getPasswordThrowsForAnUnresolvableRecordId() {
        try {
            GtmSavedConfigurationController.getPassword('garbage');
            System.assert(false, 'Expected an AuraHandledException.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    /** Users are created inside their own runAs block: inserting a User and a
     *  regular sObject in one transaction is a MIXED_DML_OPERATION. Matches
     *  the pattern already used by GtmReadoutControllerTest.createRep. */
    private static User createRep(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias             = alias,
            Email             = alias + '@example.com',
            EmailEncodingKey  = 'UTF-8',
            LastName          = 'Rep ' + alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'America/New_York',
            Username          = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    @IsTest
    static void getPasswordIsScopedByRecordSharingNotJustClassAccess() {
        // GTM_Saved_Configuration__c is Private (see object metadata), and
        // this class runs `with sharing` -- getPassword must inherit that
        // scoping like every other read on this class, not just gate on
        // class access. A rep who doesn't own the record (and has no other
        // sharing grant to it) must not be able to pull its password.
        User owningRep = createRep('gtmpwo1');
        User otherRep  = createRep('gtmpwo2');

        GTM_Saved_Configuration__c existing = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator',
            Link_Password__c = 'OwnerOnly1',
            OwnerId = owningRep.Id
        );
        insert existing;

        Test.startTest();
        String ownerResult;
        System.runAs(owningRep) {
            ownerResult = GtmSavedConfigurationController.getPassword(existing.Id);
        }

        Boolean otherRepThrew = false;
        System.runAs(otherRep) {
            try {
                GtmSavedConfigurationController.getPassword(existing.Id);
            } catch (AuraHandledException e) {
                otherRepThrew = true;
            }
        }
        Test.stopTest();

        Assert.areEqual('OwnerOnly1', ownerResult, 'The owning rep can read their own record\'s password');
        Assert.isTrue(otherRepThrew, 'A rep who does not own the record must not be able to read its password');
    }

    // --------------------------------------------------- coverage: reads used by the wizard/customize panel

    @IsTest
    static void getConfigurationReturnsTheFullSavedView() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.industry = 'fintech';
        input.company = 'Read Back Co';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=ReadBack';
        input.configPayload = '{"SOURCE_PLATFORM":"Eloqua"}';
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;

        Test.startTest();
        GtmSavedConfigurationController.SavedConfigView view =
            GtmSavedConfigurationController.getConfiguration(String.valueOf(recordId));
        GtmSavedConfigurationController.SavedConfigView missing =
            GtmSavedConfigurationController.getConfiguration(null);
        Test.stopTest();

        Assert.isNotNull(view);
        Assert.areEqual('Read Back Co', view.company);
        Assert.areEqual('fintech', view.industry);
        Assert.areEqual('migration-accelerator', view.offering);
        Assert.areEqual(input.configPayload, view.configPayload);
        Assert.areEqual(input.generatedUrl, view.generatedUrl);
        Assert.isTrue(view.isActive);
        Assert.isNull(missing, 'A blank/unresolvable id should return null, not throw');
    }

    @IsTest
    static void getConfigurationCrmDataReturnsLinkedRecords() {
        Account acc = new Account(Name = 'Crm Data Co');
        insert acc;
        Contact con = new Contact(
            FirstName = 'Jordan', LastName = 'Lee',
            Email = 'jordan.lee@crmdata.example.com', AccountId = acc.Id
        );
        insert con;
        Opportunity opp = new Opportunity(
            Name = 'Crm Data Deal', AccountId = acc.Id, StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30), Amount = 5000
        );
        insert opp;
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/a',
            Account__c = acc.Id,
            Contact__c = con.Id,
            Opportunity__c = opp.Id,
            Estimated_Value__c = 5000
        );
        insert cfg;

        Test.startTest();
        GtmSavedConfigurationController.CrmData data =
            GtmSavedConfigurationController.getConfigurationCrmData(cfg.Id);
        GtmSavedConfigurationController.CrmData missing =
            GtmSavedConfigurationController.getConfigurationCrmData(null);
        Test.stopTest();

        Assert.isNotNull(data);
        Assert.areEqual(acc.Id, data.accountId);
        Assert.areEqual('Crm Data Co', data.accountName);
        Assert.areEqual(con.Id, data.contactId);
        Assert.areEqual('jordan.lee@crmdata.example.com', data.contactEmail);
        Assert.areEqual(opp.Id, data.opportunityId);
        Assert.areEqual('5000', data.estimatedValue);
        Assert.isNull(missing, 'A blank/unresolvable id should return null, not throw');
    }

    // --------------------------------------------------- coverage: misc reads

    @IsTest
    static void isConfigManagerReturnsTrueForAnInternalStandardUser() {
        Test.startTest();
        Boolean result = GtmSavedConfigurationController.isConfigManager();
        Test.stopTest();

        Assert.isTrue(result, 'The running test user is a Standard internal user, so should be treated as a rep');
    }

    // ----------------------------------------- ownership scoping (rep-data-scoping-owd-2)

    /** Explicit OwnerId backstop on getMyConfigurations(): a rep must see
     *  only their own saved configurations, not another rep's, even though
     *  the query used to have no WHERE clause at all and relied entirely
     *  on implicit sharing. */
    @IsTest
    static void getMyConfigurationsScopesToTheOwningRepOnly() {
        User repA = createRep('gtmsc1');
        User repB = createRep('gtmsc2');

        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/a',
            Presentation_Stage__c = 'Sent',
            OwnerId = repA.Id
        );
        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/b',
            Presentation_Stage__c = 'Sent',
            OwnerId = repB.Id
        );

        Test.startTest();
        List<GTM_Saved_Configuration__c> repAView;
        System.runAs(repA) {
            repAView = GtmSavedConfigurationController.getMyConfigurations();
        }
        Test.stopTest();

        Assert.areEqual(1, repAView.size(), 'Rep A should see only their own configuration');
        Assert.areEqual(repA.Id, repAView[0].OwnerId);
    }

    /** A user holding viewAllRecords on GTM_Saved_Configuration__c
     *  (GTM_Offering_Admin) still sees everyone's configurations -- the
     *  explicit backstop must not clip an admin's existing full visibility. */
    @IsTest
    static void getMyConfigurationsAdminBypassSeesEveryonesConfigurations() {
        User repA = createRep('gtmsc3');
        User adminUser = createRep('gtmsc4');
        List<PermissionSet> adminSets = [
            SELECT Id FROM PermissionSet WHERE Name = 'GTM_Offering_Admin' LIMIT 1
        ];
        if (adminSets.isEmpty()) {
            return; // Permission set not deployed in this org -- nothing to assert.
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(
                AssigneeId = adminUser.Id,
                PermissionSetId = adminSets[0].Id
            );
        }

        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/a',
            Presentation_Stage__c = 'Sent',
            OwnerId = repA.Id
        );

        Test.startTest();
        List<GTM_Saved_Configuration__c> adminView;
        System.runAs(adminUser) {
            adminView = GtmSavedConfigurationController.getMyConfigurations();
        }
        Test.stopTest();

        Assert.areEqual(1, adminView.size(), 'An admin with viewAllRecords should see other reps\' configurations too');
    }

    // ------------------------------------- completeness filter (rep-initiated-assessment-no-page-1)

    /** getMyConfigurations()'s "All Pages" completeness filter: a brand-new
     *  save via saveConfiguration() is stamped Draft and stays excluded; a
     *  null-stage legacy row (predates this field) is excluded; a Rep_Direct
     *  pageless assessment is excluded; Sent/In_Review/Assessment are the
     *  "real page" stages and are included. */
    @IsTest
    static void getMyConfigurationsExcludesDraftNullAndRepDirectButIncludesRealPageStages() {
        // Draft: exactly what a brand-new saveConfiguration() insert now stamps.
        GtmSavedConfigurationController.SaveInput draftInput = new GtmSavedConfigurationController.SaveInput();
        draftInput.offering = 'migration-accelerator';
        draftInput.company = 'Draft Co';
        draftInput.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=Draft';
        GtmSavedConfigurationController.saveConfiguration(draftInput);

        // Null stage: a legacy row inserted directly, predating this field.
        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/legacy'
        );

        // Rep_Direct: a pageless assessment, same shape createRepDirectAssessment() inserts.
        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = 'Rep_Direct'
        );

        // The three "real page" stages -- all should be included.
        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/sent',
            Presentation_Stage__c = 'Sent'
        );
        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/inreview',
            Presentation_Stage__c = 'In_Review'
        );
        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/assessment',
            Presentation_Stage__c = 'Assessment'
        );

        Test.startTest();
        List<GTM_Saved_Configuration__c> results = GtmSavedConfigurationController.getMyConfigurations();
        Test.stopTest();

        Assert.areEqual(3, results.size(), 'Only the three real-page-stage records should be listed');
        Set<String> stages = new Set<String>();
        for (GTM_Saved_Configuration__c r : results) {
            stages.add(r.Presentation_Stage__c);
        }
        Assert.isTrue(stages.contains('Sent'));
        Assert.isTrue(stages.contains('In_Review'));
        Assert.isTrue(stages.contains('Assessment'));
    }

    @IsTest
    static void newlySavedConfigurationIsStampedDraftOnInsert() {
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.offering = 'migration-accelerator';
        input.company = 'Draft Stamp Co';
        input.generatedUrl = 'https://example.my.site.com/gtmaccelerator/s/configurator?company=DraftStamp';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.saveConfiguration(input).recordId;
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Presentation_Stage__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.areEqual('Draft', saved.Presentation_Stage__c, 'A brand-new insert should be stamped Draft');
    }

    // ------------------------------------- rep-direct pageless assessment (rep-initiated-assessment-no-page-1)

    @IsTest
    static void createRepDirectAssessmentCreatesAPagelessRecordForAPickedContact() {
        Account acc = new Account(Name = 'Rep Direct Co');
        insert acc;
        Contact con = new Contact(
            FirstName = 'Jordan', LastName = 'Lee',
            Email = 'jordan.lee@repdirect.example.com', AccountId = acc.Id
        );
        insert con;

        GtmSavedConfigurationController.RepDirectInput input = new GtmSavedConfigurationController.RepDirectInput();
        input.contactId = con.Id;
        input.accountId = acc.Id;
        input.offering = 'migration-accelerator';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.createRepDirectAssessment(input);
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Contact__c, Account__c, Presentation_Stage__c, Generated_URL__c
            FROM GTM_Saved_Configuration__c
            WHERE Id = :recordId
        ];
        Assert.areEqual(con.Id, saved.Contact__c, 'Should use the exact picked Contact, never a fuzzy resolve');
        Assert.areEqual(acc.Id, saved.Account__c);
        Assert.areEqual('Rep_Direct', saved.Presentation_Stage__c);
        Assert.isNull(saved.Generated_URL__c, 'A pageless assessment has no generated page URL');
        // And it must not surface as a page.
        List<GTM_Saved_Configuration__c> asPage = GtmSavedConfigurationController.getMyConfigurations();
        Assert.isTrue(asPage.isEmpty(), 'A Rep_Direct record must never appear in "All Pages"');
    }

    @IsTest
    static void createRepDirectAssessmentRejectsATypedOrMissingContactId() {
        GtmSavedConfigurationController.RepDirectInput blankInput = new GtmSavedConfigurationController.RepDirectInput();
        try {
            GtmSavedConfigurationController.createRepDirectAssessment(blankInput);
            System.assert(false, 'Expected an AuraHandledException when no contactId is supplied.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }

        GtmSavedConfigurationController.RepDirectInput garbageInput = new GtmSavedConfigurationController.RepDirectInput();
        garbageInput.contactId = 'not-a-real-id';
        try {
            GtmSavedConfigurationController.createRepDirectAssessment(garbageInput);
            System.assert(false, 'Expected an AuraHandledException for a garbage contactId -- no fuzzy fallback exists on this path.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM GTM_Saved_Configuration__c],
            'Neither rejected call should have created a record'
        );
    }

    @IsTest
    static void createRepDirectAssessmentWorksWithNoAccount() {
        Contact con = new Contact(FirstName = 'No', LastName = 'Account', Email = 'no.account@repdirect.example.com');
        insert con;

        GtmSavedConfigurationController.RepDirectInput input = new GtmSavedConfigurationController.RepDirectInput();
        input.contactId = con.Id;
        input.offering = 'migration-accelerator';

        Test.startTest();
        Id recordId = GtmSavedConfigurationController.createRepDirectAssessment(input);
        Test.stopTest();

        GTM_Saved_Configuration__c saved = [
            SELECT Contact__c, Account__c FROM GTM_Saved_Configuration__c WHERE Id = :recordId
        ];
        Assert.areEqual(con.Id, saved.Contact__c);
        Assert.isNull(saved.Account__c);
    }

    @IsTest
    static void createRepDirectAssessmentRejectsAMissingOffering() {
        Contact con = new Contact(FirstName = 'No', LastName = 'Offering', Email = 'no.offering@repdirect.example.com');
        insert con;

        GtmSavedConfigurationController.RepDirectInput input = new GtmSavedConfigurationController.RepDirectInput();
        input.contactId = con.Id;

        try {
            GtmSavedConfigurationController.createRepDirectAssessment(input);
            System.assert(false, 'Expected an AuraHandledException when no offering is supplied.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Saved_Configuration__c]);
    }

    // ------------------------------------- rep-direct share link (rep-initiated-assessment-no-page-2)

    /** Only works on a genuine Rep_Direct record -- never on a real page
     *  (Sent/In_Review/Assessment/Draft/null), which has its own generated
     *  page URL/password already, minted by an entirely different path
     *  (saveConfiguration()). */
    @IsTest
    static void generateRepDirectShareLinkRejectsANonRepDirectRecord() {
        GTM_Saved_Configuration__c realPage = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/sent',
            Presentation_Stage__c = 'Sent'
        );
        insert realPage;

        try {
            GtmSavedConfigurationController.generateRepDirectShareLink(realPage.Id, '');
            System.assert(false, 'Expected an AuraHandledException for a non-Rep_Direct record.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void generateRepDirectShareLinkRejectsAMissingOrGarbageRecordId() {
        try {
            GtmSavedConfigurationController.generateRepDirectShareLink(null, '');
            System.assert(false, 'Expected an AuraHandledException for a null recordId.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            GtmSavedConfigurationController.generateRepDirectShareLink('not-a-real-id', '');
            System.assert(false, 'Expected an AuraHandledException for a garbage recordId.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    /**
     * The happy path: a genuine Rep_Direct record gets a Generated_URL__c and
     * Link_Password__c, in the same shape saveConfiguration()'s links use
     * (cfgId query param, six-character alphabet password), WITHOUT ever
     * flipping Presentation_Stage__c -- so it still never reappears in
     * getMyConfigurations()'s "All Pages" list (that filter is keyed on
     * Presentation_Stage__c alone, per its own class comment, not on whether
     * a URL/password exist).
     *
     * No Experience Cloud site exists in this org's test context (see
     * orgAndSiteUrlHelpersDoNotThrowEvenWithoutASiteConfigured above, the
     * same degrade-to-null this depends on) -- so this asserts BOTH branches
     * this method can honestly take: when a site resolves, the full
     * URL/password shape and the getMyConfigurations()/stage invariants; when
     * none does, that the method fails loudly rather than minting a broken
     * link.
     */
    @IsTest
    static void generateRepDirectShareLinkPopulatesUrlAndPasswordWithoutFlippingStage() {
        Contact con = new Contact(
            FirstName = 'Share', LastName = 'Link',
            Email = 'share.link@repdirect.example.com'
        );
        insert con;
        GTM_Saved_Configuration__c rec = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Contact__c = con.Id,
            Presentation_Stage__c = 'Rep_Direct'
        );
        insert rec;

        String siteConfiguratorUrl = GtmSavedConfigurationController.getConfiguratorPageUrl();

        if (siteConfiguratorUrl == null) {
            try {
                GtmSavedConfigurationController.generateRepDirectShareLink(rec.Id, '');
                System.assert(false, 'Expected an AuraHandledException when no site URL can be resolved.');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
            return;
        }

        Test.startTest();
        GtmSavedConfigurationController.ShareLinkResult result =
            GtmSavedConfigurationController.generateRepDirectShareLink(rec.Id, '');
        Test.stopTest();

        Assert.isNotNull(result.generatedUrl);
        Assert.isTrue(result.generatedUrl.startsWith(siteConfiguratorUrl + '?cfgId='), 'URL should point at the configurator with this record\'s cfgId');
        Assert.isNotNull(result.password);
        Assert.areEqual(6, result.password.length(), 'Password should match the existing six-character format');

        GTM_Saved_Configuration__c saved = [
            SELECT Generated_URL__c, Link_Password__c, Presentation_Stage__c
            FROM GTM_Saved_Configuration__c
            WHERE Id = :rec.Id
        ];
        Assert.areEqual(result.generatedUrl, saved.Generated_URL__c);
        Assert.areEqual(result.password, saved.Link_Password__c);
        Assert.areEqual('Rep_Direct', saved.Presentation_Stage__c, 'Must never flip the stage');

        List<GTM_Saved_Configuration__c> asPage = GtmSavedConfigurationController.getMyConfigurations();
        Assert.isTrue(asPage.isEmpty(), 'Still must never appear in "All Pages" -- the filter is keyed on stage, not on URL/password');
    }

    /** A resume token, when supplied, is carried through as &resume=<token>
     *  on the URL -- what lets a prospect pick up from wherever the rep
     *  pre-filled via GtmAssessmentDraftController.saveDraft(). */
    @IsTest
    static void generateRepDirectShareLinkCarriesAResumeTokenWhenSupplied() {
        GTM_Saved_Configuration__c rec = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = 'Rep_Direct'
        );
        insert rec;

        String siteConfiguratorUrl = GtmSavedConfigurationController.getConfiguratorPageUrl();
        if (siteConfiguratorUrl == null) {
            return; // covered by generateRepDirectShareLinkPopulatesUrlAndPasswordWithoutFlippingStage
        }

        Test.startTest();
        GtmSavedConfigurationController.ShareLinkResult result =
            GtmSavedConfigurationController.generateRepDirectShareLink(rec.Id, 'abc123resumeToken');
        Test.stopTest();

        Assert.isTrue(result.generatedUrl.contains('&resume=abc123resumeToken'));
    }

    /** A retry (re-share) reuses the same password already on the record
     *  rather than rotating it out from under a rep who already relayed it
     *  to the prospect. */
    @IsTest
    static void generateRepDirectShareLinkReusesAnExistingPassword() {
        GTM_Saved_Configuration__c rec = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = 'Rep_Direct',
            Link_Password__c = 'STICKY'
        );
        insert rec;

        String siteConfiguratorUrl = GtmSavedConfigurationController.getConfiguratorPageUrl();
        if (siteConfiguratorUrl == null) {
            return;
        }

        Test.startTest();
        GtmSavedConfigurationController.ShareLinkResult result =
            GtmSavedConfigurationController.generateRepDirectShareLink(rec.Id, '');
        Test.stopTest();

        Assert.areEqual('STICKY', result.password);
    }

    @IsTest
    static void orgAndSiteUrlHelpersDoNotThrowEvenWithoutASiteConfigured() {
        Test.startTest();
        String orgBase = GtmSavedConfigurationController.getOrgBaseUrl();
        String configuratorUrl = GtmSavedConfigurationController.getConfiguratorPageUrl();
        String homeUrl = GtmSavedConfigurationController.getSiteHomePageUrl();
        Test.stopTest();

        Assert.isNotNull(orgBase, 'The org domain URL should always resolve');
        // No Experience Cloud site exists in this test context, so these
        // degrade gracefully to null rather than throwing.
        System.assert(configuratorUrl == null || configuratorUrl.endsWith('/configurator'));
        System.assert(homeUrl == null || homeUrl.endsWith('/choose-offering'));
    }
}
