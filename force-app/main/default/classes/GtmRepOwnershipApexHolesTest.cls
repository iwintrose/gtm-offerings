/**
 * ISSUE #rep-ownership-lockdown-2-apex-holes
 *
 * Owner rule: a rep may view/edit/delete only their own links and everything
 * tied to them; admins see all. Two peer reps (Standard User + the
 * GTM_Offering_User permission set) and an admin (GTM_Offering_Admin), each
 * exercised through System.runAs.
 *
 * Covers the three Apex holes (GtmStageActionsController,
 * GtmArCasePanelController, GtmAgentGetConfigState) plus regression guards
 * proving GtmSavedConfigurationController's non-owner behaviour.
 */
@IsTest
private class GtmRepOwnershipApexHolesTest {

    private static User makeUser(String alias, String permSetName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'Own ' + alias, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :permSetName LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    private class Fixture {
        User repA; User repB; User adminUser;
        GTM_Saved_Configuration__c linkA; GTM_Saved_Configuration__c linkB;
        Id requestA; Id requestB;
    }

    private static Id seedRequest(Id linkId, Id ownerId, String name, String email, String company) {
        SObject req = Schema.getGlobalDescribe().get('GTM_Assessment_Request__c').newSObject();
        req.put('Saved_Configuration__c', linkId);
        req.put('Requester_Name__c', name);
        req.put('Requester_Email__c', email);
        req.put('Company__c', company);
        req.put('OwnerId', ownerId);
        insert req;
        return req.Id;
    }

    private static GTM_Saved_Configuration__c seedLink(Id ownerId, String company, String stage) {
        GTM_Saved_Configuration__c l = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Presentation_Stage__c = stage,
            Generated_URL__c = 'https://example.com/configurator?company=' + company,
            Link_Password__c = 'Pw' + company,
            Config_Payload__c = '{"company":"' + company + '","industry":"tech"}',
            Company__c = company,
            Active__c = true,
            OwnerId = ownerId
        );
        insert l;
        return l;
    }

    private static Fixture build() {
        Fixture f = new Fixture();
        f.repA = makeUser('gtmoa1', 'GTM_Offering_User');
        f.repB = makeUser('gtmob1', 'GTM_Offering_User');
        f.adminUser = makeUser('gtmoad', 'GTM_Offering_Admin');
        f.linkA = seedLink(f.repA.Id, 'AlphaCo', 'Draft');
        f.linkB = seedLink(f.repB.Id, 'BetaCo', 'Draft');
        f.requestA = seedRequest(f.linkA.Id, f.repA.Id, 'Ann Alpha', 'ann@alpha.example.com', 'AlphaCo');
        f.requestB = seedRequest(f.linkB.Id, f.repB.Id, 'Bob Beta', 'bob@beta.example.com', 'BetaCo');
        return f;
    }

    private static Id seedReadoutAndCase(Id requestId, Id ownerId, String subject) {
        GTM_Readout__c r = new GTM_Readout__c(
            Assessment_Request__c = requestId, Status__c = 'Draft', Offering_Key__c = 'migration-accelerator',
            OwnerId = ownerId
        );
        insert r;
        insert new Case(Readout__c = r.Id, Subject = subject);
        return r.Id;
    }

    private static String stageOf(Id linkId) {
        return [SELECT Presentation_Stage__c FROM GTM_Saved_Configuration__c WHERE Id = :linkId].Presentation_Stage__c;
    }

    // ── Hole 1: GtmStageActionsController ─────────────────────────────────────

    @IsTest
    static void stageContext_nonOwnerGetsEmptyContext_ownerAndAdminGetData() {
        Fixture f = build();
        Test.startTest();
        GtmStageActionsController.StageContext other;
        GtmStageActionsController.StageContext own;
        GtmStageActionsController.StageContext adm;
        System.runAs(f.repA) {
            other = GtmStageActionsController.getStageContext(f.linkB.Id);
            own = GtmStageActionsController.getStageContext(f.linkA.Id);
        }
        System.runAs(f.adminUser) {
            adm = GtmStageActionsController.getStageContext(f.linkB.Id);
        }
        Test.stopTest();

        Assert.isNull(other.stage, 'Non-owner must not see the stage');
        Assert.isNull(other.sharedUrl);
        Assert.isNull(other.assessmentId);
        Assert.isNull(other.requesterName, 'Requester PII must not leak');
        Assert.isNull(other.requesterEmail);
        Assert.isNull(other.requesterCompany);
        Assert.areEqual('Draft', own.stage);
        Assert.areEqual('Ann Alpha', own.requesterName);
        Assert.areEqual('ann@alpha.example.com', own.requesterEmail);
        Assert.areEqual('Bob Beta', adm.requesterName, 'Admin sees every link');
    }

