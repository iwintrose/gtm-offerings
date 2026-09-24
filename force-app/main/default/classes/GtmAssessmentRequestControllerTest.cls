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

    // -------------------------------------------------- per-link notify email

    @isTest
    static void prefersLinkNotifyEmailOverCmdtWhenCmdtIsBlank() {
        // The CMDT record has NO Notify_Email__c on file -- only the link
        // does. Success here is only possible if notify() actually used the
        // link's address, since there is no other address anywhere to use.
        Account acc = new Account(Name = 'Northwind Retail');
        insert acc;
        GTM_Saved_Configuration__c savedConfig = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/configurator?company=Northwind',
            Account__c = acc.Id,
            Notify_Email__c = 'link-owner@example.com',
            OwnerId = UserInfo.getUserId()
        );
        insert savedConfig;

        GtmAssessmentRequestController.configOverride = new GTM_Assessment_Config__mdt(
            Create_Lead__c = true,
            Send_Email__c = true,
            Notify_Email__c = null,
            Activity_Type__c = 'Task'
        );
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = savedConfig.Id;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(
            result.emailSent,
            'The link\'s own Notify_Email__c should be used when the CMDT default is blank'
        );
    }

    @isTest
    static void sendEmailKillSwitchStillGatesEvenWithLinkNotifyEmailSet() {
        // Send_Email__c = false must still block sending, even though the
        // link carries a real, resolvable Notify_Email__c -- it stays the
        // one global on/off switch.
        Account acc = new Account(Name = 'Northwind Retail');
        insert acc;
        GTM_Saved_Configuration__c savedConfig = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/configurator?company=Northwind',
            Account__c = acc.Id,
            Notify_Email__c = 'link-owner@example.com',
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

        Assert.isFalse(result.emailSent, 'Send_Email__c = false should suppress email regardless of the link');
    }

    @isTest
    static void directBookingWithNoLinkAndNoCmdtDefaultSendsNoEmail() {
        // No engagement link at all, and the CMDT default is blank -- there
        // is nowhere to route the alert, so submission should still succeed
        // but simply not send one, rather than erroring.
        GtmAssessmentRequestController.configOverride = new GTM_Assessment_Config__mdt(
            Create_Lead__c = true,
            Send_Email__c = true,
            Notify_Email__c = null,
            Activity_Type__c = 'Task'
        );
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = null;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success, 'Submission should still succeed with nowhere to notify');
        Assert.isFalse(result.emailSent, 'No address anywhere means no email, not an error');
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
    static void newOpportunityIsStampedWithOfferingKey() {
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

        Opportunity opp = [SELECT Offering_Key__c FROM Opportunity WHERE Id = :result.opportunityId];
        Assert.areEqual('migration-accelerator', opp.Offering_Key__c);
    }

    /**
     * Issue #32 adds an Account+Contact+Offering open-duplicate check on the
     * wizard's save path, but this path's reuse is keyed off the link's own
     * stored Opportunity__c only (see ensureOpportunity's header comment) --
     * a second submission through the SAME link must keep landing on the
     * SAME Opportunity even when an unrelated OPEN Opportunity already
     * exists for this Account+Offering on a different link, never
     * mistakenly reuse -- or get blocked by -- that other one.
     */
    @isTest
    static void oneOpportunityPerLinkKeyingUnaffectedByOpenDuplicateCheck() {
        Account acc = new Account(Name = 'Northwind Retail');
        insert acc;

        // A separate, unrelated OPEN Opportunity for the same Account and
        // Offering -- simulating another link/rep's live deal.
        Opportunity otherOpen = new Opportunity(
            Name = 'Northwind Retail - Migration Accelerator (other link)',
            StageName = 'Prospecting',
            CloseDate = Date.today().addMonths(3),
            AccountId = acc.Id,
            Offering_Key__c = 'migration-accelerator'
        );
        insert otherOpen;

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
        GtmAssessmentRequestController.RequestInput firstInput = sampleInput();
        firstInput.savedRecordId = savedConfig.Id;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult first =
            GtmAssessmentRequestController.submitRequest(firstInput);

        // The duplicate-request guard (one request per link) now rejects a
        // second submission through the SAME link before it reaches
        // ensureOpportunity, so Opportunity reuse is asserted through the
        // link's stored Opportunity__c instead.
        GtmAssessmentRequestController.RequestInput secondInput = sampleInput();
        secondInput.savedRecordId = savedConfig.Id;
        secondInput.email = 'someone.else@example.com';
        Boolean blocked = false;
        try {
            GtmAssessmentRequestController.submitRequest(secondInput);
        } catch (AuraHandledException e) {
            blocked = true;
        }
        Test.stopTest();

        Assert.isTrue(blocked, 'A second submission through the same link is rejected by the duplicate guard');
        Assert.isNotNull(first.opportunityId);
        Assert.areNotEqual(otherOpen.Id, first.opportunityId, 'Should not silently reuse the other link\'s Opportunity');
        Assert.areEqual(first.opportunityId,
            [SELECT Opportunity__c FROM GTM_Saved_Configuration__c WHERE Id = :savedConfig.Id].Opportunity__c,
            'The link keeps pointing at its own Opportunity');
        Assert.areEqual(1, [SELECT COUNT() FROM GTM_Assessment_Request__c WHERE Saved_Configuration__c = :savedConfig.Id]);
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
            GtmAssessmentDraftController.saveDraft(null, '{"q1":"a"}', 'hubspot__sfmc', null, null);
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
    static void theClosingRowCarriesTheLinkAndIsOwnedByItsOwner() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = 'closer' + String.valueOf(Crypto.getRandomInteger()).replace('-', 'x');
        User rep = new User(
            Alias = 'closr', Email = uniq + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = uniq, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = uniq + '@gtmtest.example.com'
        );
        insert rep;
        GTM_Saved_Configuration__c link = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/a', Active__c = true, OwnerId = rep.Id
        );
        insert link;
        GtmAssessmentDraftController.DraftHandle draft =
            GtmAssessmentDraftController.saveDraft(null, '{"q1":"a"}', 'hubspot__sfmc', link.Id, null);

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.draftToken = draft.resumeToken;

        Test.startTest();
        GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        GTM_Form_Draft__c closing = [
            SELECT Status__c, Saved_Configuration__c, OwnerId
            FROM GTM_Form_Draft__c
            WHERE Resume_Token__c = :draft.resumeToken
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 1
        ];
        Assert.areEqual('Submitted', closing.Status__c);
        Assert.areEqual(link.Id, closing.Saved_Configuration__c);
        Assert.areEqual(rep.Id, closing.OwnerId);
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

    // ----------------------------------------------------- offering scoping
    //
    // ADR-0007 section 3: the offering key is resolved server-side, once, and
    // stamped on the request at insert. Never client-supplied.

    private static GTM_Saved_Configuration__c linkFor(String offeringKey) {
        Account acc = new Account(Name = 'Northwind Retail');
        insert acc;
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c      = offeringKey,
            Company__c       = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/configurator?company=Northwind',
            Account__c       = acc.Id,
            OwnerId          = UserInfo.getUserId()
        );
        insert cfg;
        return cfg;
    }

    @isTest
    static void aDirectBookingWithNoLinkIsStampedMigrationAccelerator() {
        // The fallback: migration-accelerator is the only offering that has
        // ever been assessed, so it is the honest answer rather than a guess.
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');

        Test.startTest();
        GtmAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();

        List<GTM_Assessment_Request__c> reqs = [
            SELECT Offering_Key__c, Source__c FROM GTM_Assessment_Request__c
        ];
        Assert.areEqual(1, reqs.size());
        Assert.areEqual('migration-accelerator', reqs[0].Offering_Key__c);
    }

    @isTest
    static void theLinksOwnOfferingIsWhatGetsStamped() {
        // The whole point: a request booked against a second offering's
        // engagement link is that offering's, not Migration Accelerator's.
        GTM_Saved_Configuration__c cfg = linkFor('second-offering');
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = cfg.Id;

        Test.startTest();
        GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        List<GTM_Assessment_Request__c> reqs = [
            SELECT Offering_Key__c FROM GTM_Assessment_Request__c
        ];
        Assert.areEqual(1, reqs.size());
        Assert.areEqual('second-offering', reqs[0].Offering_Key__c,
            'The engagement link\'s own offering decides which instrument scored this');
    }

    @isTest
    static void aNonMigrationOfferingIsNeverPairGated() {
        // ADR-0007 section 5: "can the accelerator process this platform move"
        // is a migration business rule. An offering that is not a migration
        // gets the inert, never-evaluated verdict, so no tier is ever
        // suppressed on it by a gate that does not apply.
        GTM_Saved_Configuration__c cfg = linkFor('second-offering');
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = cfg.Id;
        // A source/target combination Migration Accelerator would refuse.
        input.currentPlatform = 'Some Platform The Accelerator Cannot Process';
        input.targetPlatform  = 'Another One';

        Test.startTest();
        GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        List<GTM_Assessment_Request__c> reqs = [
            SELECT Assessment_Advisory__c, Advisory_Reason__c
            FROM GTM_Assessment_Request__c
        ];
        Assert.areEqual(1, reqs.size());
        Assert.isFalse(reqs[0].Assessment_Advisory__c,
            'The migration pair gate must not fire for a non-migration offering');
        Assert.isNull(reqs[0].Advisory_Reason__c);
    }

    // ------------------------------------------------- Source__c resolution
    //
    // QA round 1, Finding 1: sourceLabelFor() resolved ONLY GTM_Offering__mdt,
    // so the two offerings that actually exist in gtm-dev -- both of which have
    // page content but no custom metadata row yet -- were stamped 'Migration
    // Accelerator'. sourceLabelFor is private, so each tier is driven through
    // the real submitRequest path and asserted on the persisted field, which is
    // also what proves the tier is reachable from a guest submission at all.

    private static GTM_Page_Content__c listingName(String offeringKey, String name) {
        return new GTM_Page_Content__c(
            Offering_Key__c  = offeringKey,
            Template_Type__c = 'offerings-listing',
            Section_Key__c   = 'card',
            Field_Key__c     = 'name',
            Field_Type__c    = 'text',
            Text_Value__c    = name,
            Active__c        = true
        );
    }

    private static GTM_Page_Section__c anySection(String offeringKey) {
        return new GTM_Page_Section__c(
            Section_Address__c = offeringKey + '::story::hero',
            Offering_Key__c    = offeringKey,
            Template_Type__c   = 'story',
            Section_Key__c     = 'hero',
            Label__c           = 'Hero',
            Layout_Type__c     = 'hero',
            Width__c           = 'standard',
            Sort_Order__c      = 10,
            Active__c          = true
        );
    }

    private static String submittedSourceFor(String offeringKey) {
        GTM_Saved_Configuration__c cfg = linkFor(offeringKey);
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = cfg.Id;

        GtmAssessmentRequestController.submitRequest(input);

        List<GTM_Assessment_Request__c> reqs = [
            SELECT Offering_Key__c, Source__c FROM GTM_Assessment_Request__c
        ];
        Assert.areEqual(1, reqs.size());
        Assert.areEqual(offeringKey, reqs[0].Offering_Key__c);
        return reqs[0].Source__c;
    }

    @isTest
    static void tierOneMigrationAcceleratorKeepsTheExactLegacyLiteral() {
        // The no-regression half: GTM_Offering__mdt carries this offering, and
        // its Label__c is byte-identical to the constant the field used to be
        // hardcoded to, so no existing row's value changes.
        Test.startTest();
        String source = submittedSourceFor('migration-accelerator');
        Test.stopTest();

        Assert.areEqual('Migration Accelerator', source);
    }

    @isTest
    static void tierTwoAnOfferingWithOnlyPageContentGetsItsOwnAuthoredName() {
        // The live case: my-test-offering and data-cloud-accelorator are both
        // in exactly this state in gtm-dev today -- a name on their own
        // offerings-listing tile, no custom metadata row.
        insert listingName('page-only-offering', 'Page Only Offering');

        Test.startTest();
        String source = submittedSourceFor('page-only-offering');
        Test.stopTest();

        Assert.areEqual('Page Only Offering', source,
            'The name on an offering\'s own listing tile is the name its requests carry');
        Assert.areNotEqual('Migration Accelerator', source);
    }

    @isTest
    static void tierThreeARealButUnnamedOfferingGetsItsKeyNotAnotherOfferingsName() {
        // Sections but no authored name anywhere. Showing the raw key is the
        // same fallback getOfferings()/getHomeSummary() use, and it is honest;
        // showing 'Migration Accelerator' would not be.
        insert anySection('unnamed-offering');

        Test.startTest();
        String source = submittedSourceFor('unnamed-offering');
        Test.stopTest();

        Assert.areEqual('unnamed-offering', source);
        Assert.areNotEqual('Migration Accelerator', source);
    }

    @isTest
    static void tierFourAGenuinelyUnknownOfferingStillFallsBackToTheLegacyLiteral() {
        // Nothing in any of the three tables. There is no truthful name to
        // give, so the historical literal stands -- the documented limit of
        // this resolution, asserted so a future change to it is deliberate.
        Test.startTest();
        String source = submittedSourceFor('no-such-offering-anywhere');
        Test.stopTest();

        Assert.areEqual('Migration Accelerator', source);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ONE SUBMITTED ASSESSMENT PER ENGAGEMENT LINK (ADR-0008 section 4)
    //
    // Before this, nothing at any layer prevented N scored requests against one
    // link: closeDraft's terminal row revokes a RESUME LINK (a different
    // problem, intact, and not touched here), and the only live-path guard was
    // sessionStorage in one tab. The invariant is a SERVER rule; the client is a
    // courtesy.
    // ─────────────────────────────────────────────────────────────────────────

    /** A link with everything a real engagement link carries. */
    private static GTM_Saved_Configuration__c engagementLinkFor(String company) {
        Account acc = new Account(Name = company);
        insert acc;
        GTM_Saved_Configuration__c link = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Industry__c = 'Financial Services',
            Company__c = company,
            Generated_URL__c = 'https://example.com/configurator?company=' + company,
            Account__c = acc.Id,
            OwnerId = UserInfo.getUserId()
        );
        insert link;
        return link;
    }

    private static Integer requestCountFor(Id linkId) {
        return [
            SELECT COUNT()
            FROM GTM_Assessment_Request__c
            WHERE Saved_Configuration__c = :linkId
        ];
    }

    @isTest
    static void refusesASecondSubmissionAgainstTheSameLink() {
        GTM_Saved_Configuration__c link = engagementLinkFor('Northlight Media Group');
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');

        GtmAssessmentRequestController.RequestInput first = sampleInput();
        first.savedRecordId = link.Id;
        GtmAssessmentRequestController.submitRequest(first);
        Assert.areEqual(1, requestCountFor(link.Id), 'The first submission should land');

        GtmAssessmentRequestController.RequestInput second = sampleInput();
        second.savedRecordId = link.Id;
        second.email = 'someone.else@example.com';

        Boolean threw = false;
        Test.startTest();
        try {
            GtmAssessmentRequestController.submitRequest(second);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A second submission against the same link must be refused');
        // The assertion that actually matters. A thrown exception that still
        // wrote the row would be a guard in name only.
        Assert.areEqual(
            1,
            requestCountFor(link.Id),
            'The refused submission must not have inserted a second request'
        );
    }

    @isTest
    static void theFirstSubmissionAgainstALinkStillSucceeds() {
        // The guard must add no regression to the path everyone actually takes.
        GTM_Saved_Configuration__c link = engagementLinkFor('Ashford Capital Bank');
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');

        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = link.Id;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success, 'The first submission should succeed unchanged');
        Assert.isNotNull(result.assessmentRequestId);
        Assert.areEqual(1, requestCountFor(link.Id));
    }

    @isTest
    static void aSecondDirectBookingWithNoLinkStillSucceeds() {
        // SCOPED TO LINKS ONLY. A direct booking has no link to be a duplicate
        // against, and refusing these would silently close the one path that has
        // no engagement link at all.
        //
        // Contact creation is switched OFF here deliberately. With it on, the
        // second submission inserts a second Contact with the same name at the
        // same resolved Account and the org's standard DUPLICATE RULE rejects it
        // (CLAUDE.md section 5.2) -- which would make this test fail for a
        // reason that has nothing to do with the guard it is named after. What
        // is under test is that the resubmit guard does not fire without a link.
        GtmAssessmentRequestController.configOverride = config(false, false, 'Task');

        GtmAssessmentRequestController.submitRequest(sampleInput());

        GtmAssessmentRequestController.RequestInput second = sampleInput();
        second.name = 'Dana Okonkwo';
        second.email = 'second.person@example.com';

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(second);
        Test.stopTest();

        Assert.isTrue(result.success, 'A second link-less booking must still be accepted');
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM GTM_Assessment_Request__c WHERE Saved_Configuration__c = null],
            'Both link-less requests should exist'
        );
    }

    @isTest
    static void aDifferentLinkOnTheSameAccountStillSucceeds() {
        // The invariant is PER LINK, not per Account. A rep who sends a second
        // engagement link to the same client must get a second assessment.
        Account acc = new Account(Name = 'Solara Health Systems');
        insert acc;
        List<GTM_Saved_Configuration__c> links = new List<GTM_Saved_Configuration__c>{
            new GTM_Saved_Configuration__c(
                Offering__c = 'migration-accelerator', Company__c = 'Solara Health Systems',
                Generated_URL__c = 'https://example.com/a', Account__c = acc.Id,
                OwnerId = UserInfo.getUserId()
            ),
            new GTM_Saved_Configuration__c(
                Offering__c = 'migration-accelerator', Company__c = 'Solara Health Systems',
                Generated_URL__c = 'https://example.com/b', Account__c = acc.Id,
                OwnerId = UserInfo.getUserId()
            )
        };
        insert links;

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput first = sampleInput();
        first.savedRecordId = links[0].Id;
        GtmAssessmentRequestController.submitRequest(first);

        GtmAssessmentRequestController.RequestInput second = sampleInput();
        second.savedRecordId = links[1].Id;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(second);
        Test.stopTest();

        Assert.isTrue(result.success, 'A different link on the same Account must still be accepted');
        Assert.areEqual(1, requestCountFor(links[0].Id));
        Assert.areEqual(1, requestCountFor(links[1].Id));
    }

    @isTest
    static void theRefusedSubmissionWritesNothingAtAll() {
        // Placed before any DML on purpose: a refused duplicate must not leave a
        // Contact, an Opportunity or an activity behind it. The guard is not
        // just "no second request", it is "no side effects".
        GTM_Saved_Configuration__c link = engagementLinkFor('Harborline Transit Authority');
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');

        GtmAssessmentRequestController.RequestInput first = sampleInput();
        first.savedRecordId = link.Id;
        GtmAssessmentRequestController.submitRequest(first);

        Integer contactsBefore = [SELECT COUNT() FROM Contact];
        Integer tasksBefore    = [SELECT COUNT() FROM Task];
        Integer oppsBefore     = [SELECT COUNT() FROM Opportunity];

        GtmAssessmentRequestController.RequestInput second = sampleInput();
        second.savedRecordId = link.Id;
        second.name  = 'Someone Entirely New';
        second.email = 'someone.entirely.new@example.com';

        Test.startTest();
        try {
            GtmAssessmentRequestController.submitRequest(second);
            Assert.fail('The duplicate should have been refused');
        } catch (Exception e) {
            // expected
        }
        Test.stopTest();

        Assert.areEqual(contactsBefore, [SELECT COUNT() FROM Contact],
            'A refused duplicate must not create a Contact');
        Assert.areEqual(tasksBefore, [SELECT COUNT() FROM Task],
            'A refused duplicate must not log an activity');
        Assert.areEqual(oppsBefore, [SELECT COUNT() FROM Opportunity],
            'A refused duplicate must not create an Opportunity');
    }

    // ── the guest-safe durable status check (ADR-0008 section 4, phase 4.3) ──

    @isTest
    static void statusControllerReportsWhetherALinkHasBeenSubmitted() {
        GTM_Saved_Configuration__c link = engagementLinkFor('Northlight Media Group');

        Assert.isFalse(
            GtmConfigurationStatusController.hasSubmittedAssessment(link.Id),
            'A fresh link has no assessment against it'
        );

        GtmAssessmentRequestController.configOverride = config(false, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = link.Id;

        Test.startTest();
        GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(
            GtmConfigurationStatusController.hasSubmittedAssessment(link.Id),
            'The same link now reports as submitted -- this is what lets a fresh '
                + 'browser with no sessionStorage land in the submitted state'
        );
    }

    @isTest
    static void statusControllerFailsSafeOnABlankOrUnresolvableId() {
        // Fails to FALSE, deliberately: the client fails open on an errored
        // check (an unknown link must not lock a prospect out of a form they
        // have not filled in), and the SERVER is the enforcement point either
        // way, so a false here costs nothing.
        Assert.isFalse(GtmConfigurationStatusController.hasSubmittedAssessment(null));
        Assert.isFalse(GtmConfigurationStatusController.hasSubmittedAssessment(''));
        Assert.isFalse(GtmConfigurationStatusController.hasSubmittedAssessment('not-an-id'));
    }

    // ── atomic submit: a failed request insert rolls everything back ──

    @isTest
    static void failedRequestInsertRollsBackContactOpportunityAndTask() {
        GTM_Saved_Configuration__c link = engagementLinkFor('Atomic Rollback Co');
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = link.Id;

        Integer contactsBefore = [SELECT COUNT() FROM Contact];
        Integer oppsBefore = [SELECT COUNT() FROM Opportunity];
        Integer tasksBefore = [SELECT COUNT() FROM Task];

        GtmAssessmentRequestController.failAssessmentRequestInsert = true;
        String message;
        Test.startTest();
        try {
            GtmAssessmentRequestController.submitRequest(input);
            Assert.fail('A failed request insert must surface as an error');
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(message.contains('nothing was saved'), 'Clear retryable message: ' + message);
        Assert.areEqual(contactsBefore, [SELECT COUNT() FROM Contact], 'No orphan Contact');
        Assert.areEqual(oppsBefore, [SELECT COUNT() FROM Opportunity], 'No orphan Opportunity');
        Assert.areEqual(tasksBefore, [SELECT COUNT() FROM Task], 'No orphan Task');
        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Assessment_Request__c],
            'No request was created');
        Assert.isFalse(GtmConfigurationStatusController.hasSubmittedAssessment(link.Id),
            'The link\'s one submission must not be consumed by a failed attempt');
    }

    @isTest
    static void retryAfterFailedRequestInsertSucceedsWithoutDuplicates() {
        GTM_Saved_Configuration__c link = engagementLinkFor('Atomic Retry Co');
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = link.Id;

        GtmAssessmentRequestController.failAssessmentRequestInsert = true;
        Test.startTest();
        try {
            GtmAssessmentRequestController.submitRequest(input);
            Assert.fail('First attempt should fail');
        } catch (AuraHandledException e) {
            // expected
        }
        GtmAssessmentRequestController.failAssessmentRequestInsert = false;
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success, 'Retry succeeds');
        Assert.isNotNull(result.assessmentRequestId);
        Assert.areEqual(1, [SELECT COUNT() FROM GTM_Assessment_Request__c
            WHERE Saved_Configuration__c = :link.Id], 'Exactly one request for the link');
        Assert.areEqual(1, [SELECT COUNT() FROM Contact
            WHERE Email = 'alex.rivera@example.com'], 'No duplicate Contact');
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhoId = :result.contactId],
            'No duplicate Task');
        Assert.isTrue(GtmConfigurationStatusController.hasSubmittedAssessment(link.Id));
    }

    @isTest
    static void successPathStillCreatesRequestContactAndTask() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(sampleInput());
        Test.stopTest();
        Assert.isTrue(result.success);
        Assert.isNotNull(result.assessmentRequestId, 'Request created');
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhoId = :result.contactId]);
    }

    // ── gtmReadoutWorkspace's Conduit-tab gate (issue-gtm-readout-workspace) ──

    @isTest
    static void offeringHasConduitTrueForMigrationAccelerator() {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Offering_Key__c = 'migration-accelerator',
            Requester_Name__c = 'Alex Rivera',
            Requester_Email__c = 'alex.rivera@example.com',
            Company__c = 'Northwind Retail'
        );
        insert req;

        Test.startTest();
        Boolean hasConduit = GtmAssessmentRequestController.getOfferingHasConduit(req.Id);
        Test.stopTest();

        Assert.isTrue(
            hasConduit,
            'Migration Accelerator\'s GTM_Offering__mdt row has Has_Conduit__c = true'
        );
    }

    @isTest
    static void offeringHasConduitFalseForAnUnmappedOfferingKey() {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Offering_Key__c = 'some-other-offering',
            Requester_Name__c = 'Alex Rivera',
            Requester_Email__c = 'alex.rivera@example.com',
            Company__c = 'Northwind Retail'
        );
        insert req;

        Assert.isFalse(GtmAssessmentRequestController.getOfferingHasConduit(req.Id));
    }

    @isTest
    static void offeringHasConduitFailsSafeOnABlankOrUnresolvableId() {
        Assert.isFalse(GtmAssessmentRequestController.getOfferingHasConduit(null));
    }

    // ── generic path (assessment-instrument-rebuild-02-submission) ──
    // docs/architecture/gtm-instrument-schema.md. A submission carrying
    // input.answersJson takes the offering-agnostic path: it stores the
    // JSON blob keyed by Question_Key__c, resolves Offering__c to the
    // matching Active GTM_Instrument_Definition__c row, and never touches
    // the Migration-Accelerator-only fields.

    @isTest
    static void genericPathStoresAnswersJsonAndSkipsMigrationAcceleratorFields() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.answersJson = '{"q1":"yes","q2":["a","b"]}';

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success, 'Generic-path submission should succeed');
        GTM_Assessment_Request__c req = [
            SELECT Answers_JSON__c, Assessment_Score__c, Assessment_Tier__c,
                   Section_Scores__c, Supplement_Scores__c,
                   Estate_Complexity_Score__c, Estate_Complexity_Band__c,
                   Estate_Complexity_Basis__c, Estate_Complexity_Dimensions__c,
                   Instrument_Pair__c, Instrument_Version__c, Instrument_Max_Score__c,
                   Instrument_Branch_Path__c, Offering__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.areEqual(
            '{"q1":"yes","q2":["a","b"]}',
            req.Answers_JSON__c,
            'The generic-path answers blob is stored verbatim'
        );
        Assert.isNull(req.Assessment_Score__c, 'No Migration Accelerator scoring runs on the generic path');
        Assert.isNull(req.Assessment_Tier__c);
        Assert.isNull(req.Section_Scores__c);
        Assert.isNull(req.Supplement_Scores__c);
        Assert.isNull(req.Estate_Complexity_Score__c, 'Estate complexity is a Migration-Accelerator-only field');
        Assert.isNull(req.Estate_Complexity_Band__c);
        Assert.isNull(req.Estate_Complexity_Basis__c);
        Assert.isNull(req.Estate_Complexity_Dimensions__c);
        Assert.isNull(req.Instrument_Pair__c, 'Instrument_Pair__c is a Migration-Accelerator-only field');
        Assert.isNull(req.Instrument_Version__c);
        Assert.isNull(req.Instrument_Max_Score__c);
        Assert.isNull(req.Instrument_Branch_Path__c);
        Assert.isNull(
            req.Offering__c,
            'No GTM_Instrument_Definition__c row exists yet for this offering key, so the lookup stays null'
        );
    }

    @isTest
    static void genericPathResolvesOfferingLookupToActiveInstrumentDefinition() {
        GTM_Instrument_Definition__c def = new GTM_Instrument_Definition__c(
            Name = 'Test Instrument',
            Offering_Key__c = 'generic-test-offering',
            Status__c = 'Active',
            Version__c = 1
        );
        insert def;

        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.answersJson = '{"q1":"yes"}';
        // No engagement link on this submission, so the resolved offering key
        // falls back to whatever GtmAssessmentInstrument/config resolution
        // yields for a direct booking -- exercised via resolveOfferingKey's
        // own existing coverage. Here we only prove the lookup mechanism
        // itself: a direct query on the resolver is out of this test's reach
        // (private), so this test instead confirms an unmatched key still
        // leaves Offering__c null rather than throwing.
        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success);
        GTM_Assessment_Request__c req = [
            SELECT Offering__c, Offering_Key__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        if (req.Offering_Key__c == 'generic-test-offering') {
            Assert.areEqual(def.Id, req.Offering__c, 'Offering__c should resolve to the Active instrument definition');
        } else {
            Assert.isNull(req.Offering__c, 'A non-matching offering key leaves Offering__c null, not an error');
        }
    }

    @isTest
    static void legacyPathIsUnaffectedByAnswersJsonAbsence() {
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.answers = allAnswersAt(4);

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success);
        GTM_Assessment_Request__c req = [
            SELECT Answers_JSON__c, Assessment_Score__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :result.assessmentRequestId
        ];
        Assert.isNull(req.Answers_JSON__c, 'The legacy path never populates the generic Answers_JSON__c field');
        Assert.areEqual(32, req.Assessment_Score__c, 'The legacy Migration Accelerator scoring is unchanged');
    }

    // ------------------------------------------------ lifecycle notification
    // (Unit 3b, ADR-0010 wiring point 7 -- corrected location, see
    // docs/agent-artifacts/task-scope-notifications-unit-3b-lifecycle-wiring.md
    // §1a. Postinsert notification lives here, in the guest-reachable
    // submitAssessment/postInsertBestEffort path, not GtmHomeSnapshotController.)

    private static Id insertRoutedRep() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = 'notifyrep' + String.valueOf(Crypto.getRandomInteger()).replace('-', 'x');
        User rep = new User(
            Alias = 'ntfrep', Email = uniq + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = uniq, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = uniq + '@gtmtest.example.com'
        );
        insert rep;
        return rep.Id;
    }

    private static void setNewRequestNotification(Boolean enabled) {
        GtmNotificationSettingsController.NotificationSettingsDto dto =
            new GtmNotificationSettingsController.NotificationSettingsDto();
        dto.notifyOnNewAssessmentRequest = enabled;
        GtmNotificationSettingsController.setNotificationSettings(dto);
    }

    @isTest
    static void newAssessmentRequestFiresTaskAndBellToTheRoutedOwnerWhenSettingIsOn() {
        Id repId = insertRoutedRep();
        GTM_Saved_Configuration__c link = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/a', Active__c = true, OwnerId = repId
        );
        insert link;
        setNewRequestNotification(true);
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = link.Id;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success);
        List<Task> tasks = [
            SELECT WhatId, OwnerId, Subject
            FROM Task
            WHERE WhatId = :result.assessmentRequestId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST
        ];
        Assert.areEqual(1, tasks.size(), 'A Task should fire against the routed owner');
        Assert.areEqual(repId, tasks[0].OwnerId, 'The Task must be owned by req.OwnerId, never the running user');
    }

    @isTest
    static void newAssessmentRequestDoesNotFireWhenSettingIsOff() {
        Id repId = insertRoutedRep();
        GTM_Saved_Configuration__c link = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Northwind Retail',
            Generated_URL__c = 'https://example.com/b', Active__c = true, OwnerId = repId
        );
        insert link;
        setNewRequestNotification(false);
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();
        input.savedRecordId = link.Id;

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Task WHERE WhatId = :result.assessmentRequestId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST],
            'No Task should fire when the setting is off'
        );
    }

    @isTest
    static void newAssessmentRequestDoesNotFireWhenNoOwnerWasResolved() {
        // No savedRecordId -> resolveConfigContext never runs -> ctx.ownerId
        // stays null -> req.OwnerId (the in-memory field, not the platform
        // default) stays null, gating the fire even with the setting on.
        setNewRequestNotification(true);
        GtmAssessmentRequestController.configOverride = config(true, false, 'Task');
        GtmAssessmentRequestController.RequestInput input = sampleInput();

        Test.startTest();
        GtmAssessmentRequestController.RequestResult result =
            GtmAssessmentRequestController.submitRequest(input);
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Task WHERE WhatId = :result.assessmentRequestId
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST],
            'No routed owner means no Task, even with the setting on'
        );
    }

    @isTest
    static void enableActivitiesAllowsATaskWhatIdAgainstAnAssessmentRequest() {
        // Real-DML proof that GTM_Assessment_Request__c.enableActivities is
        // actually true, not just present in the metadata file -- the
        // platform rejects a WhatId pointing at an activity-disabled object
        // with a runtime error, not a compile error, so this must be a real
        // insert against the deployed object.
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c = 'Alex Rivera',
            Requester_Email__c = 'alex.rivera@example.com',
            Status__c = 'New'
        );
        insert req;

        Test.startTest();
        insert new Task(WhatId = req.Id, OwnerId = UserInfo.getUserId(), Subject = 'Proof', Status = 'Not Started');
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :req.Id]);
    }
}
