/**
 * The content author's instrument editor, rebuilt against the
 * `assessment-instrument-rebuild` schema (`GTM_Instrument_Definition__c` /
 * `GTM_Instrument_Question_Definition__c` / `GTM_Instrument_Outcome_Range__c`,
 * docs/architecture/gtm-instrument-schema.md). Supersedes this component's
 * prior YAML/CMDT-pack-editing incarnation (docs/architecture/
 * gtm-instrument-editor.md) for every offering that opts into the new
 * schema — per that doc's §0, no new work targets the old
 * `GTM_Instrument__c`/`GtmInstrumentController` path.
 *
 * WHY "LOGIC JUMP" LIVES ON THE OPTION, NOT A SEPARATE RULE LIST. Per the
 * Typeform-pattern research behind this rebuild: a branch is a property of
 * the answer that causes it ("if they pick THIS, go THERE"), not a fact
 * filed away from the option it depends on. Authoring it inline means an
 * author editing an option sees its consequence in the same glance, instead
 * of cross-referencing a rules table by question key. Each option's Logic
 * Jump compiles to one entry in this question's `Rules_JSON__c`
 * (`{ logic: 'AND', conditions: [{ field: questionKey, operator: 'EQUALS',
 * value: optionValue }], action, target }`, the shape `c/gtmRuleEngine`
 * already evaluates, doc §3.2) — any other rule shape found in
 * `Rules_JSON__c` that this UI didn't author (none exist yet on a schema
 * this new, but the save path is defensive) is preserved untouched in
 * `_otherRules` and re-emitted alongside the authored ones, never dropped.
 *
 * WHAT THIS EDITOR DOES NOT AUTHOR, DELIBERATELY (owner-resolved descope,
 * docs/architecture/gtm-instrument-rule-engine-cutover-plan.md §4): no UI
 * for per-pair adaptive overrides, gate predicates, an Estate Complexity
 * second scored axis, or layer-4 supplements. Those stay legacy-YAML-only.
 */
