import { createElement } from 'lwc';

// Same re-mock technique gtmAssessmentSubmissionView.test.js/
// gtmAssessmentDetail.test.js already use: the stock sfdx-lwc-jest
// navigation stub defines [NavigationMixin.Navigate] on a sealed prototype
// that cannot be spied on in place, and this suite needs to both observe
// Navigate's payload AND drive CurrentPageReference (drill-in state).
const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](...args) {
                mockNavigate(...args);
            }
        };
    NavigationMixin.Navigate = Navigate;
    const { createTestWireAdapter } = jest.requireActual('@salesforce/wire-service-jest-util');
    return {
        NavigationMixin,
        CurrentPageReference: createTestWireAdapter(jest.fn())
    };
});

// eslint-disable-next-line import/first, import/order
import { CurrentPageReference } from 'lightning/navigation';
// eslint-disable-next-line import/first, import/order
import GtmContactEngagement from 'c/gtmContactEngagement';
// eslint-disable-next-line import/first, import/order
import getEngagementSummaries from '@salesforce/apex/GtmContactEngagementController.getEngagementSummaries';

jest.mock(
    '@salesforce/apex/GtmContactEngagementController.getEngagementSummaries',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function setPageRef(state = {}) {
    CurrentPageReference.emit({ state });
    await flushPromises();
}

function result(items, overrides = {}) {
    return { items, totalCount: items.length, truncated: false, ...overrides };
}

const OPEN_READOUT_ROW = {
    recordId: 'a0X000000000001',
    linkId: 'a0S000000000001',
    linkName: 'SC-0015',
    company: 'Commercial Metals',
    contactId: '003000000000001',
    contactName: 'Jordan Reyes',
    accountId: '001000000000001',
    state: 'submitted_draft',
    stateLabel: 'Your turn — open the readout',
    rank: 1,
    primaryAction: 'open_readout',
    primaryActionLabel: 'Open the readout'
};

const RESEND_ROW = {
    recordId: null,
    linkId: 'a0S000000000002',
    linkName: 'SC-0022',
    company: 'Commercial Metals',
    contactId: '003000000000001',
    contactName: 'Jordan Reyes',
    accountId: '001000000000001',
    state: 'never_opened',
    stateLabel: 'Not yet opened',
    rank: 5,
    primaryAction: 'resend',
    primaryActionLabel: 'Resend'
};

const NONE_ROW = {
    recordId: 'a0X000000000003',
    linkId: 'a0S000000000003',
    linkName: 'SC-0031',
    company: 'Solara Health',
    contactId: '003000000000002',
    contactName: 'Priya Sundaram',
    accountId: '001000000000002',
    state: 'sent_complete',
    stateLabel: 'Complete',
    rank: 6,
    primaryAction: 'none',
    primaryActionLabel: '—'
};

describe('c-gtm-contact-engagement -- Contact record page mount (backward compatible)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('calls Apex with the record page contactId and no scope toggle', async () => {
        getEngagementSummaries.mockResolvedValue(result([OPEN_READOUT_ROW]));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        el.recordId = '003000000000001';
        document.body.appendChild(el);
        await flushPromises();

        expect(getEngagementSummaries).toHaveBeenCalledWith(
            expect.objectContaining({ contactId: '003000000000001', accountId: null })
        );
        expect(el.shadowRoot.querySelector('.scope-toggle')).toBeNull();
        expect(el.shadowRoot.querySelectorAll('.engagement-row').length).toBe(1);
    });

    it('shows the empty-state message when the wire returns no rows', async () => {
        getEngagementSummaries.mockResolvedValue(result([]));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        el.recordId = '003000000000002';
        document.body.appendChild(el);
        await flushPromises();

        expect(el.shadowRoot.querySelector('.empty-state')).not.toBeNull();
        expect(el.shadowRoot.querySelectorAll('.engagement-row').length).toBe(0);
    });
});

