/**
 * Pure column-visibility helper shared by the Pages and Assessments tables and
 * by c-gtm-column-chooser. No DOM, no LWC imports, never mutates its inputs.
 * Contract: docs/architecture/gtm-column-chooser.md section 4.
 *
 * Catalogue entry: { key, label, default, pinned }. `key` is the datatable
 * fieldName. Columns without a fieldName (the action column) are never part of
 * the catalogue and are always kept by visibleColumns.
 */

const arr = (v) => (Array.isArray(v) ? v : []);

export function buildCatalogue(allColumns, defaultKeyList, pinnedKeys) {
    const defaults = arr(defaultKeyList);
    const pinnedList = arr(pinnedKeys);
    const seen = new Set();
    const out = [];
    arr(allColumns).forEach((col) => {
        if (!col || !col.fieldName || !col.label || seen.has(col.fieldName)) return;
        seen.add(col.fieldName);
        const pinned = pinnedList.includes(col.fieldName);
        out.push({
            key: col.fieldName,
            label: col.label,
            default: pinned || defaults.includes(col.fieldName),
            pinned
        });
    });
    return out;
}

export function defaultKeys(catalogue) {
    return arr(catalogue)
        .filter((c) => c.default || c.pinned)
        .map((c) => c.key);
}

export function normalizeKeys(catalogue, keys) {
    const cat = arr(catalogue);
    if (!Array.isArray(keys)) return defaultKeys(cat);
    const want = new Set(keys);
    const result = cat.filter((c) => c.pinned || want.has(c.key)).map((c) => c.key);
    return result.length ? result : defaultKeys(cat);
}

export function visibleColumns(allColumns, catalogue, keys) {
    const show = new Set(normalizeKeys(catalogue, keys));
    return arr(allColumns).filter((col) => !col || !col.fieldName || show.has(col.fieldName));
}

export function isDefault(catalogue, keys) {
    const a = normalizeKeys(catalogue, keys);
    const b = defaultKeys(catalogue);
    return a.length === b.length && a.every((k, i) => k === b[i]);
}

export function isSortedColumnVisible(visibleCols, sortedBy) {
    if (!sortedBy) return false;
    return arr(visibleCols).some((c) => c && c.fieldName === sortedBy);
}
