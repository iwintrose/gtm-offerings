import { LightningElement, api } from 'lwc';
import searchContacts from '@salesforce/apex/GtmSavedConfigurationController.searchContacts';
import createRepDirectAssessment from '@salesforce/apex/GtmSavedConfigurationController.createRepDirectAssessment';

/**
 * The "New assessment (no page)" entry point -- opens straight to a real
 * Contact/Account picker (reusing GtmSavedConfigurationController's own
 * searchContacts(), the exact same search gtmConfigWizard's Step 1 uses) and,
 * on confirm, creates a pageless GTM_Saved_Configuration__c record
 * (Presentation_Stage__c = 'Rep_Direct') attributed to a real, picked
 * Contact/Account -- never a typed name/email. This is the supported
 * replacement for the accidental bare-/configurator-URL "direct booking"
 * path (see gtmConfigurator.js's accessBlocked, now closed).
 *
 * Deliberately does NOT offer a "type a new contact" fallback the way
 * gtmConfigWizard's Step 1 confirm-or-create gate does -- that typed-text
 * path is exactly the duplicate-creation behavior this flow exists to
 * replace. A rep whose contact doesn't exist yet creates it in Sales Cloud
 * first, then searches for it here.
 */
export default class GtmRepDirectPicker extends LightningElement {
    @api isOpen = false;
    /** Offering__c is required schema-wide on GTM_Saved_Configuration__c --
     * this is the same offering key the "New engagement link" launcher
     * already resolves (see gtmOverview.handleNewEngagementLink) before
     * opening a picker, not a rule invented by this component. */
    @api offeringKey = '';

    _searchTerm = '';
    _results = [];
    _selected = null;
    _searching = false;
    _saving = false;
    _error = '';
    _searchTimer;
    _searchToken = 0;

    get hasResults() {
        return this._results.length > 0;
    }

    get results() {
        return this._results.map((c) => ({
            id: c.contactId,
            summary: c.accountName ? `${c.name} · ${c.accountName}` : c.name
        }));
    }

    get hasSelected() {
        return !!this._selected;
    }

    get selectedSummary() {
        if (!this._selected) return '';
        return this._selected.accountName
            ? `${this._selected.name} · ${this._selected.accountName}`
            : this._selected.name;
    }

    get confirmDisabled() {
        return !this._selected || this._saving;
    }

    get searchValue() {
        return this._searchTerm;
    }

    handleSearchInput(event) {
        this._searchTerm = event.currentTarget.value;
        this._error = '';
        if (this._searchTimer) window.clearTimeout(this._searchTimer);
        const term = this._searchTerm.trim();
        if (term.length < 2) {
            this._results = [];
            return;
        }
        this._searching = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimer = window.setTimeout(() => this._runSearch(term), 300);
    }

    async _runSearch(term) {
        const token = ++this._searchToken;
        try {
            const rows = await searchContacts({ searchTerm: term });
            if (token !== this._searchToken) return;
            this._results = rows || [];
        } catch (e) {
            if (token !== this._searchToken) return;
            this._results = [];
        } finally {
            if (token === this._searchToken) this._searching = false;
        }
    }

    handleSelect(event) {
        const id = event.currentTarget.dataset.id;
        const match = this._results.find((c) => c.contactId === id);
        if (!match) return;
        this._selected = {
            id: match.contactId,
            name: match.name,
            email: match.email,
            accountId: match.accountId,
            accountName: match.accountName
        };
        this._results = [];
        this._searchTerm = '';
    }

    handleChangeSelection() {
        this._selected = null;
    }

    handleConfirm() {
        if (!this._selected || this._saving) return;
        this._saving = true;
        this._error = '';
        createRepDirectAssessment({
            input: {
                contactId: this._selected.id,
                accountId: this._selected.accountId || null,
                offering: this.offeringKey
            }
        })
            .then((recordId) => {
                this._saving = false;
                this.dispatchEvent(new CustomEvent('created', { detail: { recordId } }));
                this.handleClose();
            })
            .catch((e) => {
                this._saving = false;
                this._error = (e && e.body && e.body.message) || 'We could not start this assessment.';
            });
    }

    handleClose() {
        this._searchTerm = '';
        this._results = [];
        this._selected = null;
        this._error = '';
        this.dispatchEvent(new CustomEvent('close'));
    }
}
