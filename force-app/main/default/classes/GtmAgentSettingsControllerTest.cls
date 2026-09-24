@isTest
private class GtmAgentSettingsControllerTest {

    /** Legacy 5-arg shape wrapped into the AgentSettingsInput the controller now takes. */
    private static void save(String apiKey, String model, String chatProvider,
                             String openAiApiKey, String openAiModel) {
        GtmAgentSettingsController.AgentSettingsInput input = new GtmAgentSettingsController.AgentSettingsInput();
        input.apiKey = apiKey;
        input.model = model;
        input.chatProvider = chatProvider;
        input.openAiApiKey = openAiApiKey;
        input.openAiModel = openAiModel;
        GtmAgentSettingsController.setAgentSettings(input);
    }

    @isTest
    static void defaultsToNoKeyAndNoModelWhenNeverConfigured() {
        Test.startTest();
        GtmAgentSettingsController.AgentSettingsDto dto = GtmAgentSettingsController.getAgentSettings();
        Test.stopTest();

        Assert.isFalse(dto.hasApiKey, 'No key has been set yet');
        Assert.isNull(dto.model, 'No model has been set yet');
        Assert.areEqual('Anthropic', dto.chatProvider, 'Chat_Provider__c must default to Anthropic for back-compat');
        Assert.isFalse(dto.hasOpenAiApiKey, 'No OpenAI key has been set yet');
        Assert.isNull(dto.openAiModel, 'No OpenAI model has been set yet');
    }

    @isTest
    static void getAgentSettingsNeverReturnsTheRawKey() {
        save('super-secret-key-value', 'claude-sonnet-5', 'Anthropic', '', '');

        Test.startTest();
        GtmAgentSettingsController.AgentSettingsDto dto = GtmAgentSettingsController.getAgentSettings();
        Test.stopTest();

        Assert.isTrue(dto.hasApiKey, 'A key was set, so hasApiKey should be true');
        Assert.areEqual('claude-sonnet-5', dto.model);

        // Serialize the DTO the way the client would receive it and confirm
        // the raw secret is nowhere in the payload -- the response class
        // itself has no field for it, so this should always pass, but the
        // assertion guards against a future field being added carelessly.
        String serialized = JSON.serialize(dto);
        Assert.isFalse(
            serialized.contains('super-secret-key-value'),
            'The raw API key must never appear in the response sent to the client'
        );
    }

    @isTest
    static void modelOnlySaveLeavesAPreviouslySetKeyIntact() {
        save('original-key-value', 'claude-sonnet-4', 'Anthropic', '', '');

        Test.startTest();
        // Blank apiKey means "leave the stored key unchanged".
        save('', 'claude-sonnet-5', 'Anthropic', '', '');
        Test.stopTest();

        GTM_Agent_Settings__c settings = GTM_Agent_Settings__c.getOrgDefaults();
        Assert.areEqual('original-key-value', settings.Claude_API_Key__c, 'A model-only save must not wipe the stored key');
        Assert.areEqual('claude-sonnet-5', settings.Claude_Model__c);

        GtmAgentSettingsController.AgentSettingsDto dto = GtmAgentSettingsController.getAgentSettings();
        Assert.isTrue(dto.hasApiKey, 'The previously-set key should still be reported as present');
    }

    // ── OpenAI provider fields ────────────────────────────────────────────────

    @isTest
    static void getAgentSettingsNeverReturnsTheRawOpenAiKey() {
        save('', '', 'OpenAI', 'super-secret-openai-key', 'gpt-4o');

        Test.startTest();
        GtmAgentSettingsController.AgentSettingsDto dto = GtmAgentSettingsController.getAgentSettings();
        Test.stopTest();

        Assert.isTrue(dto.hasOpenAiApiKey, 'An OpenAI key was set, so hasOpenAiApiKey should be true');
        Assert.areEqual('OpenAI', dto.chatProvider);
        Assert.areEqual('gpt-4o', dto.openAiModel);

        String serialized = JSON.serialize(dto);
        Assert.isFalse(
            serialized.contains('super-secret-openai-key'),
            'The raw OpenAI API key must never appear in the response sent to the client'
        );
    }

