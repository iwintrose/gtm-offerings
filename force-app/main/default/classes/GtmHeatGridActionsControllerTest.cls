@IsTest
private class GtmHeatGridActionsControllerTest {

    private static User createUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'HeatAction ' + alias, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    @IsTest
    static void createFollowUpTaskInsertsOneTaskAgainstTheOpportunity() {
        User rep = createUser('hgact1');
        Account acc = new Account(Name = 'Follow Up Co');
        Opportunity opp;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert acc;
            opp = new Opportunity(
                Name = 'Follow Up Deal', AccountId = acc.Id,
                StageName = 'Prospecting', CloseDate = Date.today().addMonths(1)
            );
            insert opp;
        }

        System.runAs(rep) {
            Test.startTest();
            Id taskId = GtmHeatGridActionsController.createFollowUpTask(opp.Id, 'Follow Up Co');
            Test.stopTest();

            Task t = [SELECT Subject, WhatId, OwnerId, Status FROM Task WHERE Id = :taskId];
            Assert.areEqual(opp.Id, t.WhatId);
            Assert.areEqual(rep.Id, t.OwnerId);
            Assert.isTrue(t.Subject.contains('Follow Up Co'));
            Assert.areEqual('Not Started', t.Status);
        }
    }

    @IsTest
    static void createFollowUpTaskRequiresAnOpportunity() {
        User rep = createUser('hgact2');
        System.runAs(rep) {
            try {
                GtmHeatGridActionsController.createFollowUpTask(null, 'No Opp Co');
                Assert.fail('expected an AuraHandledException for a null Opportunity id');
            } catch (AuraHandledException e) {
                // The message is sanitized by the platform for AuraHandledException,
                // so only the fact that it threw is asserted here.
                Assert.isTrue(true);
            }
        }
    }
}
