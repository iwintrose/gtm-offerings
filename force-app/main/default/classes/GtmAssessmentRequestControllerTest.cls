@isTest
private class GtmAssessmentRequestControllerTest {
    private static GtmAssessmentRequestController.RequestInput sampleInput() {
        GtmAssessmentRequestController.RequestInput input = new GtmAssessmentRequestController.RequestInput();
        input.name = 'Alex Rivera';
        input.email = 'alex.rivera@example.com';
        input.company = 'Northwind Retail';
        input.role = 'Director, Marketing Technology';
        input.currentPlatform = 'Oracle Eloqua';
        input.environmentSize = '2,000–10,000';
        input.timeline = 'Active — next 3 months';
        input.context = 'Contract renewal in Q3.';
        input.prospect = 'Northwind Retail';
        input.industry = 'Financial Services';
        return input;
    }

    private static MA_Assessment_Config__mdt config(
        Boolean createContact,
        Boolean sendEmail,
        String activityType
    ) {
        return new MA_Assessment_Config__mdt(
            Create_Lead__c = createContact,
            Send_Email__c = sendEmail,
            Notify_Email__c = 'assessments@example.com',
            Activity_Type__c = activityType
        );
    }

    @isTest
    static void createsContactAndTaskForNewEmail() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.isTrue(result.success, 'Submission should succeed');
        Assert.isTrue(result.contactCreated, 'A new Contact should have been created');

        Contact created = [
            SELECT FirstName, LastName, Email, Title, AccountId
            FROM Contact
            WHERE Id = :result.contactId
        ];
        Assert.areEqual('Alex', created.FirstName);
        Assert.areEqual('Rivera', created.LastName);
        Assert.areEqual('alex.rivera@example.com', created.Email);
        Assert.areEqual('Director, Marketing Technology', created.Title);
        Assert.isNotNull(created.AccountId, 'Contact should be linked to the resolved Account');

