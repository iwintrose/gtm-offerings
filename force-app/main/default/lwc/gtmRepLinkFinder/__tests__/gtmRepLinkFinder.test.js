import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import GtmRepLinkFinder from 'c/gtmRepLinkFinder';
import getContactsWithLinks from '@salesforce/apex/GtmRepLinkFinderController.getContactsWithLinks';
import getMyConfigurations from '@salesforce/apex/GtmSavedConfigurationController.getMyConfigurations';
import getPassword from '@salesforce/apex/GtmSavedConfigurationController.getPassword';
import generateReadoutForRequest from '@salesforce/apex/GtmReadoutController.generateReadoutForRequest';
import getOfferingHasConduit from '@salesforce/apex/GtmAssessmentRequestController.getOfferingHasConduit';
import getStageCountsAura from '@salesforce/apex/GtmLinkStageService.getStageCountsAura';
import getLinkStatsAura from '@salesforce/apex/GtmLinkStageService.getLinkStatsAura';
import getLinkIdsForStageAura from '@salesforce/apex/GtmLinkStageService.getLinkIdsForStageAura';

jest.mock(
    '@salesforce/apex/GtmRepLinkFinderController.getContactsWithLinks',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmSavedConfigurationController.getMyConfigurations',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmSavedConfigurationController.setActive',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmSavedConfigurationController.regeneratePassword',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmSavedConfigurationController.getPassword',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutController.generateReadoutForRequest',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
// gtmReadoutWorkspace's own Conduit-tab gate -- rendered as a descendant once
// showWorkspace flips true (issue-gtm-readout-workspace).
jest.mock(
    '@salesforce/apex/GtmAssessmentRequestController.getOfferingHasConduit',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmLinkStageService.getStageCountsAura',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmLinkStageService.getLinkStatsAura',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmLinkStageService.getLinkIdsForStageAura',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmViewerContext.isRep',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

// eslint-disable-next-line import/no-unresolved
const isRep = require('@salesforce/apex/GtmViewerContext.isRep').default;

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const LINK_ROW = {
    recordId: 'a0X000000000001AAA',
    company: 'Acme Co',
    offering: 'migration-accelerator',
    industryLabel: 'Retail',
    dealName: 'Acme Deal',
    dealStage: 'Proposal',
    createdDate: '2026-01-01T00:00:00.000Z',
    active: true,
    generatedUrl: 'https://example.my.site.com/s/configurator?cfgId=a0X000000000001AAA',
    hasPassword: true,
    requestId: null,
    readoutId: null
};

/** Clicks the "Preview the link" toggle to reveal the relocated
 *  c-gtm-configurator block (issue #rlf-layout-and-preview, Option C) --
 *  hidden by default now, so any assertion that needs the embed itself
 *  must reveal it first. */
async function revealPreview(element) {
    const toggle = [...element.shadowRoot.querySelectorAll('lightning-button.rlf-preview-toggle')][0];
    toggle.click();
    await flushPromises();
}

const SAVED_ROW = {
    Id: LINK_ROW.recordId,
    Account__c: '001000000000001AAA',
    Contact__c: '003000000000001AAA',
    Company__c: 'Acme Co',
    Offering__c: 'migration-accelerator',
    Generated_URL__c: LINK_ROW.generatedUrl,
    Active__c: true,
    CreatedDate: '2026-01-01T00:00:00.000Z',
    Contact__r: { Name: 'Jane Prospect' }
};

/** Release 2: the detail view is reached through the row-action Open on the
 *  filterable table (there is no Account -> Contact -> Link walk any more). */
async function openRowDetail(element, recordId = LINK_ROW.recordId) {
    const table = element.shadowRoot.querySelector('c-gtm-link-datatable');
    table.dispatchEvent(new CustomEvent('rowaction', {
        detail: { action: { name: 'open' }, row: { recordId } }
    }));
    await flushPromises();
}

async function driveToViewStep(element, linkRow = LINK_ROW) {
    getMyConfigurations.mockResolvedValue([{ ...SAVED_ROW, Id: linkRow.recordId }]);
    getContactsWithLinks.mockResolvedValue([
        { contactId: '003000000000001AAA', contactName: 'Jane Prospect', links: [linkRow] }
    ]);

    document.body.appendChild(element);
    isRep.emit(true);
    await flushPromises();
    await openRowDetail(element, linkRow.recordId);
}

// The quick-access tile grid (product-owner feedback, live review) calls
// this unconditionally from connectedCallback -- every test in this file
// mounts the component, so this needs a safe default everywhere, not just
// in the tile-grid's own describe block below.
beforeEach(() => {
    getMyConfigurations.mockResolvedValue([]);
    // Stage-filter chip counts are fetched on every mount (stage-filter-pages-tab).
    getStageCountsAura.mockResolvedValue(null);
    getLinkStatsAura.mockResolvedValue({ viewAll: false, truncated: false, stats: [] });
});

describe('c-gtm-rep-link-finder — landing view enrich', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        jest.clearAllMocks();
    });

    it('renders the nested configurator with view-only relaxed (customize/pop-out affordance available), once previewed', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element);
        await revealPreview(element);

        const nested = element.shadowRoot.querySelector('c-gtm-configurator');
        expect(nested).not.toBeNull();
        expect(nested.viewOnly).toBe(false);
    });

    it('shows the actual engagement link as a copyable field', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element);

        const input = element.shadowRoot.querySelector('.rlf-view-input');
        expect(input.value).toBe(LINK_ROW.generatedUrl);
    });

    it('masks the password by default and only fetches the plaintext on explicit reveal', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element);

        // Masked at rest -- getPassword must not have been called on load.
        expect(getPassword).not.toHaveBeenCalled();
        const inputs = element.shadowRoot.querySelectorAll('.rlf-view-input');
        const passwordInput = inputs[1];
        expect(passwordInput.value).toBe('••••••');

        getPassword.mockResolvedValue('S3CRET');
        const showButton = element.shadowRoot.querySelector('lightning-button.rlf-pw-show');
        expect(showButton).not.toBeNull();
        showButton.click();
        await flushPromises();

        expect(getPassword).toHaveBeenCalledWith({ recordId: LINK_ROW.recordId });
        const revealedInput = element.shadowRoot.querySelectorAll('.rlf-view-input')[1];
        expect(revealedInput.value).toBe('S3CRET');
    });

    it('resets the password reveal state when navigating back to a different link', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element);

        getPassword.mockResolvedValue('S3CRET');
        element.shadowRoot.querySelector('lightning-button.rlf-pw-show').click();
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('.rlf-view-input')[1].value).toBe('S3CRET');

        element.shadowRoot.querySelector('.rlf-back').click();
        await flushPromises();

        await openRowDetail(element);

        const passwordInputAgain = element.shadowRoot.querySelectorAll('.rlf-view-input')[1];
        expect(passwordInputAgain.value).toBe('••••••');
    });
});

