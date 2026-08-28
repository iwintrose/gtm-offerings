import { LightningElement, api, track, wire } from 'lwc';
import isConfigManager from '@salesforce/apex/MaSavedConfigurationController.isConfigManager';
import isActive from '@salesforce/apex/MaConfigurationStatusController.isActive';
import getStoryContent from '@salesforce/apex/MaStoryContentController.getStoryContent';
import { FIELDS, EXAMPLE, initials, isHex6 } from 'c/maConfigData';
import USER_ID from '@salesforce/user/Id';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_NAME_FIELD from '@salesforce/schema/User.Name';
import USER_EMAIL_FIELD from '@salesforce/schema/User.Email';

function buildBuilderUrl(orgUrl, sites) {
    if (!orgUrl || !sites || !sites.length) return '#';
    const parts = window.location.pathname.split('/').filter(Boolean);
    const site = sites.find((s) => s.urlPathPrefix === parts[0]);
    if (!site) return `${orgUrl}/lightning/setup/SetupNetworks/home`;
    const segment = parts[parts.length - 1] || '';
    const page = site.pages && site.pages.find(
        (p) => p.developerName && p.developerName.toLowerCase().replace(/_/g, '-') === segment.toLowerCase()
    );
    const base = `${orgUrl}/visualforce.com/apex/networkbranding?networkId=${site.networkId}`;
    return page ? `${base}#/edit/${page.developerName}` : base;
}

const GENERIC_WHY_HEAD = 'Martech depth, plus a platform no one else brings.';
const OFFERING_LABEL = 'Migration Accelerator';
const OFFERING_KEY = 'migration-accelerator';

export default class MaConfigurator extends LightningElement {
    /** Back links, shown only for the internal/self-serve flow — hidden on
     * a shared prospect link (see showCustomizeButton). Set in Experience
     * Builder to match wherever Home and Choose Industry actually live. */
    @api offeringsUrl = '/';
    @api industryUrl = '/choose-industry';
    @api accentColor = ''; // deprecated — colour is set via saved links / Customize panel

    @track tokenState = {};
    @track company = '';
    @track industryKey = '';
    @track accent = '';
    @track theme = null;
    @track expired = false;
    @track inactive = false;
    @track isProspectLink = false;

    @track customizeOpen = false;
    @track bookingOpen = false;
    @track isConfigManager = false;
    @track savedRecordId = '';

    @track proofOn = false;
    @track objectsText = '0';
    @track depsText = '0';
    @track gaugeValue = 0;
    @track scrollPct = 0;

    _observer;
    _revealed = new Set();
    _scrollHandler;
    _keyHandler;
    _editModeHandler;
    _editMode = false;
    _orgUrl = '';
    _sites = [];

