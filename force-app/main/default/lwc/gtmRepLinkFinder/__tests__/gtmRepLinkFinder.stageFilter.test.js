import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import GtmRepLinkFinder from 'c/gtmRepLinkFinder';
import getContactsWithLinks from '@salesforce/apex/GtmRepLinkFinderController.getContactsWithLinks';
import getMyConfigurations from '@salesforce/apex/GtmSavedConfigurationController.getMyConfigurations';
import getStageCountsAura from '@salesforce/apex/GtmLinkStageService.getStageCountsAura';
import getLinkIdsForStageAura from '@salesforce/apex/GtmLinkStageService.getLinkIdsForStageAura';
import getLinkStatsAura from '@salesforce/apex/GtmLinkStageService.getLinkStatsAura';

// Same pattern as gtmAnalyticsTeam.test.js: the stock Navigate is on a sealed
// prototype, so replace the mixin; keep the real CurrentPageReference stub.
const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const actual = jest.requireActual('lightning/navigation');
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](...args) {
                mockNavigate(...args);
            }
        };
    NavigationMixin.Navigate = Navigate;
    return { ...actual, NavigationMixin };
});

jest.mock('@salesforce/apex/GtmRepLinkFinderController.getContactsWithLinks', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSavedConfigurationController.getMyConfigurations', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSavedConfigurationController.setActive', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSavedConfigurationController.regeneratePassword', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSavedConfigurationController.getPassword', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmReadoutController.generateReadoutForRequest', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmAssessmentRequestController.getOfferingHasConduit', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmAccountContactSearchController.searchAccountsAndContacts', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmLinkStageService.getStageCountsAura', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmLinkStageService.getLinkIdsForStageAura', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmLinkStageService.getLinkStatsAura', () => ({ default: jest.fn() }), { virtual: true });
jest.mock(
    '@salesforce/apex/GtmViewerContext.isRep',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const LINKS = [
    { Id: 'a0X000000000001AAA', Company__c: 'Acme', Account__c: '001000000000001AAA', Contact__c: '003000000000001AAA', Offering__c: 'migration-accelerator', Active__c: true },
    { Id: 'a0X000000000002AAA', Company__c: 'Beta', Account__c: '001000000000002AAA', Contact__c: '003000000000002AAA', Offering__c: 'migration-accelerator', Active__c: true },
    { Id: 'a0X000000000003AAA', Company__c: 'Gamma', Account__c: '001000000000001AAA', Contact__c: '003000000000003AAA', Offering__c: 'migration-accelerator', Active__c: true }
];
const COUNTS = { sent: 3, engaged: 2, started: 1, submitted: 0, quiet: 1, hot: 2, notOpened: 1, truncated: false };

function mount() {
    const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
    document.body.appendChild(element);
    return element;
}
const bar = (el) => el.shadowRoot.querySelector('c-gtm-filter-bar');
const table = (el) => el.shadowRoot.querySelector('c-gtm-link-datatable');
// Row ids in the order the table renders them (default sort: last visit desc).
const tiles = (el) => (table(el) ? table(el).data.map((r) => r.recordId) : []);

beforeEach(() => {
    getMyConfigurations.mockResolvedValue(LINKS);
    getStageCountsAura.mockResolvedValue(COUNTS);
    getLinkStatsAura.mockResolvedValue({ viewAll: false, truncated: false, stats: [] });
    getLinkIdsForStageAura.mockResolvedValue(['a0X000000000001AAA', 'a0X000000000003AAA']);
    getContactsWithLinks.mockResolvedValue([]);
});
afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    window.history.pushState({}, '', '/');
    jest.clearAllMocks();
});

