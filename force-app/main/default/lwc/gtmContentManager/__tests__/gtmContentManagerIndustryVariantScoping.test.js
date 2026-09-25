/**
 * Issue #industry-variant-ui-scoping-fix — the "Industry view" toggle and
 * "+ Industry variant" button must only render on templates that actually
 * support industry variants (today: 'configurator', the one template whose
 * TEMPLATE_LAYOUTS entry carries 'industry-profile'). They must not render
 * on framework/shared templates like 'offerings-listing', and any
 * industryView toggle state must not survive a switch away from a
 * configurator page.
 */
import { createElement } from 'lwc';
import GtmContentManager from 'c/gtmContentManager';
import getOfferings from '@salesforce/apex/GtmPageContentController.getOfferings';
import getTemplateSummary from '@salesforce/apex/GtmPageContentController.getTemplateSummary';
import getEditorSections from '@salesforce/apex/GtmPageSectionController.getEditorSections';
import getAllContent from '@salesforce/apex/GtmPageContentController.getAllContent';
import getIndustryProfiles from '@salesforce/apex/GtmPageContentReader.getIndustryProfiles';
import saveDrafts from '@salesforce/apex/GtmPageContentController.saveDrafts';

jest.mock(
    '@salesforce/apex/GtmPageContentController.getOfferings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentController.getTemplateSummary',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageSectionController.getEditorSections',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentController.getAllContent',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentController.saveDrafts',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentController.publishPage',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentController.discardDrafts',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentController.savePresentation',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageSectionController.saveSectionOrder',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageSectionController.setSectionActive',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageSectionController.createSection',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentController.createIndustry',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageSectionController.deleteSection',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageSectionController.restoreSection',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentReader.getIndustryProfiles',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageSectionController.setSectionHiddenForIndustry',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageSectionController.saveIndustrySectionOrder',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

// jsdom has no scroll implementation; c/gtmPagePreview calls scrollTo() in its
// renderedCallback once a page auto-loads.
Element.prototype.scrollTo = Element.prototype.scrollTo || (() => {});

const OFFERINGS = [{ offeringKey: 'ma-migrator', label: 'Migration Accelerator' }];

const TILE_SECTION = {
    id: 'a01tile',
    sectionKey: 'tile',
    label: 'Tile',
    layoutType: 'offering-tile',
    width: 'standard',
    industryKey: null,
    baseSectionKey: null,
    sortOrder: 10,
    hiddenForIndustry: null,
    industrySortOverrides: null,
    active: true,
    isDeleted: false,
    isNew: false,
    isMoved: false,
    isHidden: false,
    isDraft: false
};

const CONFIGURATOR_SECTION = {
    id: 'a02hero',
    sectionKey: 'hero',
    label: 'Hero',
    layoutType: 'chapter-lede',
    width: 'standard',
    industryKey: null,
    baseSectionKey: null,
    sortOrder: 10,
    hiddenForIndustry: null,
    industrySortOverrides: null,
    active: true,
    isDeleted: false,
    isNew: false,
    isMoved: false,
    isHidden: false,
    isDraft: false
};

const RECORDS = [];

function industryToggleButton(element) {
    return Array.from(element.shadowRoot.querySelectorAll('button')).find(
        (b) => b.textContent.includes('Industry view')
    );
}

function variantAddButtons(element) {
    return Array.from(element.shadowRoot.querySelectorAll('.sec-variant-add'));
}

// The offering combobox is the only lightning-combobox carrying '.gcm-pick'
// without also carrying '.gcm-pick--page' -- the per-page picker inside the
// breadcrumb has both classes, and the industry-filter combobox (rendered
// only while industryView is true) carries neither.
function offeringCombobox(element) {
    return element.shadowRoot.querySelector('lightning-combobox.gcm-pick:not(.gcm-pick--page)');
}

// '.gcm-crumb' is also worn by the "Customizer settings" button, so match on
// its text rather than the class alone.
function backToPagesButton(element) {
    return Array.from(element.shadowRoot.querySelectorAll('button.gcm-crumb')).find(
        (b) => b.textContent.includes('All pages')
    );
}

function saveAndExitButton(element) {
    return Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
        (b) => b.label === 'Save & exit'
    );
}

