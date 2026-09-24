/**
 * Lifecycle guardrail for GTM_Instrument__c: an Active instrument cannot be
 * deleted or archived directly -- it must be explicitly moved back to Draft
 * first. (Offering_Key__c is unique on this object, so there is never a
 * sibling instrument to "demote" -- publishing only ever flips this same
 * row's Status__c.)
 *
 * Thin by design -- the logic is in GtmInstrumentTriggerHandler, matching
 * this repo's GtmReadoutApprovalSync / GtmReadoutApprovalHandler pattern
 * (ADR-0003, single-owner-per-side-effect).
 */
trigger GTM_InstrumentTrigger on GTM_Instrument__c (before delete, before update) {
    if (Trigger.isDelete) {
        GtmInstrumentTriggerHandler.blockDeleteWhileActive(Trigger.old);
    } else if (Trigger.isUpdate) {
        GtmInstrumentTriggerHandler.blockArchiveWhileActive(Trigger.new, Trigger.oldMap);
    }
}
