import { createElement } from 'lwc';

const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](...args) {
                mockNavigate(...args);
            }
        };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin };
});

// D owns c/gtmSetupItem. A stub keeps this suite independent of it.
jest.mock('c/gtmSetupItem', () => require('./stubs/gtmSetupItemStub'), { virtual: true });

/* eslint-disable import/first, import/order */
import getChecklist from '@salesforce/apex/GtmSetupChecklistController.getChecklist';
import searchAssignableUsers from '@salesforce/apex/GtmSetupChecklistController.searchAssignableUsers';
import assignPermissionSet from '@salesforce/apex/GtmSetupActionController.assignPermissionSet';
import assignPermissionSetToMe from '@salesforce/apex/GtmSetupActionController.assignPermissionSetToMe';
import createFrameworkPage from '@salesforce/apex/GtmSetupActionController.createFrameworkPage';
import getStatuses from '@salesforce/apex/GtmScheduledJobsController.getStatuses';
import scheduleJob from '@salesforce/apex/GtmScheduledJobsController.scheduleJob';
import { starterFor } from 'c/gtmPageLayouts';
import GtmSetupChecklist from 'c/gtmSetupChecklist';
import { blankChecklist, allDoneChecklist, unknownRequiredChecklist, CATALOGUE } from './fixtures';
/* eslint-enable import/first, import/order */

