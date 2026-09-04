import { LightningElement, api, track } from 'lwc';
import chat from '@salesforce/apex/MaAgentProxyController.chat';

export default class MaAgentChat extends LightningElement {
    @api sessionToken = '';
    @api configId = '';

    @track messages = [];
    @track thinking = false;

    draft = '';
    historyJson = '';
    _msgCounter = 0;

    get busy() {
        return this.thinking;
    }

    get sendDisabled() {
        return this.busy || !this.draft.trim();
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
