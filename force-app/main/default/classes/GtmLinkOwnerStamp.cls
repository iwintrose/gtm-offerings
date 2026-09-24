/**
 * Resolves the owner of an engagement link so guest-created records can be
 * stamped with it (contract: docs/architecture/gtm-link-owner-stamp.md).
 *
 * No DML, never throws. A link with no usable owner (missing, inactive or
 * guest) yields null and the caller leaves the row unowned: no queue fallback.
 * The Saved_Configuration__c object is queried dynamically to keep the
 * Lookup-repoint rule described in GtmLinkEventController.
 */
public without sharing class GtmLinkOwnerStamp {

    private GtmLinkOwnerStamp() {}

    /** Class name of the last swallowed failure (no message, nothing sensitive); QA aid. */
    @TestVisible private static String lastError;

    /**
     * Two queries at most per call, never per row: the link's OwnerId, then a
     * User check (Owner is polymorphic, so a relationship filter on it is not
     * usable). Null input costs none; a non-User owner costs one.
     */
    public static Id ownerForLink(Id savedConfigurationId) {
        if (savedConfigurationId == null) return null;
        try {
            if (savedConfigurationId.getSObjectType() != GTM_Saved_Configuration__c.SObjectType) {
                return null;
            }
            List<SObject> found = Database.query(
                'SELECT OwnerId FROM GTM_Saved_Configuration__c WHERE Id = :savedConfigurationId LIMIT 1'
            );
            if (found.isEmpty()) return null;
            Id candidate = (Id) found[0].get('OwnerId');
            if (candidate == null || candidate.getSObjectType() != User.SObjectType) return null;
            List<User> usable = [
                SELECT Id FROM User
                WHERE Id = :candidate AND IsActive = true AND UserType != 'Guest'
                LIMIT 1
            ];
            return usable.isEmpty() ? null : usable[0].Id;
        } catch (Exception e) {
            lastError = e.getTypeName();
            return null;
        }
    }

    public static void stamp(List<SObject> rows, Id ownerId) {
        if (rows == null || ownerId == null) return;
        for (SObject row : rows) {
            if (row != null) row.put('OwnerId', ownerId);
        }
    }
}
