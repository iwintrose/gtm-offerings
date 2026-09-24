import { LightningElement, api } from 'lwc';

// Test stand-in for c/gtmSetupItem (owned by workstream D).
export default class GtmSetupItemStub extends LightningElement {
    @api item;
    @api busy;
    @api pickerUsers;
}