import { LightningElement, track, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getOfferings from '@salesforce/apex/GtmPageContentController.getOfferings';
import getDefinitionForOffering from '@salesforce/apex/GtmInstrumentDefinitionController.getDefinitionForOffering';
import createDefinition from '@salesforce/apex/GtmInstrumentDefinitionController.createDefinition';
import saveDefinition from '@salesforce/apex/GtmInstrumentDefinitionController.saveDefinition';
import saveQuestions from '@salesforce/apex/GtmInstrumentDefinitionController.saveQuestions';
import deleteQuestions from '@salesforce/apex/GtmInstrumentDefinitionController.deleteQuestions';
import saveOutcomeRanges from '@salesforce/apex/GtmInstrumentDefinitionController.saveOutcomeRanges';
import deleteOutcomeRanges from '@salesforce/apex/GtmInstrumentDefinitionController.deleteOutcomeRanges';
import publishDefinition from '@salesforce/apex/GtmInstrumentDefinitionController.publishDefinition';
import archiveDefinition from '@salesforce/apex/GtmInstrumentDefinitionController.archiveDefinition';
import { evaluateRules, detectCircularDependencies } from 'c/gtmRuleEngine';

const VIEW_QUESTIONS = 'questions';
const VIEW_OUTCOMES = 'outcomes';
const VIEW_PREVIEW = 'preview';

const QUESTION_TYPES = [
    { label: 'Single select', value: 'Single_Select' },
    { label: 'Multi select', value: 'Multi_Select' },
    { label: 'Dropdown', value: 'Dropdown' },
    { label: 'Numeric scale', value: 'Numeric_Scale' },
    { label: 'Matrix grid', value: 'Matrix_Grid' },
    { label: 'Short text', value: 'Short_Text' },
    { label: 'Long text', value: 'Long_Text' }
];

const JUMP_ACTIONS = [
    { label: 'No jump — continue in order', value: '' },
    { label: 'Show a later question', value: 'SHOW' },
    { label: 'Skip directly to…', value: 'SKIP_TO_SECTION' }
];

/** Framework pseudo-offering (GtmPageContentController.FRAMEWORK_KEY): owns cross-offering page content, not an instrument. */
const FRAMEWORK_KEY = 'gtm';

let nextLocalId = 1;
function localId() {
    return `local-${nextLocalId++}`;
}

function hasOptions(questionType) {
    return questionType === 'Single_Select' || questionType === 'Multi_Select' || questionType === 'Dropdown';
}

export default class GtmInstrumentAuthor extends LightningElement {
    /** A pinned starting offering, when this component is placed with one (App Page target). */
    @api offeringKey = '';

    @track offerings = [];
    @track selectedOffering = '';
    @track view = VIEW_QUESTIONS;
    @track loading = true;
    @track error = '';
    @track message = '';

    @track definitionId = null;
    @track definitionName = '';
    @track definitionStatus = '';
    @track definitionVersion = null;
    @track definitionThemeKey = '';
    @track hasDefinition = false;

    @track questions = [];
    @track outcomeRanges = [];
    @track deletedQuestionIds = [];
    @track deletedRangeIds = [];

    @track previewAnswers = {};

    _requestedOffering = '';

    /**
     * Reads `c__offering` off the tab's navigation state — the same
     * `standard__navItemPage` state key `gtmContentManager` reads, set by
     * `gtmOverview.js`'s `openEditor()`-pattern "Assessment" action so the
     * editor lands pre-scoped to the offering the rep/content manager
     * clicked from.
     */
    @wire(CurrentPageReference)
    capturePageRef(ref) {
        const offering = (ref && ref.state && ref.state.c__offering) || '';
        if (!offering || offering === this._requestedOffering) return;
        this._requestedOffering = offering;
        this.selectedOffering = offering;
        if (!this.loading) {
            this.loadDefinition();
        }
    }

    async connectedCallback() {
        try {
            const rows = await getOfferings();
            this.offerings = (rows || []).filter((o) => o.offeringKey !== FRAMEWORK_KEY);
            this.selectedOffering = this._requestedOffering || this.offeringKey
                || (this.offerings.length === 1 ? this.offerings[0].offeringKey : '');
        } catch (e) {
            this.offerings = [];
            this.error = 'Offerings could not be loaded.';
        }
        await this.loadDefinition();
        this.loading = false;
    }

    get offeringOptions() {
        return this.offerings.map((o) => ({ label: o.label, value: o.offeringKey }));
    }

    get hasOffering() { return !!this.selectedOffering; }
    get showOfferingPicker() { return this.offerings.length > 1; }

    get offeringLabel() {
        const hit = this.offerings.find((o) => o.offeringKey === this.selectedOffering);
        return hit ? hit.label : this.selectedOffering;
    }

    get headerMeta() {
        if (!this.hasOffering) return 'Choose an offering to begin';
        if (this.hasDefinition) return `${this.offeringLabel} · ${this.definitionStatus} · v${this.definitionVersion}`;
        return `${this.offeringLabel} · No instrument yet`;
    }

    async handleOfferingChange(event) {
        const next = event.detail.value;
        if (next === this.selectedOffering) return;
        this.selectedOffering = next;
        this.error = '';
        this.message = '';
        this.loading = true;
        await this.loadDefinition();
        this.loading = false;
    }

    async loadDefinition() {
        this.questions = [];
        this.outcomeRanges = [];
        this.deletedQuestionIds = [];
        this.deletedRangeIds = [];
        this.previewAnswers = {};
        if (!this.hasOffering) {
            this.hasDefinition = false;
            return;
        }
        try {
            const dto = await getDefinitionForOffering({ offeringKey: this.selectedOffering });
            if (!dto) {
                this.hasDefinition = false;
                this.definitionId = null;
                this.definitionName = '';
                this.definitionStatus = '';
                this.definitionVersion = null;
                this.definitionThemeKey = '';
                return;
            }
            this.hasDefinition = true;
            this.definitionId = dto.id;
            this.definitionName = dto.name;
            this.definitionStatus = dto.status;
            this.definitionVersion = dto.version;
            this.definitionThemeKey = dto.themeKey || '';
            this.questions = (dto.questions || []).map(fromQuestionDto);
            this.outcomeRanges = (dto.outcomeRanges || []).map(fromRangeDto);
        } catch (e) {
            this.error = 'Could not load the instrument for that offering.';
        }
    }

    async handleCreate() {
        if (!this.hasOffering) return;
        this.loading = true;
        try {
            const dto = await createDefinition({
                offeringKey: this.selectedOffering,
                name: `${this.offeringLabel} Assessment`
            });
            this.hasDefinition = true;
            this.definitionId = dto.id;
            this.definitionName = dto.name;
            this.definitionStatus = dto.status;
            this.definitionVersion = dto.version;
            this.definitionThemeKey = '';
            this.questions = [];
            this.outcomeRanges = [];
        } catch (e) {
            this.error = 'Could not create an instrument for that offering.';
        }
        this.loading = false;
    }

    // ------------------------------------------------------------- tabs

    handleViewQuestions() { this.view = VIEW_QUESTIONS; }
    handleViewOutcomes()  { this.view = VIEW_OUTCOMES; }
    handleViewPreview()   { this.view = VIEW_PREVIEW; }

    get isQuestionsView() { return this.view === VIEW_QUESTIONS; }
    get isOutcomesView()  { return this.view === VIEW_OUTCOMES; }
    get isPreviewView()   { return this.view === VIEW_PREVIEW; }
    get questionsTabClass() { return this.isQuestionsView ? 'ia-tab ia-tab--on' : 'ia-tab'; }
    get outcomesTabClass()  { return this.isOutcomesView ? 'ia-tab ia-tab--on' : 'ia-tab'; }
    get previewTabClass()   { return this.isPreviewView ? 'ia-tab ia-tab--on' : 'ia-tab'; }

    get questionTypeOptions() { return QUESTION_TYPES; }
    get jumpActionOptions() { return JUMP_ACTIONS; }

    /** Every other question's key, for a Logic Jump target picker (a question cannot jump to itself). */
    targetOptionsFor(questionKey) {
        return this.questions
            .filter((q) => q.questionKey && q.questionKey !== questionKey)
            .map((q) => ({ label: `${q.questionKey} — ${(q.questionText || '').slice(0, 40)}`, value: q.questionKey }));
    }

    get questionCards() {
        return this.questions.map((q, index) => {
            const showsOptions = hasOptions(q.questionType);
            const targets = this.targetOptionsFor(q.questionKey);
            return {
                ...q,
                index,
                showsOptions,
                showsNumeric: q.questionType === 'Numeric_Scale',
                first: index === 0,
                last: index === this.questions.length - 1,
                questionTypeOptions: QUESTION_TYPES.map((t) => ({ ...t, selected: t.value === q.questionType })),
                options: (q.options || []).map((o, oi) => ({
                    ...o,
                    index: oi,
                    targetOptions: [{ label: 'Choose a question…', value: '' }, ...targets],
                    hasJump: !!o.jumpTarget
                }))
            };
        });
    }

    handleAddQuestion() {
        const q = {
            _localId: localId(),
            id: null,
            slotOrder: this.questions.length + 1,
            questionText: '',
            questionType: 'Single_Select',
            required: false,
            questionKey: `q${this.questions.length + 1}`,
            minValue: null,
            maxValue: null,
            pointsPerUnit: null,
            options: [
                { value: 'yes', label: 'Yes', points: 1, jumpAction: '', jumpTarget: '' },
                { value: 'no', label: 'No', points: 0, jumpAction: '', jumpTarget: '' }
            ],
            _otherRules: []
        };
        this.questions = [...this.questions, q];
    }

    handleDeleteQuestion(event) {
        const idx = Number(event.currentTarget.dataset.index);
        const q = this.questions[idx];
        if (q && q.id) {
            this.deletedQuestionIds = [...this.deletedQuestionIds, q.id];
        }
        this.questions = this.questions.filter((_, i) => i !== idx);
        this.renumber();
    }

    handleMoveQuestion(event) {
        const idx = Number(event.currentTarget.dataset.index);
        const dir = event.currentTarget.dataset.dir;
        const target = dir === 'up' ? idx - 1 : idx + 1;
        if (target < 0 || target >= this.questions.length) return;
        const next = [...this.questions];
        [next[idx], next[target]] = [next[target], next[idx]];
        this.questions = next;
        this.renumber();
    }

    renumber() {
        this.questions = this.questions.map((q, i) => ({ ...q, slotOrder: i + 1 }));
    }

    handleQuestionField(event) {
        const { index, field } = event.currentTarget.dataset;
        const i = Number(index);
        const raw = event.currentTarget.type === 'checkbox' ? event.currentTarget.checked : event.currentTarget.value;
        const value = ['minValue', 'maxValue', 'pointsPerUnit'].includes(field) && raw !== ''
            ? Number(raw) : raw;
        this.questions = this.questions.map((q, qi) => (qi === i ? { ...q, [field]: value } : q));
    }

    handleAddOption(event) {
        const i = Number(event.currentTarget.dataset.index);
        this.questions = this.questions.map((q, qi) => {
            if (qi !== i) return q;
            const options = [...(q.options || []), { value: '', label: '', points: 0, jumpAction: '', jumpTarget: '' }];
            return { ...q, options };
        });
    }

    handleDeleteOption(event) {
        const i = Number(event.currentTarget.dataset.index);
        const oi = Number(event.currentTarget.dataset.optionIndex);
        this.questions = this.questions.map((q, qi) => {
            if (qi !== i) return q;
            return { ...q, options: (q.options || []).filter((_, x) => x !== oi) };
        });
    }

    handleOptionField(event) {
        const { index, optionIndex, field } = event.currentTarget.dataset;
        const i = Number(index);
        const oi = Number(optionIndex);
        const raw = event.currentTarget.value;
        const value = field === 'points' && raw !== '' ? Number(raw) : raw;
        this.questions = this.questions.map((q, qi) => {
            if (qi !== i) return q;
            const options = (q.options || []).map((o, x) => (x === oi ? { ...o, [field]: value } : o));
            return { ...q, options };
        });
    }

    /**
     * A jump action change of "No jump" clears the target too — an
     * inline Logic Jump with an action but no destination is exactly the
     * "inert branch" failure mode `gtmInstrumentAuthor`'s prior incarnation
     * warned about for `show_when`, and there is no reason to let it persist
     * here either.
     */
    handleOptionJumpAction(event) {
        const { index, optionIndex } = event.currentTarget.dataset;
        const i = Number(index);
        const oi = Number(optionIndex);
        const value = event.detail.value;
        this.questions = this.questions.map((q, qi) => {
            if (qi !== i) return q;
            const options = (q.options || []).map((o, x) => (x === oi
                ? { ...o, jumpAction: value, jumpTarget: value ? o.jumpTarget : '' }
                : o));
            return { ...q, options };
        });
    }

    handleOptionJumpTarget(event) {
        const { index, optionIndex } = event.currentTarget.dataset;
        const i = Number(index);
        const oi = Number(optionIndex);
        const value = event.detail.value;
        this.questions = this.questions.map((q, qi) => {
            if (qi !== i) return q;
            const options = (q.options || []).map((o, x) => (x === oi ? { ...o, jumpTarget: value } : o));
            return { ...q, options };
        });
    }

    // --------------------------------------------------------- outcomes

    get outcomeCards() {
        return this.outcomeRanges.map((r, index) => ({ ...r, index }));
    }

    handleAddRange() {
        const r = {
            _localId: localId(),
            id: null,
            minScore: 0,
            maxScore: 0,
            tierLabel: '',
            readoutTemplateKey: '',
            sortOrder: this.outcomeRanges.length + 1
        };
        this.outcomeRanges = [...this.outcomeRanges, r];
    }

    handleDeleteRange(event) {
        const idx = Number(event.currentTarget.dataset.index);
        const r = this.outcomeRanges[idx];
        if (r && r.id) {
            this.deletedRangeIds = [...this.deletedRangeIds, r.id];
        }
        this.outcomeRanges = this.outcomeRanges.filter((_, i) => i !== idx);
    }

    handleRangeField(event) {
        const { index, field } = event.currentTarget.dataset;
        const i = Number(index);
        const raw = event.currentTarget.value;
        const value = ['minScore', 'maxScore', 'sortOrder'].includes(field) && raw !== '' ? Number(raw) : raw;
        this.outcomeRanges = this.outcomeRanges.map((r, ri) => (ri === i ? { ...r, [field]: value } : r));
    }

    /**
     * Non-blocking authoring aid — doc §2.3 explicitly leaves non-overlap/
     * full-coverage unenforced at the schema layer, so this only surfaces
     * an overlap, it never prevents a save.
     */
    get rangeOverlapWarning() {
        const sorted = [...this.outcomeRanges]
            .filter((r) => r.minScore !== null && r.minScore !== undefined && r.maxScore !== null && r.maxScore !== undefined)
            .sort((a, b) => a.minScore - b.minScore);
        for (let i = 1; i < sorted.length; i++) {
            if (sorted[i].minScore <= sorted[i - 1].maxScore) {
                return 'Two or more outcome ranges overlap — the lowest Sort Order wins ties, but double check this is intended.';
            }
        }
        return '';
    }

    // -------------------------------------------------------- validation

    /** Structural, save-time-only check (doc §3.2 / gtmRuleEngine.detectCircularDependencies), not run per-answer. */
    get circularWarning() {
        const cycles = detectCircularDependencies(this.allRules);
        if (!cycles.length) return '';
        return `Logic Jump forms a loop: ${cycles[0].join(' → ')}. A respondent could never finish this path.`;
    }

    get allRules() {
        const rules = [];
        this.questions.forEach((q) => rules.push(...buildRulesForQuestion(q)));
        return rules;
    }

    get canSave() { return this.hasDefinition && !this.loading; }

    // -------------------------------------------------------------- save

    async handleSave() {
        if (!this.definitionId) return;
        this.loading = true;
        this.error = '';
        this.message = '';
        try {
            if (this.deletedQuestionIds.length) {
                await deleteQuestions({ questionIds: this.deletedQuestionIds });
            }
            if (this.deletedRangeIds.length) {
                await deleteOutcomeRanges({ rangeIds: this.deletedRangeIds });
            }
            if (this.questions.length) {
                // Sent as a JSON string, not a raw array, and deserialized
                // server-side with JSON.deserialize -- Aura's automatic
                // binding of a List<QuestionDto> parameter was proven (live
                // gtm-staging debug log 07LgK00000Sj1uHUAR) to silently drop
                // questionText before the Apex method body ever runs, even
                // though this exact payload shape is confirmed correct on
                // the wire. See GtmInstrumentDefinitionController.saveQuestions.
                await saveQuestions({
                    definitionId: this.definitionId,
                    questionsJson: JSON.stringify(this.questions.map(toQuestionDto))
                });
            }
            if (this.outcomeRanges.length) {
                await saveOutcomeRanges({
                    definitionId: this.definitionId,
                    rangesJson: JSON.stringify(this.outcomeRanges.map(toRangeDto))
                });
            }
            this.deletedQuestionIds = [];
            this.deletedRangeIds = [];
            await this.loadDefinition();
            this.message = 'Saved.';
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('gtmInstrumentAuthor.handleSave failed', e);
            this.error = `Save failed: ${extractErrorMessage(e)}`;
        }
        this.loading = false;
    }

    async handlePublish() {
        if (!this.definitionId) return;
        await this.handleSave();
        if (this.error) return;
        this.loading = true;
        try {
            await publishDefinition({ definitionId: this.definitionId });
            await this.loadDefinition();
            this.message = 'Published.';
        } catch (e) {
            this.error = 'Publish failed.';
        }
        this.loading = false;
    }

    async handleArchive() {
        if (!this.definitionId) return;
        this.loading = true;
        try {
            await archiveDefinition({ definitionId: this.definitionId });
            await this.loadDefinition();
            this.message = 'Archived.';
        } catch (e) {
            this.error = 'Archive failed.';
        }
        this.loading = false;
    }

    async handleRenameOrRestatus(event) {
        const { field } = event.currentTarget.dataset;
        const value = event.currentTarget.value;
        if (field === 'name') this.definitionName = value;
        if (field === 'themeKey') this.definitionThemeKey = value;
        if (!this.definitionId) return;
        try {
            await saveDefinition({
                definitionId: this.definitionId,
                name: this.definitionName,
                status: this.definitionStatus,
                themeKey: this.definitionThemeKey
            });
        } catch (e) {
            this.error = 'Could not save the instrument name/theme.';
        }
    }

    // ------------------------------------------------------------ preview

    /**
     * Read-only flow-map preview: walks the authored order, filtering by
     * `c/gtmRuleEngine.evaluateRules`'s hidden/visible sets given the
     * answers picked so far, exactly the module the guest-facing runtime
     * (sub-issue 03) evaluates against — same rules in, same visibility out.
     */
    get previewFlow() {
        const rules = this.allRules;
        const knownKeys = this.questions.map((q) => q.questionKey).filter(Boolean);
        const evaluation = evaluateRules(rules, this.previewAnswers, knownKeys);
        return this.questions.map((q) => {
            const key = q.questionKey;
            const explicitlyHidden = key && evaluation.hidden.has(key);
            const answer = key ? this.previewAnswers[key] : undefined;
            return {
                _localId: q._localId || q.id,
                questionKey: key,
                questionText: q.questionText,
                slotOrder: q.slotOrder,
                hidden: !!explicitlyHidden,
                required: !!(q.required || (key && evaluation.required.has(key))),
                options: (q.options || []).map((o) => ({
                    ...o,
                    selected: answer === o.value,
                    cls: answer === o.value ? 'ia-popt ia-popt--on' : 'ia-popt'
                }))
            };
        });
    }

    get previewSkipTarget() { return null; }

    handlePreviewChoice(event) {
        const key = event.currentTarget.dataset.key;
        const value = event.currentTarget.dataset.value;
        this.previewAnswers = { ...this.previewAnswers, [key]: value };
    }

    handleClearPreview() { this.previewAnswers = {}; }

    get previewTotal() {
        let total = 0;
        this.questions.forEach((q) => {
            const answer = this.previewAnswers[q.questionKey];
            if (answer === undefined) return;
            if (q.questionType === 'Numeric_Scale') {
                total += (Number(answer) || 0) * (q.pointsPerUnit || 0);
            } else {
                const opt = (q.options || []).find((o) => o.value === answer);
                if (opt) total += Number(opt.points) || 0;
            }
        });
        return total;
    }

    /**
     * The tier the current preview total resolves to, using the same
     * min<=score<=max / lowest-Sort-Order-wins tie-break this editor
     * documents in its own Outcome Mapping tab (doc §4's deferred
     * tie-break, decided here for the preview since sub-issue 02/03 do not
     * yet expose a server-side resolver to call).
     */
    get previewOutcome() {
        const total = this.previewTotal;
        const hit = [...this.outcomeRanges]
            .filter((r) => r.minScore !== null && r.minScore !== undefined
                && r.maxScore !== null && r.maxScore !== undefined
                && total >= r.minScore && total <= r.maxScore)
            .sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0))[0];
        return hit ? hit.tierLabel : '';
    }

    get previewScoreLine() { return `Total: ${this.previewTotal}`; }
}

