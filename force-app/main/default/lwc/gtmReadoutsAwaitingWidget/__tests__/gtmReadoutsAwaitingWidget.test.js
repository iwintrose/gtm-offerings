/**
 * ISSUE #overview-bd-heat-redesign-3-daily-widgets
 *
 * gtmReadoutsAwaitingWidget: renders rows from GtmReadoutsAwaitingController
 * and its loading/error/empty states. Asserts the COARSE PROXY wording
 * ("sent N days ago, no update since") and that neither "viewed" nor
 * "replied" ever appears -- there is no such signal (see the task-scope
 * doc's explicitly-out-of-scope section).
 *
 * ISSUE #tasks-widget-row-navigation: each openable row is a click/Enter/
 * Space target that opens the readout's parent assessment workspace via
 * c/gtmNavigate's openReadout (never a bare GTM_Readout__c record page --
 * docs/architecture/gtm-row-open-and-links.md). The real c/gtmNavigate
 * module is used (not mocked); only lightning/navigation is re-mocked so
 * the exact Navigate payload it builds can be asserted, same pattern as
 * gtmAssessmentSubmissionView.test.js.
 */
const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) => {
        return class extends Base {
            [Navigate](...args) {
                mockNavigate(...args);
            }
        };
    };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin };
});

// eslint-disable-next-line import/first, import/order
import { createElement } from 'lwc';
// eslint-disable-next-line import/first
import GtmReadoutsAwaitingWidget from 'c/gtmReadoutsAwaitingWidget';
import getReadoutsAwaiting from '@salesforce/apex/GtmReadoutsAwaitingController.getReadoutsAwaiting';

jest.mock(
    '@salesforce/apex/GtmReadoutsAwaitingController.getReadoutsAwaiting',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function mount() {
    const el = createElement('c-gtm-readouts-awaiting-widget', { is: GtmReadoutsAwaitingWidget });
    document.body.appendChild(el);
    return el;
}

afterEach(() => {
    document.body.innerHTML = '';
    jest.clearAllMocks();
    mockNavigate.mockClear();
});

describe('gtmReadoutsAwaitingWidget', () => {
    it('renders rows with the coarse "sent N days ago, no update since" proxy wording', async () => {
        getReadoutsAwaiting.mockResolvedValue([
            { readoutId: 'r1', opportunityId: 'o1', opportunityName: 'Acme Deal', accountName: 'Acme Inc', sentDate: '2026-09-19', daysSinceSent: 3 },
            { readoutId: 'r2', opportunityId: 'o2', opportunityName: 'Beta Deal', accountName: 'Beta Co', sentDate: '2026-09-21', daysSinceSent: 1 }
        ]);
        const el = mount();
        await flushPromises();

        const rows = el.shadowRoot.querySelectorAll('[data-id="readout-row"]');
        expect(rows.length).toBe(2);
        const proxyLabels = Array.from(el.shadowRoot.querySelectorAll('[data-id="readout-proxy-label"]')).map((n) => n.textContent);
        expect(proxyLabels).toContain('sent 3 days ago, no update since');
        expect(proxyLabels).toContain('sent 1 day ago, no update since');
        proxyLabels.forEach((label) => {
            expect(label.toLowerCase()).not.toContain('viewed');
            expect(label.toLowerCase()).not.toContain('replied');
        });
    });

    it('shows the empty state when there are no rows', async () => {
        getReadoutsAwaiting.mockResolvedValue([]);
        const el = mount();
        await flushPromises();

        expect(el.shadowRoot.querySelector('[data-id="readouts-empty"]')).not.toBeNull();
        expect(el.shadowRoot.querySelectorAll('[data-id="readout-row"]').length).toBe(0);
    });

    it('shows an error state with retry on Apex failure', async () => {
        getReadoutsAwaiting.mockRejectedValue({ body: { message: 'boom' } });
        const el = mount();
        await flushPromises();

        const errorEl = el.shadowRoot.querySelector('[data-id="readouts-error"]');
        expect(errorEl).not.toBeNull();
        expect(errorEl.textContent).toContain('boom');
    });

    it('is keyboard-accessible: role=button and tabindex=0 on a row with a known parent assessment', async () => {
        getReadoutsAwaiting.mockResolvedValue([
            {
                readoutId: 'a0R000000000001', assessmentRequestId: 'a0Q000000000009', offeringKey: 'migration-accelerator',
                opportunityId: 'o1', opportunityName: 'Acme Deal', accountName: 'Acme Inc', sentDate: '2026-09-19', daysSinceSent: 3
            }
        ]);
        const el = mount();
        await flushPromises();

        const row = el.shadowRoot.querySelector('[data-id="readout-row"]');
        expect(row.getAttribute('role')).toBe('button');
        expect(row.getAttribute('tabindex')).toBe('0');
        expect(row.getAttribute('aria-label')).toBe('Acme Inc, Acme Deal, sent 3 days ago, no update since');
    });

    it('clicking a row opens the parent assessment workspace with the readout focused, never a bare record page', async () => {
        getReadoutsAwaiting.mockResolvedValue([
            {
                readoutId: 'a0R000000000001', assessmentRequestId: 'a0Q000000000009', offeringKey: 'migration-accelerator',
                opportunityId: 'o1', opportunityName: 'Acme Deal', accountName: 'Acme Inc', sentDate: '2026-09-19', daysSinceSent: 3
            }
        ]);
        const el = mount();
        await flushPromises();

        const row = el.shadowRoot.querySelector('[data-id="readout-row"]');
        row.dispatchEvent(new CustomEvent('click'));

        expect(mockNavigate).toHaveBeenCalledTimes(1);
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: {
                c__assessmentRequestId: 'a0Q000000000009',
                c__readoutId: 'a0R000000000001',
                c__offeringKey: 'migration-accelerator'
            }
        });
    });

    it('pressing Enter on a row navigates the same as a click', async () => {
        getReadoutsAwaiting.mockResolvedValue([
            {
                readoutId: 'a0R000000000001', assessmentRequestId: 'a0Q000000000009', offeringKey: 'migration-accelerator',
                opportunityId: 'o1', opportunityName: 'Acme Deal', accountName: 'Acme Inc', sentDate: '2026-09-19', daysSinceSent: 3
            }
        ]);
        const el = mount();
        await flushPromises();

        const row = el.shadowRoot.querySelector('[data-id="readout-row"]');
        row.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));

        expect(mockNavigate).toHaveBeenCalledTimes(1);
    });

    it('a readout with no known parent assessment (orphan) is rendered non-interactive and never navigates', async () => {
        getReadoutsAwaiting.mockResolvedValue([
            {
                readoutId: 'a0R000000000002', assessmentRequestId: null, offeringKey: 'migration-accelerator',
                opportunityId: 'o2', opportunityName: 'Orphan Deal', accountName: 'Orphan Co', sentDate: '2026-09-19', daysSinceSent: 3
            }
        ]);
        const el = mount();
        await flushPromises();

        const row = el.shadowRoot.querySelector('[data-id="readout-row"]');
        expect(row.getAttribute('role')).toBeNull();
        expect(row.getAttribute('tabindex')).toBeNull();

        row.dispatchEvent(new CustomEvent('click'));
        expect(mockNavigate).not.toHaveBeenCalled();
    });
});
