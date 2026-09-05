/**
 * The configurator's chapters, and what each one says before anyone edits it.
 *
 * The configurator draws nine beats. Six of them used to be typed straight
 * into the template, which meant they were not sections: they did not appear
 * in the editor's rail, could not be reordered, and could not be changed for a
 * second offering without changing this component. The page a BD sends to a
 * prospect was, for two thirds of its length, a constant.
 *
 * Every string below is now the *fallback* for a content field. The seeded
 * records carry these same words, so the live page reads exactly as it did;
 * the difference is that an editor can now change them, per offering, and the
 * component keeps working if a record is missing.
 *
 * This lives beside the renderer rather than inside it because three other
 * things need it: the layout registry (which sections a new configurator
 * starts with), the seed generator (scripts/gen-configurator-seed.py), and the
 * contract checker. One copy, four readers.
 */

/**
 * Ordered. sectionKey is the address every content row hangs off, so it is not
 * free to change once seeded; label and helpText are what the editor's rail
 * shows, and are data afterwards.
 */
const CHAPTERS = [
    {
        sectionKey: 'partner',
        label: 'How we work with you',
        layoutType: 'chapter-cards',
        helpText: 'Chapter 01. Who is behind the Accelerator, and the three things they do.',
        fields: {
            eyebrow: '01 — How we work with you',
            head: 'A migration partner first.<br />The Accelerator is how we prove it.',
            lede: "Publicis Sapient runs your migration end-to-end — strategy, data, and engineering under one team, not a tool handed off and left to your side of the table. The Migration Accelerator isn't a separate product we're selling; it's the same platform our own delivery teams use to ground every engagement in evidence, from the first conversation through a live cutover.",
            cards: [
                { title: 'Strategy & business case', body: 'Our Virtual Lab reads the business case decks, briefs, and goals docs you already have, so strategy starts from your context, not a blank page.' },
                { title: 'Environment assessment', body: 'The Accelerator reads your live platform directly and scores it, every asset, every dependency, an audited health check.' },
                { title: 'Delivery & build', body: 'One team carries it through, and for supported objects, all the way to a finished cutover with rollback on standby.' }
            ]
        }
    },
    {
        sectionKey: 'challenge',
        label: 'The challenge',
        layoutType: 'chapter-lede',
        helpText: 'Chapter 02. The problem, in the generic case. An industry on this page replaces the lede with its own.',
        fields: {
            eyebrow: '02 — The challenge',
            head: 'Migrations stall<br />in the dark.',
            lede: "Years of campaigns, built by people who've since moved on. No map of what connects to what. A go-live date that won't move. The hardest part of a migration usually isn't the rebuild, it's not knowing what you actually have before you start."
        }
    },
    {
        sectionKey: 'approach',
        label: 'Our approach',
        layoutType: 'chapter-cards',
        helpText: 'Chapter 03. How the Accelerator works, and the three claims made for it.',
        fields: {
            eyebrow: '03 — Our approach',
            head: 'We read your environment first.<br />Then we build the plan.',
            lede: 'The Migration Accelerator ingests your platform and audits it automatically, turning it into one clear model and a health score, so every decision about what moves, what changes, and what retires is grounded in what’s genuinely there.',
            cards: [
                { title: 'Faster', body: 'A real, audited read on your whole environment in about an hour, not the usual weeks of discovery.' },
                { title: 'Evidence-based', body: 'Every scope and estimate traces back to your actual data, with a full audit trail on every decision.' },
                { title: 'Lower risk', body: "We size, sequence, and where it applies, execute from what's really there, dry-run first, rollback ready." }
            ]
        }
    },
    {
        sectionKey: 'proof',
        label: 'See it',
        layoutType: 'chapter-proof',
        helpText: 'Chapter 04. The live proof panel: what the numbers stand for and the words around them. The numbers themselves come from Configurator defaults or the saved link.',
        fields: {
            eyebrow: '04 — See it',
            head: 'Everything you have, mapped,<br />audited, and ready to move.',
            lede: "Point the Accelerator at your environment and it does the archaeology for you: counts every asset, scores its health, and traces what depends on what. Here's a preview of what an assessment surfaces.",
            panelTitle: 'Environment assessment',
            ctaText: "A snapshot of what the Accelerator reads from a client's environment, automatically, on day one.",
            ctaLabel: 'Reveal what the Accelerator sees →',
            assetsLabel: 'assets mapped',
            healthLabel: 'health score',
            depsLabel: 'dependencies traced',
            depHead: 'One campaign, and everything it needs to run',
            foot: 'You choose one campaign. The Accelerator brings <span class="accent">&nbsp;everything it depends on&nbsp;</span> with it, so nothing gets left behind at go-live.',
            statusLine: 'dry run complete · rollback armed'
        }
    },
    {
        sectionKey: 'deliverables',
        label: 'What you get',
        layoutType: 'chapter-cards',
        helpText: 'Chapter 05. The numbered deliverables. Numbering follows the order of the cards.',
        fields: {
            eyebrow: '05 — What you get',
            head: 'Deliverables you can act on.',
            lede: '',
            cards: [
                { title: 'Environment assessment', body: 'A complete, categorized inventory of your marketing estate, surfaced automatically, not hand-built.' },
                { title: 'An audited health score', body: 'An evidence-based read of size, complexity, and risk, the numbers your estimate and business case can stand on.' },
                { title: 'Dependency-aware migration plan', body: 'A sequenced plan where shared assets are built once and nothing ships broken.' },
                { title: 'A live cutover, where it applies', body: "Dry-run first, then executed, with rollback ready and a verification pass once it's done." }
            ]
        }
    },
    {
        sectionKey: 'engagement',
        label: 'How we work together',
        layoutType: 'chapter-phases',
        helpText: 'Chapter 06. The four phases of the engagement, and the line under them.',
        fields: {
            eyebrow: '06 — How we work together',
            head: 'Start small. Prove it. Scale.',
            lede: "You don't have to commit to the whole migration to see the value. It begins with a focused environment assessment, low commitment, high signal, and grows from there.",
            footnote: 'Your first step is just the assessment.',
            phases: [
                { step: 'Start here', title: 'Assess',    body: 'A fixed-scope read of your environment, and a health score you can act on.' },
                { step: 'Design',     title: 'Blueprint', body: 'What moves, what changes, what retires, decided with you, backed by data.' },
                { step: 'Sequence',   title: 'Plan',      body: 'A dependency-aware, wave-by-wave plan your teams can execute against.' },
                { step: 'Build',      title: 'Execute',   body: 'Build-ready specs, and for supported objects, a live cutover with rollback.' }
            ]
        }
    },
    {
        sectionKey: 'why',
        label: 'Why Publicis Sapient',
        layoutType: 'chapter-cards',
        helpText: 'Chapter 07. The case for the firm. An industry on this page can override the heading and add a line of its own.',
        fields: {
            eyebrow: '07 — Why Publicis Sapient',
            head: 'Martech depth, plus a platform no one else brings.',
            lede: '',
            cards: [
                { title: 'Deep platform expertise', body: 'Years of hands-on marketing automation delivery across global, regulated enterprises.' },
                { title: 'A platform, not just hands', body: 'Our AI-powered Accelerator does the discovery, audit, and increasingly the cutover, work that normally burns months of effort.' },
                { title: 'End-to-end partnership', body: 'Strategy, data, and engineering under one roof, from the first assessment through go-live and beyond.' }
            ]
        }
    },
    {
        sectionKey: 'closing',
        label: 'The next step',
        layoutType: 'chapter-close',
        helpText: 'Chapter 08. The ask, the button, and the second link beside it.',
        fields: {
            eyebrow: '08 — The next step',
            head: "See what's really in<br />your environment.",
            cardHead: 'Start with an environment assessment.',
            body: "Even if you're only exploring, you'll walk away with a genuine, audited read on your migration, the size, the risk, the effort, whether or not we go further. No months of discovery required.",
            ctaLabel: 'Book the assessment →',
            altCtaLabel: 'Explore Publicis Sapient',
            altCtaUrl: 'https://www.publicissapient.com'
        }
    }
];

/** The chapter defaults, keyed by section, for the renderer's fallbacks. */
const CHAPTER_DEFAULTS = CHAPTERS.reduce((acc, c) => {
    acc[c.sectionKey] = c.fields;
    return acc;
}, {});

export { CHAPTERS, CHAPTER_DEFAULTS };
