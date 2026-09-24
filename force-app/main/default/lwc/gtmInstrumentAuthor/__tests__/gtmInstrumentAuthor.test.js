/**
 * assessment-instrument-rebuild-04-editor-lwc-wiring — the rebuilt
 * gtmInstrumentAuthor editor against the new
 * GTM_Instrument_Definition__c / _Question_Definition__c /
 * _Outcome_Range__c schema (docs/architecture/gtm-instrument-schema.md).
 */
import { createElement } from 'lwc';
import GtmInstrumentAuthor from 'c/gtmInstrumentAuthor';
import getOfferings from '@salesforce/apex/GtmPageContentController.getOfferings';
import getDefinitionForOffering from '@salesforce/apex/GtmInstrumentDefinitionController.getDefinitionForOffering';
import createDefinition from '@salesforce/apex/GtmInstrumentDefinitionController.createDefinition';
import saveQuestions from '@salesforce/apex/GtmInstrumentDefinitionController.saveQuestions';
import saveOutcomeRanges from '@salesforce/apex/GtmInstrumentDefinitionController.saveOutcomeRanges';
import publishDefinition from '@salesforce/apex/GtmInstrumentDefinitionController.publishDefinition';

jest.mock(
    '@salesforce/apex/GtmPageContentController.getOfferings',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmInstrumentDefinitionController.getDefinitionForOffering',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmInstrumentDefinitionController.createDefinition',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmInstrumentDefinitionController.saveDefinition',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmInstrumentDefinitionController.saveQuestions',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmInstrumentDefinitionController.deleteQuestions',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmInstrumentDefinitionController.saveOutcomeRanges',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmInstrumentDefinitionController.deleteOutcomeRanges',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmInstrumentDefinitionController.publishDefinition',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmInstrumentDefinitionController.archiveDefinition',
    () => ({ default: jest.fn() }), { virtual: true }
);

const flush = () => new Promise((r) => setTimeout(r, 0));

const OFFERINGS = [{ offeringKey: 'ma-migrator', label: 'Migration Accelerator' }];

function DEFINITION() {
    return {
        id: 'a01000000000001',
        offeringKey: 'ma-migrator',
        name: 'Migration Accelerator Assessment',
        status: 'Draft',
        version: 1,
        themeKey: '',
        questions: [
            {
                id: 'a02000000000001',
                slotOrder: 1,
                questionText: 'What is your current platform?',
                questionType: 'Single_Select',
                optionsJson: JSON.stringify([
                    { label: 'SFMC', value: 'sfmc', points: 1 },
                    { label: 'Other', value: 'other', points: 2 }
                ]),
                rulesJson: JSON.stringify([
                    {
                        logic: 'AND',
                        conditions: [{ field: 'q1', operator: 'EQUALS', value: 'other' }],
                        action: 'SHOW',
                        target: 'q2'
                    }
                ]),
                required: true,
                questionKey: 'q1',
                minValue: null,
                maxValue: null,
                pointsPerUnit: null
            },
            {
                id: 'a02000000000002',
                slotOrder: 2,
                questionText: 'Tell us more about "Other"',
                questionType: 'Single_Select',
                optionsJson: JSON.stringify([
                    { label: 'Yes', value: 'yes', points: 3 },
                    { label: 'No', value: 'no', points: 0 }
                ]),
                rulesJson: '',
                required: false,
                questionKey: 'q2',
                minValue: null,
                maxValue: null,
                pointsPerUnit: null
            }
        ],
        outcomeRanges: [
            { id: 'a03000000000001', minScore: 0, maxScore: 2, tierLabel: 'Low', readoutTemplateKey: '', sortOrder: 1 },
            { id: 'a03000000000002', minScore: 3, maxScore: 5, tierLabel: 'High', readoutTemplateKey: 'high-tpl', sortOrder: 2 }
        ]
    };
}

function flushDom() {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
}

