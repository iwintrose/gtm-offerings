/**
 * ISSUE #overview-bd-heat-redesign-4-integration
 *
 * Wires the three already-built, self-loading components (c-gtm-heat-grid,
 * c-gtm-tasks-due-today-widget, c-gtm-readouts-awaiting-widget) into the
 * Today view's render order: heat grid hero -> Act Today tiles -> daily
 * widgets row -> follow-up table -> assessment results. None of the three
 * take @api props or emit events, so this only asserts DOM position, not
 * data plumbing (each component's own suite covers that).
 */
const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const GenerateUrl = Symbol('GenerateUrl');
    const NavigationMixin = (Base) => {
        return class extends Base {
            [Navigate](...args) {
                mockNavigate(...args);
            }
            [GenerateUrl]() {
                return Promise.resolve('https://www.example.com');
            }
        };
    };
    NavigationMixin.Navigate = Navigate;
    NavigationMixin.GenerateUrl = GenerateUrl;
    return { NavigationMixin };
});

// eslint-disable-next-line import/first, import/order
import { createElement } from 'lwc';
// eslint-disable-next-line import/first
import GtmOverview from 'c/gtmOverview';
import getHomeSummary from '@salesforce/apex/GtmPageContentController.getHomeSummary';
import getSnapshot from '@salesforce/apex/GtmHomeSnapshotController.getSnapshot';
import getDeals from '@salesforce/apex/GtmHomeSnapshotController.getDeals';
import getStageCountsAura from '@salesforce/apex/GtmLinkStageService.getStageCountsAura';
import getActToday from '@salesforce/apex/GtmActTodayController.getActToday';
import getHeatGridAura from '@salesforce/apex/GtmLinkStageService.getHeatGridAura';
import getTasksDueToday from '@salesforce/apex/GtmTasksDueTodayController.getTasksDueToday';
import getReadoutsAwaiting from '@salesforce/apex/GtmReadoutsAwaitingController.getReadoutsAwaiting';

jest.mock('@salesforce/apex/GtmPageContentController.getHomeSummary', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmHomeSnapshotController.getSnapshot', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmHomeSnapshotController.getDeals', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmLinkStageService.getStageCountsAura', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmActTodayController.getActToday', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmFeedbackController.getFeedbackFor', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmFeedbackController.submitFeedback', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmLinkStageService.getHeatGridAura', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmHeatGridActionsController.createFollowUpTask', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmTasksDueTodayController.getTasksDueToday', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmReadoutsAwaitingController.getReadoutsAwaiting', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const COUNTS = { sent: 30, engaged: 20, started: 10, submitted: 5, quiet: 4, hot: 2, notOpened: 3, truncated: false };
const ACT = {
    newRequests: { count: 1, capped: false, names: ['Acme'] },
    readoutWaiting: { count: 1, capped: false, names: ['Beta'] },
    cameBackNames: ['Gamma'],
    wentQuietNames: ['Delta']
};

function mount() {
    getHomeSummary.mockResolvedValue({ offerings: [], activity: [], pageTitles: {} });
    getSnapshot.mockResolvedValue(null);
    getDeals.mockResolvedValue([]);
    getStageCountsAura.mockResolvedValue(COUNTS);
    getActToday.mockResolvedValue(ACT);
    getHeatGridAura.mockResolvedValue([]);
    getTasksDueToday.mockResolvedValue([]);
    getReadoutsAwaiting.mockResolvedValue([]);
    const element = createElement('c-gtm-overview', { is: GtmOverview });
    document.body.appendChild(element);
    return element;
}

const root = (el) => el.shadowRoot || el;
const q = (el, sel) => root(el).querySelector(sel);

// FOLLOWING means `b` comes after `a` in document order.
const isBefore = (a, b) => Boolean(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING);

describe('c-gtm-overview: daily widgets integration (ISSUE #overview-bd-heat-redesign-4-integration)', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('renders the heat grid, Act Today, daily widgets, follow-up table and assessment results in order', async () => {
        const element = mount();
        await flushPromises();

        const heatGrid = q(element, 'c-gtm-heat-grid');
        const atRow = q(element, '.at-row');
        const dailyWidgets = q(element, '.ov-daily-widgets');
        const tasksWidget = q(element, 'c-gtm-tasks-due-today-widget');
        const readoutsWidget = q(element, 'c-gtm-readouts-awaiting-widget');
        const row2 = q(element, '.ov-row2');
        const row3 = q(element, '.ov-row3');

        expect(heatGrid).not.toBeNull();
        expect(atRow).not.toBeNull();
        expect(dailyWidgets).not.toBeNull();
        expect(tasksWidget).not.toBeNull();
        expect(readoutsWidget).not.toBeNull();
        expect(row2).not.toBeNull();
        expect(row3).not.toBeNull();

        // Hero heat grid sits above Act Today.
        expect(isBefore(heatGrid, atRow)).toBe(true);
        // Act Today sits above the daily widgets row.
        expect(isBefore(atRow, dailyWidgets)).toBe(true);
        // Both widgets render inside the daily-widgets row, side by side.
        expect(dailyWidgets.contains(tasksWidget)).toBe(true);
        expect(dailyWidgets.contains(readoutsWidget)).toBe(true);
        // Daily widgets row sits above the follow-up table, which sits above
        // assessment results -- unchanged relative order, just pushed down.
        expect(isBefore(dailyWidgets, row2)).toBe(true);
        expect(isBefore(row2, row3)).toBe(true);
    });

    it('mounts the three new components as bare tags with no props/data attributes set', async () => {
        const element = mount();
        await flushPromises();

        const heatGrid = q(element, 'c-gtm-heat-grid');
        const tasksWidget = q(element, 'c-gtm-tasks-due-today-widget');
        const readoutsWidget = q(element, 'c-gtm-readouts-awaiting-widget');

        // Bare-tag mount: no data-* attributes or custom props were wired in.
        // (lwc-* scoping tokens on the host are the synthetic-shadow engine's
        // own bookkeeping, not something this integration set.)
        [heatGrid, tasksWidget, readoutsWidget].forEach((cmp) => {
            const names = [...cmp.attributes].map((a) => a.name);
            expect(names.some((n) => n.startsWith('data-'))).toBe(false);
        });
    });
});
