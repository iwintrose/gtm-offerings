/**
 * No live-secret / no live-OAuth-flow dependency by design (TASK_SCOPE.md
 * §6): the actual authorize/token round trip can't be exercised without a
 * real callback from the org's own OAuth endpoint, so this asserts the one
 * thing that is unit-testable and load-bearing -- that createUser() links
 * to an existing internal user when one matches, and refuses (rather than
 * inventing an account) when nothing matches.
 */
@isTest
private class GtmEmployeeSsoRegHandlerTest {

    /**
     * Users are created inside their own runAs block: inserting a User and
     * a regular sObject in one transaction is a MIXED_DML_OPERATION.
     */
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

    private static Auth.UserData ssoData(String username, String federationId) {
        Map<String, String> attrs = new Map<String, String>();
        if (federationId != null) {
            attrs.put('federation_id', federationId);
        }
        return new Auth.UserData(
            'identity-' + username, 'First', 'Last', 'First Last',
            username, null, username, 'en_US',
            'salesforce', null, attrs
        );
    }

    @isTest
    static void createUserLinksToTheMatchingExistingUserByUsername() {
        User rep = createRep('gtmsso1');

        Test.startTest();
        User linked = new GtmEmployeeSsoRegHandler()
            .createUser(null, ssoData(rep.Username, null));
        Test.stopTest();

        System.assertEquals(rep.Id, linked.Id,
            'an SSO identity whose username matches an existing internal user must link to that user, not create a new one');
    }

    @isTest
    static void createUserLinksByFederationIdWhenUsernameDoesNotMatch() {
        User rep = createRep('gtmsso2');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            rep.FederationIdentifier = 'gtm-fed-002';
            update rep;
        }

        Test.startTest();
        User linked = new GtmEmployeeSsoRegHandler()
            .createUser(null, ssoData('no-such-username@example.invalid', 'gtm-fed-002'));
        Test.stopTest();

        System.assertEquals(rep.Id, linked.Id,
            'a federation-id match must still resolve to the existing user when the username does not match');
    }

    @isTest
    static void createUserRefusesRatherThanProvisioningAnUnknownIdentity() {
        Test.startTest();
        Boolean threw = false;
        try {
            new GtmEmployeeSsoRegHandler().createUser(
                null, ssoData('nobody-in-this-org@example.invalid', 'no-such-federation-id')
            );
        } catch (GtmEmployeeSsoRegHandler.SsoRegistrationException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw,
            'an identity with no matching internal user must be refused, never auto-provisioned');
    }

    @isTest
    static void createUserRefusesAnInactiveUsersIdentity() {
        User rep = createRep('gtmsso3');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            rep.IsActive = false;
            update rep;
        }

        Test.startTest();
        Boolean threw = false;
        try {
            new GtmEmployeeSsoRegHandler().createUser(null, ssoData(rep.Username, null));
        } catch (GtmEmployeeSsoRegHandler.SsoRegistrationException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw,
            'a deactivated user must not be silently reactivated by an SSO click');
    }

    @isTest
    static void updateUserIsANoOp() {
        User rep = createRep('gtmsso4');

        Test.startTest();
        new GtmEmployeeSsoRegHandler().updateUser(rep.Id, null, ssoData(rep.Username, null));
        Test.stopTest();

        // No assertion beyond "did not throw": updateUser is deliberately
        // inert (TASK_SCOPE.md §4 -- no field syncing as a side effect of a
        // login click).
    }
}
