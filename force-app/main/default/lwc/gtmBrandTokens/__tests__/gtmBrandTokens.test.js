import { BRAND_TOKENS_CSS, injectBrandTokens, applyNotch } from 'c/gtmBrandTokens';

function makeHost() {
    const el = document.createElement('div');
    document.body.appendChild(el);
    return el;
}

function setSize(el, width, height) {
    Object.defineProperty(el, 'offsetWidth', { value: width, configurable: true });
    Object.defineProperty(el, 'offsetHeight', { value: height, configurable: true });
}

function countMatches(str, re) {
    return (str.match(re) || []).length;
}

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
});

describe('BRAND_TOKENS_CSS', () => {
    it('contains the correct red and the retired wrong red nowhere', () => {
        expect(BRAND_TOKENS_CSS).toContain('#e90130');
        expect(BRAND_TOKENS_CSS.toLowerCase()).not.toContain('#e90024');
        expect(BRAND_TOKENS_CSS).not.toContain('#E4002B');
    });

    it('declares the corrected type stack and never the retired fonts', () => {
        expect(BRAND_TOKENS_CSS).toContain('Lexend Deca');
        expect(BRAND_TOKENS_CSS).toContain('Roboto Mono');
        expect(BRAND_TOKENS_CSS).toContain('"Roboto"');
        expect(BRAND_TOKENS_CSS).not.toContain('Inter');
        expect(BRAND_TOKENS_CSS).not.toContain('IBM Plex');
    });

    it('carries no dark-mode mechanism at all', () => {
        expect(BRAND_TOKENS_CSS).not.toContain('prefers-color-scheme');
        expect(BRAND_TOKENS_CSS).not.toContain('.dark');
        expect(BRAND_TOKENS_CSS).not.toContain('.light');
    });

    it('is a single :host block', () => {
        expect(BRAND_TOKENS_CSS.trim().startsWith(':host {')).toBe(true);
        expect(countMatches(BRAND_TOKENS_CSS, /:host/g)).toBe(1);
    });
});

describe('injectBrandTokens', () => {
    it('stamps every --ps-* token onto the host element as an inline custom property', () => {
        const host = makeHost();
        injectBrandTokens(host);
        expect(host.style.getPropertyValue('--ps-red')).toBe('#e90130');
        expect(host.style.getPropertyValue('--ps-font-body')).toContain('Roboto');
        expect(host.style.getPropertyValue('--ps-font-mono')).toContain('Roboto Mono');
        expect(host.style.getPropertyValue('--ps-font-display')).toContain('Lexend Deca');
    });

    it('only applies once per host, matching the data-gtm-fonts="1" dedup pattern', () => {
        const host = makeHost();
        injectBrandTokens(host);
        // Simulate a consumer/downstream override after first injection.
        host.style.setProperty('--ps-red', '#123456');
        injectBrandTokens(host);
        // A second call must not clobber the override -- proves it returned
        // early rather than re-running the full stamp.
        expect(host.style.getPropertyValue('--ps-red')).toBe('#123456');
    });

    it('is a no-op, not a throw, for a null or malformed host', () => {
        expect(() => injectBrandTokens(null)).not.toThrow();
        expect(() => injectBrandTokens({})).not.toThrow();
    });
});

describe('applyNotch', () => {
    it('clips the host to a per-instance SVG clipPath sized from its measured box', () => {
        const host = makeHost();
        setSize(host, 220, 140);
        applyNotch(host, 'tr');

        expect(host.style.clipPath).toMatch(/^url\(#ps-notch-\d+\)$/);
        const path = host.querySelector('clipPath path');
        expect(path).not.toBeNull();
        const d = path.getAttribute('d');
        // Every arc here is axis-aligned (x-axis-rotation 0) and a single
        // quarter-turn (large-arc-flag 0), so "A rx,ry 0 0 <sweep>" isolates
        // just the sweep flag without also matching the literal 0s that
        // precede it (a plain " 0 0 "/" 0 1 " substring search would double
        // count against the x-axis-rotation/large-arc-flag zeros).
        // Two convex corners (sweep 1) and exactly one concave bite (sweep 0).
        expect(countMatches(d, /A \d+,\d+ 0 0 1 /g)).toBe(2);
        expect(countMatches(d, /A \d+,\d+ 0 0 0 /g)).toBe(1);
        // The concave arc's radius is the (larger) notch radius, not the
        // (smaller) plain corner radius used by the two convex arcs.
        expect(d).toContain('A 28,28 0 0 0');
        expect(countMatches(d, /A 16,16 0 0 1/g)).toBe(2);
    });

    it('re-measures in place on repeat calls instead of creating a second clipPath', () => {
        const host = makeHost();
        setSize(host, 220, 140);
        applyNotch(host, 'tr');
        setSize(host, 320, 200);
        applyNotch(host, 'tr');

        expect(host.querySelectorAll('svg').length).toBe(1);
        expect(host.querySelectorAll('clipPath').length).toBe(1);
        const d = host.querySelector('clipPath path').getAttribute('d');
        expect(d).toContain('320'); // re-measured to the new width
    });

    it('updates the clip when the corner argument changes', () => {
        const host = makeHost();
        setSize(host, 220, 140);
        applyNotch(host, 'tr');
        const firstD = host.querySelector('clipPath path').getAttribute('d');
        applyNotch(host, 'bl');
        const secondD = host.querySelector('clipPath path').getAttribute('d');
        expect(secondD).not.toBe(firstD);
    });

    it('is a no-op for an unlaid-out element (zero measured size)', () => {
        const host = makeHost();
        setSize(host, 0, 0);
        applyNotch(host, 'tr');
        expect(host.style.clipPath).toBe('');
        expect(host.querySelector('svg')).toBeNull();
    });

    it('is a no-op, not a throw, for an invalid corner or missing host', () => {
        const host = makeHost();
        setSize(host, 220, 140);
        expect(() => applyNotch(host, 'middle')).not.toThrow();
        expect(host.style.clipPath).toBe('');
        expect(() => applyNotch(null, 'tr')).not.toThrow();
    });
});
