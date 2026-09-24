@IsTest
private class GtmLinkRecoveryControllerTest {

    @TestSetup
    static void setup() {
        Account acct = new Account(Name = 'Test Account');
        insert acct;

        Contact c = new Contact(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'test@example.com',
            AccountId = acct.Id
        );
        insert c;

        GTM_Saved_Configuration__c config = new GTM_Saved_Configuration__c(
            Contact__c = c.Id,
            Offering__c = 'Cloud Modernization',
            Active__c = true,
            Generated_URL__c = 'https://example.com/gtm'
        );
        insert config;
    }

    @IsTest
    static void testValidMatchingEmail_returnsOk() {
        Test.startTest();
        String result = GtmLinkRecoveryController.recoverLink('test@example.com');
        Test.stopTest();
        System.assertEquals('OK', result);
    }

    @IsTest
    static void testEmailNoMatch_returnsOk() {
        Test.startTest();
        String result = GtmLinkRecoveryController.recoverLink('nomatch@example.com');
        Test.stopTest();
        System.assertEquals('OK', result);
    }

    @IsTest
    static void testBlankEmail_throwsAuraHandledException() {
        Test.startTest();
        try {
            GtmLinkRecoveryController.recoverLink('');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void testMalformedEmail_throwsAuraHandledException() {
        Test.startTest();
        try {
            GtmLinkRecoveryController.recoverLink('notanemail');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }
}
