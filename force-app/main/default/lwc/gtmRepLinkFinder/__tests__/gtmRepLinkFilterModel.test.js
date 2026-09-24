import { validateFilters } from 'c/gtmFilterUrlState';
import {
    PAGES_PARAMS, buildExtraFilters, matchesDate, matchesExtra, filterLinks, hasExtraActive, extraValuesOnly,
    mapLegacyParams, cleanNavigateBase
} from '../gtmRepLinkFilterModel';

const NOW = new Date('2026-09-20T12:00:00Z').getTime();
const L = (o) => ({ Id: 'a0X1', Offering__c: 'migration-accelerator', Active__c: true, OwnerId: '005A', ...o });

describe('gtmRepLinkFilterModel config', () => {
    const links = [
        L({ Id: '1', Industry__c: 'Retail', Opportunity__r: { StageName: 'Prospecting' }, Account__c: '001A', Account__r: { Name: 'Acme' }, Contact__c: '003A', Contact__r: { Name: 'Jane' } }),
        L({ Id: '2', Offering__c: 'x-y', Industry__c: 'Retail', Account__c: '001B', Company__c: 'Beta', Contact__c: '003B' })
    ];

    it('row: Offering and Sent; More: Industry, Deal stage, Account, Contact, Link status (in order)', () => {
        const cfg = buildExtraFilters({ links, statsComplete: false, state: {} });
        expect(cfg.map((f) => f.key)).toEqual(['offering', 'sent', 'industry', 'deal', 'account', 'contact', 'active']);
        expect(cfg.filter((f) => !f.more).map((f) => f.key)).toEqual(['offering', 'sent']);
        expect(cfg.map((f) => f.param)).toEqual([
            'c__poffering', 'c__psent', 'c__pindustry', 'c__pdeal', 'c__pacct', 'c__pcontact', 'c__pactive'
        ]);
        expect(Object.values(PAGES_PARAMS)).not.toContain('c__offering');
        expect(validateFilters(cfg)).toEqual([]);
    });

    it('account and contact values are Ids with names as labels and are searchable', () => {
        const cfg = buildExtraFilters({ links, state: {} });
        const acct = cfg.find((f) => f.key === 'account');
        expect(acct.options).toEqual([{ value: '001A', label: 'Acme' }, { value: '001B', label: 'Beta' }]);
        expect(acct.searchable).toBe(true);
        expect(cfg.find((f) => f.key === 'contact').options.map((o) => o.label)).toEqual(['003B', 'Jane']);
    });

    it('Last visit only with complete stats; Owner only with more than one distinct owner', () => {
        expect(buildExtraFilters({ links, statsComplete: true }).some((f) => f.key === 'last')).toBe(true);
        expect(buildExtraFilters({ links, statsComplete: false }).some((f) => f.key === 'last')).toBe(false);
        expect(buildExtraFilters({ links }).some((f) => f.key === 'owner')).toBe(false);
        const two = [...links, L({ Id: '3', OwnerId: '005B', Owner: { Name: 'Sam' } })];
        const owner = buildExtraFilters({ links: two }).find((f) => f.key === 'owner');
        expect(owner.options.map((o) => o.value)).toEqual(['005A', '005B']);
    });

    it('deep-link values in the URL are kept as options before data loads; commas are skipped', () => {
        const cfg = buildExtraFilters({ links: [], state: { c__poffering: 'aaa,bbb', c__pacct: '001Z' } });
        expect(cfg.find((f) => f.key === 'offering').options.map((o) => o.value)).toEqual(['aaa', 'bbb']);
        expect(cfg.find((f) => f.key === 'account').options).toEqual([{ value: '001Z', label: '001Z' }]);
        const commas = buildExtraFilters({ links: [L({ Offering__c: 'a,b' })] });
        expect(commas.find((f) => f.key === 'offering').options).toEqual([]);
    });
});

