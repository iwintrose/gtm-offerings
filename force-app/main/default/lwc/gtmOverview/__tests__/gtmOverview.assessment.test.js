/**
 * assessment-instrument-rebuild-04-editor-lwc-wiring — the offering card's
 * new "Assessment" action, wired the same standard__app / navItemPage /
 * c__offering way as openEditor()'s Pages action (gtmOverview.js), but
 * landing on the GTM_Instrument_Author tab (the rebuilt gtmInstrumentAuthor
 * editor's primary entry point) instead of GTM_Content_Manager.
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
import getFeedbackFor from '@salesforce/apex/GtmFeedbackController.getFeedbackFor';

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

function showOfferings(element) {
    element.shadowRoot.querySelector('[data-view="offerings"]').click();
}

function makeHomeSummary() {
    return {
        offerings: [
            {
                offeringKey: 'ma-migrator',
                label: 'Migration Accelerator',
                isFramework: false,
                pages: [
                    { templateType: 'story', sectionCount: 3, fieldCount: 12 }
                ]
            }
        ],
        activity: [],
        pageTitles: {}
    };
}

describe('c-gtm-overview: offering card "Assessment" action (assessment-instrument-rebuild-04-editor-lwc-wiring)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    async function setup() {
        getHomeSummary.mockResolvedValue(makeHomeSummary());
        getSnapshot.mockResolvedValue(null);
        getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0, truncated: false });
        getDeals.mockResolvedValue([]);
        getActToday.mockResolvedValue(null);
        getFeedbackFor.mockResolvedValue([]);

        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        await flushPromises();
        showOfferings(element);
        await flushPromises();
        return element;
    }

    it('renders an Assessment button on the offering card', async () => {
        const element = await setup();
        const buttons = Array.from(element.shadowRoot.querySelectorAll('.ocard-acts button'));
        const assessmentBtn = buttons.find((b) => b.textContent.trim() === 'Assessment');
        expect(assessmentBtn).toBeTruthy();
    });

    it('clicking Assessment navigates standard__app into GTM_Content_Manager, landing on the GTM_Instrument_Author tab scoped to that offering', async () => {
        const element = await setup();
        const buttons = Array.from(element.shadowRoot.querySelectorAll('.ocard-acts button'));
        const assessmentBtn = buttons.find((b) => b.textContent.trim() === 'Assessment');
        assessmentBtn.click();
        await flushPromises();

        expect(mockNavigate).toHaveBeenCalledTimes(1);
        const [navArgs] = mockNavigate.mock.calls[0];
        expect(navArgs.type).toBe('standard__app');
        expect(navArgs.attributes).toEqual({ appTarget: 'c__GTM_Content_Manager' });

        const pageRef = JSON.parse(navArgs.state.pageRef);
        expect(pageRef.type).toBe('standard__navItemPage');
        expect(pageRef.attributes).toEqual({ apiName: 'GTM_Instrument_Author' });
        expect(pageRef.state).toEqual({ c__offering: 'ma-migrator' });
    });
});
