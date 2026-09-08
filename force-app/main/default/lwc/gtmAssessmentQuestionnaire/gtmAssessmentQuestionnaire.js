/**
 * The respondent-facing migration assessment.
 *
 * WHY IT IS CHUNKED. The instrument is eight scored questions, six complexity
 * questions, up to nine supplements and a contact block. As one scroll that is
 * a wall, and a wall is abandoned. The product owner's framing was exact: "it
 * should be broken up in a way a person can digest it, and based on answers the
 * branches needed fire so they don't necessarily answer every single question,
 * but the ones that are relevant to their answers."
 *
 * So: a ROUTING step first (what are you moving, and to what), because those
 * answers decide which instrument the rest of the form is. Then the eight
 * readiness slots in three themed steps, then complexity as an explicitly
 * separate axis, then supplements in their own clearly-labelled section, then
 * where to send it. NEVER MORE THAN FOUR QUESTIONS ON A SCREEN -- a rule this
 * file stated and then broke, rendering all eight supplements on one step, five
 * of them consecutive empty textareas. It is now enforced by the step model
 * rather than asserted in a comment: see supplementPages().
 *
 * WHAT "BRANCHES FIRE" MEANS HERE, PRECISELY. It never means fewer questions.
 * A branch chooses WHICH question fills one of the eight slots; the slot is
 * always filled. Two respondents can be asked two different sets of eight
 * questions and their totals are still both out of 32 and still land in the
 * same four bands. See gtmPredicate.resolveSlots and, on the server,
 * GtmAssessmentInstrument.applyBranches -- and note which of the two is
 * authoritative: this component decides what to RENDER, the server decides what
 * SCORES, and it re-resolves the branches itself from the submitted answers.
 *
 * NOTHING HERE COMPUTES A SCORE THAT MATTERS. The running total shown to the
 * respondent is a courtesy. The payload carries raw answers only; there is no
 * field on it for a score, because GtmAssessmentRequestController discards
 * client-submitted scores and always has.
 *
 * NO PLATFORM BRANCHING. There is not one platform name in this file. The
 * platform list is metadata (getPlatforms), the questions are metadata
 * (getPack), and which question a branch chooses is a predicate in metadata.
 */
import { LightningElement, api, track } from 'lwc';
import getPlatforms from '@salesforce/apex/GtmAssessmentInstrument.getPlatforms';
import getPack from '@salesforce/apex/GtmAssessmentInstrument.getPack';
import getQuestionnaire from '@salesforce/apex/GtmAssessmentQuestions.getQuestionnaire';
import submitRequest from '@salesforce/apex/GtmAssessmentRequestController.submitRequest';
import saveDraft from '@salesforce/apex/GtmAssessmentDraftController.saveDraft';
import resumeDraft from '@salesforce/apex/GtmAssessmentDraftController.resumeDraft';
import emailResumeLink from '@salesforce/apex/GtmAssessmentDraftController.emailResumeLink';
import { resolveSlots, pointsFor } from 'c/gtmPredicate';

/**
 * Titles for the three readiness steps, by slot position. Safe to hold in the
 * component precisely BECAUSE the frame is fixed: positions 1-8 are the one
 * thing no pair and no branch may vary, so a title that describes positions 1-3
 * describes them for every respondent. Anything that varies per pair — the
 * label, the question, the options — comes from the pack.
 */
const READINESS_GROUPS = [
    {
        positions: [1, 2, 3],
        title: 'What you are moving, and whether we can read it',
        blurb: 'Size, access and how much of the automation logic survives the move.'
    },
    {
        positions: [4, 5, 6],
        title: 'What comes across, and what gets rebuilt',
        blurb: 'Content, the data model underneath it, and how far the estate reaches outside the platform.'
    },
    {
        positions: [7, 8],
        title: 'Permission, and who decides',
        blurb: 'Consent state, and whether there is someone who can say yes.'
    }
];

const COMPLEXITY_CHUNK = 3;
/**
 * Supplements are chunked too, and INTERLEAVED before they are chunked.
 *
 * Both halves matter. The chunk keeps the four-per-screen rule; the interleave
 * keeps a respondent from meeting a run of empty textareas, which is what a
 * naive scored-then-verbatim ordering produced -- five of them in a row, and by
 * the third the honest answer is a blank box. Free text is expensive to answer;
 * spacing it between questions that are one click each is the difference
 * between a filled box and an abandoned form.
 */
const SUPPLEMENT_CHUNK = 3;
const BD_CONTEXT_CHUNK = 4;

/**
 * Split a list of questions into screens, BALANCED rather than sliced.
 *
 * Seven questions cut into threes leaves a final screen with one question on
 * it, which reads as the form having lost its place; the same seven spread over
 * the same three screens is 3-2-2. The cap is still the cap -- the page count is
 * derived from it -- so the four-per-screen rule this file states at the top
 * holds either way.
 *
 * ONE implementation, deliberately. This was inline in supplementPages() and
 * was lifted out when the BD-context step needed the same behaviour: a second
 * copy is how two chunking schemes drift until one of them quietly breaks the
 * four-per-screen rule the way the supplements step already did once.
 */
function chunkBalanced(all, cap) {
    if (!all || !all.length) return [];
    const pageCount = Math.ceil(all.length / cap);
    const base = Math.floor(all.length / pageCount);
    let extra = all.length % pageCount;
    const pages = [];
    let at = 0;
    for (let i = 0; i < pageCount; i += 1) {
        const size = base + (extra > 0 ? 1 : 0);
        if (extra > 0) extra -= 1;
        pages.push(all.slice(at, at + size));
        at += size;
    }
    return pages;
}

/**
 * THE BD-CONTEXT FIELDS (ADR-0008 section 5).
 *
 * Eleven qualitative fields that gtmConfigBooking collected and that
 * GtmReadoutController.buildDraftHtml and GtmReadoutAgentContext read. Their
 * only home was the booking modal, so retiring it without carrying them would
 * have quietly emptied several sections of every future readout.
 *
 * THEY ARE NOT INSTRUMENT ANSWERS. They are fixed schema fields on
 * GTM_Assessment_Request__c, not pack-resolved metadata, and nothing about them
 * may reach a score: they never enter `answers`, `complexityAnswers` or
 * `supplementAnswers`, and there is a test asserting exactly that. This is why
 * they are their own step rather than being folded into `supplements` -- the
 * supplements are resolved out of the instrument, and putting fixed schema
 * fields into that resolution chain would put non-instrument content inside the
 * instrument.
 *
 * `targetPlatform` is NOT here. The routing step already collects it
 * (this.routing.target) and buildPayload already sends it; collecting it twice
 * would be two answers to one question with no rule for which wins.
 * `context` is NOT here either -- the contact step already asks it.
 *
 * Labels, options and placeholders are carried across verbatim from
 * gtmConfigBooking.html so a rep reading a readout sees the same vocabulary
 * they always have.
 */
