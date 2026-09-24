import { createElement } from 'lwc';
import getSummary from '@salesforce/apex/GtmAnalyticsController.getSummary';
import getOfferingBreakdown from '@salesforce/apex/GtmAnalyticsController.getOfferingBreakdown';
import hasTeamAccess from '@salesforce/apex/GtmAnalyticsTeamController.hasTeamAccess';
import GtmAnalytics from 'c/gtmAnalytics';

jest.mock(
    '@salesforce/apex/GtmAnalyticsController.getSummary',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAnalyticsController.getOfferingBreakdown',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAnalyticsTeamController.hasTeamAccess',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

// Issue #138: "assessmentsCompleted"/Status__c='Completed' filtering is gone
// -- assessmentsSubmitted (a request's mere existence) is the one honest
// prospect-side signal, and the rep's own follow-up pipeline is its own field.
const SUMMARY_WITH_DATA = {
    linksCreated: 64,
    linksCreatedPrior: 54,
    linksOpened: 40,
    assessmentsSubmitted: 45,
    assessmentsSubmittedPrior: 40,
    readoutsPublished: 21,
    readoutsPublishedPrior: 22,
    avgDaysToPublish: 3.2,
    avgDaysToPublishPrior: 3.8,
    tierMix: [
        { tier: 'Fast-Track', count: 15, pct: 41 },
        { tier: 'Accelerator-Ready', count: 14, pct: 38 },
        { tier: 'Discovery First', count: 8, pct: 21 }
    ],
    followUpStatusCounts: [
        { status: 'New', count: 20 },
        { status: 'Contacted', count: 15 },
        { status: 'Completed', count: 10 }
    ],
    trend: [
        { year: 2026, week: 1, opens: 10, submitted: 6 },
        { year: 2026, week: 2, opens: 14, submitted: 9 }
    ]
};

const ROWS = [
    { offering: 'Data Cloud Migration Readiness', links: 22, submitted: 17, avgScore: 78, published: 9, topTier: 'Accelerator-Ready' },
    { offering: 'AI Enablement Assessment', links: 19, submitted: 13, avgScore: 64, published: 6, topTier: 'Prep Required' }
];

const EMPTY_SUMMARY = {
    linksCreated: 0,
    linksCreatedPrior: 0,
    linksOpened: 0,
    assessmentsSubmitted: 0,
    assessmentsSubmittedPrior: 0,
    readoutsPublished: 0,
    readoutsPublishedPrior: 0,
    avgDaysToPublish: 0,
    avgDaysToPublishPrior: 0,
    tierMix: [],
    followUpStatusCounts: [],
    trend: []
};

describe('c-gtm-analytics', () => {
    beforeEach(() => {
        // Default: no team access, so existing "my view" tests don't need
        // to know or care about the toggle. Tests that exercise the toggle
        // itself override this.
        hasTeamAccess.mockResolvedValue(false);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders KPI tiles, funnel, tier mix, follow-up status, and the offering table', async () => {
        getSummary.mockResolvedValue(SUMMARY_WITH_DATA);
        getOfferingBreakdown.mockResolvedValue(ROWS);

        const element = createElement('c-gtm-analytics', { is: GtmAnalytics });
        document.body.appendChild(element);
        await flushPromises();

        const kpis = element.shadowRoot.querySelectorAll('.kpi-value');
        expect(kpis.length).toBe(4);
        expect(kpis[0].textContent).toBe('64');
        expect(kpis[1].textContent).toBe('45');
        expect(kpis[2].textContent).toBe('21');

        // Issue #138: the funnel is 3 steps now (opened/submitted/published),
        // not the old 4-step opened/started/completed/published.
        const funnelValues = Array.from(element.shadowRoot.querySelectorAll('.fstep-value')).map((n) => n.textContent);
        expect(funnelValues).toEqual(['40', '45', '21']);

        expect(element.shadowRoot.querySelectorAll('.tier-row').length).toBe(6);
        expect(element.shadowRoot.textContent).toContain('Fast-Track');

        // The rep follow-up pipeline is its own panel, separate from tier mix.
        expect(element.shadowRoot.textContent).toContain('Rep follow-up status');
        expect(element.shadowRoot.textContent).toContain('Contacted');

        const dataRows = element.shadowRoot.querySelectorAll('.data-table tbody tr');
        expect(dataRows.length).toBe(2);
        expect(dataRows[0].textContent).toContain('Data Cloud Migration Readiness');
        expect(dataRows[0].textContent).toContain('17');
    });

    it('renders the shared page header with eyebrow, title, and the selected range as meta', async () => {
        getSummary.mockResolvedValue(SUMMARY_WITH_DATA);
        getOfferingBreakdown.mockResolvedValue(ROWS);

        const element = createElement('c-gtm-analytics', { is: GtmAnalytics });
        document.body.appendChild(element);
        await flushPromises();

        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header).not.toBeNull();
        expect(header.eyebrow).toBe('Analytics');
        expect(header.title).toBe('Your engagement analytics');
        expect(header.meta).toBe('Last 90 days');

        // The range dropdown and Refresh button live inside the header's
        // actions slot now, not a standalone toolbar -- confirm they're
        // still there exactly once (no duplication).
        expect(header.querySelectorAll('lightning-combobox[slot="actions"]').length).toBe(1);
        expect(header.querySelectorAll('lightning-button-icon[slot="actions"]').length).toBe(1);
    });

    it('updates the header meta to the newly selected range', async () => {
        getSummary.mockResolvedValue(SUMMARY_WITH_DATA);
        getOfferingBreakdown.mockResolvedValue(ROWS);

        const element = createElement('c-gtm-analytics', { is: GtmAnalytics });
        document.body.appendChild(element);
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.dispatchEvent(new CustomEvent('change', { detail: { value: '30' } }));
        await flushPromises();

        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header.meta).toBe('Last 30 days');
    });

    it('shows an empty state when there are no links in the selected range', async () => {
        getSummary.mockResolvedValue(EMPTY_SUMMARY);
        getOfferingBreakdown.mockResolvedValue([]);

        const element = createElement('c-gtm-analytics', { is: GtmAnalytics });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.an-empty')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.kpi-row')).toBeNull();
    });

    it('re-fetches with a new date range when the range picker changes', async () => {
        getSummary.mockResolvedValue(SUMMARY_WITH_DATA);
        getOfferingBreakdown.mockResolvedValue(ROWS);

        const element = createElement('c-gtm-analytics', { is: GtmAnalytics });
        document.body.appendChild(element);
        await flushPromises();

        expect(getSummary).toHaveBeenCalledTimes(1);
        const firstCallRange = getSummary.mock.calls[0][0];

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.dispatchEvent(new CustomEvent('change', { detail: { value: '30' } }));
        await flushPromises();

        expect(getSummary).toHaveBeenCalledTimes(2);
        const secondCallRange = getSummary.mock.calls[1][0];
        expect(secondCallRange.rangeStart).not.toBe(firstCallRange.rangeStart);
    });

    it('surfaces an Apex error instead of failing silently', async () => {
        getSummary.mockRejectedValue({ body: { message: 'boom' } });
        getOfferingBreakdown.mockResolvedValue([]);

        const element = createElement('c-gtm-analytics', { is: GtmAnalytics });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.an-err').textContent).toBe('boom');
    });

    // Issue #130: a single week of activity (e.g. a brand-new offering, or a
    // short date range) produced a 1-point polyline, which SVG renders as
    // nothing -- confirmed live in gtm-dev. Marker dots must always render,
    // regardless of how many points the trend has.
    it('renders a marker dot even when the trend has only one data point', async () => {
        getSummary.mockResolvedValue({
            ...SUMMARY_WITH_DATA,
            trend: [{ year: 2026, week: 37, opens: 4, submitted: 4 }]
        });
        getOfferingBreakdown.mockResolvedValue(ROWS);

        const element = createElement('c-gtm-analytics', { is: GtmAnalytics });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.trend-svg')).not.toBeNull();
        expect(element.shadowRoot.querySelectorAll('.trend-dot--opens').length).toBe(1);
        expect(element.shadowRoot.querySelectorAll('.trend-dot--submitted').length).toBe(1);
        const polylines = element.shadowRoot.querySelectorAll('.trend-line');
        polylines.forEach((p) => expect(p.getAttribute('points').trim().split(' ').length).toBe(1));
    });

    it('renders a marker dot at every point of a multi-point trend', async () => {
        getSummary.mockResolvedValue(SUMMARY_WITH_DATA);
        getOfferingBreakdown.mockResolvedValue(ROWS);

        const element = createElement('c-gtm-analytics', { is: GtmAnalytics });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelectorAll('.trend-dot--opens').length).toBe(SUMMARY_WITH_DATA.trend.length);
        expect(element.shadowRoot.querySelectorAll('.trend-dot--submitted').length).toBe(SUMMARY_WITH_DATA.trend.length);
    });

    it('refetches on Refresh', async () => {
        getSummary.mockResolvedValue(SUMMARY_WITH_DATA);
        getOfferingBreakdown.mockResolvedValue(ROWS);

        const element = createElement('c-gtm-analytics', { is: GtmAnalytics });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('lightning-button-icon').click();
        await flushPromises();

        expect(getSummary).toHaveBeenCalledTimes(2);
        expect(getOfferingBreakdown).toHaveBeenCalledTimes(2);
    });

    // Issue #177: the cross-rep leaderboard is a view toggle, not a second
    // tab -- and it must be entirely hidden from a user without team access,
    // not just fail silently if clicked.
    it('hides the Team toggle for a user without team access', async () => {
        getSummary.mockResolvedValue(SUMMARY_WITH_DATA);
        getOfferingBreakdown.mockResolvedValue(ROWS);
        hasTeamAccess.mockResolvedValue(false);

        const element = createElement('c-gtm-analytics', { is: GtmAnalytics });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.view-toggle')).toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-analytics-team')).toBeNull();
    });

    it('shows the Team toggle and switches views for a user with team access', async () => {
        getSummary.mockResolvedValue(SUMMARY_WITH_DATA);
        getOfferingBreakdown.mockResolvedValue(ROWS);
        hasTeamAccess.mockResolvedValue(true);

        const element = createElement('c-gtm-analytics', { is: GtmAnalytics });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.view-toggle')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-analytics-team')).toBeNull();
        expect(element.shadowRoot.querySelector('.kpi-row')).not.toBeNull();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const teamButton = Array.from(buttons).find((b) => b.dataset.mode === 'team');
        teamButton.click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-analytics-team')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.kpi-row')).toBeNull();
    });
});
