import { createElement } from 'lwc';

// The stock navigation stub cannot be spied on in place; replace it, keeping a
// controllable CurrentPageReference adapter (same pattern as gtmAnalyticsTeam).
const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const { createTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) => {
        return class extends Base {
            [Navigate](...args) {
                mockNavigate(...args);
            }
        };
    };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: createTestWireAdapter(jest.fn()) };
});

// eslint-disable-next-line import/first, import/order
import { CurrentPageReference } from 'lightning/navigation';
// eslint-disable-next-line import/first, import/order
import GtmGusUtility from 'c/gtmGusUtility';

jest.mock('@salesforce/apex/GtmAgentProxyController.chatOnApp',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmAgentProxyController.chat',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmAgentProxyController.chatOnReadout',
    () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function mount() {
    const el = createElement('c-gtm-gus-utility', { is: GtmGusUtility });
    document.body.appendChild(el);
    await flushPromises();
    return el;
}

function chatEl(el) {
    return el.shadowRoot.querySelector('c-gtm-agent-chat');
}

afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
});

describe('c-gtm-gus-utility', () => {
    it('renders the chat in app mode', async () => {
        const el = await mount();
        expect(chatEl(el).mode).toBe('app');
        expect(chatEl(el).pageContext).toEqual({});
    });

    it('maps a nav item page reference to the allow-listed context', async () => {
        const el = await mount();
        CurrentPageReference.emit({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Pages' },
            state: { c__stage: 'quiet', secret: 'do not forward' }
        });
        await flushPromises();
        expect(chatEl(el).pageContext).toEqual({ pageType: 'standard__navItemPage', tabApiName: 'GTM_Pages' });
    });

    it('maps a record page reference and never forwards unknown fields', async () => {
        const el = await mount();
        CurrentPageReference.emit({
            type: 'standard__recordPage',
            attributes: { recordId: '001000000000001AAA', objectApiName: 'Account', apiName: 'Ignored', other: 'x' },
            state: { anything: 'y' }
        });
        await flushPromises();
        expect(chatEl(el).pageContext).toEqual({
            pageType: 'standard__recordPage',
            objectApiName: 'Account',
            recordId: '001000000000001AAA'
        });
    });

    it('an empty page reference yields {}', async () => {
        const el = await mount();
        CurrentPageReference.emit(undefined);
        await flushPromises();
        expect(chatEl(el).pageContext).toEqual({});
        CurrentPageReference.emit({});
        await flushPromises();
        expect(chatEl(el).pageContext).toEqual({});
    });

    it('agentaction for GTM_Pages + c__stage navigates with exact args', async () => {
        const el = await mount();
        chatEl(el).dispatchEvent(new CustomEvent('agentaction', {
            detail: { type: 'navigate', label: 'Show', apiName: 'GTM_Pages', state: { c__stage: 'quiet' } }
        }));
        expect(mockNavigate).toHaveBeenCalledTimes(1);
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Pages' },
            state: { c__stage: 'quiet' }
        });
    });

    it('agentaction for home navigates to the standard named page', async () => {
        const el = await mount();
        chatEl(el).dispatchEvent(new CustomEvent('agentaction', {
            detail: { type: 'navigate', label: 'Home', apiName: 'home', state: {} }
        }));
        expect(mockNavigate).toHaveBeenCalledTimes(1);
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__namedPage',
            attributes: { pageName: 'home' }
        });
    });

    it.each([
        ['GTM_Offerings_Overview (retired key)', { apiName: 'GTM_Offerings_Overview', state: {} }],
        ['state on home', { apiName: 'home', state: { c__stage: 'quiet' } }],
        ['non-allow-listed apiName', { apiName: 'Some_Other_Tab', state: {} }],
        ['prototype key apiName', { apiName: 'constructor', state: {} }],
        ['non-allow-listed state key', { apiName: 'GTM_Pages', state: { c__other: 'x' } }],
        ['non-c__ state key', { apiName: 'GTM_Pages', state: { stage: 'x' } }],
        ['non-string state value', { apiName: 'GTM_Pages', state: { c__stage: 5 } }],
        ['oversize state value', { apiName: 'GTM_Pages', state: { c__stage: 'x'.repeat(201) } }],
        ['state on a tab that takes none', { apiName: 'GTM_Analytics', state: { c__stage: 'quiet' } }]
    ])('does not navigate for %s', async (_name, detail) => {
        const el = await mount();
        chatEl(el).dispatchEvent(new CustomEvent('agentaction', {
            detail: { type: 'navigate', label: 'x', ...detail }
        }));
        expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('ignores agentdelta', async () => {
        const el = await mount();
        chatEl(el).dispatchEvent(new CustomEvent('agentdelta', { detail: { changes: { a: 1 } } }));
        expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('New chat calls reset on the chat', async () => {
        const el = await mount();
        const chat = chatEl(el);
        chat.reset = jest.fn();
        el.shadowRoot.querySelector('.gus-new').click();
        expect(chat.reset).toHaveBeenCalledTimes(1);
    });

    it('does not import empApi', () => {
        const src = require('fs').readFileSync(
            require('path').join(__dirname, '..', 'gtmGusUtility.js'), 'utf8');
        expect(src).not.toMatch(/from\s+['"]lightning\/empApi['"]/);
    });
});
