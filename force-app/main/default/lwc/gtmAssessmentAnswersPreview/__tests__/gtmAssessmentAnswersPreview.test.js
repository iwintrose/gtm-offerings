import { createElement } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { registerLdsTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import GtmAssessmentAnswersPreview from 'c/gtmAssessmentAnswersPreview';

const getRecordWireAdapter = registerLdsTestWireAdapter(getRecord);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function baseFields(overrides = {}) {
    return {
        Contact__r: { value: null },
        Requester_Name__c: { value: 'Jane Smith' },
        Account__r: { value: null },
        Company__c: { value: 'Acme Co' },
        Submitted_At__c: { value: null },
        Pain_Points__c: { value: null },
        Migration_Goals__c: { value: null },
        Success_Criteria__c: { value: null },
        Decision_Makers__c: { value: null },
        Budget_Range__c: { value: null },
        Urgency_Driver__c: { value: null },
        Key_Integrations__c: { value: null },
        Executive_Sponsorship__c: { value: null },
        Target_Platform__c: { value: null },
        Internal_Team_Size__c: { value: null },
        Monthly_Send_Volume__c: { value: null },
        Contact_Count__c: { value: null },
        ...overrides
    };
}

function emitRecord(fields) {
    getRecordWireAdapter.emit({ fields });
}

describe('c-gtm-assessment-answers-preview', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders all twelve questions', async () => {
        const element = createElement('c-gtm-assessment-answers-preview', {
            is: GtmAssessmentAnswersPreview
        });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        await flushPromises();
        emitRecord(baseFields());
        await flushPromises();

        const items = element.shadowRoot.querySelectorAll('.gaap-item');
        expect(items.length).toBe(12);
    });

    it('shows the prospect\'s real submitted answer when a field is populated', async () => {
        const element = createElement('c-gtm-assessment-answers-preview', {
            is: GtmAssessmentAnswersPreview
        });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        await flushPromises();
        emitRecord(
            baseFields({
                Pain_Points__c: { value: 'Deliverability is terrible.' },
                Budget_Range__c: { value: '$500K – $1M' }
            })
        );
        await flushPromises();

        const answers = Array.from(element.shadowRoot.querySelectorAll('.gaap-item')).map((li) => ({
            question: li.querySelector('.gaap-question').textContent,
            answer: li.querySelector('p:last-child').textContent
        }));

        const painPoints = answers.find((a) =>
            a.question.includes("What's not working with your current platform?")
        );
        expect(painPoints.answer).toBe('Deliverability is terrible.');

        const budget = answers.find((a) => a.question === 'Budget range');
        expect(budget.answer).toBe('$500K – $1M');
    });

    it('shows "Not answered" for any question the prospect left blank, whether or not the assessment was submitted', async () => {
        const element = createElement('c-gtm-assessment-answers-preview', {
            is: GtmAssessmentAnswersPreview
        });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        await flushPromises();
        emitRecord(
            baseFields({
                Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' },
                Pain_Points__c: { value: 'Filled in.' }
                // every other answer field left blank
            })
        );
        await flushPromises();

        const blanks = element.shadowRoot.querySelectorAll('.gaap-answer--blank');
        // 11 of the 12 questions are blank in this fixture (only Pain Points is filled)
        expect(blanks.length).toBe(11);
        blanks.forEach((el) => expect(el.textContent).toBe('Not answered'));
    });

    it('renders nothing to fetch when no record id is provided', async () => {
        const element = createElement('c-gtm-assessment-answers-preview', {
            is: GtmAssessmentAnswersPreview
        });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.gaap-list')).toBeNull();
    });
});
