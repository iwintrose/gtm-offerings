@isTest
private class GtmInstrumentTriggerHandlerTest {

    private static GTM_Instrument__c newInstrument(String offeringKey, String status) {
        GTM_Instrument__c instrument = new GTM_Instrument__c(
            Offering_Key__c = offeringKey,
            Name            = 'Trigger Test ' + offeringKey,
            Status__c       = status,
            Version__c      = 1
        );
        insert instrument;
        return instrument;
    }

    @isTest
    static void deleteBlockedWhileActive() {
        GTM_Instrument__c instrument = newInstrument('trigger-delete-active', 'Active');

        Test.startTest();
        Boolean threw = false;
        try {
            delete instrument;
        } catch (DmlException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('cannot be deleted'),
                'Expected the addError message on the Active delete block'
            );
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Deleting an Active instrument must be blocked');
    }

    @isTest
    static void deleteAllowedWhileDraft() {
        GTM_Instrument__c instrument = newInstrument('trigger-delete-draft', 'Draft');

        Test.startTest();
        delete instrument;
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Instrument__c WHERE Id = :instrument.Id]);
    }

    @isTest
    static void deleteAllowedWhileArchived() {
        GTM_Instrument__c instrument = newInstrument('trigger-delete-archived', 'Draft');
        instrument.Status__c = 'Archived';
        update instrument;

        Test.startTest();
        delete instrument;
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Instrument__c WHERE Id = :instrument.Id]);
    }

    @isTest
    static void archiveTransitionBlockedWhileActive() {
        GTM_Instrument__c instrument = newInstrument('trigger-archive-active', 'Active');
        instrument.Status__c = 'Archived';

        Test.startTest();
        Boolean threw = false;
        try {
            update instrument;
        } catch (DmlException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('cannot be archived directly'),
                'Expected the addError message on the Active archive block'
            );
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Archiving an Active instrument directly must be blocked');
        GTM_Instrument__c stored = [SELECT Status__c FROM GTM_Instrument__c WHERE Id = :instrument.Id];
        Assert.areEqual('Active', stored.Status__c);
    }

    @isTest
    static void archiveTransitionAllowedFromDraft() {
        GTM_Instrument__c instrument = newInstrument('trigger-archive-draft', 'Draft');
        instrument.Status__c = 'Archived';

        Test.startTest();
        update instrument;
        Test.stopTest();

        GTM_Instrument__c stored = [SELECT Status__c FROM GTM_Instrument__c WHERE Id = :instrument.Id];
        Assert.areEqual('Archived', stored.Status__c);
    }

    @isTest
    static void unrelatedUpdateOnActiveInstrumentNeverTripsGuard() {
        GTM_Instrument__c instrument = newInstrument('trigger-unrelated-update', 'Active');
        instrument.Name = 'Renamed while Active';

        Test.startTest();
        update instrument;
        Test.stopTest();

        GTM_Instrument__c stored = [SELECT Name, Status__c FROM GTM_Instrument__c WHERE Id = :instrument.Id];
        Assert.areEqual('Renamed while Active', stored.Name);
        Assert.areEqual('Active', stored.Status__c);
    }

    @isTest
    static void publishingAnUnrelatedNewInstrumentNeverTripsGuard() {
        newInstrument('trigger-guard-existing-active', 'Active');

        Test.startTest();
        GTM_Instrument__c freshInstrument = new GTM_Instrument__c(
            Offering_Key__c = 'trigger-guard-existing-active-v2',
            Name            = 'A brand new unrelated instrument',
            Status__c       = 'Draft',
            Version__c      = 1
        );
        insert freshInstrument;
        Test.stopTest();

        Assert.areEqual(1, [
            SELECT COUNT() FROM GTM_Instrument__c WHERE Id = :freshInstrument.Id
        ]);
    }
}
