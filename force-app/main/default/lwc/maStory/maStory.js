import { LightningElement, api, track } from 'lwc';
import getStoryContent from '@salesforce/apex/MaStoryContentController.getStoryContent';
import getPageLayout from '@salesforce/apex/MaPageContentReader.getPageLayout';

const ACCELERATOR_URL =
    'https://orgfarm-5c323065da-dev-ed.develop.my.site.com/gtmaccelerator';

const FONTS_HREF =
    'https://fonts.googleapis.com/css2?family=Sora:wght@500;600;700;800&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap';

const OFFERING_KEY = 'migration-accelerator';

function buildBuilderUrl(orgUrl) {
    // The previous per-site deep link (/apex/networkbranding) pointed at a
    // page that does not exist in this org. Digital Experiences > All Sites
    // is the one Setup route guaranteed to exist; from there "Builder" opens
    // the right site in one more click.
    if (!orgUrl) return '#';
    return `${orgUrl}/lightning/setup/SetupNetworks/home`;
}

// Hardcoded fallbacks shown until CMS data loads (keeps the page usable if a
// CMS record hasn't been created yet or a callout fails).


// The field vocabulary of each layout type, bucketed by how the value is
// stored and rendered. This is the contract between the renderer and
// MA_Page_Content__c: scripts/check-content-contract.py reads it to assert
// the seeded records match, and the sections getter resolves from it, so the
// two cannot drift apart. Adding a field to a layout means adding it here.
const LAYOUT_FIELDS = {
    'hero':        { text: ['eyebrow'],                      rich: ['headline', 'subhead'],        json: [] },
    'lede-chips':  { text: ['eyebrow'],                      rich: ['lede', 'close'],              json: ['chips'] },
    'route-proof': { text: ['eyebrow', 'proofDemoRoot'],     rich: ['head', 'sub', 'proofCtaText'], json: ['routeSteps', 'proofDemoDeps'] },
    'card-grid':   { text: ['eyebrow', 'head'],              rich: ['bonusCard'],                  json: ['cards'] },
    'stat':        { text: ['eyebrow', 'head', 'statBig'],   rich: ['statDesc', 'note'],           json: [] },
    'use-pitch':   { text: ['eyebrow', 'head'],              rich: ['lede'],                       json: ['useCases', 'pitchOldChips', 'pitchNewChips'] },
    'faq':         { text: ['eyebrow', 'head'],              rich: [],                             json: ['items'] },
    'closing':     { text: ['ctaLabel'],                     rich: ['head', 'sub'],                json: [] }
};


// Per-layout fallbacks, used when a record is absent. Keyed by layout type and
// field name so they line up with LAYOUT_FIELDS. These are the floor: the page
// still renders if the org has no content rows at all.
const SECTION_FALLBACKS = {
    'hero': {
        eyebrow: DEFAULTS.heroEyebrow,
        headline: DEFAULTS.heroHeadline,
        subhead: DEFAULTS.heroSubhead
    },
    'lede-chips': {
        lede: DEFAULTS.problemLede,
        close: DEFAULTS.problemClose,
        chips: DEFAULTS.problemChips
    },
    'route-proof': {
        eyebrow: 'The mechanism',
        head: DEFAULTS.mechanismHead,
        sub: DEFAULTS.mechanismSub,
        routeSteps: DEFAULTS.routeSteps,
        proofCtaText: DEFAULTS.proofCtaText,
        proofDemoRoot: DEFAULTS.proofDemoRoot,
        proofDemoDeps: DEFAULTS.proofDemoDeps
    },
    'card-grid': {
        eyebrow: 'The capabilities',
        head: "What's actually built.",
        cards: DEFAULTS.capabilities,
        bonusCard: DEFAULTS.bonusCard
    },
    'stat': {
        eyebrow: 'The client profile',
        head: 'Who this fits.',
        statBig: DEFAULTS.clientStatBig,
        statDesc: DEFAULTS.clientStatDesc,
        note: DEFAULTS.clientNote
    },
    'use-pitch': {
        eyebrow: 'For Business Development and Industry Leaders',
        head: DEFAULTS.bdHead,
        lede: DEFAULTS.bdLede,
        useCases: DEFAULTS.bdUseCases,
        pitchOldChips: DEFAULTS.pitchOldChips,
        pitchNewChips: DEFAULTS.pitchNewChips
    },
    'faq': {
        eyebrow: 'FAQ',
        head: 'The questions this needs to survive.',
        items: DEFAULTS.faqs
    },
    'closing': {
        head: DEFAULTS.closingHead,
        sub: DEFAULTS.closingSub,
        ctaLabel: 'Build a client-specific version \u2192'
    }
};

