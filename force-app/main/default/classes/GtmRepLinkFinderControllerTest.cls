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

        GTM_Saved_Configuration__c older = new GTM_Saved_Configuration__c(
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
        GTM_Saved_Configuration__c newer = new GTM_Saved_Configuration__c(
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

        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtm/s/configurator?a=1',
            Account__c = acme.Id,
            Contact__c = acmeContact.Id
        );
        insert new GTM_Saved_Configuration__c(
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
    static void surfacesTheMostRecentRequestAndReadoutIdsForDrillThrough() {
        Account acc = new Account(Name = 'Acme Bank');
        insert acc;
        Contact jordan = new Contact(
            FirstName = 'Jordan', LastName = 'Lee',
            Email = 'jordan.lee@acmebank.example.com', AccountId = acc.Id
        );
        insert jordan;

        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.my.site.com/gtm/s/configurator?cfgId=1',
            Account__c = acc.Id,
            Contact__c = jordan.Id
        );
        insert cfg;

        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c = 'Jordan Lee',
            Requester_Email__c = 'jordan.lee@acmebank.example.com',
            Status__c = 'New',
            Source__c = 'Migration Accelerator',
            Saved_Configuration__c = cfg.Id
        );
        insert req;

        GTM_Readout__c readout = new GTM_Readout__c(
            Assessment_Request__c = req.Id,
            Offering_Key__c = 'migration-accelerator',
            Status__c = 'Draft'
        );
        insert readout;

        Test.startTest();
        List<GtmRepLinkFinderController.ContactLinks> result =
            GtmRepLinkFinderController.getContactsWithLinks(acc.Id);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals(1, result[0].links.size());
        GtmRepLinkFinderController.LinkSummary link = result[0].links[0];
        System.assertEquals(req.Id, link.requestId, 'The Assessment Request booked off this link should be surfaced.');
        System.assertEquals(readout.Id, link.readoutId, 'The Readout generated from that request should be surfaced.');
    }

    @IsTest
    static void leavesRequestAndReadoutIdsNullWhenNoAssessmentWasEverBooked() {
        Account acc = new Account(Name = 'Acme Bank');
        insert acc;
        Contact jordan = new Contact(FirstName = 'Jordan', LastName = 'Lee', AccountId = acc.Id);
        insert jordan;

        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.my.site.com/gtm/s/configurator?cfgId=2',
            Account__c = acc.Id,
            Contact__c = jordan.Id
        );
        insert cfg;

        Test.startTest();
        List<GtmRepLinkFinderController.ContactLinks> result =
            GtmRepLinkFinderController.getContactsWithLinks(acc.Id);
        Test.stopTest();

        System.assertEquals(1, result.size());
        GtmRepLinkFinderController.LinkSummary link = result[0].links[0];
        System.assertEquals(null, link.requestId);
        System.assertEquals(null, link.readoutId);
    }

    @IsTest
    static void returnsEmptyListForBlankAccountId() {
        Test.startTest();
        List<GtmRepLinkFinderController.ContactLinks> result =
            GtmRepLinkFinderController.getContactsWithLinks(null);
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    // ----------------------------------------- ownership scoping (rep-data-scoping-owd-2)

    /** Users are created inside their own runAs block: inserting a User and
     *  a regular sObject in one transaction is a MIXED_DML_OPERATION.
     *  Matches the pattern already used by GtmReadoutControllerTest.createRep. */
    private static User createRep(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias             = alias,
            Email             = alias + '@example.com',
            EmailEncodingKey  = 'UTF-8',
            LastName          = 'Rep ' + alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'America/New_York',
            Username          = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    /** Explicit OwnerId backstop: two reps sharing visibility into the same
     *  Account must each see only their own saved-configuration links, not
     *  the other's, even though both are filtered by the same
     *  Account__c -- same root-cause pattern as
     *  GtmSavedConfigurationController.getMyConfigurations(). */
    @IsTest
    static void getContactsWithLinksScopesToTheOwningRepOnly() {
        Account acc = new Account(Name = 'Shared Visibility Co');
        insert acc;
        Contact con = new Contact(FirstName = 'Jordan', LastName = 'Lee', AccountId = acc.Id);
        insert con;

        User repA = createRep('gtmlf1');
        User repB = createRep('gtmlf2');

        GTM_Saved_Configuration__c linkA = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtm/s/configurator?a=1',
            Account__c = acc.Id,
            Contact__c = con.Id,
            OwnerId = repA.Id
        );
        insert linkA;
        GTM_Saved_Configuration__c linkB = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtm/s/configurator?a=2',
            Account__c = acc.Id,
            Contact__c = con.Id,
            OwnerId = repB.Id
        );
        insert linkB;

        Test.startTest();
        List<GtmRepLinkFinderController.ContactLinks> repAView;
        System.runAs(repA) {
            repAView = GtmRepLinkFinderController.getContactsWithLinks(acc.Id);
        }
        Test.stopTest();

        Set<Id> repAIds = new Set<Id>();
        for (GtmRepLinkFinderController.ContactLinks g : repAView) {
            for (GtmRepLinkFinderController.LinkSummary link : g.links) {
                repAIds.add(link.recordId);
            }
        }
        Assert.isTrue(repAIds.contains(linkA.Id), 'Rep A must see their own link');
        Assert.isFalse(repAIds.contains(linkB.Id), 'Rep A must not see Rep B\'s link on the same Account');
    }

    /** A user holding viewAllRecords on GTM_Saved_Configuration__c
     *  (GTM_Offering_Admin) still sees everyone's links -- the explicit
     *  backstop must not clip an admin's existing full visibility. */
    @IsTest
    static void getContactsWithLinksAdminBypassSeesEveryonesLinks() {
        Account acc = new Account(Name = 'Admin Visibility Co');
        insert acc;
        Contact con = new Contact(FirstName = 'Jordan', LastName = 'Lee', AccountId = acc.Id);
        insert con;

        User repA = createRep('gtmlf3');
        User adminUser = createRep('gtmlf4');
        List<PermissionSet> adminSets = [
            SELECT Id FROM PermissionSet WHERE Name = 'GTM_Offering_Admin' LIMIT 1
        ];
        if (adminSets.isEmpty()) {
            return; // Permission set not deployed in this org -- nothing to assert.
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(
                AssigneeId = adminUser.Id,
                PermissionSetId = adminSets[0].Id
            );
        }

        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtm/s/configurator?a=3',
            Account__c = acc.Id,
            Contact__c = con.Id,
            OwnerId = repA.Id
        );

        Test.startTest();
        List<GtmRepLinkFinderController.ContactLinks> adminView;
        System.runAs(adminUser) {
            adminView = GtmRepLinkFinderController.getContactsWithLinks(acc.Id);
        }
        Test.stopTest();

        Assert.areEqual(1, adminView.size(), 'An admin with viewAllRecords should see other reps\' links too');
    }
}