// ---------------------------------------------------------------- helpers

function safeParseArray(json) {
    if (!json) return [];
    try {
        const parsed = JSON.parse(json);
        return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
        return [];
    }
}

/** Splits a question's Rules_JSON__c into "one per option, authored by this UI" vs. everything else. */
function splitRules(questionKey, options, rules) {
    const byValue = new Map();
    const other = [];
    rules.forEach((rule) => {
        const conditions = Array.isArray(rule && rule.conditions) ? rule.conditions : [];
        const isInlineShape = conditions.length === 1
            && conditions[0].field === questionKey
            && conditions[0].operator === 'EQUALS'
            && (rule.action === 'SHOW' || rule.action === 'SKIP_TO_SECTION');
        if (isInlineShape) {
            byValue.set(String(conditions[0].value), rule);
        } else {
            other.push(rule);
        }
    });
    const withJumps = options.map((o) => {
        const rule = byValue.get(String(o.value));
        return rule
            ? { ...o, jumpAction: rule.action, jumpTarget: rule.target }
            : { ...o, jumpAction: '', jumpTarget: '' };
    });
    return { options: withJumps, otherRules: other };
}

function fromQuestionDto(dto) {
    const options = safeParseArray(dto.optionsJson);
    const rules = safeParseArray(dto.rulesJson);
    const { options: withJumps, otherRules } = splitRules(dto.questionKey, options, rules);
    return {
        _localId: dto.id,
        id: dto.id,
        slotOrder: dto.slotOrder,
        questionText: dto.questionText || '',
        questionType: dto.questionType || 'Single_Select',
        required: !!dto.required,
        questionKey: dto.questionKey || '',
        minValue: dto.minValue,
        maxValue: dto.maxValue,
        pointsPerUnit: dto.pointsPerUnit,
        options: withJumps,
        _otherRules: otherRules
    };
}

