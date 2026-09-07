import { LightningElement, api, track } from 'lwc';
import chat from '@salesforce/apex/GtmAgentProxyController.chat';
import chatOnReadout from '@salesforce/apex/GtmAgentProxyController.chatOnReadout';

const FALLBACK_PLACEHOLDER = 'Ask me to update company, industry, accent color…';
const MODE_CONFIG = 'config';
const MODE_READOUT = 'readout';

/**
 * The GUS chat surface. One component, two screens (ported from
 * claude/salesforce-marketing-maturity-bsxmxs, folded onto this file rather
 * than replacing it -- see docs/handoff/port-map-ma-to-gtm.md section 5.6).
 *
 * `mode` picks which Apex entry point — and therefore which system prompt and
 * which tools — the conversation runs against. Everything else (the bubbles,
 * the history handling, the delta event) is identical, because it should be:
 * when Agentforce is provisioned this whole component is replaced by
 * <einstein-copilot-chat> with a different agent-api-name per screen, and
 * keeping the screens' differences on the SERVER side is what makes that a
 * one-line swap rather than a rewrite.
 *
 * The delta contract is unchanged: the server never writes, it returns
 * `changes`, and the host component decides what to do with them.
 *   config  → { company, industry, accent, ... } for the configurator panel
 *   readout → { draftContent } for gtmReadoutAssist
 */
export default class GtmAgentChat extends LightningElement {
    @api sessionToken = '';
    @api configId = '';

    /** 'config' (default) or 'readout'. */
    @api mode = MODE_CONFIG;

    /** Readout mode: the record the conversation is bound to. */
    @api readoutId = '';

    /**
     * Readout mode: the rep's UNSAVED editor content. Sent on every turn so
     * proposed edits are computed against what the rep is actually looking at,
     * not against the last saved version.
     */
    @api workingDraft = '';

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

    get isReadoutMode() {
        return this.mode === MODE_READOUT;
    }

    get placeholder() {
        if (this.placeholderText) return this.placeholderText;
        return this.isReadoutMode
            ? 'Paste your notes, or ask me to draft a section…'
            : FALLBACK_PLACEHOLDER;
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

        this._send(text)
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

    /**
     * Routes to the entry point for this mode. The readout call deliberately
     * carries no config session token: the two surfaces share a loop on the
     * server, not a session.
     */
    _send(text) {
        if (this.isReadoutMode) {
            return chatOnReadout({
                readoutId    : this.readoutId,
                workingDraft : this.workingDraft || '',
                userMessage  : text,
                historyJson  : this.historyJson
            });
        }
        return chat({
            sessionToken : this.sessionToken,
            configId     : this.configId,
            userMessage  : text,
            historyJson  : this.historyJson
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