/**
 * Issue #99-done-nav — gtmRepLinkFinder accepts an optional pre-selected
 * target (record id / offering / company) and, when present, skips straight
 * to the "view" step instead of the Account-search first step. Absent, the
 * normal manual Account -> Contact -> Link walk is unaffected.
 */
describe('c-gtm-rep-link-finder: pre-selected target (issue #99-done-nav)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('with targetRecordId set, jumps straight to the view step for that record', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        element.targetRecordId = 'a0X000000000099';
        element.targetCompany = 'Acme Corp';
        element.targetOfferingKey = 'migration-accelerator';
        document.body.appendChild(element);
        await flushPromises();

        // No Account-search first step shown.
        expect(element.shadowRoot.querySelector('.rlf-view')).not.toBeNull();

        // The view step's stage renders the saved link directly once
        // previewed. view-only is now relaxed on this step regardless of
        // entry path (see issue #landing-view-enrich, TASK_SCOPE.md §6 fork
        // #2) -- the Customize/Saved Links/agent-bubble affordances are
        // available here too.
        await revealPreview(element);
        const configurator = element.shadowRoot.querySelector('c-gtm-configurator');
        expect(configurator).not.toBeNull();
        expect(configurator.offeringKey).toBe('migration-accelerator');
        expect(configurator.viewOnly).toBe(false);
    });

    it('without an explicit targetOfferingKey, does not silently default to Migration Accelerator (B11)', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        element.targetRecordId = 'a0X000000000098';
        document.body.appendChild(element);
        await flushPromises();
        await revealPreview(element);

        const configurator = element.shadowRoot.querySelector('c-gtm-configurator');
        expect(configurator).not.toBeNull();
        expect(configurator.offeringKey).toBe('');
    });

    it('clearing the seeded view via "Back" does not re-seed the target (the links table returns)', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        element.targetRecordId = 'a0X000000000099';
        element.targetCompany = 'Acme Corp';
        document.body.appendChild(element);
        await flushPromises();

        const backButton = [...element.shadowRoot.querySelectorAll('button.rlf-back')]
            .find((b) => b.textContent.includes('Back'));
        expect(backButton).toBeTruthy();
        backButton.click();
        await flushPromises();

        // Back to the links table -- not re-seeded to the target's view.
        expect(element.shadowRoot.querySelector('c-gtm-configurator')).toBeNull();
        expect(element.shadowRoot.querySelector('.rlf-view')).toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-filter-bar')).not.toBeNull();
    });
});