    @isTest
    static void switchingProviderDoesNotRequireReEnteringTheOtherProvidersKey() {
        // Store both providers' keys independently, one per call, the way an
        // admin naturally would (set up Anthropic first, then later add OpenAI).
        save('claude-key-value', 'claude-sonnet-5', 'Anthropic', '', '');
        save('', '', 'OpenAI', 'openai-key-value', 'gpt-4o');

        Test.startTest();
        // Switch back to Anthropic without touching either key.
        save('', 'claude-sonnet-5', 'Anthropic', '', 'gpt-4o');
        Test.stopTest();

        GTM_Agent_Settings__c settings = GTM_Agent_Settings__c.getOrgDefaults();
        Assert.areEqual('claude-key-value', settings.Claude_API_Key__c, 'Switching providers must not clear the Claude key');
        Assert.areEqual('openai-key-value', settings.OpenAI_API_Key__c, 'Switching providers must not clear the OpenAI key');
        Assert.areEqual('Anthropic', settings.Chat_Provider__c);

        GtmAgentSettingsController.AgentSettingsDto dto = GtmAgentSettingsController.getAgentSettings();
        Assert.isTrue(dto.hasApiKey, 'The Claude key should still be reported as present');
        Assert.isTrue(dto.hasOpenAiApiKey, 'The OpenAI key should still be reported as present');
    }

    @isTest
    static void blankChatProviderDefaultsToAnthropicOnSave() {
        Test.startTest();
        save('claude-key-value', 'claude-sonnet-5', '', '', '');
        Test.stopTest();

        GTM_Agent_Settings__c settings = GTM_Agent_Settings__c.getOrgDefaults();
        Assert.areEqual('Anthropic', settings.Chat_Provider__c,
            'A blank chatProvider on save must default to Anthropic, matching the field-level default');
    }

    @isTest
    static void invalidChatProviderIsRejected() {
        Test.startTest();
        try {
            save('claude-key-value', 'claude-sonnet-5', 'Grok', '', '');
            Assert.fail('Expected an AuraHandledException for an invalid chatProvider value');
        } catch (AuraHandledException e) {
            // AuraHandledException.getMessage() only reflects the thrown
            // message once caught within Apex (its well-known quirk is that
            // an *uncaught* instance surfaces a generic message to the
            // client) -- asserting here confirms the throw happened, which is
            // what matters for this test.
        }
        Test.stopTest();

        GTM_Agent_Settings__c settings = GTM_Agent_Settings__c.getOrgDefaults();
        Assert.isTrue(settings == null || String.isBlank(settings.Chat_Provider__c),
            'An invalid chatProvider must be rejected before any DML, leaving the setting unset');
    }

    @isTest
    static void invalidChatProviderIsCaseSensitive() {
        Test.startTest();
        try {
            save('claude-key-value', 'claude-sonnet-5', 'anthropic', '', '');
            Assert.fail('Expected an AuraHandledException for a lowercase chatProvider value (allow-list is case-sensitive)');
        } catch (AuraHandledException e) {
            // Expected.
        }
        Test.stopTest();
    }

    // ── Gemini / Agentforce / blank-model semantics ──────────────────────────

    @isTest
    static void geminiAndAgentforceAreAcceptedProviders() {
        for (String provider : new List<String>{ 'Gemini', 'Agentforce', 'OpenAI', 'Anthropic' }) {
            GtmAgentSettingsController.AgentSettingsInput input = new GtmAgentSettingsController.AgentSettingsInput();
            input.chatProvider = provider;
            GtmAgentSettingsController.setAgentSettings(input);
            Assert.areEqual(provider, GTM_Agent_Settings__c.getOrgDefaults().Chat_Provider__c);
        }
    }

    @isTest
    static void getAgentSettingsNeverReturnsTheRawGeminiKey() {
        GtmAgentSettingsController.AgentSettingsInput input = new GtmAgentSettingsController.AgentSettingsInput();
        input.chatProvider = 'Gemini';
        input.geminiApiKey = 'super-secret-gemini-key';
        input.geminiModel = 'gemini-2.5-pro';
        GtmAgentSettingsController.setAgentSettings(input);

        GtmAgentSettingsController.AgentSettingsDto dto = GtmAgentSettingsController.getAgentSettings();
        Assert.isTrue(dto.hasGeminiApiKey);
        Assert.areEqual('Gemini', dto.chatProvider);
        Assert.areEqual('gemini-2.5-pro', dto.geminiModel);
        Assert.isFalse(JSON.serialize(dto).contains('super-secret-gemini-key'),
            'The raw Gemini key must never appear in the DTO');
    }

