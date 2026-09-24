import { LightningElement, api, track, wire } from 'lwc';
import saveConfiguration from '@salesforce/apex/GtmSavedConfigurationController.saveConfiguration';
import setConfigActive from '@salesforce/apex/GtmSavedConfigurationController.setActive';
import searchContacts from '@salesforce/apex/GtmSavedConfigurationController.searchContacts';
import getAccountDeals from '@salesforce/apex/GtmSavedConfigurationController.getAccountDeals';
import findAccountByName from '@salesforce/apex/GtmSavedConfigurationController.findAccountByName';
import getConfiguratorPageUrl from '@salesforce/apex/GtmSavedConfigurationController.getConfiguratorPageUrl';
import fetchLogoDataUri from '@salesforce/apex/GtmBrandLookupController.fetchLogoDataUri';
import getPageLayout from '@salesforce/apex/GtmPageContentReader.getPageLayout';
import getIndustryProfiles from '@salesforce/apex/GtmPageContentReader.getIndustryProfiles';
import listPlatforms from '@salesforce/apex/GtmMigrationPairs.listPlatforms';
import resolveDefaultLabel from '@salesforce/apex/GtmMigrationPairs.resolveDefaultLabel';
import { FRAMEWORK_KEY } from 'c/gtmPageLayouts';
import USER_ID from '@salesforce/user/Id';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_NAME_FIELD from '@salesforce/schema/User.Name';
import USER_EMAIL_FIELD from '@salesforce/schema/User.Email';
import { isHex6 } from 'c/gtmConfigData';

// Publicis Sapient's own brand red -- the Quick Link path's fallback accent
// when the rep gives no website to auto-detect a brand colour from. Chosen
// deliberately over this app's own generic swatch-list default so a link
// built in 30 seconds never looks unbranded.
const PS_RED = 'E4002B';

// Fallback only -- used until the offering's own 'defaults::sizePresets' CMS
// content resolves (or when an offering hasn't authored any presets yet).
// Shape matches the CMS JSON exactly (key/label/sub/assetCount/dependencyCount/
// healthScore) so the resolved-array code below never has to branch on where
// a preset came from. Values are Migration Accelerator's historical S/M/L
// numbers, seeded verbatim as that offering's own 'defaults::sizePresets' row
// -- this constant only matters for an offering that has none.
const DEFAULT_SIZE_PRESETS = [
    { key: 'S', label: 'Small',  sub: 'Under 1,000 assets', assetCount: 800,   dependencyCount: 1400,  healthScore: 78 },
    { key: 'M', label: 'Medium', sub: '~4,000 assets',      assetCount: 4128,  dependencyCount: 9640,  healthScore: 62 },
    { key: 'L', label: 'Large',  sub: '10,000+ assets',     assetCount: 12400, dependencyCount: 26800, healthScore: 45 }
];

const TOTAL_STEPS = 8;

// Source/Target platform inputs. The stored value is the platform's DISPLAY
// LABEL (or the rep's free text under "Other"), never Platform_Key__c -- the
// configurator page renders this string verbatim to the prospect.
const PLATFORM_KEYS = ['SOURCE_PLATFORM', 'TARGET_PLATFORM'];
const PLATFORM_OTHER = '__other__';
const isBlank = (v) => v === undefined || v === null || String(v).trim() === '';
// Never let a wired/rejected/unmocked Apex call throw synchronously.
const safeCall = (fn, params) => {
    try { return Promise.resolve(fn(params)); } catch (e) { return Promise.resolve(null); }
};

export default class GtmConfigWizard extends LightningElement {
    /**
     * Controls visibility -- same contract as c-ma-config-customize.
     *
     * Also the one reliable moment to pull in what the parent already
     * loaded for an existing record. gtmConfigurator passes company,
     * industry, accent and state down as plain props, but they arrive
     * empty at mount -- the parent's own loadSavedConfiguration() is
     * still an in-flight Apex call at that point -- and this component
     * never read them again after that first, empty pass. The result was
     * a wizard that always opened blank on an existing link: no company,
     * no industry, and an accent that fell back to PS_RED, which happens
     * to be the first swatch in the list -- so it looked "stuck" there.
     * Seeding here instead, on open, means the parent's async load has
     * had time to resolve by the time a rep actually clicks in.
     */
    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(value) {
        this._isOpen = !!value;
        if (this._isOpen && this._knownRecordId && !this._seededFromRecord) {
            if (this.company) this._company = this.company;
            if (this.industry) this._industry = this.industry;
            if (this.state && Object.keys(this.state).length) {
                const merged = { ...this.state, ...this._state };
                // A platform the wizard only seeded from the offering default
                // must never beat what the reopened record actually stored.
                PLATFORM_KEYS.forEach((k) => {
                    if (this._defaultSeeded[k] && !isBlank(this.state[k])) {
                        merged[k] = this.state[k];
                        this._defaultSeeded[k] = false;
                    }
                });
                this._state = merged;
            }
            // The record's own stored override always wins here for an
            // existing link -- an override a prior rep set must survive the
            // next person opening this same link to edit something else, not
            // get silently replaced by whoever that happens to be. Only a
            // link saved before this field existed (nothing on file at all)
            // falls back to the current viewer's own email. This is
            // deliberately NOT folded into wiredUser()'s fill-if-blank
            // default below -- that one is guarded off for a known record
            // (see there) precisely so it can never race this seed.
            if (!this._notifyEmail) {
                this._notifyEmail = this.notifyEmail || (this._currentUser && this._currentUser.email) || '';
            }
            this._seededFromRecord = true;
        }
        // Accent gets its own guard, checked independently on every open
        // rather than folded into the flag above. A record can genuinely
        // have no accent on file yet (nothing chosen, nothing saved), and
        // a still-in-flight parent load arriving a beat late shouldn't
        // permanently lock the wizard onto a color that never actually
        // came from the record -- this keeps trying each time it opens
        // until a real value shows up, instead of failing once and never
        // being given another chance for the rest of the session.
        if (this._isOpen && this._knownRecordId && !isHex6(this._accent) && isHex6(this.accent)) {
            this._accent = this.accent;
        }
    }
    _isOpen = false;
    _seededFromRecord = false;

    /** Which offering's Configurator "defaults" content (swatches, default
     * source/target platform, demo numbers) this wizard reads and writes --
     * gtmConfigurator is the only known caller and is expected to always
     * pass its own effectiveOfferingKey by the time this renders. There is
     * deliberately no Migration-Accelerator (or any other) fallback here: a
     * caller that omits offeringKey must not silently read or save against
     * some other offering's defaults. Missing it is a bug in the caller,
     * surfaced loudly below rather than papered over. */
    @api offeringKey = '';

    get _offering() {
        if (!this.offeringKey) {
            // eslint-disable-next-line no-console
            console.error(
                '[gtmConfigWizard] offeringKey was not provided by the parent -- ' +
                'saves/reads have no offering to key off of. This is a caller bug, ' +
                'not an expected state.'
            );
        }
        return this.offeringKey || '';
    }

    /** The record's current values, as loaded by the parent. Read once,
     *  on open -- see the isOpen setter above. */
    @api company = '';
    @api industry = '';
    @api accent = '';
    @api state = {};
    /** The record's currently stored notification override, as loaded by the
     * parent via getConfiguration() -- read once, on open, same as company/
     * industry/state above (see the isOpen setter). Blank for a link saved
     * before Notify_Email__c existed and never resaved since. */
    @api notifyEmail = '';

    /** True when launched from the GTM Offerings Home page (Lightning),
     * with no live prospect page rendered behind this panel. False when
     * embedded in gtmConfigurator on the live/shared page itself. Changes
     * only the final step's copy and how the link's base URL is resolved
     * -- every other step behaves identically in both contexts. */
    @api standalone = false;

