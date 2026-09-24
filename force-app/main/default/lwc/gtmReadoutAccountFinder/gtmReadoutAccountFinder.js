import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import ACCOUNT_NAME_FIELD from '@salesforce/schema/Account.Name';
import getContactsWithRequests from '@salesforce/apex/GtmReadoutController.getContactsWithRequests';
import searchAccountsAndContacts from '@salesforce/apex/GtmAccountContactSearchController.searchAccountsAndContacts';

/** Debounce window before firing the unified search Apex call, and the
 *  minimum typed length before it fires at all (issue-gtm-assessments-
 *  account-contact-trail follow-up -- see
 *  docs/architecture/gtm-unified-account-contact-search.md). */
const SEARCH_DEBOUNCE_MS = 300;
const SEARCH_MIN_CHARS = 2;

/**
 * The Assessments tab's "By Account or Contact" browse mode
 * (issue-gtm-assessments-account-contact-trail): an Account -> Contact ->
 * Assessment Request Miller-columns trail, replicating gtmRepLinkFinder's
 * existing Account -> Contact -> Link pattern as closely as possible (same
 * column/crumb structure and CSS class naming conventions, `rf-` prefixed
 * here instead of `rlf-` to avoid colliding if both components are ever
 * rendered on the same page at once).
 *
 * Unlike gtmRepLinkFinder, this component does not render a "view" step
 * itself -- picking a request dispatches a `selectrequest` event and lets
 * the parent (gtmReadoutsOverview) render the existing gtmReadoutWorkspace
 * inline detail it already owns for the flat "All Assessments" grid, so
 * there is exactly one place that embeds that component, not two
 * (WORKTREE_SCOPE.md: "Do not touch gtmReadoutWorkspace internals").
 */
export default class GtmReadoutAccountFinder extends LightningElement {
    // undefined, not '' -- see gtmRepLinkFinder's own accountId doc comment
    // for why: an empty string is still a value to the wire service.
    @track accountId;
    @track accountName = '';
    @track loadingRequests = false;
    @track loadError = '';
    @track contactGroups = [];
    @track selectedContactId = '';

    // -------------------------------------------------- unified search
    //
    // Replaces the original Account-only lightning-record-picker first
    // step (issue-gtm-assessments-account-contact-trail follow-up -- see
    // docs/architecture/gtm-unified-account-contact-search.md):
    // lightning-record-picker only supports one object-api-name, so a
    // mixed Account+Contact result set needs a plain input + custom
    // dropdown backed by GtmAccountContactSearchController instead.
    @track searchTerm = '';
    @track searchResults = [];
    @track searching = false;
    @track showSearchResults = false;
    @track searchError = '';
    /** What to show in the read-only "picked" summary once something from
     *  the search has been chosen -- the Account name if an Account result
     *  was picked, or the Contact name if a Contact result was picked
     *  (accountName alone would be wrong/blank in the Contact case until
     *  the getRecord wire above resolves it, and even then would show the
     *  Account, not what the rep actually searched for). */
    @track pickedLabel = '';
    _searchDebounceId;

    get hasPicked() {
        return !!this.accountId;
    }

    /** pickedLabel is only set by a direct search-result click; a restored
     *  (URL/tile) trail has no such click, so fall back to accountName
     *  (populated by the getRecord wire above) once it resolves. */
    get pickedSummaryLabel() {
        return this.pickedLabel || this.accountName;
    }

    get hasSearchResults() {
        return this.searchResults.length > 0;
    }

    /** Only render the "no matches" row once a search actually ran and
     *  came back empty -- not on initial render, and not while a debounced
     *  keystroke is still pending. */
    get showNoResults() {
        return this.showSearchResults && !this.searching && !this.hasSearchResults && !this.searchError;
    }

