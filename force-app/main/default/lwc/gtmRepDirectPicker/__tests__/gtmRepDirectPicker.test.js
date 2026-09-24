import { createElement } from 'lwc';
import GtmRepDirectPicker from 'c/gtmRepDirectPicker';
import searchContacts from '@salesforce/apex/GtmSavedConfigurationController.searchContacts';
import createRepDirectAssessment from '@salesforce/apex/GtmSavedConfigurationController.createRepDirectAssessment';

jest.mock('@salesforce/apex/GtmSavedConfigurationController.searchContacts',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSavedConfigurationController.createRepDirectAssessment',
    () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

// Debounce on search is 300ms -- draining past that comfortably covers it.
function drainPendingTimers() {
    return new Promise((resolve) => setTimeout(resolve, 350));
}

describe('c-gtm-rep-direct-picker', () => {
    afterEach(async () => {
        await drainPendingTimers();
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function makeElement(props = {}) {
        const element = createElement('c-gtm-rep-direct-picker', { is: GtmRepDirectPicker });
        Object.assign(element, { isOpen: true, offeringKey: 'ma-migrator', ...props });
        document.body.appendChild(element);
        return element;
    }

    it('wraps its body content in c-gtm-modal-shell with is-open/title passed through', () => {
        const element = makeElement();

        const shell = element.shadowRoot.querySelector('c-gtm-modal-shell');
        expect(shell).not.toBeNull();
        expect(shell.isOpen).toBe(true);
        expect(shell.title).toBe('New assessment (no page)');
    });

    it('searches contacts as the rep types and renders result chips', async () => {
        searchContacts.mockResolvedValue([
            { contactId: '003001', name: 'Jane Doe', email: 'jane@acme.com', accountId: '001001', accountName: 'Acme' }
        ]);
        const element = makeElement();

        const input = element.shadowRoot.querySelector('.rdp-input');
        input.value = 'jane';
        input.dispatchEvent(new CustomEvent('input'));

        await drainPendingTimers();
        await flushPromises();

        expect(searchContacts).toHaveBeenCalledWith({ searchTerm: 'jane' });
        const chip = element.shadowRoot.querySelector('.rdp-chip');
        expect(chip).not.toBeNull();
        expect(chip.textContent).toBe('Jane Doe · Acme');
    });

    it('does not search below the 2-character threshold', async () => {
        const element = makeElement();
        const input = element.shadowRoot.querySelector('.rdp-input');
        input.value = 'j';
        input.dispatchEvent(new CustomEvent('input'));

        await drainPendingTimers();
        await flushPromises();

        expect(searchContacts).not.toHaveBeenCalled();
    });

    it('selecting a chip shows the selection and clears the search results', async () => {
        searchContacts.mockResolvedValue([
            { contactId: '003001', name: 'Jane Doe', email: 'jane@acme.com', accountId: '001001', accountName: 'Acme' }
        ]);
        const element = makeElement();

        const input = element.shadowRoot.querySelector('.rdp-input');
        input.value = 'jane';
        input.dispatchEvent(new CustomEvent('input'));
        await drainPendingTimers();
        await flushPromises();

        element.shadowRoot.querySelector('.rdp-chip').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.rdp-chip')).toBeNull();
        const selected = element.shadowRoot.querySelector('.rdp-selected');
        expect(selected.textContent).toContain('Jane Doe · Acme');
    });

    it('"Change" clears the selection and returns to the search field', async () => {
        searchContacts.mockResolvedValue([
            { contactId: '003001', name: 'Jane Doe', email: 'jane@acme.com', accountId: '001001', accountName: 'Acme' }
        ]);
        const element = makeElement();

        const input = element.shadowRoot.querySelector('.rdp-input');
        input.value = 'jane';
        input.dispatchEvent(new CustomEvent('input'));
        await drainPendingTimers();
        await flushPromises();
        element.shadowRoot.querySelector('.rdp-chip').click();
        await flushPromises();

        element.shadowRoot.querySelector('.rdp-mini-link').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.rdp-selected')).toBeNull();
        expect(element.shadowRoot.querySelector('.rdp-input')).not.toBeNull();
    });

    it('confirm is disabled until a contact is selected', () => {
        const element = makeElement();
        const confirmBtn = element.shadowRoot.querySelector('.rdp-actions button');
        expect(confirmBtn.disabled).toBe(true);
    });

    it('confirming a selection creates the rep-direct assessment and dispatches created', async () => {
        searchContacts.mockResolvedValue([
            { contactId: '003001', name: 'Jane Doe', email: 'jane@acme.com', accountId: '001001', accountName: 'Acme' }
        ]);
        createRepDirectAssessment.mockResolvedValue('a0X000001');
        const element = makeElement();

        const createdHandler = jest.fn();
        element.addEventListener('created', createdHandler);
        const closeHandler = jest.fn();
        element.addEventListener('close', closeHandler);

        const input = element.shadowRoot.querySelector('.rdp-input');
        input.value = 'jane';
        input.dispatchEvent(new CustomEvent('input'));
        await drainPendingTimers();
        await flushPromises();
        element.shadowRoot.querySelector('.rdp-chip').click();
        await flushPromises();

        element.shadowRoot.querySelector('.rdp-actions button').click();
        await flushPromises();

        expect(createRepDirectAssessment).toHaveBeenCalledWith({
            input: { contactId: '003001', accountId: '001001', offering: 'ma-migrator' }
        });
        expect(createdHandler).toHaveBeenCalledTimes(1);
        expect(createdHandler.mock.calls[0][0].detail).toEqual({ recordId: 'a0X000001' });
        // handleClose runs as part of confirm's success path too.
        expect(closeHandler).toHaveBeenCalledTimes(1);
    });

    it('shows an error message when creation fails', async () => {
        searchContacts.mockResolvedValue([
            { contactId: '003001', name: 'Jane Doe', email: 'jane@acme.com', accountId: '001001', accountName: 'Acme' }
        ]);
        createRepDirectAssessment.mockRejectedValue({ body: { message: 'Duplicate found' } });
        const element = makeElement();

        const input = element.shadowRoot.querySelector('.rdp-input');
        input.value = 'jane';
        input.dispatchEvent(new CustomEvent('input'));
        await drainPendingTimers();
        await flushPromises();
        element.shadowRoot.querySelector('.rdp-chip').click();
        await flushPromises();

        element.shadowRoot.querySelector('.rdp-actions button').click();
        await flushPromises();

        const error = element.shadowRoot.querySelector('.rdp-error');
        expect(error).not.toBeNull();
        expect(error.textContent).toBe('Duplicate found');
    });

    it('closing the shell resets state and redispatches close', async () => {
        searchContacts.mockResolvedValue([
            { contactId: '003001', name: 'Jane Doe', email: 'jane@acme.com', accountId: '001001', accountName: 'Acme' }
        ]);
        const element = makeElement();

        const input = element.shadowRoot.querySelector('.rdp-input');
        input.value = 'jane';
        input.dispatchEvent(new CustomEvent('input'));
        await drainPendingTimers();
        await flushPromises();
        element.shadowRoot.querySelector('.rdp-chip').click();
        await flushPromises();

        const closeHandler = jest.fn();
        element.addEventListener('close', closeHandler);

        const shell = element.shadowRoot.querySelector('c-gtm-modal-shell');
        shell.dispatchEvent(new CustomEvent('close'));
        await flushPromises();

        expect(closeHandler).toHaveBeenCalledTimes(1);
        // State reset: selection cleared, search field back.
        expect(element.shadowRoot.querySelector('.rdp-selected')).toBeNull();
        expect(element.shadowRoot.querySelector('.rdp-input')).not.toBeNull();
    });
});
