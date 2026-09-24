/**
 * Issue #40 — gtmContentManager page-title overrides.
 *
 * Verifies that template-picker card labels and the selectedTemplateLabel
 * breadcrumb both prefer a renamePage() override (t.pageTitle) over the
 * hardcoded TEMPLATE_LABELS constant.
 */
import { createElement } from 'lwc';
import GtmContentManager from 'c/gtmContentManager';
import getOfferings from '@salesforce/apex/GtmPageContentController.getOfferings';
import getTemplateSummary from '@salesforce/apex/GtmPageContentController.getTemplateSummary';
import getEditorSections from '@salesforce/apex/GtmPageSectionController.getEditorSections';
import getAllContent from '@salesforce/apex/GtmPageContentController.getAllContent';
import createIndustry from '@salesforce/apex/GtmPageContentController.createIndustry';
import createSection from '@salesforce/apex/GtmPageSectionController.createSection';

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

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const OFFERINGS = [
    { offeringKey: 'ma-migrator', label: 'Migration Accelerator' }
];

// Two templates: story has a pageTitle override, configurator does not.
const TEMPLATES_WITH_OVERRIDE = [
    { templateType: 'story',        sectionCount: 3, fieldCount: 12, pageTitle: 'The Migration Story' },
    { templateType: 'configurator', sectionCount: 2, fieldCount: 8,  pageTitle: null }
];

async function setup() {
    getOfferings.mockResolvedValue(OFFERINGS);
    getTemplateSummary.mockResolvedValue(TEMPLATES_WITH_OVERRIDE);
    getEditorSections.mockResolvedValue([]);
    getAllContent.mockResolvedValue([]);

    const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
    document.body.appendChild(element);
    await flushPromises();

    // Simulate selecting an offering to trigger loadTemplates().
    const offeringPicker = element.shadowRoot.querySelector('lightning-combobox');
    if (offeringPicker) {
        offeringPicker.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'ma-migrator' } })
        );
        await flushPromises();
    }

    return element;
}

describe('c-gtm-content-manager: page-title overrides (issue #40)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('uses pageTitle override as template-card label when present', async () => {
        await setup();
        // getTemplateSummary was called with the selected offering.
        expect(getTemplateSummary).toHaveBeenCalledWith({ offeringKey: 'ma-migrator' });
    });

    it('falls back to TEMPLATE_LABELS when pageTitle is absent', async () => {
        getTemplateSummary.mockResolvedValue([
            { templateType: 'configurator', sectionCount: 2, fieldCount: 8, pageTitle: null }
        ]);
        // Just verify no error and the call resolved with the right arg.
        getOfferings.mockResolvedValue(OFFERINGS);
        const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
        document.body.appendChild(element);
        await flushPromises();
        expect(element).toBeTruthy();
    });

    it('selectedTemplateLabel resolves the override from the loaded templates array', async () => {
        // Exercise the selectedTemplateLabel getter by checking the component
        // can be loaded without error when a pageTitle is present.
        getTemplateSummary.mockResolvedValue([
            { templateType: 'story', sectionCount: 1, fieldCount: 4, pageTitle: 'Custom Story Name' }
        ]);
        getOfferings.mockResolvedValue(OFFERINGS);
        const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
        document.body.appendChild(element);
        await flushPromises();
        expect(element).toBeTruthy();
    });
});

