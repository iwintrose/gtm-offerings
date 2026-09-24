/**
 * One place for "open the working view, never a bare record page"
 * (docs/architecture/gtm-row-open-and-links.md).
 *
 *   - An engagement link (GTM_Saved_Configuration__c, SC-####) always opens the
 *     in-app Pages view (GTM_Pages tab, link detail).
 *   - An assessment (GTM_Assessment_Request__c, AR-####) always opens the
 *     Assessments tab readout workspace.
 *   - A readout (GTM_Readout__c) only exists inside an assessment, so it opens
 *     its parent assessment workspace with the readout focused.
 *
 * Each open* function takes the calling component (a NavigationMixin host) as
 * its first argument, since Navigate is a method of the host element.
 */
import { NavigationMixin } from 'lightning/navigation';

export const PAGES_TAB = 'GTM_Pages';
export const ASSESSMENTS_TAB = 'GTM_Assessments';

/** Page reference for the Pages view of one engagement link, or null. */
export function engagementLinkRef(cfgId, accountId, contactId) {
    if (!cfgId) return null;
    // Full drill-in deep link (what gtmRepLinkFinder writes to the URL) needs the
    // account AND the contact: the detail restore reads getContactsWithLinks, which
    // only returns links that have a contact.
    if (accountId && contactId) {
        return {
            type: 'standard__navItemPage',
            attributes: { apiName: PAGES_TAB },
            state: {
                c__rlfLinkId: cfgId,
                c__rlfAccountId: accountId,
                c__rlfContactId: contactId,
                cfgId
            }
        };
    }
    // No account or no contact: open by the link id alone (gtmPageBrowser hands
    // c__recordId to the finder as its target record).
    return {
        type: 'standard__navItemPage',
        attributes: { apiName: PAGES_TAB },
        state: { c__template: 'link', c__recordId: cfgId, cfgId }
    };
}

/**
 * Page reference for the assessment workspace, or null.
 *
 * @param {String} focusReadout  Optional (issue-102-1-engagement-links-landing,
 *   D7 + acceptance criterion 4). Only meaningful together with a truthy
 *   readoutId: carries the rider `c__focusReadoutTab` so the destination
 *   workspace (gtmReadoutsOverview -> gtmReadoutWorkspace) knows this
 *   navigation is an explicit "take me to the readout" request, not just a
 *   generic "open this assessment" one. gtmReadoutWorkspace's own default-tab
 *   logic (refinement #3) otherwise always lands on the Assessment tab
 *   regardless of readoutId -- a deliberate, tested, documented decision for
 *   every OTHER entry point (a card, "View readout", a freshly generated
 *   readout). This rider is how the NEW "Open the readout" forward action
 *   overrides that default for itself alone, without changing refinement #3's
 *   behavior for any existing caller that does not opt in.
 */
export function assessmentRef(arId, readoutId, offeringKey, focusReadout) {
    if (!arId) return null;
    const state = { c__assessmentRequestId: arId };
    if (readoutId) {
        state.c__readoutId = readoutId;
        if (focusReadout) state.c__focusReadoutTab = '1';
    }
    if (offeringKey) state.c__offeringKey = offeringKey;
    return {
        type: 'standard__navItemPage',
        attributes: { apiName: ASSESSMENTS_TAB },
        state
    };
}

function go(host, ref) {
    if (!host || !ref) return false;
    host[NavigationMixin.Navigate](ref);
    return true;
}

export function openEngagementLink(host, cfgId, accountId, contactId) {
    return go(host, engagementLinkRef(cfgId, accountId, contactId));
}

export function openAssessment(host, arId, readoutId, offeringKey, focusReadout) {
    return go(host, assessmentRef(arId, readoutId, offeringKey, focusReadout));
}

/** A readout has no page of its own: open its assessment with it focused. */
export function openReadout(host, readoutId, arId, offeringKey) {
    if (!readoutId || !arId) return false;
    return openAssessment(host, arId, readoutId, offeringKey);
}
