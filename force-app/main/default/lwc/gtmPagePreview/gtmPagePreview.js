import { LightningElement, api, track } from 'lwc';

// Fixed device sizes, matching the two the design calls out. "full" is not in
// here because it is not a size: it is whatever the panel can give.
const DEVICES = {
    tablet: { w: 834, h: 1112 },
    phone: { w: 414, h: 896 }
};

const PAD_FLUID = 16;
const PAD_FIXED = 44;
const MIN_W = 320;
const MAX_W = 1920;

/**
 * The live preview column: the real page renderer inside a resizable canvas.
 *
 * The page is drawn at a true CSS width and then scaled, rather than being
 * squeezed into whatever space is left. That distinction is the whole point of
 * a device preview — a 414px-wide render tells you about the phone layout, a
 * squashed 414px-wide panel tells you about nothing. c/maStory carries
 * container queries so it responds to this frame rather than to the browser.
 */
export default class GtmPagePreview extends LightningElement {
    @api offeringKey = '';
    @api sections = [];
    @api content = {};
    @api fieldMeta = [];
    @api pageUrl = '';
    @api hasDrafts = false;

    // The section the editor has selected. Setting it scrolls the canvas.
    @api
    get activeKey() { return this._activeKey; }
    set activeKey(value) {
        const changed = value !== this._activeKey;
        this._activeKey = value;
        if (changed && value) this._pendingScroll = value;
    }

    @track devW = 1280;
    @track devH = 800;
    @track zoom = 'fit';
    @track fluid = true;
    @track scalePct = 100;

    _activeKey = '';
    _pendingScroll = '';
    _resizeObs;
    _driven = false;
    _drivenTimer;
    _suppress = false;
    _suppressTimer;
    _queued = false;

    // ─── head ─────────────────────────────────────────────────────────────────

    get stateLabel() { return this.hasDrafts ? 'Draft' : 'Live'; }
    get urlLabel() {
        const base = this.pageUrl || 'no public site';
        return this.hasDrafts ? `${base} · unpublished draft` : base;
    }
    get urlTitle() {
        return this.hasDrafts
            ? 'Showing your unpublished draft. The live page still has the last published version.'
            : 'This matches what is published.';
    }
    get zoomLabel() { return `${this.scalePct}%`; }
    get zoomDisabled() { return this.fluid; }
    get widthValue() { return this.devW; }

    get fullClass() { return this.fluid ? 'on' : ''; }
    get tabletClass() { return this.matches('tablet') ? 'on' : ''; }
    get phoneClass() { return this.matches('phone') ? 'on' : ''; }

    matches(name) {
        const d = DEVICES[name];
        return !this.fluid && d && d.w === this.devW && d.h === this.devH;
    }

    handleDevice(event) {
        const name = event.currentTarget.dataset.dev;
        if (name === 'full') {
            this.fluid = true;
        } else {
            const d = DEVICES[name];
            if (!d) return;
            this.fluid = false;
            this.devW = d.w;
            this.devH = d.h;
        }
        this.layout();
    }

    handleWidth(event) {
        const v = parseInt(event.target.value, 10);
        if (!(v >= MIN_W && v <= MAX_W)) return;
        this.fluid = false;
        this.devW = v;
        this.layout();
    }

    handleZoom(event) {
        this.zoom = event.target.value;
        this.layout();
    }

    // ─── canvas ───────────────────────────────────────────────────────────────

    avail() {
        const sc = this.template.querySelector('.pv-scroll');
        if (!sc) return null;
        const p = this.fluid ? PAD_FLUID : PAD_FIXED;
        return {
            w: Math.max(MIN_W, sc.clientWidth - p),
            h: Math.max(240, sc.clientHeight - p)
        };
    }

    currentScale() {
        // Fluid means "render at the panel's own width", so there is nothing to
        // scale: the page is already the size it is being shown at.
        if (this.fluid) return 1;
        if (this.zoom !== 'fit') return parseFloat(this.zoom);
        const a = this.avail();
        if (!a) return 1;
        return Math.max(0.12, Math.min(1, a.w / this.devW));
    }

