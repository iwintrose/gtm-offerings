import { LightningElement, api, track, wire } from 'lwc';
import isRep from '@salesforce/apex/GtmViewerContext.isRep';
import getConfigurationCrmData from '@salesforce/apex/GtmSavedConfigurationController.getConfigurationCrmData';
import isActive from '@salesforce/apex/GtmConfigurationStatusController.isActive';
import getConfiguration from '@salesforce/apex/GtmSavedConfigurationController.getConfiguration';
import getPublicConfiguration from '@salesforce/apex/GtmConfigurationReader.getPublicConfiguration';
import getPageLayout from '@salesforce/apex/GtmPageContentReader.getPageLayout';
import { FRAMEWORK_KEY } from 'c/gtmPageLayouts';
import getIndustryProfiles from '@salesforce/apex/GtmPageContentReader.getIndustryProfiles';
import getSiteInfo from '@salesforce/apex/GtmPageContentReader.getSiteInfo';
import checkPasswordRequired from '@salesforce/apex/GtmLinkAuthController.checkPasswordRequired';
import verifyAndIssueToken from '@salesforce/apex/GtmLinkAuthController.verifyAndIssueToken';
import logEvent from '@salesforce/apex/GtmLinkEventController.logEvent';
import logEvents from '@salesforce/apex/GtmLinkEventController.logEvents';
import identifySession from '@salesforce/apex/GtmLinkEventController.identifySession';
// getPublishedReadout(token) is the one guest-facing readout method
// GtmReadoutPublicController exposes — by its own class comment, deliberately
// the ONLY query path onto GTM_Readout__c reachable by an unauthenticated
// caller. Used here exactly as specified; see the readout state machine
// section below for how this component gets a token to call it with.
// Ported from claude/salesforce-marketing-maturity-bsxmxs.
import getPublishedReadout from '@salesforce/apex/GtmReadoutPublicController.getPublishedReadout';
import { FIELDS, EXAMPLE, initials, isHex6 } from 'c/gtmConfigData';
import { CHAPTER_DEFAULTS } from 'c/gtmConfiguratorCopy';
import USER_ID from '@salesforce/user/Id';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_NAME_FIELD from '@salesforce/schema/User.Name';
import USER_EMAIL_FIELD from '@salesforce/schema/User.Email';

function buildBuilderUrl(orgUrl) {
    // The previous per-site deep link (/apex/networkbranding) pointed at a
    // page that does not exist in this org. Digital Experiences > All Sites
    // is the one Setup route guaranteed to exist; from there "Builder" opens
    // the right site in one more click.
    if (!orgUrl) return '#';
    return `${orgUrl}/lightning/setup/SetupNetworks/home`;
}

const OFFERING_LABEL = 'Migration Accelerator';
// Default only. The offering is set on the page in Experience Builder, so a
// second offering is a page assignment rather than a code change.
const DEFAULT_OFFERING_KEY = 'migration-accelerator';

export default class GtmConfigurator extends LightningElement {
    /** Which modelled page this reads. One template, many offerings. */
    @api templateType = 'configurator';

    // GTM_Page_Content__c flat map: 'section::field' -> resolved string.
    // Only the parts of this page that are the same for every client come
    // from here. The hero is assembled from the company, industry and source
    // platform at render time, so it is not flat content and is not modelled:
    // a record cannot hold "<company>'s migration should have taken months".
    @track _cms = {};
    @api offeringKey = DEFAULT_OFFERING_KEY;

    /** Back links, shown only for the internal/self-serve flow — hidden on
     * a shared prospect link (see showCustomizeButton). Set in Experience
     * Builder to match wherever Home and Choose Industry actually live. */
    @api offeringsUrl = '/';
    @api industryUrl = '/choose-industry';
    @api accentColor = ''; // deprecated — colour is set via saved links / Customize panel

    /** True when a rep is looking at a specific link they already sent
     *  (gtmRepLinkFinder / D7) — reading it, not managing it. Same content
     *  as the ordinary rep view, minus the editing chrome: no Customize/Gus,
     *  no saved-links bar, no stage actions. Never true for a guest or for
     *  the ordinary standalone/embedded rep view -- default off. */
    @api viewOnly = false;

    // Preview mode. The GTM Content Manager hands over the draft it is editing;
    // this renders that instead of fetching, so the editor previews the page
    // itself rather than a stand-in for it.
    _preview = false;
    _agentToken = '';

    @api
    get previewContent() { return this._cms; }
    set previewContent(value) {
        if (!value || !Object.keys(value).length) return;
        this._preview = true;
        this._cms = value;
        this.tokenState = { ...this._defaultsFromCms(), ...this.tokenState };
    }

    /**
     * The section the editor has selected.
     *
     * The industry sections are not separate blocks on this page -- each one is
     * the copy the whole page is personalised with -- so choosing one in the
     * rail switches which industry is being previewed, and the cover is where
     * that copy appears.
     */
    @api
    get previewSectionKey() { return this._previewSectionKey; }
    set previewSectionKey(value) {
        this._previewSectionKey = value || '';
    }
    _previewSectionKey = '';

    /**
     * Which industry section the cover currently stands for, so the editor can
     * scroll to it. Without a key here the cover belongs to no section and the
     * rail had nothing to scroll to -- which is why clicking did nothing.
     */
    get previewIndustrySection() {
        // Always the cover now. It used to resolve to industry-<key> because
        // the configurator held one section per industry; industries moved to
        // the framework, which owns them, and the page draws one cover.
        return 'cover';
    }

    /** Where each section sits, so the editor's rail and this stay in step. */
    @api
    getSectionRects() {
        const out = [];
        this.template.querySelectorAll('[data-section]').forEach((el) => {
            const r = el.getBoundingClientRect();
            const pos = window.getComputedStyle(el).position;
            out.push({
                sectionKey: el.dataset.section,
                top: r.top,
                bottom: r.bottom,
                pinned: pos === 'sticky' || pos === 'fixed'
            });
        });
        return out;
    }

    @track _loadError = '';
    @track tokenState = {};
    @track company = '';
    @track industryKey = '';
    /** The link's stored notification override, as loaded by
     * loadSavedConfiguration() -- passed straight through to
     * c-gtm-config-wizard so it can seed "Send assessment alerts to" on
     * open instead of resetting to whichever rep is currently viewing it. */
    @track notifyEmail = '';
    @track accent = '';
    @track theme = null;
    @track expired = false;
    @track inactive = false;
    @track isProspectLink = false;

    @track customizeOpen = false;
    @track bookingOpen = false;
    @track isConfigManager = false;
    @track savedRecordId = '';

    // ── recipient-facing readout state machine ──────────────────────────────
    // Ported from claude/salesforce-marketing-maturity-bsxmxs. Draft/Approved
    // both read as "in review" to the prospect — approval is an internal rep
    // gate they never see as its own state. Published is the only state that
    // changes what they're shown.
    @track assessmentRequestId = '';
    @track readoutStatus = ''; // '' | 'Draft' | 'Approved' | 'Published'
    @track readoutPublicToken = '';
    @track readoutViewOpen = false;
    @track readoutContent = '';
    @track readoutRepName = '';
    @track readoutRepEmail = '';
    @track readoutRepPhone = '';
    @track readoutLoadError = '';
    @track _readoutViewLoaded = false;

    @track passwordRequired = false;
    @track passwordVerified = false;
    @track passwordGateInput = '';
    @track passwordGateError = '';
    @track passwordGateChecking = false;
    /** True while checkPasswordGate() is in flight for a prospect link;
     * hides the page content to prevent a flash of content before the gate. */
    @track _gateCheckPending = false;
    @track _crmData = null;