    @IsTest
    static void advanceStage_nonOwnerGetsFriendlyErrorAndNothingChanges() {
        Fixture f = build();
        Test.startTest();
        String caught;
        System.runAs(f.repA) {
            try {
                GtmStageActionsController.advanceStage(f.linkB.Id, 'Sent');
            } catch (AuraHandledException e) {
                caught = e.getMessage();
            }
        }
        Test.stopTest();
        Assert.isNotNull(caught, 'Non-owner advance must throw AuraHandledException (and only that)');
        Assert.areEqual('You can only change the stage of your own links.', caught);
        Assert.areEqual('Draft', stageOf(f.linkB.Id), 'Other rep\'s stage must be unchanged');
    }

    @IsTest
    static void advanceStage_genuineDmlFailureGetsNeutralMessage() {
        Fixture f = build();
        String caught;
        Test.startTest();
        System.runAs(f.repA) {
            GtmStageActionsController.forceUpdateFailureForTest = true;
            try {
                GtmStageActionsController.advanceStage(f.linkA.Id, 'Sent');
            } catch (AuraHandledException e) {
                caught = e.getMessage();
            }
        }
        Test.stopTest();
        Assert.isNotNull(caught);
        Assert.isFalse(caught.contains('your own links'), 'Owner must not get the ownership message');
        Assert.areEqual('Draft', stageOf(f.linkA.Id));
    }

    @IsTest
    static void advanceStage_ownerAndAdminSucceed() {
        Fixture f = build();
        Test.startTest();
        System.runAs(f.repA) {
            GtmStageActionsController.advanceStage(f.linkA.Id, 'In_Review');
        }
        System.runAs(f.adminUser) {
            GtmStageActionsController.advanceStage(f.linkB.Id, 'In_Review');
        }
        Test.stopTest();
        Assert.areEqual('In_Review', stageOf(f.linkA.Id));
        Assert.areEqual('In_Review', stageOf(f.linkB.Id));
    }

    @IsTest
    static void sendProposalEmails_worksWhenRunningUserCannotSeeRequest() {
        Fixture f = build();
        Test.startTest();
        System.runAs(f.repA) {
            GtmStageActionsController.SendEmailInput inp = new GtmStageActionsController.SendEmailInput();
            inp.configId = f.linkB.Id;
            inp.sharedUrl = 'https://example.com/x';
            GtmStageActionsController.sendProposalEmails(
                new List<GtmStageActionsController.SendEmailInput>{ inp });
            // Not asserting the send count: it depends on org email settings.
            // Reaching here means the elevated read and send path did not throw.
        }
        Test.stopTest();
    }

    // ── Hole 2: GtmArCasePanelController ──────────────────────────────────────

    @IsTest
    static void caseForRequest_nonOwnerNull_ownerAndAdminGetCase() {
        Fixture f = build();
        seedReadoutAndCase(f.requestA, f.repA.Id, 'Alpha review');
        seedReadoutAndCase(f.requestB, f.repB.Id, 'Beta review');
        GtmArCasePanelController.CaseDTO other;
        GtmArCasePanelController.CaseDTO own;
        GtmArCasePanelController.CaseDTO adm;
        Test.startTest();
        System.runAs(f.repA) {
            other = GtmArCasePanelController.getCaseForRequest(f.requestB);
            own = GtmArCasePanelController.getCaseForRequest(f.requestA);
        }
        System.runAs(f.adminUser) {
            adm = GtmArCasePanelController.getCaseForRequest(f.requestB);
        }
        Test.stopTest();
        Assert.isNull(other, 'Non-owner must get null, not another rep\'s Case');
        Assert.isNotNull(own);
        Assert.areEqual('Alpha review', own.subject);
        Assert.isNotNull(adm);
        Assert.areEqual('Beta review', adm.subject);
    }

    // ── Hole 3: GtmAgentGetConfigState ────────────────────────────────────────

    private static GtmAgentGetConfigState.Output state(Id linkId) {
        GtmAgentGetConfigState.Input inp = new GtmAgentGetConfigState.Input();
        inp.configId = linkId;
        return GtmAgentGetConfigState.execute(new List<GtmAgentGetConfigState.Input>{ inp })[0];
    }

    @IsTest
    static void configState_nonOwnerGetsBlankDefaults_ownerAndAdminGetPayload() {
        Fixture f = build();
        GtmAgentGetConfigState.Output other;
        GtmAgentGetConfigState.Output own;
        GtmAgentGetConfigState.Output adm;
        Test.startTest();
        System.runAs(f.repA) {
            other = state(f.linkB.Id);
            own = state(f.linkA.Id);
        }
        System.runAs(f.adminUser) {
            adm = state(f.linkB.Id);
        }
        Test.stopTest();
        Assert.areEqual('', other.company, 'Other rep\'s payload must not be returned');
        Assert.areEqual('', other.industry);
        Assert.isNotNull(other.availableIndustries);
        Assert.areEqual('AlphaCo', own.company);
        Assert.areEqual('BetaCo', adm.company);
    }

