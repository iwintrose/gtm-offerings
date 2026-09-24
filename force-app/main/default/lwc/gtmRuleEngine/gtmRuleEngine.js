/**
 * Branching-rule engine for the `GTM_Instrument_Question_Definition__c
 * .Rules_JSON__c` schema (docs/architecture/gtm-instrument-schema.md §3.2,
 * the `assessment-instrument-rebuild-01-schema` sub-issue's schema, which
 * supersedes `docs/architecture/gtm-instrument-editor.md`'s
 * `GTM_Instrument_Question__c` object), used by the Content Manager's live
 * authoring preview (sub-issue 04).
 *
 * RE-TARGETED BY `assessment-instrument-rebuild-03-rule-engine-migration`:
 * this module previously targeted the now-superseded
 * `GTM_Instrument_Question__c.Rules_JSON__c` (from the older, separate
 * `gtm-instrument-editor.md` sub-issue 03). The `Rules_JSON__c` JSON shape
 * itself — `logic`, `conditions[]`, `action`, `target` — is byte-for-byte
 * unchanged between the two schemas (docs/architecture/
 * gtm-instrument-schema.md §3.2 restates it verbatim as "unchanged from
 * `GTM_Instrument_Question__c.Rules_JSON__c`"), so this file's evaluator
 * functions (`evaluateRules`, `detectCircularDependencies`,
 * `cleanupHiddenValues`) needed no logic changes at all — only this
 * top-comment's field references move onto the new object name. Every
 * caller is expected to pass `JSON.parse(questionDefinition.Rules_JSON__c)`
 * from the new object going forward, not the retired one.
 *
 * Pure, framework-agnostic JS — no DOM access, no `@salesforce/apex` import,
 * no LWC lifecycle. Bundled as an unexposed LWC module purely so it can be
 * imported as `c/gtmRuleEngine`, following the existing `c/gtmPredicate`
 * precedent (`.js` + `.js-meta.xml`, no `.html`/`.css`). It is a NET-NEW,
 * PARALLEL module for the `Rules_JSON__c`/`Options_JSON__c` schema — it does
 * not replace, and is not wired into, `gtmPredicate`'s YAML `show_when`
 * evaluation path, which keeps driving Migration Accelerator's live guest
 * assessment unchanged (that YAML/CMDT path is being migrated and retired by
 * this same sub-issue's migration script + prepared-cutover plan — see
 * `scripts/migrate-instrument-yaml.py` and
 * `docs/architecture/gtm-instrument-rule-engine-cutover-plan.md` — but is
 * not switched over yet, pending QA parity confirmation on `gtm-staging`).
 *
 * INPUT SHAPE DECISION (binding for sub-issue 04, per this file's own
 * top-comment contract requirement):
 *
 *   Every exported function here accepts ALREADY-PARSED JS values —
 *   `rules` is a plain array of rule objects (or `null`/`[]`), never a JSON
 *   string. This mirrors the architecture doc's §5 LWC data contract, where
 *   `QuestionDto.rulesJson`/`optionsJson` travel as JSON-encoded strings only
 *   at the Apex/LWC wire boundary and "the LWC is responsible for
 *   `JSON.parse`/`JSON.stringify` at the edges." `gtmRuleEngine` is NOT that
 *   edge — the caller (sub-issue 04's `gtmInstrumentAuthor`/its preview) owns
 *   `JSON.parse(question.rulesJson)` once per question and passes the
 *   resulting array in here. This keeps the engine reusable against rules
 *   gathered from many questions at once (a full instrument's rule graph)
 *   without re-parsing the same string repeatedly, and keeps this module's
 *   signature symmetric with `c/gtmPredicate`'s `matches(node, context)`,
 *   which also takes a parsed node, not a string.
 *
 *   Malformed/non-array input (`null`, `undefined`, `''`, a JSON string,
 *   or anything that isn't an array) is treated exactly like an empty rule
 *   set: "no branching behavior — always shown" (doc §3.2). Nothing here
 *   ever throws on bad input.
 */

