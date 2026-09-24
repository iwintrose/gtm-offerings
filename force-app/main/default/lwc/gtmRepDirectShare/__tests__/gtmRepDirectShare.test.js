import { createElement } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { registerLdsTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import GtmRepDirectShare from 'c/gtmRepDirectShare';
import generateRepDirectShareLink from '@salesforce/apex/GtmSavedConfigurationController.generateRepDirectShareLink';

jest.mock(
    '@salesforce/apex/GtmSavedConfigurationController.generateRepDirectShareLink',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const getRecordWireAdapter = registerLdsTestWireAdapter(getRecord);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function emitRecord(overrides = {}) {
    getRecordWireAdapter.emit({
        fields: {
            Presentation_Stage__c: { value: 'Rep_Direct' },
            Offering__c: { value: 'migration-accelerator' },
            Generated_URL__c: { value: null },
            ...overrides
        }
    });
}

describe('c-gtm-rep-direct-share', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders nothing for a non-Rep_Direct record', async () => {
        const element = createElement('c-gtm-rep-direct-share', { is: GtmRepDirectShare });
        element.recordId = 'a0X000000000060AAA';
        document.body.appendChild(element);
        emitRecord({ Presentation_Stage__c: { value: 'Sent' } });
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
    });

    it('shows a "Share with prospect" action for a Rep_Direct record', async () => {
        const element = createElement('c-gtm-rep-direct-share', { is: GtmRepDirectShare });
        element.recordId = 'a0X000000000061AAA';
        document.body.appendChild(element);
        emitRecord();
        await flushPromises();

        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card).not.toBeNull();
        const button = element.shadowRoot.querySelector('[data-id="share-button"]');
        expect(button).not.toBeNull();
    });

    it('calls generateRepDirectShareLink and displays the resulting URL and password', async () => {
        generateRepDirectShareLink.mockResolvedValue({
            generatedUrl: 'https://example.my.site.com/gtm/s/configurator?cfgId=a0X000000000062AAA',
            password: 'ABC234'
        });

        const element = createElement('c-gtm-rep-direct-share', { is: GtmRepDirectShare });
        element.recordId = 'a0X000000000062AAA';
        document.body.appendChild(element);
        emitRecord();
        await flushPromises();

        const button = element.shadowRoot.querySelector('[data-id="share-button"]');
        button.click();
        await flushPromises();

        expect(generateRepDirectShareLink).toHaveBeenCalledWith({
            recordId: 'a0X000000000062AAA',
            resumeToken: ''
        });
        expect(element.shadowRoot.textContent).toContain('ABC234');
        const urlEl = element.shadowRoot.querySelector('lightning-formatted-url');
        expect(urlEl.value).toBe(
            'https://example.my.site.com/gtm/s/configurator?cfgId=a0X000000000062AAA'
        );
    });

    it('carries the resume token from a rep pre-fill draft into the share link call', async () => {
        generateRepDirectShareLink.mockResolvedValue({
            generatedUrl: 'https://example.my.site.com/gtm/s/configurator?cfgId=a0X000000000063AAA&resume=repToken1',
            password: 'ZZZ999'
        });

        const element = createElement('c-gtm-rep-direct-share', { is: GtmRepDirectShare });
        element.recordId = 'a0X000000000063AAA';
        document.body.appendChild(element);
        emitRecord();
        await flushPromises();

        // Reveal the inline pre-fill questionnaire and simulate its
        // draftsaved event, exactly as gtmAssessmentQuestionnaire's own
        // pushDraft() dispatches it.
        const prefillButton = element.shadowRoot.querySelector('[data-id="prefill-button"]');
        prefillButton.click();
        await flushPromises();

        const questionnaire = element.shadowRoot.querySelector('c-gtm-assessment-questionnaire');
        expect(questionnaire).not.toBeNull();
        questionnaire.dispatchEvent(
            new CustomEvent('draftsaved', {
                detail: { resumeToken: 'repToken1', expiresAt: '2026-01-01T00:00:00Z' }
            })
        );

        const shareButton = element.shadowRoot.querySelector('[data-id="share-button"]');
        shareButton.click();
        await flushPromises();

        expect(generateRepDirectShareLink).toHaveBeenCalledWith({
            recordId: 'a0X000000000063AAA',
            resumeToken: 'repToken1'
        });
    });
});
