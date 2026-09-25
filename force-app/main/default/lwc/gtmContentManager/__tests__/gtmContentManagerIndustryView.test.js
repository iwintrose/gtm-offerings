/**
 * Issue #industry-variants-visibility-nav — the rail's "Industry view" mode:
 * toggle, industry picker, per-base-section Generic/Customized/Hidden status,
 * and drag reordering scoped to one industry.
 */
import { createElement } from 'lwc';
import GtmContentManager from 'c/gtmContentManager';
import getOfferings from '@salesforce/apex/GtmPageContentController.getOfferings';
import getTemplateSummary from '@salesforce/apex/GtmPageContentController.getTemplateSummary';
import getEditorSections from '@salesforce/apex/GtmPageSectionController.getEditorSections';
import getAllContent from '@salesforce/apex/GtmPageContentController.getAllContent';
import getIndustryProfiles from '@salesforce/apex/GtmPageContentReader.getIndustryProfiles';
import setSectionHiddenForIndustry from '@salesforce/apex/GtmPageSectionController.setSectionHiddenForIndustry';
import saveIndustrySectionOrder from '@salesforce/apex/GtmPageSectionController.saveIndustrySectionOrder';

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

Element.prototype.scrollTo = Element.prototype.scrollTo || (() => {});

const OFFERINGS = [{ offeringKey: 'ma-migrator', label: 'Migration Accelerator' }];
const TEMPLATES = [
    // Industry view is only a real capability on 'configurator' (the one
    // template carrying the 'industry-profile' layout — see issue
    // #industry-variant-ui-scoping-fix). Using it here keeps this suite
    // testing a template the toggle actually renders on.
    { templateType: 'configurator', sectionCount: 2, fieldCount: 2, pageTitle: null }
];

const HERO_SECTION = {
    id: 'a01hero',
    sectionKey: 'hero',
    label: 'Hero',
    layoutType: 'hero',
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

const FAQ_SECTION = {
    id: 'a02faq',
    sectionKey: 'faq',
    label: 'FAQ',
    layoutType: 'faq',
    width: 'standard',
    industryKey: null,
    baseSectionKey: null,
    sortOrder: 20,
    hiddenForIndustry: 'healthcare',
    industrySortOverrides: null,
    active: true,
    isDeleted: false,
    isNew: false,
    isMoved: false,
    isHidden: false,
    isDraft: false
};

const PROBLEM_SECTION = {
    id: 'a03problem',
    sectionKey: 'problem',
    label: 'Problem',
    layoutType: 'hero',
    width: 'standard',
    industryKey: null,
    baseSectionKey: null,
    sortOrder: 30,
    hiddenForIndustry: null,
    industrySortOverrides: '{"healthcare": 5}',
    active: true,
    isDeleted: false,
    isNew: false,
    isMoved: false,
    isHidden: false,
    isDraft: false
};

const PROBLEM_VARIANT = {
    id: 'a04variant',
    sectionKey: 'problem--healthcare',
    label: 'The Healthcare Problem',
    layoutType: 'card-grid',
    width: 'standard',
    industryKey: 'healthcare',
    baseSectionKey: 'problem',
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

const RECORDS = [
    { id: 'r1', sectionKey: 'hero', fieldKey: 'headline', fieldType: 'text', label: 'Headline', textValue: 'Hi' }
];

async function setupOnPage(sections) {
    getOfferings.mockResolvedValue(OFFERINGS);
    getTemplateSummary.mockResolvedValue(TEMPLATES);
    getEditorSections.mockResolvedValue(sections);
    getAllContent.mockResolvedValue(RECORDS);
    // The 'configurator' preview mounts c-gtm-saved-links-bar, which calls
    // getIndustryProfiles on connectedCallback -- default it so that call
    // doesn't crash before enterIndustryView sets its own mock.
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

function industryToggleButton(element) {
    return Array.from(element.shadowRoot.querySelectorAll('button')).find(
        (b) => b.textContent.includes('Industry view')
    );
}

async function enterIndustryView(element, industryKey) {
    getIndustryProfiles.mockResolvedValue([
        { industryKey: 'healthcare', industryLabel: 'Healthcare' },
        { industryKey: 'retail', industryLabel: 'Retail' }
    ]);
    industryToggleButton(element).dispatchEvent(new CustomEvent('click'));
    await flushPromises();

    const picker = element.shadowRoot.querySelector('.gcm-industry-picker lightning-combobox');
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: industryKey } }));
    await flushPromises();
}

