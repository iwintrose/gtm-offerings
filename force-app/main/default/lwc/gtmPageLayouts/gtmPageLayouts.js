/**
 * The layout design system, in one place.
 *
 * A layout type is a shape the page knows how to draw, and the field
 * vocabulary below is that shape's contract: the renderer (c/gtmStory) resolves
 * against it, the editor (c/gtmContentManager) creates records from it, and
 * scripts/check-content-contract.py asserts the seeded data matches it.
 *
 * It lives here rather than inside the renderer because the editor has to know
 * what a new section needs before that section exists. Two copies of this map
 * would drift the first time a layout gained a field.
 */

import { CHAPTERS } from 'c/gtmConfiguratorCopy';

// Layouts that render around the page rather than in the section sequence.
// They are declared here so the contract check covers them like any other.
// They are split so an editor can see what they are changing: with both in one
// section, selecting it scrolled the preview to the masthead whether you were
// editing the brand name or the footer.
//
// The assistant is here for the same reason and one more: it is a control the
// page carries, not a beat in the page. One per page, never added twice, and
// the page's own renderer decides where it sits.
const FRAME_LAYOUTS = ['page-header', 'page-footer', 'assistant'];

// Pages that belong to the framework rather than to any one offering. The
// offerings front door is the example: it sits above offerings and lists them,
// so it cannot be owned by one. Keyed like an offering so one schema, one
// reader and one editor cover both.
const FRAMEWORK_KEY = 'gtm';

