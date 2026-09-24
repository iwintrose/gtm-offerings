import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import GtmAssessmentPreviewModal from 'c/gtmAssessmentPreviewModal';
import generateReadoutForRequest from '@salesforce/apex/GtmReadoutController.generateReadoutForRequest';
import getOfferingHasConduit from '@salesforce/apex/GtmAssessmentRequestController.getOfferingHasConduit';

import SUBMITTED_AT  from '@salesforce/schema/GTM_Assessment_Request__c.Submitted_At__c';
import CONTACT_NAME  from '@salesforce/schema/GTM_Assessment_Request__c.Contact__r.Name';
import REQ_NAME       from '@salesforce/schema/GTM_Assessment_Request__c.Requester_Name__c';
import ACCOUNT_NAME  from '@salesforce/schema/GTM_Assessment_Request__c.Account__r.Name';
import COMPANY_FIELD from '@salesforce/schema/GTM_Assessment_Request__c.Company__c';
import CFG_ID        from '@salesforce/schema/GTM_Assessment_Request__c.Saved_Configuration__c';
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

// The instrument's own answer fields -- same list c-gtm-assessment-detail's
// "Prospect's Answers" section renders and gates on. Kept in sync with that
// component's own ANSWER_FIELDS; see its isSubmitted doc comment for why
// Submitted_At__c alone is not used as the gate.
const ANSWER_FIELDS = [
    PAIN_POINTS, MIGRATION_GOALS, SUCCESS_CRITERIA, DECISION_MAKERS,
    BUDGET_RANGE, URGENCY_DRIVER, KEY_INTEGRATIONS, EXEC_SPONSORSHIP,
    TARGET_PLATFORM, TEAM_SIZE, SEND_VOLUME, CONTACT_COUNT
];

const REQUEST_FIELDS = [
    SUBMITTED_AT, CONTACT_NAME, REQ_NAME, ACCOUNT_NAME, COMPANY_FIELD, CFG_ID,
    ...ANSWER_FIELDS
];

/**
 * The shared 3-tab (Assessment / Readout / Conduit) content a rep sees in
 * place of the list/columns view after selecting a card in
 * gtmReadoutsOverview or a link/readout action in gtmRepLinkFinder
 * (issue-gtm-readout-workspace, refined per direct product-owner feedback
 * after a live click-through). Rendered INLINE by the parent -- swapped in
 * for the list/columns content, not opened as a modal or navigated to as a
 * page. See docs/architecture/gtm-readout-workspace.md for the full
 * contract this file implements.
 *
 * The parent owns the "which one is selected" state and is responsible for
 * conditionally rendering this component in place of its own list/columns
 * markup; this component only knows how to render itself and to ask to be
 * dismissed (the "back" event below) -- it never manages its own visibility.
 *
 * The Preview tab was removed (refinement #6): a "Preview the assessment"
 * button sits above the tabset instead, opening as a MODAL (see
 * gtmAssessmentPreviewModal) -- this is the one exception to "everything else
 * in this workspace stays inline". This section used to also duplicate an
 * Assessment Link/Password box, but that box read the exact same
 * Generated_URL__c/password as gtmRepLinkFinder's own always-visible
 * Engagement Link box a few inches away on screen -- same URL, same
 * password, same Apex. It was removed here (issue-pages-preview-fixes);
 * gtmRepLinkFinder's box is the single source of that UI now. The request's
 * own Submitted_At__c / Contact__r.Name / Account__r.Name fields (read via
 * the standard UI API, the same mechanism c-gtm-assessment-detail already
 * uses) are what drive the Readout tab's submitted-gate and its
 * not-submitted message.
 */
export default class GtmReadoutWorkspace extends LightningElement {
    /** Required -- GTM_Assessment_Request__c Id. Both callers always have
     *  this (gtmReadoutsOverview's ReadoutSummary.assessmentRequestId,
     *  gtmRepLinkFinder's selectedLinkRequestId). */
    @api assessmentRequestId;

    /** Optional -- GTM_Readout__c Id, null until a readout exists. When
     *  supplied, the Readout tab (once reachable -- see isSubmitted below)
     *  shows it directly rather than the "Generate Readout" prompt. */
    @api readoutId = null;

    /** Optional -- offering key for the link section's inline
     *  "Preview the assessment" c-gtm-configurator embed. Both callers
     *  already have this on hand (gtmRepLinkFinder's
     *  selectedLinkOfferingKey / the link row's own offering) so it is
     *  passed straight through rather than re-resolved here. */
    @api offeringKey = '';