    layout() {
        const sc = this.template.querySelector('.pv-scroll');
        const device = this.template.querySelector('.device');
        const slot = this.template.querySelector('.dev-slot');
        if (!sc || !device || !slot) return;

        sc.style.padding = this.fluid ? `${PAD_FLUID / 2}px` : '14px 22px';
        if (this.fluid) {
            const a = this.avail();
            if (a) { this.devW = Math.round(a.w); this.devH = Math.round(a.h); }
        }
        const k = this.currentScale();
        device.style.width = `${this.devW}px`;
        device.style.transform = `scale(${k})`;
        // A fixed device shows its own height so the frame reads as a device.
        // Fluid follows the content, because there is no device to imply.
        device.style.height = this.fluid ? 'auto' : `${this.devH}px`;
        // The page's viewport-height rules follow the frame, not the browser,
        // or a phone preview would open with a browser-tall hero.
        device.style.setProperty('--story-vh', `${this.devH}px`);

        // transform does not change layout, so the slot has to be told what the
        // scaled page now occupies or the canvas scrolls to the wrong height.
        const drawnH = this.fluid ? device.scrollHeight : this.devH;
        slot.style.width = `${Math.round(this.devW * k)}px`;
        slot.style.height = `${Math.round(drawnH * k)}px`;

        const pct = Math.round(k * 100);
        if (pct !== this.scalePct) this.scalePct = pct;
    }

    renderedCallback() {
        this.layout();
        if (this._pendingScroll) {
            const key = this._pendingScroll;
            this._pendingScroll = '';
            this.scrollTo(key);
        }
        if (this._resizeObs || typeof ResizeObserver === 'undefined') return;
        const sc = this.template.querySelector('.pv-scroll');
        const device = this.template.querySelector('.device');
        if (!sc || !device) return;
        // Two things change the fit: the panel resizing with the window, and
        // the page growing or shrinking as it is edited.
        this._resizeObs = new ResizeObserver(() => { this.layout(); });
        this._resizeObs.observe(sc);
        this._resizeObs.observe(device);
    }

    disconnectedCallback() {
        if (this._resizeObs) { this._resizeObs.disconnect(); this._resizeObs = undefined; }
        clearTimeout(this._drivenTimer);
        clearTimeout(this._suppressTimer);
        // A grip-drag left in progress when this component unmounts would
        // otherwise leave these listening on window forever, each closing
        // over stale DOM.
        if (this._gripMove) window.removeEventListener('pointermove', this._gripMove);
        if (this._gripUp) window.removeEventListener('pointerup', this._gripUp);
    }

    // ─── viewport grip ────────────────────────────────────────────────────────

    handleGripDown(event) {
        event.preventDefault();
        const x0 = event.clientX;
        const w0 = this.devW;
        const k = this.currentScale();
        if (this.fluid) {
            // Dragging the edge is a statement that you want a specific width,
            // so leaving fluid mode here is the point, not a side effect.
            const a = this.avail();
            this.fluid = false;
            if (a) this.devH = a.h;
        }
        const move = (ev) => {
            this.devW = Math.max(MIN_W, Math.min(MAX_W, Math.round(w0 + (ev.clientX - x0) / k)));
            this.layout();
        };
        const up = () => {
            window.removeEventListener('pointermove', move);
            window.removeEventListener('pointerup', up);
            this._gripMove = undefined;
            this._gripUp = undefined;
        };
        this._gripMove = move;
        this._gripUp = up;
        window.addEventListener('pointermove', move);
        window.addEventListener('pointerup', up);
    }

    // ─── scroll sync ──────────────────────────────────────────────────────────

