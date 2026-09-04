/**
 * The layout design system, in one place.
 *
 * A layout type is a shape the page knows how to draw, and the field
 * vocabulary below is that shape's contract: the renderer (c/maStory) resolves
 * against it, the editor (c/gtmContentManager) creates records from it, and
 * scripts/check-content-contract.py asserts the seeded data matches it.
 *
 * It lives here rather than inside the renderer because the editor has to know
 * what a new section needs before that section exists. Two copies of this map
 * would drift the first time a layout gained a field.
 */

// Layouts that render around the page rather than in the section sequence.
// They are declared here so the contract check covers them like any other.
// They are split so an editor can see what they are changing: with both in one
// section, selecting it scrolled the preview to the masthead whether you were
// editing the brand name or the footer.
const FRAME_LAYOUTS = ['page-header', 'page-footer'];

const LAYOUT_FIELDS = {
    'page-header': { text: ['brandLabel', 'brandTag'],       rich: [], json: [] },
    'page-footer': { text: ['footerLeft', 'footerRight'],     rich: [], json: [] },
    'hero':        { text: ['eyebrow'],                      rich: ['headline', 'subhead'],        json: [] },
    'lede-chips':  { text: ['eyebrow'],                      rich: ['lede', 'close'],              json: ['chips'] },
    'route-proof': { text: ['eyebrow', 'proofDemoRoot'],     rich: ['head', 'sub', 'proofCtaText'], json: ['routeSteps', 'proofDemoDeps'] },
    'card-grid':   { text: ['eyebrow', 'head'],              rich: ['bonusCard'],                  json: ['cards'] },
    'stat':        { text: ['eyebrow', 'head', 'statBig'],   rich: ['statDesc', 'note'],           json: [] },
    'use-pitch':   { text: ['eyebrow', 'head'],              rich: ['lede'],                       json: ['useCases', 'pitchOldChips', 'pitchNewChips'] },
    'faq':         { text: ['eyebrow', 'head'],              rich: [],                             json: ['items'] },
    'closing':     { text: [], rich: ['head', 'sub'], json: [], icontext: ['ctaLabel'] }
};

// What each layout is for, in the words an editor would use. Shown in the
// "add section" picker, where the layout key alone tells you nothing.
const LAYOUT_LABELS = {
    'page-header': 'Header',
    'page-footer': 'Footer',
    'hero': 'Hero',
    'lede-chips': 'Lede with chips',
    'route-proof': 'Route with proof panel',
    'card-grid': 'Card grid',
    'stat': 'Big statistic',
    'use-pitch': 'Use cases and pitch',
    'faq': 'FAQ',
    'closing': 'Closing call to action'
};

const LAYOUT_HINTS = {
    'page-header': 'The brand name and tag in the masthead. One per page.',
    'page-footer': 'The two lines along the bottom of the page. One per page.',
    'hero': 'Opening statement: eyebrow, headline, subhead.',
    'lede-chips': 'A short lede, a row of chips, a closing line.',
    'route-proof': 'A numbered route beside a live proof panel.',
    'card-grid': 'A grid of cards, plus one highlighted bonus card.',
    'stat': 'One large number with a description and a note.',
    'use-pitch': 'Use cases, plus a before/after chip comparison.',
    'faq': 'A list of questions and answers.',
    'closing': 'Final headline, subhead, and a call-to-action button.'
};

/**
 * Every field a layout declares, flattened, each tagged with the value column
 * it resolves from. This is what the editor sends to Apex when it creates a
 * section: the rows to make, in the order they should be edited.
 */
function fieldsFor(layoutType) {
    const spec = LAYOUT_FIELDS[layoutType];
    if (!spec) return [];
    const out = [];
    ['text', 'rich', 'json', 'icontext'].forEach((fieldType) => {
        (spec[fieldType] || []).forEach((fieldKey) => {
            out.push({ fieldKey, fieldType, label: humaniseFieldKey(fieldKey) });
        });
    });
    return out;
}

/**
 * A readable starting label for a field the editor has just created. Labels are
 * data (MA_Page_Content__c.Label__c) and editable afterwards; this only decides
 * what they say before anyone has renamed them, so that a new section reads as
 * "Cta Label" rather than "ctaLabel".
 */
function humaniseFieldKey(key) {
    return String(key)
        .replace(/([A-Z])/g, ' $1')
        .replace(/^./, (c) => c.toUpperCase())
        .trim();
}

// Layouts an editor may add to a page. The header and footer are excluded:
// they are not beats in the sequence, and a second one would render a second
// masthead.
function addableLayouts() {
    return Object.keys(LAYOUT_FIELDS)
        .filter((k) => FRAME_LAYOUTS.indexOf(k) === -1)
        .map((k) => ({
            value: k,
            label: LAYOUT_LABELS[k] || k,
            hint: LAYOUT_HINTS[k] || '',
            fieldCount: fieldsFor(k).length
        }));
}

/**
 * The icons a call-to-action button may carry, and the glyph each one draws.
 *
 * One list, shared by the editor's picker and the renderer, for the same
 * reason the layout vocabulary is shared: a picker offering an icon the page
 * cannot draw is worse than no picker at all.
 */
const CTA_ICONS = [
    { value: '',         label: 'None',          glyph: '' },
    { value: 'arrow',    label: 'Arrow',         glyph: '→' },
    { value: 'external', label: 'External link', glyph: '↗' },
    { value: 'play',     label: 'Play',          glyph: '▶' },
    { value: 'calendar', label: 'Calendar',      glyph: '🗓︎' },
    { value: 'preview',  label: 'Preview',       glyph: '◉' },
    { value: 'check',    label: 'Check',         glyph: '✓' }
];

function ctaGlyph(value) {
    const hit = CTA_ICONS.find((i) => i.value === value);
    return hit ? hit.glyph : '';
}


export {
    CTA_ICONS,
    ctaGlyph,
    FRAME_LAYOUTS,
    LAYOUT_FIELDS,
    LAYOUT_LABELS,
    LAYOUT_HINTS,
    fieldsFor,
    humaniseFieldKey,
    addableLayouts
};
