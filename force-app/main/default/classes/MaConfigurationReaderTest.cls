/**
 * The short link only works if the SITE GUEST can read the record. Everything
 * else about it is untestable theatre if that one thing is wrong, so this
 * runs as the real guest user rather than as the running user.
 */
@isTest
private class MaConfigurationReaderTest {

    private static User guestUser() {
        List<User> gs = [SELECT Id FROM User WHERE UserType = 'Guest' AND IsActive = true LIMIT 1];
        return gs.isEmpty() ? null : gs[0];
    }

    private static Id makeConfig(Boolean active) {
        MA_Saved_Configuration__c c = new MA_Saved_Configuration__c(
            Company__c        = 'Guest Read Co',
            Industry__c       = 'media',
            Offering__c       = 'migration-accelerator',
            Active__c         = active,
            Link_Password__c  = 'secret-1234',
            Config_Payload__c = '{"ASSET_COUNT":"7777","HEALTH_SCORE":"71"}'
        );
        insert c;
        return c.Id;
    }

    @isTest
    static void guestCanReadAnActiveLink() {
        Id cid = makeConfig(true);
        User g = guestUser();
        if (g == null) return; // no guest in this org; nothing to assert against

        Test.startTest();
        MaConfigurationReader.PublicConfig got;
        System.runAs(g) {
            got = MaConfigurationReader.getPublicConfiguration(String.valueOf(cid));
        }
        Test.stopTest();

        System.assertNotEquals(null, got, 'the guest must be able to read the link its page is drawn from');
        System.assertEquals('Guest Read Co', got.company, 'company should come back');
        System.assertEquals(true, got.isActive, 'an active link reports active');
        System.assert(got.configPayload.contains('7777'), 'the payload the page draws from should come back');
    }

    @isTest
    static void aDisabledLinkStopsBeingReadable() {
        Id cid = makeConfig(false);
        User g = guestUser();
        if (g == null) return;

        Test.startTest();
        MaConfigurationReader.PublicConfig got;
        System.runAs(g) {
            got = MaConfigurationReader.getPublicConfiguration(String.valueOf(cid));
        }
        Test.stopTest();

        System.assertEquals(false, got.isActive, 'a switched-off link reports inactive');
        System.assertEquals(null, got.company, 'and stops being a way to read who the client is');
        System.assertEquals(null, got.configPayload, 'and stops handing over the payload');
    }

    @isTest
    static void aBadIdIsNullRatherThanAnException() {
        Test.startTest();
        System.assertEquals(null, MaConfigurationReader.getPublicConfiguration('not-an-id'));
        System.assertEquals(null, MaConfigurationReader.getPublicConfiguration(''));
        System.assertEquals(null, MaConfigurationReader.getPublicConfiguration(null));
        Test.stopTest();
    }

    @isTest
    static void theGuestIsNeverMistakenForARep() {
        User g = guestUser();
        if (g == null) return;
        Test.startTest();
        Boolean repFlag;
        System.runAs(g) { repFlag = MaViewerContext.isRep(); }
        Test.stopTest();
        System.assertEquals(false, repFlag, 'the site guest is not a rep');
    }
}