const OPERATORS = new Set([
    'EQUALS',
    'NOT_EQUALS',
    'CONTAINS',
    'GREATER_THAN',
    'LESS_THAN',
    'IS_EMPTY',
    'IS_NOT_EMPTY'
]);

const ACTIONS = new Set(['SHOW', 'HIDE', 'SKIP_TO_SECTION', 'MAKE_REQUIRED']);

function toRulesArray(rules) {
    return Array.isArray(rules) ? rules : [];
}

function numeric(value) {
    if (value === null || value === undefined || value === '') {
        return null;
    }
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
}

function isEmptyValue(value) {
    return value === null || value === undefined || String(value).trim() === '';
}

/** Evaluates a single condition against the current answers map. Unknown operators are false, never thrown. */
function conditionHolds(condition, answers) {
    if (!condition || typeof condition !== 'object') {
        return false;
    }
    const { field, operator, value } = condition;
    const actual = answers ? answers[field] : undefined;

    switch (operator) {
        case 'IS_EMPTY':
            return isEmptyValue(actual);
        case 'IS_NOT_EMPTY':
            return !isEmptyValue(actual);
        case 'EQUALS':
            if (isEmptyValue(actual)) return false;
            return String(actual).trim().toLowerCase() === String(value).trim().toLowerCase();
        case 'NOT_EQUALS':
            if (isEmptyValue(actual)) return false;
            return String(actual).trim().toLowerCase() !== String(value).trim().toLowerCase();
        case 'CONTAINS':
            if (isEmptyValue(actual)) return false;
            return String(actual).toLowerCase().includes(String(value).toLowerCase());
        case 'GREATER_THAN': {
            const a = numeric(actual);
            const b = numeric(value);
            if (a === null || b === null) return false;
            return a > b;
        }
        case 'LESS_THAN': {
            const a = numeric(actual);
            const b = numeric(value);
            if (a === null || b === null) return false;
            return a < b;
        }
        default:
            return false;
    }
}

function ruleHolds(rule, answers) {
    const conditions = Array.isArray(rule.conditions) ? rule.conditions : [];
    if (conditions.length === 0) {
        return false;
    }
    if (rule.logic === 'OR') {
        return conditions.some((c) => conditionHolds(c, answers));
    }
    // Default/AND: every documented rule set uses AND or OR explicitly, but an
    // unrecognized/missing `logic` value falls back to AND (the stricter,
    // safer default for a gating feature).
    return conditions.every((c) => conditionHolds(c, answers));
}

/**
 * Resolves the full set of `Rules_JSON__c`-shaped `rules` against
 * `answers` (a map of `Question_Key__c` -> current answer value), and
 * `knownKeys` (an optional iterable of every valid question/section key,
 * used only to flag unresolved `target`s in `warnings` — pass `null`/omit
 * to skip that check).
 *
 * Returns:
 *   {
 *     visible: Set<key>,   // keys explicitly SHOWn by a firing rule
 *     hidden: Set<key>,    // keys explicitly HIDden by a firing rule
 *     required: Set<key>,  // keys made required by a firing MAKE_REQUIRED rule
 *     nextSection: string|null, // last-writer-wins SKIP_TO_SECTION target, or null
 *     warnings: string[]   // human-readable, one entry per rule that could not
 *                           // be resolved (bad shape, unknown operator/action/
 *                           // logic, or an unresolved target) -- these rules
 *                           // are skipped individually, never a thrown error.
 *   }
 *
 * A question with no matching SHOW/HIDE rule at all is implicitly visible
 * per doc §3.2 ("no branching behavior — always shown"); callers combine
 * `visible`/`hidden` with each question's own authored default rather than
 * expecting this function to enumerate every question.
 */
