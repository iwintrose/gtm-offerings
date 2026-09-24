/**
 * Pure helpers for the Pages-tab filter set of gtmRepLinkFinder (Addendum C.3).
 * Everything here is CLIENT-SIDE over getMyConfigurations() rows and
 * getLinkStatsAura() stats already loaded by the component. No LWC imports so
 * it can be Jest-tested directly.
 */
import { formatLabel } from './gtmRepLinkTableModel';

/** key -> URL param. `c__offering` is reserved by gtmFilterUrlState; never use it. */
export const PAGES_PARAMS = {
    offering: 'c__poffering',
    sent: 'c__psent',
    industry: 'c__pindustry',
    deal: 'c__pdeal',
    account: 'c__pacct',
    contact: 'c__pcontact',
    active: 'c__pactive',
    last: 'c__plast',
    owner: 'c__powner'
};

export const EXTRA_KEYS = Object.keys(PAGES_PARAMS);

/** Option value for links whose industry matches no defined industry. */
export const INDUSTRY_OTHER = '__other__';

/** Normalise getIndustryProfiles() rows to { key -> label }. Blank keys dropped. */
export function industryMap(profiles) {
    const m = new Map();
    (profiles || []).forEach((p) => {
        if (p && p.industryKey && !String(p.industryKey).includes(',')) {
            m.set(String(p.industryKey), p.industryLabel || String(p.industryKey));
        }
    });
    return m;
}

/** Display label for a link's industry: the defined label when the value matches, else raw. */
export function industryDisplay(value, profiles) {
    if (!value) return '';
    const m = profiles instanceof Map ? profiles : industryMap(profiles);
    return m.get(String(value)) || String(value);
}

/** Options = defined industries, plus one 'Other' only when some link matches none. */
export function industryOptions(links, profiles, pendingRaw) {
    // profiles == null means the definitions have not loaded yet: keep any deep-linked raw
    // values selectable so URL state is not dropped before the read returns.
    if (profiles === null || profiles === undefined) {
        return (pendingRaw || []).filter((v) => !String(v).includes(',')).map((v) => ({ value: String(v), label: String(v) }));
    }
    const m = profiles instanceof Map ? profiles : industryMap(profiles);
    const opts = Array.from(m, ([value, label]) => ({ value, label })).sort((a, b) =>
        a.label.toLowerCase().localeCompare(b.label.toLowerCase())
    );
    if (opts.length && (links || []).some((l) => l.Industry__c && !m.has(String(l.Industry__c)))) {
        opts.push({ value: INDUSTRY_OTHER, label: 'Other' });
    }
    return opts;
}

const LINK_STATUS_OPTIONS = [
    { value: 'active', label: 'Active' },
    { value: 'inactive', label: 'Inactive' }
];

/** Raw c__p* values in the URL, split on commas, so a deep link is never dropped
 *  before the data (and therefore the option lists) has loaded. */
function rawValues(state, key) {
    const raw = state && state[PAGES_PARAMS[key]];
    return raw ? String(raw).split(',').filter(Boolean) : [];
}

/** Distinct { value, label } options; values with commas are skipped (URL contract). */
function collect(rows, valueOf, labelOf, extraRaw) {
    const seen = new Map();
    (rows || []).forEach((r) => {
        const v = valueOf(r);
        if (v && !String(v).includes(',') && !seen.has(String(v))) {
            seen.set(String(v), labelOf(r) || String(v));
        }
    });
    (extraRaw || []).forEach((v) => {
        if (!String(v).includes(',') && !seen.has(String(v))) seen.set(String(v), String(v));
    });
    return Array.from(seen, ([value, label]) => ({ value, label })).sort((a, b) =>
        a.label.toLowerCase().localeCompare(b.label.toLowerCase())
    );
}

/**
 * The extra Pages filters, in display order. Row (no `more`): Offering, Sent.
 * Under More: Industry, Deal stage, Account, Contact, Link status, Last visit
 * (only with complete stats), Owner (only with more than one distinct owner).
 *
 * @param {object} ctx { links, statsComplete, state, industries }  industries = getIndustryProfiles() rows  state = wired URL state
 */
export function buildExtraFilters(ctx) {
    const links = (ctx && ctx.links) || [];
    const state = (ctx && ctx.state) || {};
    const owners = new Set(links.map((l) => l.OwnerId).filter(Boolean));
    const list = [
        {
            key: 'offering', label: 'Offering', type: 'chips', multi: true, param: PAGES_PARAMS.offering,
            options: collect(links, (l) => l.Offering__c, (l) => formatLabel(l.Offering__c), rawValues(state, 'offering'))
        },
        { key: 'sent', label: 'Sent', type: 'date-range', param: PAGES_PARAMS.sent },
        {
            key: 'industry', label: 'Industry', type: 'chips', multi: true, more: true, param: PAGES_PARAMS.industry,
            options: industryOptions(links, ctx && ctx.industries, rawValues(state, 'industry'))
        },
        {
            key: 'deal', label: 'Deal stage', type: 'chips', multi: true, more: true, param: PAGES_PARAMS.deal,
            options: collect(links, (l) => l.Opportunity__r && l.Opportunity__r.StageName,
                (l) => l.Opportunity__r.StageName, rawValues(state, 'deal'))
        },
        {
            key: 'account', label: 'Account', type: 'chips', multi: true, more: true, searchable: true,
            param: PAGES_PARAMS.account,
            options: collect(links, (l) => l.Account__c,
                (l) => (l.Account__r && l.Account__r.Name) || l.Company__c, rawValues(state, 'account'))
        },
        {
            key: 'contact', label: 'Contact', type: 'chips', multi: true, more: true, searchable: true,
            param: PAGES_PARAMS.contact,
            options: collect(links, (l) => l.Contact__c, (l) => l.Contact__r && l.Contact__r.Name, rawValues(state, 'contact'))
        },
        {
            key: 'active', label: 'Link status', type: 'chips', more: true, param: PAGES_PARAMS.active,
            options: LINK_STATUS_OPTIONS
        }
    ];
    if (ctx && ctx.statsComplete) {
        list.push({ key: 'last', label: 'Last visit', type: 'date-range', more: true, param: PAGES_PARAMS.last });
    }
    if (owners.size > 1) {
        list.push({
            key: 'owner', label: 'Owner', type: 'chips', multi: true, more: true, param: PAGES_PARAMS.owner,
            options: collect(links, (l) => l.OwnerId, (l) => l.Owner && l.Owner.Name, rawValues(state, 'owner'))
        });
    }
    return list;
}

