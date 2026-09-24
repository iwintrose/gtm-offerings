/**
 * ISSUE #overview-sales-dashboard-2-act-today
 *
 * Row 1 of the Overview: four "Act today" tiles. New requests / Readout
 * waiting counts and all names come from getActToday; Came back / Went quiet
 * counts come from the funnel's getStageCountsAura call (called once).
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
import getDeals from '@salesforce/apex/GtmHomeSnapshotController.getDeals';
import getStageCountsAura from '@salesforce/apex/GtmLinkStageService.getStageCountsAura';
import getActToday from '@salesforce/apex/GtmActTodayController.getActToday';

const fs = require('fs');
const path = require('path');

jest.mock('@salesforce/apex/GtmPageContentController.getHomeSummary', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmHomeSnapshotController.getSnapshot', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmHomeSnapshotController.getDeals', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmLinkStageService.getStageCountsAura', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmActTodayController.getActToday', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmFeedbackController.getFeedbackFor', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmFeedbackController.submitFeedback', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const COUNTS = { sent: 30, engaged: 20, started: 10, submitted: 5, quiet: 4, hot: 2, notOpened: 3, truncated: false };
const ACT = {
    newRequests: { count: 12, capped: false, names: ['Acme', 'Beta', 'Gamma'] },
    readoutWaiting: { count: 2, capped: false, names: ['Delta', 'Epsilon'] },
    cameBackNames: ['Zeta', 'Eta'],
    wentQuietNames: ['Theta', 'Iota', 'Kappa']
};

function mount({ counts = COUNTS, act = ACT, actError = null, deals = [] } = {}) {
    getHomeSummary.mockResolvedValue({ offerings: [], activity: [], pageTitles: {} });
    getSnapshot.mockResolvedValue(null);
    getDeals.mockResolvedValue(deals);
    getStageCountsAura.mockResolvedValue(counts);
    if (actError) getActToday.mockRejectedValue({ body: { message: actError } });
    else getActToday.mockResolvedValue(act);
    const element = createElement('c-gtm-overview', { is: GtmOverview });
    document.body.appendChild(element);
    return element;
}

const root = (el) => el.shadowRoot || el;
const q = (el, sel) => root(el).querySelector(sel);
const qa = (el, sel) => [...root(el).querySelectorAll(sel)];
const tile = (el, key) => q(el, `.at-tile[data-key="${key}"]`);

describe('c-gtm-overview: Act today (ISSUE #overview-sales-dashboard-2-act-today)', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('renders four tiles in order with count, hint and names, before the follow-up table row', async () => {
        const element = mount();
        await flushPromises();
        const tiles = qa(element, '.at-tile');
        expect(tiles.map((t) => t.dataset.key)).toEqual(['new', 'hot', 'quiet', 'readout']);
        expect(tiles.map((t) => t.querySelector('.at-label').textContent))
            .toEqual(['New requests', 'Came back', 'Went quiet', 'Readout waiting']);
        // New requests / Readout waiting counts are the server's; hot/quiet are the funnel's.
        expect(tiles.map((t) => t.querySelector('.at-count').textContent)).toEqual(['12', '2', '4', '2']);
        tiles.forEach((t) => expect(t.querySelector('.at-hint').textContent.length).toBeGreaterThan(0));
        expect([...tile(element, 'new').querySelectorAll('.at-name')].map((n) => n.textContent))
            .toEqual(['Acme', 'Beta', 'Gamma']);
        expect([...tile(element, 'hot').querySelectorAll('.at-name')].map((n) => n.textContent))
            .toEqual(['Zeta', 'Eta']);
        expect(qa(tile(element, 'quiet'), '.at-name').length).toBe(3);
        const row = q(element, '.at-row');
        const row2 = q(element, '.ov-row2');
        expect(row.compareDocumentPosition(row2) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    });

    it('shows at most three names even if the payload carries more', async () => {
        const element = mount({ act: { ...ACT, cameBackNames: ['A', 'B', 'C', 'D'] } });
        await flushPromises();
        expect(qa(tile(element, 'hot'), '.at-name').length).toBe(3);
    });

    // ISSUE #274: .at-name used to hand-duplicate the truncation rules
    // gtmLinkCell.css already declares; it now reuses that shared class
    // (imported into gtmOverview.css) instead of a second copy.
    it('truncates "Needs attention today" names with the shared gtm-link-cell class', async () => {
        const element = mount();
        await flushPromises();
        const names = qa(tile(element, 'new'), '.at-name');
        expect(names.length).toBeGreaterThan(0);
        names.forEach((n) => {
            expect(n.classList.contains('gtm-link-cell')).toBe(true);
            expect(n.title).toBe(n.textContent);
        });
    });

    it('calls getStageCountsAura once and never derives hot/quiet from getActToday', async () => {
        const element = mount({ act: { ...ACT } });
        await flushPromises();
        expect(getStageCountsAura).toHaveBeenCalledTimes(1);
        expect(getActToday).toHaveBeenCalledTimes(1);
        expect(q(tile(element, 'hot'), '.at-count').textContent).toBe('2');
    });

    it('shows N+ for capped assessments counts and truncated stage counts', async () => {
        const element = mount({
            counts: { ...COUNTS, truncated: true },
            act: { ...ACT, newRequests: { count: 500, capped: true, names: [] }, readoutWaiting: { count: 3, capped: false, names: [] } }
        });
        await flushPromises();
        expect(q(tile(element, 'new'), '.at-count').textContent).toBe('500+');
        expect(q(tile(element, 'readout'), '.at-count').textContent).toBe('3');
        expect(q(tile(element, 'hot'), '.at-count').textContent).toBe('2+');
        expect(q(tile(element, 'quiet'), '.at-count').textContent).toBe('4+');
    });

    it('zero state: "0", "All caught up", no names, still clickable', async () => {
        const element = mount({
            counts: { ...COUNTS, hot: 0, quiet: 0 },
            act: {
                newRequests: { count: 0, capped: false, names: [] },
                readoutWaiting: { count: 0, capped: false, names: [] },
                cameBackNames: [], wentQuietNames: []
            }
        });
        await flushPromises();
        for (const key of ['new', 'hot', 'quiet', 'readout']) {
            const t = tile(element, key);
            expect(q(t, '.at-count').textContent).toBe('0');
            expect(q(t, '.at-hint').textContent).toBe('All caught up');
            expect(qa(t, '.at-name').length).toBe(0);
            expect(t.getAttribute('role')).toBe('button');
        }
        tile(element, 'new').click();
        expect(mockNavigate).toHaveBeenCalledTimes(1);
    });

    it('navigates each tile to its pre-filtered tab', async () => {
        const element = mount();
        await flushPromises();
        const expected = {
            new: { apiName: 'GTM_Assessments', state: { c__astatus: 'new' } },
            hot: { apiName: 'GTM_Pages', state: { c__stage: 'hot' } },
            quiet: { apiName: 'GTM_Pages', state: { c__stage: 'quiet' } },
            readout: { apiName: 'GTM_Assessments', state: { c__areadout: 'pending,approved-unsent' } }
        };
        for (const key of Object.keys(expected)) {
            mockNavigate.mockClear();
            tile(element, key).click();
            expect(mockNavigate).toHaveBeenCalledTimes(1);
            expect(mockNavigate.mock.calls[0][0]).toEqual({
                type: 'standard__navItemPage',
                attributes: { apiName: expected[key].apiName },
                state: expected[key].state
            });
        }
    });

    it('is keyboard operable: role, tabindex, Enter and Space navigate once; other keys do not', async () => {
        const element = mount();
        await flushPromises();
        const t = tile(element, 'hot');
        expect(t.getAttribute('role')).toBe('button');
        expect(t.getAttribute('tabindex')).toBe('0');
        t.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
        expect(mockNavigate).toHaveBeenCalledTimes(1);
        t.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true }));
        expect(mockNavigate).toHaveBeenCalledTimes(2);
        t.dispatchEvent(new KeyboardEvent('keydown', { key: 'a', bubbles: true }));
        t.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true }));
        expect(mockNavigate).toHaveBeenCalledTimes(2);
    });

    it('an act-today failure shows an error and leaves hot/quiet counts intact', async () => {
        const element = mount({ actError: 'boom' });
        await flushPromises();
        expect(q(element, '.at-error').textContent).toContain('boom');
        expect(q(tile(element, 'hot'), '.at-count').textContent).toBe('2');
        expect(q(tile(element, 'new'), '.at-count').textContent).toBe('–');
    });

    it('server values win over a disagreeing getDeals()', async () => {
        const element = mount({
            deals: [{ configId: 'a0X000000000001', opportunityId: '006000000000001', opportunityName: 'Only Deal', views: 9 }]
        });
        await flushPromises();
        expect(q(tile(element, 'new'), '.at-count').textContent).toBe('12');
    });

    it('adds no new hex colour in the Row 1 CSS', () => {
        const css = fs.readFileSync(path.join(__dirname, '..', 'gtmOverview.css'), 'utf8');
        const block = css.slice(css.indexOf('/* Row 1: "Act today"'), css.indexOf('.ov-col {'));
        const rest = css.replace(block, '');
        const used = new Set((block.match(/#[0-9a-fA-F]{3,8}\b/g) || []).map((h) => h.toLowerCase()));
        const existing = new Set((rest.match(/#[0-9a-fA-F]{3,8}\b/g) || []).map((h) => h.toLowerCase()));
        expect(used.size).toBeGreaterThan(0);
        for (const h of used) expect(existing.has(h)).toBe(true);
    });
});
