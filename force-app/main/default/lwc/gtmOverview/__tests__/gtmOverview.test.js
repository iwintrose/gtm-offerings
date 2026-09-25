/**
 * Issue #40 — gtmOverview page-title overrides.
 *
 * Verifies that:
 * 1. gtmOverview no longer contains its own local TEMPLATE_LABELS duplicate
 *    (it now imports from c/gtmPageLayouts, picking up the four keys that were
 *    previously missing: offerings-page, faq-bd, faq-content-manager, assistant).
 * 2. The canonical TEMPLATE_LABELS from gtmPageLayouts covers every template
 *    type so no raw slug falls through.
 * 3. A pageTitles override from getHomeSummary() wins over the hardcoded label.
 */
// The stock sfdx-lwc-jest navigation stub defines [NavigationMixin.Navigate]
// on a sealed prototype, so it cannot be spied on or reassigned in place.
// This test needs to observe the exact payload passed to Navigate, so the
// module is re-mocked here with a Navigate that forwards to an inspectable
// jest.fn() -- same approach as gtmReadoutsOverview's own test.
const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const GenerateUrl = Symbol('GenerateUrl');
    const NavigationMixin = (Base) => {
        return class extends Base {
            [Navigate](...args) {
                mockNavigate(...args);
            }
            [GenerateUrl]() {
                return Promise.resolve('https://www.example.com');
            }
        };
    };
    NavigationMixin.Navigate = Navigate;
    NavigationMixin.GenerateUrl = GenerateUrl;
    return { NavigationMixin };
});

// eslint-disable-next-line import/first, import/order
import { createElement } from 'lwc';
// eslint-disable-next-line import/first
import GtmOverview from 'c/gtmOverview';
import getHomeSummary from '@salesforce/apex/GtmPageContentController.getHomeSummary';
import getSnapshot from '@salesforce/apex/GtmHomeSnapshotController.getSnapshot';
import getStageCountsAura from '@salesforce/apex/GtmLinkStageService.getStageCountsAura';
import getDeals from '@salesforce/apex/GtmHomeSnapshotController.getDeals';
import getActToday from '@salesforce/apex/GtmActTodayController.getActToday';
import getFeedbackFor from '@salesforce/apex/GtmFeedbackController.getFeedbackFor';
import submitFeedback from '@salesforce/apex/GtmFeedbackController.submitFeedback';
import { TEMPLATE_LABELS } from 'c/gtmPageLayouts';

/** Header actions are now data on c-gtm-page-header (`actions` prop) and
 *  come back as a `headeraction` event, so specs read the prop and dispatch
 *  the event instead of clicking slotted buttons. Returns button-like
 *  proxies (label/variant/iconName/disabled/click). */
function headerActionButtons(element) {
    const header = element.shadowRoot.querySelector('c-gtm-page-header');
    return header.actions.map((a) => ({
        label: a.label,
        variant: a.variant,
        iconName: a.iconName,
        disabled: a.disabled,
        click() {
            if (a.disabled) return;
            header.dispatchEvent(new CustomEvent('headeraction', { detail: { name: a.name } }));
        }
    }));
}

