import { createElement } from 'lwc';
import getArchivedItems from '@salesforce/apex/GTM_RecycleBinController.getArchivedItems';
import restoreRecord from '@salesforce/apex/GTM_RecycleBinController.restoreRecord';
import restoreRecords from '@salesforce/apex/GTM_RecycleBinController.restoreRecords';
import deleteRecords from '@salesforce/apex/GTM_RecycleBinController.deleteRecords';
import GtmRecycleBin from 'c/gtmRecycleBin';

/** Header actions are now data on c-gtm-page-header (`actions` prop) and
 *  come back as a `headeraction` event, so specs read the prop and dispatch
 *  the event instead of clicking slotted buttons. Returns button-like
 *  proxies (label/variant/iconName/disabled/click). */
function headerActionButtons(element) {
    const header = element.shadowRoot.querySelector('c-gtm-page-header');
    return header.actions.map((a) => ({
        label: a.label,
        variant: a.variant,
        iconName: a.iconName,
        disabled: a.disabled,
        click() {
            if (a.disabled) return;
            header.dispatchEvent(new CustomEvent('headeraction', { detail: { name: a.name } }));
        }
    }));
}

jest.mock(
    '@salesforce/apex/GTM_RecycleBinController.getArchivedItems',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GTM_RecycleBinController.restoreRecord',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GTM_RecycleBinController.restoreRecords',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GTM_RecycleBinController.deleteRecords',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const ROW_1 = {
    recordId: 'a0R000000000001',
    objectType: 'GTM_Page_Section__c',
    recordName: 'Story Hero',
    offeringKey: 'gtm-cloud',
    archivedDate: '2026-01-01T12:00:00.000Z',
    archivedBy: 'Jane Doe',
    isOfferingTile: false
};

const ROW_2 = {
    recordId: 'a0R000000000002',
    objectType: 'GTM_Page_Content__c',
    recordName: 'section::field',
    offeringKey: 'gtm-cloud',
    archivedDate: '2026-01-02T12:00:00.000Z',
    archivedBy: 'John Smith',
    isOfferingTile: false
};