/**
 * Issue REPLINKFINDER-SUBMISSION-DETAIL — the view step surfaces the
 * prospect's actual assessment submission (via gtmAssessmentDetail) once
 * LinkSummary.requestId is populated, plus a "View readout" action once
 * readoutId is also populated. requestId == null (never started) is the
 * normal, unchanged-from-today case.
 */
describe('c-gtm-rep-link-finder: submission detail panel (REPLINKFINDER-SUBMISSION-DETAIL)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        jest.clearAllMocks();
    });

    it('renders no submission panel when requestId is null (normal, unchanged behavior)', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element, { ...LINK_ROW, requestId: null, readoutId: null });

        expect(element.shadowRoot.querySelector('c-gtm-assessment-detail')).toBeNull();
        expect(element.shadowRoot.textContent).not.toContain('View readout');
        // The link's own controls are still there, unaffected.
        expect(element.shadowRoot.querySelector('.rlf-view-input')).not.toBeNull();
        await revealPreview(element);
        expect(element.shadowRoot.querySelector('c-gtm-configurator')).not.toBeNull();
    });

    it('renders the gtmAssessmentDetail panel alongside the link controls when requestId is populated', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element, { ...LINK_ROW, requestId: 'a1X000000000001AAA', readoutId: null });

        const detail = element.shadowRoot.querySelector('c-gtm-assessment-detail');
        expect(detail).not.toBeNull();
        expect(detail.recordId).toBe('a1X000000000001AAA');

        // No readout yet -- no "View readout" action.
        expect(element.shadowRoot.textContent).not.toContain('View readout');

        // Link controls are still rendered, untouched.
        expect(element.shadowRoot.querySelector('.rlf-view-input').value).toBe(LINK_ROW.generatedUrl);
        await revealPreview(element);
        expect(element.shadowRoot.querySelector('c-gtm-configurator')).not.toBeNull();
    });

    it('surfaces a "View readout" action that renders gtmReadoutWorkspace inline, wired to the readoutId', async () => {
        getOfferingHasConduit.mockResolvedValue(false);
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element, {
            ...LINK_ROW,
            requestId: 'a1X000000000001AAA',
            readoutId: 'a2X000000000001AAA'
        });

        expect(element.shadowRoot.querySelector('c-gtm-assessment-detail')).not.toBeNull();

        const buttons = [...element.shadowRoot.querySelectorAll('lightning-button')];
        const readoutButton = buttons.find((b) => b.label === 'View readout');
        expect(readoutButton).toBeTruthy();

        readoutButton.click();
        await flushPromises();

        const workspace = element.shadowRoot.querySelector('c-gtm-readout-workspace');
        expect(workspace).not.toBeNull();
        expect(workspace.assessmentRequestId).toBe('a1X000000000001AAA');
        expect(workspace.readoutId).toBe('a2X000000000001AAA');
        // Regression check (PR #179 live QA finding): gtmReadoutWorkspace's
        // Preview tab silently shows "This offering hasn't been configured
        // yet" whenever offering-key isn't wired through from the caller.
        expect(workspace.offeringKey).toBe(LINK_ROW.offering);
    });

    it('returns to the plain assessment-submission block when gtmReadoutWorkspace fires "back"', async () => {
        getOfferingHasConduit.mockResolvedValue(false);
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element, {
            ...LINK_ROW,
            requestId: 'a1X000000000001AAA',
            readoutId: 'a2X000000000001AAA'
        });

        const buttons = [...element.shadowRoot.querySelectorAll('lightning-button')];
        buttons.find((b) => b.label === 'View readout').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-readout-workspace')).not.toBeNull();

        element.shadowRoot
            .querySelector('c-gtm-readout-workspace')
            .dispatchEvent(new CustomEvent('back'));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-readout-workspace')).toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-assessment-detail')).not.toBeNull();
    });

    it('clears the submission panel when backing out to the links step and re-entering a link with no requestId', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        const withRequest = { ...LINK_ROW, requestId: 'a1X000000000001AAA', readoutId: null };
        await driveToViewStep(element, withRequest);
        expect(element.shadowRoot.querySelector('c-gtm-assessment-detail')).not.toBeNull();

        element.shadowRoot.querySelector('.rlf-back').click();
        await flushPromises();

        // Back at the link step, no leftover submission panel.
        expect(element.shadowRoot.querySelector('c-gtm-assessment-detail')).toBeNull();
    });
});

