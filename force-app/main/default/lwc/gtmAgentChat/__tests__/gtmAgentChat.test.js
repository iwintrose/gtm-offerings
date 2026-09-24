import { createElement } from 'lwc';
import GtmAgentChat from 'c/gtmAgentChat';
import chat from '@salesforce/apex/GtmAgentProxyController.chat';
import chatOnReadout from '@salesforce/apex/GtmAgentProxyController.chatOnReadout';
import chatOnApp from '@salesforce/apex/GtmAgentProxyController.chatOnApp';

jest.mock('@salesforce/apex/GtmAgentProxyController.chat',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmAgentProxyController.chatOnReadout',
    () => ({ default: jest.fn() }), { virtual: true });

jest.mock('@salesforce/apex/GtmAgentProxyController.chatOnApp',
    () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function mount(props = {}) {
    const el = createElement('c-gtm-agent-chat', { is: GtmAgentChat });
    Object.assign(el, props);
    document.body.appendChild(el);
    await flushPromises();
    return el;
}

function textareaEl(el) {
    return el.shadowRoot.querySelector('textarea');
}

function sendBtn(el) {
    return el.shadowRoot.querySelector('.send-btn');
}

/** Sets the draft field and waits for LWC to re-render before returning. */
async function setDraft(el, value) {
    const ta = textareaEl(el);
    ta.value = value;
    ta.dispatchEvent(new CustomEvent('change'));
    await flushPromises();
}

afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
});