    handleIntent() {
        this._driven = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        clearTimeout(this._drivenTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._drivenTimer = setTimeout(() => { this._driven = false; }, 1200);
    }

    handleScroll() {
        // Only a scroll the reader caused moves the rail. Typing re-renders the
        // page, which reflows it, which fires scroll — and treating that as
        // reading reassigned the selected section mid-keystroke.
        if (!this._driven || this._suppress || this._queued) return;
        this._queued = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => { this._queued = false; this.syncFromScroll(); });
    }

    rects() {
        const story = this.template.querySelector('c-ma-story');
        if (!story || typeof story.getSectionRects !== 'function') return [];
        return story.getSectionRects();
    }

    /**
     * Which element actually scrolls, which depends on the mode.
     *
     * Fluid renders the page at full height and the canvas scrolls it. A device
     * preset is a fixed window — a phone screen is 896px tall whatever the page
     * does — so the page scrolls inside the device and the canvas does not move
     * at all. Scrolling the wrong one is why selecting a section did nothing in
     * tablet and phone.
     *
     * The device is also the element carrying the scale transform, so its own
     * scrollTop is in unscaled pixels while getBoundingClientRect is in scaled
     * ones. The caller has to divide by the scale; the canvas needs no such
     * correction because it is not transformed.
     */
    scroller() {
        const device = this.template.querySelector('.device');
        const canvas = this.template.querySelector('.pv-scroll');
        if (!this.fluid && device) return { el: device, scaled: true };
        return { el: canvas, scaled: false };
    }

    syncFromScroll() {
        const { el: sc } = this.scroller();
        const rects = this.rects();
        if (!sc || !rects.length) return;

        // The last section can never cover the top of the canvas: the canvas
        // runs out of scroll while the one before it is still up there. At the
        // bottom, the last section is what you are looking at.
        // A phone frame is short enough that the last section often cannot
        // reach the top; at the end of the scroll it is what you are looking at.
        const atBottom = sc.scrollTop + sc.clientHeight >= sc.scrollHeight - 4;
        let current = atBottom ? rects[rects.length - 1].sectionKey : '';
        if (!current && sc.scrollTop <= 4) {
            // At the very top, the pinned masthead is what you are looking at.
            const pinned = rects.find((r) => r.pinned);
            if (pinned) current = pinned.sectionKey;
        }
        if (!current) {
            const top = sc.getBoundingClientRect().top;
            // Pinned elements are skipped: sitting at the top of the frame is
            // what they always do, so they would always win this test.
            rects.forEach((r) => {
                if (!r.pinned && r.top - top <= 24) current = r.sectionKey;
            });
        }
        if (current && current !== this._activeKey) {
            this._activeKey = current;
            this.dispatchEvent(new CustomEvent('sectionchange', { detail: { sectionKey: current } }));
        }
    }

    @api
    scrollTo(sectionKey) {
        const { el: sc, scaled } = this.scroller();
        if (!sc) return;
        const hit = this.rects().find((r) => r.sectionKey === sectionKey);
        const top = sc.getBoundingClientRect().top;
        // Rect deltas are post-transform; a scrolled element's own scrollTop is
        // not. Only the device carries the transform.
        const k = scaled ? (this.currentScale() || 1) : 1;
        // A pinned element — the masthead — is drawn at the top of the frame
        // whatever the scroll position, so its rect says nothing about where to
        // go. It lives at the top of the page, so that is where we go. The same
        // fallback covers a section with no rect at all.
        const target = (hit && !hit.pinned) ? sc.scrollTop + (hit.top - top) / k - 8 : 0;
        // A scroll this code started is not the reader scrolling. That matters
        // most for the last section, where the canvas cannot scroll far enough
        // to honour the request and parks somewhere the spy would misread.
        this._driven = false;
        this._suppress = true;
        sc.scrollTo({ top: Math.max(0, target), behavior: 'smooth' });
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        clearTimeout(this._suppressTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._suppressTimer = setTimeout(() => { this._suppress = false; }, 500);
    }
}
