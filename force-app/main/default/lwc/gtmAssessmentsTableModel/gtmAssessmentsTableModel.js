/**
 * Pure model for the "All Assessments" table in gtmReadoutsOverview: the
 * shared-filter-bar config, datatable columns, server-row to datatable-row
 * mapping and the Apex query builder. No DOM, no Apex, no navigation.
 *
 * NO FILTER LOGIC LIVES HERE. Option keys/labels are declarations of the
 * server's vocabulary (GtmAssessmentListController); the preset expansion,
 * tier ranking, readout semantics and date maths are server-only.
 * Contract: docs/architecture/gtm-assessments-table.md.
 */

export const PAGE_SIZE = 50;
export const CAPPED_TOTAL_TEXT = '10,000+';

// ---- ONE label map per vocabulary, shared by the filter options AND the table
// column, so an option can never say something the column does not (filter-data
// tie audit). Keys mirror the server vocabularies in GtmAssessmentListController
// (STATUS_BY_KEY, TIER_BY_KEY, READOUT_KEYS); a Jest spec compares them.

export const STATUS_LABEL_BY_KEY = {
    new: 'New',
    contacted: 'Contacted',
    scheduled: 'Scheduled',
    completed: 'Completed',
    'no-show': 'No Show'
};

export const TIER_LABEL_BY_KEY = {
    'fast-track': 'Fast-Track',
    'accelerator-ready': 'Accelerator-Ready',
    'prep-required': 'Prep Required',
    'discovery-first': 'Discovery First'
};

export const READOUT_LABEL_BY_KEY = {
    none: 'None yet',
    draft: 'Draft',
    pending: 'Waiting on approval',
    'approved-unsent': 'Approved, not sent',
    'approved-sent': 'Approved, sent',
    published: 'Published'
};

const toOptions = (map) => Object.keys(map).map((value) => ({ value, label: map[value] }));

export const STATUS_OPTIONS = toOptions(STATUS_LABEL_BY_KEY);
export const TIER_OPTIONS = toOptions(TIER_LABEL_BY_KEY);
export const READOUT_OPTIONS = toOptions(READOUT_LABEL_BY_KEY);

/** "migration-accelerator" -> "Migration Accelerator": the Offering option label AND column text. */
export function formatOfferingLabel(key) {
    if (!key) return '';
    return String(key)
        .split(/[-_]/)
        .map((w) => (w ? w[0].toUpperCase() + w.slice(1) : w))
        .join(' ');
}

/** Mirror of GtmAssessmentListController.readoutKeyFor ('approved-sent' added with #245). */
export function readoutKeyFor(row) {
    const status = row && row.readoutStatus;
    if (!status) return 'none';
    if (status === 'Draft') return 'draft';
    if (status === 'Pending Approval') return 'pending';
    if (status === 'Published') return 'published';
    if (status === 'Approved') return row.readoutNotificationSent ? 'approved-sent' : 'approved-unsent';
    return '';
}

/** The Readout column text: the SAME label the Readout filter option uses. */
export function readoutLabelFor(row) {
    const key = readoutKeyFor(row);
    if (key) return READOUT_LABEL_BY_KEY[key];
    return (row && row.readoutStatus) || READOUT_LABEL_BY_KEY.none; // Approved and already sent: no option yet
}

export const FILTER_KEYS = ['status', 'tier', 'readout', 'range', 'offering', 'preset', 'account', 'contact'];

/**
 * @param {string[]} offeringOptions Offering_Key__c values from the server
 * @param {string[]} extraOfferingValues values already in the URL, kept in the
 *   options so gtmFilterUrlState.readFilterState does not drop them before the
 *   first response has told us what the offering options are
 * @param {{account?: object[], contact?: object[]}} [partyOptions] server-served
 *   {value,label,hint?} options for the searchable Account and Contact filters
 *   (getAssessmentFilterOptions); the caller keeps restored/selected ids in them
 */
