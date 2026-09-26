import { LightningElement, track } from 'lwc';
import getAgentSettings from '@salesforce/apex/GtmAgentSettingsController.getAgentSettings';
import setAgentSettings from '@salesforce/apex/GtmAgentSettingsController.setAgentSettings';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const DEFAULT_MODEL_PLACEHOLDER = 'claude-sonnet-5';
const DEFAULT_OPENAI_MODEL_PLACEHOLDER = 'gpt-4o';
const DEFAULT_GEMINI_MODEL_PLACEHOLDER = 'gemini-2.5-flash';

const PROVIDER_OPTIONS = [
    { label: 'Anthropic (Claude)', value: 'Anthropic' },
    { label: 'OpenAI (GPT)', value: 'OpenAI' },
    { label: 'Google Gemini', value: 'Gemini' },
    { label: 'Salesforce Agentforce', value: 'Agentforce' }
];

/**
 * "GUS Chat Provider" section, rendered inside the admin-only
 * GTM_Offerings_Settings shell tab (c-gtm-offerings-settings). Edits
 * GTM_Agent_Settings__c org-wide: Chat_Provider__c plus the selected
 * provider's own credentials/model. Contract:
 * docs/architecture/gus-chat-provider-settings.md.
 *
 * Only the selected provider's inputs are rendered (template lwc:if, not CSS
 * hiding). All values live in component state regardless of which provider is
 * showing, and every value is sent on Save; Apex treats a blank key or model
 * as "leave that stored value unchanged", so switching the dropdown never
 * clears or overwrites another provider's saved values.
 *
 * HARD SECURITY REQUIREMENT: the Claude / OpenAI / Gemini API key inputs are
 * write-only. They always start empty, regardless of whether a key is stored
 * -- the hasXxxApiKey flags only drive "Key is set" / "No key set" status
 * lines. Agentforce Agent ID / My Domain URL / consumer key are not secrets
 * and are prefilled. There is NO Agentforce consumer-secret input; it lives
 * only in the GTM_Agentforce_Credential External Credential in Setup (see
 * docs/architecture/gus-chat-provider-settings.md §5a).
 *
 * Agentforce is live for the GUS configurator chat only (issue
 * gus-live-agentforce-provider-runtime) -- conversational replies, no
 * configurator field changes applied yet (no Topics/Actions wired on the live
 * agent). The readout editor and utility bar keep using Claude/OpenAI/Gemini
 * regardless of this setting. See the in-panel notice text below.
 *
 * Imperative Apex rather than @wire, matching gtmReadoutApprovalSettings's
 * convention for a single-consumer admin surface.
 */
export default class GtmOfferingsSettingsAgent extends LightningElement {
    @track apiKeyInput = '';
    @track model = '';
    @track hasApiKey = false;
    @track chatProvider = 'Anthropic';
    @track openAiApiKeyInput = '';
    @track openAiModel = '';
    @track hasOpenAiApiKey = false;
    @track geminiApiKeyInput = '';
    @track geminiModel = '';
    @track hasGeminiApiKey = false;
    @track agentforceAgentId = '';
    @track agentforceMyDomainUrl = '';
    @track agentforceClientId = '';
    @track isLoading = true;
    @track isSaving = false;
    @track loadError = '';

    providerOptions = PROVIDER_OPTIONS;

    connectedCallback() {
        this.load();
    }

    load() {
        this.isLoading = true;
        this.loadError = '';
        getAgentSettings()
            .then((dto) => {
                this.hasApiKey = !!(dto && dto.hasApiKey);
                this.model = (dto && dto.model) || '';
                this.chatProvider = (dto && dto.chatProvider) || 'Anthropic';
                this.hasOpenAiApiKey = !!(dto && dto.hasOpenAiApiKey);
                this.openAiModel = (dto && dto.openAiModel) || '';
                this.hasGeminiApiKey = !!(dto && dto.hasGeminiApiKey);
                this.geminiModel = (dto && dto.geminiModel) || '';
                this.agentforceAgentId = (dto && dto.agentforceAgentId) || '';
                this.agentforceMyDomainUrl = (dto && dto.agentforceMyDomainUrl) || '';
                this.agentforceClientId = (dto && dto.agentforceClientId) || '';
                // Never pre-fill any API key input, even if one is stored.
                this.apiKeyInput = '';
                this.openAiApiKeyInput = '';
                this.geminiApiKeyInput = '';
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'The setting could not be loaded.';
            })
            .finally(() => { this.isLoading = false; });
    }

