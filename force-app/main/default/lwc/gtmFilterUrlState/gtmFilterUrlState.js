/**
 * Pure URL-state helpers for gtmFilterBar configs. No navigation, no DOM
 * writes. See docs/architecture/gtm-filter-bar.md.
 */

export const RESERVED_PARAMS = [
    'c__assessmentRequestId',
    'c__readoutId',
    'c__offeringKey',
    'c__browseMode',
    'c__repDirectId',
    'c__rafAccountId',
    'c__rafContactId',
    'c__template',
    'c__recordId',
    'c__company',
    'c__offering'
];
const RESERVED_PREFIXES = ['c__rlf'];

export const DEFAULT_DATE_PRESETS = ['7', '30', '90'];
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function isReserved(param) {
    return (
        RESERVED_PARAMS.includes(param) ||
        RESERVED_PREFIXES.some((p) => param.startsWith(p))
    );
}

function optionValues(filter) {
    return (filter.options || []).map((o) => String(o.value));
}

function presetValues(filter) {
    return filter.options && filter.options.length
        ? optionValues(filter)
        : DEFAULT_DATE_PRESETS;
}

function problemsFor(filter) {
    const problems = [];
    const param = filter && filter.param;
    if (!filter || !filter.key) problems.push('filter is missing a key');
    if (typeof param !== 'string' || !param.startsWith('c__') || param.length <= 3) {
        problems.push(`param "${param}" must start with c__`);
    } else if (isReserved(param)) {
        problems.push(`param "${param}" collides with a reserved param`);
    }
    if (filter && filter.type !== 'date-range') {
        const bad = optionValues(filter).filter((v) => v.includes(','));
        if (bad.length) problems.push(`option values must not contain commas: ${bad}`);
    }
    return problems;
}

/** Returns a list of human-readable problems (empty when valid). */
export function validateFilters(filters) {
    const problems = [];
    const seenParams = new Set();
    (filters || []).forEach((f) => {
        problemsFor(f).forEach((p) => problems.push(`${(f && f.key) || '?'}: ${p}`));
        if (f && f.param) {
            if (seenParams.has(f.param)) problems.push(`${f.key}: duplicate param ${f.param}`);
            seenParams.add(f.param);
        }
    });
    return problems;
}

/** Throws on an invalid config (dev/test). Read/build skip invalid filters instead. */
export function assertValidFilters(filters) {
    const problems = validateFilters(filters);
    if (problems.length) throw new Error(`Invalid filter config: ${problems.join('; ')}`);
}

function usable(filters) {
    return (filters || []).filter((f) => f && problemsFor(f).length === 0);
}

function isRealDate(s) {
    if (!ISO_DATE.test(s)) return false;
    const d = new Date(`${s}T00:00:00Z`);
    return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

function parseDateRange(raw, filter) {
    if (presetValues(filter).includes(raw)) return raw;
    const parts = raw.split('..');
    if (parts.length !== 2) return undefined;
    const [from, to] = parts;
    if (!isRealDate(from) || !isRealDate(to) || from > to) return undefined;
    return { from, to };
}

function parseOne(raw, filter) {
    if (raw === undefined || raw === null || raw === '') return undefined;
    const str = String(raw);
    switch (filter.type) {
        case 'toggle':
            return str === 'true' ? true : undefined;
        case 'date-range':
            return parseDateRange(str, filter);
        case 'chips':
            if (filter.multi) {
                const wanted = new Set(str.split(','));
                const list = optionValues(filter).filter((v) => wanted.has(v));
                return list.length ? list : undefined;
            }
            return optionValues(filter).includes(str) ? str : undefined;
        case 'select':
            return optionValues(filter).includes(str) ? str : undefined;
        default:
            return undefined;
    }
}

function serialiseOne(value, filter) {
    if (value === undefined || value === null || value === '' || value === false) return undefined;
    switch (filter.type) {
        case 'toggle':
            return value === true ? 'true' : undefined;
        case 'date-range':
            if (typeof value === 'string') {
                return presetValues(filter).includes(value) ? value : undefined;
            }
            if (value && isRealDate(value.from) && isRealDate(value.to) && value.from <= value.to) {
                return `${value.from}..${value.to}`;
            }
            return undefined;
        case 'chips':
            if (filter.multi) {
                const arr = Array.isArray(value) ? value.map(String) : [String(value)];
                const list = optionValues(filter).filter((v) => arr.includes(v));
                return list.length ? list.join(',') : undefined;
            }
            return optionValues(filter).includes(String(value)) ? String(value) : undefined;
        case 'select':
            return optionValues(filter).includes(String(value)) ? String(value) : undefined;
        default:
            return undefined;
    }
}

function sameValue(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
}

/** Wired page-reference state -> values map (only valid, non-empty values; defaults applied). */
export function readFilterState(state, filters) {
    const src = state || {};
    const values = {};
    usable(filters).forEach((f) => {
        const parsed = parseOne(src[f.param], f);
        if (parsed !== undefined) values[f.key] = parsed;
        else if (f.defaultValue !== undefined) values[f.key] = f.defaultValue;
    });
    return values;
}

/** Returns a NEW state: the config's own params rebuilt, every other key untouched. */
export function buildFilterUrlState(currentState, filters, values) {
    const next = { ...(currentState || {}) };
    const vals = values || {};
    usable(filters).forEach((f) => {
        delete next[f.param];
        const value = vals[f.key];
        if (f.defaultValue !== undefined && sameValue(value, f.defaultValue)) return;
        const out = serialiseOne(value, f);
        if (out !== undefined) next[f.param] = out;
    });
    return next;
}

/** Overlays every c__* param in window.location.search onto the wired state. */
export function mergeLocationState(pageRefState) {
    const merged = { ...(pageRefState || {}) };
    if (typeof window === 'undefined' || !window.location) return merged;
    const params = new URLSearchParams(window.location.search || '');
    params.forEach((value, key) => {
        if (key.startsWith('c__')) merged[key] = value;
    });
    return merged;
}

/**
 * Args for `this[NavigationMixin.Navigate](pageReference, replace)`.
 * `currentState` (e.g. mergeLocationState(pageRef.state)) defaults to pageRef.state.
 */
export function buildNavigateArgs(pageRef, filters, values, options = {}) {
    const { mode = 'replace', currentState } = options;
    const ref = pageRef || {};
    const base = currentState !== undefined ? currentState : ref.state;
    return {
        pageReference: {
            ...ref,
            type: ref.type,
            attributes: ref.attributes ? { ...ref.attributes } : ref.attributes,
            state: buildFilterUrlState(base, filters, values)
        },
        replace: mode !== 'push'
    };
}