describe('c-gtm-contact-engagement -- Engagement Links landing tab (no recordId)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('defaults to My links scope and shows the scope toggle', async () => {
        getEngagementSummaries.mockResolvedValue(result([OPEN_READOUT_ROW]));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        document.body.appendChild(el);
        await setPageRef({});

        expect(getEngagementSummaries).toHaveBeenCalledWith(
            expect.objectContaining({ contactId: null, accountId: null, scopeKey: 'mine' })
        );
        expect(el.shadowRoot.querySelector('.scope-toggle')).not.toBeNull();
    });

    it('groups rows visually by contact (D8) and preserves rank order within and across groups', async () => {
        getEngagementSummaries.mockResolvedValue(
            result([OPEN_READOUT_ROW, RESEND_ROW, NONE_ROW])
        );
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        document.body.appendChild(el);
        await setPageRef({});

        const groups = el.shadowRoot.querySelectorAll('.engagement-group');
        expect(groups.length).toBe(2);
        expect(groups[0].querySelector('.contact-name').textContent).toBe('Jordan Reyes');
        expect(groups[0].querySelectorAll('.engagement-row').length).toBe(2);
        expect(groups[1].querySelector('.contact-name').textContent).toBe('Priya Sundaram');
        expect(groups[1].querySelectorAll('.engagement-row').length).toBe(1);
    });

    it('re-fetches with the new scopeKey when the scope toggle changes', async () => {
        getEngagementSummaries.mockResolvedValue(result([]));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        document.body.appendChild(el);
        await setPageRef({});

        getEngagementSummaries.mockClear();
        const combobox = el.shadowRoot.querySelector('.scope-toggle');
        combobox.dispatchEvent(new CustomEvent('change', { detail: { value: 'team' } }));
        await flushPromises();

        expect(getEngagementSummaries).toHaveBeenCalledWith(
            expect.objectContaining({ scopeKey: 'team', pageNumber: 1 })
        );
    });

    it('reads c__rlfAccountId/c__rlfContactId drill-in state and hides the scope toggle', async () => {
        getEngagementSummaries.mockResolvedValue(result([OPEN_READOUT_ROW]));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        document.body.appendChild(el);
        await setPageRef({ c__rlfAccountId: '001000000000001', c__rlfContactId: '003000000000001' });

        expect(getEngagementSummaries).toHaveBeenCalledWith(
            expect.objectContaining({ contactId: '003000000000001', accountId: null })
        );
        expect(el.shadowRoot.querySelector('.scope-toggle')).toBeNull();
    });

    it('an account-only drill-in (no contact) passes accountId through', async () => {
        getEngagementSummaries.mockResolvedValue(result([OPEN_READOUT_ROW]));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        document.body.appendChild(el);
        await setPageRef({ c__rlfAccountId: '001000000000001' });

        expect(getEngagementSummaries).toHaveBeenCalledWith(
            expect.objectContaining({ contactId: null, accountId: '001000000000001' })
        );
    });
});

describe('c-gtm-contact-engagement -- row actions (D8 + D13)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('"Open the readout" navigates to the Assessments workspace for that request', async () => {
        getEngagementSummaries.mockResolvedValue(result([OPEN_READOUT_ROW]));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        document.body.appendChild(el);
        await setPageRef({});

        el.shadowRoot.querySelector('button[data-action="open_readout"]').click();

        expect(mockNavigate).toHaveBeenCalledWith(
            expect.objectContaining({
                attributes: { apiName: 'GTM_Assessments' },
                state: expect.objectContaining({ c__assessmentRequestId: 'a0X000000000001' })
            })
        );
    });

    it('"Resend" opens the engagement link itself, not an assessment (no request exists yet)', async () => {
        getEngagementSummaries.mockResolvedValue(result([RESEND_ROW]));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        document.body.appendChild(el);
        await setPageRef({});

        el.shadowRoot.querySelector('button[data-action="resend"]').click();

        expect(mockNavigate).toHaveBeenCalledWith(
            expect.objectContaining({
                attributes: { apiName: 'GTM_Pages' },
                state: expect.objectContaining({
                    c__rlfLinkId: 'a0S000000000002',
                    c__rlfAccountId: '001000000000001',
                    c__rlfContactId: '003000000000001'
                })
            })
        );
    });

    it('the "Sent / complete" row (no action) renders no button, just an em dash', async () => {
        getEngagementSummaries.mockResolvedValue(result([NONE_ROW]));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        document.body.appendChild(el);
        await setPageRef({});

        expect(el.shadowRoot.querySelector('button[data-action]')).toBeNull();
        expect(el.shadowRoot.querySelector('.row-action--none').textContent).toBe('—');
    });

    it('a "Published but not sent" row renders a disabled Send button with a tooltip', async () => {
        const row = {
            ...OPEN_READOUT_ROW,
            state: 'published_unsent',
            stateLabel: 'Your turn — send to prospect',
            rank: 2,
            primaryAction: 'send_disabled',
            primaryActionLabel: 'Send to prospect'
        };
        getEngagementSummaries.mockResolvedValue(result([row]));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        document.body.appendChild(el);
        await setPageRef({});

        const disabledButton = el.shadowRoot.querySelector('lightning-button.row-action--disabled');
        expect(disabledButton).not.toBeNull();
        expect(disabledButton.disabled).toBe(true);
    });
});

