import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ANSWER_FIELDS } from 'c/gtmAssessmentAnswerFields';

import CONTACT_NAME from '@salesforce/schema/GTM_Assessment_Request__c.Contact__r.Name';
import ACCOUNT_NAME from '@salesforce/schema/GTM_Assessment_Request__c.Account__r.Name';
import REQ_NAME from '@salesforce/schema/GTM_Assessment_Request__c.Requester_Name__c';
import COMPANY_FIELD from '@salesforce/schema/GTM_Assessment_Request__c.Company__c';
import SUBMITTED_AT from '@salesforce/schema/GTM_Assessment_Request__c.Submitted_At__c';

const FIELDS = [
    CONTACT_NAME, ACCOUNT_NAME, REQ_NAME, COMPANY_FIELD, SUBMITTED_AT,
    ...ANSWER_FIELDS
];

// Field identity (which twelve fields exist to read at all) now comes from
// the shared ANSWER_FIELDS list (c/gtmAssessmentAnswerFields) -- the same
// single source of truth c-gtm-assessment-detail's "Prospect's Answers"
// section and c-gtm-readout-workspace's Readout/Conduit gate both build on.
// This file supplies only the presentational half: a stable `key` and the
// prospect-facing `question` wording, looked up by `fieldApiName` against
// ANSWER_FIELDS below, in this component's own display order (which
// intentionally differs from ANSWER_FIELDS's declaration order --
// Target_Platform__c leads here, matching the routing step's "what are you
// moving to" question).
const ANSWER_FIELD_BY_API_NAME = new Map(ANSWER_FIELDS.map((field) => [field.fieldApiName, field]));

/**
 * The question list this component renders, and its ONLY source of truth for
 * "what questions exist" here.
 *
 * KNOWN, DOCUMENTED GAP (see docs/architecture/gtm-readout-workspace.md,
 * "Preview modal — answers-only redesign"): `gtmAssessmentQuestionnaire`
 * (the live intake form) asks up to ~23 questions per respondent -- 8 scored
 * readiness slots (dynamically branched per source/target pair via
 * `GtmAssessmentInstrument`/`gtmPredicate.resolveSlots`, no fixed key), 6
 * complexity dimensions (also pack-adapted), and up to 9 supplement
 * questions (scored + free-text, also pack-resolved) -- NONE of which are
 * persisted as individually-addressable fields on
 * `GTM_Assessment_Request__c`. Only their aggregate score is stored. There
 * is therefore no way for this (or any) component to preview those 23
 * questions' individual answers; only the fields below actually exist to
 * read.
 *
 * What IS stored, and what this list renders, is exactly the field set
 * `c-gtm-assessment-detail`'s own "Prospect's Answers" section already
 * reads (the shared `ANSWER_FIELDS`) -- the eleven BD-context fields
 * (ADR-0008 section 5, `gtmAssessmentQuestionnaire.BD_CONTEXT_FIELDS`) plus
 * `Target_Platform__c` (the routing step's "what are you moving to"
 * answer). Question wording below is carried verbatim from
 * `gtmAssessmentQuestionnaire.BD_CONTEXT_FIELDS` so a rep sees the same
 * vocabulary the prospect was actually asked, not a re-paraphrase.
 */
const QUESTIONS = [
    { key: 'targetPlatform', fieldApiName: 'Target_Platform__c', question: 'What platform are you moving to?' },
    { key: 'painPoints', fieldApiName: 'Pain_Points__c', question: "What's not working with your current platform?" },
    { key: 'migrationGoals', fieldApiName: 'Migration_Goals__c', question: 'What do you need from the new platform?' },
    { key: 'keyIntegrations', fieldApiName: 'Key_Integrations__c', question: 'Key integrations that must stay connected' },
    { key: 'successCriteria', fieldApiName: 'Success_Criteria__c', question: 'How will you know the migration succeeded?' },
    { key: 'budgetRange', fieldApiName: 'Budget_Range__c', question: 'Budget range' },
    { key: 'contactCount', fieldApiName: 'Contact_Count__c', question: 'Contact / lead database size' },
    { key: 'monthlySendVolume', fieldApiName: 'Monthly_Send_Volume__c', question: 'Monthly email send volume' },
    { key: 'internalTeamSize', fieldApiName: 'Internal_Team_Size__c', question: 'Internal team for this migration' },
    { key: 'executiveSponsorship', fieldApiName: 'Executive_Sponsorship__c', question: 'Executive sponsorship' },
    { key: 'decisionMakers', fieldApiName: 'Decision_Makers__c', question: 'Who approves the final decision?' },
    { key: 'urgencyDriver', fieldApiName: 'Urgency_Driver__c', question: "What's driving the timeline?" }
].map((q) => ({ key: q.key, field: ANSWER_FIELD_BY_API_NAME.get(q.fieldApiName), question: q.question }));

const NOT_ANSWERED = 'Not answered';

/**
 * Read-only "answers only" preview of a prospect's submitted assessment
 * answers (issue-gtm-readout-workspace, "Preview the assessment" modal
 * redesign).
 *
 * Renders every question in QUESTIONS with whatever answer state it
 * actually has -- the prospect's submitted value if present, or a "Not
 * answered" placeholder if blank. This covers "not yet submitted at all"
 * and "submitted but skipped some questions" uniformly: both simply render
 * as "Not answered" per-question, with no separate reminder-message
 * substitution.
 *
 * Purely presentational: no write actions, no submit button, no
 * localStorage/draft calls of any kind. Read-only `getRecord` wire only.
 */
export default class GtmAssessmentAnswersPreview extends LightningElement {
    /** GTM_Assessment_Request__c Id. Same identifying prop the modal (and,
     *  before it, gtmReadoutWorkspace) already has in hand. */
    @api recordId;

    _record = null;
    _error = null;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        if (data) {
            this._record = data;
            this._error = null;
        } else if (error) {
            this._error = error;
            this._record = null;
        }
    }

    get isLoading() {
        return !this._record && !this._error && !!this.recordId;
    }

    get hasError() {
        return !!this._error;
    }

    get hasNoRecordId() {
        return !this.recordId;
    }

    _fv(field) {
        return getFieldValue(this._record, field);
    }

    get contactName() {
        return this._fv(CONTACT_NAME) || this._fv(REQ_NAME) || 'The contact';
    }

    get accountName() {
        return this._fv(ACCOUNT_NAME) || this._fv(COMPANY_FIELD) || 'their company';
    }

    get isSubmitted() {
        return !!this._fv(SUBMITTED_AT);
    }

    get questions() {
        if (!this._record) {
            return [];
        }
        return QUESTIONS.map((q) => {
            const raw = this._fv(q.field);
            const answered = raw !== null && raw !== undefined && String(raw).trim() !== '';
            return {
                key: q.key,
                question: q.question,
                answer: answered ? raw : NOT_ANSWERED,
                answered,
                cls: answered ? 'gaap-answer' : 'gaap-answer gaap-answer--blank'
            };
        });
    }
}
