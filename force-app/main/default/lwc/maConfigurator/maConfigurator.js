import { LightningElement, api, track, wire } from 'lwc';
import isConfigManager from '@salesforce/apex/MaSavedConfigurationController.isConfigManager';
import isActive from '@salesforce/apex/MaConfigurationStatusController.isActive';
import {
    INDUSTRIES,
    FIELDS,
    DEFAULTS,
    EXAMPLE,
    GENERIC_DEMO,
    GENERIC_CHIPS,
    initials,
    isHex6
} from 'c/maConfigData';

const GENERIC_WHY_HEAD = 'Martech depth, plus a platform no one else brings.';
const OFFERING_LABEL = 'Migration Accelerator';

export default class MaConfigurator extends LightningElement {
    /** Back links, shown only for the internal/self-serve flow — hidden on
     * a shared prospect link (see showCustomizeButton). Set in Experience
     * Builder to match wherever Home and Choose Industry actually live. */
    @api offeringsUrl = '/';
    @api industryUrl = '/choose-industry';

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
    }

    // -------------------------------------------------------------- lifecycle

    connectedCallback() {
        this.tokenState = this.loadState();
        this.readUrlParams();
        this.setPageTitle();

        this._scrollHandler = this.handleScroll.bind(this);
        this._keyHandler = this.handleKeydown.bind(this);
        window.addEventListener('scroll', this._scrollHandler, {
            passive: true
        });
        window.addEventListener('keydown', this._keyHandler);
    }

    disconnectedCallback() {
        if (this._scrollHandler) {
            window.removeEventListener('scroll', this._scrollHandler);
        }
        if (this._keyHandler) {
            window.removeEventListener('keydown', this._keyHandler);
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
        return { ...DEFAULTS };
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
        this.industryKey = INDUSTRIES[industryParam] ? industryParam : '';
        if (accentParam) this.accent = accentParam;
        this.isProspectLink = !!companyParam;
        this.savedRecordId = cfgIdParam || '';
        this.checkActiveStatus();

        const exp = get('exp');
        if (exp) {
            const t = /^\d+$/.test(exp) ? parseInt(exp, 10) : Date.parse(exp);
            if (t && Date.now() > t) this.expired = true;
        }
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
        const hex = `#${String(this.accent).trim().replace(/^#/, '')}`;
        return `--coral: ${hex}; --coral-soft: ${hex}1a;`;
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

    get sourceDisplay() {
        return this.tokenValue('SOURCE_PLATFORM') || '{{SOURCE_PLATFORM}}';
    }

    get sourceTokClass() {
        return this.tokenValue('SOURCE_PLATFORM') ? 'tok' : 'tok empty';
    }

    get contactNameDisplay() {
        return this.tokenValue('CONTACT_NAME') || '{{CONTACT_NAME}}';
    }

    get contactNameTokClass() {
        return this.tokenValue('CONTACT_NAME') ? 'tok' : 'tok empty';
    }

    get contactEmailDisplay() {
        return this.tokenValue('CONTACT_EMAIL') || '{{CONTACT_EMAIL}}';
    }

    get contactEmailTokClass() {
        return this.tokenValue('CONTACT_EMAIL') ? 'tok' : 'tok empty';
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
        return INDUSTRIES[this.industryKey] || null;
    }

    get hasIndustry() {
        return !!this.industry;
    }

    get industryLabel() {
        return this.industry ? this.industry.label : '';
    }

    get industryTag() {
        return this.industry ? this.industry.label : 'Marketing Automation';
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
        return this.industry ? this.industry.unique : GENERIC_CHIPS;
    }

    get demoRoot() {
        return this.industry ? this.industry.demo.root : GENERIC_DEMO.root;
    }

    get demoDeps() {
        return this.industry ? this.industry.demo.deps : GENERIC_DEMO.deps;
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
        const key = event.detail.value;
        this.industryKey = INDUSTRIES[key] ? key : '';
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
            if (DEFAULTS[f.k] !== undefined) cleared[f.k] = DEFAULTS[f.k];
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
