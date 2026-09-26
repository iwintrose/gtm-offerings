import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getChecklist from '@salesforce/apex/GtmSetupChecklistController.getChecklist';
import searchAssignableUsers from '@salesforce/apex/GtmSetupChecklistController.searchAssignableUsers';
import assignPermissionSet from '@salesforce/apex/GtmSetupActionController.assignPermissionSet';
import assignPermissionSetToMe from '@salesforce/apex/GtmSetupActionController.assignPermissionSetToMe';
import createFrameworkPage from '@salesforce/apex/GtmSetupActionController.createFrameworkPage';
import getStatuses from '@salesforce/apex/GtmScheduledJobsController.getStatuses';
import scheduleJob from '@salesforce/apex/GtmScheduledJobsController.scheduleJob';
import { starterFor } from 'c/gtmPageLayouts';

/**
 * Guided Setup checklist (container). Derive-only: every load and Re-check
 * asks the server for the live state and renders exactly that. This component
 * never stores or infers a "done" flag; after any action it re-fetches the
 * whole checklist. Contract: docs/architecture/guided-setup-implementation-plan.md
 * section 2.6.
 */

const TIER_ORDER = ['REQUIRED', 'RECOMMENDED', 'OPTIONAL', 'INFO'];
const TIER_LABELS = {
    REQUIRED: 'Required',
    RECOMMENDED: 'Recommended',
    OPTIONAL: 'Optional',
    INFO: 'For your information'
};
const TIER_HINTS = {
    REQUIRED: 'These count toward the total above.',
    RECOMMENDED: 'Worth doing, but the app works without them.',
    OPTIONAL: 'Nothing here is needed. Skip anything you do not want.',
    INFO: 'Things this app needs from your org that only Salesforce Setup can change.'
};
const FRAMEWORK_TEMPLATES = ['offerings-page', 'industry-chooser', 'faq-bd', 'faq-content-manager', 'assistant'];
const SCHEDULED_JOB_KEYS = ['purgeRecordsBatch', 'assessmentDraftPurge'];
// Rows that point at another section of the Settings tab, not at a page.
const SETTINGS_SECTION_BY_KEY = {
    analytics_digest: 'analytics-notifications',
    ai_keys: 'claude-gus',
    approval_routing: 'approval-routing',
    agentforce_agent: 'claude-gus'
};
const GENERIC_ERROR = 'Something went wrong. Nothing was changed. Try Re-check, then try again.';

export default class GtmSetupChecklist extends NavigationMixin(LightningElement) {
    checklist = null;
    loading = false;
    errorMessage = '';
    busyKey = '';
    // { title, message, setupPath } when an inline action fell back to Setup.
    actionNotice = null;
    pickerUsers = [];
    // Tiers the admin has expanded. UI state only, never row status.
    expandedTiers = {};

    connectedCallback() {
        this.load();
    }

    // ---- loading -------------------------------------------------------