function buildRulesForQuestion(q) {
    const authored = (q.options || [])
        .filter((o) => o.jumpAction && o.jumpTarget)
        .map((o) => ({
            logic: 'AND',
            conditions: [{ field: q.questionKey, operator: 'EQUALS', value: o.value }],
            action: o.jumpAction,
            target: o.jumpTarget
        }));
    return [...(q._otherRules || []), ...authored];
}

/**
 * Pulls the real server/AuraHandledException message out of an imperative
 * Apex call rejection instead of letting the caller show a canned string.
 * LWC/Aura error shapes vary by failure type (body.message for
 * AuraHandledException/handled DML errors, body.pageErrors/fieldErrors for
 * some remote-action failures, plain message for JS-side throws) -- this
 * checks all of them so a real server error (e.g. REQUIRED_FIELD_MISSING)
 * surfaces instead of being swallowed into "Save failed."
 */
function extractErrorMessage(e) {
    if (!e) return 'Unknown error.';
    const body = e.body;
    if (body) {
        if (typeof body.message === 'string' && body.message) return body.message;
        if (Array.isArray(body.pageErrors) && body.pageErrors.length) {
            return body.pageErrors.map((pe) => pe.message).join('; ');
        }
        if (body.fieldErrors && Object.keys(body.fieldErrors).length) {
            return Object.values(body.fieldErrors)
                .flat()
                .map((fe) => fe.message)
                .join('; ');
        }
    }
    if (typeof e.message === 'string' && e.message) return e.message;
    if (Array.isArray(e) && e.length) return e.map((x) => x.message || x).join('; ');
    return 'Unknown error.';
}

