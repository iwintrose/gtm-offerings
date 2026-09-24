import { createElement } from 'lwc';

// The default `lightning/modal` stub's `close()` is a real (no-op-observing)
// method, and LWC locks a registered component's prototype methods against
// jest.spyOn/reassignment once instantiated -- so this suite mocks the base
// class's `close` directly, for this file only, to assert the click handler
// actually calls it.
const mockCloseSpy = jest.fn();
jest.mock('lightning/modal', () => {
    // eslint-disable-next-line global-require
    const { LightningElement } = jest.requireActual('lwc');
    return {
        __esModule: true,
        default: class LightningModal extends LightningElement {
            close(...args) {
                mockCloseSpy(...args);
            }
        }
    };
});

// eslint-disable-next-line import/first
import GtmAssessmentPreviewModal from 'c/gtmAssessmentPreviewModal';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-gtm-assessment-preview-modal', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders c-gtm-assessment-answers-preview with the assessment request id it was opened with', async () => {
        const element = createElement('c-gtm-assessment-preview-modal', { is: GtmAssessmentPreviewModal });
        element.assessmentRequestId = 'a0X000000000001';
        element.offeringKey = 'migration-accelerator';
        element.cfgId = 'a0Z000000000001';
        document.body.appendChild(element);
        await flushPromises();

        const preview = element.shadowRoot.querySelector('c-gtm-assessment-answers-preview');
        expect(preview).not.toBeNull();
        expect(preview.recordId).toBe('a0X000000000001');
        expect(element.shadowRoot.querySelector('c-gtm-configurator')).toBeNull();
    });

    it('closes itself when the Close button is clicked', async () => {
        const element = createElement('c-gtm-assessment-preview-modal', { is: GtmAssessmentPreviewModal });
        document.body.appendChild(element);
        await flushPromises();

        const closeBtn = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Close');
        expect(closeBtn).not.toBeUndefined();
        closeBtn.click();

        expect(mockCloseSpy).toHaveBeenCalledTimes(1);
    });
});