describe('c-gtm-contact-engagement -- state labels (D13 legibility fix)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    // Owner feedback on this ticket's first build: the queue rendered the
    // raw enum ("submitted_draft", "published_unsent", ...) directly in the
    // row, so "the priority is hidden and unclear." Each row must instead
    // show the server-computed, human-readable `stateLabel` -- never the
    // raw `state` key -- and that label must name who's blocking, not just
    // restate the code in nicer words.
    const STATE_LABEL_CASES = [
        ['submitted_draft', 'Your turn — open the readout'],
        ['published_unsent', 'Your turn — send to prospect'],
        ['started_not_submitted', 'Nudge-able — they started, haven\'t finished'],
        ['opened_not_started', 'Nudge-able — they opened, haven\'t started'],
        ['never_opened', 'Not yet opened'],
        ['sent_complete', 'Complete']
    ];

    it.each(STATE_LABEL_CASES)(
        'state "%s" renders its human-readable label "%s", not the raw enum',
        async (state, stateLabel) => {
            const row = { ...OPEN_READOUT_ROW, state, stateLabel };
            getEngagementSummaries.mockResolvedValue(result([row]));
            const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
            document.body.appendChild(el);
            await setPageRef({});

            const stateEl = el.shadowRoot.querySelector('.row-state');
            expect(stateEl.textContent).toBe(stateLabel);
            expect(stateEl.textContent).not.toBe(state);
            // The raw enum is still available as a hook for styling/tests,
            // just not what's shown to the rep.
            expect(el.shadowRoot.querySelector('.engagement-row').dataset.state).toBe(state);
        }
    );

    it('falls back to the raw state key only if a payload omits stateLabel entirely', async () => {
        const row = { ...OPEN_READOUT_ROW };
        delete row.stateLabel;
        getEngagementSummaries.mockResolvedValue(result([row]));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        document.body.appendChild(el);
        await setPageRef({});

        expect(el.shadowRoot.querySelector('.row-state').textContent).toBe('submitted_draft');
    });
});

describe('c-gtm-contact-engagement -- paging', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('Next requests page 2 and Next stays enabled while more pages remain', async () => {
        // pageSize defaults to 25 -- 60 total rows means three pages, so
        // page 2 (rows 26-50) still has a page 3 (51-60) after it.
        getEngagementSummaries.mockResolvedValue(result([OPEN_READOUT_ROW], { totalCount: 60 }));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        document.body.appendChild(el);
        await setPageRef({});

        getEngagementSummaries.mockResolvedValue(result([OPEN_READOUT_ROW], { totalCount: 60 }));
        el.shadowRoot.querySelector('.paging-next').click();
        await flushPromises();

        expect(getEngagementSummaries).toHaveBeenLastCalledWith(
            expect.objectContaining({ pageNumber: 2 })
        );
        expect(el.shadowRoot.querySelector('.paging-next').disabled).toBe(false);
    });

    it('Previous is disabled on the first page', async () => {
        getEngagementSummaries.mockResolvedValue(result([OPEN_READOUT_ROW]));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        document.body.appendChild(el);
        await setPageRef({});

        expect(el.shadowRoot.querySelector('.paging-prev').disabled).toBe(true);
    });

    it('Next is disabled once every row has been fetched', async () => {
        getEngagementSummaries.mockResolvedValue(result([OPEN_READOUT_ROW], { totalCount: 1 }));
        const el = createElement('c-gtm-contact-engagement', { is: GtmContactEngagement });
        document.body.appendChild(el);
        await setPageRef({});

        expect(el.shadowRoot.querySelector('.paging-next').disabled).toBe(true);
    });
});