const BD_CONTEXT_FIELDS = [
    {
        key: 'painPoints',
        kind: 'textarea',
        question: "What's not working with your current platform?",
        placeholder: 'Performance, deliverability, lack of features, cost, support…'
    },
    {
        key: 'migrationGoals',
        kind: 'textarea',
        question: 'What do you need from the new platform?',
        placeholder: 'AI-powered personalisation, better journey automation, real-time triggers…'
    },
    {
        key: 'keyIntegrations',
        kind: 'textarea',
        question: 'Key integrations that must stay connected',
        placeholder: 'Salesforce CRM, Snowflake, Adobe AEM, Shopify, internal data warehouse…'
    },
    {
        key: 'successCriteria',
        kind: 'textarea',
        question: 'How will you know the migration succeeded?',
        placeholder: 'KPIs, milestones, or business outcomes that define success'
    },
    {
        key: 'budgetRange',
        kind: 'select',
        question: 'Budget range',
        options: [
            { value: '', label: 'Prefer not to say' },
            { value: 'Under $250K', label: 'Under $250K' },
            { value: '$250K – $500K', label: '$250K – $500K' },
            { value: '$500K – $1M', label: '$500K – $1M' },
            { value: '$1M – $2.5M', label: '$1M – $2.5M' },
            { value: '$2.5M+', label: '$2.5M+' }
        ]
    },
    {
        key: 'contactCount',
        kind: 'number',
        question: 'Contact / lead database size',
        placeholder: 'e.g. 2500000'
    },
    {
        key: 'monthlySendVolume',
        kind: 'number',
        question: 'Monthly email send volume',
        placeholder: 'e.g. 5000000'
    },
    {
        key: 'internalTeamSize',
        kind: 'select',
        question: 'Internal team for this migration',
        options: [
            { value: '', label: 'Select…' },
            { value: 'Just me', label: 'Just me' },
            { value: '2–5 people', label: '2–5 people' },
            { value: '5–10 people', label: '5–10 people' },
            { value: '10+ people', label: '10+ people' }
        ]
    },
    {
        key: 'executiveSponsorship',
        kind: 'select',
        question: 'Executive sponsorship',
        options: [
            { value: '', label: 'Select…' },
            {
                value: 'Strong — executive is driving this',
                label: 'Strong — executive is driving this'
            },
            {
                value: 'Moderate — executive is aware and supportive',
                label: 'Moderate — aware and supportive'
            },
            {
                value: 'Limited — team-level initiative',
                label: 'Limited — team-level initiative'
            },
            { value: 'Unknown', label: 'Unknown' }
        ]
    },
    {
        key: 'decisionMakers',
        kind: 'text',
        question: 'Who approves the final decision?',
        placeholder: 'e.g. CMO, VP Marketing, CIO'
    },
    {
        key: 'urgencyDriver',
        kind: 'text',
        question: "What's driving the timeline?",
        placeholder: 'Contract expires March 2026, board mandate, post-acquisition…'
    }
];

/** The empty shape, so snapshot/restore and buildPayload have one source. */
function emptyBdContext() {
    const out = {};
    BD_CONTEXT_FIELDS.forEach((f) => { out[f.key] = ''; });
    return out;
}

/**
 * Storage is keyed PER LINK, not per browser.
 *
 * One key for the whole origin meant two prospects sharing a machine -- or one
 * person opening two different engagement links -- overwrote each other's
 * answers with no sign that anything had happened. The suffix is the saved
 * configuration the form was opened from, or 'direct'.
 */
const STORAGE_PREFIX = 'ma-assessment-progress-v2';
/** Bumped when the shape below changes, so an old blob is discarded rather
 *  than half-applied. v1 had no version marker at all, which is why v2 exists. */
const STORAGE_VERSION = 2;

const TIMELINES = [
    'Active — next 3 months',
    '3–6 months',
    '6–12 months',
    'Just exploring'
];
const SIZES = ['Under 500 assets', '500–2,000', '2,000–10,000', '10,000+', 'Not sure yet'];

const NOT_DECIDED = '__undecided__';

export default class GtmAssessmentQuestionnaire extends LightningElement {
    /** Passed through to submitRequest when the engagement link is password-gated. */
    @api submissionToken = '';
    @api savedRecordId = '';
    /**
     * A resume token from the page's URL (?resume=...), passed in by whatever
     * hosts the component. Also read directly off location.search as a
     * fallback, because the Experience Builder page it sits on does not always
     * forward query parameters into component attributes.
     */
    @api resumeToken = '';
    @api prospect = '';
    @api industryLabel = '';
    @api prefillCompany = '';
    /**
     * Which offering's instrument this respondent is answering.
     *
     * Defaults to migration-accelerator because that is what every route on
     * both existing sites is (ADR-0006 / backlog D9): this component's own
     * route lives only on GTM_Accelerator1, which is down for maintenance, and
     * the live GTM1 site's booking surface does not reach it at all. A page
     * that does know its offering sets this property; until one does, the
     * default is the honest answer rather than a guess -- migration-accelerator
     * is the only offering that has ever been assessed. It is an @api property
     * rather than a constant precisely so wiring a second offering's route is a
     * page-builder change and not a code change.
     */
    @api offeringKey = 'migration-accelerator';

    /**
     * Rendered inside the configurator's overlay rather than as a page of its
     * own. Only affects chrome: no step, question, branch or score differs.
     *
     * See ADR-0008 -- the overlay is the only host that has the engagement
     * link's context (savedRecordId, submissionToken, the link's own
     * Offering__c), so `embedded` is the normal case and standalone is the
     * exception.
     */
    @api embedded = false;

    /**
     * The rep's calendar link, from the engagement link's ?book= parameter.
     * Carried through to the confirmation panel so the "book an assessment"
     * half of the CTA's promise survives gtmConfigBooking's retirement.
     * Empty on a standalone visit, which simply renders no calendar CTA.
     */
    @api bookingUrl = '';

    /**
     * The host page's visit id, so a draft written during this visit ties back
     * to the trail of what was read before it. Passed down by gtmConfigurator
     * (visitSessionId); empty standalone.
     */
    @api sessionId = '';

    /**
     * The root element's class. `embedded` swaps in a modifier that undoes the
     * full-page assumptions (viewport height, max-width, centring, padding,
     * paper background) -- the overlay card supplies all five.
     */
    get rootClass() {
        return this.embedded ? 'q-root q-root--embedded' : 'q-root';
    }

    @track pack = null;
    /**
     * The unadapted six, from GTM_Assessment_Question__mdt. Only a FALLBACK now:
     * once a pack resolves it carries its own complexityDimensions, adapted to
     * the source platform the same way the eight readiness slots are. Before
     * that, this list is what the second axis looked like for everyone -- the
     * target's vocabulary asked about a source estate.
     */
    @track complexityQuestions = [];
    @track stepIndex = 0;
    @track loading = true;
    @track submitting = false;
    @track submitted = false;
    @track errorMessage = '';
    @track invalidFields = [];