// Fallback structure, used only until getPageLayout returns rows. Order here
// matches the page as originally authored; MA_Page_Section__c overrides it.
const DEFAULT_SECTIONS = [
    { sectionKey: 'hero',          layoutType: 'hero',        width: 'standard', label: '' },
    { sectionKey: 'problem',       layoutType: 'lede-chips',  width: 'standard', label: '' },
    { sectionKey: 'mechanism',     layoutType: 'route-proof', width: 'wide',     label: 'The mechanism' },
    { sectionKey: 'capabilities',  layoutType: 'card-grid',   width: 'standard', label: 'The capabilities' },
    { sectionKey: 'clientProfile', layoutType: 'stat',        width: 'standard', label: 'The client profile' },
    { sectionKey: 'bd',            layoutType: 'use-pitch',   width: 'wide',     label: 'For Business Development and Industry Leaders' },
    { sectionKey: 'faq',           layoutType: 'faq',         width: 'standard', label: 'FAQ' },
    { sectionKey: 'closing',       layoutType: 'closing',     width: 'standard', label: '' }
];

const DEFAULTS = {
    heroEyebrow: 'Internal positioning · GTM buy-in',
    heroHeadline: 'Every migration starts with a decade nobody documented. We read it in an afternoon.',
    heroSubhead: 'How Migration Accelerator turns an untrusted platform and a go-live date that won\'t move into a plan, and increasingly, a finished migration.',
    problemLede: 'Every enterprise migration starts the same way.',
    problemChips: [
        'A platform nobody fully trusts',
        'A decade of undocumented campaigns',
        'A go-live date that won\'t move'
    ],
    problemClose: 'Migration Accelerator starts working before the rebuild, before the plan, at the part everyone dreads: finding out what\'s actually there.',
    mechanismHead: 'Point it at the platform.\nGet a plan you can act on.',
    mechanismSub: 'Point it at a client\'s email tool (ex: SFMC, Eloqua, etc) — get a build-ready plan out, and for the pieces it\'s confident about, a finished migration.',
    closingHead: 'This is Migration Accelerator today: an offering built on evidence, moving toward a finished migration instead of a plan for one.',
    closingSub: 'The next step is putting a name and an industry behind it.',
    faqs: [
        {
            question: 'Does it let us run a migration with fewer people?',
            verdict: 'Yes',
            answer: 'The platform drafts the first pass, inventory, descriptions, build requirements, and a person reviews and refines instead of starting from nothing.'
        },
        {
            question: 'Does it let us do it faster?',
            verdict: 'Yes',
            answer: 'Assessment runs in about an hour instead of weeks. A full plan for a mid-size environment fits inside a single sprint.'
        },
        {
            question: 'Can it actually execute the migration, or just plan it?',
            verdict: 'Yes',
            answer: 'For supported objects, the platform previews the change with a dry run, executes it live, and keeps rollback ready if anything doesn\'t land clean.'
        },
        {
            question: 'Does it mean fewer defects?',
            verdict: 'Yes',
            answer: 'Dependency-aware planning won\'t let a destination ship without something it needs to run, the exact class of miss that spreadsheet planning lets through routinely.'
        },
        {
            question: 'Does it give us better scoping, less risk?',
            verdict: 'Yes',
            answer: 'The health score comes from an automated audit of the real environment, not client-reported counts, which is usually where scoping risk starts.'
        },
        {
            question: 'Does it let us scale without deep platform specialists on every deal?',
            verdict: 'Qualified yes',
            answer: 'Platform knowledge, field semantics, translation heuristics, vocabulary, lives in the platform, so someone without years of Eloqua or SFMC experience can operate it credibly. A specialist should still review and approve.'
        }
    ],
    routeSteps: [
        { stepLabel: 'Ingest', stepDesc: 'Every asset, read directly' },
        { stepLabel: 'Audit', stepDesc: 'A live health score' },
        { stepLabel: 'Decide', stepDesc: 'Port, rework, retire, logged' },
        { stepLabel: 'Plan', stepDesc: 'Dependencies pulled automatically' },
        { stepLabel: 'Execute', stepDesc: 'Dry run, then live, rollback ready' }
    ],
    proofCtaText: 'A snapshot of what the platform reads from an environment, automatically, on day one.',
    proofDemoRoot: 'APAC Onboarding',
    proofDemoDeps: ['Welcome email', 'Shared data extension', 'Brand header'],
    capabilities: [
        { icon: 'In', cardTitle: 'Ingestion & inventory', cardDesc: 'Automatic, for any major marketing automation platform.', isNew: false },
        { icon: 'Au', cardTitle: 'Automated audit', cardDesc: 'A health score plus an exportable report, generated on demand.', isNew: true },
        { icon: 'De', cardTitle: 'Disposition & audit trail', cardDesc: 'Port, rework, or retire, on every object, with full history.', isNew: false },
        { icon: 'Pl', cardTitle: 'Dependency-aware planning', cardDesc: 'Assigning one object pulls in everything it needs, automatically.', isNew: false },
        { icon: 'Sp', cardTitle: 'AI-drafted build specs', cardDesc: 'Human-reviewed requirements per object, down to Journey Builder specs.', isNew: false },
        { icon: 'Ex', cardTitle: 'Live execution & rollback', cardDesc: 'Dry run, then live, with a verification pass once it finishes.', isNew: true }
    ],
    bonusCard: '<strong>Also in the toolkit:</strong> a design-to-email pipeline. An approved Figma layout becomes a built, publishable email, no separate rebuild.',
    clientStatBig: '500–2,000+',
    clientStatDesc: 'objects is where this offering\'s advantage is largest, enterprise accounts migrating between major marketing automation platforms, carrying a sizable, under-documented environment.',
    clientNote: 'Today, this runs through us, in working sessions, not a self-serve portal, and that\'s exactly how it should work for now.',
    bdHead: 'One story. Here\'s how to run it.',
    bdLede: 'This is the pitch, the same one a client hears. The job is fluency in it, plus the tools to make it specific to whoever\'s in the room.',
    bdUseCases: [
        { caseTitle: 'Presales', caseDesc: 'Run a prospect\'s export before the SOW. Walk in with a real health score, not a guess.' },
        { caseTitle: 'Delivery', caseDesc: 'Run the full engagement through it, start to finish, and increasingly, the cutover itself.' },
        { caseTitle: 'The pitch', caseDesc: 'A real environment becoming a real plan, live, in the room, not described afterward.' }
    ],
    pitchOldChips: [
        'A promise to figure out scope after signature',
        'An estimate built on intuition',
        'A plan that ends in a manual handoff'
    ],
    pitchNewChips: [
        'A real health score, produced live, in the room',
        'Scope set from the actual environment',
        'A dry run, and where it applies, a finished cutover'
    ]
};

