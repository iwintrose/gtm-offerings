/**
 * Shared `lightning-datatable` custom-type cell: renders a row's Account or
 * Contact text with ONE consistent visual treatment (link-styled, left
 * aligned) regardless of whether the row has a real lookup to open -- the
 * bug this replaces was base SLDS `type: 'button'` rendering enabled vs.
 * `disabled` cells with different color/alignment (see docs/architecture/
 * gtm-link-stage-filter.md "Account/Contact cell" and gtm-assessments-table.md).
 *
 * Used exclusively via `gtmLinkDatatable`'s `customTypes.gtmLink` registration
 * (the documented `lightning-datatable` extension pattern); never mounted
 * standalone by a page.
 *
 * Contract (typeAttributes bound by the column definition):
 *   label     - display text (already precedence-resolved upstream)
 *   name      - row-action name to dispatch, e.g. 'openAccount' / 'openContact'
 *   disabled  - true when the row has no real lookup for this cell
 *   title     - tooltip text; ALWAYS rendered (interactive or not), so the
 *               "no account/contact on this link/assessment" messaging is
 *               never dropped, only its clickability changes
 *   targetId  - the id to open (Account/Contact id) when not disabled
 *   idField   - the row-object property name handleRowAction reads the id
 *               from downstream (e.g. 'accountId' or 'contactId') -- lets one
 *               shared cell type serve both the Account and Contact columns
 *               without hardcoding either field name here
 */
import { LightningElement, api } from 'lwc';

export default class GtmLinkCell extends LightningElement {
    @api value;
    @api typeAttributes;

    get label() {
        return (this.typeAttributes && this.typeAttributes.label) || this.value || '';
    }

    get titleText() {
        return (this.typeAttributes && this.typeAttributes.title) || '';
    }

    get isInteractive() {
        return !(this.typeAttributes && this.typeAttributes.disabled);
    }

    get cellClass() {
        return this.isInteractive
            ? 'slds-truncate gtm-link-cell gtm-link-cell_interactive'
            : 'slds-truncate gtm-link-cell gtm-link-cell_static';
    }

    get tabIndex() {
        return this.isInteractive ? '0' : '-1';
    }

    handleClick() {
        this.activate();
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ' || event.key === 'Spacebar') {
            event.preventDefault();
            this.activate();
        }
    }

    activate() {
        if (!this.isInteractive) return;
        const ta = this.typeAttributes || {};
        const idField = ta.idField;
        const row = idField ? { [idField]: ta.targetId } : {};
        this.dispatchEvent(
            new CustomEvent('rowaction', {
                bubbles: true,
                composed: true,
                detail: { action: { name: ta.name }, row }
            })
        );
    }
}
