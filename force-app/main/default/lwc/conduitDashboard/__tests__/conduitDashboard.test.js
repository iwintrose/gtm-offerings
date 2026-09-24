import { createElement } from 'lwc';
import ConduitDashboard from 'c/conduitDashboard';

describe('c-conduit-dashboard', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders all six child views inside a scoped tabset', () => {
        const element = createElement('c-conduit-dashboard', { is: ConduitDashboard });
        document.body.appendChild(element);

        const tabset = element.shadowRoot.querySelector('lightning-tabset');
        expect(tabset).not.toBeNull();
        expect(tabset.variant).toBe('scoped');

        expect(element.shadowRoot.querySelector('c-conduit-audience-view')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-conduit-asset-explorer')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-conduit-gap-detail')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-conduit-migration-plan')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-conduit-rationalization')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-conduit-audit-history')).not.toBeNull();
    });

    it('forwards its own recordId to every child view', () => {
        const element = createElement('c-conduit-dashboard', { is: ConduitDashboard });
        element.recordId = 'a0X000000000001';
        document.body.appendChild(element);

        const childSelectors = [
            'c-conduit-audience-view',
            'c-conduit-asset-explorer',
            'c-conduit-gap-detail',
            'c-conduit-migration-plan',
            'c-conduit-rationalization',
            'c-conduit-audit-history'
        ];
        childSelectors.forEach((selector) => {
            const child = element.shadowRoot.querySelector(selector);
            expect(child.recordId).toBe('a0X000000000001');
        });
    });

    it('has no recordId set by default', () => {
        const element = createElement('c-conduit-dashboard', { is: ConduitDashboard });
        document.body.appendChild(element);

        expect(element.recordId).toBeUndefined();
    });
});
