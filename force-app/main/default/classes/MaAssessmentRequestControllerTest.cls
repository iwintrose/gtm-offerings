@isTest
private class MaAssessmentRequestControllerTest {
    private static MaAssessmentRequestController.RequestInput sampleInput() {
        MaAssessmentRequestController.RequestInput input = new MaAssessmentRequestController.RequestInput();
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
        Boolean createLead,
        Boolean sendEmail,
        String activityType
    ) {
        return new MA_Assessment_Config__mdt(
            Create_Lead__c = createLead,
            Send_Email__c = sendEmail,
            Notify_Email__c = 'assessments@example.com',
            Lead_Source__c = 'Migration Accelerator',
            Activity_Type__c = activityType
        );
    }

    @isTest
    static void createsLeadAndTaskForNewEmail() {
        MaAssessmentRequestController.configOverride = config(true, false, 'Task');

        Test.startTest();
        MaAssessmentRequestController.RequestResult result =
            MaAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.isTrue(result.success, 'Submission should succeed');
        Assert.isTrue(result.leadCreated, 'A new Lead should have been created');

        Lead created = [
            SELECT FirstName, LastName, Email, Company, Title, LeadSource
            FROM Lead
            WHERE Id = :result.leadId
        ];
        Assert.areEqual('Alex', created.FirstName);
        Assert.areEqual('Rivera', created.LastName);
        Assert.areEqual('Northwind Retail', created.Company);
        Assert.areEqual('Migration Accelerator', created.LeadSource);

        List<Task> logged = [
            SELECT Subject, Status, Description FROM Task WHERE WhoId = :result.leadId
        ];
        Assert.areEqual(1, logged.size(), 'One activity should be logged');
        Assert.areEqual('Environment assessment request', logged[0].Subject);
        Assert.isTrue(
            logged[0].Description.contains('Oracle Eloqua'),
            'Activity should carry the submission detail'
        );
    }