    // keepError: after a failed action the re-fetch must not wipe its message.
    async load(keepError = false) {
        this.loading = true;
        if (!keepError) this.errorMessage = '';
        try {
            this.checklist = await getChecklist();
        } catch (e) {
            this.errorMessage = this.messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    handleRecheck() {
        this.actionNotice = null;
        return this.load();
    }

    // ---- derived view --------------------------------------------------

    get hasChecklist() {
        return !!this.checklist;
    }

    get headerText() {
        if (!this.checklist) return '';
        const total = this.checklist.requiredTotal || 0;
        const done = this.checklist.requiredDone || 0;
        let text = `${done} of ${total} required steps done`;
        const unknown = this.checklist.requiredUnknown || 0;
        if (unknown > 0) text += `, ${unknown} could not be verified`;
        return text;
    }

    get progressValue() {
        if (!this.checklist || !this.checklist.requiredTotal) return 0;
        return Math.round((100 * (this.checklist.requiredDone || 0)) / this.checklist.requiredTotal);
    }

    get groups() {
        const items = (this.checklist && this.checklist.items) || [];
        return TIER_ORDER.map((tier) => {
            const tierItems = items.filter((i) => i.tier === tier);
            const collapsible = tierItems.length > 0 && tierItems.every((i) => i.collapsedByDefault);
            const expanded = !collapsible || !!this.expandedTiers[tier];
            return {
                tier,
                label: TIER_LABELS[tier],
                hint: TIER_HINTS[tier],
                count: tierItems.length,
                countLabel: `${tierItems.length} ${tierItems.length === 1 ? 'item' : 'items'}`,
                collapsible,
                expanded,
                toggleIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
                toggleLabel: `${expanded ? 'Hide' : 'Show'} ${TIER_LABELS[tier]}`,
                rows: tierItems.map((item) => ({
                    key: item.key,
                    item,
                    busy: this.busyKey === item.key,
                    pickerUsers: item.actionType === 'ASSIGN_PICKER' ? this.pickerUsers : []
                }))
            };
        }).filter((g) => g.count > 0);
    }

    get showNotice() {
        return !!this.actionNotice;
    }

    get recheckDisabled() {
        return this.loading || !!this.busyKey;
    }

    // ---- section toggles ----------------------------------------------

    handleToggleTier(event) {
        const tier = event.currentTarget.dataset.tier;
        this.expandedTiers = { ...this.expandedTiers, [tier]: !this.expandedTiers[tier] };
    }

    // ---- item events ---------------------------------------------------

    async handlePickerSearch(event) {
        const term = ((event.detail && event.detail.term) || '').trim();
        try {
            const users = await searchAssignableUsers({ searchTerm: term });
            this.pickerUsers = (users || []).map((u) => ({
                value: u.userId,
                label: u.username ? `${u.name} (${u.username})` : u.name
            }));
        } catch (e) {
            this.pickerUsers = [];
            this.errorMessage = this.messageFrom(e);
        }
    }

    async handleItemAction(event) {
        const detail = event.detail || {};
        const { key, actionType } = detail;
        this.errorMessage = '';
        this.actionNotice = null;

        if (actionType === 'LINK' || actionType === 'NONE' || !actionType) {
            this.followLink(detail);
            return;
        }

        this.busyKey = key;
        try {
            if (actionType === 'ASSIGN_TO_ME') {
                this.applyAssignResult(
                    key,
                    await assignPermissionSetToMe({ permissionSetName: detail.permissionSetName })
                );
            } else if (actionType === 'ASSIGN_PICKER') {
                this.applyAssignResult(
                    key,
                    await assignPermissionSet({
                        userId: detail.userId,
                        permissionSetName: detail.permissionSetName
                    })
                );
            } else if (actionType === 'SCHEDULE_JOBS') {
                await this.runScheduleJobs();
            } else if (actionType === 'CREATE_FRAMEWORK_PAGES') {
                await this.runCreateFrameworkPages(key);
            }
        } catch (e) {
            this.errorMessage = this.messageFrom(e);
        } finally {
            this.busyKey = '';
        }
        // Never trust the action result as "done": ask the server again.
        await this.load(true);
    }

    // ---- actions -------------------------------------------------------

    applyAssignResult(key, result) {
        if (result && result.fallbackToSetup) {
            this.actionNotice = {
                title: this.titleFor(key),
                message:
                    result.message ||
                    'This could not be done here. Do it in Salesforce Setup instead.',
                setupPath: result.setupPath || null
            };
        }
    }

    async runScheduleJobs() {
        const statuses = await getStatuses();
        const pending = (statuses || []).filter((s) => !s.isScheduled).map((s) => s.jobKey);
        // scheduleJob is idempotent, so if status came back empty try both.
        const keys = (statuses || []).length ? pending : SCHEDULED_JOB_KEYS;
        for (const jobKey of keys) {
            await scheduleJob({ jobKey });
        }
    }

    async runCreateFrameworkPages(key) {
        const missing = this.missingTemplates(key);
        let firstError = null;
        for (const templateType of missing) {
            try {
                await createFrameworkPage({
                    templateType,
                    sections: starterFor(templateType)
                });
            } catch (e) {
                // Keep going: the other pages are independent transactions and
                // the re-fetch afterwards shows the true state.
                if (!firstError) firstError = e;
            }
        }
        if (firstError) this.errorMessage = this.messageFrom(firstError);
    }

    // The row's detail lists the missing templates; when it cannot be parsed,
    // fall back to all five (the server call is idempotent per template).
    missingTemplates(key) {
        const item = this.itemFor(key);
        const detail = (item && item.detail) || '';
        const named = FRAMEWORK_TEMPLATES.filter((t) => new RegExp(`(^|[^a-z-])${t}([^a-z-]|$)`).test(detail));
        return named.length ? named : FRAMEWORK_TEMPLATES;
    }

    followLink(detail) {
        const sectionId = SETTINGS_SECTION_BY_KEY[detail.key];
        if (sectionId) {
            this.dispatchEvent(new CustomEvent('selectsection', { detail: { sectionId } }));
            return;
        }
        if (detail.linkKind === 'NAV_ITEM' && detail.navApiName) {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: detail.navApiName },
                state: detail.navState || {}
            });
        } else if (detail.linkKind === 'SETUP_PATH' && detail.setupPath) {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: { url: detail.setupPath }
            });
        }
    }

    handleNoticeLink(event) {
        event.preventDefault();
        if (this.actionNotice && this.actionNotice.setupPath) {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: { url: this.actionNotice.setupPath }
            });
        }
    }

    // ---- helpers -------------------------------------------------------

    itemFor(key) {
        return ((this.checklist && this.checklist.items) || []).find((i) => i.key === key);
    }

    titleFor(key) {
        const item = this.itemFor(key);
        return item ? item.title : key;
    }

    messageFrom(error) {
        const body = error && error.body;
        if (body && typeof body.message === 'string' && body.message) return body.message;
        if (error && typeof error.message === 'string' && error.message) return error.message;
        return GENERIC_ERROR;
    }
}
