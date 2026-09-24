import {
    STATUS_OPTIONS, TIER_OPTIONS, READOUT_OPTIONS, STATUS_LABEL_BY_KEY, TIER_LABEL_BY_KEY,
    READOUT_LABEL_BY_KEY, buildFilterConfig, mapRow, readoutKeyFor, readoutLabelFor,
    formatOfferingLabel, COLUMNS, TABLE_COLUMNS, OFFERING_COLUMN
} from '../gtmAssessmentsTableModel';

const fs = require('fs');
const path = require('path');

// The Apex source is the vocabulary of record: parse its key sets so drift fails here.
const cls = fs.readFileSync(
    path.join(__dirname, '..', '..', '..', 'classes', 'GtmAssessmentListController.cls'),
    'utf8'
);
function apexMapEntries(name) {
    const m = cls.match(new RegExp(`${name}\\s*=\\s*new Map<String, [A-Za-z]+>\\{([^}]*)\\}`));
    expect(m).not.toBeNull();
    return Array.from(m[1].matchAll(/'([^']+)'\s*=>\s*'?([^',\s][^',]*)'?/g), (x) => [x[1], x[2].trim()]);
}
function apexSet(name) {
    const m = cls.match(new RegExp(`${name}\\s*=\\s*new Set<String>\\{([^}]*)\\}`));
    expect(m).not.toBeNull();
    return Array.from(m[1].matchAll(/'([^']+)'/g), (x) => x[1]);
}

describe('Assessments filter vocabularies equal the Apex vocabularies', () => {
    it('status: option values and labels equal STATUS_BY_KEY', () => {
        const apex = apexMapEntries('STATUS_BY_KEY');
        expect(STATUS_OPTIONS.map((o) => [o.value, o.label])).toEqual(apex);
    });

    it('tier: option values and labels equal TIER_BY_KEY', () => {
        const apex = apexMapEntries('TIER_BY_KEY');
        expect(TIER_OPTIONS.map((o) => [o.value, o.label])).toEqual(apex);
    });

    it('readout: option values equal READOUT_KEYS', () => {
        expect(READOUT_OPTIONS.map((o) => o.value).sort()).toEqual(apexSet('READOUT_KEYS').sort());
    });

    it('the config the bar receives uses exactly those maps', () => {
        const cfg = buildFilterConfig(['a-b'], []);
        const opts = (k) => cfg.find((f) => f.key === k).options;
        expect(opts('status')).toEqual(STATUS_OPTIONS);
        expect(opts('tier')).toEqual(TIER_OPTIONS);
        expect(opts('readout')).toEqual(READOUT_OPTIONS);
        expect(opts('offering')).toEqual([{ value: 'a-b', label: 'A B' }]);
    });
});

describe('column text comes from the same maps as the option labels (table-driven)', () => {
    it.each(Object.entries(STATUS_LABEL_BY_KEY))('status %s: a row with that status shows the option label', (key, label) => {
        expect(mapRow({ requestStatus: label }).requestStatus).toBe(label);
    });

    it.each(Object.entries(TIER_LABEL_BY_KEY))('tier %s: a row with that tier shows the option label', (key, label) => {
        expect(mapRow({ tier: label }).tierLabel).toBe(label);
    });

    const READOUT_ROWS = {
        none: {},
        draft: { readoutStatus: 'Draft' },
        pending: { readoutStatus: 'Pending Approval' },
        'approved-unsent': { readoutStatus: 'Approved', readoutNotificationSent: false },
        'approved-sent': { readoutStatus: 'Approved', readoutNotificationSent: true },
        published: { readoutStatus: 'Published' }
    };
    it.each(Object.keys(READOUT_LABEL_BY_KEY))('readout %s: some row shape produces the key AND the option label in the column', (key) => {
        const row = READOUT_ROWS[key];
        expect(readoutKeyFor(row)).toBe(key);
        expect(mapRow(row).readoutLabel).toBe(READOUT_LABEL_BY_KEY[key]);
    });

    it('the Pending Approval / Waiting on approval divergence cannot return', () => {
        expect(mapRow({ readoutStatus: 'Pending Approval' }).readoutLabel).toBe('Waiting on approval');
    });

    it('offering: the column and the option label use the same formatter', () => {
        const key = 'migration-accelerator';
        expect(mapRow({ offeringKey: key }).offeringLabel).toBe(formatOfferingLabel(key));
        expect(buildFilterConfig([key], []).find((f) => f.key === 'offering').options[0].label).toBe('Migration Accelerator');
        expect(mapRow({}).offeringLabel).toBe('—');
    });
});

describe('table columns', () => {
    it('COLUMNS (imported by the Overview card) is unchanged; the table adds an Offering column last', () => {
        expect(COLUMNS.map((c) => c.label)).toEqual([
            'Assessment', 'Contact', 'Account', 'Readiness tier', 'Score', 'Request status', 'Readout', 'Submitted'
        ]);
        expect(TABLE_COLUMNS.slice(0, COLUMNS.length)).toEqual(COLUMNS);
        expect(TABLE_COLUMNS[TABLE_COLUMNS.length - 2]).toBe(OFFERING_COLUMN);
        expect(TABLE_COLUMNS[TABLE_COLUMNS.length - 1].type).toBe('action'); // right-hand row menu
        expect(OFFERING_COLUMN.fieldName).toBe('offeringLabel');
        expect(OFFERING_COLUMN.sortable).toBe(false); // the server has no offering sort key
    });
});