describe('gtmRepLinkFilterModel matching', () => {
    it('date presets and custom ranges', () => {
        expect(matchesDate('2026-09-15T00:00:00Z', '7', NOW)).toBe(true);
        expect(matchesDate('2026-09-01T00:00:00Z', '7', NOW)).toBe(false);
        expect(matchesDate('2026-09-01T00:00:00Z', '30', NOW)).toBe(true);
        expect(matchesDate('2026-09-10T08:00:00Z', { from: '2026-09-10', to: '2026-09-10' }, NOW)).toBe(true);
        expect(matchesDate('2026-09-11T08:00:00Z', { from: '2026-09-10', to: '2026-09-10' }, NOW)).toBe(false);
        expect(matchesDate(null, '30', NOW)).toBe(false);
    });

    it('every active filter ANDs; multi values OR within one filter; inactive filters match everything', () => {
        const a = L({ Id: '1', Offering__c: 'o1', Industry__c: 'Retail', Opportunity__r: { StageName: 'Won' }, Account__c: 'A1', Contact__c: 'C1', CreatedDate: '2026-09-18T00:00:00Z' });
        expect(matchesExtra(a, null, {}, NOW)).toBe(true);
        expect(matchesExtra(a, null, { offering: ['o1', 'o2'] }, NOW)).toBe(true);
        expect(matchesExtra(a, null, { offering: ['o2'] }, NOW)).toBe(false);
        expect(matchesExtra(a, null, { offering: ['o1'], industry: ['Retail'], deal: ['Won'] }, NOW)).toBe(true);
        expect(matchesExtra(a, null, { offering: ['o1'], industry: ['Tech'] }, NOW)).toBe(false);
        expect(matchesExtra(a, null, { account: ['A1'], contact: ['C2'] }, NOW)).toBe(false);
        expect(matchesExtra(a, null, { sent: '7' }, NOW)).toBe(true);
    });

    it('rows without an opportunity, account or contact never match while that filter is active', () => {
        const bare = L({ Id: '9' });
        expect(matchesExtra(bare, null, { deal: ['Won'] }, NOW)).toBe(false);
        expect(matchesExtra(bare, null, { account: ['A1'] }, NOW)).toBe(false);
        expect(matchesExtra(bare, null, { contact: ['C1'] }, NOW)).toBe(false);
    });

    it('Link status and Last visit (never-opened links excluded while a range is active)', () => {
        const on = L({ Id: '1', Active__c: true });
        const off = L({ Id: '2', Active__c: false });
        expect(matchesExtra(on, null, { active: 'active' }, NOW)).toBe(true);
        expect(matchesExtra(off, null, { active: 'active' }, NOW)).toBe(false);
        expect(matchesExtra(off, null, { active: 'inactive' }, NOW)).toBe(true);
        expect(matchesExtra(on, { lastVisitAt: '2026-09-19T00:00:00Z' }, { last: '7' }, NOW)).toBe(true);
        expect(matchesExtra(on, null, { last: '7' }, NOW)).toBe(false);
    });

    it('filterLinks returns the same array when nothing is active, and uses stats by link Id', () => {
        const links = [L({ Id: '1' }), L({ Id: '2' })];
        expect(filterLinks(links, [], {}, NOW)).toBe(links);
        const out = filterLinks(links, [{ linkId: '2', lastVisitAt: '2026-09-19T00:00:00Z' }], { last: '30' }, NOW);
        expect(out.map((l) => l.Id)).toEqual(['2']);
        expect(hasExtraActive({ stage: 'hot' })).toBe(false);
        expect(hasExtraActive({ owner: [] })).toBe(false);
        expect(hasExtraActive({ owner: ['x'] })).toBe(true);
        expect(extraValuesOnly({ stage: 'hot', offering: ['x'] })).toEqual({ offering: ['x'] });
    });
});

