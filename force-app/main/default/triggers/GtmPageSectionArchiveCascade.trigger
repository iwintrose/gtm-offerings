/**
 * Owns two side effects for GTM_Page_Section__c, per ADR-0003 (single
 * trigger point per side effect):
 *
 *  - before update: stamp Archived_Date__c on any row whose own Archived__c
 *    changed value (self-stamp; never re-stamps a same-value write).
 *  - after update: when the offering's tile row (Section_Key__c='tile',
 *    Template_Type__c='offerings-listing') has its Archived__c changed,
 *    cascade that new value to every other GTM_Page_Section__c and
 *    GTM_Page_Content__c row sharing its Offering_Key__c.
 *
 * Logic lives in GtmOfferingArchiveCascadeHandler; see
 * docs/architecture/offering-archive-cascade.md for the full contract.
 */
trigger GtmPageSectionArchiveCascade on GTM_Page_Section__c (before update, after update) {
    if (Trigger.isBefore) {
        GtmOfferingArchiveCascadeHandler.stampSectionDates(Trigger.new, Trigger.oldMap);
    } else {
        GtmOfferingArchiveCascadeHandler.cascadeFromTiles(Trigger.new, Trigger.oldMap);
    }
}
