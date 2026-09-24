import {
    buildRows,
    intensityClass,
    dayTitle,
    encodeDefaultFieldValues,
    NUDGE_TOOLTIP,
    SCHEDULE_TOOLTIP
} from '../gtmHeatGridModel';

describe('gtmHeatGridModel', () => {
    describe('intensityClass', () => {
        it('maps each tier ordinal to its own shade class', () => {
            expect(intensityClass(0)).toBe('heat-cell heat-cell--0');
            expect(intensityClass(1)).toBe('heat-cell heat-cell--1');
            expect(intensityClass(2)).toBe('heat-cell heat-cell--2');
            expect(intensityClass(3)).toBe('heat-cell heat-cell--3');
        });

        it('clamps out-of-range values rather than emitting an unknown class', () => {
            expect(intensityClass(9)).toBe('heat-cell heat-cell--3');
            expect(intensityClass(-1)).toBe('heat-cell heat-cell--0');
            expect(intensityClass(undefined)).toBe('heat-cell heat-cell--0');
        });
    });

    describe('dayTitle', () => {
        it('renders a date + tier tooltip for an activity day', () => {
            expect(dayTitle({ day: '2026-09-10', tier: 'submitted' })).toBe('Sep 10 -- Assessment submitted');
        });

        it('renders "No activity" for a none-tier day', () => {
            expect(dayTitle({ day: '2026-09-10', tier: 'none' })).toBe('Sep 10 -- No activity');
        });
    });

    describe('buildRows', () => {
        const apexRows = [
            {
                accountId: '001AAA',
                accountName: 'Acme',
                contactId: '003AAA',
                contactName: 'Alex Rivera',
                opportunityId: '006AAA',
                opportunityStage: 'Negotiation',
                latestSignal: 'Assessment submitted today',
                nextAction: 'nudge',
                days: [{ day: '2026-09-09', tier: 'submitted', intensity: 3 }]
            },
            {
                accountId: '001BBB',
                accountName: 'Beta Co',
                contactId: null,
                contactName: '',
                opportunityId: null,
                opportunityStage: '',
                latestSignal: 'No activity in the last 14 days',
                nextAction: 'call_now',
                days: [{ day: '2026-09-09', tier: 'none', intensity: 0 }]
            },
            {
                accountId: '001CCC',
                accountName: 'Gamma Inc',
                contactId: '003CCC',
                contactName: 'Sam',
                opportunityId: '006CCC',
                opportunityStage: 'Qualification',
                latestSignal: 'Assessment started yesterday',
                nextAction: 'follow_up',
                days: [{ day: '2026-09-09', tier: 'started', intensity: 2 }]
            }
        ];

        it('maps every field the template reads', () => {
            const rows = buildRows(apexRows);
            expect(rows).toHaveLength(3);
            expect(rows[0].accountName).toBe('Acme');
            expect(rows[0].opportunityStage).toBe('Negotiation');
            expect(rows[0].latestSignal).toBe('Assessment submitted today');
            expect(rows[0].days[0].cellClass).toBe('heat-cell heat-cell--3');
        });

        it('blanks default to an em-dash for stage / disabled gtmLinkCell attrs when a row has no account/contact/opportunity', () => {
            const rows = buildRows(apexRows);
            const beta = rows[1];
            expect(beta.opportunityStage).toBe('—');
            expect(beta.contactCellAttrs.disabled).toBe(true);
            expect(beta.contactCellAttrs.title).toBe('No contact on this account');
        });

        it('renders "Nudge" as disabled with the follow-up-ticket tooltip, never silently missing', () => {
            const rows = buildRows(apexRows);
            expect(rows[0].actionLabel).toBe('Nudge');
            expect(rows[0].actionDisabled).toBe(true);
            expect(rows[0].actionTitle).toBe(NUDGE_TOOLTIP);
        });

        it('gives the disabled Nudge action a keyboard-focusable tooltip wrapper', () => {
            const rows = buildRows(apexRows);
            expect(rows[0].actionTooltipTabIndex).toBe('0');
        });

        it('does not add a redundant tab stop for an already-focusable enabled action', () => {
            const rows = buildRows(apexRows);
            expect(rows[1].actionTooltipTabIndex).toBe('-1');
            expect(rows[2].actionTooltipTabIndex).toBe('-1');
        });

        it('renders "Call now" enabled for a cold/new row', () => {
            const rows = buildRows(apexRows);
            expect(rows[1].actionLabel).toBe('Call now');
            expect(rows[1].actionDisabled).toBe(false);
        });

        it('renders "Follow up" enabled for a started row', () => {
            const rows = buildRows(apexRows);
            expect(rows[2].actionLabel).toBe('Follow up');
            expect(rows[2].actionDisabled).toBe(false);
        });

        it('maps the schedule action as disabled too, with its own tooltip', () => {
            const rows = buildRows([{ ...apexRows[0], nextAction: 'schedule' }]);
            expect(rows[0].actionDisabled).toBe(true);
            expect(rows[0].actionTitle).toBe(SCHEDULE_TOOLTIP);
        });

        it('handles an empty/undefined list', () => {
            expect(buildRows(undefined)).toEqual([]);
            expect(buildRows([])).toEqual([]);
        });
    });

    describe('encodeDefaultFieldValues', () => {
        it('joins Field=EncodedValue pairs with commas', () => {
            expect(encodeDefaultFieldValues({ WhoId: '003AAA', WhatId: '006AAA' })).toBe('WhoId=003AAA,WhatId=006AAA');
        });

        it('drops blank/undefined/null field values', () => {
            expect(encodeDefaultFieldValues({ WhoId: undefined, WhatId: '006AAA', Subject: '' })).toBe('WhatId=006AAA');
        });

        it('URI-encodes values that need it', () => {
            expect(encodeDefaultFieldValues({ Subject: 'Follow up: Acme & Co' }))
                .toBe(`Subject=${encodeURIComponent('Follow up: Acme & Co')}`);
        });
    });
});