export function buildFilterConfig(offeringOptions, extraOfferingValues, partyOptions) {
    const party = partyOptions || {};
    const offerings = [];
    [...(offeringOptions || []), ...(extraOfferingValues || [])].forEach((v) => {
        // Option values must not contain commas (gtm-filter-bar.md section 3).
        if (v && !String(v).includes(',') && !offerings.includes(v)) offerings.push(v);
    });
    return [
        { key: 'preset', label: 'Ready to book', type: 'toggle', param: 'c__apreset', more: true },
        { key: 'status', label: 'Status', type: 'chips', multi: true, param: 'c__astatus', options: STATUS_OPTIONS },
        { key: 'tier', label: 'Readiness tier', type: 'chips', multi: true, param: 'c__atier', options: TIER_OPTIONS },
        { key: 'readout', label: 'Readout', type: 'chips', multi: true, param: 'c__areadout', options: READOUT_OPTIONS, more: true },
        { key: 'range', label: 'Submitted', type: 'date-range', param: 'c__arange' },
        {
            key: 'offering',
            label: 'Offering',
            type: 'chips',
            multi: true,
            param: 'c__aoffering',
            more: true,
            options: offerings.map((v) => ({ value: v, label: formatOfferingLabel(v) }))
        },
        {
            key: 'account',
            label: 'Account',
            type: 'chips',
            multi: true,
            param: 'c__aacct',
            more: true,
            searchable: true,
            serverSearch: true,
            options: (party.account || []).filter((o) => o && o.value && !String(o.value).includes(','))
        },
        {
            key: 'contact',
            label: 'Contact',
            type: 'chips',
            multi: true,
            param: 'c__acontact',
            more: true,
            searchable: true,
            serverSearch: true,
            options: (party.contact || []).filter((o) => o && o.value && !String(o.value).includes(','))
        }
    ];
}

/** Raw offering keys from the c__aoffering param (comma separated). */
export function rawOfferingValues(state) {
    const raw = state && state.c__aoffering;
    return raw ? String(raw).split(',').filter(Boolean) : [];
}

/** Ids from a comma-separated c__aacct / c__acontact param (plus legacy-mapped ids). */
export function rawIds(state, param) {
    const raw = state && state[param];
    return raw ? String(raw).split(',').filter(Boolean) : [];
}

/** Server FilterOption {value,label,sublabel} -> bar option; the sublabel rides in the label. */
export function toPartyOption(o) {
    const opt = o || {};
    const label = opt.label || opt.value || '';
    return { value: opt.value, label: opt.sublabel ? `${label} (${opt.sublabel})` : label };
}

/** Options for one party filter: the fetched list plus every selected/restored id (labelled
 *  from `known` when it was fetched, else the id itself), de-duplicated, selected kept. */
export function mergePartyOptions(fetched, selectedIds, known) {
    const out = [];
    const seen = new Set();
    const add = (o) => {
        if (o && o.value && !seen.has(o.value)) {
            seen.add(o.value);
            out.push(o);
        }
    };
    (selectedIds || []).forEach((id) => add((known && known[id]) || { value: id, label: id }));
    (fetched || []).forEach(add);
    return out;
}

/** datatable sortedBy field name -> server sortBy key. */
export const SORT_KEY_BY_FIELD = {
    contactLabel: 'contact',
    companyLabel: 'company',
    tierLabel: 'tier',
    score: 'score',
    requestStatus: 'status',
    readoutLabel: 'readout',
    submittedAt: 'submitted'
};

const FIELD_BY_SORT_KEY = Object.keys(SORT_KEY_BY_FIELD).reduce((acc, f) => {
    acc[SORT_KEY_BY_FIELD[f]] = f;
    return acc;
}, {});

export function sortKeyForField(fieldName) {
    return SORT_KEY_BY_FIELD[fieldName] || '';
}

export function fieldForSortKey(sortKey) {
    return FIELD_BY_SORT_KEY[sortKey] || '';
}

