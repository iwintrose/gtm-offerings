import { LightningElement, api } from 'lwc';

const COMPACT_BELOW_PX = 900;

/**
 * Shared page header bar: icon circle, eyebrow label, bold title, meta
 * subtitle line, a declarative `actions` array and a named "actions" slot.
 *
 * Wide (>= 900px of the header's own width): one lightning-button per action.
 * Compact (< 900px): one hamburger lightning-button-menu. Both variants fire
 * a single `headeraction` event with detail.name. Contract:
 * docs/architecture/gtm-page-header-layout.md (Addendum A).
 */
export default class GtmPageHeader extends LightningElement {
    @api iconName = '';
    @api eyebrow = '';
    @api title = '';
    @api meta = '';

    _actions = [];
    isCompact = false;
    _observer;

    @api
    get actions() {
        return this._actions;
    }
    set actions(value) {
        this._actions = Array.isArray(value)
            ? value.map((a) => ({
                  ...a,
                  variant: a.variant || 'neutral',
                  disabled: !!a.disabled
              }))
            : [];
    }

    get hasActions() {
        return this._actions.length > 0;
    }

    get showMenu() {
        return this.isCompact && this.hasActions;
    }

    get showButtons() {
        return !this.isCompact && this.hasActions;
    }

    get hdrClass() {
        return this.isCompact ? 'slds-page-header hdr hdr-compact' : 'slds-page-header hdr';
    }

    renderedCallback() {
        if (this._observer || typeof ResizeObserver === 'undefined') {
            return;
        }
        this._observer = new ResizeObserver((entries) => {
            const entry = entries && entries[0];
            if (!entry || !entry.contentRect) {
                return;
            }
            const compact = entry.contentRect.width < COMPACT_BELOW_PX;
            if (compact !== this.isCompact) {
                this.isCompact = compact;
            }
        });
        this._observer.observe(this.template.host);
    }

    disconnectedCallback() {
        if (this._observer) {
            this._observer.disconnect();
            this._observer = undefined;
        }
    }

    handleActionClick(event) {
        this.fire(event.currentTarget.dataset.name);
    }

    handleMenuSelect(event) {
        this.fire(event.detail.value);
    }

    fire(name) {
        const action = this._actions.find((a) => a.name === name);
        if (!action || action.disabled) {
            return;
        }
        this.dispatchEvent(new CustomEvent('headeraction', { detail: { name } }));
    }
}