    /**
     * Optional (issue-102-1-engagement-links-landing, D7 + acceptance
     * criterion 4) -- when set to 'readout', overrides the initial
     * activeTabValue below so a fresh mount lands directly on the Readout
     * tab instead of refinement #3's usual Assessment default. This is
     * deliberately opt-in and additive, not a change to refinement #3's own
     * default: every existing caller (gtmReadoutsOverview's row click,
     * gtmRepLinkFinder's "View readout") leaves this unset and keeps landing
     * on Assessment first regardless of readoutId, exactly as refinement #3
     * specifies. Only c-gtm-assessment-detail's "Open the readout" forward
     * action -- an explicit, single-purpose "take me to the readout" click
     * distinct from every origin refinement #3 enumerates -- opts into this.
     * Consulted once, in connectedCallback; a later change to this prop on
     * an already-mounted instance does not re-force the tab (matches
     * refinement #3's own "the default only governs the tab active on first
     * render" rule).
     */
    @api initialTab = '';

    /** Default landing tab is always Assessment now (refinement #3) --
     *  a rep opening the workspace, whether or not a readout already
     *  exists, lands here first rather than jumping straight to Readout --
     *  UNLESS initialTab explicitly requests 'readout' (see its doc comment
     *  above), set in connectedCallback below. */
    @track activeTabValue = 'assessment';
    @track hasConduit = false;
    @track generatingReadout = false;
    @track loadError = '';

    /** Tracks the readout id locally so "Generate Readout" can flip this
     *  workspace over to the Readout tab, showing the new readout, without
     *  the parent needing to re-render it with a different readoutId. */
    _currentReadoutId = null;

    _requestRecord = null;

    connectedCallback() {
        this._currentReadoutId = this.readoutId || null;
        if (this.initialTab === 'readout' && this._currentReadoutId) {
            this.activeTabValue = 'readout';
        }

        getOfferingHasConduit({ assessmentRequestId: this.assessmentRequestId })
            .then((result) => { this.hasConduit = !!result; })
            .catch(() => {
                // Fails closed -- see GtmAssessmentRequestController.getOfferingHasConduit's
                // own doc comment. The Conduit tab simply does not render.
                this.hasConduit = false;
            });
    }

    // ------------------------------------------------------- request wire
    // Same standard UI API mechanism c-gtm-assessment-detail already uses
    // for the fields it needs -- no new Apex.
    @wire(getRecord, { recordId: '$assessmentRequestId', fields: REQUEST_FIELDS })
    wiredRequest({ data }) {
        if (data) {
            this._requestRecord = data;
            // Same mechanism gtmRepLinkFinder's own "Preview the link" uses
            // (see setCfgIdParam's doc comment there): c-gtm-configurator has
            // no @api way to be told which saved record to render -- it only
            // ever reads "?cfgId=" off the real browser URL, once, in its own
            // connectedCallback. Without this, the preview embed here would
            // show the generic unfilled template instead of the specific
            // configuration actually sent to this prospect.
            this.setCfgIdParam(this.cfgId);
        }
    }

    // Bug fix, round 2: requiring "at least one non-blank answer field" alone
    // (with Submitted_At__c dropped from the gate entirely) let a record with
    // only one field filled in -- e.g. just Target_Platform__c, everything
    // else blank -- still unlock full Readout/Conduit content, which the
    // product owner confirmed live is still "not submitted" in spirit. The
    // gate is now the AND of both signals: Submitted_At__c must be set (the
    // prospect actually completed and submitted the form) AND at least one
    // instrument answer field must be non-blank (a sanity check against a
    // stamped-but-empty record). Matches c-gtm-assessment-detail's own gate
    // exactly (independent getters over the same fields, not shared code --
    // see that component's isSubmitted doc comment).
    get hasMeaningfulAnswers() {
        return ANSWER_FIELDS.some((field) => !!getFieldValue(this._requestRecord, field));
    }

    get isSubmitted() {
        return !!getFieldValue(this._requestRecord, SUBMITTED_AT) && this.hasMeaningfulAnswers;
    }

    get contactNameForRequest() {
        // Prefer the linked Contact's name, then the Requester_Name__c
        // captured at request time (the person who submitted the form may
        // not have a CRM Contact record linked yet), and only fall back to
        // the generic "The contact" when neither is present.
        return (
            getFieldValue(this._requestRecord, CONTACT_NAME) ||
            getFieldValue(this._requestRecord, REQ_NAME) ||
            'The contact'
        );
    }