    /** Record Id of an existing saved link, when opened from "Continue a
     * saved link" (embedded mode, via the existing Customize button on a
     * link that's already been saved). Jumps straight to the review/send
     * step instead of the path chooser. */
    @api
    get savedRecordId() {
        return this._savedRecordId;
    }
    set savedRecordId(value) {
        this._savedRecordId = value || '';
        if (value) {
            this._knownRecordId = value;
            this._replacing = false;
            this._path = 'full';
            // A link that exists is finished. Opening on the last input step
            // made a completed link look half-built and made saving read as
            // "generate", when it is an update.
            this._step = TOTAL_STEPS + 1;
            this._existed = true;
            // The URL the rep already sent, captured before any edit in this
            // session changes what _buildUrl() would produce.
            this._existingUrl = this._buildUrl();
            // The Done screen's link box reads _generatedUrl (see
            // previewUrl), not _existingUrl -- the two were never the same
            // field. Nothing set _generatedUrl on this path, so opening an
            // existing link always showed an empty box until a save ran.
            // Since the URL for a known record never changes (same
            // ?cfgId=), the two can just be kept in sync here.
            this._generatedUrl = this._existingUrl;
        }
    }
    _savedRecordId = '';

    // ---------------------------------------------------------------- state

    @track _path = 'choose'; // 'choose' | 'quick' | 'full'
    @track _step = 1;        // 1-8, full walkthrough only
    @track _quickStep = 1;   // 1-2, quick link only

    @track _company = '';
    @track _industry = '';
    @track _accent = '';
    @track _state = {};

    @track _industries = [];
    @track _swatches = [];
    // Seeded with the fallback so the Environment step always has cards to
    // draw, even before getPageLayout resolves; overwritten in
    // connectedCallback() with the offering's own CMS presets when it has any.
    @track _sizePresets = DEFAULT_SIZE_PRESETS;
    _cmsDefaults = {};
    // Resolved display strings for the offering defaults (alias-resolved label,
    // else the raw text), and which _state keys are currently just that seed.
    _defaultDisplay = {};
    _defaultSeeded = {};
    @track _platformOptions = [];
    @track _platformOther = {};

    @track _selectedContact = null;

    // ---------------------------------------------- account/contact confirm
    // Visible confirm-or-create gate (issue account-contact-confirm): flips
    // true only once the rep has actually SEEN what will be linked -- an
    // existing Contact chosen from search, or an explicit "yes, create new"
    // confirmation with a real name+email. Never set silently just because
    // enough text happened to be typed.
    @track _accountContactConfirmed = false;
    // The company value the confirmation above was made against -- typing a
    // materially different company after confirming must re-open the gate,
    // not silently keep riding the old confirmation.
    _confirmedCompany = '';
    @track _confirmedNewContactName = '';
    @track _confirmedNewContactEmail = '';

    // Quick Link's own lightweight version of the same gate -- see §4 of
    // the task scope. No search UI, just an inline match/create note plus,
    // on the no-match branch, a required prospect-contact email.
    @track _quickAccountMatch = null;
    @track _quickContactEmail = '';
    _quickAccountLookupTimer;

    // Which deal this link is for. A client can have several at once --
    // different parts of the business, or one that closed and restarted --
    // so the rep says which rather than the system minting a new one every
    // time, which is what it used to do.
    @track _deals = [];
    @track _dealId = '';
    @track _dealsLoading = false;
    // The account the deals belong to, when it came from a typed company name
    // rather than a chosen contact.
    @track _matchedAccount = null;
    _dealLookupTimer;
    @track _contactSearchTerm = '';
    @track _contactResults = [];
    @track _contactSearchBusy = false;
    _contactSearchTimer = null;
    _contactSearchToken = 0;

    @track _sizePreset = 'M';
    @track _envAdvanced = false;

    @track _brandDomain = '';
    @track _brandLookupBusy = false;
    @track _brandLookupError = '';
    @track _brandLookupDone = false;

    /** 'auto' | 'custom' -- every link requires a password, no exceptions;
     *  there is deliberately no third "off" mode. Three real production
     *  links (TD Bank, Medtronic, LA Metro) were found running with none
     *  at all because that option existed and a rep once clicked it. */
    @track _passwordMode = 'auto';
    @track _generatedPassword = '';
    @track _customPassword = '';
    _passwordStepEntered = false;

    @track _saving = false;
    @track _saveError = '';
    /** Set when the server (GtmOpenOpportunityDuplicateCheck, issue #32)
     * found an already-open Opportunity for this Account+Contact+Offering
     * and this save wasn't already reusing it. Shape: { opportunityId,
     * opportunityName }. Non-null blocks the save UI in favor of the
     * "Continue with existing" / "Create new anyway" / cancel prompt --
     * enforced server-side, this is only the UX for that block. */
    @track _openDuplicate = null;
    // Whether the save being retried after that prompt should advance to
    // the done screen -- carried across the prompt so an explicit "Save"
    // click still lands on "done" once resolved, while an autosave's retry
    // still doesn't.
    _pendingSaveAdvance = true;
    // Set only by "Create new anyway" -- tells the server to skip the
    // open-duplicate check on the next attempt and mint a new Opportunity,
    // disambiguated by GtmDealNaming's existing same-Name date-append.
    // Cleared after every attempt so a later, unrelated save doesn't
    // silently inherit it.
    _forceNewOpportunity = false;
    @track _companyInvalid = false;
    @track _generatedUrl = '';
    @track _copyFeedback = 'Copy link';
    // Short-lived bypass token minted server-side (see saveConfiguration())
    // for the CREATING rep's own "Preview the page" click, immediately after
    // the password was set. Never part of _generatedUrl / the Copy box --
    // see the comment at the assignment site and previewHref below.
    @track _previewToken = '';

    _knownRecordId = '';
    _autoSaveTimer;
    // True when this wizard opened on a link that already existed.
    @track _existed = false;
    // The link that already exists, and whether the rep has chosen to leave it
    // alone and build another.
    @track _existingUrl = '';
    @track _existingActive = true;
    @track _replacing = false;
    _siteBaseUrl = '';
    _currentUser = null;
    /** "Notify me at" -- where THIS link's assessment-request alerts go.
     * Defaulted below (new link: current user, via wiredUser; existing
     * link: the record's own stored value, via the isOpen setter above),
     * always rep-editable, sent to saveConfiguration as notifyEmail. */
    @track _notifyEmail = '';

    @wire(getRecord, { recordId: USER_ID, fields: [USER_NAME_FIELD, USER_EMAIL_FIELD] })
    wiredUser({ data }) {
        if (!data) return;
        this._currentUser = {
            name: getFieldValue(data, USER_NAME_FIELD),
            email: getFieldValue(data, USER_EMAIL_FIELD)
        };
        const next = { ...this._state };
        let changed = false;
        if (!next.CONTACT_NAME && this._currentUser.name) {
            next.CONTACT_NAME = this._currentUser.name;
            changed = true;
        }
        if (!next.CONTACT_EMAIL && this._currentUser.email) {
            next.CONTACT_EMAIL = this._currentUser.email;
            changed = true;
        }
        if (changed) this._state = next;
        // New-link default only -- guarded off once a record id is known so
        // this can never race the isOpen seed above, which is what must win
        // for an EXISTING link (see the comment there). For a brand-new
        // link there is nothing to race: _knownRecordId is not set yet.
        if (!this._notifyEmail && !this._knownRecordId && this._currentUser.email) {
            this._notifyEmail = this._currentUser.email;
        }
    }

    // Chrome-offset positioning (standalone mode's fixed-header clearance)
    // now lives entirely in c-gtm-modal-shell, behind its own chrome-offset
    // prop -- passed below in gtmConfigWizard.html exactly when
    // this.standalone is true, the same condition this used to guard
    // locally. See docs/architecture/gtm-modal-shell.md.