    @track proofOn = false;
    @track objectsText = '0';
    @track depsText = '0';
    @track gaugeValue = 0;
    @track scrollPct = 0;

    _observer;
    _revealed = new Set();
    _scrollHandler;
    _keyHandler;
    _visibilityHandler;
    _orgUrl = '';
    _lightningUrl = '';
    _sites = [];
    _autoOpenWizard = false;

    // Activity tracking
    _sessionId = null;
    _formOpened = false;
    _formSubmitted = false;

    // Submission token issued by verifyAndIssueToken(); passed to gtmConfigBooking
    // so submitRequest() can validate that the guest entered the correct password.
    _submissionToken = '';

    /** Real, server-verified signal for rep-only UI (Customize, saved
     * links). Guests can't call this at all -- no class access -- so the
     * wire errors and this stays false. Whether the URL happens to carry
     * a company/industry param is irrelevant to who's allowed to edit. */
    @wire(isRep)
    wiredIsConfigManager({ data, error }) {
        this.isConfigManager = !!data;
        if (error) {
            this.isConfigManager = false;
        }
        this.maybePrefillContact();
        this.checkPasswordGate();
        this.loadOverviewCrmData();
        this.loadSavedConfiguration();
        this.maybeAutoOpenWizard();
    }

    /** ?wizard=1 (set by chooseIndustry's tiles, including "Skip for now")
     * opens the wizard immediately instead of landing a rep on a bare
     * configurator with no obvious next step. Only for a confirmed config
     * manager -- isConfigManager resolves asynchronously, so this re-checks
     * from the wire callback rather than firing once from readUrlParams,
     * and only ever fires once (_autoOpenWizard is cleared after) so it
     * can't reopen the panel if something else re-renders this wire. */
    maybeAutoOpenWizard() {
        if (!this._autoOpenWizard || !this.isConfigManager) return;
        this._autoOpenWizard = false;
        this.customizeOpen = true;
    }

    /** So a rep starting a brand-new link doesn't have to type their own
     * name/email -- prefilled from their own user record, still editable
     * in Customize like any other token. */
    _currentUser = null;

    @wire(getRecord, { recordId: USER_ID, fields: [USER_NAME_FIELD, USER_EMAIL_FIELD] })
    wiredUser({ data }) {
        if (!data) return;
        this._currentUser = {
            name: getFieldValue(data, USER_NAME_FIELD),
            email: getFieldValue(data, USER_EMAIL_FIELD)
        };
        this.maybePrefillContact();
    }

    /** Deliberately narrow: only for a rep's own blank, not-yet-shared
     * session. Never fires for a guest (isConfigManager is only ever true
     * for a server-verified rep) and never touches a link that's already
     * been personalized and shared (isProspectLink) -- a colleague
     * previewing someone else's shared link should see the link's own
     * contact info stay put, not get silently swapped to their own. Only
     * fills whichever of CONTACT_NAME/CONTACT_EMAIL is still blank, so a
     * rep/repname URL param (or a value already typed in Customize) always
     * wins regardless of which of this and the URL-param parsing resolves
     * first. */
    maybePrefillContact() {
        if (!this.isConfigManager || this.isProspectLink || !this._currentUser) {
            return;
        }
        const next = { ...this.tokenState };
        let changed = false;
        if (!next.CONTACT_NAME && this._currentUser.name) {
            next.CONTACT_NAME = this._currentUser.name;
            changed = true;
        }
        if (!next.CONTACT_EMAIL && this._currentUser.email) {
            next.CONTACT_EMAIL = this._currentUser.email;
            changed = true;
        }
        if (changed) {
            this.tokenState = next;
        }
    }

    /** Industries, and the generic/no-industry fallback content (proof-
     * number defaults, generic demo, generic chips), from CMS. Empty/null
     * until this resolves -- every getter below that reads from it already
     * has a safe "nothing selected" fallback, so the page just renders the
     * generic view for a beat rather than erroring while this loads. */
    @track _industries = [];

    _cmsDefaults = {};
    // GTM_Page_Content__c flat map: key = 'section::field', value = resolved string
    @track _cms = {};

    // -------------------------------------------------------------- lifecycle

    connectedCallback() {
        // Only the parts that are the same for every client; the hero is
        // assembled from runtime values and stays in the component.
        // The industry copy is this offering's own: one section per industry on
        // this configurator page, edited alongside the rest of the page. The
        // framework owns only the list of industries, not what we say to them.
        getIndustryProfiles({ offeringKey: this.offeringKey, templateType: this.templateType })
            .then((rows) => { if (rows && rows.length) this._industries = rows; })
            .catch((err) => {
                // eslint-disable-next-line no-console
                console.error('[gtmConfigurator] getIndustryProfiles failed:', JSON.stringify(err));
            });

        // Org URL and site list drive edit-mode deep links only.
        getSiteInfo()
            .then((info) => {
                if (!info) return;
                this._orgUrl = info.orgUrl || '';
                this._lightningUrl = info.lightningUrl || '';
                this._sites = info.sites || [];
            })
            .catch(() => {
                // Deep links are progressive enhancement.
            });

        this._sessionId = this._makeSessionId();
        this.tokenState = this.loadState();
        this.readUrlParams();
        this.setPageTitle();
        // savedRecordId is set synchronously by readUrlParams() above, so the
        // assessment state (scoped to it, same as the ma-auth- session key)
        // can be restored on this same pass.
        this.restoreAssessmentState();

        // In preview the parent owns the copy, so fetching would replace the
        // draft with what is published.
        if (this._preview) return;

        getPageLayout({
            offeringKey: this.offeringKey,
            templateType: this.templateType,
            industryKey: null
        })
            .then((layout) => {
                if (!layout || !layout.content) return;
                // Merge, not replace: the framework-level assistant fetch below
                // runs concurrently and lands in the same _cms bag. Whichever
                // of the two resolves second must not wipe out the other's
                // fields with a plain assignment (code-reviewer caught this
                // race -- Gus would silently vanish whenever the assistant
                // call happened to resolve first).
                this._cms = { ...this._cms, ...layout.content };
                // The starting numbers on this page are content now, seeded on
                // the configurator's own defaults section, rather than a custom
                // setting read through the retired story CMS controller.
                this._cmsDefaults = this._defaultsFromCms();
                this.tokenState = { ...this._cmsDefaults, ...this.tokenState };
            })
            .catch((err) => {
                this._loadError = 'Page content could not be loaded; showing built-in defaults.';
                // eslint-disable-next-line no-console
                console.error('[gtmConfigurator] getPageLayout failed:', JSON.stringify(err));
            });

        // Gus is one assistant for every offering (D8) -- his persona lives at
        // the framework level (offeringKey 'gtm'), not under this offering's
        // own configurator page, so it's a second, independent fetch merged
        // into the same _cms bag the assistant::* getters already read from.
        getPageLayout({
            offeringKey: FRAMEWORK_KEY,
            templateType: 'assistant',
            industryKey: null
        })
            .then((layout) => {
                if (!layout || !layout.content) return;
                this._cms = { ...this._cms, ...layout.content };
            })
            .catch((err) => {
                // eslint-disable-next-line no-console
                console.error('[gtmConfigurator] framework assistant getPageLayout failed:', JSON.stringify(err));
            });

        this._scrollHandler = this.handleScroll.bind(this);
        this._keyHandler = this.handleKeydown.bind(this);
        this._visibilityHandler = () => {
            if (document.visibilityState !== 'hidden') return;
            // Everything gets one last chance to be recorded before the tab is
            // gone: a trail flushed only on a timer loses the end of every visit.
            this._closeOpenSections();
            this._track('Session End');
            this._flush();
            if (this._formOpened && !this._formSubmitted) {
                this._logEvent('Drop-off');
            }
        };
        window.addEventListener('scroll', this._scrollHandler, {
            passive: true
        });
        window.addEventListener('keydown', this._keyHandler);
        document.addEventListener('visibilitychange', this._visibilityHandler);
    }

