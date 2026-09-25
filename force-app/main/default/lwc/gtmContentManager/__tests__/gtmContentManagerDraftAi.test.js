/**
 * Issue #industry-variants-agentforce-draft — "Draft with AI" modal in
 * c/gtmContentManager. Regression guard per the plan's verification step 8:
 * a successful draft must land as an editable Draft (isDraft/draftValue via
 * saveDrafts), never auto-publish.
 */
import { createElement } from 'lwc';
import GtmContentManager from 'c/gtmContentManager';
import getOfferings from '@salesforce/apex/GtmPageContentController.getOfferings';
import getTemplateSummary from '@salesforce/apex/GtmPageContentController.getTemplateSummary';
import getEditorSections from '@salesforce/apex/GtmPageSectionController.getEditorSections';
import getAllContent from '@salesforce/apex/GtmPageContentController.getAllContent';
import saveDrafts from '@salesforce/apex/GtmPageContentController.saveDrafts';
import publishPage from '@salesforce/apex/GtmPageContentController.publishPage';
import chatOnContentDraft from '@salesforce/apex/GtmAgentContentDraftController.chat';

jest.mock('@salesforce/apex/GtmPageContentController.getOfferings', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageContentController.getTemplateSummary', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageSectionController.getEditorSections', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageContentController.getAllContent', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageContentController.saveDrafts', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageContentController.publishPage', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageContentController.discardDrafts', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageContentController.savePresentation', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageSectionController.saveSectionOrder', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageSectionController.setSectionActive', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageSectionController.createSection', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageContentController.createIndustry', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageSectionController.deleteSection', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageSectionController.restoreSection', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageContentReader.getIndustryProfiles', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageSectionController.setSectionHiddenForIndustry', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageSectionController.saveIndustrySectionOrder', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmAgentContentDraftController.chat', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

Element.prototype.scrollTo = Element.prototype.scrollTo || (() => {});

const OFFERINGS = [{ offeringKey: 'ma-migrator', label: 'Migration Accelerator' }];
const TEMPLATES = [{ templateType: 'story', sectionCount: 2, fieldCount: 2, pageTitle: null }];

const BASE_SECTION = {
    id: 'a01base', sectionKey: 'problem', label: 'Problem', layoutType: 'hero', width: 'standard',
    industryKey: null, baseSectionKey: null, active: true, isDeleted: false, isNew: false,
    isMoved: false, isHidden: false, isDraft: false
};

const VARIANT_SECTION = {
    id: 'a02variant', sectionKey: 'problem--healthcare', label: 'Problem', layoutType: 'hero',
    width: 'standard', industryKey: 'healthcare', baseSectionKey: 'problem', active: true,
    isDeleted: false, isNew: false, isMoved: false, isHidden: false, isDraft: false
};

const RECORDS = [
    { id: 'r1', sectionKey: 'problem', fieldKey: 'headline', fieldType: 'text', label: 'Headline', textValue: 'Hi' },
    { id: 'r2', sectionKey: 'problem--healthcare', fieldKey: 'headline', fieldType: 'text', label: 'Headline', textValue: 'Hi (healthcare)' }
];

async function setupOnVariant() {
    getOfferings.mockResolvedValue(OFFERINGS);
    getTemplateSummary.mockResolvedValue(TEMPLATES);
    getEditorSections.mockResolvedValue([BASE_SECTION, VARIANT_SECTION]);
    getAllContent.mockResolvedValue(RECORDS);

    const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
    document.body.appendChild(element);
    await flushPromises();

    const offeringPicker = element.shadowRoot.querySelector('lightning-combobox');
    offeringPicker.dispatchEvent(new CustomEvent('change', { detail: { value: 'ma-migrator' } }));
    await flushPromises();
    await flushPromises();

    // Select the variant row so it becomes the active section.
    const variantRow = element.shadowRoot.querySelector('[data-key="problem--healthcare"]');
    expect(variantRow).not.toBeNull();
    variantRow.dispatchEvent(new CustomEvent('click'));
    await flushPromises();

    return element;
}

describe('c-gtm-content-manager: Draft with AI (issue #industry-variants-agentforce-draft)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows the "Draft with AI" button only when the active section is an industry variant', async () => {
        getEditorSections.mockResolvedValue([BASE_SECTION, VARIANT_SECTION]);
        getOfferings.mockResolvedValue(OFFERINGS);
        getTemplateSummary.mockResolvedValue(TEMPLATES);
        getAllContent.mockResolvedValue(RECORDS);

        const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
        document.body.appendChild(element);
        await flushPromises();
        const offeringPicker = element.shadowRoot.querySelector('lightning-combobox');
        offeringPicker.dispatchEvent(new CustomEvent('change', { detail: { value: 'ma-migrator' } }));
        await flushPromises();
        await flushPromises();

        // Default lands on the base section: no button yet.
        expect(element.shadowRoot.querySelector('.gcm-draft-ai-btn')).toBeNull();

        const variantRow = element.shadowRoot.querySelector('[data-key="problem--healthcare"]');
        variantRow.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(element.shadowRoot.querySelector('.gcm-draft-ai-btn')).not.toBeNull();
    });

    it('opens the modal and calls chatOnContentDraft with the active section', async () => {
        chatOnContentDraft.mockResolvedValue(JSON.stringify({
            text: 'Drafted the headline.',
            historyJson: '[]',
            changes: { proposedFields: { headline: 'AI-drafted headline' } }
        }));
        const element = await setupOnVariant();

        const draftBtn = element.shadowRoot.querySelector('.gcm-draft-ai-btn');
        draftBtn.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        const buttons = Array.from(element.shadowRoot.querySelectorAll('lightning-button'));
        const goBtn = buttons.find((b) => b.label === 'Draft');
        expect(goBtn).not.toBeNull();
        goBtn.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(chatOnContentDraft).toHaveBeenCalledWith(
            expect.objectContaining({
                offeringKey: 'ma-migrator',
                templateType: 'story',
                sectionKey: 'problem--healthcare'
            })
        );
    });

    it('REGRESSION GUARD: a successful draft lands as a Draft via saveDrafts, never publishPage', async () => {
        chatOnContentDraft.mockResolvedValue(JSON.stringify({
            text: 'Drafted the headline.',
            historyJson: '[]',
            changes: { proposedFields: { headline: 'AI-drafted headline' } }
        }));
        saveDrafts.mockResolvedValue(undefined);
        const element = await setupOnVariant();

        element.shadowRoot.querySelector('.gcm-draft-ai-btn').dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        const goBtn = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Draft');
        goBtn.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        // The debounced autosave (writeValue -> scheduleSave -> saveDraft) fires
        // 900ms after the last edit; wait past that instead of asserting
        // implementation details of the timer.
        await new Promise((resolve) => setTimeout(resolve, 950));
        await flushPromises();

        expect(saveDrafts).toHaveBeenCalledWith({
            edits: expect.arrayContaining([
                expect.objectContaining({ id: 'r2', value: 'AI-drafted headline' })
            ])
        });
        expect(publishPage).not.toHaveBeenCalled();
    });

    it('shows an error and does not close the modal when chatOnContentDraft fails', async () => {
        chatOnContentDraft.mockRejectedValue({ body: { message: 'GUS is not set up yet.' } });
        const element = await setupOnVariant();

        element.shadowRoot.querySelector('.gcm-draft-ai-btn').dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        const goBtn = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Draft');
        goBtn.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        // Modal stays open on failure so the editor can retry, and the error
        // renders inside it.
        const modalHeading = element.shadowRoot.querySelector('.modal-h h2');
        expect(modalHeading).not.toBeNull();
        expect(modalHeading.textContent).toBe('Draft with AI');
        const errorEl = element.shadowRoot.querySelector('.gcm-industry-error');
        expect(errorEl).not.toBeNull();
        expect(errorEl.textContent).toContain('GUS is not set up yet.');
    });
});
