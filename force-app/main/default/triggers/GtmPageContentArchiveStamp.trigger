/**
 * Owns GTM_Page_Content__c's half of the self-stamp rule described in
 * docs/architecture/offering-archive-cascade.md: before update, stamp
 * Archived_Date__c on any row whose own Archived__c changed value. Fires
 * both for a direct edit and for the second DML
 * GtmOfferingArchiveCascadeHandler.cascadeFromTiles issues against this
 * object when an offering's tile row is archived or restored.
 */
trigger GtmPageContentArchiveStamp on GTM_Page_Content__c (before update) {
    GtmOfferingArchiveCascadeHandler.stampContentDates(Trigger.new, Trigger.oldMap);
}
