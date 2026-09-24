import { createElement } from 'lwc';
import getAgentSettings from '@salesforce/apex/GtmAgentSettingsController.getAgentSettings';
import setAgentSettings from '@salesforce/apex/GtmAgentSettingsController.setAgentSettings';
import GtmOfferingsSettingsAgent from 'c/gtmOfferingsSettingsAgent';

jest.mock(
    '@salesforce/apex/GtmAgentSettingsController.getAgentSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAgentSettingsController.setAgentSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-gtm-offerings-settings-agent', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('never pre-fills the API key input, even when a key is already stored', async () => {
        getAgentSettings.mockResolvedValue({ hasApiKey: true, model: 'claude-sonnet-5' });
        const element = createElement('c-gtm-offerings-settings-agent', {
            is: GtmOfferingsSettingsAgent
        });
        document.body.appendChild(element);
        await flushPromises();

        const [apiKeyInput] = element.shadowRoot.querySelectorAll('lightning-input');
        expect(apiKeyInput.type).toBe('password');
        expect(apiKeyInput.value).toBe('');

        const statusLine = element.shadowRoot.textContent;
        expect(statusLine).toContain('Key is set');
    });

    it('shows "No key set" when no key is stored', async () => {
        getAgentSettings.mockResolvedValue({ hasApiKey: false, model: '' });
        const element = createElement('c-gtm-offerings-settings-agent', {
            is: GtmOfferingsSettingsAgent
        });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('No key set');
    });

    it('loads the model into the text input', async () => {
        getAgentSettings.mockResolvedValue({ hasApiKey: false, model: 'claude-sonnet-4' });
        const element = createElement('c-gtm-offerings-settings-agent', {
            is: GtmOfferingsSettingsAgent
        });
        document.body.appendChild(element);
        await flushPromises();

        const [, modelInput] = element.shadowRoot.querySelectorAll('lightning-input');
        expect(modelInput.value).toBe('claude-sonnet-4');
    });

    it('saves the model and API key through setAgentSettings', async () => {
        getAgentSettings.mockResolvedValue({ hasApiKey: false, model: '', chatProvider: 'Anthropic', hasOpenAiApiKey: false, openAiModel: '' });
        setAgentSettings.mockResolvedValue();
        const element = createElement('c-gtm-offerings-settings-agent', {
            is: GtmOfferingsSettingsAgent
        });
        document.body.appendChild(element);
        await flushPromises();

        const [apiKeyInput, modelInput] = element.shadowRoot.querySelectorAll('lightning-input');
        apiKeyInput.value = 'new-key-value';
        apiKeyInput.dispatchEvent(new CustomEvent('change'));

        modelInput.value = 'claude-sonnet-5';
        modelInput.dispatchEvent(new CustomEvent('change'));

        const saveButton = element.shadowRoot.querySelector('lightning-button');
        saveButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(setAgentSettings).toHaveBeenCalledWith({
            input: expect.objectContaining({
                apiKey: 'new-key-value',
                model: 'claude-sonnet-5',
                chatProvider: 'Anthropic',
                openAiApiKey: '',
                openAiModel: ''
            })
        });
    });

    it('defaults the chat provider picker to Anthropic when unset', async () => {
        getAgentSettings.mockResolvedValue({ hasApiKey: false, model: '', chatProvider: 'Anthropic', hasOpenAiApiKey: false, openAiModel: '' });
        const element = createElement('c-gtm-offerings-settings-agent', {
            is: GtmOfferingsSettingsAgent
        });
        document.body.appendChild(element);
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox.value).toBe('Anthropic');
        expect(combobox.options).toEqual([
            { label: 'Anthropic (Claude)', value: 'Anthropic' },
            { label: 'OpenAI (GPT)', value: 'OpenAI' },
            { label: 'Google Gemini', value: 'Gemini' },
            { label: 'Salesforce Agentforce', value: 'Agentforce' }
        ]);
    });

    it('never pre-fills the OpenAI API key input, even when a key is already stored', async () => {
        getAgentSettings.mockResolvedValue({ hasApiKey: false, model: '', chatProvider: 'OpenAI', hasOpenAiApiKey: true, openAiModel: 'gpt-4o' });
        const element = createElement('c-gtm-offerings-settings-agent', {
            is: GtmOfferingsSettingsAgent
        });
        document.body.appendChild(element);
        await flushPromises();

        const [openAiKeyInput] = element.shadowRoot.querySelectorAll('lightning-input');
        expect(openAiKeyInput.type).toBe('password');
        expect(openAiKeyInput.value).toBe('');
        expect(element.shadowRoot.textContent).toContain('Key is set');
    });

    it('saves provider, both keys independently, and both models through setAgentSettings', async () => {
        getAgentSettings.mockResolvedValue({ hasApiKey: true, model: 'claude-sonnet-5', chatProvider: 'Anthropic', hasOpenAiApiKey: false, openAiModel: '' });
        setAgentSettings.mockResolvedValue();
        const element = createElement('c-gtm-offerings-settings-agent', {
            is: GtmOfferingsSettingsAgent
        });
        document.body.appendChild(element);
        await flushPromises();

        // Switch provider to OpenAI without touching the (already-stored) Claude key.
        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.value = 'OpenAI';
        combobox.dispatchEvent(new CustomEvent('change', { detail: { value: 'OpenAI' } }));

        await flushPromises();
        const [openAiKeyInput, openAiModelInput] = element.shadowRoot.querySelectorAll('lightning-input');
        openAiKeyInput.value = 'sk-new-openai-key';
        openAiKeyInput.dispatchEvent(new CustomEvent('change'));

        openAiModelInput.value = 'gpt-4o-mini';
        openAiModelInput.dispatchEvent(new CustomEvent('change'));

        const saveButton = element.shadowRoot.querySelector('lightning-button');
        saveButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(setAgentSettings).toHaveBeenCalledWith({
            input: expect.objectContaining({
                apiKey: '',
                model: 'claude-sonnet-5',
                chatProvider: 'OpenAI',
                openAiApiKey: 'sk-new-openai-key',
                openAiModel: 'gpt-4o-mini'
            })
        });
    });

    it('clears the API key input after a successful save', async () => {
        getAgentSettings.mockResolvedValue({ hasApiKey: false, model: '' });
        setAgentSettings.mockResolvedValue();
        const element = createElement('c-gtm-offerings-settings-agent', {
            is: GtmOfferingsSettingsAgent
        });
        document.body.appendChild(element);
        await flushPromises();

        const [apiKeyInput] = element.shadowRoot.querySelectorAll('lightning-input');
        apiKeyInput.value = 'new-key-value';
        apiKeyInput.dispatchEvent(new CustomEvent('change'));

        const saveButton = element.shadowRoot.querySelector('lightning-button');
        saveButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(apiKeyInput.value).toBe('');
    });

    it('shows a load error if the setting cannot be read', async () => {
        getAgentSettings.mockRejectedValue(new Error('boom'));
        const element = createElement('c-gtm-offerings-settings-agent', {
            is: GtmOfferingsSettingsAgent
        });
        document.body.appendChild(element);
        await flushPromises();

        const error = element.shadowRoot.querySelector('.slds-text-color_error');
        expect(error).not.toBeNull();
    });

    async function mountWith(dto) {
        getAgentSettings.mockResolvedValue(dto);
        const element = createElement('c-gtm-offerings-settings-agent', {
            is: GtmOfferingsSettingsAgent
        });
        document.body.appendChild(element);
        await flushPromises();
        return element;
    }

    async function selectProvider(element, value) {
        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.dispatchEvent(new CustomEvent('change', { detail: { value } }));
        await flushPromises();
    }

    const labelsOf = (element) =>
        Array.from(element.shadowRoot.querySelectorAll('lightning-input')).map((i) => i.label);

    it('renders only the selected provider inputs in the DOM', async () => {
        const element = await mountWith({ chatProvider: 'Anthropic' });
        expect(labelsOf(element)).toEqual(['Claude API Key', 'Claude Model']);

        await selectProvider(element, 'OpenAI');
        expect(labelsOf(element)).toEqual(['OpenAI API Key', 'OpenAI Model']);

        await selectProvider(element, 'Gemini');
        expect(labelsOf(element)).toEqual(['Gemini API Key', 'Gemini Model']);

        await selectProvider(element, 'Agentforce');
        expect(labelsOf(element)).toEqual(['Agent ID', 'My Domain URL', 'Consumer Key']);
    });

    it('never pre-fills the Gemini key and shows its status line', async () => {
        const element = await mountWith({ chatProvider: 'Gemini', hasGeminiApiKey: true, geminiModel: 'gemini-2.5-pro' });
        const [keyInput, modelInput] = element.shadowRoot.querySelectorAll('lightning-input');
        expect(keyInput.type).toBe('password');
        expect(keyInput.value).toBe('');
        expect(modelInput.value).toBe('gemini-2.5-pro');
        expect(element.shadowRoot.textContent).toContain('Key is set');
    });

    it('shows the Agentforce notice only when Agentforce is selected, with no secret input', async () => {
        const element = await mountWith({
            chatProvider: 'Agentforce',
            agentforceAgentId: '0Xx000000000001AAA',
            agentforceMyDomainUrl: 'https://example.my.salesforce.com',
            agentforceClientId: 'ck'
        });
        expect(element.shadowRoot.querySelector('.agentforce-notice').textContent).toContain(
            'GUS will keep using the first configured provider until it ships.'
        );
        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        expect(Array.from(inputs).map((i) => i.value)).toEqual([
            '0Xx000000000001AAA',
            'https://example.my.salesforce.com',
            'ck'
        ]);
        expect(Array.from(inputs).some((i) => i.type === 'password')).toBe(false);

        await selectProvider(element, 'Anthropic');
        expect(element.shadowRoot.querySelector('.agentforce-notice')).toBeNull();
    });

    it('keeps typed model values when switching provider and back, and sends all values on save', async () => {
        setAgentSettings.mockResolvedValue();
        const element = await mountWith({ chatProvider: 'Anthropic', model: 'claude-sonnet-5', hasApiKey: true });

        await selectProvider(element, 'Gemini');
        let inputs = element.shadowRoot.querySelectorAll('lightning-input');
        inputs[1].value = 'gemini-2.5-pro';
        inputs[1].dispatchEvent(new CustomEvent('change'));

        await selectProvider(element, 'Anthropic');
        inputs = element.shadowRoot.querySelectorAll('lightning-input');
        expect(inputs[1].value).toBe('claude-sonnet-5');

        await selectProvider(element, 'Gemini');
        inputs = element.shadowRoot.querySelectorAll('lightning-input');
        expect(inputs[1].value).toBe('gemini-2.5-pro');

        element.shadowRoot.querySelector('lightning-button').dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(setAgentSettings).toHaveBeenCalledWith({
            input: {
                chatProvider: 'Gemini',
                apiKey: '',
                model: 'claude-sonnet-5',
                openAiApiKey: '',
                openAiModel: '',
                geminiApiKey: '',
                geminiModel: 'gemini-2.5-pro',
                agentforceAgentId: '',
                agentforceMyDomainUrl: '',
                agentforceClientId: ''
            }
        });
    });

    it('does not mark a key as set when the save fails', async () => {
        setAgentSettings.mockRejectedValue({ body: { message: 'nope' } });
        const element = await mountWith({ chatProvider: 'Anthropic', hasGeminiApiKey: false });
        await selectProvider(element, 'Gemini');
        const [keyInput] = element.shadowRoot.querySelectorAll('lightning-input');
        keyInput.value = 'gm-key';
        keyInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('lightning-button').dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('No key set');
        expect(element.shadowRoot.textContent).not.toContain('Key is set');
    });
});
