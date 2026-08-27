import { LightningElement, track } from 'lwc';
import getStoryContent from '@salesforce/apex/MaStoryContentController.getStoryContent';

const ACCELERATOR_URL =
    'https://orgfarm-5c323065da-dev-ed.develop.my.site.com/gtmaccelerator';

const FONTS_HREF =
    'https://fonts.googleapis.com/css2?family=Sora:wght@500;600;700;800&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap';

const OFFERING_KEY = 'migration-accelerator';

// Hardcoded fallbacks shown until CMS data loads (keeps the page usable if a
// CMS record hasn't been created yet or a callout fails).
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
    mechanismSub: 'Eloqua or Salesforce Marketing Cloud, in, a build-ready plan out, and for the pieces it\'s confident about, a finished migration.',
    closingHead: 'This is Migration Accelerator today: an offering built on evidence, moving toward a finished migration instead of a plan for one.',
    closingSub: 'The next step is putting a name and an industry behind it.',
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
        { icon: 'In', cardTitle: 'Ingestion & inventory', cardDesc: 'Automatic, for Eloqua and Salesforce Marketing Cloud (Content Builder).', isNew: false },
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

    _observer;
    _revealed = new Set();
    _scrollHandler;

    // ---- page getters ----

    get heroEyebrow() { return (this._page && this._page.heroEyebrow) || DEFAULTS.heroEyebrow; }
    get heroHeadline() { return (this._page && this._page.heroHeadline) || DEFAULTS.heroHeadline; }
    get heroSubhead() { return (this._page && this._page.heroSubhead) || DEFAULTS.heroSubhead; }
    get problemLede() { return (this._page && this._page.problemLede) || DEFAULTS.problemLede; }
    get problemChips() { return (this._page && this._page.problemChips && this._page.problemChips.length) ? this._page.problemChips : DEFAULTS.problemChips; }
    get problemClose() { return (this._page && this._page.problemClose) || DEFAULTS.problemClose; }
    get mechanismHead() { return (this._page && this._page.mechanismHead) || DEFAULTS.mechanismHead; }
    get mechanismSub() { return (this._page && this._page.mechanismSub) || DEFAULTS.mechanismSub; }
    get closingHead() { return (this._page && this._page.closingHead) || DEFAULTS.closingHead; }
    get closingSub() { return (this._page && this._page.closingSub) || DEFAULTS.closingSub; }

    // ---- body getters ----

    get routeSteps() { return (this._body && this._body.routeSteps && this._body.routeSteps.length) ? this._body.routeSteps : DEFAULTS.routeSteps; }
    get proofCtaText() { return (this._body && this._body.proofCtaText) || DEFAULTS.proofCtaText; }
    get proofDemoRoot() { return (this._body && this._body.proofDemoRoot) || DEFAULTS.proofDemoRoot; }
    get proofDemoDeps() { return (this._body && this._body.proofDemoDeps && this._body.proofDemoDeps.length) ? this._body.proofDemoDeps : DEFAULTS.proofDemoDeps; }
    get capabilities() {
        const caps = (this._body && this._body.capabilities && this._body.capabilities.length)
            ? this._body.capabilities : DEFAULTS.capabilities;
        return caps.map((c) => ({ ...c, cardClass: c.isNew ? 'cap-card new' : 'cap-card' }));
    }
    get bonusCard() { return (this._body && this._body.bonusCard) || DEFAULTS.bonusCard; }
    get clientStatBig() { return (this._body && this._body.clientStatBig) || DEFAULTS.clientStatBig; }
    get clientStatDesc() { return (this._body && this._body.clientStatDesc) || DEFAULTS.clientStatDesc; }
    get clientNote() { return (this._body && this._body.clientNote) || DEFAULTS.clientNote; }
    get bdHead() { return (this._body && this._body.bdHead) || DEFAULTS.bdHead; }
    get bdLede() { return (this._body && this._body.bdLede) || DEFAULTS.bdLede; }
    get bdUseCases() { return (this._body && this._body.bdUseCases && this._body.bdUseCases.length) ? this._body.bdUseCases : DEFAULTS.bdUseCases; }
    get pitchOldChips() { return (this._body && this._body.pitchOldChips && this._body.pitchOldChips.length) ? this._body.pitchOldChips : DEFAULTS.pitchOldChips; }
    get pitchNewChips() { return (this._body && this._body.pitchNewChips && this._body.pitchNewChips.length) ? this._body.pitchNewChips : DEFAULTS.pitchNewChips; }

    // ---- misc computed ----

    get rootClass() {
        if (this.theme === 'dark') return 'story-root dark';
        if (this.theme === 'light') return 'story-root light';
        return 'story-root';
    }

    get proofClass() { return this.proofOn ? 'proof rv d3 on' : 'proof rv d3'; }
    get gaugeStyle() { return `--pct: ${this.gaugeValue};`; }
    get progressStyle() { return `width: ${this.scrollPct}%;`; }

    get faqs() {
        return this._faqData.map((f, index) => {
            const id = `q${index + 1}`;
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

    // ---- lifecycle ----

    connectedCallback() {
        this.loadFonts();
        this._scrollHandler = this.handleScroll.bind(this);
        window.addEventListener('scroll', this._scrollHandler, { passive: true });
        getStoryContent({ offeringKey: OFFERING_KEY })
            .then((data) => {
                if (!data) return;
                this._faqData = data.faqs || [];
                if (data.page) {
                    this._page = data.page;
                    this._proofObjectsCount = data.page.proofObjectsCount;
                    this._proofDepsCount = data.page.proofDepsCount;
                    this._proofHealthScore = data.page.proofHealthScore;
                }
                if (data.body) this._body = data.body;
            })
            // eslint-disable-next-line no-console
            .catch((err) => { console.error('[maStory] getStoryContent:', JSON.stringify(err)); });
    }

    disconnectedCallback() {
        if (this._scrollHandler) {
            window.removeEventListener('scroll', this._scrollHandler);
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
