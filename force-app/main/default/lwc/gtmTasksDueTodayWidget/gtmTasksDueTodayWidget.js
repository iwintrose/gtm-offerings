import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTasksDueToday from '@salesforce/apex/GtmTasksDueTodayController.getTasksDueToday';
import markTaskComplete from '@salesforce/apex/GtmTasksDueTodayController.markTaskComplete';

/**
 * "Your tasks due today" widget on the Overview Today view (issue
 * overview-bd-heat-redesign-3-daily-widgets; mounted into gtmOverview.html
 * via overview-bd-heat-redesign-4-integration).
 *
 * Reads the rep's own open Tasks (due today or overdue) on GTM-linked
 * Accounts/Opportunities from GtmTasksDueTodayController -- all filtering
 * and scoping lives server-side; this component renders rows and
 * loading/error/empty states.
 *
 * Two distinct, separately-clickable targets per row (issue
 * tasks-widget-row-navigation):
 *   - The row's main content (subject/badge/account name) is click/Enter/
 *     Space-activatable and navigates to the Engagement Links landing tab
 *     (GTM_Engagement_Links), scoped to the task's own Account -- the SAME
 *     apiName/state-param shape as gtmOverview.js's handleAccountClick
 *     (issue-102-1-engagement-links-landing), not a bare
 *     `standard__recordPage` on the Task. GTM has no in-app "working view"
 *     of a bare Task, but it does of an Account's engagement links, which
 *     is what a rep chasing a task on that account actually wants next.
 *   - A "Mark complete" checkbox updates the Task's Status inline via
 *     GtmTasksDueTodayController.markTaskComplete, without navigating; on
 *     success the row removes itself (it is no longer due once complete).
 *     Its onchange/onclick handlers call event.stopPropagation() so
 *     checking it never also fires the row's own navigation.
 */
export default class GtmTasksDueTodayWidget extends NavigationMixin(LightningElement) {
    rows = [];
    isLoading = true;
    loadError = '';
    /** Separate from loadError on purpose: a failed "mark complete" must
     *  not blank out the whole rows list the way a failed initial load
     *  does -- the rep still needs to see and retry the other rows. */
    actionError = '';

    connectedCallback() {
        this.loadTasks();
    }

    loadTasks() {
        this.isLoading = true;
        this.loadError = '';
        this.actionError = '';
        let call;
        try {
            call = getTasksDueToday();
        } catch (e) {
            call = Promise.reject(e);
        }
        return Promise.resolve(call)
            .then((rows) => {
                this.rows = (rows || []).map((r) => this.toDisplayRow(r));
                this.loadError = '';
            })
            .catch((err) => {
                this.rows = [];
                this.loadError = this.messageFrom(err) || 'Tasks could not be loaded.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    toDisplayRow(r) {
        const dueLabel = r.isOverdue ? 'Overdue' : 'Due today';
        return {
            ...r,
            dueLabel,
            rowAriaLabel: `${r.subject}${r.whatName ? ', ' + r.whatName : ''}, ${dueLabel}`,
            completeLabel: `Mark "${r.subject}" complete`
        };
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    handleRetry() {
        this.loadTasks();
    }

    /**
     * Click, Enter or Space on a row's main content -> the Engagement
     * Links landing tab, scoped to that task's Account. Mirrors
     * gtmOverview.js's handleAccountClick exactly (same apiName/state-param
     * shape) -- no new navigation convention. A row with no resolved
     * accountId (rare: an Opportunity WhatId with no AccountId) has
     * nowhere in-app to route to, so it no-ops rather than guessing.
     */
    handleRowActivate(event) {
        if (event.type === 'keydown') {
            if (event.key !== 'Enter' && event.key !== ' ' && event.key !== 'Spacebar') return;
            // Space would otherwise scroll the page.
            event.preventDefault();
        }
        const accountId = event.currentTarget.dataset.accountId;
        if (!accountId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Engagement_Links' },
            state: { c__rlfAccountId: accountId }
        });
    }

    /** Blocks the click from bubbling into any ancestor row-activate
     *  handler -- belt-and-suspenders alongside the checkbox living outside
     *  the row-main click target in the markup. */
    handleCheckboxClick(event) {
        event.stopPropagation();
    }

    /** The actual "mark complete" action, fired on the checkbox's change
     *  event. Also stops propagation for the same reason as
     *  handleCheckboxClick -- change events bubble too. */
    handleCompleteChange(event) {
        event.stopPropagation();
        const checkboxEl = event.currentTarget;
        const taskId = checkboxEl.dataset.taskId;
        if (!taskId) return;
        this.actionError = '';
        checkboxEl.disabled = true;

        let call;
        try {
            call = markTaskComplete({ taskId });
        } catch (e) {
            call = Promise.reject(e);
        }
        return Promise.resolve(call)
            .then(() => {
                // No longer due once complete -- drop it from the list.
                this.rows = this.rows.filter((row) => row.taskId !== taskId);
            })
            .catch((err) => {
                checkboxEl.checked = false;
                checkboxEl.disabled = false;
                this.actionError = this.messageFrom(err) || 'Could not mark that task complete.';
            });
    }

    get hasRows() { return this.rows.length > 0; }
    get showEmpty() { return !this.isLoading && !this.loadError && !this.hasRows; }
    get showRows() { return !this.isLoading && !this.loadError && this.hasRows; }
}