    /** Everything the respondent has said, one flat object. Steps read it; nothing owns it. */
    @track routing = { source: '', target: '', timeline: '', environmentSize: '' };
    @track answers = {};           // readiness: resolved slot key -> option value
    @track complexity = {};        // complexity dimension key -> option value
    @track supplements = {};       // supplement key -> option value
    @track notes = {};             // unscored supplement key -> verbatim text
    @track contact = { name: '', email: '', company: '', role: '', context: '' };
    /**
     * The eleven BD-context fields (ADR-0008 section 5). Business-development
     * context, NOT instrument answers -- see BD_CONTEXT_FIELDS. Every one is
     * optional and none of them is ever scored.
     */
    @track bdContext = emptyBdContext();

    // --------------------------------------------------------- resume state
    /** The server-side draft's token, once one exists. Empty until the
     *  respondent leaves the routing step. */
    @track draftToken = '';
    @track draftExpiresAt = null;
    @track savingDraft = false;
    /** Shown when a server save failed. Never blocks the form: localStorage
     *  still holds everything, so a failed push costs the cross-device link,
     *  not the answers. */
    @track draftError = '';
    /** Shown when someone arrived on a link that no longer resolves. */
    @track resumeNotice = '';
    @track restoredFromLink = false;
    @track resumeEmail = '';
    /** '' | 'sending' | 'sent' | 'failed' */
    @track emailState = '';
    @track emailMessage = '';
    @track linkCopied = false;

    platforms = [];

    // ------------------------------------------------------------- lifecycle

    async connectedCallback() {
        // localStorage first, unconditionally: it is the fast path and it is
        // free. A link, if there is one, overwrites it below -- the server copy
        // is the one that followed the respondent to this device, so on a
        // conflict it is the one that is right.
        this.restore();
        if (this.prefillCompany && !this.contact.company) {
            this.contact = { ...this.contact, company: this.prefillCompany };
        }
        try {
            const [platforms, questionnaire] = await Promise.all([
                getPlatforms(),
                getQuestionnaire({ offeringKey: this.offeringKey })
            ]);
            this.platforms = platforms || [];
            this.complexityQuestions = (questionnaire && questionnaire.complexity) || [];
        } catch (e) {
            // The form still works with free-text platform entry and no
            // complexity axis; refusing to render because a config read failed
            // would lose a lead over a deployment state.
            this.errorMessage = '';
        }
        const token = this.incomingToken();
        if (token) {
            await this.hydrateFromDraft(token);
        }
        if (this.routing.source || this.routing.target) {
            await this.loadPack();
        }
        this.loading = false;
    }

    /**
     * The resume token this page was opened with, from the attribute or, if the
     * host did not forward it, from the query string.
     */
    incomingToken() {
        if (this.resumeToken) {
            return this.resumeToken;
        }
        try {
            const found = /[?&]resume=([A-Za-z0-9_-]{20,64})/.exec(window.location.search || '');
            return found ? found[1] : '';
        } catch (e) {
            return '';
        }
    }

    /**
     * Pulls a saved draft down and replaces local state with it.
     *
     * A token that does not resolve -- expired, already submitted, mistyped,
     * never issued -- comes back as null, identically in all four cases, and is
     * reported to the respondent as one honest sentence rather than four
     * different ones. Whatever was in localStorage is left alone in that case:
     * a dead link is not a reason to also throw away the answers on this
     * device.
     */
    async hydrateFromDraft(token) {
        let draft = null;
        try {
            draft = await resumeDraft({ resumeToken: token });
        } catch (e) {
            draft = null;
        }
        if (!draft || !draft.payload) {
            this.resumeNotice =
                'That saved link is no longer available — it may have expired, or the ' +
                'assessment behind it may already have been sent. Anything you filled in on ' +
                'this device is still here.';
            return;
        }
        let saved = null;
        try {
            saved = JSON.parse(draft.payload);
        } catch (e) {
            saved = null;
        }
        if (!saved) {
            this.resumeNotice = 'We could not read that saved link. Nothing has been lost here.';
            return;
        }
        this.applySnapshot(saved);
        this.draftToken = token;
        this.draftExpiresAt = draft.expiresAt;
        this.restoredFromLink = true;
        this.persist();
    }

    /**
     * Resolves the instrument for the routing answers. Called when the routing
     * step is left, not on every keystroke: the pack is the shape of the rest of
     * the form, and re-shaping it under someone mid-answer is worse than a
     * moment's wait when they press Continue.
     */
    async loadPack() {
        try {
            this.pack = await getPack({
                offeringKey: this.offeringKey,
                sourceName: this.routing.source,
                targetName: this.routing.target === NOT_DECIDED ? '' : this.routing.target
            });
        } catch (e) {
            this.pack = null;
        }
    }

    // ----------------------------------------------------------- step model

    /**
     * The steps this respondent gets, derived from the resolved pack rather
     * than declared. A pair with no supplements has no supplement step; a
     * deployment with no complexity questions has no complexity steps. What
     * never varies is that all eight readiness slots are present across the
     * readiness steps — see slotsForGroup.
     */
    get steps() {
        const steps = [{ kind: 'routing', title: 'About the move' }];
        // The three readiness steps are planned even before a pack has
        // resolved, because the frame is fixed: eight slots in these three
        // groups, for every respondent, on every branch path. Deriving them from
        // the resolved pack instead would make the progress indicator jump from
        // "of 3" to "of 7" the moment the routing step was left, which reads as
        // the form growing while you fill it in.
        READINESS_GROUPS.forEach((group, i) => {
            steps.push({ kind: 'readiness', group: i, title: group.title });
        });
        for (let i = 0; i < this.complexityDimensions.length; i += COMPLEXITY_CHUNK) {
            steps.push({ kind: 'complexity', offset: i, title: 'How big the job is' });
        }
        this.supplementPages().forEach((page, i) => {
            steps.push({ kind: 'supplements', offset: i, title: 'About the target platform' });
        });
        // ADR-0008 section 5. Chunked, so eleven fields are not one wall --
        // which is the exact mistake dc4ad5d built this component to undo. The
        // step kind is `bdContext`, not `context`: `isContext`/`isContact` a
        // single letter apart in a file this size is a bug waiting to be typed.
        this.bdContextPages().forEach((page, i) => {
            steps.push({ kind: 'bdContext', offset: i, title: 'Anything else worth knowing' });
        });
        steps.push({ kind: 'contact', title: 'Where to send it' });
        return steps;
    }

    get step() {
        const steps = this.steps;
        const index = Math.min(this.stepIndex, steps.length - 1);
        return steps[index] || steps[0];
    }

    get stepNumber() {
        return Math.min(this.stepIndex, this.steps.length - 1) + 1;
    }

    get stepCount() {
        return this.steps.length;
    }

