import { createElement } from 'lwc';
import GtmFilterBar from 'c/gtmFilterBar';
import { validateFilters } from 'c/gtmFilterUrlState';
import { buildFilterConfig } from 'c/gtmAssessmentsTableModel';

const fs = require('fs');
const path = require('path');

const FILTERS = [
    {
        key: 'multi',
        label: 'Multi',
        type: 'chips',
        multi: true,
        param: 'c__x',
        options: [
            { value: 'a', label: 'A', count: 3 },
            { value: 'b', label: 'B' },
            { value: 'c', label: 'C' }
        ]
    },
    {
        key: 'single',
        label: 'Single',
        type: 'chips',
        param: 'c__y',
        options: [
            { value: 'p', label: 'P', count: 4 },
            { value: 'q', label: 'Q' }
        ]
    },
    { key: 'sel', label: 'Sel', type: 'select', param: 'c__z', options: [{ value: 's1', label: 'S1' }, { value: 's2', label: 'S2' }] },
    { key: 'tog', label: 'Tog', type: 'toggle', param: 'c__t', more: true },
    { key: 'rng', label: 'Rng', type: 'date-range', param: 'c__r' }
];

const MANY = Array.from({ length: 10 }, (_, i) => ({ value: `o${i}`, label: i < 5 ? `Alpha ${i}` : `Beta ${i}` }));
const LONG = [{ key: 'off', label: 'Off', type: 'chips', multi: true, param: 'c__o', options: MANY }];

function make(props = {}) {
    const el = createElement('c-gtm-filter-bar', { is: GtmFilterBar });
    Object.assign(el, { filters: FILTERS, values: {}, ...props });
    document.body.appendChild(el);
    return el;
}
const q = (el, sel) => el.shadowRoot.querySelector(sel);
const qa = (el, sel) => Array.from(el.shadowRoot.querySelectorAll(sel));
const flush = () => Promise.resolve();
const tick = () => new Promise((r) => setTimeout(r, 5));
const trig = (el, key) => q(el, `button[data-slot="${key}"]`);
const open = async (el, key) => {
    trig(el, key).click();
    await flush();
    await tick(); // let the deferred document-listener attach and focus settle
};
const change = (node, detail) => node.dispatchEvent(new CustomEvent('change', { detail }));

afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
});

describe('gtmFilterBar structure', () => {
    it('renders one trigger per primary filter plus More, and no pills, chips or status row', () => {
        const el = make();
        expect(qa(el, 'button.gtm-filter-bar__trigger').map((b) => b.dataset.slot)).toEqual([
            'multi', 'single', 'sel', 'rng', '__more__'
        ]);
        expect(q(el, 'lightning-pill')).toBeNull();
        expect(q(el, '.gtm-filter-bar__pills')).toBeNull();
        expect(q(el, '.gtm-filter-bar__status')).toBeNull();
        expect(q(el, 'button[aria-pressed]')).toBeNull();
        expect(q(el, '[role="dialog"]')).toBeNull();
    });

    it('More renders only if a filter has more:true', () => {
        const el = make({ filters: FILTERS.filter((f) => !f.more) });
        expect(trig(el, '__more__')).toBeNull();
    });

    it('a config carrying more passes validateFilters', () => {
        expect(validateFilters(FILTERS)).toEqual([]);
    });

    it('shows the result count in an aria-live region on the same row', () => {
        const el = make({ resultCount: 12, resultLabel: 'pages' });
        const p = q(el, 'p[aria-live="polite"]');
        expect(p.textContent).toBe('12 pages');
        expect(p.parentElement.getAttribute('role')).toBe('group');
        expect(make({ resultCount: 0 }).shadowRoot.querySelector('p').textContent).toBe('0');
    });

    it('a11y: labelled group role; compact variant accepted', () => {
        expect(q(make({ label: 'Page filters' }), '[role="group"]').getAttribute('aria-label')).toBe('Page filters');
        expect(q(make(), '[role="group"]').getAttribute('aria-label')).toBe('Filters');
        expect(q(make({ variant: 'compact' }), '.gtm-filter-bar--compact')).not.toBeNull();
        expect(q(make(), '.gtm-filter-bar--compact')).toBeNull();
    });
});

describe('gtmFilterBar triggers and summaries', () => {
    it('sets aria-haspopup, aria-expanded, aria-controls and a label starting with the visible text', async () => {
        const el = make();
        const t = trig(el, 'multi');
        expect(t.getAttribute('aria-haspopup')).toBe('dialog');
        expect(t.getAttribute('aria-expanded')).toBe('false');
        expect(t.getAttribute('aria-controls')).toBeTruthy();
        expect(t.textContent.trim()).toBe('Multi');
        expect(t.getAttribute('aria-label')).toBe('Multi, no filter applied');
        await open(el, 'multi');
        expect(trig(el, 'multi').getAttribute('aria-expanded')).toBe('true');
        const pop = q(el, '[role="dialog"]');
        expect(pop.getAttribute('aria-label')).toBe('Multi');
        expect(pop.getAttribute('aria-modal')).toBeNull();
    });

    it('summaries: one value (no count), many, toggle, preset, custom date, More count', () => {
        const el = make({
            values: { multi: ['a'], single: 'p', tog: true, rng: { from: '2026-01-01', to: '2026-01-31' } }
        });
        expect(trig(el, 'multi').textContent.trim()).toBe('Multi: A');
        expect(trig(el, 'single').textContent.trim()).toBe('Single: P');
        expect(trig(el, 'rng').textContent.trim()).toBe('Rng: 2026-01-01 to 2026-01-31');
        // tog has a value, so it is on the row and nothing is hidden: no More button.
        expect(trig(el, 'tog').textContent.trim()).toBe('Tog: On');
        expect(trig(el, '__more__')).toBeNull();
        const idle = trig(make(), '__more__');
        expect(idle.textContent.trim()).toBe('More (1)');
        expect(idle.getAttribute('aria-label')).toBe('More (1) filters, 1 not shown, 0 added');

        const many = make({ values: { multi: ['a', 'c'], rng: '30' } });
        expect(trig(many, 'multi').textContent.trim()).toBe('Multi: 2');
        expect(trig(many, 'multi').getAttribute('aria-label')).toBe('Multi: 2 selected, A, C');
        expect(trig(many, 'rng').textContent.trim()).toBe('Rng: Last 30 days');
        expect(trig(many, 'multi').classList.contains('gtm-filter-bar__trigger--active')).toBe(true);
        expect(trig(many, 'single').classList.contains('gtm-filter-bar__trigger--active')).toBe(false);
    });

    it('a filter with a value under More shows its own button and popover control', async () => {
        const el = make({ values: { tog: true } });
        await open(el, 'tog');
        expect(q(el, 'lightning-input[data-key="tog"]').checked).toBe(true);
        expect(trig(el, '__more__')).toBeNull();
    });

    it('Clear filters shows only when active and emits clear once', async () => {
        const el = make();
        expect(q(el, 'lightning-button')).toBeNull();
        el.values = { single: 'p' };
        await flush();
        const clear = jest.fn();
        const fc = jest.fn();
        el.addEventListener('clear', clear);
        el.addEventListener('filterchange', fc);
        expect(q(el, 'lightning-button').label).toBe('Clear filters');
        q(el, 'lightning-button').dispatchEvent(new CustomEvent('click'));
        expect(clear).toHaveBeenCalledTimes(1);
        expect(fc).not.toHaveBeenCalled();
    });
});

