import { createElement } from 'lwc';
import GtmConfigurator from 'c/gtmConfigurator';
import isRep from '@salesforce/apex/GtmViewerContext.isRep';

// Issue-99-post-sso-identity. An unauthenticated rep who followed a
// ?wizard=1 link (chooseIndustry's tiles, or an old bookmark) is, for that
// request, the site's guest user -- accessBlocked is correctly true, same as
// a genuine prospect with no link. What was missing was any indication that
// logging in (via #106's "Login with Salesforce" SSO flow) is the way
// forward: they saw the same "This page needs a link." copy a real guest
// would. This does not change who gets blocked (accessBlocked's own gate is
// untested here and untouched) -- only what the already-blocked panel shows.
jest.mock(
    '@salesforce/apex/GtmViewerContext.isRep',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-gtm-configurator — login prompt for an unauthenticated wizard visitor', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        jest.restoreAllMocks();
        jest.clearAllMocks();
    });

    function blockedPanel(element) {
        return element.shadowRoot.querySelector('.expired.on');
    }
    function loginPrompt(element) {
        return element.shadowRoot.querySelector('[data-id="access-blocked-login-prompt"]');
    }
    function plain(element) {
        return element.shadowRoot.querySelector('[data-id="access-blocked-plain"]');
    }

    it('accessBlocked + wizard=1 shows the login prompt, not the generic message', async () => {
        window.history.pushState({}, '', '/configurator?wizard=1');
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();

        expect(blockedPanel(element)).not.toBeNull();
        const prompt = loginPrompt(element);
        expect(prompt).not.toBeNull();
        expect(prompt.textContent).toContain('Log in with your Salesforce account to continue');
        expect(plain(element)).toBeNull();

        // The link is present and points at the site's login route, carrying
        // a startURL back to the exact wizard URL so a rep who completes
        // "Login with Salesforce" doesn't land on a bare site root.
        const link = element.shadowRoot.querySelector('[data-id="access-blocked-login-link"]');
        expect(link).not.toBeNull();
        expect(link.getAttribute('href')).toMatch(/^\/login\?startURL=/);
        expect(link.getAttribute('href')).toContain(encodeURIComponent('wizard=1'));
    });

    it('accessBlocked without wizard=1 still shows the old generic message', async () => {
        window.history.pushState({}, '', '/configurator');
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();

        expect(blockedPanel(element)).not.toBeNull();
        expect(plain(element)).not.toBeNull();
        expect(plain(element).textContent).toContain('This page needs a link.');
        expect(loginPrompt(element)).toBeNull();
    });

    it('not accessBlocked (a real cfgId link) shows neither prompt', async () => {
        window.history.pushState({}, '', '/configurator?wizard=1&cfgId=a0X000000000001');
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();

        // savedRecordId is set, so accessBlocked is false -- neither of its
        // panel's two messages can render, regardless of anything else this
        // cfgId happens to resolve to (e.g. an unmocked isActive/expiry
        // check landing on a different, unrelated blocked state).
        expect(loginPrompt(element)).toBeNull();
        expect(plain(element)).toBeNull();
    });

    it('the wire error state still wins over the login prompt (no masked misconfiguration)', async () => {
        window.history.pushState({}, '', '/configurator?wizard=1');
        const consoleError = jest.spyOn(console, 'error').mockImplementation(() => {});
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.error({ body: { message: 'no access' }, status: 403 });
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="access-check-failed"]')).not.toBeNull();
        expect(loginPrompt(element)).toBeNull();
        expect(plain(element)).toBeNull();
        consoleError.mockRestore();
    });
});