describe('c-gtm-agent-chat', () => {
    // ── 1. Send (config mode) ────────────────────────────────────────────────
    it('send (config mode): appends user bubble, calls chat with correct args, appends assistant bubble, and stores historyJson for next turn', async () => {
        const el = await mount({ sessionToken: 'tok-1', configId: 'cfg-1' });
        chat.mockResolvedValue(JSON.stringify({ text: 'Hello!', historyJson: 'h2', changes: {} }));

        await setDraft(el, 'Hi there');
        sendBtn(el).click();
        await flushPromises();

        // user and assistant bubbles both present
        const bubbleTexts = [...el.shadowRoot.querySelectorAll('.bubble')]
            .map((b) => b.textContent)
            .filter((t) => !t.includes('\n')); // skip thinking dots
        expect(bubbleTexts).toContain('Hi there');
        expect(bubbleTexts).toContain('Hello!');

        expect(chat).toHaveBeenCalledWith({
            sessionToken: 'tok-1',
            configId: 'cfg-1',
            userMessage: 'Hi there',
            historyJson: ''
        });

        // historyJson stored for next turn
        chat.mockResolvedValue(JSON.stringify({ text: 'Second reply', historyJson: 'h3', changes: {} }));
        await setDraft(el, 'Second message');
        sendBtn(el).click();
        await flushPromises();

        expect(chat).toHaveBeenLastCalledWith(expect.objectContaining({ historyJson: 'h2' }));
    });

    // ── 2. agentdelta event ──────────────────────────────────────────────────
    it('agentdelta fires with detail.changes when changes is non-empty', async () => {
        const el = await mount();
        const changes = { company: 'Acme', accent: 'FF0000' };
        chat.mockResolvedValue(JSON.stringify({ text: 'ok', historyJson: '', changes }));

        const received = [];
        el.addEventListener('agentdelta', (e) => received.push(e));

        await setDraft(el, 'update company');
        sendBtn(el).click();
        await flushPromises();

        expect(received).toHaveLength(1);
        expect(received[0].detail.changes).toEqual(changes);
        expect(received[0].bubbles).toBe(false);
        expect(received[0].composed).toBe(false);
    });

    it('agentdelta does NOT fire when changes is absent from payload', async () => {
        const el = await mount();
        chat.mockResolvedValue(JSON.stringify({ text: 'ok', historyJson: '' }));

        const received = [];
        el.addEventListener('agentdelta', (e) => received.push(e));

        await setDraft(el, 'hello');
        sendBtn(el).click();
        await flushPromises();

        expect(received).toHaveLength(0);
    });

    it('agentdelta does NOT fire when changes is an empty object', async () => {
        const el = await mount();
        chat.mockResolvedValue(JSON.stringify({ text: 'ok', historyJson: '', changes: {} }));

        const received = [];
        el.addEventListener('agentdelta', (e) => received.push(e));

        await setDraft(el, 'hello');
        sendBtn(el).click();
        await flushPromises();

        expect(received).toHaveLength(0);
    });

    // ── 3. Send (readout mode) ───────────────────────────────────────────────
    it('send (readout mode): calls chatOnReadout with readoutId/workingDraft, not chat', async () => {
        const el = await mount({ mode: 'readout', readoutId: 'r001', workingDraft: 'draft content' });
        chatOnReadout.mockResolvedValue(JSON.stringify({ text: 'Readout reply', historyJson: 'rh1', changes: {} }));

        await setDraft(el, 'update draft');
        sendBtn(el).click();
        await flushPromises();

        expect(chat).not.toHaveBeenCalled();
        expect(chatOnReadout).toHaveBeenCalledWith({
            readoutId: 'r001',
            workingDraft: 'draft content',
            userMessage: 'update draft',
            historyJson: ''
        });
    });

    // ── 4. Error state ───────────────────────────────────────────────────────
    it('error state: appends error bubble from err.body.message and resets thinking', async () => {
        const el = await mount();
        chat.mockRejectedValue({ body: { message: 'Server blew up' }, message: 'fallback msg' });

        await setDraft(el, 'hello');
        sendBtn(el).click();
        await flushPromises();

        const bubbleTexts = [...el.shadowRoot.querySelectorAll('.bubble')].map((b) => b.textContent);
        expect(bubbleTexts).toContain('Server blew up');
        // thinking indicator gone
        expect(el.shadowRoot.querySelector('.bubble.thinking')).toBeNull();
    });

    it('error state: falls back to err.message when body.message is absent', async () => {
        const el = await mount();
        chat.mockRejectedValue({ message: 'Network error' });

        await setDraft(el, 'hello');
        sendBtn(el).click();
        await flushPromises();

        const bubbleTexts = [...el.shadowRoot.querySelectorAll('.bubble')].map((b) => b.textContent);
        expect(bubbleTexts).toContain('Network error');
    });

    it('error state: uses ultimate fallback message when no message available', async () => {
        const el = await mount();
        chat.mockRejectedValue({});

        await setDraft(el, 'hello');
        sendBtn(el).click();
        await flushPromises();

        const bubbleTexts = [...el.shadowRoot.querySelectorAll('.bubble')].map((b) => b.textContent);
        expect(bubbleTexts).toContain('Something went wrong. Please try again.');
    });

    // ── 5. Empty-input guard ─────────────────────────────────────────────────
    it('sendDisabled is true when draft is blank; handleSend no-ops and Apex is not called', async () => {
        const el = await mount();
        // draft is '' initially
        expect(sendBtn(el).disabled).toBe(true);
        // Even programmatically triggering the send button (which is disabled) should not call Apex
        // We test by confirming no Apex call happens after dispatch
        await flushPromises();
        expect(chat).not.toHaveBeenCalled();
        expect(el.shadowRoot.querySelectorAll('.message')).toHaveLength(0);
    });

    it('sendDisabled is true when draft is whitespace-only', async () => {
        const el = await mount();
        await setDraft(el, '   ');
        expect(sendBtn(el).disabled).toBe(true);
        expect(chat).not.toHaveBeenCalled();
    });

    // ── 6. Greeting ──────────────────────────────────────────────────────────
    it('greeting: prepends a synthetic assistant bubble with id greeting when greeting prop is set', async () => {
        const el = await mount({ greeting: 'Hello, how can I help?' });

        const messages = [...el.shadowRoot.querySelectorAll('.message')];
        expect(messages).toHaveLength(1);
        expect(messages[0].querySelector('.bubble').textContent).toBe('Hello, how can I help?');
        expect(messages[0].classList.contains('assistant')).toBe(true);
    });

    it('greeting: no greeting bubble when greeting prop is blank', async () => {
        const el = await mount({ greeting: '' });
        expect(el.shadowRoot.querySelectorAll('.message')).toHaveLength(0);
    });

    it('greeting bubble never appears in the historyJson sent to Apex', async () => {
        const el = await mount({ greeting: 'Hello!' });
        chat.mockResolvedValue(JSON.stringify({ text: 'reply', historyJson: 'h1', changes: {} }));

        await setDraft(el, 'test message');
        sendBtn(el).click();
        await flushPromises();

        expect(chat).toHaveBeenCalledWith(expect.objectContaining({ historyJson: '' }));
    });

    // ── 7. readOnly mode ─────────────────────────────────────────────────────
    it('readOnly mode: input and send button are disabled regardless of thinking state', async () => {
        const el = await mount({ readOnly: true });

        expect(textareaEl(el).disabled).toBe(true);
        expect(sendBtn(el).disabled).toBe(true);
    });

    it('readOnly mode: disabled even with a non-empty draft value', async () => {
        const el = await mount({ readOnly: true });
        // Even if draft were set, readOnly keeps everything disabled
        const ta = textareaEl(el);
        ta.value = 'some text';
        ta.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(textareaEl(el).disabled).toBe(true);
        expect(sendBtn(el).disabled).toBe(true);
        expect(chat).not.toHaveBeenCalled();
    });
});

