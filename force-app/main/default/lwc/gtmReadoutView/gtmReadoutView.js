import { LightningElement, api, track } from 'lwc';
import getPublishedReadout from '@salesforce/apex/GtmReadoutPublicController.getPublishedReadout';
import getCommentSections from '@salesforce/apex/GtmReadoutCommentController.getCommentSections';
import submitComment from '@salesforce/apex/GtmReadoutCommentController.submitComment';

/**
 * The readout, as the recipient sees it.
 *
 * ── What changed, and why it is arranged this way ─────────────────────────
 * This used to render Approved_Content__c through one
 * lightning-formatted-rich-text and stop. It now renders the designed
 * readout: a verdict with both axes and their ladders, a provenance-chipped
 * scorecard, a tier-grouped table of what will not port, the estate, the
 * roadmap, the limits and the close.
 *
 * The join is a SPLIT, not a template swap. A readout is two kinds of thing:
 *
 *   PROSE       Approved_Content__c. Written by the generator, edited by the
 *               rep, spliced by GUS. Seven <h2> sections, named by
 *               GtmReadoutModel.SECTIONS.
 *   MEASUREMENT Approved_Data__c. Frozen at generation, edited by nobody.
 *               Scores, band ladders, provenance, gaps, limits.
 *
 * This component renders the measurement half as the designed furniture and
 * drops each prose section into the panel that owns it. Neither half can
 * pretend to be the other: prose reaches the DOM only through
 * lightning-formatted-rich-text (which sanitises), and no number on this page
 * comes from prose.
 *
 * ── The rule that makes render-time design safe ───────────────────────────
 * THIS COMPONENT NEVER INVENTS AN ASSERTION. Every number, band, tier phrase,
 * provenance chip, hedge and limit comes from the frozen snapshot. Where a
 * datum is absent the panel is omitted — there are no defaults and no
 * placeholder values anywhere below. A renderer that can produce
 * "Accelerator-Ready" when the data does not say so is a renderer that can
 * change what an already-approved readout means, and the whole point of
 * freezing the snapshot is that it cannot.
 *
 * The furniture this component does contribute — section numbers, the word
 * VIEW, the tier key sentence, "COMMENT" — asserts nothing about the client.
 *
 * ── Modes ─────────────────────────────────────────────────────────────────
 * Read is the base form and renders with no JS at all. Present is a paged
 * pager, entered only where a pager works (fine pointer, wide enough), never
 * forced onto a phone. Print is a third form and is CSS-only, because a
 * headless PDF path does not reliably fire beforeprint.
 *
 * ── Comments ──────────────────────────────────────────────────────────────
 * Unchanged and still write-only: the box posts to the readout's review case
 * and never reads the thread back, because that thread also carries the reps'
 * own internal notes. See GtmReadoutCommentController.
 */
export default class GtmReadoutView extends LightningElement {
    // ─── preview inputs (gtmReadoutReview) ────────────────────────────────
    //
    // The rep and the approver have to be able to see the thing they are
    // approving. Passing content in directly — rather than making this
    // component fetch — keeps the guest path exactly one Apex call wide and
    // means the preview can show an UNSAVED draft, which is the state a rep
    // is actually in while editing.

    _previewContent = null;
    _previewData = null;

    @api
    get previewContent() { return this._previewContent; }
    set previewContent(value) {
        this._previewContent = value;
        this.rebuild();
    }

    @api
    get previewData() { return this._previewData; }
    set previewData(value) {
        this._previewData = value;
        this.rebuild();
    }

    /** Suppresses the comment box and the rep contact block in the preview. */
    @api previewMode = false;

    // ─── state ───────────────────────────────────────────────────────────
    @track isLoading = true;
    @track notFound = false;
    @track model = null;
    @track mode = 'read';
    @track panelIndex = 0;
    @track panelCount = 0;
    @track tone = 'normal';

    @track sectionOptions = [];
    @track selectedSection = '';
    @track commentValue = '';
    @track isSendingComment = false;
    @track commentNotice = '';
    @track commentFailed = false;

    /** Same cap the server enforces — a courtesy, not a control. */
    maxCommentLength = 3000;

