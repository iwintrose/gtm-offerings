import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import GtmReadoutsOverview from 'c/gtmReadoutsOverview';
import getAssessmentPage from '@salesforce/apex/GtmAssessmentListController.getAssessmentPage';
import getAssessmentFilterOptions from '@salesforce/apex/GtmAssessmentListController.getAssessmentFilterOptions';

jest.mock('lightning/navigation', () => {
    const { createTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    const Navigate = Symbol('Navigate');
    const GenerateUrl = Symbol('GenerateUrl');
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate]() {}
            [GenerateUrl]() {
                return Promise.resolve('https://www.example.com');
            }
        };
    NavigationMixin.Navigate = Navigate;
    NavigationMixin.GenerateUrl = GenerateUrl;
    return { CurrentPageReference: createTestWireAdapter(jest.fn()), NavigationMixin };
});
jest.mock('@salesforce/apex/GtmAssessmentListController.getAssessmentPage', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmAssessmentListController.getAssessmentFilterOptions', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSavedConfigurationController.generateRepDirectShareLink', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((r) => setTimeout(r, 0));

beforeEach(() => {
    getAssessmentFilterOptions.mockResolvedValue([]);
    getAssessmentPage.mockResolvedValue({ rows: [], totalCount: 0, totalIsCapped: false, offeringOptions: ['migration-accelerator'] });
});
afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
});

function mount() {
    const el = createElement('c-gtm-readouts-overview', { is: GtmReadoutsOverview });
    document.body.appendChild(el);
    return el;
}

describe('gtmReadoutsOverview toolbar (Addendum C.9.4, release 3)', () => {
    it('the filter bar is the only toolbar: no scope pills row; Account and Contact are addable More filters', async () => {
        const el = mount();
        CurrentPageReference.emit({ state: {} });
        await flush();
        expect(el.shadowRoot.querySelector('.ov-toolbar')).toBeNull();
        expect(el.shadowRoot.querySelector('.ov-mode-toggle')).toBeNull();
        const bar = el.shadowRoot.querySelector('c-gtm-filter-bar.ov-toolbar-bar');
        expect(bar).not.toBeNull();
        expect(bar.storageKey).toBe('assessments');
        expect(bar.filters.filter((f) => f.more).map((f) => f.key)).toEqual(['preset', 'readout', 'offering', 'account', 'contact']);
        expect(bar.filters.map((f) => f.key)).toEqual(['preset', 'status', 'tier', 'readout', 'range', 'offering', 'account', 'contact']);
    });

    it('legacy account mode still shows the bar and the table area', async () => {
        const el = mount();
        CurrentPageReference.emit({ state: { c__browseMode: 'account' } });
        await flush();
        expect(el.shadowRoot.querySelector('c-gtm-filter-bar')).not.toBeNull();
    });
});

describe('gtmReadoutsOverview stale page-reference echo (filter-data tie audit, race R-A)', () => {
    const bar = (el) => el.shadowRoot.querySelector('c-gtm-filter-bar');
    const pick = (el, key, value) => bar(el).dispatchEvent(new CustomEvent('filterchange', { detail: { key, value } }));
    const statusArgs = () => getAssessmentPage.mock.calls.map((c) => c[0].query.status || []);

    it('a page-reference echo that is OLDER than the pick does not reset the filter or refetch', async () => {
        const el = mount();
        CurrentPageReference.emit({ state: {} });
        await flush();
        const before = getAssessmentPage.mock.calls.length;
        pick(el, 'status', ['new']);
        await flush();
        expect(getAssessmentPage.mock.calls.length).toBe(before + 1);
        // The wire delivers the reference from BEFORE our navigation landed.
        CurrentPageReference.emit({ state: {} });
        await flush();
        expect(bar(el).values).toEqual({ status: ['new'] });
        expect(getAssessmentPage.mock.calls.length).toBe(before + 1);
        // The matching echo arrives afterwards: still nothing to do.
        CurrentPageReference.emit({ state: { c__astatus: 'new' } });
        await flush();
        expect(bar(el).values).toEqual({ status: ['new'] });
        expect(getAssessmentPage.mock.calls.length).toBe(before + 1);
        expect(statusArgs()[before]).toEqual(['new']);
    });

    it('two quick picks: the first pick\'s echo cannot drop the second pick', async () => {
        const el = mount();
        CurrentPageReference.emit({ state: {} });
        await flush();
        pick(el, 'status', ['new']);
        pick(el, 'status', ['new', 'contacted']);
        await flush();
        CurrentPageReference.emit({ state: { c__astatus: 'new' } }); // echo of pick 1
        await flush();
        expect(bar(el).values).toEqual({ status: ['new', 'contacted'] });
        CurrentPageReference.emit({ state: { c__astatus: 'new,contacted' } }); // echo of pick 2
        await flush();
        expect(bar(el).values).toEqual({ status: ['new', 'contacted'] });
    });

    it('a genuine external change after the echo is still applied', async () => {
        const el = mount();
        CurrentPageReference.emit({ state: {} });
        await flush();
        pick(el, 'status', ['new']);
        await flush();
        CurrentPageReference.emit({ state: { c__astatus: 'new' } });
        await flush();
        CurrentPageReference.emit({ state: { c__astatus: 'completed' } }); // e.g. browser back
        await flush();
        expect(bar(el).values).toEqual({ status: ['completed'] });
    });
});

