@IsTest
private class MaLinkAuthControllerTest {

    @TestSetup
    static void setup() {
        insert new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Test Corp',
            Generated_URL__c = 'https://example.com/test',
            Link_Password__c = 'secret123'
        );
        insert new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'No Password Corp',
            Generated_URL__c = 'https://example.com/no-pw'
        );
    }

    @IsTest
    static void testCheckPasswordRequired_withPassword() {
        MA_Saved_Configuration__c rec = [
            SELECT Id FROM MA_Saved_Configuration__c WHERE Company__c = 'Test Corp' LIMIT 1
        ];
        Test.startTest();
        Boolean result = MaLinkAuthController.checkPasswordRequired(rec.Id);
        Test.stopTest();
        System.assertEquals(true, result, 'Should return true when password is set');
    }

    @IsTest
    static void testCheckPasswordRequired_noPassword() {
        MA_Saved_Configuration__c rec = [
            SELECT Id FROM MA_Saved_Configuration__c WHERE Company__c = 'No Password Corp' LIMIT 1
        ];
        Test.startTest();
        Boolean result = MaLinkAuthController.checkPasswordRequired(rec.Id);
        Test.stopTest();
        System.assertEquals(false, result, 'Should return false when no password');
    }

    @IsTest
    static void testCheckPasswordRequired_blankId() {
        Test.startTest();
        Boolean result = MaLinkAuthController.checkPasswordRequired('');
        Test.stopTest();
        System.assertEquals(false, result);
    }

    @IsTest
    static void testVerifyPassword_correct() {
        MA_Saved_Configuration__c rec = [
            SELECT Id FROM MA_Saved_Configuration__c WHERE Company__c = 'Test Corp' LIMIT 1
        ];
        Test.startTest();
        Boolean result = MaLinkAuthController.verifyPassword(rec.Id, 'secret123');
        Test.stopTest();
        System.assertEquals(true, result, 'Correct password should verify');
        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :rec.Id];
        System.assertEquals(1, tasks.size(), 'Should log one task');
        System.assert(tasks[0].Subject.contains('accessed'), 'Task should indicate successful access');
    }

    @IsTest
    static void testVerifyPassword_wrong() {
        MA_Saved_Configuration__c rec = [
            SELECT Id FROM MA_Saved_Configuration__c WHERE Company__c = 'Test Corp' LIMIT 1
        ];
        Test.startTest();
        Boolean result = MaLinkAuthController.verifyPassword(rec.Id, 'wrongpassword');
        Test.stopTest();
        System.assertEquals(false, result, 'Wrong password should fail');
        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :rec.Id];
        System.assertEquals(1, tasks.size(), 'Should log failed attempt');
        System.assert(tasks[0].Subject.contains('failed'), 'Task should indicate failed attempt');
    }

    @IsTest
    static void testVerifyPassword_blankInputs() {
        Test.startTest();
        System.assertEquals(false, MaLinkAuthController.verifyPassword('', 'secret'));
        System.assertEquals(false, MaLinkAuthController.verifyPassword('badid', ''));
        Test.stopTest();
    }
}