    get searchResultRows() {
        return this.searchResults.map((r) => ({
            key: `${r.type}-${r.recordId}`,
            recordId: r.recordId,
            type: r.type,
            accountId: r.accountId,
            label: r.label,
            subLabel: r.subLabel,
            isAccount: r.type === 'Account',
            iconClass: r.type === 'Account' ? 'raf-result-icon raf-result-icon--account' : 'raf-result-icon raf-result-icon--contact',
            iconName: r.type === 'Account' ? 'standard:account' : 'standard:contact'
        }));
    }

    /** Debounced (300ms), and gated at 2+ characters client-side -- see
     *  GtmAccountContactSearchController.searchAccountsAndContacts's own
     *  doc comment for why the server independently re-checks the same
     *  minimum rather than trusting this gate alone. */
    handleSearchInput(event) {
        const term = event.target.value || '';
        this.searchTerm = term;
        if (this._searchDebounceId) {
            clearTimeout(this._searchDebounceId);
            this._searchDebounceId = undefined;
        }
        if (term.trim().length < SEARCH_MIN_CHARS) {
            this.searchResults = [];
            this.showSearchResults = false;
            this.searching = false;
            return;
        }
        this._searchDebounceId = setTimeout(() => {
            this.runSearch(term);
        }, SEARCH_DEBOUNCE_MS);
    }

    runSearch(term) {
        this.searching = true;
        this.searchError = '';
        searchAccountsAndContacts({ searchTerm: term })
            .then((rows) => {
                this.searchResults = rows || [];
                this.showSearchResults = true;
            })
            .catch((e) => {
                this.searchError = (e && e.body && e.body.message) || 'Search failed.';
                this.searchResults = [];
                this.showSearchResults = true;
            })
            .finally(() => { this.searching = false; });
    }

    /** Picking either an Account or a Contact result -- see the class doc
     *  comment / architecture doc for why a Contact result skips straight
     *  to the request list instead of the intermediate Contact-picking
     *  step. */
    handleSelectSearchResult(event) {
        const id = event.currentTarget.dataset.id;
        const row = this.searchResults.find((r) => r.recordId === id);
        if (!row) return;
        this.clearSearchState();
        if (row.type === 'Account') {
            this.pickedLabel = row.label;
            this.selectAccount(row.recordId);
        } else {
            this.pickedLabel = row.label;
            this.selectContactDirect(row);
        }
    }

    clearSearchState() {
        if (this._searchDebounceId) {
            clearTimeout(this._searchDebounceId);
            this._searchDebounceId = undefined;
        }
        this.searchTerm = '';
        this.searchResults = [];
        this.showSearchResults = false;
        this.searchError = '';
    }

    /** Same as the old handleAccountChange's body, minus the DOM event --
     *  the shared entry point both an Account search-result pick and (via
     *  restoreTrailState) URL restoration end up funneling through. */
    selectAccount(accountId) {
        this.accountId = accountId || undefined;
        this.accountName = '';
        this.contactGroups = [];
        this.selectedContactId = '';
        this.loadError = '';
        this.writeTrailStateToUrl();
        if (!this.accountId) return;

        this.loadingRequests = true;
        getContactsWithRequests({ accountId: this.accountId })
            .then((rows) => { this.contactGroups = rows || []; })
            .catch((e) => {
                this.loadError = (e && e.body && e.body.message) || 'Contacts could not be loaded.';
            })
            .finally(() => { this.loadingRequests = false; });
    }

    /** A Contact search result already resolves both the Account and
     *  Contact levels -- load the Account's Contact groups (needed either
     *  way, for the crumb trail and "choose a different contact" back nav)
     *  and, once loaded, select this Contact directly rather than making
     *  the rep pick it again from the list. */
    selectContactDirect(row) {
        this.accountId = row.accountId || undefined;
        this.accountName = '';
        this.contactGroups = [];
        this.selectedContactId = '';
        this.loadError = '';
        if (!this.accountId) return;

        this.loadingRequests = true;
        getContactsWithRequests({ accountId: this.accountId })
            .then((rows) => {
                this.contactGroups = rows || [];
                const group = this.contactGroups.find((g) => g.contactId === row.recordId);
                this.selectedContactId = group ? row.recordId : '';
                this.writeTrailStateToUrl();
            })
            .catch((e) => {
                this.loadError = (e && e.body && e.body.message) || 'Contacts could not be loaded.';
            })
            .finally(() => { this.loadingRequests = false; });
    }

