import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';

import CFG_FIELD from '@salesforce/schema/MA_Assessment_Request__c.Saved_Configuration__c';

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

export default class MaLinkActivity extends LightningElement {
    @api recordId;

    _configId;
    events = [];
    isLoading = true;
    hasError = false;

    @wire(getRecord, { recordId: '$recordId', fields: [CFG_FIELD] })
    wiredAr({ error, data }) {
        if (data) {
            const id = getFieldValue(data, CFG_FIELD);
            if (id) {
                this._configId = id;
            } else {
                this.isLoading = false;
            }
        } else if (error) {
            this.isLoading = false;
            this.hasError = true;
        }
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$_configId',
        relatedListId: 'Link_Events__r',
        fields: [
            'MA_Link_Event__c.Id',
            'MA_Link_Event__c.Name',
            'MA_Link_Event__c.Event_Type__c',
            'MA_Link_Event__c.Session_Id__c',
            'MA_Link_Event__c.Step__c',
            'MA_Link_Event__c.CreatedDate',
        ],
        sortBy: ['MA_Link_Event__c.CreatedDate DESC'],
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
