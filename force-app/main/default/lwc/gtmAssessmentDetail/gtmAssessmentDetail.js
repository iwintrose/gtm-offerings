import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { openEngagementLink, openAssessment } from 'c/gtmNavigate';
import { hasMeaningfulAnswers as computeHasMeaningfulAnswers } from 'c/gtmAssessmentAnswerFields';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getReadoutByRequest from '@salesforce/apex/GtmReadoutController.getReadoutByRequest';

import NAME_FIELD        from '@salesforce/schema/GTM_Assessment_Request__c.Name';
import STATUS_FIELD      from '@salesforce/schema/GTM_Assessment_Request__c.Status__c';
import CFG_ID            from '@salesforce/schema/GTM_Assessment_Request__c.Saved_Configuration__c';
import CFG_NAME          from '@salesforce/schema/GTM_Assessment_Request__c.Saved_Configuration__r.Name';
import CFG_URL           from '@salesforce/schema/GTM_Assessment_Request__c.Saved_Configuration__r.Generated_URL__c';
import ACCOUNT_ID        from '@salesforce/schema/GTM_Assessment_Request__c.Account__c';
import ACCOUNT_NAME      from '@salesforce/schema/GTM_Assessment_Request__c.Account__r.Name';
import OPP_ID            from '@salesforce/schema/GTM_Assessment_Request__c.Opportunity__c';
import OPP_NAME          from '@salesforce/schema/GTM_Assessment_Request__c.Opportunity__r.Name';
import CONTACT_ID        from '@salesforce/schema/GTM_Assessment_Request__c.Contact__c';
import CONTACT_NAME      from '@salesforce/schema/GTM_Assessment_Request__c.Contact__r.Name';
import CONTACT_EMAIL     from '@salesforce/schema/GTM_Assessment_Request__c.Contact__r.Email';
import PLATFORM_FIELD    from '@salesforce/schema/GTM_Assessment_Request__c.Current_Platform__c';
import ENV_SIZE_FIELD    from '@salesforce/schema/GTM_Assessment_Request__c.Environment_Size__c';
import TIMELINE_FIELD    from '@salesforce/schema/GTM_Assessment_Request__c.Timeline__c';
import CONTEXT_FIELD     from '@salesforce/schema/GTM_Assessment_Request__c.Context__c';
import REQ_NAME          from '@salesforce/schema/GTM_Assessment_Request__c.Requester_Name__c';
import REQ_EMAIL         from '@salesforce/schema/GTM_Assessment_Request__c.Requester_Email__c';
import COMPANY_FIELD     from '@salesforce/schema/GTM_Assessment_Request__c.Company__c';
import ROLE_FIELD        from '@salesforce/schema/GTM_Assessment_Request__c.Role__c';
import SOURCE_FIELD      from '@salesforce/schema/GTM_Assessment_Request__c.Source__c';
import SUBMITTED_AT      from '@salesforce/schema/GTM_Assessment_Request__c.Submitted_At__c';
import PAIN_POINTS       from '@salesforce/schema/GTM_Assessment_Request__c.Pain_Points__c';
import MIGRATION_GOALS   from '@salesforce/schema/GTM_Assessment_Request__c.Migration_Goals__c';
import SUCCESS_CRITERIA  from '@salesforce/schema/GTM_Assessment_Request__c.Success_Criteria__c';
import DECISION_MAKERS   from '@salesforce/schema/GTM_Assessment_Request__c.Decision_Makers__c';
import BUDGET_RANGE      from '@salesforce/schema/GTM_Assessment_Request__c.Budget_Range__c';
import URGENCY_DRIVER    from '@salesforce/schema/GTM_Assessment_Request__c.Urgency_Driver__c';
import KEY_INTEGRATIONS  from '@salesforce/schema/GTM_Assessment_Request__c.Key_Integrations__c';
import EXEC_SPONSORSHIP  from '@salesforce/schema/GTM_Assessment_Request__c.Executive_Sponsorship__c';
import TARGET_PLATFORM   from '@salesforce/schema/GTM_Assessment_Request__c.Target_Platform__c';
import TEAM_SIZE         from '@salesforce/schema/GTM_Assessment_Request__c.Internal_Team_Size__c';
import SEND_VOLUME       from '@salesforce/schema/GTM_Assessment_Request__c.Monthly_Send_Volume__c';
import CONTACT_COUNT     from '@salesforce/schema/GTM_Assessment_Request__c.Contact_Count__c';
import OFFERING_KEY      from '@salesforce/schema/GTM_Assessment_Request__c.Offering_Key__c';