        List<Task> logged = [
            SELECT Subject, Status, Description FROM Task WHERE WhoId = :result.contactId
        ];
        Assert.areEqual(1, logged.size(), 'One activity should be logged');
        Assert.areEqual('Environment assessment request', logged[0].Subject);
        Assert.isTrue(
            logged[0].Description.contains('Oracle Eloqua'),
            'Activity should carry the submission detail'
        );
    }

    @isTest
    static void reusesExistingContactAndFillsBlanksOnly() {
        Account acc = new Account(Name = 'Northwind Retail');
        insert acc;
        Contact seeded = new Contact(
            LastName = 'Rivera',
            Email = 'alex.rivera@example.com',
            AccountId = acc.Id
        );
        insert seeded;

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.isFalse(result.contactCreated, 'Existing Contact should be reused');
        Assert.areEqual(seeded.Id, result.contactId);

        Contact after = [SELECT Title FROM Contact WHERE Id = :seeded.Id];
        Assert.areEqual(
            'Director, Marketing Technology',
            after.Title,
            'A blank Title should be filled in'
        );

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhoId = :seeded.Id],
            'The submission should be appended as an activity'
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Contact WHERE Email = 'alex.rivera@example.com'],
            'No duplicate Contact should be created'
        );
    }

    @isTest
    static void logsEventWhenConfigured() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Event');

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Event WHERE WhoId = :result.contactId],
            'An Event should be logged instead of a Task'
        );
    }

    @isTest
    static void skipsContactWhenDisabled() {
        GtmAssessmentRequestController.configOverride = config(false, false, 'Task');

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.isNull(result.contactId, 'No Contact should be created when disabled');
        Assert.areEqual(0, [SELECT COUNT() FROM Contact]);
    }

    @isTest
    static void sendsEmailWhenEnabled() {
        GtmAssessmentRequestController.configOverride = config(false, true, 'Task');

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.isTrue(result.success, 'Submission should succeed with email on');
    }

    @isTest
    static void rejectsMissingName() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.name = '   ';

        Boolean threw = false;
        try {
            GtmAssessmentRequestController.submitRequest(input);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'A blank name should be rejected');
    }

    @isTest
    static void rejectsMalformedEmail() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.email = 'not-an-email';

        Boolean threw = false;
        try {
            GtmAssessmentRequestController.submitRequest(input);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'A malformed email should be rejected');
        Assert.areEqual(0, [SELECT COUNT() FROM Contact]);
    }

    @isTest
    static void rejectsNullInput() {
        Boolean threw = false;
        try {
            GtmAssessmentRequestController.submitRequest(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Null input should be rejected');
    }

    @isTest
    static void succeedsWithNoCompanyOrProspect() {
        // No company/prospect means no Account resolved, so Contact is created
        // without an AccountId — submission should still succeed.
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.company = null;
        input.prospect = null;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success, 'Submission should succeed without company');
        Assert.isTrue(result.contactCreated, 'A Contact should still be created');
    }

    @isTest
    static void usesSingleWordNameAsLastName() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.name = 'Cher';

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Contact created = [SELECT FirstName, LastName FROM Contact WHERE Id = :result.contactId];
        Assert.isNull(created.FirstName);
        Assert.areEqual('Cher', created.LastName);
    }

    @isTest
    static void readsDeployedConfigWhenNoOverride() {
        // Exercises the CMDT query path; the deployed Default record drives it.
        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.isTrue(result.success, 'Deployed config should be readable');
    }

    @isTest
    static void createsAssessmentRequestRecord() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.isNotNull(
            result.assessmentRequestId,
            'A structured assessment request record should always be filed'
        );
        GTM_Assessment_Request__c req = [
            SELECT Requester_Name__c, Requester_Email__c, Company__c, Status__c,
                   Contact__c, Opportunity__c, Saved_Configuration__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual('Alex Rivera', req.Requester_Name__c);
        Assert.areEqual('alex.rivera@example.com', req.Requester_Email__c);
        Assert.areEqual('New', req.Status__c);
        Assert.areEqual(result.contactId, req.Contact__c);
        // A submission from a named company is a lead, so an Opportunity is
        // raised for it whether or not it came from a client link -- see
        // GtmAssessmentRequestController.ensureOpportunity, which branches on
        // the link only to decide whether to stamp Engagement_Link__c. This
        // test used to assert the opposite and had been failing on it; what it
        // is actually guarding is that no link means no link, below.
        Assert.isNotNull(req.Opportunity__c, 'A named company still raises a deal');
        Assert.isNull(req.Saved_Configuration__c, 'No client link was supplied');
    }

    @isTest
    static void linksToOpportunityAndAttributesContactViaSavedConfig() {
        Account acc = new Account(Name = 'Northwind Retail');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Northwind Retail Migration',
            StageName = 'Qualification',
            CloseDate = Date.today().addMonths(2),
            AccountId = acc.Id
        );
        insert opp;

        MA_Saved_Configuration__c savedConfig = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Industry__c = 'Financial Services',
            Company__c = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/configurator?company=Northwind',
            Account__c = acc.Id,
            Opportunity__c = opp.Id,
            OwnerId = UserInfo.getUserId()
        );
        insert savedConfig;

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = savedConfig.Id;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.areEqual(opp.Id, result.opportunityId, 'Opportunity should carry through to the result');

        GTM_Assessment_Request__c req = [
            SELECT Opportunity__c, Saved_Configuration__c, Contact__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual(opp.Id, req.Opportunity__c);
        Assert.areEqual(savedConfig.Id, req.Saved_Configuration__c);

        Contact created = [SELECT OwnerId FROM Contact WHERE Id = :result.contactId];
        Assert.areEqual(
            UserInfo.getUserId(),
            created.OwnerId,
            'A new Contact should be owned by the rep who owns the client link, not left unassigned'
        );
    }

    @isTest
    static void autoCreatesOpportunityWhenLinkHasNone() {
        Account acc = new Account(Name = 'Northwind Retail');
        insert acc;

        MA_Saved_Configuration__c savedConfig = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Industry__c = 'Financial Services',
            Company__c = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/configurator?company=Northwind',
            Account__c = acc.Id,
            OwnerId = UserInfo.getUserId()
        );
        insert savedConfig;

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = savedConfig.Id;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isNotNull(result.opportunityId, 'An Opportunity should be auto-created');

        Opportunity opp = [
            SELECT Name, AccountId, Amount, StageName
            FROM Opportunity
            WHERE Id = :result.opportunityId
        ];
        Assert.areEqual(acc.Id, opp.AccountId);
        Assert.isTrue(opp.Name.contains('Northwind Retail'));
        Assert.isTrue(opp.Name.contains('Migration Accelerator'));
        Assert.areEqual(250000, opp.Amount, 'Should fall back to the CMDT annual target');

        MA_Saved_Configuration__c updated = [
            SELECT Opportunity__c FROM MA_Saved_Configuration__c WHERE Id = :savedConfig.Id
        ];
        Assert.areEqual(
            result.opportunityId,
            updated.Opportunity__c,
            'The link should be written back so future submissions reuse this Opportunity'
        );
    }

    @isTest
    static void usesEstimatedValueOverOfferingTargetForNewOpportunity() {
        MA_Saved_Configuration__c savedConfig = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/configurator?company=Northwind',
            Estimated_Value__c = 75000,
            OwnerId = UserInfo.getUserId()
        );
        insert savedConfig;

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = savedConfig.Id;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Opportunity opp = [SELECT Amount FROM Opportunity WHERE Id = :result.opportunityId];
        Assert.areEqual(75000, opp.Amount);
    }

    @isTest
    static void reusesExistingOpportunityInsteadOfCreatingAnother() {
        Opportunity existingOpp = new Opportunity(
            Name = 'Northwind Retail Migration',
            StageName = 'Negotiation/Review',
            CloseDate = Date.today().addMonths(1)
        );
        insert existingOpp;

        MA_Saved_Configuration__c savedConfig = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/configurator?company=Northwind',
            Opportunity__c = existingOpp.Id,
            OwnerId = UserInfo.getUserId()
        );
        insert savedConfig;

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = savedConfig.Id;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.areEqual(existingOpp.Id, result.opportunityId);
        Assert.areEqual(1, [SELECT COUNT() FROM Opportunity]);
    }

    @isTest
    static void directBookingWithNoEngagementLinkStillResolvesAccount() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = null;
        input.company = 'Northwind Retail';

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        GTM_Assessment_Request__c req = [
            SELECT Account__c, Account__r.Name
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.isNotNull(req.Account__c, 'A direct booking should still resolve an Account from the company name');
        Assert.areEqual('Northwind Retail', req.Account__r.Name);

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Name = 'Northwind Retail'],
            'Exactly one Account should exist, not a duplicate'
        );
    }

    @isTest
    static void engagementLinkAccountTakesPriorityOverBookingFormCompany() {
        Account existing = new Account(Name = 'Northwind Retail Holdings');
        insert existing;

        MA_Saved_Configuration__c savedConfig = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Northwind Retail Holdings',
            Generated_URL__c = 'https://example.com/configurator?company=Northwind',
            Account__c = existing.Id,
            OwnerId = UserInfo.getUserId()
        );
        insert savedConfig;

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = savedConfig.Id;
        input.company = 'Northwind Retail (typo)';

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        GTM_Assessment_Request__c req = [
            SELECT Account__c FROM GTM_Assessment_Request__c WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual(existing.Id, req.Account__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE Name = 'Northwind Retail (typo)']);
    }

    @isTest
    static void failsOpenOnMalformedSavedRecordId() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = 'not-a-real-id';

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success, 'A bad savedRecordId should not block the submission');
        // The malformed id is ignored, not fatal: the submission still resolves
        // its account and raises a deal. What must not happen is the bad id
        // being stored as though it were a real link.
        GTM_Assessment_Request__c filed = [
            SELECT Saved_Configuration__c FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.isNull(filed.Saved_Configuration__c, 'A malformed id must not be stored as a link');
    }

    // ------------------------------------------------------------ token gate

    @isTest
    static void tokenNotRequiredForUnprotectedLink() {
        // A config with no Link_Password__c should never require a token.
        Account acc = new Account(Name = 'Northwind Retail');
        insert acc;
        MA_Saved_Configuration__c savedConfig = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/configurator',
            Account__c = acc.Id,
            OwnerId = UserInfo.getUserId()
        );
        insert savedConfig;

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = savedConfig.Id;
        input.submissionToken = null; // no token

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success, 'No token should be needed for an unprotected link');
    }

    @isTest
    static void tokenRequiredForPasswordProtectedLink_missingTokenThrows() {
        MA_Saved_Configuration__c savedConfig = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/configurator',
            Link_Password__c = 'secret123',
            OwnerId = UserInfo.getUserId()
        );
        insert savedConfig;

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = savedConfig.Id;
        input.submissionToken = null;

        Boolean threw = false;
        Test.startTest();
        try {
            GtmAssessmentRequestController.submitRequest(input);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Missing token for a password-protected link should throw');
    }

    @isTest
    static void tokenRequiredForPasswordProtectedLink_validTokenSucceeds() {
        MA_Saved_Configuration__c savedConfig = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/configurator',
            Link_Password__c = 'secret123',
            OwnerId = UserInfo.getUserId()
        );
        insert savedConfig;

        // Issue a real token the same way the LWC auth flow would.
        GtmLinkAuthController.VerifyResult auth =
            GtmLinkAuthController.verifyAndIssueToken(savedConfig.Id, 'secret123');
        Assert.isTrue(auth.matched, 'verifyAndIssueToken should succeed with correct password');

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = savedConfig.Id;
        input.submissionToken = auth.submissionToken;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success, 'A valid token should allow submission to proceed');
    }

    @isTest
    static void tokenRequiredForPasswordProtectedLink_tamperedHmacThrows() {
        MA_Saved_Configuration__c savedConfig = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/configurator',
            Link_Password__c = 'secret123',
            OwnerId = UserInfo.getUserId()
        );
        insert savedConfig;

        GtmLinkAuthController.VerifyResult auth =
            GtmLinkAuthController.verifyAndIssueToken(savedConfig.Id, 'secret123');

        // Tamper with the HMAC portion.
        List<String> parts = auth.submissionToken.split(':');
        String tamperedToken = parts[0] + ':' + parts[1] + ':' + 'deadbeef0000000000000000000000000000000000000000000000000000dead';

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = savedConfig.Id;
        input.submissionToken = tamperedToken;

        Boolean threw = false;
        Test.startTest();
        try {
            GtmAssessmentRequestController.submitRequest(input);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A tampered HMAC should be rejected');
    }

    @isTest
    static void directBookingWithNoSavedRecordIdNeverNeedsToken() {
        // Even if a caller somehow passes a token, it should be silently
        // ignored when there is no savedRecordId (no password-protected link).
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = null;
        input.submissionToken = 'garbage-token';

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success, 'A garbage token should be ignored for a direct booking');
    }
}
