/**
 * Pure helpers for c/gtmHeatGrid (no LWC imports, so they're Jest-testable
 * directly). Contract: docs/architecture/overview-bd-heat-redesign-2-heat-grid.md.
 */

export const NUDGE_TOOLTIP =
    'Nudge is not built yet -- see follow-up ticket gus-nudge-tool-and-readout-viewed-tracking.';
export const SCHEDULE_TOOLTIP =
    'Booking a call from here is not built yet -- see follow-up ticket gus-nudge-tool-and-readout-viewed-tracking.';

const ACTION_LABELS = {
    call_now: 'Call now',
    follow_up: 'Follow up',
    nudge: 'Nudge',
    schedule: 'Book the call'
};

/** HeatDay.intensity (0-3) -> the CSS shade class the cell strip uses. */
export function intensityClass(intensity) {
    const n = Number.isFinite(intensity) ? intensity : 0;
    return `heat-cell heat-cell--${Math.max(0, Math.min(3, n))}`;
}

/** "Sep 9 -- No activity" / "Sep 9 -- Assessment submitted" tooltip text for one day cell. */
export function dayTitle(day) {
    const dateLabel = formatDateOnly(day.day);
    const tierLabel = day.tier === 'none' ? 'No activity' : TIER_LABELS[day.tier] || day.tier;
    return `${dateLabel} -- ${tierLabel}`;
}

const TIER_LABELS = {
    engaged: 'Page viewed',
    started: 'Assessment started',
    submitted: 'Assessment submitted'
};

/** Apex Date arrives as "yyyy-mm-dd"; build a local date so the label does not shift a day. */
function formatDateOnly(value) {
    if (!value) return '';
    const [y, m, d] = String(value).slice(0, 10).split('-').map(Number);
    if (!y || !m || !d) return '';
    return new Date(y, m - 1, d).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

/** Row shaping: HeatGridResult.rows[] -> what the template renders, including
 *  the two gtmLinkCell typeAttributes objects for Account/Contact. */
export function buildRows(apexRows) {
    return (apexRows || []).map((r) => {
        const action = mapAction(r.nextAction);
        return {
            key: r.accountId,
            accountId: r.accountId,
            accountName: r.accountName || '',
            contactId: r.contactId,
            contactName: r.contactName || '',
            opportunityId: r.opportunityId,
            opportunityStage: r.opportunityStage || '—',
            latestSignal: r.latestSignal || '',
            days: (r.days || []).map((d, i) => ({
                key: `${r.accountId}-${i}`,
                cellClass: intensityClass(d.intensity),
                title: dayTitle(d)
            })),
            accountCellAttrs: {
                label: r.accountName || '',
                name: 'openAccount',
                disabled: !r.accountId,
                title: r.accountId ? 'Open account' : 'No account on this row',
                targetId: r.accountId,
                idField: 'accountId'
            },
            contactCellAttrs: {
                label: r.contactName || '',
                name: 'openContact',
                disabled: !r.contactId,
                title: r.contactId ? 'Open contact' : 'No contact on this account',
                targetId: r.contactId,
                idField: 'contactId'
            },
            actionKey: r.nextAction,
            actionLabel: action.label,
            actionDisabled: action.disabled,
            actionTitle: action.title,
            actionVariant: action.variant,
            // Only the disabled Nudge/Book-the-call buttons need the
            // tooltip-wrapper span to be keyboard-focusable -- an enabled
            // lightning-button is already reachable/tabbable on its own, so
            // giving its wrapper a tabindex too would double the tab stops.
            actionTooltipTabIndex: action.disabled ? '0' : '-1'
        };
    });
}

function mapAction(nextAction) {
    const label = ACTION_LABELS[nextAction] || ACTION_LABELS.call_now;
    if (nextAction === 'nudge') {
        return { label, disabled: true, title: NUDGE_TOOLTIP, variant: 'neutral' };
    }
    if (nextAction === 'schedule') {
        return { label, disabled: true, title: SCHEDULE_TOOLTIP, variant: 'neutral' };
    }
    if (nextAction === 'follow_up') {
        return { label, disabled: false, title: 'Create a follow-up task on this Opportunity', variant: 'brand' };
    }
    return { label, disabled: false, title: 'Log a call for this prospect', variant: 'brand' };
}

/** Same encoding lightning/pageReferenceUtils.encodeDefaultFieldValues does,
 *  reimplemented locally so this file needs no extra jest stub -- the
 *  `defaultFieldValues` state param a standard__quickAction PageReference
 *  reads (Field=EncodedValue pairs, comma-joined). */
export function encodeDefaultFieldValues(fields) {
    return Object.keys(fields || {})
        .filter((k) => fields[k] !== undefined && fields[k] !== null && fields[k] !== '')
        .map((k) => `${k}=${encodeURIComponent(fields[k])}`)
        .join(',');
}
