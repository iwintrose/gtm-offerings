import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getAssessmentPage from '@salesforce/apex/GtmAssessmentListController.getAssessmentPage';
import getAssessmentFilterOptions from '@salesforce/apex/GtmAssessmentListController.getAssessmentFilterOptions';
import {
    readFilterState,
    buildNavigateArgs,
    mergeLocationState
} from 'c/gtmFilterUrlState';
import {
    TABLE_COLUMNS,
    PAGE_SIZE,
    buildFilterConfig,
    rawOfferingValues,
    rawIds,
    toPartyOption,
    mergePartyOptions,
    mapRow,
    buildQuery,
    toPlain,
    hasActiveFilters,
    formatTotal,
    sortKeyForField,
    fieldForSortKey
} from 'c/gtmAssessmentsTableModel';

/**
 * "All Assessments" table over GTM_Assessment_Request__c (issue
 * assessments-tab-filter; contract docs/architecture/gtm-assessments-table.md).
 * One row per assessment submission with its latest readout's status joined
 * on, in a lightning-datatable (server-side sort, infinite loading, page size
 * 50), narrowed by the shared gtmFilterBar. Every filter, preset, sort and
 * count definition is server-side in GtmAssessmentListController; this
 * component only declares the filter config and wires events to the Apex call.
 * It replaced the earlier readout-grain card grid.
 *
 * Filter state lives in the URL (c__astatus, c__atier, c__areadout, c__arange,
 * c__aoffering, c__apreset) through the shared gtmFilterUrlState helper:
 * read from @wire(CurrentPageReference) -- BEFORE the c__assessmentRequestId
 * early return below -- and written with NavigationMixin.Navigate(replace)
 * using mergeLocationState so it never clobbers this component's own
 * selection params. Those (c__assessmentRequestId, c__readoutId,
 * c__offeringKey, c__repDirectId) are still written by
 * writeSelectionToUrl() with history.replaceState, unchanged.
 *
 * Opening an assessment: lightning-datatable has no whole-row click, so the
 * Assessment (AR-####) button cell is the open action (recorded deviation,
 * section 1.3 of the contract). It renders gtmReadoutWorkspace INLINE in place
 * of the table with the request id, the latest readout id (blank when none
 * yet) and the offering key.
 *
 * Account and Contact are ordinary searchable filters (c__aacct, c__acontact)
 * whose options are served by getAssessmentFilterOptions (only parties with a
 * visible assessment), fetched on a debounced search text and, for restored
 * deep links, with includeIds so a selected id is labelled. They replaced the
 * former "By Account or Contact" browse mode; legacy deep links still work:
 * c__browseMode is ignored on read (and dropped on the next URL write), and
 * c__rafAccountId / c__rafContactId map to the Account / Contact filters.
 *
 * Rep-Direct entry point (issue
 * rep-initiated-assessment-no-page-2-share-and-continue): gtmOverview deep-links
 * here with "c__repDirectId=<GTM_Saved_Configuration__c Id>", which opens
 * c-gtm-rep-direct-share in a modal in front of the table.
 *
 * No c-gtm-page-header banner change here: it is unchanged and Refresh lives
 * in its actions slot.
 */

/** How long an older page-reference echo is ignored after we navigate. */
const ECHO_GUARD_MS = 3000;
/** Debounce for the server-backed Account/Contact option search. */
export const SEARCH_DEBOUNCE_MS = 300;
const PARTY_KINDS = [
    { kind: 'account', key: 'account', param: 'c__aacct', legacy: 'c__rafAccountId' },
    { kind: 'contact', key: 'contact', param: 'c__acontact', legacy: 'c__rafContactId' }
];
const LEGACY_KEYS = ['c__browseMode', 'c__rafAccountId', 'c__rafContactId'];

/** Legacy deep links -> the new filter params (a new param already present wins). */
function mapLegacyState(state) {
    const out = { ...(state || {}) };
    PARTY_KINDS.forEach((p) => {
        if (out[p.legacy] && !out[p.param]) out[p.param] = out[p.legacy];
    });
    return out;
}
function hasLegacy(state) {
    return LEGACY_KEYS.some((k) => state && state[k]);
}

/** Order-independent signature of a filter values map. */
function valuesSig(values) {
    const v = values || {};
    return JSON.stringify(Object.keys(v).sort().map((k) => [k, v[k]]));
}

