/**
 * Backing controller for the contextual-task widget mounted inside
 * gtmReadoutWorkspace (issue #31) -- shared by both "open Page"/"open
 * Assessment" entry paths (gtmRepLinkFinder/GTM_Pages and
 * gtmReadoutsOverview/GTM_Assessments, per
 * lwc/gtmRepLinkFinder/gtmRepLinkFinder.html:146-151 and
 * lwc/gtmReadoutsOverview/gtmReadoutsOverview.html:10-16, both of which
 * mount c-gtm-readout-workspace).
 *
 * A SCOPED REUSE of GtmTasksDueTodayController's query shape, not the same
 * component verbatim (issue #31, Architect decision #4): that controller's
 * getTasksDueToday() is hardcoded to "the running user's own open Tasks...
 * due today or overdue" -- this widget needs "every open Task on THIS
 * Contact/Account, regardless of owner or due date", a genuinely different
 * WHERE clause, so it is its own narrow class rather than a bent extension
 * of that one's existing contract.
 *
 * Takes assessmentRequestId, not a Contact/Account Id directly (Architect
 * decision #4's correction to the BA's original phrasing): gtmReadoutWorkspace
 * already has assessmentRequestId as @api, but its own REQUEST_FIELDS wire
 * (gtmReadoutWorkspace.js) only pulls Contact__r.Name/Account__r.Name
 * (display strings) via the standard UI API, never the raw Contact__c/
 * Account__c Id fields -- widening that wire was rejected in favor of one
 * narrow server-side resolution here, keeping the widget's public API to a
 * single Id.
 *
 * `with sharing`: only ever called from an authenticated rep context
 * (GTM_Pages/GTM_Assessments are both internal, not guest-facing).
 */
public with sharing class GtmContextualTasksController {

    private static final Integer TASK_LIMIT = 50;

    public class TaskRow {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String subject;
        @AuraEnabled public Date activityDate;
        @AuraEnabled public Boolean isOverdue = false;
        @AuraEnabled public String status;
        /** The Contact or Account Id this row's Task is filed against --
         *  read off Task.WhoId for a Contact target, Task.WhatId for an
         *  Account target (Salesforce Task field integrity: Contact/Lead
         *  targets can only ever live on WhoId). Named whatId, not whoId,
         *  purely to match this widget's existing public/LWC contract
         *  (gtmContextualTasksWidget.js's data-what-id/data-what-object-type
         *  navigation attributes) -- it does not mean this Id necessarily
         *  came off the Task row's own WhatId field. */
        @AuraEnabled public Id whatId;
        /** 'Contact' or 'Account' -- which of the two whatId is, so the LWC
         *  can navigate to the right objectApiName without sniffing the Id
         *  prefix client-side. */
        @AuraEnabled public String whatObjectType;
    }

    /**
     * Every open (IsClosed = false) Task against the Contact (when present)
     * and/or Account behind assessmentRequestId -- both, not a
     * coalesce-to-one-or-the-other like the Task-firing side
     * (GtmLifecycleNotificationService.syncEngagementStateTask) uses, since
     * this is a read/display surface: a Task genuinely filed against the
     * Account should still show up here even when the request also has a
     * Contact.
     */
    @AuraEnabled(cacheable=false)
    public static List<TaskRow> getOpenTasksForAssessmentRequest(Id assessmentRequestId) {
        try {
            return compute(assessmentRequestId);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    private static List<TaskRow> compute(Id assessmentRequestId) {
        List<TaskRow> out = new List<TaskRow>();
        if (assessmentRequestId == null) {
            return out;
        }

        List<GTM_Assessment_Request__c> reqs = [
            SELECT Contact__c, Account__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :assessmentRequestId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (reqs.isEmpty()) {
            return out;
        }

        // Contact and Account targets live on two different Task fields --
        // Salesforce only allows a Contact/Lead Id on WhoId, never WhatId
        // (FIELD_INTEGRITY_EXCEPTION at DML time otherwise; see
        // GtmLifecycleNotificationService.isWhoIdTarget, the fire-side half
        // of this same contract). A Contact target's open Task is therefore
        // found via WhoId, not WhatId -- querying WhatId alone (the
        // pre-issue-#31 shape) would silently return zero rows for every
        // Contact-targeted Task even though it was correctly created.
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        if (reqs[0].Contact__c != null) { contactIds.add(reqs[0].Contact__c); }
        if (reqs[0].Account__c != null) { accountIds.add(reqs[0].Account__c); }
        if (contactIds.isEmpty() && accountIds.isEmpty()) {
            return out;
        }

        Date today = Date.today();
        for (Task t : [
            SELECT Id, Subject, ActivityDate, Status, WhatId, WhoId
            FROM Task
            WHERE (WhoId IN :contactIds OR WhatId IN :accountIds)
              AND IsClosed = false
            ORDER BY ActivityDate ASC NULLS LAST, Subject ASC
            LIMIT :TASK_LIMIT
        ]) {
            TaskRow row = new TaskRow();
            row.taskId = t.Id;
            row.subject = t.Subject;
            row.activityDate = t.ActivityDate;
            row.isOverdue = t.ActivityDate != null && t.ActivityDate < today;
            row.status = t.Status;
            // A Contact-targeted row's navigable Id is on WhoId; an
            // Account-targeted row's is on WhatId -- never both, per the
            // split above.
            row.whatId = t.WhoId != null ? t.WhoId : t.WhatId;
            row.whatObjectType = t.WhoId != null ? 'Contact' : 'Account';
            out.add(row);
        }
        return out;
    }
}
