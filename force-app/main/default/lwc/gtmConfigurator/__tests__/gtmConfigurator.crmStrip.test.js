import { createElement } from 'lwc';
import GtmConfigurator from 'c/gtmConfigurator';
import getConfigurationCrmData from '@salesforce/apex/GtmSavedConfigurationController.getConfigurationCrmData';
import getConfiguration from '@salesforce/apex/GtmSavedConfigurationController.getConfiguration';

jest.mock(
    '@salesforce/apex/GtmViewerContext.isRep',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmSavedConfigurationController.getConfigurationCrmData',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
// B12: isRep.emit(true) below makes this a config-manager view, which reads
// the saved record through getConfiguration (not getPublicConfiguration).
// Left unmocked, this resolves to undefined, so the record's `offering`
// field never reaches linkOfferingKey and effectiveOfferingKey stays empty
// -- now correctly treated as isUnconfigured, which hides the whole chapter
// body (including this test's target, the CRM strip). Mocking it to resolve
// with an offering, as a real saved link would, keeps this test scoped to
// the Contact-record-link behavior it actually covers.
jest.mock(
    '@salesforce/apex/GtmSavedConfigurationController.getConfiguration',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// eslint-disable-next-line import/no-unresolved
const isRep = require('@salesforce/apex/GtmViewerContext.isRep').default;

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

// landing-view-enrich: Contact in the CRM strip now renders as a clickable
// record link (matching the existing Account/Opportunity chip treatment),
// alongside the mailto link it already had.
describe('c-gtm-configurator CRM strip — Contact record link', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        jest.clearAllMocks();
    });

    it('renders a Contact record link using the same /lightning/r/.../view shape as Account/Opportunity', async () => {
        window.history.pushState({}, '', '/s/configurator?cfgId=a0X000000000099AAA');
        getConfiguration.mockResolvedValue({ offering: 'second-offering' });
        getConfigurationCrmData.mockResolvedValue({
            contactId: '003000000000001AAA',
            contactName: 'Jane Prospect',
            contactEmail: 'jane@example.com',
            accountId: '001000000000001AAA',
            accountName: 'Acme Co',
            opportunityId: '006000000000001AAA',
            opportunityName: 'Acme Deal',
            estimatedValue: '50000'
        });

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(true);
        await flushPromises();
        await flushPromises();
        await flushPromises();

        const contactLink = element.shadowRoot.querySelector('.crm-contact-link');
        expect(contactLink).not.toBeNull();
        expect(contactLink.getAttribute('href')).toContain('/lightning/r/Contact/003000000000001AAA/view');
        expect(contactLink.textContent).toContain('Jane Prospect');

        // The existing mailto affordance must still be present alongside it.
        const emailLink = element.shadowRoot.querySelector('.crm-contact-email');
        expect(emailLink).not.toBeNull();
        expect(emailLink.getAttribute('href')).toBe('mailto:jane@example.com');

        // Account/Opportunity links are unaffected by this change.
        const accountLink = element.shadowRoot.querySelector('.crm-chip--account');
        expect(accountLink.getAttribute('href')).toContain('/lightning/r/Account/001000000000001AAA/view');
        const oppLink = element.shadowRoot.querySelector('.crm-chip--opp');
        expect(oppLink.getAttribute('href')).toContain('/lightning/r/Opportunity/006000000000001AAA/view');
    });

    it('does not render a Contact chip at all when the saved config has no linked Contact', async () => {
        window.history.pushState({}, '', '/s/configurator?cfgId=a0X000000000098AAA');
        getConfigurationCrmData.mockResolvedValue({
            contactId: null,
            accountId: '001000000000001AAA',
            accountName: 'Acme Co'
        });

        const element = createElement('c-gtm-configurator', { is: GtmConfigurator });
        document.body.appendChild(element);
        isRep.emit(true);
        await flushPromises();
        await flushPromises();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.crm-contact-link')).toBeNull();
    });
});
