/**
 * "Your tasks due today" widget on the Overview Today view (issue
 * overview-bd-heat-redesign-3-daily-widgets). getTasksDueToday() itself
 * stays read-only (SOQL only, no callouts) -- executesNoDml in the test
 * class still asserts that. markTaskComplete() (issue
 * tasks-widget-row-navigation) is this class's one deliberate exception:
 * a small, ownership-gated single-record update, same shape as
 * GtmReadoutController.selfApproveReadout's own owner check.
 *
 * Scope: the running user's OWN open Tasks (OwnerId = the running user --
 * this widget is deliberately "my tasks", not the owner-vs-viewAll toggle
 * used elsewhere in this app for records the rep doesn't personally own),
 * due today or overdue, whose WhatId is an Account or Opportunity that has
 * at least one GTM_Saved_Configuration__c (a GTM link). That second filter
 * is what keeps this widget from becoming "every Task the rep has", per the
 * task-scope doc.
 *
 * The GTM-linked universe query follows the owner-scoped-unless-viewAll
 * convention established by GtmOverviewOfferingCounts / GtmLinkStageService
 * (private hasViewAllRecords probe, no shared helper -- see the TODO on
 * GtmOverviewOfferingCounts about eventually de-duplicating this).
 */
public with sharing class GtmTasksDueTodayController {

    private static final Integer TASK_LIMIT = 50;
    private static final Integer WHATID_UNIVERSE_LIMIT = 10000;

    public class TaskRow {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String subject;
        @AuraEnabled public Date activityDate;
        @AuraEnabled public Boolean isOverdue = false;
        @AuraEnabled public Id whatId;
        @AuraEnabled public String whatName;
        @AuraEnabled public String priority;
        /** The Account behind whatId, resolved regardless of whether whatId
         *  itself is the Account or an Opportunity on that Account (issue
         *  tasks-widget-row-navigation) -- what the row's own click-through
         *  to the Engagement Links landing tab needs; whatId alone is not
         *  enough since it is polymorphic (see class header). Null on the
         *  rare row whose Opportunity has no AccountId. */
        @AuraEnabled public Id accountId;
    }

    @AuraEnabled(cacheable=false)
    public static List<TaskRow> getTasksDueToday() {
        try {
            return compute();
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    private static List<TaskRow> compute() {
        Date today = Date.today();
        Set<Id> gtmWhatIds = gtmLinkedWhatIds();
        List<TaskRow> out = new List<TaskRow>();
        if (gtmWhatIds.isEmpty()) { return out; }

        List<Task> tasks = [
            SELECT Id, Subject, ActivityDate, WhatId, What.Name, Priority
            FROM Task
            WHERE OwnerId = :UserInfo.getUserId()
              AND IsClosed = false
              AND ActivityDate != null
              AND ActivityDate <= :today
              AND WhatId IN :gtmWhatIds
            ORDER BY ActivityDate ASC, Subject ASC
            LIMIT :TASK_LIMIT
        ];

        Set<Id> whatIds = new Set<Id>();
        for (Task t : tasks) { whatIds.add(t.WhatId); }
        Map<Id, Id> accountIdByWhatId = accountIdsByWhatId(whatIds);

        for (Task t : tasks) {
            TaskRow row = new TaskRow();
            row.taskId = t.Id;
            row.subject = t.Subject;
            row.activityDate = t.ActivityDate;
            row.isOverdue = t.ActivityDate < today;
            row.whatId = t.WhatId;
            row.whatName = t.What == null ? null : t.What.Name;
            row.priority = t.Priority;
            row.accountId = accountIdByWhatId.get(t.WhatId);
            out.add(row);
        }
        return out;
    }

    /**
     * Resolves each whatId to the Account "behind" it -- whatId itself when
     * it IS an Account, or that Opportunity's AccountId when it is an
     * Opportunity (WhatId is polymorphic across both, per this class's own
     * header) -- what the row's click-through to the Engagement Links
     * landing tab needs (issue tasks-widget-row-navigation). One extra
     * query only for the Opportunity subset, bounded by TASK_LIMIT since
     * whatIds here always comes from an already-limited task list. A
     * WhatId that resolves to neither (e.g. some other What type, or an
     * Opportunity with no Account) is simply absent from the returned map
     * -- callers treat that as "no account to scope to", not an error.
     */
    private static Map<Id, Id> accountIdsByWhatId(Set<Id> whatIds) {
        Map<Id, Id> out = new Map<Id, Id>();
        if (whatIds == null || whatIds.isEmpty()) { return out; }
        Set<Id> opportunityIds = new Set<Id>();
        for (Id whatId : whatIds) {
            if (whatId.getSObjectType() == Account.SObjectType) {
                out.put(whatId, whatId);
            } else if (whatId.getSObjectType() == Opportunity.SObjectType) {
                opportunityIds.add(whatId);
            }
        }
        if (!opportunityIds.isEmpty()) {
            for (Opportunity o : [SELECT Id, AccountId FROM Opportunity WHERE Id IN :opportunityIds]) {
                if (o.AccountId != null) {
                    out.put(o.Id, o.AccountId);
                }
            }
        }
        return out;
    }

    /**
     * Marks one of the running user's own Tasks Completed, inline from the
     * widget row (issue tasks-widget-row-navigation) -- no navigation. The
     * row simply drops out of the next getTasksDueToday() call once closed,
     * since IsClosed = false is already part of that query's WHERE clause.
     *
     * Ownership-gated the same way GtmReadoutController.selfApproveReadout
     * gates self-approval: only the Task's own OwnerId may complete it
     * here. This mirrors getTasksDueToday()'s own "my tasks" scope (class
     * header) -- a rep should not be able to complete a colleague's Task
     * through this widget even if some other sharing rule would let them
     * see or edit it.
     */
    @AuraEnabled
    public static void markTaskComplete(Id taskId) {
        if (taskId == null) {
            throw new AuraHandledException('A task id is required.');
        }
        List<Task> tasks = [
            SELECT Id, OwnerId, Status
            FROM Task
            WHERE Id = :taskId
            LIMIT 1
        ];
        if (tasks.isEmpty()) {
            throw new AuraHandledException('Task not found.');
        }
        Task t = tasks[0];
        if (t.OwnerId != UserInfo.getUserId()) {
            throw new AuraHandledException('Only this task\'s owner can mark it complete.');
        }
        if (t.Status == 'Completed') {
            return;
        }
        t.Status = 'Completed';
        update t;
    }

    /** Account and Opportunity ids that have at least one GTM_Saved_Configuration__c
     *  link -- owner-scoped unless the running user holds View All on that object,
     *  same convention as GtmOverviewOfferingCounts.getOfferingCounts(). */
    private static Set<Id> gtmLinkedWhatIds() {
        Id currentUserId = UserInfo.getUserId();
        Integer queryLimit = WHATID_UNIVERSE_LIMIT;
        String query = 'SELECT Account__c, Opportunity__c FROM GTM_Saved_Configuration__c'
            + ' WHERE (Account__c != null OR Opportunity__c != null)';
        if (!hasViewAllRecords('GTM_Saved_Configuration__c')) {
            query += ' AND OwnerId = :currentUserId';
        }
        query += ' LIMIT :queryLimit';
        Set<Id> whatIds = new Set<Id>();
        for (GTM_Saved_Configuration__c cfg : Database.query(query)) {
            if (cfg.Account__c != null) { whatIds.add(cfg.Account__c); }
            if (cfg.Opportunity__c != null) { whatIds.add(cfg.Opportunity__c); }
        }
        return whatIds;
    }

    // Private copy of the same probe used by GtmOverviewOfferingCounts /
    // GtmReadoutController -- see the TODO on GtmOverviewOfferingCounts about
    // eventually de-duplicating this onto a shared helper.
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