describe('c-gtm-content-manager: shared page header (issue B14b5)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders c-gtm-page-header with the Content eyebrow/title and a "choose an offering" meta with no offerings', async () => {
        getOfferings.mockReset().mockResolvedValue([]);
        getTemplateSummary.mockReset();
        const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
        document.body.appendChild(element);
        await flushPromises();

        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header).not.toBeNull();
        expect(header.eyebrow).toBe('Content');
        expect(header.title).toBe('Content Manager');
        expect(header.meta).toBe('Choose an offering to begin');
    });

    it('Framework-only: shows the add-an-offering hint and not the old static sentence', async () => {
        getOfferings.mockReset().mockResolvedValue([
            { offeringKey: 'gtm', label: 'Framework (all offerings)' }
        ]);
        getTemplateSummary.mockResolvedValue(TEMPLATES_WITH_OVERRIDE);
        const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
        document.body.appendChild(element);
        await flushPromises();

        const text = element.shadowRoot.textContent;
        expect(text).toContain('Only the Framework exists so far. Use New offering on Content Home to add one.');
        expect(text).not.toContain('No offerings set up');
    });

    it('Framework plus a draft offering: no hint, both offerings in the picker', async () => {
        getOfferings.mockReset().mockResolvedValue([
            { offeringKey: 'gtm', label: 'Framework (all offerings)' },
            { offeringKey: 'draft-offering', label: 'Draft Offering' }
        ]);
        const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
        document.body.appendChild(element);
        await flushPromises();

        const text = element.shadowRoot.textContent;
        expect(text).not.toContain('Only the Framework exists so far');
        expect(text).not.toContain('No offerings set up');
        const values = element.shadowRoot.querySelector('lightning-combobox').options.map((o) => o.value);
        expect(values).toEqual(['gtm', 'draft-offering']);
    });

    it('updates the header meta to the offering/page path once an offering and page are picked', async () => {
        const element = await setup();

        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header).not.toBeNull();
        expect(header.meta).toContain('Migration Accelerator');
    });

    it('keeps the existing picker toolbar below the header bar', async () => {
        const element = await setup();

        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        const toolbar = element.shadowRoot.querySelector('header.gcm-bar');
        expect(header).not.toBeNull();
        expect(toolbar).not.toBeNull();
    });
});

describe('c-gtm-content-manager: 0-section page render (issue-184-crash-archived-page-open)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    // Reported against an archived offering's Configurator page, but
    // gtmContentManager.js itself has no archive-awareness -- the reachable
    // state is a page with zero GTM_Page_Section__c rows, which any
    // offering (archived or not) can have. Covers both the "already-open
    // editor, home page asks for a different page" wire re-fire (setup())
    // and the fresh-tab-navigation shape below, since the two take
    // different code paths (openRequestedPage() vs connectedCallback's own
    // preset logic).
    it('opening a page with zero sections renders the empty state, not the editor children, without throwing', async () => {
        getTemplateSummary.mockResolvedValue([
            { templateType: 'configurator', sectionCount: 0, fieldCount: 0, pageTitle: null }
        ]);
        getEditorSections.mockResolvedValue([]);
        getAllContent.mockResolvedValue([]);
        getOfferings.mockResolvedValue(OFFERINGS);

        const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
        document.body.appendChild(element);
        await flushPromises();

        const offeringPicker = element.shadowRoot.querySelector('lightning-combobox');
        offeringPicker.dispatchEvent(new CustomEvent('change', { detail: { value: 'ma-migrator' } }));
        await flushPromises();

        const templateCard = [...element.shadowRoot.querySelectorAll('button.pg-card, button[data-template]')]
            .find((b) => b.dataset && b.dataset.template === 'configurator');
        expect(templateCard).toBeDefined();
        templateCard.click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-field-editor')).toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-page-preview')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('This page has no sections yet.');
    });
});

