import { buildCatalogue, defaultKeys, normalizeKeys, visibleColumns, isDefault, isSortedColumnVisible } from 'c/gtmColumnState';

const COLS = [
    { label: 'Name', fieldName: 'name', type: 'button', sortable: true },
    { label: 'Company', fieldName: 'company', sortable: true },
    { label: 'Contact', fieldName: 'contact' },
    { label: 'Score', fieldName: 'score' },
    { type: 'action', typeAttributes: { rowActions: [] } }
];
const DEFAULTS = ['company'];
const PINNED = ['name'];

describe('buildCatalogue', () => {
    it('maps label/key, flags defaults, implies default for pinned, skips the action column', () => {
        const cat = buildCatalogue(COLS, DEFAULTS, PINNED);
        expect(cat).toEqual([
            { key: 'name', label: 'Name', default: true, pinned: true },
            { key: 'company', label: 'Company', default: true, pinned: false },
            { key: 'contact', label: 'Contact', default: false, pinned: false },
            { key: 'score', label: 'Score', default: false, pinned: false }
        ]);
    });
    it('defaults pinned to none and tolerates null inputs', () => {
        expect(buildCatalogue(COLS, DEFAULTS).every((c) => !c.pinned)).toBe(true);
        expect(buildCatalogue(null, null, null)).toEqual([]);
    });
    it('does not mutate inputs and de-dupes fieldNames', () => {
        const copy = JSON.stringify(COLS);
        buildCatalogue(COLS, DEFAULTS, PINNED);
        expect(JSON.stringify(COLS)).toBe(copy);
        expect(buildCatalogue([COLS[1], COLS[1]], [], []).length).toBe(1);
    });
});

describe('defaultKeys', () => {
    it('lists default and pinned keys in catalogue order', () => {
        expect(defaultKeys(buildCatalogue(COLS, ['score', 'company'], PINNED))).toEqual(['name', 'company', 'score']);
    });
    it('is tolerant of null', () => {
        expect(defaultKeys(null)).toEqual([]);
    });
});

describe('normalizeKeys', () => {
    const cat = buildCatalogue(COLS, DEFAULTS, PINNED);
    it('null/undefined mean defaults', () => {
        expect(normalizeKeys(cat, null)).toEqual(['name', 'company']);
        expect(normalizeKeys(cat, undefined)).toEqual(['name', 'company']);
    });
    it('drops unknown keys, ignores duplicates and uses catalogue order not input order', () => {
        expect(normalizeKeys(cat, ['score', 'bogus', 'contact', 'score'])).toEqual(['name', 'contact', 'score']);
    });
    it('always re-adds pinned keys', () => {
        expect(normalizeKeys(cat, ['score'])).toEqual(['name', 'score']);
        expect(normalizeKeys(cat, [])).toEqual(['name']); // pinned alone is a valid non-empty set
    });
    it('empty result (nothing pinned) falls back to defaults: last-column guard', () => {
        const free = buildCatalogue(COLS, ['company', 'contact'], []);
        expect(normalizeKeys(free, [])).toEqual(['company', 'contact']);
        expect(normalizeKeys(free, ['bogus'])).toEqual(['company', 'contact']);
    });
    it('does not mutate its inputs', () => {
        const keys = ['score', 'contact'];
        normalizeKeys(cat, keys);
        expect(keys).toEqual(['score', 'contact']);
    });
});

describe('visibleColumns', () => {
    const cat = buildCatalogue(COLS, DEFAULTS, PINNED);
    it('keeps the action column and preserves object identities and order', () => {
        const out = visibleColumns(COLS, cat, ['score']);
        expect(out).toEqual([COLS[0], COLS[3], COLS[4]]);
        expect(out[0]).toBe(COLS[0]);
        expect(out[1]).toBe(COLS[3]);
        expect(out[2]).toBe(COLS[4]);
    });
    it('null keys show the defaults plus the action column', () => {
        expect(visibleColumns(COLS, cat, null).map((c) => c.fieldName)).toEqual(['name', 'company', undefined]);
    });
    it('pinned is present even when omitted, and unknown keys are ignored', () => {
        expect(visibleColumns(COLS, cat, ['bogus', 'contact']).map((c) => c.fieldName)).toEqual(['name', 'contact', undefined]);
    });
    it('does not mutate the column list and tolerates null', () => {
        const before = COLS.slice();
        visibleColumns(COLS, cat, ['score']);
        expect(COLS).toEqual(before);
        expect(visibleColumns(null, cat, null)).toEqual([]);
    });
});

describe('isDefault', () => {
    const cat = buildCatalogue(COLS, DEFAULTS, PINNED);
    it('is true for null, defaults in any order, and defaults minus nothing pinned', () => {
        expect(isDefault(cat, null)).toBe(true);
        expect(isDefault(cat, ['company', 'name'])).toBe(true);
        expect(isDefault(cat, ['company'])).toBe(true); // pinned re-added
    });
    it('is false once a column is added or removed', () => {
        expect(isDefault(cat, ['company', 'score'])).toBe(false);
        const free = buildCatalogue(COLS, ['company', 'contact'], []);
        expect(isDefault(free, ['company'])).toBe(false);
    });
});

describe('isSortedColumnVisible', () => {
    const vis = [COLS[0], COLS[1], COLS[4]];
    it('checks fieldName membership', () => {
        expect(isSortedColumnVisible(vis, 'company')).toBe(true);
        expect(isSortedColumnVisible(vis, 'score')).toBe(false);
    });
    it('is false for empty sortedBy and null lists', () => {
        expect(isSortedColumnVisible(vis, undefined)).toBe(false);
        expect(isSortedColumnVisible(null, 'name')).toBe(false);
    });
});
