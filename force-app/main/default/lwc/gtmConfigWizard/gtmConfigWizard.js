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
import { FRAMEWORK_KEY } from 'c/gtmPageLayouts';
import USER_ID from '@salesforce/user/Id';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_NAME_FIELD from '@salesforce/schema/User.Name';
import USER_EMAIL_FIELD from '@salesforce/schema/User.Email';
import { isHex6, EXAMPLE } from 'c/gtmConfigData';

const OFFERING = 'migration-accelerator';

// Publicis Sapient's own brand red -- the Quick Link path's fallback accent
// when the rep gives no website to auto-detect a brand colour from. Chosen
// deliberately over this app's own generic swatch-list default so a link
// built in 30 seconds never looks unbranded.
const PS_RED = 'E4002B';

const SIZE_PRESETS = {
    S: { label: 'Small', sub: 'Under 1,000 assets', assets: 800,   deps: 1400,  health: 78 },
    M: { label: 'Medium', sub: '~4,000 assets',       assets: 4128,  deps: 9640,  health: 62 },
    L: { label: 'Large', sub: '10,000+ assets',       assets: 12400, deps: 26800, health: 45 }
};

const TOTAL_STEPS = 8;

export default class GtmConfigWizard extends LightningElement {
    /** Controls visibility -- same contract as c-ma-config-customize. */
    @api isOpen = false;

    /** True when launched from the GTM Offerings Overview tab (Lightning),
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
    _cmsDefaults = {};

    @track _selectedContact = null;

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

    @track _passwordMode = 'auto'; // 'auto' | 'custom' | 'off'
    @track _generatedPassword = '';
    @track _customPassword = '';
    _passwordStepEntered = false;

    @track _saving = false;
    @track _saveError = '';
    @track _companyInvalid = false;
    @track _generatedUrl = '';
    @track _copyFeedback = 'Copy link';

    _knownRecordId = '';
    _autoSaveTimer;
    // True when this wizard opened on a link that already existed.
    @track _existed = false;
    // The link that already exists, and whether the rep has chosen to leave it
    // alone and build another.
    @track _existingUrl = '';
    @track _existingActive = true;
    @track _replacing = false;
    @track _existingCopyLabel = 'Copy link';
    _siteBaseUrl = '';
    _currentUser = null;

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
    }

    /** Distance from the true page top to where normal content begins --
     * i.e. the height of whatever Salesforce chrome sits above it (the
     * global header, plus, on a Developer/sandbox org, the edition ribbon).
     * Only meaningful in standalone mode. Falls back to a conservative
     * guess if measurement fails (component not yet laid out, or running
     * somewhere unexpected) rather than colliding with the chrome. */
    _standaloneTopOffset = 106;

    _measureChromeOffset() {
        if (!this.standalone) return;
        try {
            const rect = this.template.host.getBoundingClientRect();
            const offset = Math.round(rect.top + window.scrollY);
            if (offset > 0) this._standaloneTopOffset = offset;
        } catch (e) {
            // keep the fallback
        }
    }

    get sheetStyle() {
        return this.standalone ? `top:${this._standaloneTopOffset}px;` : '';
    }

    get scrimStyle() {
        return this.standalone ? `top:${this._standaloneTopOffset}px;` : '';
    }

