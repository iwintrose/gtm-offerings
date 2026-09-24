import { createElement } from 'lwc';
import GtmColumnChooser from 'c/gtmColumnChooser';

const ASSESS = [
    { key: 'name', label: 'Assessment', default: true, pinned: true },
    { key: 'company', label: 'Company', default: true, pinned: false },
    { key: 'contact', label: 'Contact', default: false, pinned: false },
    { key: 'score', label: 'Score', default: false, pinned: false },
    { key: 'status', label: 'Status', default: true, pinned: false }
];
const PAGES = [
    { key: 'a', label: 'A', default: true },
    { key: 'b', label: 'B', default: true },
    { key: 'c', label: 'C', default: false }
];

const clone = (v) => JSON.parse(JSON.stringify(v));
const q = (el, sel) => el.shadowRoot.querySelector(sel);
const flush = () => Promise.resolve();
const tick = () => new Promise((r) => setTimeout(r, 5));
const trig = (el) => q(el, 'button[data-trigger]');
const group = (el) => q(el, 'lightning-checkbox-group');
const pop = (el) => q(el, '[data-pop]');
const change = (node, value) => node.dispatchEvent(new CustomEvent('change', { detail: { value } }));
const realClick = (node) => node.dispatchEvent(new MouseEvent('click', { bubbles: true, composed: true, cancelable: true }));

function make(props = {}) {
    const el = createElement('c-gtm-column-chooser', { is: GtmColumnChooser });
    Object.assign(el, { columns: clone(ASSESS), ...props });
    document.body.appendChild(el);
    return el;
}
const open = async (el) => {
    trig(el).click();
    await flush();
    await tick();
};

afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
});

describe('gtmColumnChooser trigger', () => {
    it('has the accessible name "Columns, N of M shown" and a live region outside the popover', async () => {
        const el = make();
        expect(trig(el).getAttribute('aria-label')).toBe('Columns, 3 of 5 shown');
        expect(trig(el).getAttribute('aria-haspopup')).toBe('dialog');
        expect(trig(el).getAttribute('aria-expanded')).toBe('false');
        const live = q(el, '[data-live]');
        expect(live.getAttribute('aria-live')).toBe('polite');
        expect(live.classList.contains('slds-assistive-text')).toBe(true);
        expect(live.closest('[data-pop]')).toBeNull();
        el.selectedKeys = ['name', 'contact', 'score', 'company', 'status'];
        await flush();
        expect(trig(el).getAttribute('aria-label')).toBe('Columns, 5 of 5 shown');
    });

    it('honours the label prop and defaults when selectedKeys is null', async () => {
        const el = make({ label: 'Fields', selectedKeys: null });
        expect(q(el, '.gtm-col-chooser__trigger-text').textContent).toBe('Fields');
        expect(trig(el).getAttribute('aria-label')).toBe('Fields, 3 of 5 shown');
    });

    it('opens on click, focuses the group and toggles closed on a second click', async () => {
        const el = make();
        const spy = jest.spyOn(HTMLElement.prototype, 'focus');
        await open(el);
        expect(trig(el).getAttribute('aria-expanded')).toBe('true');
        expect(pop(el).getAttribute('role')).toBe('dialog');
        expect(spy).toHaveBeenCalled();
        spy.mockRestore();
        trig(el).click();
        await flush();
        expect(pop(el)).toBeNull();
        expect(trig(el).getAttribute('aria-expanded')).toBe('false');
    });
});

