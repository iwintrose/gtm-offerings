import { ANSWER_FIELDS, hasMeaningfulAnswers } from 'c/gtmAssessmentAnswerFields';

/** Mirrors the wired getRecord shape the three real consumers pass in --
 *  { fields: { <Api_Name__c>: { value } } }. */
function record(overrides = {}) {
    return {
        fields: {
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
        }
    };
}

describe('c/gtmAssessmentAnswerFields', () => {
    it('exports exactly the twelve instrument answer fields, in the documented order', () => {
        expect(ANSWER_FIELDS).toHaveLength(12);
        expect(ANSWER_FIELDS.map((f) => f.fieldApiName)).toEqual([
            'Pain_Points__c', 'Migration_Goals__c', 'Success_Criteria__c', 'Decision_Makers__c',
            'Budget_Range__c', 'Urgency_Driver__c', 'Key_Integrations__c', 'Executive_Sponsorship__c',
            'Target_Platform__c', 'Internal_Team_Size__c', 'Monthly_Send_Volume__c', 'Contact_Count__c'
        ]);
        ANSWER_FIELDS.forEach((f) => expect(f.objectApiName).toBe('GTM_Assessment_Request__c'));
    });

    it('hasMeaningfulAnswers is false when every answer field is blank', () => {
        expect(hasMeaningfulAnswers(record())).toBe(false);
    });

    it('hasMeaningfulAnswers is true when exactly one answer field is non-blank', () => {
        expect(hasMeaningfulAnswers(record({ Target_Platform__c: { value: 'Marketing Cloud' } }))).toBe(true);
    });

    it('hasMeaningfulAnswers is true when every answer field is non-blank', () => {
        const allFilled = record(
            Object.fromEntries(ANSWER_FIELDS.map((f) => [f.fieldApiName, { value: 'x' }]))
        );
        expect(hasMeaningfulAnswers(allFilled)).toBe(true);
    });

    it('hasMeaningfulAnswers is false for a null/undefined record (no wired data yet)', () => {
        expect(hasMeaningfulAnswers(null)).toBe(false);
        expect(hasMeaningfulAnswers(undefined)).toBe(false);
    });

    it('hasMeaningfulAnswers respects a caller-supplied subset of fields rather than always defaulting to all twelve', () => {
        const partial = record({ Pain_Points__c: { value: 'Filled in.' } });
        // Restricting to a subset that does NOT include the filled field must
        // return false, proving the second `fields` argument is actually used
        // and not silently ignored in favor of the ANSWER_FIELDS default.
        expect(hasMeaningfulAnswers(partial, [ANSWER_FIELDS[1]])).toBe(false);
        expect(hasMeaningfulAnswers(partial, [ANSWER_FIELDS[0]])).toBe(true);
    });
});