jest.mock(
    '@salesforce/apex/GtmPageContentController.getHomeSummary',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmHomeSnapshotController.getSnapshot',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmLinkStageService.getStageCountsAura',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmHomeSnapshotController.getDeals',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmActTodayController.getActToday',
    () => ({ default: jest.fn(() => Promise.resolve(null)) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmFeedbackController.getFeedbackFor',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmFeedbackController.submitFeedback',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
// getSiteHomePageUrl's import and jest.mock were removed with issue #99's
// Step 1: the Overview no longer navigates to the site domain, so nothing on
// this page calls it. (submitFeedback/getFeedbackFor stay mocked below — they
// are still reachable from the feedback panel.)

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

/** Switches the page from the default Today view to Offerings, where the
 *  per-offering content/performance card now lives (issue
 *  overview-bd-heat-redesign-1-layout-toggle). */
function showOfferings(element) {
    element.shadowRoot.querySelector('[data-view="offerings"]').click();
}

const ALL_TEMPLATE_TYPES = [
    'story', 'configurator', 'industry-chooser', 'offerings-listing',
    'offerings-page', 'faq-bd', 'faq-content-manager', 'assistant'
];

function makeHomeSummary({ pageTitles = {} } = {}) {
    return {
        offerings: [
            {
                offeringKey: 'ma-migrator',
                label: 'Migration Accelerator',
                isFramework: false,
                pages: [
                    { templateType: 'story',        sectionCount: 3, fieldCount: 12 },
                    { templateType: 'configurator',  sectionCount: 2, fieldCount: 8  }
                ]
            }
        ],
        activity: [],
        pageTitles
    };
}

describe('c-gtm-overview: page-title overrides (issue #40)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('canonical TEMPLATE_LABELS from gtmPageLayouts covers all template types (no raw slug fallback)', () => {
        // The old local TEMPLATE_LABELS in gtmOverview was missing four keys.
        // Now that we import from gtmPageLayouts, all eight must resolve.
        ALL_TEMPLATE_TYPES.forEach((t) => {
            expect(TEMPLATE_LABELS[t]).toBeTruthy();
        });
    });

    it('loads without error when getHomeSummary returns pageTitles', async () => {
        getHomeSummary.mockResolvedValue(makeHomeSummary());
        getSnapshot.mockResolvedValue(null);
        getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0, truncated: false });
        getDeals.mockResolvedValue([]);

        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        await flushPromises();

        expect(element).toBeTruthy();
        expect(getHomeSummary).toHaveBeenCalled();
    });

    it('applies pageTitles override so a renamed page shows its new name', async () => {
        const overriddenTitle = 'Custom Story Name';
        getHomeSummary.mockResolvedValue(
            makeHomeSummary({ pageTitles: { 'ma-migrator::story': overriddenTitle } })
        );
        getSnapshot.mockResolvedValue(null);
        getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0, truncated: false });
        getDeals.mockResolvedValue([]);

        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        await flushPromises();
        showOfferings(element);
        await flushPromises();

        // The override should win over the hardcoded 'Story' label.
        const pageListText = element.shadowRoot.textContent;
        expect(pageListText).toContain(overriddenTitle);
        expect(pageListText).not.toContain('Story ·');
        expect(pageListText).not.toContain('· Story');
    });

    it('falls back to TEMPLATE_LABELS when no override exists for a template', async () => {
        getHomeSummary.mockResolvedValue(makeHomeSummary({ pageTitles: {} }));
        getSnapshot.mockResolvedValue(null);
        getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0, truncated: false });
        getDeals.mockResolvedValue([]);

        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        await flushPromises();
        showOfferings(element);
        await flushPromises();

        // With no override, the canonical TEMPLATE_LABELS value should appear.
        const pageListText = element.shadowRoot.textContent;
        expect(pageListText).toContain('Story');
        expect(pageListText).toContain('Configurator');
    });
});

/**
 * Issue #99 Step 1 — the link wizard is authored in Lightning, not on the site.
 *
 * The wizard is mounted behind if:true={wizardOpen} rather than left in the
 * DOM: its connectedCallback fires three Apex calls, and none of them belong
 * on every Overview load. So "is it in the DOM" is the assertion that matters,
 * not just whether it is visible.
 */
