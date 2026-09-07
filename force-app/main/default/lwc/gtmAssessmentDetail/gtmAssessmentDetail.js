import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

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

const FIELDS = [
    NAME_FIELD, STATUS_FIELD,
    CFG_ID, CFG_NAME, CFG_URL,
    ACCOUNT_ID, ACCOUNT_NAME,
    OPP_ID, OPP_NAME,
    CONTACT_ID, CONTACT_NAME, CONTACT_EMAIL,
    PLATFORM_FIELD, ENV_SIZE_FIELD, TIMELINE_FIELD, CONTEXT_FIELD,
    REQ_NAME, REQ_EMAIL, COMPANY_FIELD, ROLE_FIELD, SOURCE_FIELD
];

export default class GtmAssessmentDetail extends LightningElement {
    @api recordId;

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
    get cfgRecordUrl()  {
        const id = this._fv(CFG_ID);
        return id ? `/lightning/r/GTM_Saved_Configuration__c/${id}/view` : '#';
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
}