export default class MaStory extends LightningElement {
    acceleratorUrl = ACCELERATOR_URL;

    @track openFaqId = null;
    @track theme = null;
    @track proofOn = false;
    @track _editMode = false;
    @track objectsText = '0';
    @track depsText = '0';
    @track gaugeValue = 0;
    @track scrollPct = 0;

    @track _page = null;
    @track _body = null;
    @track _faqData = [];
    @track _proofObjectsCount = null;
    @track _proofDepsCount = null;
    @track _proofHealthScore = null;
    // MA_Page_Content__c flat map: key = 'section::field', value = resolved string
    @track _cms = {};
    // Structure of the page, ordered. Empty until getPageLayout returns, at
    // which point DEFAULT_SECTIONS stops being used.
    @track _sectionRows = [];
    @track _loadError = '';
    // Set in the Lightning App Builder / Experience Builder. Defaults to the
    // first offering but is not bound to it.
    @api offeringKey = OFFERING_KEY;

    _observer;
    _revealed = new Set();
    _scrollHandler;
    _editModeHandler;
    _orgUrl = '';
    _lightningUrl = '';
    _sites = [];

    // ─── CMS resolution helpers ────────────────────────────────────────────────
    // Priority: MA_Page_Content__c (_cms map) → legacy CMS (_page/_body) → DEFAULTS

    _ct(key) { return this._cms[key] || null; }
    _cj(key) {
        const raw = this._cms[key];
        if (!raw) return null;
        try { return JSON.parse(raw); } catch (e) { return null; }
    }


    // ─── section render model ──────────────────────────────────────────────
    // The page is drawn by iterating this. Every value the template needs is
    // resolved here, because LWC templates cannot call functions. Layout type
    // decides which branch draws the section; order comes from the records.

