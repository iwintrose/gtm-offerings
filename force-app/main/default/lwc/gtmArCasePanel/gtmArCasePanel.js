import { LightningElement, api, wire } from 'lwc';
import getCaseForRequest from '@salesforce/apex/GtmArCasePanelController.getCaseForRequest';

export default class GtmArCasePanel extends LightningElement {
    @api recordId;
    caseData;
    error;

    @wire(getCaseForRequest, { requestId: '$recordId' })
    wiredCase({ data, error }) {
        if (data) {
            this.caseData = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.caseData = undefined;
        }
    }

    get hasCase() {
        return !!this.caseData;
    }

    get caseSubject() {
        return this.caseData?.subject;
    }

    get caseStatus() {
        return this.caseData?.status;
    }

    get caseCreatedDate() {
        return this.caseData?.createdDate;
    }
}
