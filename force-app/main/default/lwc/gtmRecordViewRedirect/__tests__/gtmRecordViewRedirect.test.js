import { createElement } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import GtmRecordViewRedirect from 'c/gtmRecordViewRedirect';

jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const navigateMock = jest.fn();
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](...args) { navigateMock(...args); }
        };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, __navigateMock: navigateMock };
});
const { __navigateMock: spy } = require('lightning/navigation');

function mount(objectApiName) {
    const el = createElement('c-gtm-record-view-redirect', { is: GtmRecordViewRedirect });
    el.recordId = 'a0X000000000001';
    el.objectApiName = objectApiName;
    document.body.appendChild(el);
    return { el, spy };
}
const flush = () => Promise.resolve();

describe('c-gtm-record-view-redirect', () => {
    beforeEach(() => spy.mockClear());
    afterEach(() => { while (document.body.firstChild) document.body.removeChild(document.body.firstChild); });

    it('SC opens the Pages tab with replace, once', async () => {
        const { el, spy } = mount('GTM_Saved_Configuration__c');
        getRecord.emit({ id: 'a0X000000000001', fields: {} });
        getRecord.emit({ id: 'a0X000000000001', fields: {} });
        await flush();
        expect(el).toBeTruthy();
        expect(spy).toHaveBeenCalledTimes(1);
        const [ref, replace] = spy.mock.calls[0];
        expect(ref.type).toBe('standard__navItemPage');
        expect(ref.attributes.apiName).toBe('GTM_Pages');
        expect(ref.state.c__recordId).toBe('a0X000000000001');
        expect(replace).toBe(true);
    });

    it('AR opens the Assessments tab', async () => {
        const { spy } = mount('GTM_Assessment_Request__c');
        getRecord.emit({ id: 'a0X000000000001', fields: {} });
        await flush();
        const [ref] = spy.mock.calls[0];
        expect(ref.attributes.apiName).toBe('GTM_Assessments');
        expect(ref.state.c__assessmentRequestId).toBe('a0X000000000001');
    });

    it('shows a message and does not navigate when the record is inaccessible', async () => {
        const { el, spy } = mount('GTM_Saved_Configuration__c');
        getRecord.error();
        await flush();
        expect(spy).not.toHaveBeenCalled();
        expect(el.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
    });

    it('never redirects for an unknown object', async () => {
        const { spy } = mount('Account');
        getRecord.emit({ id: 'a0X000000000001', fields: {} });
        await flush();
        expect(spy).not.toHaveBeenCalled();
    });
});
