import { LightningElement, api, track } from 'lwc';
import getPageLayout from '@salesforce/apex/GtmPageContentReader.getPageLayout';
// The layout vocabulary is shared with the editor, which has to know what
// fields a section needs before that section exists. See c/gtmPageLayouts.
import { FRAME_LAYOUTS, LAYOUT_FIELDS, LAYOUT_BAND, ctaGlyph } from 'c/gtmPageLayouts';

const FONTS_HREF =
    'https://fonts.googleapis.com/css2?family=Lexend+Deca:wght@300;400;500;600&family=Roboto:wght@300;400;500;700&family=Roboto+Mono:wght@300;400;500;700&display=swap';

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


// Per-layout fallbacks, used when a record is absent. Keyed by layout type and
// field name so they line up with LAYOUT_FIELDS. These are the floor: the page
// still renders if the org has no content rows at all.
const SECTION_FALLBACKS = {
    'page-header': {
        brandLabel: 'Migration Accelerator',
        brandTag: '/ the story'
    },
    'page-footer': {
        footerLeft: 'Migration Accelerator — positioning working draft',
        footerRight: 'Grounded against ma-migrator + project-conduit, August 2026'
    },
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
        ctaLabel: { label: 'Build a client-specific version', icon: 'arrow' }
    },
    'statement': {
        kicker: 'The pivot',
        statement: 'Before this, scope was an argument. Now it is a reading of the environment.',
        attribution: 'Migration Accelerator — the shift, in one line'
    }
};

// Fallback structure, used only until getPageLayout returns rows. Order here
// matches the page as originally authored; GTM_Page_Section__c overrides it.
const DEFAULT_SECTIONS = [
    { sectionKey: 'header',        layoutType: 'page-header', width: 'standard', label: 'Header' },
    { sectionKey: 'footer',        layoutType: 'page-footer', width: 'standard', label: 'Footer' },
    { sectionKey: 'hero',          layoutType: 'hero',        width: 'standard', label: '' },
    { sectionKey: 'problem',       layoutType: 'lede-chips',  width: 'standard', label: 'The Problem' },
    { sectionKey: 'mechanism',     layoutType: 'route-proof', width: 'wide',     label: 'The mechanism' },
    { sectionKey: 'pivot',         layoutType: 'statement',   width: 'standard', label: 'The Pivot' },
    { sectionKey: 'capabilities',  layoutType: 'card-grid',   width: 'standard', label: 'The capabilities' },
    { sectionKey: 'clientProfile', layoutType: 'stat',        width: 'standard', label: 'The client profile' },
    { sectionKey: 'bd',            layoutType: 'use-pitch',   width: 'wide',     label: 'For Business Development and Industry Leaders' },
    { sectionKey: 'faq',           layoutType: 'faq',         width: 'standard', label: 'FAQ' },
    { sectionKey: 'closing',       layoutType: 'closing',     width: 'standard', label: 'Closing' }
];


export default class GtmStory extends LightningElement {
    @track openFaqId = null;
    @track theme = null;
    @track proofOn = false;
    @track objectsText = '0';
    @track depsText = '0';
    @track gaugeValue = 0;
    @track scrollPct = 0;

    // GTM_Page_Content__c flat map: key = 'section::field', value = resolved string
    @track _cms = {};
    // Structure of the page, ordered. Empty until getPageLayout returns, at
    // which point DEFAULT_SECTIONS stops being used.
    @track _sectionRows = [];
    // Type and label of every field, so undeclared ones can be drawn.
    @track _fieldMeta = [];
    @track _loadError = '';
    // Set in the Lightning App Builder / Experience Builder. Defaults to the
    // first offering but is not bound to it.
    @api offeringKey = OFFERING_KEY;

    // Preview mode. When the GTM Content Manager passes draft structure and
    // content in, this component renders those instead of fetching its own,
    // so the editor previews through the real renderer rather than a
    // reimplementation of it that can drift.
    _preview = false;