    // ─── CMS resolution helpers ────────────────────────────────────────────────
    _ct(key) { return this._cms[key] || null; }
    _cj(key) {
        const raw = this._cms[key];
        if (!raw) return null;
        try { return JSON.parse(raw); } catch (e) { return null; }
    }

    /**
     * One chapter, resolved.
     *
     * Every field falls back to the words the template used to hardcode, so a
     * page whose content has not been seeded -- a brand-new offering, or this
     * one before the migration ran -- renders exactly as it always did. What
     * changes is that an editor can now replace any of it.
     */
    _chapter(sectionKey) {
        const base = CHAPTER_DEFAULTS[sectionKey] || {};
        const out = {};
        Object.keys(base).forEach((field) => {
            const addr = `${sectionKey}::${field}`;
            if (Array.isArray(base[field])) {
                const parsed = this._cj(addr);
                out[field] = Array.isArray(parsed) && parsed.length ? parsed : base[field];
            } else {
                const raw = this._cms[addr];
                out[field] = (raw === undefined || raw === null || raw === '') ? base[field] : raw;
            }
        });
        return out;
    }

    /* One getter per chapter. The template reads them as ch<Name>.field, which
     * keeps the markup readable and means adding a field to a chapter is an
     * edit to the copy module and the template, not to this class. */
    /**
     * The cover, with the names filled in.
     *
     * Its sentences name the client and the platform, so they cannot be stored
     * as they read. They are stored with {client}, {source} and {industry} left
     * in, and substituted here — which is what makes the one part of the page
     * that was never editable editable.
     */
    get chCover() {
        const c = this._chapter('cover');
        const swap = (v) => String(v || '')
            .replace(/\{client\}/g, this.clientDisplay)
            .replace(/\{source\}/g, this.sourceDisplay)
            .replace(/\{industry\}/g, this.industryTag);
        return { eyebrow: swap(c.eyebrow), head: swap(c.head), lede: swap(c.lede) };
    }

    get chPartner()      { return this._chapter('partner'); }
    get chChallenge()    { return this._chapter('challenge'); }
    get chApproach()     { return this._chapter('approach'); }
    get chProof()        { return this._chapter('proof'); }
    get chDeliverables() { return this._decorate(this._chapter('deliverables')); }
    get chEngagement()   { return this._chapter('engagement'); }
    get chWhy()          { return this._chapter('why'); }
    get chClosing()      { return this._chapter('closing'); }

    /** The deliverables are numbered and banded in pairs, and a template
     *  cannot count, so the index each card needs is computed here. */
    _decorate(chapter) {
        return {
            ...chapter,
            cards: (chapter.cards || []).map((c, i) => ({
                ...c,
                num: String(i + 1).padStart(2, '0'),
                cls: i % 2 === 1 ? 'dcard new' : 'dcard'
            }))
        };
    }

    /** The starting numbers, read from the configurator's defaults section. */
    _defaultsFromCms() {
        const map = {
            SOURCE_PLATFORM: this._ct('defaults::defaultSourcePlatform'),
            TARGET_PLATFORM: this._ct('defaults::defaultTargetPlatform'),
            ASSET_COUNT: this._ct('defaults::defaultAssetCount'),
            DEPENDENCY_COUNT: this._ct('defaults::defaultDependencyCount'),
            HEALTH_SCORE: this._ct('defaults::defaultHealthScore')
        };
        Object.keys(map).forEach((k) => { if (!map[k]) delete map[k]; });
        return map;
    }


    // This page is client-facing. The failure is always logged, but the banner
    // only shows to the rep, never to a prospect on a shared link. It used to
    // key off admin edit mode, which no longer exists.
    get showLoadError() { return !!this._loadError && this.showCustomizeButton; }

    get builderUrl() { return buildBuilderUrl(this._orgUrl); }
    get contentManagerUrl() {
        return this._orgUrl ? `${this._orgUrl}/lightning/o/GTM_Page_Content__c/list` : '#';
    }

    disconnectedCallback() {
        if (this._scrollHandler) {
            window.removeEventListener('scroll', this._scrollHandler);
        }
        if (this._keyHandler) {
            window.removeEventListener('keydown', this._keyHandler);
        }
        if (this._visibilityHandler) {
            document.removeEventListener('visibilitychange', this._visibilityHandler);
        }
        if (this._sectionObserver) { this._sectionObserver.disconnect(); this._sectionObserver = null; }
        this._closeOpenSections();
        this._flush();
        if (this._observer) {
            this._observer.disconnect();
            this._observer = undefined;
        }
    }

    renderedCallback() {
        // Sections only exist once the content has resolved, so this cannot be
        // done at connect. Guarded, because renderedCallback runs on every
        // keystroke the customiser makes.
        if (!this._sectionObserver) this._watchSections();
        this._revealed.forEach((el) => {
            if (el && el.classList && !el.classList.contains('in')) {
                el.classList.add('in');
            }
        });
        // Always re-scan, not just on the first render: .rv elements that
        // enter the DOM later (the custom note paragraph only exists once
        // hasCustomNote goes true, well after this component's first
        // render) were never being observed at all, so they stayed at
        // opacity:0 forever -- rendered, but permanently invisible.
        this.setupReveal();
    }

    // ------------------------------------------------------------------ state

    /**
     * Deliberately not localStorage-backed. It used to be: this browser's
     * last-edited token values would load on ANY page visit, including a
     * bare /configurator with no saved-link params, and even leaked into
     * OTHER saved links on the same machine (nothing scoped the shared
     * storage key to a specific record). Customization belongs to the
     * specific record it was saved against, not to "whatever this browser
     * last had open" -- readUrlParams below is what actually restores a
     * saved link's own values, from the link itself, not from storage.
     */
    loadState() {
        // CMS defaults aren't loaded yet at this point (connectedCallback
        // runs before the getStoryContent wire can resolve) -- the wire
        // callback above merges them in once they arrive, without
        // clobbering anything a URL param sets in the meantime.
        return {};
    }

