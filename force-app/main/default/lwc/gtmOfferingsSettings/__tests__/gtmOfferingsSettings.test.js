import { createElement } from 'lwc';
import GtmOfferingsSettings from 'c/gtmOfferingsSettings';

// CurrentPageReference drives c__section deep-linking (issue #184). jest.mock
// factories cannot close over out-of-scope variables, so createTestWireAdapter
// is pulled in via jest.requireActual inside the factory itself.
jest.mock(
    'lightning/navigation',
    () => ({
        ...jest.requireActual('lightning/navigation'),
        CurrentPageReference: jest.requireActual('@salesforce/sfdx-lwc-jest').createTestWireAdapter(jest.fn())
    }),
    { virtual: true }
);
// eslint-disable-next-line import/first, import/order
import { CurrentPageReference } from 'lightning/navigation';

jest.mock(
    '@salesforce/apex/GTM_RecycleBinController.getArchivedItems',
    () => ({ default: jest.fn(() => Promise.resolve([])) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutApprovalSettingsController.getSelfApprovalEnabled',
    () => ({ default: jest.fn(() => Promise.resolve(false)) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutApprovalSettingsController.setSelfApprovalEnabled',
    () => ({ default: jest.fn(() => Promise.resolve()) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAgentSettingsController.getAgentSettings',
    () => ({ default: jest.fn(() => Promise.resolve({ hasApiKey: false, model: '' })) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAgentSettingsController.setAgentSettings',
    () => ({ default: jest.fn(() => Promise.resolve()) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmScheduledJobsController.getStatuses',
    () => ({ default: jest.fn(() => Promise.resolve([])) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmScheduledJobsController.scheduleJob',
    () => ({ default: jest.fn(() => Promise.resolve({})) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmNotificationSettingsController.getOrgDefaults',
    () => ({ default: jest.fn(() => Promise.resolve({})) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmNotificationSettingsController.setNotificationSettings',
    () => ({ default: jest.fn(() => Promise.resolve()) }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-gtm-offerings-settings', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders a nav rail with all seven sections: Setup, Approval Routing, Analytics Notifications, GUS Configuration, Scheduled Jobs, Recycle Bin, and Notifications', async () => {
        const element = createElement('c-gtm-offerings-settings', {
            is: GtmOfferingsSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const navItems = element.shadowRoot.querySelectorAll('.slds-nav-vertical__action');
        expect(navItems).toHaveLength(7);
        expect(navItems[0].textContent).toBe('Setup');
        expect(navItems[1].textContent).toBe('Approval Routing');
        expect(navItems[2].textContent).toBe('Analytics Notifications');
        expect(navItems[3].textContent).toBe('GUS Configuration');
        expect(navItems[4].textContent).toBe('Scheduled Jobs');
        expect(navItems[5].textContent).toBe('Recycle Bin');
        expect(navItems[6].textContent).toBe('Notifications');
    });

    it('switches to the Recycle Bin section child on nav click', async () => {
        const element = createElement('c-gtm-offerings-settings', {
            is: GtmOfferingsSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const navItems = element.shadowRoot.querySelectorAll('.slds-nav-vertical__action');
        navItems[5].dispatchEvent(new CustomEvent('click', { cancelable: true }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-recycle-bin')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-readout-approval-settings')).toBeNull();

        const activeItem = element.shadowRoot.querySelector('.slds-nav-vertical__item.slds-is-active');
        expect(activeItem.textContent).toBe('Recycle Bin');
    });

    it('deep-links to the Recycle Bin section via c__section page state', async () => {
        const element = createElement('c-gtm-offerings-settings', {
            is: GtmOfferingsSettings
        });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__section: 'recycle-bin' } });
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-recycle-bin')).not.toBeNull();
        const activeItem = element.shadowRoot.querySelector('.slds-nav-vertical__item.slds-is-active');
        expect(activeItem.textContent).toBe('Recycle Bin');
    });

    it('ignores an unknown c__section page state', async () => {
        const element = createElement('c-gtm-offerings-settings', {
            is: GtmOfferingsSettings
        });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__section: 'nope' } });
        await flushPromises();

        const activeItem = element.shadowRoot.querySelector('.slds-nav-vertical__item.slds-is-active');
        expect(activeItem.textContent).toBe('Setup');
    });

    it('marks the Setup nav item active by default and mounts the checklist', async () => {
        const element = createElement('c-gtm-offerings-settings', {
            is: GtmOfferingsSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const activeItem = element.shadowRoot.querySelector('.slds-nav-vertical__item.slds-is-active');
        expect(activeItem).not.toBeNull();
        expect(activeItem.textContent).toBe('Setup');
        expect(element.shadowRoot.querySelector('c-gtm-setup-checklist')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-readout-approval-settings')).toBeNull();
    });

    it('renders the migrated gtmReadoutApprovalSettings child when Approval Routing is selected', async () => {
        const element = createElement('c-gtm-offerings-settings', {
            is: GtmOfferingsSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelectorAll('.slds-nav-vertical__action')[1]
            .dispatchEvent(new CustomEvent('click', { cancelable: true }));
        await flushPromises();

        const child = element.shadowRoot.querySelector('c-gtm-readout-approval-settings');
        expect(child).not.toBeNull();
    });

    it('switches to the Analytics Notifications section child on nav click', async () => {
        const element = createElement('c-gtm-offerings-settings', {
            is: GtmOfferingsSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const navItems = element.shadowRoot.querySelectorAll('.slds-nav-vertical__action');
        navItems[2].dispatchEvent(new CustomEvent('click', { cancelable: true }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-analytics-notification-settings')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-readout-approval-settings')).toBeNull();

        const activeItem = element.shadowRoot.querySelector('.slds-nav-vertical__item.slds-is-active');
        expect(activeItem.textContent).toBe('Analytics Notifications');
    });

    it('switches to the GUS Configuration section child on nav click', async () => {
        const element = createElement('c-gtm-offerings-settings', {
            is: GtmOfferingsSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const navItems = element.shadowRoot.querySelectorAll('.slds-nav-vertical__action');
        navItems[3].dispatchEvent(new CustomEvent('click', { cancelable: true }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-offerings-settings-agent')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-readout-approval-settings')).toBeNull();

        const activeItem = element.shadowRoot.querySelector('.slds-nav-vertical__item.slds-is-active');
        expect(activeItem.textContent).toBe('GUS Configuration');
    });

    it('switches to the Scheduled Jobs section child on nav click', async () => {
        const element = createElement('c-gtm-offerings-settings', {
            is: GtmOfferingsSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const navItems = element.shadowRoot.querySelectorAll('.slds-nav-vertical__action');
        navItems[4].dispatchEvent(new CustomEvent('click', { cancelable: true }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-scheduled-jobs-settings')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-readout-approval-settings')).toBeNull();

        const activeItem = element.shadowRoot.querySelector('.slds-nav-vertical__item.slds-is-active');
        expect(activeItem.textContent).toBe('Scheduled Jobs');
    });

    it('switches to the Notifications section child on nav click', async () => {
        const element = createElement('c-gtm-offerings-settings', {
            is: GtmOfferingsSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const navItems = element.shadowRoot.querySelectorAll('.slds-nav-vertical__action');
        navItems[6].dispatchEvent(new CustomEvent('click', { cancelable: true }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-offerings-settings-notifications')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-readout-approval-settings')).toBeNull();

        const activeItem = element.shadowRoot.querySelector('.slds-nav-vertical__item.slds-is-active');
        expect(activeItem.textContent).toBe('Notifications');
    });

    describe('selectsection from the Setup checklist', () => {
        async function mount() {
            const element = createElement('c-gtm-offerings-settings', {
                is: GtmOfferingsSettings
            });
            document.body.appendChild(element);
            await flushPromises();
            return element;
        }
        const fire = (element, sectionId) =>
            element.shadowRoot
                .querySelector('c-gtm-setup-checklist')
                .dispatchEvent(new CustomEvent('selectsection', { detail: { sectionId } }));

        it.each([
            ['approval-routing', 'c-gtm-readout-approval-settings', 'Approval Routing'],
            ['analytics-notifications', 'c-gtm-analytics-notification-settings', 'Analytics Notifications'],
            ['claude-gus', 'c-gtm-offerings-settings-agent', 'GUS Configuration']
        ])('switches to %s', async (id, tag, label) => {
            const element = await mount();
            fire(element, id);
            await flushPromises();
            expect(element.shadowRoot.querySelector(tag)).not.toBeNull();
            expect(element.shadowRoot.querySelector('c-gtm-setup-checklist')).toBeNull();
            expect(
                element.shadowRoot.querySelector('.slds-nav-vertical__item.slds-is-active').textContent
            ).toBe(label);
        });

        it('ignores an unknown or missing section id', async () => {
            const element = await mount();
            fire(element, 'nope');
            await flushPromises();
            fire(element, undefined);
            await flushPromises();
            expect(element.shadowRoot.querySelector('c-gtm-setup-checklist')).not.toBeNull();
            expect(
                element.shadowRoot.querySelector('.slds-nav-vertical__item.slds-is-active').textContent
            ).toBe('Setup');
        });
    });
});