    get sections() {
        const rows = this._sectionRows.length ? this._sectionRows : DEFAULT_SECTIONS;
        return rows.map((row) => {
            const k = row.sectionKey;
            const t = row.layoutType;
            const spec = LAYOUT_FIELDS[t] || { text: [], rich: [], json: [] };
            const fb = SECTION_FALLBACKS[t] || {};

            const s = {
                key: k,
                layoutType: t,
                isHero: t === 'hero',
                isLedeChips: t === 'lede-chips',
                isRouteProof: t === 'route-proof',
                isCardGrid: t === 'card-grid',
                isStat: t === 'stat',
                isUsePitch: t === 'use-pitch',
                isFaq: t === 'faq',
                isClosing: t === 'closing',
                sectionClass: t === 'hero' ? 'hero wrap'
                    : t === 'closing' ? 'closing wrap'
                    : row.width === 'wide' ? 'beat wrap wide' : 'beat wrap'
            };

            // Resolve every field this layout declares: record -> fallback.
            spec.text.concat(spec.rich).forEach((f) => {
                s[f] = this._ct(k + '::' + f) || fb[f] || '';
            });
            spec.json.forEach((f) => {
                const fromRecord = this._cj(k + '::' + f);
                s[f] = (fromRecord && fromRecord.length) ? fromRecord : (fb[f] || []);
            });

            // An eyebrow renders only when the layout declares one and a value
            // resolves. The section's editor label is deliberately NOT used as a
            // fallback: sections like the problem beat carry no eyebrow on the
            // page, and borrowing the label would invent one.
            s.hasEyebrow = !!s.eyebrow;

            // Shaping the template cannot do for itself.
            if (s.isLedeChips) s.chips = this._withKeys(s.chips);
            if (s.isRouteProof) s.proofDemoDeps = this._withKeys(s.proofDemoDeps);
            if (s.isCardGrid) {
                s.cards = s.cards.map((c) => ({ ...c, cardClass: c.isNew ? 'cap-card new' : 'cap-card' }));
            }
            if (s.isUsePitch) {
                s.oldChips = this._withKeys(s.pitchOldChips);
                s.newChips = this._withKeys(s.pitchNewChips);
            }
            if (s.isFaq) s.items = this._buildFaqs(s.items);

            return s;
        });
    }

    // for:each needs a stable key, and a bare string cannot carry one.
    _withKeys(list) {
        return list.map((text, i) => ({ id: i + '-' + text, text }));
    }

    _buildFaqs(fromRecords) {
        const source = fromRecords.length
            ? fromRecords
            : (this._faqData && this._faqData.length) ? this._faqData : DEFAULTS.faqs;
        return source.map((f, index) => {
            const id = 'q' + (index + 1);
            const qualified = f.verdict !== 'Yes';
            return {
                id,
                question: f.question,
                verdict: f.verdict,
                answer: f.answer,
                itemClass: this.openFaqId === id ? 'faq-item open' : 'faq-item',
                verdictClass: qualified ? 'faq-verdict qualified' : 'faq-verdict yes'
            };
        });
    }

    // ---- page getters ----


    // ---- body getters ----


    // ---- misc computed ----

    get rootClass() {
        if (this.theme === 'dark') return 'story-root dark';
        if (this.theme === 'light') return 'story-root light';
        return 'story-root';
    }

    get proofClass() { return this.proofOn ? 'proof rv d3 on' : 'proof rv d3'; }
    get proofBarLabel() { return `${this.offeringKey} \u00b7 live preview`; }
    get gaugeStyle() { return `--pct: ${this.gaugeValue};`; }
    get progressStyle() { return `width: ${this.scrollPct}%;`; }


    get builderUrl() { return buildBuilderUrl(this._orgUrl); }
    get contentManagerUrl() {
        return this._orgUrl ? `${this._orgUrl}/lightning/o/MA_Page_Content__c/list` : '#';
    }

    // ---- lifecycle ----

