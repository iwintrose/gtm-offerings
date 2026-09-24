import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import GtmReadoutsOverview from 'c/gtmReadoutsOverview';
import getAssessmentPage from '@salesforce/apex/GtmAssessmentListController.getAssessmentPage';
import getAssessmentFilterOptions from '@salesforce/apex/GtmAssessmentListController.getAssessmentFilterOptions';

jest.mock('lightning/navigation', () => {
    const { createTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) => class extends Base { [Navigate]() {} };
    NavigationMixin.Navigate = Navigate;
    return { CurrentPageReference: createTestWireAdapter(jest.fn()), NavigationMixin };
});
jest.mock('@salesforce/apex/GtmAssessmentListController.getAssessmentPage', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmAssessmentListController.getAssessmentFilterOptions', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSavedConfigurationController.generateRepDirectShareLink', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const bar = (el) => el.shadowRoot.querySelector('c-gtm-filter-bar');
const ROW = {
    recordId: 'a0X000000000001AAA', name: 'AR-1', contactId: '003000000000001AAA', contactName: 'J',
    accountId: '001000000000001AAA', company: 'Acme', requesterName: 'J', offeringKey: 'k', tier: 'Fast-Track',
    tierRank: 4, score: 1, requestStatus: 'New', readoutId: '', readoutStatus: 'Draft',
    submittedAt: '2026-01-01T00:00:00.000Z', createdDate: '2026-01-01T00:00:00.000Z'
};
const page = (rows) => ({ rows, totalCount: rows.length, totalIsCapped: false, offeringOptions: ['k'] });
const lastQuery = () => getAssessmentPage.mock.calls[getAssessmentPage.mock.calls.length - 1][0].query;
const change = (el, key, value) => bar(el).dispatchEvent(new CustomEvent('filterchange', { detail: { key, value } }));
const STALE = '001000000000999AAA';

describe('gtmReadoutsOverview recovery (filters never wedge)', () => {
    beforeEach(() => {
        getAssessmentFilterOptions.mockResolvedValue([]);
        window.history.replaceState({}, '', '/');
    });
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
        window.history.replaceState({}, '', '/');
    });

    it('10 rapid filter changes then Clear filters requests the unfiltered list and shows rows', async () => {
        getAssessmentPage.mockImplementation(({ query }) =>
            Promise.resolve(page(query.status.length ? [] : [ROW])));
        const el = createElement('c-gtm-readouts-overview', { is: GtmReadoutsOverview });
        document.body.appendChild(el);
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: {} });
        await flush();
        for (let i = 0; i < 10; i++) change(el, 'status', i % 2 ? ['new'] : ['completed']);
        bar(el).dispatchEvent(new CustomEvent('clear'));
        await flush();
        expect(lastQuery().status).toEqual([]);
        expect(lastQuery().accountIds).toEqual([]);
        expect(el.shadowRoot.querySelector('c-gtm-link-datatable').data).toHaveLength(1);
        expect(el.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });

    it('a stale account id in the URL is dropped and the page loads unfiltered', async () => {
        window.history.replaceState({}, '', `/?c__aacct=${STALE}&c__rafContactId=003000000000999AAA`);
        getAssessmentPage.mockImplementation(({ query }) =>
            Promise.resolve(page(query.accountIds.length || query.contactIds.length ? [] : [ROW])));
        const el = createElement('c-gtm-readouts-overview', { is: GtmReadoutsOverview });
        document.body.appendChild(el);
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__aacct: STALE } });
        await flush();
        await flush();
        expect(bar(el).values).toEqual({});
        expect(lastQuery().accountIds).toEqual([]);
        expect(lastQuery().contactIds).toEqual([]);
        expect(el.shadowRoot.querySelector('c-gtm-link-datatable').data).toHaveLength(1);
    });

    it('an Apex rejection keeps prior rows with Retry, and Clear filters recovers', async () => {
        getAssessmentPage.mockResolvedValueOnce(page([ROW]));
        const el = createElement('c-gtm-readouts-overview', { is: GtmReadoutsOverview });
        document.body.appendChild(el);
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: {} });
        await flush();
        getAssessmentPage.mockRejectedValueOnce({ body: { message: 'boom' } });
        change(el, 'status', ['new']);
        await flush();
        expect(el.shadowRoot.querySelector('.ov-err').textContent).toContain('boom');
        expect(el.shadowRoot.querySelector('.ov-retry')).not.toBeNull();
        expect(el.shadowRoot.querySelector('c-gtm-link-datatable').data).toHaveLength(1);
        getAssessmentPage.mockResolvedValue(page([ROW, { ...ROW, recordId: 'a0X000000000002AAA' }]));
        bar(el).dispatchEvent(new CustomEvent('clear'));
        await flush();
        expect(el.shadowRoot.querySelector('.ov-err')).toBeNull();
        expect(lastQuery().status).toEqual([]);
        expect(el.shadowRoot.querySelector('c-gtm-link-datatable').data).toHaveLength(2);
    });

    it('a synchronous Apex throw is treated as an error and does not stick the loading flag', async () => {
        getAssessmentPage.mockImplementationOnce(() => { throw new Error('sync'); });
        const el = createElement('c-gtm-readouts-overview', { is: GtmReadoutsOverview });
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.querySelector('.ov-err').textContent).toContain('sync');
        expect(el.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });
});