    /**
     * "Section 2 of 9", not "Step 2 of 8".
     *
     * The form used to show "Step 2 of 8" in the header while the cards beneath
     * it counted "1 of 8 ... 8 of 8" -- two different eights on one screen, one
     * counting screens and one counting readiness questions, with nothing to
     * tell them apart. They are now a SECTION count and a QUESTION count, and
     * they read as different things because they are named as different things.
     * (The totals also no longer coincide, now that supplements span more than
     * one screen, but a fix that depended on that coincidence not returning
     * would not be a fix.)
     */
    get progressLabel() {
        return `Section ${this.stepNumber} of ${this.stepCount}`;
    }

    get progressStyle() {
        return `width: ${Math.round((this.stepNumber / this.stepCount) * 100)}%`;
    }

    get isRouting()     { return this.step.kind === 'routing'; }
    get isReadiness()   { return this.step.kind === 'readiness'; }
    get isComplexity()  { return this.step.kind === 'complexity'; }
    get isSupplements() { return this.step.kind === 'supplements'; }
    get isBdContext()   { return this.step.kind === 'bdContext'; }
    get isContact()     { return this.step.kind === 'contact'; }
    get isFirstStep()   { return this.stepIndex === 0; }
    get isLastStep()    { return this.stepNumber === this.stepCount; }

    get nextLabel() {
        return this.isLastStep ? this.submitLabel : 'Continue';
    }

    get submitLabel() {
        return this.submitting ? 'Sending…' : 'Send my assessment';
    }

    // --------------------------------------------------------------- slots

    /**
     * The eight questions THIS respondent is asked, after branching. Always
     * eight when a pack resolved: resolveSlots returns one slot per position,
     * because a branch substitutes for a slot's default rather than removing it.
     */
    get resolvedSlots() {
        return resolveSlots(this.pack, this.answers);
    }

    slotsForGroup(group) {
        return this.resolvedSlots.filter((s) => group.positions.includes(s.position));
    }

    /** The slots on the current readiness step, decorated for rendering. */
    get currentSlots() {
        if (!this.isReadiness) return [];
        const group = READINESS_GROUPS[this.step.group];
        return this.slotsForGroup(group).map((slot) => this.decorateSlot(slot));
    }

    get groupBlurb() {
        return this.isReadiness ? READINESS_GROUPS[this.step.group].blurb : '';
    }

    /**
     * One slot, ready to render. The only interesting part is the options:
     * a capped option is rendered DISABLED WITH ITS REASON rather than dropped,
     * so a respondent can see that a 4 was not on offer and why. A ceiling
     * nobody can see is indistinguishable from a rigged scale, and the server
     * drops an over-ceiling answer rather than clamping it, so letting one be
     * submitted at all would only produce a silently unanswered slot.
     */
    decorateSlot(slot) {
        const chosen = this.answers[slot.key];
        const options = (slot.options || []).map((o) => {
            const available = o.available !== false;
            return {
                key: `${slot.key}::${o.value}`,
                value: o.value,
                label: o.label,
                available,
                unavailable: !available,
                unavailableReason: o.unavailableReason,
                checked: chosen === o.value,
                cls: available
                    ? (chosen === o.value ? 'q-opt q-opt--on' : 'q-opt')
                    : 'q-opt q-opt--off'
            };
        });
        const answered = chosen !== undefined && chosen !== null;
        return {
            key: slot.key,
            position: slot.position,
            label: slot.label || slot.key,
            question: slot.question,
            /**
             * The prospect-facing hint. NOT slot.evidencePrompt, which is the
             * interviewer's note about the person reading this and is no longer
             * even serialised to the client -- see GtmAssessmentInstrument.Slot.
             */
            respondentHint: slot.respondentHint,
            positionLabel: `Question ${slot.position} of 8`,
            answered,
            cardCls: this.isInvalid(slot.key) ? 'q-card q-card--bad' : 'q-card',
            options
        };
    }

    // --------------------------------------------------------- complexity

    /**
     * The six complexity dimensions THIS respondent is asked, adapted to the
     * pair the same way the eight readiness slots are.
     *
     * The pack's own list wins whenever one has resolved; the flat
     * getQuestionnaire() list is the fallback for the moment before routing is
     * answered, and for a deployment where the second axis has no pair packs
     * behind it yet. Normalised to one shape here so the template has no idea
     * which of the two it is rendering -- the alternative was a template that
     * knew about both, which is how one of them quietly stops being tested.
     */
    get complexityDimensions() {
        const resolved = (this.pack && this.pack.complexityDimensions) || [];
        if (resolved.length) {
            return resolved.map((d) => ({
                key: d.key,
                label: d.label,
                question: d.question,
                respondentHint: d.respondentHint,
                options: d.options || []
            }));
        }
        return this.complexityQuestions.map((q) => ({
            key: q.dimensionKey,
            label: q.dimensionName,
            question: q.questionText,
            respondentHint: null,
            options: q.options || []
        }));
    }

    get currentComplexity() {
        if (!this.isComplexity) return [];
        const slice = this.complexityDimensions.slice(
            this.step.offset,
            this.step.offset + COMPLEXITY_CHUNK
        );
        return slice.map((q) => ({
            key: q.key,
            label: q.label,
            question: q.question,
            respondentHint: q.respondentHint,
            answered: this.complexity[q.key] !== undefined,
            cardCls: this.isInvalid(q.key) ? 'q-card q-card--bad' : 'q-card',
            options: (q.options || []).map((o) => ({
                key: `${q.key}::${o.value}`,
                value: o.value,
                label: o.label,
                available: true,
                unavailable: false,
                checked: this.complexity[q.key] === o.value,
                cls: this.complexity[q.key] === o.value ? 'q-opt q-opt--on' : 'q-opt'
            }))
        }));
    }

    // -------------------------------------------------------- supplements

    get packSupplements() {
        return (this.pack && this.pack.supplements) || [];
    }

    /**
     * Every supplement, in the order they will be ASKED -- scored and verbatim
     * interleaved rather than grouped.
     *
     * Grouping them is what produced the fault this replaces: three scored
     * questions followed by five consecutive empty textareas, all on one screen.
     * Round-robining the two lists spaces the free text between questions that
     * are one click each, so a run of textareas is at most two long even when
     * the verbatim list is the longer of the two, which it usually is.
     *
     * Order WITHIN each list is untouched: it is the authored sort_order, and a
     * set's questions are written to be read in sequence.
     */
    get orderedSupplements() {
        const scored = this.packSupplements.filter((s) => s.scored);
        const verbatim = this.packSupplements.filter((s) => !s.scored);
        if (!scored.length || !verbatim.length) {
            return [...scored, ...verbatim];
        }
        // Spread the shorter list evenly through the longer one rather than
        // alternating one-for-one. Alternating leaves the whole remainder of the
        // longer list stacked at the end, which for three scored and five
        // free-text questions is three textareas in a row -- most of the fault
        // this is here to fix, just moved to the bottom of the form. Comparing
        // each item's fractional position in its own list interleaves them in
        // proportion, so the free text is spaced however unbalanced the two are.
        // Scored questions are placed at the MIDPOINT of their share and free
        // text at the end of its own, which puts a one-click question first.
        // The section opens by saying these ask whether the destination is ready
        // to receive you; opening it with "what are you hoping for later" read
        // as a different section starting.
        const marked = [
            ...scored.map((item, i) => ({ item, at: (i + 0.5) / scored.length, scoredFirst: 0 })),
            ...verbatim.map((item, i) => ({ item, at: (i + 1) / verbatim.length, scoredFirst: 1 }))
        ];
        marked.sort((a, b) => (a.at - b.at) || (a.scoredFirst - b.scoredFirst));
        return marked.map((m) => m.item);
    }

