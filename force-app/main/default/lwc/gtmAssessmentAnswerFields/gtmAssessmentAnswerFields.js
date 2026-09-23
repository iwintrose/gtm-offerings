/**
 * Single source of truth for "which GTM_Assessment_Request__c fields count
 * as the prospect having actually answered the assessment" -- the twelve
 * instrument answer fields "Prospect's Answers" (c-gtm-assessment-detail),
 * the Readout/Conduit-tab gate (c-gtm-readout-workspace), and the
 * "Preview the assessment" modal (c-gtm-assessment-answers-preview) all
 * read off the same record.
 *
 * Extracted (issue-readout-navigation-consolidation-03-docs-and-answer-
 * fields-dedup) from three independent copies of the same field list --
 * see docs/architecture/gtm-readout-workspace.md, "Round 3 -- ... 3 & 4"
 * for the full history of the isSubmitted AND-gate this list feeds
 * (Submitted_At__c must be set AND at least one of these fields must be
 * non-blank; neither signal alone is sufficient). This module supplies
 * only the "at least one answer field is non-blank" half -- callers
 * combine it with their own Submitted_At__c check.
 *
 * Pure client-side (LWC) concern. Ticket 02
 * (readout-navigation-consolidation-02-server-completeness-gate) extracts
 * an equivalent "meaningful answers" check server-side, in Apex
 * (GtmAssessmentRequestController.hasMeaningfulAnswers(RequestInput)) --
 * different language, different data shape, no shared-code mechanism with
 * this module. Do not unify across languages.
 *
 * Follows the gtmNavigate/ convention for a plain-JS (non-visual) shared
 * LWC module: no .html/.css (renders nothing), own __tests__/,
 * isExposed=false.
 */
import { getFieldValue } from 'lightning/uiRecordApi';

import PAIN_POINTS      from '@salesforce/schema/GTM_Assessment_Request__c.Pain_Points__c';
import MIGRATION_GOALS  from '@salesforce/schema/GTM_Assessment_Request__c.Migration_Goals__c';
import SUCCESS_CRITERIA from '@salesforce/schema/GTM_Assessment_Request__c.Success_Criteria__c';
import DECISION_MAKERS  from '@salesforce/schema/GTM_Assessment_Request__c.Decision_Makers__c';
import BUDGET_RANGE     from '@salesforce/schema/GTM_Assessment_Request__c.Budget_Range__c';
import URGENCY_DRIVER   from '@salesforce/schema/GTM_Assessment_Request__c.Urgency_Driver__c';
import KEY_INTEGRATIONS from '@salesforce/schema/GTM_Assessment_Request__c.Key_Integrations__c';
import EXEC_SPONSORSHIP from '@salesforce/schema/GTM_Assessment_Request__c.Executive_Sponsorship__c';
import TARGET_PLATFORM  from '@salesforce/schema/GTM_Assessment_Request__c.Target_Platform__c';
import TEAM_SIZE        from '@salesforce/schema/GTM_Assessment_Request__c.Internal_Team_Size__c';
import SEND_VOLUME      from '@salesforce/schema/GTM_Assessment_Request__c.Monthly_Send_Volume__c';
import CONTACT_COUNT    from '@salesforce/schema/GTM_Assessment_Request__c.Contact_Count__c';

/**
 * The instrument's own answer fields, in a defined, stable order. Field
 * identity only (schema field references) -- no presentational labels or
 * question text live here; consumers that need those (e.g.
 * c-gtm-assessment-answers-preview's prospect-facing question wording)
 * keep their own key/question pairing, looked up by `fieldApiName` against
 * this list.
 */
export const ANSWER_FIELDS = [
    PAIN_POINTS, MIGRATION_GOALS, SUCCESS_CRITERIA, DECISION_MAKERS,
    BUDGET_RANGE, URGENCY_DRIVER, KEY_INTEGRATIONS, EXEC_SPONSORSHIP,
    TARGET_PLATFORM, TEAM_SIZE, SEND_VOLUME, CONTACT_COUNT
];

/**
 * True when at least one of `fields` (default ANSWER_FIELDS) is non-blank
 * on `record` -- the "the prospect has actually answered" signal. This is
 * one half of the isSubmitted AND-gate each gate consumer builds for
 * itself by also checking its own Submitted_At__c field value; this helper
 * intentionally does not know about Submitted_At__c at all.
 *
 * @param {Object} record  A wired getRecord result (or null/undefined).
 * @param {Array}  fields  Field references to check; defaults to
 *                         ANSWER_FIELDS.
 */
export function hasMeaningfulAnswers(record, fields = ANSWER_FIELDS) {
    return fields.some((field) => !!getFieldValue(record, field));
}
