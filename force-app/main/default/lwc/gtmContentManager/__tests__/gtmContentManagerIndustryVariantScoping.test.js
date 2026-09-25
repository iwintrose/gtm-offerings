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
});