function toQuestionDto(q) {
    const options = hasOptions(q.questionType)
        ? (q.options || []).map((o) => ({ label: o.label, value: o.value, points: Number(o.points) || 0 }))
        : [];
    return {
        id: q.id,
        slotOrder: q.slotOrder,
        questionText: q.questionText,
        questionType: q.questionType,
        optionsJson: options.length ? JSON.stringify(options) : '',
        rulesJson: JSON.stringify(buildRulesForQuestion(q)),
        required: q.required,
        questionKey: q.questionKey,
        minValue: q.questionType === 'Numeric_Scale' ? q.minValue : null,
        maxValue: q.questionType === 'Numeric_Scale' ? q.maxValue : null,
        pointsPerUnit: q.questionType === 'Numeric_Scale' ? q.pointsPerUnit : null
    };
}

function fromRangeDto(dto) {
    return {
        _localId: dto.id,
        id: dto.id,
        minScore: dto.minScore,
        maxScore: dto.maxScore,
        tierLabel: dto.tierLabel || '',
        readoutTemplateKey: dto.readoutTemplateKey || '',
        sortOrder: dto.sortOrder
    };
}

function toRangeDto(r) {
    return {
        id: r.id,
        minScore: r.minScore,
        maxScore: r.maxScore,
        tierLabel: r.tierLabel,
        readoutTemplateKey: r.readoutTemplateKey,
        sortOrder: r.sortOrder
    };
}