    _token = '';
    _readout = null;
    _observer = null;
    _mediaQuery = null;
    _onMediaChange = null;
    _onBeforePrint = null;
    _onAfterPrint = null;
    _printReturnMode = null;

    // ─── lifecycle ───────────────────────────────────────────────────────

    connectedCallback() {
        this.resolveMode();
        this.watchViewport();
        this.watchPrint();

        if (this.previewMode) {
            this.isLoading = false;
            this.rebuild();
            return;
        }

        const token = this.readTokenFromUrl();
        if (!token) {
            this.notFound = true;
            this.isLoading = false;
            return;
        }
        this._token = token;
        this.loadSections();
        getPublishedReadout({ token })
            .then((data) => {
                // Any falsy or content-less response is "not found" — matching
                // the guest contract's "for a valid published token only, or
                // nothing". A readout with data but no prose is still a
                // readout; one with neither is not.
                if (data && (data.content || data.dataJson)) {
                    this._readout = data;
                    this.rebuild();
                } else {
                    this.notFound = true;
                }
            })
            .catch(() => {
                // No detail surfaced to the guest: a thrown error and an empty
                // result must look identical.
                this.notFound = true;
            })
            .finally(() => { this.isLoading = false; });
    }

    disconnectedCallback() {
        if (this._observer) { this._observer.disconnect(); this._observer = null; }
        if (this._mediaQuery && this._onMediaChange) {
            const off = this._mediaQuery.removeEventListener || this._mediaQuery.removeListener;
            if (off) off.call(this._mediaQuery, 'change', this._onMediaChange);
        }
        if (this._onBeforePrint) window.removeEventListener('beforeprint', this._onBeforePrint);
        if (this._onAfterPrint) window.removeEventListener('afterprint', this._onAfterPrint);
    }

    renderedCallback() {
        this.observePanels();
    }

    // ─── the model ───────────────────────────────────────────────────────

    get rawContent() {
        if (this.previewMode) return this._previewContent || '';
        return this._readout ? (this._readout.content || '') : '';
    }

    get rawData() {
        if (this.previewMode) return this._previewData || '';
        return this._readout ? (this._readout.dataJson || '') : '';
    }

    /**
     * Recomputes everything the template reads.
     *
     * Done once, on change, rather than in getters: the template touches this
     * model from roughly eighty places and a getter chain re-deriving the
     * scorecard on every one of them is both slow and — because the derivations
     * allocate — a source of needless re-renders.
     */
    rebuild() {
        const data = this.parseData(this.rawData);
        const sections = splitSections(this.rawContent);
        this.model = buildViewModel(data, sections, this.repContact());
        this.panelCount = this.model ? this.model.panels.length : 0;
    }

    parseData(raw) {
        if (!raw) return null;
        try {
            const parsed = JSON.parse(raw);
            return parsed && typeof parsed === 'object' ? parsed : null;
        } catch (e) {
            // A snapshot we cannot read is a snapshot we do not use. The prose
            // still renders, in the designed chrome, with no invented panels.
            return null;
        }
    }

    repContact() {
        if (this.previewMode || !this._readout) return null;
        const { repName, repEmail, repPhone } = this._readout;
        if (!repName && !repEmail && !repPhone) return null;
        return {
            name: repName || '',
            email: repEmail || '',
            phone: repPhone || '',
            // Built here rather than in the template, which cannot concatenate.
            // encodeURIComponent keeps a hostile-looking address from breaking
            // out of the attribute, though what reaches here is a User record's
            // own Email/Phone rather than anything a caller supplied.
            emailHref: repEmail ? 'mailto:' + encodeURIComponent(repEmail) : '',
            phoneHref: repPhone ? 'tel:' + String(repPhone).replace(/[^\d+]/g, '') : '',
            hasEmail: !!repEmail,
            hasPhone: !!repPhone,
            initials: initialsOf(repName)
        };
    }

    // ─── template reads ──────────────────────────────────────────────────