export default class GtmReadoutsOverview extends NavigationMixin(LightningElement) {
    @track rows = [];
    totalCount = 0;
    totalIsCapped = false;
    offeringOptions = [];
    filterValues = {};
    filterConfig = buildFilterConfig([], []);
    columns = TABLE_COLUMNS;
    sortBy = '';
    sortDir = '';
    @track isLoadingMore = false;
    hasLoaded = false;
    @track loadError = '';
    @track isLoading = true;
    @track selectedAssessmentRequestId = '';
    @track selectedReadoutId = '';
    @track selectedOfferingKey = '';
    /** issue-102-1-engagement-links-landing: true only when the incoming
     *  navigation carried c__focusReadoutTab -- c-gtm-assessment-detail's
     *  "Open the readout" forward action, standalone mode. Threaded straight
     *  through to gtmReadoutWorkspace's initial-tab so THAT one navigation
     *  lands on the Readout tab; every other way of landing here (a row
     *  click, the URL round-trips below) explicitly clears it back to false
     *  so gtmReadoutWorkspace's own refinement #3 default (always Assessment
     *  first) is untouched for those origins. See
     *  docs/architecture/gtm-readout-workspace.md's "Default-active-tab
     *  logic" section. */
    @track focusReadoutTab = false;
    /** GTM_Saved_Configuration__c Id of a just-created Rep_Direct record,
     *  opened in the modal -- see class doc comment above. Blank means the
     *  modal is closed. */
    @track repDirectModalId = '';

    _pageRef;
    _rawOfferings = [];
    _seq = 0;
    _partyFetched = { account: [], contact: [] };
    _partyKnown = { account: {}, contact: {} };
    _partyRaw = { account: [], contact: [] };
    _partyTerm = { account: '', contact: '' };
    _partySeq = { account: 0, contact: 0 };
    _partyTimer = {};
    _navSig = null;
    _navAt = 0;
    _navTimer = null;

    connectedCallback() {
        // The wire below normally fires right after this with the same state,
        // which is idempotent (no second fetch). Reading the filters from the
        // location here only avoids a wasted unfiltered first fetch on a
        // deep link that carries filter params.
        const initial = mergeLocationState({});
        const mapped = mapLegacyState(initial);
        this._rawOfferings = rawOfferingValues(mapped);
        this.setPartyRaw(mapped);
        this.filterConfig = this.makeConfig(this._rawOfferings);
        this.filterValues = readFilterState(mapped, this.filterConfig);
        this.loadAssessments();
        PARTY_KINDS.forEach((p) => this.loadPartyOptions(p.kind));
    }

    disconnectedCallback() {
        clearTimeout(this._navTimer);
        Object.keys(this._partyTimer).forEach((k) => clearTimeout(this._partyTimer[k]));
    }

    setPartyRaw(state) {
        PARTY_KINDS.forEach((p) => {
            this._partyRaw[p.kind] = rawIds(state, p.param);
        });
    }

    /** Selected/restored ids of one kind: the URL ones plus the current values. */
    selectedParty(kind) {
        const p = PARTY_KINDS.find((x) => x.kind === kind);
        const cur = this.filterValues && Array.isArray(this.filterValues[p.key]) ? this.filterValues[p.key] : [];
        return [...new Set([...this._partyRaw[kind], ...cur.map(String)])];
    }

    makeConfig(rawOfferings) {
        const party = {};
        PARTY_KINDS.forEach((p) => {
            party[p.kind] = mergePartyOptions(this._partyFetched[p.kind], this.selectedParty(p.kind), this._partyKnown[p.kind]);
        });
        return buildFilterConfig(this.offeringOptions, rawOfferings, party);
    }

    /** Fetch Account/Contact options for the search text; restored ids ride in includeIds. */
    loadPartyOptions(kind) {
        const seq = ++this._partySeq[kind];
        const requested = Array.from(this.selectedParty(kind).slice(0, 50), (i) => String(i));
        let call;
        try {
            call = getAssessmentFilterOptions(
                toPlain({
                    kind: String(kind),
                    searchTerm: String(this._partyTerm[kind] || ''),
                    includeIds: requested
                })
            );
        } catch (e) {
            return Promise.resolve();
        }
        return Promise.resolve(call)
            .then((list) => {
                if (seq !== this._partySeq[kind]) return;
                const opts = (list || []).map(toPartyOption);
                opts.forEach((o) => {
                    this._partyKnown[kind][o.value] = o;
                });
                this._partyFetched[kind] = opts;
                // The server returns an id only when it exists and is visible. A requested id
                // that came back unlabelled is stale (deleted record, bad id): drop it, or the
                // list would keep filtering on it and return zero rows forever.
                const returned = new Set(opts.map((o) => String(o.value)));
                const stale = requested.filter((id) => !returned.has(id) && !this._partyKnown[kind][id]);
                if (stale.length) this.dropStaleParty(kind, stale);
                this.filterConfig = this.makeConfig(this._rawOfferings);
            })
            .catch(() => {
                // Options are a convenience: keep whatever the bar already has.
            });
    }

