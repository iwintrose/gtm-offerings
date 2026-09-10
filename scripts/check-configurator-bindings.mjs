/**
 * Asserts the configurator's template, its layout contract and its fallback
 * copy all agree.
 *
 * The chapters are read out of the template as `{chName.field}`. A typo in one
 * of those does not throw: LWC resolves the missing property to undefined and
 * the page renders a blank where a paragraph should be. That is the defect
 * class this catches, in all three directions:
 *
 *   1. the template reads a field the layout does not declare (nothing seeds
 *      it, so it is blank forever);
 *   2. the layout declares a field nothing renders (an editor types into a box
 *      that changes nothing);
 *   3. the copy module and the layout disagree about a chapter's fields;
 *   4. the copy module lists a chapter's fields in a different order from the
 *      order the page draws them. That order becomes the order of the boxes in
 *      the editor, so a mismatch makes an editor translate between the page
 *      they are reading and the form they are typing into.
 *
 * Usage: scripts/lwc-node-harness.sh, then `node <dir>/check-configurator-bindings.mjs <repoRoot>`
 */
import { readFileSync } from 'node:fs';
import { CHAPTERS } from 'c/gtmConfiguratorCopy';
import { LAYOUT_FIELDS, starterFor } from 'c/gtmPageLayouts';

const root = process.argv[2];
if (!root) throw new Error('usage: check-configurator-bindings.mjs <repoRoot>');
const html = readFileSync(`${root}/force-app/main/default/lwc/gtmConfigurator/gtmConfigurator.html`, 'utf8');

// The template reads chapters through a getter named for the section, so the
// getter name is how a binding is traced back to a section.
const GETTER = {
    chCover: 'cover', chPartner: 'partner', chChallenge: 'challenge', chApproach: 'approach',
    chProof: 'proof', chDeliverables: 'deliverables', chEngagement: 'engagement',
    chWhy: 'why', chClosing: 'closing'
};
// Properties the renderer computes rather than stores: they are derived from a
// card's position, so they are correctly absent from the layout contract.
const DERIVED = new Set(['num', 'cls']);

/** The markup inside one <template for:each> block, nesting respected. */
function blockAfter(src, from) {
    let depth = 1;
    const tag = /<template\b|<\/template>/g;
    tag.lastIndex = from;
    let m;
    while ((m = tag.exec(src))) {
        depth += m[0] === '</template>' ? -1 : 1;
        if (depth === 0) return src.slice(from, m.index);
    }
    return src.slice(from);
}

const bad = [];
const starter = new Map(starterFor('configurator').map((s) => [s.sectionKey, s]));
const used = new Map();       // sectionKey -> Set(field)

for (const [getter, sectionKey] of Object.entries(GETTER)) {
    const re = new RegExp(`\\{${getter}\\.(\\w+)\\}|value=\\{${getter}\\.(\\w+)\\}|href=\\{${getter}\\.(\\w+)\\}`, 'g');
    const seen = new Set();
    let m;
    while ((m = re.exec(html))) seen.add(m[1] || m[2] || m[3]);
    used.set(sectionKey, seen);
    if (!seen.size) bad.push(`template never reads ${getter} — chapter '${sectionKey}' renders nothing`);
}

// A for:each over a chapter's list reads the item's own properties, which
// belong to that list's element shape rather than to the chapter.
for (const [getter, sectionKey] of Object.entries(GETTER)) {
    const re = new RegExp(`for:each=\\{${getter}\\.(\\w+)\\}\\s+for:item="(\\w+)"`, 'g');
    let m;
    while ((m = re.exec(html))) {
        const [, listField, item] = m;
        used.get(sectionKey).add(listField);
        const chapter = CHAPTERS.find((c) => c.sectionKey === sectionKey);
        const sample = chapter && Array.isArray(chapter.fields[listField]) ? chapter.fields[listField][0] : null;
        if (!sample) { bad.push(`${sectionKey}: template loops over '${listField}', which is not a list in the copy module`); continue; }
        // Only the loop's own block. Two loops may bind the same item name to
        // different shapes, and scanning the whole file would report the one
        // against the other.
        const body = blockAfter(html, m.index + m[0].length);
        const itemRe = new RegExp(`\\{${item}\\.(\\w+)\\}`, 'g');
        let im;
        while ((im = itemRe.exec(body))) {
            const prop = im[1];
            if (!(prop in sample) && !DERIVED.has(prop)) {
                bad.push(`${sectionKey}: template reads ${item}.${prop}, but ${listField} entries have {${Object.keys(sample).join(', ')}}`);
            }
        }
    }
}

