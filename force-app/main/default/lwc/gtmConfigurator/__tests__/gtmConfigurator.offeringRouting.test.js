import { createElement } from 'lwc';
import GtmConfigurator from 'c/gtmConfigurator';
import checkPasswordRequired from '@salesforce/apex/GtmLinkAuthController.checkPasswordRequired';
import getPublicConfiguration from '@salesforce/apex/GtmConfigurationReader.getPublicConfiguration';

// B11 amendment §1b/§3b: effectiveOfferingKey's three-tier resolution
// (linkOfferingKey from a saved record -> ?offering= URL param -> page-level
// offeringKey), and §1's "not configured" empty state when none of the three
// resolve. Also covers the gtmConfigWizard/questionnaire prop wiring that
// depends on effectiveOfferingKey (gtmConfigurator.html lines ~461/523).

jest.mock(
    '@salesforce/apex/GtmViewerContext.isRep',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmLinkAuthController.checkPasswordRequired',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmConfigurationReader.getPublicConfiguration',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// eslint-disable-next-line import/no-unresolved
const isRep = require('@salesforce/apex/GtmViewerContext.isRep').default;

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function createEl() {
    return createElement('c-gtm-configurator', { is: GtmConfigurator });
}

async function mount(el) {
    document.body.appendChild(el);
    isRep.emit(false);
    await flushPromises();
    await flushPromises();
}

describe('c-gtm-configurator — effectiveOfferingKey three-tier resolution (B11)', () => {
    beforeEach(() => {
        checkPasswordRequired.mockResolvedValue(false);
        getPublicConfiguration.mockResolvedValue(null);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.history.pushState({}, '', '/');
        jest.clearAllMocks();
    });

    it('shows the unconfigured notice when no tier resolves at all', async () => {
        const element = createEl();
        await mount(element);

        const notice = element.shadowRoot.querySelector('.unconfigured-notice');
        expect(notice).not.toBeNull();
        expect(notice.textContent).toContain("hasn't been configured yet");
        const wizard = element.shadowRoot.querySelector('c-gtm-config-wizard');
        expect(wizard.offeringKey).toBe('');
    });

    // B12: the unconfigured notice must be the ONLY thing rendered -- no
    // marketing chapter body (progress bar, CRM strip, chapter sections,
    // footer) should render underneath it.
    it('renders ONLY the unconfigured notice -- no chapter body -- when no tier resolves', async () => {
        const element = createEl();
        await mount(element);

        expect(element.shadowRoot.querySelector('.unconfigured-notice')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.chap.cover')).toBeNull();
        expect(element.shadowRoot.querySelector('.crm-strip')).toBeNull();
        expect(element.shadowRoot.querySelector('.progress')).toBeNull();
        expect(element.shadowRoot.querySelector('footer.pf')).toBeNull();
    });

    it('renders the chapter body normally once an offering resolves (page-level default)', async () => {
        const element = createEl();
        element.offeringKey = 'second-offering';
        await mount(element);

        expect(element.shadowRoot.querySelector('.unconfigured-notice')).toBeNull();
        expect(element.shadowRoot.querySelector('.progress')).not.toBeNull();
        expect(element.shadowRoot.querySelector('footer.pf')).not.toBeNull();
    });

    it('renders the chapter body normally once an offering resolves (?offering= param)', async () => {
        window.history.pushState({}, '', '/?offering=second-offering');
        const element = createEl();
        await mount(element);

        expect(element.shadowRoot.querySelector('.unconfigured-notice')).toBeNull();
        expect(element.shadowRoot.querySelector('.progress')).not.toBeNull();
        expect(element.shadowRoot.querySelector('footer.pf')).not.toBeNull();
    });

    it('renders the chapter body normally once an offering resolves (cfgId saved record)', async () => {
        window.history.pushState({}, '', '/?cfgId=a0X000000000001');
        getPublicConfiguration.mockResolvedValue({ offering: 'third-offering' });
        const element = createEl();
        await mount(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.unconfigured-notice')).toBeNull();
        expect(element.shadowRoot.querySelector('.progress')).not.toBeNull();
        expect(element.shadowRoot.querySelector('footer.pf')).not.toBeNull();
    });

    it('resolves from the page-level offeringKey design attribute when set and nothing else overrides it', async () => {
        const element = createEl();
        element.offeringKey = 'second-offering';
        await mount(element);

        expect(element.shadowRoot.querySelector('.unconfigured-notice')).toBeNull();
        const wizard = element.shadowRoot.querySelector('c-gtm-config-wizard');
        expect(wizard.offeringKey).toBe('second-offering');
    });

    it('a ?offering= URL param wins over the page-level default when no saved record resolves', async () => {
        window.history.pushState({}, '', '/?offering=second-offering');
        const element = createEl();
        element.offeringKey = 'migration-accelerator';
        await mount(element);

        expect(element.shadowRoot.querySelector('.unconfigured-notice')).toBeNull();
        const wizard = element.shadowRoot.querySelector('c-gtm-config-wizard');
        expect(wizard.offeringKey).toBe('second-offering');
    });

    it('a cfgId-resolved saved record\'s own offering wins over both the URL param and the page default', async () => {
        window.history.pushState({}, '', '/?offering=second-offering&cfgId=a0X000000000001');
        getPublicConfiguration.mockResolvedValue({ offering: 'third-offering' });
        const element = createEl();
        element.offeringKey = 'migration-accelerator';
        await mount(element);
        await flushPromises();

        const wizard = element.shadowRoot.querySelector('c-gtm-config-wizard');
        expect(wizard.offeringKey).toBe('third-offering');
    });

    it('never silently resolves to Migration Accelerator when no key was ever provided', async () => {
        // Scoped to identity (offeringKey/document.title), not display copy --
        // the page's built-in marketing content (hero copy, section text) is
        // B12's separate, lower-priority display-fallback scope, not this
        // provisioning-identity ticket's.
        const element = createEl();
        await mount(element);

        const wizard = element.shadowRoot.querySelector('c-gtm-config-wizard');
        expect(wizard.offeringKey).not.toBe('migration-accelerator');
        expect(document.title).not.toContain('Migration Accelerator');
    });

    it('passes effectiveOfferingKey (not the raw page-level offeringKey) into c-gtm-config-wizard', async () => {
        window.history.pushState({}, '', '/?offering=second-offering');
        const element = createEl();
        element.offeringKey = 'migration-accelerator';
        await mount(element);

        const wizard = element.shadowRoot.querySelector('c-gtm-config-wizard');
        expect(wizard).not.toBeNull();
        expect(wizard.offeringKey).toBe('second-offering');
    });

    // issue-pages-preview-fixes, Bug 1: gtmConfigWizard._measureChromeOffset
    // reads host.getBoundingClientRect().top + window.scrollY, which only
    // resolves to the Salesforce chrome height at any scroll position when
    // the wizard is mounted as the literal first child of this component's
    // root container -- mirroring gtmOverview.html's own "KEEP THIS FIRST"
    // wizard mount. Confirmed here rather than relying on visual/manual QA
    // alone, since this bites specifically when gtmConfigurator is rendered
    // nested inside another component's preview pane (e.g. gtmRepLinkFinder's
    // Pages tab preview), where a regression would be easy to miss in a
    // top-level render.
    it('mounts c-gtm-config-wizard as the first child of its root container', async () => {
        const element = createEl();
        await mount(element);

        const root = element.shadowRoot.firstElementChild;
        expect(root).not.toBeNull();
        expect(root.firstElementChild).not.toBeNull();
        expect(root.firstElementChild.tagName.toLowerCase()).toBe('c-gtm-config-wizard');
    });
});