describe('gtmFilterBar popover open/close', () => {
    it('opens on click, toggles closed, and only one is open at a time', async () => {
        const el = make();
        await open(el, 'multi');
        expect(qa(el, '[role="dialog"]').length).toBe(1);
        await open(el, 'single');
        expect(qa(el, '[role="dialog"]').length).toBe(1);
        expect(trig(el, 'multi').getAttribute('aria-expanded')).toBe('false');
        expect(trig(el, 'single').getAttribute('aria-expanded')).toBe('true');
        await open(el, 'single');
        expect(q(el, '[role="dialog"]')).toBeNull();
    });

    it('moves focus inside on open, falling back to the dialog when focus() is missing', async () => {
        const el = make();
        const spy = jest.fn();
        const orig = HTMLElement.prototype.focus;
        HTMLElement.prototype.focus = spy;
        await open(el, 'multi');
        HTMLElement.prototype.focus = orig;
        expect(spy).toHaveBeenCalled();
        const el2 = make();
        await open(el2, 'single');
        expect(q(el2, '[role="dialog"]')).not.toBeNull();
    });

    it('Escape closes and returns focus to the trigger', async () => {
        const el = make();
        await open(el, 'multi');
        const spy = jest.spyOn(trig(el, 'multi'), 'focus');
        q(el, 'lightning-checkbox-group').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, composed: true }));
        await flush();
        expect(q(el, '[role="dialog"]')).toBeNull();
        expect(spy).toHaveBeenCalled();
    });

    it('focusout to outside closes without stealing focus; focusout inside keeps it open', async () => {
        const el = make();
        await open(el, 'multi');
        const spy = jest.spyOn(trig(el, 'multi'), 'focus');
        const inside = q(el, 'lightning-checkbox-group');
        q(el, '.gtm-filter-bar').dispatchEvent(new FocusEvent('focusout', { bubbles: true, relatedTarget: inside }));
        await tick();
        expect(q(el, '[role="dialog"]')).not.toBeNull();
        q(el, '[data-pop]').blur(); // focus really left
        q(el, '.gtm-filter-bar').dispatchEvent(new FocusEvent('focusout', { bubbles: true, relatedTarget: document.body }));
        await tick();
        await flush();
        expect(q(el, '[role="dialog"]')).toBeNull();
        expect(spy).not.toHaveBeenCalled();
    });

    it('an outside document click closes; a click inside does not; listener removed on disconnect', async () => {
        const el = make();
        await open(el, 'multi');
        q(el, 'lightning-checkbox-group').dispatchEvent(new MouseEvent('click', { bubbles: true, composed: true }));
        await tick();
        expect(q(el, '[role="dialog"]')).not.toBeNull();
        document.body.dispatchEvent(new MouseEvent('click', { bubbles: true }));
        await flush();
        expect(q(el, '[role="dialog"]')).not.toBeNull(); // outside close is deferred a tick
        await tick();
        expect(q(el, '[role="dialog"]')).toBeNull();
        const rm = jest.spyOn(document, 'removeEventListener');
        await open(el, 'multi');
        document.body.removeChild(el);
        expect(rm).toHaveBeenCalledWith('click', expect.any(Function));
        rm.mockRestore();
    });
});

describe('gtmFilterBar change events', () => {
    it('multi: one filterchange, option order, [] to remove', async () => {
        const el = make({ values: { multi: ['b'] } });
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        await open(el, 'multi');
        change(q(el, 'lightning-checkbox-group'), { value: ['b', 'a'] });
        change(q(el, 'lightning-checkbox-group'), { value: [] });
        expect(handler.mock.calls.map((c) => c[0].detail)).toEqual([
            { key: 'multi', value: ['a', 'b'] },
            { key: 'multi', value: [] }
        ]);
        expect(q(el, '[role="dialog"]')).not.toBeNull(); // multi stays open
    });

    it('single: emits once, closes and returns focus; re-picking the selected value emits nothing', async () => {
        const el = make({ values: { single: 'p' } });
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        await open(el, 'single');
        const group = q(el, 'lightning-radio-group');
        expect(group.value).toBe('p');
        expect(group.options.map((o) => o.label)).toEqual(['P (4)', 'Q']);
        change(group, { value: 'p' });
        expect(handler).not.toHaveBeenCalled();
        await flush();
        expect(q(el, '[role="dialog"]')).toBeNull();
        await open(el, 'single');
        const spy = jest.spyOn(trig(el, 'single'), 'focus');
        change(q(el, 'lightning-radio-group'), { value: 'q' });
        await flush();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ key: 'single', value: 'q' });
        expect(typeof handler.mock.calls[0][0].detail.value).toBe('string');
        expect(q(el, '[role="dialog"]')).toBeNull();
        expect(spy).toHaveBeenCalled();
    });

    it('select has a leading Any and closes after pick', async () => {
        const el = make();
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        await open(el, 'sel');
        const g = q(el, 'lightning-radio-group');
        expect(g.options.map((o) => o.value)).toEqual(['', 's1', 's2']);
        change(g, { value: 's1' });
        await flush();
        expect(handler.mock.calls[0][0].detail).toEqual({ key: 'sel', value: 's1' });
        expect(q(el, '[role="dialog"]')).toBeNull();
    });

    it('toggle under More emits a boolean once', async () => {
        const el = make();
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        await open(el, '__more__');
        expect(q(el, '[role="dialog"]').getAttribute('aria-label')).toBe('Add filters');
        change(q(el, 'lightning-input[data-key="tog"]'), { checked: true }); // adds + auto-opens
        await flush();
        expect(handler).not.toHaveBeenCalled();
        expect(trig(el, 'tog').getAttribute('aria-expanded')).toBe('true');
        change(q(el, 'lightning-input[data-key="tog"]'), { checked: true });
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ key: 'tog', value: true });
    });

    it('date range: presets use a radio group and custom emits {from,to} once', async () => {
        const el = make();
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        await open(el, 'rng');
        expect(q(el, 'lightning-combobox')).toBeNull();
        const g = q(el, 'lightning-radio-group');
        expect(g.options.map((o) => o.value)).toEqual(['', '7', '30', '90', '__custom__']);
        change(g, { value: '30' });
        expect(handler.mock.calls[0][0].detail).toEqual({ key: 'rng', value: '30' });
        change(q(el, 'lightning-radio-group'), { value: '__custom__' });
        await flush();
        expect(handler).toHaveBeenCalledTimes(1);
        change(q(el, 'lightning-input[data-edge="from"]'), { value: '2026-01-01' });
        expect(handler).toHaveBeenCalledTimes(1);
        await flush();
        change(q(el, 'lightning-input[data-edge="to"]'), { value: '2026-02-01' });
        expect(handler).toHaveBeenCalledTimes(2);
        expect(handler.mock.calls[1][0].detail).toEqual({ key: 'rng', value: { from: '2026-01-01', to: '2026-02-01' } });
    });

    it('shows date inputs when the value is a range object', async () => {
        const el = make({ values: { rng: { from: '2026-01-01', to: '2026-02-01' } } });
        await open(el, 'rng');
        expect(q(el, 'lightning-input[data-edge="from"]').value).toBe('2026-01-01');
        expect(q(el, 'lightning-radio-group').value).toBe('__custom__');
    });

    it('Escape/close does not emit filterchange', async () => {
        const el = make();
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        await open(el, 'multi');
        q(el, '.gtm-filter-bar').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        expect(handler).not.toHaveBeenCalled();
    });
});

