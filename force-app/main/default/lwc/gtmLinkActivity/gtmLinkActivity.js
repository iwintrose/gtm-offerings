import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import CFG_FIELD from '@salesforce/schema/GTM_Assessment_Request__c.Saved_Configuration__c';

const EVENT_ICON = {
    'Page View':      'utility:preview',
    'Form Opened':    'utility:edit_form',
    'Form Submitted': 'utility:success',
    'Drop-off':       'utility:close',
};
const EVENT_VARIANT = {
    'Page View':      'bare',
    'Form Opened':    'bare',
    'Form Submitted': 'success',
    'Drop-off':       'error',
};

export default class GtmLinkActivity extends LightningElement {
    @api recordId;

    /** True when this instance sits on the Engagement Link
     *  (MA_Saved_Configuration__c) record page, where recordId IS the
     *  config id directly -- false (the original placement, on
     *  GTM_Assessment_Request__c) needs one hop through that record's own
     *  Saved_Configuration__c lookup to find it. Two different record
     *  types can't share one @wire(getRecord) call -- fetching
     *  CFG_FIELD (an Assessment Request field) off a Saved Configuration
     *  id would error, not just return nothing -- so the wire below is
     *  only ever given a recordId when this flag says it's safe to. */
    @api parentIsSavedConfiguration = false;

    _configId;
    events = [];
    isLoading = true;
    hasError = false;

    connectedCallback() {
        if (this.parentIsSavedConfiguration) {
            this._configId = this.recordId;
        }
    }

    get _arRecordId() {
        return this.parentIsSavedConfiguration ? undefined : this.recordId;
    }

    @wire(getRecord, { recordId: '$_arRecordId', fields: [CFG_FIELD] })
    wiredAr({ error, data }) {
        if (this.parentIsSavedConfiguration) return;
        if (data) {
            this._configId = getFieldValue(data, CFG_FIELD);
        } else if (error) {
            this.hasError = true;
        }
        this.isLoading = false;
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$_configId',
        // relationshipName was renamed to GTM_Link_Events to avoid colliding
        // with MA_Saved_Configuration__c's own Link_Events relationship
        // while both objects coexist during the D6 transition.
        relatedListId: 'GTM_Link_Events__r',
        fields: [
            'GTM_Link_Event__c.Id',
            'GTM_Link_Event__c.Name',
            'GTM_Link_Event__c.Event_Type__c',
            'GTM_Link_Event__c.Session_Id__c',
            'GTM_Link_Event__c.Step__c',
            'GTM_Link_Event__c.CreatedDate',
        ],
        sortBy: ['GTM_Link_Event__c.CreatedDate DESC'],
        pageSize: 50,
    })
    wiredEvents({ error, data }) {
        if (data) {
            this.events = data.records.map(r => {
                const type = r.fields.Event_Type__c.value || '';
                return {
                    id:        r.id,
                    name:      r.fields.Name.value,
                    type,
                    session:   r.fields.Session_Id__c.value,
                    step:      r.fields.Step__c.value,
                    created:   r.fields.CreatedDate.value,
                    icon:      EVENT_ICON[type] || 'utility:event',
                    variant:   EVENT_VARIANT[type] || 'bare',
                    formatted: this._formatDate(r.fields.CreatedDate.value),
                };
            });
            this.isLoading = false;
        } else if (error) {
            this.isLoading = false;
            this.hasError = true;
        }
    }

    get hasEvents() {
        return this.events.length > 0;
    }

    get hasConfig() {
        return !!this._configId;
    }

    get noConfigMessage() {
        return this.parentIsSavedConfiguration
            ? 'This link has no activity to show yet.'
            : 'No engagement link connected to this assessment request.';
    }

    _formatDate(iso) {
        if (!iso) return '';
        try {
            return new Intl.DateTimeFormat('en-US', {
                month: 'short', day: 'numeric', year: 'numeric',
                hour: 'numeric', minute: '2-digit',
            }).format(new Date(iso));
        } catch (e) {
            return iso;
        }
    }
}
