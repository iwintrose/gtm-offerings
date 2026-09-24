import { createElement } from 'lwc';
import { __navigateMock } from 'lightning/navigation';
import GtmRepLinkFinder from 'c/gtmRepLinkFinder';
import getMyConfigurations from '@salesforce/apex/GtmSavedConfigurationController.getMyConfigurations';
import getStageCountsAura from '@salesforce/apex/GtmLinkStageService.getStageCountsAura';
import getLinkIdsForStageAura from '@salesforce/apex/GtmLinkStageService.getLinkIdsForStageAura';
import getContactsWithLinks from '@salesforce/apex/GtmRepLinkFinderController.getContactsWithLinks';
import getLinkStatsAura from '@salesforce/apex/GtmLinkStageService.getLinkStatsAura';
import { buildColumns, buildRows, DEFAULT_VISIBLE_FIELDS } from '../gtmRepLinkTableModel';

jest.mock('lightning/navigation', () => {
    const { createTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    const Navigate = Symbol('Navigate');
    const GenerateUrl = Symbol('GenerateUrl');
    const navigateMock = jest.fn();
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](...args) { navigateMock(...args); }
            [GenerateUrl]() { return Promise.resolve('https://www.example.com'); }
        };
    NavigationMixin.Navigate = Navigate;
    NavigationMixin.GenerateUrl = GenerateUrl;
    return { CurrentPageReference: createTestWireAdapter(jest.fn()), NavigationMixin, __navigateMock: navigateMock };
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
const LINK = {
    Id: 'a0X000000000001AAA', Company__c: 'Acme', Account__c: '001000000000001AAA',
    Contact__c: '003000000000001AAA', Contact__r: { Name: 'Jane' }, Offering__c: 'migration-accelerator',
    Active__c: true, OwnerId: '005USERSTUB', CreatedDate: '2026-01-01T00:00:00.000Z'
};

describe('Pages table Contact link', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('Contact column is the shared gtmLink cell type named openContact', () => {
        const col = buildColumns(false).find((c) => c.label === 'Contact');
        expect(col.type).toBe('gtmLink');
        expect(col.typeAttributes.name).toBe('openContact');
        const [withContact] = buildRows([LINK], []);
        const [without] = buildRows([{ ...LINK, Contact__c: null, Contact__r: null }], []);
        expect(withContact.contactDisabled).toBe(false);
        expect(withContact.contactTitle).toBe('Open contact');
        expect(without.contactDisabled).toBe(true);
    });

    it('navigates to the Contact record page with the contact id; the rest of the row actions are unchanged', async () => {
        getMyConfigurations.mockResolvedValue([LINK]);
        getLinkStatsAura.mockResolvedValue({ viewAll: false, truncated: false, stats: [] });
        getStageCountsAura.mockResolvedValue(null);
        getLinkIdsForStageAura.mockResolvedValue([]);
        getContactsWithLinks.mockResolvedValue([]);
        const el = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(el);
        await flush();
        await flush();
        const t = el.shadowRoot.querySelector('c-gtm-link-datatable');
        t.dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'openContact' }, row: t.data[0] } }));
        expect(__navigateMock).toHaveBeenCalledTimes(1);
        expect(__navigateMock.mock.calls[0][0]).toEqual({
            type: 'standard__recordPage',
            attributes: { recordId: '003000000000001AAA', objectApiName: 'Contact', actionName: 'view' }
        });
        __navigateMock.mockClear();
        t.dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'openContact' }, row: { ...t.data[0], contactId: null } } }));
        expect(__navigateMock).not.toHaveBeenCalled();
    });
});

describe('Pages table SC link and Account link', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('column order: SC number first, then Account, Contact; default set is <= 5', () => {
        const cols = buildColumns(false);
        expect(cols.slice(0, 3).map((c) => c.fieldName)).toEqual(['scNumber', 'company', 'contactName']);
        expect(cols[0].typeAttributes.name).toBe('open');
        expect(cols[0].typeAttributes.label).toEqual({ fieldName: 'scNumber' });
        expect(cols[1].type).toBe('gtmLink');
        expect(cols[1].label).toBe('Account');
        expect(cols[1].typeAttributes.name).toBe('openAccount');
        expect(DEFAULT_VISIBLE_FIELDS.length).toBeLessThanOrEqual(5);
        expect(DEFAULT_VISIBLE_FIELDS).toEqual(['scNumber', 'company', 'contactName', 'funnelLabel', 'lastVisitAt']);
    });

    it('rows carry the SC Name and disable Account when there is no account', () => {
        const [a] = buildRows([{ ...LINK, Name: 'SC-0157' }], []);
        const [b] = buildRows([{ ...LINK, Name: 'SC-0158', Account__c: null }], []);
        expect(a.scNumber).toBe('SC-0157');
        expect(a.accountDisabled).toBe(false);
        expect(b.accountDisabled).toBe(true);
        expect(b.openDisabled).toBe(false);
    });

    it('SC link opens the detail; Account navigates to the Account record; missing id does nothing', async () => {
        getMyConfigurations.mockResolvedValue([{ ...LINK, Name: 'SC-0157' }]);
        getLinkStatsAura.mockResolvedValue({ viewAll: false, truncated: false, stats: [] });
        getStageCountsAura.mockResolvedValue(null);
        getLinkIdsForStageAura.mockResolvedValue([]);
        getContactsWithLinks.mockResolvedValue([]);
        const el = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(el);
        await flush();
        await flush();
        const t = el.shadowRoot.querySelector('c-gtm-link-datatable');
        t.dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'openAccount' }, row: t.data[0] } }));
        expect(__navigateMock.mock.calls[0][0]).toEqual({
            type: 'standard__recordPage',
            attributes: { recordId: '001000000000001AAA', objectApiName: 'Account', actionName: 'view' }
        });
        __navigateMock.mockClear();
        t.dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'openAccount' }, row: { ...t.data[0], accountId: null } } }));
        expect(__navigateMock).not.toHaveBeenCalled();
        t.dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'open' }, row: t.data[0] } }));
        await flush();
        expect(getContactsWithLinks).toHaveBeenCalledWith({ accountId: '001000000000001AAA' });
    });
});
