import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import generateRepDirectShareLink from '@salesforce/apex/GtmSavedConfigurationController.generateRepDirectShareLink';
import PRESENTATION_STAGE_FIELD from '@salesforce/schema/GTM_Saved_Configuration__c.Presentation_Stage__c';
import OFFERING_FIELD from '@salesforce/schema/GTM_Saved_Configuration__c.Offering__c';
import GENERATED_URL_FIELD from '@salesforce/schema/GTM_Saved_Configuration__c.Generated_URL__c';

const FIELDS = [PRESENTATION_STAGE_FIELD, OFFERING_FIELD, GENERATED_URL_FIELD];

/**
 * "Share with prospect" -- the questionnaire-mount and share-link action
 * for a pageless, rep-initiated assessment (Presentation_Stage__c =
 * 'Rep_Direct', see GtmSavedConfigurationController.createRepDirectAssessment()).
 *
 * PRIMARY entry point (post QA correction, see TEST_FAILURES.log for
 * rep-initiated-assessment-no-page-2-share-and-continue): mounted straight
 * after creation inside the modal gtmReadoutsOverview renders on the
 * GTM_Assessments tab (driven by "c__repDirectId" URL state, written by
 * gtmOverview's handleRepDirectCreated). This component's own logic did not
 * change for that move -- only its container did.
 *
 * SECONDARY entry point, kept deliberately: still placed on the
 * GTM_Saved_Configuration__c record page's Activity tab (originally the
 * Architect's placement call for this issue, before the stakeholder's
 * later correction) for a rep who lands on the record some other way --
 * e.g. via the Pages tab or a direct record link -- rather than through the
 * "New assessment (no page)" picker. A GTM_Saved_Configuration__c record
 * itself is still not the flow's front door, but it remains a legitimate
 * secondary path back into the same action once you are already looking at
 * the record.
 *
 * Renders nothing at all for any record that is not Rep_Direct -- this
 * component has exactly one job, in either context.
 *
 * TWO INDEPENDENT ACTIONS, NEITHER REQUIRES THE OTHER:
 *   - "Answer some questions now" mounts c-gtm-assessment-questionnaire
 *     inline, in the SAME internal/rep context this page already is (no
 *     guest concepts apply here) -- it autosaves via the existing
 *     GtmAssessmentDraftController.saveDraft(), exactly as a prospect's
 *     session would, and this component listens for the `draftsaved` event
 *     to learn the resulting resume token.
 *   - "Share with prospect" calls generateRepDirectShareLink(), optionally
 *     carrying whatever resume token the rep's own pre-fill minted, so the
 *     prospect picks up exactly where the rep left off (or from scratch if
 *     the rep answered nothing).
 */
export default class GtmRepDirectShare extends LightningElement {
    @api recordId;

    _offeringKey = '';
    _hasExistingUrl = false;

    generatedUrl = '';
    password = '';
    sharing = false;
    shareError = '';

    showPrefill = false;
    _resumeToken = '';

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data }) {
        if (!data) return;
        this._presentationStage = getFieldValue(data, PRESENTATION_STAGE_FIELD);
        this._offeringKey = getFieldValue(data, OFFERING_FIELD) || '';
        this._hasExistingUrl = !!getFieldValue(data, GENERATED_URL_FIELD);
    }

    _presentationStage = '';

    get isRepDirect() {
        return this._presentationStage === 'Rep_Direct';
    }

    get offeringKey() {
        return this._offeringKey;
    }

    get hasShareLink() {
        return !!this.generatedUrl;
    }

    get shareButtonLabel() {
        if (this.sharing) return 'Generating…';
        return this._hasExistingUrl ? 'Regenerate share link' : 'Share with prospect';
    }

    get prefillButtonLabel() {
        return this.showPrefill ? 'Hide questionnaire' : 'Answer some questions now';
    }

    get resumeToken() {
        return this._resumeToken;
    }

    handleTogglePrefill() {
        this.showPrefill = !this.showPrefill;
    }

    /**
     * A rep pre-filling answers internally mints/updates the SAME server
     * draft a prospect resuming from the share link would -- there is no
     * separate "rep pre-fill" mechanism, per the Architect's investigation
     * (task-scope §2.B): GtmAssessmentDraftController is already agnostic
     * about who is typing.
     */
    handleDraftSaved(event) {
        const token = event && event.detail && event.detail.resumeToken;
        if (token) {
            this._resumeToken = token;
        }
    }

    async handleShare() {
        if (this.sharing) return;
        this.sharing = true;
        this.shareError = '';
        try {
            const result = await generateRepDirectShareLink({
                recordId: this.recordId,
                resumeToken: this._resumeToken || ''
            });
            this.generatedUrl = (result && result.generatedUrl) || '';
            this.password = (result && result.password) || '';
            this._hasExistingUrl = true;
        } catch (e) {
            this.shareError =
                (e && e.body && e.body.message) || 'We could not generate a share link.';
        } finally {
            this.sharing = false;
        }
    }
}
