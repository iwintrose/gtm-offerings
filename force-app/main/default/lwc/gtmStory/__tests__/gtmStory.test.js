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

describe('c-gtm-story layout primitives (issue #278 regression)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    // Jest/jsdom cannot verify the CSS rules for .boxed/.ps-grid/.ps-band*/.rv*
    // actually resolve to real declarations (that broke silently at issue #33
    // and shipped unnoticed, see docs/agent-artifacts/task-scope-278.md) -- but
    // it CAN guard against gtmStory.html/js drifting away from the class hooks
    // gtmStory.css's restored layout-primitives block depends on, which is the
    // next-cheapest regression to catch here. An empty getPageLayout response
    // falls back to DEFAULT_SECTIONS (gtmStory.js), which renders the real
    // default section set, same as the sibling test above.
    it('marks the root element with the ps-scope hook the layout primitives key off of', async () => {
        getPageLayout.mockResolvedValue({ sections: [], content: {}, fieldMeta: [] });

        const element = createElement('c-gtm-story', { is: GtmStory });
        element.offeringKey = 'migration-accelerator';
        document.body.appendChild(element);

        await Promise.resolve();
        await Promise.resolve();

        const root = element.shadowRoot.querySelector('.story-root');
        expect(root).not.toBeNull();
        expect(root.classList.contains('ps-scope')).toBe(true);
    });

    it('renders every default section wrapped in the .boxed .ps-grid primitive containers', async () => {
        getPageLayout.mockResolvedValue({ sections: [], content: {}, fieldMeta: [] });

        const element = createElement('c-gtm-story', { is: GtmStory });
        element.offeringKey = 'migration-accelerator';
        document.body.appendChild(element);

        await Promise.resolve();
        await Promise.resolve();

        const sections = element.shadowRoot.querySelectorAll('section');
        expect(sections.length).toBeGreaterThan(0);
        sections.forEach((section) => {
            expect(section.querySelector(':scope > .boxed.ps-grid')).not.toBeNull();
        });
    });
});
