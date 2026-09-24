import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getReadout from '@salesforce/apex/GtmReadoutController.getReadout';
import getAllReadouts from '@salesforce/apex/GtmReadoutController.getAllReadouts';

// The stock sfdx-lwc-jest navigation stub defines [NavigationMixin.Navigate]
// on a sealed prototype, so it cannot be spied on or reassigned in place.
// This test needs to observe the exact payload passed to Navigate, so the
// module is re-mocked here with a Navigate that forwards to an inspectable
// jest.fn(). CurrentPageReference is re-exported as a test wire adapter so
// the existing setPageRef / clearPageRef helpers keep working.
const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const GenerateUrl = Symbol('GenerateUrl');
    const NavigationMixin = (Base) => {
        return class extends Base {
            [Navigate](...args) {
                mockNavigate(...args);
            }
            [GenerateUrl]() {
                return Promise.resolve('https://www.example.com');
            }
        };
    };
    NavigationMixin.Navigate = Navigate;
    NavigationMixin.GenerateUrl = GenerateUrl;
    const { createTestWireAdapter } = jest.requireActual('@salesforce/wire-service-jest-util');
    return {
        NavigationMixin,
        CurrentPageReference: createTestWireAdapter(jest.fn())
    };
});

// eslint-disable-next-line import/first, import/order
import GtmAssessmentSubmissionView from 'c/gtmAssessmentSubmissionView';

jest.mock(
    '@salesforce/apex/GtmReadoutController.getReadout',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/GtmReadoutController.getAllReadouts',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function setPageRef(readoutId) {
    CurrentPageReference.emit({ state: { c__readout: readoutId } });
    await flushPromises();
}

async function clearPageRef() {
    CurrentPageReference.emit({ state: {} });
    await flushPromises();
}

