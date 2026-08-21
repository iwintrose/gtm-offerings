/**
 * Aggregate KPIs for the GTM Offerings app's landing page -- one cacheable
 * read, no per-record data, so it's safe to show org-wide regardless of
 * who's looking (a rep's own Engagement Links are still scoped by the
 * standard object sharing rules already governing everything else in this
 * feature; this only sums what the running user can already see).
 */
public with sharing class MaHomeSnapshotController {
    public class Snapshot {
        @AuraEnabled
        public Decimal activeEngagementValue { get; set; }
        @AuraEnabled
        public Integer activeEngagementCount { get; set; }
        @AuraEnabled
        public Integer newAssessmentCount { get; set; }
        @AuraEnabled
        public Decimal openPipelineAmount { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static Snapshot getSnapshot() {
        Snapshot snap = new Snapshot();

        AggregateResult links = [
            SELECT SUM(Estimated_Value__c) totalValue, COUNT(Id) total
            FROM MA_Saved_Configuration__c
            WHERE Active__c = true
        ][0];
        snap.activeEngagementValue = (Decimal) links.get('totalValue') != null
            ? (Decimal) links.get('totalValue')
            : 0;
        snap.activeEngagementCount = (Integer) links.get('total');

        snap.newAssessmentCount = [
            SELECT COUNT()
            FROM MA_Assessment_Request__c
            WHERE Status__c = 'New'
        ];

        AggregateResult pipeline = [
            SELECT SUM(Amount) totalAmount
            FROM Opportunity
            WHERE IsClosed = false
            AND Id IN (SELECT Opportunity__c FROM MA_Saved_Configuration__c WHERE Opportunity__c != null)
        ][0];
        snap.openPipelineAmount = (Decimal) pipeline.get('totalAmount') != null
            ? (Decimal) pipeline.get('totalAmount')
            : 0;

        return snap;
    }

    public class RequestSummary {
        @AuraEnabled
        public Id recordId { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String requesterName { get; set; }
        @AuraEnabled
        public String company { get; set; }
        @AuraEnabled
        public Datetime createdDate { get; set; }
    }

    /** The 5 newest requests still sitting at Status = New -- what a rep
     * should look at first when they open the app, not something they'd
     * otherwise notice without navigating to the tab and filtering. */
    @AuraEnabled(cacheable=true)
    public static List<RequestSummary> getRecentNewAssessmentRequests() {
        List<RequestSummary> results = new List<RequestSummary>();
        for (MA_Assessment_Request__c req : [
            SELECT Id, Name, Requester_Name__c, Company__c, CreatedDate
            FROM MA_Assessment_Request__c
            WHERE Status__c = 'New'
            ORDER BY CreatedDate DESC
            LIMIT 5
        ]) {
            RequestSummary summary = new RequestSummary();
            summary.recordId = req.Id;
            summary.name = req.Name;
            summary.requesterName = req.Requester_Name__c;
            summary.company = req.Company__c;
            summary.createdDate = req.CreatedDate;
            results.add(summary);
        }
        return results;
    }
}
