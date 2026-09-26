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

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function createEl() {
    return createElement('c-choose-industry', { is: ChooseIndustry });
}

beforeEach(() => {
    getPageLayout.mockResolvedValue({ content: {} });
    getSiteInfo.mockResolvedValue({ orgUrl: 'https://test.my.salesforce.com', lightningUrl: '', sites: [] });
    getIndustryProfiles.mockResolvedValue([]);
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

describe('chooseIndustry brand pass', () => {
    it('injects the corrected Lexend Deca/Roboto/Roboto Mono Google Fonts link, not Inter/IBM Plex', async () => {
        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const link = document.querySelector('link[data-gtm-fonts="1"]');
        expect(link).not.toBeNull();
        expect(link.href).toContain('fonts.googleapis.com/css2');
        expect(link.href).toContain('family=Lexend+Deca');
        expect(link.href).toContain('family=Roboto');
        expect(link.href).toContain('family=Roboto+Mono');
        expect(link.href).not.toContain('Inter');
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

    it('stamps the shared --ps-* brand tokens (correct red, correct fonts) onto its root element', async () => {
        const el = createEl();
        document.body.appendChild(el);
        await flushPromises();

        const root = el.shadowRoot.querySelector('.ci-root');
        expect(root.style.getPropertyValue('--ps-red')).toBe('#e90130');
        expect(root.style.getPropertyValue('--ps-font-display')).toContain('Lexend Deca');
        expect(root.style.getPropertyValue('--ps-font-body')).toContain('Roboto');
        expect(root.style.getPropertyValue('--ps-font-mono')).toContain('Roboto Mono');
    });
});
