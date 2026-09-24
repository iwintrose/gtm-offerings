/**
 * The instrument's predicate language, in the browser.
 *
 * A deliberate third implementation of GtmPredicate.cls (the second is the
 * Python mirror in scripts/build-instrument.py, which uses it to prove at build
 * time that every authored branch is reachable). Three copies of a grammar is
 * normally a smell; here it is the cheaper of two bad options. The alternative
 * is a round trip to Apex on every answer so the questionnaire can decide what
 * to ask next, which turns a form into a series of spinners on the phone of
 * someone who is already half-inclined to close the tab.
 *
 * What makes it safe is that this copy is ADVISORY. It decides what to render;
 * it never decides what scores. GtmAssessmentRequestController re-resolves the
 * same branches server-side from the submitted answers, and an answer submitted
 * under a key the server did not resolve is never read. A divergence here shows
 * up as an unanswered slot, not as a wrong score.
 *
 * The grammar, identical in all three:
 *
 *     {all: [clause, ...]} | {any: [clause, ...]} | {field, op, value}
 *     op :: eq | ne | lt | lte | gt | gte | in | not_in
 *
 * And the two rules that carry the weight, also identical in all three:
 *   - a field with no value in the context makes its clause FALSE, so a branch
 *     that depends on an unanswered question leaves the default question
 *     standing and the slot stays filled;
 *   - numbers compare as numbers, everything else as trimmed, case-insensitive
 *     text, so a predicate authored as "3" and an answer of 3 agree.
 */

const NUMERIC = (value) =>
    typeof value === 'number' && Number.isFinite(value) ? value : null;

function equalish(a, b) {
    const na = NUMERIC(a);
    const nb = NUMERIC(b);
    if (na !== null && nb !== null) {
        return na === nb;
    }
    if (a === null || a === undefined || b === null || b === undefined) {
        return false;
    }
    return String(a).trim().toLowerCase() === String(b).trim().toLowerCase();
}

/** True when `node` holds against `context`. Malformed input is false, never a throw. */
export function matches(node, context) {
    const ctx = context || {};
    if (!node || typeof node !== 'object' || Array.isArray(node)) {
        return false;
    }
    if (Object.prototype.hasOwnProperty.call(node, 'all')) {
        const children = Array.isArray(node.all) ? node.all : [];
        return children.every((child) => matches(child, ctx));
    }
    if (Object.prototype.hasOwnProperty.call(node, 'any')) {
        const children = Array.isArray(node.any) ? node.any : [];
        return children.some((child) => matches(child, ctx));
    }

    const actual = ctx[node.field];
    if (actual === null || actual === undefined) {
        return false;
    }
    const { op } = node;
    const expected = node.value;

    if (op === 'in' || op === 'not_in') {
        const list = Array.isArray(expected) ? expected : [];
        const found = list.some((candidate) => equalish(actual, candidate));
        return op === 'in' ? found : !found;
    }
    if (op === 'eq') return equalish(actual, expected);
    if (op === 'ne') return !equalish(actual, expected);

    const a = NUMERIC(actual);
    const b = NUMERIC(expected);
    if (a === null || b === null) {
        return false;
    }
    if (op === 'lt') return a < b;
    if (op === 'lte') return a <= b;
    if (op === 'gt') return a > b;
    if (op === 'gte') return a >= b;
    return false;
}

/** Parses a predicate string. Unusable JSON is null, which leaves a branch inert. */
export function parse(json) {
    if (!json) {
        return null;
    }
    try {
        return JSON.parse(json);
    } catch (e) {
        return null;
    }
}

/**
 * Walks a resolved pack's slots in position order and returns the eight
 * questions THIS respondent is asked, given the answers so far.
 *
 * The mirror of GtmAssessmentInstrument.applyBranches, and the same guarantee:
 * every slot resolves to exactly one question, because a variant is a complete
 * slot and the default is always there to fall back to. The returned array is
 * always the same length as `pack.slots` — that is the invariant this function
 * exists to make visible in one place rather than spread across a template.
 */
export function resolveSlots(pack, answers) {
    if (!pack || !Array.isArray(pack.slots)) {
        return [];
    }
    const given = answers || {};
    const context = { source: pack.sourceKey, target: pack.targetKey };
    return pack.slots.map((slot) => {
        let chosen = slot;
        const variants = Array.isArray(slot.variants) ? slot.variants : [];
        for (let i = 0; i < variants.length; i++) {
            const v = variants[i];
            if (!v.showWhenJson) continue;
            if (matches(parse(v.showWhenJson), context)) {
                chosen = v;
                break;
            }
        }
        const value = given[chosen.key];
        if (value !== null && value !== undefined) {
            context[chosen.baseKey] = value;
            context[chosen.key] = value;
        }
        return chosen;
    });
}

/**
 * The points an answer is worth on a slot, defaulting to the option's own value
 * — the same fallback GtmAssessmentScoring applies when a pack has no authored
 * points. Used only for the author's preview and the respondent's own running
 * total; nothing the client computes is ever stored.
 */
export function pointsFor(slot, value) {
    if (!slot || !Array.isArray(slot.options) || value === null || value === undefined) {
        return null;
    }
    const option = slot.options.find((o) => o.value === value);
    if (!option) return null;
    return option.points === null || option.points === undefined ? option.value : option.points;
}
