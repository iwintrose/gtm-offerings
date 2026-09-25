import { createElement } from 'lwc';
import GtmContentHome, { canRenamePage } from 'c/gtmContentHome';

// The stock sfdx-lwc-jest navigation stub defines [NavigationMixin.Navigate]
// on a sealed prototype, so it cannot be spied on or reassigned in place --
// same pattern as gtmAnalyticsTeam.test.js/gtmAssessmentSubmissionView.test.js.
const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) => {
        return class extends Base {
            [Navigate](...args) {
                mockNavigate(...args);
            }
        };
    };
    NavigationMixin.Navigate = Navigate;
    const { createTestWireAdapter } = jest.requireActual('@salesforce/sfdx-lwc-jest');
    return {
        NavigationMixin,
        CurrentPageReference: createTestWireAdapter(jest.fn())
    };
});

// eslint-disable-next-line import/first, import/order
import { CurrentPageReference } from 'lightning/navigation';
import getHomeSummary from '@salesforce/apex/GtmPageContentController.getHomeSummary';
import renameOffering from '@salesforce/apex/GtmPageContentController.renameOffering';
import createOffering from '@salesforce/apex/GtmPageContentController.createOffering';
import renamePage from '@salesforce/apex/GtmPageContentController.renamePage';
import createPage from '@salesforce/apex/GtmPageSectionController.createPage';
import setOfferingStatus from '@salesforce/apex/GtmPageContentController.setOfferingStatus';
import setOfferingArchived from '@salesforce/apex/GtmPageContentController.setOfferingArchived';

// Issue #26, item 6: each offering's card gets a new Manage control exposing
// Status (Draft/Published, gates the GTM Offerings Dashboard listing) and
// Archive (soft-hide only, never a destructive delete). TASK_SCOPE.md flags a
// naming/collision risk: c/gtmContentHome already has a per-page "Settings"
// link (handleOpenSettings) for something else entirely (the Configurator's
// offering-defaults customizer). This suite asserts the new control renders
// under its own label ("Manage offering"), is a separate element from
// Settings, and wires to the two new Apex setters -- not to anything
// Settings-related.