/**
 * Issue generate-readout-from-assessment — the "Generate Readout" button is
 * the hasSubmission && !hasReadout sibling of "View readout" above: it lets
 * a rep recover from the guest-submit transaction's best-effort
 * generateDraftReadout call having no-op'd, or kick off a readout for a
 * request that predates that logic.
 */
describe('c-gtm-rep-link-finder: Generate Readout (generate-readout-from-assessment)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        jest.clearAllMocks();
    });

    function findButton(element, label) {
        return [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            (b) => b.label === label
        );
    }

    it('renders "Generate Readout" only when hasSubmission is true and hasReadout is false', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element, { ...LINK_ROW, requestId: 'a1X000000000001AAA', readoutId: null });

        expect(findButton(element, 'Generate Readout')).toBeTruthy();
        expect(findButton(element, 'View readout')).toBeFalsy();
    });

    it('does not render "Generate Readout" once a readout already exists', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element, {
            ...LINK_ROW,
            requestId: 'a1X000000000001AAA',
            readoutId: 'a2X000000000001AAA'
        });

        expect(findButton(element, 'Generate Readout')).toBeFalsy();
        expect(findButton(element, 'View readout')).toBeTruthy();
    });

    it('does not render "Generate Readout" when there is no submission at all', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element, { ...LINK_ROW, requestId: null, readoutId: null });

        expect(findButton(element, 'Generate Readout')).toBeFalsy();
    });

    it('calls generateReadoutForRequest with the selected request Id and renders gtmReadoutWorkspace inline on success', async () => {
        getOfferingHasConduit.mockResolvedValue(false);
        generateReadoutForRequest.mockResolvedValue('a2X000000000009AAA');

        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element, { ...LINK_ROW, requestId: 'a1X000000000001AAA', readoutId: null });

        findButton(element, 'Generate Readout').click();
        await flushPromises();

        expect(generateReadoutForRequest).toHaveBeenCalledWith({
            assessmentRequestId: 'a1X000000000001AAA'
        });
        const workspace = element.shadowRoot.querySelector('c-gtm-readout-workspace');
        expect(workspace).not.toBeNull();
        expect(workspace.assessmentRequestId).toBe('a1X000000000001AAA');
    });

    it('surfaces a rejected generateReadoutForRequest call via loadError, not a silent failure', async () => {
        generateReadoutForRequest.mockRejectedValue({
            body: { message: 'Assessment request not found or not accessible.' }
        });

        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element, { ...LINK_ROW, requestId: 'a1X000000000001AAA', readoutId: null });

        findButton(element, 'Generate Readout').click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Assessment request not found or not accessible.');
        expect(element.shadowRoot.querySelector('c-gtm-readout-workspace')).toBeNull();
    });
});

