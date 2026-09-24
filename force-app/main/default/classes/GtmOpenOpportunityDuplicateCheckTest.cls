@IsTest
private class GtmOpenOpportunityDuplicateCheckTest {

    private static Account acct() {
        Account a = new Account(Name = 'Acme Bank');
        insert a;
        return a;
    }

    private static Contact contact(Id accountId) {
        Contact c = new Contact(FirstName = 'Jordan', LastName = 'Lee', Email = 'jordan.lee@example.com', AccountId = accountId);
        insert c;
        return c;
    }

    private static Opportunity opp(Id accountId, String offeringKey, Boolean isClosed) {
        Opportunity o = new Opportunity(
            Name = 'Deal',
            AccountId = accountId,
            StageName = isClosed ? 'Closed Lost' : 'Prospecting',
            CloseDate = isClosed ? Date.today().addDays(-1) : Date.today().addDays(30),
            Offering_Key__c = offeringKey
        );
        insert o;
        return o;
    }

    private static void linkContact(Id oppId, Id contactId, Boolean isPrimary) {
        insert new OpportunityContactRole(OpportunityId = oppId, ContactId = contactId, Role = 'Decision Maker', IsPrimary = isPrimary);
    }

    @IsTest
    static void findsOpenMatchOnExactAccountContactOffering() {
        Account a = acct();
        Contact c = contact(a.Id);
        Opportunity o = opp(a.Id, 'migration-accelerator', false);
        linkContact(o.Id, c.Id, true);

        Test.startTest();
        GtmOpenOpportunityDuplicateCheck.Match m =
            GtmOpenOpportunityDuplicateCheck.findOpenDuplicate(a.Id, c.Id, 'migration-accelerator');
        Test.stopTest();

        Assert.isNotNull(m);
        Assert.areEqual(o.Id, m.opportunityId);
        Assert.areEqual('Deal', m.opportunityName);
    }

    @IsTest
    static void closedOpportunityNeverMatches() {
        Account a = acct();
        Contact c = contact(a.Id);
        Opportunity o = opp(a.Id, 'migration-accelerator', true);
        linkContact(o.Id, c.Id, true);

        Test.startTest();
        GtmOpenOpportunityDuplicateCheck.Match m =
            GtmOpenOpportunityDuplicateCheck.findOpenDuplicate(a.Id, c.Id, 'migration-accelerator');
        Test.stopTest();

        Assert.isNull(m);
    }

    @IsTest
    static void differentOfferingNeverMatches() {
        Account a = acct();
        Contact c = contact(a.Id);
        Opportunity o = opp(a.Id, 'other-offering', false);
        linkContact(o.Id, c.Id, true);

        Test.startTest();
        GtmOpenOpportunityDuplicateCheck.Match m =
            GtmOpenOpportunityDuplicateCheck.findOpenDuplicate(a.Id, c.Id, 'migration-accelerator');
        Test.stopTest();

        Assert.isNull(m);
    }

    @IsTest
    static void differentContactNeverMatches() {
        Account a = acct();
        Contact c = contact(a.Id);
        Contact other = new Contact(FirstName = 'Alex', LastName = 'Rivera', Email = 'alex.rivera@example.com', AccountId = a.Id);
        insert other;
        Opportunity o = opp(a.Id, 'migration-accelerator', false);
        linkContact(o.Id, c.Id, true);

        Test.startTest();
        GtmOpenOpportunityDuplicateCheck.Match m =
            GtmOpenOpportunityDuplicateCheck.findOpenDuplicate(a.Id, other.Id, 'migration-accelerator');
        Test.stopTest();

        Assert.isNull(m);
    }

    @IsTest
    static void nullOfferingKeyOnOldOpportunityNeverFalsePositiveMatches() {
        // Old, un-backfilled Opportunity with a null Offering_Key__c must
        // never match -- a false negative here is accepted (issue #32),
        // a false positive is not.
        Account a = acct();
        Contact c = contact(a.Id);
        Opportunity o = new Opportunity(
            Name = 'Legacy Deal',
            AccountId = a.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert o;
        linkContact(o.Id, c.Id, true);

        Test.startTest();
        GtmOpenOpportunityDuplicateCheck.Match m =
            GtmOpenOpportunityDuplicateCheck.findOpenDuplicate(a.Id, c.Id, 'migration-accelerator');
        Test.stopTest();

        Assert.isNull(m);
    }

    @IsTest
    static void blankInputsNeverRunTheCheck() {
        Account a = acct();
        Contact c = contact(a.Id);

        Assert.isNull(GtmOpenOpportunityDuplicateCheck.findOpenDuplicate(null, c.Id, 'migration-accelerator'));
        Assert.isNull(GtmOpenOpportunityDuplicateCheck.findOpenDuplicate(a.Id, null, 'migration-accelerator'));
        Assert.isNull(GtmOpenOpportunityDuplicateCheck.findOpenDuplicate(a.Id, c.Id, null));
        Assert.isNull(GtmOpenOpportunityDuplicateCheck.findOpenDuplicate(a.Id, c.Id, ''));
    }

    @IsTest
    static void forMatchBuildsAStructuredAuraHandledException() {
        GtmOpenOpportunityDuplicateCheck.Match m =
            new GtmOpenOpportunityDuplicateCheck.Match('006000000000001AAA', 'Some Deal');

        Test.startTest();
        AuraHandledException ex = GtmOpenOpportunityDuplicateCheck.forMatch(m);
        Test.stopTest();

        Assert.isTrue(ex.getMessage().contains('OPEN_DUPLICATE'));
        Assert.isTrue(ex.getMessage().contains('Some Deal'));
    }
}
