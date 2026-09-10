import { createElement } from 'lwc';
import GtmReadoutAssist from 'c/gtmReadoutAssist';
import getRepNotes from '@salesforce/apex/GtmReadoutAgentContext.getRepNotes';
import saveRepNotes from '@salesforce/apex/GtmReadoutAgentContext.saveRepNotes';

jest.mock(
    '@salesforce/apex/GtmReadoutAgentContext.getRepNotes',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutAgentContext.saveRepNotes',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function mount(props = {}) {
    const element = createElement('c-gtm-readout-assist', { is: GtmReadoutAssist });
    Object.assign(element, { readoutId: 'a01000000000001', status: 'Draft', ...props });
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

async function open(element) {
    element.shadowRoot.querySelector('.ra-toggle').dispatchEvent(new CustomEvent('click'));
    await flushPromises();
    return element;
}

describe('c-gtm-readout-assist', () => {
    beforeEach(() => {
        getRepNotes.mockResolvedValue('');
        saveRepNotes.mockResolvedValue();
    });

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('starts collapsed and opens on the toggle', async () => {
        const element = await mount();
        expect(element.shadowRoot.querySelector("lightning-textarea.ra-notes")).toBeNull();

        await open(element);
        expect(element.shadowRoot.querySelector("lightning-textarea.ra-notes")).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-agent-chat')).not.toBeNull();
    });

    it('runs the chat in readout mode and hands it the unsaved working draft', async () => {
        const element = await mount({ workingDraft: '<p>unsaved edit</p>' });
        await open(element);

        const chat = element.shadowRoot.querySelector('c-gtm-agent-chat');
        expect(chat.mode).toBe('readout');
        expect(chat.readoutId).toBe('a01000000000001');
        expect(chat.workingDraft).toBe('<p>unsaved edit</p>');
    });

    it('loads the saved notes into the box', async () => {
        getRepNotes.mockResolvedValue('Procurement is the blocker.');
        const element = await mount();
        await open(element);
        expect(element.shadowRoot.querySelector("lightning-textarea.ra-notes").value).toBe('Procurement is the blocker.');
    });

    it('keeps working when the notes cannot be read', async () => {
        getRepNotes.mockRejectedValue(new Error('nope'));
        const element = await mount();
        await open(element);
        expect(element.shadowRoot.querySelector('c-gtm-agent-chat')).not.toBeNull();
    });

    it('only enables Save context once the notes have changed', async () => {
        const element = await mount();
        await open(element);
        const saveBtn = element.shadowRoot.querySelector('.ra-notes-foot lightning-button');
        expect(saveBtn.disabled).toBe(true);

        const box = element.shadowRoot.querySelector("lightning-textarea.ra-notes");
        box.value = 'They pushed the date.';
        box.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        expect(element.shadowRoot.querySelector('.ra-notes-foot lightning-button').disabled).toBe(false);
    });

    it('saves the notes against the readout', async () => {
        const element = await mount();
        await open(element);
        const box = element.shadowRoot.querySelector("lightning-textarea.ra-notes");
        box.value = 'They pushed the date.';
        box.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        element.shadowRoot
            .querySelector('.ra-notes-foot lightning-button')
            .dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(saveRepNotes).toHaveBeenCalledWith({
            readoutId: 'a01000000000001',
            notes: 'They pushed the date.'
        });
    });

    it('re-dispatches a proposed draft to the editor', async () => {
        const element = await mount();
        await open(element);
        const handler = jest.fn();
        element.addEventListener('draftproposed', handler);

        element.shadowRoot.querySelector('c-gtm-agent-chat').dispatchEvent(
            new CustomEvent('agentdelta', { detail: { changes: { draftContent: '<p>new</p>' } } })
        );
        await flushPromises();

        expect(handler).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.draftContent).toBe('<p>new</p>');
    });

    it('ignores a delta that carries no draft content', async () => {
        const element = await mount();
        await open(element);
        const handler = jest.fn();
        element.addEventListener('draftproposed', handler);

        element.shadowRoot.querySelector('c-gtm-agent-chat').dispatchEvent(
            new CustomEvent('agentdelta', { detail: { changes: { company: 'Northwind' } } })
        );
        await flushPromises();
        expect(handler).not.toHaveBeenCalled();
    });

    it('shows no lock notice on a draft', async () => {
        const element = await mount({ status: 'Draft' });
        await open(element);
        expect(element.shadowRoot.querySelector('.ra-notice')).toBeNull();
    });

    it.each([
        ['Pending Approval', 'recall'],
        ['Approved', 'Return to draft'],
        ['Published', 'unpublish']
    ])('explains on %s why GUS cannot edit, and names the way out', async (status, route) => {
        const element = await mount({ status });
        await open(element);
        const notice = element.shadowRoot.querySelector('.ra-notice');
        expect(notice).not.toBeNull();
        expect(notice.textContent.toLowerCase()).toContain(route.toLowerCase());
    });

    it('offers file upload against the readout itself', async () => {
        const element = await mount();
        await open(element);
        const upload = element.shadowRoot.querySelector('lightning-file-upload');
        expect(upload.recordId).toBe('a01000000000001');
    });

    it('lists a file once it is attached', async () => {
        const element = await mount();
        await open(element);
        element.shadowRoot.querySelector('lightning-file-upload').dispatchEvent(
            new CustomEvent('uploadfinished', {
                detail: { files: [{ documentId: '069000000000001', name: 'discovery-notes.txt' }] }
            })
        );
        await flushPromises();
        expect(element.shadowRoot.querySelector('.ra-file').textContent).toBe('discovery-notes.txt');
    });
});