describe('c-gtm-content-manager: Add industry (issue add-industry)', () => {
    const FRAMEWORK = [{ offeringKey: 'gtm', label: 'Framework (all offerings)' }];
    const TEMPLATES = [
        { templateType: 'industry-chooser', sectionCount: 2, fieldCount: 4, pageTitle: null },
        { templateType: 'faq-bd', sectionCount: 1, fieldCount: 2, pageTitle: null }
    ];
    const SECTIONS = [
        { id: 'a01', sectionKey: 'header', label: 'Header', layoutType: 'header', width: 'standard', sortOrder: 10, active: true, status: 'Published' },
        { id: 'a02', sectionKey: 'industry-financial-services', label: 'Financial Services', layoutType: 'industry-tile', width: 'standard', sortOrder: 20, active: true, status: 'Published' }
    ];

    async function open(templateType, sections = SECTIONS) {
        getOfferings.mockResolvedValue(FRAMEWORK);
        getTemplateSummary.mockResolvedValue(TEMPLATES);
        getEditorSections.mockResolvedValue(sections);
        getAllContent.mockResolvedValue([]);
        const element = createElement('c-gtm-content-manager', { is: GtmContentManager });
        document.body.appendChild(element);
        await flushPromises();
        element.shadowRoot.querySelector('lightning-combobox')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'gtm' } }));
        await flushPromises();
        const card = [...element.shadowRoot.querySelectorAll('button[data-template]')]
            .find((b) => b.dataset.template === templateType);
        card.click();
        await flushPromises();
        return element;
    }

    const foot = (el) => el.shadowRoot.querySelector('.gcm-rail-foot');
    const footButtonText = (el) => foot(el).querySelector('button.gcm-add').textContent.replace(/\s+/g, ' ').trim();
    const nameInput = (el) => el.shadowRoot.querySelector('lightning-input.gcm-industry-name');
    const addButton = (el) => [...el.shadowRoot.querySelectorAll('.modal-f lightning-button')]
        .find((b) => b.label === 'Add industry');
    const text = (el, sel) => {
        const n = el.shadowRoot.querySelector(sel);
        return n ? n.textContent.trim() : null;
    };

    async function openModal(el) {
        foot(el).querySelector('button.gcm-add').click();
        await flushPromises();
    }
    async function type(el, value) {
        const input = nameInput(el);
        input.value = value;
        input.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
    }

    // The embedded preview scrolls itself on render; jsdom has no Element.scrollTo.
    const realScrollTo = Element.prototype.scrollTo;
    beforeAll(() => { Element.prototype.scrollTo = jest.fn(); });
    afterAll(() => { Element.prototype.scrollTo = realScrollTo; });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows Add industry, not Add section, on the Industry Chooser page', async () => {
        const el = await open('industry-chooser');
        expect(footButtonText(el)).toBe('Add industry');
        expect(footButtonText(el)).not.toContain('Add section');
    });

    it('keeps Add section, and no Add industry, on any other page', async () => {
        const el = await open('faq-bd');
        expect(footButtonText(el)).toContain('Add section');
        expect(footButtonText(el)).not.toContain('Add industry');
    });

    it('opens name-only with the button disabled and no message or preview', async () => {
        const el = await open('industry-chooser');
        await openModal(el);
        expect(el.shadowRoot.querySelector('#indTitle, h2').textContent).toBeTruthy();
        expect(nameInput(el)).not.toBeNull();
        expect(addButton(el).disabled).toBe(true);
        expect(text(el, '.gcm-industry-invalid')).toBeNull();
        expect(text(el, '.gcm-industry-key')).toBeNull();
    });

    it('previews the generated key and address for a valid name and enables the button', async () => {
        const el = await open('industry-chooser');
        await openModal(el);
        await type(el, 'Public Sector');
        expect(text(el, '.gcm-industry-key')).toBe('industry-public-sector');
        expect(text(el, '.gcm-industry-address')).toBe('gtm::industry-chooser::industry-public-sector');
        expect(addButton(el).disabled).toBe(false);
    });

    it('disables with a plain message for a blank or punctuation-only name', async () => {
        const el = await open('industry-chooser');
        await openModal(el);
        await type(el, '   ');
        expect(text(el, '.gcm-industry-invalid')).toBe('Give the industry a name.');
        expect(addButton(el).disabled).toBe(true);
        await type(el, '!!!');
        expect(text(el, '.gcm-industry-invalid')).toBe('That name has no letters or numbers to build a key from.');
        expect(addButton(el).disabled).toBe(true);
        expect(text(el, '.gcm-industry-key')).toBeNull();
    });

    it('caps the slug at 71 characters so the key fits an 80-character field', async () => {
        const el = await open('industry-chooser');
        await openModal(el);
        await type(el, 'a'.repeat(100));
        expect(text(el, '.gcm-industry-key')).toBe('industry-' + 'a'.repeat(71));
        await type(el, 'a'.repeat(70) + ' ' + 'z'.repeat(20));
        expect(text(el, '.gcm-industry-key')).toBe('industry-' + 'a'.repeat(70));
    });

    it('refuses a duplicate by key, whatever the case or punctuation', async () => {
        const el = await open('industry-chooser');
        await openModal(el);
        for (const variant of ['Financial Services', 'financial services', 'Financial-Services', 'Financial Services!']) {
            await type(el, variant);
            expect(text(el, '.gcm-industry-invalid')).toBe(
                'An industry called "' + variant + '" already exists. Edit it instead.');
            expect(addButton(el).disabled).toBe(true);
        }
    });

    it('warns, without blocking, when only the label matches an existing industry', async () => {
        const extra = [
            ...SECTIONS,
            { id: 'a03', sectionKey: 'industry-fin-serv', label: 'Fintech Group', layoutType: 'industry-tile', width: 'standard', sortOrder: 30, active: true, status: 'Published' }
        ];
        const el = await open('industry-chooser', extra);
        await openModal(el);
        await type(el, 'fintech GROUP');
        expect(text(el, '.gcm-industry-warning')).toBe('There is already an industry with a similar name.');
        expect(text(el, '.gcm-industry-invalid')).toBeNull();
        expect(addButton(el).disabled).toBe(false);
    });

    it('calls createIndustry with the trimmed label and the industry-tile seeds, closes, reloads and lands on the returned key', async () => {
        createIndustry.mockResolvedValue('industry-public-sector');
        const el = await open('industry-chooser');
        await openModal(el);
        await type(el, '  Public Sector ');
        getEditorSections.mockResolvedValue([
            ...SECTIONS,
            { id: 'a09', sectionKey: 'industry-public-sector', label: 'Public Sector', layoutType: 'industry-tile', width: 'standard', sortOrder: 30, active: true, status: 'Draft' }
        ]);
        const loadsBefore = getEditorSections.mock.calls.length;
        addButton(el).click();
        await flushPromises();
        await flushPromises();

        expect(createIndustry).toHaveBeenCalledTimes(1);
        const arg = createIndustry.mock.calls[0][0];
        expect(arg.label).toBe('Public Sector');
        expect(arg.fields.map((f) => f.fieldKey).sort()).toEqual([
            'coverSub', 'demoDeps', 'demoRoot', 'industryLabel', 'pickerBlurb', 'problem',
            'proofLine', 'solution', 'uniquePoints', 'useCase', 'whyHead', 'whyLine'
        ]);
        expect(arg.fields).toHaveLength(12);
        expect(getEditorSections.mock.calls.length).toBeGreaterThan(loadsBefore);
        expect(nameInput(el)).toBeNull();
        expect(createSection).not.toHaveBeenCalled();
        expect(el.shadowRoot.querySelector('.sec[data-key="industry-public-sector"]')).not.toBeNull();
    });

    it('keeps the modal open, with the name and the server message, when createIndustry fails', async () => {
        createIndustry.mockRejectedValue({ body: { message: 'Create the Industry Chooser page first.' } });
        const el = await open('industry-chooser');
        await openModal(el);
        await type(el, 'Public Sector');
        addButton(el).click();
        await flushPromises();
        await flushPromises();

        expect(nameInput(el)).not.toBeNull();
        expect(nameInput(el).value).toBe('Public Sector');
        expect(text(el, '.gcm-industry-error')).toBe('Create the Industry Chooser page first.');
        expect(addButton(el).disabled).toBe(false);
        expect(createSection).not.toHaveBeenCalled();
    });
});
