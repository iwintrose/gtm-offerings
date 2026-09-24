import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getContactsWithLinks from '@salesforce/apex/GtmRepLinkFinderController.getContactsWithLinks';
import getMyConfigurations from '@salesforce/apex/GtmSavedConfigurationController.getMyConfigurations';
import setActive from '@salesforce/apex/GtmSavedConfigurationController.setActive';
import regeneratePassword from '@salesforce/apex/GtmSavedConfigurationController.regeneratePassword';
import getPassword from '@salesforce/apex/GtmSavedConfigurationController.getPassword';
import generateReadoutForRequest from '@salesforce/apex/GtmReadoutController.generateReadoutForRequest';
import getIndustryProfiles from '@salesforce/apex/GtmPageContentReader.getIndustryProfiles';
import getStageCountsAura from '@salesforce/apex/GtmLinkStageService.getStageCountsAura';
import getLinkIdsForStageAura from '@salesforce/apex/GtmLinkStageService.getLinkIdsForStageAura';
import getLinkStatsAura from '@salesforce/apex/GtmLinkStageService.getLinkStatsAura';
import USER_ID from '@salesforce/user/Id';
import { readFilterState, buildNavigateArgs, mergeLocationState } from 'c/gtmFilterUrlState';
import { buildColumns, buildRows, sortRows, FUNNEL_LABELS } from './gtmRepLinkTableModel';
import {
    buildExtraFilters, extraValuesOnly, filterLinks, hasExtraActive, EXTRA_KEYS, PAGES_PARAMS,
    mapLegacyParams, cleanNavigateBase
} from './gtmRepLinkFilterModel';

/** Funnel-stage filter (issue stage-filter-pages-tab). "Funnel stage" is
 *  unrelated to Presentation_Stage__c. Definitions live server-side in
 *  GtmLinkStageService (docs/architecture/gtm-link-stage-filter.md); this
 *  file only lists the vocabulary + labels and never re-implements them.
 *  not_opened is exposed as a chip too: the URL util drops values that are
 *  not in the config's options, so a valid c__stage=not_opened deep link
 *  (Overview/GUS) would otherwise be silently ignored. */
// Labels say what each option MATCHES. The Funnel stage column shows one exclusive
// stage (FUNNEL_LABELS); the filter matches cumulatively on the server
// (GtmLinkStageService.getLinkIdsForStage), so the cumulative options say "or later" and
// reuse the column's own wording. `quiet` and `hot` are behavioural flags that no column
// can show: their `hint` states the real rule from GtmLinkStageService (isQuiet: started
// and not submitted; isHot: 2+ visits and last visit within HOT_WINDOW_HOURS = 48).
// Option VALUES are frozen (Overview drill-ins, c__stage deep links, the GUS tool).
const STAGE_OPTIONS = [
    { value: 'sent', label: 'All links sent' },
    { value: 'engaged', label: `${FUNNEL_LABELS.engaged} or later` },
    { value: 'started', label: `${FUNNEL_LABELS.started} or later` },
    { value: 'submitted', label: FUNNEL_LABELS.submitted },
    { value: 'quiet', label: 'Went quiet', hint: 'started, not submitted' },
    { value: 'hot', label: 'Came back', hint: '2+ visits, last within 48 hours' },
    { value: 'not_opened', label: FUNNEL_LABELS.not_opened }
];
const STAGE_COUNT_FIELD = {
    sent: 'sent', engaged: 'engaged', started: 'started', submitted: 'submitted',
    quiet: 'quiet', hot: 'hot', not_opened: 'notOpened'
};
const STAGE_URL_CONFIG = [{
    key: 'stage', label: 'Funnel stage', type: 'chips', param: 'c__stage', options: STAGE_OPTIONS
}];

/** How long an older page-reference echo is ignored after we navigate. */
const ECHO_GUARD_MS = 3000;

/** Order-independent signature of a filter values map. */
function valuesSig(values) {
    const v = values || {};
    return JSON.stringify(Object.keys(v).sort().map((k) => [k, v[k]]));
}
/**
 * A rep's own "find a link I already sent" flow (D7), Release 2 (Addendum C.9).
 *
 * One filterable table of the rep's links (Account and Contact are ordinary
 * searchable filters whose options come only from links that exist). Each row has
 * a native row-action menu (Open, Copy link, New password, Turn on/off). Open shows
 * that link's detail view (password, readout, assessment, preview) with one
 * "Back to links" button; the filters live in the URL so Back restores them.
 * There is no All / By-account toggle and no Miller columns any more.
 */
export default class GtmRepLinkFinder extends NavigationMixin(LightningElement) {
    /** Optional pre-selected target (gtmPageBrowser wizard "Done" deep link):
     *  jumps straight to the detail view for that record. */
    @api
    get targetRecordId() {
        return this._targetRecordId;
    }
    set targetRecordId(value) {
        this._targetRecordId = value || '';
        this._applyTarget();
    }
    _targetRecordId = '';

