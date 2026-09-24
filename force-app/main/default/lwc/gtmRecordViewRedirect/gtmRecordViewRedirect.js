/**
 * App-level View override target (docs/architecture/gtm-row-open-and-links.md).
 * Placed on a minimal record flexipage that the GTM Offerings app assigns as the
 * View action for GTM_Saved_Configuration__c and GTM_Assessment_Request__c. It
 * confirms the record is accessible, then navigates (replace, so Back does not
 * bounce) to the working view: Pages for a link, Assessments for an assessment.
 * The destination is a tab page, never a record view, so it cannot loop.
 */
import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import { engagementLinkRef, assessmentRef } from 'c/gtmNavigate';

export const SC_OBJECT = 'GTM_Saved_Configuration__c';
export const AR_OBJECT = 'GTM_Assessment_Request__c';

export default class GtmRecordViewRedirect extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    error = false;
    _done = false;

    get fields() {
        return this.objectApiName ? [`${this.objectApiName}.Id`] : undefined;
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$fields' })
    wiredRecord({ data, error }) {
        if (error) {
            this.error = true;
            return;
        }
        if (!data || this._done) return;
        let ref = null;
        if (this.objectApiName === SC_OBJECT) ref = engagementLinkRef(this.recordId);
        else if (this.objectApiName === AR_OBJECT) ref = assessmentRef(this.recordId);
        if (!ref) return; // unknown object: never redirect
        this._done = true;
        this[NavigationMixin.Navigate](ref, true);
    }

    get showSpinner() {
        return !this.error;
    }
}
