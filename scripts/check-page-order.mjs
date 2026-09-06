/**
 * Every page: does the editor list what the page draws, in the order it draws it?
 *
 * The complaint this answers is not cosmetic. A rail that lists sections in a
 * different order from the page, or lists sections the page has no element
 * for, makes an editor translate between what they are reading and what they
 * are typing into — on every single edit.
 *
 * A template's data-section attributes come in two kinds, and both are read
 * here rather than only the first:
 *
 *   LITERAL   data-section="proof"        one named section, at that position
 *   SLOT      data-section={ind.key}      inside a for:each: any number of
 *                                         sections, drawn in stored order,
 *                                         all sitting at that position
 *
 * A slot is not special to industries. Any family a page draws in a loop —
 * industries, offering tiles, whatever comes next — is one slot, and the
 * sections landing in it are checked for order among themselves rather than
 * against a name the template never writes.
 *
 * Then the same question one level down: within each section, are the FIELDS
 * stored in the order the page draws them? That order is the order of the
 * boxes in the editor, so a section whose fields are stored shuffled makes an
 * editor hunt for the box matching the line they are reading.
 *
 * A looped renderer draws each layout from one branch of its template, so the
 * order a layout's fields appear in that branch is the order every section of
 * that layout is drawn in.
 *
 * Asked against the org, not the seed files, because an org drifts the moment
 * anyone edits a page.
 *
 * Usage: scripts/lwc-node-harness.sh, then
 *   node <dir>/check-page-order.mjs <repoRoot> [orgAlias]
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { LAYOUT_FIELDS } from 'c/gtmPageLayouts';

const root = process.argv[2];
const org  = process.argv[3] || process.env.SF_TARGET_ORG || '';
if (!root) throw new Error('usage: check-page-order.mjs <repoRoot> [orgAlias]');

const PAGES = [
    { offering: 'migration-accelerator', template: 'configurator',       html: 'lwc/gtmConfigurator/gtmConfigurator.html' },
    { offering: 'migration-accelerator', template: 'story',              html: 'lwc/gtmStory/gtmStory.html' },
    // One tile, drawn inside the offerings page's loop. It does not own that
    // page's masthead or footer, so only its own sections are checked.
    { offering: 'migration-accelerator', template: 'offerings-listing',  html: 'lwc/offeringChooser/offeringChooser.html', partial: true },
    { offering: 'gtm',                   template: 'offerings-page',     html: 'lwc/offeringChooser/offeringChooser.html' },
    { offering: 'gtm',                   template: 'industry-chooser',   html: 'lwc/chooseIndustry/chooseIndustry.html' }
];

// Real sections that deliberately have no element: settings a page carries
// rather than says.
const NON_VISUAL = new Set(['offering-defaults']);
// A dynamic binding outside any loop still resolves to exactly one element.
const DYNAMIC_SINGLE = { previewIndustrySection: 'cover' };

function query(soql) {
    const args = ['data', 'query', '-q', soql, '--json'];
    if (org) args.push('--target-org', org);
    try {
        const out = execFileSync('sf', args, { encoding: 'utf8', maxBuffer: 32e6, stdio: ['ignore', 'pipe', 'pipe'] });
        return JSON.parse(out).result.records;
    } catch (e) {
        let why = (e.stdout || '').toString();
        try { why = JSON.parse(why).message; } catch (_) { /* not JSON */ }
        throw new Error('sf data query failed: ' + why);
    }
}

/** The for:each blocks in a template, as [start, end) offsets. */
function loopRanges(html) {
    const out = [];
    const loopRe = /for:each=\{[^}]+\}/g;
    let lm;
    while ((lm = loopRe.exec(html))) {
        let depth = 1, end = html.length, tm;
        const tag = /<template\b|<\/template>/g;
        tag.lastIndex = lm.index + lm[0].length;
        while ((tm = tag.exec(html))) {
            depth += tm[0] === '</template>' ? -1 : 1;
            if (depth === 0) { end = tm.index; break; }
        }
        out.push([lm.index, end]);
    }
    return out;
}

/** { kind: 'literal', key } | { kind: 'slot' }, in document order. */
function drawnSequence(htmlPath) {
    const html = readFileSync(`${root}/force-app/main/default/${htmlPath}`, 'utf8');
    const loops = loopRanges(html);
    const inLoop = (i) => loops.some(([a, b]) => i > a && i < b);
    const out = [];
    const re = /data-section=("([\w-]+)"|\{([\w.]+)\})/g;
    let m;
    while ((m = re.exec(html))) {
        if (m[2]) { out.push({ kind: 'literal', key: m[2] }); continue; }
        const expr = m[3];
        if (inLoop(m.index)) { out.push({ kind: 'slot' }); continue; }
        const single = DYNAMIC_SINGLE[expr];
        out.push(single ? { kind: 'literal', key: single } : { kind: 'slot' });
    }
    return out;
}

