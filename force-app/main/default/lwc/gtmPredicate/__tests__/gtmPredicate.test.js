import { matches, parse, resolveSlots, pointsFor } from 'c/gtmPredicate';

/**
 * These tests pin the browser copy of the predicate language to the Apex one
 * (GtmPredicateTest) and to the Python one in scripts/build-instrument.py. Three
 * implementations of one grammar only stay one grammar if the same cases are
 * asserted against all three, so every case below has a named counterpart in
 * GtmPredicateTest.
 */
describe('gtmPredicate.matches', () => {
    it('a field with no value in the context is false, never true by default', () => {
        // The rule that makes branching safe: a variant whose predicate names an
        // unanswered slot does not fire, so the slot keeps its default question.
        expect(matches({ field: 'estate_scale', op: 'eq', value: 1 }, {})).toBe(false);
        expect(matches({ field: 'estate_scale', op: 'ne', value: 99 }, {})).toBe(false);
    });

    it('compares numbers as numbers and strings as trimmed, case-insensitive text', () => {
        expect(matches({ field: 'a', op: 'eq', value: '3' }, { a: 3 })).toBe(true);
        expect(matches({ field: 't', op: 'eq', value: 'SFMC_Next' }, { t: ' sfmc_next ' })).toBe(true);
    });

    it('supports every documented operator', () => {
        const ctx = { a: 3, t: 'sfmc_next' };
        expect(matches({ field: 'a', op: 'lt', value: 4 }, ctx)).toBe(true);
        expect(matches({ field: 'a', op: 'lte', value: 3 }, ctx)).toBe(true);
        expect(matches({ field: 'a', op: 'gt', value: 2 }, ctx)).toBe(true);
        expect(matches({ field: 'a', op: 'gte', value: 3 }, ctx)).toBe(true);
        expect(matches({ field: 'a', op: 'ne', value: 4 }, ctx)).toBe(true);
        expect(matches({ field: 't', op: 'in', value: ['sfmc', 'sfmc_next'] }, ctx)).toBe(true);
        expect(matches({ field: 't', op: 'not_in', value: ['sfmc'] }, ctx)).toBe(true);
    });

    it('nests all and any', () => {
        const ctx = { a: 1, b: 4 };
        expect(
            matches({ all: [{ field: 'a', op: 'eq', value: 1 }, { field: 'b', op: 'gte', value: 4 }] }, ctx)
        ).toBe(true);
        expect(
            matches({ any: [{ field: 'a', op: 'eq', value: 9 }, { field: 'b', op: 'eq', value: 4 }] }, ctx)
        ).toBe(true);
        expect(matches({ all: [{ field: 'a', op: 'eq', value: 9 }] }, ctx)).toBe(false);
    });

    it('is false rather than throwing on rubbish', () => {
        expect(matches(null, {})).toBe(false);
        expect(matches('nope', {})).toBe(false);
        expect(matches({ field: 'a', op: 'wat', value: 1 }, { a: 1 })).toBe(false);
        expect(parse('{oh no')).toBeNull();
        expect(parse('')).toBeNull();
    });
});

/** A pack shaped like GtmAssessmentInstrument.Pack, with one branched slot. */
function packWithBranch() {
    return {
        sourceKey: 'sfmc',
        targetKey: 'sfmc_next',
        slots: [
            {
                position: 1,
                key: 'estate_scale',
                baseKey: 'estate_scale',
                variantKey: 'default',
                question: 'How much is live?',
                options: [
                    { value: 1, label: 'a lot', points: 1, available: true },
                    { value: 2, label: 'some', points: 1, available: true },
                    { value: 3, label: 'a little', points: 3, available: true },
                    { value: 4, label: 'barely any', points: 4, available: true }
                ],
                variants: []
            },
            {
                position: 2,
                key: 'consent_portability',
                baseKey: 'consent_portability',
                variantKey: 'default',
                question: 'In-platform consent?',
                options: [{ value: 1, label: 'x', points: 1, available: true }],
                variants: [
                    {
                        position: 2,
                        key: 'consent_ownership_outside_platform',
                        baseKey: 'consent_portability',
                        variantKey: 'consent_owned_elsewhere',
                        showWhenJson: '{"all":[{"field":"estate_scale","op":"lte","value":2}]}',
                        question: 'Who masters consent?',
                        options: [{ value: 1, label: 'y', points: 1, available: true }],
                        variants: []
                    }
                ]
            }
        ]
    };
}

describe('gtmPredicate.resolveSlots', () => {
    it('always returns one slot per position, branch or no branch', () => {
        // The invariant, asserted directly: branching changes WHICH question
        // fills a slot and never HOW MANY slots there are.
        const pack = packWithBranch();
        expect(resolveSlots(pack, {}).length).toBe(2);
        expect(resolveSlots(pack, { estate_scale: 1 }).length).toBe(2);
        expect(resolveSlots(pack, { estate_scale: 4 }).length).toBe(2);
    });

    it('takes the branch when the earlier answer matches, and the default when it does not', () => {
        const pack = packWithBranch();
        const branched = resolveSlots(pack, { estate_scale: 2 });
        expect(branched[1].variantKey).toBe('consent_owned_elsewhere');
        expect(branched[1].key).toBe('consent_ownership_outside_platform');

        const plain = resolveSlots(pack, { estate_scale: 4 });
        expect(plain[1].variantKey).toBe('default');
        expect(plain[1].key).toBe('consent_portability');
    });

    it('leaves the default standing when the slot the branch depends on is unanswered', () => {
        expect(resolveSlots(packWithBranch(), {})[1].variantKey).toBe('default');
    });

    it('returns an empty list for a missing pack rather than throwing', () => {
        expect(resolveSlots(null, {})).toEqual([]);
        expect(resolveSlots({}, {})).toEqual([]);
    });
});

describe('gtmPredicate.pointsFor', () => {
    it('reads the authored points, not the option value', () => {
        const slot = resolveSlots(packWithBranch(), {})[0];
        expect(pointsFor(slot, 2)).toBe(1);
        expect(pointsFor(slot, 3)).toBe(3);
    });

    it('falls back to the option value when no points are authored', () => {
        const slot = { options: [{ value: 3, label: 'x' }] };
        expect(pointsFor(slot, 3)).toBe(3);
    });

    it('is null for an option the slot does not have', () => {
        expect(pointsFor({ options: [] }, 2)).toBeNull();
        expect(pointsFor(null, 2)).toBeNull();
    });
});
