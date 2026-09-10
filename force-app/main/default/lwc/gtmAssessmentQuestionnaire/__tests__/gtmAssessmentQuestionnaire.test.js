import { createElement } from 'lwc';
import GtmAssessmentQuestionnaire from 'c/gtmAssessmentQuestionnaire';
import getPlatforms from '@salesforce/apex/GtmAssessmentInstrument.getPlatforms';
import getPack from '@salesforce/apex/GtmAssessmentInstrument.getPack';
import getQuestionnaire from '@salesforce/apex/GtmAssessmentQuestions.getQuestionnaire';
import submitRequest from '@salesforce/apex/GtmAssessmentRequestController.submitRequest';
import saveDraft from '@salesforce/apex/GtmAssessmentDraftController.saveDraft';
import resumeDraft from '@salesforce/apex/GtmAssessmentDraftController.resumeDraft';
import emailResumeLink from '@salesforce/apex/GtmAssessmentDraftController.emailResumeLink';
import verifyAndIssueToken from '@salesforce/apex/GtmLinkAuthController.verifyAndIssueToken';

jest.mock(
    '@salesforce/apex/GtmLinkAuthController.verifyAndIssueToken',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentInstrument.getPlatforms',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentInstrument.getPack',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentQuestions.getQuestionnaire',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentRequestController.submitRequest',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentDraftController.saveDraft',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentDraftController.resumeDraft',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentDraftController.emailResumeLink',
    () => ({ default: jest.fn() }), { virtual: true }
);

const flush = () => new Promise((r) => setTimeout(r, 0));

const PLATFORMS = [
    { key: 'sfmc', label: 'Salesforce Marketing Cloud', family: null },
    { key: 'sfmc_next', label: 'Marketing Cloud Next', family: 'core_native' }
];

function opts(points) {
    return [1, 2, 3, 4].map((v) => ({
        value: v,
        label: `option ${v}`,
        points: points ? points[v - 1] : v,
        available: true
    }));
}

function slot(position, key, extra = {}) {
    return {
        position,
        key,
        baseKey: key,
        label: `Slot ${position}`,
        question: `Question ${position}?`,
        // The prospect-facing half. Its consultant-facing counterpart is not on
        // the wire at all: GtmAssessmentInstrument.Slot.evidencePrompt is not
        // @AuraEnabled, so a pack cannot carry one even if someone wanted it to.
        respondentHint: `Hint ${position}`,
        variantKey: 'default',
        options: opts(),
        variants: [],
        substitutable: true,
        ...extra
    };
}

/** Eight slots, one of them capped, one of them branched on slot 1. */
function pack() {
    const capped = slot(2, 'source_access');
    capped.options = capped.options.map((o) =>
        o.value === 4
            ? { ...o, available: false, unavailableReason: 'No connector ships today.' }
            : o
    );
    const branched = slot(7, 'consent_portability');
    branched.variants = [
        {
            ...slot(7, 'consent_ownership_outside_platform'),
            baseKey: 'consent_portability',
            variantKey: 'consent_owned_elsewhere',
            question: 'Who masters consent?',
            showWhenJson: '{"all":[{"field":"estate_scale","op":"lte","value":2}]}'
        }
    ];
    return {
        pairKey: 'sfmc__mcn',
        version: '2026.09.1',
        sourceKey: 'sfmc',
        targetKey: 'sfmc_next',
        postureStatement: 'We can read your current estate.',
        resolutionNote: null,
        complexityDimensions: [
            'workflow_footprint_native', 'data_extension_complexity', 'scripting_depth',
            'business_unit_structure', 'integration_surface', 'consent_suppression_model'
        ].map((k, i) => ({
            position: i + 1,
            key: k,
            baseKey: k,
            label: `Adapted ${i + 1}`,
            question: `How many ${k}?`,
            respondentHint: `Where to find ${k}`,
            options: [1, 2, 3].map((v) => ({ value: v, label: `a ${v}`, available: true }))
        })),
        supplements: [
            {
                key: 'data_cloud_state',
                setKey: 'mcn_readiness',
                scored: true,
                question: 'Where is Data Cloud?',
                options: [1, 2, 3].map((v) => ({ value: v, label: `dc ${v}`, available: true }))
            },
            {
                key: 'core_footprint',
                setKey: 'mcn_readiness',
                scored: true,
                question: 'Is Core stood up?',
                options: [1, 2, 3].map((v) => ({ value: v, label: `core ${v}`, available: true }))
            },
            {
                key: 'shared_audience_definitions',
                setKey: 'mcn_readiness',
                scored: false,
                question: 'How many share an audience definition?',
                options: []
            },
            {
                key: 'forward_looking_ambitions',
                setKey: 'mcn_readiness',
                scored: false,
                question: 'What are you hoping for later?',
                options: []
            },
            {
                key: 'reporting_signoff',
                setKey: 'mcn_readiness',
                scored: false,
                question: 'Who signs reporting off?',
                options: []
            },
            {
                key: 'cms_scope_expectation',
                setKey: 'mcn_readiness',
                scored: false,
                question: 'Does the web estate move?',
                options: []
            }
        ],
        slots: [
            slot(1, 'estate_scale'),
            capped,
            slot(3, 'orchestration_portability'),
            slot(4, 'content_portability'),
            slot(5, 'data_model_readiness'),
            slot(6, 'integration_containment'),
            branched,
            slot(8, 'decision_readiness')
        ]
    };
}

const COMPLEXITY = ['journey_footprint', 'data_extension_complexity', 'scripting_depth'].map(
    (k, i) => ({
        dimensionKey: k,
        dimensionName: `Complexity ${i + 1}`,
        questionText: `How complex is ${k}?`,
        options: [1, 2, 3].map((v) => ({ value: v, label: `c ${v}` }))
    })
);