describe('gtmFilterBar long lists', () => {
    it('search input appears above 8 options only, is bounded, and filters visible options', async () => {
        const el = make({ filters: LONG });
        await open(el, 'off');
        expect(q(el, 'lightning-input[data-role="search"]')).not.toBeNull();
        expect(q(el, '.gtm-filter-bar__list')).not.toBeNull();
        expect(q(el, 'lightning-checkbox-group').options.length).toBe(10);
        change(q(el, 'lightning-input[data-role="search"]'), { value: 'beta' });
        await flush();
        expect(q(el, 'lightning-checkbox-group').options.length).toBe(5);
        change(q(el, 'lightning-input[data-role="search"]'), { value: 'zzz' });
        await flush();
        expect(q(el, 'lightning-checkbox-group')).toBeNull();
        expect(q(el, '.gtm-filter-bar__empty').textContent).toBe('No matches');
        const small = make();
        await open(small, 'multi');
        expect(q(small, 'lightning-input[data-role="search"]')).toBeNull();
    });

    it('preserves selections hidden by the search text and emits nothing for the search itself', async () => {
        const el = make({ filters: LONG, values: { off: ['o1', 'o7'] } });
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        await open(el, 'off');
        change(q(el, 'lightning-input[data-role="search"]'), { value: 'beta' });
        await flush();
        expect(handler).not.toHaveBeenCalled();
        // visible group holds the Beta value o7; user adds o9 -> hidden o1 must survive.
        change(q(el, 'lightning-checkbox-group'), { value: ['o9', 'o7'] });
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ key: 'off', value: ['o1', 'o7', 'o9'] });
        // user unticks the visible o7 -> hidden o1 survives.
        change(q(el, 'lightning-checkbox-group'), { value: [] });
        expect(handler.mock.calls[1][0].detail).toEqual({ key: 'off', value: ['o1'] });
    });

    it('search text is cleared on close', async () => {
        const el = make({ filters: LONG });
        await open(el, 'off');
        change(q(el, 'lightning-input[data-role="search"]'), { value: 'beta' });
        await flush();
        await open(el, 'off');
        await open(el, 'off');
        expect(q(el, 'lightning-checkbox-group').options.length).toBe(10);
    });
});

