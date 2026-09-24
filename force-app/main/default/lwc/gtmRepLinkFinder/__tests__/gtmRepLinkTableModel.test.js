import {
    buildColumns, buildRows, sortRows, getRowActions, NO_ACCOUNT_TITLE, NO_ACCOUNT_ACTION_LABEL
} from '../gtmRepLinkTableModel';

const link = (over) => ({
    Id: 'L1', Account__c: 'A1', Contact__c: 'C1', Company__c: 'Acme', Offering__c: 'migration-accelerator',
    Active__c: true, CreatedDate: '2026-01-01T00:00:00.000Z', OwnerId: 'U1', Owner: { Name: 'Rep One' },
    Opportunity__r: { Name: 'Big Deal' }, Contact__r: { Name: 'Jane' }, ...over
});

describe('buildColumns', () => {
    it('has the contract columns; Owner only when asked; action column last', () => {
        const base = buildColumns(false);
        expect(base.map((c) => c.fieldName).filter(Boolean)).toEqual([
            'scNumber', 'company', 'contactName', 'offeringLabel', 'opportunityName', 'funnelLabel',
            'visits', 'lastVisitAt', 'statusLabel', 'createdDate', 'industryLabel', 'dealStage'
        ]);
        expect(base[0].type).toBe('button');
        expect(base[0].fieldName).toBe('scNumber');
        expect(base[0].typeAttributes.name).toBe('open');
        expect(base[0].typeAttributes.disabled).toEqual({ fieldName: 'openDisabled' });
        expect(base[base.length - 1].type).toBe('action');
        expect(base.filter((c) => c.fieldName).every((c) => c.sortable)).toBe(true);
        expect(base.find((c) => c.fieldName === 'funnelLabel').cellAttributes.class).toEqual({ fieldName: 'funnelClass' });
        const withOwner = buildColumns(true);
        expect(withOwner.map((c) => c.fieldName)).toContain('ownerName');
        // new catalogue columns come after the existing ones (owner included)
        const names = withOwner.map((c) => c.fieldName).filter(Boolean);
        expect(names.slice(-3)).toEqual(['ownerName', 'industryLabel', 'dealStage']);
        expect(withOwner[withOwner.length - 1].type).toBe('action');
    });
});

describe('getRowActions', () => {
    it('Open (disabled with the reason in the label when there is no account), Copy link, New password, Turn off/on', () => {
        const done = jest.fn();
        getRowActions({ openDisabled: false, statusLabel: 'Active', generatedUrl: 'https://x' }, done);
        expect(done).toHaveBeenLastCalledWith([
            { label: 'Open', name: 'open', disabled: false },
            { label: 'Copy link', name: 'copy', disabled: false },
            { label: 'New password', name: 'password' },
            { label: 'Turn off', name: 'toggle' }
        ]);
        getRowActions({ openDisabled: true, statusLabel: 'Inactive', generatedUrl: '' }, done);
        expect(done).toHaveBeenLastCalledWith([
            { label: NO_ACCOUNT_ACTION_LABEL, name: 'open', disabled: true },
            { label: 'Copy link', name: 'copy', disabled: true },
            { label: 'New password', name: 'password' },
            { label: 'Turn on', name: 'toggle' }
        ]);
    });
});

