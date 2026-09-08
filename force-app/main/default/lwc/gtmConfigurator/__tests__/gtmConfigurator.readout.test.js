import { createElement } from 'lwc';
import GtmConfigurator from 'c/gtmConfigurator';
import getPublishedReadout from '@salesforce/apex/GtmReadoutPublicController.getPublishedReadout';

// Scoped to the recipient-facing readout state machine in gtmConfigurator
// (Draft/Approved read as "in review"; Published replaces every prior section
// with a "view your assessment" entry point).
//
// PROVENANCE: this file was added on
// claude/salesforce-marketing-maturity-bsxmxs as
// lwc/maConfigurator/__tests__/maConfigurator.readout.test.js (c8945b8,
// extended by b1e2e80). The MA->GTM port (a2fc262) brought
// gtmConfigurator.html/.js/.css across and left the test behind, so the state
// machine shipped untested. Recovered from b1e2e80 and renamed into the GTM_
// world per d73b091's mapping. See ADR-0008 / the D11 plan section 0.3.
//
// NOTE ON THE SESSION KEYS: gtmConfigurator._assessmentSessionKey() and
// _readoutTokenSessionKey() still use the `ma-` prefix (`ma-assessment-<id>`,
// `ma-readout-token-<id>`). That is deliberate and must NOT be "fixed" -- it is
// live state in real prospects' browsers. The tests below assert the prefix so
// a future rename has to be a conscious one.
//
// GtmReadoutPublicController exposes exactly one guest method
// (getPublishedReadout(token)) by design, so this component only ever advances
// to Published from a token -- a `readout` URL param, or one remembered from a
// prior successful check in this browser's sessionStorage -- never from a
// status lookup by assessment request id (no such guest method exists). The
// rest of this component's behavior (CMS content, CRM strip, password gate,
// etc.) is out of scope here and tolerates its own Apex calls resolving to
// undefined via the default sfdx-lwc-jest apex mock.

