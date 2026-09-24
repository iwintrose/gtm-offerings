import { createElement } from 'lwc';
import { CurrentPageReference, __navigateMock } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import { registerLdsTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import GtmReadoutsOverview from 'c/gtmReadoutsOverview';
import getAssessmentPage from '@salesforce/apex/GtmAssessmentListController.getAssessmentPage';
import getAssessmentFilterOptions from '@salesforce/apex/GtmAssessmentListController.getAssessmentFilterOptions';

// The stock sfdx-lwc-jest NavigationMixin stub has an empty Navigate() that
// cannot be spied on (the component prototype is frozen), so this local mock
// forwards every Navigate call to __navigateMock. CurrentPageReference stays
// the standard test wire adapter.
jest.mock('lightning/navigation', () => {
    const { createTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    const Navigate = Symbol('Navigate');
    const GenerateUrl = Symbol('GenerateUrl');
    const navigateMock = jest.fn();
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](...args) {
                navigateMock(...args);
            }
            [GenerateUrl]() {
                return Promise.resolve('https://www.example.com');
            }
        };
    NavigationMixin.Navigate = Navigate;
    NavigationMixin.GenerateUrl = GenerateUrl;
    return {
        CurrentPageReference: createTestWireAdapter(jest.fn()),
        NavigationMixin,
        __navigateMock: navigateMock
    };
});
jest.mock(
    '@salesforce/apex/GtmAssessmentListController.getAssessmentPage',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentListController.getAssessmentFilterOptions',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmSavedConfigurationController.generateRepDirectShareLink',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const getRecordWireAdapter = registerLdsTestWireAdapter(getRecord);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const REQ_ID = 'a0X000000000001AAA';

function row(overrides = {}) {
    return {
        recordId: REQ_ID,
        name: 'AR-0049',
        contactId: '003000000000001AAA',
        contactName: 'Jane Smith',
        accountId: '001000000000001AAA',
        company: 'Acme Co',
        requesterName: 'Jane Smith',
        offeringKey: 'migration-accelerator',
        tier: 'Fast-Track',
        tierRank: 4,
        score: 30,
        requestStatus: 'New',
        readoutId: 'a01000000000001AAA',
        readoutStatus: 'Draft',
        readoutNotificationSent: false,
        submittedAt: '2026-01-01T00:00:00.000Z',
        createdDate: '2026-01-01T00:00:00.000Z',
        ...overrides
    };
}

function page(rows, extra = {}) {
    return {
        rows,
        totalCount: rows.length,
        totalIsCapped: false,
        offeringOptions: ['migration-accelerator'],
        ...extra
    };
}

function emptyPage() {
    return page([], { offeringOptions: [] });
}

function mount() {
    const element = createElement('c-gtm-readouts-overview', { is: GtmReadoutsOverview });
    document.body.appendChild(element);
    return element;
}

function table(element) {
    return element.shadowRoot.querySelector('c-gtm-link-datatable');
}

function bar(element) {
    return element.shadowRoot.querySelector('c-gtm-filter-bar');
}

function lastQuery() {
    const calls = getAssessmentPage.mock.calls;
    return calls[calls.length - 1][0].query;
}

function openFirstRow(element) {
    const t = table(element);
    t.dispatchEvent(
        new CustomEvent('rowaction', { detail: { action: { name: 'open' }, row: t.data[0] } })
    );
}

describe('c-gtm-readouts-overview', () => {
    const navigateSpy = __navigateMock;

    beforeEach(() => {
        getAssessmentFilterOptions.mockResolvedValue([]);
        navigateSpy.mockReset();
        window.history.replaceState({}, '', '/');
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        window.history.replaceState({}, '', '/');
    });

    // ------------------------------------------------------------- the table

    describe('assessments table', () => {
        it('renders one datatable row per assessment request, not a card grid', async () => {
            getAssessmentPage.mockResolvedValue(
                page([row(), row({ recordId: 'a0X000000000002AAA', name: 'AR-0050', contactName: 'Bo Globex' })])
            );
            const element = mount();
            await flushPromises();

            expect(element.shadowRoot.querySelector('.rcard')).toBeNull();
            expect(element.shadowRoot.querySelector('.cards')).toBeNull();
            const t = table(element);
            expect(t).not.toBeNull();
            expect(t.data).toHaveLength(2);
            expect(t.keyField).toBe('recordId');
            expect(t.hideCheckboxColumn).toBe(true);
        });

        it('declares the columns in order; Contact/Account use the shared gtmLink cell type', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();

            const cols = table(element).columns;
            expect(cols.map((c) => c.label)).toEqual([
                'Assessment', 'Contact', 'Account', 'Readiness tier', 'Score',
                'Request status', 'Readout', 'Submitted', 'Offering', undefined
            ]);
            expect(cols.map((c) => c.type)).toEqual([
                'button', 'gtmLink', 'gtmLink', 'text', 'number', 'text', 'text', 'date', 'text', 'action'
            ]);
            expect(cols[3].cellAttributes.class).toEqual({ fieldName: 'tierClass' });
            expect(cols[6].cellAttributes.class).toEqual({ fieldName: 'readoutClass' });
            // Assessment (button) is the only non-sortable data column.
            expect(cols.filter((c) => c.sortable).map((c) => c.label)).toEqual([
                'Contact', 'Account', 'Readiness tier', 'Score', 'Request status', 'Readout', 'Submitted'
            ]);
        });

        it('maps a server row to Contact/Company links and tier/readout display values', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();

            const [r] = table(element).data;
            expect(r.name).toBe('AR-0049');
            expect(r.contactLabel).toBe('Jane Smith');
            expect(r.contactId).toBe('003000000000001AAA');
            expect(r.contactDisabled).toBe(false);
            expect(r.companyLabel).toBe('Acme Co');
            expect(r.accountId).toBe('001000000000001AAA');
            expect(r.companyDisabled).toBe(false);
            expect(r.tierLabel).toBe('Fast-Track');
            expect(r.tierClass).toContain('slds-text-color_success');
            expect(r.readoutLabel).toBe('Draft');
            expect(r.score).toBe(30);
        });

        it('never renders Contact/Company blank: falls back to requester, company, account and request record', async () => {
            getAssessmentPage.mockResolvedValue(
                page([
                    row({ contactId: null, contactName: null, accountId: null }),
                    row({
                        recordId: 'a0X000000000002AAA', contactId: null, contactName: null,
                        requesterName: null, company: null, accountId: '001000000000009AAA'
                    })
                ])
            );
            const element = mount();
            await flushPromises();

            const [noContact, bare] = table(element).data;
            expect(noContact.contactLabel).toBe('Jane Smith');
            // No id -> the cell is disabled; never a link to some other record.
            expect(noContact.contactDisabled).toBe(true);
            expect(noContact.companyDisabled).toBe(true);
            expect(bare.contactLabel).toBe('AR-0049');
            expect(bare.contactDisabled).toBe(true);
            expect(bare.companyDisabled).toBe(false);
        });

        it('shows "None yet" for a request with no readout and an em dash for a null tier', async () => {
            getAssessmentPage.mockResolvedValue(
                page([row({ readoutId: null, readoutStatus: null, tier: null, tierRank: 0, score: null })])
            );
            const element = mount();
            await flushPromises();

            const [r] = table(element).data;
            expect(r.readoutLabel).toBe('None yet');
            expect(r.readoutId).toBe('');
            expect(r.tierLabel).toBe('—');
            expect(r.score).toBeNull();
        });

        it('first load asks the server for page 1 with the default (best-fit) order and no filters', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            mount();
            await flushPromises();

            expect(getAssessmentPage).toHaveBeenCalledTimes(1);
            const q = lastQuery();
            expect(q.offset).toBe(0);
            expect(q.pageSize).toBe(50);
            expect(q.sortBy).toBeUndefined();
            expect(q.status).toEqual([]);
            expect(q.preset).toBeNull();
            expect(q.range).toBeNull();
        });

        it('has no active sort column by default', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();

            expect(table(element).sortedBy).toBeFalsy();
        });

        it('re-queries the server (offset 0) when a column is sorted, instead of sorting loaded rows', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();

            table(element).dispatchEvent(
                new CustomEvent('sort', { detail: { fieldName: 'score', sortDirection: 'desc' } })
            );
            await flushPromises();

            expect(getAssessmentPage).toHaveBeenCalledTimes(2);
            expect(lastQuery().sortBy).toBe('score');
            expect(lastQuery().sortDir).toBe('desc');
            expect(lastQuery().offset).toBe(0);
            expect(table(element).sortedBy).toBe('score');
            expect(table(element).sortedDirection).toBe('desc');
        });

        it('maps the link columns to the server contact/company sort keys and ignores unknown fields', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();

            table(element).dispatchEvent(
                new CustomEvent('sort', { detail: { fieldName: 'contactLabel', sortDirection: 'asc' } })
            );
            await flushPromises();
            expect(lastQuery().sortBy).toBe('contact');

            getAssessmentPage.mockClear();
            table(element).dispatchEvent(
                new CustomEvent('sort', { detail: { fieldName: 'name', sortDirection: 'asc' } })
            );
            await flushPromises();
            expect(getAssessmentPage).not.toHaveBeenCalled();
        });

        it('appends the next page on loadmore, using the loaded row count as the offset', async () => {
            getAssessmentPage.mockResolvedValueOnce(page([row()], { totalCount: 2 }));
            const element = mount();
            await flushPromises();
            expect(table(element).enableInfiniteLoading).toBe(true);

            getAssessmentPage.mockResolvedValueOnce(
                page([row({ recordId: 'a0X000000000002AAA', name: 'AR-0050' })], { totalCount: 2 })
            );
            table(element).dispatchEvent(new CustomEvent('loadmore'));
            await flushPromises();

            expect(lastQuery().offset).toBe(1);
            expect(table(element).data.map((r) => r.name)).toEqual(['AR-0049', 'AR-0050']);
            expect(table(element).enableInfiniteLoading).toBe(false);
        });

        it('loadmore is a no-op once every row is loaded', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();

            table(element).dispatchEvent(new CustomEvent('loadmore'));
            await flushPromises();

            expect(getAssessmentPage).toHaveBeenCalledTimes(1);
        });

        it('shows the true total in the shared bar, not the loaded row count', async () => {
            getAssessmentPage.mockResolvedValue(page([row()], { totalCount: 137 }));
            const element = mount();
            await flushPromises();

            expect(bar(element).resultCount).toBe(137);
            expect(bar(element).resultLabel).toBe('assessments');
        });

        it('discloses a capped total as "10,000+"', async () => {
            getAssessmentPage.mockResolvedValue(page([row()], { totalCount: 10000, totalIsCapped: true }));
            const element = mount();
            await flushPromises();

            expect(element.shadowRoot.querySelector('.ov-count').textContent).toBe('10,000+ assessments');
            expect(bar(element).resultCount).toBeUndefined();
        });

        it('shows the true-empty state (no filters) with request-grain copy', async () => {
            getAssessmentPage.mockResolvedValue(emptyPage());
            const element = mount();
            await flushPromises();

            expect(table(element)).toBeNull();
            const empty = element.shadowRoot.querySelector('.ov-empty');
            expect(empty.textContent).toContain('No assessment submissions yet');
            expect(empty.textContent).not.toContain('No draft or approved readouts');
            expect(element.shadowRoot.querySelector('.ov-empty--filtered')).toBeNull();
        });

        it('shows a distinct filtered-empty state with Clear all when filters match nothing', async () => {
            getAssessmentPage.mockResolvedValue(emptyPage());
            const element = mount();
            CurrentPageReference.emit({ state: { c__astatus: 'completed' } });
            await flushPromises();

            const empty = element.shadowRoot.querySelector('.ov-empty--filtered');
            expect(empty).not.toBeNull();
            expect(empty.textContent).toContain('No assessments match these filters');
            expect(element.shadowRoot.textContent).not.toContain('No assessment submissions yet');

            empty.querySelector('lightning-button').click();
            await flushPromises();
            expect(lastQuery().status).toEqual([]);
            expect(navigateSpy).toHaveBeenCalled();
        });

        it('surfaces an Apex error instead of failing silently', async () => {
            getAssessmentPage.mockRejectedValue({ body: { message: 'boom' } });
            const element = mount();
            await flushPromises();

            expect(element.shadowRoot.querySelector('.ov-err').textContent).toContain('boom');
        });

        it('ignores a stale response that resolves after a newer request', async () => {
            let resolveFirst;
            getAssessmentPage.mockImplementationOnce(
                () => new Promise((resolve) => { resolveFirst = resolve; })
            );
            const element = mount();
            getAssessmentPage.mockResolvedValueOnce(page([row({ name: 'AR-NEW' })]));
            element.shadowRoot.querySelector('lightning-button-icon').click();
            await flushPromises();
            resolveFirst(page([row({ name: 'AR-STALE' })]));
            await flushPromises();

            expect(table(element).data.map((r) => r.name)).toEqual(['AR-NEW']);
        });
    });

    // docs/agent-artifacts/header-bar-consistency-assessment.md: this page
    // must use the same shared c-gtm-page-header component the rest of the
    // app uses, with Refresh in its actions slot.
    it('renders the shared c-gtm-page-header with the correct props, and Refresh works from its actions slot', async () => {
        getAssessmentPage.mockResolvedValue(emptyPage());
        const element = mount();
        await flushPromises();

        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header).not.toBeNull();
        expect(header.iconName).toBe('standard:report');
        expect(header.eyebrow).toBe('Submissions');
        expect(header.title).toBe('Find an assessment');

        const refreshButton = element.shadowRoot.querySelector('lightning-button-icon[slot="actions"]');
        expect(refreshButton).not.toBeNull();
    });

    // A rep clicks Refresh precisely because something just changed (a readout
    // approved or published in the editor). The refetch must reach the server:
    // getAssessmentPage is imperative and deliberately not cacheable.
    it('refetches from the server on Refresh and re-renders the new rows', async () => {
        getAssessmentPage.mockResolvedValueOnce(
            page([row(), row({ recordId: 'a0X000000000002AAA', name: 'AR-0050' })])
        );
        const element = mount();
        await flushPromises();
        expect(table(element).data).toHaveLength(2);

        getAssessmentPage.mockResolvedValue(page([row({ readoutStatus: 'Approved' })]));
        element.shadowRoot.querySelector('lightning-button-icon').click();
        await flushPromises();

        expect(getAssessmentPage).toHaveBeenCalledTimes(2);
        expect(table(element).data).toHaveLength(1);
        expect(table(element).data[0].readoutLabel).toBe('Approved, not sent');
    });

    // ------------------------------------------------------------- open row

    describe('opening an assessment (the AR-#### button cell)', () => {
        it('renders gtmReadoutWorkspace inline wired to the row ids and hides the table', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();

            openFirstRow(element);
            await flushPromises();

            expect(table(element)).toBeNull();
            expect(bar(element)).toBeNull();
            const workspace = element.shadowRoot.querySelector('c-gtm-readout-workspace');
            expect(workspace).not.toBeNull();
            expect(workspace.assessmentRequestId).toBe(REQ_ID);
            expect(workspace.readoutId).toBe('a01000000000001AAA');
            expect(workspace.offeringKey).toBe('migration-accelerator');
        });

        it('opens with a BLANK readoutId when the request has no readout yet', async () => {
            getAssessmentPage.mockResolvedValue(page([row({ readoutId: null, readoutStatus: null })]));
            const element = mount();
            await flushPromises();

            openFirstRow(element);
            await flushPromises();

            const workspace = element.shadowRoot.querySelector('c-gtm-readout-workspace');
            expect(workspace.assessmentRequestId).toBe(REQ_ID);
            expect(workspace.readoutId).toBe('');
            expect(new URL(window.location.href).searchParams.get('c__readoutId')).toBeNull();
        });

        // Regression check for the offering-key wiring gap (issue found in
        // live QA of PR #179): a blank offeringKey silently breaks the Preview tab.
        it('passes an empty offeringKey through cleanly when the row has none', async () => {
            getAssessmentPage.mockResolvedValue(page([row({ offeringKey: null })]));
            const element = mount();
            await flushPromises();

            openFirstRow(element);
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-gtm-readout-workspace').offeringKey).toBe('');
        });

        it('ignores row actions other than "open"', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();

            const t = table(element);
            t.dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'other' }, row: t.data[0] } }));
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-gtm-readout-workspace')).toBeNull();
        });

        it('returns to the table (rows retained) when gtmReadoutWorkspace fires "back"', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();

            openFirstRow(element);
            await flushPromises();
            element.shadowRoot.querySelector('c-gtm-readout-workspace').dispatchEvent(new CustomEvent('back'));
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-gtm-readout-workspace')).toBeNull();
            expect(table(element).data).toHaveLength(1);
        });
    });

    // Bug fix: selection state used to live only in @track fields, so a
    // browser refresh while viewing the workspace bounced a rep back to the
    // list. It is mirrored onto the URL (history.replaceState) and restored
    // from CurrentPageReference.
    describe('URL state persistence (existing params unaffected)', () => {
        it('writes the selection to the URL when an assessment is opened', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();

            openFirstRow(element);
            await flushPromises();

            const url = new URL(window.location.href);
            expect(url.searchParams.get('c__assessmentRequestId')).toBe(REQ_ID);
            expect(url.searchParams.get('c__readoutId')).toBe('a01000000000001AAA');
            expect(url.searchParams.get('c__offeringKey')).toBe('migration-accelerator');
        });

        it('clears the selection URL state when "back" is fired', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();

            openFirstRow(element);
            await flushPromises();
            element.shadowRoot.querySelector('c-gtm-readout-workspace').dispatchEvent(new CustomEvent('back'));
            await flushPromises();

            const url = new URL(window.location.href);
            expect(url.searchParams.get('c__assessmentRequestId')).toBeNull();
            expect(url.searchParams.get('c__readoutId')).toBeNull();
            expect(url.searchParams.get('c__offeringKey')).toBeNull();
        });

        it('writeSelectionToUrl leaves filter params in the URL untouched', async () => {
            window.history.replaceState({}, '', '/?c__astatus=new&c__atier=fast-track');
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();

            openFirstRow(element);
            await flushPromises();
            let url = new URL(window.location.href);
            expect(url.searchParams.get('c__astatus')).toBe('new');
            expect(url.searchParams.get('c__atier')).toBe('fast-track');
            expect(url.searchParams.get('c__assessmentRequestId')).toBe(REQ_ID);

            element.shadowRoot.querySelector('c-gtm-readout-workspace').dispatchEvent(new CustomEvent('back'));
            await flushPromises();
            url = new URL(window.location.href);
            expect(url.searchParams.get('c__astatus')).toBe('new');
            expect(url.searchParams.get('c__assessmentRequestId')).toBeNull();
        });

        it('restores the workspace directly from CurrentPageReference state (simulating a refresh)', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({
                state: {
                    c__assessmentRequestId: REQ_ID,
                    c__readoutId: 'a01000000000001AAA',
                    c__offeringKey: 'migration-accelerator'
                }
            });
            await flushPromises();

            const workspace = element.shadowRoot.querySelector('c-gtm-readout-workspace');
            expect(workspace).not.toBeNull();
            expect(workspace.assessmentRequestId).toBe(REQ_ID);
            expect(workspace.readoutId).toBe('a01000000000001AAA');
            expect(workspace.offeringKey).toBe('migration-accelerator');
            expect(table(element)).toBeNull();
        });

        // issue-102-1-engagement-links-landing, D7 + acceptance criterion 4:
        // c-gtm-assessment-detail's standalone "Open the readout" forward
        // action navigates here with c__focusReadoutTab riding alongside
        // c__readoutId -- this must thread through to gtmReadoutWorkspace's
        // initial-tab so THAT mount lands on Readout, not Assessment.
        describe('focus-readout rider (c__focusReadoutTab)', () => {
            it('threads a deep link\'s c__focusReadoutTab through to gtmReadoutWorkspace as initial-tab="readout"', async () => {
                getAssessmentPage.mockResolvedValue(page([row()]));
                const element = mount();
                CurrentPageReference.emit({
                    state: {
                        c__assessmentRequestId: REQ_ID,
                        c__readoutId: 'a01000000000001AAA',
                        c__offeringKey: 'migration-accelerator',
                        c__focusReadoutTab: '1'
                    }
                });
                await flushPromises();

                const workspace = element.shadowRoot.querySelector('c-gtm-readout-workspace');
                expect(workspace.initialTab).toBe('readout');
            });

            it('leaves initial-tab blank (refinement #3\'s own default) when no c__focusReadoutTab rider is present', async () => {
                getAssessmentPage.mockResolvedValue(page([row()]));
                const element = mount();
                CurrentPageReference.emit({
                    state: {
                        c__assessmentRequestId: REQ_ID,
                        c__readoutId: 'a01000000000001AAA',
                        c__offeringKey: 'migration-accelerator'
                    }
                });
                await flushPromises();

                const workspace = element.shadowRoot.querySelector('c-gtm-readout-workspace');
                expect(workspace.initialTab).toBe('');
            });

            it('a plain row click never inherits a stale c__focusReadoutTab left in the URL from an earlier deep link', async () => {
                getAssessmentPage.mockResolvedValue(page([row()]));
                const element = mount();
                // Simulate having arrived here once already via the
                // focus-readout deep link (as the previous test does)...
                CurrentPageReference.emit({
                    state: {
                        c__assessmentRequestId: REQ_ID,
                        c__readoutId: 'a01000000000001AAA',
                        c__focusReadoutTab: '1'
                    }
                });
                await flushPromises();
                expect(element.shadowRoot.querySelector('c-gtm-readout-workspace').initialTab).toBe('readout');

                // ...then back out to the table and click a row normally --
                // that is exactly the "card" origin refinement #3 keeps
                // defaulting to Assessment; it must not inherit the earlier
                // focus intent.
                element.shadowRoot.querySelector('c-gtm-readout-workspace').dispatchEvent(new CustomEvent('back'));
                await flushPromises();
                openFirstRow(element);
                await flushPromises();

                const workspace = element.shadowRoot.querySelector('c-gtm-readout-workspace');
                expect(workspace.initialTab).toBe('');
                const url = new URL(window.location.href);
                expect(url.searchParams.get('c__focusReadoutTab')).toBeNull();
            });
        });

        it('a deep link with a selection AND filters restores both', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({
                state: { c__assessmentRequestId: REQ_ID, c__astatus: 'new' }
            });
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-gtm-readout-workspace').assessmentRequestId).toBe(REQ_ID);
            expect(lastQuery().status).toEqual(['new']);
        });
    });

    // ---------------------------------------------------------------- filters

    describe('shared filter bar wiring', () => {
        it('passes the assessments filter config to c-gtm-filter-bar', async () => {
            getAssessmentPage.mockResolvedValue(page([row()], { offeringOptions: ['migration-accelerator', 'other-offer'] }));
            const element = mount();
            await flushPromises();

            const filters = bar(element).filters;
            expect(filters.map((f) => [f.key, f.param, f.type])).toEqual([
                ['preset', 'c__apreset', 'toggle'],
                ['status', 'c__astatus', 'chips'],
                ['tier', 'c__atier', 'chips'],
                ['readout', 'c__areadout', 'chips'],
                ['range', 'c__arange', 'date-range'],
                ['offering', 'c__aoffering', 'chips'],
                ['account', 'c__aacct', 'chips'],
                ['contact', 'c__acontact', 'chips']
            ]);
            const byKey = Object.fromEntries(filters.map((f) => [f.key, f]));
            expect(byKey.preset.label).toBe('Ready to book');
            expect(byKey.status.options.map((o) => o.value)).toEqual([
                'new', 'contacted', 'scheduled', 'completed', 'no-show'
            ]);
            expect(byKey.tier.options.map((o) => o.value)).toEqual([
                'fast-track', 'accelerator-ready', 'prep-required', 'discovery-first'
            ]);
            expect(byKey.readout.options.map((o) => o.value)).toEqual([
                'none', 'draft', 'pending', 'approved-unsent', 'approved-sent', 'published'
            ]);
            // Multi within a dimension.
            expect(byKey.status.multi && byKey.tier.multi && byKey.readout.multi && byKey.offering.multi).toBe(true);
            // Offering options come from the server response, not a hard-coded list.
            expect(byKey.offering.options.map((o) => o.value)).toEqual(['migration-accelerator', 'other-offer']);
        });

        it('config validates against the shared helper (no reserved or duplicate params)', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();

            const { validateFilters } = require('c/gtmFilterUrlState');
            expect(validateFilters(bar(element).filters)).toEqual([]);
        });

        it('a filterchange refetches from offset 0 with the server-shaped query and writes the URL via Navigate(replace)', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            const ref = { type: 'standard__navItemPage', attributes: { apiName: 'GTM_Assessments' }, state: {} };
            CurrentPageReference.emit(ref);
            await flushPromises();
            getAssessmentPage.mockClear();

            bar(element).dispatchEvent(
                new CustomEvent('filterchange', { detail: { key: 'status', value: ['new', 'contacted'] } })
            );
            await flushPromises();

            expect(lastQuery().status).toEqual(['new', 'contacted']);
            expect(lastQuery().offset).toBe(0);
            expect(bar(element).values).toEqual({ status: ['new', 'contacted'] });
            expect(navigateSpy).toHaveBeenCalledTimes(1);
            const [pageRef, replace] = navigateSpy.mock.calls[0];
            expect(replace).toBe(true);
            expect(pageRef.type).toBe('standard__navItemPage');
            expect(pageRef.attributes).toEqual({ apiName: 'GTM_Assessments' });
            expect(pageRef.state.c__astatus).toBe('new,contacted');
        });

        it('sends the ready-to-book preset as a key and never the expanded values', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: {} });
            await flushPromises();

            bar(element).dispatchEvent(new CustomEvent('filterchange', { detail: { key: 'preset', value: true } }));
            await flushPromises();

            expect(lastQuery().preset).toBe('ready-to-book');
            expect(lastQuery().status).toEqual([]);
            expect(lastQuery().tier).toEqual([]);
            expect(navigateSpy.mock.calls[0][0].state.c__apreset).toBe('true');
        });

        it('passes plain (non-proxy) arrays to Apex even when filter values are Proxy-wrapped', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: {} });
            await flushPromises();
            getAssessmentPage.mockClear();
            getAssessmentFilterOptions.mockClear();

            bar(element).dispatchEvent(
                new CustomEvent('filterchange', {
                    detail: { key: 'status', value: new Proxy(['completed'], {}) }
                })
            );
            bar(element).dispatchEvent(
                new CustomEvent('filterchange', {
                    detail: { key: 'account', value: new Proxy(['001000000000001AAA'], {}) }
                })
            );
            await flushPromises();

            const arg = getAssessmentPage.mock.calls[getAssessmentPage.mock.calls.length - 1][0];
            expect(Array.isArray(arg.query.status)).toBe(true);
            expect(arg.query.status).toEqual(['completed']);
            expect(arg.query.accountIds).toEqual(['001000000000001AAA']);
            expect(JSON.stringify(arg)).toBe(JSON.stringify(JSON.parse(JSON.stringify(arg))));
            getAssessmentFilterOptions.mock.calls.forEach(([o]) => {
                expect(Array.isArray(o.includeIds)).toBe(true);
                expect(o.includeIds.every((x) => typeof x === 'string')).toBe(true);
            });
        });

        it('sends date ranges as a preset token or FROM..TO', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: {} });
            await flushPromises();

            bar(element).dispatchEvent(new CustomEvent('filterchange', { detail: { key: 'range', value: '30' } }));
            await flushPromises();
            expect(lastQuery().range).toBe('30');

            bar(element).dispatchEvent(
                new CustomEvent('filterchange', { detail: { key: 'range', value: { from: '2026-01-01', to: '2026-01-31' } } })
            );
            await flushPromises();
            expect(lastQuery().range).toBe('2026-01-01..2026-01-31');
            expect(navigateSpy.mock.calls[1][0].state.c__arange).toBe('2026-01-01..2026-01-31');
        });

        it('an emptied filter is removed from the query and the URL', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__astatus: 'new', c__atier: 'fast-track' } });
            await flushPromises();

            bar(element).dispatchEvent(new CustomEvent('filterchange', { detail: { key: 'status', value: [] } }));
            await flushPromises();

            expect(lastQuery().status).toEqual([]);
            expect(lastQuery().tier).toEqual(['fast-track']);
            const state = navigateSpy.mock.calls[0][0].state;
            expect(state.c__astatus).toBeUndefined();
            expect(state.c__atier).toBe('fast-track');
        });

        it('Clear all drops every filter param, keeps every other param, and refetches unfiltered', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({
                type: 'standard__navItemPage',
                attributes: {},
                state: { c__astatus: 'new', c__apreset: 'true', c__arange: '7', c__unrelated: '001000000000001AAA' }
            });
            await flushPromises();

            bar(element).dispatchEvent(new CustomEvent('clear'));
            await flushPromises();

            expect(lastQuery().status).toEqual([]);
            expect(lastQuery().preset).toBeNull();
            expect(lastQuery().range).toBeNull();
            const state = navigateSpy.mock.calls[0][0].state;
            expect(Object.keys(state).filter((k) => /^c__a(status|tier|readout|range|offering|preset)$/.test(k))).toEqual([]);
            expect(state.c__unrelated).toBe('001000000000001AAA');
            expect(bar(element).values).toEqual({});
        });

        it('a filter write preserves the component\'s own params and never uses history.replaceState', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({
                type: 'standard__navItemPage',
                attributes: {},
                state: { c__repDirectId: 'a0X000000000999AAA' }
            });
            await flushPromises();
            const replaceSpy = jest.spyOn(window.history, 'replaceState');

            bar(element).dispatchEvent(new CustomEvent('filterchange', { detail: { key: 'status', value: ['new'] } }));
            await flushPromises();

            const state = navigateSpy.mock.calls[0][0].state;
            expect(state.c__repDirectId).toBe('a0X000000000999AAA');
            expect(state.c__astatus).toBe('new');
            expect(replaceSpy).not.toHaveBeenCalled();
            replaceSpy.mockRestore();
        });

        it('does not resurrect a selection param the component already cleared (stale wired state)', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            // Deep link opened the workspace...
            CurrentPageReference.emit({
                type: 'standard__navItemPage',
                attributes: {},
                state: { c__assessmentRequestId: REQ_ID }
            });
            await flushPromises();
            // ...then the rep pressed Back (replaceState only; the wired state is stale).
            element.shadowRoot.querySelector('c-gtm-readout-workspace').dispatchEvent(new CustomEvent('back'));
            await flushPromises();

            bar(element).dispatchEvent(new CustomEvent('filterchange', { detail: { key: 'status', value: ['new'] } }));
            await flushPromises();

            const state = navigateSpy.mock.calls[0][0].state;
            expect(state.c__assessmentRequestId).toBeUndefined();
            expect(state.c__astatus).toBe('new');
        });
    });

    describe('restoring filters from CurrentPageReference', () => {
        it('restores every dimension into the bar and the query (before any c__assessmentRequestId)', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({
                state: {
                    c__astatus: 'new,contacted',
                    c__atier: 'fast-track',
                    c__areadout: 'none,pending',
                    c__arange: '30',
                    c__aoffering: 'migration-accelerator',
                    c__apreset: 'true'
                }
            });
            await flushPromises();

            expect(bar(element).values).toEqual({
                status: ['new', 'contacted'],
                tier: ['fast-track'],
                readout: ['none', 'pending'],
                range: '30',
                offering: ['migration-accelerator'],
                preset: true
            });
            const q = lastQuery();
            expect(q.status).toEqual(['new', 'contacted']);
            expect(q.tier).toEqual(['fast-track']);
            expect(q.readout).toEqual(['none', 'pending']);
            expect(q.range).toBe('30');
            expect(q.offering).toEqual(['migration-accelerator']);
            expect(q.preset).toBe('ready-to-book');
            expect(element.shadowRoot.querySelector('c-gtm-readout-workspace')).toBeNull();
        });

        it('keeps an offering from the URL that the server has not listed yet', async () => {
            getAssessmentPage.mockResolvedValue(page([row()], { offeringOptions: [] }));
            const element = mount();
            CurrentPageReference.emit({ state: { c__aoffering: 'not-listed-yet' } });
            await flushPromises();

            expect(bar(element).values.offering).toEqual(['not-listed-yet']);
            expect(lastQuery().offering).toEqual(['not-listed-yet']);
        });

        it('restores custom ranges', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({ state: { c__arange: '2026-01-01..2026-01-31' } });
            await flushPromises();

            expect(bar(element).values.range).toEqual({ from: '2026-01-01', to: '2026-01-31' });
            expect(lastQuery().range).toBe('2026-01-01..2026-01-31');
        });

        it('ignores invalid and unknown values instead of throwing', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({
                state: {
                    c__astatus: 'bogus',
                    c__atier: 'nope,fast-track',
                    c__areadout: 'zzz',
                    c__arange: '45',
                    c__apreset: 'maybe'
                }
            });
            await flushPromises();

            expect(bar(element).values).toEqual({ tier: ['fast-track'] });
        });

        it('a re-fired page reference with unchanged filters does not refetch', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            mount();
            CurrentPageReference.emit({ state: { c__astatus: 'new' } });
            await flushPromises();
            const calls = getAssessmentPage.mock.calls.length;

            CurrentPageReference.emit({ state: { c__astatus: 'new', c__unrelated: 'x' } });
            CurrentPageReference.emit({ state: { c__astatus: 'new' } });
            await flushPromises();

            expect(getAssessmentPage.mock.calls.length).toBe(calls);
        });

        it('with no filter params behaves like the plain tab: no filters, no filtered-empty state', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({ state: {} });
            await flushPromises();

            expect(getAssessmentPage).toHaveBeenCalledTimes(1);
            expect(bar(element).values).toEqual({});
        });

        it('reads filter params from the location on first load, so a deep link is not fetched unfiltered first', async () => {
            window.history.replaceState({}, '', '/?c__astatus=completed');
            getAssessmentPage.mockResolvedValue(page([row()]));
            mount();
            await flushPromises();

            expect(getAssessmentPage).toHaveBeenCalledTimes(1);
            expect(lastQuery().status).toEqual(['completed']);
        });
    });

    // issue-gtm-assessments-account-contact-trail: the trail is unchanged by
    // the table; filter params are preserved in the URL and ignored there.
    describe('Account and Contact filters (release 3; replaces the browse-mode trail)', () => {
        const ACCT = '001000000000001AAA';
        const ACCT2 = '001000000000002AAA';
        const CON = '003000000000001AAA';
        const optionsFor = (kind) => getAssessmentFilterOptions.mock.calls.filter((c) => c[0].kind === kind).map((c) => c[0]);
        const byKey = (element, key) => bar(element).filters.find((f) => f.key === key);

        beforeEach(() => {
            getAssessmentFilterOptions.mockImplementation(({ kind }) =>
                Promise.resolve(
                    kind === 'account'
                        ? [{ value: ACCT, label: 'Acme Co' }, { value: ACCT2, label: 'Beta Corp' }]
                        : [{ value: CON, label: 'Jane Prospect', sublabel: 'Acme Co' }]
                )
            );
        });

        it('has no scope toggle, no trail, and no browse-mode subtitle', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();
            expect(element.shadowRoot.querySelector('.ov-mode-toggle')).toBeNull();
            expect(element.shadowRoot.querySelector('.ov-toggle-btn')).toBeNull();
            expect(element.shadowRoot.querySelector('c-gtm-readout-account-finder')).toBeNull();
            expect(bar(element)).not.toBeNull();
            expect(element.shadowRoot.querySelector('c-gtm-page-header').meta).toBeFalsy();
        });

        it('loads server options for both kinds on start and feeds them to the bar as searchable server filters', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();
            expect(optionsFor('account')[0]).toEqual({ kind: 'account', searchTerm: '', includeIds: [] });
            expect(optionsFor('contact')).toHaveLength(1);
            const a = byKey(element, 'account');
            expect(a.serverSearch).toBe(true);
            expect(a.options).toEqual([{ value: ACCT, label: 'Acme Co' }, { value: ACCT2, label: 'Beta Corp' }]);
            expect(byKey(element, 'contact').options).toEqual([{ value: CON, label: 'Jane Prospect (Acme Co)' }]);
        });

        it('a pick refetches with accountIds/contactIds and writes c__aacct / c__acontact', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: {} });
            await flushPromises();
            bar(element).dispatchEvent(new CustomEvent('filterchange', { detail: { key: 'account', value: [ACCT, ACCT2] } }));
            await flushPromises();
            expect(lastQuery().accountIds).toEqual([ACCT, ACCT2]);
            expect(lastQuery().contactIds).toEqual([]);
            expect(navigateSpy.mock.calls[0][0].state.c__aacct).toBe(`${ACCT},${ACCT2}`);
            bar(element).dispatchEvent(new CustomEvent('filterchange', { detail: { key: 'contact', value: [CON] } }));
            await flushPromises();
            expect(lastQuery().contactIds).toEqual([CON]);
            expect(lastQuery().accountIds).toEqual([ACCT, ACCT2]);
        });

        it('restores deep-link ids: the filter value is kept, and the ids go up in includeIds to be labelled', async () => {
            getAssessmentFilterOptions.mockImplementation(({ kind, includeIds }) =>
                Promise.resolve(kind === 'account' ? includeIds.map((id) => ({ value: id, label: 'Restored Co' })) : []));
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({ state: { c__aacct: ACCT } });
            await flushPromises();
            expect(bar(element).values).toEqual({ account: [ACCT] });
            expect(lastQuery().accountIds).toEqual([ACCT]);
            expect(optionsFor('account').some((c) => c.includeIds.includes(ACCT))).toBe(true);
            expect(byKey(element, 'account').options[0]).toEqual({ value: ACCT, label: 'Restored Co' });
        });

        it('drops a restored id the server does not return (deleted record) and reloads unfiltered', async () => {
            getAssessmentFilterOptions.mockResolvedValue([]);
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            CurrentPageReference.emit({ state: { c__acontact: CON } });
            await flushPromises();
            expect(bar(element).values).toEqual({});
            expect(lastQuery().contactIds).toEqual([]);
            expect(table(element).data).toHaveLength(1);
        });

        describe('debounced server search', () => {
            beforeEach(() => jest.useFakeTimers());
            afterEach(() => jest.useRealTimers());

            it('waits for a pause in typing, then fetches once with the last term; selected ids ride along', async () => {
                getAssessmentPage.mockResolvedValue(page([row()]));
                const element = mount();
                CurrentPageReference.emit({ state: { c__aacct: ACCT2 } });
                await Promise.resolve();
                const before = optionsFor('account').length;
                const type = (value) => bar(element).dispatchEvent(new CustomEvent('filtersearch', { detail: { key: 'account', value } }));
                type('ac');
                type('acm');
                jest.advanceTimersByTime(299);
                expect(optionsFor('account')).toHaveLength(before);
                jest.advanceTimersByTime(2);
                const calls = optionsFor('account');
                expect(calls).toHaveLength(before + 1);
                expect(calls[calls.length - 1].searchTerm).toBe('acm');
                expect(calls[calls.length - 1].includeIds).toContain(ACCT2);
            });

            it('ignores search events for keys that are not party filters', async () => {
                getAssessmentPage.mockResolvedValue(page([row()]));
                const element = mount();
                await Promise.resolve();
                const before = getAssessmentFilterOptions.mock.calls.length;
                bar(element).dispatchEvent(new CustomEvent('filtersearch', { detail: { key: 'status', value: 'x' } }));
                jest.advanceTimersByTime(1000);
                expect(getAssessmentFilterOptions.mock.calls.length).toBe(before);
            });
        });

        it('a failing options call leaves the bar working', async () => {
            getAssessmentFilterOptions.mockRejectedValue(new Error('boom'));
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();
            expect(bar(element)).not.toBeNull();
            expect(byKey(element, 'account').options).toEqual([]);
        });

        describe('legacy deep links', () => {
            it('c__browseMode=account is ignored: the plain table shows (no trail) and the param is dropped on rewrite', async () => {
                getAssessmentPage.mockResolvedValue(page([row()]));
                const element = mount();
                CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__browseMode: 'account' } });
                await flushPromises();
                expect(table(element)).not.toBeNull();
                expect(element.shadowRoot.querySelector('c-gtm-readout-account-finder')).toBeNull();
                const states = navigateSpy.mock.calls.map((c) => c[0].state);
                expect(states.length).toBeGreaterThan(0);
                states.forEach((st) => expect(st.c__browseMode).toBeUndefined());
            });

            it('c__rafAccountId / c__rafContactId map to the Account / Contact filters and are rewritten to c__aacct / c__acontact', async () => {
                getAssessmentPage.mockResolvedValue(page([row()]));
                const element = mount();
                CurrentPageReference.emit({
                    type: 'standard__navItemPage',
                    attributes: {},
                    state: { c__browseMode: 'account', c__rafAccountId: ACCT, c__rafContactId: CON, c__astatus: 'new' }
                });
                await flushPromises();
                expect(bar(element).values).toEqual({ status: ['new'], account: [ACCT], contact: [CON] });
                expect(lastQuery().accountIds).toEqual([ACCT]);
                expect(lastQuery().contactIds).toEqual([CON]);
                const st = navigateSpy.mock.calls[navigateSpy.mock.calls.length - 1][0].state;
                expect([st.c__aacct, st.c__acontact, st.c__astatus]).toEqual([ACCT, CON, 'new']);
                expect(st.c__rafAccountId).toBeUndefined();
                expect(st.c__rafContactId).toBeUndefined();
                expect(st.c__browseMode).toBeUndefined();
            });

            it('an explicit c__aacct wins over the legacy c__rafAccountId', async () => {
                getAssessmentPage.mockResolvedValue(page([row()]));
                const element = mount();
                CurrentPageReference.emit({ state: { c__aacct: ACCT2, c__rafAccountId: ACCT } });
                await flushPromises();
                expect(bar(element).values).toEqual({ account: [ACCT2] });
            });

            it('opening a row still works and never writes c__browseMode', async () => {
                getAssessmentPage.mockResolvedValue(page([row()]));
                const element = mount();
                CurrentPageReference.emit({ state: { c__aacct: ACCT } });
                await flushPromises();
                openFirstRow(element);
                await flushPromises();
                expect(element.shadowRoot.querySelector('c-gtm-readout-workspace')).not.toBeNull();
                expect(new URL(window.location.href).searchParams.get('c__browseMode')).toBeNull();
            });
        });
    });

    // QA follow-up (TEST_FAILURES.log,
    // rep-initiated-assessment-no-page-2-share-and-continue): gtmOverview's
    // post-create hand-off now deep-links here with c__repDirectId, and this
    // tab must open the questionnaire in a modal rather than requiring a
    // separate trip to the raw GTM_Saved_Configuration__c record page.
    describe('Rep-Direct entry point (post-create modal)', () => {
        it('opens the modal, mounting c-gtm-rep-direct-share, when c__repDirectId arrives via CurrentPageReference', async () => {
            getAssessmentPage.mockResolvedValue(emptyPage());
            const element = createElement('c-gtm-readouts-overview', { is: GtmReadoutsOverview });
            document.body.appendChild(element);
            CurrentPageReference.emit({ state: { c__repDirectId: 'a0X000000000999AAA' } });
            await flushPromises();

            expect(element.shadowRoot.querySelector('.slds-modal')).not.toBeNull();
            const share = element.shadowRoot.querySelector('c-gtm-rep-direct-share');
            expect(share).not.toBeNull();
            expect(share.recordId).toBe('a0X000000000999AAA');

            getRecordWireAdapter.emit({
                fields: {
                    Presentation_Stage__c: { value: 'Rep_Direct' },
                    Offering__c: { value: 'migration-accelerator' },
                    Generated_URL__c: { value: null }
                }
            });
            await flushPromises();

            expect(share.shadowRoot.querySelector('[data-id="prefill-button"]')).not.toBeNull();
        });

        it('does not open the modal, and does not render c-gtm-rep-direct-share at all, on a normal load with no c__repDirectId', async () => {
            getAssessmentPage.mockResolvedValue(emptyPage());
            const element = createElement('c-gtm-readouts-overview', { is: GtmReadoutsOverview });
            document.body.appendChild(element);
            await flushPromises();

            expect(element.shadowRoot.querySelector('.slds-modal')).toBeNull();
            expect(element.shadowRoot.querySelector('c-gtm-rep-direct-share')).toBeNull();
        });

        it('closes the modal and clears the URL state when Done/close is clicked', async () => {
            getAssessmentPage.mockResolvedValue(emptyPage());
            const element = createElement('c-gtm-readouts-overview', { is: GtmReadoutsOverview });
            document.body.appendChild(element);
            CurrentPageReference.emit({ state: { c__repDirectId: 'a0X000000000999AAA' } });
            await flushPromises();

            expect(element.shadowRoot.querySelector('.slds-modal')).not.toBeNull();

            element.shadowRoot.querySelector('.slds-modal__footer lightning-button').click();
            await flushPromises();

            expect(element.shadowRoot.querySelector('.slds-modal')).toBeNull();
            expect(element.shadowRoot.querySelector('c-gtm-rep-direct-share')).toBeNull();

            const url = new URL(window.location.href);
            expect(url.searchParams.get('c__repDirectId')).toBeNull();
        });
    });

    describe('row open and record links', () => {
        const fire = (element, name, r) => {
            const t = table(element);
            t.dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name }, row: r || t.data[0] } }));
        };

        it('ends with a right-hand row-action column whose menu leads with Open assessment', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();
            const cols = table(element).columns;
            const last = cols[cols.length - 1];
            expect(last.type).toBe('action');
            const items = await new Promise((res) => last.typeAttributes.rowActions(table(element).data[0], res));
            expect(items.map((i) => [i.name, i.label, !!i.disabled])).toEqual([
                ['open', 'Open assessment', false],
                ['openContact', 'Open contact', false],
                ['openAccount', 'Open account', false]
            ]);
        });

        it('disables Open contact / Open account when the row has no such id', async () => {
            getAssessmentPage.mockResolvedValue(page([row({ contactId: null, accountId: null })]));
            const element = mount();
            await flushPromises();
            const cols = table(element).columns;
            const items = await new Promise((res) =>
                cols[cols.length - 1].typeAttributes.rowActions(table(element).data[0], res)
            );
            expect(items[1].disabled).toBe(true);
            expect(items[2].disabled).toBe(true);
        });

        it('the menu Open action opens the same workspace as the Assessment cell (request, readout, offering)', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();
            fire(element, 'open');
            await flushPromises();
            const url = new URL(window.location.href);
            expect(url.searchParams.get('c__assessmentRequestId')).toBe(REQ_ID);
            expect(url.searchParams.get('c__readoutId')).toBe('a01000000000001AAA');
        });

        it('Contact cell navigates to the Contact record page with the contact id (not account/request)', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();
            navigateSpy.mockClear();
            fire(element, 'openContact');
            expect(navigateSpy).toHaveBeenCalledTimes(1);
            expect(navigateSpy.mock.calls[0][0]).toEqual({
                type: 'standard__recordPage',
                attributes: { recordId: '003000000000001AAA', objectApiName: 'Contact', actionName: 'view' }
            });
        });

        it('Company cell navigates to the Account record page with the account id (not contact/request)', async () => {
            getAssessmentPage.mockResolvedValue(page([row()]));
            const element = mount();
            await flushPromises();
            navigateSpy.mockClear();
            fire(element, 'openAccount');
            expect(navigateSpy.mock.calls[0][0]).toEqual({
                type: 'standard__recordPage',
                attributes: { recordId: '001000000000001AAA', objectApiName: 'Account', actionName: 'view' }
            });
        });

        it('does not navigate when the id is missing (no dead link)', async () => {
            getAssessmentPage.mockResolvedValue(page([row({ contactId: null, accountId: null })]));
            const element = mount();
            await flushPromises();
            navigateSpy.mockClear();
            fire(element, 'openContact');
            fire(element, 'openAccount');
            expect(navigateSpy).not.toHaveBeenCalled();
        });
    });
});

