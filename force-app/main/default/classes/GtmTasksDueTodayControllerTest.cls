/**
 * Tests for GtmTasksDueTodayController (issue
 * overview-bd-heat-redesign-3-daily-widgets). Every test creates its own
 * data; nothing reads or seeds live records.
 */
@IsTest
private class GtmTasksDueTodayControllerTest {

    private static Integer seq = 0;

    private static User createUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'Tasks ' + alias, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    private static User createViewAllUser(String alias) {
        User u = createUser(alias);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet ps = new PermissionSet(Name = 'TasksViewAll' + alias, Label = 'Tasks ViewAll ' + alias);
            insert ps;
            insert new ObjectPermissions(
                ParentId = ps.Id, SobjectType = 'GTM_Saved_Configuration__c',
                PermissionsRead = true, PermissionsViewAllRecords = true
            );
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    private static Account newAccount(String name) {
        return new Account(Name = name);
    }

    private static GTM_Saved_Configuration__c newLink(Id ownerId, Id accountId) {
        seq++;
        return new GTM_Saved_Configuration__c(
            OwnerId = ownerId, Offering__c = 'migration-accelerator', Company__c = 'Co ' + seq,
            Account__c = accountId, Generated_URL__c = 'https://example.com/task' + seq,
            Presentation_Stage__c = 'Sent', Active__c = true
        );
    }

    /** Same GTM link shape as newLink, but keyed off Opportunity__c instead
     *  of Account__c -- needed to put an Opportunity Id into the
     *  GTM-linked WhatId universe (issue tasks-widget-row-navigation's
     *  accountId-resolution tests). */
    private static GTM_Saved_Configuration__c newOpportunityLink(Id ownerId, Id opportunityId) {
        seq++;
        return new GTM_Saved_Configuration__c(
            OwnerId = ownerId, Offering__c = 'migration-accelerator', Company__c = 'Co ' + seq,
            Opportunity__c = opportunityId, Generated_URL__c = 'https://example.com/task' + seq,
            Presentation_Stage__c = 'Sent', Active__c = true
        );
    }

    private static Task newTask(Id ownerId, Id whatId, Date dueDate, Boolean closed) {
        seq++;
        return new Task(
            OwnerId = ownerId, WhatId = whatId, Subject = 'Task ' + seq,
            ActivityDate = dueDate, Status = closed ? 'Completed' : 'Not Started'
        );
    }

    @IsTest
    static void repSeesOnlyOwnOpenTasksDueTodayOrOverdueOnGtmLinkedWhat() {
        User repA = createUser('tdtrepa');
        User repB = createUser('tdtrepb');
        Account gtmAccount;
        Account nonGtmAccount;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            gtmAccount = newAccount('GTM Linked Co');
            nonGtmAccount = newAccount('No GTM Link Co');
            insert new List<Account>{ gtmAccount, nonGtmAccount };
            insert newLink(repA.Id, gtmAccount.Id);
        }

        Date today = Date.today();
        List<Task> tasks = new List<Task>{
            newTask(repA.Id, gtmAccount.Id, today, false),          // due today: included
            newTask(repA.Id, gtmAccount.Id, today.addDays(-3), false), // overdue: included
            newTask(repA.Id, gtmAccount.Id, today.addDays(2), false),  // future: excluded
            newTask(repA.Id, gtmAccount.Id, today, true),            // closed: excluded
            newTask(repA.Id, nonGtmAccount.Id, today, false),        // not GTM-linked: excluded
            newTask(repB.Id, gtmAccount.Id, today, false)            // other rep's task: excluded
        };
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert tasks;
        }