describe('c-gtm-overview: engagement-link wizard (issue #99)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function mountWithOfferings(offerings) {
        getHomeSummary.mockResolvedValue({ offerings, activity: [], pageTitles: {} });
        getSnapshot.mockResolvedValue(null);
        getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0, truncated: false });
        getDeals.mockResolvedValue([]);
        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        return element;
    }

    const OFFERING = (key, label) => ({
        offeringKey: key,
        label,
        isFramework: false,
        offeringStatus: 'Active',
        archived: false,
        pages: [{ templateType: 'story', sectionCount: 2, fieldCount: 5 }]
    });

    /** The one and only trigger: the page-header button. The offering cards
     *  carry no "New link" button of their own -- see the card-button test
     *  below, which pins that down. */
    function newEngagementLinkButton(element) {
        return headerActionButtons(element)[0];
    }

    it('does NOT render the wizard while wizardOpen is false', async () => {
        const element = mountWithOfferings([OFFERING('ma-migrator', 'Migration Accelerator')]);
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-config-wizard')).toBeNull();
    });

    it('renders the wizard once wizardOpen is true, for the only offering', async () => {
        const element = mountWithOfferings([OFFERING('ma-migrator', 'Migration Accelerator')]);
        await flushPromises();

        newEngagementLinkButton(element).click();
        await flushPromises();

        const wizard = element.shadowRoot.querySelector('c-gtm-config-wizard');
        expect(wizard).not.toBeNull();
        expect(wizard.isOpen).toBe(true);
        // Offering__c is required and saveConfiguration() throws on a blank
        // one, so an opened wizard that carried no key could never save.
        expect(wizard.offeringKey).toBe('ma-migrator');
        expect(wizard.standalone).toBe(true);
    });

    it('never binds saved-record-id — that would jump the wizard to the "Link generated" screen', async () => {
        const element = mountWithOfferings([OFFERING('ma-migrator', 'Migration Accelerator')]);
        await flushPromises();

        newEngagementLinkButton(element).click();
        await flushPromises();

        const wizard = element.shadowRoot.querySelector('c-gtm-config-wizard');
        expect(wizard.savedRecordId).toBeFalsy();
    });

    it('the top-of-page "New engagement link" button is the entry point, and it opens the wizard', async () => {
        // This is now the ONLY way in -- the per-offering card button was
        // removed -- so if this breaks, the wizard is unreachable.
        const element = mountWithOfferings([OFFERING('ma-migrator', 'Migration Accelerator')]);
        await flushPromises();

        const header = newEngagementLinkButton(element);
        expect(header.label).toBe('New engagement link');

        header.click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-config-wizard')).not.toBeNull();
    });

    it('the offering cards carry NO "New link" button — the header button is the only trigger', async () => {
        // Stakeholder call: one trigger, at the top of the page. A card-level
        // button was briefly added and then pulled; this pins it out.
        const element = mountWithOfferings([
            OFFERING('ma-migrator', 'Migration Accelerator'),
            OFFERING('data-cloud', 'Data Cloud')
        ]);
        await flushPromises();
        showOfferings(element);
        await flushPromises();

        const cardButtons = [...element.shadowRoot.querySelectorAll('.ocard-acts button')]
            .map((b) => b.textContent.trim());
        expect(cardButtons.length).toBeGreaterThan(0);
        expect(cardButtons).not.toContain('New link');
        // The cards keep exactly the two they always had.
        expect(cardButtons).toContain('Read the story');
    });

    it('with several offerings the header button hints instead of guessing one (branch unreachable today: the org has one offering)', async () => {
        const element = mountWithOfferings([
            OFFERING('ma-migrator', 'Migration Accelerator'),
            OFFERING('data-cloud', 'Data Cloud')
        ]);
        await flushPromises();

        newEngagementLinkButton(element).click();
        await flushPromises();

        // Guessing offerings[0] would write a link against the wrong offering,
        // so it refuses rather than picks.
        expect(element.shadowRoot.querySelector('c-gtm-config-wizard')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('Choose an offering below to start a link.');
    });

    it('closes on the wizard\'s own close event', async () => {
        const element = mountWithOfferings([OFFERING('ma-migrator', 'Migration Accelerator')]);
        await flushPromises();

        newEngagementLinkButton(element).click();
        await flushPromises();

        element.shadowRoot
            .querySelector('c-gtm-config-wizard')
            .dispatchEvent(new CustomEvent('close'));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-config-wizard')).toBeNull();
    });

    it('mounts the wizard as the FIRST child of the root container, so its chrome offset measures right', async () => {
        // Not cosmetic. gtmConfigWizard._measureChromeOffset reads
        // host.getBoundingClientRect().top + window.scrollY -- an absolute
        // document offset -- and feeds it to a position: fixed overlay, which
        // wants a viewport offset. Only at the top of the container do the two
        // terms cancel (rect.top falls as you scroll, scrollY rises) and
        // resolve to the Salesforce chrome height. Mounted at the end of the
        // container the wizard measured top: 1915px on a 643px viewport and
        // rendered off-screen: open, opacity 1, and invisible. jsdom reports
        // every rect as zero so the offset itself is not assertable here --
        // DOM order is the thing that is, and it is what broke.
        const element = mountWithOfferings([OFFERING('ma-migrator', 'Migration Accelerator')]);
        await flushPromises();

        newEngagementLinkButton(element).click();
        await flushPromises();

        const root = element.shadowRoot.querySelector('div.ov');
        const wizard = element.shadowRoot.querySelector('c-gtm-config-wizard');
        expect(root).not.toBeNull();
        expect(wizard).not.toBeNull();

        // The wizard belongs to the root container, not some nested card.
        expect(wizard.parentElement).toBe(root);
        // ...and it is that container's very first element. firstElementChild
        // skips the comment nodes LWC leaves behind for if:true placeholders,
        // so this stays exact rather than brittle.
        expect(root.firstElementChild).toBe(wizard);

        // Belt and braces: also assert the weaker, refactor-proof property --
        // the wizard precedes the page header in document order. The header
        // bar is now the shared c-gtm-page-header (issue B14), so its own
        // .slds-page-header lives in a separate shadow tree -- query the
        // custom element itself instead.
        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header).not.toBeNull();
        // eslint-disable-next-line no-bitwise
        expect(
            wizard.compareDocumentPosition(header) & Node.DOCUMENT_POSITION_FOLLOWING
        ).toBeTruthy();
    });

    it('a save refreshes the funnel and the deals table, and leaves the wizard open', async () => {
        const element = mountWithOfferings([OFFERING('ma-migrator', 'Migration Accelerator')]);
        await flushPromises();

        newEngagementLinkButton(element).click();
        await flushPromises();
        getSnapshot.mockClear();
        getDeals.mockClear();

        element.shadowRoot
            .querySelector('c-gtm-config-wizard')
            .dispatchEvent(new CustomEvent('configsaved', {
                detail: { recordId: 'a0X000000000001', generatedUrl: 'https://example.my.site.com/gtm/s/configurator?cfgId=a0X000000000001' }
            }));
        await flushPromises();

        expect(getSnapshot).toHaveBeenCalled();
        expect(getDeals).toHaveBeenCalled();
        // configsaved also fires on every autosave, so closing here would
        // shut the panel under a rep who is still typing.
        expect(element.shadowRoot.querySelector('c-gtm-config-wizard')).not.toBeNull();
    });

    describe('issue #99-done-nav — Done navigates to the Pages tab', () => {
        beforeEach(() => {
            mockNavigate.mockClear();
        });

        it('closes the panel and navigates to GTM_Pages with the saved record on a genuine "done"', async () => {
            const element = mountWithOfferings([OFFERING('ma-migrator', 'Migration Accelerator')]);
            await flushPromises();

            newEngagementLinkButton(element).click();
            await flushPromises();

            element.shadowRoot
                .querySelector('c-gtm-config-wizard')
                .dispatchEvent(new CustomEvent('done', {
                    detail: {
                        recordId: 'a0X000000000001',
                        generatedUrl: 'https://example.my.site.com/gtm/s/configurator?cfgId=a0X000000000001',
                        company: 'Acme Corp'
                    }
                }));
            await flushPromises();

            // Panel closes, same as the plain close path.
            expect(element.shadowRoot.querySelector('c-gtm-config-wizard')).toBeNull();

            expect(mockNavigate).toHaveBeenCalledWith({
                type: 'standard__navItemPage',
                attributes: { apiName: 'GTM_Pages' },
                state: {
                    c__template: 'link',
                    c__recordId: 'a0X000000000001',
                    c__generatedUrl: 'https://example.my.site.com/gtm/s/configurator?cfgId=a0X000000000001',
                    c__company: 'Acme Corp'
                }
            });
        });

        it('an early exit via plain "close" does NOT navigate', async () => {
            const element = mountWithOfferings([OFFERING('ma-migrator', 'Migration Accelerator')]);
            await flushPromises();

            newEngagementLinkButton(element).click();
            await flushPromises();

            element.shadowRoot
                .querySelector('c-gtm-config-wizard')
                .dispatchEvent(new CustomEvent('close'));
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-gtm-config-wizard')).toBeNull();
            expect(mockNavigate).not.toHaveBeenCalled();
        });

        it('per-autosave "configsaved" keeps refreshing snapshot/deals and does NOT navigate', async () => {
            const element = mountWithOfferings([OFFERING('ma-migrator', 'Migration Accelerator')]);
            await flushPromises();

            newEngagementLinkButton(element).click();
            await flushPromises();
            getSnapshot.mockClear();
            getDeals.mockClear();

            element.shadowRoot
                .querySelector('c-gtm-config-wizard')
                .dispatchEvent(new CustomEvent('configsaved', {
                    detail: { recordId: 'a0X000000000002', generatedUrl: 'https://example.my.site.com/gtm/s/configurator?cfgId=a0X000000000002' }
                }));
            await flushPromises();

            expect(getSnapshot).toHaveBeenCalled();
            expect(getDeals).toHaveBeenCalled();
            expect(mockNavigate).not.toHaveBeenCalled();
            // Still open — configsaved never closes the panel.
            expect(element.shadowRoot.querySelector('c-gtm-config-wizard')).not.toBeNull();
        });
    });

    describe('issue #PAGES-REACHABILITY — persistent "Find a link you sent" entry point', () => {
        beforeEach(() => {
            mockNavigate.mockClear();
        });

        function browseLinksButton(element) {
            return headerActionButtons(element)
                .find((b) => b.label === 'Find a link you sent');
        }

        it('renders the button alongside "New engagement link", always available', async () => {
            const element = mountWithOfferings([OFFERING('ma-migrator', 'Migration Accelerator')]);
            await flushPromises();

            const button = browseLinksButton(element);
            expect(button).not.toBeUndefined();
        });

        it('navigates to GTM_Pages with c__template=browse and no record id', async () => {
            const element = mountWithOfferings([OFFERING('ma-migrator', 'Migration Accelerator')]);
            await flushPromises();

            browseLinksButton(element).click();
            await flushPromises();

            expect(mockNavigate).toHaveBeenCalledWith({
                type: 'standard__navItemPage',
                attributes: { apiName: 'GTM_Pages' },
                state: { c__template: 'browse' }
            });
        });

        it('does not open the wizard — it is a separate nav action, not tangled up with handleNewEngagementLink', async () => {
            const element = mountWithOfferings([OFFERING('ma-migrator', 'Migration Accelerator')]);
            await flushPromises();

            browseLinksButton(element).click();
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-gtm-config-wizard')).toBeNull();
        });
    });
});

