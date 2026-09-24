/**
 * "Readouts awaiting response" widget on the Overview Today view (issue
 * overview-bd-heat-redesign-3-daily-widgets). Read-only: SOQL only, no DML,
 * no callouts, no `without sharing`.
 *
 * COARSE PROXY ONLY. Neither GTM_Readout__c nor its related objects
 * (GTM_Readout_Approval_Log__c, GTM_Readout_Version__c) carry any real
 * viewed/replied signal, and adding one is explicitly out of scope for this
 * ticket (deferred to gus-nudge-tool-and-readout-viewed-tracking). This
 * widget surfaces readouts that are Status__c = 'Published' with a populated
 * Notification_Sent_Date__c, and days-since-sent -- nothing more. Callers
 * MUST word this as "sent N days ago, no update since", never "viewed" or
 * "replied", since the app has no way to know either of those facts.
 *
 * Scoping follows the same owner-scoped-unless-viewAll convention as
 * GtmOverviewOfferingCounts / GtmReadoutController (private hasViewAllRecords
 * probe).
 */
public with sharing class GtmReadoutsAwaitingController {

    private static final Integer ROW_LIMIT = 50;

    public class ReadoutRow {
        @AuraEnabled public Id readoutId;
        // A readout has no page of its own (docs/architecture/gtm-row-open-and-links.md):
        // the row must open via c/gtmNavigate's openReadout(host, readoutId,
        // assessmentRequestId, offeringKey), which needs both ids below. Without
        // them the LWC has no way to route a click anywhere but a bare
        // GTM_Readout__c record page, which is the exact thing that doc forbids.
        @AuraEnabled public Id assessmentRequestId;
        @AuraEnabled public String offeringKey;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String accountName;
        @AuraEnabled public Datetime sentDate;
        @AuraEnabled public Integer daysSinceSent;
    }

    @AuraEnabled(cacheable=false)
    public static List<ReadoutRow> getReadoutsAwaiting() {
        try {
            return compute();
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    private static List<ReadoutRow> compute() {
        Id currentUserId = UserInfo.getUserId();
        Integer rowLimit = ROW_LIMIT;
        String query = 'SELECT Id, Assessment_Request__c, Offering_Key__c, Opportunity__c,'
            + ' Opportunity__r.Name, Opportunity__r.Account.Name,'
            + ' Notification_Sent_Date__c'
            + ' FROM GTM_Readout__c'
            + ' WHERE Status__c = \'Published\''
            + ' AND Notification_Sent_Date__c != null';
        if (!hasViewAllRecords('GTM_Readout__c')) {
            query += ' AND OwnerId = :currentUserId';
        }
        query += ' ORDER BY Notification_Sent_Date__c ASC LIMIT :rowLimit';

        Date today = Date.today();
        List<ReadoutRow> out = new List<ReadoutRow>();
        for (GTM_Readout__c r : Database.query(query)) {
            ReadoutRow row = new ReadoutRow();
            row.readoutId = r.Id;
            row.assessmentRequestId = r.Assessment_Request__c;
            row.offeringKey = r.Offering_Key__c;
            row.opportunityId = r.Opportunity__c;
            row.opportunityName = r.Opportunity__r == null ? null : r.Opportunity__r.Name;
            row.accountName = (r.Opportunity__r == null || r.Opportunity__r.Account == null)
                ? null : r.Opportunity__r.Account.Name;
            row.sentDate = r.Notification_Sent_Date__c;
            row.daysSinceSent = row.sentDate == null ? null : row.sentDate.date().daysBetween(today);
            out.add(row);
        }
        return out;
    }

    // Private copy of the same probe used by GtmOverviewOfferingCounts /
    // GtmTasksDueTodayController / GtmReadoutController -- see the TODO on
    // GtmOverviewOfferingCounts about eventually de-duplicating this.
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