export const COLUMNS = [
    {
        label: 'Assessment',
        type: 'button',
        fieldName: 'name',
        initialWidth: 120,
        typeAttributes: { label: { fieldName: 'name' }, name: 'open', variant: 'base', title: 'Open assessment' }
    },
    {
        // Shared "gtmLink" cell type (gtmLinkDatatable / gtmLinkCell): renders
        // consistently whether or not the row has a real contact/account id --
        // see docs/architecture/gtm-assessments-table.md "Contact/Account cell".
        label: 'Contact',
        fieldName: 'contactLabel',
        type: 'gtmLink',
        sortable: true,
        typeAttributes: {
            label: { fieldName: 'contactLabel' },
            name: 'openContact',
            disabled: { fieldName: 'contactDisabled' },
            title: { fieldName: 'contactTitle' },
            targetId: { fieldName: 'contactId' },
            idField: 'contactId'
        }
    },
    {
        label: 'Account',
        fieldName: 'companyLabel',
        type: 'gtmLink',
        sortable: true,
        typeAttributes: {
            label: { fieldName: 'companyLabel' },
            name: 'openAccount',
            disabled: { fieldName: 'companyDisabled' },
            title: { fieldName: 'companyTitle' },
            targetId: { fieldName: 'accountId' },
            idField: 'accountId',
            showBackfillHint: { fieldName: 'accountBackfillHint' }
        }
    },
    {
        label: 'Readiness tier',
        fieldName: 'tierLabel',
        type: 'text',
        sortable: true,
        cellAttributes: { class: { fieldName: 'tierClass' }, iconName: { fieldName: 'tierIcon' } }
    },
    { label: 'Score', fieldName: 'score', type: 'number', sortable: true, initialWidth: 90 },
    {
        label: 'Request status',
        fieldName: 'requestStatus',
        type: 'text',
        sortable: true
    },
    {
        label: 'Readout',
        fieldName: 'readoutLabel',
        type: 'text',
        sortable: true,
        cellAttributes: { class: { fieldName: 'readoutClass' }, iconName: { fieldName: 'readoutIcon' } }
    },
    {
        label: 'Submitted',
        fieldName: 'submittedAt',
        type: 'date',
        sortable: true,
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
    }
];

/** Offering catalogue column (after the existing ones). COLUMNS itself is unchanged so the
 *  Overview results card, which imports it, renders exactly what it did. */
export const OFFERING_COLUMN = {
    label: 'Offering',
    fieldName: 'offeringLabel',
    type: 'text',
    sortable: false
};

/** Rep-language labels for the trailing row-action menu (name -> label). */
export const ROW_ACTION_LABELS = {
    open: 'Open assessment',
    openContact: 'Open contact',
    openAccount: 'Open account'
};

/** Native row-action menu (same pattern as the Pages table): Open assessment
 *  first, then the contact / account for context. Items without an id are
 *  disabled with the reason in the label (native menu items have no tooltip). */
export function getRowActions(row, doneCallback) {
    doneCallback([
        { label: ROW_ACTION_LABELS.open, name: 'open' },
        {
            label: row.contactId ? ROW_ACTION_LABELS.openContact : 'Open contact (none on this assessment)',
            name: 'openContact',
            disabled: !row.contactId
        },
        {
            label: row.accountId ? ROW_ACTION_LABELS.openAccount : 'Open account (none on this assessment)',
            name: 'openAccount',
            disabled: !row.accountId
        }
    ]);
}

export const ACTION_COLUMN = { type: 'action', typeAttributes: { rowActions: getRowActions } };

/** COLUMNS plus the catalogue columns and the trailing (right-hand) row-action
 *  menu: what the All Assessments table renders. */
export const TABLE_COLUMNS = [...COLUMNS, OFFERING_COLUMN, ACTION_COLUMN];

const TIER_STYLE = {
    'Fast-Track': { cls: 'slds-text-color_success slds-text-title_bold', icon: 'utility:success' },
    'Accelerator-Ready': { cls: 'slds-text-color_success', icon: 'utility:success' },
    'Prep Required': { cls: 'slds-text-color_default', icon: 'utility:warning' },
    'Discovery First': { cls: 'slds-text-color_weak', icon: 'utility:info' }
};