describe('gtmFilterBar opens with real bubbling events (real-runtime defect)', () => {
    // Emulates the Lightning runtime, where a document listener sees an event whose
    // composedPath() is filtered and whose target is retargeted to an outer host.
    let addSpy;
    let rmSpy;
    beforeEach(() => {
        // Document click listeners receive an event retargeted to an OUTER host that is
        // neither our host nor inside our wrapper, with an empty composedPath().
        const outer = document.createElement('c-outer-host');
        const map = new Map();
        const realAdd = document.addEventListener.bind(document);
        const realRm = document.removeEventListener.bind(document);
        addSpy = jest.spyOn(document, 'addEventListener').mockImplementation((type, fn, opts) => {
            if (type !== 'click') return realAdd(type, fn, opts);
            const wrapped = (e) => fn({ type: e.type, target: outer, composedPath: () => [] });
            map.set(fn, wrapped);
            return realAdd(type, wrapped, opts);
        });
        rmSpy = jest.spyOn(document, 'removeEventListener').mockImplementation((type, fn, opts) =>
            realRm(type, type === 'click' && map.has(fn) ? map.get(fn) : fn, opts)
        );
    });
    afterEach(() => {
        addSpy.mockRestore();
        rmSpy.mockRestore();
    });

    const realClick = (node) => node.dispatchEvent(new MouseEvent('click', { bubbles: true, composed: true, cancelable: true }));

    it('a real bubbling click opens the popover and it stays open', async () => {
        const el = make();
        realClick(trig(el, 'multi'));
        await flush();
        await tick();
        expect(trig(el, 'multi').getAttribute('aria-expanded')).toBe('true');
        expect(q(el, '[role="dialog"]')).not.toBeNull();
    });

    it('More opens the same way', async () => {
        const el = make();
        realClick(trig(el, '__more__'));
        await tick();
        expect(q(el, '[role="dialog"]').getAttribute('aria-label')).toBe('Add filters');
    });

    it('Enter and Space (native button click) open it', async () => {
        const el = make();
        const t = trig(el, 'single');
        t.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, composed: true }));
        realClick(t); // browsers synthesise click for Enter/Space on a button
        await tick();
        expect(q(el, '[role="dialog"]')).not.toBeNull();
        realClick(t);
        await tick();
        expect(q(el, '[role="dialog"]')).toBeNull();
        t.dispatchEvent(new KeyboardEvent('keyup', { key: ' ', bubbles: true, composed: true }));
        realClick(t);
        await tick();
        expect(q(el, '[role="dialog"]')).not.toBeNull();
    });

    it('focus moves into the popover on open', async () => {
        const el = make();
        const spy = jest.spyOn(HTMLElement.prototype, 'focus');
        realClick(trig(el, 'single'));
        await tick();
        expect(spy).toHaveBeenCalled();
        spy.mockRestore();
    });

    it('a focusout in the same interaction as the open does not close it', async () => {
        const el = make();
        realClick(trig(el, 'multi'));
        q(el, '.gtm-filter-bar').dispatchEvent(new FocusEvent('focusout', { bubbles: true, relatedTarget: null }));
        await tick();
        await tick();
        expect(q(el, '[role="dialog"]')).not.toBeNull();
    });

    it('the opening click never closes it, even when the document listener sees it as outside', async () => {
        const el = make();
        realClick(trig(el, 'multi'));
        await tick();
        await tick();
        expect(q(el, '[role="dialog"]')).not.toBeNull();
        // A LATER click that the listener sees as outside does close it.
        realClick(document.body);
        await tick();
        expect(q(el, '[role="dialog"]')).toBeNull();
    });

    it('a real click INSIDE the popover (document listener retargeted) keeps it open and the change still fires', async () => {
        const el = make();
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        realClick(trig(el, 'multi'));
        await tick();
        const group = q(el, 'lightning-checkbox-group');
        realClick(group);
        await flush();
        await flush();
        expect(group.isConnected).toBe(true);
        expect(q(el, '[data-pop]')).not.toBeNull();
        change(group, { value: ['a'] }); // activation behaviour: change AFTER click + microtasks
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ key: 'multi', value: ['a'] });
        await tick();
        expect(q(el, '[data-pop]')).not.toBeNull();
    });

    it('radio: click, microtasks, then change applies the value and only then closes', async () => {
        const el = make();
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        realClick(trig(el, 'single'));
        await tick();
        const group = q(el, 'lightning-radio-group');
        realClick(group);
        await flush();
        await flush();
        expect(group.isConnected).toBe(true);
        change(group, { value: 'q' });
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ key: 'single', value: 'q' });
        await tick();
        expect(q(el, '[data-pop]')).toBeNull();
    });

    it('Space/keydown inside marks an inside interaction (no close on the following click)', async () => {
        const el = make();
        realClick(trig(el, 'multi'));
        await tick();
        const group = q(el, 'lightning-checkbox-group');
        group.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true, composed: true }));
        realClick(group);
        await flush();
        await flush();
        expect(q(el, '[data-pop]')).not.toBeNull();
        expect(group.isConnected).toBe(true);
    });

    it('a real outside click closes after a timeout, not before an in-flight change', async () => {
        const el = make();
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        realClick(trig(el, 'multi'));
        await tick();
        const group = q(el, 'lightning-checkbox-group');
        realClick(document.body);
        await flush();
        await flush();
        expect(group.isConnected).toBe(true); // never closed synchronously / in a microtask
        change(group, { value: ['b'] });
        expect(handler).toHaveBeenCalledTimes(1);
        await tick();
        expect(q(el, '[data-pop]')).toBeNull();
    });

    it('opening a second popover closes the first; Escape closes and returns focus', async () => {
        const el = make();
        realClick(trig(el, 'multi'));
        await tick();
        realClick(trig(el, 'single'));
        await tick();
        expect(qa(el, '[role="dialog"]').length).toBe(1);
        expect(trig(el, 'single').getAttribute('aria-expanded')).toBe('true');
        const spy = jest.spyOn(trig(el, 'single'), 'focus');
        q(el, 'lightning-radio-group').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, composed: true }));
        await tick();
        expect(q(el, '[role="dialog"]')).toBeNull();
        expect(spy).toHaveBeenCalled();
    });

    it('removes the document listener on close and on disconnect', async () => {
        const add = jest.spyOn(document, 'addEventListener');
        const rm = jest.spyOn(document, 'removeEventListener');
        const el = make();
        realClick(trig(el, 'multi'));
        await tick();
        const added = add.mock.calls.filter((c) => c[0] === 'click');
        expect(added.length).toBe(1);
        realClick(trig(el, 'multi'));
        await tick();
        expect(rm.mock.calls.filter((c) => c[0] === 'click' && c[1] === added[0][1]).length).toBeGreaterThan(0);
        rm.mockClear();
        realClick(trig(el, 'multi'));
        await tick();
        document.body.removeChild(el);
        expect(rm.mock.calls.some((c) => c[0] === 'click')).toBe(true);
        add.mockRestore();
        rm.mockRestore();
    });
});

const PAGES = [
    {
        key: 'stage',
        label: 'Funnel stage',
        type: 'chips',
        param: 'c__stage',
        options: [
            'not_opened', 'sent', 'engaged', 'quiet', 'hot', 'a', 'b'
        ].map((v, i) => ({ value: v, label: `Stage ${i}`, count: i }))
    }
];

describe('gtmFilterBar Pages configuration (single-select, compact)', () => {
    it('renders ONE Funnel stage trigger, not seven chips, in the compact variant', () => {
        const el = make({ filters: PAGES, variant: 'compact', resultCount: 0, resultLabel: 'links' });
        expect(qa(el, 'button').length).toBe(1);
        expect(trig(el, 'stage').textContent.trim()).toBe('Funnel stage');
        expect(trig(el, 'stage').getAttribute('aria-haspopup')).toBe('dialog');
        expect(q(el, 'button[aria-pressed]')).toBeNull();
        expect(q(el, 'lightning-button')).toBeNull();
        expect(q(el, 'p[aria-live="polite"]').textContent).toBe('0 links');
        expect(q(el, 'p[aria-live="polite"]').parentElement.classList.contains('gtm-filter-bar')).toBe(true);
    });

    it('shows the value (without its count) in the trigger; counts stay in the option labels', async () => {
        const el = make({ filters: PAGES, variant: 'compact', values: { stage: 'hot' } });
        expect(trig(el, 'stage').textContent.trim()).toBe('Funnel stage: Stage 4');
        expect(q(el, 'lightning-button').label).toBe('Clear filters');
        await open(el, 'stage');
        const g = q(el, 'lightning-radio-group');
        expect(g.options.length).toBe(7);
        expect(g.options[0].label).toBe('Stage 0 (0)');
        expect(g.options[6].label).toBe('Stage 6 (6)');
    });

    it('choosing an option emits the same payload as before and closes the popover', async () => {
        const el = make({ filters: PAGES, variant: 'compact' });
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        await open(el, 'stage');
        change(q(el, 'lightning-radio-group'), { value: 'hot' });
        await flush();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ key: 'stage', value: 'hot' });
        expect(q(el, '[role="dialog"]')).toBeNull();
    });
});

describe('gtmFilterBar Assessments configuration', () => {
    const cfg = () => buildFilterConfig(['Offer A', 'Offer B'], []);

    it('with nothing active: one row of Status, Readiness tier, Submitted, More; order comes from config', async () => {
        const el = make({ filters: cfg(), variant: 'compact' });
        expect(qa(el, 'button').map((b) => b.textContent.trim())).toEqual([
            'Status', 'Readiness tier', 'Submitted', 'More (5)'
        ]);
        expect(q(el, 'lightning-button')).toBeNull();
        expect(q(el, '.gtm-filter-bar').classList.contains('slds-wrap')).toBe(true);
        await open(el, '__more__');
        const titles = qa(el, '.gtm-filter-bar__additem lightning-input').map((n) => n.label);
        expect(titles).toEqual(['Ready to book', 'Readout', 'Offering', 'Account', 'Contact']);
    });

    it('a deep-linked More value always shows its own button; More counts only what is hidden', () => {
        const el = make({ filters: cfg(), values: { offering: ['Offer A'], preset: true } });
        expect(qa(el, 'button.gtm-filter-bar__trigger').map((b) => b.textContent.trim())).toEqual([
            'Ready to book: On', 'Status', 'Readiness tier', 'Submitted', 'Offering: Offer A', 'More (3)'
        ]);
        expect(validateFilters(cfg())).toEqual([]);
    });
});

