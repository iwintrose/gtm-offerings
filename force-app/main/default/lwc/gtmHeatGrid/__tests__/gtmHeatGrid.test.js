/**
 * ISSUE #overview-bd-heat-redesign-2-heat-grid
 */
const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) => {
        return class extends Base {
            [Navigate](...args) {
                mockNavigate(...args);
            }
        };
    };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin };
});

// eslint-disable-next-line import/first, import/order
import { createElement } from 'lwc';
// eslint-disable-next-line import/first
import GtmHeatGrid from 'c/gtmHeatGrid';
import getHeatGridAura from '@salesforce/apex/GtmLinkStageService.getHeatGridAura';
import createFollowUpTask from '@salesforce/apex/GtmHeatGridActionsController.createFollowUpTask';

jest.mock('@salesforce/apex/GtmLinkStageService.getHeatGridAura', () => ({ default: jest.fn() }), { virtual: true });
jest.mock(
    '@salesforce/apex/GtmHeatGridActionsController.createFollowUpTask',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const RESULT = {
    truncated: false,
    rows: [
        {
            accountId: '001HOT',
            accountName: 'Hot Co',
            contactId: '003HOT',
            contactName: 'Pat Prospect',
            opportunityId: '006HOT',
            opportunityStage: 'Negotiation',
            latestSignal: 'Assessment submitted today',
            currentTier: 'submitted',
            nextAction: 'nudge',
            days: [{ day: '2026-09-22', tier: 'submitted', intensity: 3 }]
        },
        {
            accountId: '001STARTED',
            accountName: 'Started Co',
            contactId: '003STARTED',
            contactName: 'Jordan Started',
            opportunityId: '006STARTED',
            opportunityStage: 'Qualification',
            latestSignal: 'Assessment started yesterday',
            currentTier: 'started',
            nextAction: 'follow_up',
            days: [{ day: '2026-09-22', tier: 'started', intensity: 2 }]
        },
        {
            accountId: '001COLD',
            accountName: 'Cold Co',
            contactId: null,
            contactName: '',
            opportunityId: null,
            opportunityStage: '',
            latestSignal: 'No activity in the last 14 days',
            currentTier: 'none',
            nextAction: 'call_now',
            days: [{ day: '2026-09-22', tier: 'none', intensity: 0 }]
        }
    ]
};

function mount() {
    const el = createElement('c-gtm-heat-grid', { is: GtmHeatGrid });
    document.body.appendChild(el);
    return el;
}

afterEach(() => {
    document.body.innerHTML = '';
    jest.clearAllMocks();
});

describe('c-gtm-heat-grid', () => {
    it('loads on connect and renders one row per Account, sorted as the server returned them', async () => {
        getHeatGridAura.mockResolvedValue(RESULT);
        const el = mount();
        await flushPromises();

        const rows = el.shadowRoot.querySelectorAll('.heat-grid__row');
        expect(rows).toHaveLength(3);
    });

    it('shows an error message when the load fails', async () => {
        getHeatGridAura.mockRejectedValue({ body: { message: 'boom' } });
        const el = mount();
        await flushPromises();

        const errorEl = el.shadowRoot.querySelector('.heat-grid__status--error');
        expect(errorEl.textContent).toBe('boom');
    });

    it('shows the empty state when there are no rows', async () => {
        getHeatGridAura.mockResolvedValue({ truncated: false, rows: [] });
        const el = mount();
        await flushPromises();

        expect(el.shadowRoot.querySelectorAll('.heat-grid__row')).toHaveLength(0);
        expect(el.shadowRoot.textContent).toContain('No account activity');
    });

    it('renders the Nudge action disabled, with its tooltip on a focusable wrapper (not the disabled button)', async () => {
        // A disabled HTML element never fires hover/focus events, so a `title`
        // on the disabled lightning-button itself would be permanently inert --
        // the tooltip must live on a non-disabled wrapper instead.
        getHeatGridAura.mockResolvedValue(RESULT);
        const el = mount();
        await flushPromises();

        const buttons = el.shadowRoot.querySelectorAll('lightning-button');
        const nudgeButton = buttons[0];
        expect(nudgeButton.label).toBe('Nudge');
        expect(nudgeButton.disabled).toBe(true);

        const wrapper = el.shadowRoot.querySelectorAll('.heat-grid__action-tip')[0];
        expect(wrapper.title).toContain('gus-nudge-tool-and-readout-viewed-tracking');
        expect(wrapper.tabIndex).toBe(0);
    });

    it('"Call now" navigates to the Log a Call quick action pre-filled from the row, no Apex call', async () => {
        getHeatGridAura.mockResolvedValue(RESULT);
        const el = mount();
        await flushPromises();

        const buttons = el.shadowRoot.querySelectorAll('lightning-button');
        buttons[2].click(); // Cold Co row -> call_now
        await flushPromises();

        expect(mockNavigate).toHaveBeenCalledWith(
            expect.objectContaining({
                type: 'standard__quickAction',
                attributes: { apiName: 'Task.LogACall' }
            })
        );
        expect(createFollowUpTask).not.toHaveBeenCalled();
    });

    it('"Follow up" creates a Task against the row\'s Opportunity', async () => {
        getHeatGridAura.mockResolvedValue(RESULT);
        createFollowUpTask.mockResolvedValue('00TFOLLOWUP');
        const el = mount();
        await flushPromises();

        const buttons = el.shadowRoot.querySelectorAll('lightning-button');
        buttons[1].click(); // Started Co row -> follow_up
        await flushPromises();

        expect(createFollowUpTask).toHaveBeenCalledWith({ opportunityId: '006STARTED', accountName: 'Started Co' });
    });

    it('a click on the disabled Nudge button does not create a Task or navigate', async () => {
        getHeatGridAura.mockResolvedValue(RESULT);
        const el = mount();
        await flushPromises();

        const buttons = el.shadowRoot.querySelectorAll('lightning-button');
        buttons[0].click();
        await flushPromises();

        expect(createFollowUpTask).not.toHaveBeenCalled();
        expect(mockNavigate).not.toHaveBeenCalled();
    });

    // ISSUE #274: Stage/Latest-signal/Next-best-action had no truncation at
    // all -- only Account/Contact (via c-gtm-link-cell) did. These reuse the
    // same shared `.gtm-link-cell` class (imported from the real gtmLinkCell
    // bundle, not a third hand-duplicated copy -- see gtmHeatGrid.css).
    it('truncates the Stage and Latest signal columns with the shared gtm-link-cell class', async () => {
        getHeatGridAura.mockResolvedValue(RESULT);
        const el = mount();
        await flushPromises();

        const stageCells = el.shadowRoot.querySelectorAll('.heat-grid__col--stage .gtm-link-cell');
        const signalCells = el.shadowRoot.querySelectorAll('.heat-grid__col--signal .gtm-link-cell');
        expect(stageCells).toHaveLength(3);
        expect(signalCells).toHaveLength(3);
        expect(stageCells[0].textContent).toBe('Negotiation');
        expect(stageCells[0].title).toBe('Negotiation');
        expect(signalCells[0].textContent).toBe('Assessment submitted today');
    });

    it('truncates the Next best action tooltip wrapper with the shared gtm-link-cell class', async () => {
        getHeatGridAura.mockResolvedValue(RESULT);
        const el = mount();
        await flushPromises();

        const tips = el.shadowRoot.querySelectorAll('.heat-grid__action-tip');
        expect(tips).toHaveLength(3);
        tips.forEach((tip) => expect(tip.classList.contains('gtm-link-cell')).toBe(true));
    });

    // ISSUE #274: unlike lightning-datatable's own internal horizontal-scroll
    // wrapper, this hand-built CSS Grid table had none of its own -- it just
    // stretched to 100% of its card's width.
    it('wraps the grid in its own horizontal-scroll container', async () => {
        getHeatGridAura.mockResolvedValue(RESULT);
        const el = mount();
        await flushPromises();

        const scrollWrapper = el.shadowRoot.querySelector('.heat-grid-scroll');
        expect(scrollWrapper).not.toBeNull();
        expect(scrollWrapper.querySelector('.heat-grid')).not.toBeNull();
    });
});
