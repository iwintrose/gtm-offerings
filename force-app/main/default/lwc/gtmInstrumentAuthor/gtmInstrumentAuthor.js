/**
 * The content author's instrument editor: questions, per-option scores, and
 * answer-driven branches — with a preview that walks the branches.
 *
 * WHERE THIS LIVES AND WHY. The content-author surface (the gtmContentManager
 * app), not the BD/rep surface. A rep works a deal in gtmReadoutReview and must
 * not be able to retune the instrument the deal was scored on; a content person
 * owns the offering and the framework and must. Blurring the two would let the
 * person with the most incentive to move a number be the person who can.
 *
 * THREE THINGS THE AUTHORING SURFACE DID NOT HAVE:
 *
 *   1. PER-OPTION POINTS. Points used to be implicit in position — option 1 was
 *      worth 1, option 4 worth 4. Now they are set here and stored beside the
 *      label. What an author may do with them is make a scale NON-LINEAR
 *      ("these two answers are equally bad"); what they may not do is change
 *      what the slot is worth, because the four bands were calibrated against a
 *      32-point maximum. The editor computes the slot's top and bottom live and
 *      says so before the author ever reaches the build script.
 *
 *   2. BRANCHES (show_when). A predicate per question, in the SAME language as
 *      GTM_Assessment_Gate__mdt.Predicate_JSON__c, because a second predicate
 *      dialect is a second thing to get wrong. A branch chooses WHICH question
 *      fills a slot; it can never leave the slot empty, and the editor shows the
 *      default question that catches everything the branches do not.
 *
 *   3. THE PREVIEW. Pick a source and a target, answer as a respondent would,
 *      and see exactly what they would be asked and what they would score.
 *      Without it nobody can tell whether an edit broke a path — a branch that
 *      never fires looks identical to a branch that is simply not needed yet.
 *
 * WHAT IT DOES NOT DO, DELIBERATELY. It does not write to custom metadata.
 * The YAML under instrument/ is the source of truth and
 * the custom metadata is a build output (scripts/build-instrument.py); a second
 * write path into the compiled records would mean two authorities for the same
 * question and no way to review either. So the editor emits the YAML fragment
 * for the change and the author commits it, which is also what puts every edit
 * through the eleven build-time rules before it can reach anyone.
 */
import { LightningElement, track, api } from 'lwc';
import getPlatforms from '@salesforce/apex/GtmAssessmentInstrument.getPlatforms';
import getPack from '@salesforce/apex/GtmAssessmentInstrument.getPack';
import getFrame from '@salesforce/apex/GtmAssessmentInstrument.getFrame';
import getOfferings from '@salesforce/apex/GtmPageContentController.getOfferings';
import { resolveSlots, pointsFor, parse } from 'c/gtmPredicate';

const VIEW_EDIT = 'edit';
const VIEW_PREVIEW = 'preview';
const ORIENTATION_KEY = 'gtmInstrumentAuthor.orientationCollapsed';

/**
 * The framework pseudo-offering (GtmPageContentController.FRAMEWORK_KEY). It
 * owns cross-offering page content, not an instrument, so it is filtered out of
 * this screen's picker -- there is nothing here for it to be.
 */
const FRAMEWORK_KEY = 'gtm';

export default class GtmInstrumentAuthor extends LightningElement {
    /**
     * A pinned starting offering, when this component is placed with one. No
     * longer the dead default it used to be: connectedCallback now loads the
     * real offering list and selectedOffering is what every Apex call is keyed
     * on, so this is a preset rather than the answer.
     */
    @api offeringKey = '';

    @track offerings = [];
    @track selectedOffering = '';
    @track platforms = [];
    @track frame = null;
    @track pack = null;
    @track sourceKey = '';
    @track targetKey = '';
    @track selectedBaseKey = '';
    @track view = VIEW_EDIT;
    @track loading = true;
    @track error = '';
    @track orientationCollapsed = false;

    /** Unsaved edits, keyed `${baseKey}::${variantKey}`. The pack is never mutated. */
    @track edits = {};
    /** Preview answers: resolved slot key -> option value. */
    @track previewAnswers = {};

