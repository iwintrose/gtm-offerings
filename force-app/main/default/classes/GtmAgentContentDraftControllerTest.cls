/**
 * GtmAgentContentDraftController.chat() ultimately makes an HTTP callout via
 * GtmAgentProxyController.runLoop() once a provider key is configured, which
 * these tests deliberately never configure -- so every path here exercises
 * validation only, never a callout, matching how GtmAgentProxyControllerTest
 * covers the "no key configured" branch for the other entry points.
 */
@IsTest
private class GtmAgentContentDraftControllerTest {

    @IsTest
    static void chat_blankOfferingKey_throws() {
        Boolean threw = false;
        try {
            GtmAgentContentDraftController.chat('', 'story', 'problem--healthcare', 'hi', '');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Blank offeringKey must be rejected before any callout is attempted.');
    }

    @IsTest
    static void chat_blankSectionKey_throws() {
        Boolean threw = false;
        try {
            GtmAgentContentDraftController.chat('migration-accelerator', 'story', '', 'hi', '');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Blank sectionKey must be rejected before any callout is attempted.');
    }

    @IsTest
    static void chat_noProviderKeyConfigured_throwsConfigurationError() {
        // Valid inputs, but GTM_Agent_Settings__c has no key in this test context,
        // so runLoop() must fail closed before any HTTP callout -- proving
        // GtmAgentContentDraftController really does reach the shared loop
        // rather than silently no-op-ing.
        Boolean threw = false;
        String message = '';
        Test.startTest();
        try {
            GtmAgentContentDraftController.chat(
                'migration-accelerator', 'story', 'problem--healthcare', 'Draft this for me', '');
        } catch (AuraHandledException e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(threw, 'With no API key configured, chat() must throw rather than attempt a callout.');
        Assert.isTrue(message.containsIgnoreCase('API key not configured'),
            'Error should be the same configuration message the other GUS entry points already use; got: ' + message);
    }
}