describe('gtmFilterBar REAL input event order (defects found with real mouse/keyboard)', () => {
    const ev = (Type, type, init = {}) => new Type(type, { bubbles: true, composed: true, ...init });

    // Real browser order on a mouse click of a checkbox label inside the popover:
    // pointerdown, mousedown, focusout(input -> popover div), focusin(div), mouseup,
    // click (label), change (input), then a focusout(div, relatedTarget null).
    async function realClickOnOption(el, group, valueOnChange) {
        const pop = q(el, '[data-pop]');
        const wrapper = q(el, '.gtm-filter-bar');
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        const stillOpen = () => expect(q(el, '[data-pop]')).not.toBeNull();
        group.dispatchEvent(ev(MouseEvent, 'pointerdown'));
        group.dispatchEvent(ev(MouseEvent, 'mousedown'));
        wrapper.dispatchEvent(ev(FocusEvent, 'focusout', { relatedTarget: pop }));
        pop.dispatchEvent(ev(FocusEvent, 'focusin'));
        await tick();
        stillOpen();
        group.dispatchEvent(ev(MouseEvent, 'mouseup'));
        group.dispatchEvent(ev(MouseEvent, 'click'));
        change(group, { value: valueOnChange });
        pop.blur(); // real runtime: nothing focused after the div lost focus
        wrapper.dispatchEvent(ev(FocusEvent, 'focusout', { relatedTarget: null }));
        await tick();
        await tick();
        stillOpen();
        return handler;
    }

    it('multi: a real click keeps the popover open through the focus hops and the change fires once', async () => {
        const el = make();
        await open(el, 'multi');
        const handler = await realClickOnOption(el, q(el, 'lightning-checkbox-group'), ['a']);
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ key: 'multi', value: ['a'] });
    });

    it('a focusout with a null relatedTarget never closes the popover', async () => {
        const el = make();
        await open(el, 'multi');
        q(el, '[data-pop]').blur();
        q(el, '.gtm-filter-bar').dispatchEvent(ev(FocusEvent, 'focusout', { relatedTarget: null }));
        await tick();
        await tick();
        expect(q(el, '[data-pop]')).not.toBeNull();
    });

    it('single: a real pick emits once and closes', async () => {
        const el = make();
        await open(el, 'single');
        const group = q(el, 'lightning-radio-group');
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        group.dispatchEvent(ev(MouseEvent, 'mousedown'));
        q(el, '.gtm-filter-bar').dispatchEvent(ev(FocusEvent, 'focusout', { relatedTarget: q(el, '[data-pop]') }));
        change(group, { value: 'q' });
        await tick();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(q(el, '[data-pop]')).toBeNull();
    });

    it('multi: stays open when the consumer re-renders the bar with new values, even if focus drops', async () => {
        const el = make();
        await open(el, 'multi');
        el.addEventListener('filterchange', (e) => {
            el.values = { ...el.values, [e.detail.key]: e.detail.value };
        });
        change(q(el, 'lightning-checkbox-group'), { value: ['a'] });
        await flush();
        await tick();
        expect(q(el, '[data-pop]')).not.toBeNull();
        expect(trig(el, 'multi').textContent.trim()).toBe('Multi: A');
        q(el, '[data-pop]').blur();
        q(el, '.gtm-filter-bar').dispatchEvent(ev(FocusEvent, 'focusout', { relatedTarget: null }));
        await tick();
        await tick();
        change(q(el, 'lightning-checkbox-group'), { value: ['a', 'b'] });
        await flush();
        await tick();
        expect(q(el, '[data-pop]')).not.toBeNull();
        expect(trig(el, 'multi').textContent.trim()).toBe('Multi: 2');
    });

    it('Tab/focus landing on an element outside the wrapper closes it without stealing focus', async () => {
        const el = make();
        await open(el, 'multi');
        const spy = jest.spyOn(trig(el, 'multi'), 'focus');
        q(el, '[data-pop]').blur();
        q(el, '.gtm-filter-bar').dispatchEvent(ev(FocusEvent, 'focusout', { relatedTarget: document.body }));
        await tick();
        expect(q(el, '[data-pop]')).toBeNull();
        expect(spy).not.toHaveBeenCalled();
    });
});

describe('gtmFilterBar parent re-render with NEW config/values identities (Assessments-only defect)', () => {
    const cfg = () => buildFilterConfig(['Offer A', 'Offer B'], []);

    it('keeps child option/value identities and the popover across parent re-renders with equal content', async () => {
        const el = make({ filters: cfg(), values: { status: ['new'] } });
        await open(el, 'status');
        const group = q(el, 'lightning-checkbox-group');
        const optsBefore = group.options;
        const valBefore = group.value;
        el.filters = cfg(); // parent re-render: new array, new objects, same content
        el.values = { status: ['new'] };
        await flush();
        await tick();
        const after = q(el, 'lightning-checkbox-group');
        expect(after).toBe(group); // same element, not re-created
        expect(after.options).toBe(optsBefore); // base component gets no new options to re-render
        expect(after.value).toBe(valBefore);
        expect(q(el, '[data-pop]')).not.toBeNull();
    });

    it('a parent re-render between click and change does not lose the change (checkbox and radio)', async () => {
        const el = make({ filters: cfg(), values: {} });
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        await open(el, 'status');
        const group = q(el, 'lightning-checkbox-group');
        const opts = group.options;
        group.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, composed: true }));
        el.filters = cfg(); // parent churn during the interaction
        el.values = {};
        await flush();
        group.dispatchEvent(new MouseEvent('click', { bubbles: true, composed: true }));
        el.filters = cfg();
        await flush();
        expect(q(el, 'lightning-checkbox-group')).toBe(group);
        expect(q(el, 'lightning-checkbox-group').options).toBe(opts);
        change(group, { value: ['new'] });
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ key: 'status', value: ['new'] });

        await open(el, 'status'); // close
        await open(el, 'range');
        const radio = q(el, 'lightning-radio-group');
        const ropts = radio.options;
        el.filters = cfg();
        await flush();
        expect(q(el, 'lightning-radio-group')).toBe(radio);
        expect(q(el, 'lightning-radio-group').options).toBe(ropts);
    });
});

