import { createElement } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { registerLdsTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import GtmAssessmentDetail from 'c/gtmAssessmentDetail';
import getReadoutByRequest from '@salesforce/apex/GtmReadoutController.getReadoutByRequest';

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
const { __navigateMock: mockNavigate } = require('lightning/navigation');

jest.mock(
    '@salesforce/apex/GtmReadoutController.getReadoutByRequest',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const getRecordWireAdapter = registerLdsTestWireAdapter(getRecord);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function baseFields(overrides = {}) {
    return {
        Name: { value: 'AR-0049' },
        Status__c: { value: 'In Progress' },
        Contact__c: { value: '003000000000001' },
        Contact__r: { value: { fields: { Name: { value: 'Jane Smith' } } } },
        Account__c: { value: '001000000000001' },
        Account__r: { value: { fields: { Name: { value: 'Acme Co' } } } },
        Company__c: { value: 'Acme Co' },
        Submitted_At__c: { value: null },
        ...overrides
    };
}

function emitRecord(fields) {
    getRecordWireAdapter.emit({ fields });
}

describe('c-gtm-assessment-detail — prospect\'s answers section', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    // issue-gtm-readout-workspace refinement #4
    it('shows the not-submitted reminder message with contact and account interpolated when Submitted_At__c is blank', async () => {
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        emitRecord(baseFields());
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'Jane Smith at Acme Co has not submitted the assessment. Reach out to them to remind them.'
        );
    });

    // Bug fix: a request without a linked CRM Contact record (common -- the
    // person who submitted the form may not be bound to a Contact yet) must
    // still show their actual name via Requester_Name__c, not fall through
    // to the generic "The contact" placeholder.
    it('falls back to Requester_Name__c for the reminder message when no Contact is linked', async () => {
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        emitRecord(baseFields({
            Contact__c: { value: null },
            Contact__r: { value: null },
            Requester_Name__c: { value: 'Alex Rivera' }
        }));
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'Alex Rivera at Acme Co has not submitted the assessment. Reach out to them to remind them.'
        );
    });

    // Only genuinely no name at all (no Contact, no Requester_Name__c)
    // should fall back to the generic placeholder.
    it('falls back to "The contact" only when neither a Contact nor a Requester_Name__c is present', async () => {
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        emitRecord(baseFields({
            Contact__c: { value: null },
            Contact__r: { value: null },
            Requester_Name__c: { value: null }
        }));
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'The contact at Acme Co has not submitted the assessment. Reach out to them to remind them.'
        );
    });

    it('shows the prospect\'s submitted answers once Submitted_At__c is populated', async () => {
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        emitRecord(baseFields({
            Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' },
            Pain_Points__c: { value: 'Deliverability issues on the current platform.' },
            Budget_Range__c: { value: '$50k-$100k' }
        }));
        await flushPromises();

        expect(element.shadowRoot.textContent).not.toContain('has not submitted the assessment');
        expect(element.shadowRoot.textContent).toContain('Deliverability issues on the current platform.');
        expect(element.shadowRoot.textContent).toContain('$50k-$100k');
    });

    // Bug fix: gating on Submitted_At__c alone conflated "a timestamp was
    // written" with "the prospect actually answered questions" -- these can
    // diverge either way. A timestamp with no real answers must still show
    // the not-submitted reminder, not the (blank) answers section.
    it('still shows the not-submitted reminder when Submitted_At__c is set but no answer fields are populated', async () => {
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        emitRecord(baseFields({ Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' } }));
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'Jane Smith at Acme Co has not submitted the assessment. Reach out to them to remind them.'
        );
    });

    // Bug fix, round 2: the gate previously dropped Submitted_At__c entirely
    // and unlocked on "any one non-blank answer field" alone -- which let a
    // record with real answers but no Submitted_At__c stamp (still
    // technically in progress) show as fully submitted. The gate now
    // requires BOTH signals together, so real answers without a submission
    // timestamp must still show the reminder, not the answers.
    it('still shows the not-submitted reminder when an answer field is populated but Submitted_At__c is blank', async () => {
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        emitRecord(baseFields({
            Submitted_At__c: { value: null },
            Migration_Goals__c: { value: 'Move off legacy ESP within Q3.' }
        }));
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'Jane Smith at Acme Co has not submitted the assessment. Reach out to them to remind them.'
        );
    });

    // The genuinely-unlocked case: both signals present together.
    it('shows the prospect\'s answers when Submitted_At__c is set AND an answer field is populated', async () => {
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        emitRecord(baseFields({
            Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' },
            Migration_Goals__c: { value: 'Move off legacy ESP within Q3.' }
        }));
        await flushPromises();

        expect(element.shadowRoot.textContent).not.toContain('has not submitted the assessment');
        expect(element.shadowRoot.textContent).toContain('Move off legacy ESP within Q3.');
    });
});