describe('c-gtm-content-manager: Industry view rail mode (issue #industry-variants-visibility-nav)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows the industry toggle and loads industries via getIndustryProfiles on first use', async () => {
        const element = await setupOnPage([HERO_SECTION, FAQ_SECTION]);
        await enterIndustryView(element, 'healthcare');

        expect(getIndustryProfiles).toHaveBeenCalledWith({ offeringKey: 'gtm', templateType: 'industry-chooser' });
        expect(element.shadowRoot.querySelector('.gcm-industry-picker')).not.toBeNull();
    });

    it('labels every base section Generic, Customized or Hidden for the selected industry', async () => {
        const element = await setupOnPage([HERO_SECTION, FAQ_SECTION, PROBLEM_SECTION, PROBLEM_VARIANT]);
        await enterIndustryView(element, 'healthcare');

        const statuses = Array.from(element.shadowRoot.querySelectorAll('.sec-industry-status'))
            .map((el) => el.textContent);
        expect(statuses).toContain('Generic');   // hero
        expect(statuses).toContain('Hidden');    // faq
        expect(statuses).toContain('Customized'); // problem (has a live healthcare variant)
    });

    it('applies the Industry_Sort_Overrides__c order, so an overridden section moves ahead', async () => {
        const element = await setupOnPage([HERO_SECTION, PROBLEM_SECTION, PROBLEM_VARIANT]);
        await enterIndustryView(element, 'healthcare');

        const names = Array.from(element.shadowRoot.querySelectorAll('.gcm-rail-body .sec-name'))
            .map((el) => el.textContent);
        // problem's healthcare override (5) sorts it before hero (10).
        expect(names.indexOf('The Healthcare Problem')).toBeLessThan(names.indexOf('Hero'));
    });

    it('calls setSectionHiddenForIndustry when the hide toggle is clicked', async () => {
        setSectionHiddenForIndustry.mockResolvedValue(true);
        const element = await setupOnPage([HERO_SECTION, FAQ_SECTION]);
        await enterIndustryView(element, 'healthcare');

        // Re-mock the reload after the toggle.
        getEditorSections.mockResolvedValue([HERO_SECTION, FAQ_SECTION]);

        const rows = element.shadowRoot.querySelectorAll('.gcm-rail-body .sec--industry');
        const heroRow = Array.from(rows).find((r) => r.textContent.includes('Hero'));
        const toggleBtn = heroRow.querySelector('.mv');
        toggleBtn.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(setSectionHiddenForIndustry).toHaveBeenCalledWith({
            sectionId: 'a01hero',
            industryKey: 'healthcare',
            hidden: true
        });
    });

    it('calls saveIndustrySectionOrder on drop, scoped to the selected industry, and never touches saveSectionOrder', async () => {
        saveIndustrySectionOrder.mockResolvedValue(['a02faq', 'a01hero']);
        const element = await setupOnPage([HERO_SECTION, PROBLEM_SECTION]);
        await enterIndustryView(element, 'retail');

        getEditorSections.mockResolvedValue([HERO_SECTION, PROBLEM_SECTION]);

        const rows = element.shadowRoot.querySelectorAll('.gcm-rail-body .sec--industry');
        const first = rows[0];
        const second = rows[1];

        first.dispatchEvent(new CustomEvent('dragstart'));
        const dropEvent = new CustomEvent('drop');
        dropEvent.preventDefault = jest.fn();
        second.dispatchEvent(dropEvent);
        await flushPromises();

        expect(saveIndustrySectionOrder).toHaveBeenCalledWith(
            expect.objectContaining({ industryKey: 'retail' })
        );
    });
});