export function evaluateRules(rules, answers, knownKeys) {
    const result = {
        visible: new Set(),
        hidden: new Set(),
        required: new Set(),
        nextSection: null,
        warnings: []
    };
    const list = toRulesArray(rules);
    const known = knownKeys ? new Set(knownKeys) : null;
    const ctx = answers || {};

    list.forEach((rule, index) => {
        if (!rule || typeof rule !== 'object') {
            result.warnings.push(`Rule at index ${index} is not a valid object and was skipped.`);
            return;
        }
        const { action, target } = rule;
        if (!ACTIONS.has(action)) {
            result.warnings.push(`Rule at index ${index} has an unrecognized action "${action}" and was skipped.`);
            return;
        }
        if (!target) {
            result.warnings.push(`Rule at index ${index} has no target and was skipped.`);
            return;
        }
        if (known && !known.has(target)) {
            result.warnings.push(
                `Rule at index ${index} targets unknown key "${target}" and was skipped.`
            );
            return;
        }
        const conditions = Array.isArray(rule.conditions) ? rule.conditions : [];
        const badOperator = conditions.find((c) => c && !OPERATORS.has(c.operator));
        if (badOperator) {
            result.warnings.push(
                `Rule at index ${index} has an unrecognized operator "${badOperator.operator}" and was skipped.`
            );
            return;
        }

        if (!ruleHolds(rule, ctx)) {
            return;
        }

        switch (action) {
            case 'SHOW':
                result.visible.add(target);
                break;
            case 'HIDE':
                result.hidden.add(target);
                break;
            case 'MAKE_REQUIRED':
                result.required.add(target);
                break;
            case 'SKIP_TO_SECTION':
                result.nextSection = target;
                break;
            default:
                break;
        }
    });

    return result;
}

/**
 * Walks the SHOW/HIDE target reference graph built from `rules` (each
 * condition `field` -> each SHOW/HIDE rule's `target` is treated as a
 * directed edge: "target's visibility depends on field's answer, and
 * field's own visibility rules chain onward from there") and reports any
 * cycle found. This is a static, save-time structural check (used by
 * sub-issue 04's editor before persisting) — it does not run as part of
 * `evaluateRules`'s per-answer runtime evaluation.
 *
 * Returns an array of cycles, each cycle a array of keys in traversal
 * order (e.g. `['q1', 'q2', 'q1']`). An acyclic rule set, an empty rule
 * set, or `null`/non-array input returns `[]`.
 */
export function detectCircularDependencies(rules) {
    const list = toRulesArray(rules);
    const edges = new Map(); // field -> Set(target)

    list.forEach((rule) => {
        if (!rule || typeof rule !== 'object') return;
        if (rule.action !== 'SHOW' && rule.action !== 'HIDE') return;
        const { target } = rule;
        if (!target) return;
        const conditions = Array.isArray(rule.conditions) ? rule.conditions : [];
        conditions.forEach((c) => {
            if (!c || !c.field) return;
            if (!edges.has(c.field)) {
                edges.set(c.field, new Set());
            }
            edges.get(c.field).add(target);
        });
    });

    const cycles = [];
    const visitedGlobal = new Set();

    function dfs(node, stack, onStack) {
        onStack.add(node);
        stack.push(node);

        const neighbors = edges.get(node);
        if (neighbors) {
            for (const next of neighbors) {
                if (onStack.has(next)) {
                    const cycleStart = stack.indexOf(next);
                    cycles.push([...stack.slice(cycleStart), next]);
                } else if (!visitedGlobal.has(next)) {
                    dfs(next, stack, onStack);
                }
            }
        }

        stack.pop();
        onStack.delete(node);
        visitedGlobal.add(node);
    }

    for (const node of edges.keys()) {
        if (!visitedGlobal.has(node)) {
            dfs(node, [], new Set());
        }
    }

    return cycles;
}

/**
 * Returns a new answers map with every key in `hiddenKeys` removed, so a
 * hidden question's stale answer doesn't silently persist into
 * scoring/branching once it's shown again or the instrument is saved.
 * Does not mutate `answers`. An empty/`null` `hiddenKeys` is a no-op copy.
 */
export function cleanupHiddenValues(answers, hiddenKeys) {
    const source = answers && typeof answers === 'object' ? answers : {};
    const hidden = hiddenKeys instanceof Set ? hiddenKeys : new Set(toRulesArray(hiddenKeys));
    const cleaned = {};
    Object.keys(source).forEach((key) => {
        if (!hidden.has(key)) {
            cleaned[key] = source[key];
        }
    });
    return cleaned;
}