const FIELDS = [
    NAME_FIELD, STATUS_FIELD,
    CFG_ID, CFG_NAME, CFG_URL,
    ACCOUNT_ID, ACCOUNT_NAME,
    OPP_ID, OPP_NAME,
    CONTACT_ID, CONTACT_NAME, CONTACT_EMAIL,
    PLATFORM_FIELD, ENV_SIZE_FIELD, TIMELINE_FIELD, CONTEXT_FIELD,
    REQ_NAME, REQ_EMAIL, COMPANY_FIELD, ROLE_FIELD, SOURCE_FIELD,
    SUBMITTED_AT, PAIN_POINTS, MIGRATION_GOALS, SUCCESS_CRITERIA,
    DECISION_MAKERS, BUDGET_RANGE, URGENCY_DRIVER, KEY_INTEGRATIONS,
    EXEC_SPONSORSHIP, TARGET_PLATFORM, TEAM_SIZE, SEND_VOLUME, CONTACT_COUNT,
    OFFERING_KEY
];

export default class GtmAssessmentDetail extends NavigationMixin(LightningElement) {
    @api recordId;

    /**
     * Dual-mode forward action (issue-102-1-engagement-links-landing, D7 +
     * acceptance criterion 4). Two real mount shapes, confirmed by grep
     * against current main rather than assumed (WORKTREE_SCOPE's own
     * instruction):
     *   - Tabset context with a sibling Readout tab (gtmReadoutWorkspace):
     *     the host sets tabset-mode and listens for `openreadout` to swap
     *     its own active tab -- no page navigation, the readout is one tab
     *     over in the same component tree.
     *   - Standalone context (GTM_Assessment_Request_Record_Page flexipage,
     *     and any other mount that does NOT opt into tabset-mode, e.g.
     *     gtmRepLinkFinder's pre-workspace inline render, or
     *     gtmAssessmentSubmissionView): no sibling tab to swap to, so this
     *     component navigates itself via NavigationMixin (the same
     *     c/gtmNavigate.openAssessment utility every other "go to the
     *     assessment workspace" link in this app already uses). This
     *     component has no readout Id on hand client-side -- unlike
     *     gtmReadoutWorkspace (which is handed one as an @api prop),
     *     GTM_Assessment_Request__c carries no forward lookup to
     *     GTM_Readout__c, only the reverse GTM_Readout__c.Assessment_Request__c
     *     relationship exists -- so handleOpenReadout resolves it first via
     *     GtmReadoutController.getReadoutByRequest (the same lookup
     *     gtmReadoutReview's own record-page fallback already uses; reused
     *     rather than adding a new Apex method), then navigates with
     *     focusReadout=true so the destination workspace lands on the
     *     Readout tab instead of its usual Assessment-tab default (see
     *     c/gtmNavigate.assessmentRef's own doc comment on
     *     c__focusReadoutTab).
     */
    @api tabsetMode = false;