    handleSearchAgain() {
        this.accountId = undefined;
        this.accountName = '';
        this.contactGroups = [];
        this.selectedContactId = '';
        this.loadError = '';
        this.pickedLabel = '';
        this.clearSearchState();
        this.writeTrailStateToUrl();
    }

    @wire(getRecord, { recordId: '$accountId', fields: [ACCOUNT_NAME_FIELD] })
    wiredAccount({ data }) {
        if (data) {
            this.accountName = getFieldValue(data, ACCOUNT_NAME_FIELD) || '';
        }
    }

    // -------------------------------------------------------- url state
    //
    // Mirrors gtmRepLinkFinder's own "?c__rlfAccountId=...&c__rlfContactId=..."
    // mechanism so a refresh mid-trail (Account picked, or Account+Contact
    // picked) restores instead of bouncing back to the empty first step.
    // Namespaced "raf" (Readout Account Finder) so it can never collide with
    // gtmRepLinkFinder's own "rlf" state on the same URL, or with
    // gtmReadoutsOverview's own "c__assessmentRequestId"/"c__browseMode"
    // params for the selected-request/mode state it owns itself.
    //
    // Does not persist a selected request: picking one immediately hands
    // off to the parent's own selection state (c__assessmentRequestId etc.),
    // which is what survives a refresh once a request is open -- this
    // component's own URL state only needs to cover its two browsing steps.
    _restoredAccountId = '';
    _restoredContactId = '';

    @wire(CurrentPageReference)
    captureTrailState(ref) {
        const state = (ref && ref.state) || {};
        const accountId = state.c__rafAccountId || '';
        if (!accountId) return;
        if (this._restoredAccountId === accountId) return;
        this._restoredAccountId = accountId;
        this._restoredContactId = state.c__rafContactId || '';
        this.restoreTrailState(accountId);
    }

    restoreTrailState(accountId) {
        this.accountId = accountId;
        this.accountName = '';
        this.pickedLabel = '';
        this.contactGroups = [];
        this.selectedContactId = '';
        this.loadError = '';
        this.loadingRequests = true;
        getContactsWithRequests({ accountId })
            .then((rows) => {
                this.contactGroups = rows || [];
                if (!this._restoredContactId) return;
                const group = this.contactGroups.find((g) => g.contactId === this._restoredContactId);
                if (!group) return;
                this.selectedContactId = this._restoredContactId;
            })
            .catch((e) => {
                this.loadError = (e && e.body && e.body.message) || 'Contacts could not be loaded.';
            })
            .finally(() => { this.loadingRequests = false; });
    }

    /** Best-effort only, same pattern as gtmRepLinkFinder's
     *  writeDrillStateToUrl -- a sandbox that blocks History mutation
     *  should still work, it just won't survive a refresh. */
    writeTrailStateToUrl() {
        try {
            const url = new URL(window.location.href);
            const params = [
                ['c__rafAccountId', this.accountId || ''],
                ['c__rafContactId', this.selectedContactId || '']
            ];
            params.forEach(([key, value]) => {
                if (value) {
                    url.searchParams.set(key, value);
                } else {
                    url.searchParams.delete(key);
                }
            });
            window.history.replaceState(window.history.state, '', url.toString());
        } catch (e) {
            // best-effort -- see comment above
        }
    }

    // ------------------------------------------------------------- steps

    get step() {
        if (this.selectedContactId) return 'request';
        if (this.accountId) return 'contact';
        return 'account';
    }

    get isAccountStep() { return this.step === 'account'; }
    get isContactStep() { return this.step === 'contact'; }
    get isRequestStep() { return this.step === 'request'; }

