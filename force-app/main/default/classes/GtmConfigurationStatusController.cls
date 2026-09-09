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

    /**
     * Whether this link has already had an assessment submitted against it.
     *
     * A BOOLEAN AND NOTHING ELSE -- no id, no score, no date, no company. The
     * caller already holds the link; this tells them the form is done, which is
     * the one thing the page needs in order not to invite a second submission
     * (ADR-0008 section 4). The disclosure is "this link's form is done", which
     * the holder of the link is entitled to and which is strictly less than
     * isActive above already tells them. Returning the request id or the score
     * here would be exactly the scope creep this class's header warns about --
     * GtmReadoutPublicController is the only guest path onto assessment
     * *content*, and it is token-gated for a reason.
     *
     * NOT CACHEABLE, unlike isActive. A stale `false` served from the Lightning
     * data service immediately after a submit is the precise case this method
     * exists to prevent.
     *
     * The `without sharing` context on this class is what makes the query
     * resolve: GTM_Assessment_Guest grants the guest allowRead + allowCreate on
     * GTM_Assessment_Request__c with viewAllRecords = false, exactly as it does
     * for isActive's own read.
     *
     * SERVER ENFORCEMENT IS NOT HERE. GtmAssessmentRequestController.submitRequest
     * holds the invariant; this only lets the page tell the truth about it in a
     * browser that has never seen the submission. A caller that skips this
     * method gains nothing.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean hasSubmittedAssessment(String recordId) {
        if (String.isBlank(recordId)) {
            return false;
        }
        Id parsedId = GtmLegacyConfigId.resolve(recordId);
        if (parsedId == null) {
            return false;
        }
        return ![
            SELECT Id
            FROM   GTM_Assessment_Request__c
            WHERE  Saved_Configuration__c = :parsedId
            LIMIT  1
        ].isEmpty();
    }
}