    /**
     * The supplement screens, as arrays of questions. Chunked so the file's own
     * four-per-screen rule holds -- it did not, before: this step rendered all
     * eight at once.
     */
    supplementPages() {
        return chunkBalanced(this.orderedSupplements, SUPPLEMENT_CHUNK);
    }

    /** The current supplement screen's questions, decorated for rendering. */
    get currentSupplements() {
        if (!this.isSupplements) return [];
        const page = this.supplementPages()[this.step.offset] || [];
        return page.map((s) => ({
            key: s.key,
            question: s.question,
            scored: !!s.scored,
            verbatim: !s.scored,
            value: this.notes[s.key] || '',
            options: (s.options || []).map((o) => ({
                key: `${s.key}::${o.value}`,
                value: o.value,
                label: o.label,
                available: true,
                unavailable: false,
                checked: this.supplements[s.key] === o.value,
                cls: this.supplements[s.key] === o.value ? 'q-opt q-opt--on' : 'q-opt'
            }))
        }));
    }

    /**
     * The "these do not affect your score" preamble belongs at the top of the
     * FIRST supplement screen and nowhere else. Repeating it on each one would
     * be the posture paragraph's mistake in miniature.
     */
    get isFirstSupplementStep() {
        return this.isSupplements && this.step.offset === 0;
    }

    // ----------------------------------------------------------- BD context
    //
    // ADR-0008 section 5. Eleven fields the readout depends on, carried over
    // from gtmConfigBooking when it was retired. Every one is optional, the
    // whole step is skippable in one click, and NOTHING here is ever scored.

    bdContextPages() {
        return chunkBalanced(BD_CONTEXT_FIELDS, BD_CONTEXT_CHUNK);
    }

    /** The current BD-context screen's fields, decorated for rendering. */
    get currentBdContext() {
        if (!this.isBdContext) return [];
        const page = this.bdContextPages()[this.step.offset] || [];
        const value = (f) => this.bdContext[f.key] || '';
        return page.map((f) => ({
            key: f.key,
            question: f.question,
            placeholder: f.placeholder || '',
            value: value(f),
            isSelect: f.kind === 'select',
            isTextarea: f.kind === 'textarea',
            isNumber: f.kind === 'number',
            isText: f.kind === 'text',
            // Same pattern as the routing selects: an option carries its own
            // `selected` flag rather than relying on the select's value
            // binding, because both are rendered in the same pass.
            options: (f.options || []).map((o) => ({
                key: `${f.key}::${o.value}`,
                value: o.value,
                label: o.label,
                selected: value(f) === o.value
            }))
        }));
    }

    /** The "these do not affect your score" note belongs on the first of these
     *  screens and nowhere else -- the supplements step learned the same. */
    get isFirstBdContextStep() {
        return this.isBdContext && this.step.offset === 0;
    }

    handleBdContext(event) {
        const key = event.target.dataset.key;
        if (!key) return;
        this.bdContext = { ...this.bdContext, [key]: event.target.value };
        this.persist();
    }

    /**
     * Past the whole BD-context block in one click.
     *
     * Not "skip this screen": a respondent who does not want to answer these
     * does not want to be asked the same thing again on the next screen. Lands
     * on `contact`, which is the one step after this block.
     */
    handleSkipBdContext() {
        const steps = this.steps;
        const contactAt = steps.findIndex((s) => s.kind === 'contact');
        this.stepIndex = contactAt > -1 ? contactAt : this.stepIndex + 1;
        this.errorMessage = '';
        this.invalidFields = [];
        this.persist();
        this.pushDraft(false);
        this.scrollTop();
    }

    // ------------------------------------------------------------- context

    /**
     * Select options carry their own `selected` flag rather than relying on the
     * select's value binding: the options are rendered in the same pass as the
     * select, and the existing booking form learned the same lesson.
     */
    get sourceOptions() {
        return this.platforms.map((p) => ({
            value: p.key,
            label: p.label,
            selected: p.key === this.routing.source
        }));
    }

    get targetOptions() {
        return [
            ...this.platforms.map((p) => ({ value: p.key, label: p.label })),
            { value: NOT_DECIDED, label: 'Not decided yet' }
        ].map((o) => ({ ...o, selected: o.value === this.routing.target }));
    }

    get timelineChoices() {
        return TIMELINES.map((t) => ({ value: t, selected: t === this.routing.timeline }));
    }

    get sizeChoices() {
        return SIZES.map((t) => ({ value: t, selected: t === this.routing.environmentSize }));
    }

    /**
     * The posture paragraph: ONCE, at the top of the first question section.
     *
     * It used to render at the bottom of all seven screens after routing -- the
     * same ~90 words, verbatim, seven times, ending with "every count below"
     * while sitting at the bottom of a screen with nothing below it.
     *
     * WHY NOT THE ROUTING SCREEN, which is where "before you start" would read
     * most naturally: the pack does not exist yet. loadPack() runs when the
     * routing step is LEFT, deliberately -- see its comment -- so a posture
     * rendered there would resolve to nothing for every respondent, every time.
     * The first readiness section is the earliest point at which there is a
     * posture to state, it is above the questions rather than below them, and it
     * is the screen where the first count is actually asked for.
     *
     * (The authored wording no longer depends on the placement either way: the
     * deixis came out of the statements themselves, because the same sentence is
     * rendered on the readout, where nothing is below it there.)
     */
    get postureStatement() {
        return this.isFirstQuestionStep && this.pack ? this.pack.postureStatement : null;
    }

    /** The first screen on which the pack exists and a question is asked. */
    get isFirstQuestionStep() {
        return this.isReadiness && this.step.group === 0;
    }

    get resolutionNote() {
        return this.isFirstQuestionStep && this.pack ? this.pack.resolutionNote : null;
    }

    /**
     * The running total, for the respondent's own orientation. Advisory: the
     * stored score is computed on the server from the raw answers, and this
     * number never leaves the browser.
     */
    get runningTotal() {
        return this.resolvedSlots.reduce((sum, slot) => {
            const points = pointsFor(slot, this.answers[slot.key]);
            return sum + (points || 0);
        }, 0);
    }

    get answeredCount() {
        return this.resolvedSlots.filter(
            (s) => this.answers[s.key] !== undefined && this.answers[s.key] !== null
        ).length;
    }

