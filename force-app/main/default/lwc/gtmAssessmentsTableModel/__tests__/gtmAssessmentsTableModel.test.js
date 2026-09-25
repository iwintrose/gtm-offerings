import {
    COLUMNS,
    PAGE_SIZE,
    buildFilterConfig,
    buildQuery,
    toPlain,
    fieldForSortKey,
    formatTotal,
    hasActiveFilters,
    mapRow,
    rawOfferingValues,
    rawIds,
    toPartyOption,
    mergePartyOptions,
    sortKeyForField
} from 'c/gtmAssessmentsTableModel';
import { validateFilters, readFilterState, buildFilterUrlState } from 'c/gtmFilterUrlState';

describe('gtmAssessmentsTableModel', () => {

    describe('buildFilterConfig', () => {
        it('is a valid shared-filter-bar config using the assessments params', () => {
            const cfg = buildFilterConfig(['a', 'b'], []);
            expect(validateFilters(cfg)).toEqual([]);
            expect(cfg.map((f) => f.param)).toEqual([
                'c__apreset', 'c__astatus', 'c__atier', 'c__areadout', 'c__arange', 'c__aoffering', 'c__aacct', 'c__acontact'
            ]);
        });
        it('Account and Contact are searchable, server-searched multi filters in More, options from the server', () => {
            const cfg = buildFilterConfig([], [], {
                account: [{ value: '001A', label: 'Acme' }, { value: 'bad,id', label: 'x' }],
                contact: [{ value: '003A', label: 'Jane' }]
            });
            const a = cfg.find((f) => f.key === 'account');
            const c = cfg.find((f) => f.key === 'contact');
            expect([a.type, a.multi, a.searchable, a.serverSearch, a.more]).toEqual(['chips', true, true, true, true]);
            expect(a.options).toEqual([{ value: '001A', label: 'Acme' }]);
            expect(c.options).toEqual([{ value: '003A', label: 'Jane' }]);
            expect(buildFilterConfig([], []).find((f) => f.key === 'account').options).toEqual([]);
        });
        it('round-trips account and contact ids through the url state', () => {
            const cfg = buildFilterConfig([], [], { account: [{ value: '001A', label: 'A' }, { value: '001B', label: 'B' }], contact: [{ value: '003A', label: 'J' }] });
            const state = buildFilterUrlState({}, cfg, { account: ['001A', '001B'], contact: ['003A'] });
            expect(state).toEqual({ c__aacct: '001A,001B', c__acontact: '003A' });
            expect(readFilterState(state, cfg)).toEqual({ account: ['001A', '001B'], contact: ['003A'] });
        });
        it('merges URL offering values into the options without duplicates or commas', () => {
            const cfg = buildFilterConfig(['a'], ['a', 'z', 'bad,value']);
            expect(cfg.find((f) => f.key === 'offering').options.map((o) => o.value)).toEqual(['a', 'z']);
        });
        it('round-trips state through gtmFilterUrlState', () => {
            const cfg = buildFilterConfig([], ['x']);
            const values = { status: ['new'], preset: true, range: '30', offering: ['x'] };
            const state = buildFilterUrlState({}, cfg, values);
            expect(state).toEqual({ c__astatus: 'new', c__apreset: 'true', c__arange: '30', c__aoffering: 'x' });
            expect(readFilterState(state, cfg)).toEqual(values);
        });
    });

    it('rawIds, toPartyOption and mergePartyOptions', () => {
        expect(rawIds({ c__aacct: '1,2' }, 'c__aacct')).toEqual(['1', '2']);
        expect(rawIds({}, 'c__aacct')).toEqual([]);
        expect(toPartyOption({ value: '003A', label: 'Jane', sublabel: 'Acme' })).toEqual({ value: '003A', label: 'Jane (Acme)' });
        expect(toPartyOption({ value: '001A', label: 'Acme' })).toEqual({ value: '001A', label: 'Acme' });
        const known = { '001B': { value: '001B', label: 'Beta' } };
        expect(
            mergePartyOptions([{ value: '001A', label: 'Acme' }, { value: '001B', label: 'Beta' }], ['001B', '001Z'], known)
        ).toEqual([{ value: '001B', label: 'Beta' }, { value: '001Z', label: '001Z' }, { value: '001A', label: 'Acme' }]);
    });

    it('rawOfferingValues splits the comma list and tolerates absence', () => {
        expect(rawOfferingValues({ c__aoffering: 'a,b' })).toEqual(['a', 'b']);
        expect(rawOfferingValues({})).toEqual([]);
        expect(rawOfferingValues(undefined)).toEqual([]);
    });

    describe('buildQuery', () => {
        it('maps values to the Apex AssessmentQuery shape', () => {
            expect(
                buildQuery({ status: ['new'], preset: true, range: { from: '2026-01-01', to: '2026-01-31' } }, null, 50, 50)
            ).toEqual({
                status: ['new'], tier: [], readout: [], offering: [], accountIds: [], contactIds: [],
                range: '2026-01-01..2026-01-31', preset: 'ready-to-book', offset: 50, pageSize: 50
            });
        });
        it('sends account and contact filter values as accountIds / contactIds', () => {
            const q = buildQuery({ account: ['001A'], contact: ['003A', '003B'] });
            expect(q.accountIds).toEqual(['001A']);
            expect(q.contactIds).toEqual(['003A', '003B']);
        });
        it('defaults: no sort keys, page 1, PAGE_SIZE', () => {
            const q = buildQuery({}, { sortBy: '', sortDir: '' });
            expect(q.sortBy).toBeUndefined();
            expect(q.offset).toBe(0);
            expect(q.pageSize).toBe(PAGE_SIZE);
            expect(q.preset).toBeNull();
            expect(q.range).toBeNull();
        });
        it('carries an explicit sort', () => {
            const q = buildQuery({}, { sortBy: 'score', sortDir: 'desc' });
            expect([q.sortBy, q.sortDir]).toEqual(['score', 'desc']);
        });
    });

    describe('sort key mapping', () => {
        it('is symmetric for every sortable column and unknown for the button column', () => {
            COLUMNS.filter((c) => c.sortable).forEach((c) => {
                const key = sortKeyForField(c.fieldName);
                expect(key).not.toBe('');
                expect(fieldForSortKey(key)).toBe(c.fieldName);
            });
            expect(sortKeyForField('name')).toBe('');
        });
    });

    describe('mapRow', () => {
        it('carries the contact and account ids and disables the cell when an id is missing', () => {
            const full = mapRow({ recordId: 'r', contactId: 'c', accountId: 'a' });
            expect([full.contactId, full.accountId, full.contactDisabled, full.companyDisabled]).toEqual(['c', 'a', false, false]);
            const bare = mapRow({ recordId: 'r' });
            expect([bare.contactDisabled, bare.companyDisabled]).toEqual([true, true]);
        });
        it('contact label falls back name -> requester -> company -> AR number', () => {
            expect(mapRow({ contactName: 'C', requesterName: 'R', company: 'Co', name: 'AR-1' }).contactLabel).toBe('C');
            expect(mapRow({ requesterName: 'R', company: 'Co', name: 'AR-1' }).contactLabel).toBe('R');
            expect(mapRow({ company: 'Co', name: 'AR-1' }).contactLabel).toBe('Co');
            expect(mapRow({ name: 'AR-1' }).contactLabel).toBe('AR-1');
        });
        it('falls back to createdDate for the submitted column', () => {
            expect(mapRow({ createdDate: 'x' }).submittedAt).toBe('x');
        });
        it('styles each tier and readout status, and the neutral cases', () => {
            expect(mapRow({ tier: 'Fast-Track' }).tierClass).toContain('success');
            expect(mapRow({ tier: 'Discovery First' }).tierClass).toContain('weak');
            expect(mapRow({}).tierLabel).toBe('—');
            expect(mapRow({ readoutStatus: 'Published' }).readoutClass).toContain('success');
            expect(mapRow({}).readoutLabel).toBe('None yet');
        });
        it('passes through the server-computed accountBackfillHint flag', () => {
            expect(mapRow({ accountBackfillHint: true }).accountBackfillHint).toBe(true);
            expect(mapRow({ accountBackfillHint: false }).accountBackfillHint).toBe(false);
            expect(mapRow({}).accountBackfillHint).toBe(false);
        });
    });

    it('hasActiveFilters ignores empty values', () => {
        expect(hasActiveFilters({})).toBe(false);
        expect(hasActiveFilters({ status: [], preset: false, range: '' })).toBe(false);
        expect(hasActiveFilters({ status: ['new'] })).toBe(true);
        expect(hasActiveFilters({ preset: true })).toBe(true);
    });

    it('formatTotal shows 10,000+ only when capped', () => {
        expect(formatTotal(10000, true)).toBe('10,000+');
        expect(formatTotal(42, false)).toBe('42');
    });

    it('buildQuery returns plain arrays even when inputs are Proxy-wrapped', () => {
        const q = buildQuery(
            {
                status: new Proxy(['completed'], {}),
                account: new Proxy(['001A', '001B'], {}),
                contact: new Proxy(['003A'], {}),
                readout: new Proxy(['none'], {})
            },
            null,
            0,
            10
        );
        expect(Array.isArray(q.status)).toBe(true);
        expect(q.status).toEqual(['completed']);
        expect(q.accountIds).toEqual(['001A', '001B']);
        expect(q.contactIds).toEqual(['003A']);
        expect(q.readout).toEqual(['none']);
        expect(q.tier).toEqual([]);
        expect(JSON.parse(JSON.stringify(q))).toEqual(q);
    });

    it('toPlain deep-copies', () => {
        const o = { a: new Proxy(['x'], {}) };
        const p = toPlain(o);
        expect(p).toEqual({ a: ['x'] });
        expect(p.a).not.toBe(o.a);
    });
});