    async connectedCallback() {
        try {
            this.orientationCollapsed = window.localStorage.getItem(ORIENTATION_KEY) === '1';
        } catch (e) {
            // Private browsing / storage blocked — default to shown.
        }
        try {
            const rows = await getOfferings();
            // The framework entry owns page content, not an instrument.
            this.offerings = (rows || []).filter((o) => o.offeringKey !== FRAMEWORK_KEY);
            // Same preset rule gtmContentManager uses: a pinned property first,
            // then the only offering when there is exactly one.
            this.selectedOffering = this.offeringKey
                || (this.offerings.length === 1 ? this.offerings[0].offeringKey : '');
        } catch (e) {
            this.offerings = [];
            this.error = 'Offerings could not be loaded.';
        }
        try {
            this.platforms = (await getPlatforms()) || [];
        } catch (e) {
            this.platforms = [];
        }
        await this.loadOffering();
        this.loading = false;
    }

    /**
     * Everything that is a property of the CHOSEN OFFERING: its frame, and the
     * pack for whichever pair is selected. Re-run whenever the offering
     * changes, because after ADR-0007 neither of them is global any more --
     * showing offering A's frame beside offering B's pack would be exactly the
     * cross-offering blend this screen now exists to make impossible.
     */
    async loadOffering() {
        if (!this.hasOffering) {
            this.frame = null;
            this.pack = null;
            return;
        }
        try {
            this.frame = await getFrame({ offeringKey: this.selectedOffering });
        } catch (e) {
            this.frame = null;
            this.error = 'Could not read the instrument configuration.';
        }
        await this.load();
    }

    get offeringOptions() {
        return this.offerings.map((o) => ({ label: o.label, value: o.offeringKey }));
    }

    get hasOffering() { return !!this.selectedOffering; }

    get showOfferingPicker() { return this.offerings.length > 1; }

    async handleOfferingChange(event) {
        const next = event.detail.value;
        if (next === this.selectedOffering) return;
        this.selectedOffering = next;
        // A slot key is only meaningful inside one offering's frame, and the
        // edit buffer is keyed by slot key -- carrying either across a switch
        // would silently apply offering A's edits to offering B's questions.
        this.selectedBaseKey = '';
        this.edits = {};
        this.previewAnswers = {};
        this.error = '';
        this.loading = true;
        await this.loadOffering();
        this.loading = false;
    }

    handleToggleOrientation() {
        this.orientationCollapsed = !this.orientationCollapsed;
        try {
            window.localStorage.setItem(ORIENTATION_KEY, this.orientationCollapsed ? '1' : '0');
        } catch (e) {
            // Non-persistent this session; not worth failing over.
        }
    }

    get offeringLabel() {
        const hit = this.offerings.find((o) => o.offeringKey === this.selectedOffering);
        return hit ? hit.label : this.selectedOffering;
    }

    get pairSummaryLabel() {
        if (!this.pack) return '';
        const src = this.sourceKey ? this.labelForKey(this.sourceKey) : 'Any source';
        const tgt = this.targetKey ? this.labelForKey(this.targetKey) : 'Any target';
        return `${src} → ${tgt}`;
    }

    labelForKey(key) {
        const hit = this.platforms.find((p) => p.key === key);
        return hit ? hit.label : key;
    }

    /**
     * The reachability caveat is GONE, and that is the point.
     *
     * It used to tell an author: "the live GTM1 site's booking form does not
     * yet ask these questions, so editing a pack here does not change what a
     * real prospect sees today." Its own comment said to delete it "the day
     * gtmConfigBooking is rewired onto the real questionnaire". That is this
     * change (ADR-0008 / backlog D11): the live /configurator route now hosts
     * the real questionnaire, so a pack edited here DOES change what a real
     * prospect is asked. Leaving the banner up would now be actively
     * misleading -- it would tell an author their work does not matter when it
     * does.
     *
     * If a future change ever puts the authoring screen and the live guest
     * surface out of step again, this is where that warning goes back.
     */