    @api targetCompany = '';
    @api targetOfferingKey = '';

    /** Only ever applied once per incoming target. */
    _targetApplied = false;

    _applyTarget() {
        if (!this._targetRecordId || this._targetApplied) return;
        this._targetApplied = true;
        this.setCfgIdParam(this._targetRecordId);
        // Deferred to a microtask: targetCompany/targetOfferingKey may be assigned
        // after this setter in the same synchronous pass.
        Promise.resolve().then(() => {
            this.selectedLink = {
                recordId: this._targetRecordId,
                offering: this.targetOfferingKey || '',
                company: this.targetCompany || ''
            };
        });
    }

    // undefined, not '': only the detail view's URL state uses these.
    @track accountId;
    @track loadingLinks = false;
    @track loadError = '';
    @track selectedContactId = '';
    @track selectedLink = null;
    @track regeneratingIds = [];
    @track showPreview = false;
    @track passwordRevealed = false;
    @track revealedPassword = '';
    @track revealingPassword = false;
    @track showWorkspace = false;

    // ------------------------------------------------------ links table
    @track industryProfiles = null; // null until getIndustryProfiles returns
    @track savedLinks = [];
    @track loadingSavedLinks = false;
    @track savedLinksError = '';

    /** True until all 4 of the connectedCallback's concurrent initial Apex calls
     *  (industries, saved links, link stats, stage counts) have settled -- gates a
     *  single page-level spinner so the whole tab shows a clear loading state on
     *  first paint, on top of the narrower sub-state spinners below (loadingSavedLinks/
     *  loadingLinks/stageLoading) which are left as-is. */
    @track initialLoading = true;
    _initialLoadPending = 0;

    disconnectedCallback() {
        clearTimeout(this._navTimer);
    }

    connectedCallback() {
        this._initialLoadPending = 4;
        this.loadIndustries();
        this.loadSavedLinks();
        this.loadLinkStats();
        this.loadStageCounts();
    }

    /** Decrements the initial-load counter; called once per settled initial call. */
    settleInitialLoad() {
        if (this._initialLoadPending > 0) this._initialLoadPending -= 1;
        if (this._initialLoadPending === 0) this.initialLoading = false;
    }

    /** Defined industries (Published + Active Industry Chooser sections): shared framework
     *  config, readable by every rep. On failure the Industry filter simply stays hidden. */
    loadIndustries() {
        Promise.resolve(getIndustryProfiles({ offeringKey: 'gtm', templateType: 'industry-chooser' }))
            .then((rows) => { this.industryProfiles = Array.isArray(rows) ? rows : []; })
            .catch(() => { this.industryProfiles = []; })
            .finally(() => { this.settleInitialLoad(); });
    }

    _linksSeq = 0;

    /** Sequence-tokened: overlapping loads cannot leave the flag stuck or overwrite newer rows.
     *  On error the previous rows stay and savedLinksError offers Retry. */
    loadSavedLinks() {
        const seq = ++this._linksSeq;
        this.loadingSavedLinks = true;
        this.savedLinksError = '';
        let call;
        try {
            call = getMyConfigurations();
        } catch (e) {
            call = Promise.reject(e);
        }
        Promise.resolve(call)
            .then((rows) => {
                if (seq !== this._linksSeq) return;
                this.savedLinks = rows || [];
                this.pruneStaleExtra();
            })
            .catch((e) => {
                if (seq !== this._linksSeq) return;
                this.savedLinksError = (e && e.body && e.body.message) || 'Saved links could not be loaded.';
            })
            .finally(() => {
                if (seq === this._linksSeq) this.loadingSavedLinks = false;
                this.settleInitialLoad();
            });
    }

    handleRetryLinks() {
        this.loadSavedLinks();
    }

    /** A filter value naming a record/option no link has any more (deleted account or contact,
     *  unknown offering) can only ever empty the table: drop it and rewrite the URL. */
    pruneStaleExtra() {
        const cfg = this.configFor({});
        const next = {};
        let dropped = false;
        Object.keys(this.pageExtra).forEach((k) => {
            const f = cfg.find((x) => x.key === k);
            const v = this.pageExtra[k];
            const listy = f && f.type === 'chips' && Array.isArray(v) && Array.isArray(f.options);
            const skip = !listy || (k === 'industry' && this.industryProfiles === null);
            if (skip) {
                next[k] = v;
                return;
            }
            const valid = new Set(f.options.map((o) => String(o.value)));
            const kept = v.map(String).filter((x) => valid.has(x));
            if (kept.length !== v.length) dropped = true;
            if (kept.length) next[k] = kept;
        });
        if (!dropped) return;
        this._pageState = {};
        this.pageExtra = next;
        this.navigateFilters();
    }