async function setupOnSingleTemplate(templateType, section) {
    getOfferings.mockResolvedValue(OFFERINGS);
    getTemplateSummary.mockResolvedValue([
        { templateType, sectionCount: 1, fieldCount: 1, pageTitle: null }
    ]);
    getEditorSections.mockResolvedValue([section]);
    getAllContent.mockResolvedValue(RECORDS);
    getIndustryProfiles.mockResolvedValue([]);

    const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
    document.body.appendChild(element);
    await flushPromises();

    const offeringPicker = element.shadowRoot.querySelector('lightning-combobox');
    offeringPicker.dispatchEvent(new CustomEvent('change', { detail: { value: 'ma-migrator' } }));
    await flushPromises();
    await flushPromises();

    return element;
}

describe('c-gtm-content-manager: industry-variant UI scoping (issue #industry-variant-ui-scoping-fix)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('hides the Industry view toggle and + Industry variant button on offerings-listing', async () => {
        const element = await setupOnSingleTemplate('offerings-listing', TILE_SECTION);

        expect(industryToggleButton(element)).toBeUndefined();
        expect(variantAddButtons(element).length).toBe(0);
    });

    it.each(['story', 'offerings-page', 'industry-chooser', 'faq-bd', 'faq-content-manager', 'assistant'])(
        'hides both industry-variant controls on the non-configurator template %s',
        async (templateType) => {
            const element = await setupOnSingleTemplate(templateType, { ...TILE_SECTION, sectionKey: 'sec1' });

            expect(industryToggleButton(element)).toBeUndefined();
            expect(variantAddButtons(element).length).toBe(0);
        }
    );

    it('shows both the Industry view toggle and + Industry variant button on configurator', async () => {
        const element = await setupOnSingleTemplate('configurator', CONFIGURATOR_SECTION);

        expect(industryToggleButton(element)).not.toBeUndefined();
        expect(variantAddButtons(element).length).toBe(1);
    });

    it('resets industryView to false after switching from configurator to a non-configurator page', async () => {
        getOfferings.mockResolvedValue(OFFERINGS);
        getTemplateSummary.mockResolvedValue([
            { templateType: 'configurator', sectionCount: 1, fieldCount: 1, pageTitle: null },
            { templateType: 'offerings-listing', sectionCount: 1, fieldCount: 1, pageTitle: null }
        ]);
        getEditorSections.mockImplementation(({ templateType }) =>
            Promise.resolve(templateType === 'configurator' ? [CONFIGURATOR_SECTION] : [TILE_SECTION])
        );
        getAllContent.mockResolvedValue(RECORDS);
        getIndustryProfiles.mockResolvedValue([]);

        const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
        document.body.appendChild(element);
        await flushPromises();

        const offeringPicker = element.shadowRoot.querySelector('lightning-combobox');
        offeringPicker.dispatchEvent(new CustomEvent('change', { detail: { value: 'ma-migrator' } }));
        await flushPromises();
        await flushPromises();

        // Two built pages -- lands on the page picker, not auto-opened.
        const templateCard = element.shadowRoot.querySelector('[data-template="configurator"]');
        templateCard.dispatchEvent(new CustomEvent('click'));
        await flushPromises();
        await flushPromises();

        const toggle = industryToggleButton(element);
        expect(toggle).not.toBeUndefined();
        toggle.dispatchEvent(new CustomEvent('click'));
        await flushPromises();
        expect(element.shadowRoot.querySelector('.gcm-industry-picker')).not.toBeNull();

        // Switch to the page picker's "Page" combobox, over to offerings-listing.
        const pagePicker = element.shadowRoot.querySelector('.gcm-pick--page');
        pagePicker.dispatchEvent(new CustomEvent('change', { detail: { value: 'offerings-listing' } }));
        await flushPromises();
        await flushPromises();

        // The toggle/button are gone on this template, and there is no
        // industry-view rail left stuck open behind them.
        expect(industryToggleButton(element)).toBeUndefined();
        expect(variantAddButtons(element).length).toBe(0);
        expect(element.shadowRoot.querySelector('.gcm-industry-picker')).toBeNull();

        // And switching back to configurator starts in the normal (not
        // industry-view) rail mode, not still toggled on from before.
        const pagePicker2 = element.shadowRoot.querySelector('.gcm-pick--page');
        pagePicker2.dispatchEvent(new CustomEvent('change', { detail: { value: 'configurator' } }));
        await flushPromises();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.gcm-industry-picker')).toBeNull();
        expect(industryToggleButton(element).textContent).toContain('Industry view');
    });

    // The reset above (loadPage()'s guard) is only one of five places the fix
    // added `this.industryView = false;`. The other four -- handleBackToPages,
    // handleOfferingChange, handleSaveAndExit and openRequestedPage -- are not
    // reachable through handlePageChange at all, so they need their own
    // coverage or a regression in any one of them ships with a fully green
    // suite. See issue #industry-variant-ui-scoping-fix QA fail notes.

    it('does not leave Industry view stuck on after "Back to pages" and reopening the same configurator', async () => {
        getOfferings.mockResolvedValue(OFFERINGS);
        getTemplateSummary.mockResolvedValue([
            { templateType: 'configurator', sectionCount: 1, fieldCount: 1, pageTitle: null },
            { templateType: 'offerings-listing', sectionCount: 1, fieldCount: 1, pageTitle: null }
        ]);
        getEditorSections.mockImplementation(({ templateType }) =>
            Promise.resolve(templateType === 'configurator' ? [CONFIGURATOR_SECTION] : [TILE_SECTION])
        );
        getAllContent.mockResolvedValue(RECORDS);
        getIndustryProfiles.mockResolvedValue([]);

        const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
        document.body.appendChild(element);
        await flushPromises();

        offeringCombobox(element).dispatchEvent(new CustomEvent('change', { detail: { value: 'ma-migrator' } }));
        await flushPromises();
        await flushPromises();

        // Two built pages -- lands on the page picker, not auto-opened.
        const templateCard = element.shadowRoot.querySelector('[data-template="configurator"]');
        templateCard.dispatchEvent(new CustomEvent('click'));
        await flushPromises();
        await flushPromises();

        const toggle = industryToggleButton(element);
        expect(toggle).not.toBeUndefined();
        toggle.dispatchEvent(new CustomEvent('click'));
        await flushPromises();
        expect(element.shadowRoot.querySelector('.gcm-industry-picker')).not.toBeNull();
        // Pick an industry too, so the filter-key reset is actually exercised
        // (an unset key would trivially "look" cleared either way).
        const industryFilter = element.shadowRoot.querySelector('.gcm-industry-picker lightning-combobox');
        industryFilter.dispatchEvent(new CustomEvent('change', { detail: { value: 'healthcare' } }));
        await flushPromises();

        // handleBackToPages -- distinct from a template switch via the page
        // picker, which is the only path the pre-existing spec drove.
        const backButton = backToPagesButton(element);
        expect(backButton).not.toBeUndefined();
        backButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        // Reopen the very same configurator page from the picker.
        const templateCardAgain = element.shadowRoot.querySelector('[data-template="configurator"]');
        templateCardAgain.dispatchEvent(new CustomEvent('click'));
        await flushPromises();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.gcm-industry-picker')).toBeNull();
        expect(industryToggleButton(element).textContent).toContain('Industry view');
        // Re-opening Industry view fresh must not carry over the old filter.
        industryToggleButton(element).dispatchEvent(new CustomEvent('click'));
        await flushPromises();
        expect(
            element.shadowRoot.querySelector('.gcm-industry-picker lightning-combobox').value
        ).toBe('');
    });

    it('does not leave Industry view stuck on after switching to a different offering', async () => {
        const TWO_OFFERINGS = [
            { offeringKey: 'ma-migrator', label: 'Migration Accelerator' },
            { offeringKey: 'other-offering', label: 'Other Offering' }
        ];
        getOfferings.mockResolvedValue(TWO_OFFERINGS);
        getTemplateSummary.mockResolvedValue([
            { templateType: 'configurator', sectionCount: 1, fieldCount: 1, pageTitle: null }
        ]);
        getEditorSections.mockResolvedValue([CONFIGURATOR_SECTION]);
        getAllContent.mockResolvedValue(RECORDS);
        getIndustryProfiles.mockResolvedValue([]);

        const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
        document.body.appendChild(element);
        await flushPromises();

        // Neither offering is auto-selected (two offerings exist), and each
        // has exactly one built page, so choosing one auto-opens its
        // configurator straight into the editor.
        offeringCombobox(element).dispatchEvent(new CustomEvent('change', { detail: { value: 'ma-migrator' } }));
        await flushPromises();
        await flushPromises();

        const toggle = industryToggleButton(element);
        expect(toggle).not.toBeUndefined();
        toggle.dispatchEvent(new CustomEvent('click'));
        await flushPromises();
        expect(element.shadowRoot.querySelector('.gcm-industry-picker')).not.toBeNull();

        // handleOfferingChange -- the new offering's configurator also
        // supports industry variants, so this proves the *state* did not
        // carry over, not merely that the controls disappeared.
        offeringCombobox(element).dispatchEvent(
            new CustomEvent('change', { detail: { value: 'other-offering' } })
        );
        await flushPromises();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.gcm-industry-picker')).toBeNull();
        expect(industryToggleButton(element).textContent).toContain('Industry view');
    });

    it('does not leave Industry view stuck on after Save & exit and reopening a configurator', async () => {
        const DRAFT_RECORD = {
            id: 'rec1',
            sectionKey: 'hero',
            fieldKey: 'headline',
            fieldType: 'text',
            label: 'Headline',
            textValue: 'Original',
            richValue: null,
            jsonValue: null,
            draftValue: 'Edited',
            isDraft: true,
            active: true,
            pendingDelete: false
        };
        getOfferings.mockResolvedValue(OFFERINGS);
        getTemplateSummary.mockResolvedValue([
            { templateType: 'configurator', sectionCount: 1, fieldCount: 1, pageTitle: null }
        ]);
        getEditorSections.mockResolvedValue([CONFIGURATOR_SECTION]);
        // A draft record is what makes hasDrafts (and so the Save & exit
        // button) render without needing a separate field edit first.
        getAllContent.mockResolvedValue([DRAFT_RECORD]);
        getIndustryProfiles.mockResolvedValue([]);
        saveDrafts.mockResolvedValue();

        const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
        document.body.appendChild(element);
        await flushPromises();

        offeringCombobox(element).dispatchEvent(new CustomEvent('change', { detail: { value: 'ma-migrator' } }));
        await flushPromises();
        await flushPromises();

        const toggle = industryToggleButton(element);
        expect(toggle).not.toBeUndefined();
        toggle.dispatchEvent(new CustomEvent('click'));
        await flushPromises();
        expect(element.shadowRoot.querySelector('.gcm-industry-picker')).not.toBeNull();

        // handleSaveAndExit -- back to the page picker with a kept draft.
        const saveExitButton = saveAndExitButton(element);
        expect(saveExitButton).not.toBeUndefined();
        saveExitButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        // Reopen the same configurator page.
        const templateCard = element.shadowRoot.querySelector('[data-template="configurator"]');
        expect(templateCard).not.toBeNull();
        templateCard.dispatchEvent(new CustomEvent('click'));
        await flushPromises();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.gcm-industry-picker')).toBeNull();
        expect(industryToggleButton(element).textContent).toContain('Industry view');
    });
});