    /** Remove ids the server no longer knows from the raw list and the filter value; reload. */
    dropStaleParty(kind, staleIds) {
        const p = PARTY_KINDS.find((x) => x.kind === kind);
        const gone = new Set(staleIds);
        this._partyRaw[kind] = this._partyRaw[kind].filter((id) => !gone.has(id));
        const cur = this.filterValues && Array.isArray(this.filterValues[p.key]) ? this.filterValues[p.key] : [];
        const kept = cur.map(String).filter((id) => !gone.has(id));
        if (kept.length === cur.length) return;
        const next = { ...this.filterValues };
        if (kept.length) next[p.key] = kept;
        else delete next[p.key];
        this.applyFilters(next);
    }

    /** Debounced server search from the bar's additive filtersearch event. */
    handleFilterSearch(event) {
        const { key, value } = event.detail || {};
        const p = PARTY_KINDS.find((x) => x.key === key);
        if (!p) return;
        this._partyTerm[p.kind] = value || '';
        clearTimeout(this._partyTimer[p.kind]);
        this._partyTimer[p.kind] = setTimeout(() => this.loadPartyOptions(p.kind), SEARCH_DEBOUNCE_MS);
    }

    @wire(CurrentPageReference)
    capturePageRef(ref) {
        this._pageRef = ref;
        const state = (ref && ref.state) || {};
        // Filters are parsed BEFORE the early return below: a filter-only
        // state has no c__assessmentRequestId.
        this.syncFiltersFromState(state);
        if (state.c__repDirectId) {
            this.repDirectModalId = state.c__repDirectId;
        }
        if (!state.c__assessmentRequestId) return;
        this.selectedAssessmentRequestId = state.c__assessmentRequestId;
        this.selectedReadoutId = state.c__readoutId || '';
        this.selectedOfferingKey = state.c__offeringKey || '';
        this.focusReadoutTab = !!state.c__focusReadoutTab;
    }

    /** initial-tab passed to gtmReadoutWorkspace -- see focusReadoutTab's
     *  own doc comment above. */
    get initialWorkspaceTab() {
        return this.focusReadoutTab ? 'readout' : '';
    }

    /** A re-fired page reference with unchanged filters must not refetch. A reference
     *  that is OLDER than our own pending navigation (its echo arrives after a newer
     *  pick) is ignored, or it would reset the filter and lose ticks (race R-A). */
    syncFiltersFromState(wiredState) {
        // The wired state can lag the URL (cold load, or an echo older than the URL): the
        // location's c__ params overlay it, exactly as writeFiltersToUrl already does, so a
        // reference without the params never resets filters the URL still carries.
        const merged = mergeLocationState(wiredState);
        const legacy = hasLegacy(merged);
        const state = mapLegacyState(merged);
        const raw = rawOfferingValues(state);
        const prevPartyRaw = { account: this._partyRaw.account, contact: this._partyRaw.contact };
        this.setPartyRaw(state);
        const config = this.makeConfig(raw);
        const values = readFilterState(state, config);
        if (this._navSig !== null) {
            const sig = valuesSig(values);
            if (sig === this._navSig) {
                this._navSig = null; // our own echo arrived
            } else if (Date.now() - this._navAt < ECHO_GUARD_MS) {
                this._partyRaw = prevPartyRaw; // a stale echo must not resurrect old ids
                return; // an older echo: keep what the user just picked
            } else {
                this._navSig = null;
            }
        }
        this._rawOfferings = raw;
        this.filterConfig = config;
        // Restored ids the option list has not labelled yet: fetch them with includeIds.
        PARTY_KINDS.forEach((p) => {
            if (this._partyRaw[p.kind].some((id) => !this._partyKnown[p.kind][id])) this.loadPartyOptions(p.kind);
        });
        const changed = JSON.stringify(values) !== JSON.stringify(this.filterValues);
        if (changed) {
            this.filterValues = values;
            this.loadAssessments();
        }
        // Legacy browse-mode params: rewrite the URL to the new filter params (replace).
        if (legacy && this._pageRef) this.writeFiltersToUrl();
    }

