import { createElement } from 'lwc';
import GtmConfigurator from 'c/gtmConfigurator';
import getPublishedReadout from '@salesforce/apex/GtmReadoutPublicController.getPublishedReadout';
import hasSubmittedAssessment from '@salesforce/apex/GtmConfigurationStatusController.hasSubmittedAssessment';
import getPublicConfiguration from '@salesforce/apex/GtmConfigurationReader.getPublicConfiguration';

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
//
// B12: isConfigManager stays false throughout this file (the isRep wire is
// never mocked), so the guest read path (GtmConfigurationReader
// .getPublicConfiguration) is what resolves a cfgId'd saved link's offering
// into linkOfferingKey. Left unmocked it auto-resolves to undefined, so
// effectiveOfferingKey never resolves and the whole chapter body -- the
// closing card these tests assert against -- is now correctly hidden behind
// isUnconfigured. Mocking it to resolve with an offering, as a real saved
// link would, keeps this suite scoped to the readout state machine it
// actually covers.

jest.mock(
    '@salesforce/apex/GtmReadoutPublicController.getPublishedReadout',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmConfigurationStatusController.hasSubmittedAssessment',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmConfigurationReader.getPublicConfiguration',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
// B12: loadSavedConfiguration() (which resolves a cfgId'd link's offering
// into linkOfferingKey via the getPublicConfiguration mock above) is only
// ever invoked from inside the isRep @wire callback. Left unmocked, the
// import falls back to a plain jest.fn() that @wire never treats as an
// adapter and so never fires -- which is fine for every test in this file
// except the two that assert on chapter-body content ("[data-section=
// closing]"), which now needs an offering to have resolved. Mocked here as a
// real (pending-until-emitted) wire adapter so those two tests can call
// isRep.emit(false) once; every other test in this file that never calls
// emit() sees identical pending-forever behavior to before.
jest.mock(
    '@salesforce/apex/GtmViewerContext.isRep',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

// eslint-disable-next-line import/no-unresolved
const isRep = require('@salesforce/apex/GtmViewerContext.isRep').default;

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

/**
 * The assessment child, opening the overlay first if it is not already open.
 *
 * Since ADR-0008 the questionnaire is rendered behind if:true={bookingOpen}
 * rather than always-mounted, so there is no child to talk to until the CTA has
 * been clicked. That is deliberate -- the questionnaire does real Apex work in
 * connectedCallback and must not do it for every prospect who never opens the
 * form -- and it means these tests exercise the real path a respondent takes.
 */
async function openAssessment(element) {
    if (!element.shadowRoot.querySelector('c-gtm-assessment-questionnaire')) {
        const cta = element.shadowRoot.querySelector('.psbar .bar-right button.cta');
        expect(cta).not.toBeNull();
        cta.click();
        await flushPromises();
    }
    const child = element.shadowRoot.querySelector('c-gtm-assessment-questionnaire');
    expect(child).not.toBeNull();
    return child;
}

/** The submitted event the assessment child raises on a successful submit. */
async function dispatchSubmitted(element, detail) {
    const child = await openAssessment(element);
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
        hasSubmittedAssessment.mockResolvedValue(false);
        getPublicConfiguration.mockResolvedValue({ offering: 'second-offering' });
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

        await dispatchSubmitted(element, { assessmentRequestId: 'AR001' });
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
        isRep.emit(false);
        await flushPromises();
        await flushPromises();

        const before = element.shadowRoot.querySelector('[data-section="closing"]');
        expect(before.textContent).not.toContain('Your request has been submitted.');

        await dispatchSubmitted(element, { assessmentRequestId: 'AR003' });
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
        await dispatchSubmitted(element1, { assessmentRequestId: 'AR002' });
        await flushPromises();
        document.body.removeChild(element1);

        // The `ma-` prefix is live browser state; see the note at the top.
        expect(sessionStore['ma-assessment-CFG1']).toBe('AR002');

        const element2 = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element2);
        await flushPromises();

        expect(topCtaText(element2)).toContain('in review');
    });

    // ── the submitted state survives a new browser (ADR-0008 section 4) ─────
    //
    // sessionStorage survives a refresh in the same tab and nothing else. A
    // prospect who submitted yesterday on their laptop was shown the open CTA
    // again on their phone, and could burn fifteen minutes re-answering a form
    // the server would now refuse. These cover the durable half.

    it('lands in the submitted state on first load in a fresh browser', async () => {
        // No sessionStorage at all -- exactly a new tab, a second device, or a
        // private window.
        window.history.pushState({}, '', '/configurator?cfgId=CFG-DONE&company=Northlight');
        hasSubmittedAssessment.mockResolvedValue(true);

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();
        await flushPromises();

        expect(hasSubmittedAssessment).toHaveBeenCalledWith({ recordId: 'CFG-DONE' });
        expect(topCtaText(element)).toContain('in review');
        expect(topCta(element).disabled).toBe(true);
        expect(
            element.shadowRoot.querySelector('[data-section="closing"]').textContent
        ).toContain('Your request has been submitted.');
    });

    it('leaves the CTA open when the durable check says no', async () => {
        window.history.pushState({}, '', '/configurator?cfgId=CFG-OPEN&company=Northlight');
        hasSubmittedAssessment.mockResolvedValue(false);

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        expect(topCtaText(element)).toContain('environment assessment →');
        expect(topCta(element).disabled).toBe(false);
    });

    it('fails OPEN when the durable check errors', async () => {
        // The server is the enforcement point. A status-check blip must never
        // lock a prospect out of a form they have not yet filled in -- the same
        // reasoning checkActiveStatus states for itself.
        window.history.pushState({}, '', '/configurator?cfgId=CFG-ERR&company=Northlight');
        hasSubmittedAssessment.mockRejectedValue(new Error('boom'));

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        expect(topCtaText(element)).toContain('environment assessment →');
        expect(topCta(element).disabled).toBe(false);
    });

    it('never asks the server about a link it does not have', async () => {
        window.history.pushState({}, '', '/configurator');
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        expect(hasSubmittedAssessment).not.toHaveBeenCalled();
    });

    it('lets the locally-known request id win over the bare boolean', async () => {
        // sessionStorage carries the actual assessmentRequestId; the durable
        // check only knows "yes". The specific answer must not be overwritten
        // by the vague one.
        window.history.pushState({}, '', '/configurator?cfgId=CFG1');
        sessionStore['ma-assessment-CFG1'] = 'AR-REAL';
        hasSubmittedAssessment.mockResolvedValue(true);

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        expect(topCtaText(element)).toContain('in review');
        // Not called at all: the local answer was already known and is better.
        expect(hasSubmittedAssessment).not.toHaveBeenCalled();
    });

    it('recovers to the submitted state when a submit loses the race', async () => {
        // ADR-0008 phase 5.2. The server refused this submit because an
        // assessment already landed for the link in another tab or on another
        // device. The honest state afterwards is "submitted" -- the request
        // exists -- not "failed". Recovered by re-asking the server, not by
        // matching on the refusal message.
        window.history.pushState({}, '', '/configurator?cfgId=CFG-RACE&company=Northlight');
        hasSubmittedAssessment.mockResolvedValue(false);

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();
        expect(topCtaText(element)).toContain('environment assessment →');

        // The submit now races and loses; the server has the request.
        hasSubmittedAssessment.mockResolvedValue(true);
        const child = await openAssessment(element);
        child.dispatchEvent(
            new CustomEvent('submitfailed', { detail: { message: 'already been submitted' } })
        );
        await flushPromises();

        expect(topCtaText(element)).toContain('in review');
        expect(topCta(element).disabled).toBe(true);
    });

    it('leaves the CTA alone when a submit failure really was just a failure', async () => {
        window.history.pushState({}, '', '/configurator?cfgId=CFG-NET&company=Northlight');
        hasSubmittedAssessment.mockResolvedValue(false);

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        const child = await openAssessment(element);
        child.dispatchEvent(
            new CustomEvent('submitfailed', { detail: { message: 'Network error' } })
        );
        await flushPromises();

        // Still open, so the respondent can retry rather than being told their
        // assessment is in review when it is not.
        expect(topCtaText(element)).toContain('environment assessment →');
        expect(topCta(element).disabled).toBe(false);
    });

    // ── emailed resume links (ADR-0008 phase 7.1) ───────────────────────────

    it('auto-opens the assessment when the URL carries a resume token', async () => {
        // The questionnaire lives behind /configurator now, so an emailed
        // resume link lands here. Dropping the respondent on the story page
        // with the form shut would be a resume link that does not resume.
        window.history.pushState(
            {}, '', '/configurator?cfgId=CFG-R&company=Northlight&resume=TOK-RESUME'
        );

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        const child = element.shadowRoot.querySelector('c-gtm-assessment-questionnaire');
        expect(child).not.toBeNull();
        expect(child.resumeToken).toBe('TOK-RESUME');
        // And the engagement link came with it, which is the whole point of
        // carrying cfgId on the emailed URL.
        expect(child.savedRecordId).toBe('CFG-R');
    });

    it('does not open the assessment without a resume token', async () => {
        window.history.pushState({}, '', '/configurator?cfgId=CFG-R&company=Northlight');

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        await flushPromises();

        // Closed until the CTA is clicked -- the questionnaire does real Apex
        // work on mount and must not do it for every prospect who never opens
        // the form.
        expect(
            element.shadowRoot.querySelector('c-gtm-assessment-questionnaire')
        ).toBeNull();
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