    @isTest
    static void reusesExistingLeadAndFillsBlanksOnly() {
        Lead seeded = new Lead(
            LastName = 'Rivera',
            Company = 'Original Co',
            Email = 'alex.rivera@example.com'
        );
        insert seeded;

        MaAssessmentRequestController.configOverride = config(true, false, 'Task');

        Test.startTest();
        MaAssessmentRequestController.RequestResult result =
            MaAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.isFalse(result.leadCreated, 'Existing Lead should be reused');
        Assert.areEqual(seeded.Id, result.leadId);

        Lead after = [SELECT Company, Title, LeadSource FROM Lead WHERE Id = :seeded.Id];
        Assert.areEqual(
            'Original Co',
            after.Company,
            'An existing Company must not be overwritten'
        );
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
            [SELECT COUNT() FROM Lead WHERE Email = 'alex.rivera@example.com'],
            'No duplicate Lead should be created'
        );
    }

    @isTest
    static void logsEventWhenConfigured() {
        MaAssessmentRequestController.configOverride = config(true, false, 'Event');

        Test.startTest();
        MaAssessmentRequestController.RequestResult result =
            MaAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Event WHERE WhoId = :result.leadId],
            'An Event should be logged instead of a Task'
        );
    }

    @isTest
    static void skipsLeadWhenDisabled() {
        MaAssessmentRequestController.configOverride = config(false, false, 'Task');

        Test.startTest();
        MaAssessmentRequestController.RequestResult result =
            MaAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.isNull(result.leadId, 'No Lead should be created when disabled');
        Assert.areEqual(0, [SELECT COUNT() FROM Lead]);
    }

    @isTest
    static void sendsEmailWhenEnabled() {
        MaAssessmentRequestController.configOverride = config(false, true, 'Task');

        Test.startTest();
        MaAssessmentRequestController.RequestResult result =
            MaAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.isTrue(result.success, 'Submission should succeed with email on');
    }

    @isTest
    static void rejectsMissingName() {
        MaAssessmentRequestController.configOverride = config(true, false, 'Task');
        MaAssessmentRequestController.RequestInput input = sampleInput();
        input.name = '   ';

        Boolean threw = false;
        try {
            MaAssessmentRequestController.submitRequest(input);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'A blank name should be rejected');
    }

    @isTest
    static void rejectsMalformedEmail() {
        MaAssessmentRequestController.configOverride = config(true, false, 'Task');
        MaAssessmentRequestController.RequestInput input = sampleInput();
        input.email = 'not-an-email';

        Boolean threw = false;
        try {
            MaAssessmentRequestController.submitRequest(input);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'A malformed email should be rejected');
        Assert.areEqual(0, [SELECT COUNT() FROM Lead]);
    }

    @isTest
    static void rejectsNullInput() {
        Boolean threw = false;
        try {
            MaAssessmentRequestController.submitRequest(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Null input should be rejected');
    }

    @isTest
    static void fallsBackToCompanyPlaceholderWhenUnknown() {
        MaAssessmentRequestController.configOverride = config(true, false, 'Task');
        MaAssessmentRequestController.RequestInput input = sampleInput();
        input.company = null;
        input.prospect = null;

        Test.startTest();
        MaAssessmentRequestController.RequestResult result =
            MaAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Lead created = [SELECT Company FROM Lead WHERE Id = :result.leadId];
        Assert.areEqual('Unknown', created.Company);
    }

    @isTest
    static void usesSingleWordNameAsLastName() {
        MaAssessmentRequestController.configOverride = config(true, false, 'Task');
        MaAssessmentRequestController.RequestInput input = sampleInput();
        input.name = 'Cher';

        Test.startTest();
        MaAssessmentRequestController.RequestResult result =
            MaAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Lead created = [SELECT FirstName, LastName FROM Lead WHERE Id = :result.leadId];
        Assert.isNull(created.FirstName);
        Assert.areEqual('Cher', created.LastName);
    }

    @isTest
    static void readsDeployedConfigWhenNoOverride() {
        // Exercises the CMDT query path; the deployed Default record drives it.
        Test.startTest();
        MaAssessmentRequestController.RequestResult result =
            MaAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.isTrue(result.success, 'Deployed config should be readable');
    }

    @isTest
    static void createsAssessmentRequestRecord() {
        MaAssessmentRequestController.configOverride = config(true, false, 'Task');

        Test.startTest();
        MaAssessmentRequestController.RequestResult result =
            MaAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        Assert.isNotNull(
            result.assessmentRequestId,
            'A structured assessment request record should always be filed'
        );
        MA_Assessment_Request__c req = [
            SELECT Requester_Name__c, Requester_Email__c, Company__c, Status__c,
                   Lead__c, Opportunity__c, Saved_Configuration__c
            FROM MA_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual('Alex Rivera', req.Requester_Name__c);
        Assert.areEqual('alex.rivera@example.com', req.Requester_Email__c);
        Assert.areEqual('New', req.Status__c);
        Assert.areEqual(result.leadId, req.Lead__c);
        Assert.isNull(req.Opportunity__c, 'No client link was supplied');
        Assert.isNull(req.Saved_Configuration__c);
    }

    @isTest
    static void linksToOpportunityAndAttributesLeadViaSavedConfig() {
        Opportunity opp = new Opportunity(
            Name = 'Northwind Retail Migration',
            StageName = 'Qualification',
            CloseDate = Date.today().addMonths(2)
        );
        insert opp;

        MA_Saved_Configuration__c savedConfig = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Industry__c = 'Financial Services',
            Company__c = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/configurator?company=Northwind',
            Opportunity__c = opp.Id,
            OwnerId = UserInfo.getUserId()
        );
        insert savedConfig;

        MaAssessmentRequestController.configOverride = config(true, false, 'Task');
        MaAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = savedConfig.Id;

        Test.startTest();
        MaAssessmentRequestController.RequestResult result =
            MaAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.areEqual(opp.Id, result.opportunityId, 'Opportunity should carry through to the result');

        MA_Assessment_Request__c req = [
            SELECT Opportunity__c, Saved_Configuration__c, Lead__c
            FROM MA_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual(opp.Id, req.Opportunity__c);
        Assert.areEqual(savedConfig.Id, req.Saved_Configuration__c);

        Lead created = [SELECT OwnerId FROM Lead WHERE Id = :result.leadId];
        Assert.areEqual(
            UserInfo.getUserId(),
            created.OwnerId,
            'A new Lead should be owned by the rep who owns the client link, not left unassigned'
        );
    }

    @isTest
    static void failsOpenOnMalformedSavedRecordId() {
        MaAssessmentRequestController.configOverride = config(true, false, 'Task');
        MaAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = 'not-a-real-id';

        Test.startTest();
        MaAssessmentRequestController.RequestResult result =
            MaAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success, 'A bad savedRecordId should not block the submission');
        Assert.isNull(result.opportunityId);
    }
}
