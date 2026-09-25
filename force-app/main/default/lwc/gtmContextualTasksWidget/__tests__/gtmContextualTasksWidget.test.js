/**
 * ISSUE #31
 *
 * gtmContextualTasksWidget: renders rows from
 * GtmContextualTasksController.getOpenTasksForAssessmentRequest and its
 * loading/error/empty states, mirroring gtmTasksDueTodayWidget's own test
 * shape (same navigation-mixin re-mock pattern, since the stock
 * sfdx-lwc-jest [NavigationMixin.Navigate] lives on a sealed prototype and
 * cannot be spied on in place).
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
import GtmContextualTasksWidget from 'c/gtmContextualTasksWidget';
import getOpenTasksForAssessmentRequest from '@salesforce/apex/GtmContextualTasksController.getOpenTasksForAssessmentRequest';

jest.mock(
    '@salesforce/apex/GtmContextualTasksController.getOpenTasksForAssessmentRequest',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function mount(props = {}) {
    const el = createElement('c-gtm-contextual-tasks-widget', { is: GtmContextualTasksWidget });
    Object.assign(el, { assessmentRequestId: 'a0R000000000099', ...props });
    document.body.appendChild(el);
    return el;
}

afterEach(() => {
    document.body.innerHTML = '';
    jest.clearAllMocks();
    mockNavigate.mockClear();
});

describe('gtmContextualTasksWidget', () => {
    it('renders open tasks with a due/overdue badge', async () => {
        getOpenTasksForAssessmentRequest.mockResolvedValue([
            { taskId: '1', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, status: 'Not Started', whatId: '003000000001AAA', whatObjectType: 'Contact' },
            { taskId: '2', subject: 'Follow up Beta', activityDate: '2026-09-18', isOverdue: true, status: 'Not Started', whatId: '001000000001AAA', whatObjectType: 'Account' }
        ]);
        const el = mount();
        await flushPromises();

        const rows = el.shadowRoot.querySelectorAll('[data-id="contextual-task-row"]');
        expect(rows.length).toBe(2);
        const labels = Array.from(el.shadowRoot.querySelectorAll('[data-id="contextual-task-due-label"]')).map((n) => n.textContent);
        expect(labels).toContain('Overdue');
        expect(el.shadowRoot.querySelector('[data-id="contextual-tasks-empty"]')).toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="contextual-tasks-error"]')).toBeNull();
    });

    it('shows the empty state when there are no open tasks', async () => {
        getOpenTasksForAssessmentRequest.mockResolvedValue([]);
        const el = mount();
        await flushPromises();

        expect(el.shadowRoot.querySelector('[data-id="contextual-tasks-empty"]')).not.toBeNull();
        expect(el.shadowRoot.querySelectorAll('[data-id="contextual-task-row"]').length).toBe(0);
    });

    it('shows an error state with retry on Apex failure', async () => {
        getOpenTasksForAssessmentRequest.mockRejectedValue({ body: { message: 'boom' } });
        const el = mount();
        await flushPromises();

        const errorEl = el.shadowRoot.querySelector('[data-id="contextual-tasks-error"]');
        expect(errorEl).not.toBeNull();
        expect(errorEl.textContent).toContain('boom');
    });

    it('retry re-calls the Apex method', async () => {
        getOpenTasksForAssessmentRequest.mockRejectedValueOnce({ body: { message: 'boom' } });
        const el = mount();
        await flushPromises();

        getOpenTasksForAssessmentRequest.mockResolvedValueOnce([
            { taskId: '1', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, status: 'Not Started', whatId: '003000000001AAA', whatObjectType: 'Contact' }
        ]);
        el.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(getOpenTasksForAssessmentRequest).toHaveBeenCalledTimes(2);
        expect(el.shadowRoot.querySelectorAll('[data-id="contextual-task-row"]').length).toBe(1);
    });

    it('never calls Apex with no assessmentRequestId', async () => {
        const el = mount({ assessmentRequestId: undefined });
        await flushPromises();

        expect(getOpenTasksForAssessmentRequest).not.toHaveBeenCalled();
        expect(el.shadowRoot.querySelector('[data-id="contextual-tasks-empty"]')).not.toBeNull();
    });

    it("clicking a row navigates to that Task's WhatId record, Activity tab", async () => {
        getOpenTasksForAssessmentRequest.mockResolvedValue([
            { taskId: '1', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, status: 'Not Started', whatId: '003000000001AAA', whatObjectType: 'Contact' }
        ]);
        const el = mount();
        await flushPromises();

        el.shadowRoot.querySelector('[data-id="contextual-task-row-main"]').dispatchEvent(new CustomEvent('click'));

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__recordPage',
            attributes: { recordId: '003000000001AAA', objectApiName: 'Contact', actionName: 'view' }
        });
    });

    it("clicking an Account-scoped row navigates with objectApiName Account", async () => {
        getOpenTasksForAssessmentRequest.mockResolvedValue([
            { taskId: '1', subject: 'Nudge', activityDate: '2026-09-22', isOverdue: false, status: 'Not Started', whatId: '001000000001AAA', whatObjectType: 'Account' }
        ]);
        const el = mount();
        await flushPromises();

        el.shadowRoot.querySelector('[data-id="contextual-task-row-main"]').dispatchEvent(new CustomEvent('click'));

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__recordPage',
            attributes: { recordId: '001000000001AAA', objectApiName: 'Account', actionName: 'view' }
        });
    });

    it('pressing Enter on a row navigates the same as a click', async () => {
        getOpenTasksForAssessmentRequest.mockResolvedValue([
            { taskId: '1', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, status: 'Not Started', whatId: '003000000001AAA', whatObjectType: 'Contact' }
        ]);
        const el = mount();
        await flushPromises();

        const rowMain = el.shadowRoot.querySelector('[data-id="contextual-task-row-main"]');
        rowMain.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));

        expect(mockNavigate).toHaveBeenCalledTimes(1);
    });

    it('ignores keys other than Enter/Space', async () => {
        getOpenTasksForAssessmentRequest.mockResolvedValue([
            { taskId: '1', subject: 'Call Acme', activityDate: '2026-09-22', isOverdue: false, status: 'Not Started', whatId: '003000000001AAA', whatObjectType: 'Contact' }
        ]);
        const el = mount();
        await flushPromises();

        const rowMain = el.shadowRoot.querySelector('[data-id="contextual-task-row-main"]');
        rowMain.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true }));

        expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('a task with no due date renders without a badge', async () => {
        getOpenTasksForAssessmentRequest.mockResolvedValue([
            { taskId: '1', subject: 'No due date', activityDate: null, isOverdue: false, status: 'Not Started', whatId: '003000000001AAA', whatObjectType: 'Contact' }
        ]);
        const el = mount();
        await flushPromises();

        expect(el.shadowRoot.querySelector('[data-id="contextual-task-due-label"]')).toBeNull();
    });
});
