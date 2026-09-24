import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHeatGridAura from '@salesforce/apex/GtmLinkStageService.getHeatGridAura';
import createFollowUpTask from '@salesforce/apex/GtmHeatGridActionsController.createFollowUpTask';
import { buildRows, encodeDefaultFieldValues } from './gtmHeatGridModel';

/**
 * "Who's hot right now" heat grid (issue overview-bd-heat-redesign-2-heat-grid).
 * Contract: docs/architecture/overview-bd-heat-redesign-2-heat-grid.md.
 *
 * Live on gtmOverview.html today as <c-gtm-heat-grid></c-gtm-heat-grid> (see
 * gtmOverview.html/.css and gtmOverview.dailyWidgets.test.js). It loads its
 * own data (GtmLinkStageService.getHeatGridAura, cacheable=false -- same
 * imperative-not-wired reasoning as GtmActTodayController.getActToday) on
 * connectedCallback and is fully self-loading, independent of whatever else
 * is on the page.
 */
export default class GtmHeatGrid extends NavigationMixin(LightningElement) {
    @track rows = [];
    @track loading = true;
    @track error = '';
    @track busyRowId = '';

    connectedCallback() {
        this.load();
    }

    load() {
        this.loading = true;
        return getHeatGridAura()
            .then((data) => {
                this.rows = buildRows((data && data.rows) || []);
                this.error = '';
            })
            .catch((e) => {
                this.rows = [];
                this.error = this.messageFrom(e) || 'The heat grid could not be loaded.';
            })
            .finally(() => { this.loading = false; });
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    get hasRows() { return this.rows.length > 0; }
    get showEmpty() { return !this.loading && !this.error && !this.hasRows; }

    /** gtmLinkCell dispatches a plain `rowaction` CustomEvent (not the
     *  lightning-datatable `rowaction` event shape) -- see gtmLinkCell.js:
     *  `detail: { action: { name }, row }`. */
    handleLinkCellAction(event) {
        const action = event.detail && event.detail.action;
        const row = event.detail && event.detail.row;
        if (!action || !row) return;
        if (action.name === 'openAccount' && row.accountId) {
            this.openRecord(row.accountId);
        } else if (action.name === 'openContact' && row.contactId) {
            this.openRecord(row.contactId);
        }
    }

    openRecord(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    /**
     * "Call now": client-side navigation only, no Apex -- the native Log a
     * Call quick action, pre-filled with WhoId (Contact)/WhatId
     * (Opportunity) from the row.
     */
    handleCallNow(event) {
        const row = this.rowFor(event);
        if (!row) return;
        const defaultFieldValues = encodeDefaultFieldValues({
            WhoId: row.contactId || undefined,
            WhatId: row.opportunityId || undefined
        });
        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: { apiName: 'Task.LogACall' },
            state: { defaultFieldValues }
        });
    }

    /** "Follow up": creates one Task on the row's Opportunity. */
    handleFollowUp(event) {
        const row = this.rowFor(event);
        if (!row || !row.opportunityId || this.busyRowId) return;
        this.busyRowId = row.accountId;
        createFollowUpTask({ opportunityId: row.opportunityId, accountName: row.accountName })
            .then(() => { this.error = ''; })
            .catch((e) => { this.error = this.messageFrom(e) || 'The follow-up task could not be created.'; })
            .finally(() => { this.busyRowId = ''; });
    }

    /** Dispatched by the disabled Nudge/Book-the-call buttons purely so a
     *  click/focus does not silently do nothing -- the button itself stays
     *  `disabled`; this only exists for keyboard users tabbing to a
     *  disabled control to still see the tooltip via aria/title. No-op. */
    handleDisabledAction() {
        // Intentionally empty: lightning-button disabled=true already blocks
        // activation; the tooltip is the whole explanation (see
        // gtmHeatGridModel's NUDGE_TOOLTIP/SCHEDULE_TOOLTIP).
    }

    handleActionClick(event) {
        const actionKey = event.currentTarget.dataset.action;
        if (actionKey === 'call_now') { this.handleCallNow(event); return; }
        if (actionKey === 'follow_up') { this.handleFollowUp(event); return; }
        this.handleDisabledAction();
    }

    rowFor(event) {
        const accountId = event.currentTarget.dataset.accountId;
        return this.rows.find((r) => r.accountId === accountId);
    }
}