jest.mock(
    '@salesforce/apex/GtmReadoutPublicController.getPublishedReadout',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

/** The three-state top-bar CTA, whichever state it is currently in. */
function topCta(element) {
    return element.shadowRoot.querySelector('.psbar .bar-right button.cta');
}

function topCtaText(element) {
    const btn = topCta(element);
    return btn ? btn.textContent.replace(/\s+/g, ' ').trim() : '';
}

/** The submitted event the assessment child raises on a successful submit. */
function dispatchSubmitted(element, detail) {
    const child = element.shadowRoot.querySelector('c-gtm-config-booking');
    expect(child).not.toBeNull();
    child.dispatchEvent(new CustomEvent('submitted', { detail }));
}

describe('c-gtm-configurator — recipient readout state machine', () => {
    let sessionStore;

    beforeEach(() => {
        sessionStore = {};
        jest.spyOn(window.sessionStorage.__proto__, 'getItem')
            .mockImplementation((k) => (k in sessionStore ? sessionStore[k] : null));
        jest.spyOn(window.sessionStorage.__proto__, 'setItem')
            .mockImplementation((k, v) => { sessionStore[k] = v; });
        getPublishedReadout.mockResolvedValue(null);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        jest.restoreAllMocks();
        jest.clearAllMocks();
    });

    it('shows the normal booking CTA before any assessment is submitted', async () => {
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        const bar = element.shadowRoot.querySelector('.psbar .bar-right');
        expect(bar.textContent).toContain('environment assessment');
        expect(element.shadowRoot.querySelector('.readout-gate')).toBeNull();
    });

    // Phase 1.3 -- the exact opening state the D11 swap has to preserve.
    it('opens on the enabled "Get an environment assessment" CTA with no request id', async () => {
        window.history.pushState({}, '', '/configurator?cfgId=CFG0&company=Northlight');
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        // Asserted in two parts on purpose. `.cta` is `display: inline-flex`
        // with `gap: .4rem`, so the space between "Get an" and "environment"
        // is supplied by the gap, not by a whitespace node -- which is why the
        // markup deliberately has no space (and why the &nbsp; that used to be
        // there was removed). textContent is therefore "Get anenvironment
        // assessment →" and a single toBe() on it would assert the absence of
        // a character the design intends to be absent.
        expect(element.shadowRoot.querySelector('.psbar .cta .cta-long').textContent)
            .toBe('Get an');
        expect(topCtaText(element)).toContain('environment assessment →');
        expect(topCta(element).disabled).toBe(false);
        expect(element.shadowRoot.querySelector('.readout-gate')).toBeNull();
    });

    it('switches the top CTA to a disabled "in review" state once submitted, with no token yet', async () => {
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        dispatchSubmitted(element, { assessmentRequestId: 'AR001' });
        await flushPromises();

        const cta = topCta(element);
        expect(cta.textContent).toContain('in review');
        expect(cta.disabled).toBe(true);
        expect(getPublishedReadout).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('.readout-gate')).toBeNull();
    });

    // Phase 1.3 -- the closing card is the second half of the same flip, and
    // is what a prospect who scrolls actually sees. Asserted separately from
    // the top CTA because they are two independent template branches over the
    // same getter, and the D11 swap edits the region around both.
    it('flips the closing card to "Your request has been submitted." on submit', async () => {
        window.history.pushState({}, '', '/configurator?cfgId=CFG3&company=Northlight');
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        const before = element.shadowRoot.querySelector('[data-section="closing"]');
        expect(before.textContent).not.toContain('Your request has been submitted.');

        dispatchSubmitted(element, { assessmentRequestId: 'AR003' });
        await flushPromises();

        const after = element.shadowRoot.querySelector('[data-section="closing"]');
        expect(after.textContent).toContain('Your request has been submitted.');
        expect(topCta(element).disabled).toBe(true);
    });

    it('persists the assessment id across a reconnect so "in review" survives a reload', async () => {
        // The session key is scoped by savedRecordId (cfgId), same as the
        // existing ma-auth- pattern this mirrors — a real prospect link
        // always carries one.
        window.history.pushState({}, '', '/configurator?cfgId=CFG1');

        const element1 = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element1);
        await flushPromises();
        dispatchSubmitted(element1, { assessmentRequestId: 'AR002' });
        await flushPromises();
        document.body.removeChild(element1);

        // The `ma-` prefix is live browser state; see the note at the top.
        expect(sessionStore['ma-assessment-CFG1']).toBe('AR002');

        const element2 = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element2);
        await flushPromises();

        expect(topCtaText(element2)).toContain('in review');
    });

    it('resolves a `readout` URL param via getPublishedReadout and shows the published gate', async () => {
        window.history.pushState({}, '', '/configurator?readout=tok1');
        getPublishedReadout.mockResolvedValue({
            content: '<p>Findings</p>',
            repName: 'Jamie Rep',
            repEmail: 'jamie@example.com',
            repPhone: '555-0100'
        });

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        expect(getPublishedReadout).toHaveBeenCalledWith({ token: 'tok1' });
        expect(element.shadowRoot.querySelector('.readout-gate')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.chap.cover')).toBeNull();

        // Phase 1.3 -- and the top CTA is the ENABLED third state, not the
        // disabled "in review" one.
        expect(topCtaText(element)).toBe('View your assessment');
        expect(topCta(element).disabled).toBe(false);
    });

    it('opens the modal with the already-fetched content and rep info, without a second Apex call', async () => {
        window.history.pushState({}, '', '/configurator?readout=tok1');
        getPublishedReadout.mockResolvedValue({
            content: '<p>Findings</p>',
            repName: 'Jamie Rep',
            repEmail: 'jamie@example.com',
            repPhone: '555-0100'
        });

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        const gateButton = element.shadowRoot.querySelector('.readout-gate .cta');
        gateButton.click();
        await flushPromises();

        expect(getPublishedReadout).toHaveBeenCalledTimes(1);
        expect(element.shadowRoot.querySelector('.scrim')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.modal-rep-name').textContent).toBe('Jamie Rep');
    });

    it('remembers a resolved token across a reconnect (no URL param on the next visit)', async () => {
        window.history.pushState({}, '', '/configurator?cfgId=CFG2&readout=tok2');
        getPublishedReadout.mockResolvedValue({ content: '<p>Findings</p>' });

        const element1 = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element1);
        await flushPromises();
        document.body.removeChild(element1);

        expect(sessionStore['ma-readout-token-CFG2']).toBe('tok2');

        window.history.pushState({}, '', '/configurator?cfgId=CFG2');
        getPublishedReadout.mockClear();
        getPublishedReadout.mockResolvedValue({ content: '<p>Findings</p>' });

        const element2 = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element2);
        await flushPromises();

        expect(getPublishedReadout).toHaveBeenCalledWith({ token: 'tok2' });
        expect(element2.shadowRoot.querySelector('.readout-gate')).not.toBeNull();
    });

    it('stays in "in review" (never errors) when a stored/param token no longer resolves', async () => {
        window.history.pushState({}, '', '/configurator?readout=stale-token');
        getPublishedReadout.mockResolvedValue(null);

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.readout-gate')).toBeNull();
        expect(element.shadowRoot.querySelector('.load-error')).toBeNull();
    });

    // This page is guest-facing. GtmReadoutPublicController's whole contract is
    // that an anonymous visitor cannot tell an invalid token from a valid but
    // unpublished or revoked one — c/gtmReadoutView swallows this same failure
    // with no detail for exactly that reason. A console.error carrying the
    // error object (status, message, the token in the request) would hand back
    // the distinction the Apex side is careful never to give, to anyone with
    // devtools open.
    it('logs no error detail to the guest console when the readout call rejects', async () => {
        window.history.pushState({}, '', '/configurator?readout=tok-rejects');
        getPublishedReadout.mockRejectedValue({
            body: { message: 'No such published readout' },
            status: 404
        });
        const consoleError = jest.spyOn(console, 'error').mockImplementation(() => {});
        const consoleWarn = jest.spyOn(console, 'warn').mockImplementation(() => {});
        const consoleLog = jest.spyOn(console, 'log').mockImplementation(() => {});

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        expect(getPublishedReadout).toHaveBeenCalledWith({ token: 'tok-rejects' });
        const logged = []
            .concat(consoleError.mock.calls, consoleWarn.mock.calls, consoleLog.mock.calls)
            .map((args) => args.join(' '))
            .join('\n');
        expect(logged).not.toContain('getPublishedReadout');
        expect(logged).not.toContain('No such published readout');
        expect(logged).not.toContain('tok-rejects');

        // And it fails the same way a resolved-but-empty response does.
        expect(element.shadowRoot.querySelector('.readout-gate')).toBeNull();
        expect(element.shadowRoot.querySelector('.load-error')).toBeNull();
    });
});