    get modelPlaceholder() {
        return DEFAULT_MODEL_PLACEHOLDER;
    }

    get openAiModelPlaceholder() {
        return DEFAULT_OPENAI_MODEL_PLACEHOLDER;
    }

    get geminiModelPlaceholder() {
        return DEFAULT_GEMINI_MODEL_PLACEHOLDER;
    }

    get apiKeyStatusLabel() {
        return this.hasApiKey ? 'Key is set (••••••)' : 'No key set';
    }

    get openAiApiKeyStatusLabel() {
        return this.hasOpenAiApiKey ? 'Key is set (••••••)' : 'No key set';
    }

    get geminiApiKeyStatusLabel() {
        return this.hasGeminiApiKey ? 'Key is set (••••••)' : 'No key set';
    }

    get isAnthropicSelected() {
        return this.chatProvider === 'Anthropic';
    }

    get isOpenAiSelected() {
        return this.chatProvider === 'OpenAI';
    }

    get isGeminiSelected() {
        return this.chatProvider === 'Gemini';
    }

    get isAgentforceSelected() {
        return this.chatProvider === 'Agentforce';
    }

    handleProviderChange(event) {
        this.chatProvider = event.detail.value;
    }

    handleApiKeyChange(event) {
        this.apiKeyInput = event.target.value;
    }

    handleModelChange(event) {
        this.model = event.target.value;
    }

    handleOpenAiApiKeyChange(event) {
        this.openAiApiKeyInput = event.target.value;
    }

    handleOpenAiModelChange(event) {
        this.openAiModel = event.target.value;
    }

    handleGeminiApiKeyChange(event) {
        this.geminiApiKeyInput = event.target.value;
    }

    handleGeminiModelChange(event) {
        this.geminiModel = event.target.value;
    }

    handleAgentforceAgentIdChange(event) {
        this.agentforceAgentId = event.target.value;
    }

    handleAgentforceMyDomainUrlChange(event) {
        this.agentforceMyDomainUrl = event.target.value;
    }

    handleAgentforceClientIdChange(event) {
        this.agentforceClientId = event.target.value;
    }

    handleSave() {
        const previous = {
            model: this.model,
            hasApiKey: this.hasApiKey,
            chatProvider: this.chatProvider,
            openAiModel: this.openAiModel,
            hasOpenAiApiKey: this.hasOpenAiApiKey,
            geminiModel: this.geminiModel,
            hasGeminiApiKey: this.hasGeminiApiKey,
            agentforceAgentId: this.agentforceAgentId,
            agentforceMyDomainUrl: this.agentforceMyDomainUrl,
            agentforceClientId: this.agentforceClientId
        };

        const input = {
            chatProvider: this.chatProvider,
            apiKey: this.apiKeyInput,
            model: this.model,
            openAiApiKey: this.openAiApiKeyInput,
            openAiModel: this.openAiModel,
            geminiApiKey: this.geminiApiKeyInput,
            geminiModel: this.geminiModel,
            agentforceAgentId: this.agentforceAgentId,
            agentforceMyDomainUrl: this.agentforceMyDomainUrl,
            agentforceClientId: this.agentforceClientId
        };
        const hasText = (v) => !!(v && v.trim().length > 0);

        this.isSaving = true;
        setAgentSettings({ input })
            .then(() => {
                if (hasText(input.apiKey)) this.hasApiKey = true;
                if (hasText(input.openAiApiKey)) this.hasOpenAiApiKey = true;
                if (hasText(input.geminiApiKey)) this.hasGeminiApiKey = true;
                // Never leave an entered key sitting in its input.
                this.apiKeyInput = '';
                this.openAiApiKeyInput = '';
                this.geminiApiKeyInput = '';
                this.toast('Saved', 'GUS chat provider settings were updated.', 'success');
            })
            .catch((err) => {
                // Revert visual state on failure so the UI never shows a
                // setting that did not actually save.
                Object.assign(this, previous);
                this.toast('Could not save', this.messageFrom(err), 'error');
            })
            .finally(() => { this.isSaving = false; });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }
}