const READOUT_STYLE = {
    Draft: { cls: 'slds-text-color_default', icon: 'utility:edit' },
    'Pending Approval': { cls: 'slds-text-color_default', icon: 'utility:approval' },
    Approved: { cls: 'slds-text-color_success', icon: 'utility:check' },
    Published: { cls: 'slds-text-color_success', icon: 'utility:success' }
};

/** Server AssessmentRow -> datatable row (never blank when the row has data). */
export function mapRow(r) {
    const row = r || {};
    const contactLabel = row.contactName || row.requesterName || row.company || row.name || '';
    const companyLabel = row.company || '';
    const tier = TIER_STYLE[row.tier];
    const readout = READOUT_STYLE[row.readoutStatus];
    return {
        recordId: row.recordId,
        name: row.name || '',
        contactId: row.contactId || '',
        accountId: row.accountId || '',
        contactLabel,
        contactDisabled: !row.contactId,
        contactTitle: row.contactId ? 'Open contact' : 'No contact on this assessment',
        companyLabel: companyLabel || (row.accountId ? '' : '—'),
        companyDisabled: !row.accountId,
        companyTitle: row.accountId ? 'Open account' : 'No account on this assessment',
        // Visibility-only nudge (issue-11): pass through the server-computed
        // "has Company__c but no Account__c" flag so the gtmLinkCell can
        // surface the backfill hint on this table too.
        accountBackfillHint: !!row.accountBackfillHint,
        tierLabel: row.tier || '—',
        tierClass: tier ? tier.cls : 'slds-text-color_weak',
        tierIcon: tier ? tier.icon : '',
        score: row.score === undefined ? null : row.score,
        requestStatus: row.requestStatus || '',
        readoutId: row.readoutId || '',
        readoutLabel: readoutLabelFor(row),
        readoutClass: readout ? readout.cls : 'slds-text-color_weak',
        readoutIcon: readout ? readout.icon : '',
        offeringKey: row.offeringKey || '',
        offeringLabel: formatOfferingLabel(row.offeringKey) || '—',
        submittedAt: row.submittedAt || row.createdDate || null
    };
}

/** gtmFilterUrlState values map -> the Apex AssessmentQuery shape. */
/** Plain-array copy (defeats LWC reactive Proxies, which Aura serialises as empty). */
const plainList = (x) => (x && typeof x.length === 'number' && typeof x !== 'string' ? Array.from(x, (i) => String(i)) : []);

/** Deep-plain a param object right before an Apex call (drops any Proxy wrappers). */
export function toPlain(obj) {
    return JSON.parse(JSON.stringify(obj));
}

export function buildQuery(values, sort, offset, pageSize) {
    const v = values || {};
    const range = v.range;
    const query = {
        status: plainList(v.status),
        tier: plainList(v.tier),
        readout: plainList(v.readout),
        offering: plainList(v.offering),
        accountIds: plainList(v.account),
        contactIds: plainList(v.contact),
        range: range && typeof range === 'object' ? `${range.from}..${range.to}` : range || null,
        preset: v.preset === true ? 'ready-to-book' : null,
        offset: offset || 0,
        pageSize: pageSize || PAGE_SIZE
    };
    if (sort && sort.sortBy) {
        query.sortBy = sort.sortBy;
        query.sortDir = sort.sortDir === 'desc' ? 'desc' : 'asc';
    }
    return toPlain(query);
}

export function hasActiveFilters(values) {
    const v = values || {};
    return Object.keys(v).some((k) => {
        const x = v[k];
        if (Array.isArray(x)) return x.length > 0;
        return x !== undefined && x !== null && x !== '' && x !== false;
    });
}

export function formatTotal(totalCount, totalIsCapped) {
    if (totalIsCapped) return CAPPED_TOTAL_TEXT;
    return String(totalCount || 0);
}
