import { createElement } from 'lwc';
import GtmConfigurator from 'c/gtmConfigurator';
import isRep from '@salesforce/apex/GtmViewerContext.isRep';

// isConfigManager is the server-verified isRep wire, so the wire has to be a
// test adapter we can drive into each of its three states: pending, error,
// and a clean false.
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

// Issue #99. GtmViewerContext was granted class access in GTM_Guest only, so a
// logged-in rep's isRep wire threw on class access and the caller read the
// throw as "not a rep" — the same swallow GtmViewerContext.cls:16-26 documents
// as a previously fixed defect on the guard-class side. The grants are the
// blocking fix; this covers the caller no longer failing silently.
describe('c-gtm-configurator — isRep wire failure is not silent', () => {
    let consoleError;

    beforeEach(() => {
        consoleError = jest.spyOn(console, 'error').mockImplementation(() => {});
    });

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
    function diagnostic(element) {
        return element.shadowRoot.querySelector('[data-id="access-check-failed"]');
    }
    function plain(element) {
        return element.shadowRoot.querySelector('[data-id="access-blocked-plain"]');
    }

    it('does NOT render the diagnostic while the check is still pending', async () => {
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        // No emit and no error: the wire has not resolved.
        await flushPromises();

        // The wall itself is still up — accessBlocked must not be softened
        // during the pending window, or a true guest briefly sees template
        // content on a bare public URL.
        expect(blockedPanel(element)).not.toBeNull();
        expect(plain(element)).not.toBeNull();
        expect(plain(element).textContent).toContain('This page needs a link.');
        // The operator diagnostic is gated on the 'error' state specifically,
        // so it cannot flash before the wire has actually failed.
        expect(diagnostic(element)).toBeNull();
    });

    it('on wire error logs GtmViewerContext.isRep, stays blocked, shows the diagnostic', async () => {
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.error({ body: { message: 'no access' }, status: 403 });
        await flushPromises();

        // (a) the failure is named in the console
        const logged = consoleError.mock.calls.map((args) => String(args[0])).join('\n');
        expect(logged).toContain('GtmViewerContext.isRep');

        // (b) still fail-closed: the blocked panel is rendering at all, which
        // only happens when accessBlocked is true
        expect(blockedPanel(element)).not.toBeNull();

        // (c) the operator diagnostic replaces the plain message
        const panel = diagnostic(element);
        expect(panel).not.toBeNull();
        expect(panel.textContent).toContain('Access check failed.');
        expect(plain(element)).toBeNull();

        // (d) operator-neutral: a genuine anonymous visitor can reach this
        // string when a site's Guest User Profile is missing GTM_Guest, so it
        // must leak no class or permission-set names.
        const visible = blockedPanel(element).textContent;
        expect(visible).not.toContain('GtmViewerContext');
        expect(visible).not.toContain('GTM_Guest');
        expect(visible).not.toContain('GTM_Offering_User');
        expect(visible).not.toContain('Apex');
    });

    it('on a clean false shows the plain message and never the diagnostic', async () => {
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();

        expect(blockedPanel(element)).not.toBeNull();
        expect(plain(element)).not.toBeNull();
        expect(plain(element).textContent).toContain('This page needs a link.');
        expect(diagnostic(element)).toBeNull();
        const logged = consoleError.mock.calls.map((args) => String(args[0])).join('\n');
        expect(logged).not.toContain('GtmViewerContext.isRep');
    });

    // Issue rep-initiated-assessment-no-page-1-picker-and-record: the old
    // internal-user exemption on accessBlocked (`!this.isConfigManager &&
    // !this.savedRecordId`) waved ANY internal user through to a live,
    // unattributed questionnaire on the bare URL with no savedRecordId. It
    // is now closed entirely -- an internal user with no savedRecordId sees
    // the same blocked panel a guest would, not a second parallel flag.
    it('no longer exempts an internal user (isRep true) with no savedRecordId', async () => {
        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(true);
        await flushPromises();

        expect(blockedPanel(element)).not.toBeNull();
        expect(plain(element)).not.toBeNull();
        expect(plain(element).textContent).toContain('This page needs a link.');
    });
});