describe('gtmColumnChooser content', () => {
    it('offers only non-pinned columns, with the pinned ones in an Always shown line', async () => {
        const el = make();
        await open(el);
        expect(group(el).options).toEqual([
            { label: 'Company', value: 'company' },
            { label: 'Contact', value: 'contact' },
            { label: 'Score', value: 'score' },
            { label: 'Status', value: 'status' }
        ]);
        expect(group(el).value).toEqual(['company', 'status']);
        expect(q(el, '[data-role="pinned"]').textContent).toBe('Always shown: Assessment');
    });

    it('omits the Always shown line when nothing is pinned', async () => {
        const el = make({ columns: clone(PAGES) });
        await open(el);
        expect(q(el, '[data-role="pinned"]')).toBeNull();
        expect(group(el).options.length).toBe(3);
    });

    it('is non-modal: no backdrop element and a focusable dialog fallback', async () => {
        const el = make();
        await open(el);
        expect(pop(el).getAttribute('tabindex')).toBe('-1');
        expect(pop(el).getAttribute('aria-label')).toBe('Choose columns');
        expect(q(el, '.slds-backdrop')).toBeNull();
    });

    it('falls back to focusing the dialog when the group cannot take focus', async () => {
        const el = make();
        const spy = jest.spyOn(HTMLElement.prototype, 'focus');
        await open(el);
        const targets = spy.mock.calls.map((c, i) => spy.mock.instances[i]);
        expect(targets.some((t) => t === pop(el) || t === group(el))).toBe(true);
        spy.mockRestore();
    });
});

describe('gtmColumnChooser changes', () => {
    it('a tick emits columnschange once, pinned included, in catalogue order (not tick order)', async () => {
        const el = make();
        const h = jest.fn();
        el.addEventListener('columnschange', h);
        await open(el);
        change(group(el), ['status', 'score', 'company']);
        expect(h).toHaveBeenCalledTimes(1);
        expect(h.mock.calls[0][0].detail).toEqual({ keys: ['name', 'company', 'score', 'status'] });
        expect(h.mock.calls[0][0].bubbles).toBe(false);
        expect(h.mock.calls[0][0].composed).toBe(false);
        await tick();
        expect(pop(el)).not.toBeNull(); // stays open across picks
    });

    it('an untick emits the reduced set; several picks in a row all apply with the popover open', async () => {
        const el = make();
        const h = jest.fn();
        el.addEventListener('columnschange', h);
        await open(el);
        change(group(el), ['company']);
        change(group(el), ['company', 'contact']);
        change(group(el), []);
        expect(h.mock.calls.map((c) => c[0].detail.keys)).toEqual([
            ['name', 'company'],
            ['name', 'company', 'contact'],
            ['name']
        ]);
        await tick();
        expect(pop(el)).not.toBeNull();
    });

    it('is controlled: it never mutates selectedKeys and reflects a new value from the parent', async () => {
        const el = make({ selectedKeys: ['name', 'contact'] });
        await open(el);
        expect(group(el).value).toEqual(['contact']);
        change(group(el), ['contact', 'score']);
        await flush();
        expect(el.selectedKeys).toEqual(['name', 'contact']);
        expect(group(el).value).toEqual(['contact']);
        el.selectedKeys = ['name', 'score'];
        await flush();
        expect(group(el).value).toEqual(['score']);
        expect(trig(el).getAttribute('aria-label')).toBe('Columns, 2 of 5 shown');
    });

    it('updates the live region on each change', async () => {
        const el = make();
        await open(el);
        change(group(el), ['company', 'score']);
        await flush();
        expect(q(el, '[data-live]').textContent).toBe('3 of 5 columns shown');
    });

    it('does not offer, and cannot hide, a pinned column through any event', async () => {
        const el = make();
        const h = jest.fn();
        el.addEventListener('columnschange', h);
        await open(el);
        expect(group(el).options.map((o) => o.value)).not.toContain('name');
        change(group(el), []); // a stray empty selection
        expect(h.mock.calls[0][0].detail.keys).toContain('name');
    });

    it('ignores unknown values coming from the group', async () => {
        const el = make();
        const h = jest.fn();
        el.addEventListener('columnschange', h);
        await open(el);
        change(group(el), ['bogus', 'score']);
        expect(h.mock.calls[0][0].detail.keys).toEqual(['name', 'score']);
    });
});