    get resolutionChainLabel() {
        const chain = this.pack && this.pack.resolutionChain;
        return chain && chain.length ? chain.join(' → ') : '';
    }

    async load() {
        if (!this.hasOffering) {
            this.pack = null;
            return;
        }
        try {
            this.pack = await getPack({
                offeringKey: this.selectedOffering,
                sourceName: this.sourceKey,
                targetName: this.targetKey
            });
            if (!this.selectedBaseKey && this.pack && this.pack.slots.length) {
                this.selectedBaseKey = this.pack.slots[0].baseKey;
            }
            this.previewAnswers = {};
        } catch (e) {
            this.pack = null;
            this.error = 'Could not resolve a pack for that pair.';
        }
    }

    // --------------------------------------------------------------- pickers

    get sourceOptions() {
        return this.platforms.map((p) => ({
            value: p.key,
            label: p.label,
            selected: p.key === this.sourceKey
        }));
    }

    get targetOptions() {
        return this.platforms.map((p) => ({
            value: p.key,
            label: p.label,
            selected: p.key === this.targetKey
        }));
    }

    async handlePair(event) {
        const field = event.currentTarget.dataset.field;
        this[field] = event.currentTarget.value;
        this.loading = true;
        await this.load();
        this.loading = false;
    }

    handleSelectSlot(event) {
        this.selectedBaseKey = event.currentTarget.dataset.key;
    }

    handleEdit()    { this.view = VIEW_EDIT; }
    handlePreview() { this.view = VIEW_PREVIEW; }

    get isEdit()    { return this.view === VIEW_EDIT; }
    get isPreview() { return this.view === VIEW_PREVIEW; }
    get editTabClass()    { return this.isEdit ? 'ia-tab ia-tab--on' : 'ia-tab'; }
    get previewTabClass() { return this.isPreview ? 'ia-tab ia-tab--on' : 'ia-tab'; }

    // ------------------------------------------------------------ slot rail

    get slots() {
        return (this.pack && this.pack.slots) || [];
    }

    get rail() {
        return this.slots.map((s) => {
            const variants = s.variants || [];
            return {
                baseKey: s.baseKey,
                position: s.position,
                label: s.label || s.baseKey,
                branchCount: variants.length,
                branchNote: variants.length
                    ? `${variants.length} branch${variants.length === 1 ? '' : 'es'}`
                    : 'no branches',
                pinned: s.substitutable === false,
                cls: s.baseKey === this.selectedBaseKey ? 'ia-slot ia-slot--on' : 'ia-slot'
            };
        });
    }

    get selectedSlot() {
        return this.slots.find((s) => s.baseKey === this.selectedBaseKey) || null;
    }

    /**
     * The selected slot's questions: the default first, then each branch
     * variant in evaluation order. Rendering them in one list, with the default
     * labelled as the one that always applies, is what makes the invariant
     * legible to the person editing it: whatever the branches do, that first
     * entry is still there to fill the slot.
     */
    get questionCards() {
        const slot = this.selectedSlot;
        if (!slot) return [];
        const cards = [this.card(slot, slot, true)];
        (slot.variants || []).forEach((v) => cards.push(this.card(slot, v, false)));
        return cards;
    }