let failures = 0;
for (const page of PAGES) {
    const secs = query(
        `SELECT Section_Key__c, Layout_Type__c, Sort_Order__c FROM GTM_Page_Section__c ` +
        `WHERE Offering_Key__c='${page.offering}' AND Template_Type__c='${page.template}' ` +
        `AND Active__c=true AND Status__c='Published' ORDER BY Sort_Order__c ASC NULLS LAST`);
    const stored = secs.map((s) => s.Section_Key__c);
    const visual = secs.filter((s) => !NON_VISUAL.has(s.Layout_Type__c)).map((s) => s.Section_Key__c);

    const bad = [];
    const seq = drawnSequence(page.html);
    const literals = seq.filter((e) => e.kind === 'literal').map((e) => e.key);
    const slots = seq.filter((e) => e.kind === 'slot').length;

    // A section the template never names needs a slot to land in.
    const unnamed = visual.filter((k) => !literals.includes(k));
    if (!slots && unnamed.length) {
        unnamed.forEach((k) => bad.push(`the editor lists '${k}' but the page has no element for it`));
    }
    // A named element with no section behind it is a part of the page nobody
    // can edit.
    if (!page.partial) {
        for (const k of literals) {
            if (!stored.includes(k)) bad.push(`the page draws '${k}' but no section backs it — nobody can edit it`);
        }
    }
    // The named sections must run in the template's order.
    const mine = visual.filter((k) => literals.includes(k));
    const theirs = literals.filter((k) => visual.includes(k));
    if (mine.join(',') !== theirs.join(',')) {
        bad.push(`order differs — page: [${theirs.join(' > ')}]  editor: [${mine.join(' > ')}]`);
    }
    // Ties leave the rail's order to a database tiebreak nobody chose.
    for (let i = 1; i < secs.length; i++) {
        if (secs[i].Sort_Order__c !== null && secs[i].Sort_Order__c === secs[i - 1].Sort_Order__c) {
            bad.push(`'${stored[i - 1]}' and '${stored[i]}' share sort order ${secs[i].Sort_Order__c}`);
        }
    }

    const label = `${page.offering}::${page.template}`;
    if (bad.length) {
        failures += bad.length;
        console.log(`\nX ${label} (${secs.length} sections, ${slots} slot${slots === 1 ? '' : 's'})`);
        bad.forEach((b) => console.log('    ' + b));
    } else {
        console.log(`  ${label} — ${secs.length} sections, ${slots} slot${slots === 1 ? '' : 's'}, in the order the page draws them`);
    }
}

// ── field order, per section, on every page ────────────────────────────────

/**
 * The order a layout's fields are drawn, read from the renderer.
 *
 * A looped template draws a layout inside `if:true={s.isCardGrid}`; a fixed one
 * names its fields through a per-section getter. Either way the first mention
 * of a field in the relevant block is where the page draws it.
 */
function fieldOrderByLayout(htmlPath) {
    const html = readFileSync(`${root}/force-app/main/default/${htmlPath}`, 'utf8');
    const byLayout = {};
    const camel = (l) => l.split('-').map((p) => p[0].toUpperCase() + p.slice(1)).join('');
    for (const layout of Object.keys(LAYOUT_FIELDS)) {
        const marker = `if:true={s.is${camel(layout)}}`;
        const at = html.indexOf(marker);
        if (at === -1) continue;
        let depth = 1, end = html.length, tm;
        const tag = /<template\b|<\/template>/g;
        tag.lastIndex = at + marker.length;
        while ((tm = tag.exec(html))) {
            depth += tm[0] === '</template>' ? -1 : 1;
            if (depth === 0) { end = tm.index; break; }
        }
        const block = html.slice(at, end);
        const seen = [];
        const re = /\{s\.(\w+)\}/g;
        let m;
        const declared = new Set(['text','rich','json','icontext'].flatMap((b) => LAYOUT_FIELDS[layout][b] || []));
        while ((m = re.exec(block))) if (declared.has(m[1]) && !seen.includes(m[1])) seen.push(m[1]);
        if (seen.length) byLayout[layout] = seen;
    }
    return byLayout;
}

for (const page of PAGES) {
    const order = fieldOrderByLayout(page.html);
    if (!Object.keys(order).length) continue;
    const rows = query(
        `SELECT Section_Key__c, Field_Key__c, Sort_Order__c FROM GTM_Page_Content__c ` +
        `WHERE Offering_Key__c='${page.offering}' AND Template_Type__c='${page.template}' ` +
        `AND Active__c=true AND Industry_Key__c=null ORDER BY Section_Key__c, Sort_Order__c ASC NULLS LAST`);
    const layoutOf = {};
    for (const s2 of query(
        `SELECT Section_Key__c, Layout_Type__c FROM GTM_Page_Section__c ` +
        `WHERE Offering_Key__c='${page.offering}' AND Template_Type__c='${page.template}' AND Active__c=true`)) {
        layoutOf[s2.Section_Key__c] = s2.Layout_Type__c;
    }
    const stored = {};
    for (const r of rows) (stored[r.Section_Key__c] ||= []).push(r.Field_Key__c);

    for (const [sec, fields] of Object.entries(stored)) {
        const drawn = order[layoutOf[sec]];
        if (!drawn) continue;
        const mine = fields.filter((f) => drawn.includes(f)).join(',');
        const theirs = drawn.filter((f) => fields.includes(f)).join(',');
        if (mine !== theirs) {
            failures++;
            console.log(`\nX ${page.offering}::${page.template} :: ${sec}`);
            console.log(`    page draws  [${theirs}]`);
            console.log(`    editor lists[${mine}]`);
        }
    }
}

if (failures) { console.log(`\n${failures} ordering problem(s).`); process.exit(1); }
console.log('\nEvery page lists what it draws, in the order it draws it — sections and fields.');
