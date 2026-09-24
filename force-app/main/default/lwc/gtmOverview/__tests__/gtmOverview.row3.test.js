/**
 * ISSUE #overview-bd-heat-redesign-1-layout-toggle
 *
 * The Today/Offerings toggle: Offerings holds only the re-homed per-offering
 * content/performance card (live-link and submitted counts from
 * GtmOverviewOfferingCounts); the "Assessment results" ranked datatable stays
 * in Today, unchanged in shape from the old Row 3. The two views are never
 * blended -- the offering card renders ONLY under Offerings, and Assessment
 * results renders ONLY under Today.
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
import getOfferingCounts from '@salesforce/apex/GtmOverviewOfferingCounts.getOfferingCounts';
import getAssessmentPage from '@salesforce/apex/GtmAssessmentListController.getAssessmentPage';

const fs = require('fs');
const path = require('path');

jest.mock('@salesforce/apex/GtmPageContentController.getHomeSummary', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmHomeSnapshotController.getSnapshot', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmHomeSnapshotController.getDeals', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmLinkStageService.getStageCountsAura', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmOverviewOfferingCounts.getOfferingCounts', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmAssessmentListController.getAssessmentPage', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmFeedbackController.getFeedbackFor', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmFeedbackController.submitFeedback', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const OFFERINGS = [
    { offeringKey: 'ma-migrator', label: 'Migration Accelerator', isFramework: false, offeringStatus: 'Active', archived: false,
      pages: [{ templateType: 'story', sectionCount: 2, fieldCount: 5 }] },
    { offeringKey: 'other', label: 'Other Offering', isFramework: false, offeringStatus: 'Active', archived: false,
      pages: [{ templateType: 'story', sectionCount: 1, fieldCount: 1 }] }
];

// Deliberately NOT in tier order alphabetically or by score: the component must keep server order.
const ROWS = [
    { recordId: 'a1', name: 'AR-1', company: 'Zeta Co', tier: 'Fast-Track', score: 30, requestStatus: 'New' },
    { recordId: 'a2', name: 'AR-2', company: 'Alpha Co', tier: 'Discovery First', score: 10, requestStatus: 'Contacted' },
    { recordId: 'a3', name: 'AR-3', contactName: 'Pat Doe', tier: null, requestStatus: 'New' },
    { recordId: 'a4', name: 'AR-4', tier: 'Prep Required', score: 18, requestStatus: 'New' }
];

function mount({ counts, countsError, rows = ROWS, rowsError, offerings = OFFERINGS } = {}) {
    getHomeSummary.mockResolvedValue({ offerings, activity: [], pageTitles: {} });
    getSnapshot.mockResolvedValue(null);
    getDeals.mockResolvedValue([]);
    getStageCountsAura.mockResolvedValue({ sent: 0, engaged: 0, started: 0, submitted: 0 });
    if (countsError) getOfferingCounts.mockRejectedValue({ body: { message: countsError } });
    else getOfferingCounts.mockResolvedValue(counts || []);
    if (rowsError) getAssessmentPage.mockRejectedValue({ body: { message: rowsError } });
    else getAssessmentPage.mockResolvedValue({ rows });
    const element = createElement('c-gtm-overview', { is: GtmOverview });
    document.body.appendChild(element);
    return element;
}

const q = (el, sel) => el.shadowRoot.querySelector(sel);
const qa = (el, sel) => [...el.shadowRoot.querySelectorAll(sel)];

/** Switches from the default Today view to Offerings. */
function showOfferings(element) {
    q(element, '[data-view="offerings"]').click();
}
function showToday(element) {
    q(element, '[data-view="today"]').click();
}