const LAYOUT_FIELDS = {
    'page-header': { text: ['brandLabel', 'brandTag'],       rich: [], json: [] },
    'page-footer': { text: ['footerLeft', 'footerRight'],     rich: [], json: [] },
    'hero':        { text: ['eyebrow'],                      rich: ['headline', 'subhead'],        json: [] },
    'lede-chips':  { text: ['eyebrow'],                      rich: ['lede', 'close'],              json: ['chips'] },
    'route-proof': { text: ['eyebrow', 'proofDemoRoot', 'proofObjectsCount', 'proofDepsCount', 'proofHealthScore'], rich: ['head', 'sub', 'proofCtaText'], json: ['routeSteps', 'proofDemoDeps'] },
    'card-grid':   { text: ['eyebrow', 'head'],              rich: ['bonusCard'],                  json: ['cards'] },
    'stat':        { text: ['eyebrow', 'head', 'statBig'],   rich: ['statDesc', 'note'],           json: [] },
    'use-pitch':   { text: ['eyebrow', 'head'],              rich: ['lede'],                       json: ['useCases', 'pitchOldChips', 'pitchNewChips'] },
    'faq':         { text: ['eyebrow', 'head'],              rich: [],                             json: ['items'] },
    'closing':     { text: [], rich: ['head', 'sub'], json: [], icontext: ['ctaLabel'] },
    // One offering's entry on the offerings page: how it introduces itself.
    'offering-tile': { text: ['mark', 'name'], rich: ['description'], json: [] },
    // The defaults a configurator starts from before a rep customises it.
    'offering-defaults': {
        text: ['defaultSourcePlatform', 'defaultTargetPlatform', 'defaultAssetCount',
               'defaultDependencyCount', 'defaultHealthScore', 'genericDemoRoot'],
        rich: [],
        json: ['genericDemoDeps', 'genericChips', 'swatches', 'sizePresets']
    },
    // The helper in the corner of a configurator: who it is and what it says
    // before anyone has typed. It lives on the offering's own configurator
    // page, so a second offering gets its own character and its own opening
    // line rather than inheriting this one's.
    'assistant': {
        text: ['assistantName', 'assistantRole', 'fabLabel', 'greeting', 'inputPlaceholder'],
        rich: [],
        json: [],
        // A bounded choice, not free text: the content author picks one of a
        // fixed set of pre-written tone sentences (c/GtmAgentTone.TONE_CLAUSES
        // in Apex owns the actual wording; AGENT_TONE_OPTIONS below is the
        // matching option list for the dropdown -- keep the two key sets in
        // lockstep, see the comment on AGENT_TONE_OPTIONS).
        enum: ['agentTone']
    },
    // The configurator's chapters. Each one is a beat of the page a BD sends a
    // prospect, and each was typed into the template until it became a
    // section: unreachable from the editor, and identical for every offering
    // that ever used this template.
    'chapter-cards':  { text: ['eyebrow'], rich: ['head', 'lede'], json: ['cards'] },
    'chapter-lede':   { text: ['eyebrow'], rich: ['head', 'lede'], json: [] },
    'chapter-proof': {
        text: ['eyebrow', 'panelTitle', 'ctaLabel', 'assetsLabel', 'healthLabel',
               'depsLabel', 'depHead', 'statusLine'],
        rich: ['head', 'lede', 'ctaText', 'foot'],
        json: []
    },
    'chapter-phases': { text: ['eyebrow', 'footnote'], rich: ['head', 'lede'], json: ['phases'] },
    'chapter-close': {
        text: ['eyebrow', 'ctaLabel', 'altCtaLabel', 'altCtaUrl'],
        rich: ['head', 'cardHead', 'body'],
        json: []
    },
    // One industry, in the one place that owns industries.
    //
    // This used to be split: the framework held the name and the picker blurb,
    // and each offering's configurator held six more sections saying what that
    // offering says to each industry. The configurator draws ONE cover, not
    // six, so the editor listed six sections for a single element of the page
    // and an industry's copy lived in two places at once. It lives here.
    'industry-tile': {
        text: ['industryLabel', 'whyHead', 'demoRoot'],
        rich: ['pickerBlurb', 'coverSub', 'problem', 'useCase', 'solution', 'proofLine', 'whyLine'],
        json: ['uniquePoints', 'demoDeps']
    },
    // How one offering pitches itself to one industry. This is offering copy,
    // not taxonomy: it lives on that offering's configurator page, so two
    // offerings can say different things about the same industry.
    'industry-profile': {
        text: ['whyHead', 'demoRoot'],
        rich: ['coverSub', 'problem', 'useCase', 'solution', 'proofLine', 'whyLine'],
        json: ['uniquePoints', 'demoDeps']
    }
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
    'closing': 'Closing call to action',
    'offering-tile': 'Offering tile',
    'offering-defaults': 'Configurator defaults',
    'industry-tile': 'Industry',
    'industry-profile': 'Industry angle',
    'assistant': 'Assistant',
    'chapter-cards': 'Chapter with cards',
    'chapter-lede': 'Chapter, text only',
    'chapter-proof': 'Chapter with proof panel',
    'chapter-phases': 'Chapter with phases',
    'chapter-close': 'Chapter with the ask'
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
    'closing': 'Final headline, subhead, and a call-to-action button.',
    'offering-tile': 'The short badge, name and description shown on the offerings page.',
    'offering-defaults': 'What a configurator shows before a rep customises it: platforms, counts, demo and colour swatches.',
    'industry-tile': 'One industry in the shared list: its name and the blurb on its card.',
    'industry-profile': 'What this offering says to one industry: their problem, the solution, the proof and the demo.',
    'assistant': 'The helper in the corner of this page: its name, its role, the label on its button, the line it opens with, the prompt in its input, and the tone it answers in.',
    'chapter-cards': 'A chapter: eyebrow, heading, a lede, and a row of cards.',
    'chapter-lede': 'A chapter that is just the eyebrow, heading and a lede.',
    'chapter-proof': 'The live proof panel and every word around it. The numbers come from the defaults or the saved link.',
    'chapter-phases': 'A chapter whose body is the phases of an engagement.',
    'chapter-close': 'The last chapter: the ask, the button and the link beside it.'
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
    ['text', 'rich', 'json', 'icontext', 'enum'].forEach((fieldType) => {
        (spec[fieldType] || []).forEach((fieldKey) => {
            out.push({ fieldKey, fieldType, label: humaniseFieldKey(fieldKey) });
        });
    });
    return out;
}

