import { LightningElement, api, track } from 'lwc';
import { subscribe, unsubscribe } from 'lightning/empApi';

// The Agentforce path: the bot applies a change server-side and publishes it,
// rather than returning it in a chat reply. Both paths end at the same
// agentdelta event, so the page has one way to receive a change.
const CONFIG_UPDATE_CHANNEL = '/event/GTM_Config_Update__e';

/**
 * The assistant, as a bubble in the corner.
 *
 * It used to be a mode inside the Customize flyout: to reach it you opened a
 * form, then switched the form to something that was not a form. A bubble is
 * where people already look for an assistant, and it leaves the page visible
 * behind it, which matters when the assistant's whole job is changing that
 * page.
 */
// Who the assistant is when the page has not said. Every one of these is a
// content field on the page's Assistant section; these are the values a page
// falls back to before that section is filled in, not the values it uses.
const FALLBACK = {
    name: 'Gus',
    role: 'GTM Utility Sidekick',
    label: 'Ask Gus'
};

export default class GtmAgentBubble extends LightningElement {
    @api sessionToken = '';
    @api configId = '';

    /**
     * The assistant's persona, as content.
     *
     * Gus is this offering's character, not the framework's. A second offering
     * modelled on the same configurator template gets its own Assistant
     * section and can name, describe and brief its own helper without any of
     * this code changing.
     */
    @api assistantName = '';
    @api assistantRole = '';
    @api greeting = '';
    @api placeholder = '';

    /** Label on the collapsed bubble. */
    @api label = '';

    /**
     * Docked: shown in the flow of the page rather than fixed over it.
     *
     * The editor previews the assistant the same way it previews every other
     * section — in place, in the page. Fixed positioning escaped the preview
     * frame and floated the bubble over the editor itself, and an assistant
     * with no configuration behind it has nothing to answer, so docked is also
     * read-only.
     */
    @api docked = false;

    @track isOpen = false;
    @track busy = false;

    _sub = null;

    get name() { return this.assistantName || FALLBACK.name; }
    get role() { return this.assistantRole || FALLBACK.role; }

    get mood() {
        if (this.busy) return 'thinking';
        return this.isOpen ? 'happy' : 'idle';
    }

    get rootClass() { return this.docked ? 'ab-root ab-root--docked' : 'ab-root'; }
    /** Docked, the panel is the point, so it is never collapsed. */
    get panelOpen() { return this.docked || this.isOpen; }
    get panelLabel() { return `${this.name}, the ${this.role}`; }

    get fabClass() { return this.isOpen ? 'ab-fab ab-fab--open' : 'ab-fab'; }
    get fabLabel() { return this.label || FALLBACK.label; }
    get fabTitle() {
        return this.isOpen ? 'Hide the assistant' : `Ask ${this.name} about this page`;
    }
    get statusLabel() {
        return this.busy ? 'Working on it…' : this.role;
    }

    connectedCallback() {
        // Docked is a picture of the assistant in the editor. Subscribing
        // would have every open editor tab listening for deltas meant for a
        // live page, and acting on them.
        if (this.docked) return;
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
                console.error('[gtmAgentBubble] platform-event delta:', e);
            }
        })
            .then((sub) => { this._sub = sub; })
            // eslint-disable-next-line no-console
            .catch((err) => { console.warn('[gtmAgentBubble] subscribe failed:', err); });
    }

    disconnectedCallback() {
        if (!this._sub) return;
        // eslint-disable-next-line no-console
        unsubscribe(this._sub).catch((err) => console.warn('[gtmAgentBubble] unsubscribe:', err));
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