    get hasReadout() { return !!this.model; }
    get rootClass() { return 'rv-root'; }
    get isPresent() { return this.mode === 'present'; }
    get presentClass() { return this.mode === 'present' ? 'on' : ''; }
    get readClass() { return this.mode === 'present' ? '' : 'on'; }
    get counterLabel() {
        return pad2(this.panelIndex + 1) + ' / ' + pad2(this.panelCount);
    }
    get showComment() {
        return !this.previewMode && this.hasReadout && this.sectionOptions.length > 0;
    }
    get isCommentDisabled() { return this.isSendingComment; }
    get canSendComment() {
        return !this.isSendingComment && !!this.selectedSection && !!this.commentValue.trim();
    }
    get commentNoticeClass() {
        return this.commentFailed
            ? 'rv-comment-notice rv-comment-notice--error'
            : 'rv-comment-notice';
    }

    // ─── modes ───────────────────────────────────────────────────────────

    /**
     * Read unless a pager genuinely works here. The saved preference can only
     * ever pin Read — never force Present — so a stored choice made on a
     * desktop cannot follow the reader onto a phone and give them a horizontal
     * pager with no room to page.
     */
    resolveMode() {
        let saved = null;
        try { saved = window.localStorage.getItem('ma-readout-view'); } catch (e) { saved = null; }
        if (saved === 'read') { this.mode = 'read'; return; }
        this.mode = this.viewportSuitsPresent() ? 'present' : 'read';
    }

    viewportSuitsPresent() {
        try {
            return window.matchMedia('(pointer: fine) and (min-width: 1180px) and (min-height: 700px)').matches;
        } catch (e) {
            return false;
        }
    }

    watchViewport() {
        try {
            this._mediaQuery = window.matchMedia('(pointer: fine) and (min-width: 1180px) and (min-height: 700px)');
            this._onMediaChange = () => { this.resolveMode(); };
            const on = this._mediaQuery.addEventListener || this._mediaQuery.addListener;
            if (on) on.call(this._mediaQuery, 'change', this._onMediaChange);
        } catch (e) {
            this._mediaQuery = null;
        }
    }

    /**
     * Print is the Read form. The CSS guarantees it on its own; this only
     * restores the reader's mode afterwards so printing from Present does not
     * silently leave them in Read.
     */
    watchPrint() {
        this._onBeforePrint = () => {
            this._printReturnMode = this.mode;
            this.mode = 'read';
        };
        this._onAfterPrint = () => {
            if (this._printReturnMode) this.mode = this._printReturnMode;
            this._printReturnMode = null;
        };
        window.addEventListener('beforeprint', this._onBeforePrint);
        window.addEventListener('afterprint', this._onAfterPrint);
    }

    handleShowPresent() { this.setMode('present'); }
    handleShowRead() { this.setMode('read'); }

    setMode(next) {
        if (next === 'present' && !this.viewportSuitsPresent()) return;
        this.mode = next;
        try {
            if (next === 'read') window.localStorage.setItem('ma-readout-view', 'read');
            else window.localStorage.removeItem('ma-readout-view');
        } catch (e) {
            // A browser refusing storage costs the preference, not the page.
        }
    }

    handlePrint() {
        try { window.print(); } catch (e) { /* nothing else to offer */ }
    }

    // ─── pager ───────────────────────────────────────────────────────────

    observePanels() {
        if (!this.isPresent) {
            if (this._observer) { this._observer.disconnect(); this._observer = null; }
            return;
        }
        const stage = this.template.querySelector('.stage');
        const panels = this.template.querySelectorAll('.panel');
        if (!stage || !panels.length) return;
        if (this._observer) this._observer.disconnect();
        try {
            this._observer = new IntersectionObserver((entries) => {
                let best = null;
                entries.forEach((entry) => {
                    if (!entry.isIntersecting) return;
                    if (!best || entry.intersectionRatio > best.intersectionRatio) best = entry;
                });
                if (!best) return;
                const index = [].indexOf.call(panels, best.target);
                if (index > -1 && index !== this.panelIndex) {
                    this.panelIndex = index;
                    this.tone = best.target.classList.contains('red') ? 'red' : 'normal';
                }
            }, { root: stage, threshold: [0.6] });
            panels.forEach((panel) => this._observer.observe(panel));
        } catch (e) {
            this._observer = null;
        }
    }

    handlePrev() { this.goToPanel(this.panelIndex - 1); }
    handleNext() { this.goToPanel(this.panelIndex + 1); }

