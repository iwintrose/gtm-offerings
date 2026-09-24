import { createElement } from 'lwc';
import ChooseIndustry from 'c/chooseIndustry';
import getPageLayout from '@salesforce/apex/GtmPageContentReader.getPageLayout';
import getIndustryProfiles from '@salesforce/apex/GtmPageContentReader.getIndustryProfiles';
import getSiteInfo from '@salesforce/apex/GtmPageContentReader.getSiteInfo';

jest.mock(
    '@salesforce/apex/GtmPageContentReader.getPageLayout',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentReader.getIndustryProfiles',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmPageContentReader.getSiteInfo',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('c/gtmPageLayouts', () => ({ FRAMEWORK_KEY: 'framework' }), { virtual: true });

const INDUSTRIES = [
    { industryKey: 'financial-services', industryLabel: 'Financial Services' },
    { industryKey: 'health', industryLabel: 'Health' }
];

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function createEl() {
    return createElement('c-choose-industry', { is: ChooseIndustry });
}

beforeEach(() => {
    getPageLayout.mockResolvedValue({ content: {} });
    getSiteInfo.mockResolvedValue({ orgUrl: 'https://test.my.salesforce.com', lightningUrl: '', sites: [] });
    getIndustryProfiles.mockResolvedValue(INDUSTRIES);
    // Ensure window.location is replaceable in every test.
    delete window.location;
    window.location = { search: '' };
});

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
});

describe('cfgId forwarding in industry tile hrefs', () => {
    it('appends cfgId to each industry tile href when present in URL', async () => {
        window.location = { search: '?cfgId=abc123' };

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        // Industry tiles are <a class="tile"> inside the for:each loop
        const tiles = el.shadowRoot.querySelectorAll('a.tile:not(.skip)');
        expect(tiles.length).toBeGreaterThan(0);
        tiles.forEach((a) => {
            expect(a.href).toContain('cfgId=abc123');
            expect(a.href).toContain('wizard=1');
        });
    });

    it('does not append cfgId to industry tile hrefs when absent from URL', async () => {
        window.location = { search: '' };

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const tiles = el.shadowRoot.querySelectorAll('a.tile:not(.skip)');
        expect(tiles.length).toBeGreaterThan(0);
        tiles.forEach((a) => {
            expect(a.href).not.toContain('cfgId');
        });
    });
});

describe('cfgId forwarding in skipHref', () => {
    it('appends cfgId to skipHref when present in URL', async () => {
        window.location = { search: '?cfgId=skip99' };

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const skipLink = el.shadowRoot.querySelector('a.tile.skip');
        expect(skipLink).not.toBeNull();
        expect(skipLink.href).toContain('cfgId=skip99');
        expect(skipLink.href).toContain('wizard=1');
    });

    it('does not append cfgId to skipHref when absent from URL', async () => {
        window.location = { search: '' };

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const skipLink = el.shadowRoot.querySelector('a.tile.skip');
        expect(skipLink).not.toBeNull();
        expect(skipLink.href).not.toContain('cfgId');
        expect(skipLink.href).toContain('wizard=1');
    });
});

describe('?offering= forwarding (B11 amendment §1b)', () => {
    it('forwards the incoming ?offering= param on every industry tile href', async () => {
        window.location = { search: '?offering=second-offering' };

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const tiles = el.shadowRoot.querySelectorAll('a.tile:not(.skip)');
        expect(tiles.length).toBeGreaterThan(0);
        tiles.forEach((a) => {
            expect(a.href).toContain('offering=second-offering');
        });
    });

    it('forwards ?offering= on skipHref alongside cfgId', async () => {
        window.location = { search: '?offering=second-offering&cfgId=abc123' };

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const skipLink = el.shadowRoot.querySelector('a.tile.skip');
        expect(skipLink).not.toBeNull();
        expect(skipLink.href).toContain('offering=second-offering');
        expect(skipLink.href).toContain('cfgId=abc123');
    });

    it('omits ?offering= entirely when the incoming URL has none', async () => {
        window.location = { search: '' };

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const tiles = el.shadowRoot.querySelectorAll('a.tile:not(.skip)');
        tiles.forEach((a) => {
            expect(a.href).not.toContain('offering=');
        });
    });
});

describe('degraded state when getIndustryProfiles fails', () => {
    it('shows the retry error, not the empty note, on rejection', async () => {
        getIndustryProfiles.mockRejectedValue(new Error('callout failed'));
        const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        expect(el.shadowRoot.querySelectorAll('.tile-wrap').length).toBe(0);
        expect(el.shadowRoot.querySelector('.load-error').textContent).toContain('Please retry');
        expect(el.shadowRoot.querySelector('.empty-note')).toBeNull();
        expect(el.shadowRoot.querySelector('.tile.skip')).not.toBeNull();
        consoleSpy.mockRestore();
    });
});

describe('empty state when getIndustryProfiles resolves with no industries', () => {
    async function assertEmptyState() {
        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const note = el.shadowRoot.querySelector('.empty-note');
        expect(note).not.toBeNull();
        expect(note.textContent).toContain('No industries have been set up yet');
        expect(note.getAttribute('role')).toBe('status');
        expect(el.shadowRoot.querySelector('.load-error')).toBeNull();
        expect(el.shadowRoot.textContent).not.toMatch(/retry|could not be loaded|error/i);
        expect(el.shadowRoot.querySelectorAll('.tile-wrap').length).toBe(0);
        expect(el.shadowRoot.querySelector('.tile.skip')).not.toBeNull();
    }

    it('shows a neutral notice and no error on an empty array', async () => {
        getIndustryProfiles.mockResolvedValue([]);
        await assertEmptyState();
    });

    it('treats a resolved null the same as empty', async () => {
        getIndustryProfiles.mockResolvedValue(null);
        await assertEmptyState();
    });

    it('shows tiles and neither notice when industries exist', async () => {
        getIndustryProfiles.mockResolvedValue(INDUSTRIES);

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        expect(el.shadowRoot.querySelectorAll('.tile-wrap').length).toBe(2);
        expect(el.shadowRoot.querySelector('.empty-note')).toBeNull();
        expect(el.shadowRoot.querySelector('.load-error')).toBeNull();
        expect(el.shadowRoot.querySelector('.tile.skip')).not.toBeNull();
    });

    it('keeps the empty note when getPageLayout fails and overwrites _loadError', async () => {
        getIndustryProfiles.mockResolvedValue([]);
        getPageLayout.mockRejectedValue(new Error('layout failed'));
        const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        expect(el.shadowRoot.querySelector('.empty-note')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.load-error').textContent)
            .toContain('Page content could not be loaded');
        consoleSpy.mockRestore();
    });
});
