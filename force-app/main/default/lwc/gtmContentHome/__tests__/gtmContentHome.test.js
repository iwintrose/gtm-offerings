import { createElement } from 'lwc';
import GtmContentHome from 'c/gtmContentHome';
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
            offeringStatus: 'Published',
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

    it('does not render a Manage control on the framework card', async () => {
        const element = await setup();
        expect(manageButtonFor(element, 'gtm')).toBeNull();
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
});
