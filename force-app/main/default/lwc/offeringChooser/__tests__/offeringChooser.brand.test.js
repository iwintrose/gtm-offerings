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

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function createEl() {
    return createElement('c-offering-chooser', { is: OfferingChooser });
}

beforeEach(() => {
    getPageLayout.mockResolvedValue({ content: {} });
    getSiteInfo.mockResolvedValue({ orgUrl: 'https://test.my.salesforce.com', lightningUrl: '', sites: [] });
    getOfferingTiles.mockResolvedValue([]);
    delete window.location;
    window.location = { search: '' };
    document.querySelectorAll('link[data-gtm-fonts="1"]').forEach((l) => l.remove());
});

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
    document.querySelectorAll('link[data-gtm-fonts="1"]').forEach((l) => l.remove());
    jest.clearAllMocks();
});

describe('offeringChooser brand pass', () => {
    it('injects the Inter Google Fonts link, not the old Sora/IBM Plex request', async () => {
        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const link = document.querySelector('link[data-gtm-fonts="1"]');
        expect(link).not.toBeNull();
        expect(link.href).toContain('fonts.googleapis.com/css2');
        expect(link.href).toContain('family=Inter');
        expect(link.href).not.toContain('Sora');
        expect(link.href).not.toContain('IBM+Plex');
    });

    it('only injects the font link once even if connected twice', async () => {
        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const el2 = createEl();
        document.body.appendChild(el2);
        await flushPromises();

        expect(document.querySelectorAll('link[data-gtm-fonts="1"]').length).toBe(1);
    });

    it('renders the wordmark as two-tone "publicis"/"sapient" spans', async () => {
        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const black = el.shadowRoot.querySelector('.bar-wm .wm-black');
        const red = el.shadowRoot.querySelector('.bar-wm .wm-red');
        expect(black).not.toBeNull();
        expect(red).not.toBeNull();
        expect(black.textContent.trim()).toBe('Publicis');
        expect(red.textContent.trim()).toBe('Sapient');
    });
});
