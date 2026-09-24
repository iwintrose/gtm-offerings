import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import GtmRepLinkFinder from 'c/gtmRepLinkFinder';
import getContactsWithLinks from '@salesforce/apex/GtmRepLinkFinderController.getContactsWithLinks';
import getMyConfigurations from '@salesforce/apex/GtmSavedConfigurationController.getMyConfigurations';
import setActive from '@salesforce/apex/GtmSavedConfigurationController.setActive';
import regeneratePassword from '@salesforce/apex/GtmSavedConfigurationController.regeneratePassword';
import getIndustryProfiles from '@salesforce/apex/GtmPageContentReader.getIndustryProfiles';
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
jest.mock('@salesforce/apex/GtmPageContentReader.getIndustryProfiles', () => ({ default: jest.fn() }), { virtual: true });
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

const A1 = '001000000000001AAA';
const A2 = '001000000000002AAA';
const C1 = '003000000000001AAA';
const C2 = '003000000000002AAA';
const recent = new Date(Date.now() - 2 * 86400000).toISOString();
const old = new Date(Date.now() - 200 * 86400000).toISOString();
const LINKS = [
    { Id: 'a0X000000000001AAA', Company__c: 'Acme Co', Account__c: A1, Account__r: { Name: 'Acme Co' }, Contact__c: C1, Contact__r: { Name: 'Jane' }, Offering__c: 'migration-accelerator', Industry__c: 'Retail', Opportunity__r: { StageName: 'Prospecting' }, Active__c: true, CreatedDate: recent, OwnerId: '005A', Owner: { Name: 'Rep A' } },
    { Id: 'a0X000000000002AAA', Company__c: 'Beta Inc', Account__c: A2, Account__r: { Name: 'Beta Inc' }, Contact__c: C2, Contact__r: { Name: 'Sam' }, Offering__c: 'other-offer', Industry__c: 'Tech', Active__c: false, CreatedDate: old, OwnerId: '005A', Owner: { Name: 'Rep A' } },
    { Id: 'a0X000000000003AAA', Company__c: 'Acme Co', Account__c: A1, Account__r: { Name: 'Acme Co' }, Contact__c: C2, Contact__r: { Name: 'Sam' }, Offering__c: 'migration-accelerator', Industry__c: 'Retail', Active__c: true, CreatedDate: recent, OwnerId: '005A', Owner: { Name: 'Rep A' } }
];
const COUNTS = { sent: 3, engaged: 2, started: 1, submitted: 0, quiet: 1, hot: 2, notOpened: 1, truncated: false };

function mount() {
    const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
    document.body.appendChild(element);
    return element;
}
const bar = (el) => el.shadowRoot.querySelector('c-gtm-filter-bar');
const table = (el) => el.shadowRoot.querySelector('c-gtm-link-datatable');
const ids = (el) => (table(el) ? table(el).data.map((r) => r.recordId).sort() : []);
const emit = (state) => CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: { apiName: 'GTM_Pages' }, state });
const change = (el, key, value) =>
    bar(el).dispatchEvent(new CustomEvent('filterchange', { detail: { key, value } }));

const DEFINED = [{ industryKey: 'Retail', industryLabel: 'Retail' }, { industryKey: 'Tech', industryLabel: 'Tech' }];
beforeEach(() => {
    getIndustryProfiles.mockResolvedValue(DEFINED);
    getMyConfigurations.mockResolvedValue(LINKS);
    getStageCountsAura.mockResolvedValue(COUNTS);
    getLinkStatsAura.mockResolvedValue({ viewAll: false, truncated: false, stats: [] });
    getLinkIdsForStageAura.mockResolvedValue(['a0X000000000001AAA']);
    getContactsWithLinks.mockResolvedValue([]);
});
afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    window.history.pushState({}, '', '/');
    jest.clearAllMocks();
});