    card(slot, source, isDefault) {
        const id = `${slot.baseKey}::${isDefault ? 'default' : source.variantKey}`;
        const edit = this.edits[id] || {};
        const options = (source.options || []).map((o, i) => {
            const points = this.pointsOf(id, i, o);
            return {
                index: i,
                key: `${id}::${o.value}`,
                value: o.value,
                label: o.label,
                points,
                available: o.available !== false,
                unavailable: o.available === false,
                unavailableReason: o.unavailableReason,
                cls: o.available === false ? 'ia-opt ia-opt--off' : 'ia-opt'
            };
        });
        const points = options.map((o) => Number(o.points));
        const bottom = points.length ? Math.min(...points) : null;
        const top = points.length ? Math.max(...points) : null;
        const descends = points.some((p, i) => i > 0 && p < points[i - 1]);
        const showWhen = edit.showWhen !== undefined ? edit.showWhen : source.showWhenJson || '';
        return {
            id,
            isDefault,
            variantKey: isDefault ? 'default' : source.variantKey,
            heading: isDefault ? 'Default — always applies' : `Branch: ${source.variantKey}`,
            headingCls: isDefault ? 'ia-card-head ia-card-head--default' : 'ia-card-head',
            resolvedKey: source.key,
            question: source.question,
            options,
            showWhen,
            showWhenValid: !showWhen || parse(showWhen) !== null,
            showWhenError:
                showWhen && parse(showWhen) === null
                    ? 'Not valid JSON — this branch would be inert, which looks exactly like a branch that is not needed yet.'
                    : '',
            bottom,
            top,
            pointsOk: bottom === 1 && top === this.maxAnswerValue && !descends,
            pointsWarning: this.pointsWarning(bottom, top, descends)
        };
    }

    pointsWarning(bottom, top, descends) {
        const max = this.maxAnswerValue;
        if (bottom === 1 && top === max && !descends) return '';
        if (descends) {
            return 'These points descend. Options render in ascending order and a respondent reads them as a scale.';
        }
        return `This question is worth ${bottom}–${top}. Every slot must be worth 1–${max}, or the pair is scored out of something other than ${this.maxTotal} and the four bands stop meaning what they say. The build script will refuse it.`;
    }

    pointsOf(id, index, option) {
        const edit = this.edits[id];
        if (edit && edit.points && edit.points[index] !== undefined) {
            return edit.points[index];
        }
        return option.points === null || option.points === undefined
            ? option.value
            : option.points;
    }

    get maxAnswerValue() {
        return this.frame ? this.frame.maxAnswerValue : 4;
    }
    get maxTotal() {
        return this.frame ? this.frame.maxTotal : 32;
    }

    handlePoints(event) {
        const { id, index } = event.currentTarget.dataset;
        const value = parseInt(event.currentTarget.value, 10);
        const current = this.edits[id] || { points: {} };
        const points = { ...(current.points || {}), [index]: Number.isNaN(value) ? '' : value };
        this.edits = { ...this.edits, [id]: { ...current, points } };
    }

    handleShowWhen(event) {
        const { id } = event.currentTarget.dataset;
        const current = this.edits[id] || {};
        this.edits = {
            ...this.edits,
            [id]: { ...current, showWhen: event.currentTarget.value }
        };
    }

    // ---------------------------------------------------------- the preview

    /**
     * The questionnaire the author is editing, walked exactly as a respondent
     * would walk it — same module, same predicates, same order.
     *
     * Using c/gtmPredicate rather than a preview-only implementation is the
     * point: a preview that agrees with itself and disagrees with the form is
     * worse than no preview, because it is believed.
     */
    get previewSlots() {
        const slots = resolveSlots(this.pack, this.previewAnswers);
        return slots.map((slot) => {
            const chosen = this.previewAnswers[slot.key];
            return {
                key: slot.key,
                position: slot.position,
                label: slot.label || slot.key,
                question: slot.question,
                variantKey: slot.variantKey,
                branched: slot.variantKey && slot.variantKey !== 'default',
                branchNote:
                    slot.variantKey && slot.variantKey !== 'default'
                        ? `Branched to ${slot.variantKey}`
                        : '',
                options: (slot.options || []).map((o) => ({
                    key: `${slot.key}::${o.value}`,
                    value: o.value,
                    label: o.label,
                    points: o.points === null || o.points === undefined ? o.value : o.points,
                    unavailable: o.available === false,
                    unavailableReason: o.unavailableReason,
                    cls:
                        o.available === false
                            ? 'ia-popt ia-popt--off'
                            : chosen === o.value
                            ? 'ia-popt ia-popt--on'
                            : 'ia-popt'
                }))
            };
        });
    }

