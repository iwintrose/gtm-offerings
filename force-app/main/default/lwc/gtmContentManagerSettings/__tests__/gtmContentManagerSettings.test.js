import { createElement } from 'lwc';
import GtmContentManagerSettings from 'c/gtmContentManagerSettings';

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
    '@salesforce/apex/GTM_RecycleBinController.restoreRecord',
    () => ({ default: jest.fn(() => Promise.resolve()) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GTM_RecycleBinController.restoreRecords',
    () => ({ default: jest.fn(() => Promise.resolve([])) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GTM_RecycleBinController.deleteRecords',
    () => ({ default: jest.fn(() => Promise.resolve([])) }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-gtm-content-manager-settings', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders a nav rail with the Recycle Bin section, selected by default', async () => {
        const element = createElement('c-gtm-content-manager-settings', {
            is: GtmContentManagerSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const navItems = element.shadowRoot.querySelectorAll('.slds-nav-vertical__action');
        expect(navItems).toHaveLength(1);
        expect(navItems[0].textContent).toBe('Recycle Bin');

        const activeItem = element.shadowRoot.querySelector('.slds-nav-vertical__item.slds-is-active');
        expect(activeItem.textContent).toBe('Recycle Bin');
        expect(element.shadowRoot.querySelector('c-gtm-recycle-bin')).not.toBeNull();
    });

    it('deep-links to the Recycle Bin section via c__section page state', async () => {
        const element = createElement('c-gtm-content-manager-settings', {
            is: GtmContentManagerSettings
        });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__section: 'recycle-bin' } });
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-recycle-bin')).not.toBeNull();
    });

    it('ignores an unknown c__section page state', async () => {
        const element = createElement('c-gtm-content-manager-settings', {
            is: GtmContentManagerSettings
        });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__section: 'nope' } });
        await flushPromises();

        const activeItem = element.shadowRoot.querySelector('.slds-nav-vertical__item.slds-is-active');
        expect(activeItem.textContent).toBe('Recycle Bin');
    });
});
