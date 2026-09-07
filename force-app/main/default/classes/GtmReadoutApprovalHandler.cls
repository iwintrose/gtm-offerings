/**
 * What happens on GTM_Readout__c when Status__c becomes Approved.
 *
 * Called from GtmReadoutApprovalSync. In production the transition is produced
 * by the GTM_Readout_Approval process's final-approval field update; keying off
 * the transition rather than off the approval event means an admin who sets
 * Status__c by hand, or a test that does the same DML, gets the identical
 * behaviour -- there is exactly one definition of "approved" on this object.
 *
 * `without sharing`: this runs inside an approval transaction, where the
 * running user is the approver -- a manager who, under the object's Private
 * sharing model, may well have no direct access to the readout beyond the role
 * hierarchy, and none at all to its GTM_Readout_Version__c child. The trigger is
 * not making an access decision; the platform already made it when it routed
 * the approval to this person. Refusing to snapshot because the approver cannot
 * see the child record would lose the evidence of the very approval they just
 * gave.
 */
public without sharing class GtmReadoutApprovalHandler {

    /**
     * The statuses an approval can legitimately arrive from.
     *
     * Published -> Approved is the deliberate omission. That transition is
     * GtmReadoutController.unpublishReadout revoking a live link, not an
     * approval, and treating it as one would overwrite the approved content
     * with whatever is in the draft and re-stamp a new approver on a readout
     * nobody re-approved.
     */
    private static final Set<String> PRE_APPROVAL_STATUSES = new Set<String>{
        'Draft', 'Pending Approval'
    };

    private static final String APPROVED = 'Approved';

    /**
     * Before update: fill in everything an approval means beyond the status
     * word itself.
     *
     * Approved_Content__c is the load-bearing one -- it is what
     * GtmReadoutPublicController serves to the prospect, so approval has to be
     * the moment it is fixed. A workflow field update cannot write a Rich Text
     * Area field, which is exactly why this trigger exists.
     *
     * Approved_By__c comes from the running user. During a final-approval field
     * update that is the person who clicked Approve, so this is the approver
     * and not the submitter -- the property the old custom approve button could
     * not have, since there the two were always the same person.
     * ProcessInstanceStep.ActorId remains the audit record of record; this is
     * the copy that list views and reports can use.
     */
    public static void stampApproval(List<GTM_Readout__c> updated, Map<Id, GTM_Readout__c> priorById) {
        if (updated == null || priorById == null) {
            return;
        }
        for (GTM_Readout__c readout : updated) {
            GTM_Readout__c prior = priorById.get(readout.Id);
            if (!isApprovalTransition(readout, prior)) {
                continue;
            }
            readout.Approved_Content__c = readout.Draft_Content__c;
            // The measurement half, fixed by the same act that fixes the prose.
            // Readout_Data__c is written once at generation and nothing edits
            // it, so in practice these two are already identical -- copying it
            // anyway is what makes "what publishes is what was approved" a
            // property of the record rather than a property of nobody having
            // touched a field. GtmReadoutPublicController serves this copy.
            readout.Approved_Data__c    = readout.Readout_Data__c;
            readout.Approved_By__c      = UserInfo.getUserId();
            readout.Approved_Date__c    = System.now();
        }
    }

    /**
     * After update: the immutable snapshot of what was approved.
     *
     * This is the half that field history and ProcessInstance cannot replace.
     * History does not retain Long Text / Rich Text Area values and
     * Approved_Content__c is overwritten by the next approval cycle, so without
     * this row "prove what was approved on the 3rd" has no answer at all.
     *
     * Best-effort: an approval that has already been recorded by the platform
     * must not be rolled back because its evidence row failed to insert. The
     * failure is logged with the readout Id, and the approval history still
     * carries who and when.
     */
    public static void snapshotApprovals(List<GTM_Readout__c> updated, Map<Id, GTM_Readout__c> priorById) {
        if (updated == null || priorById == null) {
            return;
        }
        List<GTM_Readout__c> approvedReadouts = new List<GTM_Readout__c>();
        for (GTM_Readout__c readout : updated) {
            if (isApprovalTransition(readout, priorById.get(readout.Id))) {
                approvedReadouts.add(readout);
            }
        }
        if (approvedReadouts.isEmpty()) {
            return;
        }

        Map<Id, Integer> nextNumbers = nextVersionNumbers(approvedReadouts);
        List<GTM_Readout_Version__c> versions = new List<GTM_Readout_Version__c>();
        for (GTM_Readout__c readout : approvedReadouts) {
            versions.add(new GTM_Readout_Version__c(
                Readout__c            = readout.Id,
                Version_Number__c     = nextNumbers.get(readout.Id),
                Snapshot__c           = readout.Approved_Content__c,
                Data_Snapshot__c      = readout.Approved_Data__c,
                Change_Summary__c     = 'Approved',
                Status_At_Snapshot__c = APPROVED
            ));
        }
        try {
            insert versions;
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'GtmReadoutApprovalHandler could not snapshot approved content for ' +
                approvedReadouts.size() + ' readout(s): ' + e.getTypeName() +
                ' at line ' + e.getLineNumber() + ' -- ' + e.getMessage()
            );
        }
    }

    /** Draft/Pending -> Approved, and nothing else. */
    private static Boolean isApprovalTransition(GTM_Readout__c readout, GTM_Readout__c prior) {
        return prior != null
            && readout.Status__c == APPROVED
            && prior.Status__c != APPROVED
            && PRE_APPROVAL_STATUSES.contains(prior.Status__c);
    }

    /**
     * One aggregate query for the whole batch rather than a COUNT() per record
     * -- an approval can be taken on several readouts at once from a list view,
     * and a SOQL call inside the loop would govern how many.
     *
     * MAX + 1 rather than COUNT + 1: the two agree today, and MAX keeps
     * agreeing if a version row is ever deleted.
     */
    private static Map<Id, Integer> nextVersionNumbers(List<GTM_Readout__c> readouts) {
        Map<Id, Integer> next = new Map<Id, Integer>();
        for (GTM_Readout__c readout : readouts) {
            next.put(readout.Id, 1);
        }
        for (AggregateResult row : [
            SELECT Readout__c readoutId, MAX(Version_Number__c) highest
            FROM GTM_Readout_Version__c
            WHERE Readout__c IN :next.keySet()
            GROUP BY Readout__c
        ]) {
            Decimal highest = (Decimal) row.get('highest');
            next.put((Id) row.get('readoutId'), highest == null ? 1 : highest.intValue() + 1);
        }
        return next;
    }
}
