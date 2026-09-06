/**
 * Renumbers content rows so the editor lists a section's fields in the order
 * the page draws them.
 *
 * check-page-order.mjs finds the mismatches; this repairs them, from the same
 * source of truth — the renderer's own template. Prints a CSV of the rows to
 * change so the upsert is reviewable before it runs.
 *
 * Usage: node <dir>/fix-field-order.mjs <repoRoot> <outCsv> [orgAlias]
 */
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { LAYOUT_FIELDS } from 'c/gtmPageLayouts';

const [root, outCsv, orgArg] = process.argv.slice(2);
if (!root || !outCsv) throw new Error('usage: fix-field-order.mjs <repoRoot> <outCsv> [orgAlias]');
const org = orgArg || process.env.SF_TARGET_ORG || '';

const PAGES = [
    { offering: 'migration-accelerator', template: 'configurator',      html: 'lwc/gtmConfigurator/gtmConfigurator.html' },
    { offering: 'migration-accelerator', template: 'story',             html: 'lwc/gtmStory/gtmStory.html' },
    { offering: 'migration-accelerator', template: 'offerings-listing', html: 'lwc/offeringChooser/offeringChooser.html' },
    { offering: 'gtm',                   template: 'offerings-page',    html: 'lwc/offeringChooser/offeringChooser.html' },
    { offering: 'gtm',                   template: 'industry-chooser',  html: 'lwc/chooseIndustry/chooseIndustry.html' }
];

function query(soql) {
    const args = ['data', 'query', '-q', soql, '--json'];
    if (org) args.push('--target-org', org);
    return JSON.parse(execFileSync('sf', args, { encoding: 'utf8', maxBuffer: 32e6, stdio: ['ignore','pipe','pipe'] })).result.records;
}

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
        const declared = new Set(['text','rich','json','icontext'].flatMap((b) => LAYOUT_FIELDS[layout][b] || []));
        const seen = [];
        const re = /\{s\.(\w+)\}/g;
        let m;
        while ((m = re.exec(block))) if (declared.has(m[1]) && !seen.includes(m[1])) seen.push(m[1]);
        if (seen.length) byLayout[layout] = seen;
    }
    return byLayout;
}

const rows = [];
for (const page of PAGES) {
    const order = fieldOrderByLayout(page.html);
    if (!Object.keys(order).length) continue;
    const layoutOf = {};
    for (const s of query(
        `SELECT Section_Key__c, Layout_Type__c FROM GTM_Page_Section__c ` +
        `WHERE Offering_Key__c='${page.offering}' AND Template_Type__c='${page.template}' AND Active__c=true`)) {
        layoutOf[s.Section_Key__c] = s.Layout_Type__c;
    }
    for (const r of query(
        `SELECT Content_Address__c, Section_Key__c, Field_Key__c, Sort_Order__c FROM GTM_Page_Content__c ` +
        `WHERE Offering_Key__c='${page.offering}' AND Template_Type__c='${page.template}' AND Active__c=true`)) {
        const drawn = order[layoutOf[r.Section_Key__c]];
        if (!drawn) continue;
        const i = drawn.indexOf(r.Field_Key__c);
        if (i === -1) continue;
        const want = (i + 1) * 10;
        if (r.Sort_Order__c !== want) {
            rows.push({ Content_Address__c: r.Content_Address__c, Sort_Order__c: want,
                        _was: r.Sort_Order__c, _sec: r.Section_Key__c, _f: r.Field_Key__c });
        }
    }
}

if (!rows.length) { console.log('Nothing to renumber.'); process.exit(0); }
rows.sort((a, b) => (a._sec + a.Sort_Order__c).localeCompare(b._sec + b.Sort_Order__c));
for (const r of rows) console.log(`  ${r._sec}::${r._f}  ${r._was} -> ${r.Sort_Order__c}`);
const cols = ['Content_Address__c', 'Sort_Order__c'];
writeFileSync(outCsv, [cols.join(','), ...rows.map((r) => cols.map((c) => r[c]).join(','))].join('\n') + '\n');
console.log(`\n${rows.length} rows written to ${outCsv}`);