for (const chapter of CHAPTERS) {
    const spec = starter.get(chapter.sectionKey);
    if (!spec) { bad.push(`chapter '${chapter.sectionKey}' is not in the configurator starter`); continue; }
    if (spec.layoutType !== chapter.layoutType) {
        bad.push(`${chapter.sectionKey}: copy says layout '${chapter.layoutType}', starter says '${spec.layoutType}'`);
        continue;
    }
    const declared = new Set(['text', 'rich', 'json', 'icontext'].flatMap((b) => LAYOUT_FIELDS[chapter.layoutType][b] || []));
    const defaults = new Set(Object.keys(chapter.fields));
    const read = used.get(chapter.sectionKey) || new Set();

    for (const f of declared) if (!defaults.has(f)) bad.push(`${chapter.sectionKey}: layout declares '${f}' but the copy module has no default for it`);
    for (const f of defaults) if (!declared.has(f)) bad.push(`${chapter.sectionKey}: copy defines '${f}' but layout '${chapter.layoutType}' does not declare it`);
    for (const f of read) if (!declared.has(f)) bad.push(`${chapter.sectionKey}: template reads '${f}', which layout '${chapter.layoutType}' does not declare — always blank`);
    // whyHead and the industry overrides are rendered through their own
    // getters, so a declared field can legitimately be read indirectly.
    for (const f of declared) {
        if (read.has(f)) continue;
        if (chapter.sectionKey === 'why' && f === 'head') continue;   // drawn via whyHead
        if (f === 'lede' && !chapter.fields.lede) continue;           // deliberately empty
        bad.push(`${chapter.sectionKey}: '${f}' is declared and seeded but the template never renders it — an edit to it would do nothing`);
    }
}

// The order the template first mentions each field is the order the page draws
// it; the copy module's key order is the order the editor shows it.
for (const chapter of CHAPTERS) {
    const getter = Object.keys(GETTER).find((g) => GETTER[g] === chapter.sectionKey);
    if (!getter) continue;
    const drawn = [];
    const re = new RegExp(`\\{${getter}\\.(\\w+)\\}`, 'g');
    let m;
    while ((m = re.exec(html))) if (!drawn.includes(m[1])) drawn.push(m[1]);

    // Only fields the template names directly can be ordered against it; one
    // drawn through another getter (why's heading) has no position here.
    const editorOrder = Object.keys(chapter.fields).filter((f) => drawn.includes(f)).join(',');
    const pageOrder   = drawn.filter((f) => f in chapter.fields).join(',');
    if (editorOrder !== pageOrder) {
        bad.push(`${chapter.sectionKey}: the page draws [${pageOrder}] but the editor lists [${editorOrder}]`);
    }
}

const total = CHAPTERS.reduce((n, c) => n + Object.keys(c.fields).length, 0);
console.log(`configurator: ${CHAPTERS.length} chapters, ${total} content fields, ${[...used.values()].reduce((n, s) => n + s.size, 0)} template bindings`);
if (bad.length) { console.log(`\nBINDING VIOLATIONS (${bad.length}):`); bad.forEach((b) => console.log('  x ' + b)); process.exit(1); }
console.log('\nBindings hold: every field the template reads is declared and seeded, and every declared field is rendered.');
