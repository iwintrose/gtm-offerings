import { createElement } from 'lwc';
import GtmSetupItem from 'c/gtmSetupItem';

const base = {
    key: 'k',
    tier: 'REQUIRED',
    category: 'ACCESS',
    status: 'TODO',
    title: 'A step',
    why: 'Because.',
    detail: '',
    humanMustAct: true,
    actionType: 'NONE',
    actionLabel: '',
    linkKind: 'NONE',
    blockedBy: [],
    collapsedByDefault: false
};

const flush = () => Promise.resolve();

function mount(item, props = {}) {
    const el = createElement('c-gtm-setup-item', { is: GtmSetupItem });
    el.item = { ...base, ...item };
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

describe('c-gtm-setup-item', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    const statuses = ['DONE', 'TODO', 'NOT_SET', 'BLOCKED', 'UNKNOWN', 'INFO'];
    const tiers = ['REQUIRED', 'RECOMMENDED', 'OPTIONAL', 'INFO'];

    describe.each(statuses)('status %s', (status) => {
        it.each(tiers)('renders title, why and an icon in tier %s', async (tier) => {
            const el = mount({ status, tier, collapsedByDefault: false });
            await flush();
            const root = el.shadowRoot;
            expect(root.querySelector('.title').textContent).toBe('A step');
            expect(root.querySelector('.why').textContent).toBe('Because.');
            expect(root.querySelector('lightning-icon')).not.toBeNull();
        });
    });

    it.each(['NOT_SET', 'INFO', 'OPTIONAL'])('uses no error or warning styling for %s', async (v) => {
        const el = mount(
            v === 'OPTIONAL' ? { tier: 'OPTIONAL', status: 'NOT_SET' } : { status: v, tier: v === 'INFO' ? 'INFO' : 'OPTIONAL' }
        );
        await flush();
        expect(el.shadowRoot.innerHTML).not.toMatch(/error|warning|destructive|red/i);
    });

    it('shows the human marker from humanMustAct', async () => {
        const human = mount({ humanMustAct: true });
        const auto = mount({ humanMustAct: false });
        await flush();
        expect(human.shadowRoot.querySelector('.marker').textContent).toBe('You need to do this');
        expect(auto.shadowRoot.querySelector('.marker').textContent).toBe('Done for you');
    });

    it('never shows an automatic-done marker on UNKNOWN or BLOCKED', async () => {
        const el = mount({ status: 'UNKNOWN', humanMustAct: true });
        await flush();
        expect(el.shadowRoot.querySelector('lightning-icon').iconName).toBe('utility:question');
    });

    it('renders detail and blockedBy when present', async () => {
        const el = mount({ status: 'BLOCKED', detail: '2 drafts', blockedBy: ['a', 'b'] });
        await flush();
        expect(el.shadowRoot.querySelector('.detail').textContent).toBe('2 drafts');
        expect(el.shadowRoot.querySelector('.blocked-by').textContent).toBe('Waiting on: a, b');
    });

    it('renders no action control for NONE', async () => {
        const el = mount({});
        await flush();
        expect(el.shadowRoot.querySelector('lightning-button')).toBeNull();
    });

    it('starts collapsed when collapsedByDefault and toggles open', async () => {
        const el = mount({ tier: 'OPTIONAL', status: 'NOT_SET', collapsedByDefault: true, actionType: 'LINK', actionLabel: 'Open' });
        await flush();
        expect(el.shadowRoot.querySelector('.why')).toBeNull();
        expect(el.shadowRoot.querySelector('.title')).not.toBeNull();
        el.shadowRoot.querySelector('lightning-button-icon').click();
        await flush();
        expect(el.shadowRoot.querySelector('.why')).not.toBeNull();
        expect(el.shadowRoot.querySelector('lightning-button')).not.toBeNull();
    });

    it.each([
        ['LINK', { linkKind: 'NAV_ITEM', navApiName: 'GTM_Content_Home', navState: { c__x: '1' } }],
        ['LINK', { linkKind: 'SETUP_PATH', setupPath: '/lightning/setup/Queues/home' }],
        ['ASSIGN_TO_ME', { permissionSetName: 'GTM_Offering_Admin' }],
        ['SCHEDULE_JOBS', {}],
        ['CREATE_FRAMEWORK_PAGES', {}]
    ])('fires itemaction with full detail for %s', async (actionType, extra) => {
        const el = mount({ key: 'row', actionType, actionLabel: 'Do it', ...extra });
        const handler = jest.fn();
        el.addEventListener('itemaction', handler);
        await flush();
        el.shadowRoot.querySelector('lightning-button').click();
        expect(handler).toHaveBeenCalledTimes(1);
        const evt = handler.mock.calls[0][0];
        expect(evt.bubbles).toBe(false);
        expect(evt.composed).toBe(false);
        expect(evt.detail).toEqual({
            key: 'row',
            actionType,
            permissionSetName: extra.permissionSetName,
            linkKind: extra.linkKind || 'NONE',
            navApiName: extra.navApiName,
            navState: extra.navState,
            setupPath: extra.setupPath,
            userId: undefined
        });
    });

    it('disables the action while busy and fires nothing', async () => {
        const el = mount({ actionType: 'SCHEDULE_JOBS', actionLabel: 'Go' }, { busy: true });
        const handler = jest.fn();
        el.addEventListener('itemaction', handler);
        await flush();
        const btn = el.shadowRoot.querySelector('lightning-button');
        expect(btn.disabled).toBe(true);
        btn.click();
        expect(handler).not.toHaveBeenCalled();
    });

    describe('ASSIGN_PICKER', () => {
        const users = [{ value: '005A', label: 'Ann' }];
        const item = { key: 'p', actionType: 'ASSIGN_PICKER', actionLabel: 'Assign', permissionSetName: 'GTM_Offering_User' };

        it('disables Assign until a user is chosen, then fires with userId', async () => {
            const el = mount(item, { pickerUsers: users });
            const handler = jest.fn();
            el.addEventListener('itemaction', handler);
            await flush();
            const btn = el.shadowRoot.querySelector('.assign-button');
            expect(btn.disabled).toBe(true);
            expect(el.shadowRoot.querySelector('.picker-select').options).toEqual(users);

            el.shadowRoot.querySelector('.picker-select').dispatchEvent(
                new CustomEvent('change', { detail: { value: '005A' } })
            );
            await flush();
            expect(btn.disabled).toBe(false);
            btn.click();
            expect(handler.mock.calls[0][0].detail).toMatchObject({
                key: 'p',
                actionType: 'ASSIGN_PICKER',
                permissionSetName: 'GTM_Offering_User',
                userId: '005A'
            });
        });

        it('fires pickersearch with the typed term', async () => {
            const el = mount(item, { pickerUsers: users });
            const handler = jest.fn();
            el.addEventListener('pickersearch', handler);
            await flush();
            const input = el.shadowRoot.querySelector('.picker-search');
            input.value = 'an';
            input.dispatchEvent(new CustomEvent('change'));
            expect(handler.mock.calls[0][0].detail).toEqual({ term: 'an' });
        });
    });
});
