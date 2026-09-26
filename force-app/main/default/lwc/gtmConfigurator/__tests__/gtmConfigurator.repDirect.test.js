import { createElement } from 'lwc';
import GtmConfigurator from 'c/gtmConfigurator';
import getPublicConfiguration from '@salesforce/apex/GtmConfigurationReader.getPublicConfiguration';
import checkPasswordRequired from '@salesforce/apex/GtmLinkAuthController.checkPasswordRequired';
import isActive from '@salesforce/apex/GtmConfigurationStatusController.isActive';

jest.mock(
    '@salesforce/apex/GtmViewerContext.isRep',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmConfigurationReader.getPublicConfiguration',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmLinkAuthController.checkPasswordRequired',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmConfigurationStatusController.isActive',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// eslint-disable-next-line import/no-unresolved
const isRep = require('@salesforce/apex/GtmViewerContext.isRep').default;

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

/**
 * The Rep_Direct branch (issue
 * rep-initiated-assessment-no-page-2-share-and-continue): a pageless,
 * rep-initiated assessment record has no Config_Payload__c, so
 * gtmConfigurator skips every branded chapter and renders the
 * questionnaire component directly, gated by the same access checks the
 * branded path uses.
 */
describe('c-gtm-configurator Rep_Direct branch (issue rep-initiated-assessment-no-page-2-share-and-continue)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        jest.clearAllMocks();
    });

    it('skips the branded chapters and renders the questionnaire directly for a guest on a Rep_Direct link', async () => {
        window.history.pushState({}, '', '/s/configurator?cfgId=a0X000000000050AAA');
        getPublicConfiguration.mockResolvedValue({
            isActive: true,
            offering: 'migration-accelerator',
            presentationStage: 'Rep_Direct'
        });
        isActive.mockResolvedValue(true);

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();
        await flushPromises();
        await flushPromises();

        // No branded chapter content anywhere -- a Rep_Direct record was
        // never given any.
        expect(element.shadowRoot.querySelector('.chap.cover')).toBeNull();
        // Not the branded top bar either.
        expect(element.shadowRoot.querySelector('.psbar')).toBeNull();
        // Not the overlay-on-top-of-a-page modal chrome (.bk) -- the
        // questionnaire is the whole page here, not something opened on top
        // of one.
        expect(element.shadowRoot.querySelector('.bk')).toBeNull();

        const questionnaire = element.shadowRoot.querySelector('c-gtm-assessment-questionnaire');
        expect(questionnaire).not.toBeNull();
        expect(questionnaire.savedRecordId).toBe('a0X000000000050AAA');
        expect(questionnaire.offeringKey).toBe('migration-accelerator');
    });

    it('honors a ?resume= token on the Rep_Direct branch', async () => {
        window.history.pushState(
            {},
            '',
            '/s/configurator?cfgId=a0X000000000051AAA&resume=repPrefilledToken123'
        );
        getPublicConfiguration.mockResolvedValue({
            isActive: true,
            offering: 'migration-accelerator',
            presentationStage: 'Rep_Direct'
        });
        isActive.mockResolvedValue(true);

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();
        await flushPromises();
        await flushPromises();

        const questionnaire = element.shadowRoot.querySelector('c-gtm-assessment-questionnaire');
        expect(questionnaire).not.toBeNull();
        expect(questionnaire.resumeToken).toBe('repPrefilledToken123');
    });

    it('renders the ordinary branded chapters for a ordinary (non-Rep_Direct) link', async () => {
        window.history.pushState({}, '', '/s/configurator?cfgId=a0X000000000052AAA&company=Acme');
        getPublicConfiguration.mockResolvedValue({
            isActive: true,
            offering: 'migration-accelerator',
            company: 'Acme',
            configPayload: '{}'
        });

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();
        await flushPromises();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.chap.cover')).not.toBeNull();
        // The questionnaire is NOT mounted until the guest opens the overlay.
        expect(element.shadowRoot.querySelector('c-gtm-assessment-questionnaire')).toBeNull();
    });

    it('renders the ordinary branded chapters for a link whose stage has advanced to Assessment (post-submission, non-Rep_Direct)', async () => {
        // Companion to issue-rep-direct-presentation-stage-flip:
        // postInsertBestEffort() legitimately advances a normal (Sent) link
        // to 'Assessment' after a real submission -- this asserts the client
        // renders that server value exactly like any other non-Rep_Direct
        // stage, i.e. isRepDirect stays strictly false and chapters render.
        window.history.pushState({}, '', '/s/configurator?cfgId=a0X000000000054AAA&company=Acme');
        getPublicConfiguration.mockResolvedValue({
            isActive: true,
            offering: 'migration-accelerator',
            company: 'Acme',
            configPayload: '{}',
            presentationStage: 'Assessment'
        });

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();
        await flushPromises();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.chap.cover')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-assessment-questionnaire')).toBeNull();
    });

    it('still applies the password gate on a Rep_Direct link -- the branch changes CONTENT, not protection', async () => {
        window.history.pushState({}, '', '/s/configurator?cfgId=a0X000000000053AAA');
        getPublicConfiguration.mockResolvedValue({
            isActive: true,
            offering: 'migration-accelerator',
            presentationStage: 'Rep_Direct'
        });
        isActive.mockResolvedValue(true);
        checkPasswordRequired.mockResolvedValue(true);

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(false);
        await flushPromises();
        await flushPromises();
        await flushPromises();

        // The password gate renders instead of the questionnaire -- a
        // Rep_Direct record is exactly as protected as a branded one, only
        // the content BEHIND the gate differs.
        expect(element.shadowRoot.querySelector('.pw-gate')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-assessment-questionnaire')).toBeNull();
    });
});