jest.mock(
    '@salesforce/apex/GtmPageContentController.getHomeSummary',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentController.renameOffering',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentController.createOffering',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentController.renamePage',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageSectionController.createPage',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentController.setOfferingStatus',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentController.setOfferingArchived',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const HOME_SUMMARY = {
    offerings: [
        {
            offeringKey: 'gtm',
            label: 'Framework (all offerings)',
            isFramework: true,
            canRename: false,
            offeringStatus: 'Draft',
            archived: false,
            pages: []
        },
        {
            offeringKey: 'ma-migrator',
            label: 'Migration Accelerator',
            isFramework: false,
            canRename: true,
            offeringStatus: 'Published',
            archived: false,
            pages: [
                { offeringKey: 'ma-migrator', templateType: 'story', sectionCount: 5, fieldCount: 20 },
                { offeringKey: 'ma-migrator', templateType: 'configurator', sectionCount: 8, fieldCount: 40 },
                { offeringKey: 'ma-migrator', templateType: 'offerings-listing', sectionCount: 1, fieldCount: 3 }
            ]
        }
    ],
    activity: [],
    pageTitles: {}
};

async function setup() {
    getHomeSummary.mockResolvedValue(JSON.parse(JSON.stringify(HOME_SUMMARY)));
    const element = createElement('c-gtm-content-home', { is: GtmContentHome });
    document.body.appendChild(element);
    CurrentPageReference.emit({ state: {} });
    await flushPromises();
    return element;
}

function manageButtonFor(element, offeringKey) {
    return element.shadowRoot.querySelector(`button.off-foot-manage[data-key="${offeringKey}"]`);
}

function settingsButtonFor(element, offeringKey) {
    return element.shadowRoot.querySelector(`button.off-foot-settings[data-key="${offeringKey}"]`);
}

describe('c-gtm-content-home: offering Manage control (Status / Archive)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders a "Manage offering" control distinct from the existing Settings link', async () => {
        const element = await setup();

        const manageBtn = manageButtonFor(element, 'ma-migrator');
        const settingsBtn = settingsButtonFor(element, 'ma-migrator');

        expect(manageBtn).not.toBeNull();
        expect(settingsBtn).not.toBeNull();
        expect(manageBtn).not.toBe(settingsBtn);
        expect(manageBtn.textContent.trim()).toBe('Manage offering');
        expect(manageBtn.textContent.trim()).not.toBe('Settings');
        expect(settingsBtn.textContent.trim()).toBe('Settings');
    });

    it('does not render a Manage control or status badge on the framework card', async () => {
        const element = await setup();
        const manageBtn = manageButtonFor(element, 'gtm');
        expect(manageBtn).toBeNull();

        const badges = [...element.shadowRoot.querySelectorAll('.off-manage-badge')];
        expect(badges.length).toBe(0);
    });

    it('still renders the Manage control and status badge for a real offering', async () => {
        const element = await setup();
        const manageBtn = manageButtonFor(element, 'ma-migrator');
        expect(manageBtn).not.toBeNull();
    });

    it('opens the Manage modal on click, showing the offering name and no modal beforehand', async () => {
        const element = await setup();
        // LWC's synthetic shadow DOM re-scopes ids referenced by aria-*
        // attributes for uniqueness, so the dialog is found by its role and
        // heading text rather than by the literal "mgTitle" id in source.
        expect(element.shadowRoot.querySelector('section[role="dialog"]')).toBeNull();

        manageButtonFor(element, 'ma-migrator').click();
        await flushPromises();

        const dialog = element.shadowRoot.querySelector('section[role="dialog"]');
        expect(dialog).not.toBeNull();
        const title = dialog.querySelector('h2');
        expect(title).not.toBeNull();
        expect(title.textContent).toContain('Migration Accelerator');
    });

    it('toggling Status calls setOfferingStatus with the offering key and the flipped value', async () => {
        setOfferingStatus.mockResolvedValue(true);
        const element = await setup();

        manageButtonFor(element, 'ma-migrator').click();
        await flushPromises();

        const statusBtn = [...element.shadowRoot.querySelectorAll('lightning-button')]
            .find((b) => b.label === 'Set to Draft');
        expect(statusBtn).toBeDefined();
        statusBtn.click();
        await flushPromises();

        expect(setOfferingStatus).toHaveBeenCalledWith({ offeringKey: 'ma-migrator', status: 'Draft' });
    });

    // Issue #27: the Apex guard in GtmPageContentController.setOfferingStatus
    // rejects a Draft -> Published call unless all three required pages
    // (Story, Configurator, Offerings Listing) are built. These assertions
    // are the client-side courtesy for that same rule -- the button disables
    // and names what's missing, using the same templatesFor()/sectionCount/
    // fieldCount data nextStepHintFor() already reads off getHomeSummary().

    it('disables "Set to Published" and names every missing page for a Draft offering with unbuilt pages', async () => {
        const summary = JSON.parse(JSON.stringify(HOME_SUMMARY));
        const offering = summary.offerings[1]; // ma-migrator
        offering.offeringStatus = 'Draft';
        // Story never built at all.
        offering.pages[0].sectionCount = 0;
        offering.pages[0].fieldCount = 0;
        getHomeSummary.mockResolvedValue(summary);

        const element = createElement('c-gtm-content-home', { is: GtmContentHome });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: {} });
        await flushPromises();

        manageButtonFor(element, 'ma-migrator').click();
        await flushPromises();

        const statusBtn = [...element.shadowRoot.querySelectorAll('lightning-button')]
            .find((b) => b.label === 'Set to Published');
        expect(statusBtn).toBeDefined();
        expect(statusBtn.disabled).toBe(true);

        const hint = element.shadowRoot.querySelector('.modal-note');
        expect(hint.textContent).toContain('Story');
        expect(hint.textContent.toLowerCase()).toContain('still to build');
    });

    it('disables "Set to Published" and names Offerings Listing for the scaffold-only (1 section / 0 fields) bug', async () => {
        // Reproduces the live Migration Accelerator bug exactly: Story and
        // Configurator fully built, Offerings Listing left as the bare
        // tileSectionFor() scaffold (1 section, 0 fields) -- sectionCount
        // alone would read this page as built.
        const summary = JSON.parse(JSON.stringify(HOME_SUMMARY));
        const offering = summary.offerings[1]; // ma-migrator
        offering.offeringStatus = 'Draft';
        const listing = offering.pages.find((p) => p.templateType === 'offerings-listing');
        listing.sectionCount = 1;
        listing.fieldCount = 0;
        getHomeSummary.mockResolvedValue(summary);

        const element = createElement('c-gtm-content-home', { is: GtmContentHome });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: {} });
        await flushPromises();

        manageButtonFor(element, 'ma-migrator').click();
        await flushPromises();

        const statusBtn = [...element.shadowRoot.querySelectorAll('lightning-button')]
            .find((b) => b.label === 'Set to Published');
        expect(statusBtn).toBeDefined();
        expect(statusBtn.disabled).toBe(true);

        const hint = element.shadowRoot.querySelector('.modal-note');
        expect(hint.textContent).toContain('Offerings Listing');
        // Story and Configurator are actually built -- naming them too would
        // disagree with what the card itself already shows as done.
        expect(hint.textContent).not.toContain('Story');
        expect(hint.textContent).not.toContain('Configurator');
    });

    it('leaves "Set to Published" enabled for a Draft offering whose required pages are all built', async () => {
        const summary = JSON.parse(JSON.stringify(HOME_SUMMARY));
        const offering = summary.offerings[1]; // ma-migrator -- fully built in the base fixture
        offering.offeringStatus = 'Draft';
        getHomeSummary.mockResolvedValue(summary);

        const element = createElement('c-gtm-content-home', { is: GtmContentHome });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: {} });
        await flushPromises();

        manageButtonFor(element, 'ma-migrator').click();
        await flushPromises();

        const statusBtn = [...element.shadowRoot.querySelectorAll('lightning-button')]
            .find((b) => b.label === 'Set to Published');
        expect(statusBtn).toBeDefined();
        expect(statusBtn.disabled).toBe(false);

        const hint = element.shadowRoot.querySelector('.modal-note');
        expect(hint.textContent.toLowerCase()).not.toContain('still to build');
    });

    it('archiving asks for confirmation before calling setOfferingArchived', async () => {
        setOfferingArchived.mockResolvedValue(true);
        const element = await setup();

        manageButtonFor(element, 'ma-migrator').click();
        await flushPromises();

        const archiveBtn = [...element.shadowRoot.querySelectorAll('lightning-button')]
            .find((b) => b.label === 'Archive this offering');
        expect(archiveBtn).toBeDefined();
        archiveBtn.click();
        await flushPromises();

        // Still not called -- the click above only opens the confirm step.
        expect(setOfferingArchived).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('Archive "Migration Accelerator"?');

        const confirmBtn = [...element.shadowRoot.querySelectorAll('lightning-button')]
            .filter((b) => b.label === 'Archive this offering')
            .pop();
        confirmBtn.click();
        await flushPromises();

        expect(setOfferingArchived).toHaveBeenCalledWith({ offeringKey: 'ma-migrator', archived: true });
    });

    it('archived offering does not appear in the active grid', async () => {
        const archivedSummary = JSON.parse(JSON.stringify(HOME_SUMMARY));
        archivedSummary.offerings[1].archived = true;
        getHomeSummary.mockResolvedValue(archivedSummary);

        const element = createElement('c-gtm-content-home', { is: GtmContentHome });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: {} });
        await flushPromises();

        // The active off-grid should not contain the archived offering's card.
        // The archived section should render (details.arc-section present).
        const arcSection = element.shadowRoot.querySelector('details.arc-section');
        expect(arcSection).not.toBeNull();

        // The active grid renders cards via off-grid (the first one).
        // The manage button for ma-migrator should only appear inside arc-section
        // since it is archived and moved there, not in the main grid.
        const allManageBtns = element.shadowRoot.querySelectorAll('button.off-foot-manage[data-key="ma-migrator"]');
        // All manage buttons for ma-migrator must be inside the arc-section.
        allManageBtns.forEach((btn) => {
            expect(arcSection.contains(btn)).toBe(true);
        });
    });

    it('archived section is absent when no offerings are archived', async () => {
        const element = await setup();
        const arcSection = element.shadowRoot.querySelector('details.arc-section');
        expect(arcSection).toBeNull();
    });

    it('search auto-expands the archived section when a match is found there', async () => {
        const archivedSummary = JSON.parse(JSON.stringify(HOME_SUMMARY));
        archivedSummary.offerings[1].archived = true;
        getHomeSummary.mockResolvedValue(archivedSummary);

        const element = createElement('c-gtm-content-home', { is: GtmContentHome });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: {} });
        await flushPromises();

        const searchInput = element.shadowRoot.querySelector('lightning-input');
        searchInput.dispatchEvent(new CustomEvent('change', { detail: { value: 'Migration' } }));
        await flushPromises();

        const arcSection = element.shadowRoot.querySelector('details.arc-section');
        expect(arcSection).not.toBeNull();
        expect(arcSection.open).toBe(true);
    });

    it('restoring an already-archived offering calls setOfferingArchived(false) with no confirm step', async () => {
        setOfferingArchived.mockResolvedValue(true);
        const archivedSummary = JSON.parse(JSON.stringify(HOME_SUMMARY));
        archivedSummary.offerings[1].archived = true;
        getHomeSummary.mockResolvedValue(archivedSummary);

        const element = createElement('c-gtm-content-home', { is: GtmContentHome });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: {} });
        await flushPromises();

        manageButtonFor(element, 'ma-migrator').click();
        await flushPromises();

        const restoreBtn = [...element.shadowRoot.querySelectorAll('lightning-button')]
            .find((b) => b.label === 'Restore from archive');
        expect(restoreBtn).toBeDefined();
        restoreBtn.click();
        await flushPromises();

        expect(setOfferingArchived).toHaveBeenCalledWith({ offeringKey: 'ma-migrator', archived: false });
    });

    // issue-184-crash-archived-page-open: clicking from an archived
    // offering's tile into one of its pages -- including a 0-section page
    // like the reported Configurator case -- must not throw. Covers the
    // click itself (handleOpenPage reading offering/template off the
    // archived row's dataset) rather than what gtmContentManager does with
    // the navigation afterwards, which is covered separately in that
    // component's own test file.
    it('clicking an archived offering\'s 0-section page row opens the editor without throwing', async () => {
        const archivedSummary = JSON.parse(JSON.stringify(HOME_SUMMARY));
        archivedSummary.offerings[1].archived = true;
        // Configurator with zero sections -- the reported "EMPTY" case.
        archivedSummary.offerings[1].pages[1].sectionCount = 0;
        archivedSummary.offerings[1].pages[1].fieldCount = 0;
        getHomeSummary.mockResolvedValue(archivedSummary);

        const element = createElement('c-gtm-content-home', { is: GtmContentHome });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: {} });
        await flushPromises();

        const arcSection = element.shadowRoot.querySelector('details.arc-section');
        expect(arcSection).not.toBeNull();

        const configuratorRow = [...element.shadowRoot.querySelectorAll('.arc-section button.pg')]
            .find((b) => b.dataset.offering === 'ma-migrator' && b.dataset.template === 'configurator');
        expect(configuratorRow).toBeDefined();
        expect(configuratorRow.classList.contains('pg--unbuilt')).toBe(true);

        expect(() => configuratorRow.click()).not.toThrow();
        await flushPromises();
    });
});

