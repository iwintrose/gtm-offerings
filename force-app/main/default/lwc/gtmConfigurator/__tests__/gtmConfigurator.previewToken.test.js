import { createElement } from 'lwc';
import GtmConfigurator from 'c/gtmConfigurator';
import checkPasswordRequired from '@salesforce/apex/GtmLinkAuthController.checkPasswordRequired';
import validatePreviewToken from '@salesforce/apex/GtmLinkAuthController.validatePreviewToken';

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
jest.mock(
    '@salesforce/apex/GtmLinkAuthController.validatePreviewToken',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// eslint-disable-next-line import/no-unresolved
const isRep = require('@salesforce/apex/GtmViewerContext.isRep').default;

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

/**
 * saToken URL-param bypass path (issue #108). A rep who just created a link
 * clicks "Preview the page" (gtmConfigWizard's previewHref, carrying
 * &saToken=...) and lands on a brand-new page load of this component with
 * no shared browser state with the Lightning tab that minted the token --
 * checkPasswordGate() is the only place that can pick it up.
 */
describe('c-gtm-configurator preview token bypass (issue #108)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        jest.clearAllMocks();
    });

    it('a valid saToken sets passwordVerified without ever calling checkPasswordRequired, and strips the token from the address bar', async () => {
        window.history.pushState({}, '', '/s/configurator?cfgId=a0X000000000042AAA&saToken=a0X000000000042AAA%3A1700000000%3Adeadbeef');
        validatePreviewToken.mockResolvedValue(true);

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();
        await flushPromises();

        expect(validatePreviewToken).toHaveBeenCalledWith({
            recordId: 'a0X000000000042AAA',
            token: 'a0X000000000042AAA:1700000000:deadbeef'
        });
        // No password prompt rendered -- a valid preview token is a
        // complete substitute for it, same as the sessionStorage-cached
        // token path.
        expect(element.shadowRoot.querySelector('.pw-gate')).toBeNull();
        // The normal password gate must never have been consulted.
        expect(checkPasswordRequired).not.toHaveBeenCalled();

        // The token is a live bypass credential and must not linger visibly
        // in the address bar once redeemed.
        expect(window.location.search).not.toContain('saToken');
        expect(window.location.search).toContain('cfgId=a0X000000000042AAA');

        // Same cache the password-entry path writes, so a same-session
        // refresh behaves identically either way.
        expect(window.sessionStorage.getItem('ma-auth-a0X000000000042AAA'))
            .toBe('a0X000000000042AAA:1700000000:deadbeef');
    });

    it('an invalid/expired saToken falls through to the normal password gate and still strips the token from the URL', async () => {
        window.history.pushState({}, '', '/s/configurator?cfgId=a0X000000000043AAA&saToken=bogus%3A1%3Adeadbeef');
        validatePreviewToken.mockResolvedValue(false);
        checkPasswordRequired.mockResolvedValue(true);

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();
        await flushPromises();

        expect(validatePreviewToken).toHaveBeenCalled();
        // Falls through to the ordinary gate exactly as a cold prospect
        // would see it.
        expect(checkPasswordRequired).toHaveBeenCalledWith({ recordId: 'a0X000000000043AAA' });
        expect(element.shadowRoot.querySelector('.pw-gate')).not.toBeNull();
        expect(window.location.search).not.toContain('saToken');
    });

    it('no saToken present at all behaves exactly like today -- goes straight to checkPasswordRequired', async () => {
        window.history.pushState({}, '', '/s/configurator?cfgId=a0X000000000044AAA');
        checkPasswordRequired.mockResolvedValue(true);

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();
        await flushPromises();

        expect(validatePreviewToken).not.toHaveBeenCalled();
        expect(checkPasswordRequired).toHaveBeenCalledWith({ recordId: 'a0X000000000044AAA' });
    });
});
