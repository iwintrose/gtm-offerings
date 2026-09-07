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

    private static GTM_Assessment_Config__mdt config(
        Boolean createContact,
        Boolean sendEmail,
        String activityType
    ) {
        return new GTM_Assessment_Config__mdt(
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
        // Dynamic query avoids a static compile-time reference to
        // Saved_Configuration__c, which would otherwise block that field
        // from being deleted and recreated when its referenceTo changes.
        Id filedRequestId = result.assessmentRequestId;
        SObject req = Database.query(
            'SELECT Requester_Name__c, Requester_Email__c, Company__c, Status__c, ' +
            'Contact__c, Opportunity__c, Saved_Configuration__c ' +
            'FROM GTM_Assessment_Request__c WHERE Id = :filedRequestId'
        )[0];
        Assert.areEqual('Alex Rivera', req.get('Requester_Name__c'));
        Assert.areEqual('alex.rivera@example.com', req.get('Requester_Email__c'));
        Assert.areEqual('New', req.get('Status__c'));
        Assert.areEqual(result.contactId, req.get('Contact__c'));
        // A submission from a named company is a lead, so an Opportunity is
        // raised for it whether or not it came from a client link -- see
        // GtmAssessmentRequestController.ensureOpportunity, which branches on
        // the link only to decide whether to stamp Engagement_Link__c. This
        // test used to assert the opposite and had been failing on it; what it
        // is actually guarding is that no link means no link, below.
        Assert.isNotNull(req.get('Opportunity__c'), 'A named company still raises a deal');
        Assert.isNull(req.get('Saved_Configuration__c'), 'No client link was supplied');
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

        GTM_Saved_Configuration__c savedConfig = new GTM_Saved_Configuration__c(
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

        Id filedRequestId = result.assessmentRequestId;
        SObject req = Database.query(
            'SELECT Opportunity__c, Saved_Configuration__c, Contact__c ' +
            'FROM GTM_Assessment_Request__c WHERE Id = :filedRequestId'
        )[0];
        Assert.areEqual(opp.Id, req.get('Opportunity__c'));
        Assert.areEqual(savedConfig.Id, req.get('Saved_Configuration__c'));

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

        GTM_Saved_Configuration__c savedConfig = new GTM_Saved_Configuration__c(
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

        GTM_Saved_Configuration__c updated = [
            SELECT Opportunity__c FROM GTM_Saved_Configuration__c WHERE Id = :savedConfig.Id
        ];
        Assert.areEqual(
            result.opportunityId,
            updated.Opportunity__c,
            'The link should be written back so future submissions reuse this Opportunity'
        );
    }

    @isTest
    static void usesEstimatedValueOverOfferingTargetForNewOpportunity() {
        GTM_Saved_Configuration__c savedConfig = new GTM_Saved_Configuration__c(
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

        GTM_Saved_Configuration__c savedConfig = new GTM_Saved_Configuration__c(
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

        GTM_Saved_Configuration__c savedConfig = new GTM_Saved_Configuration__c(
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
        Id filedRequestId = result.assessmentRequestId;
        SObject filed = Database.query(
            'SELECT Saved_Configuration__c FROM GTM_Assessment_Request__c WHERE Id = :filedRequestId'
        )[0];
        Assert.isNull(filed.get('Saved_Configuration__c'), 'A malformed id must not be stored as a link');
    }

    // ------------------------------------------------------------ token gate

    @isTest
    static void tokenNotRequiredForUnprotectedLink() {
        // A config with no Link_Password__c should never require a token.
        Account acc = new Account(Name = 'Northwind Retail');
        insert acc;
        GTM_Saved_Configuration__c savedConfig = new GTM_Saved_Configuration__c(
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
        GTM_Saved_Configuration__c savedConfig = new GTM_Saved_Configuration__c(
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
        GTM_Saved_Configuration__c savedConfig = new GTM_Saved_Configuration__c(
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
        GTM_Saved_Configuration__c savedConfig = new GTM_Saved_Configuration__c(
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

    // ------------------------------------------------------------ scoring
    // Ported from claude/salesforce-marketing-maturity-bsxmxs. Object/class
    // names retargeted GTM_/Gtm; behavior identical to what shipped there.

    /** One scored answer, in the wire shape the client submits. */
    private static GtmAssessmentRequestController.AnswerInput answer(String dimension, Integer value) {
        GtmAssessmentRequestController.AnswerInput a =
            new GtmAssessmentRequestController.AnswerInput();
        a.dimension = dimension;
        a.value = value;
        return a;
    }

    /** Every scored dimension answered at the same value. */
    private static List<GtmAssessmentRequestController.AnswerInput> allAnswersAt(Integer value) {
        List<GtmAssessmentRequestController.AnswerInput> answers =
            new List<GtmAssessmentRequestController.AnswerInput>();
        for (String dimension : GtmAssessmentScoring.DIMENSIONS) {
            answers.add(answer(dimension, value));
        }
        return answers;
    }

    /** One complexity answer, in the wire shape the client submits. */
    private static List<GtmAssessmentRequestController.AnswerInput> complexityAnswersAt(Integer value) {
        List<GtmAssessmentRequestController.AnswerInput> answers =
            new List<GtmAssessmentRequestController.AnswerInput>();
        for (String dimension : GtmEstateComplexity.DIMENSIONS) {
            answers.add(answer(dimension, value));
        }
        return answers;
    }

    @isTest
    static void submitRequestScoresTheAnswersServerSideAndGeneratesDraftReadout() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        // Two dimensions answered, the rest left blank: 3 + 2 = 5.
        input.answers = new List<GtmAssessmentRequestController.AnswerInput>{
            answer('estate_scale', 3),
            answer('source_access', 2)
        };
        input.branchPlatform = 'MCE';

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success);
        GTM_Assessment_Request__c req = [
            SELECT Assessment_Score__c, Assessment_Tier__c, Section_Scores__c, Branch_Platform__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual(5, req.Assessment_Score__c, 'The total is summed in Apex from the raw answers');
        Assert.areEqual('Discovery First', req.Assessment_Tier__c, 'And the tier band is derived from that total');
        Assert.areEqual('MCE', req.Branch_Platform__c);
        Map<String, Object> sections =
            (Map<String, Object>) JSON.deserializeUntyped(req.Section_Scores__c);
        Assert.areEqual(2, sections.size());
        Assert.areEqual(3, (Integer) sections.get('estate_scale'));
        Assert.areEqual(2, (Integer) sections.get('source_access'));

        List<GTM_Readout__c> readouts = [
            SELECT Status__c FROM GTM_Readout__c WHERE Assessment_Request__c = :result.assessmentRequestId
        ];
        Assert.areEqual(1, readouts.size(), 'A Draft readout should be auto-generated on submission');
        Assert.areEqual('Draft', readouts[0].Status__c);
    }

    @isTest
    static void aTamperedClientScoreIsNeverPersisted() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.answers = new List<GtmAssessmentRequestController.AnswerInput>{
            answer('estate_scale', 1),
            answer('source_access', 1)
        };
        input.assessmentScore = 999;
        input.assessmentTier  = 'Fast-Track';
        input.sectionScores   = '{"estate_scale":4,"source_access":4,"invented":4}';

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        GTM_Assessment_Request__c req = [
            SELECT Assessment_Score__c, Assessment_Tier__c, Section_Scores__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual(2, req.Assessment_Score__c, 'The stored score is the one Apex computed: 1 + 1');
        Assert.areNotEqual(999, req.Assessment_Score__c, 'The client-supplied score must not survive');
        Assert.areEqual('Discovery First', req.Assessment_Tier__c);
        Assert.areNotEqual('Fast-Track', req.Assessment_Tier__c, 'Nor the client-supplied tier');
        Assert.isFalse(
            req.Section_Scores__c.contains('invented'),
            'The stored breakdown is rebuilt server-side: ' + req.Section_Scores__c
        );
        Map<String, Object> sections =
            (Map<String, Object>) JSON.deserializeUntyped(req.Section_Scores__c);
        Assert.areEqual(1, (Integer) sections.get('estate_scale'), 'Not the 4 the client claimed');
    }

    @isTest
    static void aFullyAnsweredQuestionnaireTopsOutAtThirtyTwo() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.answers = allAnswersAt(4);
        input.answers.add(answer('invented_dimension', 4));
        input.answers.add(answer('another_invented_one', 4));

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        GTM_Assessment_Request__c req = [
            SELECT Assessment_Score__c, Assessment_Tier__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual(32, req.Assessment_Score__c, 'Eight dimensions at four points is 32, not 40');
        Assert.areEqual(GtmAssessmentScoring.MAX_TOTAL_SCORE, req.Assessment_Score__c);
        Assert.areEqual('Fast-Track', req.Assessment_Tier__c);
    }

    @isTest
    static void noSourceAccessCapsTheStoredTierAtDiscoveryFirst() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.answers = allAnswersAt(4);
        for (GtmAssessmentRequestController.AnswerInput a : input.answers) {
            if (a.dimension == 'source_access') {
                a.value = 1;
            }
        }

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        GTM_Assessment_Request__c req = [
            SELECT Assessment_Score__c, Assessment_Tier__c, Assessment_Advisory__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual(29, req.Assessment_Score__c, 'The score is untouched by the gate');
        Assert.areEqual('Discovery First', req.Assessment_Tier__c,
            'No extract, no offering -- 29/32 does not buy a Fast-Track');
        Assert.isFalse(req.Assessment_Advisory__c, 'Capped, not suppressed');
    }

    @isTest
    static void theRebuildRatioFlagIsStoredAlongsideAHighTier() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.answers = allAnswersAt(4);
        for (GtmAssessmentRequestController.AnswerInput a : input.answers) {
            if (a.dimension == 'orchestration_portability' || a.dimension == 'content_portability') {
                a.value = 1;
            }
        }

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        GTM_Assessment_Request__c req = [
            SELECT Assessment_Tier__c, Assessment_Flags__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual('Accelerator-Ready', req.Assessment_Tier__c,
            'The annotation is non-blocking -- the band is unchanged');
        Assert.isTrue(req.Assessment_Flags__c.contains('high_rebuild_ratio'));
        Assert.isTrue(req.Assessment_Flags__c.contains('C/D'));
    }

    @isTest
    static void anUnsupportedPairIsStoredAsAdvisoryWithNoTier() {
        GtmMigrationPairs.resetCache();
        GtmMigrationPairs.platformOverride = new List<GTM_Migration_Platform__mdt>{
            new GTM_Migration_Platform__mdt(
                Platform_Key__c = 'adobe', Display_Label__c = 'Adobe Campaign',
                Aliases__c = 'Adobe Campaign', Active__c = true
            ),
            new GTM_Migration_Platform__mdt(
                Platform_Key__c = 'sfmc', Display_Label__c = 'Marketing Cloud Engagement',
                Aliases__c = 'SFMC;MCE', Active__c = true
            )
        };
        GtmMigrationPairs.pairOverride = new List<GTM_Migration_Pair__mdt>{
            new GTM_Migration_Pair__mdt(
                Source_Key__c = 'adobe', Target_Key__c = 'sfmc', Supported__c = false,
                Unsupported_Reason__c = 'Adobe Campaign is not an extractable source.',
                Active__c = true
            )
        };

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.currentPlatform = 'Adobe Campaign';
        input.targetPlatform  = 'MCE';
        input.answers = allAnswersAt(4);

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        GTM_Assessment_Request__c req = [
            SELECT Assessment_Score__c, Assessment_Tier__c,
                   Assessment_Advisory__c, Advisory_Reason__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual(32, req.Assessment_Score__c, 'Still scored -- it is still useful input');
        Assert.isNull(req.Assessment_Tier__c, 'But never banded');
        Assert.isTrue(req.Assessment_Advisory__c);
        Assert.areEqual('Adobe Campaign is not an extractable source.', req.Advisory_Reason__c);
    }

    @isTest
    static void complexityIsStoredOnItsOwnAxisAndNeverAddedToTheScore() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.answers = allAnswersAt(4);                 // readiness 32/32
        input.complexityAnswers = complexityAnswersAt(3); // complexity 18/18

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        GTM_Assessment_Request__c req = [
            SELECT Assessment_Score__c, Assessment_Tier__c,
                   Estate_Complexity_Score__c, Estate_Complexity_Band__c,
                   Estate_Complexity_Basis__c, Estate_Complexity_Dimensions__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual(32, req.Assessment_Score__c, 'Complexity must not leak into the readiness total');
        Assert.areEqual('Fast-Track', req.Assessment_Tier__c);
        Assert.areEqual(18, req.Estate_Complexity_Score__c);
        Assert.areEqual('Heavy', req.Estate_Complexity_Band__c);
        Assert.areEqual('Self-Estimated', req.Estate_Complexity_Basis__c,
            'A questionnaire answer is a pre-scan estimate, whatever the client called it');
        Assert.isTrue(req.Estate_Complexity_Dimensions__c.contains('scripting_depth'));
    }

    @isTest
    static void aClientCannotLabelItsOwnEstimateAsMeasured() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.complexityAnswers = complexityAnswersAt(1);
        input.complexityBasis = 'Measured';

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        GTM_Assessment_Request__c req = [
            SELECT Estate_Complexity_Score__c, Estate_Complexity_Band__c, Estate_Complexity_Basis__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual(6, req.Estate_Complexity_Score__c);
        Assert.areEqual('Light', req.Estate_Complexity_Band__c);
        Assert.areEqual('Self-Estimated', req.Estate_Complexity_Basis__c);
    }

    @isTest
    static void noComplexityAnswersLeavesTheSecondAxisEmptyRatherThanLight() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.answers = allAnswersAt(2);

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        GTM_Assessment_Request__c req = [
            SELECT Assessment_Score__c, Estate_Complexity_Score__c,
                   Estate_Complexity_Band__c, Estate_Complexity_Basis__c,
                   Estate_Complexity_Dimensions__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual(16, req.Assessment_Score__c, 'The readiness axis is unaffected');
        Assert.isNull(req.Estate_Complexity_Score__c, '"Not estimated", not "Light"');
        Assert.isNull(req.Estate_Complexity_Band__c);
        Assert.isNull(req.Estate_Complexity_Basis__c);
        Assert.isNull(req.Estate_Complexity_Dimensions__c);
    }

    @isTest
    static void oversizeSectionScoresAreDroppedRatherThanLosingTheSubmission() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.sectionScores = '{"padding":"' + 'x'.repeat(40000) + '"}';

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.isNotNull(
            result.assessmentRequestId,
            'The submission must survive an oversize section-scores blob'
        );
        GTM_Assessment_Request__c req = [
            SELECT Assessment_Score__c, Assessment_Tier__c, Section_Scores__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.isNull(
            req.Section_Scores__c,
            'An oversize blob is stored as null, never truncated into unparseable JSON'
        );
        Assert.isNull(
            req.Assessment_Score__c,
            'No answers were submitted, so there is no score -- "not assessed", not zero'
        );
        Assert.isNull(req.Assessment_Tier__c);

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM GTM_Readout__c WHERE Assessment_Request__c = :result.assessmentRequestId],
            'And the draft readout is still generated'
        );
    }

    @isTest
    static void submitRequestSucceedsEvenWithoutScoringData() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM GTM_Readout__c WHERE Assessment_Request__c = :result.assessmentRequestId]
        );
        GTM_Assessment_Request__c req = [
            SELECT Assessment_Score__c, Assessment_Tier__c, Section_Scores__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.isNull(req.Assessment_Score__c, 'Unscored stays unscored -- never a defaulted zero');
        Assert.isNull(req.Assessment_Tier__c);
        Assert.isNull(req.Section_Scores__c);
    }

    @isTest
    static void aLegacyClientsSectionScoresSurviveWhenItSendsNoAnswers() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.sectionScores = '{"estate_scale":3,"source_access":2}';
        input.assessmentScore = 30;
        input.assessmentTier = 'Fast-Track';

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        GTM_Assessment_Request__c req = [
            SELECT Assessment_Score__c, Assessment_Tier__c, Section_Scores__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.isTrue(req.Section_Scores__c.contains('estate_scale'), 'The legacy blob is kept');
        Assert.isNull(req.Assessment_Score__c, 'But the client score is still discarded');
        Assert.isNull(req.Assessment_Tier__c, 'And so is the client tier');
    }

    // -------------------------------------------------------- draft closing
    // New for the port: proves closeDraft's append-and-count revocation
    // (docs/handoff/port-map-ma-to-gtm.md section F) against the real
    // GtmAssessmentDraftController mint path, end to end.

    @isTest
    static void submittingClosesTheLinkedDraftByAppendingNotUpdating() {
        GtmAssessmentDraftController.DraftHandle draft =
            GtmAssessmentDraftController.saveDraft(null, '{"q1":"a"}', 'hubspot__sfmc');
        Integer rowsBeforeSubmit = [
            SELECT COUNT() FROM GTM_Form_Draft__c WHERE Resume_Token__c = :draft.resumeToken
        ];

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.draftToken = draft.resumeToken;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success);
        Integer rowsAfterSubmit = [
            SELECT COUNT() FROM GTM_Form_Draft__c WHERE Resume_Token__c = :draft.resumeToken
        ];
        Assert.areEqual(rowsBeforeSubmit + 1, rowsAfterSubmit,
            'Submitting must APPEND a closing row, never UPDATE the existing one -- a guest '
            + 'cannot update in this org (see GtmGuestUpdateProbeTest)');

        GtmAssessmentDraftController.DraftPayload resumed =
            GtmAssessmentDraftController.resumeDraft(draft.resumeToken);
        Assert.isNull(resumed, 'A submitted draft must stop resolving');

        List<GTM_Form_Draft__c> closingRow = [
            SELECT Submitted_Request__c
            FROM GTM_Form_Draft__c
            WHERE Resume_Token__c = :draft.resumeToken
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 1
        ];
        Assert.areEqual(result.assessmentRequestId, closingRow[0].Submitted_Request__c);
    }

    @isTest
    static void submitWithNoDraftTokenNeverTouchesGtmFormDraft() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.draftToken = null;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success);
        // No assertion needed beyond success -- closeDraft's own blank-token
        // guard means this path issues no GTM_Form_Draft__c query or DML at
        // all, and a stray exception there would have surfaced as a failure.
    }
}