    get showRunningTotal() {
        return this.answeredCount > 0 && !this.isRouting;
    }

    get runningTotalLabel() {
        return `${this.answeredCount} of ${this.resolvedSlots.length} answered`;
    }

    /**
     * Whether there is anything to say about saving yet.
     *
     * True from the first thing the respondent touches, including a routing
     * answer -- deliberately earlier than "has answered a scored question".
     * The block it gates carries the sentence "not saved anywhere else yet",
     * and that sentence is most needed at the start, not once someone is eight
     * questions in and already assuming.
     */
    get hasSavedProgress() {
        const r = this.routing;
        return (
            this.answeredCount > 0 ||
            this.stepIndex > 0 ||
            !!(r.source || r.target || r.timeline || r.environmentSize)
        );
    }

    /** True on the routing step, before anything durable exists. The footer
     *  says so plainly there rather than implying a save that has not happened. */
    get nothingSavedYet() {
        return !this.draftToken;
    }

    // -------------------------------------------------------------- events

    handleRouting(event) {
        const field = event.currentTarget.dataset.field;
        this.routing = { ...this.routing, [field]: event.currentTarget.value };
        this.clearInvalid(field);
        this.persist();
    }

    handleContact(event) {
        const field = event.currentTarget.dataset.field;
        this.contact = { ...this.contact, [field]: event.currentTarget.value };
        this.clearInvalid(field);
        this.persist();
    }

    handleNote(event) {
        this.notes = { ...this.notes, [event.currentTarget.dataset.key]: event.currentTarget.value };
        this.persist();
    }

    /**
     * One handler for every scored option, in all three instruments. The bucket
     * comes from the markup rather than from a branch on the key, so adding a
     * question set never adds a case here.
     */
    handleChoice(event) {
        const { key, bucket } = event.currentTarget.dataset;
        const value = parseInt(event.currentTarget.dataset.value, 10);
        if (bucket === 'complexity') {
            this.complexity = { ...this.complexity, [key]: value };
        } else if (bucket === 'supplement') {
            this.supplements = { ...this.supplements, [key]: value };
        } else {
            this.answers = { ...this.answers, [key]: value };
            // An answer can change which question a LATER slot asks. Answers to
            // slots that are no longer asked are dropped here rather than left
            // to be submitted under a key the server will not resolve — see
            // pruneOrphans.
            this.pruneOrphans();
        }
        this.clearInvalid(key);
        this.persist();
    }

    /**
     * Drops answers whose question is no longer being asked.
     *
     * Going back and changing an earlier answer can re-branch a later slot. The
     * old answer would otherwise sit in the payload under a key the server's own
     * branch resolution does not produce — harmless, because the scorer never
     * reads a key it did not ask for, but it would let the respondent see a
     * "answered" tick against a question that is no longer on their form. This
     * keeps what they see and what they submit the same thing.
     */
    pruneOrphans() {
        const asked = new Set(this.resolvedSlots.map((s) => s.key));
        const kept = {};
        Object.keys(this.answers).forEach((k) => {
            if (asked.has(k)) kept[k] = this.answers[k];
        });
        this.answers = kept;
    }

    async handleNext() {
        if (!this.validateStep()) return;
        if (this.isLastStep) {
            await this.submit();
            return;
        }
        if (this.isRouting) {
            this.loading = true;
            await this.loadPack();
            this.pruneOrphans();
            this.loading = false;
        }
        this.stepIndex = Math.min(this.stepIndex + 1, this.steps.length - 1);
        this.persist();
        // The durable save happens on step transitions. Not awaited: the next
        // step renders immediately and the push settles behind it, because a
        // spinner between steps is the thing that loses the respondent.
        this.pushDraft(false);
        this.scrollTop();
    }

    handleBack() {
        this.errorMessage = '';
        this.invalidFields = [];
        this.stepIndex = Math.max(this.stepIndex - 1, 0);
        this.persist();
        this.scrollTop();
    }

    /**
     * Starts over on this device.
     *
     * Deliberately does NOT delete the server draft. This button exists for
     * "I answered the first questions wrong", not for "erase me", and a click
     * that silently killed a link the respondent had already emailed to
     * themselves would be a nasty surprise. The old draft expires on its own
     * schedule; the next step transition mints a new one.
     */
    handleRestart() {
        // `contact` and `bdContext` are deliberately NOT cleared, for the same
        // reason: this button means "I answered the instrument wrong", and it
        // is a nasty surprise if fixing a routing answer also silently deletes
        // your name and four paragraphs of free text about your estate. What is
        // cleared below is exactly what the instrument produced.
        this.clearStorage();
        this.answers = {};
        this.complexity = {};
        this.supplements = {};
        this.notes = {};
        this.routing = { source: '', target: '', timeline: '', environmentSize: '' };
        this.stepIndex = 0;
        this.pack = null;
        this.draftToken = '';
        this.draftExpiresAt = null;
        this.draftError = '';
        this.resumeNotice = '';
        this.restoredFromLink = false;
        this.emailState = '';
        this.emailMessage = '';
        this.linkCopied = false;
    }

    scrollTop() {
        const top = this.template.querySelector('.q-top');
        if (top && top.scrollIntoView) {
            top.scrollIntoView({ block: 'start' });
        }
    }

    // ---------------------------------------------------------- validation

    isInvalid(field) {
        return this.invalidFields.includes(field);
    }

    clearInvalid(field) {
        if (this.invalidFields.includes(field)) {
            this.invalidFields = this.invalidFields.filter((f) => f !== field);
        }
        if (!this.invalidFields.length) {
            this.errorMessage = '';
        }
    }

    get sourceFieldClass() {
        return this.isInvalid('source') ? 'q-field q-field--bad' : 'q-field';
    }
    get nameFieldClass() {
        return this.isInvalid('name') ? 'q-field q-field--bad' : 'q-field';
    }
    get emailFieldClass() {
        return this.isInvalid('email') ? 'q-field q-field--bad' : 'q-field';
    }

    /**
     * Every question on the step must be answered before moving on.
     *
     * Deliberately strict on the eight: a skipped slot is an unscored slot, and
     * an unscored slot makes a total that is not out of 32 while the readout
     * still says it is. Blocking here is the only place that can be prevented
     * without inventing an answer, since the server correctly refuses to invent
     * one either.
     */
    validateStep() {
        const missing = [];
        if (this.isRouting) {
            if (!this.routing.source) missing.push('source');
            if (!this.routing.target) missing.push('target');
        } else if (this.isReadiness) {
            this.currentSlots.forEach((s) => {
                if (!s.answered) missing.push(s.key);
            });
        } else if (this.isComplexity) {
            this.currentComplexity.forEach((q) => {
                if (!q.answered) missing.push(q.key);
            });
        } else if (this.isContact) {
            if (!this.contact.name.trim()) missing.push('name');
            if (!this.isValidEmail(this.contact.email)) missing.push('email');
        }
        this.invalidFields = missing;
        this.errorMessage = missing.length ? this.missingMessage(missing) : '';
        return missing.length === 0;
    }

