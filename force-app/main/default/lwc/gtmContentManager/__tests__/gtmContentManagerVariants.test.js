/**
 * Issue #industry-variants-core — "+ Industry variant" modal and rail
 * grouping in c/gtmContentManager.
 */
import { createElement } from 'lwc';
import GtmContentManager from 'c/gtmContentManager';
import getOfferings from '@salesforce/apex/GtmPageContentController.getOfferings';
import getTemplateSummary from '@salesforce/apex/GtmPageContentController.getTemplateSummary';
import getEditorSections from '@salesforce/apex/GtmPageSectionController.getEditorSections';
import getAllContent from '@salesforce/apex/GtmPageContentController.getAllContent';
import createSection from '@salesforce/apex/GtmPageSectionController.createSection';
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

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

// jsdom has no scroll implementation; c/gtmPagePreview calls scrollTo() in its
// renderedCallback once a page auto-loads (this suite lands directly on a
// single-page offering, unlike the page-title-override suite, which stays on
// the page picker and never renders the preview).
Element.prototype.scrollTo = Element.prototype.scrollTo || (() => {});

const OFFERINGS = [{ offeringKey: 'ma-migrator', label: 'Migration Accelerator' }];
// The "+ Industry variant" button only renders on 'configurator' (the one
// template carrying the 'industry-profile' layout — see issue
// #industry-variant-ui-scoping-fix), so this suite exercises that template.
const TEMPLATES = [
    { templateType: 'configurator', sectionCount: 1, fieldCount: 2, pageTitle: null }
];

const BASE_SECTION = {
    id: 'a01base',
    sectionKey: 'problem',
    label: 'Problem',
    layoutType: 'hero',
    width: 'standard',
    industryKey: null,
    baseSectionKey: null,
    active: true,
    isDeleted: false,
    isNew: false,
    isMoved: false,
    isHidden: false,
    isDraft: false
};

const VARIANT_SECTION = {
    id: 'a02variant',
    sectionKey: 'problem--healthcare',
    label: 'Problem',
    layoutType: 'hero',
    width: 'standard',
    industryKey: 'healthcare',
    baseSectionKey: 'problem',
    active: true,
    isDeleted: false,
    isNew: false,
    isMoved: false,
    isHidden: false,
    isDraft: false
};

const RECORDS = [
    { id: 'r1', sectionKey: 'problem', fieldKey: 'headline', fieldType: 'text', label: 'Headline', textValue: 'Hi' }
];

async function setupOnPage(sections) {
    getOfferings.mockResolvedValue(OFFERINGS);
    getTemplateSummary.mockResolvedValue(TEMPLATES);
    getEditorSections.mockResolvedValue(sections);
    getAllContent.mockResolvedValue(RECORDS);

    const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
    document.body.appendChild(element);
    await flushPromises();

    const offeringPicker = element.shadowRoot.querySelector('lightning-combobox');
    offeringPicker.dispatchEvent(new CustomEvent('change', { detail: { value: 'ma-migrator' } }));
    await flushPromises();

    // Land on the only built page automatically (built.length === 1 path).
    await flushPromises();

    return element;
}

describe('c-gtm-content-manager: industry variants (issue #industry-variants-core)', () => {
    beforeEach(() => {
        // The 'configurator' preview mounts c-gtm-saved-links-bar, which calls
        // getIndustryProfiles on connectedCallback -- default it here so that
        // call doesn't crash; a test that needs specific data overrides this
        // afterward, before it renders.
        getIndustryProfiles.mockResolvedValue([]);
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('groups a variant section under its base in the rail rather than listing it separately', async () => {
        const element = await setupOnPage([BASE_SECTION, VARIANT_SECTION]);

        // Only the base section counts toward the rail's own sequence.
        const countEl = element.shadowRoot.querySelector('.gcm-count');
        expect(countEl.textContent).toBe('1');
    });

    it('opens the "+ Industry variant" modal, loads industries and hides ones already used', async () => {
        getIndustryProfiles.mockResolvedValue([
            { industryKey: 'healthcare', industryLabel: 'Healthcare' },
            { industryKey: 'retail', industryLabel: 'Retail' }
        ]);
        const element = await setupOnPage([BASE_SECTION, VARIANT_SECTION]);

        const addVariantBtn = element.shadowRoot.querySelector('.sec-variant-add');
        expect(addVariantBtn).not.toBeNull();
        // c-gtm-saved-links-bar's own connectedCallback already called this
        // mock once while the page was loading -- clear that call so the
        // assertion below is actually about the click, not a coincidental
        // match against an unrelated child component's mount-time fetch.
        getIndustryProfiles.mockClear();
        addVariantBtn.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(getIndustryProfiles).toHaveBeenCalledWith({ offeringKey: 'gtm', templateType: 'industry-chooser' });

        // healthcare already has a variant of 'problem', so only retail should
        // be offered.
        const combo = element.shadowRoot.querySelector('.modal-b lightning-combobox');
        expect(combo).not.toBeNull();
        expect(combo.options).toEqual([{ label: 'Retail', value: 'retail' }]);
    });

    it('createSection is called with industryKey/baseSectionKey and a snapshot of the base fields', async () => {
        getIndustryProfiles.mockResolvedValue([{ industryKey: 'retail', industryLabel: 'Retail' }]);
        createSection.mockResolvedValue('a03newvariant');
        const element = await setupOnPage([BASE_SECTION]);

        const addVariantBtn = element.shadowRoot.querySelector('.sec-variant-add');
        addVariantBtn.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        const combo = element.shadowRoot.querySelector('.modal-b lightning-combobox');
        combo.dispatchEvent(new CustomEvent('change', { detail: { value: 'retail' } }));

        // Re-mock getEditorSections so the reload after create resolves too.
        getEditorSections.mockResolvedValue([BASE_SECTION, VARIANT_SECTION]);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const addBtn = Array.from(buttons).find((b) => b.label === 'Add industry variant');
        addBtn.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(createSection).toHaveBeenCalledWith(
            expect.objectContaining({
                offeringKey: 'ma-migrator',
                templateType: 'configurator',
                industryKey: 'retail',
                baseSectionKey: 'problem',
                fields: [{ fieldKey: 'headline', fieldType: 'text', label: 'Headline' }]
            })
        );
    });
});
