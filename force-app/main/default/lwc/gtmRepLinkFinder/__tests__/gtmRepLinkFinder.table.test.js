import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import GtmRepLinkFinder from 'c/gtmRepLinkFinder';
import getContactsWithLinks from '@salesforce/apex/GtmRepLinkFinderController.getContactsWithLinks';
import getMyConfigurations from '@salesforce/apex/GtmSavedConfigurationController.getMyConfigurations';
import getStageCountsAura from '@salesforce/apex/GtmLinkStageService.getStageCountsAura';
import getLinkIdsForStageAura from '@salesforce/apex/GtmLinkStageService.getLinkIdsForStageAura';
import getLinkStatsAura from '@salesforce/apex/GtmLinkStageService.getLinkStatsAura';

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

const mk = (n, over) => ({
    Id: `a0X00000000000${n}AAA`, Company__c: `Co${n}`, Account__c: `00100000000000${n}AAA`,
    Contact__c: `00300000000000${n}AAA`, Contact__r: { Name: `Contact ${n}` },
    Offering__c: 'migration-accelerator', Active__c: true, OwnerId: '005USERSTUB',
    Owner: { Name: 'Me' }, CreatedDate: `2026-01-0${n}T00:00:00.000Z`, ...over
});
const LINKS = [mk(1), mk(2), mk(3)];
const STATS = {
    viewAll: false, truncated: false,
    stats: [
        { linkId: LINKS[0].Id, visits: 2, lastVisitAt: '2026-05-01T00:00:00.000Z', funnelStage: 'started' },
        { linkId: LINKS[1].Id, visits: 5, lastVisitAt: '2026-06-01T00:00:00.000Z', funnelStage: 'submitted' },
        { linkId: LINKS[2].Id, visits: 0, lastVisitAt: null, funnelStage: 'not_opened' }
    ]
};

const table = (el) => el.shadowRoot.querySelector('c-gtm-link-datatable');
const rowIds = (el) => table(el).data.map((r) => r.recordId);
const bar = (el) => el.shadowRoot.querySelector('c-gtm-filter-bar');
function mount() {
    const el = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
    document.body.appendChild(el);
    return el;
}
const rowAction = (el, name, row) =>
    table(el).dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name }, row } }));

beforeEach(() => {
    getMyConfigurations.mockResolvedValue(LINKS);
    getLinkStatsAura.mockResolvedValue(STATS);
    getStageCountsAura.mockResolvedValue(null);
    getLinkIdsForStageAura.mockResolvedValue([]);
    getContactsWithLinks.mockResolvedValue([
        { contactId: LINKS[1].Contact__c, contactName: 'Contact 2', links: [{ recordId: LINKS[1].Id, company: 'Co2', generatedUrl: 'https://x' }] }
    ]);
});
afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    window.history.pushState({}, '', '/');
    jest.clearAllMocks();
});

