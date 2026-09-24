import { createElement } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { registerLdsTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import GtmReadoutWorkspace from 'c/gtmReadoutWorkspace';
import generateReadoutForRequest from '@salesforce/apex/GtmReadoutController.generateReadoutForRequest';
import getOfferingHasConduit from '@salesforce/apex/GtmAssessmentRequestController.getOfferingHasConduit';
import GtmAssessmentPreviewModal from 'c/gtmAssessmentPreviewModal';

jest.mock('c/gtmAssessmentPreviewModal', () => ({
    __esModule: true,
    default: { open: jest.fn() }
}));

jest.mock(
    '@salesforce/apex/GtmReadoutController.generateReadoutForRequest',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/GtmAssessmentRequestController.getOfferingHasConduit',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const getRecordWireAdapter = registerLdsTestWireAdapter(getRecord);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function findButtonByLabel(root, label) {
    return Array.from(root.querySelectorAll('lightning-button')).find((b) => b.label === label);
}

function emitRequest(overrides = {}) {
    getRecordWireAdapter.emit({
        fields: {
            Submitted_At__c: { value: null },
            Contact__r: { value: { fields: { Name: { value: 'Jane Smith' } } } },
            Account__r: { value: { fields: { Name: { value: 'Acme Co' } } } },
            Company__c: { value: 'Acme Co' },
            Saved_Configuration__c: { value: null },
            Saved_Configuration__r: { value: null },
            ...overrides
        }
    });
}

describe('c-gtm-readout-workspace', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('defaults to the Assessment tab regardless of readoutId (refinement #3)', async () => {
        getOfferingHasConduit.mockResolvedValue(false);
        const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
        element.assessmentRequestId = 'a0X000000000001';
        element.readoutId = 'a0Y000000000002';
        document.body.appendChild(element);
        await flushPromises();

        const tabset = element.shadowRoot.querySelector('lightning-tabset');
        expect(tabset.activeTabValue).toBe('assessment');
    });

    // issue-102-1-engagement-links-landing, D7 + acceptance criterion 4: the
    // opt-in override that lets c-gtm-assessment-detail's "Open the readout"
    // forward action land on Readout, without changing refinement #3's own
    // default for any other caller (the test above).
    it('initialTab="readout" overrides refinement #3 and lands on the Readout tab when a readoutId is also supplied', async () => {
        getOfferingHasConduit.mockResolvedValue(false);
        const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
        element.assessmentRequestId = 'a0X000000000001';
        element.readoutId = 'a0Y000000000002';
        element.initialTab = 'readout';
        document.body.appendChild(element);
        await flushPromises();

        const tabset = element.shadowRoot.querySelector('lightning-tabset');
        expect(tabset.activeTabValue).toBe('readout');
    });

    it('initialTab="readout" is ignored (stays on Assessment) when there is no readoutId to focus on', async () => {
        getOfferingHasConduit.mockResolvedValue(false);
        const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
        element.assessmentRequestId = 'a0X000000000001';
        element.initialTab = 'readout';
        document.body.appendChild(element);
        await flushPromises();

        const tabset = element.shadowRoot.querySelector('lightning-tabset');
        expect(tabset.activeTabValue).toBe('assessment');
    });

    it('renders exactly three tabs -- Assessment, Readout, Conduit -- with no Preview tab', async () => {
        getOfferingHasConduit.mockResolvedValue(true);
        const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
        element.assessmentRequestId = 'a0X000000000001';
        document.body.appendChild(element);
        await flushPromises();

        const tabs = Array.from(element.shadowRoot.querySelectorAll('lightning-tab')).map((t) => t.value);
        expect(tabs).toEqual(['assessment', 'readout', 'conduit']);
        expect(element.shadowRoot.querySelector('c-gtm-configurator[template-type="configurator"]')).toBeNull();
    });

    it('embeds the Assessment tab with the assessmentRequestId as its record-id', async () => {
        getOfferingHasConduit.mockResolvedValue(false);
        const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
        element.assessmentRequestId = 'a0X000000000001';
        document.body.appendChild(element);
        await flushPromises();

        const detail = element.shadowRoot.querySelector('c-gtm-assessment-detail');
        expect(detail.recordId).toBe('a0X000000000001');
    });

    // issue-102-1-engagement-links-landing, D7 + acceptance criterion 4:
    // this workspace is the "tabset context" c-gtm-assessment-detail's
    // "Open the readout" forward action targets -- it owns the sibling
    // Readout tab, so the action must be a local tab swap here, not a
    // navigation.
    it('opts c-gtm-assessment-detail into tabset-mode and swaps to the Readout tab on its openreadout event', async () => {
        getOfferingHasConduit.mockResolvedValue(false);
        const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
        element.assessmentRequestId = 'a0X000000000001';
        document.body.appendChild(element);
        await flushPromises();

        const detail = element.shadowRoot.querySelector('c-gtm-assessment-detail');
        expect(detail.tabsetMode).toBe(true);

        detail.dispatchEvent(new CustomEvent('openreadout', {
            detail: { assessmentRequestId: 'a0X000000000001' }
        }));
        await flushPromises();

        const tabset = element.shadowRoot.querySelector('lightning-tabset');
        expect(tabset.activeTabValue).toBe('readout');
    });

    describe('Readout tab gating (refinement #5)', () => {
        it('shows the not-submitted reminder message instead of readout content when unsubmitted', async () => {
            getOfferingHasConduit.mockResolvedValue(false);
            const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
            element.assessmentRequestId = 'a0X000000000001';
            document.body.appendChild(element);
            await flushPromises();
            emitRequest();
            await flushPromises();

            expect(element.shadowRoot.textContent).toContain(
                'Jane Smith at Acme Co has not submitted the assessment. Reach out to them to remind them.'
            );
            expect(findButtonByLabel(element.shadowRoot, 'Generate Readout')).toBeUndefined();
        });

        // Bug fix: a request without a linked CRM Contact record (common --
        // the person who submitted the form may not be bound to a Contact
        // yet) must still show their actual name via Requester_Name__c,
        // not fall through to the generic "The contact" placeholder.
        it('falls back to Requester_Name__c for the reminder message when no Contact is linked', async () => {
            getOfferingHasConduit.mockResolvedValue(false);
            const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
            element.assessmentRequestId = 'a0X000000000001';
            document.body.appendChild(element);
            await flushPromises();
            emitRequest({
                Contact__r: { value: null },
                Requester_Name__c: { value: 'Alex Rivera' }
            });
            await flushPromises();

            expect(element.shadowRoot.textContent).toContain(
                'Alex Rivera at Acme Co has not submitted the assessment. Reach out to them to remind them.'
            );
        });

        // Only genuinely no name at all (no Contact, no Requester_Name__c)
        // should fall back to the generic placeholder.
        it('falls back to "The contact" only when neither a Contact nor a Requester_Name__c is present', async () => {
            getOfferingHasConduit.mockResolvedValue(false);
            const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
            element.assessmentRequestId = 'a0X000000000001';
            document.body.appendChild(element);
            await flushPromises();
            emitRequest({
                Contact__r: { value: null },
                Requester_Name__c: { value: null }
            });
            await flushPromises();

            expect(element.shadowRoot.textContent).toContain(
                'The contact at Acme Co has not submitted the assessment. Reach out to them to remind them.'
            );
        });

        it('shows the normal Generate Readout / readout content once submitted', async () => {
            getOfferingHasConduit.mockResolvedValue(false);
            const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
            element.assessmentRequestId = 'a0X000000000001';
            document.body.appendChild(element);
            await flushPromises();
            emitRequest({ Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' }, Pain_Points__c: { value: 'Deliverability issues.' } });
            await flushPromises();

            expect(element.shadowRoot.textContent).not.toContain('has not submitted the assessment');
            expect(findButtonByLabel(element.shadowRoot, 'Generate Readout')).not.toBeUndefined();
        });

        // Bug fix, round 2: a stamped Submitted_At__c with no real answers is
        // still not "submitted" in spirit -- both signals are required
        // together now, not either alone (see hasMeaningfulAnswers/
        // isSubmitted's own doc comment).
        it('still shows the not-submitted reminder when Submitted_At__c is set but no answer fields are populated', async () => {
            getOfferingHasConduit.mockResolvedValue(false);
            const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
            element.assessmentRequestId = 'a0X000000000001';
            document.body.appendChild(element);
            await flushPromises();
            emitRequest({ Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' } });
            await flushPromises();

            expect(element.shadowRoot.textContent).toContain(
                'Jane Smith at Acme Co has not submitted the assessment. Reach out to them to remind them.'
            );
            expect(findButtonByLabel(element.shadowRoot, 'Generate Readout')).toBeUndefined();
        });

        // The reverse case: an answer present without a submission timestamp
        // must also still be gated.
        it('still shows the not-submitted reminder when an answer field is populated but Submitted_At__c is blank', async () => {
            getOfferingHasConduit.mockResolvedValue(false);
            const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
            element.assessmentRequestId = 'a0X000000000001';
            document.body.appendChild(element);
            await flushPromises();
            emitRequest({ Pain_Points__c: { value: 'Deliverability issues.' } });
            await flushPromises();

            expect(element.shadowRoot.textContent).toContain(
                'Jane Smith at Acme Co has not submitted the assessment. Reach out to them to remind them.'
            );
            expect(findButtonByLabel(element.shadowRoot, 'Generate Readout')).toBeUndefined();
        });

        it('shows a readout that already exists once submitted', async () => {
            getOfferingHasConduit.mockResolvedValue(false);
            const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
            element.assessmentRequestId = 'a0X000000000001';
            element.readoutId = 'a0Y000000000002';
            document.body.appendChild(element);
            await flushPromises();
            emitRequest({ Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' }, Pain_Points__c: { value: 'Deliverability issues.' } });
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-gtm-readout-review')).not.toBeNull();
        });
    });

    it('shows Generate Readout, then switches to the Readout tab once generated', async () => {
        getOfferingHasConduit.mockResolvedValue(false);
        generateReadoutForRequest.mockResolvedValue('a0Y000000000009');
        const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
        element.assessmentRequestId = 'a0X000000000001';
        document.body.appendChild(element);
        await flushPromises();
        emitRequest({ Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' }, Pain_Points__c: { value: 'Deliverability issues.' } });
        await flushPromises();

        const generateBtn = findButtonByLabel(element.shadowRoot, 'Generate Readout');
        expect(generateBtn).not.toBeUndefined();
        generateBtn.click();
        await flushPromises();

        expect(generateReadoutForRequest).toHaveBeenCalledWith({ assessmentRequestId: 'a0X000000000001' });
        const tabset = element.shadowRoot.querySelector('lightning-tabset');
        expect(tabset.activeTabValue).toBe('readout');
        expect(element.shadowRoot.querySelector('c-gtm-readout-review')).not.toBeNull();
    });

    it('renders no Conduit tab when the offering does not have one', async () => {
        getOfferingHasConduit.mockResolvedValue(false);
        const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
        element.assessmentRequestId = 'a0X000000000001';
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-conduit-dashboard')).toBeNull();
    });

    it('renders the Conduit tab, wired to the assessmentRequestId, when the offering has one and the assessment is submitted', async () => {
        getOfferingHasConduit.mockResolvedValue(true);
        const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
        element.assessmentRequestId = 'a0X000000000001';
        document.body.appendChild(element);
        await flushPromises();
        emitRequest({
            Submitted_At__c: { value: '2026-01-01T00:00:00.000Z' },
            Pain_Points__c: { value: 'Deliverability issues.' }
        });
        await flushPromises();

        const conduit = element.shadowRoot.querySelector('c-conduit-dashboard');
        expect(conduit).not.toBeNull();
        expect(conduit.recordId).toBe('a0X000000000001');
        expect(element.shadowRoot.textContent).not.toContain('has not submitted the assessment yet');
    });

    // Bug fix, round 2: Conduit used to fully block on the same gate as
    // Readout, showing only the reminder message and no dashboard at all
    // when unsubmitted. The product owner confirmed Conduit should ALWAYS
    // render conduitDashboard once the offering is conduit-eligible,
    // regardless of submission status -- an unsubmitted assessment now
    // additionally shows a small note above the dashboard, not instead of it.
    it('always renders conduitDashboard when the offering is eligible, adding a not-submitted note (not a block) when unsubmitted', async () => {
        getOfferingHasConduit.mockResolvedValue(true);
        const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
        element.assessmentRequestId = 'a0X000000000001';
        document.body.appendChild(element);
        await flushPromises();
        emitRequest();
        await flushPromises();

        const tabs = Array.from(element.shadowRoot.querySelectorAll('lightning-tab'));
        const conduitTab = tabs.find((t) => t.value === 'conduit');
        expect(conduitTab).not.toBeUndefined();
        const conduit = element.shadowRoot.querySelector('c-conduit-dashboard');
        expect(conduit).not.toBeNull();
        expect(conduit.recordId).toBe('a0X000000000001');
        expect(conduitTab.textContent).toContain(
            'Note: Jane Smith at Acme Co has not submitted the assessment yet.'
        );
    });

    describe('link section / preview modal (issue-pages-preview-fixes)', () => {
        it('does not render the link section when the request has no saved configuration', async () => {
            getOfferingHasConduit.mockResolvedValue(false);
            const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
            element.assessmentRequestId = 'a0X000000000001';
            document.body.appendChild(element);
            await flushPromises();
            emitRequest();
            await flushPromises();

            expect(element.shadowRoot.querySelector('.grw-link-section')).toBeNull();
        });

        // Reversed per direct product-owner correction after a live review:
        // "Preview the assessment" now opens as a MODAL (lightning/modal),
        // not an inline toggle/embed. See gtmAssessmentPreviewModal.
        it('shows the link section and opens the preview modal, passing the offering key and saved-configuration id through', async () => {
            getOfferingHasConduit.mockResolvedValue(false);
            GtmAssessmentPreviewModal.open.mockResolvedValue(undefined);
            const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
            element.assessmentRequestId = 'a0X000000000001';
            element.offeringKey = 'migration-accelerator';
            document.body.appendChild(element);
            await flushPromises();
            emitRequest({
                Saved_Configuration__c: { value: 'a0Z000000000001' },
                'Saved_Configuration__r.Generated_URL__c': { value: 'https://example.com/go/abc123' }
            });
            await flushPromises();

            expect(element.shadowRoot.querySelector('.grw-link-section')).not.toBeNull();
            expect(element.shadowRoot.querySelector('c-gtm-configurator')).toBeNull();

            // No Assessment Link/Password fields any more (issue-pages-preview-fixes) --
            // gtmRepLinkFinder's own always-visible Engagement Link box is now the
            // single source of that URL/password UI, this box just kept the distinct
            // "Preview the assessment" modal trigger.
            expect(element.shadowRoot.querySelector('.grw-view-details')).toBeNull();
            expect(element.shadowRoot.textContent).not.toContain('Assessment Link');

            const toggle = findButtonByLabel(element.shadowRoot, 'Preview the assessment');
            expect(toggle).not.toBeUndefined();
            toggle.click();
            await flushPromises();

            expect(GtmAssessmentPreviewModal.open).toHaveBeenCalledWith(
                expect.objectContaining({
                    assessmentRequestId: 'a0X000000000001',
                    offeringKey: 'migration-accelerator',
                    cfgId: 'a0Z000000000001'
                })
            );
            // Nothing renders inline for the preview any more -- the modal is
            // its own mounted component, outside this shadow root.
            expect(element.shadowRoot.querySelector('c-gtm-configurator')).toBeNull();
        });

        // Bug fix: c-gtm-configurator has no @api way to be told which saved
        // record to render -- it only ever reads "?cfgId=" off the real
        // browser URL, the same mechanism gtmRepLinkFinder's "Preview the
        // link" already relies on. Without this, "Preview the assessment"
        // showed the generic unfilled template instead of the specific
        // configuration actually sent to this prospect.
        it('sets the "?cfgId=" URL param to the request\'s saved configuration once known', async () => {
            getOfferingHasConduit.mockResolvedValue(false);
            const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
            element.assessmentRequestId = 'a0X000000000001';
            document.body.appendChild(element);
            await flushPromises();
            emitRequest({ Saved_Configuration__c: { value: 'a0Z000000000001' } });
            await flushPromises();

            const url = new URL(window.location.href);
            expect(url.searchParams.get('cfgId')).toBe('a0Z000000000001');
        });

        it('clears the "?cfgId=" URL param on back so a later selection cannot leak into it', async () => {
            getOfferingHasConduit.mockResolvedValue(false);
            const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
            element.assessmentRequestId = 'a0X000000000001';
            document.body.appendChild(element);
            await flushPromises();
            emitRequest({ Saved_Configuration__c: { value: 'a0Z000000000001' } });
            await flushPromises();

            element.shadowRoot.querySelector('.grw-back').click();
            await flushPromises();

            const url = new URL(window.location.href);
            expect(url.searchParams.get('cfgId')).toBeNull();
        });

    });

    it('dispatches a "back" event, rather than hiding itself, when Back is clicked', async () => {
        getOfferingHasConduit.mockResolvedValue(false);
        const element = createElement('c-gtm-readout-workspace', { is: GtmReadoutWorkspace });
        element.assessmentRequestId = 'a0X000000000001';
        const backHandler = jest.fn();
        element.addEventListener('back', backHandler);
        document.body.appendChild(element);
        await flushPromises();

        const backBtn = element.shadowRoot.querySelector('.grw-back');
        backBtn.click();

        expect(backHandler).toHaveBeenCalledTimes(1);
        // Still in the DOM -- this component never manages its own visibility;
        // it is the parent's job to remove it in response to "back".
        expect(document.body.contains(element)).toBe(true);
    });
});