        List<GtmTasksDueTodayController.TaskRow> rows;
        System.runAs(repA) {
            rows = GtmTasksDueTodayController.getTasksDueToday();
        }
        System.assertEquals(2, rows.size(), 'only the due-today and overdue open tasks on the GTM-linked account');
        Set<Boolean> overdueFlags = new Set<Boolean>();
        for (GtmTasksDueTodayController.TaskRow r : rows) { overdueFlags.add(r.isOverdue); }
        System.assert(overdueFlags.contains(true), 'overdue task flagged');
        System.assert(overdueFlags.contains(false), 'due-today task not flagged overdue');
    }

    @IsTest
    static void repWithNoGtmLinksSeesNothing() {
        User rep = createUser('tdtrepl1');
        Account acct;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            acct = newAccount('Unlinked Co');
            insert acct;
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert newTask(rep.Id, acct.Id, Date.today(), false);
        }
        List<GtmTasksDueTodayController.TaskRow> rows;
        System.runAs(rep) {
            rows = GtmTasksDueTodayController.getTasksDueToday();
        }
        System.assertEquals(0, rows.size(), 'no GTM_Saved_Configuration__c means no linked-What universe');
    }

    @IsTest
    static void viewAllUserStillOnlySeesOwnTasksButUniverseIncludesEveryonesLinks() {
        User repA = createUser('tdtrepva');
        User admin = createViewAllUser('tdtradmv');
        Account acctA;
        Account acctAdmin;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            acctA = newAccount('Rep A Linked Co');
            acctAdmin = newAccount('Admin Linked Co');
            insert new List<Account>{ acctA, acctAdmin };
            insert newLink(repA.Id, acctA.Id);
            insert newLink(admin.Id, acctAdmin.Id);
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert newTask(admin.Id, acctA.Id, Date.today(), false);
            insert newTask(admin.Id, acctAdmin.Id, Date.today(), false);
        }
        List<GtmTasksDueTodayController.TaskRow> rows;
        System.runAs(admin) {
            rows = GtmTasksDueTodayController.getTasksDueToday();
        }
        // Task ownership is always "my tasks" -- both belong to admin, so both
        // are eligible; the viewAll grant only widens the linked-What universe.
        System.assertEquals(2, rows.size());
    }

    @IsTest
    static void executesNoDml() {
        User rep = createUser('tdtrepdm');
        Account acct;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            acct = newAccount('DML Check Co');
            insert acct;
            insert newLink(rep.Id, acct.Id);
            insert newTask(rep.Id, acct.Id, Date.today(), false);
        }
        Integer before;
        Integer after;
        System.runAs(rep) {
            before = Limits.getDmlStatements();
            GtmTasksDueTodayController.getTasksDueToday();
            after = Limits.getDmlStatements();
        }
        System.assertEquals(before, after, 'read-only');
    }

    // ----------------------------------------------------- accountId (issue
    // tasks-widget-row-navigation): TaskRow.whatId alone is polymorphic
    // (Account OR Opportunity per the class header) -- these assert the
    // resolved accountId is correct in both shapes, since that's exactly
    // what the row's own click-through to the Engagement Links tab depends
    // on.

    @IsTest
    static void taskRowResolvesAccountIdWhenWhatIdIsAlreadyTheAccount() {
        User rep = createUser('tdtaccwa');
        Account acct;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            acct = newAccount('Direct Account Co');
            insert acct;
            insert newLink(rep.Id, acct.Id);
            insert newTask(rep.Id, acct.Id, Date.today(), false);
        }
        List<GtmTasksDueTodayController.TaskRow> rows;
        System.runAs(rep) {
            rows = GtmTasksDueTodayController.getTasksDueToday();
        }
        System.assertEquals(1, rows.size());
        System.assertEquals(acct.Id, rows[0].whatId, 'whatId is the Account itself');
        System.assertEquals(acct.Id, rows[0].accountId, 'accountId resolves straight through when whatId IS the Account');
    }

    @IsTest
    static void taskRowResolvesAccountIdViaOpportunityAccountIdWhenWhatIdIsAnOpportunity() {
        User rep = createUser('tdtaccwo');
        Account acct;
        Opportunity opp;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            acct = newAccount('Opportunity Parent Co');
            insert acct;
            opp = new Opportunity(
                Name = 'Opportunity Parent Co Deal', AccountId = acct.Id,
                StageName = 'Qualification', CloseDate = Date.today().addMonths(1)
            );
            insert opp;
            insert newOpportunityLink(rep.Id, opp.Id);
            insert newTask(rep.Id, opp.Id, Date.today(), false);
        }
        List<GtmTasksDueTodayController.TaskRow> rows;
        System.runAs(rep) {
            rows = GtmTasksDueTodayController.getTasksDueToday();
        }
        System.assertEquals(1, rows.size());
        System.assertEquals(opp.Id, rows[0].whatId, 'whatId is the Opportunity');
        System.assertEquals(acct.Id, rows[0].accountId, 'accountId resolves via the Opportunity\'s own AccountId');
    }

    // ----------------------------------------------------- markTaskComplete
    // (issue tasks-widget-row-navigation): inline "Mark complete" checkbox
    // action, ownership-gated the same way
    // GtmReadoutController.selfApproveReadout gates self-approval.

    @IsTest
    static void ownerCanMarkTheirOwnTaskComplete() {
        User rep = createUser('tdtmcown');
        Account acct;
        Task t;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            acct = newAccount('Complete Me Co');
            insert acct;
            insert newLink(rep.Id, acct.Id);
            t = newTask(rep.Id, acct.Id, Date.today(), false);
            insert t;
        }

        System.runAs(rep) {
            GtmTasksDueTodayController.markTaskComplete(t.Id);
        }

        Task updated = [SELECT Status FROM Task WHERE Id = :t.Id];
        System.assertEquals('Completed', updated.Status, 'owner can complete their own task');

        List<GtmTasksDueTodayController.TaskRow> rows;
        System.runAs(rep) {
            rows = GtmTasksDueTodayController.getTasksDueToday();
        }
        System.assertEquals(0, rows.size(), 'a completed task is no longer due');
    }

    @IsTest
    static void nonOwnerCannotMarkAnotherUsersTaskComplete() {
        User repA = createUser('tdtmcowa');
        User repB = createUser('tdtmcowb');
        Account acct;
        Task t;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            acct = newAccount('Ownership Boundary Co');
            insert acct;
            insert newLink(repA.Id, acct.Id);
            t = newTask(repA.Id, acct.Id, Date.today(), false);
            insert t;
        }

        Boolean threw = false;
        String message = '';
        System.runAs(repB) {
            try {
                GtmTasksDueTodayController.markTaskComplete(t.Id);
            } catch (AuraHandledException e) {
                threw = true;
                message = e.getMessage();
            }
        }
        System.assert(threw, 'a non-owner must not be able to complete another rep\'s task');

        Task stillOpen = [SELECT Status FROM Task WHERE Id = :t.Id];
        System.assertNotEquals('Completed', stillOpen.Status, 'the task must be untouched after a rejected attempt');
    }

    @IsTest
    static void markTaskCompleteWithNullIdThrows() {
        User rep = createUser('tdtmcnul');
        Boolean threw = false;
        System.runAs(rep) {
            try {
                GtmTasksDueTodayController.markTaskComplete(null);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'a null task id must be rejected');
    }

    @IsTest
    static void markTaskCompleteOnAnAlreadyCompletedTaskIsANoOp() {
        User rep = createUser('tdtmcdon');
        Account acct;
        Task t;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            acct = newAccount('Already Done Co');
            insert acct;
            insert newLink(rep.Id, acct.Id);
            t = newTask(rep.Id, acct.Id, Date.today(), true);
            insert t;
        }

        System.runAs(rep) {
            GtmTasksDueTodayController.markTaskComplete(t.Id);
        }

        Task stillDone = [SELECT Status FROM Task WHERE Id = :t.Id];
        System.assertEquals('Completed', stillDone.Status, 'already-completed stays completed, no error thrown');
    }
}
