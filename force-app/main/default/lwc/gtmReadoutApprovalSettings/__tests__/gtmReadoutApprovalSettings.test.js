import { createElement } from 'lwc';
import getSelfApprovalEnabled from '@salesforce/apex/GtmReadoutApprovalSettingsController.getSelfApprovalEnabled';
import setSelfApprovalEnabled from '@salesforce/apex/GtmReadoutApprovalSettingsController.setSelfApprovalEnabled';
import GtmReadoutApprovalSettings from 'c/gtmReadoutApprovalSettings';

jest.mock(
    '@salesforce/apex/GtmReadoutApprovalSettingsController.getSelfApprovalEnabled',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutApprovalSettingsController.setSelfApprovalEnabled',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-gtm-readout-approval-settings', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads the current setting and reflects it on the toggle', async () => {
        getSelfApprovalEnabled.mockResolvedValue(false);
        const element = createElement('c-gtm-readout-approval-settings', {
            is: GtmReadoutApprovalSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const toggle = element.shadowRoot.querySelector('lightning-input');
        expect(toggle.checked).toBe(false);
        expect(getSelfApprovalEnabled).toHaveBeenCalledTimes(1);
    });

    it('saves the toggle change through setSelfApprovalEnabled', async () => {
        getSelfApprovalEnabled.mockResolvedValue(false);
        setSelfApprovalEnabled.mockResolvedValue();
        const element = createElement('c-gtm-readout-approval-settings', {
            is: GtmReadoutApprovalSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const toggle = element.shadowRoot.querySelector('lightning-input');
        toggle.checked = true;
        toggle.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(setSelfApprovalEnabled).toHaveBeenCalledWith({ enabled: true });
    });

    it('renders the shared page header with eyebrow and title', async () => {
        getSelfApprovalEnabled.mockResolvedValue(false);
        const element = createElement('c-gtm-readout-approval-settings', {
            is: GtmReadoutApprovalSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header).not.toBeNull();
        expect(header.eyebrow).toBe('Settings');
        expect(header.title).toBe('Readout Approval Settings');
    });

    it('wraps the toggle content in a white slds-card container', async () => {
        getSelfApprovalEnabled.mockResolvedValue(false);
        const element = createElement('c-gtm-readout-approval-settings', {
            is: GtmReadoutApprovalSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const card = element.shadowRoot.querySelector('.slds-card');
        expect(card).not.toBeNull();
        expect(card.querySelector('lightning-input')).not.toBeNull();
    });

    it('shows a load error if the setting cannot be read', async () => {
        getSelfApprovalEnabled.mockRejectedValue(new Error('boom'));
        const element = createElement('c-gtm-readout-approval-settings', {
            is: GtmReadoutApprovalSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const error = element.shadowRoot.querySelector('.slds-text-color_error');
        expect(error).not.toBeNull();
    });
});
