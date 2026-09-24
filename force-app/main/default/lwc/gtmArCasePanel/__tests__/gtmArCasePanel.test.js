/**
 * Issue #63 — gtmArCasePanel: inline Case summary on AR record page.
 *
 * Verifies:
 *  - Case subject/status/date render when wired data is present.
 *  - Panel renders empty (no error thrown) when wired data is null.
 *  - Error from wire does not crash the component.
 */
import { createElement } from 'lwc';
import GtmArCasePanel from 'c/gtmArCasePanel';
import getCaseForRequest from '@salesforce/apex/GtmArCasePanelController.getCaseForRequest';

// Mock the Apex wire as a jest function; the LWC testing library intercepts
// @wire adapters that resolve to a jest.fn via virtual mock.
jest.mock(
    '@salesforce/apex/GtmArCasePanelController.getCaseForRequest',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const { registerApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
const getCaseAdapter = registerApexTestWireAdapter(getCaseForRequest);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const MOCK_CASE = {
    subject:     'Review and approve readout — Acme',
    status:      'New',
    createdDate: '2026-08-01'
};

describe('c-gtm-ar-case-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders case subject, status, and date when data is returned', async () => {
        const el = createElement('c-gtm-ar-case-panel', { is: GtmArCasePanel });
        el.recordId = 'a001000000000001';
        document.body.appendChild(el);

        getCaseAdapter.emit(MOCK_CASE);
        await flushPromises();

        const text = el.shadowRoot.textContent;
        expect(text).toContain('Review and approve readout — Acme');
        expect(text).toContain('New');
        expect(text).toContain('2026-08-01');
    });

    it('renders nothing (no error) when wire returns null', async () => {
        const el = createElement('c-gtm-ar-case-panel', { is: GtmArCasePanel });
        el.recordId = 'a001000000000002';
        document.body.appendChild(el);

        getCaseAdapter.emit(null);
        await flushPromises();

        const panel = el.shadowRoot.querySelector('.ar-case-panel');
        expect(panel).toBeNull();
    });

    it('sets error state when wire errors', async () => {
        const el = createElement('c-gtm-ar-case-panel', { is: GtmArCasePanel });
        el.recordId = 'a001000000000003';
        document.body.appendChild(el);

        getCaseAdapter.error({ message: 'Apex error' });
        await flushPromises();

        const panel = el.shadowRoot.querySelector('.ar-case-panel');
        expect(panel).toBeNull();
    });
});
