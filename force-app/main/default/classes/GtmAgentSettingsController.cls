/**
 * Admin-only accessor for GTM_Agent_Settings__c, backing the "GUS
 * Configuration" section of the GTM_Offerings_Settings tab /
 * gtmOfferingsSettingsAgent LWC.
 *
 * Deliberately its own class rather than folded into GtmAgentProxyController
 * (that class's Apex class access is granted more broadly for the GUS
 * runtime tool surface) -- keeping this admin-config surface in a class
 * granted only to GTM_Offering_Admin is what makes that boundary real rather
 * than just a hidden tab a determined user could still reach through Apex.
 *
 * `with sharing`: this is an internal admin config surface, not a
 * public/guest one, and the Custom Setting itself has no row-level sharing to
 * enforce anyway -- with sharing costs nothing here and is the safer default.
 *
 * HARD SECURITY REQUIREMENT: the stored Claude_API_Key__c and
 * OpenAI_API_Key__c and Gemini_API_Key__c values must never be returned to the client, in any
 * form (not even masked). The get method returns AgentSettingsDto, which
 * deliberately has no field for either raw key -- only hasApiKey /
 * hasOpenAiApiKey / hasGeminiApiKey booleans the LWC uses to render status lines. Both
 * Claude_API_Key__c and OpenAI_API_Key__c are plain Text fields (Custom
 * Settings -- GTM_Agent_Settings__c is a Hierarchy Custom Setting -- do not
 * support EncryptedText at all), so there is no field-type-level masking to
 * rely on for either one. The write-only/never-prefill boundary enforced in
 * this class is the only thing protecting both values, exactly the same way
 * for each.
 */
