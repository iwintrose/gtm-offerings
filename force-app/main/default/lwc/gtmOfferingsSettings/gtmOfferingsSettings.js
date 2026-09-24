import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

/**
 * Admin-only shell tab (GTM_Offerings_Settings) that hosts every GTM
 * Offerings admin-configuration concern behind a single internal nav
 * rail of sections, per ADR-0010 (one tab, many sections -- not many
 * standalone tabs).
 *
 * This component owns no settings logic itself: each section is a
 * self-contained child component (e.g. c-gtm-readout-approval-settings)
 * that this shell simply mounts based on the selected nav item.
 *
 * Unit 1 shipped "Approval Routing" (migrated from the retired standalone
 * GTM_Readout_Approval_Settings tab). "Analytics Notifications" (issue
 * #147) folds in what would otherwise have been a standalone GTM_Settings
 * tab -- same one-tab-many-sections pattern. "Claude / GUS" (Unit 2 of
 * ADR-0010) exposes GTM_Agent_Settings__c through gtmOfferingsSettingsAgent.
 * "Scheduled Jobs" (issue #184-purge-batch-autoschedule) exposes
 * GtmScheduledJobsController so an admin can activate the two purge jobs
 * without Setup/CLI access. "Setup" is the default guided checklist
 * (gtmSetupChecklist); it fires selectsection { sectionId } to jump to a
sibling section. "Recycle Bin" (issue #184) hosts the shared
 * gtmRecycleBin component -- the standalone GTM_RecycleBin tab/app-page
 * route it used to live at is retired per the issue's placement redirect.
 * "Notifications" (ADR-0010 Unit 3) exposes GTM_Notification_Settings__c
 * through gtmOfferingsSettingsNotifications -- nine fields gating six
 * existing readout/assessment-request lifecycle Apex trigger points
 * (submitForApproval/publishReadout/returnToDraft, stampApproval, and the
 * new-assessment-request path).
 */
const SECTIONS = [
    { id: 'setup', label: 'Setup' },
    { id: 'approval-routing', label: 'Approval Routing' },
    { id: 'analytics-notifications', label: 'Analytics Notifications' },
    { id: 'claude-gus', label: 'Claude / GUS' },
    { id: 'scheduled-jobs', label: 'Scheduled Jobs' },
    { id: 'recycle-bin', label: 'Recycle Bin' },
    { id: 'notifications', label: 'Notifications' }
];

export default class GtmOfferingsSettings extends LightningElement {
    @track selectedSectionId = SECTIONS[0].id;

    // Deep-link support, e.g. gtmContentHome-style navigation with
    // state: { c__section: 'recycle-bin' } -- lands directly on the
    // requested section instead of always defaulting to Setup.
    @wire(CurrentPageReference)
    onPageRef(pageRef) {
        const sectionId = pageRef && pageRef.state && pageRef.state.c__section;
        if (sectionId && SECTIONS.some((section) => section.id === sectionId)) {
            this.selectedSectionId = sectionId;
        }
    }

    get sections() {
        return SECTIONS.map((section) => ({
            ...section,
            isSelected: section.id === this.selectedSectionId,
            navClass: section.id === this.selectedSectionId
                ? 'slds-nav-vertical__item slds-is-active'
                : 'slds-nav-vertical__item'
        }));
    }

    get sectionsMeta() {
        return `${SECTIONS.length} section${SECTIONS.length === 1 ? '' : 's'}`;
    }

    get isSetupSelected() {
        return this.selectedSectionId === 'setup';
    }

    get isApprovalRoutingSelected() {
        return this.selectedSectionId === 'approval-routing';
    }

    get isAnalyticsNotificationsSelected() {
        return this.selectedSectionId === 'analytics-notifications';
    }

    get isClaudeGusSelected() {
        return this.selectedSectionId === 'claude-gus';
    }

    get isScheduledJobsSelected() {
        return this.selectedSectionId === 'scheduled-jobs';
    }

    get isRecycleBinSelected() {
        return this.selectedSectionId === 'recycle-bin';
    }

    get isNotificationsSelected() {
        return this.selectedSectionId === 'notifications';
    }

    handleSectionSelect(event) {
        event.preventDefault();
        const sectionId = event.currentTarget.dataset.sectionId;
        if (sectionId) {
            this.selectedSectionId = sectionId;
        }
    }

    handleSelectSection(event) {
        const sectionId = event && event.detail && event.detail.sectionId;
        if (SECTIONS.some((section) => section.id === sectionId)) {
            this.selectedSectionId = sectionId;
        }
    }
}