    handleKey(event) {
        if (!this.isPresent) return;
        const target = event.target;
        if (target && (target.tagName === 'TEXTAREA' || target.tagName === 'INPUT')) return;
        if (event.key === 'ArrowRight' || event.key === 'PageDown') {
            event.preventDefault(); this.goToPanel(this.panelIndex + 1);
        } else if (event.key === 'ArrowLeft' || event.key === 'PageUp') {
            event.preventDefault(); this.goToPanel(this.panelIndex - 1);
        } else if (event.key === 'Home') {
            event.preventDefault(); this.goToPanel(0);
        } else if (event.key === 'End') {
            event.preventDefault(); this.goToPanel(this.panelCount - 1);
        }
    }

    goToPanel(index) {
        const panels = this.template.querySelectorAll('.panel');
        if (!panels.length) return;
        const bounded = Math.max(0, Math.min(panels.length - 1, index));
        const panel = panels[bounded];
        if (!panel) return;
        try {
            panel.scrollIntoView({ inline: 'start', block: 'nearest', behavior: 'smooth' });
        } catch (e) {
            panel.scrollIntoView();
        }
        this.panelIndex = bounded;
    }

    // ─── token ───────────────────────────────────────────────────────────

    /**
     * Deliberately permissive: ?token=, the ?readout= spelling gtmConfigurator
     * mints for the same token, the hash form of either, and a trailing
     * /readout/<token> path segment. Being permissive costs nothing
     * security-wise — the Apex WHERE clause, not the URL shape, is the access
     * control.
     */
    readTokenFromUrl() {
        const get = (name) => {
            try {
                const search = new URLSearchParams(window.location.search);
                if (search.has(name)) return search.get(name);
                const hash = new URLSearchParams((window.location.hash || '').replace(/^#/, ''));
                if (hash.has(name)) return hash.get(name);
            } catch (e) {
                return null;
            }
            return null;
        };
        return get('token') || get('readout') || this.readTokenFromPath() || '';
    }

    readTokenFromPath() {
        try {
            const path = (window.location && window.location.pathname) || '';
            const match = /\/readout\/([^/?#]+)\/?$/.exec(path);
            if (!match) return null;
            const candidate = decodeURIComponent(match[1]);
            return /^[A-Za-z0-9_-]+$/.test(candidate) ? candidate : null;
        } catch (e) {
            return null;
        }
    }

    // ─── comments ────────────────────────────────────────────────────────

    loadSections() {
        return getCommentSections()
            .then((sections) => {
                this.sectionOptions = (sections || []).map((s) => ({ label: s, value: s }));
            })
            .catch(() => { this.sectionOptions = []; });
    }

    handleSectionChange(event) {
        this.selectedSection = event.detail ? event.detail.value : event.target.value;
    }

    handleCommentChange(event) {
        this.commentValue = event.target.value || '';
    }

    handleSendComment() {
        if (!this.canSendComment) return;
        this.isSendingComment = true;
        this.commentNotice = '';
        this.commentFailed = false;
        submitComment({
            token: this._token,
            section: this.selectedSection,
            body: this.commentValue
        })
            .then((result) => {
                const accepted = !!(result && result.accepted);
                this.commentFailed = !accepted;
                this.commentNotice = (result && result.message)
                    || (accepted ? 'Thanks — your comment has been sent.' : '');
                if (accepted) this.commentValue = '';
            })
            .catch(() => {
                this.commentFailed = true;
                this.commentNotice =
                    'Your comment could not be sent. Please reach out to your Publicis Sapient contact.';
            })
            .finally(() => { this.isSendingComment = false; });
    }
}

/* ═══════════════════════════════════════════════════════════════════════════
   Pure helpers. Exported for the tests, and kept out of the class because none
   of them touch component state — they turn a snapshot and some prose into the
   shape the template reads, and nothing else.
   ═══════════════════════════════════════════════════════════════════════════ */

/**
 * Splits the readout prose into its <h2> sections.
 *
 * Deliberately the same rule GtmReadoutAgentEdit.sectionSpan applies on the
 * server: a section runs from just after its heading's closing tag to just
 * before the next heading of the same or a higher level, so an <h2> section
 * takes its <h3> children with it. Two implementations of one rule is a risk
 * worth naming; one rule with two implementations is still better than two
 * rules, which is what a DOM-walking version here would have been.
 *
 * Anything before the first <h2> is returned under an empty heading, and a
 * heading nobody recognises is still returned — it is the renderer's job to
 * place it, never to drop it.
 */
export function splitSections(html) {
    const out = [];
    if (!html) return out;
    const pattern = /<h([12])[^>]*>([\s\S]*?)<\/h\1\s*>/gi;
    let match = pattern.exec(html);
    if (!match) {
        const body = html.trim();
        if (body) out.push({ heading: '', body });
        return out;
    }
    const preamble = html.slice(0, match.index).trim();
    if (preamble) out.push({ heading: '', body: preamble });
    while (match) {
        const heading = stripTags(match[2]).replace(/\s+/g, ' ').trim();
        const bodyStart = match.index + match[0].length;
        const next = pattern.exec(html);
        const bodyEnd = next ? next.index : html.length;
        out.push({ heading, body: html.slice(bodyStart, bodyEnd).trim() });
        match = next;
    }
    return out;
}

function stripTags(value) {
    return value ? String(value).replace(/<[^>]*>/g, '') : '';
}

function pad2(n) {
    return String(n).padStart(2, '0');
}

function initialsOf(name) {
    if (!name) return '';
    return String(name)
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 2)
        .map((part) => part.charAt(0).toUpperCase())
        .join('');
}

function proseFor(sections, heading) {
    const wanted = String(heading).toLowerCase();
    const found = sections.find((s) => s.heading.toLowerCase() === wanted);
    return found && found.body ? found.body : '';
}

/** The six lanes are the accelerator's own method, not a claim about a client.
 *  How many phases they run across is the one thing the data decides. */
const LANES = [
    { key: 'foundation', label: 'FOUNDATION & DATA', work: 'Identity, schema, consent model', tone: 'red', start: 1, span: 2 },
    { key: 'audience', label: 'AUDIENCE', work: 'Segment rebuild & consolidation', tone: 'red', start: 2, span: 2 },
    { key: 'content', label: 'CONTENT', work: 'Template and component port', tone: 'g2', start: 2, span: 1 },
    { key: 'journeys', label: 'JOURNEYS', work: 'Restructure & rebuild by priority', tone: 'red', start: 3, span: 2 },
    { key: 'governance', label: 'GOVERNANCE', work: 'Naming, permissions, cutover controls', tone: 'g1', start: 1, span: 1 },
    { key: 'enablement', label: 'ENABLEMENT', work: 'Runs throughout — never "done"', tone: 'dark', start: 1, span: 4 }
];

/**
 * Turns the frozen snapshot plus the prose sections into the template's model.
 *
 * Every branch here is "does the data say this?" — never "what should we show
 * if it doesn't?". A panel with nothing to render is not in the list.
 */
export function buildViewModel(data, sections, rep) {
    const hasProse = sections && sections.length > 0;
    if (!data && !hasProse) return null;

    const d = data || {};
    const pair = d.pair || {};
    const posture = d.posture || {};
    const readiness = d.readiness || null;
    const complexity = d.complexity || null;

    const pairLine = [pair.sourceLabel, pair.targetLabel].filter(Boolean).join(' → ');
    const company = d.company || '';
    const illustrative = posture.illustrative === true;

    const model = {
        company,
        companyUpper: company.toUpperCase(),
        pairLine,
        pairLineUpper: pairLine.toUpperCase(),
        hasPairLine: !!pairLine,
        illustrative,
        illustrativeNote: posture.illustrativeNote || '',
        hasIllustrativeNote: !!posture.illustrativeNote,
        hasMasthead: !!(company || pairLine),
        rep,
        hasRep: !!rep,
        panels: []
    };

    let index = 0;
    const add = (panel) => {
        index += 1;
        panel.eyebrow = pad2(index) + ' / ' + panel.eyebrowText;
        model.panels.push(panel);
    };

    // 01 VERDICT ----------------------------------------------------------
    const verdict = {
        id: 'verdict',
        key: 'verdict',
        title: 'Verdict',
        eyebrowText: 'THE VERDICT',
        cls: 'panel',
        isVerdict: true,
        prose: proseFor(sections, 'Verdict'),
        advisory: d.advisory && d.advisory.on ? d.advisory : null,
        postureStatement: posture.statement || '',
        readiness: readiness ? axisModel(readiness, 'stair') : null,
        complexity: complexity ? axisModel(complexity, 'cx') : null,
        annotations: (d.annotations || []).map((a, i) => ({
            key: 'note-' + i, marker: pad2(i + 1), text: a.text
        })),
        gates: (d.gates || []).map((g, i) => ({
            key: 'gate-' + i, title: g.title, block: g.block
        }))
    };
    verdict.hasAdvisory = !!verdict.advisory;
    verdict.hasPosture = !!verdict.postureStatement;
    verdict.hasProse = !!verdict.prose;
    verdict.hasScores = !!(verdict.readiness || verdict.complexity);
    verdict.hasAnnotations = verdict.annotations.length > 0;
    verdict.hasGates = verdict.gates.length > 0;
    verdict.headline = verdictHeadline(readiness, complexity);
    add(verdict);

    // 02 FINDINGS ---------------------------------------------------------
    const findingsProse = proseFor(sections, 'Findings');
    if (findingsProse) {
        add({
            id: 'findings', key: 'findings', title: 'Findings', eyebrowText: 'WHAT WE FOUND',
            cls: 'panel', isProseOnly: true, headline: 'What we found.',
            prose: findingsProse, hasProse: true
        });
    }

    // 03 THE PATH ---------------------------------------------------------
    const pathProse = proseFor(sections, 'The path');
    const horizon = d.horizon || '';
    if (pathProse || horizon) {
        const phases = phasesFrom(LANES);
        add({
            id: 'path', key: 'path', title: 'The path', eyebrowText: 'THE PATH',
            cls: 'panel', isPath: true,
            headline: 'Six workstreams, sequenced by dependency.',
            prose: pathProse, hasProse: !!pathProse,
            horizon, hasHorizon: !!horizon,
            lanes: LANES.map((l) => ({
                key: l.key, label: l.label, work: l.work,
                segClass: 'lseg ' + l.tone + ' c' + l.start + ' n' + l.span
            })),
            phases
        });
    }

    // 04 CAPABILITY GAPS --------------------------------------------------
    const gaps = d.gaps || null;
    const gapsProse = proseFor(sections, 'Capability gaps');
    if ((gaps && gaps.groups && gaps.groups.length) || gapsProse) {
        add({
            id: 'gaps', key: 'gaps', title: 'Capability gaps', eyebrowText: "WHAT WON'T PORT",
            cls: 'panel', isGaps: true,
            headline: 'Constructs with no direct equivalent.',
            prose: gapsProse, hasProse: !!gapsProse,
            tierKey: gaps ? gaps.key : '',
            hasTierKey: !!(gaps && gaps.key),
            groups: gapsGroups(gaps),
            hasGroups: !!(gaps && gaps.groups && gaps.groups.length)
        });
    }

    // 05 CONTEXT / YOUR ESTATE -------------------------------------------
    const estate = d.estate || null;
    const contextProse = proseFor(sections, 'Context');
    if (estate || contextProse) {
        const tiles = (estate && estate.tiles ? estate.tiles : []).map((t, i) => ({
            key: 'tile-' + i, n: formatCount(t.n), label: t.label
        }));
        const facts = (estate && estate.facts ? estate.facts : []).map((f, i) => ({
            key: 'fact-' + i, label: f.label, value: f.value
        }));
        add({
            id: 'context', key: 'context', title: 'Your estate', eyebrowText: 'YOUR ESTATE',
            cls: 'panel grey', isEstate: true,
            headline: 'What the assessment recorded.',
            prose: contextProse, hasProse: !!contextProse,
            tiles, hasTiles: tiles.length > 0,
            facts, hasFacts: facts.length > 0
        });
    }

    // 06 SCORECARD --------------------------------------------------------
    const dimensions = d.dimensions || [];
    const scorecardProse = proseFor(sections, 'Scorecard');
    if (dimensions.length || scorecardProse) {
        const rows = dimensions.map((row, i) => scorecardRow(row, i));
        const note = scanNote(dimensions);
        add({
            id: 'scorecard', key: 'scorecard', title: 'Scorecard', eyebrowText: 'SCORECARD',
            cls: 'panel', isScorecard: true,
            headline: dimensions.length
                ? dimensions.length + ' dimensions that predict how this goes.'
                : 'Scorecard',
            prose: scorecardProse, hasProse: !!scorecardProse,
            rows, hasRows: rows.length > 0,
            bars: rows.map((r, i) => ({
                key: 'bar-' + i,
                cls: 'b ' + (r.weak ? 'weak ' : '') + percentClass(r.value, r.max)
            })),
            scanNote: note,
            hasScanNote: !!note
        });
    }

    // 07 THE BASIS --------------------------------------------------------
    // Never editable and never abridged. The limits are what make the numbers
    // above them worth trusting, and a rep trimming them to the two that look
    // least awkward is the failure this panel exists to make impossible.
    const basis = d.basis || null;
    const limits = d.limits || [];
    if (basis || limits.length) {
        add({
            id: 'basis', key: 'basis', title: 'How we know', eyebrowText: 'THE BASIS',
            cls: 'panel grey', isBasis: true,
            headline: "How we know this — and what we can't see.",
            how: (basis && basis.how ? basis.how : []).map((h, i) => ({
                key: 'how-' + i, marker: pad2(i + 1), lead: h.lead, text: h.text
            })),
            limits: limits.map((l, i) => ({ key: 'limit-' + i, lead: l.lead, text: l.text })),
            hasHow: !!(basis && basis.how && basis.how.length),
            hasLimits: limits.length > 0,
            resolutionNote: d.resolutionNote || '',
            hasResolutionNote: !!d.resolutionNote
        });
    }

    // 08 NEXT STEPS -------------------------------------------------------
    const nextProse = proseFor(sections, 'Next steps');
    if (nextProse || rep) {
        add({
            id: 'next', key: 'next', title: 'Next steps', eyebrowText: 'NEXT STEPS',
            cls: 'panel red', isNext: true,
            headline: "What we'd need to start.",
            prose: nextProse, hasProse: !!nextProse,
            rep, hasRep: !!rep
        });
    }

    // Anything the generator, a rep or GUS wrote under a heading this
    // renderer does not know. Never dropped — a section nobody planned for is
    // still a section somebody wrote.
    const known = ['', 'verdict', 'findings', 'the path', 'capability gaps',
        'context', 'scorecard', 'next steps'];
    const extras = sections.filter(
        (s) => s.body && known.indexOf(s.heading.toLowerCase()) === -1
    );
    extras.forEach((s, i) => {
        add({
            id: 'extra-' + i, key: 'extra-' + i, title: s.heading, eyebrowText: 'ALSO',
            cls: 'panel', isProseOnly: true, headline: s.heading,
            prose: s.body, hasProse: true
        });
    });

    // Preamble — anything written above the first heading.
    const preamble = sections.find((s) => s.heading === '' && s.body);
    if (preamble && model.panels.length) {
        model.panels[0].preamble = preamble.body;
        model.panels[0].hasPreamble = true;
    }

    return model;
}

function verdictHeadline(readiness, complexity) {
    const tier = readiness && (readiness.tierPhrase || readiness.tier);
    const band = complexity && complexity.band;
    if (tier && band) return tier + ', on a ' + String(band).toLowerCase() + ' estate.';
    if (tier) return tier + '.';
    if (band) return String(band) + ' estate complexity.';
    return 'Where you stand.';
}

/** One axis: the number, the phrase, and the ladder it was scored against. */
function axisModel(axis, shape) {
    const bands = (axis.bands || []).map((b, i) => ({
        key: shape + '-' + i,
        label: b.label,
        range: b.low + '–' + b.high,
        current: b.current === true,
        cls: shape === 'stair'
            ? 'step s' + i + (b.current ? ' on' : '')
            : 'cx' + (b.current ? ' on' : '')
    }));
    const name = axis.tierPhrase || axis.tier || axis.band || '';
    return {
        score: axis.score,
        max: axis.max,
        name,
        hasName: !!name,
        nameClass: shape === 'stair' ? 'tiername' : 'tiername ink',
        scale: axis.scale || '',
        hasScale: !!axis.scale,
        basis: axis.basis || '',
        hasBasis: !!axis.basis,
        bands,
        hasBands: bands.length > 0,
        ladderLabel: bands
            .map((b) => b.label + ' ' + b.range + (b.current ? ' (current)' : ''))
            .join(', ')
    };
}

function scorecardRow(row, i) {
    const value = Number(row.value);
    const max = Number(row.max) || 4;
    const chip = row.chip || '';
    const steps = [];
    for (let s = 1; s <= max; s += 1) {
        steps.push({
            key: 'ms-' + i + '-' + s,
            cls: 'ms h' + s + ' ' + (s === value ? 'now' : (s < value ? 'fill' : 'empty'))
        });
    }
    return {
        key: 'dim-' + i,
        label: row.label,
        value,
        max,
        score: value + ' / ' + max,
        chip,
        chipClass: chip === 'MEASURED' ? 'prov meas' : (chip === 'PARTIAL' ? 'prov part' : 'prov'),
        hasChip: !!chip,
        read: row.read || '',
        hasRead: !!row.read,
        stageLabel: 'Stage ' + value + ' of ' + max,
        steps,
        weak: max > 0 && value / max <= 0.5
    };
}

function percentClass(value, max) {
    const ratio = max ? value / max : 0;
    if (ratio >= 1) return 'p100';
    if (ratio >= 0.75) return 'p75';
    if (ratio >= 0.5) return 'p50';
    return 'p25';
}

/**
 * "Three of eight dimensions score at or below half — read weakest first, that
 * is the order of the work." Counted, never asserted: with nothing weak the
 * sentence says so instead of being suppressed.
 */
function scanNote(dimensions) {
    if (!dimensions || !dimensions.length) return '';
    const weak = dimensions.filter((d) => {
        const max = Number(d.max) || 4;
        return max > 0 && Number(d.value) / max <= 0.5;
    }).length;
    const total = dimensions.length;
    if (!weak) {
        return 'No dimension scores at or below half of its maximum. They are shown weakest '
            + 'first, which is the order of the work.';
    }
    return weak + ' of ' + total + ' dimensions score at or below half. They are shown weakest '
        + 'first, which is the order of the work.';
}

function gapsGroups(gaps) {
    if (!gaps || !gaps.groups) return [];
    return gaps.groups.map((g, i) => ({
        key: 'group-' + i,
        title: g.tier + ' · ' + g.label,
        rows: (g.rows || []).map((r, j) => ({
            key: 'gap-' + i + '-' + j,
            construct: r.construct || '',
            onTarget: r.onTarget || '',
            hasOnTarget: !!r.onTarget,
            takes: r.takes || '',
            hasTakes: !!r.takes,
            hedge: r.hedge || '',
            hedged: r.hedged === true && !!r.hedge
        }))
    }));
}

/** The Gantt, transposed. Same facts, the form that survives a narrow column. */
function phasesFrom(lanes) {
    const phases = [];
    for (let p = 1; p <= 4; p += 1) {
        const items = lanes
            // Enablement is excluded here and stated once, in the band below
            // the list. Repeating "runs throughout" inside all four phases is
            // four lines saying the thing the band already says.
            .filter((l) => l.key !== 'enablement')
            .filter((l) => p >= l.start && p < l.start + l.span)
            .map((l) => ({
                key: 'p' + p + '-' + l.key,
                lane: l.label,
                work: l.work,
                swatch: 'sw ' + l.tone,
                continues: p > l.start
            }));
        if (items.length) phases.push({ key: 'phase-' + p, label: 'PHASE ' + p, items });
    }
    return phases;
}

/** 1200000 reads as 1.2M on a tile; 96 reads as 96. */
function formatCount(value) {
    const n = Number(value);
    if (!isFinite(n)) return String(value);
    if (n >= 1000000) return trimZero(n / 1000000) + 'M';
    if (n >= 10000) return trimZero(n / 1000) + 'k';
    return String(n);
}

function trimZero(n) {
    const rounded = Math.round(n * 10) / 10;
    return String(rounded).replace(/\.0$/, '');
}
