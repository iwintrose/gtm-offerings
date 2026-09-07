/**
 * Guest-reachable, deliberately tiny: the ONE thing a client's browser
 * needs to know about a saved configuration is whether it's still active.
 * Runs `without sharing` because the guest user has no object access at
 * all -- same pattern as GtmAssessmentRequestController. Never expose
 * Company__c, Config_Payload__c, or anything else here; that's exactly
 * the kind of scope creep GtmSavedConfigurationController (rep-only,
 * `with sharing`, never granted to the guest permission set) exists to
 * avoid.
 */
public without sharing class GtmConfigurationStatusController {
    /**
     * A blank id (a generic or pre-record link) is treated as active --
     * there's nothing to gate. Anything non-blank that doesn't resolve to a
     * real record -- malformed, or a legacy id with no match -- returns
     * false, same as a real id that's been switched off. (Malformed input
     * used to be treated the same as blank; folded into the "false" case
     * now that GtmLegacyConfigId.resolve() can no longer tell "malformed"
     * apart from "a legacy id with no mapping" -- fail closed is the
     * safer default for either.)
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isActive(String recordId) {
        if (String.isBlank(recordId)) {
            return true;
        }
        Id parsedId = GtmLegacyConfigId.resolve(recordId);
        if (parsedId == null) {
            return false;
        }
        List<GTM_Saved_Configuration__c> rows = [
            SELECT Active__c
            FROM GTM_Saved_Configuration__c
            WHERE Id = :parsedId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return false;
        }
        return rows[0].Active__c;
    }
}
