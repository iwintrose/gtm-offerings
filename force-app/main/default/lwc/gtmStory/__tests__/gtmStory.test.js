import { createElement } from 'lwc';
import GtmStory from 'c/gtmStory';
import getPageLayout from '@salesforce/apex/GtmPageContentReader.getPageLayout';

jest.mock('@salesforce/apex/GtmPageContentReader.getPageLayout',
    () => ({ default: jest.fn() }), { virtual: true });

describe('c-gtm-story closing section', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders the closing section without the dead GTM_Accelerator1 CTA', async () => {
        getPageLayout.mockResolvedValue({ sections: [], content: {}, fieldMeta: [] });

        const element = createElement('c-gtm-story', { is: GtmStory });
        element.offeringKey = 'migration-accelerator';
        document.body.appendChild(element);

        await Promise.resolve();
        await Promise.resolve();

        // The CTA `<a class="btn">` that used to link to the now-permanently
        // unreachable GTM_Accelerator1 dark site must not be present anywhere
        // in the rendered output, nor should any leftover empty wrapper for it.
        expect(element.shadowRoot.querySelector('a.btn')).toBeNull();
        expect(element.shadowRoot.querySelector('.cta-line')).toBeNull();
        expect(element.acceleratorUrl).toBeUndefined();
    });
});
