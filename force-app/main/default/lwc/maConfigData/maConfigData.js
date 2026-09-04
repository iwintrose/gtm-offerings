/**
 * Shared content for the Migration Accelerator configurator.
 *
 * INDUSTRIES, IND_ORDER, SWATCHES, GENERIC_DEMO, GENERIC_CHIPS, and
 * DEFAULTS used to live here as hardcoded constants -- they're now
 * authored in Salesforce CMS (force-app/main/default/managedContentTypes/)
 * and read at runtime via MaStoryContentController.getStoryContent(),
 * wired directly in maConfigurator.js, maConfigCustomize.js, and
 * maSavedLinksBar.js. See DEPLOYMENT.md for how that content gets from
 * CMS onto the page.
 *
 * What's left here is genuinely static: the per-client personalization
 * token definitions (FIELDS) surfaced through the Customize panel, one
 * example preset, and small utility functions -- none of that is
 * "editorial content" a BA would need to change without a deploy.
 */

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
        label: 'A note for this client (appears below the industry intro on the page)',
        ph: 'e.g. We know Northwind’s Q3 renewal timeline — here’s how we’d de-risk it.',
        textarea: true
    }
];

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
