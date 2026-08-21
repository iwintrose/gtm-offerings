/**
 * Shared content for the Migration Accelerator configurator.
 * Ported verbatim from gtm-offerings/migration-accelerator/configurator.html.
 */

export const INDUSTRIES = {
    fintech: {
        label: 'Financial Services',
        coverSub:
            'For banks and insurers, a migration is a compliance event as much as a technology one. Here’s how we move you without putting consent, disclosures, or audit trails at risk.',
        problem:
            'Your marketing runs under the regulator’s eye. Consent states, suppression lists, disclosure language, and audit trails aren’t metadata, they’re obligations, and in most enterprises they’re spread across a decade of undocumented campaigns.',
        useCase:
            'Take a global retail bank moving off Eloqua: thousands of assets across regions, each carrying consent rules and regional disclosures nobody fully documented.',
        solution:
            'The Accelerator reads the whole environment and preserves what regulators care about, consent, suppression, disclosures, and audit lineage, so nothing compliance-critical is ever rebuilt from memory.',
        unique: [
            'Consent & suppression preserved',
            'Disclosure & audit lineage intact',
            'Data residency across regions'
        ],
        proofLine:
            'Every object mapped with its consent and suppression state, so the plan is defensible, not just fast.',
        whyLine:
            'Deep delivery experience with regulated financial institutions, where a comms error carries real regulatory weight.',
        whyHead: 'Built for regulated financial marketing.',
        demo: {
            root: 'Rate-change notification',
            deps: [
                'Statement email',
                'Disclosure block',
                'Rates data extension',
                'Compliance footer'
            ]
        }
    },
    medtech: {
        label: 'MedTech',
        coverSub:
            'For medical-device organizations, promotional content is regulated content. Here’s how we migrate without losing MLR-approved assets or blurring the HCP/patient line.',
        problem:
            'Every promotional asset has passed MLR review, and HCP and patient audiences must never bleed into each other. A migration that treats them as ordinary emails puts approvals, and compliance, at risk.',
        useCase:
            'Take a global device manufacturer moving to Salesforce: campaigns spanning HCP and patient journeys, each asset tied to an approval record.',
        solution:
            'The Accelerator carries approved content, claims, and the approval records behind them into the new platform, with HCP and patient audiences kept distinct by construction.',
        unique: [
            'MLR-approved content preserved',
            'HCP vs. patient separation',
            'Adverse-event & consent handling'
        ],
        proofLine:
            'Each asset mapped with its approval lineage, so nothing regulated gets rebuilt off-record.',
        whyLine:
            'Hands-on delivery for regulated medical-device marketing, where approval and audience integrity are non-negotiable.',
        whyHead: 'Built for regulated medical-device marketing.',
        demo: {
            root: 'HCP product update',
            deps: [
                'Approved email',
                'ISI safety block',
                'HCP data extension',
                'Brand header'
            ]
        }
    },
    lifesci: {
        label: 'Life Sciences',
        coverSub:
            'For pharma and life sciences, content is regulated and every market differs. Here’s how we migrate without losing approval lineage or market-specific rules.',
        problem:
            'Regulated content, many markets, and Veeva-shaped approval workflows. The risk in a migration isn’t rebuilding an email, it’s losing the approval lineage and the market-by-market rules that make it compliant.',
        useCase:
            'Take a global pharma brand consolidating onto Salesforce: the same campaign expressed differently per market, each version approved separately.',
        solution:
            'The Accelerator preserves approval lineage and market-specific rules as it moves your content, so compliance travels with the campaign, market by market.',
        unique: [
            'Approval lineage kept auditable',
            'Market-by-market content rules',
            'Regulated content-system integration'
        ],
        proofLine:
            'Every market variant mapped with its approval record, so nothing regulated ships unreviewed.',
        whyLine:
            'Global life-sciences delivery experience, across regulated markets and content systems.',
        whyHead: 'Built for regulated, multi-market life sciences.',
        demo: {
            root: 'Patient support program',
            deps: [
                'Approved email — US',
                'Approved email — EU',
                'Consent data extension',
                'Localized footer'
            ]
        }
    },
    media: {
        label: 'Media & Entertainment',
        coverSub:
            'For media and entertainment, the challenge is scale and breadth. Here’s how we migrate dozens of brands and millions of subscribers without a visible seam.',
        problem:
            'Dozens of brands, millions of subscribers, campaigns shipping daily. Shared assets are reused across franchises, and at your scale a single dropped journey is a visible failure to real audiences.',
        useCase:
            'Take a streaming-and-studios group moving onto Salesforce: overlapping brands sharing templates and data, subscriber lifecycles running around the clock.',
        solution:
            'The Accelerator maps the whole estate across brands, finds what’s shared, and sequences the rebuild so subscribers never feel the move, and shared assets are built once, not per brand.',
        unique: [
            'Many brands & business units',
            'Subscriber lifecycle at scale',
            'Shared assets built once across franchises'
        ],
        proofLine:
            'Shared assets found and de-duplicated across brands, built once, never twice.',
        whyLine:
            'Experience delivering personalization and lifecycle at consumer-media scale.',
        whyHead: 'Built for personalization at media scale.',
        demo: {
            root: 'New season launch',
            deps: [
                'Announcement email',
                'Trailer content block',
                'Subscriber segment',
                'Brand header'
            ]
        }
    },
    transport: {
        label: 'Transportation & Logistics',
        coverSub:
            'For transportation and logistics, comms are operational. Here’s how we migrate real-time, triggered journeys without a customer feeling it at the worst possible moment.',
        problem:
            'Half your comms are operational, itineraries, disruptions, delay alerts, loyalty. They’re real-time and triggered; a migration that drops one leaves a customer stranded without an update.',
        useCase:
            'Take an international airline moving onto Salesforce: hundreds of triggered journeys firing on operational events, each with dependencies nobody has fully traced.',
        solution:
            'The Accelerator maps every trigger and its dependencies, so operational journeys are rebuilt intact and in the right order, not rediscovered after go-live.',
        unique: [
            'Operational & triggered comms',
            'Real-time journeys preserved',
            'Global, multi-region delivery'
        ],
        proofLine:
            'Every triggered journey mapped with its dependencies, so nothing operational goes dark at cutover.',
        whyLine:
            'Delivery experience where operational comms are mission-critical, not marketing nice-to-haves.',
        whyHead: 'Built for mission-critical operational comms.',
        demo: {
            root: 'Flight disruption alert',
            deps: [
                'Delay email',
                'Rebooking block',
                'Itinerary data extension',
                'Loyalty footer'
            ]
        }
    },
    government: {
        label: 'Government & Public Sector',
        coverSub:
            'For government and public sector, citizen comms must be accessible, secure, and plain. Here’s how we migrate while carrying the compliance, not just the templates.',
        problem:
            'Citizen communications must be accessible (WCAG / Section 508), secure, multilingual, and plain-spoken. A migration has to carry accessibility and security posture, not just move the content.',
        useCase:
            'Take a federal agency consolidating onto Salesforce: citizen notifications across programs and languages, each bound by accessibility and security requirements.',
        solution:
            'The Accelerator preserves accessibility, security posture, and multilingual content as it migrates, so citizen comms stay compliant by construction.',
        unique: [
            'Accessibility (WCAG / Section 508)',
            'Security & data-handling posture',
            'Multilingual, plain-language content'
        ],
        proofLine:
            'Content mapped with its accessibility and language requirements, so compliance isn’t rebuilt by hand.',
        whyLine:
            'Public-sector delivery experience where accessibility and security are requirements, not options.',
        whyHead: 'Built for accessible, secure citizen comms.',
        demo: {
            root: 'Benefits renewal notice',
            deps: [
                'Notice email',
                'Accessibility footer',
                'Citizen data extension',
                'Translation set'
            ]
        }
    },
    municipal: {
        label: 'Municipal & Civic',
        coverSub:
            'For cities and civic agencies, it’s citizen services on lean teams. Here’s how we consolidate without dropping the alerts and services residents rely on.',
        problem:
            'Alerts, services, and notifications span departments, often on lean teams and tight budgets. The migration has to consolidate without dropping the citizen-facing services residents depend on.',
        useCase:
            'Take a metro authority consolidating several departments onto one platform: overlapping alert systems and service notifications, built up independently over years.',
        solution:
            'The Accelerator maps every department’s comms, finds the overlap, and plans one consolidated estate, so nothing citizen-facing falls through the cracks.',
        unique: [
            'Multi-department consolidation',
            'Citizen alerts & service comms',
            'Accessible, budget-aware delivery'
        ],
        proofLine:
            'Every department’s comms mapped and de-duplicated, so consolidation doesn’t drop a service.',
        whyLine:
            'Civic delivery experience, consolidating services for lean public-sector teams.',
        whyHead: 'Built for lean, multi-department civic teams.',
        demo: {
            root: 'Service outage alert',
            deps: [
                'Alert email',
                'SMS block',
                'Resident data extension',
                'Department footer'
            ]
        }
    }
};