async function mount() {
    const el = createElement('c-gtm-assessment-questionnaire', {
        is: GtmAssessmentQuestionnaire
    });
    document.body.appendChild(el);
    await flush();
    await flush();
    return el;
}

const q = (el, sel) => el.shadowRoot.querySelectorAll(sel);
const one = (el, sel) => el.shadowRoot.querySelector(sel);

/** Answers every visible option group on the current step by clicking option 3. */
function answerStep(el, value = 3) {
    q(el, 'fieldset').forEach((fs) => {
        const btns = fs.querySelectorAll(`.q-opt-btn[data-value="${value}"]`);
        if (btns.length) btns[0].click();
    });
}

async function next(el) {
    one(el, '.q-btn--go').click();
    await flush();
    await flush();
}

async function toReadiness(el) {
    one(el, 'select[data-field="source"]').value = 'sfmc';
    one(el, 'select[data-field="source"]').dispatchEvent(new CustomEvent('change'));
    one(el, 'select[data-field="target"]').value = 'sfmc_next';
    one(el, 'select[data-field="target"]').dispatchEvent(new CustomEvent('change'));
    await flush();
    await next(el);
}

describe('c-gtm-assessment-questionnaire', () => {
    beforeEach(() => {
        window.localStorage.clear();
        getPlatforms.mockResolvedValue(PLATFORMS);
        getPack.mockResolvedValue(pack());
        getQuestionnaire.mockResolvedValue({
            readiness: [],
            complexity: COMPLEXITY,
            readinessMaxScore: 32,
            complexityMaxScore: 18
        });
        submitRequest.mockResolvedValue({ assessmentRequestId: '001' });
        saveDraft.mockResolvedValue({
            resumeToken: 'TOKEN-AAA',
            expiresAt: '2026-10-06T09:00:00.000Z',
            created: true
        });
        resumeDraft.mockResolvedValue(null);
        emailResumeLink.mockResolvedValue({ sent: true, message: 'Sent.' });
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('opens on the routing step, not on a wall of questions', async () => {
        const el = await mount();
        expect(one(el, '.q-title').textContent).toBe('About the move');
        expect(q(el, 'fieldset').length).toBe(0);
        // Six steps are known before a pack resolves — routing, the three fixed
        // readiness groups, complexity and contact — because those are the fixed
        // frame and do not depend on the pair. The seventh appears once the pack
        // says this pair has supplements. Counting them the other way round
        // (deriving all the readiness steps from the resolved pack) made the
        // form appear to double in length the moment you answered the first
        // question, which is the opposite of what a progress bar is for.
        expect(one(el, '.q-progress-label').textContent).toBe('Section 1 of 9');
    });

    it('adds the supplement step once the pack says the pair has one', async () => {
        const el = await mount();
        await toReadiness(el);
        expect(one(el, '.q-progress-label').textContent).toBe('Section 2 of 12');
    });

    it('shows the posture statement exactly once, leading the first questions', async () => {
        // It used to render at the bottom of every screen after routing -- the
        // same ~90 words, verbatim, seven times, ending "every count below"
        // while sitting at the bottom with nothing below it. Not the routing
        // step: the pack does not exist until that step is left, so a posture
        // rendered there would be empty for every respondent, every time.
        const el = await mount();
        expect(q(el, '.q-posture').length).toBe(0);
        await toReadiness(el);
        expect(q(el, '.q-posture').length).toBe(1);
        expect(one(el, '.q-posture').textContent).toContain('We can read your current estate.');
        // And on no screen after it.
        let guard = 0;
        while (!one(el, '.q-done') && guard < 16) {
            answerStep(el);
            const before = one(el, '.q-progress-label')
                ? one(el, '.q-progress-label').textContent : null;
            await next(el);
            if (one(el, '.q-progress-label') &&
                one(el, '.q-progress-label').textContent === before) break;
            expect(q(el, '.q-posture').length).toBe(0);
            guard += 1;
        }
        expect(guard).toBeGreaterThan(3);
    });

    it('shows the respondent hint and never an interviewer note', async () => {
        // The worst fault the form had: every readiness slot ended with a
        // consultant's note written in the second person ABOUT the person
        // reading it ("Ask for five numbers, not an adjective"). The fix is
        // structural -- evidencePrompt is not @AuraEnabled, so it is not on the
        // wire -- and this pins the rendered half.
        const el = await mount();
        await toReadiness(el);
        const hints = [...q(el, '.q-evidence')].map((n) => n.textContent.trim());
        expect(hints).toContain('Hint 1');
        hints.forEach((h) => expect(h.startsWith('Ask')).toBe(false));
    });

    it('asks the complexity dimensions the PACK resolved, not the unadapted six', async () => {
        const el = await mount();
        await toReadiness(el);
        let guard = 0;
        while (!one(el, '.q-title') ||
               one(el, '.q-title').textContent !== 'How big the job is') {
            answerStep(el);
            await next(el);
            guard += 1;
            if (guard > 6) break;
        }
        expect(one(el, '.q-title').textContent).toBe('How big the job is');
        const questions = [...q(el, '.q-question')].map((n) => n.textContent);
        expect(questions[0]).toBe('How many workflow_footprint_native?');
        // The flat getQuestionnaire() list is a fallback only; a resolved pack
        // wins, or the second axis is still asking a HubSpot marketer about
        // "30-100 tables, moderate SQL".
        questions.forEach((t) => expect(t.startsWith('How complex is')).toBe(false));
    });

    it('spreads the supplements over screens and never stacks free text', async () => {
        // Eight supplements on one screen, five of them consecutive empty
        // textareas, is what this replaces -- in a component whose own header
        // says never more than four questions on a screen.
        const el = await mount();
        await toReadiness(el);
        const runs = [];
        // Counted ACROSS screen boundaries: two textareas either side of a
        // Continue button are still two textareas in a row to the person
        // answering them.
        let run = 0;
        let guard = 0;
        while (!one(el, '.q-done') && guard < 14) {
            if (one(el, '.q-title') &&
                one(el, '.q-title').textContent === 'About the target platform') {
                expect(q(el, 'fieldset').length).toBeLessThanOrEqual(4);
                q(el, 'fieldset').forEach((fs) => {
                    if (fs.querySelector('textarea')) {
                        run += 1;
                        runs.push(run);
                    } else {
                        run = 0;
                    }
                });
            }
            answerStep(el);
            const before = one(el, '.q-progress-label')
                ? one(el, '.q-progress-label').textContent : null;
            await next(el);
            if (one(el, '.q-progress-label') &&
                one(el, '.q-progress-label').textContent === before) break;
            guard += 1;
        }
        expect(runs.length).toBeGreaterThan(0);
        expect(Math.max(...runs)).toBeLessThanOrEqual(2);
    });

    it('labels the two counters as different things', async () => {
        // "Step 2 of 8" in the header above cards counting "1 of 8 ... 8 of 8"
        // was two different eights on one screen with nothing to tell them apart.
        const el = await mount();
        await toReadiness(el);
        expect(one(el, '.q-progress-label').textContent.startsWith('Section ')).toBe(true);
        expect(one(el, '.q-pos').textContent).toBe('Question 1 of 8');
    });

    it('refuses to leave the routing step without a source and a target', async () => {
        const el = await mount();
        await next(el);
        expect(one(el, '.q-error')).not.toBeNull();
        expect(one(el, '.q-title').textContent).toBe('About the move');
    });

    it('never shows more than four questions on one step', async () => {
        const el = await mount();
        await toReadiness(el);
        let guard = 0;
        while (!one(el, '.q-done') && guard < 16) {
            expect(q(el, 'fieldset').length).toBeLessThanOrEqual(4);
            answerStep(el);
            const before = one(el, '.q-progress-label').textContent;
            await next(el);
            if (one(el, '.q-progress-label') &&
                one(el, '.q-progress-label').textContent === before) break;
            guard += 1;
        }
        expect(guard).toBeGreaterThan(0);
    });

    it('renders a capped option visibly unavailable with its reason, rather than dropping it', async () => {
        const el = await mount();
        await toReadiness(el);
        const off = one(el, '.q-opt--off');
        expect(off).not.toBeNull();
        expect(off.querySelector('.q-opt-btn').disabled).toBe(true);
        expect(one(el, '.q-opt-why').textContent).toContain('No connector ships today.');
        // The whole point: it is still on the page. A respondent can see a 4 was
        // not on offer and why.
        expect(q(el, '.q-opt-btn[data-value="4"]').length).toBeGreaterThan(0);
    });

    it('will not let an over-ceiling answer be chosen at all', async () => {
        const el = await mount();
        await toReadiness(el);
        const capped = one(el, '.q-opt--off .q-opt-btn');
        capped.click();
        await flush();
        expect(one(el, '.q-opt--off').classList.contains('q-opt--on')).toBe(false);
    });

    it('keeps answers when stepping back', async () => {
        const el = await mount();
        await toReadiness(el);
        answerStep(el);
        await next(el);
        one(el, '.q-btn--quiet').click();
        await flush();
        expect(q(el, '.q-opt--on').length).toBe(3);
    });

    it('branches a later slot on an earlier answer, and still asks eight questions', async () => {
        const el = await mount();
        await toReadiness(el);
        // Answer slot 1 low, which fires the consent branch.
        one(el, '.q-opt-btn[data-key="estate_scale"][data-value="1"]').click();
        await flush();
        // Walk to the step holding slot 7.
        answerStep(el, 2);
        await next(el);
        answerStep(el, 2);
        await next(el);
        const questions = Array.from(q(el, '.q-question')).map((p) => p.textContent);
        expect(questions).toContain('Who masters consent?');
        // Two questions on the final readiness step: positions 7 and 8. The
        // branch substituted; it did not remove.
        expect(q(el, 'fieldset').length).toBe(2);
    });

    it('labels the supplements as not affecting the score', async () => {
        const el = await mount();
        await toReadiness(el);
        let guard = 0;
        while (!one(el, '.q-aside-tag') && guard < 12) {
            answerStep(el);
            await next(el);
            guard += 1;
        }
        const aside = one(el, '.q-aside-tag');
        expect(aside).not.toBeNull();
        expect(aside.textContent).toBe('These do not affect your score');
        expect(one(el, '.q-textarea')).not.toBeNull();
    });

    it('submits raw answers and never a score', async () => {
        const el = await mount();
        await toReadiness(el);
        let guard = 0;
        while (!one(el, 'input[data-field="name"]') && guard < 14) {
            answerStep(el);
            await next(el);
            guard += 1;
        }
        one(el, 'input[data-field="name"]').value = 'Ada';
        one(el, 'input[data-field="name"]').dispatchEvent(new CustomEvent('change'));
        one(el, 'input[data-field="email"]').value = 'ada@example.com';
        one(el, 'input[data-field="email"]').dispatchEvent(new CustomEvent('change'));
        await flush();
        await next(el);

        expect(submitRequest).toHaveBeenCalled();
        const payload = submitRequest.mock.calls[0][0].input;
        expect(payload.assessmentScore).toBeUndefined();
        expect(payload.assessmentTier).toBeUndefined();
        expect(payload.sectionScores).toBeUndefined();
        expect(payload.answers.length).toBe(8);
        expect(payload.answers[0]).toHaveProperty('dimension');
        expect(payload.answers[0]).toHaveProperty('value');
        expect(payload.complexityAnswers.length).toBe(6);
    });

    /**
     * TOKEN RE-AUTH OVERLAY. The 30-minute password-gate token (separate from
     * the resume link, which is long-lived) can go stale while someone is
     * still filling the form in -- easily, on a resumed draft link. The old
     * behaviour surfaced the server's raw message with only "Start again" as
     * a way out, which read as data loss even though the draft survives.
     */
    async function reachContactStep(el) {
        await toReadiness(el);
        let guard = 0;
        while (!one(el, 'input[data-field="name"]') && guard < 14) {
            answerStep(el);
            await next(el);
            guard += 1;
        }
        one(el, 'input[data-field="name"]').value = 'Ada';
        one(el, 'input[data-field="name"]').dispatchEvent(new CustomEvent('change'));
        one(el, 'input[data-field="email"]').value = 'ada@example.com';
        one(el, 'input[data-field="email"]').dispatchEvent(new CustomEvent('change'));
        await flush();
    }

    const TOKEN_REAUTH_MESSAGE =
        'Your session has expired. Please re-enter the access password to send your assessment.';

    it('shows the re-auth overlay, not a raw error, when the submission token has gone stale', async () => {
        const el = await mount();
        await reachContactStep(el);
        submitRequest.mockRejectedValueOnce({ body: { message: TOKEN_REAUTH_MESSAGE } });

        await next(el);

        expect(one(el, '.q-reauth-overlay')).toBeTruthy();
        expect(one(el, '.q-error')).toBeFalsy();
        // The answers are untouched -- nothing was cleared to show the overlay.
        expect(one(el, 'input[data-field="name"]').value).toBe('Ada');
    });

    it('re-authenticates and retries the same submit, with no lost answers', async () => {
        const el = await mount();
        await reachContactStep(el);
        submitRequest.mockRejectedValueOnce({ body: { message: TOKEN_REAUTH_MESSAGE } });
        await next(el);
        expect(one(el, '.q-reauth-overlay')).toBeTruthy();

        verifyAndIssueToken.mockResolvedValue({
            matched: true,
            submissionToken: 'REC:1234:freshhmac'
        });
        submitRequest.mockResolvedValueOnce({ assessmentRequestId: '002' });

        const pwInput = one(el, '.q-reauth-overlay input[type="password"]');
        pwInput.value = 'secret123';
        pwInput.dispatchEvent(new CustomEvent('change'));
        one(el, '.q-reauth-overlay form').dispatchEvent(new CustomEvent('submit'));
        await flush();
        await flush();

        expect(verifyAndIssueToken).toHaveBeenCalledWith(
            expect.objectContaining({ password: 'secret123' })
        );
        expect(one(el, '.q-reauth-overlay')).toBeFalsy();
        expect(submitRequest).toHaveBeenCalledTimes(2);
        const retriedPayload = submitRequest.mock.calls[1][0].input;
        expect(retriedPayload.submissionToken).toBe('REC:1234:freshhmac');
        expect(retriedPayload.name).toBe('Ada');
        expect(one(el, '.q-done')).toBeTruthy();
    });

    it('shows an inline error on a wrong re-auth password and keeps the overlay and the form state', async () => {
        const el = await mount();
        await reachContactStep(el);
        submitRequest.mockRejectedValueOnce({ body: { message: TOKEN_REAUTH_MESSAGE } });
        await next(el);
        expect(one(el, '.q-reauth-overlay')).toBeTruthy();

        verifyAndIssueToken.mockResolvedValue({ matched: false });

        const pwInput = one(el, '.q-reauth-overlay input[type="password"]');
        pwInput.value = 'wrong';
        pwInput.dispatchEvent(new CustomEvent('change'));
        one(el, '.q-reauth-overlay form').dispatchEvent(new CustomEvent('submit'));
        await flush();
        await flush();

        expect(one(el, '.q-reauth-overlay')).toBeTruthy();
        expect(one(el, '.q-reauth-overlay .q-error').textContent).toContain('Incorrect password');
        // submitRequest was never retried on a failed re-auth.
        expect(submitRequest).toHaveBeenCalledTimes(1);
        expect(one(el, 'input[data-field="name"]').value).toBe('Ada');
    });

    /**
     * SAME-DEVICE RESUME. The assertion that matters is the step label: an
     * answer map that comes back but dumps the respondent at step 1 is not
     * resuming, it is asking them to find their place again. The old version of
     * this test asserted `not.toBe('Section 1 of 7')`, which a regression to
     * "Section 1 of 9" would have passed.
     */
    it('restores both the answers AND the step after a reload', async () => {
        const el = await mount();
        await toReadiness(el);
        answerStep(el);
        document.body.removeChild(el);

        getPack.mockResolvedValue(pack());
        const again = await mount();
        expect(one(again, '.q-progress-label').textContent).toBe('Section 2 of 12');
        expect(one(again, '.q-title').textContent).toBe(
            'What you are moving, and whether we can read it'
        );
        expect(q(again, '.q-opt--on').length).toBe(3);
    });

    it('restores a later step too, not just the first one', async () => {
        const el = await mount();
        await toReadiness(el);
        answerStep(el);
        await next(el);
        answerStep(el);
        await next(el);
        expect(one(el, '.q-progress-label').textContent).toBe('Section 4 of 12');
        document.body.removeChild(el);

        getPack.mockResolvedValue(pack());
        const again = await mount();
        expect(one(again, '.q-progress-label').textContent).toBe('Section 4 of 12');
    });

    /**
     * Two engagement links on one machine used to overwrite each other, because
     * the storage key was one string for the whole origin.
     */
    it('keeps one engagement link progress out of another link progress', async () => {
        const a = createElement('c-gtm-assessment-questionnaire', {
            is: GtmAssessmentQuestionnaire
        });
        a.savedRecordId = 'cfg-A';
        document.body.appendChild(a);
        await flush();
        await flush();
        await toReadiness(a);
        answerStep(a);
        document.body.removeChild(a);

        const b = createElement('c-gtm-assessment-questionnaire', {
            is: GtmAssessmentQuestionnaire
        });
        b.savedRecordId = 'cfg-B';
        document.body.appendChild(b);
        await flush();
        await flush();
        expect(one(b, '.q-progress-label').textContent).toBe('Section 1 of 9');
        expect(q(b, '.q-opt--on').length).toBe(0);
    });

    // ─── cross-device resume ────────────────────────────────────────────

    it('saves nothing to the server while still on the routing step', async () => {
        await mount();
        expect(saveDraft).not.toHaveBeenCalled();
    });

    it('mints a draft on the first step transition, before any email exists', async () => {
        const el = await mount();
        await toReadiness(el);
        expect(saveDraft).toHaveBeenCalled();
        const args = saveDraft.mock.calls[0][0];
        expect(args.resumeToken).toBe('');
        expect(args.pairKey).toBe('sfmc__mcn');
        expect(JSON.parse(args.payload).stepIndex).toBe(1);
    });

    it('tells the respondent plainly that nothing is saved yet, then that it is', async () => {
        const el = await mount();
        one(el, 'select[data-field="source"]').value = 'sfmc';
        one(el, 'select[data-field="source"]').dispatchEvent(new CustomEvent('change'));
        await flush();
        expect(one(el, '.q-keep-tag').textContent).toContain('this device only');

        await toReadiness(el);
        answerStep(el);
        await flush();
        expect(one(el, '.q-keep-tag').textContent).toContain('Your place is saved');
        expect(one(el, '.q-keep-url').value).toContain('resume=TOKEN-AAA');
    });

    it('reuses the token it was given rather than minting a second draft', async () => {
        const el = await mount();
        await toReadiness(el);
        answerStep(el);
        saveDraft.mockResolvedValue({
            resumeToken: 'TOKEN-AAA',
            expiresAt: '2026-10-06T09:00:00.000Z',
            created: false
        });
        await next(el);
        const last = saveDraft.mock.calls[saveDraft.mock.calls.length - 1][0];
        expect(last.resumeToken).toBe('TOKEN-AAA');
    });

    it('picks a saved draft back up on another device, at the step it was left on', async () => {
        resumeDraft.mockResolvedValue({
            payload: JSON.stringify({
                v: 2,
                routing: { source: 'sfmc', target: 'sfmc_next', timeline: '', environmentSize: '' },
                answers: { estate_scale: 3, source_access: 2, orchestration_portability: 4 },
                complexity: {},
                supplements: {},
                notes: {},
                contact: { name: '', email: '', company: '', role: '', context: '' },
                stepIndex: 2
            }),
            expiresAt: '2026-10-06T09:00:00.000Z',
            lastSavedAt: '2026-09-06T09:00:00.000Z'
        });
        const el = createElement('c-gtm-assessment-questionnaire', {
            is: GtmAssessmentQuestionnaire
        });
        el.resumeToken = 'TOKEN-BBB';
        document.body.appendChild(el);
        await flush();
        await flush();
        await flush();

        expect(resumeDraft).toHaveBeenCalledWith({ resumeToken: 'TOKEN-BBB' });
        expect(one(el, '.q-progress-label').textContent).toBe('Section 3 of 12');
        expect(one(el, '.q-notice')).not.toBeNull();
    });

    /**
     * Expired, submitted, mistyped and never-issued are one response from the
     * server, and must be one sentence here. Local answers survive it.
     */
    it('says so once when a link is dead, and keeps what is on this device', async () => {
        const first = await mount();
        await toReadiness(first);
        answerStep(first);
        document.body.removeChild(first);

        resumeDraft.mockResolvedValue(null);
        getPack.mockResolvedValue(pack());
        const el = createElement('c-gtm-assessment-questionnaire', {
            is: GtmAssessmentQuestionnaire
        });
        el.resumeToken = 'TOKEN-DEAD';
        document.body.appendChild(el);
        await flush();
        await flush();
        await flush();

        expect(one(el, '.q-notice').textContent).toContain('no longer available');
        expect(q(el, '.q-opt--on').length).toBe(3);
    });

    it('carries the draft token on submit so the server can revoke it', async () => {
        const el = await mount();
        await toReadiness(el);
        // Walk to the contact step rather than counting screens: how many there
        // are is a property of the resolved pack, and a test that hard-codes it
        // fails every time a supplement set grows.
        let guard = 0;
        while (!one(el, 'input[data-field="name"]') && guard < 14) {
            answerStep(el);
            await next(el);
            guard += 1;
        }
        one(el, 'input[data-field="name"]').value = 'Dana Cole';
        one(el, 'input[data-field="name"]').dispatchEvent(new CustomEvent('change'));
        one(el, 'input[data-field="email"]').value = 'dana@example.com';
        one(el, 'input[data-field="email"]').dispatchEvent(new CustomEvent('change'));
        await flush();
        await next(el);

        const payload = submitRequest.mock.calls[0][0].input;
        expect(payload.draftToken).toBe('TOKEN-AAA');
        expect(payload.assessmentScore).toBeUndefined();
    });

    it('does not block the form when the server save fails', async () => {
        saveDraft.mockRejectedValue({ body: { message: 'no' } });
        const el = await mount();
        await toReadiness(el);
        await flush();
        expect(one(el, '.q-title').textContent).toBe(
            'What you are moving, and whether we can read it'
        );
        expect(one(el, '.q-keep-bad')).not.toBeNull();
    });

    it('emails the link with the token and the typed address, and stores neither', async () => {
        const el = await mount();
        await toReadiness(el);
        answerStep(el);
        await flush();
        const input = one(el, '.q-keep-email input');
        input.value = 'someone@example.com';
        input.dispatchEvent(new CustomEvent('change'));
        await flush();
        [...q(el, '.q-keep-actions .q-btn')].pop().click();
        await flush();
        await flush();

        expect(emailResumeLink).toHaveBeenCalledWith({
            resumeToken: 'TOKEN-AAA',
            emailAddress: 'someone@example.com'
        });
        // The address given for a resume link is not the respondent's contact
        // details, and must not quietly become them.
        const stored = JSON.parse(
            window.localStorage.getItem('ma-assessment-progress-v2:direct')
        );
        expect(stored.contact.email).toBe('');
    });

    it('renders the questions from the pack rather than from a hardcoded list', async () => {
        const el = await mount();
        await toReadiness(el);
        expect(one(el, '.q-question').textContent).toBe('Question 1?');
        expect(getPack).toHaveBeenCalledWith({
            // Which offering's instrument these questions came from. Defaults
            // to migration-accelerator until a page sets the @api property --
            // see the property's own comment for why that default is honest
            // rather than a guess.
            offeringKey: 'migration-accelerator',
            sourceName: 'sfmc',
            targetName: 'sfmc_next'
        });
        // The base question set is offering-scoped too: GtmAssessmentQuestions
        // filters its rows by Offering_Key__c, so an un-keyed call would serve
        // whatever offering's questions happened to sort first.
        expect(getQuestionnaire).toHaveBeenCalledWith({
            offeringKey: 'migration-accelerator'
        });
    });

    // ── the resume link keeps the engagement link (ADR-0008 phase 7.1) ──────

    it('sends the engagement link and the session with every draft save', async () => {
        // Stored on the draft row so the EMAILED resume link can carry ?cfgId=
        // as well as the token. Without it, a respondent who resumes from their
        // inbox and finishes produces an unlinked request: no Opportunity, no
        // Account, no rep attribution, scored against the default offering.
        const el = createElement('c-gtm-assessment-questionnaire', {
            is: GtmAssessmentQuestionnaire
        });
        el.savedRecordId = 'a0Bgk000000ABCDEAA';
        el.sessionId = 'visit-123';
        document.body.appendChild(el);
        await flush();
        await flush();
        await toReadiness(el);

        expect(saveDraft).toHaveBeenCalled();
        const args = saveDraft.mock.calls[0][0];
        expect(args.configId).toBe('a0Bgk000000ABCDEAA');
        expect(args.sessionId).toBe('visit-123');
    });

    it('keeps the engagement link on the copyable resume URL', async () => {
        // This used to be origin + pathname + the token, which threw the whole
        // query string away -- and since the questionnaire moved behind
        // /configurator, that means throwing away ?cfgId=.
        const el = createElement('c-gtm-assessment-questionnaire', {
            is: GtmAssessmentQuestionnaire
        });
        el.savedRecordId = 'a0Bgk000000ABCDEAA';
        document.body.appendChild(el);
        await flush();
        await flush();
        await toReadiness(el);

        const url = one(el, '.q-keep-url').value;
        expect(url).toContain('cfgId=a0Bgk000000ABCDEAA');
        expect(url).toContain('resume=TOKEN-AAA');
        // Exactly two parameters: the incidental ones on the URL the respondent
        // happens to be sitting on (?rep=, ?book=, a stale ?readout=) are not
        // handed to whoever they forward this to.
        expect(url.split('?')[1].split('&').length).toBe(2);
    });

    it('still builds a usable resume URL with no engagement link at all', async () => {
        const el = await mount();
        await toReadiness(el);

        const url = one(el, '.q-keep-url').value;
        expect(url).toContain('resume=TOKEN-AAA');
        expect(url).not.toContain('cfgId=');
    });

    // ── the BD-context step (ADR-0008 section 5) ────────────────────────────

    /** Walks to the first BD-context screen. */
    async function toBdContext(el) {
        await toReadiness(el);
        let guard = 0;
        while (!one(el, '.q-skip') && guard < 14) {
            answerStep(el);
            await next(el);
            guard += 1;
        }
        expect(one(el, '.q-skip')).not.toBeNull();
    }

    it('asks the BD-context fields as their own optional, chunked step', async () => {
        const el = await mount();
        await toBdContext(el);

        expect(one(el, '.q-title').textContent).toBe('Anything else worth knowing');
        // The file's own rule, which it has broken once before: never more than
        // four questions on a screen. Eleven fields, chunked, is 4-4-3.
        expect(q(el, 'fieldset').length).toBeLessThanOrEqual(4);
        // Said in prose once, and per field where the decision is actually made.
        expect(one(el, '.q-aside-tag').textContent).toBe('These do not affect your score');
        expect(q(el, '.q-optional').length).toBe(q(el, 'fieldset').length);
    });

    it('blocks nothing on the BD-context step — every field is optional', async () => {
        const el = await mount();
        await toBdContext(el);
        const before = one(el, '.q-progress-label').textContent;

        // Nothing answered at all, straight to Continue.
        await next(el);

        expect(one(el, '.q-error')).toBeNull();
        expect(one(el, '.q-progress-label').textContent).not.toBe(before);
    });

    it('skips the whole BD-context block in one click, not just one screen', async () => {
        // A respondent who does not want to answer these does not want to be
        // asked the same thing again on the next screen.
        const el = await mount();
        await toBdContext(el);

        one(el, '.q-skip').click();
        await flush();
        await flush();

        expect(one(el, 'input[data-field="name"]')).not.toBeNull();
        expect(one(el, '.q-title').textContent).toBe('Where to send it');
        expect(one(el, '.q-skip')).toBeNull();
    });

    it('carries all eleven BD-context fields on the payload', async () => {
        const el = await mount();
        await toBdContext(el);

        const type = (key, value) => {
            const node = one(el, `[data-key="${key}"]`);
            expect(node).not.toBeNull();
            node.value = value;
            node.dispatchEvent(new CustomEvent('change'));
        };
        const VALUES = {
            painPoints: 'Deliverability is poor',
            migrationGoals: 'Real-time triggers',
            keyIntegrations: 'Snowflake',
            successCriteria: 'Sends land',
            budgetRange: '$500K – $1M',
            contactCount: '2500000',
            monthlySendVolume: '5000000',
            internalTeamSize: '2–5 people',
            executiveSponsorship: 'Unknown',
            decisionMakers: 'CMO',
            urgencyDriver: 'Contract expires March 2026'
        };
        // Spread across the three chunked screens, so this also proves the
        // values survive the step transitions between them.
        let guard = 0;
        while (one(el, '.q-skip') && guard < 6) {
            Object.keys(VALUES).forEach((k) => {
                if (one(el, `[data-key="${k}"]`)) type(k, VALUES[k]);
            });
            await flush();
            await next(el);
            guard += 1;
        }

        one(el, 'input[data-field="name"]').value = 'Ada';
        one(el, 'input[data-field="name"]').dispatchEvent(new CustomEvent('change'));
        one(el, 'input[data-field="email"]').value = 'ada@example.com';
        one(el, 'input[data-field="email"]').dispatchEvent(new CustomEvent('change'));
        await flush();
        await next(el);

        const payload = submitRequest.mock.calls[0][0].input;
        Object.keys(VALUES).forEach((k) => {
            expect(payload[k]).toBe(VALUES[k]);
        });
        // targetPlatform is NOT a bdContext key -- routing already collects it,
        // and collecting it twice would be two answers to one question.
        expect(payload.targetPlatform).toBe('Marketing Cloud Next');
    });

    /**
     * THE ISOLATION TEST. ADR-0008 section 5 and ADR-0007's hard boundary.
     *
     * These eleven are BD context, not instrument answers. answers,
     * complexityAnswers and supplementAnswers are the only scoring inputs Apex
     * trusts; a BD field that leaked into one of them would be scored as though
     * it were a dimension the respondent had been asked about.
     */
    it('never lets a BD-context field into a scored answer map', async () => {
        const el = await mount();
        await toBdContext(el);

        let guard = 0;
        while (one(el, '.q-skip') && guard < 6) {
            q(el, '[data-key]').forEach((node) => {
                node.value = 'SENTINEL';
                node.dispatchEvent(new CustomEvent('change'));
            });
            await flush();
            await next(el);
            guard += 1;
        }
        one(el, 'input[data-field="name"]').value = 'Ada';
        one(el, 'input[data-field="name"]').dispatchEvent(new CustomEvent('change'));
        one(el, 'input[data-field="email"]').value = 'ada@example.com';
        one(el, 'input[data-field="email"]').dispatchEvent(new CustomEvent('change'));
        await flush();
        await next(el);

        const payload = submitRequest.mock.calls[0][0].input;
        const BD_KEYS = [
            'painPoints', 'migrationGoals', 'keyIntegrations', 'successCriteria',
            'budgetRange', 'contactCount', 'monthlySendVolume', 'internalTeamSize',
            'executiveSponsorship', 'decisionMakers', 'urgencyDriver'
        ];
        const scoredDimensions = []
            .concat(payload.answers, payload.complexityAnswers, payload.supplementAnswers)
            .map((a) => a.dimension);

        BD_KEYS.forEach((k) => {
            expect(scoredDimensions).not.toContain(k);
        });
        // And the shape is undisturbed: still exactly eight scored slots.
        expect(payload.answers.length).toBe(8);
        expect(payload.complexityAnswers.length).toBe(6);
    });

    it('carries the BD-context answers through a draft round-trip', async () => {
        const el = await mount();
        await toBdContext(el);
        const pain = one(el, '[data-key="painPoints"]');
        pain.value = 'Deliverability is poor';
        pain.dispatchEvent(new CustomEvent('change'));
        await flush();

        const stored = JSON.parse(
            window.localStorage.getItem('ma-assessment-progress-v2:direct')
        );
        expect(stored.bdContext.painPoints).toBe('Deliverability is poor');

        // And it comes back on a fresh mount, at the same step.
        document.body.removeChild(el);
        getPack.mockResolvedValue(pack());
        const again = await mount();
        expect(one(again, '[data-key="painPoints"]').value).toBe('Deliverability is poor');
    });

    // ── the confirmation panel (ADR-0008 phase 5.3) ─────────────────────────

    /** Walks a mounted element all the way to a completed submission. */
    async function submitFully(el) {
        await toReadiness(el);
        let guard = 0;
        while (!one(el, 'input[data-field="name"]') && guard < 14) {
            answerStep(el);
            await next(el);
            guard += 1;
        }
        one(el, 'input[data-field="name"]').value = 'Ada';
        one(el, 'input[data-field="name"]').dispatchEvent(new CustomEvent('change'));
        one(el, 'input[data-field="email"]').value = 'ada@example.com';
        one(el, 'input[data-field="email"]').dispatchEvent(new CustomEvent('change'));
        await flush();
        await next(el);
    }

    it('offers the calendar CTA on the confirmation panel when the link carried one', async () => {
        // The "book an assessment" half of the CTA's promise. gtmConfigBooking's
        // confirmation panel had this; the questionnaire's did not, and a
        // straight swap would have dropped it.
        const el = createElement('c-gtm-assessment-questionnaire', {
            is: GtmAssessmentQuestionnaire
        });
        el.bookingUrl = 'https://calendly.example.com/rep';
        document.body.appendChild(el);
        await flush();
        await flush();
        await submitFully(el);

        expect(one(el, '.q-done')).not.toBeNull();
        const cta = one(el, '.q-done .q-cta');
        expect(cta).not.toBeNull();
        expect(cta.textContent.trim()).toBe('Pick a time in our calendar →');
        expect(cta.href).toBe('https://calendly.example.com/rep');
        expect(cta.target).toBe('_blank');
        expect(cta.rel).toBe('noopener');
    });

    it('shows no calendar CTA when the link carried no ?book= URL', async () => {
        const el = await mount();
        await submitFully(el);

        expect(one(el, '.q-done')).not.toBeNull();
        expect(one(el, '.q-done .q-cta')).toBeNull();
    });

    it('never offers a way to re-open the request after submitting', async () => {
        // gtmConfigBooking's confirmation panel had "Didn't send? Re-open the
        // request", which was the un-guarded resubmit path. After the
        // one-per-link server guard it would only offer a prospect a form the
        // server will refuse.
        const el = await mount();
        await submitFully(el);

        const done = one(el, '.q-done');
        expect(done.textContent).not.toContain('Re-open');
        expect(done.textContent).not.toContain('re-open');
        expect(one(el, '.q-btn--go')).toBeNull();
        expect(one(el, 'input[data-field="name"]')).toBeNull();
    });

    it('tells the host when a submit fails, so a lost race can be recovered', async () => {
        // The server refuses a duplicate (ADR-0008 section 4). The host re-asks
        // the server whether the link is now submitted rather than matching on
        // the refusal message -- so this event carries the message for display
        // and nothing the host has to parse.
        submitRequest.mockRejectedValue({
            body: { message: 'An assessment has already been submitted for this link.' }
        });
        const el = await mount();
        const failures = [];
        el.addEventListener('submitfailed', (e) => failures.push(e.detail));

        await submitFully(el);

        expect(failures.length).toBe(1);
        expect(failures[0].message).toContain('already been submitted');
        // The respondent sees why, in the form's own error slot, and the form
        // is still there rather than showing a false confirmation.
        expect(one(el, '.q-error').textContent).toContain('already been submitted');
        expect(one(el, '.q-done')).toBeNull();
    });

    // ── hosted inside the configurator's overlay (ADR-0008) ─────────────────

    it('renders full-page chrome by default and drops it when embedded', async () => {
        const standalone = await mount();
        expect(one(standalone, '.q-root')).not.toBeNull();
        expect(one(standalone, '.q-root--embedded')).toBeNull();

        const el = createElement('c-gtm-assessment-questionnaire', {
            is: GtmAssessmentQuestionnaire
        });
        el.embedded = true;
        document.body.appendChild(el);
        await flush();
        await flush();
        // Both classes: the modifier only undoes the page-level box, so every
        // rule that hangs off .q-root must still apply.
        expect(one(el, '.q-root.q-root--embedded')).not.toBeNull();
    });

    it('is embeddable without changing a single question, step or branch', async () => {
        // The whole safety argument for the D11 swap is that `embedded` is
        // chrome and nothing else. Asserted by walking the same form twice.
        const plain = await mount();
        await toReadiness(plain);
        const plainTitle = one(plain, '.q-title').textContent;
        const plainLabel = one(plain, '.q-progress-label').textContent;
        const plainQuestions = Array.from(q(plain, '.q-question')).map((n) => n.textContent);
        document.body.removeChild(plain);
        window.localStorage.clear();

        const el = createElement('c-gtm-assessment-questionnaire', {
            is: GtmAssessmentQuestionnaire
        });
        el.embedded = true;
        document.body.appendChild(el);
        await flush();
        await flush();
        await toReadiness(el);

        expect(one(el, '.q-title').textContent).toBe(plainTitle);
        expect(one(el, '.q-progress-label').textContent).toBe(plainLabel);
        expect(Array.from(q(el, '.q-question')).map((n) => n.textContent))
            .toEqual(plainQuestions);
    });

    it('asks the offering it was given, not the built-in default', async () => {
        // ADR-0008 section 3. gtmConfigurator passes the ENGAGEMENT LINK's own
        // Offering__c down here -- the same field
        // GtmAssessmentRequestController.resolveOfferingKey scores against. If
        // this property were ignored, the client would render one offering's
        // questions and the server would score them against another's pack,
        // resolving none of the submitted dimension keys and scoring nothing
        // while looking like it scored.
        const el = createElement('c-gtm-assessment-questionnaire', {
            is: GtmAssessmentQuestionnaire
        });
        el.offeringKey = 'commerce-accelerator';
        document.body.appendChild(el);
        await flush();
        await flush();

        expect(getQuestionnaire).toHaveBeenCalledWith({
            offeringKey: 'commerce-accelerator'
        });

        await toReadiness(el);
        expect(getPack).toHaveBeenCalledWith({
            offeringKey: 'commerce-accelerator',
            sourceName: 'sfmc',
            targetName: 'sfmc_next'
        });
    });

    it('carries contactId on the submitted event so the reading trail stays attributable', async () => {
        // gtmConfigurator.handleBookingSubmitted calls identifySession with
        // this, which attributes the whole anonymous reading trail to the
        // person who left it. gtmConfigBooking's event carried it; losing it in
        // the swap would have been a silent regression.
        submitRequest.mockResolvedValue({
            assessmentRequestId: 'AR-9',
            contactId: '003000000000001'
        });
        const el = await mount();
        const seen = [];
        el.addEventListener('submitted', (e) => seen.push(e.detail));

        await toReadiness(el);
        let guard = 0;
        while (!one(el, 'input[data-field="name"]') && guard < 14) {
            answerStep(el);
            await next(el);
            guard += 1;
        }
        one(el, 'input[data-field="name"]').value = 'Ada';
        one(el, 'input[data-field="name"]').dispatchEvent(new CustomEvent('change'));
        one(el, 'input[data-field="email"]').value = 'ada@example.com';
        one(el, 'input[data-field="email"]').dispatchEvent(new CustomEvent('change'));
        await flush();
        await next(el);

        expect(seen.length).toBe(1);
        expect(seen[0].assessmentRequestId).toBe('AR-9');
        expect(seen[0].contactId).toBe('003000000000001');
        expect(seen[0].email).toBe('ada@example.com');
    });
});