describe('c-gtm-overview: Today/Offerings toggle, offering card and Assessment results (ISSUE #overview-bd-heat-redesign-1-layout-toggle)', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('defaults to Today: offering card markup is absent, Assessment results is present', async () => {
        const element = mount();
        await flushPromises();
        expect(q(element, '[data-view="today"]').getAttribute('aria-selected')).toBe('true');
        expect(q(element, '[data-view="offerings"]').getAttribute('aria-selected')).toBe('false');
        expect(q(element, '.ov-offerings')).toBeNull();
        expect(qa(element, '.ocard').length).toBe(0);
        expect(q(element, '.ov-results')).not.toBeNull();
    });

    it('switching to Offerings shows the offering card and hides Assessment results; switching back reverses it', async () => {
        const element = mount();
        await flushPromises();

        showOfferings(element);
        await flushPromises();
        expect(q(element, '[data-view="offerings"]').getAttribute('aria-selected')).toBe('true');
        expect(q(element, '.ov-offerings')).not.toBeNull();
        expect(qa(element, '.ocard').length).toBe(2);
        expect(q(element, '.ov-results')).toBeNull();
        expect(q(element, '.at-row')).toBeNull();

        showToday(element);
        await flushPromises();
        expect(q(element, '.ov-offerings')).toBeNull();
        expect(qa(element, '.ocard').length).toBe(0);
        expect(q(element, '.ov-results')).not.toBeNull();
    });

    it('never renders the offering card and Assessment results together, in either view', async () => {
        const element = mount();
        await flushPromises();
        expect(!!q(element, '.ov-offerings') && !!q(element, '.ov-results')).toBe(false);
        showOfferings(element);
        await flushPromises();
        expect(!!q(element, '.ov-offerings') && !!q(element, '.ov-results')).toBe(false);
    });

    it('shows live-link and submitted counts per card, zeros included, from the Apex payload', async () => {
        const element = mount({ counts: [
            { offeringKey: 'ma-migrator', offeringLabel: 'Migration Accelerator', liveLinkCount: 4, submittedAssessmentCount: 2 },
            { offeringKey: 'other', offeringLabel: 'Other Offering', liveLinkCount: 0, submittedAssessmentCount: 0 }
        ] });
        await flushPromises();
        showOfferings(element);
        await flushPromises();
        const cards = qa(element, '.ocard');
        expect(cards.length).toBe(2);
        expect(cards[0].querySelector('.ocount-live').textContent).toBe('Live links: 4');
        expect(cards[0].querySelector('.ocount-subm').textContent).toBe('Assessments submitted: 2');
        expect(cards[1].querySelector('.ocount-live').textContent).toBe('Live links: 0');
        expect(cards[1].querySelector('.ocount-subm').textContent).toBe('Assessments submitted: 0');
    });

    it('states the live-link definition in a footnote', async () => {
        const element = mount();
        await flushPromises();
        showOfferings(element);
        await flushPromises();
        expect(q(element, '.ocount-footnote').textContent).toContain('Live links = sent, active links');
        expect(q(element, '.ocount-footnote').textContent).toContain('Draft and Rep_Direct');
    });

    it('degrades to cards without counts when the counts call fails', async () => {
        const element = mount({ countsError: 'boom' });
        await flushPromises();
        showOfferings(element);
        await flushPromises();
        expect(qa(element, '.ocard').length).toBe(2);
        expect(qa(element, '.ocard-counts').length).toBe(0);
        expect(q(element, '.ov-err')).toBeNull();
    });

    it('keeps the existing offerings empty state, only in the Offerings view', async () => {
        const element = mount({ offerings: [] });
        await flushPromises();
        showOfferings(element);
        await flushPromises();
        expect(q(element, '.ov-offerings').textContent).toContain('No offerings set up yet');
    });

    it('requests 25 rows with no filters and no sort, and renders them in the server order, in Today', async () => {
        const element = mount();
        await flushPromises();
        expect(getAssessmentPage).toHaveBeenCalledWith({ query: { pageSize: 25 } });
        const table = q(element, '.ar-table');
        expect(table.data.map((r) => r.recordId)).toEqual(['a1', 'a2', 'a3', 'a4']);
        // Null tier is shown (em dash), not dropped.
        expect(table.data[2].tierLabel).toBe('—');
        expect(table.data.map((r) => r.openLabel)).toEqual(['Zeta Co', 'Alpha Co', 'Pat Doe', 'AR-4']);
        expect(table.keyField).toBe('recordId');
        expect(table.hideCheckboxColumn).toBe(true);
    });

    it('uses a plain-text (gtmLink) company column first, then tier, score and status, all unsortable', async () => {
        // ISSUE #274: was `type: 'button'`, which lightning-datatable renders
        // centered and without truncation, unlike every other column -- the
        // exact "one row looks different" defect. `gtmLink` (the same custom
        // type the Assessments tab's own Account/Contact columns use) renders
        // through the identical left-aligned, truncating text-cell path as
        // tierLabel/score/requestStatus, while still dispatching a rowaction.
        const element = mount();
        await flushPromises();
        const cols = q(element, '.ar-table').columns;
        expect(cols.map((c) => c.fieldName)).toEqual(['openLabel', 'tierLabel', 'score', 'requestStatus']);
        expect(cols[0].type).toBe('gtmLink');
        expect(cols[0].type).not.toBe('button');
        expect(cols[0].typeAttributes.name).toBe('open');
        expect(cols[0].typeAttributes.idField).toBe('recordId');
        cols.forEach((c) => expect(c.sortable).not.toBe(true));
    });

    it('lives in a capped scroll container that shares the Row 2 cap', async () => {
        const element = mount();
        await flushPromises();
        const card = q(element, '.ov-results');
        expect(card.classList.contains('ov-row2-card')).toBe(true);
        expect(q(element, '.ov-results-body').className).toContain('slds-scrollable_y');
        const css = fs.readFileSync(path.join(__dirname, '..', 'gtmOverview.css'), 'utf8');
        expect(css).toMatch(/--ov-row2-cap:\s*470px/);
        expect(css).toMatch(/\.ov-row2-card\s*\{[^}]*max-height:\s*var\(--ov-row2-cap\)/);
        expect(css).toMatch(/\.ov-results-body[^{]*\{[^}]*overflow-y:\s*auto/);
    });

    it('opens the assessment from the row action with c__assessmentRequestId', async () => {
        const element = mount();
        await flushPromises();
        // The gtmLink cell type only ever dispatches { recordId }, mirroring
        // what c-gtm-link-cell's activate() actually sends -- see the
        // handler's own comment for why.
        q(element, '.ar-table').dispatchEvent(new CustomEvent('rowaction', {
            detail: { action: { name: 'open' }, row: { recordId: 'a2' } }
        }));
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: { c__assessmentRequestId: 'a2' }
        });
    });

    it('carries readoutId and offeringKey through the row action by re-looking up the full row (ISSUE #274)', async () => {
        const element = mount({ rows: [
            { recordId: 'r1', name: 'AR-R1', company: 'Readout Co', tier: 'Fast-Track', score: 40,
              requestStatus: 'Completed', readoutId: 'ro1', offeringKey: 'ma-migrator' }
        ] });
        await flushPromises();
        // The synthetic gtmLink row only ever carries recordId -- readoutId
        // and offeringKey have to come from a lookup against assessmentRows,
        // not the dispatched event, or the deep link silently loses them.
        q(element, '.ar-table').dispatchEvent(new CustomEvent('rowaction', {
            detail: { action: { name: 'open' }, row: { recordId: 'r1' } }
        }));
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: { c__assessmentRequestId: 'r1', c__readoutId: 'ro1', c__offeringKey: 'ma-migrator' }
        });
    });

    it('View all assessments has no state; Ready to book carries c__apreset', async () => {
        const element = mount();
        await flushPromises();
        q(element, '.ov-view-all').click();
        expect(mockNavigate).toHaveBeenLastCalledWith({
            type: 'standard__navItemPage', attributes: { apiName: 'GTM_Assessments' }
        });
        q(element, '.ov-ready-to-book').click();
        expect(mockNavigate).toHaveBeenLastCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: { c__apreset: 'ready-to-book' }
        });
    });

    it('shows a friendly empty state with no table', async () => {
        const element = mount({ rows: [] });
        await flushPromises();
        expect(q(element, '.ar-empty').textContent).toBe('No assessments submitted yet');
        expect(q(element, '.ar-table')).toBeNull();
        expect(q(element, '.ar-error')).toBeNull();
    });

    it('shows an error banner in the card only when the list fails', async () => {
        const element = mount({ rowsError: 'nope' });
        await flushPromises();
        expect(q(element, '.ar-error').textContent).toContain('nope');
        expect(q(element, '.ar-empty')).toBeNull();
    });

    it('has no chart, average-score text, or new hex colours in the Row 3 CSS', async () => {
        const element = mount();
        await flushPromises();
        const text = element.shadowRoot.textContent;
        expect(text).not.toContain('How ready are the prospects');
        expect(text).not.toMatch(/average/i);
        const css = fs.readFileSync(path.join(__dirname, '..', 'gtmOverview.css'), 'utf8');
        const row3Css = css.slice(css.indexOf('/* ── Row 3'));
        const hexes = (row3Css.match(/#[0-9a-fA-F]{3,6}\b/g) || []).map((h) => h.toLowerCase());
        expect(hexes.filter((h) => h !== '#747474')).toEqual([]);
    });

    it('removes the funnel card and its stage-count markup entirely', async () => {
        const element = mount();
        await flushPromises();
        expect(q(element, '.ov-funnel-card')).toBeNull();
        expect(q(element, '.fs-row')).toBeNull();
        showOfferings(element);
        await flushPromises();
        expect(q(element, '.ov-funnel-card')).toBeNull();
        expect(q(element, '.fs-row')).toBeNull();
        const jsSrc = fs.readFileSync(path.join(__dirname, '..', 'gtmOverview.js'), 'utf8');
        expect(jsSrc).not.toMatch(/funnelSegments|fs-row|fs-shape/);
        const htmlSrc = fs.readFileSync(path.join(__dirname, '..', 'gtmOverview.html'), 'utf8');
        expect(htmlSrc).not.toMatch(/funnelSegments|fs-row|fs-shape/);
        const cssSrc = fs.readFileSync(path.join(__dirname, '..', 'gtmOverview.css'), 'utf8');
        expect(cssSrc).not.toMatch(/fs-row|fs-shape/);
    });
});
