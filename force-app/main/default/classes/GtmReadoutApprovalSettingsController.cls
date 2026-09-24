/**
 * Admin-only accessor for GTM_Readout_Approval_Settings__c, backing the
 * GTM_Readout_Approval_Settings tab / gtmReadoutApprovalSettings LWC.
 *
 * Deliberately its own class rather than added to GtmReadoutController: that
 * class's Apex class access is granted to GTM_Offering_User (every rep needs
 * it for the readout editor), and the routing toggle is an admin-only action
 * per the Architect decision -- keeping it in a class granted only to
 * GTM_Offering_Admin is what makes that boundary real rather than just a
 * hidden tab a determined user could still reach through Apex.
 *
 * `with sharing`: this is an internal admin config surface, not a
 * public/guest one, and the Custom Setting itself has no row-level sharing to
 * enforce anyway -- with sharing costs nothing here and is the safer default.
 */
public with sharing class GtmReadoutApprovalSettingsController {

    @AuraEnabled(cacheable=true)
    public static Boolean getSelfApprovalEnabled() {
        GTM_Readout_Approval_Settings__c settings = GTM_Readout_Approval_Settings__c.getOrgDefaults();
        return settings != null && settings.Self_Approval_Enabled__c == true;
    }

    /**
     * Writes the org default row specifically (Id == null on the Hierarchy
     * setting's org-wide row) rather than getInstance()'s resolved row for the
     * running user -- an admin toggling this tab means "change it for
     * everyone," not "change it for me."
     */
    @AuraEnabled
    public static void setSelfApprovalEnabled(Boolean enabled) {
        GTM_Readout_Approval_Settings__c settings = GTM_Readout_Approval_Settings__c.getOrgDefaults();
        if (settings == null || settings.Id == null) {
            settings = new GTM_Readout_Approval_Settings__c();
        }
        settings.Self_Approval_Enabled__c = enabled == true;
        upsert settings;
    }
}