    _record = null;
    _error  = null;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        if (data)  { this._record = data; this._error = null; }
        else if (error) { this._error = error; this._record = null; }
    }

    get isLoading() { return !this._record && !this._error; }
    get hasError()  { return !!this._error; }

    _fv(field) { return getFieldValue(this._record, field); }

    // ---- header
    get arName()      { return this._fv(NAME_FIELD) || ''; }
    get status()      { return this._fv(STATUS_FIELD) || ''; }
    get statusClass() {
        const slug = (this.status || '').toLowerCase().replace(/\s+/g, '-');
        return `status-badge status--${slug}`;
    }
    get reqName()     { return this._fv(REQ_NAME) || ''; }
    get reqEmail()    { return this._fv(REQ_EMAIL) || ''; }
    get company()     { return this._fv(COMPANY_FIELD) || ''; }
    get role()        { return this._fv(ROLE_FIELD) || ''; }

    // ---- engagement link (saved config)
    get hasCfg()        { return !!this._fv(CFG_ID); }
    get cfgName()       { return this._fv(CFG_NAME) || ''; }
    get cfgProspectUrl(){ return this._fv(CFG_URL) || '#'; }
    /** The SC name opens the Pages view of the link, never the SC record page. */
    handleOpenEngagementLink(event) {
        if (event && event.preventDefault) event.preventDefault();
        openEngagementLink(this, this._fv(CFG_ID), this._fv(ACCOUNT_ID), this._fv(CONTACT_ID));
    }

    // ---- account
    get hasAccount()  { return !!this._fv(ACCOUNT_ID); }
    get accountName() { return this._fv(ACCOUNT_NAME) || ''; }
    get accountUrl()  {
        const id = this._fv(ACCOUNT_ID);
        return id ? `/lightning/r/Account/${id}/view` : '#';
    }

    // ---- opportunity
    get hasOpp()  { return !!this._fv(OPP_ID); }
    get oppName() { return this._fv(OPP_NAME) || ''; }
    get oppUrl()  {
        const id = this._fv(OPP_ID);
        return id ? `/lightning/r/Opportunity/${id}/view` : '#';
    }

    // ---- contact
    get hasContact()    { return !!this._fv(CONTACT_ID); }
    get contactName()   { return this._fv(CONTACT_NAME) || ''; }
    get contactEmail()  { return this._fv(CONTACT_EMAIL) || ''; }
    get contactUrl()    {
        const id = this._fv(CONTACT_ID);
        return id ? `/lightning/r/Contact/${id}/view` : '#';
    }

    get hasCrmChain() { return this.hasCfg || this.hasAccount; }

    // ---- assessment details
    get platform()        { return this._fv(PLATFORM_FIELD)  || '—'; }
    get environmentSize() { return this._fv(ENV_SIZE_FIELD)   || '—'; }
    get timeline()        { return this._fv(TIMELINE_FIELD)   || '—'; }
    get context()         { return this._fv(CONTEXT_FIELD)    || ''; }
    get hasContext()      { return !!this._fv(CONTEXT_FIELD); }
    get source()          { return this._fv(SOURCE_FIELD)     || ''; }

    // ---- prospect's submitted answers (issue-gtm-readout-workspace
    // refinement #4) -- these are the raw instrument answers already
    // captured directly on GTM_Assessment_Request__c at submission time
    // (see GtmAssessmentScoring), not a new data source.
    //
    // Bug fix, round 2: a prior round dropped Submitted_At__c from this gate
    // entirely, on the grounds that a timestamp alone doesn't prove real
    // answers exist. True, but that swung too far the other way -- "any one
    // non-blank answer field" alone let a record with just Target_Platform__c
    // filled in (everything else blank) render full readout/Conduit content,
    // which the product owner confirmed live is still "not submitted" in
    // spirit. The gate is now the AND of both signals: the prospect must have
    // actually completed and submitted the form (Submitted_At__c set) AND at
    // least one of the instrument's own answer fields must be non-blank (a
    // sanity check against a stamped-but-empty record). Neither alone is
    // sufficient.
    get hasMeaningfulAnswers() {
        return computeHasMeaningfulAnswers(this._record);
    }

    get isSubmitted() {
        return !!this._fv(SUBMITTED_AT) && this.hasMeaningfulAnswers;
    }

    get notSubmittedMessage() {
        // Prefer the linked Contact's name, then the Requester_Name__c
        // captured at request time (the person who actually filled out the
        // form may not have a CRM Contact record linked yet), and only fall
        // back to the generic "The contact" when neither is present.
        const contact = this.contactName || this.reqName || 'The contact';
        const account = this.accountName || this.company || 'their company';
        return `${contact} at ${account} has not submitted the assessment. Reach out to them to remind them.`;
    }

    get painPoints()       { return this._fv(PAIN_POINTS)      || ''; }
    get hasPainPoints()     { return !!this._fv(PAIN_POINTS); }
    get migrationGoals()   { return this._fv(MIGRATION_GOALS)  || ''; }
    get hasMigrationGoals() { return !!this._fv(MIGRATION_GOALS); }
    get successCriteria()  { return this._fv(SUCCESS_CRITERIA) || ''; }
    get hasSuccessCriteria() { return !!this._fv(SUCCESS_CRITERIA); }
    get decisionMakers()   { return this._fv(DECISION_MAKERS)  || ''; }
    get hasDecisionMakers() { return !!this._fv(DECISION_MAKERS); }
    get budgetRange()      { return this._fv(BUDGET_RANGE)     || '—'; }
    get urgencyDriver()    { return this._fv(URGENCY_DRIVER)   || ''; }
    get hasUrgencyDriver()  { return !!this._fv(URGENCY_DRIVER); }
    get keyIntegrations()  { return this._fv(KEY_INTEGRATIONS) || ''; }
    get hasKeyIntegrations() { return !!this._fv(KEY_INTEGRATIONS); }
    get execSponsorship()  { return this._fv(EXEC_SPONSORSHIP) || '—'; }
    get targetPlatform()   { return this._fv(TARGET_PLATFORM)  || '—'; }
    get teamSize()         { return this._fv(TEAM_SIZE)        || '—'; }
    get sendVolume()       { return this._fv(SEND_VOLUME)      || '—'; }
    get contactCount()     { return this._fv(CONTACT_COUNT)    || '—'; }

    get hasAnyAnswers() {
        return this.isSubmitted;
    }

    // ---- forward action: "Open the readout" (D7 -- never "Generate", the
    // Draft readout already exists by the time a BD reaches this screen).
    // Shown once the assessment is genuinely submitted -- before that there
    // is nothing for the action to open (no request exists pre-submission).
    get showOpenReadoutAction() {
        return this.isSubmitted;
    }

    handleOpenReadout() {
        if (this.tabsetMode) {
            this.dispatchEvent(new CustomEvent('openreadout', {
                bubbles: true,
                composed: true,
                detail: { assessmentRequestId: this.recordId }
            }));
            return;
        }
        const recordId = this.recordId;
        const offeringKey = this._fv(OFFERING_KEY);
        // D7: the Draft readout already exists by the time a BD reaches this
        // screen (created inside the prospect's own submit transaction), so
        // this lookup should always resolve -- but if it errors, still
        // navigate to the assessment workspace rather than stranding the
        // click with no visible effect.
        getReadoutByRequest({ requestId: recordId })
            .then((summary) => {
                const readoutId = summary && summary.id ? summary.id : null;
                openAssessment(this, recordId, readoutId, offeringKey, true);
            })
            .catch(() => {
                openAssessment(this, recordId, null, offeringKey);
            });
    }
}