    missingMessage(missing) {
        if (this.isContact) {
            return 'We need your name and a work email to send the readout to.';
        }
        if (this.isRouting) {
            return 'Tell us what you are moving from and to — the rest of the questions depend on it.';
        }
        return missing.length === 1
            ? 'One question on this step still needs an answer.'
            : `${missing.length} questions on this step still need an answer.`;
    }

    isValidEmail(value) {
        return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(value || '').trim());
    }

    // ------------------------------------------------------------- submit

    /**
     * Raw answers only. There is no score field on the payload and there must
     * never be one: GtmAssessmentRequestController scores server-side from these
     * answers and discards anything a client claims about the result.
     */
    buildPayload() {
        const toList = (map) =>
            Object.keys(map).map((k) => ({ dimension: k, value: map[k] }));
        const noteList = Object.keys(this.notes)
            .filter((k) => String(this.notes[k] || '').trim())
            .map((k) => ({ dimension: k, text: this.notes[k] }));
        return {
            name: this.contact.name.trim(),
            email: this.contact.email.trim(),
            company: this.contact.company,
            role: this.contact.role,
            context: this.contact.context,
            // The eleven BD-context fields, ADR-0008 section 5. Spread as
            // top-level keys because that is what RequestInput declares and
            // recordAssessmentRequest writes -- no Apex change was needed.
            //
            // NOTE THE POSITION. They sit here, beside `context` and `role`,
            // and NOT inside answers / complexityAnswers / supplementAnswers.
            // Those three are the only scoring inputs Apex trusts; a BD field
            // that leaked into one of them would be scored as if it were an
            // instrument dimension. There is a test asserting they never do.
            ...this.bdContext,
            currentPlatform: this.labelFor(this.routing.source),
            targetPlatform:
                this.routing.target === NOT_DECIDED ? '' : this.labelFor(this.routing.target),
            timeline: this.routing.timeline,
            environmentSize: this.routing.environmentSize,
            answers: toList(this.answers),
            complexityAnswers: toList(this.complexity),
            supplementAnswers: [...toList(this.supplements), ...noteList],
            prospect: this.prospect,
            industry: this.industryLabel,
            savedRecordId: this.savedRecordId,
            submissionToken: this.submissionToken || '',
            // Carried so the submit transaction can close the draft and revoke
            // its token in the same transaction as the request it became. Not a
            // source of answers -- the answers above are the ones that score.
            draftToken: this.draftToken || ''
        };
    }

    labelFor(key) {
        const found = this.platforms.find((p) => p.key === key);
        return found ? found.label : key;
    }

    async submit() {
        if (this.submitting) return;
        this.submitting = true;
        this.errorMessage = '';
        try {
            const result = await submitRequest({ input: this.buildPayload() });
            // Both copies go at once: the local one because the form is done,
            // the token because GtmAssessmentRequestController has just revoked
            // it server-side and a client still holding it would render a link
            // that no longer works.
            this.clearStorage();
            this.draftToken = '';
            this.draftExpiresAt = null;
            this.submitted = true;
            this.dispatchEvent(
                new CustomEvent('submitted', {
                    detail: {
                        email: this.contact.email.trim(),
                        assessmentRequestId: result ? result.assessmentRequestId : null,
                        // gtmConfigBooking's submitted event carried this and
                        // gtmConfigurator.handleBookingSubmitted uses it to call
                        // identifySession -- which attributes the whole
                        // anonymous reading trail that led here to the person
                        // who left it. Omitting it would have made the D11 swap
                        // silently lose session identification. RequestResult
                        // has always returned it; nothing else was needed.
                        contactId: result ? result.contactId : null
                    }
                })
            );
        } catch (error) {
            this.errorMessage = this.readError(error);
            // ADR-0008 section 5.2. A submit can lose a race against a
            // submission that already landed for this link -- another tab,
            // another device -- and the server refuses it. The host has to be
            // told, because the honest state of the page afterwards is
            // "submitted" (the request exists), not "failed".
            //
            // Deliberately NOT detected by matching the server's message text:
            // the host re-asks the server whether this link now has an
            // assessment, which is authoritative, survives any rewording of
            // that message, and correctly does nothing on an ordinary network
            // failure. See gtmConfigurator.handleBookingFailed.
            this.dispatchEvent(
                new CustomEvent('submitfailed', {
                    detail: { message: this.errorMessage }
                })
            );
        } finally {
            this.submitting = false;
        }
    }

    readError(error) {
        const body = error && error.body;
        if (body && body.message) return body.message;
        if (Array.isArray(body) && body.length && body[0].message) return body[0].message;
        return 'We could not send that just now. Please try again in a moment.';
    }

    /** Whether the engagement link carried a ?book= calendar URL. */
    get hasBookingUrl() {
        return !!(this.bookingUrl || '').trim();
    }

    get confirmMessage() {
        const email = this.contact.email.trim();
        return `Thanks — that is with our team. We will follow up at ${email} with your readout.`;
    }

    // ----------------------------------------------------------- persistence
    //
    // TWO LAYERS, AND THEY DO DIFFERENT JOBS.
    //
    // localStorage is the FAST PATH. It is written on every change, needs no
    // round trip, and covers the cases that happen constantly: a refresh, a
    // browser restart, a tab closed by accident, a phone call mid-form. It
    // restores the STEP as well as the answers, which is the difference between
    // "your answers are still here" and "start again and re-enter them".
    //
    // The server draft is the DURABLE PATH. It is what makes a form resumable
    // on another device, from a link, after the browser's storage is gone. It
    // is pushed on step transitions rather than on every keystroke, because a
    // write per character is a write per character.
    //
    // WHEN THE DURABLE ONE STARTS. On leaving the routing step -- the first
    // point at which anything has been said that is worth carrying. That is
    // deliberately BEFORE any email address exists, because the address is
    // asked for on the last step and a resume mechanism that only switches on
    // at the end is a resume mechanism for people who no longer need one. So
    // the link is minted automatically and shown as something to copy; emailing
    // it is offered on top, optional, and asks for an address for that single
    // purpose only (GtmAssessmentDraftController never stores it).
    //
    // WHAT THE RESPONDENT IS TOLD. On the routing step, before a draft exists,
    // the footer says nothing is saved yet and when saving starts. From then on
    // it says where the answers are and what the link does. Someone who assumes
    // they are saved and is not will lose fifteen minutes and not come back, so
    // the wording never runs ahead of the facts.

    get storageKey() {
        return `${STORAGE_PREFIX}:${this.savedRecordId || 'direct'}`;
    }

    /** Everything worth carrying, in one object. The shape the draft stores. */
    snapshot() {
        return {
            v: STORAGE_VERSION,
            routing: this.routing,
            answers: this.answers,
            complexity: this.complexity,
            supplements: this.supplements,
            notes: this.notes,
            contact: this.contact,
            bdContext: this.bdContext,
            stepIndex: this.stepIndex,
            savedAt: new Date().toISOString()
        };
    }

    applySnapshot(saved) {
        if (!saved || typeof saved !== 'object') {
            return;
        }
        this.routing     = { ...this.routing, ...(saved.routing || {}) };
        this.answers     = saved.answers || {};
        this.complexity  = saved.complexity || {};
        this.supplements = saved.supplements || {};
        this.notes       = saved.notes || {};
        this.contact     = { ...this.contact, ...(saved.contact || {}) };
        // Merged onto the empty shape rather than assigned, so a draft written
        // before this step existed (or by an older client) restores as blanks
        // rather than as undefined -- undefined would reach buildPayload and be
        // sent as null over a field the respondent may since have filled in.
        this.bdContext   = { ...emptyBdContext(), ...(saved.bdContext || {}) };
        // Position matters as much as the answers. Clamped rather than trusted:
        // a stored index from a longer instrument must not land past the end.
        const wanted = Number(saved.stepIndex);
        this.stepIndex = Number.isFinite(wanted) && wanted > 0 ? Math.floor(wanted) : 0;
    }

    persist() {
        try {
            window.localStorage.setItem(this.storageKey, JSON.stringify(this.snapshot()));
        } catch (e) {
            // Private browsing, blocked storage, quota. Progress simply is not
            // kept on this device; nothing about the form stops working, and
            // the server draft is unaffected.
        }
    }

    restore() {
        try {
            const raw = window.localStorage.getItem(this.storageKey);
            if (!raw) {
                return;
            }
            const saved = JSON.parse(raw);
            // A blob written by an older shape is discarded rather than
            // half-applied: a partially-restored form is worse than an empty
            // one, because it looks finished.
            if (!saved || saved.v !== STORAGE_VERSION) {
                this.clearStorage();
                return;
            }
            this.applySnapshot(saved);
            if (saved.draftToken) {
                this.draftToken = saved.draftToken;
            }
        } catch (e) {
            this.clearStorage();
        }
    }

    clearStorage() {
        try {
            window.localStorage.removeItem(this.storageKey);
        } catch (e) {
            // nothing to clear
        }
    }

    /**
     * Pushes the current state to the server draft, minting one if there is not
     * one yet.
     *
     * NEVER BLOCKS AND NEVER THROWS OUTWARDS. A failed push costs the
     * cross-device link for now; it does not cost the answers, which are
     * already in localStorage, and it must not stop someone finishing the form.
     * The message a failure produces is the server's single generic one -- the
     * client cannot tell an expired token from a submitted one from a network
     * blip, by design -- so the recovery offered is the one that works for all
     * of them: start a fresh link.
     */
    async pushDraft(force) {
        if (this.submitted || this.savingDraft) {
            return;
        }
        // Nothing worth a durable record until the routing step is behind us.
        if (!force && !this.draftToken && this.stepIndex === 0) {
            return;
        }
        this.savingDraft = true;
        try {
            const handle = await saveDraft({
                resumeToken: this.draftToken || '',
                payload: JSON.stringify(this.snapshot()),
                pairKey: (this.pack && this.pack.pairKey) || ''
            });
            if (handle && handle.resumeToken) {
                this.draftToken = handle.resumeToken;
                this.draftExpiresAt = handle.expiresAt;
            }
            this.draftError = '';
            this.persist();
        } catch (e) {
            this.draftError =
                'We could not save your place just now. Your answers are still here in this ' +
                'browser — you can carry on, and try saving again in a moment.';
        } finally {
            this.savingDraft = false;
        }
    }

    /** Abandons a token that has stopped working and mints a fresh draft. */
    async handleNewLink() {
        this.draftToken = '';
        this.draftError = '';
        this.emailState = '';
        this.emailMessage = '';
        this.linkCopied = false;
        await this.pushDraft(true);
    }

    handleSaveMyPlace() {
        this.linkCopied = false;
        return this.pushDraft(true);
    }

    // ------------------------------------------------------ the resume link

    get hasDraft() {
        return !!this.draftToken;
    }

    /**
     * The copyable link. Built in the browser from the page it is on, for
     * display only -- the emailed one is built server-side from configuration,
     * because a link in an email whose host came from the browser is an open
     * redirect with our name on the envelope.
     */
    get resumeUrl() {
        if (!this.draftToken) {
            return '';
        }
        try {
            const { origin, pathname } = window.location;
            return `${origin}${pathname}?resume=${this.draftToken}`;
        } catch (e) {
            return '';
        }
    }

    get expiryLabel() {
        if (!this.draftExpiresAt) {
            return '';
        }
        try {
            return new Date(this.draftExpiresAt).toLocaleDateString(undefined, {
                day: 'numeric',
                month: 'long',
                year: 'numeric'
            });
        } catch (e) {
            return '';
        }
    }

    get saveButtonLabel() {
        return this.savingDraft ? 'Saving…' : 'Save my place';
    }

    get copyLabel() {
        return this.linkCopied ? 'Copied' : 'Copy link';
    }

    get emailButtonLabel() {
        return this.emailState === 'sending' ? 'Sending…' : 'Email me this link';
    }

    get emailBusy() {
        return this.emailState === 'sending';
    }

    get showEmailMessage() {
        return !!this.emailMessage;
    }

    handleResumeEmail(event) {
        this.resumeEmail = event.currentTarget.value;
        this.emailMessage = '';
        this.emailState = '';
    }

    async handleCopyLink() {
        const url = this.resumeUrl;
        if (!url) {
            return;
        }
        try {
            await window.navigator.clipboard.writeText(url);
            this.linkCopied = true;
        } catch (e) {
            // No clipboard permission. The link is rendered in a selectable
            // field beside the button, so there is always a way to get it.
            this.linkCopied = false;
        }
    }

    /**
     * Asks the server to email the resume link.
     *
     * The address goes to Apex and nowhere else: it is not written to the
     * draft, not added to `contact`, and not used for anything but addressing
     * one message. Someone who wants their place saved has not thereby agreed
     * to be contacted, and the copy on screen says so.
     */
    async handleEmailLink() {
        if (!this.draftToken || this.emailState === 'sending') {
            return;
        }
        if (!this.isValidEmail(this.resumeEmail)) {
            this.emailState = 'failed';
            this.emailMessage = 'That does not look like an email address.';
            return;
        }
        this.emailState = 'sending';
        this.emailMessage = '';
        try {
            const result = await emailResumeLink({
                resumeToken: this.draftToken,
                emailAddress: this.resumeEmail.trim()
            });
            if (result && result.sent) {
                this.emailState = 'sent';
                this.emailMessage = result.message;
                this.resumeEmail = '';
            } else {
                this.emailState = 'failed';
                this.emailMessage = (result && result.message)
                    || 'We could not send that just now.';
            }
        } catch (e) {
            this.emailState = 'failed';
            this.emailMessage = 'We could not send that just now.';
        }
    }
}