public with sharing class GtmAgentSettingsController {

    private static final Set<String> VALID_CHAT_PROVIDERS =
        new Set<String>{ 'Anthropic', 'OpenAI', 'Gemini', 'Agentforce' };

    /**
     * Input wrapper for setAgentSettings (contract:
     * docs/architecture/gus-chat-provider-settings.md). The LWC passes it as
     * `{ input: { ... } }`. There is deliberately no Agentforce consumer
     * SECRET member: only the (non-secret) consumer key is stored.
     */
    public class AgentSettingsInput {
        @AuraEnabled public String chatProvider;
        @AuraEnabled public String apiKey;
        @AuraEnabled public String model;
        @AuraEnabled public String openAiApiKey;
        @AuraEnabled public String openAiModel;
        @AuraEnabled public String geminiApiKey;
        @AuraEnabled public String geminiModel;
        @AuraEnabled public String agentforceAgentId;
        @AuraEnabled public String agentforceMyDomainUrl;
        @AuraEnabled public String agentforceClientId;
    }

    public class AgentSettingsDto {
        @AuraEnabled public Boolean hasApiKey;
        @AuraEnabled public String model;
        @AuraEnabled public String chatProvider;
        @AuraEnabled public Boolean hasOpenAiApiKey;
        @AuraEnabled public String openAiModel;
        @AuraEnabled public Boolean hasGeminiApiKey;
        @AuraEnabled public String geminiModel;
        @AuraEnabled public String agentforceAgentId;
        @AuraEnabled public String agentforceMyDomainUrl;
        @AuraEnabled public String agentforceClientId;
    }

    @AuraEnabled(cacheable=true)
    public static AgentSettingsDto getAgentSettings() {
        GTM_Agent_Settings__c settings = GTM_Agent_Settings__c.getOrgDefaults();
        AgentSettingsDto dto = new AgentSettingsDto();
        dto.hasApiKey = settings != null && String.isNotBlank(settings.Claude_API_Key__c);
        dto.model = settings != null ? settings.Claude_Model__c : null;
        dto.chatProvider = (settings != null && String.isNotBlank(settings.Chat_Provider__c))
            ? settings.Chat_Provider__c
            : 'Anthropic';
        dto.hasOpenAiApiKey = settings != null && String.isNotBlank(settings.OpenAI_API_Key__c);
        dto.openAiModel = settings != null ? settings.OpenAI_Model__c : null;
        dto.hasGeminiApiKey = settings != null && String.isNotBlank(settings.Gemini_API_Key__c);
        dto.geminiModel = settings != null ? settings.Gemini_Model__c : null;
        // Agent ID / My Domain URL / consumer key are identifiers, not secrets.
        dto.agentforceAgentId = settings != null ? settings.Agentforce_Agent_Id__c : null;
        dto.agentforceMyDomainUrl = settings != null ? settings.Agentforce_My_Domain_URL__c : null;
        dto.agentforceClientId = settings != null ? settings.Agentforce_Client_Id__c : null;
        return dto;
    }

    /**
     * Writes the org default row specifically (Id == null on the Hierarchy
     * setting's org-wide row) rather than getInstance()'s resolved row for
     * the running user -- an admin editing this tab means "change it for
     * everyone," not "change it for me."
     *
     * A blank/whitespace API key (Claude, OpenAI or Gemini) means "leave that
     * provider's stored key unchanged" -- each key is independently
     * write-only/never-prefill, so switching the provider picker never forces
     * re-entering another provider's already-stored key. A blank/whitespace
     * MODEL likewise means "leave that provider's stored model unchanged"
     * (for every provider), so saving one provider never blanks another's
     * model; the runtime default constants apply only while a model is unset.
     *
     * The Agentforce Agent ID / My Domain URL / consumer key are trimmed;
     * blank leaves the stored value unchanged. A non-blank My Domain URL must
     * start with https:// and has any trailing slash stripped -- Agentforce
     * is live for GtmAgentProxyController.chat() (the configurator surface)
     * as of gus-live-agentforce-provider-runtime, and that call site is
     * responsible for re-appending exactly one trailing slash when it builds
     * the Start Session request's instanceConfig.endpoint (see
     * docs/architecture/gus-chat-provider-settings.md §5a "RESOLVED" -- a
     * missing trailing slash there 404s indistinguishably from an
     * unauthenticated request). chatOnReadout()/chatOnApp() still never call
     * Agentforce; they keep the stateless Claude/OpenAI/Gemini fallback.
     *
     * chatProvider is validated against an explicit allow-list
     * ('Anthropic'/'OpenAI'/'Gemini'/'Agentforce', case-sensitive) here at
     * the Apex layer: Chat_Provider__c is plain Text (Custom Settings don't
     * support Picklist), so there is no platform-level restriction on the
     * stored value -- this check is what the field's Picklist valueSet used
     * to enforce.
     */
    @AuraEnabled
    public static void setAgentSettings(AgentSettingsInput input) {
        if (input == null) {
            input = new AgentSettingsInput();
        }
        String chatProvider = input.chatProvider;
        if (String.isNotBlank(chatProvider) && !VALID_CHAT_PROVIDERS.contains(chatProvider)) {
            throw new AuraHandledException('Invalid chatProvider "' + chatProvider
                + '" -- must be "Anthropic", "OpenAI", "Gemini" or "Agentforce".');
        }
        String myDomain = input.agentforceMyDomainUrl == null ? null : input.agentforceMyDomainUrl.trim();
        if (String.isNotBlank(myDomain)) {
            if (!myDomain.startsWith('https://')) {
                throw new AuraHandledException('Agentforce My Domain URL must start with https://');
            }
            while (myDomain.endsWith('/')) {
                myDomain = myDomain.substring(0, myDomain.length() - 1);
            }
        }

        GTM_Agent_Settings__c settings = GTM_Agent_Settings__c.getOrgDefaults();
        if (settings == null || settings.Id == null) {
            settings = new GTM_Agent_Settings__c();
        }
        settings.Chat_Provider__c = String.isBlank(chatProvider) ? 'Anthropic' : chatProvider;

        if (String.isNotBlank(input.apiKey)) settings.Claude_API_Key__c = input.apiKey;
        if (String.isNotBlank(input.model)) settings.Claude_Model__c = input.model;
        if (String.isNotBlank(input.openAiApiKey)) settings.OpenAI_API_Key__c = input.openAiApiKey;
        if (String.isNotBlank(input.openAiModel)) settings.OpenAI_Model__c = input.openAiModel;
        if (String.isNotBlank(input.geminiApiKey)) settings.Gemini_API_Key__c = input.geminiApiKey;
        if (String.isNotBlank(input.geminiModel)) settings.Gemini_Model__c = input.geminiModel;

        if (String.isNotBlank(input.agentforceAgentId)) settings.Agentforce_Agent_Id__c = input.agentforceAgentId.trim();
        if (String.isNotBlank(myDomain)) settings.Agentforce_My_Domain_URL__c = myDomain;
        if (String.isNotBlank(input.agentforceClientId)) settings.Agentforce_Client_Id__c = input.agentforceClientId.trim();
        upsert settings;
    }
}
