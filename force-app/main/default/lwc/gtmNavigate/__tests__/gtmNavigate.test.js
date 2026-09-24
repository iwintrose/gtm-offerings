import { NavigationMixin } from 'lightning/navigation';
import {
    engagementLinkRef, assessmentRef, openEngagementLink, openAssessment, openReadout
} from 'c/gtmNavigate';

function host() {
    const h = {};
    h[NavigationMixin.Navigate] = jest.fn();
    return h;
}

describe('c/gtmNavigate', () => {
    it('engagement link with account and contact uses the Pages drill-in deep link', () => {
        const h = host();
        expect(openEngagementLink(h, 'a0X1', '001A', '003C')).toBe(true);
        expect(h[NavigationMixin.Navigate]).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Pages' },
            state: { c__rlfLinkId: 'a0X1', c__rlfAccountId: '001A', c__rlfContactId: '003C', cfgId: 'a0X1' }
        });
    });

    it('engagement link with no account opens by link id alone', () => {
        expect(engagementLinkRef('a0X1', '', '003C').state).toEqual(
            { c__template: 'link', c__recordId: 'a0X1', cfgId: 'a0X1' });
    });

    it('engagement link with an account but no contact also opens by link id', () => {
        expect(engagementLinkRef('a0X1', '001A', undefined).state.c__template).toBe('link');
    });

    it('never produces a record page reference', () => {
        [engagementLinkRef('a0X1', '001A', '003C'), engagementLinkRef('a0X1'),
            assessmentRef('a1Y', 'a2R', 'ma')].forEach((r) => {
            expect(r.type).toBe('standard__navItemPage');
        });
    });

    it('missing link id does not navigate', () => {
        const h = host();
        expect(openEngagementLink(h, '', '001A', '003C')).toBe(false);
        expect(h[NavigationMixin.Navigate]).not.toHaveBeenCalled();
    });

    it('assessment opens the workspace with optional readout and offering', () => {
        const h = host();
        openAssessment(h, 'a1Y', 'a2R', 'migration-accelerator');
        expect(h[NavigationMixin.Navigate]).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: { c__assessmentRequestId: 'a1Y', c__readoutId: 'a2R', c__offeringKey: 'migration-accelerator' }
        });
        expect(assessmentRef('a1Y').state).toEqual({ c__assessmentRequestId: 'a1Y' });
        expect(assessmentRef('')).toBeNull();
    });

    it('a readout opens its parent assessment focused; without the parent it does nothing', () => {
        const h = host();
        expect(openReadout(h, 'a2R', 'a1Y', 'ma')).toBe(true);
        expect(h[NavigationMixin.Navigate].mock.calls[0][0].state.c__readoutId).toBe('a2R');
        expect(openReadout(h, 'a2R', '', 'ma')).toBe(false);
        expect(h[NavigationMixin.Navigate]).toHaveBeenCalledTimes(1);
    });

    // issue-102-1-engagement-links-landing, D7 + acceptance criterion 4: the
    // new "Open the readout" forward action's standalone-mode navigation
    // must carry a rider so the destination workspace lands on the Readout
    // tab, not the Assessment tab (gtmReadoutWorkspace's refinement #3
    // default). openReadout() (the pre-existing "View readout" list action)
    // is deliberately left unchanged -- refinement #3 explicitly keeps that
    // origin defaulting to Assessment.
    it('assessment with focusReadout=true adds the c__focusReadoutTab rider alongside the readout id', () => {
        expect(assessmentRef('a1Y', 'a2R', 'ma', true).state).toEqual({
            c__assessmentRequestId: 'a1Y',
            c__readoutId: 'a2R',
            c__focusReadoutTab: '1',
            c__offeringKey: 'ma'
        });
    });

    it('focusReadout is ignored without a readout id -- no rider with nothing to focus on', () => {
        expect(assessmentRef('a1Y', null, 'ma', true).state).toEqual({
            c__assessmentRequestId: 'a1Y',
            c__offeringKey: 'ma'
        });
    });

    it('openAssessment threads focusReadout through to the navigation state', () => {
        const h = host();
        openAssessment(h, 'a1Y', 'a2R', 'ma', true);
        expect(h[NavigationMixin.Navigate]).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Assessments' },
            state: {
                c__assessmentRequestId: 'a1Y',
                c__readoutId: 'a2R',
                c__focusReadoutTab: '1',
                c__offeringKey: 'ma'
            }
        });
    });
});