    @isTest
    static void savingOneProviderLeavesOtherKeysAndBlankModelsIntact() {
        GtmAgentSettingsController.AgentSettingsInput first = new GtmAgentSettingsController.AgentSettingsInput();
        first.chatProvider = 'Anthropic';
        first.apiKey = 'claude-key';
        first.model = 'claude-sonnet-5';
        first.openAiApiKey = 'openai-key';
        first.openAiModel = 'gpt-4o-mini';
        first.geminiApiKey = 'gemini-key';
        first.geminiModel = 'gemini-2.5-pro';
        GtmAgentSettingsController.setAgentSettings(first);

        // Switch to Gemini; every other key and model blank/whitespace.
        GtmAgentSettingsController.AgentSettingsInput second = new GtmAgentSettingsController.AgentSettingsInput();
        second.chatProvider = 'Gemini';
        second.model = '';
        second.openAiModel = '   ';
        second.geminiModel = null;
        GtmAgentSettingsController.setAgentSettings(second);

        GTM_Agent_Settings__c s = GTM_Agent_Settings__c.getOrgDefaults();
        Assert.areEqual('Gemini', s.Chat_Provider__c);
        Assert.areEqual('claude-key', s.Claude_API_Key__c);
        Assert.areEqual('openai-key', s.OpenAI_API_Key__c);
        Assert.areEqual('gemini-key', s.Gemini_API_Key__c);
        Assert.areEqual('claude-sonnet-5', s.Claude_Model__c, 'Blank model must not null the stored Claude model');
        Assert.areEqual('gpt-4o-mini', s.OpenAI_Model__c, 'Whitespace model must not null the stored OpenAI model');
        Assert.areEqual('gemini-2.5-pro', s.Gemini_Model__c, 'Null model must not null the stored Gemini model');
    }

    @isTest
    static void agentforceConfigIsSavedTrimmedAndReturnedButNoSecretExists() {
        GtmAgentSettingsController.AgentSettingsInput input = new GtmAgentSettingsController.AgentSettingsInput();
        input.chatProvider = 'Agentforce';
        input.agentforceAgentId = '  0Xx000000000001AAA ';
        input.agentforceMyDomainUrl = ' https://example.my.salesforce.com/ ';
        input.agentforceClientId = 'consumer-key-123';
        GtmAgentSettingsController.setAgentSettings(input);

        GtmAgentSettingsController.AgentSettingsDto dto = GtmAgentSettingsController.getAgentSettings();
        Assert.areEqual('Agentforce', dto.chatProvider);
        Assert.areEqual('0Xx000000000001AAA', dto.agentforceAgentId);
        Assert.areEqual('https://example.my.salesforce.com', dto.agentforceMyDomainUrl);
        Assert.areEqual('consumer-key-123', dto.agentforceClientId);

        // A later save with blank Agentforce fields leaves them unchanged.
        GtmAgentSettingsController.AgentSettingsInput again = new GtmAgentSettingsController.AgentSettingsInput();
        again.chatProvider = 'Anthropic';
        GtmAgentSettingsController.setAgentSettings(again);
        Assert.areEqual('0Xx000000000001AAA', GtmAgentSettingsController.getAgentSettings().agentforceAgentId);
    }

    @isTest
    static void agentforceMyDomainUrlMustBeHttps() {
        GtmAgentSettingsController.AgentSettingsInput input = new GtmAgentSettingsController.AgentSettingsInput();
        input.chatProvider = 'Agentforce';
        input.agentforceMyDomainUrl = 'http://example.my.salesforce.com';
        Boolean threw = false;
        try {
            GtmAgentSettingsController.setAgentSettings(input);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'A non-https My Domain URL must be rejected');
        GTM_Agent_Settings__c s = GTM_Agent_Settings__c.getOrgDefaults();
        Assert.isTrue(s == null || String.isBlank(s.Chat_Provider__c), 'Rejected before any DML');
    }
}