    // ---- Pages table (all mode; contract: gtm-link-stage-filter.md) ----

    @track linkStats = [];
    @track statsViewAll = null; // null until the stats call succeeds
    @track statsTruncated = false;
    @track statsError = false;
    @track sortedBy = 'lastVisitAt';
    @track sortedDirection = 'desc';
    _statsSeq = 0;

    loadLinkStats() {
        const seq = ++this._statsSeq;
        getLinkStatsAura()
            .then((r) => {
                if (seq !== this._statsSeq) return;
                this.linkStats = (r && r.stats) || [];
                this.statsViewAll = !!(r && r.viewAll);
                this.statsTruncated = !!(r && r.truncated);
                this.statsError = false;
            })
            .catch(() => {
                if (seq !== this._statsSeq) return;
                this.linkStats = [];
                this.statsViewAll = null;
                this.statsTruncated = true;
                this.statsError = true;
            })
            .finally(() => { this.settleInitialLoad(); });
    }

    /** Explicit flag from Apex; if the stats call failed, infer from the rows. */
    get showOwnerColumn() {
        if (this.statsViewAll !== null) return this.statsViewAll;
        return this.savedLinks.some((l) => l.OwnerId && l.OwnerId !== USER_ID);
    }

    get columns() {
        return buildColumns(this.showOwnerColumn);
    }

    get tableRows() {
        let links = this.savedLinks;
        if (this.stageKey) {
            // While the id set is in flight show nothing rather than flashing
            // the unfiltered table; on an Apex error stageIdSet stays null so
            // the unfiltered list is shown together with the error banner.
            if (this.stageLoading) return [];
            if (this.stageIdSet) links = links.filter((l) => this.stageIdSet.has(l.Id));
        }
        links = filterLinks(links, this.linkStats, this.pageExtra, Date.now(), this.industryProfiles);
        return sortRows(buildRows(links, this.linkStats, this.industryProfiles), this.sortedBy, this.sortedDirection);
    }

    get hasTableRows() {
        return this.tableRows.length > 0;
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy = fieldName;
        this.sortedDirection = sortDirection;
    }

    /** Native row-action menu: Open, Copy link, New password, Turn on/off. */
    handleRowAction(event) {
        const { action, row } = event.detail;
        if (!action || !row) return;
        if (action.name === 'open') this.openLinkRow(row.recordId);
        else if (action.name === 'openAccount') this.openAccountRecord(row);
        else if (action.name === 'openContact') this.openContactRecord(row);
        else if (action.name === 'copy') this.copyToClipboard(row.generatedUrl);
        else if (action.name === 'password') this.rowRegeneratePassword(row);
        else if (action.name === 'toggle') this.rowToggleActive(row);
    }

