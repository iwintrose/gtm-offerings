/**
 * The one piece of glue the native approval process cannot do for itself.
 *
 * The GTM_Readout_Approval process moves Status__c to Approved with a workflow
 * field update. A workflow field update cannot target a Rich Text Area field,
 * so it cannot copy Draft_Content__c into Approved_Content__c -- and that copy
 * is the whole substance of an approval here: Approved_Content__c is what
 * publish exposes to the prospect, and the GTM_Readout_Version__c snapshot of it
 * is the only thing that can later prove *what* was approved (ProcessInstance
 * proves who and when; field history does not retain Long Text / Rich Text
 * values).
 *
 * So this trigger reacts to the transition rather than to the click, which
 * means it behaves identically whether Status__c was moved by the approval
 * process, by an admin editing the record, or by a test.
 *
 * Thin by design -- the logic is in GtmReadoutApprovalHandler.
 */
trigger GtmReadoutApprovalSync on GTM_Readout__c (before update, after update) {
    if (Trigger.isBefore) {
        GtmReadoutApprovalHandler.stampApproval(Trigger.new, Trigger.oldMap);
    } else {
        GtmReadoutApprovalHandler.snapshotApprovals(Trigger.new, Trigger.oldMap);
    }
}
