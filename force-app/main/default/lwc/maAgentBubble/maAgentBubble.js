import { LightningElement, api, track } from 'lwc';
import { subscribe, unsubscribe } from 'lightning/empApi';

// The Agentforce path: the bot applies a change server-side and publishes it,
// rather than returning it in a chat reply. Both paths end at the same
// agentdelta event, so the page has one way to receive a change.
const CONFIG_UPDATE_CHANNEL = '/event/MA_Config_Update__e';

/**
 * The assistant, as a bubble in the corner.
 *
 * It used to be a mode inside the Customize flyout: to reach it you opened a
 * form, then switched the form to something that was not a form. A bubble is
 * where people already look for an assistant, and it leaves the page visible
 * behind it, which matters when the assistant's whole job is changing that
 * page.
 */
export default class MaAgentBubble extends LightningElement {
    @api sessionToken = '';
    @api configId = '';

    /** Label on the collapsed bubble. */
    @api label = 'Ask Gus';

    @track isOpen = false;
    @track busy = false;

    _sub = null;

    get mood() {
        if (this.busy) return 'thinking';
        return this.isOpen ? 'happy' : 'idle';
    }

    get fabClass() { return this.isOpen ? 'ab-fab ab-fab--open' : 'ab-fab'; }
    get fabLabel() { return this.label; }
    get fabTitle() {
        return this.isOpen ? 'Hide the assistant' : 'Ask Gus about this page';
    }
    get statusLabel() {
        return this.busy ? 'Working on it…' : 'GTM assistant';
    }

    connectedCallback() {
        // Only events carrying this tab's token are ours; without the check a
        // second rep's session would rewrite this page.
        subscribe(CONFIG_UPDATE_CHANNEL, -1, (msg) => {
            try {
                const payload = msg && msg.data && msg.data.payload;
                if (!payload || payload.Session_Token__c !== this.sessionToken) return;
                const changes = JSON.parse(payload.Updates_JSON__c || '{}');
                if (!Object.keys(changes).length) return;
                this.busy = false;
                this.dispatchEvent(new CustomEvent('agentdelta', { detail: { changes } }));
            } catch (e) {
                // eslint-disable-next-line no-console
                console.error('[maAgentBubble] platform-event delta:', e);
            }
        })
            .then((sub) => { this._sub = sub; })
            // eslint-disable-next-line no-console
            .catch((err) => { console.warn('[maAgentBubble] subscribe failed:', err); });
    }

    disconnectedCallback() {
        if (!this._sub) return;
        // eslint-disable-next-line no-console
        unsubscribe(this._sub).catch((err) => console.warn('[maAgentBubble] unsubscribe:', err));
        this._sub = null;
    }

    handleToggle() { this.isOpen = !this.isOpen; }

    // The change the assistant made is the page's to apply, not the bubble's,
    // so this passes it straight up.
    handleAgentDelta(event) {
        this.busy = false;
        this.dispatchEvent(new CustomEvent('agentdelta', { detail: event.detail }));
    }
}
