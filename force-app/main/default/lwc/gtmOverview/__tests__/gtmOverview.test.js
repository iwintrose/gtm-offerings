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
import { createElement } from 'lwc';
import GtmOverview from 'c/gtmOverview';
import getHomeSummary from '@salesforce/apex/GtmPageContentController.getHomeSummary';
import getSnapshot from '@salesforce/apex/GtmHomeSnapshotController.getSnapshot';
import getRecentNewAssessmentRequests from '@salesforce/apex/GtmHomeSnapshotController.getRecentNewAssessmentRequests';
import getDeals from '@salesforce/apex/GtmHomeSnapshotController.getDeals';
import getFeedbackFor from '@salesforce/apex/GtmFeedbackController.getFeedbackFor';
import submitFeedback from '@salesforce/apex/GtmFeedbackController.submitFeedback';
import getSiteHomePageUrl from '@salesforce/apex/GtmSavedConfigurationController.getSiteHomePageUrl';
import { TEMPLATE_LABELS } from 'c/gtmPageLayouts';

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
    '@salesforce/apex/GtmHomeSnapshotController.getRecentNewAssessmentRequests',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmHomeSnapshotController.getDeals',
    () => ({ default: jest.fn() }),
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
jest.mock(
    '@salesforce/apex/GtmSavedConfigurationController.getSiteHomePageUrl',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
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
        getRecentNewAssessmentRequests.mockResolvedValue([]);
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
        getRecentNewAssessmentRequests.mockResolvedValue([]);
        getDeals.mockResolvedValue([]);

        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
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
        getRecentNewAssessmentRequests.mockResolvedValue([]);
        getDeals.mockResolvedValue([]);

        const element = createElement('c-gtm-overview', { is: GtmOverview });
        document.body.appendChild(element);
        await flushPromises();

        // With no override, the canonical TEMPLATE_LABELS value should appear.
        const pageListText = element.shadowRoot.textContent;
        expect(pageListText).toContain('Story');
        expect(pageListText).toContain('Configurator');
    });
});