describe('c-gtm-instrument-author (assessment-instrument-rebuild-04-editor-lwc-wiring)', () => {
    afterEach(() => {
        flushDom();
        jest.clearAllMocks();
    });

    async function setup(definition = DEFINITION()) {
        getOfferings.mockResolvedValue(OFFERINGS);
        getDefinitionForOffering.mockResolvedValue(definition);
        const element = createElement('c-gtm-instrument-author', { is: GtmInstrumentAuthor });
        document.body.appendChild(element);
        await flush();
        await flush();
        return element;
    }

    it('loads the offering, hydrates questions with inline Logic Jump parsed from Rules_JSON__c, and shows the Questions tab by default', async () => {
        const element = await setup();
        expect(getDefinitionForOffering).toHaveBeenCalledWith({ offeringKey: 'ma-migrator' });

        const cards = element.shadowRoot.querySelectorAll('.ia-qcard');
        expect(cards.length).toBe(2);

        // The first question's "other" option carries the inline Logic Jump
        // parsed out of its Rules_JSON__c (SHOW -> q2).
        const jumpActions = element.shadowRoot.querySelectorAll('lightning-combobox.ia-jump-action');
        expect(jumpActions.length).toBeGreaterThan(0);
    });

    it('offers a Create instrument action when the offering has none yet', async () => {
        getOfferings.mockResolvedValue(OFFERINGS);
        getDefinitionForOffering.mockResolvedValue(null);
        createDefinition.mockResolvedValue({
            id: 'a01000000000099', offeringKey: 'ma-migrator',
            name: 'Migration Accelerator Assessment', status: 'Draft', version: 1
        });

        const element = createElement('c-gtm-instrument-author', { is: GtmInstrumentAuthor });
        document.body.appendChild(element);
        await flush();
        await flush();

        const createBtn = element.shadowRoot.querySelector('.ia-empty button');
        expect(createBtn).toBeTruthy();
        createBtn.click();
        await flush();

        expect(createDefinition).toHaveBeenCalledWith({
            offeringKey: 'ma-migrator', name: 'Migration Accelerator Assessment'
        });
    });

    it('switches to the Outcome Mapping tab and renders the authored score ranges', async () => {
        const element = await setup();
        const outcomesTab = Array.from(element.shadowRoot.querySelectorAll('.ia-tabs button'))
            .find((b) => b.textContent === 'Outcome Mapping');
        outcomesTab.click();
        await flush();

        const rows = element.shadowRoot.querySelectorAll('.ia-range-row');
        expect(rows.length).toBe(2);
    });

    it('switches to the Flow-map Preview tab and computes a total/tier from selected preview answers', async () => {
        const element = await setup();
        const previewTab = Array.from(element.shadowRoot.querySelectorAll('.ia-tabs button'))
            .find((b) => b.textContent === 'Flow-map Preview');
        previewTab.click();
        await flush();

        // Answer q1 with "sfmc" (1 point) -- lands in the "Low" range (0-2).
        const optionButtons = element.shadowRoot.querySelectorAll('.ia-popts button');
        const sfmcBtn = Array.from(optionButtons).find((b) => b.textContent.includes('SFMC'));
        expect(sfmcBtn).toBeTruthy();
        sfmcBtn.click();
        await flush();

        const scoreLine = element.shadowRoot.querySelector('.ia-preview-score');
        expect(scoreLine.textContent).toContain('Total: 1');
        expect(scoreLine.textContent).toContain('Low');
    });

    it('saves questions and outcome ranges as DTOs matching the Apex contract on Save', async () => {
        saveQuestions.mockResolvedValue();
        saveOutcomeRanges.mockResolvedValue();
        const element = await setup();
        // Re-stub the reload call after save.
        getDefinitionForOffering.mockResolvedValue(DEFINITION());

        const saveBtn = Array.from(element.shadowRoot.querySelectorAll('.ia-actions button'))
            .find((b) => b.textContent === 'Save');
        saveBtn.click();
        await flush();
        await flush();

        expect(saveQuestions).toHaveBeenCalled();
        const [{ definitionId, questionsJson }] = saveQuestions.mock.calls[0];
        expect(definitionId).toBe('a01000000000001');
        // questionsJson is sent as a JSON string, not a raw array -- see
        // GtmInstrumentDefinitionController.saveQuestions for why (Aura's
        // automatic List<QuestionDto> parameter binding silently dropped
        // questionText; JSON.deserialize on a string parameter does not).
        expect(typeof questionsJson).toBe('string');
        const questions = JSON.parse(questionsJson);
        expect(questions[0].questionKey).toBe('q1');
        // The inline Logic Jump on q1's "other" option round-trips back into rulesJson.
        const rules = JSON.parse(questions[0].rulesJson);
        expect(rules.some((r) => r.target === 'q2' && r.action === 'SHOW')).toBe(true);

        expect(saveOutcomeRanges).toHaveBeenCalled();
        const [{ definitionId: rangeDefId, rangesJson }] = saveOutcomeRanges.mock.calls[0];
        expect(rangeDefId).toBe('a01000000000001');
        expect(typeof rangesJson).toBe('string');
        const ranges = JSON.parse(rangesJson);
        expect(ranges.length).toBe(2);
    });

    it('publishing saves first, then calls publishDefinition', async () => {
        saveQuestions.mockResolvedValue();
        saveOutcomeRanges.mockResolvedValue();
        publishDefinition.mockResolvedValue();
        const element = await setup();
        getDefinitionForOffering.mockResolvedValue({ ...DEFINITION(), status: 'Active', version: 2 });

        const publishBtn = Array.from(element.shadowRoot.querySelectorAll('.ia-actions button'))
            .find((b) => b.textContent === 'Publish');
        publishBtn.click();
        await flush();
        await flush();

        expect(saveQuestions).toHaveBeenCalled();
        expect(publishDefinition).toHaveBeenCalledWith({ definitionId: 'a01000000000001' });
    });

    it('adding a new question renders an additional card with the inline option row (no separate rule list)', async () => {
        const element = await setup();
        const addBtn = element.shadowRoot.querySelector('.ia-add-q');
        addBtn.click();
        await flush();

        const cards = element.shadowRoot.querySelectorAll('.ia-qcard');
        expect(cards.length).toBe(3);
    });

    /**
     * Regression test for the live gtm-staging bug (confirmed 2026-09-23):
     * Question_Text__c never persisted -- text was visibly typed into the
     * input, but never made it into the DTO Save actually sent to Apex.
     *
     * Root cause was proven, via live Apex debug log 07LgK00000Sj1uHUAR, to
     * be Aura's automatic server-side binding of the `List<QuestionDto>`
     * @AuraEnabled parameter silently dropping `questionText` before
     * saveQuestions's body ever ran -- NOT this client component (the
     * captured XHR payload already contained the correct string), and NOT
     * stripInaccessible/FLS (that runs later, on the sObject, and the DTO
     * was already null before it was reached). This test locks in the
     * client-side half of the fix: the typed input -> handleQuestionField ->
     * toQuestionDto -> JSON.stringify -> saveQuestions payload path must
     * keep carrying the typed value end to end. The server-side half (Apex
     * now accepts a JSON string and deserializes it itself, bypassing
     * Aura's binder) is proven separately in
     * GtmInstrumentDefinitionControllerTest.
     */
    it('typing into a newly-added question\'s text input carries that value all the way into the saveQuestions DTO', async () => {
        saveQuestions.mockResolvedValue();
        saveOutcomeRanges.mockResolvedValue();
        const element = await setup();
        getDefinitionForOffering.mockResolvedValue(DEFINITION());

        const addBtn = element.shadowRoot.querySelector('.ia-add-q');
        addBtn.click();
        await flush();

        const cards = element.shadowRoot.querySelectorAll('.ia-qcard');
        expect(cards.length).toBe(3);
        const newCard = cards[2];
        const textInput = newCard.querySelector('.ia-qtext');
        expect(textInput).toBeTruthy();

        textInput.value = 'Do you have a documented migration plan?';
        textInput.dispatchEvent(new CustomEvent('change'));
        await flush();

        // Blur (as the bug report's repro explicitly tested) shouldn't
        // change anything -- the value is already committed on 'change'.
        textInput.dispatchEvent(new CustomEvent('blur'));
        await flush();

        const saveBtn = Array.from(element.shadowRoot.querySelectorAll('.ia-actions button'))
            .find((b) => b.textContent === 'Save');
        saveBtn.click();
        await flush();
        await flush();

        expect(saveQuestions).toHaveBeenCalled();
        const [{ questionsJson }] = saveQuestions.mock.calls[0];
        expect(typeof questionsJson).toBe('string');
        const questions = JSON.parse(questionsJson);
        expect(questions.length).toBe(3);
        expect(questions[2].questionText).toBe('Do you have a documented migration plan?');
    });
});
