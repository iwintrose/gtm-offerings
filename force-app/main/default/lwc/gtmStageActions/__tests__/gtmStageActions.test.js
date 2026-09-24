/**
 * Issue #slds-button-audit-p2 — gtmStageActions button markup.
 *
 * Verifies:
 *  - The action rail renders SLDS button classes (slds-button + variant
 *    modifier) instead of raw custom-CSS-only buttons.
 *  - Exactly one slds-button_brand action is present per rendered panel
 *    (the true "Send to client" primary action on the Draft stage), all
 *    other actions use slds-button_neutral.
 */
import { createElement } from 'lwc';
import GtmStageActions from 'c/gtmStageActions';
import getStageContext from '@salesforce/apex/GtmStageActionsController.getStageContext';

jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const navigateMock = jest.fn();
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](...args) { navigateMock(...args); }
        };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, __navigateMock: navigateMock };
});
const { __navigateMock: mockNavigate } = require('lightning/navigation');
jest.mock(
    '@salesforce/apex/GtmStageActionsController.getStageContext',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmStageActionsController.advanceStage',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const { registerApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
const getStageContextAdapter = registerApexTestWireAdapter(getStageContext);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-gtm-stage-actions', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders exactly one slds-button_brand action on the Draft stage rail', async () => {
        const el = createElement('c-gtm-stage-actions', { is: GtmStageActions });
        el.configId = 'a01000000000001';
        el.isConfigManager = true;
        document.body.appendChild(el);

        getStageContextAdapter.emit({ stage: 'Draft', requesterName: 'Acme Co' });
        await flushPromises();

        const brandButtons = el.shadowRoot.querySelectorAll('.slds-button_brand');
        expect(brandButtons.length).toBe(1);
        expect(brandButtons[0].textContent.trim()).toBe('Send to client');

        const neutralButtons = el.shadowRoot.querySelectorAll('.slds-button_neutral');
        expect(neutralButtons.length).toBeGreaterThan(0);
        neutralButtons.forEach((btn) => {
            expect(btn.classList.contains('slds-button_brand')).toBe(false);
        });
    });

    it('View assessment opens the assessment workspace, not the AR record page', async () => {
        const el = createElement('c-gtm-stage-actions', { is: GtmStageActions });
        el.configId = 'a01000000000001';
        el.isConfigManager = true;
        document.body.appendChild(el);
        getStageContextAdapter.emit({ stage: 'Draft', assessmentId: 'a0Q000000000009' });
        await flushPromises();

        expect(el.shadowRoot.querySelector('a[href*="/lightning/r/"]')).toBeNull();
        const btn = [...el.shadowRoot.querySelectorAll('button')]
            .find((b) => b.textContent.trim() === 'View assessment');
        expect(btn).toBeTruthy();
        btn.click();
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: { c__assessmentRequestId: 'a0Q000000000009' }
        });
    });
});