describe('gtmFilterBar Tab-away to a sibling control inside the bar', () => {
    const fo = (el, rel) =>
        q(el, '.gtm-filter-bar').dispatchEvent(new FocusEvent('focusout', { bubbles: true, composed: true, relatedTarget: rel }));

    it('focus landing on a sibling trigger closes the open popover and does not steal focus', async () => {
        const el = make({ values: { single: 'p' } });
        await open(el, 'multi');
        const spy = jest.spyOn(trig(el, 'multi'), 'focus');
        fo(el, trig(el, 'single'));
        await tick();
        expect(q(el, '[data-pop]')).toBeNull();
        expect(spy).not.toHaveBeenCalled();
    });

    it('focus landing on the Clear filters button closes it', async () => {
        const el = make({ values: { single: 'p' } });
        await open(el, 'multi');
        fo(el, q(el, 'lightning-button'));
        await tick();
        expect(q(el, '[data-pop]')).toBeNull();
    });

    it('does NOT close for a null relatedTarget, the popover itself, its content, or its own trigger', async () => {
        const el = make();
        await open(el, 'multi');
        fo(el, null);
        fo(el, q(el, '[data-pop]'));
        fo(el, q(el, 'lightning-checkbox-group'));
        fo(el, trig(el, 'multi'));
        await tick();
        expect(q(el, '[data-pop]')).not.toBeNull();
    });

    it('does not close during the pointerdown flag window (an inside click)', async () => {
        const el = make();
        await open(el, 'multi');
        q(el, 'lightning-checkbox-group').dispatchEvent(new MouseEvent('mousedown', { bubbles: true, composed: true }));
        fo(el, trig(el, 'single'));
        await tick(); // flag cleared only after the click completes or 500 ms
        expect(q(el, '[data-pop]')).not.toBeNull();
    });
});

describe('gtmFilterBar addable More filters (Addendum C.2)', () => {
    const CFG = [
        { key: 'p', label: 'Primary', type: 'chips', multi: true, param: 'c__p', options: [{ value: 'x', label: 'X' }, { value: 'y', label: 'Y' }] },
        { key: 'a', label: 'Alpha', type: 'chips', multi: true, param: 'c__a', more: true, options: [{ value: 'a1', label: 'A1' }, { value: 'a2', label: 'A2' }] },
        { key: 'b', label: 'Beta', type: 'toggle', param: 'c__b', more: true },
        { key: 'c', label: 'Gamma', type: 'chips', param: 'c__c', more: true, options: [{ value: 'g1', label: 'G1' }, { value: 'g2', label: 'G2' }] }
    ];
    const KEY = 'gtm.filterbar.added.t';
    const slots = (el) => qa(el, 'button.gtm-filter-bar__trigger').map((b) => b.dataset.slot);
    const stored = () => JSON.parse(localStorage.getItem(KEY));

    beforeEach(() => localStorage.clear());
    afterEach(() => {
        jest.restoreAllMocks();
        localStorage.clear();
    });

    // Real pointer sequence on a checkbox inside the More popover.
    async function realTick(el, key, checked) {
        const box = q(el, `lightning-input[data-key="${key}"]`);
        const wrapper = q(el, '.gtm-filter-bar');
        const pop = q(el, '[data-pop]');
        const e = (T, type, init = {}) => new T(type, { bubbles: true, composed: true, ...init });
        box.dispatchEvent(e(MouseEvent, 'pointerdown'));
        box.dispatchEvent(e(MouseEvent, 'mousedown'));
        wrapper.dispatchEvent(e(FocusEvent, 'focusout', { relatedTarget: pop }));
        box.dispatchEvent(e(MouseEvent, 'mouseup'));
        box.dispatchEvent(e(MouseEvent, 'click'));
        change(box, { checked });
        wrapper.dispatchEvent(e(FocusEvent, 'focusout', { relatedTarget: null }));
        await flush();
        await tick();
    }

    it('row = primaries; More (n) counts what is hidden and lists the extras as a checklist', async () => {
        const el = make({ filters: CFG, storageKey: 't' });
        expect(slots(el)).toEqual(['p', '__more__']);
        expect(trig(el, '__more__').textContent.trim()).toBe('More (3)');
        expect(trig(el, '__more__').getAttribute('aria-label')).toBe('More (3) filters, 3 not shown, 0 added');
        await open(el, '__more__');
        expect(q(el, '[role="dialog"]').getAttribute('aria-label')).toBe('Add filters');
        expect(q(el, '[role="group"][aria-label="Add filters"]')).not.toBeNull();
        expect(qa(el, '.gtm-filter-bar__additem lightning-input').map((n) => n.label)).toEqual(['Alpha', 'Beta', 'Gamma']);
        expect(qa(el, '.gtm-filter-bar__additem lightning-input').every((n) => n.checked === false)).toBe(true);
    });

    it('ticking a filter adds its button, opens its popover with focus inside, closes More (real event order)', async () => {
        const el = make({ filters: CFG, storageKey: 't' });
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        await open(el, '__more__');
        const focus = jest.spyOn(HTMLElement.prototype, 'focus');
        await realTick(el, 'a', true);
        await tick();
        expect(slots(el)).toEqual(['p', 'a', '__more__']);
        expect(trig(el, 'a').getAttribute('aria-expanded')).toBe('true');
        expect(trig(el, '__more__').getAttribute('aria-expanded')).toBe('false');
        expect(qa(el, '[data-pop]').length).toBe(1);
        expect(q(el, '[data-pop]').getAttribute('aria-label')).toBe('Alpha');
        expect(focus).toHaveBeenCalled();
        expect(handler).not.toHaveBeenCalled(); // an empty filter changes no values
        expect(trig(el, '__more__').textContent.trim()).toBe('More (2)');
        expect(stored()).toEqual(['a']);
    });

    it('the auto-opened popover survives the retargeted document click and a null-relatedTarget focusout', async () => {
        const el = make({ filters: CFG, storageKey: 't' });
        await open(el, '__more__');
        await realTick(el, 'b', true);
        document.body.dispatchEvent(new MouseEvent('click', { bubbles: true })); // an unrelated click AFTER is outside
        q(el, '.gtm-filter-bar').dispatchEvent(new MouseEvent('click', { bubbles: true, composed: true }));
        await tick();
        expect(trig(el, 'b')).not.toBeNull();
    });

    it('More disappears when nothing is hidden', async () => {
        const el = make({ filters: CFG, storageKey: 't' });
        await open(el, '__more__');
        await realTick(el, 'a', true);
        await open(el, '__more__');
        await realTick(el, 'b', true);
        await open(el, '__more__');
        await realTick(el, 'c', true);
        await tick();
        expect(slots(el)).toEqual(['p', 'a', 'b', 'c']);
        expect(trig(el, '__more__')).toBeNull();
    });

    it('a deep-linked value always shows its button, checked and disabled ("In use") in the list', async () => {
        const el = make({ filters: CFG, values: { a: ['a1'] }, storageKey: 't' });
        expect(slots(el)).toEqual(['p', 'a', '__more__']);
        await open(el, '__more__');
        const [alpha] = qa(el, '.gtm-filter-bar__additem lightning-input');
        expect(alpha.checked).toBe(true);
        expect(alpha.disabled).toBe(true);
        expect(q(el, '.gtm-filter-bar__inuse').textContent).toBe('In use');
        expect(stored()).toBeNull(); // an implicit add alone never writes
    });

    it('Clear filters clears values but keeps the added button', async () => {
        const el = make({ filters: CFG, values: { a: ['a1'] }, storageKey: 't' });
        const clear = jest.fn();
        el.addEventListener('clear', clear);
        q(el, 'lightning-button').dispatchEvent(new CustomEvent('click'));
        expect(clear).toHaveBeenCalledTimes(1);
        el.values = {}; // the consumer's answer to clear
        await flush();
        expect(slots(el)).toEqual(['p', 'a', '__more__']);
    });

    it('Clear filters resets transient popover state after a rapid open/close sequence', async () => {
        const el = make({ filters: CFG, values: { a: ['a1'] }, storageKey: 't' });
        const triggers = () => el.shadowRoot.querySelectorAll('button[data-slot]');
        for (let i = 0; i < 6; i++) {
            triggers()[0].click();
            await Promise.resolve();
        }
        q(el, 'lightning-button').dispatchEvent(new CustomEvent('click'));
        await flush();
        expect(el.shadowRoot.querySelector('[data-pop]')).toBeNull();
        // a fresh open still works and can be closed again
        triggers()[0].click();
        await flush();
        expect(el.shadowRoot.querySelector('[data-pop]')).not.toBeNull();
        triggers()[0].click();
        await flush();
        expect(el.shadowRoot.querySelector('[data-pop]')).toBeNull();
    });

    it('the x on a filter with a value emits one empty filterchange (never clear), removes and forgets it', async () => {
        const el = make({ filters: CFG, values: { a: ['a1'] }, storageKey: 't' });
        localStorage.setItem(KEY, JSON.stringify(['a', 'zzz']));
        el.storageKey = ''; // force reload path
        el.storageKey = 't';
        const handler = jest.fn();
        const clear = jest.fn();
        el.addEventListener('filterchange', handler);
        el.addEventListener('clear', clear);
        const x = q(el, 'lightning-button-icon[data-key="a"]');
        expect(x.alternativeText).toBe('Remove Alpha filter');
        expect(x.iconName).toBe('utility:close');
        x.dispatchEvent(new CustomEvent('click'));
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ key: 'a', value: [] });
        expect(clear).not.toHaveBeenCalled();
        el.values = {};
        await flush();
        expect(slots(el)).toEqual(['p', '__more__']);
        expect(stored()).toEqual(['zzz']); // forgotten, unknown key preserved
    });

    it('the x on an empty added filter emits nothing, and focus returns to More', async () => {
        localStorage.setItem(KEY, JSON.stringify(['b']));
        const el = make({ filters: CFG, storageKey: 't' });
        expect(slots(el)).toEqual(['p', 'b', '__more__']);
        const handler = jest.fn();
        el.addEventListener('filterchange', handler);
        const spy = jest.spyOn(trig(el, '__more__'), 'focus');
        q(el, 'lightning-button-icon[data-key="b"]').dispatchEvent(new CustomEvent('click'));
        await flush();
        await flush();
        expect(handler).not.toHaveBeenCalled();
        expect(slots(el)).toEqual(['p', '__more__']);
        expect(spy).toHaveBeenCalled();
    });

    it('primary filters have no x', () => {
        const el = make({ filters: CFG, storageKey: 't' });
        expect(q(el, 'lightning-button-icon')).toBeNull();
    });

    it('unticking an added, empty filter removes and forgets it; unknown keys are ignored but kept', async () => {
        localStorage.setItem(KEY, JSON.stringify(['gone', 'a']));
        const el = make({ filters: CFG, storageKey: 't' });
        expect(slots(el)).toEqual(['p', 'a', '__more__']);
        expect(trig(el, '__more__').textContent.trim()).toBe('More (2)');
        await open(el, '__more__');
        change(q(el, 'lightning-input[data-key="a"]'), { checked: false });
        await flush();
        expect(slots(el)).toEqual(['p', '__more__']);
        expect(stored()).toEqual(['gone']);
    });
});