export const IND_ORDER = [
    'fintech',
    'medtech',
    'lifesci',
    'media',
    'transport',
    'government',
    'municipal'
];

export const FIELDS = [
    { k: 'SOURCE_PLATFORM', label: 'Current platform', ph: 'e.g. Eloqua' },
    {
        k: 'TARGET_PLATFORM',
        label: 'Target platform',
        ph: 'e.g. Salesforce Marketing Cloud'
    },
    { k: 'ASSET_COUNT', label: 'Assets mapped (proof number)', ph: 'e.g. 4,128' },
    {
        k: 'DEPENDENCY_COUNT',
        label: 'Dependencies traced (proof number)',
        ph: 'e.g. 9,640'
    },
    {
        k: 'HEALTH_SCORE',
        label: 'Health score (proof number, 0-100)',
        ph: 'e.g. 84'
    },
    { k: 'CONTACT_NAME', label: 'Your name', ph: 'e.g. Alex Rivera' },
    {
        k: 'CONTACT_EMAIL',
        label: 'Your email, shown as the contact on this page',
        ph: 'assessments@publicissapient.com'
    },
    {
        k: 'BOOKING_URL',
        label: 'Microsoft Bookings link (optional)',
        ph: 'https://outlook.office365.com/owa/calendar/…/bookings/'
    },
    {
        k: 'CUSTOM_NOTE',
        label: 'A note for this client (replaces the default intro line on the page)',
        ph: 'e.g. We know Northwind’s Q3 renewal timeline — here’s how we’d de-risk it.',
        textarea: true
    }
];

