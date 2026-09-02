/**
 * Aggregate KPIs for the GTM Offerings app's landing page -- one cacheable
 * read, no per-record data, so it's safe to show org-wide regardless of
 * who's looking.
 */
public with sharing class MaHomeSnapshotController {
    public class Snapshot {
        @AuraEnabled public Integer activeEngagementCount { get; set; }
        @AuraEnabled public Integer newAssessmentCount    { get; set; }
        @AuraEnabled public Integer recentViews          { get; set; }
        @AuraEnabled public Integer submissionsThisMonth { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static Snapshot getSnapshot() {
        Snapshot snap = new Snapshot();

        snap.activeEngagementCount = [
            SELECT COUNT() FROM MA_Saved_Configuration__c WHERE Active__c = true
        ];

        snap.newAssessmentCount = [
            SELECT COUNT() FROM MA_Assessment_Request__c WHERE Status__c = 'New'
        ];

        snap.recentViews = [
            SELECT COUNT() FROM MA_Link_Event__c
            WHERE Event_Type__c = 'Page View'
            AND CreatedDate = LAST_N_DAYS:7
        ];

        snap.submissionsThisMonth = [
            SELECT COUNT() FROM MA_Link_Event__c
            WHERE Event_Type__c = 'Form Submitted'
            AND CreatedDate = THIS_MONTH
        ];

        return snap;
    }

    public class RequestSummary {
        @AuraEnabled public Id      recordId      { get; set; }
        @AuraEnabled public String  name          { get; set; }
        @AuraEnabled public String  requesterName { get; set; }
        @AuraEnabled public String  company       { get; set; }
        @AuraEnabled public String  platform      { get; set; }
        @AuraEnabled public Datetime createdDate  { get; set; }
    }

    /** The 5 newest requests still at Status = New, ordered newest first. */
    @AuraEnabled(cacheable=true)
    public static List<RequestSummary> getRecentNewAssessmentRequests() {
        List<RequestSummary> results = new List<RequestSummary>();
        for (MA_Assessment_Request__c req : [
            SELECT Id, Name, Requester_Name__c, Company__c,
                   Current_Platform__c, CreatedDate
            FROM MA_Assessment_Request__c
            WHERE Status__c = 'New'
            ORDER BY CreatedDate DESC
            LIMIT 5
        ]) {
            RequestSummary s = new RequestSummary();
            s.recordId      = req.Id;
            s.name          = req.Name;
            s.requesterName = req.Requester_Name__c;
            s.company       = req.Company__c;
            s.platform      = req.Current_Platform__c;
            s.createdDate   = req.CreatedDate;
            results.add(s);
        }
        return results;
    }
}