describe('gtmFilterBar remembered filters and storage failures', () => {
    const CFG = [
        { key: 'p', label: 'Primary', type: 'toggle', param: 'c__p' },
        { key: 'a', label: 'Alpha', type: 'toggle', param: 'c__a', more: true },
        { key: 'b', label: 'Beta', type: 'toggle', param: 'c__b', more: true }
    ];
    const slots = (el) => qa(el, 'button.gtm-filter-bar__trigger').map((b) => b.dataset.slot);
    beforeEach(() => localStorage.clear());
    afterEach(() => {
        jest.restoreAllMocks();
        localStorage.clear();
    });

    it('restores remembered added filters on load, per storage key', () => {
        localStorage.setItem('gtm.filterbar.added.pages', JSON.stringify(['b']));
        localStorage.setItem('gtm.filterbar.added.assessments', JSON.stringify(['a']));
        expect(slots(make({ filters: CFG, storageKey: 'pages' }))).toEqual(['p', 'b', '__more__']);
        expect(slots(make({ filters: CFG, storageKey: 'assessments' }))).toEqual(['p', 'a', '__more__']);
        expect(slots(make({ filters: CFG }))).toEqual(['p', '__more__']); // no key: no memory
    });

    it('bad JSON, a non-array, non-string entries and a huge list render normally', () => {
        localStorage.setItem('gtm.filterbar.added.t', '{not json');
        expect(slots(make({ filters: CFG, storageKey: 't' }))).toEqual(['p', '__more__']);
        localStorage.setItem('gtm.filterbar.added.t', '{"a":1}');
        expect(slots(make({ filters: CFG, storageKey: 't' }))).toEqual(['p', '__more__']);
        localStorage.setItem('gtm.filterbar.added.t', JSON.stringify([1, null, 'b']));
        expect(slots(make({ filters: CFG, storageKey: 't' }))).toEqual(['p', 'b', '__more__']);
    });

    it('a throwing localStorage renders normally and adds still work; the in-memory map remembers', async () => {
        jest.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
            throw new Error('SecurityError');
        });
        jest.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
            throw new Error('QuotaExceeded');
        });
        const el = make({ filters: CFG, storageKey: 'blocked' });
        expect(slots(el)).toEqual(['p', '__more__']);
        await open(el, '__more__');
        change(q(el, 'lightning-input[data-key="a"]'), { checked: true });
        await flush();
        expect(slots(el)).toEqual(['p', 'a', '__more__']);
        // A re-created bar (page step change) gets it back from the module-level map.
        expect(slots(make({ filters: CFG, storageKey: 'blocked' }))).toEqual(['p', 'a', '__more__']);
    });

    it('stores only filter KEYS, capped at 20', async () => {
        const many = Array.from({ length: 25 }, (_, i) => ({ key: `k${i}`, label: `K${i}`, type: 'toggle', param: `c__k${i}`, more: true }));
        const el = make({ filters: [{ key: 'p', label: 'P', type: 'toggle', param: 'c__p' }, ...many], values: { k0: true }, storageKey: 'cap' });
        for (let i = 1; i < 25; i++) {
            await open(el, '__more__');
            change(q(el, `lightning-input[data-key="k${i}"]`), { checked: true });
            await flush();
            await tick();
        }
        const list = JSON.parse(localStorage.getItem('gtm.filterbar.added.cap'));
        expect(list.length).toBe(20);
        expect(list.every((k) => typeof k === 'string' && /^k\d+$/.test(k))).toBe(true);
    });
});

