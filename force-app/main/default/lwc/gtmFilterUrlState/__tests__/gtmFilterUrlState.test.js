import {
    readFilterState,
    buildFilterUrlState,
    buildNavigateArgs,
    mergeLocationState,
    validateFilters,
    assertValidFilters,
    RESERVED_PARAMS
} from 'c/gtmFilterUrlState';

const FILTERS = [
    { key: 'stage', label: 'Stage', type: 'chips', multi: true, param: 'c__stage',
      options: [{ value: 'sent', label: 'S' }, { value: 'quiet', label: 'Q' }, { value: 'hot', label: 'H' }] },
    { key: 'tier', label: 'Tier', type: 'select', param: 'c__atier', options: [{ value: 'one', label: '1' }] },
    { key: 'mode', label: 'Mode', type: 'chips', param: 'c__amode', options: [{ value: 'x', label: 'X' }, { value: 'y', label: 'Y' }] },
    { key: 'mine', label: 'Mine', type: 'toggle', param: 'c__amine' },
    { key: 'range', label: 'Range', type: 'date-range', param: 'c__arange' }
];

describe('gtmFilterUrlState', () => {
    it('round-trips config -> state -> values -> state', () => {
        const values = {
            stage: ['sent', 'hot'], tier: 'one', mode: 'y', mine: true,
            range: { from: '2026-01-01', to: '2026-03-01' }
        };
        const state = buildFilterUrlState({}, FILTERS, values);
        expect(state).toEqual({
            c__stage: 'sent,hot', c__atier: 'one', c__amode: 'y', c__amine: 'true',
            c__arange: '2026-01-01..2026-03-01'
        });
        expect(readFilterState(state, FILTERS)).toEqual(values);
        expect(buildFilterUrlState({}, FILTERS, readFilterState(state, FILTERS))).toEqual(state);
    });

    it('encodes multi as one comma param in option order', () => {
        expect(buildFilterUrlState({}, FILTERS, { stage: ['hot', 'quiet'] }).c__stage).toBe('quiet,hot');
    });

    it('supports preset tokens for date range', () => {
        const state = buildFilterUrlState({}, FILTERS, { range: '30' });
        expect(state.c__arange).toBe('30');
        expect(readFilterState(state, FILTERS).range).toBe('30');
    });

    it('drops invalid or unknown values on read', () => {
        const values = readFilterState(
            { c__stage: 'bogus,hot', c__atier: 'nope', c__amode: 'zzz', c__amine: 'false',
              c__arange: '2026-02-30..2026-03-01' },
            FILTERS
        );
        expect(values).toEqual({ stage: ['hot'] });
        expect(readFilterState({ c__arange: '2026-03-01..2026-01-01' }, FILTERS)).toEqual({});
        expect(readFilterState({ c__arange: '45' }, FILTERS)).toEqual({});
    });

    it('empty values remove only the config params; unrelated params untouched', () => {
        const current = {
            c__assessmentRequestId: 'a01', c__repDirectId: '005', c__rlfMode: 'm', other: 'keep',
            c__stage: 'hot', c__atier: 'one'
        };
        const next = buildFilterUrlState(current, FILTERS, { stage: [], tier: '', mine: false });
        expect(next).toEqual({ c__assessmentRequestId: 'a01', c__repDirectId: '005', c__rlfMode: 'm', other: 'keep' });
        expect(current.c__stage).toBe('hot'); // input not mutated
    });

    it('omits params equal to defaultValue and applies default on read', () => {
        const f = [{ key: 'm', label: 'M', type: 'chips', param: 'c__m', defaultValue: 'x',
            options: [{ value: 'x', label: 'X' }, { value: 'y', label: 'Y' }] }];
        expect(buildFilterUrlState({}, f, { m: 'x' })).toEqual({});
        expect(buildFilterUrlState({}, f, { m: 'y' })).toEqual({ c__m: 'y' });
        expect(readFilterState({}, f)).toEqual({ m: 'x' });
    });

    it('rejects colliding / non-c__ params and comma option values', () => {
        RESERVED_PARAMS.concat(['c__rlfAccountId']).forEach((param) => {
            const f = [{ key: 'k', type: 'toggle', param }];
            expect(validateFilters(f).length).toBe(1);
            expect(() => assertValidFilters(f)).toThrow(/reserved/);
            expect(buildFilterUrlState({ [param]: 'orig' }, f, { k: true })).toEqual({ [param]: 'orig' });
            expect(readFilterState({ [param]: 'true' }, f)).toEqual({});
        });
        expect(() => assertValidFilters([{ key: 'k', type: 'toggle', param: 'stage' }])).toThrow(/c__/);
        expect(validateFilters([{ key: 'k', type: 'select', param: 'c__k', options: [{ value: 'a,b', label: 'x' }] }]).length).toBe(1);
        expect(() => assertValidFilters(FILTERS)).not.toThrow();
    });

    it('buildNavigateArgs merges state, keeps page ref, replace by default', () => {
        const ref = { type: 'standard__navItemPage', attributes: { apiName: 'Tab' }, state: { c__repDirectId: '005', c__stage: 'hot' } };
        const { pageReference, replace } = buildNavigateArgs(ref, FILTERS, { stage: ['sent'] });
        expect(replace).toBe(true);
        expect(pageReference.type).toBe('standard__navItemPage');
        expect(pageReference.attributes).toEqual({ apiName: 'Tab' });
        expect(pageReference.state).toEqual({ c__repDirectId: '005', c__stage: 'sent' });
        expect(ref.state.c__stage).toBe('hot');
        expect(buildNavigateArgs(ref, FILTERS, {}, { mode: 'push' }).replace).toBe(false);
        const withCurrent = buildNavigateArgs(ref, FILTERS, {}, { currentState: { c__rlfX: '1' } });
        expect(withCurrent.pageReference.state).toEqual({ c__rlfX: '1' });
    });

    describe('mergeLocationState', () => {
        const original = window.location.href;
        afterEach(() => window.history.replaceState({}, '', original));

        it('overlays c__ location params onto stale wired state', () => {
            window.history.replaceState({}, '', '/?c__assessmentRequestId=a01&c__rlfMode=x&foo=bar&c__stage=hot');
            const wired = { c__stage: 'sent', c__repDirectId: '005' };
            const merged = mergeLocationState(wired);
            expect(merged).toEqual({ c__stage: 'hot', c__repDirectId: '005', c__assessmentRequestId: 'a01', c__rlfMode: 'x' });
            expect(wired.c__stage).toBe('sent');
            const { pageReference } = buildNavigateArgs({ type: 't', attributes: {}, state: wired }, FILTERS, { stage: ['quiet'] }, { currentState: merged });
            expect(pageReference.state.c__assessmentRequestId).toBe('a01');
            expect(pageReference.state.c__stage).toBe('quiet');
        });

        it('handles missing state', () => {
            window.history.replaceState({}, '', '/');
            expect(mergeLocationState(undefined)).toEqual({});
        });
    });
});
