import { LightningElement, api, track } from 'lwc';
import getLinkSitemap from '@salesforce/apex/MaHomeSnapshotController.getLinkSitemap';

/**
 * What the recipient of this link actually read.
 *
 * The record page already lists the events. A list of events is a log: you read
 * it top to bottom and reconstruct the visit in your head. This draws the page
 * instead — every chapter in the order the page shows them, how many people
 * reached each, how long they stayed, and the point where reading stops.
 *
 * The chapters nobody reached are the finding, so they are drawn too, greyed
 * rather than omitted: a map with the unread parts left out is a map that can
 * only tell you good news.
 */
export default class MaLinkSitemap extends LightningElement {
    @api recordId;

    @track nodes = [];
    @track loading = true;
    @track error = '';

    connectedCallback() { this.load(); }

    /** Re-read when the tab is looked at again, rather than making someone
     *  find a button to ask for what they can already see is stale. */
    renderedCallback() {
        if (this._focusBound) return;
        this._focusBound = true;
        this._onFocus = () => { if (document.visibilityState === 'visible') this.load(); };
        window.addEventListener('focus', this._onFocus);
        document.addEventListener('visibilitychange', this._onFocus);
    }

    disconnectedCallback() {
        if (!this._onFocus) return;
        window.removeEventListener('focus', this._onFocus);
        document.removeEventListener('visibilitychange', this._onFocus);
    }

    load() {
        if (!this.recordId) { this.loading = false; return; }
        return getLinkSitemap({ configId: this.recordId })
            .then((rows) => {
                const peak = (rows || []).reduce((m, r) => Math.max(m, r.readers || 0), 0);
                this.nodes = (rows || []).map((r) => {
                    const readers = r.readers || 0;
                    return {
                        key: r.sectionKey,
                        label: r.label || r.sectionKey,
                        readers,
                        readersLabel: readers === 1 ? '1 reader' : `${readers} readers`,
                        dwellLabel: r.avgDwell > 0 ? `${r.avgDwell}s each` : '',
                        clicksLabel: r.clicks > 0
                            ? (r.clicks === 1 ? '1 click' : `${r.clicks} clicks`)
                            : '',
                        // Scaled against the best-read chapter, not against the
                        // number of links: the shape of attention is the point,
                        // and an absolute scale flattens it to nothing.
                        barStyle: `width: ${peak ? Math.max(2, (readers / peak) * 100) : 0}%`,
                        rowClass: readers === 0 ? 'node node--cold' : 'node',
                        barClass: r.isLastSeen ? 'bar bar--last' : 'bar',
                        isLastSeen: r.isLastSeen === true
                    };
                });
                this.error = '';
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || 'Activity could not be loaded.';
            })
            .finally(() => { this.loading = false; });
    }

    get hasNodes() { return this.nodes.length > 0; }
    get showEmpty() { return !this.loading && !this.error && !this.hasNodes; }

    /** Said once, above the map, so the reader knows what they are looking at
     *  before they interpret a bar. */
    get summary() {
        const read = this.nodes.filter((n) => n.readers > 0);
        if (!read.length) return 'Nobody has opened this link yet.';
        const stop = this.nodes.find((n) => n.isLastSeen);
        const total = this.nodes.length;
        const got = read.length;
        if (got === total) return 'Read all the way through.';
        return stop
            ? `Read as far as “${stop.label}” — ${total - got} of ${total} chapters never reached.`
            : `${got} of ${total} chapters reached.`;
    }
}
