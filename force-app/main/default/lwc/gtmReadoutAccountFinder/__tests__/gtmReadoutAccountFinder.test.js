import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import GtmReadoutAccountFinder from 'c/gtmReadoutAccountFinder';
import getContactsWithRequests from '@salesforce/apex/GtmReadoutController.getContactsWithRequests';
import searchAccountsAndContacts from '@salesforce/apex/GtmAccountContactSearchController.searchAccountsAndContacts';

jest.mock(
    '@salesforce/apex/GtmReadoutController.getContactsWithRequests',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAccountContactSearchController.searchAccountsAndContacts',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

/** The unified search debounce is a real 300ms setTimeout -- real timers
 *  throughout this file, waiting it out for real rather than mocking
 *  timers globally. */
function waitForSearchDebounce() {
    return new Promise((resolve) => setTimeout(resolve, 350));
}

const REQUEST_ROW = {
    recordId: 'a0X000000000001AAA',
    name: 'AR-0049',
    company: 'Acme Co',
    offeringKey: 'migration-accelerator',
    status: 'Draft',
    requesterName: 'Jane Prospect',
    createdDate: '2026-01-01T00:00:00.000Z',
    readoutId: null
};

const ACCOUNT_RESULT = {
    recordId: '001000000000001AAA',
    type: 'Account',
    label: 'Acme Co',
    subLabel: '',
    accountId: '001000000000001AAA'
};

const CONTACT_RESULT = {
    recordId: '003000000000001AAA',
    type: 'Contact',
    label: 'Jane Prospect',
    subLabel: 'Acme Co',
    accountId: '001000000000001AAA'
};

function typeSearchTerm(element, term) {
    const input = element.shadowRoot.querySelector('lightning-input');
    input.value = term;
    input.dispatchEvent(new CustomEvent('change', { detail: { value: term } }));
}

describe('c-gtm-readout-account-finder', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows the unified search empty state on first render', async () => {
        const element = createElement('c-gtm-readout-account-finder', { is: GtmReadoutAccountFinder });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.raf-empty-state')).not.toBeNull();
        expect(element.shadowRoot.querySelector('lightning-input')).not.toBeNull();
        expect(element.shadowRoot.querySelector('lightning-record-picker')).toBeNull();
    });

    it('does not call Apex before 2 characters are typed', async () => {
        const element = createElement('c-gtm-readout-account-finder', { is: GtmReadoutAccountFinder });
        document.body.appendChild(element);
        await flushPromises();

        typeSearchTerm(element, 'a');
        await waitForSearchDebounce();
        await flushPromises();

        expect(searchAccountsAndContacts).not.toHaveBeenCalled();
    });

    it('debounces the search call by 300ms after the minimum length is met', async () => {
        searchAccountsAndContacts.mockResolvedValue([ACCOUNT_RESULT]);
        const element = createElement('c-gtm-readout-account-finder', { is: GtmReadoutAccountFinder });
        document.body.appendChild(element);
        await flushPromises();

        typeSearchTerm(element, 'ac');
        await new Promise((resolve) => setTimeout(resolve, 100));
        expect(searchAccountsAndContacts).not.toHaveBeenCalled();

        await new Promise((resolve) => setTimeout(resolve, 250));
        expect(searchAccountsAndContacts).toHaveBeenCalledWith({ searchTerm: 'ac' });
    });

    it('picking an Account result continues into the Contact -> Request drill-down', async () => {
        searchAccountsAndContacts.mockResolvedValue([ACCOUNT_RESULT]);
        getContactsWithRequests.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', requests: [REQUEST_ROW] }
        ]);

        const element = createElement('c-gtm-readout-account-finder', { is: GtmReadoutAccountFinder });
        const handler = jest.fn();
        element.addEventListener('selectrequest', handler);
        document.body.appendChild(element);
        await flushPromises();

        typeSearchTerm(element, 'Acme');
        await waitForSearchDebounce();

        const resultButton = element.shadowRoot.querySelector('button[data-id="001000000000001AAA"]');
        expect(resultButton).not.toBeNull();
        resultButton.click();
        await flushPromises();

        expect(getContactsWithRequests).toHaveBeenCalledWith({ accountId: '001000000000001AAA' });
        const contactRow = element.shadowRoot.querySelector('button[data-id="003000000000001AAA"]');
        expect(contactRow).not.toBeNull();
        contactRow.click();
        await flushPromises();

        const requestRow = element.shadowRoot.querySelector(`button[data-id="${REQUEST_ROW.recordId}"]`);
        expect(requestRow).not.toBeNull();
        requestRow.click();
        await flushPromises();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({
            assessmentRequestId: REQUEST_ROW.recordId,
            readoutId: '',
            offeringKey: 'migration-accelerator'
        });
    });

    it('picking a Contact result skips straight to that Contact\'s request list', async () => {
        searchAccountsAndContacts.mockResolvedValue([CONTACT_RESULT]);
        getContactsWithRequests.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', requests: [REQUEST_ROW] }
        ]);

        const element = createElement('c-gtm-readout-account-finder', { is: GtmReadoutAccountFinder });
        document.body.appendChild(element);
        await flushPromises();

        typeSearchTerm(element, 'Jane');
        await waitForSearchDebounce();

        const resultButton = element.shadowRoot.querySelector('button[data-id="003000000000001AAA"]');
        expect(resultButton).not.toBeNull();
        resultButton.click();
        await flushPromises();

        expect(getContactsWithRequests).toHaveBeenCalledWith({ accountId: '001000000000001AAA' });
        // No intermediate Contact-picking screen -- straight to the request list.
        const requestRow = element.shadowRoot.querySelector(`button[data-id="${REQUEST_ROW.recordId}"]`);
        expect(requestRow).not.toBeNull();
    });

    it('writes the drill-down depth to the URL as c__rafAccountId/c__rafContactId', async () => {
        searchAccountsAndContacts.mockResolvedValue([ACCOUNT_RESULT]);
        getContactsWithRequests.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', requests: [REQUEST_ROW] }
        ]);

        const element = createElement('c-gtm-readout-account-finder', { is: GtmReadoutAccountFinder });
        document.body.appendChild(element);
        await flushPromises();

        typeSearchTerm(element, 'Acme');
        await waitForSearchDebounce();
        element.shadowRoot.querySelector('button[data-id="001000000000001AAA"]').click();
        await flushPromises();

        let url = new URL(window.location.href);
        expect(url.searchParams.get('c__rafAccountId')).toBe('001000000000001AAA');
        expect(url.searchParams.get('c__rafContactId')).toBeNull();

        element.shadowRoot.querySelector('button[data-id="003000000000001AAA"]').click();
        await flushPromises();

        url = new URL(window.location.href);
        expect(url.searchParams.get('c__rafContactId')).toBe('003000000000001AAA');
    });

    it('restores mid-trail (account + contact) from CurrentPageReference state, simulating a refresh', async () => {
        getContactsWithRequests.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', requests: [REQUEST_ROW] }
        ]);

        const element = createElement('c-gtm-readout-account-finder', { is: GtmReadoutAccountFinder });
        document.body.appendChild(element);
        CurrentPageReference.emit({
            state: {
                c__rafAccountId: '001000000000001AAA',
                c__rafContactId: '003000000000001AAA'
            }
        });
        await flushPromises();

        expect(getContactsWithRequests).toHaveBeenCalledWith({ accountId: '001000000000001AAA' });
        const requestRow = element.shadowRoot.querySelector(`button[data-id="${REQUEST_ROW.recordId}"]`);
        expect(requestRow).not.toBeNull();
    });

    it('"Search again" clears the trail and returns to the empty search state', async () => {
        searchAccountsAndContacts.mockResolvedValue([ACCOUNT_RESULT]);
        getContactsWithRequests.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', requests: [REQUEST_ROW] }
        ]);

        const element = createElement('c-gtm-readout-account-finder', { is: GtmReadoutAccountFinder });
        document.body.appendChild(element);
        await flushPromises();

        typeSearchTerm(element, 'Acme');
        await waitForSearchDebounce();
        element.shadowRoot.querySelector('button[data-id="001000000000001AAA"]').click();
        await flushPromises();

        const searchAgain = element.shadowRoot.querySelector('.raf-search-again');
        expect(searchAgain).not.toBeNull();
        searchAgain.click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.raf-empty-state')).not.toBeNull();
        expect(element.shadowRoot.querySelector('lightning-input')).not.toBeNull();
        const url = new URL(window.location.href);
        expect(url.searchParams.get('c__rafAccountId')).toBeNull();
    });

    it('crumb click back to Account clears the trail', async () => {
        searchAccountsAndContacts.mockResolvedValue([ACCOUNT_RESULT]);
        getContactsWithRequests.mockResolvedValue([
            { contactId: '003000000000001AAA', contactName: 'Jane Prospect', requests: [REQUEST_ROW] }
        ]);

        const element = createElement('c-gtm-readout-account-finder', { is: GtmReadoutAccountFinder });
        document.body.appendChild(element);
        await flushPromises();

        typeSearchTerm(element, 'Acme');
        await waitForSearchDebounce();
        element.shadowRoot.querySelector('button[data-id="001000000000001AAA"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('button[data-id="003000000000001AAA"]').click();
        await flushPromises();

        const accountCrumb = element.shadowRoot.querySelector('button[data-key="account"]');
        accountCrumb.click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.raf-empty-state')).not.toBeNull();
        const url = new URL(window.location.href);
        expect(url.searchParams.get('c__rafAccountId')).toBeNull();
    });
});
