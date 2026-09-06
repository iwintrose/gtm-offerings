@IsTest
private class GtmLinkAuthControllerTest {

    @TestSetup
    static void setup() {
        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Test Corp',
            Generated_URL__c = 'https://example.com/test',
            Link_Password__c = 'secret123'
        );
        insert new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'No Password Corp',
            Generated_URL__c = 'https://example.com/no-pw'
        );
    }

    @IsTest
    static void testCheckPasswordRequired_withPassword() {
        GTM_Saved_Configuration__c rec = [
            SELECT Id FROM GTM_Saved_Configuration__c WHERE Company__c = 'Test Corp' LIMIT 1
        ];
        Test.startTest();
        Boolean result = GtmLinkAuthController.checkPasswordRequired(rec.Id);
        Test.stopTest();
        System.assertEquals(true, result, 'Should return true when password is set');
    }

    @IsTest
    static void testCheckPasswordRequired_noPassword() {
        GTM_Saved_Configuration__c rec = [
            SELECT Id FROM GTM_Saved_Configuration__c WHERE Company__c = 'No Password Corp' LIMIT 1
        ];
        Test.startTest();
        Boolean result = GtmLinkAuthController.checkPasswordRequired(rec.Id);
        Test.stopTest();
        System.assertEquals(false, result, 'Should return false when no password');
    }

    @IsTest
    static void testCheckPasswordRequired_blankId() {
        Test.startTest();
        Boolean result = GtmLinkAuthController.checkPasswordRequired('');
        Test.stopTest();
        System.assertEquals(false, result);
    }

    @IsTest
    static void testVerifyPassword_correct() {
        GTM_Saved_Configuration__c rec = [
            SELECT Id FROM GTM_Saved_Configuration__c WHERE Company__c = 'Test Corp' LIMIT 1
        ];
        Test.startTest();
        Boolean result = GtmLinkAuthController.verifyPassword(rec.Id, 'secret123');
        Test.stopTest();
        System.assertEquals(true, result, 'Correct password should verify');
        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :rec.Id];
        System.assertEquals(1, tasks.size(), 'Should log one task');
        System.assert(tasks[0].Subject.contains('accessed'), 'Task should indicate successful access');
    }

    @IsTest
    static void testVerifyPassword_wrong() {
        GTM_Saved_Configuration__c rec = [
            SELECT Id FROM GTM_Saved_Configuration__c WHERE Company__c = 'Test Corp' LIMIT 1
        ];
        Test.startTest();
        Boolean result = GtmLinkAuthController.verifyPassword(rec.Id, 'wrongpassword');
        Test.stopTest();
        System.assertEquals(false, result, 'Wrong password should fail');
        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :rec.Id];
        System.assertEquals(1, tasks.size(), 'Should log failed attempt');
        System.assert(tasks[0].Subject.contains('failed'), 'Task should indicate failed attempt');
    }

    @IsTest
    static void testVerifyPassword_blankInputs() {
        Test.startTest();
        System.assertEquals(false, GtmLinkAuthController.verifyPassword('', 'secret'));
        System.assertEquals(false, GtmLinkAuthController.verifyPassword('badid', ''));
        Test.stopTest();
    }

    // -------------------------------------------------------- verifyAndIssueToken

    @IsTest
    static void testVerifyAndIssueToken_correctPassword_returnsMatchedAndToken() {
        GTM_Saved_Configuration__c rec = [
            SELECT Id FROM GTM_Saved_Configuration__c WHERE Company__c = 'Test Corp' LIMIT 1
        ];
        Test.startTest();
        GtmLinkAuthController.VerifyResult res =
            GtmLinkAuthController.verifyAndIssueToken(rec.Id, 'secret123');
        Test.stopTest();

        System.assertEquals(true, res.matched, 'Correct password should match');
        System.assertNotEquals(null, res.submissionToken, 'A token should be issued on success');
        // Token must be three colon-delimited segments.
        List<String> parts = res.submissionToken.split(':');
        System.assertEquals(3, parts.size(), 'Token must have exactly 3 segments');
        // First segment must be the record Id.
        System.assertEquals(String.valueOf(rec.Id), parts[0], 'First segment must be the record Id');
        // Second segment must be a parseable epoch.
        Long epoch = Long.valueOf(parts[1]);
        System.assert(epoch > 0, 'Epoch segment must be a positive number');

        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :rec.Id];
        System.assertEquals(1, tasks.size(), 'Should log one access task');
        System.assert(tasks[0].Subject.contains('accessed'));
    }

    @IsTest
    static void testVerifyAndIssueToken_wrongPassword_noToken() {
        GTM_Saved_Configuration__c rec = [
            SELECT Id FROM GTM_Saved_Configuration__c WHERE Company__c = 'Test Corp' LIMIT 1
        ];
        Test.startTest();
        GtmLinkAuthController.VerifyResult res =
            GtmLinkAuthController.verifyAndIssueToken(rec.Id, 'wrongpassword');
        Test.stopTest();

        System.assertEquals(false, res.matched, 'Wrong password should not match');
        System.assertEquals(null, res.submissionToken, 'No token on failure');

        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :rec.Id];
        System.assertEquals(1, tasks.size(), 'Failed attempt should still be logged');
        System.assert(tasks[0].Subject.contains('failed'));
    }

    @IsTest
    static void testVerifyAndIssueToken_noPasswordOnRecord_noToken() {
        GTM_Saved_Configuration__c rec = [
            SELECT Id FROM GTM_Saved_Configuration__c WHERE Company__c = 'No Password Corp' LIMIT 1
        ];
        Test.startTest();
        GtmLinkAuthController.VerifyResult res =
            GtmLinkAuthController.verifyAndIssueToken(rec.Id, 'anypassword');
        Test.stopTest();

        System.assertEquals(false, res.matched, 'Record with no password should not match');
        System.assertEquals(null, res.submissionToken);
    }

    @IsTest
    static void testVerifyAndIssueToken_blankInputs_returnsFalse() {
        Test.startTest();
        GtmLinkAuthController.VerifyResult res1 =
            GtmLinkAuthController.verifyAndIssueToken('', 'secret123');
        GtmLinkAuthController.VerifyResult res2 =
            GtmLinkAuthController.verifyAndIssueToken('badid', '');
        Test.stopTest();

        System.assertEquals(false, res1.matched);
        System.assertEquals(null, res1.submissionToken);
        System.assertEquals(false, res2.matched);
        System.assertEquals(null, res2.submissionToken);
    }
}
