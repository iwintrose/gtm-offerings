/**
 * ISSUE #overview-bd-heat-redesign-3-daily-widgets
 *
 * gtmTasksDueTodayWidget: renders rows from GtmTasksDueTodayController and
 * its loading/error/empty states. Standalone component test, but the
 * component itself IS mounted into gtmOverview.html (see
 * overview-bd-heat-redesign-4-integration).
 *
 * ISSUE #tasks-widget-row-navigation: each row has two distinct,
 * separately-clickable targets -- the main content (click/Enter/Space)
 * navigates to the Engagement Links landing tab scoped to the task's
 * Account, and an inline "Mark complete" checkbox completes the Task via
 * Apex without navigating, removing the row on success. The stock
 * sfdx-lwc-jest navigation stub's [NavigationMixin.Navigate] lives on a
 * sealed prototype and cannot be spied on in place, so this module is
 * re-mocked with a Navigate that forwards to an inspectable jest.fn(),
 * same pattern as gtmHeatGrid.test.js.
 */
const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) => {
        return class extends Base {
            [Navigate](...args) {
                mockNavigate(...args);
            }
        };
    };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin };
});

// eslint-disable-next-line import/first, import/order
import { createElement } from 'lwc';
// eslint-disable-next-line import/first
import GtmTasksDueTodayWidget from 'c/gtmTasksDueTodayWidget';
import getTasksDueToday from '@salesforce/apex/GtmTasksDueTodayController.getTasksDueToday';
import markTaskComplete from '@salesforce/apex/GtmTasksDueTodayController.markTaskComplete';

jest.mock(
    '@salesforce/apex/GtmTasksDueTodayController.getTasksDueToday',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmTasksDueTodayController.markTaskComplete',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function mount() {
    const el = createElement('c-gtm-tasks-due-today-widget', { is: GtmTasksDueTodayWidget });
    document.body.appendChild(el);
    return el;
}

afterEach(() => {
    document.body.innerHTML = '';
    jest.clearAllMocks();
    mockNavigate.mockClear();
});

