/**
 * Pure helpers for the Pages-tab table (all mode) of gtmRepLinkFinder.
 * Contract: docs/architecture/gtm-link-stage-filter.md ("Pages table").
 * No LWC imports so it can be Jest-tested directly.
 */

export const NO_ACCOUNT_TITLE = 'No account on this link; nothing to open';
export const NO_ACCOUNT_ACTION_LABEL = 'Open (no account on this link)';

export const FUNNEL_LABELS = {
    not_opened: 'Not opened',
    engaged: 'Prospect engaged',
    started: 'Assessment started',
    submitted: 'Assessment submitted'
};
export const FUNNEL_RANK = { not_opened: 0, engaged: 1, started: 2, submitted: 3 };
const FUNNEL_CLASS = {
    submitted: 'slds-text-color_success',
    not_opened: 'slds-text-color_weak'
};

export const DATE_TYPE_ATTRIBUTES = {
    year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit'
};

/** "migration-accelerator" -> "Migration Accelerator". */
export function formatLabel(slug) {
    if (!slug) return slug;
    return slug
        .split(/[-_]/)
        .map((w) => (w ? w[0].toUpperCase() + w.slice(1) : w))
        .join(' ');
}

const BASE_COLUMNS_BEFORE_OWNER = [
    {
        label: 'Page', fieldName: 'scNumber', type: 'button', sortable: true, initialWidth: 110,
        typeAttributes: {
            label: { fieldName: 'scNumber' }, name: 'open', variant: 'base',
            disabled: { fieldName: 'openDisabled' }, title: { fieldName: 'openTitle' }
        }
    },
    {
        // Shared "gtmLink" cell type (gtmLinkDatatable / gtmLinkCell): renders
        // consistently whether or not the row has a real Account__c lookup --
        // see docs/architecture/gtm-link-stage-filter.md "Account/Contact cell".
        label: 'Account', fieldName: 'company', type: 'gtmLink', sortable: true,
        typeAttributes: {
            label: { fieldName: 'company' }, name: 'openAccount',
            disabled: { fieldName: 'accountDisabled' }, title: { fieldName: 'accountTitle' },
            targetId: { fieldName: 'accountId' }, idField: 'accountId',
            showBackfillHint: { fieldName: 'accountBackfillHint' }
        }
    },
    {
        label: 'Contact', fieldName: 'contactName', type: 'gtmLink', sortable: true,
        typeAttributes: {
            label: { fieldName: 'contactName' }, name: 'openContact',
            disabled: { fieldName: 'contactDisabled' }, title: { fieldName: 'contactTitle' },
            targetId: { fieldName: 'contactId' }, idField: 'contactId'
        }
    },
    { label: 'Offering', fieldName: 'offeringLabel', type: 'text', sortable: true },
    { label: 'Opportunity', fieldName: 'opportunityName', type: 'text', sortable: true },
    {
        label: 'Funnel stage', fieldName: 'funnelLabel', type: 'text', sortable: true,
        cellAttributes: { class: { fieldName: 'funnelClass' } }
    },
    { label: 'Visits', fieldName: 'visits', type: 'number', sortable: true, initialWidth: 90 },
    {
        label: 'Last visit', fieldName: 'lastVisitAt', type: 'date', sortable: true,
        typeAttributes: DATE_TYPE_ATTRIBUTES
    },
    {
        label: 'Status', fieldName: 'statusLabel', type: 'text', sortable: true, initialWidth: 100,
        cellAttributes: { class: { fieldName: 'statusClass' } }
    },
    {
        label: 'Saved', fieldName: 'createdDate', type: 'date', sortable: true,
        typeAttributes: DATE_TYPE_ATTRIBUTES
    }
];
/** Proposed default-visible set (<= 5, docs/architecture/gtm-column-chooser.md convention). */
export const DEFAULT_VISIBLE_FIELDS = ['scNumber', 'company', 'contactName', 'funnelLabel', 'lastVisitAt'];

const OWNER_COLUMN = { label: 'Owner', fieldName: 'ownerName', type: 'text', sortable: true };
// Catalogue columns for the Industry and Deal stage filters (added after the existing ones).
const INDUSTRY_COLUMN = { label: 'Industry', fieldName: 'industryLabel', type: 'text', sortable: true };
const DEAL_STAGE_COLUMN = { label: 'Deal stage', fieldName: 'dealStage', type: 'text', sortable: true };

/** Native row-action menu: Open, Copy link, New password, Turn off / Turn on.
 *  Native menu items have no tooltip, so the reason goes in the label. */
export function getRowActions(row, doneCallback) {
    doneCallback([
        {
            label: row.openDisabled ? NO_ACCOUNT_ACTION_LABEL : 'Open',
            name: 'open',
            disabled: !!row.openDisabled
        },
        { label: 'Copy link', name: 'copy', disabled: !row.generatedUrl },
        { label: 'New password', name: 'password' },
        { label: row.statusLabel === 'Inactive' ? 'Turn on' : 'Turn off', name: 'toggle' }
    ]);
}

export function buildColumns(showOwner) {
    const cols = BASE_COLUMNS_BEFORE_OWNER.slice();
    if (showOwner) cols.push(OWNER_COLUMN);
    cols.push(INDUSTRY_COLUMN, DEAL_STAGE_COLUMN);
    cols.push({ type: 'action', typeAttributes: { rowActions: getRowActions } });
    return cols;
}

