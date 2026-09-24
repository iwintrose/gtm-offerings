import { createElement } from 'lwc';

// The stock sfdx-lwc-jest navigation stub defines [NavigationMixin.Navigate]
// on a sealed prototype, so it cannot be spied on or reassigned in place --
// same pattern as gtmAssessmentSubmissionView.test.js.
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
import getRepLeaderboard from '@salesforce/apex/GtmAnalyticsTeamController.getRepLeaderboard';
// eslint-disable-next-line import/first, import/order
import getFlaggedRequests from '@salesforce/apex/GtmAnalyticsTeamController.getFlaggedRequests';
// eslint-disable-next-line import/first, import/order
import getInstrumentVersionComparison from '@salesforce/apex/GtmAnalyticsTeamController.getInstrumentVersionComparison';
import GtmAnalyticsTeam from 'c/gtmAnalyticsTeam';

jest.mock(
    '@salesforce/apex/GtmAnalyticsTeamController.getRepLeaderboard',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/GtmAnalyticsTeamController.getFlaggedRequests',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/GtmAnalyticsTeamController.getInstrumentVersionComparison',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const ROWS = [
    { repId: '005000000000001', repName: 'Jane Rep', links: 22, submitted: 17, avgScore: 24.3, published: 9 },
    { repId: '005000000000002', repName: 'Sam Rep', links: 5, submitted: 0, avgScore: null, published: 0 }
];

const FLAGGED_RESULT = {
    rows: [
        {
            requestId: '003000000000001',
            requestName: 'Assessment-0001',
            repId: '005000000000001',
            repName: 'Jane Rep',
            createdDate: '2026-01-01T00:00:00.000Z',
            advisory: true,
            advisoryReason: 'Unsupported source/target pair.',
            flagMessages: ['High rebuild ratio.']
        }
    ],
    returnedCount: 1,
    hasMore: false
};

const VERSION_ROWS = [
    {
        pairKey: 'hubspot__mcn',
        version: 'v2',
        submitted: 10,
        avgScore: 24.3,
        tierCounts: { 'Discovery First': 0, 'Prep Required': 2, 'Accelerator-Ready': 6, 'Fast-Track': 2, Unscored: 0 },
        published: 6,
        publishRate: 60.0
    },
    {
        pairKey: '(unset)',
        version: '(unset)',
        submitted: 3,
        avgScore: null,
        tierCounts: { 'Discovery First': 0, 'Prep Required': 0, 'Accelerator-Ready': 0, 'Fast-Track': 0, Unscored: 3 },
        published: 0,
        publishRate: 0.0
    }
];

describe('c-gtm-analytics-team', () => {
    beforeEach(() => {
        getInstrumentVersionComparison.mockResolvedValue([]);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders one row per rep, sorted as returned by the controller', async () => {
        getRepLeaderboard.mockResolvedValue(ROWS);
        getFlaggedRequests.mockResolvedValue({ rows: [], returnedCount: 0, hasMore: false });

        const element = createElement('c-gtm-analytics-team', { is: GtmAnalyticsTeam });
        document.body.appendChild(element);
        await flushPromises();

        const rows = element.shadowRoot.querySelectorAll('.data-table tbody tr');
        expect(rows.length).toBe(2);
        expect(rows[0].textContent).toContain('Jane Rep');
        expect(rows[0].textContent).toContain('24');
        expect(rows[1].textContent).toContain('Sam Rep');
        expect(rows[1].textContent).toContain('—');
    });

    it('shows an empty state when no rep has links in range', async () => {
        getRepLeaderboard.mockResolvedValue([]);
        getFlaggedRequests.mockResolvedValue({ rows: [], returnedCount: 0, hasMore: false });

        const element = createElement('c-gtm-analytics-team', { is: GtmAnalyticsTeam });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.an-empty')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.data-table')).toBeNull();
    });

    it('surfaces an Apex error instead of failing silently', async () => {
        getRepLeaderboard.mockRejectedValue({ body: { message: 'boom' } });
        getFlaggedRequests.mockResolvedValue({ rows: [], returnedCount: 0, hasMore: false });

        const element = createElement('c-gtm-analytics-team', { is: GtmAnalyticsTeam });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.an-err').textContent).toBe('boom');
    });

    it('re-fetches on range change and manual refresh', async () => {
        getRepLeaderboard.mockResolvedValue(ROWS);
        getFlaggedRequests.mockResolvedValue({ rows: [], returnedCount: 0, hasMore: false });

        const element = createElement('c-gtm-analytics-team', { is: GtmAnalyticsTeam });
        document.body.appendChild(element);
        await flushPromises();
        expect(getRepLeaderboard).toHaveBeenCalledTimes(1);
        expect(getFlaggedRequests).toHaveBeenCalledTimes(1);

        element.shadowRoot.querySelector('lightning-combobox')
            .dispatchEvent(new CustomEvent('change', { detail: { value: '30' } }));
        await flushPromises();
        expect(getRepLeaderboard).toHaveBeenCalledTimes(2);
        expect(getFlaggedRequests).toHaveBeenCalledTimes(2);

        element.shadowRoot.querySelector('lightning-button-icon').click();
        await flushPromises();
        expect(getRepLeaderboard).toHaveBeenCalledTimes(3);
        expect(getFlaggedRequests).toHaveBeenCalledTimes(3);
    });

    it('renders the flagged/advisory panel with reasons and a "showing N of possibly more" hint when truncated', async () => {
        getRepLeaderboard.mockResolvedValue([]);
        getFlaggedRequests.mockResolvedValue({ ...FLAGGED_RESULT, hasMore: true, returnedCount: 500 });

        const element = createElement('c-gtm-analytics-team', { is: GtmAnalyticsTeam });
        document.body.appendChild(element);
        await flushPromises();

        const flaggedRow = element.shadowRoot.querySelector('.flagged-row');
        expect(flaggedRow).not.toBeNull();
        expect(flaggedRow.textContent).toContain('Assessment-0001');
        expect(flaggedRow.textContent).toContain('Jane Rep');
        expect(flaggedRow.textContent).toContain('Unsupported source/target pair.');
        expect(flaggedRow.textContent).toContain('High rebuild ratio.');

        const moreHint = element.shadowRoot.querySelector('.an-more');
        expect(moreHint).not.toBeNull();
        expect(moreHint.textContent).toContain('Showing 500 of possibly more');
    });

    it('shows an empty state for the flagged panel when nothing is flagged in range', async () => {
        getRepLeaderboard.mockResolvedValue(ROWS);
        getFlaggedRequests.mockResolvedValue({ rows: [], returnedCount: 0, hasMore: false });

        const element = createElement('c-gtm-analytics-team', { is: GtmAnalyticsTeam });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.flagged-row')).toBeNull();
        const emptyStates = element.shadowRoot.querySelectorAll('.an-empty');
        expect(
            Array.from(emptyStates).some((el) =>
                el.textContent.includes('No flagged or advisory assessments')
            )
        ).toBe(true);
    });

    it('surfaces a flagged-panel Apex error independently of the leaderboard', async () => {
        getRepLeaderboard.mockResolvedValue(ROWS);
        getFlaggedRequests.mockRejectedValue({ body: { message: 'flagged boom' } });

        const element = createElement('c-gtm-analytics-team', { is: GtmAnalyticsTeam });
        document.body.appendChild(element);
        await flushPromises();

        const errs = Array.from(element.shadowRoot.querySelectorAll('.an-err'));
        expect(errs.some((el) => el.textContent === 'flagged boom')).toBe(true);
    });

    it('navigates to the record page when a flagged row is clicked', async () => {
        getRepLeaderboard.mockResolvedValue([]);
        getFlaggedRequests.mockResolvedValue(FLAGGED_RESULT);

        const element = createElement('c-gtm-analytics-team', { is: GtmAnalyticsTeam });
        document.body.appendChild(element);
        await flushPromises();

        mockNavigate.mockClear();
        element.shadowRoot.querySelector('.flagged-row').click();

        expect(mockNavigate).toHaveBeenCalledTimes(1);
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__recordPage',
            attributes: {
                recordId: '003000000000001',
                objectApiName: 'GTM_Assessment_Request__c',
                actionName: 'view'
            }
        });
    });

    it('renders the instrument version comparison panel, including the "(unset)" bucket', async () => {
        getRepLeaderboard.mockResolvedValue([]);
        getFlaggedRequests.mockResolvedValue({ rows: [], returnedCount: 0, hasMore: false });
        getInstrumentVersionComparison.mockResolvedValue(VERSION_ROWS);

        const element = createElement('c-gtm-analytics-team', { is: GtmAnalyticsTeam });
        document.body.appendChild(element);
        await flushPromises();

        const tables = element.shadowRoot.querySelectorAll('.data-table');
        expect(tables.length).toBe(1);

        const rows = tables[0].querySelectorAll('tbody tr');
        expect(rows.length).toBe(2);
        expect(rows[0].textContent).toContain('hubspot__mcn');
        expect(rows[0].textContent).toContain('v2');
        expect(rows[0].textContent).toContain('60.0%');
        expect(rows[1].textContent).toContain('(unset)');
        expect(rows[1].textContent).toContain('—');
    });

    it('shows an empty state for the version panel when there is no data in range', async () => {
        getRepLeaderboard.mockResolvedValue(ROWS);
        getFlaggedRequests.mockResolvedValue(FLAGGED_RESULT);
        getInstrumentVersionComparison.mockResolvedValue([]);

        const element = createElement('c-gtm-analytics-team', { is: GtmAnalyticsTeam });
        document.body.appendChild(element);
        await flushPromises();

        const emptyMessages = element.shadowRoot.querySelectorAll('.an-empty');
        expect(emptyMessages.length).toBe(1);
        expect(emptyMessages[0].textContent).toContain('No assessment requests');
    });

    it('surfaces an Apex error from the version comparison call without failing silently', async () => {
        getRepLeaderboard.mockResolvedValue(ROWS);
        getInstrumentVersionComparison.mockRejectedValue({ body: { message: 'version boom' } });

        const element = createElement('c-gtm-analytics-team', { is: GtmAnalyticsTeam });
        document.body.appendChild(element);
        await flushPromises();

        const errors = element.shadowRoot.querySelectorAll('.an-err');
        expect(Array.from(errors).some((e) => e.textContent === 'version boom')).toBe(true);
    });

    it('re-fetches the version comparison on range change and manual refresh', async () => {
        getRepLeaderboard.mockResolvedValue([]);
        getInstrumentVersionComparison.mockResolvedValue(VERSION_ROWS);

        const element = createElement('c-gtm-analytics-team', { is: GtmAnalyticsTeam });
        document.body.appendChild(element);
        await flushPromises();
        expect(getInstrumentVersionComparison).toHaveBeenCalledTimes(1);

        element.shadowRoot.querySelector('lightning-combobox')
            .dispatchEvent(new CustomEvent('change', { detail: { value: '30' } }));
        await flushPromises();
        expect(getInstrumentVersionComparison).toHaveBeenCalledTimes(2);

        element.shadowRoot.querySelector('lightning-button-icon').click();
        await flushPromises();
        expect(getInstrumentVersionComparison).toHaveBeenCalledTimes(3);
    });
});