/**
 * Issue pages-assessments-loading-state — a page-level lightning-spinner for
 * first paint only (isLoading with no rows loaded yet), since the still-empty
 * lightning-datatable's own is-loading attribute is easy to miss before any
 * row shell exists. The datatable's own is-loading/enable-infinite-loading
 * pagination behavior for subsequent "load more" fetches is untouched.
 */
describe('c-gtm-readouts-overview: initial page-level loading spinner (issue pages-assessments-loading-state)', () => {
    beforeEach(() => {
        getAssessmentFilterOptions.mockResolvedValue([]);
        window.history.replaceState({}, '', '/');
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        window.history.replaceState({}, '', '/');
    });

    function deferred() {
        let resolve;
        const promise = new Promise((r) => { resolve = r; });
        return { promise, resolve };
    }

    it('shows the page-level spinner on initial load, before getAssessmentPage settles', () => {
        const initial = deferred();
        getAssessmentPage.mockReturnValue(initial.promise);

        const element = mount();

        expect(element.shadowRoot.querySelector('lightning-spinner')).not.toBeNull();
    });

    it('hides the page-level spinner once rows arrive from the initial load', async () => {
        const initial = deferred();
        getAssessmentPage.mockReturnValue(initial.promise);
        const element = mount();
        await flushPromises();
        expect(element.shadowRoot.querySelector('lightning-spinner')).not.toBeNull();

        initial.resolve(page([row()]));
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });

    it('hides the page-level spinner once the initial load settles even with zero rows', async () => {
        getAssessmentPage.mockResolvedValue(emptyPage());
        const element = mount();
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });

    it('does not reappear on a subsequent "load more" pagination fetch (isLoadingMore, not isLoading)', async () => {
        getAssessmentPage.mockResolvedValue(page([row()], { totalCount: 2 }));
        const element = mount();
        await flushPromises();
        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();

        const loadMore = deferred();
        getAssessmentPage.mockReturnValue(loadMore.promise);
        table(element).dispatchEvent(new CustomEvent('loadmore'));
        await flushPromises();

        // Rows already exist, so the page-level spinner must stay hidden;
        // the datatable's own is-loading attribute covers this instead.
        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
        expect(table(element).isLoading).toBe(true);

        loadMore.resolve(page([row(), row({ recordId: 'a0X000000000002AAA' })]));
        await flushPromises();
        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });
});