jest.mock('@salesforce/apex/GtmSetupChecklistController.getChecklist', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSetupChecklistController.searchAssignableUsers', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSetupActionController.assignPermissionSet', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSetupActionController.assignPermissionSetToMe', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmSetupActionController.createFrameworkPage', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmScheduledJobsController.getStatuses', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmScheduledJobsController.scheduleJob', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mount(checklist = blankChecklist) {
    getChecklist.mockResolvedValue(checklist);
    const el = createElement('c-gtm-setup-checklist', { is: GtmSetupChecklist });
    document.body.appendChild(el);
    await flush();
    return el;
}

const rows = (el) => Array.from(el.shadowRoot.querySelectorAll('.setup-row'));
const groupEl = (el, tier) => el.shadowRoot.querySelector(`.setup-group[data-tier="${tier}"]`);
const rowEl = (el, key) => el.shadowRoot.querySelector(`.setup-row[data-key="${key}"] c-gtm-setup-item`);
const fire = (el, key, detail) => {
    rowEl(el, key).dispatchEvent(new CustomEvent('itemaction', { detail: { key, ...detail } }));
    return flush();
};
const withItem = (key, overrides) => ({
    ...blankChecklist,
    items: blankChecklist.items.map((i) => (i.key === key ? { ...i, ...overrides } : i))
});

describe('c-gtm-setup-checklist', () => {
    beforeEach(() => {
        jest.clearAllMocks();
        assignPermissionSetToMe.mockResolvedValue({ assigned: true });
        assignPermissionSet.mockResolvedValue({ assigned: true });
        createFrameworkPage.mockResolvedValue({ created: true });
        getStatuses.mockResolvedValue([]);
        scheduleJob.mockResolvedValue({});
        searchAssignableUsers.mockResolvedValue([]);
    });
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('renders the blank fixture without error and lists every catalogue key once', async () => {
        const el = await mount(blankChecklist);
        expect(el.shadowRoot.querySelector('.setup-error')).toBeNull();
        // Optional and info groups start collapsed, so expand them to count all.
        el.shadowRoot.querySelectorAll('.setup-toggle').forEach((b) => b.click());
        await flush();
        expect(rows(el).map((r) => r.dataset.key).sort()).toEqual(CATALOGUE.map((c) => c[0]).sort());
    });

    it('shows the header math, and the unknown suffix only when needed', async () => {
        let el = await mount(blankChecklist);
        expect(el.shadowRoot.querySelector('.setup-header').textContent).toBe('0 of 8 required steps done');
        document.body.removeChild(el);

        el = await mount(unknownRequiredChecklist);
        expect(el.shadowRoot.querySelector('.setup-header').textContent).toBe(
            '0 of 8 required steps done, 2 could not be verified'
        );
        document.body.removeChild(el);

        el = await mount(allDoneChecklist);
        expect(el.shadowRoot.querySelector('.setup-header').textContent).toBe('8 of 8 required steps done');
    });

    it('renders groups in tier order and passes each item to the row component', async () => {
        const el = await mount(blankChecklist);
        const tiers = Array.from(el.shadowRoot.querySelectorAll('.setup-group')).map((g) => g.dataset.tier);
        expect(tiers).toEqual(['REQUIRED', 'RECOMMENDED', 'OPTIONAL', 'INFO']);
        expect(rowEl(el, 'framework_pages').item.key).toBe('framework_pages');
        // content_access is a REQUIRED-tier helper row in the fixture.
        expect(groupEl(el, 'REQUIRED').querySelectorAll('.setup-row').length).toBe(9);
    });

    it('collapses optional and info groups and never counts them in the total', async () => {
        const el = await mount(blankChecklist);
        expect(groupEl(el, 'OPTIONAL').querySelectorAll('.setup-row').length).toBe(0);
        expect(groupEl(el, 'INFO').querySelectorAll('.setup-row').length).toBe(0);
        expect(groupEl(el, 'REQUIRED').querySelector('.setup-toggle')).toBeNull();
        groupEl(el, 'OPTIONAL').querySelector('.setup-toggle').click();
        await flush();
        expect(groupEl(el, 'OPTIONAL').querySelectorAll('.setup-row').length).toBe(6);
        expect(el.shadowRoot.querySelector('.setup-header').textContent).toContain('of 8 required');
    });

    it('never renders a done state for UNKNOWN or BLOCKED rows', async () => {
        const checklist = {
            ...blankChecklist,
            items: blankChecklist.items.map((i) =>
                i.key === 'site_active'
                    ? { ...i, status: 'UNKNOWN' }
                    : i.key === 'industry_added'
                      ? { ...i, status: 'BLOCKED', blockedBy: ['framework_pages'] }
                      : i
            ),
            requiredDone: 0
        };
        const el = await mount(checklist);
        expect(rowEl(el, 'site_active').item.status).toBe('UNKNOWN');
        expect(rowEl(el, 'industry_added').item.status).toBe('BLOCKED');
        expect(el.shadowRoot.querySelector('.setup-header').textContent).toMatch(/^0 of 8/);
    });

    it('shows a load failure with the server message', async () => {
        getChecklist.mockRejectedValue({ body: { message: 'Setup could not be loaded.' } });
        const el = createElement('c-gtm-setup-checklist', { is: GtmSetupChecklist });
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.querySelector('.setup-error').textContent).toContain('Setup could not be loaded.');
    });

    it('ASSIGN_TO_ME calls assignPermissionSetToMe then re-fetches', async () => {
        const el = await mount(blankChecklist);
        getChecklist.mockClear();
        await fire(el, 'admin_assigned', { actionType: 'ASSIGN_TO_ME', permissionSetName: 'GTM_Offering_Admin' });
        expect(assignPermissionSetToMe).toHaveBeenCalledWith({ permissionSetName: 'GTM_Offering_Admin' });
        expect(getChecklist).toHaveBeenCalledTimes(1);
    });

    it('ASSIGN_PICKER searches, then assigns the chosen user, then re-fetches', async () => {
        searchAssignableUsers.mockResolvedValue([{ userId: '005000000000001AAA', name: 'Pat Rep', username: 'pat@example.test' }]);
        const el = await mount(blankChecklist);
        rowEl(el, 'reps_assigned').dispatchEvent(new CustomEvent('pickersearch', { detail: { term: 'pat' } }));
        await flush();
        expect(searchAssignableUsers).toHaveBeenCalledWith({ searchTerm: 'pat' });
        expect(rowEl(el, 'reps_assigned').pickerUsers).toEqual([
            { value: '005000000000001AAA', label: 'Pat Rep (pat@example.test)' }
        ]);
        getChecklist.mockClear();
        await fire(el, 'reps_assigned', {
            actionType: 'ASSIGN_PICKER',
            permissionSetName: 'GTM_Offering_User',
            userId: '005000000000001AAA'
        });
        expect(assignPermissionSet).toHaveBeenCalledWith({
            userId: '005000000000001AAA',
            permissionSetName: 'GTM_Offering_User'
        });
        expect(getChecklist).toHaveBeenCalledTimes(1);
    });

    it('SCHEDULE_JOBS schedules only unscheduled jobs', async () => {
        getStatuses.mockResolvedValue([
            { jobKey: 'purgeRecordsBatch', isScheduled: true },
            { jobKey: 'assessmentDraftPurge', isScheduled: false }
        ]);
        const el = await mount(blankChecklist);
        getChecklist.mockClear();
        await fire(el, 'scheduled_jobs', { actionType: 'SCHEDULE_JOBS' });
        expect(scheduleJob).toHaveBeenCalledTimes(1);
        expect(scheduleJob).toHaveBeenCalledWith({ jobKey: 'assessmentDraftPurge' });
        expect(getChecklist).toHaveBeenCalledTimes(1);
    });

    it('CREATE_FRAMEWORK_PAGES loops only over templates named as missing, using starterFor', async () => {
        const checklist = withItem('framework_pages', {
            detail: 'Missing: industry-chooser, faq-bd'
        });
        const el = await mount(checklist);
        getChecklist.mockClear();
        await fire(el, 'framework_pages', { actionType: 'CREATE_FRAMEWORK_PAGES' });
        expect(createFrameworkPage).toHaveBeenCalledTimes(2);
        expect(createFrameworkPage).toHaveBeenNthCalledWith(1, {
            templateType: 'industry-chooser',
            sections: starterFor('industry-chooser')
        });
        expect(createFrameworkPage.mock.calls[1][0].templateType).toBe('faq-bd');
        expect(getChecklist).toHaveBeenCalledTimes(1);
    });

    it('CREATE_FRAMEWORK_PAGES continues past a failed template, shows the message, and re-fetches', async () => {
        createFrameworkPage
            .mockRejectedValueOnce({ body: { message: 'Page already has sections.' } })
            .mockResolvedValue({ created: true });
        const el = await mount(blankChecklist); // blank detail: all five
        getChecklist.mockClear();
        await fire(el, 'framework_pages', { actionType: 'CREATE_FRAMEWORK_PAGES' });
        expect(createFrameworkPage).toHaveBeenCalledTimes(5);
        expect(el.shadowRoot.querySelector('.setup-error').textContent).toContain('Page already has sections.');
        expect(getChecklist).toHaveBeenCalledTimes(1);
    });

    it('a failing action shows the server message and does not mark anything done', async () => {
        assignPermissionSetToMe.mockRejectedValue({ body: { message: 'Not allowed.' } });
        const el = await mount(blankChecklist);
        await fire(el, 'admin_assigned', { actionType: 'ASSIGN_TO_ME', permissionSetName: 'GTM_Offering_Admin' });
        expect(el.shadowRoot.querySelector('.setup-error').textContent).toContain('Not allowed.');
        expect(rowEl(el, 'admin_assigned').item.status).toBe('TODO');
        expect(el.shadowRoot.querySelector('.setup-header').textContent).toMatch(/^0 of 8/);
    });

    it('fallbackToSetup renders a link to the Setup path instead of claiming success', async () => {
        assignPermissionSetToMe.mockResolvedValue({
            assigned: false,
            fallbackToSetup: true,
            setupPath: '/lightning/setup/PermSets/home',
            message: 'You need the Assign Permission Sets permission.'
        });
        const el = await mount(blankChecklist);
        await fire(el, 'admin_assigned', { actionType: 'ASSIGN_TO_ME', permissionSetName: 'GTM_Offering_Admin' });
        const link = el.shadowRoot.querySelector('.setup-notice-link');
        expect(link.getAttribute('href')).toBe('/lightning/setup/PermSets/home');
        expect(el.shadowRoot.querySelector('.setup-notice').textContent).toContain('Assign Permission Sets');
        link.click();
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__webPage',
            attributes: { url: '/lightning/setup/PermSets/home' }
        });
    });

    it('navigates NAV_ITEM and SETUP_PATH links', async () => {
        const el = await mount(blankChecklist);
        await fire(el, 'industry_added', {
            actionType: 'LINK',
            linkKind: 'NAV_ITEM',
            navApiName: 'GTM_Content_Manager',
            navState: { c__offering: 'gtm', c__template: 'industry-chooser' }
        });
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Content_Manager' },
            state: { c__offering: 'gtm', c__template: 'industry-chooser' }
        });
        await fire(el, 'site_active', {
            actionType: 'LINK',
            linkKind: 'SETUP_PATH',
            setupPath: '/lightning/setup/NetworkSettings/home'
        });
        expect(mockNavigate).toHaveBeenLastCalledWith({
            type: 'standard__webPage',
            attributes: { url: '/lightning/setup/NetworkSettings/home' }
        });
        expect(getChecklist).toHaveBeenCalledTimes(1); // links do not re-fetch
    });

    it('fires selectsection for the three settings-section rows', async () => {
        const el = await mount(blankChecklist);
        const handler = jest.fn();
        el.addEventListener('selectsection', handler);
        el.shadowRoot.querySelectorAll('.setup-toggle').forEach((b) => b.click());
        await flush();
        await fire(el, 'approval_routing', { actionType: 'LINK', linkKind: 'NONE' });
        await fire(el, 'analytics_digest', { actionType: 'LINK', linkKind: 'NONE' });
        await fire(el, 'ai_keys', { actionType: 'LINK', linkKind: 'NONE' });
        expect(handler.mock.calls.map((c) => c[0].detail.sectionId)).toEqual([
            'approval-routing',
            'analytics-notifications',
            'claude-gus'
        ]);
        expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('Re-check re-fetches the checklist', async () => {
        const el = await mount(blankChecklist);
        getChecklist.mockClear();
        el.shadowRoot.querySelector('.setup-recheck').click();
        await flush();
        expect(getChecklist).toHaveBeenCalledTimes(1);
    });
});