export const DEFAULTS = {
    SOURCE_PLATFORM: 'Eloqua',
    TARGET_PLATFORM: 'Salesforce Marketing Cloud',
    ASSET_COUNT: '4,128',
    DEPENDENCY_COUNT: '9,640',
    HEALTH_SCORE: '62'
};

export const EXAMPLE = {
    SOURCE_PLATFORM: 'Eloqua',
    TARGET_PLATFORM: 'Salesforce Marketing Cloud',
    ASSET_COUNT: '4,128',
    DEPENDENCY_COUNT: '9,640',
    HEALTH_SCORE: '62',
    CONTACT_NAME: 'Alex Rivera',
    CONTACT_EMAIL: 'assessments@publicissapient.com',
    BOOKING_URL:
        'https://outlook.office365.com/owa/calendar/MigrationAssessment@publicissapient.com/bookings/'
};

export const SWATCHES = [
    { name: 'PS Coral (default)', hex: 'EE3D23' },
    { name: 'Corporate blue', hex: '0B5FFF' },
    { name: 'Slate navy', hex: '1E293B' },
    { name: 'Forest green', hex: '166534' },
    { name: 'Deep purple', hex: '5B21B6' },
    { name: 'Steel gray', hex: '44403C' }
];

export const GENERIC_DEMO = {
    root: 'Welcome Series',
    deps: [
        'Welcome email 1',
        'Welcome email 2',
        'Shared data extension',
        'Brand header'
    ]
};

export const GENERIC_CHIPS = [
    'Undocumented environment',
    'Scope you can’t confidently size',
    'Risk of breaking what works'
];

export const STORAGE_KEY = 'ps_ma_configurator_v1';
export const LINKS_KEY = 'ps_ma_links_v1';

export function initials(name) {
    const parts = String(name || '').trim().split(/\s+/);
    if (!parts[0]) return '';
    const first = parts[0][0] || '';
    const last = parts.length > 1 ? parts[parts.length - 1][0] || '' : '';
    return (first + last).toUpperCase();
}

export function isHex6(value) {
    return /^#?[0-9a-fA-F]{6}$/.test(String(value || '').trim());
}
