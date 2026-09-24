/**
 * Per-offering counts for the Overview "Offerings" cards (issue
 * overview-sales-dashboard-3-offerings-results). Contract:
 * docs/architecture/overview-sales-dashboard-3-offerings-results.md.
 *
 * Read-only: SOQL only, no DML, no callouts, no `without sharing`.
 *
 * Live links = the GtmLinkStageService universe (Presentation_Stage__c not
 * null, not Draft, not Rep_Direct) AND Active__c = true. That is deliberately
 * NARROWER than the Pages tab / funnel, which do not filter on Active__c.
 * Submitted assessments = every GTM_Assessment_Request__c, any status.
 *
 * Scoping: owner-scoped unless the running user holds View All on that object
 * (checked per object with a private copy of the ObjectPermissions probe).
 * getAssessmentPage additionally shows queue-owned orphan requests to a rep
 * via an elevated read; this plain `with sharing` aggregate does not, so a
 * rep's submitted count can be lower than the Assessments tab. Accepted.
 *
 * Rows: one per GTM_Offering__mdt (zero defaults) plus one per key present in
 * the data but not in the mdt (label = raw key). Blank/null keys are skipped
 * (no row). Sorted by label then key.
 */
public with sharing class GtmOverviewOfferingCounts {

    public class OfferingCount {
        @AuraEnabled public String offeringKey;
        @AuraEnabled public String offeringLabel;
        @AuraEnabled public Integer liveLinkCount = 0;
        @AuraEnabled public Integer submittedAssessmentCount = 0;
    }

    @AuraEnabled(cacheable=false)
    public static List<OfferingCount> getOfferingCounts() {
        try {
            return compute();
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    private static List<OfferingCount> compute() {
        Map<String, OfferingCount> byKey = new Map<String, OfferingCount>();
        for (GTM_Offering__mdt off : [
            SELECT Offering_Key__c, Label__c FROM GTM_Offering__mdt
        ]) {
            if (String.isBlank(off.Offering_Key__c)) { continue; }
            OfferingCount oc = new OfferingCount();
            oc.offeringKey = off.Offering_Key__c;
            oc.offeringLabel = String.isBlank(off.Label__c) ? off.Offering_Key__c : off.Label__c;
            byKey.put(oc.offeringKey, oc);
        }

        Id currentUserId = UserInfo.getUserId();

        String linkQuery = 'SELECT Offering__c k, COUNT(Id) c FROM GTM_Saved_Configuration__c'
            + ' WHERE Presentation_Stage__c != null'
            + ' AND Presentation_Stage__c != \'Draft\''
            + ' AND Presentation_Stage__c != \'Rep_Direct\''
            + ' AND Active__c = true';
        if (!hasViewAllRecords('GTM_Saved_Configuration__c')) {
            linkQuery += ' AND OwnerId = :currentUserId';
        }
        linkQuery += ' GROUP BY Offering__c';
        for (AggregateResult ar : Database.query(linkQuery)) {
            OfferingCount oc = rowFor(byKey, (String) ar.get('k'));
            if (oc != null) { oc.liveLinkCount = (Integer) ar.get('c'); }
        }

        String reqQuery = 'SELECT Offering_Key__c k, COUNT(Id) c FROM GTM_Assessment_Request__c';
        if (!hasViewAllRecords('GTM_Assessment_Request__c')) {
            reqQuery += ' WHERE OwnerId = :currentUserId';
        }
        reqQuery += ' GROUP BY Offering_Key__c';
        for (AggregateResult ar : Database.query(reqQuery)) {
            OfferingCount oc = rowFor(byKey, (String) ar.get('k'));
            if (oc != null) { oc.submittedAssessmentCount = (Integer) ar.get('c'); }
        }

        List<OfferingCount> out = byKey.values();
        out.sort(new ByLabelThenKey());
        return out;
    }

    private static OfferingCount rowFor(Map<String, OfferingCount> byKey, String keyName) {
        if (String.isBlank(keyName)) { return null; }
        OfferingCount oc = byKey.get(keyName);
        if (oc == null) {
            oc = new OfferingCount();
            oc.offeringKey = keyName;
            oc.offeringLabel = keyName;
            byKey.put(keyName, oc);
        }
        return oc;
    }

    private class ByLabelThenKey implements System.Comparator<OfferingCount> {
        public Integer compare(OfferingCount a, OfferingCount b) {
            Integer byLabel = a.offeringLabel.toLowerCase().compareTo(b.offeringLabel.toLowerCase());
            return byLabel != 0 ? byLabel : a.offeringKey.compareTo(b.offeringKey);
        }
    }

    // TODO de-duplicate onto the shared helper: private copy of
    // GtmLinkStageService.hasViewAllRecords (deliberately NOT
    // GtmHomeSnapshotController.isAdmin(), which matches permission-set names).
    private static Boolean hasViewAllRecords(String sobjectApiName) {
        List<ObjectPermissions> perms = [
            SELECT PermissionsViewAllRecords
            FROM ObjectPermissions
            WHERE SobjectType = :sobjectApiName
              AND ParentId IN (
                  SELECT PermissionSetId FROM PermissionSetAssignment
                  WHERE AssigneeId = :UserInfo.getUserId()
              )
              AND PermissionsViewAllRecords = true
            LIMIT 1
        ];
        return !perms.isEmpty();
    }
}