describe('gtmRepLinkFinder stage filter', () => {
    it('with no c__stage: no Apex id call, all rows, chips carry live counts, result count is the full row count', async () => {
        const el = mount();
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: { apiName: 'GTM_Pages' }, state: {} });
        await flush();
        expect(getLinkIdsForStageAura).not.toHaveBeenCalled();
        expect(tiles(el)).toHaveLength(3);
        const cfg = bar(el).filters[0];
        expect(cfg.param).toBe('c__stage');
        expect(cfg.options.map((o) => o.value)).toEqual(
            ['sent', 'engaged', 'started', 'submitted', 'quiet', 'hot', 'not_opened']);
        expect(cfg.options.find((o) => o.value === 'quiet').count).toBe(1);
        expect(cfg.options.find((o) => o.value === 'not_opened').count).toBe(1);
        expect(bar(el).values).toEqual({});
        expect(bar(el).resultCount).toBe(3);
        expect(bar(el).resultLabel).toBe('links');
    });

    it('counts failing: chips render without badges and the table still works', async () => {
        getStageCountsAura.mockRejectedValue({ body: { message: 'boom' } });
        const el = mount();
        CurrentPageReference.emit({ state: {} });
        await flush();
        expect(bar(el).filters[0].options.every((o) => o.count === undefined)).toBe(true);
        expect(tiles(el)).toHaveLength(3);
    });

    it('restores c__stage from the URL: filters rows by the id set, marks the chip active, count equals rows', async () => {
        const el = mount();
        CurrentPageReference.emit({ state: { c__stage: 'quiet' } });
        await flush();
        expect(getLinkIdsForStageAura).toHaveBeenCalledWith({ stageKey: 'quiet' });
        expect(tiles(el)).toEqual(['a0X000000000001AAA', 'a0X000000000003AAA']);
        expect(bar(el).values).toEqual({ stage: 'quiet' });
        expect(bar(el).resultCount).toBe(2);
        expect(bar(el).resultLabel).toContain('Went quiet');
    });

    it('ignores an unknown c__stage (no filter, no Apex id call)', async () => {
        const el = mount();
        CurrentPageReference.emit({ state: { c__stage: 'bogus' } });
        await flush();
        expect(getLinkIdsForStageAura).not.toHaveBeenCalled();
        expect(tiles(el)).toHaveLength(3);
        expect(bar(el).values).toEqual({});
    });

    it('a re-fired identical page reference does not refetch', async () => {
        mount();
        CurrentPageReference.emit({ state: { c__stage: 'hot' } });
        await flush();
        CurrentPageReference.emit({ state: { c__stage: 'hot' } });
        await flush();
        expect(getLinkIdsForStageAura).toHaveBeenCalledTimes(1);
    });

    it('a chip change filters immediately and navigates (replace) with c__stage, preserving other c__ params', async () => {
        const el = mount();
        const ref = { type: 'standard__navItemPage', attributes: { apiName: 'GTM_Pages' }, state: { c__other: 'keep' } };
        CurrentPageReference.emit(ref);
        await flush();
        bar(el).dispatchEvent(new CustomEvent('filterchange', { detail: { key: 'stage', value: 'hot' } }));
        await flush();
        expect(getLinkIdsForStageAura).toHaveBeenCalledWith({ stageKey: 'hot' });
        expect(tiles(el)).toHaveLength(2);
        expect(mockNavigate).toHaveBeenCalledTimes(1);
        const [pageRef, replace] = mockNavigate.mock.calls[0];
        expect(replace).toBe(true);
        expect(pageRef.attributes.apiName).toBe('GTM_Pages');
        expect(pageRef.state).toEqual({ c__other: 'keep', c__stage: 'hot' });
    });

    it('clear (event or empty chip value) removes the filter, the param, and restores the full table', async () => {
        const el = mount();
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: { apiName: 'GTM_Pages' }, state: { c__stage: 'quiet' } });
        await flush();
        expect(tiles(el)).toHaveLength(2);
        bar(el).dispatchEvent(new CustomEvent('clear'));
        await flush();
        expect(tiles(el)).toHaveLength(3);
        expect(mockNavigate.mock.calls[0][0].state).toEqual({});
        expect(bar(el).values).toEqual({});
    });

    it('empty result shows a stage-specific empty state with a working Clear filter', async () => {
        getLinkIdsForStageAura.mockResolvedValue([]);
        const el = mount();
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__stage: 'submitted' } });
        await flush();
        expect(tiles(el)).toHaveLength(0);
        const empty = el.shadowRoot.querySelector('.rlf-empty');
        expect(empty.textContent).toContain('No links have reached "Assessment submitted" yet.');
        expect(empty.textContent).not.toContain('No saved links yet');
        empty.querySelector('button').click();
        await flush();
        expect(tiles(el)).toHaveLength(3);
    });

    it('Apex failure shows the error and the UNFILTERED list, never an empty table', async () => {
        getLinkIdsForStageAura.mockRejectedValue({ body: { message: 'Stage service down' } });
        const el = mount();
        CurrentPageReference.emit({ state: { c__stage: 'quiet' } });
        await flush();
        expect(tiles(el)).toHaveLength(3);
        expect(el.shadowRoot.textContent).toContain('Stage service down');
        expect(bar(el).resultCount).toBe(3);
    });

    it('a stage deep link shows the filtered table (there is no mode to force)', async () => {
        const el = mount();
        CurrentPageReference.emit({ state: { c__rlfMode: 'account' } });
        await flush();
        CurrentPageReference.emit({ state: { c__stage: 'quiet' } });
        await flush();
        expect(el.shadowRoot.querySelector('.rlf-mode-toggle')).toBeNull();
        expect(tiles(el)).toHaveLength(2);
    });

    it('c__stage + Account filter intersect: only rows in the stage set AND the account remain', async () => {
        getLinkIdsForStageAura.mockResolvedValue(['a0X000000000001AAA', 'a0X000000000002AAA']);
        const el = mount();
        CurrentPageReference.emit({ state: { c__stage: 'quiet', c__rlfAccountId: '001000000000001AAA' } });
        await flush();
        await flush();
        expect(tiles(el)).toHaveLength(1);
        expect(bar(el).resultCount).toBe(1);
        expect(bar(el).values).toEqual({ stage: 'quiet', account: ['001000000000001AAA'] });
    });

    it('c__stage survives writeDrillStateToUrl (an Open row action does not strip it)', async () => {
        getContactsWithLinks.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane', links: [{ recordId: 'a0X000000000001AAA', company: 'Acme' }] }
        ]);
        const el = mount();
        CurrentPageReference.emit({ state: { c__stage: 'quiet' } });
        await flush();
        table(el).dispatchEvent(new CustomEvent('rowaction', {
            detail: { action: { name: 'open' }, row: { recordId: 'a0X000000000001AAA' } }
        }));
        await flush();
        expect(new URL(window.location.href).searchParams.get('c__stage')).toBe('quiet');
    });
});