    get accountNameForRequest() {
        return (
            getFieldValue(this._requestRecord, ACCOUNT_NAME) ||
            getFieldValue(this._requestRecord, COMPANY_FIELD) ||
            'their company'
        );
    }

    get notSubmittedMessage() {
        return `${this.contactNameForRequest} at ${this.accountNameForRequest} has not submitted the assessment. Reach out to them to remind them.`;
    }

    // Conduit-tab note (issue-gtm-readout-workspace, "require genuine
    // completion" round): unlike the Readout tab, Conduit no longer blocks on
    // this gate -- it always renders c-conduit-dashboard when the offering is
    // conduit-eligible. When the assessment has not been submitted, this note
    // is shown above the dashboard as a heads-up, not a replacement for it.
    get notSubmittedNote() {
        return `Note: ${this.contactNameForRequest} at ${this.accountNameForRequest} has not submitted the assessment yet.`;
    }

    get cfgId() {
        return getFieldValue(this._requestRecord, CFG_ID) || '';
    }

    get hasCfg() {
        return !!this.cfgId;
    }

    /** Static now -- the button no longer toggles an inline embed open/shut,
     *  it always opens the modal (see handleTogglePreview below). Kept as a
     *  getter rather than a template literal for parity with the rest of
     *  this file's label getters. */
    get previewToggleLabel() {
        return 'Preview the assessment';
    }

    /** "Preview the assessment" opens as a modal (reversing the prior
     *  inline-toggle design, confirmed live by the product owner) and shows
     *  a read-only "answers only" preview of the prospect's submitted
     *  answers -- see gtmAssessmentPreviewModal and
     *  docs/architecture/gtm-readout-workspace.md for the final design. */
    async handleTogglePreview() {
        await GtmAssessmentPreviewModal.open({
            size: 'large',
            assessmentRequestId: this.assessmentRequestId,
            offeringKey: this.offeringKey,
            cfgId: this.cfgId
        });
    }

    get hasReadout() {
        return !!this._currentReadoutId;
    }

    get showGenerateReadout() {
        return !this.hasReadout;
    }

    get currentReadoutId() {
        return this._currentReadoutId;
    }

    handleGenerateReadout() {
        if (this.generatingReadout || this.hasReadout) return;
        this.loadError = '';
        this.generatingReadout = true;
        generateReadoutForRequest({ assessmentRequestId: this.assessmentRequestId })
            .then((newReadoutId) => {
                this._currentReadoutId = newReadoutId;
                this.activeTabValue = 'readout';
            })
            .catch((e) => {
                this.loadError = (e && e.body && e.body.message) || 'The readout could not be generated.';
            })
            .finally(() => {
                this.generatingReadout = false;
            });
    }

    handleActiveTabChange(event) {
        this.activeTabValue = event.detail.value;
    }

    /** c-gtm-assessment-detail's "Open the readout" forward action
     *  (issue-102-1-engagement-links-landing, D7 + acceptance criterion 4).
     *  This workspace IS the tabset context that action's dual mode targets
     *  -- it already owns a sibling Readout tab, so opening it is a local
     *  tab swap, never a navigation. Mirrors handleGenerateReadout's own
     *  "flip to the readout tab" line exactly. */
    handleOpenReadoutFromDetail() {
        this.activeTabValue = 'readout';
    }

    /** Mirrors the mockup's back-link pattern: this component never hides
     *  itself, it only asks the parent to -- the parent (gtmReadoutsOverview
     *  or gtmRepLinkFinder) owns the selected/detail state and clears it on
     *  this event, returning to its own list/columns view. */
    handleBack() {
        this.clearCfgIdParam();
        this.dispatchEvent(new CustomEvent('back'));
    }

    disconnectedCallback() {
        this.clearCfgIdParam();
    }

    // ------------------------------------------------------------------ url
    // Mirrors gtmRepLinkFinder's own setCfgIdParam/clearCfgIdParam exactly --
    // same mechanism, same best-effort try/catch, for the same reason (see
    // wiredRequest's comment above).
    setCfgIdParam(recordId) {
        if (!recordId) return;
        try {
            const url = new URL(window.location.href);
            url.searchParams.set('cfgId', recordId);
            window.history.replaceState(null, '', url.toString());
        } catch (e) {
            // best-effort -- see gtmRepLinkFinder's identical comment
        }
    }

    clearCfgIdParam() {
        try {
            const url = new URL(window.location.href);
            url.searchParams.delete('cfgId');
            window.history.replaceState(null, '', url.toString());
        } catch (e) {
            // best-effort -- see gtmRepLinkFinder's identical comment
        }
    }
}
