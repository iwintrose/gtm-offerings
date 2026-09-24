import { readFileSync } from 'fs';
import path from 'path';
import { createElement } from 'lwc';
import GtmPageHeader from 'c/gtmPageHeader';

// jsdom does not run real layout, so element.getBoundingClientRect()/
// getComputedStyle() can't distinguish a top-aligned icon/title from a
// re-centered one the way QA's live browser check did. Instead, this reads
// the actual shipped CSS source and asserts the mechanism that keeps the
// icon and title fixed in place: the row/col-title flex containers must be
// top-aligned (not centered, which was the original defect -- centering
// re-positions the icon/title whenever the content block's height changes
// based on whether the meta line is populated), and the meta line itself
// must reserve its own line-height via min-height so its box never
// disappears and changes the height of the stack above it (issue
// gtm-page-header-icon-shift).
const CSS_PATH = path.join(__dirname, '..', 'gtmPageHeader.css');

function readCss() {
    return readFileSync(CSS_PATH, 'utf8');
}

function ruleFor(css, selectorSource) {
    const match = css.match(new RegExp(`${selectorSource}\\s*{([^}]*)}`));
    if (!match) {
        throw new Error(`Expected a CSS rule for ${selectorSource}`);
    }
    return match[1];
}

describe('c-gtm-page-header', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createHeader(props = {}) {
        const element = createElement('c-gtm-page-header', { is: GtmPageHeader });
        Object.assign(element, props);
        document.body.appendChild(element);
        return element;
    }

    it('renders the icon, eyebrow, title and meta from props', async () => {
        const element = createHeader({
            iconName: 'standard:opportunity',
            eyebrow: 'Go to market',
            title: 'GTM Offerings',
            meta: '3 offerings · 2 requests waiting'
        });
        await Promise.resolve();

        const icon = element.shadowRoot.querySelector('lightning-icon');
        expect(icon.iconName).toBe('standard:opportunity');

        const eyebrow = element.shadowRoot.querySelector('.hdr-eyebrow');
        expect(eyebrow.textContent).toBe('Go to market');

        const title = element.shadowRoot.querySelector('.hdr-title');
        expect(title.textContent).toBe('GTM Offerings');

        const meta = element.shadowRoot.querySelector('.hdr-meta');
        expect(meta.textContent).toBe('3 offerings · 2 requests waiting');

        // The icon/title row must reserve a fixed min-height so the icon's
        // vertical position doesn't depend on whether the meta line has
        // content (issue gtm-page-header-icon-shift).
        const row = element.shadowRoot.querySelector('.slds-page-header__col-title');
        expect(row.className).toContain('slds-page-header__col-title');
    });

    it('renders a blank meta line without error when meta is not supplied, keeping the same reserved row height as when meta is populated', async () => {
        const element = createHeader({
            iconName: 'standard:article',
            eyebrow: 'Content',
            title: 'GTM Offerings'
        });
        await Promise.resolve();

        const meta = element.shadowRoot.querySelector('.hdr-meta');
        expect(meta.textContent).toBe('');

        // Same row/class structure must be present regardless of blank meta,
        // since the min-height reserving the icon's position is applied via
        // the shared .slds-page-header__col-title class, not conditionally.
        const row = element.shadowRoot.querySelector('.slds-page-header__col-title');
        expect(row).not.toBeNull();
        expect(row.querySelector('lightning-icon')).not.toBeNull();
        expect(row.querySelector('.hdr-meta')).not.toBeNull();
    });

    it('top-aligns the icon/title row and col-title instead of centering, so the icon and title never re-position based on meta content (regression guard for issue gtm-page-header-icon-shift)', () => {
        const css = readCss();

        const row = ruleFor(css, '\\.hdr\\s+\\.slds-page-header__row');
        expect(row).toMatch(/align-items:\s*flex-start/);
        expect(row).not.toMatch(/align-items:\s*center/);

        const colTitle = ruleFor(css, '\\.hdr\\s+\\.slds-page-header__col-title');
        expect(colTitle).toMatch(/align-items:\s*flex-start/);
        expect(colTitle).not.toMatch(/align-items:\s*center/);
        // The old fix anchored a min-height on this row itself; that was the
        // fragile, easily-decayed part. It must not come back here.
        expect(colTitle).not.toMatch(/min-height/);
    });

    it('reserves one line of height on the meta paragraph itself via min-height, so its box never collapses when meta is blank and never grows the space above it (regression guard for issue gtm-page-header-icon-shift)', () => {
        const css = readCss();
        const meta = ruleFor(css, '\\.hdr-meta');
        expect(meta).toMatch(/min-height:\s*[\d.]+(em|rem|px)/);
        expect(meta).toMatch(/line-height:\s*[\d.]+/);
    });

    it('lets the row wrap so actions never crush or overlap the title (issue page-header-layout-fix)', () => {
        const row = ruleFor(readCss(), '\\.hdr\\s+\\.slds-page-header__row');
        expect(row).toMatch(/display:\s*flex/);
        expect(row).toMatch(/flex-wrap:\s*wrap/);
        expect(row).toMatch(/gap:\s*1rem/);
    });

    it('gives the title column a 16rem floor and keeps it shrinkable (issue page-header-layout-fix)', () => {
        const colTitle = ruleFor(readCss(), '\\.hdr\\s+\\.slds-page-header__col-title');
        expect(colTitle).toMatch(/flex:\s*1\s+1\s+16rem/);
        expect(colTitle).toMatch(/min-width:\s*0/);
        expect(colTitle).toMatch(/display:\s*flex/);
        expect(colTitle).toMatch(/gap:\s*\.75rem/);
    });

    it('lets the actions column shrink, wrap and stay right-aligned (issue page-header-layout-fix)', () => {
        const actions = ruleFor(readCss(), '\\.hdr\\s+\\.slds-page-header__col-actions');
        expect(actions).toMatch(/flex:\s*0\s+1\s+auto/);
        expect(actions).toMatch(/min-width:\s*0/);
        expect(actions).toMatch(/display:\s*flex/);
        expect(actions).toMatch(/flex-wrap:\s*wrap/);
        expect(actions).toMatch(/justify-content:\s*flex-end/);
        expect(actions).toMatch(/align-items:\s*center/);
        expect(actions).toMatch(/gap:\s*\.5rem/);
        expect(actions).toMatch(/margin-left:\s*auto/);
    });

    it('wraps long titles instead of truncating them, and does not truncate (issue page-header-layout-fix)', () => {
        const title = ruleFor(readCss(), '\\.hdr-title');
        expect(title).toMatch(/overflow-wrap:\s*anywhere/);
        expect(title).not.toMatch(/text-overflow/);
        expect(title).not.toMatch(/white-space:\s*nowrap/);
        expect(ruleFor(readCss(), '\\.hdr-meta')).toMatch(/min-height:\s*1\.2em/);
    });

    it('projects action buttons passed into the named "actions" slot', async () => {
        const element = createElement('c-gtm-page-header', { is: GtmPageHeader });
        element.iconName = 'standard:opportunity';
        element.eyebrow = 'Go to market';
        element.title = 'GTM Offerings';

        const button = document.createElement('lightning-button');
        button.setAttribute('slot', 'actions');
        button.setAttribute('label', 'New engagement link');
        element.appendChild(button);

        document.body.appendChild(element);
        await Promise.resolve();

        const slot = element.shadowRoot.querySelector('slot[name="actions"]');
        expect(slot).not.toBeNull();

        // The button is a light-DOM child of the host (slotted in), not part
        // of the component's own shadow tree. LWC's synthetic shadow patches
        // querySelector on the host itself to search its shadow tree, so the
        // plain, unpatched document is used to find the light-DOM child.
        const assigned = document.body.querySelector('lightning-button[slot="actions"]');
        expect(assigned).not.toBeNull();
        expect(assigned.getAttribute('label')).toBe('New engagement link');
    });

    // ---- Addendum A: declarative actions + compact hamburger ----------

    describe('actions prop, wide/compact variants (issue page-header-actions-menu)', () => {
        const ACTIONS = [
            { name: 'primary', label: 'Primary', iconName: 'utility:new', variant: 'brand' },
            { name: 'second', label: 'Second', iconName: 'utility:search' },
            { name: 'off', label: 'Off', iconName: 'utility:delete', variant: 'destructive', disabled: true }
        ];
        let observers;
        const realRO = global.ResizeObserver;

        beforeEach(() => {
            observers = [];
            global.ResizeObserver = class {
                constructor(cb) {
                    this.cb = cb;
                    this.observe = jest.fn((t) => { this.target = t; });
                    this.disconnect = jest.fn();
                    observers.push(this);
                }
            };
        });
        afterEach(() => {
            global.ResizeObserver = realRO;
        });

        async function resize(width) {
            observers[0].cb([{ contentRect: { width } }]);
            await Promise.resolve();
        }
        const wide = (el) => [...el.shadowRoot.querySelectorAll('lightning-button.hdr-action')];
        const menu = (el) => el.shadowRoot.querySelector('lightning-button-menu');
        const items = (el) => [...el.shadowRoot.querySelectorAll('lightning-menu-item')];

        it('observes the host element and starts wide with one lightning-button per action', async () => {
            const el = createHeader({ actions: ACTIONS });
            await Promise.resolve();
            expect(observers).toHaveLength(1);
            expect(observers[0].observe).toHaveBeenCalledWith(el);
            expect(menu(el)).toBeNull();
            const buttons = wide(el);
            expect(buttons.map((b) => b.label)).toEqual(['Primary', 'Second', 'Off']);
            expect(buttons.map((b) => b.iconName)).toEqual(['utility:new', 'utility:search', 'utility:delete']);
            expect(buttons.map((b) => b.variant)).toEqual(['brand', 'neutral', 'destructive']);
            expect(buttons.map((b) => b.disabled)).toEqual([false, false, true]);
        });

        it('switches at 900px of header width, exactly one variant in the DOM', async () => {
            const el = createHeader({ actions: ACTIONS });
            await Promise.resolve();
            await resize(899);
            expect(wide(el)).toHaveLength(0);
            expect(el.shadowRoot.querySelectorAll('lightning-button-menu')).toHaveLength(1);
            expect(el.shadowRoot.querySelector('.hdr').classList.contains('hdr-compact')).toBe(true);
            await resize(900);
            expect(menu(el)).toBeNull();
            expect(wide(el)).toHaveLength(3);
            expect(el.shadowRoot.querySelector('.hdr').classList.contains('hdr-compact')).toBe(false);
        });

        it('renders the hamburger with utility:rows, right alignment (opens downward), aria label and primary-first items with matching icons', async () => {
            const el = createHeader({ actions: ACTIONS });
            await Promise.resolve();
            await resize(600);
            const m = menu(el);
            expect(m.iconName).toBe('utility:rows');
            expect(m.alternativeText).toBe('Page actions');
            expect(m.menuAlignment).toBe('right');
            expect(m.menuAlignment).not.toMatch(/auto|bottom/);
            const list = items(el);
            expect(list.map((i) => i.value)).toEqual(['primary', 'second', 'off']);
            expect(list.map((i) => i.label)).toEqual(['Primary', 'Second', 'Off']);
            list.forEach((i, n) => expect(i.prefixIconName).toBe(ACTIONS[n].iconName));
            expect(list.map((i) => i.disabled)).toEqual([false, false, true]);
        });

        it('fires one headeraction event with detail.name from the wide buttons', async () => {
            const el = createHeader({ actions: ACTIONS });
            await Promise.resolve();
            const handler = jest.fn();
            el.addEventListener('headeraction', handler);
            wide(el)[1].dispatchEvent(new CustomEvent('click'));
            expect(handler).toHaveBeenCalledTimes(1);
            expect(handler.mock.calls[0][0].detail).toEqual({ name: 'second' });
            expect(handler.mock.calls[0][0].bubbles).toBe(false);
        });

        it('fires one headeraction event with detail.name from the menu select', async () => {
            const el = createHeader({ actions: ACTIONS });
            await Promise.resolve();
            await resize(500);
            const handler = jest.fn();
            el.addEventListener('headeraction', handler);
            menu(el).dispatchEvent(new CustomEvent('select', { detail: { value: 'primary' } }));
            expect(handler).toHaveBeenCalledTimes(1);
            expect(handler.mock.calls[0][0].detail).toEqual({ name: 'primary' });
        });

        it('never fires for a disabled action', async () => {
            const el = createHeader({ actions: ACTIONS });
            await Promise.resolve();
            const handler = jest.fn();
            el.addEventListener('headeraction', handler);
            wide(el)[2].dispatchEvent(new CustomEvent('click'));
            await resize(500);
            menu(el).dispatchEvent(new CustomEvent('select', { detail: { value: 'off' } }));
            expect(handler).not.toHaveBeenCalled();
        });

        it('re-renders when the actions array changes (disabled toggles)', async () => {
            const el = createHeader({ actions: ACTIONS });
            await Promise.resolve();
            el.actions = [{ ...ACTIONS[0], disabled: true }];
            await Promise.resolve();
            expect(wide(el)).toHaveLength(1);
            expect(wide(el)[0].disabled).toBe(true);
        });

        it('renders no buttons or menu for no actions, and tolerates a non-array', async () => {
            const el = createHeader();
            await Promise.resolve();
            expect(wide(el)).toHaveLength(0);
            el.actions = null;
            await Promise.resolve();
            expect(wide(el)).toHaveLength(0);
        });

        it('compact with no actions renders no menu (no dead hamburger) but keeps the slot; wide renders nothing extra', async () => {
            const el = createHeader();
            await Promise.resolve();
            expect(wide(el)).toHaveLength(0);
            expect(menu(el)).toBeNull();
            await resize(400);
            expect(menu(el)).toBeNull();
            expect(wide(el)).toHaveLength(0);
            expect(el.shadowRoot.querySelector('slot[name="actions"]')).not.toBeNull();
            el.actions = [];
            await Promise.resolve();
            expect(menu(el)).toBeNull();
        });

        it('compact with actions renders the menu, and it appears when actions arrive later', async () => {
            const el = createHeader();
            await Promise.resolve();
            await resize(400);
            expect(menu(el)).toBeNull();
            el.actions = ACTIONS;
            await Promise.resolve();
            expect(menu(el)).not.toBeNull();
            expect(items(el)).toHaveLength(3);
        });

        it('keeps the actions slot in the DOM in both variants', async () => {
            const el = createHeader({ actions: ACTIONS });
            await Promise.resolve();
            expect(el.shadowRoot.querySelector('slot[name="actions"]')).not.toBeNull();
            await resize(400);
            expect(el.shadowRoot.querySelector('slot[name="actions"]')).not.toBeNull();
        });

        it('disconnects the observer when removed', async () => {
            const el = createHeader({ actions: ACTIONS });
            await Promise.resolve();
            document.body.removeChild(el);
            expect(observers[0].disconnect).toHaveBeenCalledTimes(1);
        });

        it('stays wide without throwing when ResizeObserver is undefined', async () => {
            delete global.ResizeObserver;
            const el = createHeader({ actions: ACTIONS });
            await Promise.resolve();
            expect(wide(el)).toHaveLength(3);
            expect(menu(el)).toBeNull();
        });
    });

    describe('static CSS for actions layout (issue page-header-actions-menu)', () => {
        it('wide: actions column is bottom-right; #230 base rules stay', () => {
            const actions = ruleFor(readCss(), '\\.hdr\\s+\\.slds-page-header__col-actions');
            expect(actions).toMatch(/align-self:\s*flex-end/);
            expect(actions).toMatch(/margin-left:\s*auto/);
            expect(actions).toMatch(/flex-wrap:\s*wrap/);
            expect(ruleFor(readCss(), '\\.hdr\\s+\\.slds-page-header__col-title')).toMatch(/flex:\s*1\s+1\s+16rem/);
        });

        it('compact: actions top-right and no-wrap, title floor lowered to 10rem', () => {
            const css = readCss();
            const actions = ruleFor(css, '\\.hdr-compact\\s+\\.slds-page-header__col-actions');
            expect(actions).toMatch(/align-self:\s*flex-start/);
            expect(actions).toMatch(/flex-wrap:\s*nowrap/);
            expect(ruleFor(css, '\\.hdr-compact\\s+\\.slds-page-header__col-title')).toMatch(/flex-basis:\s*10rem/);
        });

        it('hamburger has a 44px minimum touch target', () => {
            const menu = ruleFor(readCss(), '\\.hdr-menu');
            expect(menu).toMatch(/min-width:\s*2\.75rem/);
            expect(menu).toMatch(/min-height:\s*2\.75rem/);
        });

        it('adds nothing that can clip or trap the dropdown', () => {
            const css = readCss().replace(/\/\*[\s\S]*?\*\//g, '');
            expect(css).not.toMatch(/overflow\s*:/);
            expect(css).not.toMatch(/contain\s*:/);
            expect(css).not.toMatch(/transform\s*:/);
            expect(css).not.toMatch(/container-type/);
            expect(css).not.toMatch(/position\s*:/);
            expect(css).not.toMatch(/z-index/);
        });
    });
});
