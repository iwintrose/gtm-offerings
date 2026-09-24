import { createElement } from 'lwc';
import getSettings from '@salesforce/apex/GtmAnalyticsSettingsController.getSettings';
import saveSettings from '@salesforce/apex/GtmAnalyticsSettingsController.saveSettings';
import GtmAnalyticsNotificationSettings from 'c/gtmAnalyticsNotificationSettings';

jest.mock(
    '@salesforce/apex/GtmAnalyticsSettingsController.getSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAnalyticsSettingsController.saveSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const OFF_SETTINGS = {
    digestEnabled: false,
    digestDayOfWeek: 'MON',
    digestHour: 8,
    nextRunDescription: 'Analytics email is off.'
};

describe('c-gtm-analytics-notification-settings', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads and displays the current digest settings', async () => {
        getSettings.mockResolvedValue(OFF_SETTINGS);

        const element = createElement('c-gtm-analytics-notification-settings', { is: GtmAnalyticsNotificationSettings });
        document.body.appendChild(element);
        await flushPromises();

        const toggle = element.shadowRoot.querySelector('lightning-input');
        expect(toggle.checked).toBe(false);
        expect(element.shadowRoot.textContent).toContain('Analytics email is off.');
        // Day/time pickers only show once enabled.
        expect(element.shadowRoot.querySelector('lightning-combobox')).toBeNull();
    });

    it('shows day/time pickers once the toggle is turned on, and saves them', async () => {
        getSettings.mockResolvedValue(OFF_SETTINGS);
        saveSettings.mockResolvedValue({
            digestEnabled: true,
            digestDayOfWeek: 'FRI',
            digestHour: 17,
            nextRunDescription: 'Weekly on Friday at 5:00 PM (org time zone).'
        });

        const element = createElement('c-gtm-analytics-notification-settings', { is: GtmAnalyticsNotificationSettings });
        document.body.appendChild(element);
        await flushPromises();

        const toggle = element.shadowRoot.querySelector('lightning-input');
        toggle.checked = true;
        toggle.dispatchEvent(new CustomEvent('change', { target: { checked: true } }));
        await flushPromises();

        expect(element.shadowRoot.querySelectorAll('lightning-combobox').length).toBe(2);

        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(saveSettings).toHaveBeenCalledWith({ enabled: true, dayOfWeek: 'MON', hour: 8 });
        expect(element.shadowRoot.textContent).toContain('Weekly on Friday at 5:00 PM');
    });

    it('surfaces an Apex error on load instead of failing silently', async () => {
        getSettings.mockRejectedValue({ body: { message: 'boom' } });

        const element = createElement('c-gtm-analytics-notification-settings', { is: GtmAnalyticsNotificationSettings });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.slds-text-color_error').textContent).toBe('boom');
    });

    it('surfaces an Apex error on save instead of failing silently', async () => {
        getSettings.mockResolvedValue(OFF_SETTINGS);
        saveSettings.mockRejectedValue({ body: { message: 'nope' } });

        const element = createElement('c-gtm-analytics-notification-settings', { is: GtmAnalyticsNotificationSettings });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.slds-text-color_error').textContent).toBe('nope');
    });
});
