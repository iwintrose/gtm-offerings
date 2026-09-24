/**
 * Issue rep-initiated-assessment-no-page-1-picker-and-record.
 *
 * Verifies the new "New assessment (no page)" entry point on gtmOverview:
 * the button renders alongside "New engagement link", and clicking it
 * (with exactly one offering, mirroring handleNewEngagementLink's own
 * single-offering gate) mounts the gtmRepDirectPicker component.
 */
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

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function makeHomeSummary() {
    return {
        offerings: [
            {
                offeringKey: 'migration-accelerator',
                label: 'Migration Accelerator',
                isFramework: false,
                pages: [
                    { templateType: 'story', sectionCount: 3, fieldCount: 12 },
                    { templateType: 'configurator', sectionCount: 2, fieldCount: 8 }
                ]
            }
        ],
        activity: [],
        pageTitles: {}
    };
}

describe('c-gtm-overview: New assessment (no page) entry point', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders a "New assessment (no page)" button next to "New engagement link"', async () => {
        getHomeSummary.mockResolvedValue(makeHomeSummary());
        getSnapshot.mockResolvedValue(null);
        getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0, truncated: false });
        getDeals.mockResolvedValue([]);

        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        await flushPromises();

        const buttons = headerActionButtons(element);
        const labels = Array.from(buttons).map((b) => b.label);
        expect(labels).toContain('New engagement link');
        expect(labels).toContain('New assessment (no page)');
    });

    it('clicking the button (single offering) mounts the picker', async () => {
        getHomeSummary.mockResolvedValue(makeHomeSummary());
        getSnapshot.mockResolvedValue(null);
        getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0, truncated: false });
        getDeals.mockResolvedValue([]);

        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-rep-direct-picker')).toBeNull();

        const buttons = headerActionButtons(element);
        const repDirectButton = Array.from(buttons).find(
            (b) => b.label === 'New assessment (no page)'
        );
        expect(repDirectButton).toBeTruthy();
        repDirectButton.click();
        await flushPromises();

        const picker = element.shadowRoot.querySelector('c-gtm-rep-direct-picker');
        expect(picker).toBeTruthy();
        expect(picker.offeringKey).toBe('migration-accelerator');
    });

    // QA follow-up (TEST_FAILURES.log,
    // rep-initiated-assessment-no-page-2-share-and-continue): a rep who just
    // created a Rep_Direct record must land on the GTM_Assessments tab with
    // the questionnaire ready in a modal, never the raw
    // GTM_Saved_Configuration__c record page.
    it('navigates to GTM_Assessments with c__repDirectId (not the raw record page) when the picker fires "created"', async () => {
        getHomeSummary.mockResolvedValue(makeHomeSummary());
        getSnapshot.mockResolvedValue(null);
        getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0, truncated: false });
        getDeals.mockResolvedValue([]);

        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        await flushPromises();

        const buttons = headerActionButtons(element);
        const repDirectButton = Array.from(buttons).find(
            (b) => b.label === 'New assessment (no page)'
        );
        repDirectButton.click();
        await flushPromises();

        const picker = element.shadowRoot.querySelector('c-gtm-rep-direct-picker');
        picker.dispatchEvent(new CustomEvent('created', { detail: { recordId: 'a0X000000000123' } }));
        await flushPromises();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: { c__repDirectId: 'a0X000000000123' }
        });
        // The picker panel closes as part of the same hand-off.
        expect(element.shadowRoot.querySelector('c-gtm-rep-direct-picker')).toBeNull();
    });
});