describe('gtmRepLinkFinder Pages filter set (Addendum C.3, release 1)', () => {
    it('the bar gets Funnel stage first, then Offering and Sent on the row and the rest under More', async () => {
        const el = mount();
        emit({});
        await flush();
        const cfg = bar(el).filters;
        expect(cfg.map((f) => f.key)).toEqual(['stage', 'offering', 'sent', 'industry', 'deal', 'account', 'contact', 'active', 'last']);
        expect(cfg.filter((f) => !f.more).map((f) => f.key)).toEqual(['stage', 'offering', 'sent']);
        expect(cfg[0].options.map((o) => o.value)).toEqual(['sent', 'engaged', 'started', 'submitted', 'quiet', 'hot', 'not_opened']);
        expect(cfg.map((f) => f.param)).toEqual([
            'c__stage', 'c__poffering', 'c__psent', 'c__pindustry', 'c__pdeal', 'c__pacct', 'c__pcontact', 'c__pactive', 'c__plast'
        ]);
        expect(bar(el).storageKey).toBe('pages');
        expect(bar(el).values).toEqual({});
    });

    it('Last visit appears only with complete stats; Owner only with more than one owner', async () => {
        getMyConfigurations.mockResolvedValue([...LINKS, { ...LINKS[0], Id: 'a0X000000000004AAA', OwnerId: '005B', Owner: { Name: 'Rep B' } }]);
        const el = mount();
        emit({});
        await flush();
        const keys = bar(el).filters.map((f) => f.key);
        expect(keys).toContain('last');
        expect(keys[keys.length - 1]).toBe('owner');
        getLinkStatsAura.mockResolvedValue({ viewAll: true, truncated: true, stats: [] });
        const el2 = mount();
        emit({});
        await flush();
        expect(bar(el2).filters.map((f) => f.key)).not.toContain('last');
    });

    it('a filter change filters the table client-side and navigates (replace) with the c__p param only', async () => {
        const el = mount();
        emit({ c__other: 'keep' });
        await flush();
        change(el, 'offering', ['other-offer']);
        await flush();
        expect(ids(el)).toEqual(['a0X000000000002AAA']);
        const [pageRef, replace] = mockNavigate.mock.calls[mockNavigate.mock.calls.length - 1];
        expect(replace).toBe(true);
        expect(pageRef.state).toEqual({ c__other: 'keep', c__poffering: 'other-offer' });
        expect(bar(el).values).toEqual({ offering: ['other-offer'] });
        expect(bar(el).resultCount).toBe(1);
        expect(getLinkIdsForStageAura).not.toHaveBeenCalled(); // no stage: no Apex
    });

    it('filters compose with AND, and with the stage id set', async () => {
        const el = mount();
        emit({});
        await flush();
        change(el, 'offering', ['migration-accelerator']);
        change(el, 'industry', ['Retail']);
        await flush();
        expect(ids(el)).toEqual(['a0X000000000001AAA', 'a0X000000000003AAA']);
        change(el, 'stage', 'hot'); // id set contains only link 1
        await flush();
        expect(ids(el)).toEqual(['a0X000000000001AAA']);
        const state = mockNavigate.mock.calls[mockNavigate.mock.calls.length - 1][0].state;
        expect(state).toEqual({ c__stage: 'hot', c__poffering: 'migration-accelerator', c__pindustry: 'Retail' });
    });

    it('Account and Contact filter by Id; Sent and Link status work', async () => {
        const el = mount();
        emit({});
        await flush();
        change(el, 'account', [A1]);
        await flush();
        expect(ids(el)).toEqual(['a0X000000000001AAA', 'a0X000000000003AAA']);
        change(el, 'contact', [C2]);
        await flush();
        expect(ids(el)).toEqual(['a0X000000000003AAA']);
        change(el, 'account', []);
        change(el, 'contact', []);
        change(el, 'active', 'inactive');
        await flush();
        expect(ids(el)).toEqual(['a0X000000000002AAA']);
        change(el, 'active', '');
        change(el, 'sent', '30');
        await flush();
        expect(ids(el)).toEqual(['a0X000000000001AAA', 'a0X000000000003AAA']);
    });

    it('deep links restore every param, the bar shows the values, and the URL round-trips', async () => {
        const el = mount();
        emit({ c__poffering: 'other-offer,migration-accelerator', c__pacct: A2, c__pactive: 'inactive', c__psent: '365' });
        await flush();
        expect(bar(el).values).toEqual({ offering: ['migration-accelerator', 'other-offer'], account: [A2], active: 'inactive' });
        expect(ids(el)).toEqual(['a0X000000000002AAA']);
        change(el, 'active', '');
        await flush();
        const state = mockNavigate.mock.calls[mockNavigate.mock.calls.length - 1][0].state;
        expect(state).toEqual({ c__poffering: 'migration-accelerator,other-offer', c__pacct: A2 });
    });

    it('a deep-linked account is shown even before the data loads (kept as an option)', async () => {
        let resolve;
        getMyConfigurations.mockReturnValue(new Promise((r) => { resolve = r; }));
        const el = mount();
        emit({ c__pacct: A2 });
        await flush();
        expect(bar(el).values).toEqual({ account: [A2] });
        resolve(LINKS);
        await flush();
        expect(bar(el).filters.find((f) => f.key === 'account').options.map((o) => o.label)).toEqual(['Acme Co', 'Beta Inc']);
    });

    it('clear removes every filter param and restores the full table', async () => {
        const el = mount();
        emit({ c__poffering: 'other-offer', c__stage: 'hot' });
        await flush();
        bar(el).dispatchEvent(new CustomEvent('clear'));
        await flush();
        expect(ids(el)).toHaveLength(3);
        expect(mockNavigate.mock.calls[mockNavigate.mock.calls.length - 1][0].state).toEqual({});
        expect(bar(el).values).toEqual({});
    });

    it('no rows: "No links match these filters." with a working Clear filter', async () => {
        const el = mount();
        emit({});
        await flush();
        change(el, 'industry', ['Retail']);
        change(el, 'active', 'inactive');
        await flush();
        const empty = el.shadowRoot.querySelector('.rlf-empty');
        expect(empty.textContent).toContain('No links match these filters.');
        empty.querySelector('button.rlf-change').click();
        await flush();
        expect(ids(el)).toHaveLength(3);
    });
});