/**
 * Issue #rlf-layout-and-preview (Option C) — the view step's own content
 * (engagement link, password, submission detail, assessment details) is a
 * full-width block below the compact Contact/Link columns, not a third
 * column beside them, and the embedded c-gtm-configurator is relocated into
 * its own full-width block below that, hidden until "Preview the link" is
 * clicked.
 */
describe('c-gtm-rep-link-finder: full-width view block + gated preview (issue #rlf-layout-and-preview)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        jest.clearAllMocks();
    });

    it('hides the relocated preview block by default and surfaces a "Preview the link" action', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element);

        expect(element.shadowRoot.querySelector('.rlf-preview-row')).toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-configurator')).toBeNull();

        const toggle = element.shadowRoot.querySelector('lightning-button.rlf-preview-toggle');
        expect(toggle).not.toBeNull();
        expect(toggle.label).toBe('Preview the link');
    });

    it('reveals the relocated configurator block on click, and hides it again on a second click', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element);

        const toggle = element.shadowRoot.querySelector('lightning-button.rlf-preview-toggle');
        toggle.click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.rlf-preview-row')).not.toBeNull();
        const configurator = element.shadowRoot.querySelector('c-gtm-configurator');
        expect(configurator).not.toBeNull();
        expect(configurator.offeringKey).toBe(LINK_ROW.offering);
        expect(element.shadowRoot.querySelector('lightning-button.rlf-preview-toggle').label).toBe('Hide preview');

        toggle.click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.rlf-preview-row')).toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-configurator')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-button.rlf-preview-toggle').label).toBe('Preview the link');
    });

    it('re-hides the preview when navigating to a different link', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element);
        await revealPreview(element);
        expect(element.shadowRoot.querySelector('c-gtm-configurator')).not.toBeNull();

        element.shadowRoot.querySelector('.rlf-back').click();
        await flushPromises();

        await openRowDetail(element);

        expect(element.shadowRoot.querySelector('c-gtm-configurator')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-button.rlf-preview-toggle').label).toBe('Preview the link');
    });

    it('all other view-step controls (copy link, password reveal/copy/regenerate) still work once previewed', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element);
        await revealPreview(element);

        // Copy link still present and wired to the same URL.
        const input = element.shadowRoot.querySelector('.rlf-view-input');
        expect(input.value).toBe(LINK_ROW.generatedUrl);

        // Password reveal still works.
        getPassword.mockResolvedValue('S3CRET');
        const showButton = element.shadowRoot.querySelector('lightning-button.rlf-pw-show');
        expect(showButton).not.toBeNull();
        showButton.click();
        await flushPromises();
        expect(getPassword).toHaveBeenCalledWith({ recordId: LINK_ROW.recordId });

        // The configurator embed is still present and functioning.
        expect(element.shadowRoot.querySelector('c-gtm-configurator')).not.toBeNull();
    });
});

// Bug fix: the Account -> Contact -> Link drill-down state used to live only
// in @track fields, so a browser refresh at any depth bounced a rep back to
// the empty Account-search first step. State is now mirrored onto the URL
// (c__rlfAccountId/c__rlfContactId/c__rlfLinkId) and restored from
// CurrentPageReference on load, the same round-trip gtmReadoutsOverview now
// uses for its own selection state.
describe('c-gtm-rep-link-finder: URL state persistence (bug fix)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        jest.clearAllMocks();
    });

    it('writes account, contact, and link ids to the URL as the rep drills all the way down', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element);

        const url = new URL(window.location.href);
        expect(url.searchParams.get('c__rlfAccountId')).toBe('001000000000001AAA');
        expect(url.searchParams.get('c__rlfContactId')).toBe('003000000000001AAA');
        expect(url.searchParams.get('c__rlfLinkId')).toBe(LINK_ROW.recordId);
    });

    it('clears every detail param from the URL on "Back to links"', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element);

        const backButton = [...element.shadowRoot.querySelectorAll('button')]
            .find((b) => b.textContent.includes('Back to'));
        backButton.click();
        await flushPromises();

        const url = new URL(window.location.href);
        expect(url.searchParams.get('c__rlfAccountId')).toBeNull();
        expect(url.searchParams.get('c__rlfContactId')).toBeNull();
        expect(url.searchParams.get('c__rlfLinkId')).toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-link-datatable')).not.toBeNull();
    });

    it('restores full-depth state (account, contact, and link all selected) from CurrentPageReference, simulating a refresh', async () => {
        getContactsWithLinks.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', links: [LINK_ROW] }
        ]);
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(element);
        CurrentPageReference.emit({
            state: {
                c__rlfAccountId: '001000000000001AAA',
                c__rlfContactId: '003000000000001AAA',
                c__rlfLinkId: LINK_ROW.recordId
            }
        });
        await flushPromises();

        const input = element.shadowRoot.querySelector('.rlf-view-input');
        expect(input).not.toBeNull();
        expect(input.value).toBe(LINK_ROW.generatedUrl);
    });

    it('does not restore drill state from the URL when a targetRecordId prop is also present (the wizard deep-link path wins)', async () => {
        getContactsWithLinks.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', links: [LINK_ROW] }
        ]);
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        element.targetRecordId = 'a0X000000000099AAA';
        element.targetCompany = 'Globex';
        element.targetOfferingKey = 'migration-accelerator';
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__rlfAccountId: '001000000000001AAA' } });
        await flushPromises();

        expect(getContactsWithLinks).not.toHaveBeenCalled();
        const input = element.shadowRoot.querySelector('.rlf-view-input');
        expect(input.value).toBe(''); // no generatedUrl on the seeded target -- confirms the target path ran, not the URL-restore path
    });
});