// Issue #content-home-consolidate-new-page-entry-points: the sidebar
// "New Offering Page" tile (offering-agnostic shortcut, .side-new) is
// removed entirely -- each offering card's own "New page for this
// offering" footer button (handleNewPageFor) is now the single remaining
// entry point into the shared New Offering Page modal.
describe('c-gtm-content-home: single "new page" entry point', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('does not render the removed sidebar "New Offering Page" tile', async () => {
        const element = await setup();
        expect(element.shadowRoot.querySelector('.side-new')).toBeNull();
    });

    it('opens the New Offering Page modal pre-filled with the clicked card\'s offering', async () => {
        const element = await setup();

        const addBtn = element.shadowRoot.querySelector('button.off-foot-btn[data-key="ma-migrator"]');
        expect(addBtn).not.toBeNull();

        expect(element.shadowRoot.querySelector('section[role="dialog"]')).toBeNull();

        addBtn.click();
        await flushPromises();

        const dialog = element.shadowRoot.querySelector('section[role="dialog"]');
        expect(dialog).not.toBeNull();
        expect(dialog.querySelector('.modal-h h2').textContent.trim()).toBe('New Offering Page');

        const offeringCombobox = dialog.querySelector('lightning-combobox');
        expect(offeringCombobox).not.toBeNull();
        expect(offeringCombobox.value).toBe('ma-migrator');
    });
});

