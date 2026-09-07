import { createElement } from 'lwc';
import GtmReadoutsOverview from 'c/gtmReadoutsOverview';
import getReadoutsForReview from '@salesforce/apex/GtmReadoutController.getReadoutsForReview';

jest.mock(
    '@salesforce/apex/GtmReadoutController.getReadoutsForReview',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-gtm-readouts-overview', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders a card for each readout returned', async () => {
        getReadoutsForReview.mockResolvedValue([
            {
                id: 'a01',
                name: 'Acme Readout',
                status: 'Draft',
                assessmentRequestName: 'Acme Assessment',
                company: 'Acme Co',
                lastModifiedDate: '2026-01-01T00:00:00.000Z'
            },
            {
                id: 'a02',
                name: 'Globex Readout',
                status: 'Approved',
                assessmentRequestName: 'Globex Assessment',
                company: 'Globex',
                lastModifiedDate: '2026-01-02T00:00:00.000Z'
            }
        ]);

        const element = createElement('c-gtm-readouts-overview', { is: GtmReadoutsOverview });
        document.body.appendChild(element);
        await flushPromises();

        const cards = element.shadowRoot.querySelectorAll('.rcard');
        expect(cards.length).toBe(2);
        expect(element.shadowRoot.textContent).toContain('Acme Readout');
        expect(element.shadowRoot.textContent).toContain('Globex Readout');
    });

    it('shows an empty state when there are no readouts to review', async () => {
        getReadoutsForReview.mockResolvedValue([]);

        const element = createElement('c-gtm-readouts-overview', { is: GtmReadoutsOverview });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelectorAll('.rcard').length).toBe(0);
        expect(element.shadowRoot.textContent).toContain('No draft or approved readouts');
    });

    // A rep clicks Refresh precisely because something just changed — most
    // often a readout they approved or published in the editor, which should
    // then change badge or drop off this list entirely. That only works if the
    // refetch reaches the server: getReadoutsForReview is imperative and
    // deliberately not cacheable, so a stale client-cached response can't be
    // served in place of the post-DML state.
    it('refetches from the server on Refresh and re-renders the new rows', async () => {
        getReadoutsForReview.mockResolvedValueOnce([
            {
                id: 'a01',
                name: 'Acme Readout',
                status: 'Draft',
                assessmentRequestName: 'Acme Assessment',
                company: 'Acme Co',
                lastModifiedDate: '2026-01-01T00:00:00.000Z'
            },
            {
                id: 'a02',
                name: 'Globex Readout',
                status: 'Approved',
                assessmentRequestName: 'Globex Assessment',
                company: 'Globex',
                lastModifiedDate: '2026-01-02T00:00:00.000Z'
            }
        ]);

        const element = createElement('c-gtm-readouts-overview', { is: GtmReadoutsOverview });
        document.body.appendChild(element);
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('.rcard').length).toBe(2);
        expect(element.shadowRoot.textContent).toContain('Draft');

        // Globex was published elsewhere and drops off; Acme was approved.
        getReadoutsForReview.mockResolvedValue([
            {
                id: 'a01',
                name: 'Acme Readout',
                status: 'Approved',
                assessmentRequestName: 'Acme Assessment',
                company: 'Acme Co',
                lastModifiedDate: '2026-01-03T00:00:00.000Z'
            }
        ]);

        element.shadowRoot.querySelector('lightning-button-icon').click();
        await flushPromises();

        expect(getReadoutsForReview).toHaveBeenCalledTimes(2);
        expect(element.shadowRoot.querySelectorAll('.rcard').length).toBe(1);
        expect(element.shadowRoot.textContent).not.toContain('Globex Readout');
        expect(element.shadowRoot.querySelector('.rcard .badge--approved')).not.toBeNull();
    });

    it('surfaces an Apex error instead of failing silently', async () => {
        getReadoutsForReview.mockRejectedValue({ body: { message: 'boom' } });

        const element = createElement('c-gtm-readouts-overview', { is: GtmReadoutsOverview });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.ov-err').textContent).toBe('boom');
    });
});