describe('gtmColumnChooser last-column guard', () => {
    it('ignores a change that would hide every column, shows a hint and recreates the group', async () => {
        const el = make({ columns: clone(PAGES), selectedKeys: ['a'] });
        const h = jest.fn();
        el.addEventListener('columnschange', h);
        await open(el);
        const before = group(el);
        change(before, []);
        await flush();
        expect(h).not.toHaveBeenCalled();
        expect(q(el, '[data-role="hint"]').textContent).toBe('At least one column must stay shown');
        expect(group(el)).not.toBe(before);
        expect(group(el).value).toEqual(['a']);
        expect(pop(el)).not.toBeNull();
    });

    it('clears the hint on the next valid change', async () => {
        const el = make({ columns: clone(PAGES), selectedKeys: ['a'] });
        await open(el);
        change(group(el), []);
        await flush();
        change(group(el), ['a', 'c']);
        await flush();
        expect(q(el, '[data-role="hint"]')).toBeNull();
    });

    it('does not recreate the group on a valid change', async () => {
        const el = make({ columns: clone(PAGES) });
        await open(el);
        const before = group(el);
        change(before, ['a']);
        await flush();
        expect(group(el)).toBe(before);
    });
});

describe('gtmColumnChooser Reset', () => {
    it('is disabled at the default and enabled otherwise', async () => {
        const el = make();
        await open(el);
        expect(q(el, '[data-role="reset"]').disabled).toBe(true);
        el.selectedKeys = ['name', 'company', 'score'];
        await flush();
        expect(q(el, '[data-role="reset"]').disabled).toBe(false);
    });

    it('emits the defaults (pinned included, catalogue order) and leaves the popover open', async () => {
        const el = make({ selectedKeys: ['name', 'score'] });
        const h = jest.fn();
        el.addEventListener('columnschange', h);
        await open(el);
        q(el, '[data-role="reset"]').click();
        await flush();
        expect(h).toHaveBeenCalledTimes(1);
        expect(h.mock.calls[0][0].detail).toEqual({ keys: ['name', 'company', 'status'] });
        await tick();
        expect(pop(el)).not.toBeNull();
    });

    it('moves focus into the popover when Reset becomes disabled', async () => {
        const el = make({ selectedKeys: ['name', 'score'] });
        await open(el);
        q(el, '[data-role="reset"]').click();
        const spy = jest.spyOn(HTMLElement.prototype, 'focus');
        el.selectedKeys = ['name', 'company', 'status']; // parent applies the emitted keys
        await flush();
        await flush();
        expect(spy).toHaveBeenCalled();
        spy.mockRestore();
    });
});

describe('gtmColumnChooser keyboard and focus', () => {
    it('Escape closes, stops propagation and returns focus to the trigger', async () => {
        const el = make();
        await open(el);
        const outer = jest.fn();
        document.body.addEventListener('keydown', outer);
        const spy = jest.spyOn(HTMLElement.prototype, 'focus');
        group(el).dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, composed: true }));
        await flush();
        expect(pop(el)).toBeNull();
        expect(spy.mock.instances).toContain(trig(el));
        expect(outer).not.toHaveBeenCalled();
        spy.mockRestore();
        document.body.removeEventListener('keydown', outer);
    });

    it('Escape while closed does nothing', async () => {
        const el = make();
        trig(el).dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, composed: true }));
        await flush();
        expect(pop(el)).toBeNull();
    });

    it('Tab-away to a real outside Element closes it', async () => {
        const el = make();
        await open(el);
        const outside = document.createElement('button');
        document.body.appendChild(outside);
        q(el, '.gtm-col-chooser').dispatchEvent(new FocusEvent('focusout', { bubbles: true, relatedTarget: outside }));
        await flush();
        expect(pop(el)).toBeNull();
    });

    it('focusout to null, to the document, to the trigger or inside the popover never closes it', async () => {
        const el = make();
        await open(el);
        const wrap = q(el, '.gtm-col-chooser');
        const fire = (relatedTarget) => wrap.dispatchEvent(new FocusEvent('focusout', { bubbles: true, relatedTarget }));
        fire(null);
        fire(document);
        fire(trig(el));
        fire(pop(el));
        fire(q(el, '[data-role="reset"]'));
        await tick();
        expect(pop(el)).not.toBeNull();
    });

    it('a focusout during an inside pointer interaction never closes it', async () => {
        const el = make();
        await open(el);
        const wrap = q(el, '.gtm-col-chooser');
        const outside = document.createElement('button');
        document.body.appendChild(outside);
        wrap.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
        wrap.dispatchEvent(new FocusEvent('focusout', { bubbles: true, relatedTarget: outside }));
        await flush();
        expect(pop(el)).not.toBeNull();
    });

    it('a focusout in the same interaction as the open does not close it', async () => {
        const el = make();
        realClick(trig(el));
        const outside = document.createElement('button');
        document.body.appendChild(outside);
        q(el, '.gtm-col-chooser').dispatchEvent(new FocusEvent('focusout', { bubbles: true, relatedTarget: outside }));
        await tick();
        await tick();
        expect(pop(el)).not.toBeNull();
    });
});

