import { createElement } from 'lwc';
import GtmReadoutView from 'c/gtmReadoutView';
import getPublishedReadout from '@salesforce/apex/GtmReadoutPublicController.getPublishedReadout';
import getCommentSections from '@salesforce/apex/GtmReadoutCommentController.getCommentSections';
import submitComment from '@salesforce/apex/GtmReadoutCommentController.submitComment';

jest.mock(
    '@salesforce/apex/GtmReadoutPublicController.getPublishedReadout',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutCommentController.getCommentSections',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutCommentController.submitComment',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const SECTIONS = [
    'Verdict',
    'Context',
    'Scorecard',
    'Capability gaps',
    'Findings',
    'The path',
    'Next steps'
];

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function setUrl(search, pathname = '/gtmaccelerator/s/readout') {
    delete window.location;
    window.location = { search, hash: '', pathname };
}

describe('c-gtm-readout-view', () => {
    beforeEach(() => {
        getCommentSections.mockResolvedValue(SECTIONS);
        submitComment.mockResolvedValue({ accepted: true, message: 'Thanks — your comment has been sent.' });
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders the readout content and rep info for a valid token', async () => {
        setUrl('?token=abc123');
        getPublishedReadout.mockResolvedValue({
            content: '<p>Your assessment</p>',
            repName: 'Jamie Rep',
            repEmail: 'jamie@example.com',
            repPhone: '555-0100'
        });

        const element = createElement('c-gtm-readout-view', { is: GtmReadoutView });
        document.body.appendChild(element);
        await flushPromises();

        expect(getPublishedReadout).toHaveBeenCalledWith({ token: 'abc123' });
        expect(element.shadowRoot.querySelector('.rv-notfound')).toBeNull();
        // The contact block moved into the designed close panel; the rep's
        // name is still the thing that has to be on the page.
        expect(element.shadowRoot.querySelector('.who .nm').textContent).toBe('Jamie Rep');
    });

    it('accepts the ?readout= spelling gtmConfigurator mints for the same token', async () => {
        setUrl('?readout=abc123');
        getPublishedReadout.mockResolvedValue({ content: '<p>Your assessment</p>' });

        const element = createElement('c-gtm-readout-view', { is: GtmReadoutView });
        document.body.appendChild(element);
        await flushPromises();

        expect(getPublishedReadout).toHaveBeenCalledWith({ token: 'abc123' });
    });

    it('falls back to a /readout/<token> path segment when there is no query param', async () => {
        setUrl('', '/gtmaccelerator/s/readout/abc123');
        getPublishedReadout.mockResolvedValue({ content: '<p>Your assessment</p>' });

        const element = createElement('c-gtm-readout-view', { is: GtmReadoutView });
        document.body.appendChild(element);
        await flushPromises();

        expect(getPublishedReadout).toHaveBeenCalledWith({ token: 'abc123' });
    });

    it('does not treat the bare /readout page as a token', async () => {
        setUrl('', '/gtmaccelerator/s/readout');

        const element = createElement('c-gtm-readout-view', { is: GtmReadoutView });
        document.body.appendChild(element);
        await flushPromises();

        expect(getPublishedReadout).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('.rv-notfound')).not.toBeNull();
    });

    it('shows the generic not-found state for a missing token, without calling Apex', async () => {
        setUrl('');

        const element = createElement('c-gtm-readout-view', { is: GtmReadoutView });
        document.body.appendChild(element);
        await flushPromises();

        expect(getPublishedReadout).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('.rv-notfound')).not.toBeNull();
    });

    it('shows the same not-found state for an empty Apex response as for a thrown error', async () => {
        setUrl('?token=expired');
        getPublishedReadout.mockResolvedValue(null);

        const element = createElement('c-gtm-readout-view', { is: GtmReadoutView });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.rv-notfound')).not.toBeNull();
        // The generic copy is allowed to say "may have expired"; what must
        // never appear is anything derived from the token/response itself.
        expect(element.shadowRoot.textContent).not.toContain('expired-token-value');
    });

    it('does not distinguish a thrown Apex error from a not-found response', async () => {
        setUrl('?token=bad');
        getPublishedReadout.mockRejectedValue({ body: { message: 'INVALID_TOKEN' } });

        const element = createElement('c-gtm-readout-view', { is: GtmReadoutView });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.rv-notfound')).not.toBeNull();
        expect(element.shadowRoot.textContent).not.toContain('INVALID_TOKEN');
    });

    // ── recipient comments ───────────────────────────────────────────────────
    //
    // The box posts to GtmReadoutCommentController, which appends to the
    // readout's review Case. It is write-only: this page never reads the thread
    // back, because the same thread carries the reps' internal notes.

    async function renderWithComment(token = 'abc123') {
        setUrl(`?token=${token}`);
        getPublishedReadout.mockResolvedValue({ content: '<p>Your assessment</p>' });
        const element = createElement('c-gtm-readout-view', { is: GtmReadoutView });
        document.body.appendChild(element);
        await flushPromises();
        return element;
    }

    it('offers a per-section comment box once the readout has loaded', async () => {
        const element = await renderWithComment();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox).not.toBeNull();
        // The options come from Apex so the picker and the server's validation
        // cannot drift apart.
        expect(combobox.options.map((o) => o.value)).toEqual(SECTIONS);
        expect(element.shadowRoot.querySelector('lightning-textarea')).not.toBeNull();
    });

    it('shows no comment box on the not-found state, so it cannot be used to probe', async () => {
        setUrl('?token=nope');
        getPublishedReadout.mockResolvedValue(null);

        const element = createElement('c-gtm-readout-view', { is: GtmReadoutView });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.rv-notfound')).not.toBeNull();
        expect(element.shadowRoot.querySelector('lightning-textarea')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-combobox')).toBeNull();
    });

    it('sends the token, the section and the text, and clears the box on success', async () => {
        const element = await renderWithComment('tok-9');

        element.shadowRoot.querySelector('lightning-combobox')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'Scorecard' } }));
        const textarea = element.shadowRoot.querySelector('lightning-textarea');
        textarea.value = 'The integration score looks generous.';
        textarea.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(submitComment).toHaveBeenCalledWith({
            token: 'tok-9',
            section: 'Scorecard',
            body: 'The integration score looks generous.'
        });
        expect(element.shadowRoot.querySelector('.rv-comment-notice').textContent)
            .toContain('Thanks');
    });

    it('sends nothing until a section and some text are both chosen', async () => {
        const element = await renderWithComment();

        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();
        expect(submitComment).not.toHaveBeenCalled();

        // Section only, still no text.
        element.shadowRoot.querySelector('lightning-combobox')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'Verdict' } }));
        await flushPromises();
        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();
        expect(submitComment).not.toHaveBeenCalled();
    });

    it('renders the server refusal verbatim and infers nothing from it', async () => {
        // The server answers with a result, not an exception, precisely so that
        // every server-state failure reads the same. This page must not decorate
        // it, retry it, or say anything more specific than it did.
        const refusal = 'Your comment could not be sent. Please reach out to your Publicis Sapient contact.';
        submitComment.mockResolvedValue({ accepted: false, message: refusal });
        const element = await renderWithComment();

        element.shadowRoot.querySelector('lightning-combobox')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'Findings' } }));
        const textarea = element.shadowRoot.querySelector('lightning-textarea');
        textarea.value = 'Anything at all.';
        textarea.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        const notice = element.shadowRoot.querySelector('.rv-comment-notice');
        expect(notice.textContent).toBe(refusal);
        expect(notice.className).toContain('rv-comment-notice--error');
    });

    it('makes a transport failure read exactly like a refusal', async () => {
        submitComment.mockRejectedValue({ body: { message: 'FIELD_CUSTOM_VALIDATION_EXCEPTION' } });
        const element = await renderWithComment();

        element.shadowRoot.querySelector('lightning-combobox')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'Context' } }));
        const textarea = element.shadowRoot.querySelector('lightning-textarea');
        textarea.value = 'Anything at all.';
        textarea.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        const notice = element.shadowRoot.querySelector('.rv-comment-notice');
        expect(notice.textContent).toContain('could not be sent');
        expect(element.shadowRoot.textContent).not.toContain('FIELD_CUSTOM_VALIDATION_EXCEPTION');
    });

    it('hides the comment box entirely when the section list cannot be loaded', async () => {
        // A picker with no valid options would only ever produce refusals.
        getCommentSections.mockRejectedValue(new Error('no access'));
        const element = await renderWithComment();

        expect(element.shadowRoot.querySelector('lightning-combobox')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-textarea')).toBeNull();
        // The readout itself still renders — commenting is additive.
        expect(element.shadowRoot.querySelector('.stage')).not.toBeNull();
    });
});