// issue-pages-preview-fixes, Bug 3: showPreview/showWorkspace/
// passwordRevealed are additive params on the same URL channel as the
// c__rlfAccountId/c__rlfContactId/c__rlfLinkId drill state above, so a real
// <a href> navigation away from gtmAssessmentDetail (a full page unload) and
// back restores the rep's preview/workspace/password-reveal state instead of
// resetting to the plain view step.
describe('c-gtm-rep-link-finder: preview/workspace/password-reveal URL state (issue-pages-preview-fixes)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        jest.clearAllMocks();
    });

    it('writes c__rlfShowPreview to the URL when the preview is toggled open, and clears it when toggled shut', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element);

        await revealPreview(element);
        let url = new URL(window.location.href);
        expect(url.searchParams.get('c__rlfShowPreview')).toBe('1');

        await revealPreview(element);
        url = new URL(window.location.href);
        expect(url.searchParams.get('c__rlfShowPreview')).toBeNull();
    });

    it('writes c__rlfPwRevealed to the URL once the password is revealed', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element);

        getPassword.mockResolvedValue('S3CRET');
        const showButton = element.shadowRoot.querySelector('lightning-button.rlf-pw-show');
        showButton.click();
        await flushPromises();

        const url = new URL(window.location.href);
        expect(url.searchParams.get('c__rlfPwRevealed')).toBe('1');
    });

    it('does not write c__rlfShowPreview/c__rlfShowWorkspace/c__rlfPwRevealed to the URL when none are active (no collision with existing params)', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        await driveToViewStep(element);

        const url = new URL(window.location.href);
        expect(url.searchParams.get('c__rlfShowPreview')).toBeNull();
        expect(url.searchParams.get('c__rlfShowWorkspace')).toBeNull();
        expect(url.searchParams.get('c__rlfPwRevealed')).toBeNull();
        // Existing drill-state params are unaffected.
        expect(url.searchParams.get('c__rlfAccountId')).toBe('001000000000001AAA');
        expect(url.searchParams.get('c__rlfLinkId')).toBe(LINK_ROW.recordId);
    });

    it('restores showPreview from CurrentPageReference (c__rlfShowPreview), simulating a refresh/back-navigation after a real <a href> nav away', async () => {
        getContactsWithLinks.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', links: [LINK_ROW] }
        ]);
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(element);
        CurrentPageReference.emit({
            state: {
                c__rlfAccountId: '001000000000001AAA',
                c__rlfContactId: '003000000000001AAA',
                c__rlfLinkId: LINK_ROW.recordId,
                c__rlfShowPreview: '1'
            }
        });
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-configurator')).not.toBeNull();
        expect(element.shadowRoot.querySelector('lightning-button.rlf-preview-toggle').label).toBe('Hide preview');
    });

    it('restores showWorkspace from CurrentPageReference (c__rlfShowWorkspace), simulating a refresh/back-navigation after a real <a href> nav away', async () => {
        const linkRowWithReadout = { ...LINK_ROW, requestId: 'a0Y000000000001AAA', readoutId: 'a0Z000000000001AAA' };
        getContactsWithLinks.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', links: [linkRowWithReadout] }
        ]);
        getOfferingHasConduit.mockResolvedValue(false);
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(element);
        CurrentPageReference.emit({
            state: {
                c__rlfAccountId: '001000000000001AAA',
                c__rlfContactId: '003000000000001AAA',
                c__rlfLinkId: linkRowWithReadout.recordId,
                c__rlfShowWorkspace: '1'
            }
        });
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-readout-workspace')).not.toBeNull();
    });

    it('restores the password reveal from CurrentPageReference (c__rlfPwRevealed) by re-fetching it via getPassword, not by persisting the plaintext on the URL', async () => {
        getContactsWithLinks.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', links: [LINK_ROW] }
        ]);
        getPassword.mockResolvedValue('S3CRET');
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(element);
        CurrentPageReference.emit({
            state: {
                c__rlfAccountId: '001000000000001AAA',
                c__rlfContactId: '003000000000001AAA',
                c__rlfLinkId: LINK_ROW.recordId,
                c__rlfPwRevealed: '1'
            }
        });
        await flushPromises();

        expect(getPassword).toHaveBeenCalledWith({ recordId: LINK_ROW.recordId });
        const url = new URL(window.location.href);
        // The plaintext password is never written to the URL, only the
        // boolean reveal-state flag.
        expect(url.search).not.toContain('S3CRET');
    });

    it('does not restore preview/workspace/password-reveal state when no link is selected yet (gated on _restoredLinkId)', async () => {
        getContactsWithLinks.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', links: [LINK_ROW] }
        ]);
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(element);
        CurrentPageReference.emit({
            state: {
                c__rlfAccountId: '001000000000001AAA',
                c__rlfShowPreview: '1',
                c__rlfShowWorkspace: '1',
                c__rlfPwRevealed: '1'
            }
        });
        await flushPromises();

        expect(getPassword).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('c-gtm-readout-workspace')).toBeNull();
    });
});