describe('gtmFilterBar placement (Addendum C.1)', () => {
    it('packs the cluster to the right and anchors popovers right', () => {
        const el = make();
        expect(q(el, '.gtm-filter-bar').classList.contains('slds-grid_align-end')).toBe(true);
        const css = fs.readFileSync(path.join(__dirname, '..', 'gtmFilterBar.css'), 'utf8');
        expect(css).toMatch(/\.gtm-filter-bar__pop\s*\{[^}]*right:\s*0/);
        expect(css).not.toMatch(/margin-left:\s*auto/);
    });

    it('the one-shot clamp shifts a right-anchored popover back inside the viewport', async () => {
        const el = make();
        Object.defineProperty(document.documentElement, 'clientWidth', { value: 300, configurable: true });
        const rect = jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({ left: 100, right: 340, top: 0, bottom: 0, width: 240, height: 0 });
        await open(el, 'multi');
        expect(q(el, '[data-pop]').style.right).toBe('48px');
        rect.mockRestore();
        Object.defineProperty(document.documentElement, 'clientWidth', { value: 0, configurable: true });
    });
});

describe('gtmFilterBar hides no-choice filters and shows option hints', () => {
    const one = { key: 'one', label: 'One', type: 'chips', multi: true, param: 'c__one', options: [{ value: 'a', label: 'A' }] };
    const none = { key: 'none', label: 'None', type: 'chips', multi: true, param: 'c__none', options: [] };
    const two = { key: 'two', label: 'Two', type: 'chips', multi: true, param: 'c__two', options: [{ value: 'a', label: 'A' }, { value: 'b', label: 'B' }] };
    const oneMore = { ...one, key: 'onem', label: 'OneMore', param: 'c__onem', more: true };
    const slots = (el) => qa(el, 'button.gtm-filter-bar__trigger').map((b) => b.dataset.slot);

    it('a filter with one or no option is not rendered (row or More list)', async () => {
        const el = make({ filters: [one, none, two, oneMore], values: {} });
        expect(slots(el)).toEqual(['two']); // no More either: its only member has no choice
    });

    it('a deep-linked value still shows the single-option filter button', () => {
        const el = make({ filters: [one, two], values: { one: ['a'] } });
        expect(slots(el)).toEqual(['one', 'two']);
        expect(trig(el, 'one').textContent.trim()).toBe('One: A');
    });

    it('toggles and date ranges are always offered', () => {
        const el = make({ filters: [{ key: 't', label: 'T', type: 'toggle', param: 'c__t' }, { key: 'd', label: 'D', type: 'date-range', param: 'c__d' }] });
        expect(slots(el)).toEqual(['t', 'd']);
    });

    it('an option hint shows in the list label after the name and before the count, not in the trigger', async () => {
        const el = make({
            filters: [{ key: 's', label: 'S', type: 'chips', param: 'c__s', options: [
                { value: 'q', label: 'Quiet', hint: 'started, not submitted', count: 2 },
                { value: 'p', label: 'Plain', count: 1 }
            ] }],
            values: { s: 'q' }
        });
        expect(trig(el, 's').textContent.trim()).toBe('S: Quiet');
        await open(el, 's');
        expect(q(el, 'lightning-radio-group').options.map((o) => o.label)).toEqual([
            'Quiet: started, not submitted (2)', 'Plain (1)'
        ]);
    });
});

describe('gtmFilterBar static source', () => {
    it('CSS: only #747474, no custom properties or container queries; JS: no ResizeObserver', () => {
        const css = fs.readFileSync(path.join(__dirname, '..', 'gtmFilterBar.css'), 'utf8');
        const hexes = css.match(/#[0-9a-fA-F]{3,8}\b/g) || [];
        expect(hexes.every((h) => h.toLowerCase() === '#747474')).toBe(true);
        expect(css).not.toMatch(/@container/);
        // Only the one density token family may be referenced, always with a fallback.
        const vars = css.match(/var\(--[a-z-]+/g) || [];
        expect(vars.every((v) => v.startsWith('var(--gtm-control-'))).toBe(true);
        expect(css).toMatch(/--gtm-control-h:\s*32px/);
        expect(css).toMatch(/max\(24px,\s*var\(--gtm-control-h,\s*32px\)\)/);
        expect(css).toMatch(/min-width:\s*0/);
        expect(css).toMatch(/max-width:\s*calc\(100vw - 1rem\)/);
        expect(css).toMatch(/max-height:\s*14rem/);
        const js = fs.readFileSync(path.join(__dirname, '..', 'gtmFilterBar.js'), 'utf8');
        expect(js).not.toMatch(/ResizeObserver/);
    });
});


describe('gtmFilterBar serverSearch filters (additive: filtersearch event)', () => {
    const SERVER = [
        {
            key: 'account', label: 'Account', type: 'chips', multi: true, param: 'c__aacct',
            searchable: true, serverSearch: true,
            options: [{ value: '001A', label: 'Acme' }, { value: '001B', label: 'Beta' }]
        }
    ];
    const search = (el, value) =>
        q(el, 'lightning-input[data-role="search"]').dispatchEvent(new CustomEvent('change', { detail: { value } }));

    it('is usable with no options, and a search emits filtersearch instead of narrowing client-side', async () => {
        const el = make({ filters: [{ ...SERVER[0], options: [] }] });
        expect(trig(el, 'account')).not.toBeNull();
        el.filters = SERVER;
        await flush();
        await open(el, 'account');
        const handler = jest.fn();
        el.addEventListener('filtersearch', handler);
        search(el, 'zzz');
        await flush();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ key: 'account', value: 'zzz' });
        // Options are the consumer's to narrow: nothing is hidden client-side.
        expect(q(el, 'lightning-checkbox-group').options.map((o) => o.value)).toEqual(['001A', '001B']);
    });

    it('a filter without serverSearch never emits filtersearch and still narrows client-side', async () => {
        const el = make({ filters: [{ ...SERVER[0], serverSearch: false }] });
        await open(el, 'account');
        const handler = jest.fn();
        el.addEventListener('filtersearch', handler);
        search(el, 'acm');
        await flush();
        expect(handler).not.toHaveBeenCalled();
        expect(q(el, 'lightning-checkbox-group').options.map((o) => o.value)).toEqual(['001A']);
    });
});
