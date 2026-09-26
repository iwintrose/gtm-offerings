import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getOpenTasksForAssessmentRequest from '@salesforce/apex/GtmContextualTasksController.getOpenTasksForAssessmentRequest';

/**
 * Contextual-task widget (issue #31): mounted inside gtmReadoutWorkspace,
 * shared by both entry paths a rep opens a specific link/assessment from
 * (gtmRepLinkFinder/GTM_Pages and gtmReadoutsOverview/GTM_Assessments both
 * mount c-gtm-readout-workspace -- see that component's own header). Shows
 * every open Task on THIS record's Contact/Account, so a rep working one
 * record is not blind to a follow-up that the retired "Engagement Links"
 * tab used to be the only place to see.
 *
 * A scoped reuse of gtmTasksDueTodayWidget's row shape/style (Architect
 * decision #4), not the same component verbatim -- that widget is
 * hardcoded to the running user's own "due today or overdue" Tasks;
 * this one shows every open Task on the record, regardless of owner or
 * due date, backed by its own narrow GtmContextualTasksController rather
 * than bending that controller's existing "due today" contract.
 *
 * Single public API, matching decision #4's "keep the widget's public API
 * to a single Id" instruction: assessmentRequestId, which
 * gtmReadoutWorkspace already has as @api and passes straight through.
 * Contact/Account resolution happens server-side off that one Id -- this
 * component never needs, and is never given, either Id directly.
 */
export default class GtmContextualTasksWidget extends NavigationMixin(LightningElement) {
    @api assessmentRequestId;

    rows = [];
    isLoading = true;
    loadError = '';

    connectedCallback() {
        this.loadTasks();
    }

    loadTasks() {
        if (!this.assessmentRequestId) {
            this.isLoading = false;
            this.rows = [];
            return undefined;
        }
        this.isLoading = true;
        this.loadError = '';
        let call;
        try {
            call = getOpenTasksForAssessmentRequest({ assessmentRequestId: this.assessmentRequestId });
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
                this.loadError = this.messageFrom(err) || 'Open tasks could not be loaded.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    toDisplayRow(r) {
        const dueLabel = r.activityDate ? (r.isOverdue ? 'Overdue' : 'Due ' + r.activityDate) : '';
        return {
            ...r,
            dueLabel,
            rowAriaLabel: `${r.subject}${dueLabel ? ', ' + dueLabel : ''}`
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

    /** Click, Enter or Space on a row -> that Task's WhatId record
     *  (Contact or Account -- whatObjectType tells us which, resolved
     *  server-side so this component never sniffs the Id prefix),
     *  Activity tab. Same shape as gtmTasksDueTodayWidget/gtmOverview's own
     *  row click-throughs (issue #31). */
    handleRowActivate(event) {
        if (event.type === 'keydown') {
            if (event.key !== 'Enter' && event.key !== ' ' && event.key !== 'Spacebar') return;
            event.preventDefault();
        }
        const whatId = event.currentTarget.dataset.whatId;
        const whatObjectType = event.currentTarget.dataset.whatObjectType;
        if (!whatId || !whatObjectType) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: whatId, objectApiName: whatObjectType, actionName: 'view' }
        });
    }

    get hasRows() { return this.rows.length > 0; }
    get showEmpty() { return !this.isLoading && !this.loadError && !this.hasRows; }
    get showRows() { return !this.isLoading && !this.loadError && this.hasRows; }
}