describe('c-gtm-recycle-bin', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads and renders archived items in a datatable', async () => {
        getArchivedItems.mockResolvedValue([ROW_1, ROW_2]);
        const element = createElement('c-gtm-recycle-bin', { is: GtmRecycleBin });
        document.body.appendChild(element);
        await flushPromises();

        expect(getArchivedItems).toHaveBeenCalledTimes(1);
        const table = element.shadowRoot.querySelector('lightning-datatable');
        expect(table).not.toBeNull();
        expect(table.data.length).toBe(2);
    });

    it('shows an empty state when nothing is archived', async () => {
        getArchivedItems.mockResolvedValue([]);
        const element = createElement('c-gtm-recycle-bin', { is: GtmRecycleBin });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-datatable')).toBeNull();
        expect(element.shadowRoot.querySelector('.rb-empty')).not.toBeNull();
    });

    it('restores a single row via the row action and refreshes the list', async () => {
        getArchivedItems.mockResolvedValueOnce([ROW_1]);
        restoreRecord.mockResolvedValue({ recordId: ROW_1.recordId, success: true, message: null });

        const element = createElement('c-gtm-recycle-bin', { is: GtmRecycleBin });
        document.body.appendChild(element);
        await flushPromises();

        getArchivedItems.mockResolvedValueOnce([]);
        const table = element.shadowRoot.querySelector('lightning-datatable');
        table.dispatchEvent(new CustomEvent('rowaction', {
            detail: { action: { name: 'restore' }, row: table.data[0] }
        }));
        await flushPromises();

        expect(restoreRecord).toHaveBeenCalledWith({ recordId: ROW_1.recordId });
        // Post-action refresh: getArchivedItems called again (load + reload)
        expect(getArchivedItems).toHaveBeenCalledTimes(2);
    });

    it('bulk-restores selected rows and surfaces a mixed success/failure result', async () => {
        getArchivedItems.mockResolvedValueOnce([ROW_1, ROW_2]);
        restoreRecords.mockResolvedValue([
            { recordId: ROW_1.recordId, success: true, message: null },
            { recordId: ROW_2.recordId, success: false, message: 'Blocked: offering still archived.' }
        ]);

        const element = createElement('c-gtm-recycle-bin', { is: GtmRecycleBin });
        document.body.appendChild(element);
        await flushPromises();

        const table = element.shadowRoot.querySelector('lightning-datatable');
        table.dispatchEvent(new CustomEvent('rowselection', {
            detail: { selectedRows: [ROW_1, ROW_2] }
        }));
        await flushPromises();

        getArchivedItems.mockResolvedValueOnce([ROW_2]);

        const restoreButton = headerActionButtons(element)
            .find((b) => b.label === 'Restore selected');
        expect(restoreButton.disabled).toBe(false);
        restoreButton.click();
        await flushPromises();

        expect(restoreRecords).toHaveBeenCalledWith({
            recordIds: [ROW_1.recordId, ROW_2.recordId]
        });
        expect(getArchivedItems).toHaveBeenCalledTimes(2);
    });

    it('requires a selection before Delete Selected Permanently can be used', async () => {
        getArchivedItems.mockResolvedValue([ROW_1]);
        const element = createElement('c-gtm-recycle-bin', { is: GtmRecycleBin });
        document.body.appendChild(element);
        await flushPromises();

        const emptyTrashButton = headerActionButtons(element)
            .find((b) => b.label === 'Delete Selected Permanently');
        expect(emptyTrashButton.disabled).toBe(true);

        emptyTrashButton.click();
        await flushPromises();
        expect(element.shadowRoot.querySelector('.slds-modal')).toBeNull();
    });

    it('runs Delete Selected Permanently through a two-step confirmation modal before deleting the selection', async () => {
        getArchivedItems.mockResolvedValueOnce([ROW_1]);
        deleteRecords.mockResolvedValue([
            { recordId: ROW_1.recordId, success: true, message: null }
        ]);

        const element = createElement('c-gtm-recycle-bin', { is: GtmRecycleBin });
        document.body.appendChild(element);
        await flushPromises();

        const table = element.shadowRoot.querySelector('lightning-datatable');
        table.dispatchEvent(new CustomEvent('rowselection', {
            detail: { selectedRows: [ROW_1] }
        }));
        await flushPromises();

        const emptyTrashButton = headerActionButtons(element)
            .find((b) => b.label === 'Delete Selected Permanently');
        expect(emptyTrashButton.disabled).toBe(false);
        emptyTrashButton.click();
        await flushPromises();

        // Step one of the modal is open; deleteRecords must not have fired yet.
        expect(element.shadowRoot.querySelector('.slds-modal')).not.toBeNull();
        expect(deleteRecords).not.toHaveBeenCalled();

        let continueButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Continue');
        continueButton.click();
        await flushPromises();

        expect(deleteRecords).not.toHaveBeenCalled();

        getArchivedItems.mockResolvedValueOnce([]);
        const finalDeleteButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Permanently Delete');
        expect(finalDeleteButton).not.toBeNull();
        finalDeleteButton.click();
        await flushPromises();

        expect(deleteRecords).toHaveBeenCalledWith({ recordIds: [ROW_1.recordId] });
        expect(getArchivedItems).toHaveBeenCalledTimes(2);
        expect(element.shadowRoot.querySelector('.slds-modal')).toBeNull();
    });

    it('lets the confirmation modal be cancelled without deleting anything', async () => {
        getArchivedItems.mockResolvedValue([ROW_1]);
        const element = createElement('c-gtm-recycle-bin', { is: GtmRecycleBin });
        document.body.appendChild(element);
        await flushPromises();

        const table = element.shadowRoot.querySelector('lightning-datatable');
        table.dispatchEvent(new CustomEvent('rowselection', {
            detail: { selectedRows: [ROW_1] }
        }));
        await flushPromises();

        const emptyTrashButton = headerActionButtons(element)
            .find((b) => b.label === 'Delete Selected Permanently');
        emptyTrashButton.click();
        await flushPromises();

        const cancelButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Cancel');
        cancelButton.click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.slds-modal')).toBeNull();
        expect(deleteRecords).not.toHaveBeenCalled();
    });

    it('passes actions with Delete last (destructive, utility:delete) and disabled tracking the selection (issue page-header-actions-menu)', async () => {
        getArchivedItems.mockResolvedValue([ROW_1]);
        const element = createElement('c-gtm-recycle-bin', { is: GtmRecycleBin });
        document.body.appendChild(element);
        await flushPromises();

        let actions = element.shadowRoot.querySelector('c-gtm-page-header').actions;
        expect(actions.map((a) => a.name)).toEqual(['refresh', 'restore-selected', 'delete-selected']);
        expect(actions.map((a) => a.iconName)).toEqual(['utility:refresh', 'utility:undo', 'utility:delete']);
        expect(actions[2].variant).toBe('destructive');
        expect(actions.map((a) => a.disabled)).toEqual([false, true, true]);

        element.shadowRoot.querySelector('lightning-datatable').dispatchEvent(new CustomEvent('rowselection', {
            detail: { selectedRows: [ROW_1] }
        }));
        await flushPromises();
        actions = element.shadowRoot.querySelector('c-gtm-page-header').actions;
        expect(actions.map((a) => a.disabled)).toEqual([false, false, false]);
    });
});