describe('c-gtm-overview: SLDS 2 button compliance (issue slds-button-audit-p1)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    const OFFERING = (key, label) => ({
        offeringKey: key,
        label,
        isFramework: false,
        offeringStatus: 'Active',
        archived: false,
        pages: [{ templateType: 'story', sectionCount: 2, fieldCount: 5 }]
    });

    function mountWithOffering() {
        getHomeSummary.mockResolvedValue({
            offerings: [OFFERING('ma-migrator', 'Migration Accelerator')],
            activity: [],
            pageTitles: {}
        });
        getSnapshot.mockResolvedValue(null);
        getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0, truncated: false });
        getDeals.mockResolvedValue([]);
        getFeedbackFor.mockResolvedValue([]);
        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        return element;
    }

    it('"Read the story" and the feedback toggle render as slds-button_neutral, not raw .ocard-btn styling', async () => {
        const element = mountWithOffering();
        await flushPromises();
        showOfferings(element);
        await flushPromises();

        const [readStory, toggle] = [...element.shadowRoot.querySelectorAll('.ocard-acts button')];
        expect(readStory.className).toContain('slds-button');
        expect(readStory.className).toContain('slds-button_neutral');
        expect(readStory.className).not.toContain('slds-button_brand');
        expect(toggle.className).toContain('slds-button');
        expect(toggle.className).toContain('slds-button_neutral');
        expect(toggle.className).not.toContain('slds-button_brand');
    });

    it('"Send to the writers" is the single slds-button_brand action inside the offering feedback panel', async () => {
        const element = mountWithOffering();
        await flushPromises();
        showOfferings(element);
        await flushPromises();

        const toggle = [...element.shadowRoot.querySelectorAll('.ocard-acts button')]
            .find((b) => b.textContent.trim() !== 'Read the story');
        toggle.click();
        await flushPromises();

        const panel = element.shadowRoot.querySelector('.ocard-panel--on');
        expect(panel).not.toBeNull();

        const panelButtons = [...panel.querySelectorAll('button')];
        const brandButtons = panelButtons.filter((b) => b.className.includes('slds-button_brand'));
        expect(brandButtons).toHaveLength(1);
        expect(brandButtons[0].textContent.trim()).toBe('Send to the writers');
    });

    it('the page header keeps exactly one brand button ("New engagement link"); "Find a link you sent" is not brand', async () => {
        const element = mountWithOffering();
        await flushPromises();

        // The header bar is now the shared c-gtm-page-header; its
        // .slds-page-header__col-actions lives in that component's own
        // shadow DOM, so the action buttons (light DOM children slotted in)
        // are queried by their slot attribute instead (issue B14).
        // Was 3 -- now 4: "New assessment (no page)" (issue
        // rep-initiated-assessment-no-page-1-picker-and-record) added a
        // second, non-brand entry point next to "New engagement link".
        const headerButtons = headerActionButtons(element);
        expect(headerButtons).toHaveLength(4);

        const newLink = headerButtons.find((b) => b.label === 'New engagement link');
        const newRepDirect = headerButtons.find((b) => b.label === 'New assessment (no page)');
        const findLink = headerButtons.find((b) => b.label === 'Find a link you sent');
        const seeAssessments = headerButtons.find((b) => b.label === 'See Assessments');
        expect(newLink.variant).toBe('brand');
        expect(newRepDirect.variant).not.toBe('brand');
        expect(findLink.variant).not.toBe('brand');
        expect(seeAssessments.variant).not.toBe('brand');
    });

    // Regression test: "See Assessments" previously carried
    // icon-name="utility:assessment", which is not a real SLDS icon and so
    // silently rendered no icon at all (flagged in live QA, fixed here) --
    // "Find a link you sent" is the known-good sibling button confirmed to
    // render its icon, so this locks "See Assessments" to a real icon too.
    it('"See Assessments" has a real icon set, matching its sibling "Find a link you sent" button', async () => {
        const element = mountWithOffering();
        await flushPromises();

        const headerButtons = headerActionButtons(element);
        const findLink = headerButtons.find((b) => b.label === 'Find a link you sent');
        const seeAssessments = headerButtons.find((b) => b.label === 'See Assessments');

        expect(findLink.iconName).toBeTruthy();
        expect(seeAssessments.iconName).toBeTruthy();
        expect(seeAssessments.iconName).not.toBe('utility:assessment');
    });

    it('"See Assessments" navigates to the GTM_Assessments tab (issue gtm-nav-restructure)', async () => {
        const element = mountWithOffering();
        await flushPromises();

        const headerButtons = headerActionButtons(element);
        const seeAssessments = headerButtons.find((b) => b.label === 'See Assessments');
        seeAssessments.click();

        expect(mockNavigate).toHaveBeenCalledWith(
            expect.objectContaining({
                type: 'standard__navItemPage',
                attributes: expect.objectContaining({ apiName: 'GTM_Assessments' })
            })
        );
    });
});