describe('gtmColumnChooser outside clicks and one-at-a-time', () => {
    it('the opening click never closes it; a later outside click closes it after a timeout, not synchronously', async () => {
        const el = make();
        realClick(trig(el));
        await tick();
        await tick();
        expect(pop(el)).not.toBeNull();
        realClick(document.body);
        expect(pop(el)).not.toBeNull(); // not synchronous
        await tick();
        expect(pop(el)).toBeNull();
    });

    it('opening another popover (document event) closes it; its own open does not', async () => {
        const el = make();
        await open(el);
        document.dispatchEvent(new CustomEvent('gtmpopoveropen', { detail: { source: {} } }));
        await flush();
        expect(pop(el)).toBeNull();
    });

    it('two choosers: opening one closes the other', async () => {
        const a = make();
        const b = make();
        await open(a);
        expect(pop(a)).not.toBeNull();
        await open(b);
        expect(pop(a)).toBeNull();
        expect(pop(b)).not.toBeNull();
    });

    it('opening dispatches the document event with the chooser as its source', async () => {
        const el = make();
        const h = jest.fn();
        document.addEventListener('gtmpopoveropen', h);
        trig(el).click();
        expect(h).toHaveBeenCalledTimes(1);
        document.removeEventListener('gtmpopoveropen', h);
    });
});

