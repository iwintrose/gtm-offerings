import LightningModal from 'lightning/modal';
import { api } from 'lwc';

/**
 * "Preview the assessment" modal (issue-gtm-readout-workspace).
 *
 * Reverses the prior inline-toggle design: gtmReadoutWorkspace used to render
 * c-gtm-configurator directly below a "Preview the assessment" button, in
 * place. The product owner, confirmed live, wants this specific action to
 * open as a modal instead -- nothing else about the workspace (the tabset,
 * the link/password section itself) changes.
 *
 * Uses the standard lightning/modal base component (LightningModal) --
 * there is no prior `lightning/modal` usage anywhere else in this codebase
 * to follow (confirmed by a repo-wide grep), so this follows the documented
 * base-component contract directly: a component that extends LightningModal,
 * opened via `MyModal.open({...})` from the caller, closed via this.close()/
 * this.dismiss() from inside.
 *
 * FINAL DESIGN (round 4, see docs/architecture/gtm-readout-workspace.md
 * "Preview modal — answers-only redesign"): this used to embed
 * c-gtm-configurator (the prospect-facing marketing/story landing page),
 * which was flagged as showing the wrong content, then investigated
 * embedding c-gtm-assessment-questionnaire directly (the LIVE intake form)
 * and rejected -- it has no read-only mode and writes real drafts/
 * submissions. Per direct product-owner decision, this now embeds
 * c-gtm-assessment-answers-preview: a small, purpose-built, read-only
 * component that renders the actual assessment questions with the
 * prospect's submitted answer (or "Not answered") for each -- neither the
 * marketing page nor the live form.
 */
export default class GtmAssessmentPreviewModal extends LightningModal {
    /** GTM_Assessment_Request__c Id -- the same identifying prop
     *  gtmReadoutWorkspace already has in hand, now passed through so the
     *  answers-only preview can read the request's submitted answer
     *  fields. */
    @api assessmentRequestId = '';

    /** GTM_Saved_Configuration__c-scoped offering key. No longer used by
     *  this modal's own markup (the answers-only preview does not need it),
     *  kept as an accepted prop so gtmReadoutWorkspace's existing
     *  `.open({...})` call site does not need to drop it defensively. */
    @api offeringKey = '';

    /** The saved configuration's own Id. Same note as offeringKey above --
     *  accepted for call-site compatibility, unused by the answers-only
     *  preview. */
    @api cfgId = '';

    handleCloseClick() {
        this.close();
    }
}
