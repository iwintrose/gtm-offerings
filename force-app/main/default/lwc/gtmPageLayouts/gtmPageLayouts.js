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

// Page chrome (masthead + footer) is a layout so the contract check covers it,
// but it renders around the page rather than in the section sequence.
const CHROME_LAYOUT = 'page-chrome';

const LAYOUT_FIELDS = {
    'page-chrome': { text: ['brandLabel', 'brandTag', 'footerLeft', 'footerRight'], rich: [], json: [] },
    'hero':        { text: ['eyebrow'],                      rich: ['headline', 'subhead'],        json: [] },
    'lede-chips':  { text: ['eyebrow'],                      rich: ['lede', 'close'],              json: ['chips'] },
    'route-proof': { text: ['eyebrow', 'proofDemoRoot'],     rich: ['head', 'sub', 'proofCtaText'], json: ['routeSteps', 'proofDemoDeps'] },
    'card-grid':   { text: ['eyebrow', 'head'],              rich: ['bonusCard'],                  json: ['cards'] },
    'stat':        { text: ['eyebrow', 'head', 'statBig'],   rich: ['statDesc', 'note'],           json: [] },
    'use-pitch':   { text: ['eyebrow', 'head'],              rich: ['lede'],                       json: ['useCases', 'pitchOldChips', 'pitchNewChips'] },
    'faq':         { text: ['eyebrow', 'head'],              rich: [],                             json: ['items'] },
    'closing':     { text: ['ctaLabel'],                     rich: ['head', 'sub'],                json: [] }
};

// What each layout is for, in the words an editor would use. Shown in the
// "add section" picker, where the layout key alone tells you nothing.
const LAYOUT_LABELS = {
    'page-chrome': 'Page Chrome',
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
    'page-chrome': 'Masthead and footer text. One per page.',
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
    ['text', 'rich', 'json'].forEach((fieldType) => {
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

// Layouts an editor may add to a page. Chrome is excluded: it is not a beat in
// the sequence, and a second one would render two mastheads.
function addableLayouts() {
    return Object.keys(LAYOUT_FIELDS)
        .filter((k) => k !== CHROME_LAYOUT)
        .map((k) => ({
            value: k,
            label: LAYOUT_LABELS[k] || k,
            hint: LAYOUT_HINTS[k] || '',
            fieldCount: fieldsFor(k).length
        }));
}

export {
    CHROME_LAYOUT,
    LAYOUT_FIELDS,
    LAYOUT_LABELS,
    LAYOUT_HINTS,
    fieldsFor,
    humaniseFieldKey,
    addableLayouts
};