describe('gtmRepLinkFinder Pages table', () => {
    it('renders a datatable, no tile markup, with the contract attributes', async () => {
        const el = mount();
        await flush();
        expect(table(el)).not.toBeNull();
        expect(el.shadowRoot.querySelector('.rlf-tile')).toBeNull();
        expect(table(el).keyField).toBe('recordId');
        expect(table(el).hideCheckboxColumn).toBe(true);
        expect(el.shadowRoot.querySelector('.rlf-table-wrap')).not.toBeNull();
    });

    it('default sort is last visit desc, never-visited last; header indicator matches', async () => {
        const el = mount();
        await flush();
        expect(rowIds(el)).toEqual([LINKS[1].Id, LINKS[0].Id, LINKS[2].Id]);
        expect(table(el).sortedBy).toBe('lastVisitAt');
        expect(table(el).sortedDirection).toBe('desc');
    });

    it('onsort reorders and updates sortedBy / sortedDirection', async () => {
        const el = mount();
        await flush();
        table(el).dispatchEvent(new CustomEvent('sort', { detail: { fieldName: 'visits', sortDirection: 'asc' } }));
        await flush();
        expect(rowIds(el)).toEqual([LINKS[2].Id, LINKS[0].Id, LINKS[1].Id]);
        expect(table(el).sortedBy).toBe('visits');
        expect(table(el).sortedDirection).toBe('asc');
    });

    it('sort state is not written to the URL', async () => {
        const el = mount();
        await flush();
        table(el).dispatchEvent(new CustomEvent('sort', { detail: { fieldName: 'company', sortDirection: 'asc' } }));
        await flush();
        expect(window.location.search).toBe('');
    });

    it('Owner column is hidden for a rep and shown for a viewAll user', async () => {
        let el = mount();
        await flush();
        expect(table(el).columns.map((c) => c.fieldName)).not.toContain('ownerName');
        document.body.removeChild(el);

        getLinkStatsAura.mockResolvedValue({ ...STATS, viewAll: true });
        el = mount();
        await flush();
        expect(table(el).columns.map((c) => c.fieldName)).toContain('ownerName');
    });

    it('stats failure: table still renders with blank stats, a notice, and Owner inferred from rows', async () => {
        getLinkStatsAura.mockRejectedValue({ body: { message: 'nope' } });
        getMyConfigurations.mockResolvedValue([mk(1, { OwnerId: '005SOMEONEELSE' })]);
        const el = mount();
        await flush();
        expect(table(el).data).toHaveLength(1);
        expect(table(el).data[0].funnelLabel).toBe('—');
        expect(table(el).data[0].visits).toBeNull();
        expect(el.shadowRoot.textContent).toContain('Visit details could not be loaded');
        expect(table(el).columns.map((c) => c.fieldName)).toContain('ownerName');
    });

    it('result count is the row count always in all mode (label "links"), and follows the stage filter', async () => {
        const el = mount();
        CurrentPageReference.emit({ state: {} });
        await flush();
        expect(bar(el).resultCount).toBe(3);
        expect(bar(el).resultLabel).toBe('links');

        getLinkIdsForStageAura.mockResolvedValue([LINKS[1].Id]);
        CurrentPageReference.emit({ state: { c__stage: 'submitted' } });
        await flush();
        expect(rowIds(el)).toEqual([LINKS[1].Id]);
        expect(bar(el).resultCount).toBe(1);
        expect(bar(el).resultLabel).toContain('Assessment submitted');
    });

    it('column-1 button and the row action both route to the one open handler', async () => {
        const el = mount();
        await flush();
        // Both entry points fire the same datatable rowaction event with action.name 'open'.
        expect(table(el).columns[0].typeAttributes.name).toBe('open');
        rowAction(el, 'open', { recordId: LINKS[1].Id });
        await flush();
        expect(getContactsWithLinks).toHaveBeenCalledWith({ accountId: LINKS[1].Account__c });
        expect(new URL(window.location.href).searchParams.get('c__rlfLinkId')).toBe(LINKS[1].Id);
        expect(table(el)).toBeNull();
    });

    it('a link with no account still opens, by its own id, without the account drill', async () => {
        getMyConfigurations.mockResolvedValue([mk(1, { Account__c: null })]);
        const el = mount();
        await flush();
        const row = table(el).data[0];
        expect(row.openDisabled).toBe(false);
        rowAction(el, 'open', row);
        await flush();
        expect(getContactsWithLinks).not.toHaveBeenCalled();
        expect(table(el)).toBeNull(); // the detail view replaced the table
    });

    it('a link with an account but no contact also opens by its own id', async () => {
        getMyConfigurations.mockResolvedValue([mk(1, { Contact__c: null, Contact__r: null })]);
        const el = mount();
        await flush();
        rowAction(el, 'open', table(el).data[0]);
        await flush();
        expect(getContactsWithLinks).not.toHaveBeenCalled();
        expect(table(el)).toBeNull();
    });

    it('unrelated row actions are ignored', async () => {
        const el = mount();
        await flush();
        rowAction(el, 'other', { recordId: LINKS[1].Id });
        await flush();
        expect(getContactsWithLinks).not.toHaveBeenCalled();
    });

    it('three distinct empty/error states', async () => {
        getMyConfigurations.mockResolvedValue([]);
        let el = mount();
        await flush();
        expect(table(el)).toBeNull();
        expect(el.shadowRoot.textContent).toContain('No saved links yet');
        document.body.removeChild(el);

        getMyConfigurations.mockRejectedValue({ body: { message: 'Load blew up' } });
        el = mount();
        await flush();
        expect(el.shadowRoot.textContent).toContain('Load blew up');
        document.body.removeChild(el);

        getMyConfigurations.mockResolvedValue(LINKS);
        getLinkIdsForStageAura.mockResolvedValue([]);
        el = mount();
        CurrentPageReference.emit({ state: { c__stage: 'submitted' } });
        await flush();
        expect(table(el)).toBeNull();
        expect(el.shadowRoot.textContent).toContain('No links have reached "Assessment submitted" yet.');
        expect(el.shadowRoot.textContent).not.toContain('No saved links yet');
    });
});
