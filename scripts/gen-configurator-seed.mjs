/**
 * Emits the configurator's section and content rows from the renderer's own
 * copy module.
 *
 * The chapters used to be typed into the template. Turning them into content
 * means writing ~50 records, and hand-writing them would guarantee the seed
 * and the fallbacks disagreed within a release. They are generated from the
 * one place that defines them instead, so a change to a chapter's words is one
 * edit and this regenerates.
 *
 * Usage:  scripts/lwc-node-harness.sh   # then, from the printed directory:
 *         node <repo>/scripts/gen-configurator-seed.mjs <offeringKey> <outDir>
 * Output: <outDir>/sections.csv and <outDir>/content.csv, ready for
 *         `sf data upsert bulk` against the external ids.
 */
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { CHAPTERS } from 'c/maConfiguratorCopy';
import { starterFor, LAYOUT_FIELDS } from 'c/gtmPageLayouts';

const offering = process.argv[2] || 'migration-accelerator';
const outDir = process.argv[3];
if (!outDir) throw new Error('usage: gen-configurator-seed.mjs <offeringKey> <outDir>');
const TEMPLATE = 'configurator';

// The rail's order is the page's order: masthead, the cover the industries
// drive, the eight chapters, then the chrome and the settings behind it.
//
// The masthead is 10 and the chapters start at 100 because the block between
// belongs to the industry sections, which this generator does not own: one per
// industry, added and removed by a BA, and already numbered. Leaving them a
// range of their own is what keeps this from renumbering content it did not
// write, or colliding with it.
const ORDER = ['header', ...CHAPTERS.map((c) => c.sectionKey), 'assistant', 'footer', 'defaults'];
const INDUSTRY_BLOCK_END = 90;
const sortFor = (i) => (i === 0 ? 10 : INDUSTRY_BLOCK_END + i * 10);

const sectionRows = [];
const contentRows = [];
const starter = new Map(starterFor(TEMPLATE).map((s) => [s.sectionKey, s]));

// The assistant's own words. They are the component's fallbacks made explicit,
// so the editor opens on the copy the page is actually showing.
const ASSISTANT = {
    assistantName: 'Gus',
    assistantRole: 'GTM Utility Sidekick',
    fabLabel: 'Ask Gus',
    greeting: "I'm Gus. Tell me who this page is for and I'll set it up — company, industry, the accent colour, the numbers on the proof panel.",
    inputPlaceholder: 'Ask me to update company, industry, accent colour…'
};

function csv(rows, cols) {
    const esc = (v) => {
        const s = v === undefined || v === null ? '' : String(v);
        return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
    };
    return [cols.join(','), ...rows.map((r) => cols.map((c) => esc(r[c])).join(','))].join('\n') + '\n';
}

ORDER.forEach((sectionKey, i) => {
    const spec = starter.get(sectionKey);
    if (!spec) throw new Error(`no starter entry for section '${sectionKey}'`);
    const sortOrder = sortFor(i);
    sectionRows.push({
        'Section_Address__c': `${offering}::${TEMPLATE}::${sectionKey}`,
        'Offering_Key__c': offering,
        'Template_Type__c': TEMPLATE,
        'Section_Key__c': sectionKey,
        'Label__c': spec.label,
        'Help_Text__c': spec.helpText,
        'Layout_Type__c': spec.layoutType,
        'Width__c': spec.width,
        'Sort_Order__c': sortOrder,
        'Status__c': 'Published',
        'Active__c': 'true'
    });

    // Only the sections this generator owns get content written. The header,
    // footer and defaults are already seeded and edited; overwriting them here
    // would silently discard whatever a BA has since typed into them.
    const chapter = CHAPTERS.find((c) => c.sectionKey === sectionKey);
    const values = chapter ? chapter.fields : (sectionKey === 'assistant' ? ASSISTANT : null);
    if (!values) return;

    const spec2 = LAYOUT_FIELDS[spec.layoutType];
    const typeOf = (field) => ['text', 'rich', 'json', 'icontext']
        .find((b) => (spec2[b] || []).includes(field));

    Object.keys(values).forEach((field, fi) => {
        const fieldType = typeOf(field);
        if (!fieldType) throw new Error(`'${sectionKey}::${field}' is not declared by layout '${spec.layoutType}'`);
        const value = values[field];
        contentRows.push({
            'Content_Address__c': `${offering}::${TEMPLATE}::${sectionKey}::${field}`,
            'Offering_Key__c': offering,
            'Template_Type__c': TEMPLATE,
            'Section_Key__c': sectionKey,
            'Field_Key__c': field,
            'Field_Type__c': fieldType,
            'Label__c': field.replace(/([A-Z])/g, ' $1').replace(/^./, (c) => c.toUpperCase()).trim(),
            'Text_Value__c': fieldType === 'text' ? value : '',
            'Rich_Value__c': fieldType === 'rich' ? value : '',
            'JSON_Value__c': fieldType === 'json' ? JSON.stringify(value) : '',
            'Sort_Order__c': (fi + 1) * 10,
            'Status__c': 'Published',
            'Active__c': 'true'
        });
    });

    // Every field the layout declares must have a row, or the page silently
    // falls back and an edit appears to save but changes nothing.
    (['text', 'rich', 'json', 'icontext']).forEach((b) => {
        (spec2[b] || []).forEach((f) => {
            if (!(f in values)) throw new Error(`layout '${spec.layoutType}' declares '${f}' but '${sectionKey}' has no value for it`);
        });
    });
});

mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'sections.csv'), csv(sectionRows, Object.keys(sectionRows[0])));
writeFileSync(join(outDir, 'content.csv'), csv(contentRows, Object.keys(contentRows[0])));
console.log(`${sectionRows.length} sections, ${contentRows.length} content rows -> ${outDir}`);
