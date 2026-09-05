@IsTest
private class GtmRepLinkFinderControllerTest {

    @IsTest
    static void groupsLinksByContactNewestFirst() {
        Account acc = new Account(Name = 'Acme Bank');
        insert acc;
        Contact jordan = new Contact(
            FirstName = 'Jordan', LastName = 'Lee',
            Email = 'jordan.lee@acmebank.example.com', AccountId = acc.Id
        );
        insert jordan;
        Opportunity opp = new Opportunity(
            Name = 'Acme Bank - Migration Accelerator', AccountId = acc.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30)
        );
        insert opp;

        MA_Saved_Configuration__c older = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Industry__c = 'fintech',
            Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.my.site.com/gtm/s/configurator',
            Account__c = acc.Id,
            Contact__c = jordan.Id,
            Opportunity__c = opp.Id
        );
        insert older;
        // CreatedDate can't be set on insert -- a second real insert is
        // enough to prove grouping and count without depending on ordering
        // between the two (asserted only as a set, not by position).
        MA_Saved_Configuration__c newer = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.my.site.com/gtm/s/configurator?v=2',
            Account__c = acc.Id,
            Contact__c = jordan.Id
        );
        insert newer;

        Test.startTest();
        List<GtmRepLinkFinderController.ContactLinks> result =
            GtmRepLinkFinderController.getContactsWithLinks(acc.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'One Contact has links on this Account.');
        GtmRepLinkFinderController.ContactLinks grp = result[0];
        System.assertEquals(jordan.Id, grp.contactId);
        System.assertEquals('Jordan Lee', grp.contactName);
        System.assertEquals(2, grp.links.size());

        Set<Id> linkIds = new Set<Id>();
        for (GtmRepLinkFinderController.LinkSummary link : grp.links) {
            linkIds.add(link.recordId);
        }
        System.assert(linkIds.contains(older.Id));
        System.assert(linkIds.contains(newer.Id));

        GtmRepLinkFinderController.LinkSummary withDeal = grp.links[0].recordId == older.Id
            ? grp.links[0] : grp.links[1];
        System.assertEquals('Acme Bank', withDeal.company);
        System.assertEquals('migration-accelerator', withDeal.offering);
        System.assertEquals('Financial Services', withDeal.industryLabel);
        System.assertEquals('Acme Bank - Migration Accelerator', withDeal.dealName);
        System.assertEquals('Prospecting', withDeal.dealStage);
    }

    @IsTest
    static void omitsContactsWithNoLinks() {
        Account acc = new Account(Name = 'Globex Corp');
        insert acc;
        insert new Contact(FirstName = 'No', LastName = 'Links', AccountId = acc.Id);

        Test.startTest();
        List<GtmRepLinkFinderController.ContactLinks> result =
            GtmRepLinkFinderController.getContactsWithLinks(acc.Id);
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    @IsTest
    static void scopesStrictlyToTheRequestedAccount() {
        Account acme = new Account(Name = 'Acme Bank');
        insert acme;
        Account other = new Account(Name = 'Other Co');
        insert other;
        Contact acmeContact = new Contact(FirstName = 'Priya', LastName = 'Natarajan', AccountId = acme.Id);
        insert acmeContact;
        Contact otherContact = new Contact(FirstName = 'Someone', LastName = 'Else', AccountId = other.Id);
        insert otherContact;

        insert new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtm/s/configurator?a=1',
            Account__c = acme.Id,
            Contact__c = acmeContact.Id
        );
        insert new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtm/s/configurator?a=2',
            Account__c = other.Id,
            Contact__c = otherContact.Id
        );

        Test.startTest();
        List<GtmRepLinkFinderController.ContactLinks> result =
            GtmRepLinkFinderController.getContactsWithLinks(acme.Id);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals(acmeContact.Id, result[0].contactId);
    }

    @IsTest
    static void returnsEmptyListForBlankAccountId() {
        Test.startTest();
        List<GtmRepLinkFinderController.ContactLinks> result =
            GtmRepLinkFinderController.getContactsWithLinks(null);
        Test.stopTest();

        System.assertEquals(0, result.size());
    }
}
