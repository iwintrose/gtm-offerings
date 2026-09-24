/**
 * What GTM_InstrumentTrigger enforces: an Active GTM_Instrument__c cannot be
 * deleted or archived directly, whether the caller is the UI, direct Apex
 * DML, or a data-loader-style update. It must be moved back to Draft first
 * before it can be archived or deleted. (Offering_Key__c is unique on
 * GTM_Instrument__c, so there is never a sibling instrument for the same
 * offering to "supersede" -- GtmInstrumentController.publishInstrument only
 * ever flips this same row's Status__c to Active.)
 *
 * `with sharing`: there is no privileged-approver-style reason to bypass
 * sharing here, unlike GtmReadoutApprovalHandler -- Content Managers editing
 * their own instruments already have object access via the permission sets
 * in docs/architecture/gtm-instrument-editor.md §6.
 */
public with sharing class GtmInstrumentTriggerHandler {

    private static final String ACTIVE   = 'Active';
    private static final String ARCHIVED = 'Archived';

    /** Before delete: block delete of any instrument that is currently Active. */
    public static void blockDeleteWhileActive(List<GTM_Instrument__c> deleted) {
        if (deleted == null) {
            return;
        }
        for (GTM_Instrument__c instrument : deleted) {
            if (instrument.Status__c == ACTIVE) {
                instrument.addError(
                    'An Active instrument cannot be deleted. Publish a ' +
                    'different instrument for this offering, or move this ' +
                    'one to Draft first.'
                );
            }
        }
    }

    /**
     * Before update: block a transition that moves Status__c to Archived
     * while the prior value was Active -- Active -> Draft -> Archived is the
     * only allowed path away from Active into Archived.
     */
    public static void blockArchiveWhileActive(
        List<GTM_Instrument__c> updated,
        Map<Id, GTM_Instrument__c> priorById
    ) {
        if (updated == null || priorById == null) {
            return;
        }
        for (GTM_Instrument__c instrument : updated) {
            GTM_Instrument__c prior = priorById.get(instrument.Id);
            if (prior == null) {
                continue;
            }
            Boolean movingToArchived = instrument.Status__c == ARCHIVED
                && prior.Status__c != ARCHIVED;
            if (movingToArchived && prior.Status__c == ACTIVE) {
                instrument.addError(
                    'An Active instrument cannot be archived directly. ' +
                    'Move it to Draft first, then Archive.'
                );
            }
        }
    }
}