describe('gtmColumnChooser real event order (B.13.x regressions)', () => {
    // Emulates the Lightning runtime: a document click listener sees an event
    // retargeted to an OUTER host with an empty composedPath().
    let addSpy;
    let rmSpy;
    beforeEach(() => {
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

    it('a real click opens it and it stays open', async () => {
        const el = make();
        realClick(trig(el));
        await flush();
        await tick();
        expect(trig(el).getAttribute('aria-expanded')).toBe('true');
        expect(pop(el)).not.toBeNull();
    });

    it('a click INSIDE the popover (retargeted, empty composedPath) keeps it open and the change fires exactly once', async () => {
        const el = make();
        const h = jest.fn();
        el.addEventListener('columnschange', h);
        realClick(trig(el));
        await tick();
        const g = group(el);
        realClick(g);
        await flush();
        await flush();
        expect(g.isConnected).toBe(true);
        expect(pop(el)).not.toBeNull();
        change(g, ['company', 'score', 'status']); // activation behaviour: change AFTER click + microtasks
        expect(h).toHaveBeenCalledTimes(1);
        expect(h.mock.calls[0][0].detail.keys).toEqual(['name', 'company', 'score', 'status']);
        await tick();
        expect(pop(el)).not.toBeNull();
    });

    it('full pointer sequence (pointerdown, mousedown, focusout, focusin, mouseup, click) keeps it open', async () => {
        const el = make();
        realClick(trig(el));
        await tick();
        const wrap = q(el, '.gtm-col-chooser');
        const g = group(el);
        const outside = document.createElement('div');
        document.body.appendChild(outside);
        g.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true, composed: true }));
        g.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, composed: true }));
        wrap.dispatchEvent(new FocusEvent('focusout', { bubbles: true, relatedTarget: outside }));
        g.dispatchEvent(new FocusEvent('focusin', { bubbles: true }));
        wrap.dispatchEvent(new FocusEvent('focusout', { bubbles: true, relatedTarget: null }));
        g.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, composed: true }));
        realClick(g);
        await flush();
        await flush();
        expect(pop(el)).not.toBeNull();
        expect(g.isConnected).toBe(true);
    });

    it('Space/keydown inside marks an inside interaction (no close on the following click)', async () => {
        const el = make();
        realClick(trig(el));
        await tick();
        const g = group(el);
        g.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true, composed: true }));
        realClick(g);
        await flush();
        await flush();
        expect(pop(el)).not.toBeNull();
        expect(g.isConnected).toBe(true);
    });

    it('a later real outside click closes it, but not before an in-flight change', async () => {
        const el = make();
        const h = jest.fn();
        el.addEventListener('columnschange', h);
        realClick(trig(el));
        await tick();
        realClick(document.body);
        change(group(el), ['company', 'contact', 'status']); // change runs right after the click, same task
        expect(h).toHaveBeenCalledTimes(1);
        await tick();
        expect(pop(el)).toBeNull();
    });
});

describe('gtmColumnChooser stable identities under parent re-render', () => {
    it('equal-content columns and selectedKeys keep the same group, options and value references, and stay open', async () => {
        const el = make({ selectedKeys: ['name', 'company', 'score'] });
        await open(el);
        const g = group(el);
        const opts = g.options;
        const val = g.value;
        for (let i = 0; i < 3; i++) {
            el.columns = clone(ASSESS); // the parent's getter yields new arrays every render
            el.selectedKeys = ['name', 'company', 'score'];
            await flush();
        }
        expect(group(el)).toBe(g);
        expect(group(el).options).toBe(opts);
        expect(group(el).value).toBe(val);
        expect(pop(el)).not.toBeNull();
    });

    it('options keep identity across a tick while value legitimately changes', async () => {
        const el = make({ selectedKeys: ['name', 'company'] });
        await open(el);
        const opts = group(el).options;
        const val = group(el).value;
        el.selectedKeys = ['name', 'company', 'contact'];
        await flush();
        expect(group(el).options).toBe(opts);
        expect(group(el).value).not.toBe(val);
        expect(group(el).value).toEqual(['company', 'contact']);
    });

    it('a new catalogue updates the options and does not close the popover', async () => {
        const el = make();
        await open(el);
        const opts = group(el).options;
        el.columns = clone(ASSESS).concat([{ key: 'x', label: 'X', default: false, pinned: false }]);
        await flush();
        expect(group(el).options).not.toBe(opts);
        expect(group(el).options.length).toBe(5);
        expect(pop(el)).not.toBeNull();
    });
});

describe('gtmColumnChooser cleanup', () => {
    it('removes the document listeners and pending timers on disconnect', async () => {
        const rm = jest.spyOn(document, 'removeEventListener');
        const el = make();
        await open(el);
        document.body.removeChild(el);
        const types = rm.mock.calls.map((c) => c[0]);
        expect(types).toContain('click');
        expect(types).toContain('gtmpopoveropen');
        rm.mockRestore();
    });

    it('never attaches the document click listener when disconnected before the deferred attach', async () => {
        const add = jest.spyOn(document, 'addEventListener');
        const el = make();
        trig(el).click();
        document.body.removeChild(el);
        await tick();
        expect(add.mock.calls.filter((c) => c[0] === 'click').length).toBe(0);
        add.mockRestore();
    });
});
