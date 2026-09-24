// Shared checklist fixtures (workstream C, published for D). Shapes and
// string literals mirror the frozen Apex DTOs in
// docs/architecture/guided-setup-implementation-plan.md sections 2.2 and 3.1.
// Every catalogue key appears exactly once in each fixture.
// Not a test file: jest.config.js only collects *.test.js.

// [key, tier, category, actionType, linkKind]
const CATALOGUE = [
    ['admin_assigned', 'REQUIRED', 'ACCESS', 'ASSIGN_TO_ME', 'NONE'],
    ['content_access', 'REQUIRED', 'ACCESS', 'ASSIGN_TO_ME', 'NONE'],
    ['reps_assigned', 'RECOMMENDED', 'ACCESS', 'ASSIGN_PICKER', 'NONE'],
    ['guest_permset', 'REQUIRED', 'SITE', 'LINK', 'SETUP_PATH'],
    ['site_active', 'REQUIRED', 'SITE', 'LINK', 'SETUP_PATH'],
    ['framework_pages', 'REQUIRED', 'CONTENT', 'CREATE_FRAMEWORK_PAGES', 'NONE'],
    ['industry_added', 'REQUIRED', 'CONTENT', 'LINK', 'NAV_ITEM'],
    ['offering_created', 'REQUIRED', 'CONTENT', 'LINK', 'NAV_ITEM'],
    ['offering_published', 'REQUIRED', 'CONTENT', 'LINK', 'NAV_ITEM'],
    ['offering_listed', 'REQUIRED', 'CONFIGURATION', 'LINK', 'SETUP_PATH'],
    ['triage_queue', 'RECOMMENDED', 'CONFIGURATION', 'LINK', 'SETUP_PATH'],
    ['manager_on_reps', 'RECOMMENDED', 'CONFIGURATION', 'LINK', 'SETUP_PATH'],
    ['scheduled_jobs', 'RECOMMENDED', 'CONFIGURATION', 'SCHEDULE_JOBS', 'NONE'],
    ['site_members', 'RECOMMENDED', 'SITE', 'LINK', 'SETUP_PATH'],
    ['page_offerings', 'OPTIONAL', 'CONTENT', 'LINK', 'NAV_ITEM'],
    ['page_faq_bd', 'OPTIONAL', 'CONTENT', 'LINK', 'NAV_ITEM'],
    ['page_faq_cm', 'OPTIONAL', 'CONTENT', 'LINK', 'NAV_ITEM'],
    ['page_assistant', 'OPTIONAL', 'CONTENT', 'LINK', 'NAV_ITEM'],
    ['analytics_digest', 'OPTIONAL', 'CONFIGURATION', 'LINK', 'NONE'],
    ['ai_keys', 'OPTIONAL', 'CONFIGURATION', 'LINK', 'NONE'],
    ['approval_routing', 'INFO', 'CONFIGURATION', 'LINK', 'NONE'],
    ['offering_pages', 'INFO', 'CONTENT', 'LINK', 'NAV_ITEM'],
    ['org_digital_experiences', 'INFO', 'ORG', 'LINK', 'SETUP_PATH'],
    ['org_my_domain', 'INFO', 'ORG', 'LINK', 'SETUP_PATH'],
    ['org_chatter', 'INFO', 'ORG', 'LINK', 'SETUP_PATH'],
    ['org_email', 'INFO', 'ORG', 'LINK', 'SETUP_PATH']
];

const PERMSET = {
    admin_assigned: 'GTM_Offering_Admin',
    content_access: 'GTM_Content_Manager',
    reps_assigned: 'GTM_Offering_User'
};

function item(row, status, overrides = {}) {
    const [key, tier, category, actionType, linkKind] = row;
    const isInfoTier = tier === 'INFO';
    return {
        key,
        tier,
        category,
        status: isInfoTier ? 'INFO' : status,
        title: `Title for ${key}`,
        why: `Why ${key} matters.`,
        detail: null,
        humanMustAct: linkKind !== 'NONE' && actionType === 'LINK',
        actionType: status === 'DONE' && !isInfoTier ? 'NONE' : actionType,
        actionLabel: `Action for ${key}`,
        linkKind: status === 'DONE' && !isInfoTier ? 'NONE' : linkKind,
        navApiName: linkKind === 'NAV_ITEM' ? 'GTM_Content_Manager' : null,
        navState: linkKind === 'NAV_ITEM' ? { c__offering: 'gtm', c__template: 'industry-chooser' } : null,
        setupPath: linkKind === 'SETUP_PATH' ? '/lightning/setup/SetupOneHome/home' : null,
        permissionSetName: PERMSET[key] || null,
        blockedBy: [],
        collapsedByDefault: tier === 'OPTIONAL' || tier === 'INFO',
        ...overrides
    };
}

function build(statusFor, extra = {}) {
    const items = CATALOGUE.map((row) => item(row, statusFor(row)));
    const required = items.filter((i) => i.tier === 'REQUIRED' && i.key !== 'content_access');
    return {
        items,
        requiredTotal: 8,
        requiredDone: required.filter((i) => i.status === 'DONE').length,
        requiredUnknown: required.filter((i) => i.status === 'UNKNOWN').length,
        selfApprovalEnabled: false,
        checkedAt: '2026-09-20T12:00:00.000Z',
        ...extra
    };
}

// Blank install: nothing configured. Optional rows NOT_SET, info rows INFO.
const blankChecklist = build(([, tier]) => (tier === 'OPTIONAL' ? 'NOT_SET' : 'TODO'));

// Everything required is done; the rest neutral.
const allDoneChecklist = build(([, tier]) => (tier === 'REQUIRED' || tier === 'RECOMMENDED' ? 'DONE' : 'NOT_SET'));

// Two required rows could not be verified (site cannot be identified).
const unknownRequiredChecklist = build(([key, tier]) => {
    if (key === 'guest_permset' || key === 'site_active') return 'UNKNOWN';
    return tier === 'OPTIONAL' ? 'NOT_SET' : 'TODO';
});

module.exports = {
    CATALOGUE,
    item,
    build,
    blankChecklist,
    allDoneChecklist,
    unknownRequiredChecklist
};