/**
 * A readable starting label for a field the editor has just created. Labels are
 * data (GTM_Page_Content__c.Label__c) and editable afterwards; this only decides
 * what they say before anyone has renamed them, so that a new section reads as
 * "Cta Label" rather than "ctaLabel".
 */
function humaniseFieldKey(key) {
    return String(key)
        .replace(/([A-Z])/g, ' $1')
        .replace(/^./, (c) => c.toUpperCase())
        .trim();
}

/**
 * Which layouts each page's renderer can actually draw.
 *
 * Offering every layout on every page was harmless while the vocabulary was
 * one shared story shape. It stopped being harmless when the configurator got
 * chapters: a chapter added to a story page is a section the story renderer
 * has no branch for, so it saves, publishes, and draws nothing. The picker
 * asks the renderer's own list instead.
 *
 * A template not listed here gets everything that is not page chrome, which is
 * the old behaviour and the right default for a renderer that loops over
 * whatever sections it is given.
 */
const TEMPLATE_LAYOUTS = {
    story: ['hero', 'lede-chips', 'route-proof', 'card-grid', 'stat', 'use-pitch', 'faq', 'closing'],
    configurator: ['chapter-cards', 'chapter-lede', 'chapter-proof', 'chapter-phases',
                   'chapter-close', 'offering-defaults'],
    'offerings-listing': ['offering-tile'],
    // The offerings page draws its tiles from the offerings themselves, so
    // there is nothing to add to it beyond the chrome it already has.
    'offerings-page': [],
    'industry-chooser': ['industry-tile'],
    // Each app's help panel is one section, in the one layout that already
    // knows how to hold a list of questions and answers — no new layout type
    // needed for a shape the story page already draws.
    'faq-bd': ['faq'],
    'faq-content-manager': ['faq'],
    // The assistant settings page is exactly its one frame-layout section and
    // nothing else -- there is no beat to add a second thing to.
    assistant: []
};