describe('c-gtm-assessment-detail -- engagement link opens the Pages view', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        mockNavigate.mockClear();
    });

    it('the SC name navigates to the Pages link detail, never the SC record page', async () => {
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        emitRecord(baseFields({
            Saved_Configuration__c: { value: 'a0S000000000007' },
            Saved_Configuration__r: { value: { fields: { Name: { value: 'SC-0007' }, Generated_URL__c: { value: 'https://x.test' } } } }
        }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('a[href*="GTM_Saved_Configuration__c"]')).toBeNull();
        const link = [...element.shadowRoot.querySelectorAll('a')].find((a) => a.textContent.trim() === 'SC-0007');
        expect(link).toBeTruthy();
        link.click();
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Pages' },
            state: {
                c__rlfLinkId: 'a0S000000000007', c__rlfAccountId: '001000000000001',
                c__rlfContactId: '003000000000001', cfgId: 'a0S000000000007'
            }
        });
    });
});

// issue-102-1-engagement-links-landing, D7 + acceptance criterion 4
describe('c-gtm-assessment-detail -- "Open the readout" forward action (dual mode)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        mockNavigate.mockClear();
        getReadoutByRequest.mockReset();
    });

    it('does not render the forward action before the assessment is submitted', async () => {
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        emitRecord(baseFields());
        await flushPromises();

        expect(element.shadowRoot.querySelector('.open-readout-button')).toBeNull();
    });

    it('renders "Open the readout" once genuinely submitted', async () => {
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        emitRecord(baseFields({
            Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' },
            Migration_Goals__c: { value: 'Move off legacy ESP within Q3.' }
        }));
        await flushPromises();

        const button = element.shadowRoot.querySelector('.open-readout-button');
        expect(button).not.toBeNull();
        expect(button.label).toBe('Open the readout');
    });

    // Bug fix (QA fail, first pass): the non-tabset branch used to call
    // openAssessment with a hardcoded null readoutId -- GTM_Assessment_Request__c
    // has no forward lookup to GTM_Readout__c, so it never actually resolved
    // one, and the destination workspace neither landed on the Readout tab
    // nor recognized the Draft readout as existing. It now resolves the real
    // readout Id first via GtmReadoutController.getReadoutByRequest (reused,
    // not a new Apex method) and passes focusReadout=true so the state rides
    // along as c__readoutId + c__focusReadoutTab.
    it('standalone/default mode: resolves the readout id via Apex first, then navigates with it and the focus-readout rider', async () => {
        getReadoutByRequest.mockResolvedValue({ id: 'a0Y000000000009' });
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        emitRecord(baseFields({
            Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' },
            Migration_Goals__c: { value: 'Move off legacy ESP within Q3.' },
            Offering_Key__c: { value: 'migration-accelerator' }
        }));
        await flushPromises();

        element.shadowRoot.querySelector('.open-readout-button').click();
        await flushPromises();

        expect(getReadoutByRequest).toHaveBeenCalledWith({ requestId: 'a0X000000000001' });
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: {
                c__assessmentRequestId: 'a0X000000000001',
                c__readoutId: 'a0Y000000000009',
                c__focusReadoutTab: '1',
                c__offeringKey: 'migration-accelerator'
            }
        });
    });

    // Defensive boundary: D7's premise is the Draft readout already exists
    // by the time a BD reaches this screen, but the lookup can still
    // legitimately come back empty (e.g. stale data) -- the click must still
    // navigate, just without a readout id/focus rider to attach.
    it('standalone mode: still navigates, without a readout id, when the lookup finds none', async () => {
        getReadoutByRequest.mockResolvedValue(null);
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        emitRecord(baseFields({
            Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' },
            Migration_Goals__c: { value: 'Move off legacy ESP within Q3.' }
        }));
        await flushPromises();

        element.shadowRoot.querySelector('.open-readout-button').click();
        await flushPromises();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: { c__assessmentRequestId: 'a0X000000000001' }
        });
    });

    // The lookup itself is not expected to fail (D7), but a click must not
    // silently strand the user with no navigation at all if it does.
    it('standalone mode: still navigates, without a readout id, when the Apex lookup errors', async () => {
        getReadoutByRequest.mockRejectedValue(new Error('boom'));
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);
        emitRecord(baseFields({
            Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' },
            Migration_Goals__c: { value: 'Move off legacy ESP within Q3.' }
        }));
        await flushPromises();

        element.shadowRoot.querySelector('.open-readout-button').click();
        await flushPromises();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: { c__assessmentRequestId: 'a0X000000000001' }
        });
    });

    it('tabset-mode: clicking dispatches "openreadout" instead of navigating', async () => {
        const element = createElement('c-gtm-assessment-detail', { is: GtmAssessmentDetail });
        element.recordId = 'a0X000000000001';
        element.tabsetMode = true;
        const openReadoutHandler = jest.fn();
        element.addEventListener('openreadout', openReadoutHandler);
        document.body.appendChild(element);
        emitRecord(baseFields({
            Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' },
            Migration_Goals__c: { value: 'Move off legacy ESP within Q3.' }
        }));
        await flushPromises();

        element.shadowRoot.querySelector('.open-readout-button').click();
        await flushPromises();

        expect(mockNavigate).not.toHaveBeenCalled();
        expect(getReadoutByRequest).not.toHaveBeenCalled();
        expect(openReadoutHandler).toHaveBeenCalledTimes(1);
        expect(openReadoutHandler.mock.calls[0][0].detail).toEqual({
            assessmentRequestId: 'a0X000000000001'
        });
    });
});