function newOfferingDialog(element) {
    return [...element.shadowRoot.querySelectorAll('section[role="dialog"] h2')]
        .find((h) => h.textContent === 'New offering') || null;
}

describe('c-gtm-content-home: header actions (issue page-header-actions-menu)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('passes primary-first actions with the existing icons, and New offering opens the dialog via headeraction', async () => {
        const element = await setup();
        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header.actions.map((a) => [a.name, a.label, a.iconName, a.variant])).toEqual([
            ['open-new-offering', 'New offering', 'utility:new', 'brand'],
            ['refresh', 'Refresh', 'utility:refresh', 'neutral'],
            ['open-recycle-bin', 'Recycle Bin', 'utility:recycle_bin_empty', 'neutral']
        ]);
        expect(newOfferingDialog(element)).toBeNull();
        header.dispatchEvent(new CustomEvent('headeraction', { detail: { name: 'open-new-offering' } }));
        await flushPromises();
        expect(newOfferingDialog(element)).not.toBeNull();
    });

    it('Refresh via headeraction reloads the summary', async () => {
        const element = await setup();
        getHomeSummary.mockClear();
        element.shadowRoot.querySelector('c-gtm-page-header')
            .dispatchEvent(new CustomEvent('headeraction', { detail: { name: 'refresh' } }));
        await flushPromises();
        expect(getHomeSummary).toHaveBeenCalledTimes(1);
    });

    it('Recycle Bin via headeraction navigates to the relocated GTM_Content_Manager_Settings tab, not the retired standalone route', async () => {
        const element = await setup();
        mockNavigate.mockClear();
        element.shadowRoot.querySelector('c-gtm-page-header')
            .dispatchEvent(new CustomEvent('headeraction', { detail: { name: 'open-recycle-bin' } }));
        await flushPromises();
        expect(mockNavigate).toHaveBeenCalledTimes(1);
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Content_Manager_Settings' },
            state: { c__section: 'recycle-bin' }
        });
    });
});

