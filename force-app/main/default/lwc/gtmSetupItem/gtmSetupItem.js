import { LightningElement, api } from 'lwc';

/**
 * Presentational row for the guided Setup checklist (gtmSetupChecklist owns
 * all state and Apex; this component holds none of it). Contract:
 * docs/architecture/guided-setup-implementation-plan.md section 2.6.
 *
 * Events (neither bubbles nor is composed):
 *  - itemaction { key, actionType, permissionSetName, linkKind, navApiName,
 *                 navState, setupPath, userId }
 *  - pickersearch { term }
 *
 * NOT_SET, INFO and OPTIONAL rows are deliberately neutral: never an error
 * or warning treatment, so an unset API key never reads as a failure.
 */
const ICONS = {
    DONE: { name: 'utility:success', cls: 'slds-icon-text-success', alt: 'Done' },
    TODO: { name: 'utility:record', cls: 'slds-icon-text-default', alt: 'To do' },
    NOT_SET: { name: 'utility:dash', cls: 'slds-icon-text-default', alt: 'Not set' },
    BLOCKED: { name: 'utility:lock', cls: 'slds-icon-text-default', alt: 'Blocked' },
    UNKNOWN: { name: 'utility:question', cls: 'slds-icon-text-default', alt: 'Could not be verified' },
    INFO: { name: 'utility:info', cls: 'slds-icon-text-default', alt: 'Information' }
};

export default class GtmSetupItem extends LightningElement {
    @api item;
    @api busy = false;
    @api pickerUsers = [];

    expandedOverride;
    selectedUserId;

    get key() {
        return this.item && this.item.key;
    }

    get icon() {
        return ICONS[this.item && this.item.status] || ICONS.UNKNOWN;
    }

    get iconClass() {
        return this.icon.cls;
    }

    get rowClass() {
        const status = (this.item && this.item.status) || 'UNKNOWN';
        return `setup-item setup-item_${status.toLowerCase().replace('_', '-')}`;
    }

    get isNeutral() {
        const i = this.item || {};
        return i.status === 'NOT_SET' || i.status === 'INFO' || i.tier === 'OPTIONAL' || i.tier === 'INFO';
    }

    get isCollapsible() {
        return !!(this.item && this.item.collapsedByDefault);
    }

    get isExpanded() {
        if (!this.isCollapsible) {
            return true;
        }
        return this.expandedOverride === undefined ? false : this.expandedOverride;
    }

    get toggleIcon() {
        return this.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get toggleLabel() {
        return `${this.isExpanded ? 'Collapse' : 'Expand'} ${this.item ? this.item.title : ''}`;
    }

    get marker() {
        if (!this.item || this.item.status === 'DONE') {
            return '';
        }
        return this.item.humanMustAct ? 'You need to do this' : 'Done for you';
    }

    get hasDetail() {
        return !!(this.item && this.item.detail);
    }

    get hasBlockedBy() {
        return !!(this.item && this.item.blockedBy && this.item.blockedBy.length);
    }

    get blockedByText() {
        return this.hasBlockedBy ? `Waiting on: ${this.item.blockedBy.join(', ')}` : '';
    }

    get hasAction() {
        const t = this.item && this.item.actionType;
        return !!t && t !== 'NONE';
    }

    get isPicker() {
        return this.item && this.item.actionType === 'ASSIGN_PICKER';
    }

    get isSimpleAction() {
        return this.hasAction && !this.isPicker;
    }

    get actionLabel() {
        return (this.item && this.item.actionLabel) || 'Go';
    }

    get actionDisabled() {
        return this.busy === true || this.item.status === 'BLOCKED';
    }

    get assignDisabled() {
        return this.actionDisabled || !this.selectedUserId;
    }

    get pickerOptions() {
        return this.pickerUsers || [];
    }

    handleToggle() {
        this.expandedOverride = !this.isExpanded;
    }

    fire(userId) {
        const i = this.item;
        this.dispatchEvent(
            new CustomEvent('itemaction', {
                detail: {
                    key: i.key,
                    actionType: i.actionType,
                    permissionSetName: i.permissionSetName,
                    linkKind: i.linkKind,
                    navApiName: i.navApiName,
                    navState: i.navState,
                    setupPath: i.setupPath,
                    userId
                }
            })
        );
    }

    handleAction() {
        if (this.actionDisabled) {
            return;
        }
        this.fire(undefined);
    }

    handleAssign() {
        if (this.assignDisabled) {
            return;
        }
        this.fire(this.selectedUserId);
    }

    handlePickerChange(event) {
        this.selectedUserId = event.detail.value;
    }

    handleSearch(event) {
        this.dispatchEvent(
            new CustomEvent('pickersearch', { detail: { term: event.target.value } })
        );
    }
}
