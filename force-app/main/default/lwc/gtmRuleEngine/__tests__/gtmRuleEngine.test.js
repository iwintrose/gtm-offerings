import { evaluateRules, detectCircularDependencies, cleanupHiddenValues } from 'c/gtmRuleEngine';

describe('gtmRuleEngine.evaluateRules', () => {
    it('resolves EQUALS / NOT_EQUALS', () => {
        const rules = [
            { logic: 'AND', conditions: [{ field: 'q1', operator: 'EQUALS', value: 'yes' }], action: 'SHOW', target: 'q3' }
        ];
        expect(evaluateRules(rules, { q1: 'yes' }).visible.has('q3')).toBe(true);
        expect(evaluateRules(rules, { q1: 'no' }).visible.has('q3')).toBe(false);

        const neRules = [
            { logic: 'AND', conditions: [{ field: 'q1', operator: 'NOT_EQUALS', value: 'yes' }], action: 'SHOW', target: 'q3' }
        ];
        expect(evaluateRules(neRules, { q1: 'no' }).visible.has('q3')).toBe(true);
        expect(evaluateRules(neRules, { q1: 'yes' }).visible.has('q3')).toBe(false);
    });

    it('resolves CONTAINS', () => {
        const rules = [
            { logic: 'AND', conditions: [{ field: 'q1', operator: 'CONTAINS', value: 'sfmc' }], action: 'SHOW', target: 'q3' }
        ];
        expect(evaluateRules(rules, { q1: 'SFMC_Next' }).visible.has('q3')).toBe(true);
        expect(evaluateRules(rules, { q1: 'other' }).visible.has('q3')).toBe(false);
    });

    it('resolves GREATER_THAN / LESS_THAN numerically', () => {
        const gt = [{ logic: 'AND', conditions: [{ field: 'q2', operator: 'GREATER_THAN', value: '5' }], action: 'SHOW', target: 'q3' }];
        expect(evaluateRules(gt, { q2: '6' }).visible.has('q3')).toBe(true);
        expect(evaluateRules(gt, { q2: 5 }).visible.has('q3')).toBe(false);
        expect(evaluateRules(gt, { q2: 'not-a-number' }).visible.has('q3')).toBe(false);

        const lt = [{ logic: 'AND', conditions: [{ field: 'q2', operator: 'LESS_THAN', value: '5' }], action: 'SHOW', target: 'q3' }];
        expect(evaluateRules(lt, { q2: 4 }).visible.has('q3')).toBe(true);
        expect(evaluateRules(lt, { q2: 5 }).visible.has('q3')).toBe(false);
    });

    it('resolves IS_EMPTY / IS_NOT_EMPTY', () => {
        const isEmpty = [{ logic: 'AND', conditions: [{ field: 'q1', operator: 'IS_EMPTY' }], action: 'SHOW', target: 'q3' }];
        expect(evaluateRules(isEmpty, {}).visible.has('q3')).toBe(true);
        expect(evaluateRules(isEmpty, { q1: '' }).visible.has('q3')).toBe(true);
        expect(evaluateRules(isEmpty, { q1: 'x' }).visible.has('q3')).toBe(false);

        const isNotEmpty = [{ logic: 'AND', conditions: [{ field: 'q1', operator: 'IS_NOT_EMPTY' }], action: 'SHOW', target: 'q3' }];
        expect(evaluateRules(isNotEmpty, { q1: 'x' }).visible.has('q3')).toBe(true);
        expect(evaluateRules(isNotEmpty, {}).visible.has('q3')).toBe(false);
    });

    it('combines conditions with AND', () => {
        const rules = [
            {
                logic: 'AND',
                conditions: [
                    { field: 'q1', operator: 'EQUALS', value: 'yes' },
                    { field: 'q2', operator: 'GREATER_THAN', value: '5' }
                ],
                action: 'SHOW',
                target: 'q3'
            }
        ];
        expect(evaluateRules(rules, { q1: 'yes', q2: 6 }).visible.has('q3')).toBe(true);
        expect(evaluateRules(rules, { q1: 'yes', q2: 4 }).visible.has('q3')).toBe(false);
        expect(evaluateRules(rules, { q1: 'no', q2: 6 }).visible.has('q3')).toBe(false);
    });

    it('combines conditions with OR', () => {
        const rules = [
            {
                logic: 'OR',
                conditions: [
                    { field: 'q1', operator: 'EQUALS', value: 'yes' },
                    { field: 'q2', operator: 'GREATER_THAN', value: '5' }
                ],
                action: 'SHOW',
                target: 'q3'
            }
        ];
        expect(evaluateRules(rules, { q1: 'yes', q2: 1 }).visible.has('q3')).toBe(true);
        expect(evaluateRules(rules, { q1: 'no', q2: 6 }).visible.has('q3')).toBe(true);
        expect(evaluateRules(rules, { q1: 'no', q2: 1 }).visible.has('q3')).toBe(false);
    });

    it('resolves all four action types', () => {
        const rules = [
            { logic: 'AND', conditions: [{ field: 'q1', operator: 'EQUALS', value: 'yes' }], action: 'SHOW', target: 'q3' },
            { logic: 'AND', conditions: [{ field: 'q1', operator: 'EQUALS', value: 'yes' }], action: 'HIDE', target: 'q4' },
            { logic: 'AND', conditions: [{ field: 'q1', operator: 'EQUALS', value: 'yes' }], action: 'MAKE_REQUIRED', target: 'q5' },
            { logic: 'AND', conditions: [{ field: 'q1', operator: 'EQUALS', value: 'yes' }], action: 'SKIP_TO_SECTION', target: 'section2' }
        ];
        const result = evaluateRules(rules, { q1: 'yes' });
        expect(result.visible.has('q3')).toBe(true);
        expect(result.hidden.has('q4')).toBe(true);
        expect(result.required.has('q5')).toBe(true);
        expect(result.nextSection).toBe('section2');
    });

    it('does not throw and warns on an unresolvable target', () => {
        const rules = [{ logic: 'AND', conditions: [{ field: 'q1', operator: 'EQUALS', value: 'yes' }], action: 'SHOW', target: 'ghost' }];
        const result = evaluateRules(rules, { q1: 'yes' }, ['q1', 'q3']);
        expect(result.visible.has('ghost')).toBe(false);
        expect(result.warnings.length).toBe(1);
        expect(result.warnings[0]).toMatch(/ghost/);
    });

    it('warns and skips (never throws) on malformed rule shapes', () => {
        expect(() => evaluateRules([null, 'nope', {}], {})).not.toThrow();
        const result = evaluateRules([null, 'nope', {}], {});
        expect(result.warnings.length).toBe(3);

        const badAction = [{ logic: 'AND', conditions: [], action: 'DESTROY', target: 'q1' }];
        expect(evaluateRules(badAction, {}).warnings.length).toBe(1);

        const badOperator = [{ logic: 'AND', conditions: [{ field: 'q1', operator: 'FROBNICATE', value: 1 }], action: 'SHOW', target: 'q2' }];
        expect(evaluateRules(badOperator, {}).warnings.length).toBe(1);
    });

    it('treats null/empty/non-array rules as no branching behavior', () => {
        expect(evaluateRules(null, {}).visible.size).toBe(0);
        expect(evaluateRules([], {}).visible.size).toBe(0);
        expect(evaluateRules(undefined, {}).warnings.length).toBe(0);
        expect(evaluateRules('[]', {}).warnings.length).toBe(0);
        expect(evaluateRules('[]', {}).visible.size).toBe(0);
    });
});