describe('c-gtm-overview: "Opportunities to follow up on" 3-column grouped table (issue opportunities-table-redesign-v2)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    const GROUPED_DEAL = (overrides = {}) => ({
        configId: overrides.configId || 'a0X0000000001',
        configName: overrides.configName || 'Mike P Intro',
        opportunityId: overrides.opportunityId || '006000000000001',
        opportunityName: overrides.opportunityName || 'Acme Deal',
        offeringLabel: overrides.offeringLabel || 'Migration Accelerator',
        accountId: overrides.accountId || '001000000000001',
        accountName: overrides.accountName || 'Acme Bank',
        contactId: overrides.contactId || '003000000000001',
        contactName: overrides.contactName || 'Jordan Lee',
        stageName: overrides.stageName || 'Qualification',
        views: overrides.views || 0,
        requestId: overrides.requestId,
        requestName: overrides.requestName,
        requestStatus: overrides.requestStatus,
        requestSubmittedAt: overrides.requestSubmittedAt,
        formOpened: overrides.formOpened || false,
        formSubmitted: overrides.formSubmitted || false,
        ...overrides
    });

    function mountDeals(deals) {
        getHomeSummary.mockResolvedValue({
            offerings: [{
                offeringKey: 'ma-migrator',
                label: 'Migration Accelerator',
                isFramework: false,
                offeringStatus: 'Active',
                archived: false,
                pages: [{ templateType: 'story', sectionCount: 2, fieldCount: 5 }]
            }],
            activity: [],
            pageTitles: {}
        });
        getSnapshot.mockResolvedValue(null);
        getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0, truncated: false });
        getDeals.mockResolvedValue(deals);
        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        return element;
    }

    it('groups rows by Account -> Contact -> link, showing the account name exactly once and no duplicate account line under the link name', async () => {
        const element = mountDeals([GROUPED_DEAL()]);
        await flushPromises();

        const text = element.shadowRoot.textContent;
        const occurrences = text.split('Acme Bank').length - 1;
        expect(occurrences).toBe(1);
        expect(text).toContain('Jordan Lee');
        expect(text).toContain('Migration Accelerator');
        expect(text).toContain('Mike P Intro');
    });

    it('column headers are reduced to exactly 3: Account/contact/link, Opportunity, Assessment', async () => {
        const element = mountDeals([GROUPED_DEAL()]);
        await flushPromises();

        const headers = [...element.shadowRoot.querySelectorAll('.deal--head [role="columnheader"]')];
        expect(headers.length).toBe(3);
        expect(headers.map((h) => h.textContent)).toEqual([
            'Account / contact / link', 'Opportunity', 'Assessment'
        ]);
        const text = element.shadowRoot.textContent;
        expect(text).not.toContain('CRM stage');
        expect(text).not.toContain('On the page');
        expect(text).not.toContain('Last activity');
        expect(text).not.toContain('What each recipient did with the page you sent');
    });

    it('Column 3 shows the AR-### assessment name and submitted date when a request exists', async () => {
        const element = mountDeals([GROUPED_DEAL({
            requestId: 'a0R000000000001',
            requestName: 'AR-001',
            requestStatus: 'New',
            requestSubmittedAt: '2026-01-05T00:00:00Z'
        })]);
        await flushPromises();

        const link = element.shadowRoot.querySelector('.deal-req');
        expect(link.textContent).toBe('AR-001');
        expect(element.shadowRoot.querySelector('.deal-assessment').textContent).toContain('AR-001');
    });

    it('Column 3 shows an em dash with no link when no assessment exists', async () => {
        const element = mountDeals([GROUPED_DEAL()]);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.deal-req')).toBeNull();
        expect(element.shadowRoot.querySelector('.deal-none').textContent).toBe('—');
    });

    // issue #31: the Engagement Links landing tab this click-through used
    // to navigate to is retired -- these now land on the Account/Contact
    // record's own native Activity tab instead (this click-through's
    // Account -> Contact grouping itself is unchanged).
    it("handleAccountClick navigates to the Account record's Activity tab", async () => {
        const element = mountDeals([GROUPED_DEAL()]);
        await flushPromises();

        element.shadowRoot.querySelector('.deal-group-name').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__recordPage',
            attributes: { recordId: '001000000000001', objectApiName: 'Account', actionName: 'view' }
        });
    });

    it("handleContactClick navigates to the Contact record's Activity tab", async () => {
        const element = mountDeals([GROUPED_DEAL()]);
        await flushPromises();

        element.shadowRoot.querySelector('.deal-contact-name').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__recordPage',
            attributes: { recordId: '003000000000001', objectApiName: 'Contact', actionName: 'view' }
        });
    });

    it('Column 1 click drills into the Pages tab for that specific link', async () => {
        const element = mountDeals([GROUPED_DEAL({ configId: 'cfg-xyz' })]);
        await flushPromises();

        element.shadowRoot.querySelector('.deal-id').closest('.deal').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Pages' },
            state: {
                c__rlfLinkId: 'cfg-xyz', c__rlfAccountId: '001000000000001',
                c__rlfContactId: '003000000000001', cfgId: 'cfg-xyz'
            }
        });
    });

    it('Column 3 assessment click drills into the Assessments tab for that specific request', async () => {
        const element = mountDeals([GROUPED_DEAL({
            requestId: 'a0R000000000099', requestName: 'AR-099'
        })]);
        await flushPromises();

        element.shadowRoot.querySelector('.deal-req').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: { c__assessmentRequestId: 'a0R000000000099' }
        });
    });

    it('the Opportunity stage pill reuses an existing .pill--* tone class, no new colors', async () => {
        const element = mountDeals([GROUPED_DEAL({ stageName: 'Qualification' })]);
        await flushPromises();

        const pill = element.shadowRoot.querySelector('.deal-opp span.pill');
        expect(pill).not.toBeNull();
        expect(pill.className).toMatch(/pill--(good|warn|info|quiet)/);
    });
});

