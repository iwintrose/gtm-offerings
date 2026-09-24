/**
 * Apex controller for the gtmArCasePanel LWC.
 *
 * Runs with sharing: the caller must be able to see the Assessment Request
 * and its Readout (owner, admin, or GTM_Readout_Triage queue member via
 * queue-owned records) or the method returns null. Only the final Case read
 * is elevated (private CaseReads, without sharing), keyed on the readout id
 * already proven visible: internal reps on GTM_Offering_User do not have a
 * Case objectPermissions grant (the license rejects it at deploy time -- see
 * CLAUDE.md §6 FLS note and GTM_Offering_User.permissionset-meta.xml).
 */
public with sharing class GtmArCasePanelController {

    public class CaseDTO {
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String createdDate;
    }

    /**
     * Returns a lightweight DTO describing the review Case linked to the
     * Assessment Request, or null when no readout or Case exists yet.
     *
     * Two-hop traversal:
     *   GTM_Assessment_Request__c.Id
     *     -> GTM_Readout__c.Assessment_Request__c
     *       -> Case.Readout__c
     */
    @AuraEnabled(cacheable=true)
    public static CaseDTO getCaseForRequest(Id requestId) {
        if (requestId == null) {
            return null;
        }

        // Gate: the request itself must be visible under sharing.
        if ([SELECT COUNT() FROM GTM_Assessment_Request__c WHERE Id = :requestId] == 0) {
            return null;
        }

        List<GTM_Readout__c> readouts = [
            SELECT Id FROM GTM_Readout__c
            WHERE Assessment_Request__c = :requestId
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (readouts.isEmpty()) {
            return null;
        }

        List<Case> cases = new CaseReads().latestCase(readouts[0].Id);
        if (cases.isEmpty()) {
            return null;
        }

        CaseDTO dto = new CaseDTO();
        dto.subject     = cases[0].Subject;
        dto.status      = cases[0].Status;
        dto.createdDate = String.valueOf(cases[0].CreatedDate.date());
        return dto;
    }

    private without sharing class CaseReads {
        List<Case> latestCase(Id readoutId) {
            return [
                SELECT Id, Subject, Status, CreatedDate
                FROM Case
                WHERE Readout__c = :readoutId
                ORDER BY CreatedDate DESC LIMIT 1
            ];
        }
    }
}
