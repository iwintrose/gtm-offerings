@IsTest
private class GtmLegacyConfigIdTest {

    @IsTest
    static void resolvesACurrentFormatIdStraightThrough() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Acme Bank'
        );
        insert cfg;

        Test.startTest();
        Id resolved = GtmLegacyConfigId.resolve(cfg.Id);
        Test.stopTest();

        Assert.areEqual(cfg.Id, resolved);
    }

    @IsTest
    static void resolvesALegacyIdViaTheStampedLookup() {
        // A real MA_Saved_Configuration__c id has a different key prefix
        // (object-specific), but any string that isn't a valid current-format
        // id exercises the same fallback path -- we can't insert an
        // MA_Saved_Configuration__c row here since that object no longer
        // exists post-cutover, so a synthetic legacy value stands in for one.
        String legacyId = 'a00XX0000012345AAA';
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Acme Bank',
            Legacy_Id__c = legacyId
        );
        insert cfg;

        Test.startTest();
        Id resolved = GtmLegacyConfigId.resolve(legacyId);
        Test.stopTest();

        Assert.areEqual(cfg.Id, resolved);
    }

    @IsTest
    static void returnsNullForAnUnknownLegacyId() {
        Test.startTest();
        Id resolved = GtmLegacyConfigId.resolve('a00XX0000000000AAA');
        Test.stopTest();

        Assert.isNull(resolved);
    }

    @IsTest
    static void returnsNullForBlankInput() {
        Assert.isNull(GtmLegacyConfigId.resolve(null));
        Assert.isNull(GtmLegacyConfigId.resolve(''));
        Assert.isNull(GtmLegacyConfigId.resolve('   '));
    }

    @IsTest
    static void returnsNullForGarbageInput() {
        Assert.isNull(GtmLegacyConfigId.resolve('not-an-id-and-not-legacy'));
    }
}