    connectedCallback() {
        // The industry list is the framework's shared taxonomy.
        getIndustryProfiles({ offeringKey: FRAMEWORK_KEY, templateType: 'industry-chooser' })
            .then((rows) => { this._industries = rows || []; })
            // eslint-disable-next-line no-console
            .catch((err) => console.warn('[gtmConfigWizard] getIndustryProfiles:', JSON.stringify(err)));

        safeCall(listPlatforms)
            .then((rows) => { this._platformOptions = Array.isArray(rows) ? rows : []; })
            // eslint-disable-next-line no-console
            .catch((err) => console.warn('[gtmConfigWizard] listPlatforms:', JSON.stringify(err)));

        // The swatches and the platforms a link starts from are content on the
        // configurator's own defaults section, not a custom setting.
        getPageLayout({ offeringKey: this._offering, templateType: 'configurator', industryKey: null })
            .then((layout) => {
                const c = (layout && layout.content) || {};
                let swatches = [];
                try { swatches = JSON.parse(c['defaults::swatches'] || '[]'); } catch (e) { swatches = []; }
                this._swatches = swatches.map((sw) => ({
                    name: sw.name, hex: sw.hex, style: `background:#${sw.hex}`
                }));
                this._cmsDefaults = {
                    SOURCE_PLATFORM: c['defaults::defaultSourcePlatform'],
                    TARGET_PLATFORM: c['defaults::defaultTargetPlatform']
                };
                this._resolvePlatformDefaults();

                // The Environment step's S/M/L presets, same reuse-the-JSON-
                // editor pattern as swatches above. An offering that hasn't
                // authored any yet (or a malformed value) falls back to the
                // built-in defaults -- this offering's own historical numbers.
                let sizePresets;
                try { sizePresets = JSON.parse(c['defaults::sizePresets'] || '[]'); } catch (e) { sizePresets = []; }
                this._sizePresets = (Array.isArray(sizePresets) && sizePresets.length)
                    ? sizePresets
                    : DEFAULT_SIZE_PRESETS;
            })
            // eslint-disable-next-line no-console
            .catch((err) => console.warn('[gtmConfigWizard] getPageLayout:', JSON.stringify(err)));

        if (this.standalone) {
            getConfiguratorPageUrl()
                .then((url) => {
                    this._siteBaseUrl = url || '';
                    // savedRecordId's setter runs synchronously, well before
                    // this async call resolves -- if it already built a URL
                    // for a known record, it did so against window.location
                    // (the Lightning tab's own URL, not the public site's),
                    // since _siteBaseUrl was still blank at that point.
                    // Rebuild now that the real base is in.
                    if (this._knownRecordId) {
                        this._existingUrl = this._buildUrl();
                        this._generatedUrl = this._existingUrl;
                    }
                })
                // eslint-disable-next-line no-console
                .catch((err) => console.warn('[gtmConfigWizard] getConfiguratorPageUrl:', JSON.stringify(err)));
        }
    }

    // ------------------------------------------------- source/target platform

    /** Resolves each offering default to a display label through the platform
     * aliases (server-side), then seeds _state. Unresolved non-blank text is
     * kept as-is and shows under "Other". */
    _resolvePlatformDefaults() {
        PLATFORM_KEYS.forEach((k) => {
            const raw = this._cmsDefaults[k];
            if (isBlank(raw)) return;
            const text = String(raw).trim();
            safeCall(resolveDefaultLabel, { raw: text })
                .catch(() => null)
                .then((label) => {
                    this._defaultDisplay = { ...this._defaultDisplay, [k]: label || text };
                    this._seedPlatformDefault(k);
                });
        });
    }

    /** Re-checks _state at call time (inside the async callback): a value the
     * rep typed, or one loaded from a reopened link, is never overwritten. */
    _seedPlatformDefault(key) {
        if (!isBlank(this._state[key]) || isBlank(this._defaultDisplay[key])) return;
        this._state = { ...this._state, [key]: this._defaultDisplay[key] };
        this._defaultSeeded[key] = true;
    }

    _setPlatformValue(key, value) {
        const next = { ...this._state };
        if (isBlank(value)) delete next[key];
        else next[key] = value;
        this._state = next;
        this._defaultSeeded[key] = false;
    }

    get platformFields() {
        const labels = new Set(this._platformOptions.map((o) => o.label));
        return PLATFORM_KEYS.map((key) => {
            const value = this._state[key];
            const isOther = !!this._platformOther[key] || (!isBlank(value) && !labels.has(value));
            const selectValue = isOther ? PLATFORM_OTHER : (isBlank(value) ? '' : value);
            const options = [
                { value: '', label: 'Use offering default' },
                ...this._platformOptions.map((o) => ({ value: o.label, label: o.label })),
                { value: PLATFORM_OTHER, label: 'Other (type it)' }
            ].map((o) => ({ ...o, selected: o.value === selectValue }));
            return {
                key,
                label: key === 'SOURCE_PLATFORM' ? 'Source platform' : 'Target platform',
                options,
                showOther: isOther,
                otherValue: isBlank(value) ? '' : value
            };
        });
    }

    handlePlatformSelect(event) {
        const key = event.currentTarget.dataset.key;
        const v = event.currentTarget.value;
        if (v === PLATFORM_OTHER) {
            this._platformOther = { ...this._platformOther, [key]: true };
            this._setPlatformValue(key, '');
        } else {
            this._platformOther = { ...this._platformOther, [key]: false };
            this._setPlatformValue(key, v);
        }
    }

    handlePlatformOtherInput(event) {
        this._setPlatformValue(event.currentTarget.dataset.key, event.currentTarget.value);
    }

    // ------------------------------------------------------------- display

    get showChooser() { return this._path === 'choose'; }
    get showQuick()   { return this._path === 'quick'; }
    get showFull()    { return this._path === 'full'; }

    get headerLabel() {
        if (this._path === 'quick') return 'Quick link';
        if (this._path === 'full')  return `Step ${this._step} of ${TOTAL_STEPS}`;
        return 'New prospect page';
    }

    get progressStyle() {
        const pct = this._path === 'full' ? (this._step / TOTAL_STEPS) * 100 : 0;
        return `width:${pct}%;`;
    }

    // --------------------------------------------------------- path chooser

    handleChooseQuick() { this._path = 'quick'; this._quickStep = 1; }
    handleChooseFull()  { this._path = 'full';  this._step = 1; }

    handleBackToChooser() {
        this._path = 'choose';
        this._saveError = '';
    }

    // ------------------------------------------------------------- company

    get showContactSearch() {
        return !this._selectedContact;
    }

    get contactResults() {
        return this._contactResults.map((c) => ({
            id: c.contactId,
            summary: c.accountName ? `${c.name} · ${c.accountName}` : c.name
        }));
    }

    get hasContactResults() { return this._contactResults.length > 0; }

    get selectedContactSummary() {
        if (!this._selectedContact) return '';
        return this._selectedContact.accountName
            ? `${this._selectedContact.name} · ${this._selectedContact.accountName}`
            : this._selectedContact.name;
    }

    handleCompanyInput(event) {
        this._company = event.currentTarget.value;
        this._contactSearchTerm = this._company;
        this.lookupDealsForTypedCompany();
        if (this._companyInvalid && this._company.trim()) {
            this._companyInvalid = false;
            this._saveError = '';
        }
        // A materially different company than whatever was last confirmed
        // invalidates that confirmation -- the rep must see the match/create
        // state again for the company now on screen, not keep riding a
        // confirmation made against different text.
        if (this._accountContactConfirmed && this._company.trim() !== this._confirmedCompany) {
            this._accountContactConfirmed = false;
        }
        if (this._contactSearchTimer) window.clearTimeout(this._contactSearchTimer);
        const term = this._company.trim();
        if (term.length < 2) { this._contactResults = []; return; }
        this._contactSearchBusy = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._contactSearchTimer = window.setTimeout(() => this._runContactSearch(term), 300);
    }

