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
}