describe('gtmReadoutsOverview filtered response must win (real gtmFilterUrlState + buildFilterConfig)', () => {
    const bar = (el) => el.shadowRoot.querySelector('c-gtm-filter-bar');
    const table = (el) => el.shadowRoot.querySelector('c-gtm-link-datatable');
    const R = (id, status) => ({ recordId: id, name: id, requestStatus: status, offeringKey: 'migration-accelerator', createdDate: '2026-01-01T00:00:00.000Z' });
    const ALL = [R('a0X000000000001AAA', 'Completed'), R('a0X000000000002AAA', 'New'), R('a0X000000000003AAA', 'Scheduled')];
    // A server that filters like the real one: status keys map to labels.
    const serve = ({ query }) => {
        const wanted = (query.status || []).map((k) => ({ completed: 'Completed', new: 'New' }[k]));
        const rows = wanted.length ? ALL.filter((r) => wanted.includes(r.requestStatus)) : ALL;
        return Promise.resolve({ rows, totalCount: rows.length, totalIsCapped: false, offeringOptions: ['migration-accelerator'] });
    };
    const queries = () => getAssessmentPage.mock.calls.map((c) => c[0].query);

    beforeEach(() => {
        getAssessmentPage.mockImplementation(serve);
        window.history.pushState({}, '', '/');
    });
    afterEach(() => window.history.pushState({}, '', '/'));

    it('cold deep link, first wire emission carries the params: one filtered load, filtered rows', async () => {
        window.history.pushState({}, '', '/?c__astatus=completed');
        const el = mount();
        CurrentPageReference.emit({ state: { c__astatus: 'completed' } });
        await flush();
        expect(queries().every((q) => (q.status || []).join() === 'completed')).toBe(true);
        expect(table(el).data.length).toBe(1);
        expect(bar(el).values).toEqual({ status: ['completed'] });
        expect(bar(el).resultCount).toBe(1);
    });

    it('cold deep link, first wire emission does NOT yet carry the params: never an unfiltered load, filtered rows', async () => {
        window.history.pushState({}, '', '/?c__astatus=completed');
        const el = mount();
        CurrentPageReference.emit({ state: {} });
        await flush();
        expect(queries().every((q) => (q.status || []).join() === 'completed')).toBe(true);
        expect(table(el).data.length).toBe(1);
        expect(bar(el).values).toEqual({ status: ['completed'] });
        CurrentPageReference.emit({ state: { c__astatus: 'completed' } });
        await flush();
        expect(table(el).data.length).toBe(1);
        expect(queries().every((q) => (q.status || []).join() === 'completed')).toBe(true);
    });

    it('a pick, an OLD echo, then the NEW echo: rows equal the filtered response and no unfiltered call follows it', async () => {
        const el = mount();
        CurrentPageReference.emit({ state: {} });
        await flush();
        expect(table(el).data.length).toBe(3);
        bar(el).dispatchEvent(new CustomEvent('filterchange', { detail: { key: 'status', value: ['new'] } }));
        await flush();
        CurrentPageReference.emit({ state: {} }); // OLD state right after the pick
        await flush();
        CurrentPageReference.emit({ state: { c__astatus: 'new' } }); // NEW state
        await flush();
        const qs = queries();
        const firstFiltered = qs.findIndex((q) => (q.status || []).length);
        expect(firstFiltered).toBeGreaterThan(-1);
        expect(qs.slice(firstFiltered).every((q) => (q.status || []).join() === 'new')).toBe(true);
        expect(table(el).data.map((r) => r.requestStatus)).toEqual(['New']);
        expect(bar(el).resultCount).toBe(1);
    });

    it('every filter kind reaches the query (status, tier, readout, offering, range, preset)', async () => {
        const el = mount();
        CurrentPageReference.emit({ state: {} });
        await flush();
        const pick = (key, value) => bar(el).dispatchEvent(new CustomEvent('filterchange', { detail: { key, value } }));
        pick('status', ['new']);
        pick('tier', ['fast-track']);
        pick('readout', ['published']);
        pick('offering', ['migration-accelerator']);
        pick('range', '30');
        pick('preset', true);
        await flush();
        const q = queries()[queries().length - 1];
        expect(q.status).toEqual(['new']);
        expect(q.tier).toEqual(['fast-track']);
        expect(q.readout).toEqual(['published']);
        expect(q.offering).toEqual(['migration-accelerator']);
        expect(q.range).toBe('30');
        expect(q.preset).toBe('ready-to-book');
    });
});