    // ── GtmSavedConfigurationController regression guards (non-owner) ─────────

    @IsTest
    static void savedConfig_setActiveNonOwnerThrowsAndRecordUnchanged() {
        Fixture f = build();
        Boolean threw = false;
        Test.startTest();
        System.runAs(f.repA) {
            try {
                GtmSavedConfigurationController.setActive(f.linkB.Id, false);
            } catch (AuraHandledException e) {
                threw = true;
            }
            GtmSavedConfigurationController.setActive(f.linkA.Id, false);
        }
        Test.stopTest();
        Assert.isTrue(threw);
        Assert.isTrue([SELECT Active__c FROM GTM_Saved_Configuration__c WHERE Id = :f.linkB.Id].Active__c);
        Assert.isFalse([SELECT Active__c FROM GTM_Saved_Configuration__c WHERE Id = :f.linkA.Id].Active__c);
    }

    @IsTest
    static void savedConfig_regeneratePasswordNonOwnerThrowsAndPasswordUnchanged() {
        Fixture f = build();
        Boolean threw = false;
        String ownResult;
        Test.startTest();
        System.runAs(f.repA) {
            try {
                GtmSavedConfigurationController.regeneratePassword(f.linkB.Id);
            } catch (AuraHandledException e) {
                threw = true;
            }
            ownResult = GtmSavedConfigurationController.regeneratePassword(f.linkA.Id);
        }
        Test.stopTest();
        Assert.isTrue(threw);
        Assert.areEqual('PwBetaCo',
            [SELECT Link_Password__c FROM GTM_Saved_Configuration__c WHERE Id = :f.linkB.Id].Link_Password__c);
        Assert.isNotNull(ownResult);
    }

    @IsTest
    static void savedConfig_deleteNonOwnerThrowsAndRecordSurvives() {
        Fixture f = build();
        Boolean threw = false;
        Test.startTest();
        System.runAs(f.repA) {
            try {
                GtmSavedConfigurationController.deleteConfiguration(f.linkB.Id);
            } catch (AuraHandledException e) {
                threw = true;
            }
            GtmSavedConfigurationController.deleteConfiguration(f.linkA.Id);
        }
        Test.stopTest();
        Assert.isTrue(threw);
        Assert.areEqual(1, [SELECT COUNT() FROM GTM_Saved_Configuration__c WHERE Id = :f.linkB.Id]);
        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Saved_Configuration__c WHERE Id = :f.linkA.Id]);
    }

    @IsTest
    static void savedConfig_getConfigurationNonOwnerReturnsNull() {
        Fixture f = build();
        GtmSavedConfigurationController.SavedConfigView other;
        GtmSavedConfigurationController.SavedConfigView own;
        Test.startTest();
        System.runAs(f.repA) {
            other = GtmSavedConfigurationController.getConfiguration(f.linkB.Id);
            own = GtmSavedConfigurationController.getConfiguration(f.linkA.Id);
        }
        Test.stopTest();
        Assert.isNull(other);
        Assert.isNotNull(own);
        Assert.areEqual('AlphaCo', own.company);
    }

    @IsTest
    static void savedConfig_resendEngagementLinkNonOwnerThrowsAndSendsNothing() {
        Fixture f = build();
        Boolean threw = false;
        Test.startTest();
        System.runAs(f.repA) {
            try {
                GtmSavedConfigurationController.resendEngagementLink(f.linkB.Id);
            } catch (AuraHandledException e) {
                threw = true;
            }
            Assert.areEqual(0, Limits.getEmailInvocations(), 'No email for a non-owner');
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    @IsTest
    static void savedConfig_saveConfigurationByIdNonOwnerCannotUpdate() {
        Fixture f = build();
        GtmSavedConfigurationController.SaveInput input = new GtmSavedConfigurationController.SaveInput();
        input.recordId = f.linkB.Id;
        input.offering = 'migration-accelerator';
        input.generatedUrl = 'https://example.com/hijacked';
        input.company = 'Hijack';
        Test.startTest();
        System.runAs(f.repA) {
            try {
                GtmSavedConfigurationController.saveConfiguration(input);
            } catch (Exception e) {
                // Any refusal is acceptable; the assertion below is the contract.
            }
        }
        Test.stopTest();
        GTM_Saved_Configuration__c b = [
            SELECT Generated_URL__c, Company__c FROM GTM_Saved_Configuration__c WHERE Id = :f.linkB.Id
        ];
        Assert.areEqual('https://example.com/configurator?company=BetaCo', b.Generated_URL__c);
        Assert.areEqual('BetaCo', b.Company__c);
    }
}