// Issue #21: structural/Framework pages (Offerings Page, Industry Chooser,
// both FAQ panels, Story, Configurator, Offerings Listing, Assistant) have a
// fixed name and must not offer the rename pencil. GtmPageContentController's
// renamePage() enforces the same rule server-side (the must-have half, since
// it also blocks a direct Apex/API call) -- this suite covers the UX half.
const STRUCTURAL_TEMPLATE_TYPES = [
    'offerings-page', 'industry-chooser', 'faq-bd', 'faq-content-manager',
    'assistant', 'story', 'configurator', 'offerings-listing'
];

describe('c-gtm-content-home: structural pages cannot be renamed (issue #21)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders no .pg-rename button anywhere -- every page HOME_SUMMARY renders today is structural', async () => {
        const element = await setup();
        expect(element.shadowRoot.querySelectorAll('.pg-rename').length).toBe(0);
    });

    // The pages list is driven by templatesFor(), which today only ever
    // yields the eight structural/Framework templateTypes, so there is no
    // rendered row that could prove a non-structural page IS still renamable.
    // The positive case is asserted directly against the exported
    // canRenamePage() helper the pages mapper itself calls, using a
    // templateType that does not exist in TEMPLATE_LABELS.
    it('canRenamePage returns false for every structural templateType and true for a non-structural one', () => {
        STRUCTURAL_TEMPLATE_TYPES.forEach((t) => {
            expect(canRenamePage(t)).toBe(false);
        });
        expect(canRenamePage('totally-fake-non-structural-page')).toBe(true);
    });
});