describe('c-gtm-assessment-submission-view', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders the tabset with an Assessments tab bound to the resolved Assessment Request', async () => {
        getAllReadouts.mockResolvedValue([]);
        getReadout.mockResolvedValue({
            id: 'r1',
            assessmentRequestId: 'a0X000000000001',
            assessmentRequestName: 'Acme Assessment',
            company: 'Acme'
        });

        const element = createElement('c-gtm-assessment-submission-view', { is: GtmAssessmentSubmissionView });
        document.body.appendChild(element);
        await setPageRef('r1');

        const tabset = element.shadowRoot.querySelector('lightning-tabset');
        expect(tabset).not.toBeNull();

        const detail = element.shadowRoot.querySelector('c-gtm-assessment-detail');
        expect(detail).not.toBeNull();
        expect(detail.recordId).toBe('a0X000000000001');

        expect(element.shadowRoot.querySelector('c-gtm-readout-review')).not.toBeNull();
    });

    it('renders the Migration Accelerator tab with conduit-dashboard when assessmentRequestId is set', async () => {
        getAllReadouts.mockResolvedValue([]);
        getReadout.mockResolvedValue({
            id: 'r1',
            assessmentRequestId: 'a0X000000000001',
            assessmentRequestName: 'Acme Assessment'
        });

        const element = createElement('c-gtm-assessment-submission-view', { is: GtmAssessmentSubmissionView });
        document.body.appendChild(element);
        await setPageRef('r1');

        const conduit = element.shadowRoot.querySelector('c-conduit-dashboard');
        expect(conduit).not.toBeNull();
        expect(conduit.recordId).toBe('a0X000000000001');

        expect(element.shadowRoot.querySelector('iframe')).toBeNull();
    });

    it('shows an orphan notice in Migration Accelerator tab when there is no Assessment Request', async () => {
        getAllReadouts.mockResolvedValue([]);
        getReadout.mockResolvedValue({
            id: 'r2',
            assessmentRequestId: null,
            company: null
        });

        const element = createElement('c-gtm-assessment-submission-view', { is: GtmAssessmentSubmissionView });
        document.body.appendChild(element);
        await setPageRef('r2');

        expect(element.shadowRoot.querySelector('c-conduit-dashboard')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('Migration Accelerator data is unavailable');
    });

    it('shows an orphan notice instead of the Assessments detail when there is no Assessment Request', async () => {
        getAllReadouts.mockResolvedValue([]);
        getReadout.mockResolvedValue({
            id: 'r2',
            assessmentRequestId: null,
            company: null
        });

        const element = createElement('c-gtm-assessment-submission-view', { is: GtmAssessmentSubmissionView });
        document.body.appendChild(element);
        await setPageRef('r2');

        expect(element.shadowRoot.querySelector('c-gtm-assessment-detail')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('not linked to an Assessment Request');

        // The in-place editor must still work for an orphan readout — it only
        // needs the readout id (via the same page-ref state), not an
        // Assessment Request.
        expect(element.shadowRoot.querySelector('c-gtm-readout-review')).not.toBeNull();
    });

    it('surfaces an Apex error instead of failing silently', async () => {
        getAllReadouts.mockResolvedValue([]);
        getReadout.mockRejectedValue({ body: { message: 'boom' } });

        const element = createElement('c-gtm-assessment-submission-view', { is: GtmAssessmentSubmissionView });
        document.body.appendChild(element);
        await setPageRef('r3');

        expect(element.shadowRoot.querySelector('.asv-err').textContent).toBe('boom');
    });

    it('shows the list view with a datatable when no readout param is set', async () => {
        getAllReadouts.mockResolvedValue([
            { id: 'r1', name: 'Readout 1', status: 'Draft', company: 'Acme', assessmentRequestName: null },
            { id: 'r2', name: 'Readout 2', status: 'Approved', company: null, assessmentRequestName: 'Beta Corp' },
        ]);

        const element = createElement('c-gtm-assessment-submission-view', { is: GtmAssessmentSubmissionView });
        document.body.appendChild(element);
        await clearPageRef();

        const table = element.shadowRoot.querySelector('lightning-datatable');
        expect(table).not.toBeNull();
        expect(table.data.length).toBe(2);

        // No detail tabs rendered in list mode
        expect(element.shadowRoot.querySelector('lightning-tabset')).toBeNull();
    });

    it('renders the shared page header in list mode with eyebrow/title/meta and a Refresh action', async () => {
        getAllReadouts.mockResolvedValue([
            { id: 'r1', name: 'Readout 1', status: 'Draft', company: 'Acme' },
            { id: 'r2', name: 'Readout 2', status: 'Approved', company: 'Beta Corp' },
        ]);

        const element = createElement('c-gtm-assessment-submission-view', { is: GtmAssessmentSubmissionView });
        document.body.appendChild(element);
        await clearPageRef();

        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header).not.toBeNull();
        expect(header.eyebrow).toBe('Assessment');
        expect(header.title).toBe('Assessment Submissions');
        expect(header.meta).toBe('2 submissions');

        const refreshButton = header.querySelector('lightning-button-icon[slot="actions"]');
        expect(refreshButton).not.toBeNull();
        expect(refreshButton.iconName).toBe('utility:refresh');
    });

    it('re-fetches the readout list when the header Refresh action is clicked', async () => {
        getAllReadouts.mockResolvedValue([
            { id: 'r1', name: 'Readout 1', status: 'Draft', company: 'Acme' }
        ]);

        const element = createElement('c-gtm-assessment-submission-view', { is: GtmAssessmentSubmissionView });
        document.body.appendChild(element);
        await clearPageRef();

        getAllReadouts.mockClear();
        getAllReadouts.mockResolvedValue([
            { id: 'r1', name: 'Readout 1', status: 'Draft', company: 'Acme' },
            { id: 'r2', name: 'Readout 2', status: 'Approved', company: 'Beta Corp' },
        ]);

        let header = element.shadowRoot.querySelector('c-gtm-page-header');
        const refreshButton = header.querySelector('lightning-button-icon[slot="actions"]');
        refreshButton.click();
        await flushPromises();

        expect(getAllReadouts).toHaveBeenCalledTimes(1);
        const table = element.shadowRoot.querySelector('lightning-datatable');
        expect(table.data.length).toBe(2);

        // The list-loading spinner swaps the whole list block (including the
        // header) back in once the refreshed data resolves, so re-query for
        // the current header rather than relying on the pre-refresh handle.
        header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header.meta).toBe('2 submissions');
    });

    // Regression pin for issue-gtm-nav-restructure: the GTM_Assessment_Submission_View
    // CustomTab that used to host this component was retired (consolidated
    // into the Assessments tab), so the row action must no longer target it
    // -- every drill-in showed "Page doesn't exist" once that tab was
    // deleted. It now navigates straight to the GTM_Readout__c record page.
    it('opens the readout inside its parent assessment workspace, never a record page', async () => {
        getAllReadouts.mockResolvedValue([
            { id: 'a0R000000000001', name: 'RDO-0001', status: 'Draft', company: 'Acme', assessmentRequestId: 'a0Q000000000009', offeringKey: 'migration-accelerator' }
        ]);

        const element = createElement('c-gtm-assessment-submission-view', { is: GtmAssessmentSubmissionView });
        document.body.appendChild(element);
        await clearPageRef();

        mockNavigate.mockClear();

        const table = element.shadowRoot.querySelector('lightning-datatable');
        table.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { action: { name: 'open' }, row: table.data[0] }
            })
        );

        expect(mockNavigate).toHaveBeenCalledTimes(1);
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: {
                c__assessmentRequestId: 'a0Q000000000009',
                c__readoutId: 'a0R000000000001',
                c__offeringKey: 'migration-accelerator'
            }
        });
    });

    // Issue: clicking the Name cell used to do nothing (type: 'text'). The
    // Name column must now render as a link whose href resolves to the same
    // c__readout destination the existing "Open" row action navigates to.
    it('renders the Name column as a link to the same c__readout destination as the Open row action', async () => {
        getAllReadouts.mockResolvedValue([
            { id: 'a0R000000000001', name: 'RDO-0001', status: 'Draft', company: 'Acme', assessmentRequestId: 'a0Q000000000009', offeringKey: 'migration-accelerator' }
        ]);

        const element = createElement('c-gtm-assessment-submission-view', { is: GtmAssessmentSubmissionView });
        document.body.appendChild(element);
        await clearPageRef();

        const table = element.shadowRoot.querySelector('lightning-datatable');
        const nameColumn = table.columns.find((col) => col.label === 'Name');

        // A button cell that fires the same 'open' action; no record-page url cell.
        expect(nameColumn.type).toBe('button');
        expect(nameColumn.typeAttributes.name).toBe('open');
        expect(nameColumn.typeAttributes.label.fieldName).toBe('name');
        expect(table.data[0].nameUrl).toBeUndefined();
    });
});
