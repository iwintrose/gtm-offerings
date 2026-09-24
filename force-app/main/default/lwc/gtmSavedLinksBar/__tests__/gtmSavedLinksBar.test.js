import { createElement } from 'lwc';
import GtmSavedLinksBar from 'c/gtmSavedLinksBar';
import getMyConfigurations from '@salesforce/apex/GtmSavedConfigurationController.getMyConfigurations';
import getConfiguratorPageUrl from '@salesforce/apex/GtmSavedConfigurationController.getConfiguratorPageUrl';
import getOrgBaseUrl from '@salesforce/apex/GtmSavedConfigurationController.getOrgBaseUrl';
import deleteConfiguration from '@salesforce/apex/GtmSavedConfigurationController.deleteConfiguration';
import setActive from '@salesforce/apex/GtmSavedConfigurationController.setActive';
import resendEngagementLink from '@salesforce/apex/GtmSavedConfigurationController.resendEngagementLink';
import getIndustryProfiles from '@salesforce/apex/GtmPageContentReader.getIndustryProfiles';

jest.mock('@salesforce/apex/GtmSavedConfigurationController.getMyConfigurations',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSavedConfigurationController.getConfiguratorPageUrl',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSavedConfigurationController.getOrgBaseUrl',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSavedConfigurationController.deleteConfiguration',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSavedConfigurationController.setActive',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSavedConfigurationController.resendEngagementLink',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmPageContentReader.getIndustryProfiles',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/user/isGuest', () => ({ default: false }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const RECORD_WITH_EMAIL = {
    Id: 'a001000000000001',
    Name: 'GTM-0001',
    Offering__c: 'migration-accelerator',
    Industry__c: 'fintech',
    Company__c: 'Acme Bank',
    Generated_URL__c: 'https://example.my.site.com/gtmaccelerator/s/configurator?cfgId=a001',
    Active__c: true,
    CreatedDate: '2025-01-01T00:00:00.000Z',
    Contact__c: 'c001000000000001',
    Contact__r: { Name: 'Jordan Lee', Email: 'jordan.lee@acmebank.example.com' },
    Account__c: null,
    Account__r: null,
    Opportunity__c: null,
    Opportunity__r: null,
    Owner: { Name: 'Test User' }
};

const RECORD_WITHOUT_EMAIL = {
    Id: 'a001000000000002',
    Name: 'GTM-0002',
    Offering__c: 'migration-accelerator',
    Industry__c: 'fintech',
    Company__c: 'Beta Corp',
    Generated_URL__c: 'https://example.my.site.com/gtmaccelerator/s/configurator?cfgId=a002',
    Active__c: true,
    CreatedDate: '2025-01-02T00:00:00.000Z',
    Contact__c: null,
    Contact__r: null,
    Account__c: null,
    Account__r: null,
    Opportunity__c: null,
    Opportunity__r: null,
    Owner: { Name: 'Test User' }
};

async function mount() {
    const el = createElement('c-gtm-saved-links-bar', { is: GtmSavedLinksBar });
    document.body.appendChild(el);
    await flushPromises();
    return el;
}

describe('c-gtm-saved-links-bar resend link', () => {
    beforeEach(() => {
        getOrgBaseUrl.mockResolvedValue('https://test.my.salesforce.com');
        getConfiguratorPageUrl.mockResolvedValue('https://example.my.site.com/gtmaccelerator/s/configurator');
        getIndustryProfiles.mockResolvedValue([]);
        deleteConfiguration.mockResolvedValue(undefined);
        setActive.mockResolvedValue(undefined);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows resend button only when contactEmail is present', async () => {
        getMyConfigurations.mockResolvedValue([RECORD_WITH_EMAIL, RECORD_WITHOUT_EMAIL]);
        const el = await mount();
        // Open the panel
        el.shadowRoot.querySelector('.sl-toggle').click();
        await flushPromises();

        const resendBtns = el.shadowRoot.querySelectorAll('.sl-resend');
        // Only the row with a contact email should show the button
        expect(resendBtns.length).toBe(1);
    });

    it('calls resendEngagementLink with the correct recordId on click', async () => {
        resendEngagementLink.mockResolvedValue(undefined);
        getMyConfigurations.mockResolvedValue([RECORD_WITH_EMAIL]);
        const el = await mount();
        el.shadowRoot.querySelector('.sl-toggle').click();
        await flushPromises();

        const resendBtn = el.shadowRoot.querySelector('.sl-resend');
        expect(resendBtn).not.toBeNull();
        resendBtn.click();
        await flushPromises();

        expect(resendEngagementLink).toHaveBeenCalledWith({ recordId: RECORD_WITH_EMAIL.Id });
    });

    it('dispatches showtoast event on successful resend', async () => {
        resendEngagementLink.mockResolvedValue(undefined);
        getMyConfigurations.mockResolvedValue([RECORD_WITH_EMAIL]);
        const el = await mount();
        el.shadowRoot.querySelector('.sl-toggle').click();
        await flushPromises();

        const toastHandler = jest.fn();
        el.addEventListener('showtoast', toastHandler);

        el.shadowRoot.querySelector('.sl-resend').click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalledTimes(1);
        const detail = toastHandler.mock.calls[0][0].detail;
        expect(detail.variant).toBe('success');
    });

    it('sets actionError on resend failure', async () => {
        resendEngagementLink.mockRejectedValue({
            body: { message: 'No contact email address is set on this link.' }
        });
        getMyConfigurations.mockResolvedValue([RECORD_WITH_EMAIL]);
        const el = await mount();
        el.shadowRoot.querySelector('.sl-toggle').click();
        await flushPromises();

        el.shadowRoot.querySelector('.sl-resend').click();
        await flushPromises();

        const errorEl = el.shadowRoot.querySelector('.sl-error');
        expect(errorEl).not.toBeNull();
        expect(errorEl.textContent).toContain('No contact email address is set on this link.');
    });
});