    get isContactVisible() { return !!this.accountId; }
    get isRequestVisible() { return !!this.selectedContactId; }

    get contactColumnClass() {
        return this.isContactStep ? 'raf-col' : 'raf-col raf-col--compact';
    }

    get crumbs() {
        const out = [{ key: 'account', label: 'Account', disabled: this.isAccountStep }];
        if (this.accountId) {
            out.push({
                key: 'contact',
                label: this.accountName || this.pickedLabel || 'Contact',
                disabled: this.isAccountStep
            });
        }
        if (this.selectedContactId) {
            out.push({
                key: 'request',
                label: this.selectedContactName || 'Assessment',
                disabled: this.isRequestStep
            });
        }
        return out;
    }

    get hasCrumbTrail() {
        return this.crumbs.length > 1;
    }

    handleCrumbClick(event) {
        const key = event.currentTarget.dataset.key;
        if (key === 'account') this.handleBackToAccount();
        else if (key === 'contact') this.handleBackToContact();
    }

    // ------------------------------------------------------------ account

    get hasContactGroups() {
        return this.contactGroups.length > 0;
    }

    get contactRows() {
        return this.contactGroups.map((g) => ({
            contactId: g.contactId,
            contactName: g.contactName,
            requestCount: g.requests.length,
            requestCountLabel: g.requests.length === 1 ? '1 assessment' : `${g.requests.length} assessments`
        }));
    }

    // ------------------------------------------------------------ contact

    handleSelectContact(event) {
        this.selectedContactId = event.currentTarget.dataset.id;
        this.writeTrailStateToUrl();
    }

    get selectedGroup() {
        return this.contactGroups.find((g) => g.contactId === this.selectedContactId) || null;
    }

    get selectedContactName() {
        return this.selectedGroup ? this.selectedGroup.contactName : '';
    }

    get requestRows() {
        const requests = this.selectedGroup ? this.selectedGroup.requests : [];
        return requests.map((r) => ({
            recordId: r.recordId,
            company: r.company,
            offeringLabel: formatLabel(r.offeringKey),
            statusLabel: r.status || '',
            statusClass: `raf-status raf-status--${(r.status || '').toLowerCase().replace(/\s+/g, '-')}`,
            requesterName: r.requesterName,
            createdLabel: r.createdDate ? new Date(r.createdDate).toLocaleDateString() : '',
            hasReadout: !!r.readoutId,
            _raw: r
        }));
    }

    get hasRequestRows() {
        return this.requestRows.length > 0;
    }

    // ---------------------------------------------------------- request

    /** Hands off to the parent's own gtmReadoutWorkspace embed -- this
     *  component never renders that itself (see class doc comment). */
    handleSelectRequest(event) {
        const id = event.currentTarget.dataset.id;
        const row = this.requestRows.find((r) => r.recordId === id);
        if (!row) return;
        this.dispatchEvent(new CustomEvent('selectrequest', {
            detail: {
                assessmentRequestId: row.recordId,
                readoutId: row._raw.readoutId || '',
                offeringKey: row._raw.offeringKey || ''
            }
        }));
    }

    // ------------------------------------------------------------ back nav

    handleBackToAccount() {
        this.accountId = undefined;
        this.accountName = '';
        this.pickedLabel = '';
        this.contactGroups = [];
        this.selectedContactId = '';
        this.loadError = '';
        this.clearSearchState();
        this.writeTrailStateToUrl();
    }

    handleBackToContact() {
        this.selectedContactId = '';
        this.writeTrailStateToUrl();
    }
}

/** "migration-accelerator" -> "Migration Accelerator". Same rule
 *  gtmRepLinkFinder/gtmSavedLinksBar use for the same reason. */
function formatLabel(slug) {
    if (!slug) return slug;
    return slug
        .split(/[-_]/)
        .map((w) => (w ? w[0].toUpperCase() + w.slice(1) : w))
        .join(' ');
}