/** Flatten getMyConfigurations() rows and merge in stats (by link Id). A row
 *  without a stat entry renders blank stat cells. */
export function buildRows(links, stats, industries) {
    const defined = new Map();
    (industries || []).forEach((p) => { if (p && p.industryKey) defined.set(String(p.industryKey), p.industryLabel || String(p.industryKey)); });
    const byId = new Map();
    (stats || []).forEach((s) => byId.set(s.linkId, s));
    return (links || []).map((l) => {
        const st = byId.get(l.Id);
        const stage = st && FUNNEL_LABELS[st.funnelStage] ? st.funnelStage : null;
        const inactive = l.Active__c === false;
        const noAccount = !l.Account__c;
        return {
            recordId: l.Id,
            scNumber: l.Name || '',
            generatedUrl: l.Generated_URL__c || '',
            accountId: l.Account__c,
            contactId: l.Contact__c,
            company: (l.Account__r ? l.Account__r.Name : '') || l.Company__c || '',
            contactName: l.Contact__r ? l.Contact__r.Name : '',
            offeringLabel: formatLabel(l.Offering__c) || '',
            opportunityName: l.Opportunity__r ? l.Opportunity__r.Name : '',
            industryLabel: (l.Industry__c && defined.get(String(l.Industry__c))) || l.Industry__c || '',
            dealStage: l.Opportunity__r && l.Opportunity__r.StageName ? l.Opportunity__r.StageName : '',
            funnelStage: stage,
            funnelLabel: stage ? FUNNEL_LABELS[stage] : '—',
            funnelRank: stage ? FUNNEL_RANK[stage] : null,
            funnelClass: stage ? (FUNNEL_CLASS[stage] || '') : 'slds-text-color_weak',
            visits: st && typeof st.visits === 'number' ? st.visits : null,
            lastVisitAt: st && st.lastVisitAt ? st.lastVisitAt : null,
            statusLabel: inactive ? 'Inactive' : 'Active',
            statusClass: inactive ? 'slds-text-color_weak' : '',
            createdDate: l.CreatedDate || null,
            ownerId: l.OwnerId,
            ownerName: l.Owner ? l.Owner.Name : '',
            accountDisabled: noAccount,
            accountTitle: noAccount ? 'No account on this page' : 'Open account',
            // Visibility-only nudge (issue-11): flag rows with a free-typed
            // Company__c value but no real Account__c lookup, so reps/admins
            // notice the gap surfaced by the disabled-cell rendering fix
            // without this issue touching any write path.
            accountBackfillHint: noAccount && !!l.Company__c,
            contactDisabled: !l.Contact__c,
            contactTitle: l.Contact__c ? 'Open contact' : 'No contact on this page',
            // A page with no account still opens (by its link id alone).
            openDisabled: false,
            openTitle: 'Open this page'
        };
    });
}

/** Column fieldName -> the row property (and kind) the sort actually uses. */
const SORT_KEYS = {
    funnelLabel: { key: 'funnelRank', kind: 'number' },
    visits: { key: 'visits', kind: 'number' },
    lastVisitAt: { key: 'lastVisitAt', kind: 'date' },
    createdDate: { key: 'createdDate', kind: 'date' },
    scNumber: { key: 'scNumber', kind: 'text' },
    company: { key: 'company', kind: 'text' },
    contactName: { key: 'contactName', kind: 'text' },
    offeringLabel: { key: 'offeringLabel', kind: 'text' },
    opportunityName: { key: 'opportunityName', kind: 'text' },
    statusLabel: { key: 'statusLabel', kind: 'text' },
    ownerName: { key: 'ownerName', kind: 'text' },
    industryLabel: { key: 'industryLabel', kind: 'text' },
    dealStage: { key: 'dealStage', kind: 'text' }
};

function isBlank(v) {
    return v === null || v === undefined || v === '';
}

function compareValues(a, b, kind) {
    if (kind === 'text') {
        return String(a).toLowerCase().localeCompare(String(b).toLowerCase());
    }
    if (kind === 'date') {
        const ta = new Date(a).getTime();
        const tb = new Date(b).getTime();
        return ta === tb ? 0 : ta < tb ? -1 : 1;
    }
    return a === b ? 0 : a < b ? -1 : 1;
}

/** Stable sort; blanks last in BOTH directions; ties by createdDate desc, then Id. */
export function sortRows(rows, fieldName, direction) {
    const spec = SORT_KEYS[fieldName] || { key: fieldName, kind: 'text' };
    const dir = direction === 'asc' ? 1 : -1;
    return rows.slice().sort((x, y) => {
        const a = x[spec.key];
        const b = y[spec.key];
        const ab = isBlank(a);
        const bb = isBlank(b);
        if (ab !== bb) return ab ? 1 : -1;
        if (!ab) {
            const c = compareValues(a, b, spec.kind);
            if (c !== 0) return c * dir;
        }
        const t = compareValues(
            isBlank(x.createdDate) ? 0 : x.createdDate,
            isBlank(y.createdDate) ? 0 : y.createdDate, 'date'
        );
        if (t !== 0) return -t;
        return String(x.recordId).localeCompare(String(y.recordId));
    });
}
