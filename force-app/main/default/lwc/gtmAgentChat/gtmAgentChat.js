import { LightningElement, api, track } from 'lwc';
import chat from '@salesforce/apex/GtmAgentProxyController.chat';
import chatOnReadout from '@salesforce/apex/GtmAgentProxyController.chatOnReadout';
import chatOnApp from '@salesforce/apex/GtmAgentProxyController.chatOnApp';
import { loadBrandFonts } from 'c/gtmBrandFonts';

const FALLBACK_PLACEHOLDER = 'Ask me to update company, industry, accent color…';
const MODE_CONFIG = 'config';
const MODE_READOUT = 'readout';
const MODE_APP = 'app';
const NO_ACCESS_MARKER = 'access to the Apex class';
const NO_ACCESS_MESSAGE =
    'You do not have access to GUS. Ask an admin to assign the GTM Offering User permission set.';
const MAX_EFFECT_LABEL = 60;

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
 *   app     → { pageEffect } for the utility-bar host (gtmGusUtility); the
 *             rep gets a button and the host navigates on click (`agentaction`)
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

    /**
     * App mode: where the rep is (allow-listed by the host, re-sanitised by
     * Apex). Read at SEND time, never cached: the utility panel stays mounted
     * while the rep navigates.
     */
    @api pageContext = {};

    /** Clears the conversation (the host's "New chat"). The greeting is not a
     *  stored message, so it stays. */
    @api reset() {
        this.messages = [];
        this.historyJson = '';
        this.draft = '';
        this.thinking = false;
    }

    @track messages = [];
    @track thinking = false;

    draft = '';
    historyJson = '';
    _msgCounter = 0;

    connectedCallback() {
        // Every GUS chat mount runs through this one component, so loading
        // the brand fonts here once covers gtmGusUtility, gtmAgentBubble and
        // gtmReadoutAssist without each host needing its own call.
        loadBrandFonts();
    }

    get isReadoutMode() {
        return this.mode === MODE_READOUT;
    }

    get isAppMode() {
        return this.mode === MODE_APP;
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
            this._addMessage('assistant', parsed.text || '',
                this.isAppMode ? this._validEffect(parsed.changes?.pageEffect) : null);

            if (parsed.changes && Object.keys(parsed.changes).length > 0) {
                this.dispatchEvent(new CustomEvent('agentdelta', {
                    detail   : { changes: parsed.changes },
                    bubbles  : false,
                    composed : false
                }));
            }
        })
        .catch(err => {
            let msg = err?.body?.message || err?.message || 'Something went wrong. Please try again.';
            if (this.isAppMode && msg.includes(NO_ACCESS_MARKER)) {
                msg = NO_ACCESS_MESSAGE;
            }
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
        if (this.isAppMode) {
            return chatOnApp({
                pageContextJson : JSON.stringify(this.pageContext || {}),
                userMessage     : text,
                historyJson     : this.historyJson
            });
        }
        return chat({
            sessionToken : this.sessionToken,
            configId     : this.configId,
            userMessage  : text,
            historyJson  : this.historyJson
        });
    }

    /** Shape check only; the host decides what is allowed to happen. */
    _validEffect(effect) {
        if (!effect || typeof effect !== 'object' || effect.type !== 'navigate') return null;
        if (typeof effect.apiName !== 'string' || !effect.apiName) return null;
        if (typeof effect.label !== 'string' || !effect.label
            || effect.label.length > MAX_EFFECT_LABEL) return null;
        const state = effect.state;
        if (state !== undefined && state !== null
            && (typeof state !== 'object' || Array.isArray(state))) return null;
        return { label: effect.label, apiName: effect.apiName, state: state || {} };
    }

    handleEffectClick(e) {
        const id = Number(e.currentTarget.dataset.id);
        const msg = this.messages.find((m) => m.id === id);
        if (!msg || !msg.effect) return;
        this.dispatchEvent(new CustomEvent('agentaction', {
            detail   : { type: 'navigate', ...msg.effect },
            bubbles  : false,
            composed : false
        }));
    }

    _addMessage(role, text, effect = null) {
        this._msgCounter += 1;
        this.messages = [
            ...this.messages,
            { id: this._msgCounter, role, text, cssClass: effect ? `message ${role} has-effect` : `message ${role}`,
              effect, effectLabel: effect ? effect.label : '' }
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