// Quick-access table (formerly a tile grid; issue pages-tab-table-view) --
// reuses GtmSavedConfigurationController.getMyConfigurations, the same Apex
// gtmSavedLinksBar already calls. Column/sort/filter/open coverage lives in
// gtmRepLinkFinder.table.test.js.
describe('c-gtm-rep-link-finder: quick-access links table (product-owner feedback)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    const SAVED_CONFIG = {
        Id: LINK_ROW.recordId,
        Account__c: '001000000000001AAA',
        Account__r: { Name: 'Acme Co' },
        Contact__c: '003000000000001AAA',
        Contact__r: { Name: 'Jane Prospect' },
        Company__c: 'Acme Co',
        Offering__c: 'migration-accelerator',
        Active__c: true,
        CreatedDate: '2026-01-01T00:00:00.000Z'
    };

    const openRow = (element, recordId) => {
        element.shadowRoot.querySelector('c-gtm-link-datatable').dispatchEvent(
            new CustomEvent('rowaction', { detail: { action: { name: 'open' }, row: { recordId } } })
        );
    };

    it('renders a table row for each saved link, in "All Pages" mode (the default)', async () => {
        getMyConfigurations.mockResolvedValue([SAVED_CONFIG]);

        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(element);
        await flushPromises();

        const table = element.shadowRoot.querySelector('c-gtm-link-datatable');
        expect(table).not.toBeNull();
        expect(table.data.length).toBe(1);
        expect(table.data[0].company).toBe('Acme Co');
        expect(table.data[0].contactName).toBe('Jane Prospect');
    });

    it('shows an empty message when there are no saved links yet, in "All Pages" mode', async () => {
        getMyConfigurations.mockResolvedValue([]);

        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-link-datatable')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('No saved links yet');
    });

    it('hides the table once a row is opened (drilling past the account step)', async () => {
        getMyConfigurations.mockResolvedValue([SAVED_CONFIG]);
        getContactsWithLinks.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', links: [LINK_ROW] }
        ]);

        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(element);
        await flushPromises();
        expect(element.shadowRoot.querySelector('c-gtm-link-datatable')).not.toBeNull();

        openRow(element, SAVED_CONFIG.Id);
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-link-datatable')).toBeNull();
    });

    // Opening a row must behave exactly like walking the Miller columns
    // to the same link by hand -- same end state (the view step, wired to
    // the same link record), not a separate/parallel selection path.
    it('opening a row drives straight to the same view step the Miller columns would reach', async () => {
        getMyConfigurations.mockResolvedValue([SAVED_CONFIG]);
        getContactsWithLinks.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', links: [LINK_ROW] }
        ]);

        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(element);
        await flushPromises();

        openRow(element, SAVED_CONFIG.Id);
        await flushPromises();

        expect(getContactsWithLinks).toHaveBeenCalledWith({ accountId: SAVED_CONFIG.Account__c });
        const input = element.shadowRoot.querySelector('.rlf-view-input');
        expect(input).not.toBeNull();
        expect(input.value).toBe(LINK_ROW.generatedUrl);

        const url = new URL(window.location.href);
        expect(url.searchParams.get('c__rlfLinkId')).toBe(LINK_ROW.recordId);
    });
});

