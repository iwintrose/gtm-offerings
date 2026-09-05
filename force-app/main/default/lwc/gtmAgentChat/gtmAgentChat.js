import { LightningElement, api, track } from 'lwc';
import chat from '@salesforce/apex/GtmAgentProxyController.chat';

const FALLBACK_PLACEHOLDER = 'Ask me to update company, industry, accent color…';

export default class GtmAgentChat extends LightningElement {
    @api sessionToken = '';
    @api configId = '';

    /**
     * The words, which belong to the offering rather than to this component.
     *
     * The prompt in the input and the line the assistant opens with are the
     * two things a reader actually reads before typing, and what they should
     * say depends entirely on what the page is for. They arrive as content
     * from the page's own Assistant section; the constants below are only
     * what shows if that section has not been filled in yet.
     */
    @api placeholderText = '';
    @api greeting = '';

    /** In the editor's preview this is a picture of the assistant, not the
     *  assistant: there is no configuration behind it to change. */
    @api readOnly = false;

    @track messages = [];
    @track thinking = false;

    draft = '';
    historyJson = '';
    _msgCounter = 0;

    get placeholder() {
        return this.placeholderText || FALLBACK_PLACEHOLDER;
    }

    /**
     * The opening line is drawn as the assistant's first message rather than
     * stored as one, so it stays put when the conversation is replayed and
     * never ends up in the history sent back to the model.
     */
    get visibleMessages() {
        const greet = (this.greeting || '').trim();
        if (!greet) return this.messages;
        return [
            { id: 'greeting', role: 'assistant', text: greet, cssClass: 'message assistant' },
            ...this.messages
        ];
    }

    get busy() {
        return this.thinking;
    }

    get inputDisabled() {
        return this.busy || this.readOnly;
    }

    get sendDisabled() {
        return this.inputDisabled || !this.draft.trim();
    }

    handleDraftChange(e) {
        this.draft = e.target.value;
    }

    handleKeyDown(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            if (!this.sendDisabled) this.handleSend();
        }
    }

    handleSend() {
        const text = this.draft.trim();
        if (!text) return;

        this._addMessage('user', text);
        this.draft = '';
        this.thinking = true;

        chat({
            sessionToken : this.sessionToken,
            configId     : this.configId,
            userMessage  : text,
            historyJson  : this.historyJson
        })
        .then(result => {
            const parsed = JSON.parse(result);
            this.historyJson = parsed.historyJson || '';
            this._addMessage('assistant', parsed.text || '');

            if (parsed.changes && Object.keys(parsed.changes).length > 0) {
                this.dispatchEvent(new CustomEvent('agentdelta', {
                    detail   : { changes: parsed.changes },
                    bubbles  : false,
                    composed : false
                }));
            }
        })
        .catch(err => {
            const msg = err?.body?.message || err?.message || 'Something went wrong. Please try again.';
            this._addMessage('assistant', msg);
        })
        .finally(() => {
            this.thinking = false;
            this._scrollToBottom();
        });
    }

    _addMessage(role, text) {
        this._msgCounter += 1;
        this.messages = [
            ...this.messages,
            { id: this._msgCounter, role, text, cssClass: `message ${role}` }
        ];
        this._scrollToBottom();
    }

    _scrollToBottom() {
        // Defer to let the DOM update first
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const el = this.refs?.messageList;
            if (el) el.scrollTop = el.scrollHeight;
        }, 50);
    }
}
