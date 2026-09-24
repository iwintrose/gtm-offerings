/**
 * Shared open-Opportunity duplicate check (issue #32).
 *
 * Both Opportunity-creating paths -- GtmSavedConfigurationController's
 * rep-facing save, and GtmAssessmentRequestController's assessment-submission
 * path -- ask the same question before minting a brand-new Opportunity: is
 * there already an OPEN one for this exact Account + primary Contact +
 * Offering? Kept as its own class (mirroring GtmDealNaming's "one naming
 * authority, shared" pattern) rather than duplicated per-controller, since
 * the query and its false-positive/false-negative rules are exactly the
 * kind of thing that quietly drifts apart if copied.
 *
 * Match rule is strict equality only, joined through OpportunityContactRole
 * for the given Contact:
 *
 *     Offering_Key__c = :offeringKey AND AccountId = :accountId AND IsClosed = false
 *
 * Never `!=` and never an `OR ... = null` variant: a pre-existing Opportunity
 * with a null Offering_Key__c (nothing here is backfilled -- see issue #32's
 * explicit out-of-scope) must simply never match. A false negative there is
 * an accepted, known gap; a false positive (wrongly blocking a rep on an old,
 * unrelated Opportunity) is not.
 */
public with sharing class GtmOpenOpportunityDuplicateCheck {

    public class Match {
        public Id opportunityId;
        public String opportunityName;
        public Match(Id opportunityId, String opportunityName) {
            this.opportunityId = opportunityId;
            this.opportunityName = opportunityName;
        }
    }

    /**
     * Thrown by a caller (currently only
     * GtmSavedConfigurationController.resolveOpportunity, the only path with
     * a UI able to show the two-choice prompt) when findOpenDuplicate()
     * found a match and the caller hasn't already been told to proceed
     * anyway. The message is a small JSON payload -- not free text -- so
     * gtmConfigWizard.js can render the "Continue with existing" /
     * "Create new anyway" / cancel prompt instead of a dead-end error toast.
     * AuraHandledException requires an explicit setMessage() call for the
     * message to actually reach the client; the constructor argument alone
     * is not enough.
     */
    public static AuraHandledException forMatch(Match m) {
        String payload = JSON.serialize(new Map<String, Object>{
            'type' => 'OPEN_DUPLICATE',
            'opportunityId' => m.opportunityId,
            'opportunityName' => m.opportunityName
        });
        AuraHandledException e = new AuraHandledException(payload);
        e.setMessage(payload);
        return e;
    }

    /**
     * Returns the open Opportunity already on file for this exact
     * Account + primary/any Contact-role + Offering combination, or null
     * when there isn't one (including whenever accountId, contactId, or
     * offeringKey is blank -- the check simply doesn't run rather than
     * guessing).
     */
    public static Match findOpenDuplicate(Id accountId, Id contactId, String offeringKey) {
        if (accountId == null || contactId == null || String.isBlank(offeringKey)) {
            return null;
        }

        List<Opportunity> candidates = [
            SELECT Id, Name
            FROM Opportunity
            WHERE Offering_Key__c = :offeringKey
              AND AccountId = :accountId
              AND IsClosed = false
            ORDER BY CreatedDate DESC
        ];
        if (candidates.isEmpty()) {
            return null;
        }

        Set<Id> candidateIds = new Set<Id>();
        for (Opportunity o : candidates) {
            candidateIds.add(o.Id);
        }

        Set<Id> withContact = new Set<Id>();
        for (OpportunityContactRole r : [
            SELECT OpportunityId
            FROM OpportunityContactRole
            WHERE OpportunityId IN :candidateIds AND ContactId = :contactId
        ]) {
            withContact.add(r.OpportunityId);
        }

        for (Opportunity o : candidates) {
            if (withContact.contains(o.Id)) {
                return new Match(o.Id, o.Name);
            }
        }
        return null;
    }
}
