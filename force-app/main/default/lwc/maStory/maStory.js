import { LightningElement, track } from 'lwc';

const ACCELERATOR_URL =
    'https://orgfarm-5c323065da-dev-ed.develop.my.site.com/gtmaccelerator';

const FONTS_HREF =
    'https://fonts.googleapis.com/css2?family=Sora:wght@500;600;700;800&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap';

const FAQ_DATA = [
    {
        id: 'q1',
        question: 'Does it let us run a migration with fewer people?',
        verdict: 'Yes',
        qualified: false,
        answer:
            'The platform drafts the first pass, inventory, descriptions, build requirements, and a person reviews and refines instead of starting from nothing.'
    },
    {
        id: 'q2',
        question: 'Does it let us do it faster?',
        verdict: 'Yes',
        qualified: false,
        answer:
            'Assessment runs in about an hour instead of weeks. A full plan for a mid-size environment fits inside a single sprint.'
    },
    {
        id: 'q3',
        question: 'Can it actually execute the migration, or just plan it?',
        verdict: 'Yes',
        qualified: false,
        answer:
            "For supported objects, the platform previews the change with a dry run, executes it live, and keeps rollback ready if anything doesn't land clean."
    },
    {
        id: 'q4',
        question: 'Does it mean fewer defects?',
        verdict: 'Yes',
        qualified: false,
        answer:
            "Dependency-aware planning won't let a destination ship without something it needs to run, the exact class of miss that spreadsheet planning lets through routinely."
    },
    {
        id: 'q5',
        question: 'Does it give us better scoping, less risk?',
        verdict: 'Yes',
        qualified: false,
        answer:
            'The health score comes from an automated audit of the real environment, not client-reported counts, which is usually where scoping risk starts.'
    },
    {
        id: 'q6',
        question:
            'Does it let us scale without deep platform specialists on every deal?',
        verdict: 'Qualified yes',
        qualified: true,
        answer:
            'Platform knowledge, field semantics, translation heuristics, vocabulary, lives in the platform, so someone without years of Eloqua or SFMC experience can operate it credibly. A specialist should still review and approve.'
    }
];

export default class MaStory extends LightningElement {
    acceleratorUrl = ACCELERATOR_URL;

    @track openFaqId = null;
    @track theme = null; // null = follow system, 'light', 'dark'
    @track proofOn = false;
    @track objectsText = '0';
    @track depsText = '0';
    @track gaugeValue = 0;
    @track scrollPct = 0;

    _observer;
    _revealed = new Set();
    _scrollHandler;

    // ---------- computed ----------

    get rootClass() {
        if (this.theme === 'dark') return 'story-root dark';
        if (this.theme === 'light') return 'story-root light';
        return 'story-root';
    }

    get proofClass() {
        return this.proofOn ? 'proof rv d3 on' : 'proof rv d3';
    }

    get gaugeStyle() {
        return `--pct: ${this.gaugeValue};`;
    }

    get progressStyle() {
        return `width: ${this.scrollPct}%;`;
    }

    get faqs() {
        return FAQ_DATA.map((f) => ({
            id: f.id,
            question: f.question,
            verdict: f.verdict,
            answer: f.answer,
            itemClass: this.openFaqId === f.id ? 'faq-item open' : 'faq-item',
            verdictClass: f.qualified
                ? 'faq-verdict qualified'
                : 'faq-verdict yes'
        }));
    }

    // ---------- lifecycle ----------

    connectedCallback() {
        this.loadFonts();
        this._scrollHandler = this.handleScroll.bind(this);
        window.addEventListener('scroll', this._scrollHandler, {
            passive: true
        });
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

    // ---------- fonts ----------

    loadFonts() {
        try {
            const existing = document.querySelector(
                'link[data-ma-story-fonts="1"]'
            );
            if (existing) return;
            const link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = FONTS_HREF;
            link.setAttribute('data-ma-story-fonts', '1');
            document.head.appendChild(link);
        } catch (e) {
            // Fonts are progressive enhancement; fall back to the stack in CSS.
        }
    }

    // ---------- scroll reveal ----------

    get reducedMotion() {
        return (
            window.matchMedia &&
            window.matchMedia('(prefers-reduced-motion: reduce)').matches
        );
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

    // ---------- theme ----------

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

    // ---------- proof panel ----------

    handleReveal() {
        if (this.proofOn) return;
        this.proofOn = true;

        if (this.reducedMotion) {
            this.objectsText = (1284).toLocaleString();
            this.depsText = (3140).toLocaleString();
            this.gaugeValue = 84;
            return;
        }

        this.countTo(1284, 900, (v) => {
            this.objectsText = v.toLocaleString();
        });
        this.countTo(3140, 1100, (v) => {
            this.depsText = v.toLocaleString();
        });
        this.countTo(84, 1000, (v) => {
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

    // ---------- FAQ ----------

    handleFaqToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.openFaqId = this.openFaqId === id ? null : id;
    }
}