describe('gtmRepLinkFinder legacy deep-link mapping (Addendum C.9.3, release 2)', () => {
    it('c__rlfAccountId alone maps to the Account filter and the URL is rewritten via Navigate(replace)', async () => {
        const el = mount();
        emit({ c__rlfAccountId: A1, c__rlfMode: 'account' });
        await flush();
        expect(bar(el).values).toEqual({ account: [A1] });
        expect(ids(el)).toEqual(['a0X000000000001AAA', 'a0X000000000003AAA']);
        expect(bar(el).resultCount).toBe(2);
        const [ref, replace] = mockNavigate.mock.calls[mockNavigate.mock.calls.length - 1];
        expect(replace).toBe(true);
        expect(ref.state.c__pacct).toBe(A1);
        expect(ref.state.c__rlfAccountId).toBeUndefined();
        expect(ref.state.c__rlfMode).toBeUndefined();
        expect(getContactsWithLinks).not.toHaveBeenCalled();
    });

    it('c__rlfAccountId plus c__rlfContactId map to both filters (AND)', async () => {
        const el = mount();
        emit({ c__rlfAccountId: A1, c__rlfContactId: C2 });
        await flush();
        expect(bar(el).values).toEqual({ account: [A1], contact: [C2] });
        expect(ids(el)).toEqual(['a0X000000000003AAA']);
    });

    it('ids plus c__rlfLinkId still open the detail view and are NOT mapped to filters', async () => {
        getContactsWithLinks.mockResolvedValue([
            { contactId: C1, contactName: 'Jane', links: [{ recordId: 'a0X000000000001AAA', company: 'Acme Co', generatedUrl: 'https://x/y' }] }
        ]);
        const el = mount();
        emit({ c__rlfAccountId: A1, c__rlfContactId: C1, c__rlfLinkId: 'a0X000000000001AAA' });
        await flush();
        await flush();
        expect(el.shadowRoot.querySelector('.rlf-view')).not.toBeNull();
        expect(bar(el)).toBeNull();
        expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('an unknown (deleted) account id is dropped once links load and the full list shows', async () => {
        const el = mount();
        emit({ c__pacct: '001000000000999AAA' });
        await flush();
        expect(bar(el).values).toEqual({});
        expect(ids(el)).toHaveLength(3);
    });

    it('an explicit c__pacct wins over a legacy c__rlfAccountId', async () => {
        const el = mount();
        emit({ c__rlfAccountId: A1, c__pacct: A2 });
        await flush();
        expect(bar(el).values).toEqual({ account: [A2] });
    });

    it('Account and Contact options come only from accounts/contacts that have links, searchable', async () => {
        const el = mount();
        emit({});
        await flush();
        const acct = bar(el).filters.find((f) => f.key === 'account');
        const contact = bar(el).filters.find((f) => f.key === 'contact');
        expect(acct.options).toEqual([{ value: A1, label: 'Acme Co' }, { value: A2, label: 'Beta Inc' }]);
        expect(contact.options.map((o) => o.value).sort()).toEqual([C1, C2]);
        expect(acct.searchable).toBe(true);
        expect(contact.searchable).toBe(true);
    });
});

describe('gtmRepLinkFinder filter vocabulary ties to the columns (filter-data tie audit)', () => {
    const fs = require('fs');
    const path = require('path');
    const { FUNNEL_LABELS } = require('../gtmRepLinkTableModel');

    it('Funnel stage: values equal the Apex STAGE_KEYS; labels reuse the column wording', async () => {
        const apex = fs.readFileSync(path.join(__dirname, '..', '..', '..', 'classes', 'GtmLinkStageService.cls'), 'utf8');
        const keys = Array.from(apex.match(/STAGE_KEYS\s*=\s*new List<String>\{([^}]*)\}/)[1].matchAll(/'([^']+)'/g), (m) => m[1]);
        const el = mount();
        emit({});
        await flush();
        const opts = bar(el).filters[0].options;
        expect(opts.map((o) => o.value)).toEqual(keys);
        const label = (v) => opts.find((o) => o.value === v).label;
        expect(label('sent')).toBe('All links sent');
        expect(label('engaged')).toBe(`${FUNNEL_LABELS.engaged} or later`);
        expect(label('started')).toBe(`${FUNNEL_LABELS.started} or later`);
        expect(label('submitted')).toBe(FUNNEL_LABELS.submitted);
        expect(label('not_opened')).toBe(FUNNEL_LABELS.not_opened);
        expect(new Set(opts.map((o) => o.label)).size).toBe(7);
    });

    it('quiet and hot carry hints from the real Apex rules; the others carry none', async () => {
        const apex = fs.readFileSync(path.join(__dirname, '..', '..', '..', 'classes', 'GtmLinkStageService.cls'), 'utf8');
        expect(apex).toMatch(/isQuiet\(\) \{ return isStarted\(\) && !isSubmitted\(\)/);
        expect(apex).toMatch(/HOT_WINDOW_HOURS = 48/);
        expect(apex).toMatch(/visits\(\) >= 2/);
        const el = mount();
        emit({});
        await flush();
        const byValue = (v) => bar(el).filters[0].options.find((o) => o.value === v);
        expect(byValue('quiet').hint).toBe('started, not submitted');
        expect(byValue('hot').hint).toBe('2+ visits, last within 48 hours');
        ['sent', 'engaged', 'started', 'submitted', 'not_opened'].forEach((v) => expect(byValue(v).hint).toBeUndefined());
    });

    it('Link status options say Active / Inactive, the same words as the Status column', async () => {
        const el = mount();
        emit({});
        await flush();
        expect(bar(el).filters.find((f) => f.key === 'active').options.map((o) => o.label)).toEqual(['Active', 'Inactive']);
        const { buildRows } = require('../gtmRepLinkTableModel');
        expect(buildRows([{ Id: '1', Active__c: false }], []).map((r) => r.statusLabel)).toEqual(['Inactive']);
        expect(buildRows([{ Id: '1', Active__c: true }], []).map((r) => r.statusLabel)).toEqual(['Active']);
    });

    it('Industry, Deal stage and Account options equal what their columns show', async () => {
        const { buildRows } = require('../gtmRepLinkTableModel');
        const el = mount();
        emit({});
        await flush();
        const rows = buildRows(LINKS, [], DEFINED);
        const cfg = (k) => bar(el).filters.find((f) => f.key === k);
        const colValues = (field) => Array.from(new Set(rows.map((r) => r[field]).filter(Boolean))).sort();
        expect(cfg('industry').options.map((o) => o.label).sort()).toEqual(colValues('industryLabel'));
        expect(cfg('deal').options.map((o) => o.label)).toEqual(['Prospecting']); // one value: the bar hides it (L5)
        expect(colValues('dealStage')).toEqual(['Prospecting']);
        // one option per account (its name); every option label is the text the Account / company column shows
        expect(cfg('account').options.map((o) => o.label).sort()).toEqual(colValues('company'));
        expect(cfg('offering').options.map((o) => o.label).sort()).toEqual(colValues('offeringLabel'));
        expect(table(el).columns.map((c) => c.fieldName)).toEqual(expect.arrayContaining(['industryLabel', 'dealStage']));
    });
});

describe('gtmRepLinkFinder toolbar (Addendum C.9.4)', () => {
    it('the filter bar is the only toolbar: no scope pills, no toggle, no Miller columns', async () => {
        const el = mount();
        emit({});
        await flush();
        expect(el.shadowRoot.querySelector('.rlf-toolbar')).toBeNull();
        expect(el.shadowRoot.querySelector('.rlf-mode-toggle')).toBeNull();
        expect(el.shadowRoot.querySelector('.rlf-columns')).toBeNull();
        expect(el.shadowRoot.querySelector('.rlf-search')).toBeNull();
        expect(el.shadowRoot.querySelector('c-gtm-filter-bar.rlf-toolbar-bar')).not.toBeNull();
    });

    it('the stage error is shown', async () => {
        getLinkIdsForStageAura.mockRejectedValue({ body: { message: 'boom' } });
        const el = mount();
        emit({ c__stage: 'hot' });
        await flush();
        expect(el.shadowRoot.querySelector('.rlf-msg--err').textContent).toContain('boom');
    });
});

describe('gtmRepLinkFinder row actions and Back to links (release 2)', () => {
    const rowAction = (el, name, recordId = 'a0X000000000001AAA') =>
        table(el).dispatchEvent(new CustomEvent('rowaction', {
            detail: { action: { name }, row: table(el).data.find((r) => r.recordId === recordId) }
        }));

    it('Turn off calls setActive with the row id, updates Status and refreshes stats', async () => {
        setActive.mockResolvedValue(undefined);
        const el = mount();
        emit({});
        await flush();
        const before = getLinkStatsAura.mock.calls.length;
        rowAction(el, 'toggle');
        await flush();
        expect(setActive).toHaveBeenCalledWith({ recordId: 'a0X000000000001AAA', active: false });
        expect(table(el).data.find((r) => r.recordId === 'a0X000000000001AAA').statusLabel).toBe('Inactive');
        expect(getLinkStatsAura.mock.calls.length).toBe(before + 1);
        rowAction(el, 'toggle'); // now Turn on
        await flush();
        expect(setActive).toHaveBeenLastCalledWith({ recordId: 'a0X000000000001AAA', active: true });
    });

    it('New password confirms, calls regeneratePassword and shows the password once', async () => {
        regeneratePassword.mockResolvedValue('N3W');
        global.confirm = jest.fn(() => true);
        global.alert = jest.fn();
        const el = mount();
        emit({});
        await flush();
        rowAction(el, 'password');
        await flush();
        expect(regeneratePassword).toHaveBeenCalledWith({ recordId: 'a0X000000000001AAA' });
        expect(global.alert.mock.calls[0][0]).toContain('N3W');
    });

    it('New password does nothing when the rep cancels the confirm', async () => {
        global.confirm = jest.fn(() => false);
        const el = mount();
        emit({});
        await flush();
        rowAction(el, 'password');
        await flush();
        expect(regeneratePassword).not.toHaveBeenCalled();
    });

    it('Open then Back to links returns to the table with the filters intact', async () => {
        getContactsWithLinks.mockResolvedValue([
            { contactId: C1, contactName: 'Jane', links: [{ recordId: 'a0X000000000001AAA', company: 'Acme Co', generatedUrl: 'https://x/y' }] }
        ]);
        const el = mount();
        emit({ c__pindustry: 'Retail' });
        await flush();
        rowAction(el, 'open');
        await flush();
        expect(bar(el)).toBeNull();
        const back = [...el.shadowRoot.querySelectorAll('button.rlf-back')].find((b) => b.textContent.includes('Back to links'));
        back.click();
        await flush();
        expect(bar(el).values).toEqual({ industry: ['Retail'] });
        expect(table(el)).not.toBeNull();
    });
});

describe('gtmRepLinkFinder stale page-reference echo (filter-data tie audit, race R-B)', () => {
    it('an OLDER reference does not clear a just-picked stage or extra filter', async () => {
        const el = mount();
        emit({});
        await flush();
        change(el, 'stage', 'hot');
        change(el, 'offering', ['other-offer']);
        await flush();
        expect(getLinkIdsForStageAura).toHaveBeenCalledTimes(1);
        emit({}); // the wire re-fires with the state from before our navigation landed
        await flush();
        expect(bar(el).values).toEqual({ stage: 'hot', offering: ['other-offer'] });
        expect(getLinkIdsForStageAura).toHaveBeenCalledTimes(1);
        emit({ c__stage: 'hot', c__poffering: 'other-offer' }); // the matching echo
        await flush();
        expect(bar(el).values).toEqual({ stage: 'hot', offering: ['other-offer'] });
        expect(getLinkIdsForStageAura).toHaveBeenCalledTimes(1);
    });

    it('a genuine external change after the echo is still applied', async () => {
        const el = mount();
        emit({});
        await flush();
        change(el, 'offering', ['other-offer']);
        await flush();
        emit({ c__poffering: 'other-offer' });
        await flush();
        emit({ c__poffering: 'migration-accelerator' }); // e.g. browser back
        await flush();
        expect(bar(el).values).toEqual({ offering: ['migration-accelerator'] });
    });
});

describe('gtmRepLinkFinder cold deep link with a wired state that lags the URL', () => {
    it('a first wire emission without the params does not clear filters the URL carries', async () => {
        window.history.pushState({}, '', '/?c__stage=hot&c__poffering=other-offer');
        const el = mount();
        emit({});
        await flush();
        expect(bar(el).values).toEqual({ stage: 'hot', offering: ['other-offer'] });
        expect(getLinkIdsForStageAura).toHaveBeenCalledWith({ stageKey: 'hot' });
        expect(getLinkIdsForStageAura.mock.calls.every((c) => c[0].stageKey === 'hot')).toBe(true);
    });
});

describe('gtmRepLinkFinder Industry filter source (defined industries)', () => {
    const cfgIndustry = (el) => bar(el).filters.find((f) => f.key === 'industry');
    const colLabels = (el) => (table(el) ? table(el).data.map((r) => r.industryLabel) : []);

    it('offers the defined industries with their labels, not raw link values', async () => {
        getIndustryProfiles.mockResolvedValue([
            { industryKey: 'Retail', industryLabel: 'Retail and Consumer' },
            { industryKey: 'Tech', industryLabel: 'Technology' },
            { industryKey: 'unused', industryLabel: 'Unused Industry' }
        ]);
        const el = mount();
        emit({});
        await flush();
        expect(cfgIndustry(el).options).toEqual([
            { value: 'Retail', label: 'Retail and Consumer' },
            { value: 'Tech', label: 'Technology' },
            { value: 'unused', label: 'Unused Industry' }
        ]);
        expect(colLabels(el).sort()).toEqual(['Retail and Consumer', 'Retail and Consumer', 'Technology']);
    });

    it('adds a single Other option for undefined values and filters by it', async () => {
        getIndustryProfiles.mockResolvedValue([{ industryKey: 'Retail', industryLabel: 'Retail and Consumer' }, { industryKey: 'X', industryLabel: 'Ex' }]);
        const el = mount();
        emit({});
        await flush();
        expect(cfgIndustry(el).options.map((o) => o.label)).toEqual(['Ex', 'Retail and Consumer', 'Other']);
        change(el, 'industry', ['__other__']);
        await flush();
        expect(ids(el)).toEqual(['a0X000000000002AAA']);
        expect(colLabels(el)).toEqual(['Tech']); // raw value shown in the column
    });

    it('no defined industries: the filter has no options (bar hides it) and none are invented', async () => {
        getIndustryProfiles.mockResolvedValue([]);
        const el = mount();
        emit({});
        await flush();
        expect(cfgIndustry(el).options).toEqual([]);
    });

    it('a failed industries read leaves the filter empty', async () => {
        getIndustryProfiles.mockRejectedValue({ body: { message: 'x' } });
        const el = mount();
        emit({});
        await flush();
        expect(cfgIndustry(el).options).toEqual([]);
    });
});

describe('gtmRepLinkFinder recovery (filters never wedge)', () => {
    it('10 rapid filter changes then Clear filters shows the full unfiltered list', async () => {
        const el = mount();
        emit({});
        await flush();
        for (let i = 0; i < 10; i++) change(el, 'offering', i % 2 ? ['other-offer'] : ['migration-accelerator']);
        change(el, 'account', [A1]);
        await flush();
        bar(el).dispatchEvent(new CustomEvent('clear'));
        await flush();
        expect(bar(el).values).toEqual({});
        expect(ids(el)).toHaveLength(3);
        // a stale (older) echo of the last pick must not bring the filter back
        emit({ c__poffering: 'other-offer' });
        await flush();
        expect(ids(el)).toHaveLength(3);
    });

    it('a rejected links load shows Retry, and Retry recovers', async () => {
        getMyConfigurations.mockRejectedValueOnce({ body: { message: 'down' } });
        const el = mount();
        emit({});
        await flush();
        const err = el.shadowRoot.querySelector('.rlf-msg--err');
        expect(err.textContent).toContain('down');
        err.querySelector('button').click();
        await flush();
        expect(el.shadowRoot.querySelector('.rlf-msg--err')).toBeNull();
        expect(ids(el)).toHaveLength(3);
    });
});
