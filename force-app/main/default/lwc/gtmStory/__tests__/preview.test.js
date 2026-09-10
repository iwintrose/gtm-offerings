import { createElement } from 'lwc';
import GtmStory from 'c/gtmStory';
import getPageLayout from '@salesforce/apex/GtmPageContentReader.getPageLayout';

const fs = require('fs');
const path = require('path');

const SEED = path.join(__dirname, '..', '..', '..', '..', '..', '..', 'data', 'seed');

/**
 * Rebuild what GtmPageContentReader.getPageLayout would return, from the same
 * seed JSON that populates the org. starterFor('story') was the easy source
 * but it only carries the 5 starter sections — the real page has 10, so half
 * the design was invisible in the preview.
 *
 * Mirrors the Apex exactly: sections ordered by Sort_Order__c, content keyed
 * `sectionKey::fieldKey`, and the value column chosen by Field_Type__c the way
 * GtmPageContentReader.resolveValue does it.
 */
function seedLayout() {
    const read = (f) => JSON.parse(fs.readFileSync(path.join(SEED, f), 'utf8')).records;

    const sections = read('migration-accelerator.story.sections.json')
        .filter((r) => r.Active__c)
        .sort((a, b) => (a.Sort_Order__c ?? 0) - (b.Sort_Order__c ?? 0))
        .map((r) => ({
            sectionKey: r.Section_Key__c,
            label: r.Label__c,
            helpText: r.Help_Text__c,
            layoutType: r.Layout_Type__c,
            width: r.Width__c,
            sortOrder: r.Sort_Order__c
        }));

    const content = {};
    const fieldMeta = [];
    read('migration-accelerator.story.records.json')
        .filter((r) => r.Active__c)
        .forEach((r) => {
            const key = `${r.Section_Key__c}::${r.Field_Key__c}`;
            const value =
                r.Field_Type__c === 'rich'
                    ? r.Rich_Value__c
                    : r.Field_Type__c === 'json' || r.Field_Type__c === 'icontext'
                      ? r.JSON_Value__c
                      : r.Text_Value__c;
            if (!(key in content)) content[key] = value;
            fieldMeta.push({
                sectionKey: r.Section_Key__c,
                fieldKey: r.Field_Key__c,
                fieldType: r.Field_Type__c,
                label: r.Label__c
            });
        });

    return { sections, content, fieldMeta };
}

jest.mock('@salesforce/apex/GtmPageContentReader.getPageLayout',
    () => ({ default: jest.fn() }), { virtual: true });

/**
 * Renders the REAL gtmStory and writes a standalone page of it, so a palette
 * change can be looked at in a browser without an org.
 *
 * Same contract as gtmReadoutView/__tests__/preview.test.js: the markup is the
 * component's own shadow DOM dumped verbatim, and the CSS is gtmStory.css read
 * off disk, so this page cannot drift from what ships. Two substitutions are
 * needed that a shadow root gives the component for free and a plain page does
 * not: `:host` becomes `.story-host`, and `<lightning-formatted-rich-text
 * value="X">` — which jest stubs to an empty element — is replaced by a plain
 * div carrying X, without which most of the body prose renders blank.
 *
 * Sections come from starterFor('story') and the copy from the component's own
 * built-in DEFAULTS, so this needs no org and no seed data.
 *
 * Skipped unless STORY_PREVIEW_OUT is set, so a normal test run writes nothing.
 */
const OUT = process.env.STORY_PREVIEW_OUT;
const maybe = OUT ? describe : describe.skip;

maybe('story preview page', () => {
    it('writes a standalone page of the rendered component', async () => {
        const layout = seedLayout();
        getPageLayout.mockResolvedValue(layout);

        const element = createElement('c-gtm-story', { is: GtmStory });
        element.offeringKey = 'migration-accelerator';
        element.previewSections = layout.sections;
        element.previewContent = layout.content;
        element.previewFieldMeta = layout.fieldMeta;
        document.body.appendChild(element);
        await new Promise((resolve) => setTimeout(resolve, 0));

        // Lightning base components are empty stubs under jest, and `value` is
        // set on them as a PROPERTY — it never appears in innerHTML. So swap
        // each one for a plain div carrying its prose in the live DOM, before
        // serializing, or the page photographs blank where the copy should be.
        const swap = (root) => {
            root.querySelectorAll('lightning-formatted-rich-text').forEach((el) => {
                const div = document.createElement('div');
                div.className = 'lfrt';
                div.innerHTML = el.value == null ? '' : String(el.value);
                el.parentNode.replaceChild(div, el);
            });
            root.querySelectorAll('lightning-formatted-text').forEach((el) => {
                const span = document.createElement('span');
                span.textContent = el.value == null ? '' : String(el.value);
                el.parentNode.replaceChild(span, el);
            });
        };
        swap(element.shadowRoot);

        const markup = element.shadowRoot.innerHTML;

        // `@import 'c/x'` is resolved by the LWC compiler, not by a browser —
        // left as-is it would silently do nothing and the page would render
        // with every token undefined. Inline the imported module the same way
        // the compiler does, so the preview shows the real cascade.
        // Strip comments first: gtmBrandTokens.css documents its own usage with
        // a literal `@import 'c/gtmBrandTokens';` line inside its header, and
        // without this the resolver follows that and recurses forever.
        const seen = new Set();
        const readCss = (file) => {
            if (seen.has(file)) return '';
            seen.add(file);
            return fs
                .readFileSync(file, 'utf8')
                .replace(/\/\*[\s\S]*?\*\//g, '')
                .replace(/@import\s+['"]c\/(\w+)['"]\s*;/g, (_whole, name) =>
                    readCss(path.join(__dirname, '..', '..', name, `${name}.css`))
                );
        };

        // `:host(.dark)` must become `.story-host.dark`, not `.story-host(.dark)`,
        // so the functional form has to be rewritten before the bare one.
        const cssPath = path.join(__dirname, '..', 'gtmStory.css');
        const css = readCss(cssPath)
            .replace(/:host\(([^)]*)\)/g, '.story-host$1')
            .replace(/:host\b/g, '.story-host');

        const page = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Story preview — rendered from c-gtm-story</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Lexend+Deca:wght@100..900&family=Roboto+Mono:ital,wght@0,100..700;1,100..700&family=Roboto:ital,wght@0,100..900;1,100..900&family=Sora:wght@300..700&family=IBM+Plex+Sans:wght@300;400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>html,body{margin:0}${css}</style>
</head><body><div class="story-host">${markup}</div>
<script>
(function () {
  var root = document.querySelector('.story-root');
  if (!root) return;
  var q = new URLSearchParams(location.search);
  if (q.get('theme') === 'dark') root.classList.add('dark');
  if (q.get('theme') === 'light') root.classList.add('light');
})();
</script>
</body></html>`;

        fs.mkdirSync(OUT, { recursive: true });
        fs.writeFileSync(path.join(OUT, 'story-preview.html'), page, 'utf8');
        expect(markup.length).toBeGreaterThan(1000);
    });
});
