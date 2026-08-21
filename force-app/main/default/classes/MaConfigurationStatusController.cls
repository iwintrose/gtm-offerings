/**
 * Guest-reachable, deliberately tiny: the ONE thing a client's browser
 * needs to know about a saved configuration is whether it's still active.
 * Runs `without sharing` because the guest user has no object access at
 * all -- same pattern as MaAssessmentRequestController. Never expose
 * Company__c, Config_Payload__c, or anything else here; that's exactly
 * the kind of scope creep MaSavedConfigurationController (rep-only,
 * `with sharing`, never granted to the guest permission set) exists to
 * avoid.
 */
public without sharing class MaConfigurationStatusController {
    /**
     * A blank/unrecognized id (a generic or pre-record link) is treated as
     * active -- there's nothing to gate. A real id that's been switched
     * off, or that no longer exists, returns false.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isActive(String recordId) {
        if (String.isBlank(recordId)) {
            return true;
        }
        Id parsedId;
        try {
            parsedId = Id.valueOf(recordId);
        } catch (System.StringException e) {
            return true;
        }
        List<MA_Saved_Configuration__c> rows = [
            SELECT Active__c
            FROM MA_Saved_Configuration__c
            WHERE Id = :parsedId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return false;
        }
        return rows[0].Active__c;
    }
}