/**
 * Issue pages-assessments-loading-state — a page-level spinner gated on all 4
 * of connectedCallback's concurrent initial Apex calls (industries, saved
 * links, link stats, stage counts) settling, so the whole tab shows a clear
 * loading state on first paint rather than relying on the narrower
 * loadingSavedLinks/loadingLinks/stageLoading sub-state spinners alone.
 */
describe('c-gtm-rep-link-finder: initial page-level loading spinner (issue pages-assessments-loading-state)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        jest.clearAllMocks();
    });

    function deferred() {
        let resolve;
        const promise = new Promise((r) => { resolve = r; });
        return { promise, resolve };
    }

    it('shows the page-level spinner immediately on connectedCallback, before any of the 4 initial calls settle', () => {
        const savedLinks = deferred();
        const linkStats = deferred();
        const stageCounts = deferred();
        getMyConfigurations.mockReturnValue(savedLinks.promise);
        getLinkStatsAura.mockReturnValue(linkStats.promise);
        getStageCountsAura.mockReturnValue(stageCounts.promise);

        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(element);

        expect(element.shadowRoot.querySelector('lightning-spinner')).not.toBeNull();
    });

    it('hides the page-level spinner only once all 4 initial calls have settled', async () => {
        const savedLinks = deferred();
        const linkStats = deferred();
        const stageCounts = deferred();
        getMyConfigurations.mockReturnValue(savedLinks.promise);
        getLinkStatsAura.mockReturnValue(linkStats.promise);
        getStageCountsAura.mockReturnValue(stageCounts.promise);

        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(element);
        await flushPromises();

        // Only 2 of the 4 calls (industries + the default stub) have settled.
        expect(element.shadowRoot.querySelector('lightning-spinner')).not.toBeNull();

        savedLinks.resolve([]);
        await flushPromises();
        expect(element.shadowRoot.querySelector('lightning-spinner')).not.toBeNull();

        linkStats.resolve({ viewAll: false, truncated: false, stats: [] });
        await flushPromises();
        expect(element.shadowRoot.querySelector('lightning-spinner')).not.toBeNull();

        stageCounts.resolve(null);
        await flushPromises();
        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });

    it('does not reappear once initial load settles, even if a sub-load (e.g. stage counts refresh) runs again', async () => {
        const element = createElement('c-gtm-rep-link-finder', { is: GtmRepLinkFinder });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();

        // A later stage-filter chip pick re-fetches stage counts; the page-level
        // spinner must stay gone -- only the narrower stageLoading spinner covers this.
        getStageCountsAura.mockResolvedValue({ sent: 1 });
        getLinkIdsForStageAura.mockResolvedValue([]);
        const filterBar = element.shadowRoot.querySelector('c-gtm-filter-bar');
        filterBar.dispatchEvent(new CustomEvent('filterchange', { detail: { key: 'stage', value: 'sent' } }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });
});