const DAY_MS = 86400000;

/** Preset token ('7' | '30' | '90') or { from, to } (ISO dates, inclusive). */
export function matchesDate(iso, value, now = Date.now()) {
    if (!iso) return false;
    const t = new Date(iso).getTime();
    if (Number.isNaN(t)) return false;
    if (typeof value === 'string') {
        const days = parseInt(value, 10);
        return Number.isFinite(days) && t >= now - days * DAY_MS;
    }
    if (value && value.from && value.to) {
        const d = String(iso).slice(0, 10);
        return d >= value.from && d <= value.to;
    }
    return true;
}

function inList(list, v) {
    return Array.isArray(list) ? list.map(String).includes(String(v)) : true;
}

function matchesIndustry(value, selected, industries) {
    if (!Array.isArray(selected)) return true;
    const sel = selected.map(String);
    if (value && sel.includes(String(value))) return true;
    if (sel.includes(INDUSTRY_OTHER)) {
        return !!value && !industryMap(industries).has(String(value));
    }
    return false;
}

/** Does one saved link (plus its stat row) satisfy every ACTIVE extra filter? */
export function matchesExtra(link, stat, values, now = Date.now(), industries = null) {
    const v = values || {};
    if (v.offering && !inList(v.offering, link.Offering__c)) return false;
    if (v.industry && !matchesIndustry(link.Industry__c, v.industry, industries)) return false;
    if (v.deal && !inList(v.deal, link.Opportunity__r && link.Opportunity__r.StageName)) return false;
    if (v.account && !inList(v.account, link.Account__c)) return false;
    if (v.contact && !inList(v.contact, link.Contact__c)) return false;
    if (v.owner && !inList(v.owner, link.OwnerId)) return false;
    if (v.active === 'active' && link.Active__c === false) return false;
    if (v.active === 'inactive' && link.Active__c !== false) return false;
    if (v.sent && !matchesDate(link.CreatedDate, v.sent, now)) return false;
    if (v.last && !matchesDate(stat && stat.lastVisitAt, v.last, now)) return false;
    return true;
}

export function hasExtraActive(values) {
    return EXTRA_KEYS.some((k) => {
        const v = values && values[k];
        return v !== undefined && v !== null && v !== '' && !(Array.isArray(v) && v.length === 0);
    });
}

/** Keep only the extra-filter entries of a values map. */
export function extraValuesOnly(values) {
    const out = {};
    EXTRA_KEYS.forEach((k) => {
        if (values && values[k] !== undefined) out[k] = values[k];
    });
    return out;
}

export function filterLinks(links, stats, values, now = Date.now(), industries = null) {
    if (!hasExtraActive(values)) return links;
    const byId = new Map();
    (stats || []).forEach((s) => byId.set(s.linkId, s));
    return (links || []).filter((l) => matchesExtra(l, byId.get(l.Id), values, now, industries));
}

/**
 * Legacy deep-link mapping (Addendum C.9.3, Release 2). Overview drill-ins and old
 * bookmarks carry `c__rlfAccountId` / `c__rlfContactId` (no link id): they mean "show
 * that account's / contact's links", i.e. the Account / Contact filters. With a
 * `c__rlfLinkId` the three ids are the detail-view deep link and are left alone.
 * `c__rlfMode` is ignored everywhere. An explicit `c__pacct` / `c__pcontact` wins.
 * Returns { state, mapped } where `mapped` is true when a filter param was added.
 */
export function mapLegacyParams(state) {
    const s = { ...(state || {}) };
    let mapped = false;
    if (!s.c__rlfLinkId) {
        if (s.c__rlfAccountId && !s[PAGES_PARAMS.account]) {
            s[PAGES_PARAMS.account] = s.c__rlfAccountId;
            mapped = true;
        }
        if (s.c__rlfContactId && !s[PAGES_PARAMS.contact]) {
            s[PAGES_PARAMS.contact] = s.c__rlfContactId;
            mapped = true;
        }
    }
    return { state: s, mapped };
}

/**
 * Base state for a filter navigation: drops c__rlfMode, the legacy account/contact ids
 * (no link id) and any c__rlf* param the browser URL no longer carries (a stale wired
 * state after "Back to links" would otherwise reopen the detail view).
 */
export function cleanNavigateBase(state, search) {
    const s = { ...(state || {}) };
    let loc = search;
    if (loc === undefined && typeof window !== 'undefined' && window.location) loc = window.location.search;
    const params = new URLSearchParams(loc || '');
    Object.keys(s).forEach((k) => {
        if (k.startsWith('c__rlf') && !params.has(k)) delete s[k];
    });
    delete s.c__rlfMode;
    if (!s.c__rlfLinkId) {
        delete s.c__rlfAccountId;
        delete s.c__rlfContactId;
    }
    return s;
}
