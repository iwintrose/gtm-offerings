import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

// Same fallback gtmConfigurator itself uses when no offering is named --
// only reached here if a Story deep link somehow arrives with no offering
// in its state, which no caller in this app actually does today.
const DEFAULT_OFFERING_KEY = 'migration-accelerator';

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
 *
 * So this component is now just the fork between those two, decided by
 * how the tab was reached -- not a renderer in its own right.
 */
export default class GtmPageBrowser extends LightningElement {
    @track isStoryMode = false;
    @track storyOfferingKey = '';

    @wire(CurrentPageReference)
    capturePageRef(ref) {
        const state = (ref && ref.state) || {};
        if (state.c__template !== 'story') {
            this.isStoryMode = false;
            return;
        }
        this.isStoryMode = true;
        this.storyOfferingKey = state.c__offering || DEFAULT_OFFERING_KEY;
    }
}