    // --------------------------------- Step 1 visible confirm-or-create gate

    /** Shown whenever no existing Contact has been selected -- the rep must
     * either pick one from search above, or confirm a new Account/Contact
     * will be created here, before Step 1 is considered complete. */
    get showNewContactConfirm() {
        return !this._selectedContact;
    }

    get confirmNewContactCopy() {
        const company = (this._company || '').trim();
        return company
            ? `No existing contact found for ${company} — a new Account and Contact will be created. `
              + 'Confirm name and email to continue:'
            : 'Type a company name above, then confirm the new contact\'s name and email.';
    }

    get confirmedNewContactNameValue() { return this._confirmedNewContactName; }
    get confirmedNewContactEmailValue() { return this._confirmedNewContactEmail; }

    handleConfirmedNewContactNameInput(event) {
        this._confirmedNewContactName = event.currentTarget.value;
    }

    handleConfirmedNewContactEmailInput(event) {
        this._confirmedNewContactEmail = event.currentTarget.value;
    }

    get confirmedNewContactEmailInvalid() {
        const v = (this._confirmedNewContactEmail || '').trim();
        return !!v && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);
    }

    /** Enabled once there's a company, a non-blank email in a valid shape --
     * resolveContact() already requires a real email to do anything; this is
     * the point that requirement becomes visible to the rep instead of a
     * field that silently stays null. */
    get canConfirmNewContact() {
        return !!(this._company || '').trim()
            && !!(this._confirmedNewContactEmail || '').trim()
            && !this.confirmedNewContactEmailInvalid;
    }

    get confirmNewContactDisabled() {
        return !this.canConfirmNewContact;
    }

    handleConfirmNewContact() {
        if (!this.canConfirmNewContact) return;
        this._confirmedCompany = (this._company || '').trim();
        this._accountContactConfirmed = true;
    }

    async _runContactSearch(term) {
        const token = ++this._contactSearchToken;
        try {
            const results = await searchContacts({ searchTerm: term });
            if (token !== this._contactSearchToken) return;
            this._contactResults = results;
        } catch (e) {
            if (token !== this._contactSearchToken) return;
            this._contactResults = [];
        } finally {
            if (token === this._contactSearchToken) this._contactSearchBusy = false;
        }
    }

    handleSelectContact(event) {
        const id = event.currentTarget.dataset.id;
        const match = this._contactResults.find((c) => c.contactId === id);
        if (!match) return;
        this._selectedContact = {
            id: match.contactId,
            name: match.name,
            email: match.email,
            accountId: match.accountId,
            accountName: match.accountName
        };
        if (match.accountName) this._company = match.accountName;
        this._contactResults = [];
        // Picking an existing Contact from search IS the confirmed state --
        // no separate click needed, the rep is already looking straight at
        // who this will attach to.
        this._confirmedCompany = (this._company || '').trim();
        this._accountContactConfirmed = true;
        this.loadDeals(match.accountId);
    }

    // ---------------------------------------------------------------- deals

    /**
     * A typed company name also finds the deals.
     *
     * Picking a contact was the only thing that supplied an account, so a rep
     * who typed the client instead never saw the picker and got a new deal
     * created without being asked -- the same gap this feature exists to
     * close, left open for half the people using it.
     */
    lookupDealsForTypedCompany() {
        if (this._selectedContact) return;
        const name = (this._company || '').trim();
        clearTimeout(this._dealLookupTimer);
        if (name.length < 2) {
            this._matchedAccount = null;
            this._deals = [];
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._dealLookupTimer = setTimeout(async () => {
            try {
                const match = await findAccountByName({ company: name });
                this._matchedAccount = match || null;
                if (match) await this.loadDeals(match.accountId);
                else this._deals = [];
            } catch (e) {
                this._matchedAccount = null;
                this._deals = [];
            }
        }, 350);
    }

    get matchedAccountNote() {
        if (this._selectedContact || !this._matchedAccount) return '';
        return this._matchedAccount.isExact
            ? `Deals below are ${this._matchedAccount.name}'s.`
            : `Closest account is ${this._matchedAccount.name} — saving under a `
              + 'different spelling creates a new account instead.';
    }

    async loadDeals(accountId) {
        this._deals = [];
        this._dealId = '';
        if (!accountId) return;
        this._dealsLoading = true;
        try {
            this._deals = (await getAccountDeals({ accountId })) || [];
            // Default to the deal that is already open rather than to a new
            // one. Two contacts at the same client, saved back to back, used to
            // produce two opportunities -- the second called "<Client> —
            // <Offering> (2026-09-05)" -- because "new deal" was preselected
            // and nothing made a rep notice. One open deal is not a choice, so
            // it is made for them; two or more is a real choice, so it is not.
            const open = this._deals.filter((d) => !d.isClosed);
            this._dealId = open.length === 1 ? open[0].opportunityId : '';
        } catch (e) {
            // Not being able to list the deals is not a reason to block the
            // link: leaving the choice empty still creates a new one, which is
            // the behaviour that existed before there was a choice at all.
            // eslint-disable-next-line no-console
            console.warn('[gtmConfigWizard] getAccountDeals:', JSON.stringify(e));
        } finally {
            this._dealsLoading = false;
        }
    }

    get dealOptions() {
        return this._deals.map((d) => {
            const chosen = this._dealId === d.opportunityId;
            const bits = [d.stage];
            if (d.isClosed) bits.push('closed');
            if (d.linkCount > 0) {
                bits.push(d.linkCount === 1 ? 'already has a link' : `${d.linkCount} links already`);
            }
            return {
                id: d.opportunityId,
                name: d.name,
                meta: bits.filter(Boolean).join(' · '),
                // A closed deal is offered but not encouraged: a restarted
                // engagement is usually a new deal, not the old one reopened.
                cls: 'mw-deal' + (chosen ? ' sel' : '') + (d.isClosed ? ' closed' : ''),
                warn: d.linkCount > 0
            };
        });
    }

    get hasDeals() { return this._deals.length > 0; }
    get newDealClass() { return 'mw-deal' + (this._dealId ? '' : ' sel'); }

    /** The warning only matters once they have actually chosen that deal. */
    get dealAlreadyLinked() {
        if (!this._dealId) return false;
        const hit = this._deals.find((d) => d.opportunityId === this._dealId);
        return !!hit && hit.linkCount > 0;
    }

    get dealWarning() {
        if (!this.dealAlreadyLinked) return '';
        return 'This deal already has a link. Saving here makes a second one — '
             + 'open the existing link instead if you meant to change it.';
    }

    /**
     * Said only when choosing "new deal" would actually add one.
     *
     * A rep sending a second contact at the same client a page of their own is
     * doing something ordinary; ending up with two opportunities for it is not.
     */
    get newDealWarning() {
        if (this._dealId) return '';
        const open = this._deals.filter((d) => !d.isClosed);
        if (!open.length) return '';
        return open.length === 1
            ? `${open[0].name} is already open for this client. A new deal here means two.`
            : `This client already has ${open.length} open deals. A new deal here makes another.`;
    }

    get showNewDealWarning() { return !!this.newDealWarning; }

    handlePickDeal(event) {
        this._dealId = event.currentTarget.dataset.id;
    }

    handlePickNewDeal() {
        this._dealId = '';
    }

    handleChangeContact() {
        this._selectedContact = null;
        this._deals = [];
        this._dealId = '';
        // Reopens the gate -- a rep who changes their mind on the selected
        // Contact must go through the match/create prompt again, not keep
        // the confirmation that Contact earned.
        this._accountContactConfirmed = false;
    }

    // ------------------------------------------------------------ industry

    get industryChips() {
        return this._industries.map((ind) => ({
            key: ind.industryKey,
            label: ind.industryLabel,
            chipClass: this._industry === ind.industryKey ? 'mw-chip sel' : 'mw-chip'
        }));
    }

    get genericChipClass() {
        return !this._industry ? 'mw-chip sel' : 'mw-chip';
    }

    handleIndustryPick(event) {
        this._industry = event.currentTarget.dataset.key || '';
    }

    // ---------------------------------------------------------------- brand

    handleBrandDomainInput(event) {
        this._brandDomain = event.currentTarget.value;
        this._brandLookupError = '';
    }

    async handleBrandLookup() {
        const domain = normalizeDomain(this._brandDomain);
        if (!domain) {
            this._brandLookupError = 'Enter a domain, e.g. acme.com.';
            return;
        }
        this._brandLookupBusy = true;
        this._brandLookupError = '';
        this._brandLookupDone = false;
        try {
            const dataUri = await fetchLogoDataUri({ domain });
            if (!dataUri) {
                this._brandLookupError = "Couldn't find a logo for that domain — pick a shade below instead.";
                return;
            }
            const outcome = await dominantColorFromDataUri(dataUri);
            if (outcome) {
                this._accent = outcome;
                this._brandLookupDone = true;
            } else {
                this._brandLookupError = "Found a logo, but couldn't read a colour from it — pick a shade below.";
            }
        } catch (e) {
            this._brandLookupError = e?.body?.message || 'That lookup failed. Please try again.';
        } finally {
            this._brandLookupBusy = false;
        }
    }

    handleSwatch(event) {
        this._accent = event.currentTarget.dataset.hex;
        this._brandLookupDone = false;
    }

    get accentHex() {
        return isHex6(this._accent) ? `#${String(this._accent).replace(/^#/, '')}` : '#EE3D23';
    }

    get accentSwatchStyle() {
        return `background:${this.accentHex};`;
    }

    // ------------------------------------------------------------- proof

    get sizeCards() {
        return this._sizePresets.map((p) => ({
            key: p.key,
            letter: p.key,
            label: p.label,
            sub: p.sub,
            cardClass: this._sizePreset === p.key ? 'mw-preset sel' : 'mw-preset'
        }));
    }

    handleSizePick(event) {
        const key = event.currentTarget.dataset.key;
        this._sizePreset = key;
        const p = this._sizePresets.find((sp) => sp.key === key);
        if (!p) return;
        this._state = {
            ...this._state,
            ASSET_COUNT: String(p.assetCount),
            DEPENDENCY_COUNT: String(p.dependencyCount),
            HEALTH_SCORE: String(p.healthScore)
        };
    }

    get envAdvancedToggleLabel() {
        return this._envAdvanced ? 'Use size presets instead' : "I know the exact numbers";
    }

    handleEnvAdvancedToggle() {
        this._envAdvanced = !this._envAdvanced;
    }

    handleEnvFieldInput(event) {
        const key = event.currentTarget.dataset.key;
        this._state = { ...this._state, [key]: event.currentTarget.value };
    }

    get assetsValue()   { return this._state.ASSET_COUNT || ''; }
    get depsValue()     { return this._state.DEPENDENCY_COUNT || ''; }
    get healthValue()   { return this._state.HEALTH_SCORE || ''; }

    // ------------------------------------------------------------- note

    handleNoteInput(event) {
        this._state = { ...this._state, CUSTOM_NOTE: event.currentTarget.value };
    }

    get noteValue() { return this._state.CUSTOM_NOTE || ''; }

    // ---------------------------------------------------------------- you

    handleContactFieldInput(event) {
        const key = event.currentTarget.dataset.key;
        this._state = { ...this._state, [key]: event.currentTarget.value };
    }

    get contactNameValue()  { return this._state.CONTACT_NAME || ''; }
    get contactEmailValue() { return this._state.CONTACT_EMAIL || ''; }
    get bookingUrlValue()   { return this._state.BOOKING_URL || ''; }

    // ----------------------------------------------------------- password

    get passwordDisplay() {
        return this._passwordMode === 'custom' ? this._customPassword : this._generatedPassword;
    }

    get passwordKeepClass()   { return this._passwordMode === 'auto'   ? 'mw-chip sel' : 'mw-chip'; }
    get passwordCustomClass() { return this._passwordMode === 'custom' ? 'mw-chip sel' : 'mw-chip'; }
    get showCustomPasswordInput() { return this._passwordMode === 'custom'; }

    _ensureGeneratedPassword() {
        if (this._generatedPassword) return;
        const stem = (this._company || 'link').replace(/[^a-zA-Z]/g, '').slice(0, 5).toLowerCase() || 'link';
        const digits = Math.floor(1000 + Math.random() * 9000);
        this._generatedPassword = `${stem}-${digits}`;
    }

    handlePasswordKeep()   { this._passwordMode = 'auto'; }
    handlePasswordCustom() {
        this._passwordMode = 'custom';
        if (!this._customPassword) this._customPassword = this._generatedPassword;
    }
    handleCustomPasswordInput(event) {
        this._customPassword = event.currentTarget.value;
    }

    // ---------------------------------------------------- notify email

    /** Where THIS link's assessment-request alerts go. A future chat-driven
     * (Gus) surface could set the same GTM_Saved_Configuration__c.
     * Notify_Email__c field this writes to -- this plain input is the real,
     * working mechanism today; it does not wait on or depend on that. */
    get notifyEmailValue() { return this._notifyEmail || ''; }

    handleNotifyEmailInput(event) {
        this._notifyEmail = event.currentTarget.value;
    }

    /** Blank is fine -- saveConfiguration() defaults an empty override to
     * the creating user's email server-side. Only a non-blank value that
     * doesn't look like a real email blocks generating the link. */
    get notifyEmailInvalid() {
        const v = (this._notifyEmail || '').trim();
        return !!v && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);
    }

    // -------------------------------------------------------------- nav

    /** Steps a rep has landed on, in either direction or via a direct jump
     * -- drives the "done" dot state below. A plain array (not a Set) so
     * reassigning it is what LWC's @track reactivity actually watches. */
    @track _visitedSteps = [1];

    _markVisited(n) {
        if (!this._visitedSteps.includes(n)) this._visitedSteps = [...this._visitedSteps, n];
    }

    get canGoBackFull() { return this._step > 1; }

    get isStep1() { return this._step === 1; }
    get isStep2() { return this._step === 2; }
    get isStep3() { return this._step === 3; }
    get isStep4() { return this._step === 4; }
    get isStep5() { return this._step === 5; }
    get isStep6() { return this._step === 6; }
    get isStep7() { return this._step === 7; }
    get isStep8() { return this._step === 8; }

    /** Required, not just visited: company (Step 1) and the rep's own
     * contact details (Step 6) -- everything else stays genuinely optional,
     * including industry ("Not sure — use general content" is itself a
     * valid, complete answer, not a blank one). This is the one thing
     * that's actually enforced; every other step is free to skip or jump
     * past, per Isiah's ask -- reps can move around freely, only
     * *generating the link* is held back until this is true. */
    get canGenerateLink() {
        return !!(this._company || '').trim()
            && this._accountContactConfirmed
            && !!(this._state.CONTACT_NAME || '').trim()
            && !!(this._state.CONTACT_EMAIL || '').trim()
            && !this.notifyEmailInvalid;
    }

    get generateBlockedReason() {
        if (this.canGenerateLink) return '';
        if (!(this._company || '').trim()) return 'Add a company name (Step 1) before generating a link.';
        if (!this._accountContactConfirmed) {
            return 'Confirm the Account/Contact that will be linked (Step 1) before generating a link.';
        }
        if (this.notifyEmailInvalid) return 'Enter a valid notification email (Step 7), or clear it, before generating a link.';
        return 'Add your name and email (Step 6) before generating a link.';
    }

    /** Numbered, clickable progress rail -- lets a rep jump straight to any
     * step instead of only stepping through with Next/Back. dotState drives
     * the CSS class: 'current', 'needs' (a required step still incomplete),
     * 'done' (visited, or optional and already has a value), or 'todo'. */
    get stepDots() {
        const labels = ['Company', 'Industry', 'Colour', 'Their environment', 'Note', 'Contact', 'Password', 'Review'];
        const requiredOk = [
            !!(this._company || '').trim() && this._accountContactConfirmed,
            true,
            true,
            true,
            true,
            !!(this._state.CONTACT_NAME || '').trim() && !!(this._state.CONTACT_EMAIL || '').trim(),
            true,
            true
        ];
        return labels.map((label, i) => {
            const n = i + 1;
            let dotState = 'todo';
            if (n === this._step) dotState = 'current';
            else if (!requiredOk[i]) dotState = 'needs';
            else if (this._visitedSteps.includes(n)) dotState = 'done';
            return { n, label, dotClass: `mw-dot mw-dot--${dotState}` };
        });
    }

    handleStepJump(event) {
        const n = parseInt(event.currentTarget.dataset.step, 10);
        if (!n || n === this._step) return;
        this._step = n;
        this._markVisited(n);
        if (n === 7) this._ensureGeneratedPassword();
        this._autoSave();
    }

    handleFullNext() {
        if (this._step < TOTAL_STEPS) {
            this._step += 1;
            this._markVisited(this._step);
            if (this._step === 7) this._ensureGeneratedPassword();
            this._autoSave();
        } else {
            if (!this.canGenerateLink) {
                this._companyInvalid = !(this._company || '').trim();
                this._saveError = this.generateBlockedReason;
                return;
            }
            this._save();
        }
    }

    handleFullBack() {
        if (this._step > 1) {
            this._step -= 1;
            this._markVisited(this._step);
            this._autoSave();
        }
    }

    handleFullSkip() {
        this.handleFullNext();
    }

    get nextLabel() {
        if (this._step !== TOTAL_STEPS) return 'Next →';
        if (this._saving) return 'Saving…';
        // Updating a link someone already has is a different promise from
        // generating one, so the button says which it is.
        return this._knownRecordId ? 'Save changes' : 'Save & generate link';
    }

    // ─── the done screen, for a link that already existed ─────────────────────

    get doneHeadline() {
        if (!this._existed) return `Link generated ${this.doneCompanyLine}`;
        const who = (this._company || '').trim();
        return who ? `${who}'s link is live` : 'This link is live';
    }

    get doneSubline() {
        return this._existed
            ? 'Edit any of the details and save — whoever has this link sees the change on their next load. The link itself does not change.'
            : '';
    }

    get showEditDetails() { return this._existed && this.isDone; }

    /** Back into the form on the link that already exists. */
    handleEditDetails() {
        if (this._path === 'quick') {
            this._quickStep = 1;
            return;
        }
        this._step = 1;
        this._markVisited(1);
    }

    /** "Change path" is offered on Quick's Done screen only; Full shows its own
     * on every step. Data is never cleared by switching path. */
    get showDoneChangePath() { return this._path === 'quick'; }

    get nextDisabled() {
        return this._saving || (this._step === TOTAL_STEPS && !this.canGenerateLink);
    }

    get showSkip() {
        return this._path === 'full' && [3, 4, 5, 7].includes(this._step);
    }

    // ------------------------------------------------------- quick link

    handleQuickCompanyInput(event) {
        this._company = event.currentTarget.value;
        if (this._companyInvalid && this._company.trim()) this._companyInvalid = false;
        this._lookupQuickAccount();
    }

    handleQuickIndustryPick(event) {
        this._industry = event.currentTarget.dataset.key || '';
    }

    /** Quick Link's lightweight version of the same visible confirm/create
     * step Full walkthrough gets -- see §4 of the task scope. Debounced,
     * same pattern as lookupDealsForTypedCompany, reusing the same
     * findAccountByName() Apex method rather than a separate search UI
     * (a full contact search here would defeat Quick Link's whole point).
     *
     * A prior lookup's match must never survive into a newer, unresolved
     * one -- this used to only clear _quickAccountMatch when the field
     * dropped below 2 characters, so a match found for an earlier,
     * shorter/different typed value (e.g. a mid-word pause during a fuzzy
     * substring lookup) stayed truthy for the *entire* 350ms of every
     * subsequent keystroke's fresh debounce, incorrectly satisfying
     * quickNeedsContactEmail/quickBlockedReason and letting Generate run
     * with no email collected for a company that, by the time of the
     * click, had no real match at all -- this is what let a bare "Brand
     * New Prospect Co" create a real Account/Opportunity with no email.
     * Clearing eagerly here, on every keystroke, means the gate defaults
     * back to "needs email" for the whole in-flight window, not just at
     * the two edges of the old logic. */
    _lookupQuickAccount() {
        clearTimeout(this._quickAccountLookupTimer);
        this._quickAccountMatch = null;
        const name = (this._company || '').trim();
        if (name.length < 2) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._quickAccountLookupTimer = setTimeout(async () => {
            try {
                const match = await findAccountByName({ company: name });
                // The debounce can still be beaten by a slower callout from
                // an even-newer keystroke's own timer if this stale
                // response arrives last; only apply it if the company text
                // hasn't changed since this lookup was kicked off.
                if ((this._company || '').trim() === name) {
                    this._quickAccountMatch = match || null;
                }
            } catch (e) {
                if ((this._company || '').trim() === name) {
                    this._quickAccountMatch = null;
                }
            }
        }, 350);
    }

    get quickAccountNote() {
        const company = (this._company || '').trim();
        if (!company) return '';
        return this._quickAccountMatch
            ? `Matches existing account: ${this._quickAccountMatch.name}. This link will attach to it.`
            : `No existing account found — a new Account (${company}) will be created.`;
    }

    /** The rep sees the match-vs-create state plainly either way; the extra
     * required input only appears on the no-match branch, since that is the
     * one case resolveContact() otherwise has nothing to work with. */
    get quickNeedsContactEmail() {
        return !!(this._company || '').trim() && !this._quickAccountMatch;
    }

    get quickContactEmailValue() { return this._quickContactEmail; }

    handleQuickContactEmailInput(event) {
        this._quickContactEmail = event.currentTarget.value;
        if (this._saveError) this._saveError = '';
    }

    get quickContactEmailInvalid() {
        const v = (this._quickContactEmail || '').trim();
        return !!v && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);
    }

    /** Blocks Generate exactly on the no-match branch, mirroring Full
     * walkthrough's canGenerateLink gate -- an exact match needs nothing
     * further, since proceeding to Generate IS the confirmation there. */
    get quickBlockedReason() {
        if (!(this._company || '').trim()) return 'Add a company name to continue.';
        if (this.quickNeedsContactEmail) {
            const v = (this._quickContactEmail || '').trim();
            if (!v) return 'Add a prospect contact email so we can find or create a Contact.';
            if (this.quickContactEmailInvalid) return 'Enter a valid prospect contact email to continue.';
        }
        return '';
    }

    /** Only pre-disables for the no-match branch's required email -- a
     * blank company stays click-to-validate, same as it always was, so the
     * rep still gets the explicit "Add a company name to continue" message
     * on click rather than a silently inert button. */
    get quickGenerateDisabled() {
        if (this._saving) return true;
        if (!this.quickNeedsContactEmail) return false;
        const v = (this._quickContactEmail || '').trim();
        return !v || this.quickContactEmailInvalid;
    }

    async handleQuickGenerate() {
        if (this.quickBlockedReason) {
            this._companyInvalid = !(this._company || '').trim();
            this._saveError = this.quickBlockedReason;
            return;
        }
        // Defaults for everything the quick path skips: the medium preset
        // from whichever list is resolved (CMS-or-fallback), falling back
        // further to the first available preset if this offering's own list
        // has no 'M' key.
        const preset = this._sizePresets.find((p) => p.key === 'M') || this._sizePresets[0];
        // Defaults first, then only non-blank typed keys: a blank/undefined
        // platform must never clobber (or be written over) the offering default.
        const defaults = {};
        PLATFORM_KEYS.forEach((k) => {
            const d = this._defaultDisplay[k] || this._cmsDefaults[k];
            if (!isBlank(d)) defaults[k] = d;
        });
        const typed = { ...this._state };
        PLATFORM_KEYS.forEach((k) => { if (isBlank(typed[k])) delete typed[k]; });
        this._state = {
            ...defaults,
            ...typed,
            ASSET_COUNT: this._state.ASSET_COUNT || String(preset.assetCount),
            DEPENDENCY_COUNT: this._state.DEPENDENCY_COUNT || String(preset.dependencyCount),
            HEALTH_SCORE: this._state.HEALTH_SCORE || String(preset.healthScore)
        };
        if (!isHex6(this._accent)) this._accent = PS_RED;
        this._ensureGeneratedPassword();
        this._quickStep = 2;
        await this._save();
    }

    // ------------------------------------------------------------- save

    /**
     * Save what has been filled in so far, without leaving the step.
     *
     * A wizard that only writes at the end loses everything to a closed tab,
     * and the first save is what creates the record the link points at — so
     * progressing a step is the natural moment to commit. Quiet on failure:
     * the rep is mid-form, and the real save at the end reports properly.
     */
    /** Confirmed-new fields (either path) only ride in the payload when
     * there is no _selectedContact -- an exact-picked Contact is already the
     * real record via contactId, so it always wins over anything typed. */
    _payloadContactName() {
        if (this._selectedContact) return this._selectedContact.name;
        if (this._path === 'quick') return null; // Quick Link collects email only, not a name
        return this._accountContactConfirmed ? (this._confirmedNewContactName || '').trim() || null : null;
    }

    _payloadContactEmail() {
        if (this._selectedContact) return this._selectedContact.email || null;
        if (this._path === 'quick') return (this._quickContactEmail || '').trim() || null;
        return this._accountContactConfirmed ? (this._confirmedNewContactEmail || '').trim() || null : null;
    }

    _autoSave() {
        // Nothing to save a link against until there is a company on it.
        if (this._saving || !(this._company || '').trim()) return;
        clearTimeout(this._autoSaveTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._autoSaveTimer = setTimeout(() => { this._save(false); }, 400);
    }

    /**
     * @param {boolean} advance  Move to the done screen. False for the
     *   step-by-step autosave, which must leave the rep where they are.
     */
    async _save(advance = true) {
        this._saving = true;
        this._saveError = '';
        this._pendingSaveAdvance = advance;
        try {
            // Every save needs a real password value ready, not just the
            // final one on step 7 -- autosave fires from step 1 onward
            // (see _scheduleAutoSave), and a rep who never reaches step 7
            // still creates a real record. This is what actually closed
            // the gap that left three production links (TD Bank,
            // Medtronic, LA Metro) with none at all -- removing the "off"
            // chip alone would not have, since autosave could still send
            // a blank password before the rep ever got there.
            this._ensureGeneratedPassword();
            const linkPassword = this._passwordMode === 'custom' ? this._customPassword : this._generatedPassword;

            const url = this._buildUrl();
            const { recordId, previewToken } = await saveConfiguration({
                input: {
                    recordId: this._knownRecordId || null,
                    offering: this._offering,
                    industry: this._industry,
                    company: (this._company || '').trim(),
                    generatedUrl: url,
                    // The accent is part of what this link looks like, but it
                    // lived only in the generated URL -- so a record could not
                    // rebuild its own page without the query string. It rides
                    // in the payload now, alongside everything else.
                    configPayload: JSON.stringify({ ...this._state, ACCENT: this._accent || '' }),
                    clientContactName: this._payloadContactName(),
                    clientContactEmail: this._payloadContactEmail(),
                    contactId: this._selectedContact ? this._selectedContact.id : null,
                    // Blank means "a new deal" -- which is what this always
                    // did, silently, whether or not the client already had one.
                    opportunityId: this._dealId || null,
                    accountId: this._selectedContact ? this._selectedContact.accountId : null,
                    // Only true immediately after the rep explicitly chose
                    // "Create new anyway" on the open-duplicate prompt --
                    // see handleCreateNewAnyway().
                    forceNewOpportunity: this._forceNewOpportunity === true,
                    linkPassword,
                    // Blank goes up as null, same as every other optional
                    // field here -- saveConfiguration() defaults a blank
                    // override to the creating user's email itself, so this
                    // component doesn't need to know that rule.
                    notifyEmail: (this._notifyEmail || '').trim() || null,
                    website: this._brandDomain || null,
                    accountIndustry: this._industry || null
                }
            });
            this._knownRecordId = recordId;
            this._generatedUrl = this._buildUrl();
            // The token bypasses this same link's password gate, so it must
            // never ride on _generatedUrl -- that field is what populates
            // the "Copy the link" box a rep pastes and sends onward, and
            // anyone who received that box's contents with a live token
            // attached would inherit the rep's own bypass. It is only ever
            // appended, separately, to the "Preview the page" anchor href
            // (see previewHref below). A resave that doesn't touch the
            // password returns no token; the prior one (if any) is cleared
            // rather than left stale for a URL that no longer matches it.
            this._previewToken = previewToken || '';
            if (advance) {
                if (this._path === 'full') this._step = TOTAL_STEPS + 1; // "done" screen
                // Quick too, so its Done screen offers "Edit the details".
                this._existed = true;
            }
            // The URL goes up with the id: the page this wizard sits on
            // restores itself from query params, so without it a refresh
            // lands on a bare configurator and the work looks lost.
            this.dispatchEvent(new CustomEvent('configsaved', {
                detail: { recordId, generatedUrl: this._generatedUrl }
            }));
            this._forceNewOpportunity = false;
        } catch (e) {
            const duplicate = this._parseOpenDuplicate(e);
            if (duplicate) {
                // Server-side block (GtmOpenOpportunityDuplicateCheck) --
                // surface the two-choice prompt instead of a dead-end error,
                // even on a silent autosave: an autosave that goes unnoticed
                // and un-resolved simply leaves the save pending, which is
                // safer than letting an autosave slip a second Opportunity
                // in underneath the rep.
                this._openDuplicate = duplicate;
                this._forceNewOpportunity = false;
            } else if (advance) {
                // An autosave failing mid-form is not something to interrupt
                // for; the explicit save at the end surfaces it.
                this._saveError = e?.body?.message || 'That link did not save. Please try again.';
                this._forceNewOpportunity = false;
            }
        } finally {
            this._saving = false;
        }
    }

    /** Parses the small JSON payload GtmOpenOpportunityDuplicateCheck's
     * OpenDuplicateException sends as its AuraHandledException message --
     * not free text -- so this prompt can be shown instead of a raw error.
     * Returns null for any other error shape (including a normal DML
     * failure message, which is never valid JSON). */
    _parseOpenDuplicate(e) {
        const message = e?.body?.message;
        if (!message) return null;
        try {
            const parsed = JSON.parse(message);
            if (parsed && parsed.type === 'OPEN_DUPLICATE' && parsed.opportunityId) {
                return { opportunityId: parsed.opportunityId, opportunityName: parsed.opportunityName || 'this deal' };
            }
        } catch (parseErr) {
            // Not JSON -- a normal error message, not this prompt.
        }
        return null;
    }

    /** "Continue with existing" -- reuses the Opportunity the check found,
     * creates nothing new, and retries the exact save that was blocked. */
    async handleContinueWithExisting() {
        if (!this._openDuplicate) return;
        this._dealId = this._openDuplicate.opportunityId;
        this._openDuplicate = null;
        await this._save(this._pendingSaveAdvance);
    }

    /** "Create new anyway" -- tells the server to skip the check this one
     * time. Disambiguation is GtmDealNaming's existing same-Name date-append,
     * not a new prompted label: the rep is told that up front (see the
     * template copy next to this action), never asked to type one. */
    async handleCreateNewAnyway() {
        if (!this._openDuplicate) return;
        this._openDuplicate = null;
        this._forceNewOpportunity = true;
        await this._save(this._pendingSaveAdvance);
    }

    /** Cancel/dismiss -- takes no action at all; the save stays blocked
     * until the rep picks one of the two real choices above. */
    handleCancelDuplicatePrompt() {
        this._openDuplicate = null;
    }

    /**
     * The link a rep sends.
     *
     * Once the record exists the link is just its id. The page asks Salesforce
     * for the rest, which keeps the client's company, numbers and brand colour
     * out of browser history, referrer headers and forwarded messages -- and
     * means an edit made afterwards shows up on the prospect's next load
     * instead of needing a newly generated link.
     *
     * Before the first save there is no record to point at, so the long form
     * is still built: it is what the preview and the pre-save state need. Old
     * long links keep working, because the page still reads these parameters
     * and only lets the record override them.
     */
    get hasOpenDuplicate() {
        return !!this._openDuplicate;
    }

    get openDuplicateName() {
        return this._openDuplicate ? this._openDuplicate.opportunityName : '';
    }

    _buildUrl() {
        let base = this._siteBaseUrl;
        if (!base) {
            try { base = window.location.origin + window.location.pathname; } catch (e) { base = ''; }
        }
        if (this._knownRecordId) {
            return `${base}?cfgId=${encodeURIComponent(this._knownRecordId)}`;
        }
        const params = [];
        const push = (k, v) => { if (v) params.push(`${k}=${encodeURIComponent(v)}`); };
        // Pre-save share link: the saved record doesn't exist yet to stamp
        // its own offering (that only happens once _knownRecordId exists,
        // above), so the offering has to ride in the URL itself, or a
        // reopened pre-save link silently loses which offering it was for.
        push('offering', this._offering);
        push('company', (this._company || '').trim());
        push('industry', this._industry);
        if (isHex6(this._accent)) push('accent', String(this._accent).replace(/^#/, ''));
        push('rep', this._state.CONTACT_EMAIL);
        push('repname', this._state.CONTACT_NAME);
        push('book', this._state.BOOKING_URL);
        push('src', this._state.SOURCE_PLATFORM);
        push('tgt', this._state.TARGET_PLATFORM);
        push('assets', this._state.ASSET_COUNT);
        push('deps', this._state.DEPENDENCY_COUNT);
        push('health', this._state.HEALTH_SCORE);
        push('note', this._state.CUSTOM_NOTE);
        return params.length ? `${base}?${params.join('&')}` : base;
    }

    // -------------------------------------------------------------- done

    get isDone() {
        return (this._path === 'full' && this._step > TOTAL_STEPS) || (this._path === 'quick' && this._quickStep === 2 && !!this._generatedUrl);
    }

    get doneCompanyLine() {
        return this._company ? `for ${this._company}` : '';
    }

    handleCopyLink() {
        const url = this._generatedUrl;
        const done = (ok) => {
            this._copyFeedback = ok ? 'Copied ✓' : 'Press ⌘/Ctrl-C';
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            window.setTimeout(() => { this._copyFeedback = 'Copy link'; }, 1600);
        };
        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(url).then(() => done(true), () => done(false));
                return;
            }
        } catch (e) { /* fall through */ }
        const input = this.template.querySelector('.mw-url');
        if (input) { input.removeAttribute('readonly'); input.focus(); input.select(); input.setAttribute('readonly', ''); }
        done(false);
    }

    get previewUrl() { return this._generatedUrl; }

    /**
     * Used ONLY by the "Preview the page ↗" anchor's href -- never by the
     * "Copy the link" box, which stays bound to the token-free previewUrl
     * above. This is a live bypass credential for the rep's own first
     * click, not something safe to hand a prospect: appending it here,
     * separately, is what keeps it off the string reps actually send.
     */
    get previewHref() {
        if (!this._previewToken) return this._generatedUrl;
        const sep = this._generatedUrl.includes('?') ? '&' : '?';
        return `${this._generatedUrl}${sep}saToken=${encodeURIComponent(this._previewToken)}`;
    }

    get showPreviewLink() { return this.standalone; }

    handleFinish() {
        this.dispatchEvent(new CustomEvent('done', {
            detail: {
                recordId: this._knownRecordId,
                generatedUrl: this._generatedUrl,
                company: this._company
            }
        }));
        this.handleClose();
    }

    // -------------------------------------------------------------- close

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}