    connectedCallback() {
        this.loadFonts();
        this._scrollHandler = this.handleScroll.bind(this);
        this._editModeHandler = (evt) => { this._editMode = evt.detail.active; };
        window.addEventListener('scroll', this._scrollHandler, { passive: true });
        window.addEventListener('maadminedit', this._editModeHandler);
        // Phase 1 — MA_Page_Content__c is the primary CMS; falls back to legacy getStoryContent.
        getPageLayout({ offeringKey: this.offeringKey, templateType: 'story', industryKey: null })
            .then((layout) => {
                if (!layout) return;
                if (layout.content) this._cms = layout.content;
                if (layout.sections && layout.sections.length) this._sectionRows = layout.sections;
            })
            .catch((err) => {
                // Surfaced, not swallowed: a silent failure here is what let the
                // page render hardcoded defaults for months without anyone noticing.
                this._loadError = 'Page content could not be loaded; showing built-in defaults.';
                // eslint-disable-next-line no-console
                console.error('[maStory] getPageLayout failed:', JSON.stringify(err));
            });
        getStoryContent({ offeringKey: OFFERING_KEY })
            .then((data) => {
                if (!data) return;
                this._faqData = data.faqs || [];
                this._orgUrl = data.orgUrl || '';
                this._lightningUrl = data.lightningUrl || '';
                if (data.page) {
                    this._page = data.page;
                    this._proofObjectsCount = data.page.proofObjectsCount;
                    this._proofDepsCount = data.page.proofDepsCount;
                    this._proofHealthScore = data.page.proofHealthScore;
                }
                if (data.body) this._body = data.body;
                this._sites = data.sites || [];
            })
            // eslint-disable-next-line no-console
            .catch((err) => { console.error('[maStory] getStoryContent:', JSON.stringify(err)); });
    }

    disconnectedCallback() {
        if (this._scrollHandler) {
            window.removeEventListener('scroll', this._scrollHandler);
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
        this.reapplyRevealed();
        if (this._observer) return;
        this.setupReveal();
    }

    loadFonts() {
        try {
            if (document.querySelector('link[data-ma-story-fonts="1"]')) return;
            const link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = FONTS_HREF;
            link.setAttribute('data-ma-story-fonts', '1');
            document.head.appendChild(link);
        } catch (e) {
            // Fonts are progressive enhancement; fall back to the stack in CSS.
        }
    }

    // ---- scroll reveal ----

    get reducedMotion() {
        return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    }

    setupReveal() {
        const nodes = this.template.querySelectorAll('.rv');
        if (!nodes || nodes.length === 0) return;
        if (!('IntersectionObserver' in window) || this.reducedMotion) {
            nodes.forEach((el) => { el.classList.add('in'); this._revealed.add(el); });
            return;
        }
        this._observer = new IntersectionObserver(
            (entries) => {
                entries.forEach((entry) => {
                    if (!entry.isIntersecting) return;
                    entry.target.classList.add('in');
                    this._revealed.add(entry.target);
                    this._observer.unobserve(entry.target);
                });
            },
            { threshold: 0.12, rootMargin: '0px 0px -6% 0px' }
        );
        nodes.forEach((el) => this._observer.observe(el));
    }

    reapplyRevealed() {
        this._revealed.forEach((el) => {
            if (el && el.classList && !el.classList.contains('in')) {
                el.classList.add('in');
            }
        });
    }

    handleScroll() {
        const doc = document.documentElement;
        const max = doc.scrollHeight - doc.clientHeight;
        this.scrollPct = max > 0 ? (doc.scrollTop / max) * 100 : 0;
    }

    // ---- theme ----

    handleThemeToggle() {
        if (this.theme === 'dark') { this.theme = 'light'; return; }
        if (this.theme === 'light') { this.theme = 'dark'; return; }
        const systemDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        this.theme = systemDark ? 'light' : 'dark';
    }

    // ---- proof panel ----

    handleReveal() {
        if (this.proofOn) return;
        this.proofOn = true;

        const objects = parseInt(this._proofObjectsCount, 10) || 1284;
        const deps = parseInt(this._proofDepsCount, 10) || 3140;
        const health = parseInt(this._proofHealthScore, 10) || 84;

        if (this.reducedMotion) {
            this.objectsText = objects.toLocaleString();
            this.depsText = deps.toLocaleString();
            this.gaugeValue = health;
            return;
        }
        this.countTo(objects, 900, (v) => { this.objectsText = v.toLocaleString(); });
        this.countTo(deps, 1100, (v) => { this.depsText = v.toLocaleString(); });
        this.countTo(health, 1000, (v) => { this.gaugeValue = v; });
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

    // ---- FAQ ----

    handleFaqToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.openFaqId = this.openFaqId === id ? null : id;
    }
}
