import { createElement } from 'lwc';
import getOrgDefaults from '@salesforce/apex/GtmNotificationSettingsController.getOrgDefaults';
import setNotificationSettings from '@salesforce/apex/GtmNotificationSettingsController.setNotificationSettings';
import GtmOfferingsSettingsNotifications from 'c/gtmOfferingsSettingsNotifications';

jest.mock(
    '@salesforce/apex/GtmNotificationSettingsController.getOrgDefaults',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmNotificationSettingsController.setNotificationSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const ALL_ON_DTO = {
    notifyOnSubmitForApproval: true,
    autoCloseSubmitTasks: true,
    notifyOnApproved: true,
    autoCloseApprovedTasks: true,
    publishedNotificationMode: 'Bell + Task',
    autoClosePublishedTasks: true,
    notifyOnNewAssessmentRequest: true,
    autoCloseNewRequestTasks: true,
    notifyOnReturnedToDraft: true
};

function checkboxes(element) {
    return Array.from(element.shadowRoot.querySelectorAll('lightning-input')).filter(
        (cb) => cb.type === 'checkbox'
    );
}

async function mountWith(dto) {
    getOrgDefaults.mockResolvedValue(dto);
    const element = createElement('c-gtm-offerings-settings-notifications', {
        is: GtmOfferingsSettingsNotifications
    });
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

describe('c-gtm-offerings-settings-notifications', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('defaults every checkbox off and mode to None when never configured', async () => {
        const element = await mountWith({});
        checkboxes(element).forEach((cb) => expect(cb.checked).toBe(false));

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox.value).toBe('None');
    });

    it('loads all nine fields from getOrgDefaults', async () => {
        const element = await mountWith(ALL_ON_DTO);
        checkboxes(element).forEach((cb) => expect(cb.checked).toBe(true));
        expect(element.shadowRoot.querySelector('lightning-combobox').value).toBe('Bell + Task');
    });

    it('only shows Auto Close Published Tasks when mode is Bell + Task', async () => {
        const element = await mountWith({ publishedNotificationMode: 'None' });
        let labels = checkboxes(element).map((cb) => cb.label);
        expect(labels).not.toContain('Auto-close the published Task on the next lifecycle event');

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.value = 'Bell + Task';
        combobox.dispatchEvent(new CustomEvent('change', { detail: { value: 'Bell + Task' } }));
        await flushPromises();

        labels = checkboxes(element).map((cb) => cb.label);
        expect(labels).toContain('Auto-close the published Task on the next lifecycle event');
    });

    it('saves all nine fields through setNotificationSettings', async () => {
        setNotificationSettings.mockResolvedValue();
        const element = await mountWith(ALL_ON_DTO);

        element.shadowRoot.querySelector('lightning-button').dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(setNotificationSettings).toHaveBeenCalledWith({ input: ALL_ON_DTO });
    });

    it('shows a load error if the setting cannot be read', async () => {
        getOrgDefaults.mockRejectedValue(new Error('boom'));
        const element = createElement('c-gtm-offerings-settings-notifications', {
            is: GtmOfferingsSettingsNotifications
        });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.slds-text-color_error')).not.toBeNull();
    });
});