/** "https://www.acme.com/about" -> "acme.com" */
function normalizeDomain(value) {
    let v = String(value || '').trim().toLowerCase();
    if (!v) return '';
    v = v.replace(/^https?:\/\//, '').replace(/^www\./, '').split('/')[0].split('?')[0];
    return /^[a-z0-9.-]+\.[a-z]{2,}$/.test(v) ? v : '';
}

/** Same dominant-color-from-image technique used in maConfigCustomize,
 * factored out here since this component doesn't otherwise share code
 * with it (no shared base class in LWC). */
function dominantColorFromDataUri(dataUri) {
    return new Promise((resolve) => {
        const img = new Image();
        img.onload = () => {
            try {
                const canvas = document.createElement('canvas');
                const size = 48;
                canvas.width = size;
                canvas.height = size;
                const ctx = canvas.getContext('2d');
                ctx.drawImage(img, 0, 0, size, size);
                const { data } = ctx.getImageData(0, 0, size, size);
                const colorBuckets = new Map();
                const anyBuckets = new Map();
                const bucketKey = (r, g, b) => [r, g, b].map((c) => Math.round(c / 16) * 16).join(',');
                const addTo = (map, key, r, g, b) => {
                    const bucket = map.get(key) || { r: 0, g: 0, b: 0, n: 0 };
                    bucket.r += r; bucket.g += g; bucket.b += b; bucket.n += 1;
                    map.set(key, bucket);
                };
                for (let i = 0; i < data.length; i += 4) {
                    const r = data[i], g = data[i + 1], b = data[i + 2], a = data[i + 3];
                    if (a < 128) continue;
                    const key = bucketKey(r, g, b);
                    addTo(anyBuckets, key, r, g, b);
                    const max = Math.max(r, g, b), min = Math.min(r, g, b);
                    const isNeutral = max < 30 || min > 225 || max - min < 18;
                    if (isNeutral) continue;
                    addTo(colorBuckets, key, r, g, b);
                }
                const pickWinner = (map) => {
                    let best = null;
                    map.forEach((bucket) => { if (!best || bucket.n > best.n) best = bucket; });
                    return best;
                };
                const winner = pickWinner(colorBuckets) || pickWinner(anyBuckets);
                if (!winner) { resolve(null); return; }
                const toHex = (v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0');
                resolve(toHex(winner.r / winner.n) + toHex(winner.g / winner.n) + toHex(winner.b / winner.n));
            } catch (e) {
                resolve(null);
            }
        };
        img.onerror = () => resolve(null);
        img.src = dataUri;
    });
}