describe('gtmRuleEngine.detectCircularDependencies', () => {
    it('flags a direct 2-node cycle', () => {
        const rules = [
            { logic: 'AND', conditions: [{ field: 'q1', operator: 'EQUALS', value: 'yes' }], action: 'SHOW', target: 'q2' },
            { logic: 'AND', conditions: [{ field: 'q2', operator: 'EQUALS', value: 'yes' }], action: 'SHOW', target: 'q1' }
        ];
        const cycles = detectCircularDependencies(rules);
        expect(cycles.length).toBeGreaterThan(0);
    });

    it('flags a longer indirect cycle (q1 -> q2 -> q3 -> q1)', () => {
        const rules = [
            { logic: 'AND', conditions: [{ field: 'q1', operator: 'EQUALS', value: 'yes' }], action: 'SHOW', target: 'q2' },
            { logic: 'AND', conditions: [{ field: 'q2', operator: 'EQUALS', value: 'yes' }], action: 'SHOW', target: 'q3' },
            { logic: 'AND', conditions: [{ field: 'q3', operator: 'EQUALS', value: 'yes' }], action: 'SHOW', target: 'q1' }
        ];
        const cycles = detectCircularDependencies(rules);
        expect(cycles.length).toBeGreaterThan(0);
    });

    it('returns an empty result for acyclic rule sets', () => {
        const rules = [
            { logic: 'AND', conditions: [{ field: 'q1', operator: 'EQUALS', value: 'yes' }], action: 'SHOW', target: 'q2' },
            { logic: 'AND', conditions: [{ field: 'q2', operator: 'EQUALS', value: 'yes' }], action: 'SHOW', target: 'q3' }
        ];
        expect(detectCircularDependencies(rules)).toEqual([]);
    });

    it('returns an empty result for no rules at all', () => {
        expect(detectCircularDependencies([])).toEqual([]);
        expect(detectCircularDependencies(null)).toEqual([]);
        expect(detectCircularDependencies(undefined)).toEqual([]);
    });
});

describe('gtmRuleEngine.cleanupHiddenValues', () => {
    it('strips exactly the hidden keys and leaves others untouched', () => {
        const answers = { q1: 'yes', q2: 'no', q3: '5' };
        const cleaned = cleanupHiddenValues(answers, new Set(['q2']));
        expect(cleaned).toEqual({ q1: 'yes', q3: '5' });
        // original untouched
        expect(answers).toEqual({ q1: 'yes', q2: 'no', q3: '5' });
    });

    it('is a no-op when the hidden set is empty', () => {
        const answers = { q1: 'yes', q2: 'no' };
        expect(cleanupHiddenValues(answers, new Set())).toEqual(answers);
        expect(cleanupHiddenValues(answers, [])).toEqual(answers);
        expect(cleanupHiddenValues(answers, null)).toEqual(answers);
    });

    it('clears everything when the hidden set covers all keys', () => {
        const answers = { q1: 'yes', q2: 'no' };
        expect(cleanupHiddenValues(answers, new Set(['q1', 'q2']))).toEqual({});
    });

    it('accepts a plain array of hidden keys, not just a Set', () => {
        const answers = { q1: 'yes', q2: 'no' };
        expect(cleanupHiddenValues(answers, ['q1'])).toEqual({ q2: 'no' });
    });
});