describe('c-gtm-overview: unconfigured offerings filter (issue #47)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('hides an offering whose pages all have sectionCount 0', async () => {
        getHomeSummary.mockResolvedValue({
            offerings: [
                {
                    offeringKey: 'configured-offering',
                    label: 'Configured Offering',
                    isFramework: false,
                    offeringStatus: 'Active',
                    archived: false,
                    pages: [
                        { templateType: 'story', sectionCount: 2, fieldCount: 5 }
                    ]
                },
                {
                    offeringKey: 'empty-offering',
                    label: 'Empty Offering',
                    isFramework: false,
                    offeringStatus: 'Active',
                    archived: false,
                    pages: [
                        { templateType: 'story', sectionCount: 0, fieldCount: 0 },
                        { templateType: 'configurator', sectionCount: 0, fieldCount: 0 }
                    ]
                }
            ],
            activity: [],
            pageTitles: {}
        });
        getSnapshot.mockResolvedValue(null);
        getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0, truncated: false });
        getDeals.mockResolvedValue([]);

        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        await flushPromises();
        showOfferings(element);
        await flushPromises();

        const text = element.shadowRoot.textContent;
        expect(text).toContain('Configured Offering');
        expect(text).not.toContain('Empty Offering');
    });
});

// Ported from agent/issue-56 (integration-wave-2): status/archive filtering
// of the rendered offering list, which had no equivalent test on main.
describe('c-gtm-overview: status and archive filtering (issue #56)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('excludes offerings with offeringStatus=Draft from the rendered page list', async () => {
        getHomeSummary.mockResolvedValue({
            offerings: [
                {
                    offeringKey: 'published-offering',
                    label: 'Published Offering',
                    isFramework: false,
                    offeringStatus: 'Published',
                    archived: false,
                    pages: [{ templateType: 'story', sectionCount: 1, fieldCount: 4 }]
                },
                {
                    offeringKey: 'draft-offering',
                    label: 'Draft Offering',
                    isFramework: false,
                    offeringStatus: 'Draft',
                    archived: false,
                    pages: [{ templateType: 'story', sectionCount: 1, fieldCount: 4 }]
                }
            ],
            activity: [],
            pageTitles: {}
        });
        getSnapshot.mockResolvedValue(null);
        getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0, truncated: false });
        getDeals.mockResolvedValue([]);

        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        await flushPromises();
        showOfferings(element);
        await flushPromises();

        const text = element.shadowRoot.textContent;
        expect(text).toContain('Published Offering');
        expect(text).not.toContain('Draft Offering');
    });

    it('excludes offerings with archived=true from the rendered page list', async () => {
        getHomeSummary.mockResolvedValue({
            offerings: [
                {
                    offeringKey: 'active-offering',
                    label: 'Active Offering',
                    isFramework: false,
                    offeringStatus: 'Published',
                    archived: false,
                    pages: [{ templateType: 'story', sectionCount: 1, fieldCount: 4 }]
                },
                {
                    offeringKey: 'archived-offering',
                    label: 'Archived Offering',
                    isFramework: false,
                    offeringStatus: 'Published',
                    archived: true,
                    pages: [{ templateType: 'story', sectionCount: 1, fieldCount: 4 }]
                }
            ],
            activity: [],
            pageTitles: {}
        });
        getSnapshot.mockResolvedValue(null);
        getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0, truncated: false });
        getDeals.mockResolvedValue([]);

        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        await flushPromises();
        showOfferings(element);
        await flushPromises();

        const text = element.shadowRoot.textContent;
        expect(text).toContain('Active Offering');
        expect(text).not.toContain('Archived Offering');
    });
});
