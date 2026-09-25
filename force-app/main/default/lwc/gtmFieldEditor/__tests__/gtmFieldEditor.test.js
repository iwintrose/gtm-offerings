/**
 * Issue #industry-variants-core — c/gtmFieldEditor threads @api industryKey
 * through to createField, and shows a variant banner when it is set.
 */
import { createElement } from 'lwc';
import GtmFieldEditor from 'c/gtmFieldEditor';
import createField from '@salesforce/apex/GtmPageSectionController.createField';

jest.mock(
    '@salesforce/apex/GtmPageSectionController.createField',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageSectionController.deleteField',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageSectionController.restoreField',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageSectionController.saveFieldOrder',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function makeElement(props) {
    const element = createElement('c-gtm-field-editor', { is: GtmFieldEditor });
    Object.assign(element, {
        records: [],
        activeKey: 'problem--healthcare',
        sectionLabel: 'Problem',
        sectionHelp: '',
        sectionAddress: 'ma-migrator::story::problem--healthcare',
        layoutType: 'hero',
        offeringKey: 'ma-migrator',
        templateType: 'story',
        busy: false,
        ...props
    });
    document.body.appendChild(element);
    return element;
}

describe('c-gtm-field-editor: industryKey plumbing (issue #industry-variants-core)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('passes industryKey through to createField when set', async () => {
        createField.mockResolvedValue('a04field');
        const element = makeElement({ industryKey: 'healthcare' });
        await flushPromises();

        element.shadowRoot.querySelector('.gcm-add--field').dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        const labelInput = element.shadowRoot.querySelector('.modal-b lightning-input');
        labelInput.value = 'Extra note';
        labelInput.dispatchEvent(new CustomEvent('change'));

        const addBtn = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Add field');
        addBtn.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(createField).toHaveBeenCalledWith(
            expect.objectContaining({
                sectionKey: 'problem--healthcare',
                industryKey: 'healthcare'
            })
        );
    });

    it('sends industryKey: null when the section is not a variant', async () => {
        createField.mockResolvedValue('a05field');
        const element = makeElement({ industryKey: '', activeKey: 'problem' });
        await flushPromises();

        element.shadowRoot.querySelector('.gcm-add--field').dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        const labelInput = element.shadowRoot.querySelector('.modal-b lightning-input');
        labelInput.value = 'Extra note';
        labelInput.dispatchEvent(new CustomEvent('change'));

        const addBtn = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Add field');
        addBtn.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(createField).toHaveBeenCalledWith(
            expect.objectContaining({ sectionKey: 'problem', industryKey: null })
        );
    });

    it('shows the "Editing: <Section> — <Industry> variant" banner only when industryKey is set', async () => {
        const withIndustry = makeElement({ industryKey: 'healthcare' });
        await flushPromises();
        expect(withIndustry.shadowRoot.querySelector('.gcm-variant-banner').textContent)
            .toBe('Editing: Problem — healthcare variant');

        document.body.removeChild(withIndustry);

        const withoutIndustry = makeElement({ industryKey: '' });
        await flushPromises();
        expect(withoutIndustry.shadowRoot.querySelector('.gcm-variant-banner')).toBeNull();
    });
});
