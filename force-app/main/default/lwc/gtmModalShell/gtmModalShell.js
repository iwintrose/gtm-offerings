import { LightningElement, api } from 'lwc';

/**
 * Shared side-sheet modal shell (scrim + sliding sheet + close control +
 * title). Owns presentation only -- consumer content is slotted in via the
 * default slot, and any domain events (`created`, `done`, `configsaved`,
 * etc.) stay owned by that slotted content, never touched here. See
 * docs/architecture/gtm-modal-shell.md for the full contract.
 */
export default class GtmModalShell extends LightningElement {
    @api isOpen = false;
    @api title = '';
    @api chromeOffset = false;

    /** Distance from the true page top to where normal content begins --
     * only measured/used when chromeOffset is true. Mirrors
     * gtmConfigWizard's _standaloneTopOffset fallback. Not exercised by
     * this issue's only consumer (gtmRepDirectPicker), which never sets
     * chrome-offset -- kept as a documented no-op path for the future
     * gtmConfigWizard migration. */
    _topOffset = 106;

    connectedCallback() {
        if (this.chromeOffset) {
            // Deferred one tick: at connectedCallback the host isn't laid
            // out yet (getBoundingClientRect would read 0,0).
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this._measureChromeOffset(), 0);
        }
    }

    _measureChromeOffset() {
        if (!this.chromeOffset) return;
        try {
            const rect = this.template.host.getBoundingClientRect();
            const offset = Math.round(rect.top + window.scrollY);
            if (offset > 0) this._topOffset = offset;
        } catch (e) {
            // keep the fallback
        }
    }

    get scrimClass() {
        return this.isOpen ? 'gms-scrim open' : 'gms-scrim';
    }

    get sheetClass() {
        return this.isOpen ? 'gms-sheet open' : 'gms-sheet';
    }

    get sheetStyle() {
        return this.chromeOffset ? `top:${this._topOffset}px;` : '';
    }

    handleScrimClick() {
        this._fireClose();
    }

    handleCloseClick() {
        this._fireClose();
    }

    _fireClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}