describe('gtmTasksDueTodayWidget', () => {
    it('renders rows with due-today and overdue labels', async () => {
        getTasksDueToday.mockResolvedValue([
            { taskId: '1', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, whatId: 'a1', whatName: 'Acme Inc', accountId: 'a1' },
            { taskId: '2', subject: 'Follow up Beta', activityDate: '2026-09-18', isOverdue: true, whatId: 'a2', whatName: 'Beta Co', accountId: 'a2' }
        ]);
        const el = mount();
        await flushPromises();

        const rows = el.shadowRoot.querySelectorAll('[data-id="task-row"]');
        expect(rows.length).toBe(2);
        const labels = Array.from(el.shadowRoot.querySelectorAll('[data-id="task-due-label"]')).map((n) => n.textContent);
        expect(labels).toContain('Due today');
        expect(labels).toContain('Overdue');
        expect(el.shadowRoot.querySelector('[data-id="tasks-empty"]')).toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="tasks-error"]')).toBeNull();
    });

    it('shows the empty state when there are no rows', async () => {
        getTasksDueToday.mockResolvedValue([]);
        const el = mount();
        await flushPromises();

        expect(el.shadowRoot.querySelector('[data-id="tasks-empty"]')).not.toBeNull();
        expect(el.shadowRoot.querySelectorAll('[data-id="task-row"]').length).toBe(0);
    });

    it('shows an error state with retry on Apex failure', async () => {
        getTasksDueToday.mockRejectedValue({ body: { message: 'boom' } });
        const el = mount();
        await flushPromises();

        const errorEl = el.shadowRoot.querySelector('[data-id="tasks-error"]');
        expect(errorEl).not.toBeNull();
        expect(errorEl.textContent).toContain('boom');
    });

    it('is keyboard-accessible: role=button and tabindex=0 on the row\'s main content', async () => {
        getTasksDueToday.mockResolvedValue([
            { taskId: '1', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, whatId: 'a1', whatName: 'Acme Inc', accountId: 'a1' }
        ]);
        const el = mount();
        await flushPromises();

        const rowMain = el.shadowRoot.querySelector('[data-id="task-row-main"]');
        expect(rowMain.getAttribute('role')).toBe('button');
        expect(rowMain.getAttribute('tabindex')).toBe('0');
        expect(rowMain.getAttribute('aria-label')).toBe('Call Acme, Acme Inc, Due today');
    });

    it('the task subject and account name stay visibly rendered in the row', async () => {
        getTasksDueToday.mockResolvedValue([
            { taskId: '1', subject: 'Call Acme about renewal', activityDate: '2026-09-22', isOverdue: false, whatId: 'a1', whatName: 'Acme Inc', accountId: 'a1' }
        ]);
        const el = mount();
        await flushPromises();

        const rowMain = el.shadowRoot.querySelector('[data-id="task-row-main"]');
        expect(rowMain.textContent).toContain('Call Acme about renewal');
        expect(rowMain.textContent).toContain('Acme Inc');
    });

    it("clicking a row's main content navigates to that task's Account record, Activity tab", async () => {
        getTasksDueToday.mockResolvedValue([
            { taskId: '00T000000001AAA', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, whatId: '001000000001AAA', whatName: 'Acme Inc', accountId: '001000000001AAA' },
            { taskId: '00T000000002BBB', subject: 'Follow up Beta', activityDate: '2026-09-18', isOverdue: true, whatId: '006000000002BBB', whatName: 'Beta Co', accountId: '001000000002BBB' }
        ]);
        const el = mount();
        await flushPromises();

        const rows = el.shadowRoot.querySelectorAll('[data-id="task-row-main"]');
        rows[1].dispatchEvent(new CustomEvent('click'));

        expect(mockNavigate).toHaveBeenCalledTimes(1);
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__recordPage',
            attributes: { recordId: '001000000002BBB', objectApiName: 'Account', actionName: 'view' }
        });
    });

    it('pressing Enter on the row\'s main content navigates the same as a click', async () => {
        getTasksDueToday.mockResolvedValue([
            { taskId: '00T000000001AAA', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, whatId: '001000000001AAA', whatName: 'Acme Inc', accountId: '001000000001AAA' }
        ]);
        const el = mount();
        await flushPromises();

        const rowMain = el.shadowRoot.querySelector('[data-id="task-row-main"]');
        rowMain.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));

        expect(mockNavigate).toHaveBeenCalledTimes(1);
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__recordPage',
            attributes: { recordId: '001000000001AAA', objectApiName: 'Account', actionName: 'view' }
        });
    });

    it('pressing Space on the row\'s main content navigates and prevents the page from scrolling', async () => {
        getTasksDueToday.mockResolvedValue([
            { taskId: '00T000000001AAA', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, whatId: '001000000001AAA', whatName: 'Acme Inc', accountId: '001000000001AAA' }
        ]);
        const el = mount();
        await flushPromises();

        const rowMain = el.shadowRoot.querySelector('[data-id="task-row-main"]');
        const evt = new KeyboardEvent('keydown', { key: ' ', bubbles: true, cancelable: true });
        const preventDefaultSpy = jest.spyOn(evt, 'preventDefault');
        rowMain.dispatchEvent(evt);

        expect(preventDefaultSpy).toHaveBeenCalled();
        expect(mockNavigate).toHaveBeenCalledTimes(1);
    });

    it('ignores keys other than Enter/Space', async () => {
        getTasksDueToday.mockResolvedValue([
            { taskId: '00T000000001AAA', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, whatId: '001000000001AAA', whatName: 'Acme Inc', accountId: '001000000001AAA' }
        ]);
        const el = mount();
        await flushPromises();

        const rowMain = el.shadowRoot.querySelector('[data-id="task-row-main"]');
        rowMain.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true }));

        expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('does not navigate when a row has no resolved Account (e.g. an Opportunity with no AccountId)', async () => {
        getTasksDueToday.mockResolvedValue([
            { taskId: '00T000000001AAA', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, whatId: '006000000001AAA', whatName: 'Acme Inc', accountId: null }
        ]);
        const el = mount();
        await flushPromises();

        const rowMain = el.shadowRoot.querySelector('[data-id="task-row-main"]');
        rowMain.dispatchEvent(new CustomEvent('click'));

        expect(mockNavigate).not.toHaveBeenCalled();
    });

    describe('inline "Mark complete" checkbox', () => {
        it('renders one checkbox per row', async () => {
            getTasksDueToday.mockResolvedValue([
                { taskId: '1', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, whatId: 'a1', whatName: 'Acme Inc', accountId: 'a1' },
                { taskId: '2', subject: 'Follow up Beta', activityDate: '2026-09-18', isOverdue: true, whatId: 'a2', whatName: 'Beta Co', accountId: 'a2' }
            ]);
            const el = mount();
            await flushPromises();

            expect(el.shadowRoot.querySelectorAll('[data-id="task-complete-checkbox"]').length).toBe(2);
        });

        it('calls markTaskComplete with the row\'s task id when checked', async () => {
            getTasksDueToday.mockResolvedValue([
                { taskId: '00T000000001AAA', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, whatId: '001000000001AAA', whatName: 'Acme Inc', accountId: '001000000001AAA' }
            ]);
            markTaskComplete.mockResolvedValue(undefined);
            const el = mount();
            await flushPromises();

            const checkbox = el.shadowRoot.querySelector('[data-id="task-complete-checkbox"]');
            checkbox.dispatchEvent(new CustomEvent('change', { target: { checked: true } }));
            await flushPromises();

            expect(markTaskComplete).toHaveBeenCalledTimes(1);
            expect(markTaskComplete).toHaveBeenCalledWith({ taskId: '00T000000001AAA' });
        });

        it('does NOT trigger row navigation when the checkbox is clicked or changed', async () => {
            getTasksDueToday.mockResolvedValue([
                { taskId: '00T000000001AAA', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, whatId: '001000000001AAA', whatName: 'Acme Inc', accountId: '001000000001AAA' }
            ]);
            markTaskComplete.mockResolvedValue(undefined);
            const el = mount();
            await flushPromises();

            const checkbox = el.shadowRoot.querySelector('[data-id="task-complete-checkbox"]');
            checkbox.dispatchEvent(new CustomEvent('click', { bubbles: true }));
            checkbox.dispatchEvent(new CustomEvent('change', { bubbles: true, target: { checked: true } }));
            await flushPromises();

            expect(mockNavigate).not.toHaveBeenCalled();
        });

        it('removes the row from the list on successful completion', async () => {
            getTasksDueToday.mockResolvedValue([
                { taskId: '00T000000001AAA', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, whatId: '001000000001AAA', whatName: 'Acme Inc', accountId: '001000000001AAA' },
                { taskId: '00T000000002BBB', subject: 'Follow up Beta', activityDate: '2026-09-18', isOverdue: true, whatId: '001000000002BBB', whatName: 'Beta Co', accountId: '001000000002BBB' }
            ]);
            markTaskComplete.mockResolvedValue(undefined);
            const el = mount();
            await flushPromises();

            expect(el.shadowRoot.querySelectorAll('[data-id="task-row"]').length).toBe(2);

            const checkbox = el.shadowRoot.querySelector('[data-task-id="00T000000001AAA"][data-id="task-complete-checkbox"]');
            checkbox.dispatchEvent(new CustomEvent('change', { target: { checked: true } }));
            await flushPromises();

            const remainingRows = el.shadowRoot.querySelectorAll('[data-id="task-row"]');
            expect(remainingRows.length).toBe(1);
            expect(remainingRows[0].dataset.taskId).toBe('00T000000002BBB');
        });

        it('shows the empty state once the only row is completed', async () => {
            getTasksDueToday.mockResolvedValue([
                { taskId: '00T000000001AAA', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, whatId: '001000000001AAA', whatName: 'Acme Inc', accountId: '001000000001AAA' }
            ]);
            markTaskComplete.mockResolvedValue(undefined);
            const el = mount();
            await flushPromises();

            const checkbox = el.shadowRoot.querySelector('[data-id="task-complete-checkbox"]');
            checkbox.dispatchEvent(new CustomEvent('change', { target: { checked: true } }));
            await flushPromises();

            expect(el.shadowRoot.querySelectorAll('[data-id="task-row"]').length).toBe(0);
            expect(el.shadowRoot.querySelector('[data-id="tasks-empty"]')).not.toBeNull();
        });

        it('keeps the row and shows an action error when markTaskComplete fails', async () => {
            getTasksDueToday.mockResolvedValue([
                { taskId: '00T000000001AAA', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, whatId: '001000000001AAA', whatName: 'Acme Inc', accountId: '001000000001AAA' }
            ]);
            markTaskComplete.mockRejectedValue({ body: { message: 'Only this task\'s owner can mark it complete.' } });
            const el = mount();
            await flushPromises();

            const checkbox = el.shadowRoot.querySelector('[data-id="task-complete-checkbox"]');
            checkbox.dispatchEvent(new CustomEvent('change', { target: { checked: true } }));
            await flushPromises();

            expect(el.shadowRoot.querySelectorAll('[data-id="task-row"]').length).toBe(1);
            const actionError = el.shadowRoot.querySelector('[data-id="tasks-action-error"]');
            expect(actionError).not.toBeNull();
            expect(actionError.textContent).toContain("Only this task's owner can mark it complete.");
        });
    });
});