describe('buildRows', () => {
    it('flattens, merges stats and colours via SLDS utilities', () => {
        const [r] = buildRows([link()], [{ linkId: 'L1', visits: 3, lastVisitAt: '2026-02-01T00:00:00.000Z', funnelStage: 'submitted' }]);
        expect(r).toMatchObject({
            recordId: 'L1', accountId: 'A1', contactId: 'C1', company: 'Acme', contactName: 'Jane',
            offeringLabel: 'Migration Accelerator', opportunityName: 'Big Deal', funnelStage: 'submitted',
            funnelLabel: 'Assessment submitted', funnelRank: 3, funnelClass: 'slds-text-color_success',
            visits: 3, statusLabel: 'Active', ownerName: 'Rep One', openDisabled: false
        });
    });

    it('a row with no stat, contact, opportunity or account still renders, blank and disabled', () => {
        const [r] = buildRows([link({ Account__c: null, Contact__r: null, Opportunity__r: null, Active__c: false })], []);
        expect(r.funnelLabel).toBe('—');
        expect(r.visits).toBeNull();
        expect(r.lastVisitAt).toBeNull();
        expect(r.contactName).toBe('');
        expect(r.opportunityName).toBe('');
        expect(r.statusLabel).toBe('Inactive');
        expect(r.statusClass).toBe('slds-text-color_weak');
        expect(r.openDisabled).toBe(false); // opens by link id alone
        expect(r.openTitle).toBe('Open this page');
    });

    it('falls back to Account name when Company__c is blank', () => {
        const [r] = buildRows([link({ Company__c: null, Account__r: { Name: 'From Account' } })], []);
        expect(r.company).toBe('From Account');
    });

    it('prefers Account.Name over Company__c when both are populated', () => {
        const [r] = buildRows([link({ Company__c: 'Stale Typed Name', Account__r: { Name: 'Real Account Name' } })], []);
        expect(r.company).toBe('Real Account Name');
    });

    it('falls back to Company__c when there is no Account at all', () => {
        const [r] = buildRows([link({ Company__c: 'Typed Only', Account__c: null, Account__r: null })], []);
        expect(r.company).toBe('Typed Only');
    });
});

describe('sortRows', () => {
    const rows = [
        { recordId: 'a', company: 'beta', visits: 2, lastVisitAt: '2026-03-01T00:00:00.000Z', createdDate: '2026-01-01T00:00:00.000Z', funnelRank: 3 },
        { recordId: 'b', company: 'Alpha', visits: null, lastVisitAt: null, createdDate: '2026-01-05T00:00:00.000Z', funnelRank: 0 },
        { recordId: 'c', company: 'Gamma', visits: 10, lastVisitAt: '2026-04-01T00:00:00.000Z', createdDate: '2026-01-02T00:00:00.000Z', funnelRank: 1 },
        { recordId: 'd', company: 'delta', visits: null, lastVisitAt: null, createdDate: '2026-01-09T00:00:00.000Z', funnelRank: null }
    ];
    const ids = (r) => r.map((x) => x.recordId);

    it('last visit desc: newest first; never-visited last, newest saved first', () => {
        expect(ids(sortRows(rows, 'lastVisitAt', 'desc'))).toEqual(['c', 'a', 'd', 'b']);
    });
    it('last visit asc: never-visited still last', () => {
        expect(ids(sortRows(rows, 'lastVisitAt', 'asc'))).toEqual(['a', 'c', 'd', 'b']);
    });
    it('text sorts case-insensitively, both directions', () => {
        expect(ids(sortRows(rows, 'company', 'asc'))).toEqual(['b', 'a', 'd', 'c']);
        expect(ids(sortRows(rows, 'company', 'desc'))).toEqual(['c', 'd', 'a', 'b']);
    });
    it('numbers sort numerically with blanks last in both directions', () => {
        expect(ids(sortRows(rows, 'visits', 'asc'))).toEqual(['a', 'c', 'd', 'b']);
        expect(ids(sortRows(rows, 'visits', 'desc'))).toEqual(['c', 'a', 'd', 'b']);
    });
    it('funnel stage sorts by rank, not label', () => {
        expect(ids(sortRows(rows, 'funnelLabel', 'desc'))).toEqual(['a', 'c', 'b', 'd']);
        expect(ids(sortRows(rows, 'funnelLabel', 'asc'))).toEqual(['b', 'c', 'a', 'd']);
    });
    it('saved date sorts on the raw value', () => {
        expect(ids(sortRows(rows, 'createdDate', 'desc'))).toEqual(['d', 'b', 'c', 'a']);
    });
    it('does not mutate its input', () => {
        const copy = rows.slice();
        sortRows(rows, 'visits', 'asc');
        expect(rows).toEqual(copy);
    });
});
