import { createElement } from 'lwc';
import OfferingChooser from 'c/offeringChooser';
import getPageLayout from '@salesforce/apex/GtmPageContentReader.getPageLayout';
import getOfferingTiles from '@salesforce/apex/GtmPageContentReader.getOfferingTiles';
import getSiteInfo from '@salesforce/apex/GtmPageContentReader.getSiteInfo';

jest.mock(
    '@salesforce/apex/GtmPageContentReader.getPageLayout',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentReader.getOfferingTiles',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentReader.getSiteInfo',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('c/gtmPageLayouts', () => ({ FRAMEWORK_KEY: 'framework' }), { virtual: true });

const LIVE_TILES = [
    { offeringKey: 'migration-accelerator', name: 'Migration Accelerator', mark: 'MA', description: 'desc', isLive: true }
];

const PLACEHOLDER_TILES = [
    { offeringKey: 'future-offering', name: 'Future', mark: 'F', description: 'soon', isLive: false }
];

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function createEl() {
    return createElement('c-offering-chooser', { is: OfferingChooser });
}

beforeEach(() => {
    getPageLayout.mockResolvedValue({ content: {} });
    getSiteInfo.mockResolvedValue({ orgUrl: 'https://test.my.salesforce.com', lightningUrl: '', sites: [] });
    getOfferingTiles.mockResolvedValue(LIVE_TILES);
    delete window.location;
    window.location = { search: '' };
});

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
});

describe('cfgId forwarding in offering tile hrefs', () => {
    it('appends cfgId to live tile hrefs when present in URL', async () => {
        window.location = { search: '?cfgId=tok42' };

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const liveTiles = el.shadowRoot.querySelectorAll('a.tile.live');
        expect(liveTiles.length).toBeGreaterThan(0);
        liveTiles.forEach((a) => {
            expect(a.href).toContain('cfgId=tok42');
        });
    });

    it('does not append cfgId to tile hrefs when absent from URL', async () => {
        window.location = { search: '' };

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const liveTiles = el.shadowRoot.querySelectorAll('a.tile.live');
        expect(liveTiles.length).toBeGreaterThan(0);
        liveTiles.forEach((a) => {
            expect(a.href).not.toContain('cfgId');
        });
    });

    it('placeholder tiles have no href regardless of cfgId', async () => {
        window.location = { search: '?cfgId=tok42' };
        getOfferingTiles.mockResolvedValue(PLACEHOLDER_TILES);

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        // Placeholder tiles render as <a class="tile soon"> with no href attribute
        const soonTiles = el.shadowRoot.querySelectorAll('a.tile.soon');
        soonTiles.forEach((a) => {
            // An <a> without href renders href as empty string or the current document URL
            // The component sets href: undefined for placeholders, so it should not contain cfgId
            expect(a.getAttribute('href')).toBeFalsy();
        });
    });
});

describe('?offering= forwarding in offering tile hrefs (B11 amendment §1b)', () => {
    it('appends this tile\'s own offeringKey as ?offering= on the live tile href', async () => {
        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const liveTiles = el.shadowRoot.querySelectorAll('a.tile.live');
        expect(liveTiles.length).toBeGreaterThan(0);
        liveTiles.forEach((a) => {
            expect(a.href).toContain(`offering=${encodeURIComponent(LIVE_TILES[0].offeringKey)}`);
        });
    });

    it('forwards both ?offering= and &cfgId= together when both are present', async () => {
        window.location = { search: '?cfgId=tok42' };

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const liveTiles = el.shadowRoot.querySelectorAll('a.tile.live');
        liveTiles.forEach((a) => {
            expect(a.href).toContain('offering=migration-accelerator');
            expect(a.href).toContain('cfgId=tok42');
        });
    });
});

describe('empty state when no tiles are configured (B11 §3 item 3)', () => {
    it('shows "No offerings are configured yet" instead of a hardcoded Migration Accelerator tile', async () => {
        getOfferingTiles.mockResolvedValue([]);

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        expect(el.shadowRoot.textContent).toContain('No offerings are configured yet');
        expect(el.shadowRoot.querySelectorAll('a.tile').length).toBe(0);
    });
});
