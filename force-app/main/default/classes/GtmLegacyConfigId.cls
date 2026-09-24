/**
 * Resolves a client-supplied Engagement Link id, old or new.
 *
 * Four real, already-distributed guest URLs (?cfgId=<id>) predate the D6
 * MA_Saved_Configuration__c -> GTM_Saved_Configuration__c rename. Salesforce
 * Ids are permanently bound to their originating object, so those ids can
 * never resolve directly against the renamed object -- every guest-facing
 * entry point that accepts a configId/recordId calls resolve() on it first.
 * A current-format id passes straight through; anything else is looked up
 * against GTM_Saved_Configuration__c.Legacy_Id__c, which was stamped with
 * each migrated row's old Id during the Stage 5 data copy. Returns null for
 * anything that resolves to neither, same as an unrecognised id today.
 *
 * The current-format check compares the id's own key prefix against
 * GTM_Saved_Configuration__c's key prefix as a plain string, rather than
 * parsing the id and calling getSObjectType() on it -- once MA_Saved_
 * Configuration__c is deleted at final cutover, an old id's prefix no
 * longer resolves to any live SObjectType, and what getSObjectType() does
 * with a dead prefix isn't something to depend on. A prefix string compare
 * has no such dependency: it works identically whether the old object
 * still exists or not.
 *
 * Dynamic SOQL, not static: Legacy_Id__c is a newly deployed unique/external-
 * id field, and this org has repeatedly shown a propagation lag between an
 * external-id field's own index build and both Apex's static-compile schema
 * cache and the REST Data API recognising it -- dynamic Database.query
 * sidesteps the static-compile side of that lag, matching the pattern used
 * elsewhere in this migration for the same reason.
 */
public without sharing class GtmLegacyConfigId {

    public static Id resolve(String recordId) {
        if (String.isBlank(recordId)) return null;
        String trimmed = recordId.trim();

        if (isCurrentFormat(trimmed)) {
            try {
                return Id.valueOf(trimmed);
            } catch (Exception e) {
                return null;
            }
        }

        // Not a current-format id -- try it as a legacy one. No further
        // format check: anything that isn't already a current-format id is
        // worth one lookup, and a miss just returns null like today.
        List<SObject> rows = Database.query(
            'SELECT Id FROM GTM_Saved_Configuration__c ' +
            'WHERE Legacy_Id__c = :trimmed LIMIT 1'
        );
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static Boolean isCurrentFormat(String value) {
        if (value.length() != 15 && value.length() != 18) return false;
        String prefix = GTM_Saved_Configuration__c.SObjectType.getDescribe().getKeyPrefix();
        return value.startsWith(prefix);
    }
}
