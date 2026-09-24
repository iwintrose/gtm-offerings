@IsTest
private class GtmAccountContactSearchControllerTest {

    private static Account makeAccount() {
        Account acc = new Account(Name = 'Acme Bank');
        insert acc;
        return acc;
    }

    private static Contact makeContact(Account acc) {
        Contact con = new Contact(
            FirstName = 'Jordan', LastName = 'Lee',
            Email = 'jordan.lee@acmebank.example.com', AccountId = acc.Id
        );
        insert con;
        return con;
    }

    @IsTest
    static void returnsMixedAccountAndContactResults() {
        Account acc = makeAccount();
        Contact con = makeContact(acc);

        // SOSL never actually executes against real search index data in a
        // test context -- Test.setFixedSearchResults is the documented way
        // to make [FIND ...] return specific records so the method's own
        // mapping/stripInaccessible logic can be exercised deterministically.
        Test.setFixedSearchResults(new List<Id>{ acc.Id, con.Id });

        Test.startTest();
        List<GtmAccountContactSearchController.SearchResult> results =
            GtmAccountContactSearchController.searchAccountsAndContacts('Acme');
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Both the Account and Contact fixed results should come back.');

        GtmAccountContactSearchController.SearchResult accountResult = null;
        GtmAccountContactSearchController.SearchResult contactResult = null;
        for (GtmAccountContactSearchController.SearchResult r : results) {
            if (r.type == 'Account') accountResult = r;
            if (r.type == 'Contact') contactResult = r;
        }

        System.assertNotEquals(null, accountResult, 'An Account result should be present.');
        System.assertEquals(acc.Id, accountResult.recordId);
        System.assertEquals('Acme Bank', accountResult.label);
        System.assertEquals(acc.Id, accountResult.accountId);
        System.assertEquals('', accountResult.subLabel);

        System.assertNotEquals(null, contactResult, 'A Contact result should be present.');
        System.assertEquals(con.Id, contactResult.recordId);
        System.assertEquals('Jordan Lee', contactResult.label);
        System.assertEquals(acc.Id, contactResult.accountId);
        System.assertEquals('Acme Bank', contactResult.subLabel);
    }

    @IsTest
    static void returnsAccountOnlyResults() {
        Account acc = makeAccount();
        Test.setFixedSearchResults(new List<Id>{ acc.Id });

        Test.startTest();
        List<GtmAccountContactSearchController.SearchResult> results =
            GtmAccountContactSearchController.searchAccountsAndContacts('Acme');
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Account', results[0].type);
        System.assertEquals(acc.Id, results[0].recordId);
    }

    @IsTest
    static void returnsContactOnlyResults() {
        Account acc = makeAccount();
        Contact con = makeContact(acc);
        Test.setFixedSearchResults(new List<Id>{ con.Id });

        Test.startTest();
        List<GtmAccountContactSearchController.SearchResult> results =
            GtmAccountContactSearchController.searchAccountsAndContacts('Jordan');
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Contact', results[0].type);
        System.assertEquals(con.Id, results[0].recordId);
        System.assertEquals(acc.Id, results[0].accountId);
    }

    @IsTest
    static void returnsNoResultsWhenFixedSearchIsEmpty() {
        Test.setFixedSearchResults(new List<Id>());

        Test.startTest();
        List<GtmAccountContactSearchController.SearchResult> results =
            GtmAccountContactSearchController.searchAccountsAndContacts('Nothing Matches This');
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    @IsTest
    static void returnsNoResultsForBlankOrShortSearchTermWithoutQuerying() {
        Test.startTest();
        System.assertEquals(0, GtmAccountContactSearchController.searchAccountsAndContacts(null).size());
        System.assertEquals(0, GtmAccountContactSearchController.searchAccountsAndContacts('').size());
        System.assertEquals(0, GtmAccountContactSearchController.searchAccountsAndContacts(' ').size());
        System.assertEquals(0, GtmAccountContactSearchController.searchAccountsAndContacts('a').size());
        Test.stopTest();
    }

    /**
     * FLS-stripping behavior: Security.stripInaccessible removes fields the
     * running user can't see rather than throwing, but this org's standard
     * Name/FirstName/LastName/AccountId fields are always readable to any
     * user with object access, so there's no field to actually observe being
     * stripped without a dedicated restricted-field/permission-set fixture
     * this org doesn't have. This test instead documents and asserts the
     * safe-by-construction property: calling stripInaccessible never throws
     * and never blows up the mapping loop even when given the exact record
     * shape this method queries, which is the behavior that matters here
     * (no fatal error surfaced to the LWC just because FLS trimmed a field).
     */
    @IsTest
    static void strippingRunsWithoutErrorAndPreservesRecordIdentity() {
        Account acc = makeAccount();
        Contact con = makeContact(acc);
        Test.setFixedSearchResults(new List<Id>{ acc.Id, con.Id });

        Test.startTest();
        List<GtmAccountContactSearchController.SearchResult> results =
            GtmAccountContactSearchController.searchAccountsAndContacts('Acme');
        Test.stopTest();

        for (GtmAccountContactSearchController.SearchResult r : results) {
            System.assertNotEquals(null, r.recordId, 'stripInaccessible must never null out the Id field.');
        }
    }
}
