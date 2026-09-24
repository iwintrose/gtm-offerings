/**
 * gtmPageBrowser's CurrentPageReference state fork -- the existing Story
 * deep-link case, plus the new "link" deep link case (issue #99-done-nav)
 * added for the wizard's Done button (gtmOverview.handleWizardDone), which
 * routes gtmRepLinkFinder straight to the just-saved record.
 */
const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) => {
        return class extends Base {
            [Navigate](...args) {
                mockNavigate(...args);
            }
        };
    };
    NavigationMixin.Navigate = Navigate;
    const { createTestWireAdapter } = jest.requireActual('@salesforce/wire-service-jest-util');
    return {
        NavigationMixin,
        CurrentPageReference: createTestWireAdapter(jest.fn())
    };
});

// eslint-disable-next-line import/first
import { createElement } from 'lwc';
// eslint-disable-next-line import/first
import { CurrentPageReference } from 'lightning/navigation';
// eslint-disable-next-line import/first
import GtmPageBrowser from 'c/gtmPageBrowser';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-gtm-page-browser: CurrentPageReference state fork', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('with no state, shows the default "find a link you sent" mode', async () => {
        const element = createElement('c-gtm-page-browser', { is: GtmPageBrowser });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: {} });
        await flushPromises();

        // The header bar is now the shared c-gtm-page-header (issue B14), so
        // its own title/meta text lives in a separate shadow tree -- assert
        // on the custom element's props instead of shadowRoot.textContent.
        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header).not.toBeNull();
        expect(header.title).toBe('Find a link you sent');
        expect(element.shadowRoot.querySelector('c-gtm-story')).toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-rep-link-finder')).not.toBeNull();
    });

    it('c__template=story routes to the Story (existing precedent, unchanged)', async () => {
        const element = createElement('c-gtm-page-browser', { is: GtmPageBrowser });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__template: 'story', c__offering: 'migration-accelerator' } });
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-story')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-gtm-rep-link-finder')).toBeNull();
    });

    it('c__template=link with a record id routes gtmRepLinkFinder straight to that record', async () => {
        const element = createElement('c-gtm-page-browser', { is: GtmPageBrowser });
        document.body.appendChild(element);
        CurrentPageReference.emit({
            state: {
                c__template: 'link',
                c__recordId: 'a0X000000000099',
                c__company: 'Acme Corp',
                c__offering: 'migration-accelerator'
            }
        });
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-gtm-story')).toBeNull();
        const finder = element.shadowRoot.querySelector('c-gtm-rep-link-finder');
        expect(finder).not.toBeNull();
        expect(finder.targetRecordId).toBe('a0X000000000099');
        expect(finder.targetCompany).toBe('Acme Corp');
        expect(finder.targetOfferingKey).toBe('migration-accelerator');
    });

    it('c__template=link with no record id falls back to the default (unaffected) mode', async () => {
        const element = createElement('c-gtm-page-browser', { is: GtmPageBrowser });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__template: 'link' } });
        await flushPromises();

        const finder = element.shadowRoot.querySelector('c-gtm-rep-link-finder');
        expect(finder).not.toBeNull();
        expect(finder.targetRecordId).toBeFalsy();
    });

    it('c__template=browse (Overview\'s persistent nav button) lands on the default find-a-link mode', async () => {
        const element = createElement('c-gtm-page-browser', { is: GtmPageBrowser });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__template: 'browse' } });
        await flushPromises();

        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header).not.toBeNull();
        expect(header.title).toBe('Find a link you sent');
        expect(element.shadowRoot.querySelector('c-gtm-story')).toBeNull();
        const finder = element.shadowRoot.querySelector('c-gtm-rep-link-finder');
        expect(finder).not.toBeNull();
        expect(finder.targetRecordId).toBeFalsy();
    });

    it('c__template=browse resets stale link-mode state from a prior visit', async () => {
        const element = createElement('c-gtm-page-browser', { is: GtmPageBrowser });
        document.body.appendChild(element);
        CurrentPageReference.emit({
            state: { c__template: 'link', c__recordId: 'a0X000000000099', c__company: 'Acme Corp' }
        });
        await flushPromises();
        CurrentPageReference.emit({ state: { c__template: 'browse' } });
        await flushPromises();

        const finder = element.shadowRoot.querySelector('c-gtm-rep-link-finder');
        expect(finder.targetRecordId).toBeFalsy();
        expect(finder.targetCompany).toBeFalsy();
    });
});

describe('c-gtm-page-browser: shared header meta line and actions slot (issue B14b1)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('default mode: no back button in the actions slot, and a blank meta line (gtmRepLinkFinder now defaults to "All Pages")', async () => {
        const element = createElement('c-gtm-page-browser', { is: GtmPageBrowser });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: {} });
        await flushPromises();

        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header.meta).toBeFalsy();
        const back = element.shadowRoot.querySelector('lightning-button.pb-back');
        expect(back).toBeNull();
    });

    // Release 2 (Addendum C.9): the finder has no mode any more, so the header
    // subtitle no longer depends on a `modechange` event.
    it('default mode: no modechange binding; the meta line stays blank whatever the finder does', async () => {
        const element = createElement('c-gtm-page-browser', { is: GtmPageBrowser });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: {} });
        await flushPromises();

        const finder = element.shadowRoot.querySelector('c-gtm-rep-link-finder');
        finder.dispatchEvent(new CustomEvent('modechange', { detail: 'account' }));
        await flushPromises();

        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header.meta).toBeFalsy();
    });

    it('story mode: meta names the offering, and the back button is slotted into the header', async () => {
        const element = createElement('c-gtm-page-browser', { is: GtmPageBrowser });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__template: 'story', c__offering: 'migration-accelerator' } });
        await flushPromises();

        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header.meta).toBe('Offering: migration-accelerator');
        const back = element.shadowRoot.querySelector('lightning-button.pb-back');
        expect(back).not.toBeNull();
        expect(back.getAttribute('slot')).toBe('actions');
        expect(back.label).toBe('Back to Pages');
    });

    it('link mode: meta names the company the link was generated for', async () => {
        const element = createElement('c-gtm-page-browser', { is: GtmPageBrowser });
        document.body.appendChild(element);
        CurrentPageReference.emit({
            state: {
                c__template: 'link',
                c__recordId: 'a0X000000000099',
                c__company: 'Acme Corp',
                c__offering: 'migration-accelerator'
            }
        });
        await flushPromises();

        const header = element.shadowRoot.querySelector('c-gtm-page-header');
        expect(header.meta).toBe('Just-generated link for Acme Corp');
        const back = element.shadowRoot.querySelector('lightning-button.pb-back');
        expect(back).not.toBeNull();
    });

    it('clicking the slotted back button still navigates to GTM_Pages', async () => {
        const element = createElement('c-gtm-page-browser', { is: GtmPageBrowser });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__template: 'story', c__offering: 'migration-accelerator' } });
        await flushPromises();

        element.shadowRoot.querySelector('lightning-button.pb-back').click();
        await flushPromises();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Pages' }
        });
    });
});