    connectedCallback() {
        // Deferred one tick: at connectedCallback the host isn't laid out
        // yet (getBoundingClientRect would read 0,0). Measuring is only
        // ever a refinement over the CSS fallback above, never a
        // requirement for anything else to work.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this._measureChromeOffset(), 0);

        // The industry list is the framework's shared taxonomy.
        getIndustryProfiles({ offeringKey: FRAMEWORK_KEY, templateType: 'industry-chooser' })
            .then((rows) => { this._industries = rows || []; })
            // eslint-disable-next-line no-console
            .catch((err) => console.warn('[gtmConfigWizard] getIndustryProfiles:', JSON.stringify(err)));

        // The swatches and the platforms a link starts from are content on the
        // configurator's own defaults section, not a custom setting.
        getPageLayout({ offeringKey: OFFERING, templateType: 'configurator', industryKey: null })
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
            })
            // eslint-disable-next-line no-console
            .catch((err) => console.warn('[gtmConfigWizard] getPageLayout:', JSON.stringify(err)));

        if (this.standalone) {
            getConfiguratorPageUrl()
                .then((url) => { this._siteBaseUrl = url || ''; })
                // eslint-disable-next-line no-console
                .catch((err) => console.warn('[gtmConfigWizard] getConfiguratorPageUrl:', JSON.stringify(err)));
        }
    }

    // ------------------------------------------------------------- display

    /** Standalone (launched from the GTM Offerings Overview Lightning tab)
     * sits inside real Salesforce chrome -- the fixed global header and, on
     * a Developer/sandbox org, the edition ribbon above it. Embedded mode
     * (the live Experience Cloud page) has no such chrome to clear, so it
     * keeps the full-height panel unchanged. */
    get panelClass() {
        const base = this.standalone ? 'mw-scrim mw-scrim--standalone' : 'mw-scrim';
        return this.isOpen ? `${base} open` : base;
    }

    get sheetClass() {
        const base = this.standalone ? 'mw-sheet mw-sheet--standalone' : 'mw-sheet';
        return this.isOpen ? `${base} open` : base;
    }

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
        if (this._contactSearchTimer) window.clearTimeout(this._contactSearchTimer);
        const term = this._company.trim();
        if (term.length < 2) { this._contactResults = []; return; }
        this._contactSearchBusy = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._contactSearchTimer = window.setTimeout(() => this._runContactSearch(term), 300);
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
            accountId: match.accountId,
            accountName: match.accountName
        };
        if (match.accountName) this._company = match.accountName;
        this._contactResults = [];
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
        return Object.keys(SIZE_PRESETS).map((key) => ({
            key,
            letter: key,
            label: SIZE_PRESETS[key].label,
            sub: SIZE_PRESETS[key].sub,
            cardClass: this._sizePreset === key ? 'mw-preset sel' : 'mw-preset'
        }));
    }

    handleSizePick(event) {
        const key = event.currentTarget.dataset.key;
        this._sizePreset = key;
        const p = SIZE_PRESETS[key];
        this._state = {
            ...this._state,
            ASSET_COUNT: String(p.assets),
            DEPENDENCY_COUNT: String(p.deps),
            HEALTH_SCORE: String(p.health)
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
    get passwordOffClass()    { return this._passwordMode === 'off'    ? 'mw-chip sel' : 'mw-chip'; }
    get showCustomPasswordInput() { return this._passwordMode === 'custom'; }

    _ensureGeneratedPassword() {
        if (this._generatedPassword) return;
        const stem = (this._company || 'link').replace(/[^a-zA-Z]/g, '').slice(0, 5).toLowerCase() || 'link';
        const digits = Math.floor(1000 + Math.random() * 9000);
        this._generatedPassword = `${stem}-${digits}`;
    }

    handlePasswordKeep()   { this._passwordMode = 'auto'; }
    handlePasswordOff()    { this._passwordMode = 'off'; }
    handlePasswordCustom() {
        this._passwordMode = 'custom';
        if (!this._customPassword) this._customPassword = this._generatedPassword;
    }
    handleCustomPasswordInput(event) {
        this._customPassword = event.currentTarget.value;
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
            && !!(this._state.CONTACT_NAME || '').trim()
            && !!(this._state.CONTACT_EMAIL || '').trim();
    }

    get generateBlockedReason() {
        if (this.canGenerateLink) return '';
        if (!(this._company || '').trim()) return 'Add a company name (Step 1) before generating a link.';
        return 'Add your name and email (Step 6) before generating a link.';
    }

    /** Numbered, clickable progress rail -- lets a rep jump straight to any
     * step instead of only stepping through with Next/Back. dotState drives
     * the CSS class: 'current', 'needs' (a required step still incomplete),
     * 'done' (visited, or optional and already has a value), or 'todo'. */
    get stepDots() {
        const labels = ['Company', 'Industry', 'Colour', 'Environment', 'Note', 'Contact', 'Password', 'Review'];
        const requiredOk = [
            !!(this._company || '').trim(),
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
        this._step = 1;
        this._markVisited(1);
    }

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
    }

    handleQuickIndustryPick(event) {
        this._industry = event.currentTarget.dataset.key || '';
    }

    async handleQuickGenerate() {
        if (!(this._company || '').trim()) {
            this._companyInvalid = true;
            this._saveError = 'Add a company name to continue.';
            return;
        }
        // Defaults for everything the quick path skips.
        const preset = SIZE_PRESETS.M;
        this._state = {
            ...this._cmsDefaults,
            ...this._state,
            ASSET_COUNT: this._state.ASSET_COUNT || String(preset.assets),
            DEPENDENCY_COUNT: this._state.DEPENDENCY_COUNT || String(preset.deps),
            HEALTH_SCORE: this._state.HEALTH_SCORE || String(preset.health)
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
        try {
            const linkPassword = this._passwordMode === 'off'
                ? null
                : (this._passwordMode === 'custom' ? this._customPassword : this._generatedPassword);

            const url = this._buildUrl();
            const recordId = await saveConfiguration({
                input: {
                    recordId: this._knownRecordId || null,
                    offering: OFFERING,
                    industry: this._industry,
                    company: (this._company || '').trim(),
                    generatedUrl: url,
                    // The accent is part of what this link looks like, but it
                    // lived only in the generated URL -- so a record could not
                    // rebuild its own page without the query string. It rides
                    // in the payload now, alongside everything else.
                    configPayload: JSON.stringify({ ...this._state, ACCENT: this._accent || '' }),
                    clientContactName: this._selectedContact ? this._selectedContact.name : null,
                    contactId: this._selectedContact ? this._selectedContact.id : null,
                    // Blank means "a new deal" -- which is what this always
                    // did, silently, whether or not the client already had one.
                    opportunityId: this._dealId || null,
                    accountId: this._selectedContact ? this._selectedContact.accountId : null,
                    linkPassword,
                    clearLinkPassword: this._passwordMode === 'off',
                    website: this._brandDomain || null,
                    accountIndustry: this._industry || null
                }
            });
            this._knownRecordId = recordId;
            this._generatedUrl = this._buildUrl();
            if (advance && this._path === 'full') {
                this._step = TOTAL_STEPS + 1; // "done" screen
                this._existed = true;
            }
            // The URL goes up with the id: the page this wizard sits on
            // restores itself from query params, so without it a refresh
            // lands on a bare configurator and the work looks lost.
            this.dispatchEvent(new CustomEvent('configsaved', {
                detail: { recordId, generatedUrl: this._generatedUrl }
            }));
        } catch (e) {
            // An autosave failing mid-form is not something to interrupt for;
            // the explicit save at the end surfaces it.
            if (advance) {
                this._saveError = e?.body?.message || 'That link did not save. Please try again.';
            }
        } finally {
            this._saving = false;
        }
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
    get showPreviewLink() { return this.standalone; }

    handleFinish() {
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
