/**
 * The wizard used to create a new Opportunity on every save, so a rep building
 * a second link for a client who already had a live deal got a competing one
 * created underneath them. These pin the behaviour that replaced it.
 */
@isTest
private class GtmSavedConfigurationDealTest {

    private static Account makeAccount() {
        Account a = new Account(Name = 'Deal Choice Co');
        insert a;
        return a;
    }

    private static Opportunity makeOpp(Id accountId, String name) {
        Opportunity o = new Opportunity(
            Name = name, AccountId = accountId,
            StageName = 'Qualification', CloseDate = Date.today().addDays(60)
        );
        insert o;
        return o;
    }

    private static GtmSavedConfigurationController.SaveInput baseInput(Id accountId) {
        GtmSavedConfigurationController.SaveInput in0 = new GtmSavedConfigurationController.SaveInput();
        in0.offering      = 'migration-accelerator';
        in0.industry      = 'media';
        in0.company       = 'Deal Choice Co';
        in0.generatedUrl  = 'https://example.invalid/s/configurator';
        in0.configPayload = '{"ASSET_COUNT":"10"}';
        in0.accountId     = String.valueOf(accountId);
        return in0;
    }

    @isTest
    static void choosingAnExistingDealReusesItRatherThanCreatingOne() {
        Account a = makeAccount();
        Opportunity existing = makeOpp(a.Id, 'Live deal already running');
        Integer before = [SELECT COUNT() FROM Opportunity WHERE AccountId = :a.Id];

        GtmSavedConfigurationController.SaveInput in0 = baseInput(a.Id);
        in0.opportunityId = String.valueOf(existing.Id);

        Test.startTest();
        Id linkId = GtmSavedConfigurationController.saveConfiguration(in0);
        Test.stopTest();

        MA_Saved_Configuration__c saved = [
            SELECT Opportunity__c FROM MA_Saved_Configuration__c WHERE Id = :linkId
        ];
        System.assertEquals(existing.Id, saved.Opportunity__c,
            'the link should be on the deal the rep chose');
        System.assertEquals(before, [SELECT COUNT() FROM Opportunity WHERE AccountId = :a.Id],
            'choosing an existing deal must not create another one');
    }

    @isTest
    static void choosingNothingStillCreatesANewDeal() {
        Account a = makeAccount();
        makeOpp(a.Id, 'Some other deal');
        Integer before = [SELECT COUNT() FROM Opportunity WHERE AccountId = :a.Id];

        Test.startTest();
        Id linkId = GtmSavedConfigurationController.saveConfiguration(baseInput(a.Id));
        Test.stopTest();

        System.assertEquals(before + 1, [SELECT COUNT() FROM Opportunity WHERE AccountId = :a.Id],
            'no choice means a new deal, which is what "A new deal" offers');
        System.assertNotEquals(null,
            [SELECT Opportunity__c FROM MA_Saved_Configuration__c WHERE Id = :linkId].Opportunity__c);
    }

    @isTest
    static void aDealOnAnotherAccountIsIgnored() {
        Account a = makeAccount();
        Account other = new Account(Name = 'Somebody Else');
        insert other;
        Opportunity theirs = makeOpp(other.Id, 'Not this client\'s deal');

        GtmSavedConfigurationController.SaveInput in0 = baseInput(a.Id);
        in0.opportunityId = String.valueOf(theirs.Id);

        Test.startTest();
        Id linkId = GtmSavedConfigurationController.saveConfiguration(in0);
        Test.stopTest();

        MA_Saved_Configuration__c saved = [
            SELECT Opportunity__c FROM MA_Saved_Configuration__c WHERE Id = :linkId
        ];
        System.assertNotEquals(theirs.Id, saved.Opportunity__c,
            'a stray id must not attach this link to another client\'s deal');
    }

    @isTest
    static void theDealListSaysWhichOnesAlreadyHaveALink() {
        Account a = makeAccount();
        Opportunity taken = makeOpp(a.Id, 'Deal with a link');
        Opportunity free  = makeOpp(a.Id, 'Deal with none');

        GtmSavedConfigurationController.SaveInput in0 = baseInput(a.Id);
        in0.opportunityId = String.valueOf(taken.Id);
        GtmSavedConfigurationController.saveConfiguration(in0);

        Test.startTest();
        List<GtmSavedConfigurationController.DealOption> deals =
            GtmSavedConfigurationController.getAccountDeals(String.valueOf(a.Id));
        Test.stopTest();

        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (GtmSavedConfigurationController.DealOption d : deals) {
            counts.put(d.opportunityId, d.linkCount);
        }
        System.assertEquals(1, counts.get(taken.Id), 'the deal with a link says so');
        System.assertEquals(0, counts.get(free.Id), 'the deal without one says so too');
    }
}