describe('mapLegacyParams', () => {
    it('maps account and contact ids without a link id; ignores c__rlfMode; keeps unrelated params', () => {
        const r = mapLegacyParams({ c__rlfAccountId: 'A', c__rlfContactId: 'C', c__rlfMode: 'account', c__x: '1' });
        expect(r.mapped).toBe(true);
        expect(r.state.c__pacct).toBe('A');
        expect(r.state.c__pcontact).toBe('C');
        expect(r.state.c__x).toBe('1');
    });
    it('does not map when a link id is present (detail deep link) or nothing legacy is present', () => {
        expect(mapLegacyParams({ c__rlfAccountId: 'A', c__rlfLinkId: 'L' }).mapped).toBe(false);
        expect(mapLegacyParams({ c__pacct: 'A' }).mapped).toBe(false);
        expect(mapLegacyParams(undefined).mapped).toBe(false);
    });
    it('an explicit filter param wins', () => {
        const r = mapLegacyParams({ c__rlfAccountId: 'A', c__pacct: 'B' });
        expect(r.state.c__pacct).toBe('B');
        expect(r.mapped).toBe(false);
    });
});

describe('cleanNavigateBase', () => {
    it('drops c__rlfMode, legacy ids without a link id and stale detail params absent from the URL', () => {
        const out = cleanNavigateBase(
            { c__rlfMode: 'all', c__rlfAccountId: 'A', c__rlfContactId: 'C', c__rlfShowPreview: '1', c__stage: 'hot' }, '?c__stage=hot');
        expect(out).toEqual({ c__stage: 'hot' });
    });
    it('keeps the detail params while the URL still carries a link id', () => {
        const state = { c__rlfAccountId: 'A', c__rlfLinkId: 'L' };
        expect(cleanNavigateBase(state, '?c__rlfAccountId=A&c__rlfLinkId=L')).toEqual(state);
    });
});

describe('industry source helpers', () => {
    const { industryOptions, industryDisplay, INDUSTRY_OTHER, matchesExtra } = require('../gtmRepLinkFilterModel');
    const defs = [{ industryKey: 'fintech', industryLabel: 'Financial Services' }, { industryKey: 'lifesci', industryLabel: 'Life Sciences' }];
    it('options come from definitions, sorted by label, with labels', () => {
        expect(industryOptions([{ Industry__c: 'fintech' }], defs)).toEqual([
            { value: 'fintech', label: 'Financial Services' },
            { value: 'lifesci', label: 'Life Sciences' }
        ]);
    });
    it('Other only when some link value matches no definition', () => {
        expect(industryOptions([{ Industry__c: 'retail' }, { Industry__c: 'mining' }], defs).filter((o) => o.value === INDUSTRY_OTHER)).toHaveLength(1);
        expect(industryOptions([{ Industry__c: '' }, {}], defs).some((o) => o.value === INDUSTRY_OTHER)).toBe(false);
    });
    it('no definitions: no options at all, never invents values or Other', () => {
        expect(industryOptions([{ Industry__c: 'retail' }], [])).toEqual([]);
        expect(industryOptions([{ Industry__c: 'retail' }], undefined)).toEqual([]);
        expect(industryOptions([], null, ['fintech'])).toEqual([{ value: 'fintech', label: 'fintech' }]); // pre-load deep link
    });
    it('display label when matched, else raw, else blank', () => {
        expect(industryDisplay('fintech', defs)).toBe('Financial Services');
        expect(industryDisplay('retail', defs)).toBe('retail');
        expect(industryDisplay('', defs)).toBe('');
    });
    it('matchesExtra: Other matches undefined values only', () => {
        const v = { industry: [INDUSTRY_OTHER] };
        expect(matchesExtra({ Industry__c: 'retail' }, null, v, Date.now(), defs)).toBe(true);
        expect(matchesExtra({ Industry__c: 'fintech' }, null, v, Date.now(), defs)).toBe(false);
        expect(matchesExtra({ Industry__c: '' }, null, v, Date.now(), defs)).toBe(false);
        expect(matchesExtra({ Industry__c: 'fintech' }, null, { industry: ['fintech'] }, Date.now(), defs)).toBe(true);
    });
});
