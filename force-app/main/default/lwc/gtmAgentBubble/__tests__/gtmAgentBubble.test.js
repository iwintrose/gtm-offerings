import { createElement } from 'lwc';

const mockSubscribe = jest.fn(() => Promise.resolve({}));
const mockUnsubscribe = jest.fn(() => Promise.resolve());
jest.mock('lightning/empApi', () => ({
    subscribe: (...args) => mockSubscribe(...args),
    unsubscribe: (...args) => mockUnsubscribe(...args)
}));

// eslint-disable-next-line import/first
import GtmAgentBubble from 'c/gtmAgentBubble';

jest.mock('@salesforce/apex/GtmAgentProxyController.chatOnApp',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmAgentProxyController.chat',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmAgentProxyController.chatOnReadout',
    () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function mount(props = {}) {
    const el = createElement('c-gtm-agent-bubble', { is: GtmAgentBubble });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

describe('c/gtmAgentBubble', () => {
    afterEach(() => {
        document.body.innerHTML = '';
        jest.clearAllMocks();
    });

    it('starts closed with the plain (non-docked) root and fab classes', () => {
        const el = mount();
        const root = el.shadowRoot.querySelector('.ab-root');
        const fab = el.shadowRoot.querySelector('.ab-fab');
        expect(root.className).toBe('ab-root');
        expect(fab.className).toBe('ab-fab');
    });

    it('toggles to the open fab class and shows the panel on click', async () => {
        const el = mount();
        el.shadowRoot.querySelector('.ab-fab').click();
        await flushPromises();
        expect(el.shadowRoot.querySelector('.ab-fab').className).toBe('ab-fab ab-fab--open');
        expect(el.shadowRoot.querySelector('.ab-panel')).not.toBeNull();
    });

    it('docked mode renders the docked root class and skips empApi subscription', async () => {
        mount({ docked: true });
        await flushPromises();
        expect(mockSubscribe).not.toHaveBeenCalled();
    });

    it('non-docked mode subscribes to the config-update platform event', async () => {
        mount({ docked: false });
        await flushPromises();
        expect(mockSubscribe).toHaveBeenCalled();
    });

    it('docked root uses the ab-root--docked class', () => {
        const el = mount({ docked: true });
        expect(el.shadowRoot.querySelector('.ab-root').className).toBe('ab-root ab-root--docked');
    });

    it('mascot mood is idle when closed and happy once opened', async () => {
        const el = mount();
        expect(el.shadowRoot.querySelector('c-gtm-mascot').mood).toBe('idle');
        el.shadowRoot.querySelector('.ab-fab').click();
        await flushPromises();
        const openMascots = el.shadowRoot.querySelectorAll('c-gtm-mascot');
        expect(openMascots[0].mood).toBe('happy');
    });
});