// Layouts an editor may add to a page. The header, footer and assistant are
// excluded: they are not beats in the sequence, and a second one would render
// a second masthead.
function addableLayouts(templateType) {
    const allowed = TEMPLATE_LAYOUTS[templateType];
    const keys = allowed
        ? allowed.filter((k) => LAYOUT_FIELDS[k])
        : Object.keys(LAYOUT_FIELDS).filter((k) => FRAME_LAYOUTS.indexOf(k) === -1);
    return keys
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

/**
 * The bounded set of tones GUS can answer in, for the assistant::agentTone
 * dropdown (c/gtmFieldEditor's lightning-combobox for fieldType 'enum').
 *
 * This is a menu of pre-written sentences, not a text field: a content
 * author selects one of these keys, never supplies prompt wording of their
 * own. c/GtmAgentTone.TONE_CLAUSES (Apex) owns the actual sentence text and
 * is the real allow-list/safety backstop -- these labels are only what the
 * dropdown shows. THE KEYS HERE MUST MATCH TONE_CLAUSES' KEYS EXACTLY; there
 * is no shared source of truth across Apex/JS in this codebase (same as
 * every other cross-language constant here), so keep the two lists in
 * lockstep by hand.
 */
const AGENT_TONE_OPTIONS = [
    { value: 'professional-concise', label: 'Professional & concise' },
    { value: 'warm-consultative',    label: 'Warm & consultative' },
    { value: 'direct-executive',     label: 'Direct & executive' },
    { value: 'technical-precise',    label: 'Technical & precise' }
];


/**
 * What a page is made of when it is first created.
 *
 * A template is a starting shape, not a fixed one: these sections are created
 * so a new page opens with something to edit rather than an empty rail, and
 * every one of them can then be renamed, reordered, added to or removed. The
 * three pages beyond the story reuse the story's own layouts — a listing is a
 * heading and a grid of cards whatever it is listing — which is the whole
 * claim of the layout system, so no new layout types are needed to model them.
 */
const STARTER_PAGES = {
    'story': [
        { sectionKey: 'header',  label: 'Header',        layoutType: 'page-header', width: 'standard', helpText: 'The brand name and tag shown in the masthead.' },
        { sectionKey: 'hero',    label: 'Hero',          layoutType: 'hero',        width: 'standard', helpText: 'The first screen: eyebrow, headline and the one line saying what this is.' },
        { sectionKey: 'problem', label: 'The Problem',   layoutType: 'lede-chips',  width: 'standard', helpText: 'What the reader recognises before you have said anything about the offering.' },
        { sectionKey: 'closing', label: 'Closing CTA',   layoutType: 'closing',     width: 'standard', helpText: 'The last screen and the button.' },
        { sectionKey: 'footer',  label: 'Footer',        layoutType: 'page-footer', width: 'standard', helpText: 'The two lines along the bottom of the page.' }
    ],
    'offerings-listing': [
        { sectionKey: 'tile', label: 'Offerings page entry', layoutType: 'offering-tile', width: 'standard', helpText: 'How this offering introduces itself on the offerings page that lists them all.' }
    ],
    'industry-chooser': [
        { sectionKey: 'header',     label: 'Header',     layoutType: 'page-header', width: 'standard', helpText: 'The brand name and tag shown in the masthead.' },
        { sectionKey: 'intro',      label: 'Intro',      layoutType: 'hero',        width: 'standard', helpText: 'Step label, heading and the line under it.' },
        { sectionKey: 'industries', label: 'Industries', layoutType: 'card-grid',   width: 'standard', helpText: 'One card per industry offered.' },
        { sectionKey: 'footer',     label: 'Footer',     layoutType: 'page-footer', width: 'standard', helpText: 'The two lines along the bottom of the page.' }
    ],
    // Framework-level, not offering-level: the page above the offerings.
    'offerings-page': [
        { sectionKey: 'header', label: 'Header', layoutType: 'page-header', width: 'standard', helpText: 'The brand name and tag shown in the masthead.' },
        { sectionKey: 'intro',  label: 'Intro',  layoutType: 'hero',        width: 'standard', helpText: 'Step label, heading and the line under it. The tiles below come from each offering.' },
        { sectionKey: 'footer', label: 'Footer', layoutType: 'page-footer', width: 'standard', helpText: 'The two lines along the bottom of the page.' }
    ],
    // The help panel inside each app. One section, the same 'faq' layout the
    // story page already uses — a heading plus a list of questions and
    // answers, nothing else.
    'faq-bd': [
        { sectionKey: 'faq', label: 'FAQ', layoutType: 'faq', width: 'standard', helpText: 'The questions and answers shown in the BD app’s help panel.' }
    ],
    'faq-content-manager': [
        { sectionKey: 'faq', label: 'FAQ', layoutType: 'faq', width: 'standard', helpText: 'The questions and answers shown in the Content Manager app’s help panel.' }
    ],
    // D8: Gus the assistant, framework-wide rather than pinned to one
    // offering's configurator. One frame-layout section, addressed
    // gtm::assistant::assistant -- not reachable through "New framework
    // page" (see SETTINGS_TEMPLATES in c/gtmContentHome), but modelled here
    // for the same reason every other framework page is: so createPage can
    // rebuild it from nothing if it is ever deleted.
    assistant: [
        { sectionKey: 'assistant', label: 'Assistant', layoutType: 'assistant', width: 'standard', helpText: 'The one assistant character every offering’s configurator shows: name, role, greeting, button label and input prompt.' }
    ],
    'configurator': [
        { sectionKey: 'header',   label: 'Header',       layoutType: 'page-header', width: 'standard', helpText: 'The brand name and tag shown in the masthead.' },
        { sectionKey: 'cover',    label: 'Cover',        layoutType: 'chapter-lede', width: 'standard', helpText: 'The opening screen. The line about the industry comes from the industry itself, edited on the framework\u2019s Industry Chooser.' },
        // The chapters, in the order the page draws them. They come from the
        // renderer's own copy module so that adding a chapter is one edit, not
        // three that have to agree.
        ...CHAPTERS.map((c) => ({
            sectionKey: c.sectionKey,
            label: c.label,
            layoutType: c.layoutType,
            width: 'standard',
            helpText: c.helpText
        })),
        // In the order the page draws them: the assistant floats above the
        // footer, so it is listed above it too.
        { sectionKey: 'assistant', label: 'Assistant',   layoutType: 'assistant',   width: 'standard', helpText: 'The helper in the corner of this page. Only the rep sees it; a prospect on a shared link does not.' },
        { sectionKey: 'footer',   label: 'Footer',       layoutType: 'page-footer', width: 'standard', helpText: 'The two lines along the bottom of the page.' },
        { sectionKey: 'defaults', label: 'Configurator defaults', layoutType: 'offering-defaults', width: 'standard', helpText: 'Settings, not a beat of the page: what it shows before a rep customises it — platforms, counts, the demo campaign and the colour swatches.' },
    ]
};

/** The starter sections for a template, each with the fields its layout declares. */
function starterFor(templateType) {
    return (STARTER_PAGES[templateType] || []).map((s) => ({
        ...s,
        fields: fieldsFor(s.layoutType)
    }));
}


/**
 * Which pages exist under a given owner.
 *
 * The framework owns the page that lists offerings; an offering owns the pages
 * that describe it. Offering a framework a "story" or an offering an
 * "offerings page" would both be nonsense, so the picker asks this rather than
 * showing one fixed list.
 */
// Industries are a shared taxonomy — fintech and medtech are not facts about
// Migration Accelerator — so the list of them, and the chooser page that shows
// it, belong to the framework. What an offering *says* to an industry is not
// taxonomy: that copy lives on that offering's own configurator page, one
// section per industry, so two offerings can pitch the same industry
// differently.
const OFFERING_TEMPLATES = ['story', 'configurator', 'offerings-listing'];
// B1: the static, CMS-editable FAQ panel each app carries. Framework-level —
// the panel is chrome for the app itself, not copy about an offering — so it
// lives beside the offerings page and the industry chooser rather than under
// migration-accelerator or any other single offering.
//
// D8: 'assistant' joins this list for the same reason -- Gus is one character
// shared by every offering's configurator, not copy that belongs to
// migration-accelerator, so his name/role/greeting move to the framework. He
// is a setting rather than a page (nobody reads him top to bottom the way they
// read the offerings page), which is why c/gtmContentHome renders him apart
// from the pages list even though he is registered here beside them.
const FRAMEWORK_TEMPLATES = ['offerings-page', 'industry-chooser', 'faq-bd', 'faq-content-manager', 'assistant'];

function templatesFor(offeringKey) {
    return offeringKey === FRAMEWORK_KEY ? FRAMEWORK_TEMPLATES : OFFERING_TEMPLATES;
}

const TEMPLATE_LABELS = {
    story: 'Story',
    configurator: 'Configurator',
    'industry-chooser': 'Industry Chooser',
    'offerings-listing': 'Offerings Listing',
    'offerings-page': 'Offerings Page',
    'faq-bd': 'BD App Help (FAQ)',
    'faq-content-manager': 'Content Manager Help (FAQ)',
    assistant: 'Assistant'
};


export {
    OFFERING_TEMPLATES,
    FRAMEWORK_TEMPLATES,
    TEMPLATE_LABELS,
    templatesFor,
    FRAMEWORK_KEY,
    STARTER_PAGES,
    starterFor,
    CTA_ICONS,
    ctaGlyph,
    AGENT_TONE_OPTIONS,
    FRAME_LAYOUTS,
    TEMPLATE_LAYOUTS,
    LAYOUT_FIELDS,
    LAYOUT_LABELS,
    LAYOUT_HINTS,
    fieldsFor,
    humaniseFieldKey,
    addableLayouts
};
