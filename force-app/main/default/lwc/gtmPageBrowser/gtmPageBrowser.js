import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';

/**
 * The "Pages" tab (GTM_Pages), inside GTM Offerings.
 *
 * This used to be a free-form picker -- any offering, any template,
 * rendered from two comboboxes -- which read as an internal CMS preview
 * tool. That's the Content Manager's job, not a rep's (D7). A rep only
 * ever needs one of two things here:
 *
 *   - The Story, for context. Reached one way: Overview's "Read the story"
 *     button, which lands here with c__template=story and c__offering set.
 *     That path is unchanged -- it was already right.
 *   - Their own view of a Configurator link they already sent someone.
 *     Not a blank preview: the actual saved record, reached by walking
 *     Account -> Contact -> Link rather than picking a page off a menu.
 *     See gtmRepLinkFinder for that whole flow.
 *   - The one link they just finished building in the wizard, landed on
 *     directly. Reached the same deep-link way as the Story above --
 *     Overview's "Done" button (gtmOverview.handleWizardDone) navigates
 *     here with c__template=link and c__recordId set. gtmRepLinkFinder
 *     is handed that record id and skips straight to its "view" step
 *     instead of the Account-search first step.
 *
 * Overview also carries a persistent "Find a link you sent" button
 * (gtmOverview.handleBrowseLinks) for reaching that same Account -> Contact
 * -> Link drill-down at any time, not just right after the wizard. It
 * navigates here with c__template=browse and no record id, so this always
 * resets to gtmRepLinkFinder's first step (Account search) rather than
 * carrying over stale link-mode target ids from an earlier visit.
 *
 * So this component is now just the fork between those, decided by
 * how the tab was reached -- not a renderer in its own right.
 */
export default class GtmPageBrowser extends NavigationMixin(LightningElement) {
    @track isStoryMode = false;
    @track storyOfferingKey = '';

    @track isLinkMode = false;
    @track linkRecordId = '';
    @track linkCompany = '';
    @track linkOfferingKey = '';

    @wire(CurrentPageReference)
    capturePageRef(ref) {
        const state = (ref && ref.state) || {};
        if (state.c__template === 'story') {
            this.isStoryMode = true;
            this.isLinkMode = false;
            // No fallback: an unnamed offering in the deep link's state is an
            // unconfigured deep link, not silently Migration Accelerator's
            // story -- the downstream c-gtm-story render is expected to show
            // its own "not configured" state for a blank offeringKey.
            this.storyOfferingKey = state.c__offering || '';
            return;
        }
        if (state.c__template === 'link' && state.c__recordId) {
            this.isStoryMode = false;
            this.isLinkMode = true;
            this.linkRecordId = state.c__recordId;
            this.linkCompany = state.c__company || '';
            this.linkOfferingKey = state.c__offering || '';
            return;
        }
        // c__template=browse (Overview's persistent "Find a link you sent"
        // button), or no state at all -- either way, land on
        // gtmRepLinkFinder's own first step with nothing pre-selected.
        this.isStoryMode = false;
        this.isLinkMode = false;
        this.linkRecordId = '';
        this.linkCompany = '';
        this.linkOfferingKey = '';
    }

    /** One header, always on screen, whatever this tab is currently
     *  showing -- the title is the only thing that changes with context. */
    get headerTitle() {
        if (this.isStoryMode) return 'The Story';
        if (this.isLinkMode) return 'Your new link';
        return 'Find a link you sent';
    }

    get showBackToPages() {
        return this.isStoryMode || this.isLinkMode;
    }

    /** Meta line under the title -- tells the rep what they're looking at,
     *  the same way headerMeta does on Overview/Content Home (issue B14). */
    get headerMeta() {
        if (this.isStoryMode) {
            return this.storyOfferingKey
                ? `Offering: ${this.storyOfferingKey}`
                : 'No offering selected';
        }
        if (this.isLinkMode) {
            return this.linkCompany
                ? `Just-generated link for ${this.linkCompany}`
                : 'Your new link';
        }
        // No mode exists any more (Addendum C.9): the finder is one filterable table.
        return '';
    }

    /** Story mode and link mode are both deep links in from Overview (the
     *  "Read the story" button, and the wizard's own Done button), not a
     *  step in a flow this component owns -- so leaving either means
     *  clearing that link's own state param, not a local back-stack. */
    handleBackToPages() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Pages' }
        });
    }
}
