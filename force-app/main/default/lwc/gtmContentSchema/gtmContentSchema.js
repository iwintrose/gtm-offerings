/**
 * Human-readable labels and display order for GTM Content Manager, keyed by
 * template type. Purely presentational -- the underlying MA_Page_Content__c
 * records are unaffected; a field/section with no entry here just falls
 * back to its raw key and insertion order, so new content never breaks the
 * editor while waiting to be added here.
 */

const STORY_SECTIONS = {
    hero: { label: 'Hero', order: 1, help: 'The first thing a visitor sees at the top of the page.' },
    problem: { label: 'The Problem', order: 2, help: "What's broken about the status quo -- sets up the pitch." },
    bd: { label: 'BD Pitch', order: 3, help: 'The before/after case for switching, plus real-world use cases.' },
    mechanism: { label: 'How It Works', order: 4, help: 'The actual steps of the migration process.' },
    capabilities: { label: 'Capabilities', order: 5, help: 'The feature/capability cards shown on the page.' },
    clientProfile: { label: 'Client Proof Point', order: 6, help: 'A stat or note proving this works for real clients.' },
    closing: { label: 'Closing CTA', order: 7, help: 'The final call-to-action at the bottom of the page.' }
};

const STORY_FIELDS = {
    'hero::eyebrow': { label: 'Eyebrow', help: 'Small label above the headline.' },
    'hero::headline': { label: 'Headline', help: 'The main hero headline.' },
    'hero::subhead': { label: 'Subheadline', help: 'Supporting line under the headline.' },

    'problem::lede': { label: 'Opening line', help: 'The first line making the case that something is broken.' },
    'problem::chips': { label: 'Pain points', help: 'Short pain-point chips, e.g. "A decade of undocumented campaigns".' },
    'problem::close': { label: 'Closing line', help: 'Wraps up the problem section before moving to the pitch.' },

    'bd::head': { label: 'Section heading', help: '' },
    'bd::lede': { label: 'Opening line', help: '' },
    'bd::useCases': { label: 'Use cases', help: 'Title + description pairs, e.g. Presales / Delivery.' },
    'bd::pitchOldChips': { label: 'Old way (before)', help: 'Chips describing the old, broken way of doing things.' },
    'bd::pitchNewChips': { label: 'New way (after)', help: 'Chips describing what this offering replaces it with.' },

    'mechanism::head': { label: 'Section heading', help: '' },
    'mechanism::sub': { label: 'Subheading', help: '' },
    'mechanism::routeSteps': { label: 'Process steps', help: 'Step label + description pairs, e.g. Ingest / Audit / Decide / Plan.' },
    'mechanism::proofCtaText': { label: 'Proof CTA text', help: 'Call-to-action text near the live demo/proof.' },
    'mechanism::proofDemoRoot': { label: 'Demo root asset', help: 'The root asset name shown in the live demo.' },
    'mechanism::proofDemoDeps': { label: 'Demo dependencies', help: 'Chips listing dependent assets shown in the demo.' },

    'capabilities::cards': { label: 'Capability cards', help: 'Icon + title + description, one card per capability.' },
    'capabilities::bonusCard': { label: 'Bonus card', help: 'Extra highlighted card at the end of the row.' },

    'clientProfile::statBig': { label: 'Big stat', help: 'The large number/stat, e.g. "40%".' },
    'clientProfile::statDesc': { label: 'Stat description', help: 'What the big stat means.' },
    'clientProfile::note': { label: 'Client note', help: 'A supporting quote or note.' },

    'closing::head': { label: 'Closing headline', help: '' },
    'closing::sub': { label: 'Closing subheading', help: '' }
};

const SCHEMA = {
    story: { sections: STORY_SECTIONS, fields: STORY_FIELDS }
};

function forTemplate(templateType) {
    return SCHEMA[templateType] || { sections: {}, fields: {} };
}

export function sectionMeta(templateType, sectionKey) {
    const entry = forTemplate(templateType).sections[sectionKey];
    return {
        label: entry ? entry.label : sectionKey,
        help: entry ? entry.help : '',
        order: entry ? entry.order : 999
    };
}

export function fieldMeta(templateType, sectionKey, fieldKey) {
    const entry = forTemplate(templateType).fields[`${sectionKey}::${fieldKey}`];
    return {
        label: entry ? entry.label : fieldKey,
        help: entry ? entry.help : ''
    };
}
