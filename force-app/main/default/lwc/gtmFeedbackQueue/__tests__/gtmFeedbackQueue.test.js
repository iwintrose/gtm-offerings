/**
 * Issue #40 — gtmFeedbackQueue page-title overrides.
 *
 * Verifies that a feedback item's "page" label reflects a renamePage()
 * override rather than the hardcoded TEMPLATE_LABELS value.
 */
import { createElement } from 'lwc';
import GtmFeedbackQueue from 'c/gtmFeedbackQueue';
import getOpenFeedback from '@salesforce/apex/GtmFeedbackController.getOpenFeedback';
import respond from '@salesforce/apex/GtmFeedbackController.respond';
import getPageTitles from '@salesforce/apex/GtmPageContentController.getPageTitles';

jest.mock(
    '@salesforce/apex/GtmFeedbackController.getOpenFeedback',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmFeedbackController.respond',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentController.getPageTitles',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const FEEDBACK_ROW = {
    recordId: 'rec001',
    name:     'Test feedback',
    body:     'The story section needs work.',
    submittedBy: 'Jane',
    createdDate: '2026-01-01T00:00:00Z',
    offeringKey: 'ma-migrator',
    templateType: 'story',
    status: 'New',
    response: null
};

describe('c-gtm-feedback-queue: page-title overrides (issue #40)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows hardcoded TEMPLATE_LABELS label when no override exists', async () => {
        getOpenFeedback.mockResolvedValue([FEEDBACK_ROW]);
        getPageTitles.mockResolvedValue({});

        const element = createElement('c-gtm-feedback-queue', { is: GtmFeedbackQueue });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Story');
        expect(getPageTitles).toHaveBeenCalled();
    });

    it('shows the pageTitles override when a rename has been saved', async () => {
        // Use a name that shares no text with any hardcoded TEMPLATE_LABELS value,
        // so the "does not contain the old label" assertion is unambiguous.
        const overriddenTitle = 'Migrator Narrative';
        getOpenFeedback.mockResolvedValue([FEEDBACK_ROW]);
        getPageTitles.mockResolvedValue({ 'ma-migrator::story': overriddenTitle });

        const element = createElement('c-gtm-feedback-queue', { is: GtmFeedbackQueue });
        document.body.appendChild(element);
        await flushPromises();

        const text = element.shadowRoot.textContent;
        // The override must appear …
        expect(text).toContain(overriddenTitle);
        // … and the raw hardcoded label must not, since the override replaced it.
        expect(text).not.toContain('Story');
        expect(getPageTitles).toHaveBeenCalled();
    });

    it('calls getPageTitles alongside getOpenFeedback on load', async () => {
        getOpenFeedback.mockResolvedValue([]);
        getPageTitles.mockResolvedValue({});

        const element = createElement('c-gtm-feedback-queue', { is: GtmFeedbackQueue });
        document.body.appendChild(element);
        await flushPromises();

        expect(getOpenFeedback).toHaveBeenCalledTimes(1);
        expect(getPageTitles).toHaveBeenCalledTimes(1);
    });
});