    @api
    get previewSections() { return this._sectionRows; }
    set previewSections(value) {
        // An empty array is truthy. Without the length check the editor's
        // first render would put this component into preview mode with no
        // sections and it would never fetch its own.
        if (!value || !value.length) return;
        this._preview = true;
        this._sectionRows = value;
    }

    @api
    get previewFieldMeta() { return this._fieldMeta; }
    set previewFieldMeta(value) {
        if (!value) return;
        this._preview = true;
        this._fieldMeta = value;
    }

    @api
    get previewContent() { return this._cms; }
    set previewContent(value) {
        if (!value || !Object.keys(value).length) return;
        this._preview = true;
        this._cms = value;
    }

    /**
     * Where each section currently sits, in viewport coordinates.
     *
     * Viewport-relative rather than offsetTop because in the editor this
     * component is inside a scaled container: offsetTop reports untransformed
     * layout pixels, and the caller would scroll to the wrong place by exactly
     * the scale factor. getBoundingClientRect is measured after the transform,
     * so the caller can diff it against its own rect and get a real answer.
     */
    @api
    getSectionRects() {
        const out = [];
        this.template.querySelectorAll('[data-section]').forEach((el) => {
            const r = el.getBoundingClientRect();
            // The masthead is sticky, so its rect sits at the top of the frame
            // no matter where the page is scrolled. A caller that treated that
            // as a position would compute "no movement" when asked to scroll to
            // it, and would read it as the current section forever.
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

    _observer;
    _revealed = new Set();
    _observed = new WeakSet();
    _scrollHandler;

    // ─── CMS resolution helpers ────────────────────────────────────────────────
    // Priority: GTM_Page_Content__c (_cms map) → the built-in DEFAULTS

    _ct(key) { return this._cms[key] || null; }

    /**
     * Undeclared fields on a section, shaped for the template.
     *
     * The item shape of a list is read from the data rather than configured:
     * strings become chips, two-key objects become a titled paragraph, and
     * anything wider becomes a card. Nothing here knows what a capability or
     * an FAQ entry is, which is what keeps it general.
     */
    /**
     * The class, id and inline style an editor set on a field, keyed by
     * "section::field". LWC cannot compute an attribute inside a template, so
     * every field that can carry presentation resolves it here.
     */
    _pres(sectionKey, fieldKey) {
        const m = this._fieldMeta.find(
            (x) => x.sectionKey === sectionKey && x.fieldKey === fieldKey
        );
        if (!m) return { cls: '', id: null, style: null };
        return {
            cls: m.cssClass ? ' ' + m.cssClass : '',
            id: m.htmlId || null,
            style: m.inlineStyle || null
        };
    }

    _extrasFor(sectionKey, spec) {
        // All five LAYOUT_FIELDS buckets count as "declared" -- missing
        // icontext/enum here is why a properly-bound field (closing's
        // ctaLabel, an icontext) used to leak through a second time as an
        // orphaned "extra": rendered correctly where it's actually bound,
        // then again here as a bare label with no value, because none of
        // isText/isRich/isList/isPairs/isCards matches 'icontext' or 'enum'.
        const declared = new Set(
            (spec.text || []).concat(
                spec.rich || [],
                spec.json || [],
                spec.icontext || [],
                spec.enum || []
            )
        );
        const prefix = sectionKey + '::';
        return this._fieldMeta
            .filter((m) => m.sectionKey === sectionKey && !declared.has(m.fieldKey))
            .map((m) => {
                const raw = this._cms[prefix + m.fieldKey];
                const out = {
                    key: m.fieldKey,
                    label: m.label || '',
                    cls: 'extra' + (m.cssClass ? ' ' + m.cssClass : ''),
                    htmlId: m.htmlId || null,
                    style: m.inlineStyle || null,
                    hasLabel: !!m.label,
                    isText: m.fieldType === 'text',
                    isRich: m.fieldType === 'rich',
                    isList: false,
                    isPairs: false,
                    isCards: false,
                    value: raw || '',
                    items: []
                };
                if (m.fieldType !== 'json') return out;
                const list = this._cj(prefix + m.fieldKey) || [];
                if (!list.length) return out;
                const first = list[0];
                if (typeof first !== 'object' || first === null) {
                    out.isList = true;
                    out.items = this._withKeys(list.map((v) => String(v)));
                    return out;
                }
                const keys = Object.keys(first);
                const shaped = list.map((entry, i) => ({
                    id: `${m.fieldKey}-${i}`,
                    badge: keys.length > 2 ? String(entry[keys[0]] || '') : '',
                    title: String(entry[keys[keys.length > 2 ? 1 : 0]] || ''),
                    body: String(entry[keys[keys.length > 2 ? 2 : 1]] || '')
                }));
                if (keys.length > 2) { out.isCards = true; } else { out.isPairs = true; }
                out.items = shaped;
                return out;
            })
            // A field with nothing in it draws nothing, rather than an empty
            // heading where an editor has created a row but not filled it.
            .filter((x) => x.value || x.items.length);
    }
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
        const list = rows
            .filter((row) => FRAME_LAYOUTS.indexOf(row.layoutType) === -1)
            // A layout this build does not know is skipped rather than drawn.
            // Without this it fell through to the generic path, where every one
            // of its fields counted as undeclared and got dumped into the page
            // as loose headings — which is what a renamed layout looks like to
            // a browser still running the previous bundle.
            .filter((row) => {
                if (LAYOUT_FIELDS[row.layoutType]) return true;
                // eslint-disable-next-line no-console
                console.warn('[gtmStory] unknown layout, section skipped:', row.layoutType, row.sectionKey);
                return false;
            })
            .map((row) => {
            const k = row.sectionKey;
            const t = row.layoutType;
            const spec = LAYOUT_FIELDS[t] || { text: [], rich: [], json: [] };
            const fb = SECTION_FALLBACKS[t] || {};

            // The ground this section sits on -- 'page' (white/default),
            // 'tint' (grey) or 'invert' (black). Drives both the section's own
            // banding classes and whether a spacer renders after it (§2.4).
            const band = LAYOUT_BAND[t] || 'page';
            const widthClass = row.width === 'wide' ? 'sec--wide' : 'sec--standard';
            const bandClasses = [];
            if (band === 'invert') {
                bandClasses.push(t === 'closing' ? 'ps-band--asym' : 'ps-band', 'ps-band--invert');
            } else if (band === 'tint') {
                bandClasses.push('ps-band', 'ps-band--tint');
            }
            const sectionClass = [
                t === 'hero' ? 'sec--hero' : '',
                t === 'closing' ? 'sec--closing' : '',
                widthClass,
                ...bandClasses
            ].filter(Boolean).join(' ');

            const s = {
                key: k,
                layoutType: t,
                band,
                navLabel: row.label || '',
                isHero: t === 'hero',
                isLedeChips: t === 'lede-chips',
                isRouteProof: t === 'route-proof',
                isCardGrid: t === 'card-grid',
                isStat: t === 'stat',
                isUsePitch: t === 'use-pitch',
                isFaq: t === 'faq',
                isClosing: t === 'closing',
                isStatement: t === 'statement',
                sectionClass
            };

            // Resolve every field this layout declares: record -> fallback.
            spec.text.concat(spec.rich).forEach((f) => {
                s[f] = this._ct(k + '::' + f) || fb[f] || '';
            });
            // A button carries a label and an icon in one JSON object, so it
            // resolves to two values the template can place separately.
            (spec.icontext || []).forEach((f) => {
                const parsed = this._cj(k + '::' + f) || {};
                const fbv = fb[f] || {};
                s[f] = parsed.label || fbv.label || '';
                s[f + 'Icon'] = ctaGlyph(parsed.icon || fbv.icon || '');
            });
            spec.json.forEach((f) => {
                const fromRecord = this._cj(k + '::' + f);
                s[f] = (fromRecord && fromRecord.length) ? fromRecord : (fb[f] || []);
            });

            // Presentation an editor set on any of this section's fields.
            s.pres = {};
            ['text', 'rich', 'json', 'icontext'].forEach((bucket) => {
                (spec[bucket] || []).forEach((f) => { s.pres[f] = this._pres(k, f); });
            });

            // Fields nobody declared. A layout is a shape the page knows how to
            // draw, but the schema is editable, so a section can carry fields
            // this renderer has never heard of. Those are drawn generically,
            // after the layout's own content — visible and editable rather
            // than silently dropped, which is what happens when a renderer
            // only ever looks for the names it was written against.
            s.extras = this._extrasFor(k, spec);
            s.hasExtras = s.extras.length > 0;

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

        // Spacer pass (§2.4): deterministic, computed over the drawn sequence
        // once every section's band is known. A spacer renders after a section
        // unless it or the next section is self-padded (tint or invert ground)
        // -- a banded section already carries its own top/bottom rhythm, so a
        // spacer beside it would double it up.
        const selfPadded = (s) => s.band !== 'page';
        list.forEach((s, i) => {
            s.spacerAfter = (i === list.length - 1)
                ? !selfPadded(s)
                : !selfPadded(s) && !selfPadded(list[i + 1]);
        });

        return list;
    }

    // for:each needs a stable key, and a bare string cannot carry one.
    _withKeys(list) {
        return list.map((text, i) => ({ id: i + '-' + text, text }));
    }

    _buildFaqs(fromRecords) {
        const source = fromRecords.length ? fromRecords : DEFAULTS.faqs;
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

    /**
     * The page's own beats, in order, for the non-interactive index rendered
     * beside the hero. Frame layouts (masthead/footer/assistant) are not
     * beats; a layout this build cannot draw is not on the page; the hero
     * itself does not list itself; and a row nobody has labelled yet has
     * nothing to show.
     */
    get pageIndex() {
        const rows = this._sectionRows.length ? this._sectionRows : DEFAULT_SECTIONS;
        return rows
            .filter((row) => FRAME_LAYOUTS.indexOf(row.layoutType) === -1)
            .filter((row) => LAYOUT_FIELDS[row.layoutType])
            .filter((row) => row.layoutType !== 'hero')
            .filter((row) => row.label)
            .map((row, i) => ({
                id: row.sectionKey,
                label: row.label,
                num: String(i + 1).padStart(2, '0')
            }));
    }


    // ---- body getters ----


    // ---- misc computed ----

    get rootClass() {
        if (this.theme === 'dark') return 'story-root ps-scope dark';
        if (this.theme === 'light') return 'story-root ps-scope light';
        return 'story-root ps-scope';
    }

    get proofClass() { return this.proofOn ? 'proof rv d3 on' : 'proof rv d3'; }
    // Masthead and footer text. Resolved the same way as any section, so a
    // second offering supplies its own rather than inheriting this one's.
    // The masthead and the footer are separate sections so that selecting one
    // in the editor scrolls the preview to it. Both resolve the same way as any
    // other section; they just render outside the sequence.
    _frame(layoutType) {
        const rows = this._sectionRows.length ? this._sectionRows : DEFAULT_SECTIONS;
        const row = rows.find((r) => r.layoutType === layoutType);
        const key = row ? row.sectionKey : layoutType.replace('page-', '');
        const fb = SECTION_FALLBACKS[layoutType] || {};
        const out = { sectionKey: key };
        (LAYOUT_FIELDS[layoutType] || { text: [] }).text.forEach((f) => {
            out[f] = this._ct(key + '::' + f) || fb[f] || '';
        });
        return out;
    }

    get header() { return this._frame('page-header'); }
    get footer() { return this._frame('page-footer'); }

    get proofBarLabel() { return `${this.offeringKey} \u00b7 live preview`; }
    get gaugeStyle() { return `--pct: ${this.gaugeValue};`; }
    get progressStyle() { return `width: ${this.scrollPct}%;`; }



    // ---- lifecycle ----

    connectedCallback() {
        this.loadFonts();
        // In preview mode the parent owns the data; fetching would overwrite the
        // draft. The window-level listeners are skipped too: inside the editor
        // this component sits in a scaled, scrolling container, so window scroll
        // is not this page's scroll and the progress bar would read as noise.
        if (this._preview) return;
        this._scrollHandler = this.handleScroll.bind(this);
        window.addEventListener('scroll', this._scrollHandler, { passive: true });
        getPageLayout({ offeringKey: this.offeringKey, templateType: 'story', industryKey: null })
            .then((layout) => {
                if (!layout) return;
                if (layout.content) this._cms = layout.content;
                if (layout.sections && layout.sections.length) this._sectionRows = layout.sections;
                if (layout.fieldMeta) this._fieldMeta = layout.fieldMeta;
            })
            .catch((err) => {
                // Surfaced, not swallowed: a silent failure here is what let the
                // page render hardcoded defaults for months without anyone noticing.
                this._loadError = 'Page content could not be loaded; showing built-in defaults.';
                // eslint-disable-next-line no-console
                console.error('[gtmStory] getPageLayout failed:', JSON.stringify(err));
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
        // Deliberately not guarded on "have we set up yet". Sections arrive in
        // two waves — the built-in defaults, then the records — and a section
        // added in the editor is a DOM node that did not exist on the first
        // render. Bailing out here once the observer existed left those nodes
        // unobserved and therefore permanently at opacity 0: the section took
        // up its full height on the page and drew nothing.
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
        // .rv-stagger containers do not carry .rv -- they must be queried too.
        const nodes = this.template.querySelectorAll('.rv, .rv-stagger');
        if (!nodes || nodes.length === 0) return;
        // In preview the sections live in a transformed, independently scrolled
        // container. IntersectionObserver measures against the browser viewport,
        // so anything below the fold there would never intersect and would stay
        // at opacity 0 — a blank preview. Reveal everything up front instead.
        if (this._preview || !('IntersectionObserver' in window) || this.reducedMotion) {
            nodes.forEach((el) => { el.classList.add('in'); this._revealed.add(el); });
            return;
        }
        if (!this._observer) {
            this._observer = new IntersectionObserver(
                (entries) => {
                    entries.forEach((entry) => {
                        // PS's threshold is 0.2, but a section taller than
                        // ~3.5 viewports can never reach 20% visible. The
                        // [0, 0.2] pair lets a tall element in on height.
                        const shown = entry.isIntersecting && (
                            entry.intersectionRatio >= 0.2 ||
                            entry.intersectionRect.height >= 240
                        );
                        // once:false -- PS replays on scroll-back.
                        if (shown) {
                            entry.target.classList.add('in');
                            this._revealed.add(entry.target);
                        } else if (!entry.isIntersecting) {
                            entry.target.classList.remove('in');
                            this._revealed.delete(entry.target);
                        }
                    });
                },
                // PS's exact observer options.
                { threshold: [0, 0.2], rootMargin: '0px 0px -50px 0px' }
            );
        }
        // Observing a node twice is harmless, but tracking what has already
        // been handed over keeps this cheap on every re-render.
        nodes.forEach((el) => {
            if (this._observed.has(el)) return;
            this._observed.add(el);
            this._observer.observe(el);
        });
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

    // The hero's page index doubles as real in-page navigation -- a rep or
    // prospect can jump straight to a section, not just see its name. Same
    // [data-section] attribute getSectionRects() already queries, so this
    // never drifts from what the Content Manager preview considers a section.
    handleNavClick(event) {
        const targetKey = event.currentTarget.dataset.target;
        const el = this.template.querySelector(`[data-section="${targetKey}"]`);
        if (el) el.scrollIntoView({ behavior: this.reducedMotion ? 'auto' : 'smooth', block: 'start' });
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

        // These are content: they live on the mechanism section like every
        // other field on this page, rather than on a custom setting read
        // through the retired story CMS controller.
        const objects = parseInt(this._ct('mechanism::proofObjectsCount'), 10) || 1284;
        const deps = parseInt(this._ct('mechanism::proofDepsCount'), 10) || 3140;
        const health = parseInt(this._ct('mechanism::proofHealthScore'), 10) || 84;

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
