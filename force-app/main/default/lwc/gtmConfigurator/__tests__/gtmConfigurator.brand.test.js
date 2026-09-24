import { createElement } from 'lwc';
import GtmConfigurator from 'c/gtmConfigurator';
import checkPasswordRequired from '@salesforce/apex/GtmLinkAuthController.checkPasswordRequired';

jest.mock(
    '@salesforce/apex/GtmViewerContext.isRep',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmLinkAuthController.checkPasswordRequired',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// eslint-disable-next-line import/no-unresolved
const isRep = require('@salesforce/apex/GtmViewerContext.isRep').default;

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('gtmConfigurator brand pass', () => {
    beforeEach(() => {
        checkPasswordRequired.mockResolvedValue(false);
        document.querySelectorAll('link[data-gtm-fonts="1"]').forEach((l) => l.remove());
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        document.querySelectorAll('link[data-gtm-fonts="1"]').forEach((l) => l.remove());
        jest.clearAllMocks();
    });

    it('injects the Inter Google Fonts link on connect', async () => {
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();
        await flushPromises();

        const link = document.querySelector('link[data-gtm-fonts="1"]');
        expect(link).not.toBeNull();
        expect(link.href).toContain('fonts.googleapis.com/css2');
        expect(link.href).toContain('family=Inter');
        expect(link.href).not.toContain('Sohne');
        expect(link.href).not.toContain('Sora');
    });

    it('renders the top-bar wordmark as two-tone "publicis"/"sapient" spans, lowercase', async () => {
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();
        await flushPromises();

        const black = element.shadowRoot.querySelector('.psbar .wm-black');
        const red = element.shadowRoot.querySelector('.psbar .wm-red');
        expect(black).not.toBeNull();
        expect(red).not.toBeNull();
        expect(black.textContent.trim()).toBe('publicis');
        expect(red.textContent.trim()).toBe('sapient');
    });
});