    /** Real, server-verified signal for rep-only UI (Customize, saved
     * links). Guests can't call this at all -- no class access -- so the
     * wire errors and this stays false. Whether the URL happens to carry
     * a company/industry param is irrelevant to who's allowed to edit. */
    @wire(isConfigManager)
    wiredIsConfigManager({ data, error }) {
        this.isConfigManager = !!data;
        if (error) {
            this.isConfigManager = false;
        }
        this.maybePrefillContact();
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
    @track _storySetting = null;

    _cmsDefaults = {};

    // -------------------------------------------------------------- lifecycle

    connectedCallback() {
        this.tokenState = this.loadState();
        this.readUrlParams();
        this.setPageTitle();
        getStoryContent({ offeringKey: OFFERING_KEY })
            .then((data) => {
                if (!data) return;
                this._orgUrl = data.orgUrl || '';
                this._sites = data.sites || [];
                this._industries = data.industries;
                this._storySetting = data.setting;
                if (data.setting) {
                    const cmsDefaults = {
                        SOURCE_PLATFORM: data.setting.defaultSourcePlatform,
                        TARGET_PLATFORM: data.setting.defaultTargetPlatform,
                        ASSET_COUNT: data.setting.defaultAssetCount,
                        DEPENDENCY_COUNT: data.setting.defaultDependencyCount,
                        HEALTH_SCORE: data.setting.defaultHealthScore
                    };
                    this._cmsDefaults = cmsDefaults;
                    this.tokenState = { ...cmsDefaults, ...this.tokenState };
                }
            })
            // eslint-disable-next-line no-console
            .catch((err) => { console.error('[maConfigurator] getStoryContent:', JSON.stringify(err)); });

        this._scrollHandler = this.handleScroll.bind(this);
        this._keyHandler = this.handleKeydown.bind(this);
        this._editModeHandler = (evt) => { this._editMode = evt.detail.active; };
        window.addEventListener('scroll', this._scrollHandler, {
            passive: true
        });
        window.addEventListener('keydown', this._keyHandler);
        window.addEventListener('maadminedit', this._editModeHandler);
    }

    get builderUrl() { return buildBuilderUrl(this._orgUrl, this._sites); }

    disconnectedCallback() {
        if (this._scrollHandler) {
            window.removeEventListener('scroll', this._scrollHandler);
        }
        if (this._keyHandler) {
            window.removeEventListener('keydown', this._keyHandler);
        }
        if (this._editModeHandler) {
            window.removeEventListener('maadminedit', this._editModeHandler);
        }
        if (this._observer) {
            this._observer.disconnect();
            this._observer = undefined;
        }
    }

    renderedCallback() {
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

    /** A rep can flip a saved config to inactive without deleting or
     * hiding it from their own list -- this is what actually stops a
     * client's already-shared link from working. Guest-safe, tiny,
     * separate class (MaConfigurationStatusController) -- see that file
     * for why this isn't just another method on MaSavedConfigurationController. */
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
        return this.isConfigManager;
    }

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

    // ------------------------------------------------------- industry engine

    get industry() {
        if (!this.industryKey) return null;
        return (
            this._industries.find(
                (ind) => ind.industryKey === this.industryKey
            ) || null
        );
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

    /** A rep-written note takes over the cover's intro line in place of the
     * generic industry blurb -- this is the live-edit-in-Customize ask:
     * the rep's own words replace the default copy on the page itself. */
    get hasCustomNote() {
        return !!this.tokenValue('CUSTOM_NOTE');
    }

    get customNoteDisplay() {
        return this.tokenValue('CUSTOM_NOTE');
    }

    get showIndustryDefault() {
        return this.hasIndustry && !this.hasCustomNote;
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
        return this.industry ? this.industry.whyHead : GENERIC_WHY_HEAD;
    }

    get chips() {
        if (this.industry) return this.industry.uniquePoints;
        return this._storySetting ? this._storySetting.genericChips : [];
    }

    get demoRoot() {
        if (this.industry) return this.industry.demoRoot;
        return this._storySetting ? this._storySetting.genericDemoRoot : '';
    }

    get demoDeps() {
        if (this.industry) return this.industry.demoDeps;
        return this._storySetting ? this._storySetting.genericDemoDeps : [];
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
    handleConfigSaved() {
        const bar = this.refs.savedLinksBar;
        if (bar) bar.refresh();
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

    // -------------------------------------------------------- booking events

    handleOpenBooking() {
        const modal = this.template.querySelector('c-ma-config-booking');
        if (modal) modal.reset();
        this.bookingOpen = true;
    }

    handleCloseBooking() {
        this.bookingOpen = false;
    }

    handleKeydown(event) {
        if (event.key !== 'Escape') return;
        this.bookingOpen = false;
        this.customizeOpen = false;
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

    // ---------------------------------------------------------------- helpers

    tokenValue(key) {
        const value = this.tokenState[key];
        return value != null && String(value).trim() !== '' ? String(value) : '';
    }

    numberFrom(key, fallback) {
        const parsed = parseFloat(this.tokenValue(key).replace(/[^0-9.]/g, ''));
        return isNaN(parsed) ? fallback : Math.round(parsed);
    }
}
