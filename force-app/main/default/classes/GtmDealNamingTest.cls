/**
 * Both paths that create an opportunity must name it the same way. They did
 * not: one produced "MUCH Music - Assessment Follow-up" and the other
 * "Migration Accelerator — MUCH Music" for the same kind of record on the
 * same account. These pin the single convention so it cannot drift apart
 * again.
 */
@isTest
private class GtmDealNamingTest {

    private static Account makeAccount(String name) {
        Account a = new Account(Name = name);
        insert a;
        return a;
    }

    @isTest
    static void theNameIsClientThenOffering() {
        Account a = makeAccount('Naming Co');
        Test.startTest();
        String n = GtmDealNaming.nameFor('Naming Co', 'migration-accelerator', a.Id);
        Test.stopTest();

        System.assert(n.startsWith('Naming Co'),
            'the client leads, because the list is read by client: ' + n);
        System.assert(n.contains(' — '),
            'one dash, the em dash, in every name: ' + n);
        System.assert(!n.contains(' - '),
            'never the hyphen form the other path used: ' + n);
    }

    @isTest
    static void theOfferingComesFromMetadataNotFromCode() {
        Account a = makeAccount('Label Co');
        Test.startTest();
        String known   = GtmDealNaming.nameFor('Label Co', 'migration-accelerator', a.Id);
        String unknown = GtmDealNaming.nameFor('Label Co', 'no-such-offering', a.Id);
        String blank   = GtmDealNaming.nameFor('Label Co', '', a.Id);
        Test.stopTest();

        System.assertEquals('Migration Accelerator',
            GtmDealNaming.offeringLabel('migration-accelerator'),
            'a real offering resolves to its own label, not a hardcoded one');
        System.assert(known.endsWith('Migration Accelerator'), known);
        System.assert(unknown.endsWith('Assessment Follow-up'),
            'an unknown offering falls back rather than failing: ' + unknown);
        System.assert(blank.endsWith('Assessment Follow-up'), blank);
    }

    @isTest
    static void aSecondDealOnOneAccountIsDistinguishable() {
        Account a = makeAccount('Clash Co');
        String first = GtmDealNaming.nameFor('Clash Co', 'migration-accelerator', a.Id);
        insert new Opportunity(Name = first, AccountId = a.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30));

        Test.startTest();
        String second = GtmDealNaming.nameFor('Clash Co', 'migration-accelerator', a.Id);
        Test.stopTest();

        System.assertNotEquals(first, second,
            'two deals on one account must not carry the identical name');
        System.assert(second.startsWith(first), second);
    }

    @isTest
    static void bothCreationPathsProduceTheSameShape() {
        Account a = makeAccount('Both Paths Co');

        // The path a rep takes: saving an engagement link.
        GtmSavedConfigurationController.SaveInput in0 = new GtmSavedConfigurationController.SaveInput();
        in0.offering      = 'migration-accelerator';
        in0.industry      = 'media';
        in0.company       = 'Both Paths Co';
        in0.generatedUrl  = 'https://example.invalid/s/configurator';
        in0.configPayload = '{"ASSET_COUNT":"1"}';
        in0.accountId     = String.valueOf(a.Id);

        Test.startTest();
        Id linkId = GtmSavedConfigurationController.saveConfiguration(in0);
        Test.stopTest();

        Id oppId = [SELECT Opportunity__c FROM MA_Saved_Configuration__c WHERE Id = :linkId].Opportunity__c;
        String repName = [SELECT Name FROM Opportunity WHERE Id = :oppId].Name;

        System.assert(repName.startsWith('Both Paths Co — '),
            'the rep path must use the shared convention: ' + repName);
        System.assert(repName.contains('Migration Accelerator'),
            'and the offering label must be looked up, not hardcoded: ' + repName);
        System.assertEquals(GtmDealNaming.nameFor('Both Paths Co', 'migration-accelerator', null),
            repName.split(' \\(')[0],
            'what the rep path produced must match what the naming authority says');
    }
}