    handlePreviewChoice(event) {
        const key = event.currentTarget.dataset.key;
        const value = parseInt(event.currentTarget.dataset.value, 10);
        const next = { ...this.previewAnswers, [key]: value };
        // Re-branching can strand an answer to a question that is no longer
        // asked. Dropping it here keeps the preview honest about what the
        // respondent's payload would actually contain.
        const asked = new Set(resolveSlots(this.pack, next).map((s) => s.key));
        const kept = {};
        Object.keys(next).forEach((k) => {
            if (asked.has(k)) kept[k] = next[k];
        });
        this.previewAnswers = kept;
    }

    handleClearPreview() {
        this.previewAnswers = {};
    }

    get previewTotal() {
        return resolveSlots(this.pack, this.previewAnswers).reduce((sum, slot) => {
            const p = pointsFor(slot, this.previewAnswers[slot.key]);
            return sum + (p || 0);
        }, 0);
    }

    get previewAnswered() {
        const slots = resolveSlots(this.pack, this.previewAnswers);
        return slots.filter((s) => this.previewAnswers[s.key] !== undefined).length;
    }

    get previewComplete() {
        return this.previewAnswered === this.slots.length && this.slots.length > 0;
    }

    /**
     * The band, read from the server's own edges. Only shown once every slot is
     * answered: a partial total lands in a band it would never land in when
     * finished, and an author who sees "Discovery First" halfway through will
     * reasonably believe they have broken something.
     */
    get previewBand() {
        if (!this.previewComplete || !this.frame) return '';
        const total = this.previewTotal;
        const band = this.frame.bands.find((b) => total >= b.lowest && total <= b.highest);
        return band ? band.tier : '';
    }

    get previewScoreLine() {
        return `${this.previewTotal} of ${this.maxTotal}`;
    }

    get previewProgress() {
        return `${this.previewAnswered} of ${this.slots.length} answered`;
    }

    /**
     * The branch path this set of answers took — the same map the server stores
     * on Instrument_Branch_Path__c. Shown because "which question did they
     * actually get" is the thing an author is checking, and a total alone cannot
     * answer it.
     */
    get previewPath() {
        return resolveSlots(this.pack, this.previewAnswers).map((s) => ({
            key: s.baseKey,
            variant: s.variantKey || 'default',
            asked: s.key,
            branched: (s.variantKey || 'default') !== 'default'
        }));
    }

    // --------------------------------------------------------- yaml output

    /**
     * The edits, as the YAML that would go into the pair file.
     *
     * This is the save button. The instrument's source of truth is
     * instrument/migration-accelerator/pairs/*.yaml, compiled to custom metadata
     * by scripts/build-instrument.py — so the way an edit becomes real is by
     * being committed and built, which is also the only way it passes the eleven
     * rules that stop a broken branch reaching a client.
     */
    get yamlFragment() {
        const ids = Object.keys(this.edits);
        if (!ids.length) {
            return '';
        }
        const lines = [
            '# Paste into the `overrides:` list of',
            `# instrument/<offering-key>/pairs/<pair>.yaml, then run`,
            '#   python3 scripts/build-instrument.py',
            ''
        ];
        ids.forEach((id) => {
            const [baseKey, variantKey] = id.split('::');
            const card = this.questionCards.find((c) => c.id === id);
            if (!card) return;
            lines.push(`  - dimension: ${baseKey}`);
            if (variantKey !== 'default') {
                lines.push(`    variant_key: ${variantKey}`);
            }
            if (card.showWhen) {
                lines.push('    show_when:');
                String(card.showWhen)
                    .split('\n')
                    .forEach((l) => lines.push(`      ${l}`));
            }
            lines.push('    options:');
            card.options.forEach((o) => {
                lines.push(`      - value: ${o.value}`);
                lines.push(`        label: ${JSON.stringify(o.label || '')}`);
                lines.push(`        points: ${o.points}`);
            });
            lines.push('');
        });
        return lines.join('\n');
    }

    get hasEdits() {
        return Object.keys(this.edits).length > 0;
    }

    handleDiscard() {
        this.edits = {};
    }
}