    readUrlParams() {
        const get = (name) => {
            try {
                const search = new URLSearchParams(window.location.search);
                if (search.has(name)) return search.get(name);
                const hash = new URLSearchParams(
                    (window.location.hash || '').replace(/^#/, '')
                );
                if (hash.has(name)) return hash.get(name);
            } catch (e) {
                return null;
            }
            return null;
        };

        const next = { ...this.tokenState };
        const rep = get('rep');
        const repname = get('repname');
        const book = get('book');
        if (rep) next.CONTACT_EMAIL = rep;
        if (repname) next.CONTACT_NAME = repname;
        if (book) next.BOOKING_URL = book;

        // Same fix as rep/repname/book: these override whatever's sitting
        // in this browser's shared localStorage draft, so a saved link
        // always shows its own values instead of leaking whatever another
        // config was last edited to on this machine.
        const src = get('src');
        const tgt = get('tgt');
        const assets = get('assets');
        const deps = get('deps');
        const health = get('health');
        if (src) next.SOURCE_PLATFORM = src;
        if (tgt) next.TARGET_PLATFORM = tgt;
        if (assets) next.ASSET_COUNT = assets;
        if (deps) next.DEPENDENCY_COUNT = deps;
        if (health) next.HEALTH_SCORE = health;

        const note = get('note');
        if (note) next.CUSTOM_NOTE = note;

        this.tokenState = next;

        const companyParam = get('company');
        const industryParam = get('industry');
        const accentParam = get('accent');
        const cfgIdParam = get('cfgId');

        this.company = companyParam || '';
        // Not validated against the loaded industries list here -- that
        // list may not have arrived from the wire yet. An unrecognized (or
        // not-yet-loaded) key just falls through the `industry` getter's
        // lookup below as "no match", which already renders the generic
        // fallback content correctly.
        this.industryKey = industryParam || '';
        if (accentParam) this.accent = accentParam;
        this.isProspectLink = !!companyParam;
        this.savedRecordId = cfgIdParam || '';
        this.checkActiveStatus();
        if (cfgIdParam) this.loadOverviewCrmData();

        // Carried by a published-readout notification link back to this same
        // page (see the readout state machine section below) -- checked
        // straight away so the gate can show without waiting on
        // restoreAssessmentState()'s sessionStorage-only path.
        const readoutParam = get('readout');
        if (readoutParam) this.checkReadoutToken(readoutParam);

        // Set from chooseIndustry's tiles (?wizard=1); consumed once
        // isConfigManager resolves -- see maybeAutoOpenWizard(). Never set
        // on a prospect link (isProspectLink), which never carries this
        // param in the first place, but guarded here too for safety.
        this._autoOpenWizard = get('wizard') === '1' && !this.isProspectLink;
        this.maybeAutoOpenWizard();

        const exp = get('exp');
        if (exp) {
            const t = /^\d+$/.test(exp) ? parseInt(exp, 10) : Date.parse(exp);
            if (t && Date.now() > t) this.expired = true;
        }

        // isProspectLink is only just now known -- catches the case where
        // the isConfigManager/getRecord wires already resolved before this
        // ran (a warm cache can deliver a wired value synchronously during
        // init, ahead of this method's own place in connectedCallback).
        this.maybePrefillContact();
    }

    /**
     * Refill the page from the record, for a rep who already built this link.
     *
     * The URL parameters were the only thing repopulating the page, so
     * reopening a link with anything missing from the query string meant
     * retyping values the record already held. The record is the source of
     * truth: it is what the rep last saved, and it is newer than any URL that
     * was generated before the last edit.
     *
     * Rep-only. The method behind it is on the rep controller, which the guest
     * permission set is never granted, so a prospect's page is unaffected and
     * still reads its own link.
     */
    async loadSavedConfiguration() {
        if (!this.savedRecordId) return;
        try {
            // A rep reads through the rep controller, which the guest is never
            // granted. Everyone else reads the public view, which returns no
            // password and nothing at all for a link that has been switched
            // off. Same record either way.
            const rec = this.isConfigManager
                ? await getConfiguration({ recordId: this.savedRecordId })
                : await getPublicConfiguration({ recordId: this.savedRecordId });
            if (!rec) return;
            if (rec.isActive === false) { this.inactive = true; return; }

            if (rec.company) this.company = rec.company;
            if (rec.industry) this.industryKey = rec.industry;
            if (rec.notifyEmail) this.notifyEmail = rec.notifyEmail;

            let saved = {};
            try { saved = JSON.parse(rec.configPayload || '{}'); } catch (e) { saved = {}; }
            if (rec.industryLabel && !this.industryKey) this.industryKey = rec.industry;
            if (saved && typeof saved === 'object') {
                // The record wins over the URL: the link in someone's inbox
                // was generated before the last edit, the record was not.
                // This is what makes an edit show up on the next page load
                // rather than needing a freshly generated link.
                this.tokenState = { ...this.tokenState, ...saved };
                if (saved.ACCENT) this.accent = saved.ACCENT;
            }
            this.setPageTitle();
        } catch (e) {
            // The URL still carries enough to render; a failed refill should
            // not blank a page that was about to work.
            // eslint-disable-next-line no-console
            console.warn('[gtmConfigurator] getConfiguration:', JSON.stringify(e));
        }
    }

    /** A rep can flip a saved config to inactive without deleting or
     * hiding it from their own list -- this is what actually stops a
     * client's already-shared link from working. Guest-safe, tiny,
     * separate class (GtmConfigurationStatusController) -- see that file
     * for why this isn't just another method on GtmSavedConfigurationController. */
    async checkActiveStatus() {
        if (!this.savedRecordId) return;
        try {
            const active = await isActive({ recordId: this.savedRecordId });
            this.inactive = !active;
        } catch (e) {
            // Fails open: a status-check error should never itself block a
            // client from seeing an otherwise-working link.
        }
    }

    /** Browser tab title, e.g. "Acme Bank - Migration Accelerator" once a
     * company is known, so a rep's open tabs / bookmarks are legible. */
    setPageTitle() {
        try {
            document.title = this.hasCompany
                ? `${this.company} - ${OFFERING_LABEL}`
                : OFFERING_LABEL;
        } catch (e) {
            // document.title is always writable in practice; nothing to
            // recover from if this somehow throws.
        }
    }

    // ---------------------------------------------------------------- display

    get rootClass() {
        if (this.theme === 'dark') return 'cfg-root dark';
        if (this.theme === 'light') return 'cfg-root light';
        return 'cfg-root';
    }

    get rootStyle() {
        if (!isHex6(this.accent)) return '';
        const hex = String(this.accent).trim().replace(/^#/, '');
        const rv = parseInt(hex.slice(0, 2), 16);
        const gv = parseInt(hex.slice(2, 4), 16);
        const bv = parseInt(hex.slice(4, 6), 16);
        const lin = (c) => { const s = c / 255; return s <= 0.04045 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
        const lum = 0.2126 * lin(rv) + 0.7152 * lin(gv) + 0.0722 * lin(bv);
        const isLight = lum > 0.35;
        const softAlpha = isLight ? '0.12' : '0.18';
        const onCoral = isLight ? '#17140F' : '#FFFFFF';
        const inkFactor = isLight ? 0.55 : 0.82;
        const inkHex = [rv, gv, bv].map((c) => Math.round(c * inkFactor).toString(16).padStart(2, '0')).join('');
        const ring = lum > 0.7 ? 'var(--line)' : 'transparent';
        return `--coral: #${hex}; --coral-soft: rgba(${rv},${gv},${bv},${softAlpha}); --on-coral: ${onCoral}; --coral-ink: #${inkHex}; --coral-ring: ${ring};`;
    }

    get progressStyle() {
        return `width: ${this.scrollPct}%;`;
    }

    get showCustomizeButton() {
        return this.isConfigManager && !this.viewOnly;
    }

    /**
     * Gus is a control on the live page, not part of the page.
     *
     * His bubble is position:fixed, so inside the editor's preview it escaped
     * the frame and floated over the editor itself. The preview is meant to
     * show what the page says, and he is not something the page says.
     */
    get showAssistant() {
        return this.isConfigManager && !this._preview && !this.viewOnly;
    }

    /**
     * The assistant, previewed in place.
     *
     * In the editor he is a section of this page like any other, so he is
     * drawn in the flow with a data-section the rail can scroll to, and drawn
     * whether or not that section is the one selected -- a section that only
     * exists while it is selected has no rect for the rail to find.
     */
    get showAssistantPreview() {
        return this._preview && !!this._cms['assistant::assistantName'];
    }

    /* A valueless attribute on a custom element is not reliably a boolean
     * across LWC versions, and this one decides whether the assistant is inert.
     * Binding an explicit true removes the doubt. */
    get alwaysTrue() { return true; }

    /* The assistant's own copy, from the Assistant section of this page. Each
     * getter falls back inside the component, so an offering that has not
     * written its own still gets a working helper. */
    get assistantName() { return this._ct('assistant::assistantName') || ''; }
    get assistantRole() { return this._ct('assistant::assistantRole') || ''; }
    get assistantLabel() { return this._ct('assistant::fabLabel') || ''; }
    get assistantGreeting() { return this._ct('assistant::greeting') || ''; }
    get assistantPlaceholder() { return this._ct('assistant::inputPlaceholder') || ''; }

    get hasCompany() {
        return !!(this.company && this.company.trim());
    }

    get companyInitials() {
        return initials(this.company);
    }

    get clientDisplay() {
        return this.hasCompany ? this.company : 'your organization';
    }

    get clientTokClass() {
        return 'tok';
    }

    /* Returns the rep-facing {{TOKEN}} placeholder only for reps; guests
       get an empty string so half-filled links don't expose raw tokens. */
    tokFallback(name) {
        return this.isConfigManager ? `{{${name}}}` : '';
    }

    get sourceDisplay() {
        return this.tokenValue('SOURCE_PLATFORM') || this.tokFallback('SOURCE_PLATFORM');
    }

    /** Raw platform value passed to the booking form so it can pre-select
     *  the matching option — never includes the {{TOKEN}} placeholder. */
    get sourcePlatformPrefill() {
        return this.tokenValue('SOURCE_PLATFORM');
    }


    /**
     * A guest with no saved-configuration id has nothing to see: no client
     * name, no deal, nothing a real recipient's link would carry. Without
     * this, the bare public URL (no ?cfgId=) rendered the template's built-in
     * defaults to anyone who found it -- not a specific prospect's page, just
     * the product itself, fully visible with no link and no password.
     *
     * A signed-in Salesforce user (isConfigManager) is exempt: that is the
     * internal preview case -- a rep on the org's own session, not a
     * stranger who wandered onto the site.
     */
    get accessBlocked() {
        return !this.isConfigManager && !this.savedRecordId;
    }

    get showPasswordGate() {
        return (
            !!this.savedRecordId &&
            !this.isConfigManager &&
            this.passwordRequired &&
            !this.passwordVerified
        );
    }

    /** Blanks the page while the gate check is in flight so the content
     * never flickers in before the password overlay appears. */
    get showGateLoading() {
        return this._gateCheckPending && !this.passwordVerified;
    }

    get passwordGateSubmitLabel() {
        return this.passwordGateChecking ? 'Checking…' : 'Access this link →';
    }

    get sourceTokClass() {
        return this.tokenValue('SOURCE_PLATFORM') || !this.isConfigManager ? 'tok' : 'tok empty';
    }

    get contactNameDisplay() {
        return this.tokenValue('CONTACT_NAME') || this.tokFallback('CONTACT_NAME');
    }

    get contactNameTokClass() {
        return this.tokenValue('CONTACT_NAME') || !this.isConfigManager ? 'tok' : 'tok empty';
    }

    get contactEmailDisplay() {
        return this.tokenValue('CONTACT_EMAIL') || this.tokFallback('CONTACT_EMAIL');
    }

    get contactEmailTokClass() {
        return this.tokenValue('CONTACT_EMAIL') || !this.isConfigManager ? 'tok' : 'tok empty';
    }

    get mailtoHref() {
        const email = this.tokenValue('CONTACT_EMAIL');
        const subject = encodeURIComponent(
            `Environment assessment${this.hasCompany ? ` — ${this.company}` : ''}`
        );
        return `mailto:${email}?subject=${subject}`;
    }

    get bookingUrl() {
        return this.tokenValue('BOOKING_URL');
    }

    // ---------------------------------------------------------- the assistant

    /** One token per visit, so the agent's replies can be matched to this tab. */
    /** The id of this visit, so a draft written during it can be tied back to
     *  the trail of what was read before it. */
    get visitSessionId() { return this._sessionId || ''; }

    get agentSessionToken() {
        if (!this._agentToken) {
            this._agentToken = (typeof crypto !== 'undefined' && crypto.randomUUID)
                ? crypto.randomUUID()
                : String(Date.now()) + Math.random().toString(16).slice(2);
        }
        return this._agentToken;
    }

    /**
     * A change the assistant proposes is applied through the same handlers the
     * form inputs use, so there is one path into the page's state rather than
     * a second one that can drift from it.
     */
    handleAgentDelta(event) {
        const delta = (event.detail && event.detail.changes) || null;
        if (!delta || typeof delta !== 'object') return;
        if ('company' in delta) this.handleCompanyChange({ detail: { value: String(delta.company) } });
        if ('industry' in delta) this.handleIndustryChange({ detail: { value: String(delta.industry) } });
        if ('accent' in delta) this.handleAccentChange({ detail: { value: String(delta.accent) } });
        ['objectsCount', 'depsCount', 'healthScore', 'note'].forEach((k) => {
            if (k in delta) this.handleFieldChange({ detail: { key: k, value: String(delta[k]) } });
        });
    }

    // ------------------------------------------------------- industry engine

    get industry() {
        const rows = this._preview ? this._draftProfiles() : this._industries;
        if (!rows.length) return null;
        // A prospect arrives with an industry chosen. The editor has no
        // prospect, so it previews the first industry on the page rather than
        // the generic version, which is where the copy being edited shows up.
        const key = this.industryKey || (this._preview ? rows[0].industryKey : '');
        if (!key) return null;
        return rows.find((ind) => ind.industryKey === key) || null;
    }

    /**
     * The per-industry sections of the draft being edited, rebuilt from the
     * content map so the preview changes as the copy is typed.
     */
    _draftProfiles() {
        const byKey = {};
        const out = [];
        Object.keys(this._cms || {}).forEach((addr) => {
            const cut = addr.indexOf('::');
            if (cut < 0) return;
            const section = addr.substring(0, cut);
            if (section.indexOf('industry-') !== 0) return;
            const key = section.substring(9);
            if (!byKey[key]) { byKey[key] = { industryKey: key }; out.push(byKey[key]); }
            const field = addr.substring(cut + 2);
            const raw = this._cms[addr];
            if (field === 'uniquePoints' || field === 'demoDeps') {
                try { byKey[key][field] = JSON.parse(raw); } catch (e) { byKey[key][field] = []; }
            } else {
                byKey[key][field] = raw;
            }
        });
        return out.length ? out : this._industries;
    }

    get hasIndustry() {
        return !!this.industry;
    }

    get industryLabel() {
        return this.industry ? this.industry.industryLabel : '';
    }

    get industryTag() {
        return this.industry ? this.industry.industryLabel : 'Marketing Automation';
    }

    get coverSub() {
        return this.industry ? this.industry.coverSub : '';
    }

    get hasCustomNote() {
        return !!this.tokenValue('CUSTOM_NOTE');
    }

    get customNoteDisplay() {
        return this.tokenValue('CUSTOM_NOTE');
    }

    /** Industry blurb always shows when an industry is selected -- the
     * custom note is additive (appears below), not a replacement. */
    get showIndustryDefault() {
        return this.hasIndustry;
    }

    get challengeExtra() {
        return this.industry ? this.industry.problem : '';
    }

    get useCase() {
        return this.industry ? this.industry.useCase : '';
    }

    get solution() {
        return this.industry ? this.industry.solution : '';
    }

    get proofLine() {
        return this.industry ? this.industry.proofLine : '';
    }

    get whyLine() {
        return this.industry ? this.industry.whyLine : '';
    }

    get whyHead() {
        // An industry-specific heading still wins: it is more specific than
        // the page-level one, which is the generic case.
        if (this.industry) return this.industry.whyHead;
        return this.chWhy.head;
    }

    get footerLeft() {
        return this._ct('footer::footerLeft') || 'Publicis Sapient';
    }

    get footerRight() {
        return this._ct('footer::footerRight')
            || 'Migration Accelerator, prepared with the Publicis Sapient Marketing Automation practice.';
    }

    /* The no-industry view. These used to read a custom setting that was
     * retired with the story CMS controller and never replaced, so the generic
     * page rendered an empty chip row and an empty dependency flow while the
     * values sat seeded and unread on the Configurator defaults section. They
     * read that section now, which is where the editor edits them. */
    get chips() {
        if (this.industry) return this.industry.uniquePoints;
        return this._cj('defaults::genericChips') || [];
    }

    get demoRoot() {
        if (this.industry) return this.industry.demoRoot;
        return this._ct('defaults::genericDemoRoot') || '';
    }

    get demoDeps() {
        if (this.industry) return this.industry.demoDeps;
        return this._cj('defaults::genericDemoDeps') || [];
    }

    // ------------------------------------------------------------ proof panel

    get proofClass() {
        return this.proofOn ? 'proof revealed' : 'proof';
    }

    get gaugeStyle() {
        return `--pct: ${this.gaugeValue};`;
    }

    handleReveal() {
        if (this.proofOn) return;
        this.proofOn = true;
        // The one thing on this page a reader has to choose to do. Whether they
        // do it is the strongest signal the page gives short of the form.
        this._track('CTA Clicked', 'proof', 'Revealed the assessment');

        const assets = this.numberFrom('ASSET_COUNT', 4128);
        const deps = this.numberFrom('DEPENDENCY_COUNT', 9640);
        const health = this.numberFrom('HEALTH_SCORE', 62);

        if (this.reducedMotion) {
            this.objectsText = assets.toLocaleString();
            this.depsText = deps.toLocaleString();
            this.gaugeValue = health;
            return;
        }
        this.countTo(assets, 1100, (v) => {
            this.objectsText = v.toLocaleString();
        });
        this.countTo(deps, 1300, (v) => {
            this.depsText = v.toLocaleString();
        });
        this.countTo(health, 1200, (v) => {
            this.gaugeValue = v;
        });
    }

    countTo(target, duration, apply) {
        let start = null;
        const step = (timestamp) => {
            if (start === null) start = timestamp;
            const progress = Math.min((timestamp - start) / duration, 1);
            apply(Math.floor(progress * target));
            if (progress < 1) {
                window.requestAnimationFrame(step);
            } else {
                apply(target);
            }
        };
        window.requestAnimationFrame(step);
    }

    // ---------------------------------------------------------- panel events

    handleOpenCustomize() {
        this.customizeOpen = true;
    }

    handleCloseCustomize() {
        this.customizeOpen = false;
    }

    /** So a save shows up in the Saved bar immediately -- without this,
     * the only way to see it was navigating away and back. */
    handleConfigSaved(event) {
        const bar = this.refs.savedLinksBar;
        if (bar) bar.refresh();
        this._adoptSavedUrl(event && event.detail ? event.detail.generatedUrl : '');
    }

    /**
     * Put the saved link's own parameters in the address bar.
     *
     * This page restores itself from query params -- that is deliberate, so a
     * link always shows its own values rather than whatever this browser last
     * edited. But a wizard save left the address bar on a bare /configurator,
     * so refreshing showed an empty page and the work read as lost. It was
     * never lost: the record was saved. The browser just had no way back to
     * it.
     *
     * Only the query string is adopted, against the current path: the
     * generated URL is absolute to the public site, and replacing the whole
     * URL would throw inside Experience Builder, where the origin differs.
     */
    _adoptSavedUrl(generatedUrl) {
        if (!generatedUrl) return;
        try {
            const search = generatedUrl.slice(generatedUrl.indexOf('?'));
            if (!search || search[0] !== '?') return;
            window.history.replaceState(null, '', window.location.pathname + search);
        } catch (e) {
            // A URL that cannot be rewritten is not a reason to fail the save.
        }
    }

    handleFieldChange(event) {
        const { key, value } = event.detail;
        this.tokenState = { ...this.tokenState, [key]: value };
    }

    handleCompanyChange(event) {
        this.company = event.detail.value;
    }

    handleIndustryChange(event) {
        this.industryKey = event.detail.value || '';
    }

    handleAccentChange(event) {
        this.accent = event.detail.value;
    }

    handleLoadExample() {
        this.tokenState = { ...EXAMPLE };
    }

    handleClearAll() {
        const cleared = {};
        FIELDS.forEach((f) => {
            if (this._cmsDefaults[f.k] !== undefined) {
                cleared[f.k] = this._cmsDefaults[f.k];
            }
        });
        this.tokenState = cleared;
    }

    // ------------------------------------------------------------- scroll nav

    /** The "read on" cue at the bottom of each chapter was purely decorative
     * -- no click handler at all -- despite looking like a scroll-to-next
     * affordance. This makes it one. */
    handleScrollNext(event) {
        const current = event.currentTarget.closest('.chap');
        const next = current && current.nextElementSibling;
        if (next && typeof next.scrollIntoView === 'function') {
            next.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    // ---------------------------------------------------- password gate

    async checkPasswordGate() {
        if (!this.savedRecordId || this.isConfigManager) return;
        // Blank the page immediately so there's no flash of content while
        // we wait for the Apex check to tell us whether a gate is needed.
        this._gateCheckPending = true;

        // Restore a cached token from this browser session, but only if it
        // is still within its 30-minute validity window (epoch is embedded
        // in the token as the second colon-delimited segment).
        try {
            const sessionKey = `ma-auth-${this.savedRecordId}`;
            const cached = window.sessionStorage && window.sessionStorage.getItem(sessionKey);
            if (cached) {
                const parts = cached.split(':');
                const epochSeconds = parts.length === 3 ? parseInt(parts[1], 10) : 0;
                const nowSeconds = Math.floor(Date.now() / 1000);
                if (epochSeconds > 0 && nowSeconds - epochSeconds < 1800) {
                    this._submissionToken = cached;
                    this.passwordVerified = true;
                    this._gateCheckPending = false;
                    this._logEvent('Page View');
                    return;
                }
                // Expired or old '1' marker — clear and re-gate.
                window.sessionStorage.removeItem(sessionKey);
            }
        } catch (e) { /* sessionStorage not available */ }

        try {
            this.passwordRequired = await checkPasswordRequired({
                recordId: this.savedRecordId
            });
            if (!this.passwordRequired) {
                this._logEvent('Page View');
            }
        } catch (e) {
            this.passwordRequired = false;
        } finally {
            this._gateCheckPending = false;
        }
    }

    handlePasswordInput(event) {
        this.passwordGateInput = event.currentTarget.value;
        this.passwordGateError = '';
    }

    async handlePasswordSubmit(event) {
        event.preventDefault();
        const pw = (this.passwordGateInput || '').trim();
        if (!pw) {
            this.passwordGateError = 'Please enter the access password.';
            return;
        }
        this.passwordGateChecking = true;
        this.passwordGateError = '';
        try {
            const res = await verifyAndIssueToken({
                recordId: this.savedRecordId,
                password: pw
            });
            if (res && res.matched) {
                this._submissionToken = res.submissionToken || '';
                this.passwordVerified = true;
                this._logEvent('Page View');
                try {
                    // Cache the token so a same-session page refresh doesn't force
                    // re-entry. The token embeds its own epoch; checkPasswordGate()
                    // checks expiry before using it.
                    window.sessionStorage.setItem(
                        `ma-auth-${this.savedRecordId}`,
                        this._submissionToken
                    );
                } catch (e) { /* sessionStorage not available */ }
            } else {
                this.passwordGateError = 'Incorrect password. Please try again.';
            }
        } catch (e) {
            this.passwordGateError = 'Something went wrong. Please try again.';
        } finally {
            this.passwordGateChecking = false;
        }
    }

    get submissionToken() {
        return this._submissionToken;
    }

    // -------------------------------------------------------- booking events

    handleOpenBooking() {
        const modal = this.template.querySelector('c-gtm-config-booking');
        if (modal) modal.reset();
        this.bookingOpen = true;
        if (!this._formOpened) {
            this._formOpened = true;
            this._logEvent('Form Opened');
        }
        this._track('CTA Clicked', 'closing', 'Opened the assessment form');
    }

    handleCloseBooking() {
        this.bookingOpen = false;
    }

    handleBookingSubmitted(event) {
        this._formSubmitted = true;
        const detail = event.detail || {};
        this._logEvent('Form Submitted', null, detail.assessmentRequestId || null);
        this._track('CTA Clicked', 'closing', 'Submitted the assessment');
        this._flush();

        // Everything they read before this was anonymous. Now that they have
        // said who they are, the whole session becomes theirs -- so the trail
        // that led to the request is attributable to the person who left it.
        if (detail.contactId && this.savedRecordId) {
            identifySession({
                configId: this.savedRecordId,
                sessionId: this._sessionId,
                contactId: detail.contactId
            }).catch(() => { /* the request itself already succeeded */ });
        }

        if (detail.assessmentRequestId) {
            this.assessmentRequestId = detail.assessmentRequestId;
            this.persistAssessmentId(detail.assessmentRequestId);
        }
    }

    /** A resumed form is worth knowing about: it means the link did its job on
     *  a second visit, which a first-visit-only funnel would never show. */
    handleFormResumed() {
        this._track('Form Resumed', 'assessment');
    }

    // ── readout state machine (recipient side) ──────────────────────────────
    // Ported from claude/salesforce-marketing-maturity-bsxmxs.
    // GtmReadoutPublicController is, by design (see its own class comment),
    // the ONLY guest-accessible query path onto GTM_Readout__c, and it
    // exposes exactly one method: getPublishedReadout(token). There is
    // deliberately no guest-safe way to look up a readout's status from an
    // assessment request id alone -- adding one would widen that surface.
    //
    // So this state machine only ever *advances* to Published when it
    // actually has a token, from one of two sources:
    //   1. A `readout` URL param -- the shape a published notification link
    //      back to this same page would carry (mirrors how every other
    //      saved-link value here is read as a URL param).
    //   2. A token remembered from a previous successful check in this
    //      browser (sessionStorage, scoped by savedRecordId like ma-auth-).
    // Short of one of those, a submitted assessment is shown as "in review"
    // indefinitely -- Draft and Approved are indistinguishable from here
    // either way, which matches the spec (approval is an internal gate the
    // prospect never sees as its own state).

    _assessmentSessionKey() {
        return `ma-assessment-${this.savedRecordId}`;
    }

    _readoutTokenSessionKey() {
        return `ma-readout-token-${this.savedRecordId}`;
    }

    restoreAssessmentState() {
        if (!this.savedRecordId) return;
        try {
            const storedArId = window.sessionStorage
                && window.sessionStorage.getItem(this._assessmentSessionKey());
            if (storedArId) this.assessmentRequestId = storedArId;

            const storedToken = window.sessionStorage
                && window.sessionStorage.getItem(this._readoutTokenSessionKey());
            if (storedToken) this.checkReadoutToken(storedToken);
        } catch (e) { /* sessionStorage not available */ }
    }

    persistAssessmentId(arId) {
        try {
            if (window.sessionStorage) {
                window.sessionStorage.setItem(this._assessmentSessionKey(), arId);
            }
        } catch (e) { /* sessionStorage not available */ }
    }

    persistReadoutToken(token) {
        try {
            if (window.sessionStorage) {
                window.sessionStorage.setItem(this._readoutTokenSessionKey(), token);
            }
        } catch (e) { /* sessionStorage not available */ }
    }

    /**
     * Confirms a token actually resolves to a currently-published readout,
     * using the one sanctioned guest call, and caches its content so opening
     * the modal later doesn't need a second round trip. A submitted-but-
     * unresolved token (not yet published, or invalid) is not treated as an
     * error -- the page just stays in its "in review" state, exactly as the
     * guest contract intends (Published vs. everything else is
     * indistinguishable to the caller by design).
     */
    checkReadoutToken(token) {
        if (!token) return;
        getPublishedReadout({ token })
            .then((data) => {
                if (!data || !data.content) return;
                this.readoutStatus = 'Published';
                this.readoutPublicToken = token;
                // A token proves a readout exists for this prospect even if
                // this browser never saw the original submission (e.g. the
                // published link was opened on a different device).
                if (!this.assessmentRequestId) this.assessmentRequestId = 'linked';
                this.persistReadoutToken(token);
                this._readoutViewLoaded = true;
                this.readoutContent = data.content;
                this.readoutRepName = data.repName || '';
                this.readoutRepEmail = data.repEmail || '';
                this.readoutRepPhone = data.repPhone || '';
            })
            .catch(() => {
                // Swallowed on purpose, and with no detail in the console.
                // This is a guest-facing page, and the whole point of
                // GtmReadoutPublicController's contract is that an anonymous
                // visitor cannot tell an invalid token from a real one that is
                // not published yet, or from one that was revoked --
                // c/gtmReadoutView swallows the identical error for exactly
                // this reason. A logged error object (status, message, the
                // token in the request) hands back the distinction the Apex
                // side is careful never to give. A failure here just leaves
                // the page in its "in review" state, which is also what a
                // resolved-but-empty response does.
            });
    }

    get hasSubmittedAssessment() { return !!this.assessmentRequestId; }
    get showPublishedGate() { return this.readoutStatus === 'Published'; }

    get topCtaLabel() {
        return this.showPublishedGate ? 'View your assessment' : 'Your assessment is in review';
    }
    get topCtaDisabled() { return !this.showPublishedGate; }

    handleTopCtaClick() {
        if (this.showPublishedGate) this.handleOpenReadoutView();
    }

    handleOpenReadoutView() {
        this.readoutViewOpen = true;
        if (!this._readoutViewLoaded && this.readoutPublicToken) {
            this.checkReadoutToken(this.readoutPublicToken);
        }
        if (!this._readoutViewLoaded) {
            this.readoutLoadError = 'Your assessment could not be opened right now. Please try again shortly.';
        }
    }

    handleCloseReadoutView() { this.readoutViewOpen = false; }

    get hasReadoutRep() {
        return !!(this.readoutRepName || this.readoutRepEmail || this.readoutRepPhone);
    }
    get hasReadoutRepEmail() { return !!this.readoutRepEmail; }
    get hasReadoutRepPhone() { return !!this.readoutRepPhone; }

    handleKeydown(event) {
        if (event.key !== 'Escape') return;
        this.bookingOpen = false;
        this.customizeOpen = false;
        this.readoutViewOpen = false;
    }

    // -------------------------------------------------- stage actions events

    handleStageSent(event) {
        const email = event.detail?.requesterEmail;
        const msg   = email
            ? `Proposal sent to ${email}.`
            : 'Proposal marked as sent.';
        this._showToast(msg);
    }

    handleStagePreview() {
        // Toggle isConfigManager so the rep sees the client view temporarily.
        // A second click or page reload restores their internal view.
        this._stagePreviewMode = !this._stagePreviewMode;
    }

    // ----------------------------------------------------- scroll and reveal

    get reducedMotion() {
        return (
            window.matchMedia &&
            window.matchMedia('(prefers-reduced-motion: reduce)').matches
        );
    }

    handleScroll() {
        const doc = document.documentElement;
        const max = doc.scrollHeight - doc.clientHeight;
        this.scrollPct = max > 0 ? (doc.scrollTop / max) * 100 : 0;
    }

    setupReveal() {
        const nodes = this.template.querySelectorAll('.rv');
        if (!nodes || nodes.length === 0) return;

        if (!('IntersectionObserver' in window) || this.reducedMotion) {
            nodes.forEach((el) => {
                el.classList.add('in');
                this._revealed.add(el);
            });
            return;
        }
        if (!this._observer) {
            this._observer = new IntersectionObserver(
                (entries) => {
                    entries.forEach((entry) => {
                        if (!entry.isIntersecting) return;
                        entry.target.classList.add('in');
                        this._revealed.add(entry.target);
                        this._observer.unobserve(entry.target);
                    });
                },
                { threshold: 0.14, rootMargin: '0px 0px -8% 0px' }
            );
        }
        // observe() is a no-op if already observing a given target, so
        // it's safe to call on every render rather than tracking which
        // nodes were already registered.
        nodes.forEach((el) => {
            if (!this._revealed.has(el)) {
                this._observer.observe(el);
            }
        });
    }

    handleThemeToggle() {
        if (this.theme === 'dark') {
            this.theme = 'light';
            return;
        }
        if (this.theme === 'light') {
            this.theme = 'dark';
            return;
        }
        const systemDark =
            window.matchMedia &&
            window.matchMedia('(prefers-color-scheme: dark)').matches;
        this.theme = systemDark ? 'light' : 'dark';
    }

    // ------------------------------------------------------------ CRM overview

    get showCrmStrip() {
        return this.isConfigManager && !!this.savedRecordId && !!this._crmData;
    }

    get hasCrmAccount() {
        return !!(this._crmData && this._crmData.accountId);
    }

    get crmAccountName() {
        return this._crmData ? (this._crmData.accountName || '') : '';
    }

    get crmAccountUrl() {
        if (!this._crmData || !this._crmData.accountId) return '#';
        return `${this._orgUrl}/lightning/r/Account/${this._crmData.accountId}/view`;
    }

    get hasCrmOpp() {
        return !!(this._crmData && this._crmData.opportunityId);
    }

    get crmOppName() {
        return this._crmData ? (this._crmData.opportunityName || '') : '';
    }

    get crmOppUrl() {
        if (!this._crmData || !this._crmData.opportunityId) return '#';
        return `${this._orgUrl}/lightning/r/Opportunity/${this._crmData.opportunityId}/view`;
    }

    get hasCrmContact() {
        return !!(this._crmData && this._crmData.contactId);
    }

    get crmContactName() {
        return this._crmData ? (this._crmData.contactName || '') : '';
    }

    get crmContactEmail() {
        return this._crmData ? (this._crmData.contactEmail || '') : '';
    }

    get crmEstimatedValue() {
        if (!this._crmData || !this._crmData.estimatedValue) return '';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        }).format(this._crmData.estimatedValue);
    }

    async loadOverviewCrmData() {
        if (!this.isConfigManager || !this.savedRecordId) return;
        try {
            this._crmData = await getConfigurationCrmData({ recordId: this.savedRecordId });
        } catch (e) {
            this._crmData = null;
        }
    }

    // ---------------------------------------------------------------- helpers

    _showToast(message) {
        // Experience Cloud doesn't support ShowToastEvent — use a brief inline banner instead
        const el = document.createElement('div');
        el.textContent = message;
        el.style.cssText = [
            'position:fixed', 'top:60px', 'left:50%', 'transform:translateX(-50%)',
            'background:#166534', 'color:#fff', 'padding:10px 20px',
            'border-radius:6px', 'font-size:14px', 'z-index:9999',
            'box-shadow:0 4px 12px rgba(0,0,0,.2)'
        ].join(';');
        document.body.appendChild(el);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => el.remove(), 3500);
    }

    tokenValue(key) {
        const value = this.tokenState[key];
        return value != null && String(value).trim() !== '' ? String(value) : '';
    }

    numberFrom(key, fallback) {
        const parsed = parseFloat(this.tokenValue(key).replace(/[^0-9.]/g, ''));
        return isNaN(parsed) ? fallback : Math.round(parsed);
    }

    /**
     * The interaction trail: which chapters were read, for how long, and what
     * was pressed.
     *
     * A page view says the link was opened. It does not say whether the proof
     * panel was reached or the pricing chapter was skipped, which is the part a
     * BD can act on. The page is already modelled as named sections, so an
     * IntersectionObserver over them produces an attributed trail for free --
     * the sitemap that Marketing Cloud Personalization and Adobe both make you
     * build and maintain by hand is, here, the page's own structure.
     *
     * Batched: a single read of this page leaves a dozen or more section
     * events, and a round trip each would put the prospect's connection to work
     * while they read.
     */
    _queue = [];
    _seq = 0;
    _flushTimer = null;
    _sectionObserver = null;
    _visibleSince = new Map();

    _track(eventType, step, target, dwellSeconds) {
        if (!this.isProspectLink || !this.savedRecordId || this.isConfigManager) return;
        this._seq += 1;
        this._queue.push({
            eventType,
            step: step || null,
            target: target || null,
            dwellSeconds: dwellSeconds == null ? null : Math.round(dwellSeconds * 10) / 10,
            sequence: this._seq
        });
        // A queue this long means something is firing in a loop; send it and
        // start again rather than growing without bound.
        if (this._queue.length >= 25) this._flush();
        else this._scheduleFlush();
    }

    _scheduleFlush() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        clearTimeout(this._flushTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._flushTimer = setTimeout(() => this._flush(), 4000);
    }

    _flush() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        clearTimeout(this._flushTimer);
        if (!this._queue.length) return;
        const batch = this._queue;
        this._queue = [];
        logEvents({
            configId: this.savedRecordId,
            sessionId: this._sessionId,
            events: batch
        }).catch(() => { /* best-effort, like every other event on this page */ });
    }

    /**
     * Dwell, measured as time actually on screen.
     *
     * Time-on-page counts a tab someone walked away from; this counts a section
     * from when it comes into view to when it leaves, and only reports a stay
     * long enough to be reading rather than scrolling past.
     */
    _watchSections() {
        if (typeof IntersectionObserver === 'undefined') return;
        if (!this.isProspectLink || this.isConfigManager) return;

        this._sectionObserver = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                const key = entry.target.dataset.section;
                if (!key) return;
                if (entry.isIntersecting) {
                    if (!this._visibleSince.has(key)) this._visibleSince.set(key, Date.now());
                    return;
                }
                const since = this._visibleSince.get(key);
                if (!since) return;
                this._visibleSince.delete(key);
                const seconds = (Date.now() - since) / 1000;
                // Under a second is a scroll, not a read.
                if (seconds >= 1) this._track('Section Viewed', key, null, seconds);
            });
        }, { threshold: 0.35 });

        this.template.querySelectorAll('[data-section]')
            .forEach((el) => this._sectionObserver.observe(el));
    }

    /** Anything still on screen when they go has been dwelt on until now. */
    _closeOpenSections() {
        const now = Date.now();
        this._visibleSince.forEach((since, key) => {
            const seconds = (now - since) / 1000;
            if (seconds >= 1) this._track('Section Viewed', key, null, seconds);
        });
        this._visibleSince.clear();
    }

    _logEvent(eventType, step, assessmentRequestId) {
        // Only track prospect links (not rep previews or blank sessions).
        if (!this.isProspectLink || !this.savedRecordId || this.isConfigManager) return;
        logEvent({
            configId: this.savedRecordId,
            eventType,
            sessionId: this._sessionId,
            step: step || null,
            assessmentRequestId: assessmentRequestId || null
        }).catch(() => { /* best-effort */ });
    }

    _makeSessionId() {
        try {
            if (typeof crypto !== 'undefined' && crypto.randomUUID) {
                return crypto.randomUUID();
            }
        } catch (e) { /* ignore */ }
        // Fallback for browsers without crypto.randomUUID
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
            const r = (Math.random() * 16) | 0;
            return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
        });
    }
}