    /** Account cell: the standard Account record page (view). */
    openAccountRecord(row) {
        if (!row || !row.accountId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: row.accountId, objectApiName: 'Account', actionName: 'view' }
        });
    }

    /** Contact cell: the standard Contact record page (view), same tab context. */
    openContactRecord(row) {
        if (!row || !row.contactId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: row.contactId, objectApiName: 'Contact', actionName: 'view' }
        });
    }

    rowRegeneratePassword(row) {
        const id = row.recordId;
        if (this.regeneratingIds.indexOf(id) !== -1) return;
        const company = row.company || 'this link';
        // eslint-disable-next-line no-alert
        if (!confirm(`Set a new password for ${company}'s link? Their current password will stop working.`)) return;
        this.regeneratingIds = [...this.regeneratingIds, id];
        regeneratePassword({ recordId: id })
            .then((newPassword) => {
                this.copyToClipboard(newPassword);
                // eslint-disable-next-line no-alert
                alert(`New password for ${company}: ${newPassword}\n\nCopied to your clipboard.`);
            })
            .catch((e) => {
                this.loadError = (e && e.body && e.body.message) || 'A new password could not be set.';
            })
            .finally(() => {
                this.regeneratingIds = this.regeneratingIds.filter((x) => x !== id);
            });
    }

    /** Turn a link on/off (setActive), then update the row and refresh stats. */
    rowToggleActive(row) {
        const id = row.recordId;
        if (this.togglingIds.indexOf(id) !== -1) return;
        const nextActive = row.statusLabel === 'Inactive';
        this.loadError = '';
        this.togglingIds = [...this.togglingIds, id];
        setActive({ recordId: id, active: nextActive })
            .then(() => {
                this.savedLinks = this.savedLinks.map((l) => (l.Id === id ? { ...l, Active__c: nextActive } : l));
                this.loadLinkStats();
                this.loadStageCounts();
            })
            .catch((e) => {
                this.loadError = (e && e.body && e.body.message) || 'This link’s status could not be updated.';
            })
            .finally(() => {
                this.togglingIds = this.togglingIds.filter((x) => x !== id);
            });
    }
    @track togglingIds = [];

    // ------------------------------------------------- funnel-stage filter

    @track stageKey = '';
    @track stageCounts = null;
    @track stageIdSet = null;
    @track stageLoading = false;
    @track stageError = '';
    _pageRef = null;
    _idsSeq = 0;
    _countsSeq = 0;

    loadStageCounts() {
        const seq = ++this._countsSeq;
        getStageCountsAura()
            .then((c) => { if (seq === this._countsSeq) this.stageCounts = c || null; })
            .catch(() => {
                // Chips simply render without badges; filtering still works.
                if (seq === this._countsSeq) this.stageCounts = null;
            })
            .finally(() => {
                // Only the very first call (connectedCallback) counts toward initial load;
                // a later refresh (rowToggleActive/applyStage) must not re-decrement a
                // counter that already reached 0.
                if (this._initialLoadPending > 0) this.settleInitialLoad();
            });
    }

    /** Idempotent: a re-fired CurrentPageReference (or our own Navigate echo)
     *  with an unchanged key does nothing, so there is no double fetch. */
    applyStage(key, fromUrl) {
        if (key === this.stageKey) return;
        this.stageKey = key;
        this.stageIdSet = null;
        this.stageError = '';
        const seq = ++this._idsSeq;
        if (!key) {
            this.stageLoading = false;
            return;
        }
        this.stageLoading = true;
        getLinkIdsForStageAura({ stageKey: key })
            .then((ids) => {
                if (seq !== this._idsSeq) return;
                this.stageIdSet = new Set(ids || []);
            })
            .catch((e) => {
                if (seq !== this._idsSeq) return;
                this.stageError = (e && e.body && e.body.message) || 'The stage filter could not be applied.';
            })
            .finally(() => {
                if (seq === this._idsSeq) this.stageLoading = false;
            });
        this.loadStageCounts();
    }

    get stageFilterActive() {
        return !!this.stageKey && !!this.stageIdSet;
    }

    get stageLabel() {
        const o = STAGE_OPTIONS.find((x) => x.value === this.stageKey);
        return o ? o.label : '';
    }
    // ---- Addendum C.3 extra filters (client-side over savedLinks / linkStats) ----

    @track pageExtra = {};
    _pageState = {};
    _navSig = null;
    _navAt = 0;
    _navTimer = null;

    get statsComplete() {
        return this.statsViewAll !== null && !this.statsError && !this.statsTruncated;
    }

    get stageConfig() {
        return {
            ...STAGE_URL_CONFIG[0],
            options: STAGE_OPTIONS.map((o) => {
                const n = this.stageCounts ? this.stageCounts[STAGE_COUNT_FIELD[o.value]] : undefined;
                return typeof n === 'number' ? { ...o, count: n } : { ...o };
            })
        };
    }

    /** Funnel stage first (unchanged, filters[0]), then the extra Pages filters. */
    get filterConfig() {
        return this.configFor(this._pageState);
    }

    configFor(rawState) {
        return [
            this.stageConfig,
            ...buildExtraFilters({
                links: this.savedLinks,
                statsComplete: this.statsComplete,
                industries: this.industryProfiles,
                state: rawState
            })
        ];
    }

    get filterValues() {
        return { ...(this.stageKey ? { stage: this.stageKey } : {}), ...this.pageExtra };
    }

    get extraFilterActive() {
        return hasExtraActive(this.pageExtra);
    }

    get anyFilterActive() {
        return this.stageFilterActive || this.extraFilterActive;
    }

    /** Wired URL state -> stage + extra filter values (idempotent; never refetches).
     *  A reference OLDER than our own pending navigation (its echo arrives after a newer
     *  pick) is ignored, or it would clear what the user just picked (race R-B). */
    syncFilterState(wiredState) {
        // The wired state can lag the URL (cold load, or an echo older than the URL): the
        // location's c__ params overlay it, as navigateFilters already does.
        const loc = mapLegacyParams(mergeLocationState(wiredState));
        const src = loc.state;
        const raw = {};
        EXTRA_KEYS.forEach((k) => {
            const param = PAGES_PARAMS[k];
            if (src[param] !== undefined) raw[param] = src[param];
        });
        const stage = readFilterState(src, STAGE_URL_CONFIG).stage || '';
        const config = this.configFor(raw);
        const extra = extraValuesOnly(readFilterState(src, config));
        if (this._navSig !== null) {
            const sig = valuesSig({ ...(stage ? { stage } : {}), ...extra });
            if (sig === this._navSig) {
                this._navSig = null; // our own echo arrived
            } else if (Date.now() - this._navAt < ECHO_GUARD_MS) {
                return; // an older echo: keep what the user just picked
            } else {
                this._navSig = null;
            }
        }
        this._pageState = raw;
        this.applyStage(stage, true);
        if (JSON.stringify(extra) !== JSON.stringify(this.pageExtra)) this.pageExtra = extra;
        // Legacy c__rlfAccountId / c__rlfContactId (Overview drill-ins, bookmarks) were
        // mapped into the Account / Contact filters above: rewrite the URL (replace) to the
        // c__pacct / c__pcontact form so the legacy params are gone.
        if (loc.mapped) this.navigateFilters();
    }

    get showFilterBar() {
        return !this.selectedLink;
    }

    get filterResultCount() {
        return this.tableRows.length;
    }

    get filterResultLabel() {
        return this.stageFilterActive ? `links · ${this.stageLabel}` : 'links';
    }

    get showStageEmpty() {
        return this.anyFilterActive && !this.stageLoading
            && !this.loadingSavedLinks && !this.hasTableRows;
    }

    get showNoSavedLinks() {
        return !this.hasTableRows && !this.loadingSavedLinks && !this.stageLoading
            && !this.showStageEmpty;
    }

    get stageEmptyText() {
        if (this.stageFilterActive && !this.extraFilterActive) {
            return `No links have reached "${this.stageLabel}" yet.`;
        }
        return 'No links match these filters.';
    }

    get clearFiltersLabel() {
        return this.stageFilterActive && !this.extraFilterActive ? 'Clear filter' : 'Clear filters';
    }

    handleFilterChange(event) {
        const { key, value } = event.detail || {};
        if (key === 'stage') {
            this.changeStage(typeof value === 'string' ? value : '');
            return;
        }
        if (!EXTRA_KEYS.includes(key)) return;
        const next = { ...this.pageExtra };
        const empty =
            value === undefined || value === null || value === '' || value === false ||
            (Array.isArray(value) && value.length === 0);
        if (empty) delete next[key];
        else next[key] = value;
        this.pageExtra = next;
        this.navigateFilters();
    }

    handleFilterClear() {
        // Reset everything that affects the list: values, the raw URL-derived option state
        // and the echo guard, so no older echo can bring a stale filter back.
        this._pageState = {};
        this.pageExtra = {};
        this.changeStage('');
    }

    handleClearStage() {
        this.handleFilterClear();
    }

    changeStage(rawKey) {
        const key = STAGE_OPTIONS.some((o) => o.value === rawKey) ? rawKey : '';
        this.applyStage(key, false);
        this.navigateFilters();
    }
    /** State-only Navigate(replace) via the shared util. Other c__ params are
     *  preserved; legacy c__rlfMode/account/contact params and a stale detail-view
     *  state are dropped (cleanNavigateBase). */
    navigateFilters() {
        if (!this._pageRef) return;
        const args = buildNavigateArgs(
            this._pageRef, this.filterConfig, this.filterValues,
            { mode: 'replace', currentState: cleanNavigateBase(mergeLocationState(this._pageRef.state)) }
        );
        this._navSig = valuesSig(this.filterValues);
        this._navAt = Date.now();
        // Safety expiry: if our own echo never arrives, stop ignoring later state.
        clearTimeout(this._navTimer);
        this._navTimer = setTimeout(() => { this._navSig = null; }, ECHO_GUARD_MS);
        this[NavigationMixin.Navigate](args.pageReference, args.replace);
    }

    /** Open: shows this link's detail view. The row only has the saved record, so the
     *  richer LinkSummary (request/readout ids) is re-derived from the existing
     *  getContactsWithLinks Apex through restoreDrillState. A row without an account is
     *  disabled in the table; the silent return is belt and braces. */
    openLinkRow(recordId) {
        const row = this.tableRows.find((t) => t.recordId === recordId);
        if (!row) return;
        // The drill restore reads getContactsWithLinks (links WITH a contact, by account).
        // A link missing either opens by its own id, the same shape as targetRecordId.
        if (!row.accountId || !row.contactId) {
            this.setCfgIdParam(row.recordId);
            this.selectedLink = {
                recordId: row.recordId,
                offering: row.offeringLabel || '',
                company: row.company || ''
            };
            this.writeDrillStateToUrl();
            return;
        }
        this._restoredContactId = row.contactId || '';
        this._restoredLinkId = row.recordId;
        this.restoreDrillState(row.accountId);
    }

    // -------------------------------------------------------- url state
    //
    // Detail view only: c__rlfAccountId + c__rlfContactId + c__rlfLinkId (+ ShowPreview,
    // ShowWorkspace, PwRevealed) stay the deep-link contract, mirrored with
    // history.replaceState. Without a c__rlfLinkId the account/contact ids are LEGACY
    // and map into the Account/Contact filters (mapLegacyParams). c__rlfMode is ignored.
    _restoredKey = '';
    _restoredContactId = '';
    _restoredLinkId = '';
    _pendingShowPreview = false;
    _pendingShowWorkspace = false;
    _pendingPwRevealed = false;

    @wire(CurrentPageReference)
    captureLinkFinderState(ref) {
        const state = (ref && ref.state) || {};
        this._pageRef = ref || null;
        this.syncFilterState(state);
        const accountId = state.c__rlfAccountId || '';
        const linkId = state.c__rlfLinkId || '';
        // Deep-link to a link's detail needs the link id; an account (and contact) alone
        // is a legacy filter deep link and was mapped by syncFilterState.
        if (!accountId || !linkId || this._targetRecordId) return;
        const key = `${accountId}|${linkId}`;
        if (this._restoredKey === key) return;
        this._restoredKey = key;
        this._restoredContactId = state.c__rlfContactId || '';
        this._restoredLinkId = linkId;
        this.restoreDrillState(accountId);
        this.restoreLinkFinderViewState(state);
    }

    /** issue-pages-preview-fixes: mirrors showPreview/showWorkspace/
     *  passwordRevealed onto the same URL channel writeDrillStateToUrl
     *  already uses for the Account -> Contact -> Link drill state, so a
     *  real <a href> navigation away from gtmAssessmentDetail (Account/
     *  Opportunity/Contact links, a full page unload/reload) and back via
     *  browser back-navigation restores the rep's preview/workspace/
     *  password-reveal state instead of resetting to the plain view step.
     *
     *  Deliberately does NOT persist the plaintext password itself on the
     *  URL -- if c__rlfPwRevealed=1 is present, the password is re-fetched
     *  via the same getPassword Apex call handleRevealPassword already
     *  uses, once selectedLink is set, rather than round-tripping the
     *  secret through browser history/URL state. */
    restoreLinkFinderViewState(state) {
        if (!this._restoredLinkId) return;
        // restoreDrillState (triggered just above) resolves selectedLink
        // asynchronously via getContactsWithLinks -- stash the desired
        // view-state as pending flags here and apply them once that promise
        // actually lands the link (see restoreDrillState's own .then below),
        // rather than acting on a selectedLink that isn't set yet.
        this._pendingShowPreview = state.c__rlfShowPreview === '1';
        this._pendingShowWorkspace = state.c__rlfShowWorkspace === '1';
        this._pendingPwRevealed = state.c__rlfPwRevealed === '1';
    }

    /** Applies the view-state flags restoreLinkFinderViewState stashed,
     *  once restoreDrillState's own async link-restore has actually set
     *  selectedLink -- see restoreLinkFinderViewState's doc comment. */
    applyPendingLinkFinderViewState() {
        if (!this.selectedLink) return;
        if (this._pendingShowPreview) this.showPreview = true;
        if (this._pendingShowWorkspace) this.showWorkspace = true;
        if (this._pendingPwRevealed) this.handleRevealPassword();
        this._pendingShowPreview = false;
        this._pendingShowWorkspace = false;
        this._pendingPwRevealed = false;
    }
    /** Re-derives the LinkSummary for one link from getContactsWithLinks. */
    restoreDrillState(accountId) {
        this.accountId = accountId;
        this.selectedContactId = '';
        this.selectedLink = null;
        this.loadError = '';
        this.loadingLinks = true;
        getContactsWithLinks({ accountId })
            .then((rows) => {
                const groups = rows || [];
                let group = groups.find((g) => g.contactId === this._restoredContactId);
                let link = group && (group.links || []).find((l) => l.recordId === this._restoredLinkId);
                if (!link) {
                    group = groups.find((g) => (g.links || []).some((l) => l.recordId === this._restoredLinkId));
                    link = group && group.links.find((l) => l.recordId === this._restoredLinkId);
                }
                if (!link) {
                    this.accountId = undefined;
                    this.loadError = 'This link could not be opened.';
                    return;
                }
                this.selectedContactId = group.contactId;
                this.selectedLink = link;
                this.setCfgIdParam(link.recordId);
                this.applyPendingLinkFinderViewState();
                this.writeDrillStateToUrl();
            })
            .catch((e) => {
                this.accountId = undefined;
                this.loadError = (e && e.body && e.body.message) || 'This link could not be opened.';
            })
            .finally(() => { this.loadingLinks = false; });
    }

    /** Best-effort only (a sandbox that blocks History mutation just loses refresh
     *  restore). Called after every open/close/view-state change. */
    writeDrillStateToUrl() {
        try {
            const url = new URL(window.location.href);
            const params = [
                ['c__rlfAccountId', this.accountId || ''],
                ['c__rlfContactId', this.selectedContactId || ''],
                ['c__rlfLinkId', this.selectedLink ? this.selectedLink.recordId : ''],
                ['c__rlfMode', ''], // no mode exists any more; never written
                ['c__stage', this.stageKey || ''],
                ['c__rlfShowPreview', this.showPreview ? '1' : ''],
                ['c__rlfShowWorkspace', this.showWorkspace ? '1' : ''],
                ['c__rlfPwRevealed', this.passwordRevealed ? '1' : '']
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

    get isViewVisible() {
        return !!this.selectedLink;
    }

    get backToLinksLabel() {
        return '← Back to links';
    }

    handleTogglePreview() {
        this.showPreview = !this.showPreview;
        this.writeDrillStateToUrl();
    }

    get previewToggleLabel() {
        return this.showPreview ? 'Hide preview' : 'Preview the link';
    }

    handleCopyLink(event) {
        event.stopPropagation();
        const url = event.currentTarget.dataset.url;
        if (!url) return;
        this.copyToClipboard(url);
    }

    copyToClipboard(text) {
        if (text && navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).catch(() => {
                // best-effort -- the alert/visible text is still there to copy by hand
            });
        }
    }

    get selectedLinkOfferingKey() {
        return this.selectedLink ? this.selectedLink.offering : '';
    }

    /** This "view" step now shows the same rep-facing controls
     *  (Customize/Gus button, Saved Links bar, floating agent bubble) that
     *  gtmConfigurator already renders elsewhere for a signed-in rep --
     *  view-only was previously hard-coded true here with no documented
     *  reason (see Architect resolution, TASK_SCOPE.md §6 fork #2); kept as
     *  a getter, not a bare attribute, so a future embedding of this
     *  component can still force read-only mode if ever needed. */
    get viewStepViewOnly() {
        return false;
    }

    get selectedLinkCompany() {
        return this.selectedLink ? this.selectedLink.company : '';
    }

    get selectedLinkUrl() {
        return this.selectedLink ? (this.selectedLink.generatedUrl || '') : '';
    }

    get selectedLinkRecordId() {
        return this.selectedLink ? this.selectedLink.recordId : '';
    }

    /** Populated by PR #121 only once a prospect has actually started (or
     *  finished) an assessment from this link -- null is the normal,
     *  common case for a link nobody has used yet, not an error (see
     *  LinkSummary's own doc comment). Drives whether the gtmAssessmentDetail
     *  panel below renders at all. */
    get selectedLinkRequestId() {
        return this.selectedLink ? this.selectedLink.requestId : '';
    }

    get hasSubmission() {
        return !!this.selectedLinkRequestId;
    }

    /** Only set once a readout already exists for that request -- the
     *  "generate one" path is a deliberately separate, deferred unit (see
     *  TASK_SCOPE.md), not built here. */
    get selectedLinkReadoutId() {
        return this.selectedLink ? this.selectedLink.readoutId : '';
    }

    get hasReadout() {
        return !!this.selectedLinkReadoutId;
    }

    @track generatingReadout = false;

    /** "Generate Readout" is the hasSubmission-but-not-hasReadout sibling of
     *  "View readout" above -- the recovery action for when the guest-submit
     *  transaction's own best-effort generateDraftReadout call no-op'd (see
     *  GtmReadoutController.generateReadoutForRequest's doc comment) or the
     *  request predates that logic. Hidden once hasReadout flips true. */
    get showGenerateReadout() {
        return this.hasSubmission && !this.hasReadout;
    }

    /** Renders gtmReadoutWorkspace INLINE (in place of this view step's own
     *  content) on the Readout tab already showing selectedLinkReadoutId,
     *  rather than deep-linking away into the retired
     *  GTM_Assessment_Submission_View tab (issue-gtm-readout-workspace).
     *  handleWorkspaceBack below is what returns to this view step. */
    handleViewReadout() {
        if (!this.selectedLinkReadoutId) return;
        this.showWorkspace = true;
        this.writeDrillStateToUrl();
    }

    handleGenerateReadout() {
        if (!this.selectedLinkRequestId || this.generatingReadout) return;
        this.loadError = '';
        this.generatingReadout = true;
        generateReadoutForRequest({ assessmentRequestId: this.selectedLinkRequestId })
            .then((readoutId) => {
                if (this.selectedLink) {
                    this.selectedLink = { ...this.selectedLink, readoutId };
                }
                this.showWorkspace = true;
                this.writeDrillStateToUrl();
            })
            .catch((e) => {
                this.loadError = (e && e.body && e.body.message) || 'The readout could not be generated.';
            })
            .finally(() => {
                this.generatingReadout = false;
            });
    }

    /** gtmReadoutWorkspace's own "back" event -- it never hides itself, this
     *  is the parent-owned state that does, returning to the normal view
     *  step content. */
    handleWorkspaceBack() {
        this.showWorkspace = false;
        this.writeDrillStateToUrl();
    }
    get copyLinkLabel() {
        return 'Copy link';
    }

    /** Masked (dots) until the rep explicitly reveals it -- the plaintext
     *  is never fetched or held until handleRevealPassword is clicked (see
     *  Apex GtmSavedConfigurationController.getPassword doc comment). */
    get passwordDisplay() {
        return this.passwordRevealed ? this.revealedPassword : '••••••';
    }

    get regeneratingSelectedLink() {
        return this.selectedLink
            ? this.regeneratingIds.indexOf(this.selectedLink.recordId) !== -1
            : false;
    }

    handleCopySelectedLink() {
        if (!this.selectedLinkUrl) return;
        this.copyToClipboard(this.selectedLinkUrl);
    }

    /** Fetches the current plaintext password on demand only, exactly once
     *  per reveal click -- never prefetched with the rest of the view
     *  step's data. */
    handleRevealPassword() {
        if (this.revealingPassword || !this.selectedLinkRecordId) return;
        this.revealingPassword = true;
        getPassword({ recordId: this.selectedLinkRecordId })
            .then((password) => {
                this.revealedPassword = password || '';
                this.passwordRevealed = true;
                // issue-pages-preview-fixes: mirror the reveal onto the URL
                // so it survives the gtmAssessmentDetail <a href> full-page
                // navigation/back-navigation round trip -- see
                // restoreLinkFinderViewState's doc comment.
                this.writeDrillStateToUrl();
            })
            .catch((e) => {
                this.loadError = (e && e.body && e.body.message) || 'The password could not be retrieved.';
            })
            .finally(() => {
                this.revealingPassword = false;
            });
    }

    handleCopyRevealedPassword(event) {
        const value = event.currentTarget.dataset.url;
        if (!value) return;
        this.copyToClipboard(value);
    }

    /** Same reset-and-reveal-once action as the link-list step's "New
     *  password" button, promoted up to the view step too so a rep doesn't
     *  have to back out just to reset a password they're already looking
     *  at (handleRegeneratePassword above is what still backs the
     *  link-list step's own button). */
    handleRegeneratePasswordOnView(event) {
        event.stopPropagation();
        const id = this.selectedLinkRecordId;
        if (!id || this.regeneratingIds.indexOf(id) !== -1) return;
        const company = this.selectedLinkCompany || 'this link';
        // eslint-disable-next-line no-alert
        if (!confirm(`Set a new password for ${company}'s link? Their current password will stop working.`)) return;

        this.regeneratingIds = [...this.regeneratingIds, id];
        regeneratePassword({ recordId: id })
            .then((newPassword) => {
                this.passwordRevealed = true;
                this.revealedPassword = newPassword;
                this.copyToClipboard(newPassword);
                // eslint-disable-next-line no-alert
                alert(`New password for ${company}: ${newPassword}\n\nCopied to your clipboard.`);
            })
            .catch((e) => {
                this.loadError = (e && e.body && e.body.message) || 'A new password could not be set.';
            })
            .finally(() => {
                this.regeneratingIds = this.regeneratingIds.filter((existingId) => existingId !== id);
            });
    }

    // ------------------------------------------------------------ back nav

    /** One "Back to links": closes the detail view; the list filters live in the URL
     *  and component state, so they are intact. */
    handleBackToLinks() {
        this.accountId = undefined;
        this.selectedContactId = '';
        this.selectedLink = null;
        this.loadError = '';
        this.clearCfgIdParam();
        this.resetPasswordReveal();
        this.showPreview = false;
        this.showWorkspace = false;
        this._restoredKey = '';
        this.writeDrillStateToUrl();
    }

    /** Never let a previously-revealed plaintext password leak into a
     *  different link's view just because state wasn't cleared -- reset
     *  whenever the selected link changes or the rep navigates away. */
    resetPasswordReveal() {
        this.passwordRevealed = false;
        this.revealedPassword = '';
        this.revealingPassword = false;
    }

    // ---------------------------------------------------------------- url

    /**
     * gtmConfigurator has never had an @api way to be told which saved
     * record to render -- it reads "?cfgId=" off the real browser URL once,
     * in its own connectedCallback (see readUrlParams()). Setting that
     * query param here, before the element with a fresh `key` gets created,
     * is what lets it render this specific link instead of the generic
     * unfilled template. Best-effort: a sandbox that blocks History
     * mutation should still show the (unfilled) template rather than throw.
     */
    setCfgIdParam(recordId) {
        try {
            const url = new URL(window.location.href);
            url.searchParams.set('cfgId', recordId);
            window.history.replaceState(null, '', url.toString());
        } catch (e) {
            // best-effort -- see comment above
        }
    }

    clearCfgIdParam() {
        try {
            const url = new URL(window.location.href);
            url.searchParams.delete('cfgId');
            window.history.replaceState(null, '', url.toString());
        } catch (e) {
            // best-effort -- see comment above
        }
    }
}