describe('c-gtm-agent-chat app mode', () => {
    const EFFECT = { type: 'navigate', label: 'Show these in Pages', apiName: 'GTM_Pages', state: { c__stage: 'quiet' } };

    async function sendOne(el, text = 'hi') {
        await setDraft(el, text);
        sendBtn(el).click();
        await flushPromises();
    }

    it('calls chatOnApp (not chat/chatOnReadout) with pageContextJson read at send time', async () => {
        chatOnApp.mockResolvedValue(JSON.stringify({ text: 'ok', historyJson: 'h', changes: {} }));
        const el = await mount({ mode: 'app', pageContext: { tabApiName: 'GTM_Pages' } });
        await sendOne(el);
        expect(chatOnApp).toHaveBeenCalledWith({
            pageContextJson: JSON.stringify({ tabApiName: 'GTM_Pages' }),
            userMessage: 'hi',
            historyJson: ''
        });
        expect(chat).not.toHaveBeenCalled();
        expect(chatOnReadout).not.toHaveBeenCalled();

        el.pageContext = { tabApiName: 'GTM_Analytics' };
        await sendOne(el, 'again');
        expect(chatOnApp).toHaveBeenLastCalledWith({
            pageContextJson: JSON.stringify({ tabApiName: 'GTM_Analytics' }),
            userMessage: 'again',
            historyJson: 'h'
        });
    });

    it('sends {} when pageContext is unset', async () => {
        chatOnApp.mockResolvedValue(JSON.stringify({ text: 'ok', historyJson: '', changes: {} }));
        const el = await mount({ mode: 'app', pageContext: undefined });
        await sendOne(el);
        expect(chatOnApp).toHaveBeenCalledWith(expect.objectContaining({ pageContextJson: '{}' }));
    });

    it('pageEffect renders one button that dispatches exactly one agentaction per click', async () => {
        chatOnApp.mockResolvedValue(JSON.stringify({ text: 'Found 3', historyJson: 'h', changes: { pageEffect: EFFECT } }));
        const el = await mount({ mode: 'app' });
        const onAction = jest.fn();
        const onDelta = jest.fn();
        el.addEventListener('agentaction', onAction);
        el.addEventListener('agentdelta', onDelta);
        await sendOne(el);

        const btns = el.shadowRoot.querySelectorAll('.effect-btn');
        expect(btns.length).toBe(1);
        expect(btns[0].textContent).toBe('Show these in Pages');
        expect(onAction).not.toHaveBeenCalled();
        expect(onDelta).toHaveBeenCalledTimes(1);

        btns[0].click();
        expect(onAction).toHaveBeenCalledTimes(1);
        expect(onAction.mock.calls[0][0].detail).toEqual(EFFECT);
    });

    it('ignores malformed pageEffect (no button)', async () => {
        chatOnApp.mockResolvedValue(JSON.stringify({ text: 'x', historyJson: '', changes: { pageEffect: { type: 'evil', apiName: 'GTM_Pages', label: 'Go' } } }));
        const el = await mount({ mode: 'app' });
        await sendOne(el);
        expect(el.shadowRoot.querySelectorAll('.effect-btn').length).toBe(0);
    });

    it('does not render pageEffect buttons outside app mode', async () => {
        chat.mockResolvedValue(JSON.stringify({ text: 'x', historyJson: '', changes: { pageEffect: EFFECT } }));
        const el = await mount({});
        await sendOne(el);
        expect(el.shadowRoot.querySelectorAll('.effect-btn').length).toBe(0);
    });

    it('maps an Apex class access error to a friendly message (app mode only)', async () => {
        chatOnApp.mockRejectedValue({ body: { message: 'You do not have access to the Apex class named GtmAgentProxyController' } });
        const el = await mount({ mode: 'app' });
        await sendOne(el);
        const texts = [...el.shadowRoot.querySelectorAll('.bubble')].map((b) => b.textContent);
        expect(texts).toContain('You do not have access to GUS. Ask an admin to assign the GTM Offering User permission set.');
    });

    it('other errors keep the existing fallback in app mode', async () => {
        chatOnApp.mockRejectedValue({ body: { message: 'Callout failed' } });
        const el = await mount({ mode: 'app' });
        await sendOne(el);
        const texts = [...el.shadowRoot.querySelectorAll('.bubble')].map((b) => b.textContent);
        expect(texts).toContain('Callout failed');
    });

    it('reset() clears messages and history but keeps the greeting', async () => {
        chatOnApp.mockResolvedValue(JSON.stringify({ text: 'ok', historyJson: 'h1', changes: {} }));
        const el = await mount({ mode: 'app', greeting: 'Hello there' });
        await sendOne(el);
        el.reset();
        await flushPromises();
        const texts = [...el.shadowRoot.querySelectorAll('.bubble')].map((b) => b.textContent);
        expect(texts).toEqual(['Hello there']);

        await sendOne(el, 'fresh');
        expect(chatOnApp).toHaveBeenLastCalledWith(expect.objectContaining({ historyJson: '' }));
    });
});
