@IsTest
private class GtmContextualTasksControllerTest {

    private static GTM_Assessment_Request__c seedRequest(Id contactId, Id accountId) {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c  = 'Alex Rivera',
            Requester_Email__c = 'alex.rivera@example.com',
            Company__c         = 'Northwind Retail',
            Contact__c         = contactId,
            Account__c         = accountId
        );
        insert req;
        return req;
    }

    @IsTest
    static void returnsOpenTasksAgainstTheContact() {
        Contact con = new Contact(LastName = 'Prospect');
        insert con;
        GTM_Assessment_Request__c req = seedRequest(con.Id, null);
        insert new Task(WhatId = con.Id, OwnerId = UserInfo.getUserId(), Subject = 'Follow up', Status = 'Not Started');

        Test.startTest();
        List<GtmContextualTasksController.TaskRow> rows =
            GtmContextualTasksController.getOpenTasksForAssessmentRequest(req.Id);
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.areEqual(con.Id, rows[0].whatId);
        Assert.areEqual('Contact', rows[0].whatObjectType);
        Assert.areEqual('Follow up', rows[0].subject);
        Assert.areEqual('Not Started', rows[0].status);
    }

    @IsTest
    static void returnsOpenTasksAgainstTheAccountWhenNoContactIsResolved() {
        Account acc = new Account(Name = 'Fallback Co');
        insert acc;
        GTM_Assessment_Request__c req = seedRequest(null, acc.Id);
        insert new Task(WhatId = acc.Id, OwnerId = UserInfo.getUserId(), Subject = 'Nudge', Status = 'Not Started');

        Test.startTest();
        List<GtmContextualTasksController.TaskRow> rows =
            GtmContextualTasksController.getOpenTasksForAssessmentRequest(req.Id);
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.areEqual(acc.Id, rows[0].whatId);
        Assert.areEqual('Account', rows[0].whatObjectType);
    }

    @IsTest
    static void returnsTasksAgainstBothContactAndAccountWhenBothAreResolved() {
        Account acc = new Account(Name = 'Both Co');
        insert acc;
        Contact con = new Contact(LastName = 'Prospect', AccountId = acc.Id);
        insert con;
        GTM_Assessment_Request__c req = seedRequest(con.Id, acc.Id);
        insert new Task(WhatId = con.Id, OwnerId = UserInfo.getUserId(), Subject = 'Contact task', Status = 'Not Started');
        insert new Task(WhatId = acc.Id, OwnerId = UserInfo.getUserId(), Subject = 'Account task', Status = 'Not Started');

        Test.startTest();
        List<GtmContextualTasksController.TaskRow> rows =
            GtmContextualTasksController.getOpenTasksForAssessmentRequest(req.Id);
        Test.stopTest();

        Assert.areEqual(2, rows.size(),
            'A Task filed directly against the Account must still show even when the request also has a Contact');
    }

    @IsTest
    static void closedTasksAreExcluded() {
        Contact con = new Contact(LastName = 'Prospect');
        insert con;
        GTM_Assessment_Request__c req = seedRequest(con.Id, null);
        insert new Task(WhatId = con.Id, OwnerId = UserInfo.getUserId(), Subject = 'Done already', Status = 'Completed');

        Test.startTest();
        List<GtmContextualTasksController.TaskRow> rows =
            GtmContextualTasksController.getOpenTasksForAssessmentRequest(req.Id);
        Test.stopTest();

        Assert.areEqual(0, rows.size(), 'A closed Task must not appear in the contextual widget');
    }

    @IsTest
    static void doesNotScopeToTheRunningUsersOwnTasksOnly() {
        // Deliberately the opposite of GtmTasksDueTodayController's own
        // "my tasks" scope -- this widget shows every open Task on the
        // record regardless of who owns it (issue #31, Architect decision
        // #4: "every open Task on THIS Contact/Account", not "my tasks").
        Contact con = new Contact(LastName = 'Prospect');
        insert con;
        GTM_Assessment_Request__c req = seedRequest(con.Id, null);
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = 'other' + String.valueOf(Crypto.getRandomInteger()).replace('-', 'x');
        User other = new User(
            Alias = 'other1', Email = uniq + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = uniq, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = uniq + '@gtmtest.example.com'
        );
        insert other;
        insert new Task(WhatId = con.Id, OwnerId = other.Id, Subject = 'Owned by someone else', Status = 'Not Started');

        Test.startTest();
        List<GtmContextualTasksController.TaskRow> rows =
            GtmContextualTasksController.getOpenTasksForAssessmentRequest(req.Id);
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'A Task owned by a different user must still appear');
    }

    @IsTest
    static void aRequestWithNeitherContactNorAccountReturnsEmpty() {
        GTM_Assessment_Request__c req = seedRequest(null, null);

        Test.startTest();
        List<GtmContextualTasksController.TaskRow> rows =
            GtmContextualTasksController.getOpenTasksForAssessmentRequest(req.Id);
        Test.stopTest();

        Assert.areEqual(0, rows.size());
    }

    @IsTest
    static void aNullOrNonexistentAssessmentRequestIdReturnsEmptyWithoutThrowing() {
        Test.startTest();
        List<GtmContextualTasksController.TaskRow> nullResult =
            GtmContextualTasksController.getOpenTasksForAssessmentRequest(null);
        Test.stopTest();

        Assert.areEqual(0, nullResult.size());
    }

    @IsTest
    static void isOverdueReflectsActivityDateInThePast() {
        Contact con = new Contact(LastName = 'Prospect');
        insert con;
        GTM_Assessment_Request__c req = seedRequest(con.Id, null);
        insert new Task(
            WhatId = con.Id, OwnerId = UserInfo.getUserId(), Subject = 'Overdue nudge',
            Status = 'Not Started', ActivityDate = Date.today().addDays(-3)
        );
        insert new Task(
            WhatId = con.Id, OwnerId = UserInfo.getUserId(), Subject = 'No due date yet',
            Status = 'Not Started'
        );

        Test.startTest();
        List<GtmContextualTasksController.TaskRow> rows =
            GtmContextualTasksController.getOpenTasksForAssessmentRequest(req.Id);
        Test.stopTest();

        Map<String, Boolean> overdueBySubject = new Map<String, Boolean>();
        for (GtmContextualTasksController.TaskRow r : rows) {
            overdueBySubject.put(r.subject, r.isOverdue);
        }
        Assert.areEqual(true, overdueBySubject.get('Overdue nudge'));
        Assert.areEqual(false, overdueBySubject.get('No due date yet'),
            'A Task with no ActivityDate at all must not be misreported as overdue');
    }
}
