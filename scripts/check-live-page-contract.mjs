/**
 * Checks a page as it actually exists in the org, not as it is seeded on disk.
 *
 * scripts/check-content-contract.py checks the seed files. That catches a bad
 * seed, and nothing else: an org drifts the moment anyone edits a page in the
 * CMS, changes a section's layout, or adds a section by hand. This asks the org
 * the same three questions the seed checker asks the files —
 *
 *   is every field the layout renders backed by a record (or is the page
 *   silently falling back)? is every record still rendered by something (or is
 *   it a dead row an editor can type into for no effect)? does each record's
 *   type match how the layout resolves it?
 *
 * Industry_Key__c does not mean "extra". On a configurator it scopes an
 * override of a page-wide field, but on the industry chooser it is the row's
 * only scope: an industry-tile section has one industry and its rows carry it.
 * Skipping those rows reported every tile on the chooser as unbacked. So a
 * field is satisfied by any active row for it, and duplicates across industries
 * are overrides rather than dead rows.
 *
 * Usage: scripts/lwc-node-harness.sh, then
 *   node <dir>/check-live-page-contract.mjs <offeringKey> <templateType> [orgAlias]
 *
 * The org alias is needed because the harness runs outside the project
 * directory, and that is where the sf CLI keeps its default target; without it
 * every query fails with NoDefaultEnvError. SF_TARGET_ORG works too.
 */
import { execFileSync } from 'node:child_process';
import { LAYOUT_FIELDS } from 'c/gtmPageLayouts';

const [offering, template, orgArg] = process.argv.slice(2);
if (!offering || !template) throw new Error('usage: check-live-page-contract.mjs <offeringKey> <templateType> [orgAlias]');
const org = orgArg || process.env.SF_TARGET_ORG || '';
const BUCKETS = ['text', 'rich', 'json', 'icontext'];

const query = (soql) => {
    const args = ['data', 'query', '-q', soql, '--json'];
    if (org) args.push('--target-org', org);
    let out;
    try {
        out = execFileSync('sf', args, { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (e) {
        // The CLI reports SOQL and auth failures on stdout as JSON and exits
        // non-zero; the stack trace node prints instead buries the reason.
        const body = (e.stdout || '').toString();
        let why = body;
        try { why = JSON.parse(body).message; } catch (_) { /* not JSON */ }
        throw new Error(`sf data query failed: ${why}`);
    }
    return JSON.parse(out).result.records;
};

const where = `Offering_Key__c='${offering}' AND Template_Type__c='${template}' AND Active__c=true`;
const sections = query(`SELECT Section_Key__c, Layout_Type__c FROM MA_Page_Section__c WHERE ${where}`);
const content = query(`SELECT Section_Key__c, Field_Key__c, Field_Type__c, Industry_Key__c FROM MA_Page_Content__c WHERE ${where}`);

const bad = [];
const expected = new Map();
for (const s of sections) {
    const spec = LAYOUT_FIELDS[s.Layout_Type__c];
    if (!spec) { bad.push(`section '${s.Section_Key__c}' has layout '${s.Layout_Type__c}', which LAYOUT_FIELDS does not define`); continue; }
    for (const b of BUCKETS) for (const f of (spec[b] || [])) expected.set(`${s.Section_Key__c}::${f}`, b);
}

const present = new Set();
const sectionKeys = new Set(sections.map((s) => s.Section_Key__c));
for (const c of content) {
    const key = `${c.Section_Key__c}::${c.Field_Key__c}`;
    present.add(key);
    const want = expected.get(key);
    const scope = c.Industry_Key__c ? ` (industry '${c.Industry_Key__c}')` : '';
    if (want === undefined) {
        bad.push(`'${key}'${scope} has a record but ${sectionKeys.has(c.Section_Key__c) ? 'no layout renders it' : `its section is gone`} (dead row)`);
    } else if (want !== c.Field_Type__c) {
        bad.push(`'${key}'${scope} is stored as '${c.Field_Type__c}' but the layout resolves it as '${want}'`);
    }
}
for (const [k, t] of expected) if (!present.has(k)) bad.push(`'${k}' is rendered but has no record — the page falls back to a built-in default`);

console.log(`${offering}::${template} — ${sections.length} sections, ${expected.size} fields expected, ${present.size} distinct fields backed, ${content.length} records`);
if (bad.length) { console.log(`\nLIVE CONTRACT VIOLATIONS (${bad.length}):`); bad.forEach((b) => console.log('  x ' + b)); process.exit(1); }
console.log('\nLive contract holds.');