    /** Best-effort only, same pattern as gtmRepLinkFinder's setCfgIdParam/
     *  gtmContentManager's stripNewFromUrl -- a sandbox that blocks History
     *  mutation should still work, it just won't survive a refresh. */
    writeSelectionToUrl() {
        try {
            const url = new URL(window.location.href);
            const params = [
                ['c__assessmentRequestId', this.selectedAssessmentRequestId],
                ['c__readoutId', this.selectedReadoutId],
                ['c__offeringKey', this.selectedOfferingKey],
                ['c__repDirectId', this.repDirectModalId],
                // Always re-derived from the component's own current
                // in-memory state (never left stale from an earlier deep
                // link) -- see focusReadoutTab's doc comment.
                ['c__focusReadoutTab', this.focusReadoutTab ? '1' : '']
            ];
            LEGACY_KEYS.forEach((k) => url.searchParams.delete(k));
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

    loadAssessments(append = false) {
        const seq = ++this._seq;
        const offset = append ? this.rows.length : 0;
        if (append) {
            this.isLoadingMore = true;
        } else {
            this.isLoading = true;
            this.loadError = '';
        }
        const query = buildQuery(
            this.filterValues,
            { sortBy: this.sortBy, sortDir: this.sortDir },
            offset,
            PAGE_SIZE
        );
        let call;
        try {
            call = getAssessmentPage(toPlain({ query }));
        } catch (e) {
            call = Promise.reject(e);
        }
        return Promise.resolve(call)
            .then((page) => {
                // A newer request (filter/sort change, Refresh) supersedes this one.
                if (seq !== this._seq) return;
                const mapped = ((page && page.rows) || []).map(mapRow);
                this.rows = append ? [...this.rows, ...mapped] : mapped;
                this.totalCount = (page && page.totalCount) || 0;
                this.totalIsCapped = !!(page && page.totalIsCapped);
                if (!append) {
                    this.offeringOptions = (page && page.offeringOptions) || [];
                    this.filterConfig = this.makeConfig(this._rawOfferings);
                }
                this.hasLoaded = true;
                this.loadError = '';
            })
            .catch((err) => {
                if (seq !== this._seq) return;
                // Prior rows stay; the error banner offers Retry.
                this.loadError = this.messageFrom(err) || 'Assessments could not be loaded.';
            })
            .finally(() => {
                // Only the newest request owns the flags; a superseded one must not
                // clear them, and the newest always does (success or error).
                if (seq !== this._seq) return;
                this.isLoading = false;
                this.isLoadingMore = false;
            });
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    /** Page-level spinner for first paint only: true while the initial (non-append) load
     *  is in flight and no rows have arrived yet -- the still-empty lightning-datatable's
     *  own is-loading attribute is easy to miss before any row shell exists. Subsequent
     *  "load more" pagination (isLoadingMore) never gates this, and it goes away the
     *  moment rows arrive even if a later reload is triggered. */
    get showInitialSpinner() { return this.isLoading && !this.hasRows; }

    get hasRows() { return this.rows.length > 0; }
    get showEmpty() { return !this.isLoading && !this.hasRows && !this.loadError; }
    get showWorkspace() { return !!this.selectedAssessmentRequestId; }
    get hasActiveFilters() { return hasActiveFilters(this.filterValues); }
    get showFilteredEmpty() { return this.showEmpty && this.hasActiveFilters; }
    get showTrueEmpty() { return this.showEmpty && !this.hasActiveFilters; }
    get showTable() { return this.hasRows || this.isLoading; }
    get canLoadMore() { return this.rows.length < this.totalCount; }
    get sortedByField() { return fieldForSortKey(this.sortBy); }
    get sortedDirection() { return this.sortDir || 'asc'; }
    /** Number for the shared bar; a capped total is shown by countCappedText instead. */
    get barResultCount() {
        return !this.hasLoaded || this.totalIsCapped || this.loadError ? undefined : this.totalCount;
    }
    get isTableLoading() { return this.isLoading || this.isLoadingMore; }
    get countCappedText() {
        return this.totalIsCapped ? `${formatTotal(this.totalCount, true)} assessments` : '';
    }

    // ------------------------------------------------------------- filters

    handleFilterChange(event) {
        const { key, value } = event.detail || {};
        if (!key) return;
        const next = { ...this.filterValues };
        const empty =
            value === undefined || value === null || value === '' || value === false ||
            (Array.isArray(value) && value.length === 0);
        if (empty) {
            delete next[key];
        } else {
            next[key] = value;
        }
        this.applyFilters(next);
    }

    handleFiltersClear() {
        // Reset EVERYTHING that affects results: values, restored raw ids, the search text
        // and the echo guard (so no older echo can put a stale filter back).
        this._rawOfferings = [];
        PARTY_KINDS.forEach((p) => {
            this._partyRaw[p.kind] = [];
            this._partyTerm[p.kind] = '';
        });
        this.applyFilters({});
    }

    handleRetry() {
        this.loadAssessments();
    }

    applyFilters(values) {
        this.filterValues = values;
        this.writeFiltersToUrl();
        this.loadAssessments();
    }

    /**
     * Shared helper + NavigationMixin.Navigate(replace) (shared-filter-bar F1).
     * currentState overlays the location (mergeLocationState) and then this
     * component's OWN selection params, in-memory truth, so a param removed by
     * writeSelectionToUrl()'s replaceState is not resurrected from a stale
     * wired state.
     */
    writeFiltersToUrl() {
        if (!this._pageRef) return;
        const base = mergeLocationState(this._pageRef.state);
        const own = {
            c__assessmentRequestId: this.selectedAssessmentRequestId,
            c__readoutId: this.selectedReadoutId,
            c__offeringKey: this.selectedOfferingKey,
            c__repDirectId: this.repDirectModalId,
            c__focusReadoutTab: this.focusReadoutTab ? '1' : ''
        };
        LEGACY_KEYS.forEach((k) => delete base[k]);
        Object.keys(own).forEach((k) => {
            if (own[k]) {
                base[k] = own[k];
            } else {
                delete base[k];
            }
        });
        const args = buildNavigateArgs(this._pageRef, this.filterConfig, this.filterValues, {
            currentState: base
        });
        this._navSig = valuesSig(this.filterValues);
        this._navAt = Date.now();
        // Safety expiry: if our own echo never arrives, stop ignoring later state.
        clearTimeout(this._navTimer);
        this._navTimer = setTimeout(() => {
            this._navSig = null;
        }, ECHO_GUARD_MS);
        this[NavigationMixin.Navigate](args.pageReference, args.replace);
    }

    // --------------------------------------------------------------- table

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail || {};
        const key = sortKeyForField(fieldName);
        if (!key) return;
        this.sortBy = key;
        this.sortDir = sortDirection === 'desc' ? 'desc' : 'asc';
        this.loadAssessments();
    }

    handleLoadMore() {
        if (this.isLoading || this.isLoadingMore || !this.canLoadMore) return;
        this.loadAssessments(true);
    }

    /** Row actions: the AR-#### button cell and the trailing row-action menu's
     *  "Open assessment" both fire 'open' (opens the workspace inline, see class
     *  comment). 'openContact' / 'openAccount' (Contact / Company cells and the
     *  menu) navigate to that record with NavigationMixin. */
    handleRowAction(event) {
        const detail = event.detail || {};
        const row = detail.row;
        const name = detail.action && detail.action.name;
        if (!name || !row) return;
        if (name === 'openContact' || name === 'openAccount') {
            const isContact = name === 'openContact';
            const recordId = isContact ? row.contactId : row.accountId;
            if (!recordId) return;
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId,
                    objectApiName: isContact ? 'Contact' : 'Account',
                    actionName: 'view'
                }
            });
            return;
        }
        if (name !== 'open' || !row.recordId) return;
        this.selectedAssessmentRequestId = row.recordId;
        // Blank when the request has no readout yet; the workspace tolerates it.
        this.selectedReadoutId = row.readoutId || '';
        this.selectedOfferingKey = row.offeringKey || '';
        // A plain row click is exactly the "card" origin refinement #3 keeps
        // defaulting to Assessment -- never inherit a focus-readout rider
        // left over from an earlier deep link into this same component.
        this.focusReadoutTab = false;
        this.writeSelectionToUrl();
    }

    /** gtmReadoutWorkspace's own "back" event -- it never hides itself, this
     *  is the parent-owned state that does. */
    handleWorkspaceBack() {
        this.selectedAssessmentRequestId = '';
        this.selectedReadoutId = '';
        this.selectedOfferingKey = '';
        this.focusReadoutTab = false;
        this.writeSelectionToUrl();
    }

    handleRefresh() { this.loadAssessments(); }

    // ------------------------------------------------------- rep-direct modal

    get showRepDirectModal() { return !!this.repDirectModalId; }

    /** Backdrop click / "x" / Done -- all three just close the modal. The
     *  underlying record is unaffected either way: gtmRepDirectShare saves
     *  its own draft/share-link state via its own Apex calls, and a
     *  Rep_Direct config never appears in this tab's table (it is keyed off
     *  GTM_Assessment_Request__c, which a Rep_Direct record does not have
     *  until a prospect actually submits the shared link) -- so there is
     *  nothing here to refresh on close. */
    handleCloseRepDirectModal() {
        this.repDirectModalId = '';
        this.writeSelectionToUrl();
    }
}
