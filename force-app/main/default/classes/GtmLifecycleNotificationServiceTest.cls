@isTest
private class GtmLifecycleNotificationServiceTest {

    private static GTM_Assessment_Request__c seedRequest() {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c   = 'Alex Rivera',
            Requester_Email__c  = 'alex.rivera@example.com',
            Company__c          = 'Northwind Retail',
            Status__c           = 'New'
        );
        insert req;
        return req;
    }

    @isTest
    static void fireTaskCreatesAnOpenTaskAgainstWhatId() {
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        GtmLifecycleNotificationService.fireTask(
            req.Id, UserInfo.getUserId(),
            GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, 'Detail text.');
        Test.stopTest();

        List<Task> tasks = [SELECT WhatId, OwnerId, Subject, Status, Description FROM Task WHERE WhatId = :req.Id];
        Assert.areEqual(1, tasks.size());
        Assert.areEqual(GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, tasks[0].Subject);
        Assert.areEqual('Not Started', tasks[0].Status);
        Assert.areEqual(UserInfo.getUserId(), tasks[0].OwnerId);
        Assert.areEqual('Detail text.', tasks[0].Description);
    }

    @isTest
    static void fireTaskIsANoOpWhenWhatIdOrOwnerIdIsMissing() {
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        GtmLifecycleNotificationService.fireTask(null, UserInfo.getUserId(), 'Subject', 'Body');
        GtmLifecycleNotificationService.fireTask(req.Id, null, 'Subject', 'Body');
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :req.Id]);
    }

    @isTest
    static void closeOpenTasksClosesOnlyExactWhatIdAndSubjectMatches() {
        GTM_Assessment_Request__c reqA = seedRequest();
        GTM_Assessment_Request__c reqB = seedRequest();

        insert new Task(
            WhatId = reqA.Id, OwnerId = UserInfo.getUserId(),
            Subject = GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, Status = 'Not Started'
        );
        insert new Task(
            WhatId = reqA.Id, OwnerId = UserInfo.getUserId(),
            Subject = 'A different subject', Status = 'Not Started'
        );
        insert new Task(
            WhatId = reqB.Id, OwnerId = UserInfo.getUserId(),
            Subject = GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, Status = 'Not Started'
        );

        Test.startTest();
        GtmLifecycleNotificationService.closeOpenTasks(
            reqA.Id, GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST);
        Test.stopTest();

        Map<Id, Task> byId = new Map<Id, Task>([SELECT WhatId, Subject, Status FROM Task]);
        for (Task t : byId.values()) {
            if (t.WhatId == reqA.Id && t.Subject == GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST) {
                Assert.areEqual('Completed', t.Status, 'The exact WhatId+Subject match should be closed');
            } else {
                Assert.areNotEqual('Completed', t.Status, 'Every other Task must be left alone');
            }
        }
    }

    @isTest
    static void closeOpenTasksIsBulkSafeAcrossMultipleOpenMatches() {
        GTM_Assessment_Request__c req = seedRequest();
        insert new List<Task> {
            new Task(WhatId = req.Id, OwnerId = UserInfo.getUserId(),
                Subject = GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, Status = 'Not Started'),
            new Task(WhatId = req.Id, OwnerId = UserInfo.getUserId(),
                Subject = GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, Status = 'In Progress')
        };

        Test.startTest();
        GtmLifecycleNotificationService.closeOpenTasks(
            req.Id, GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST);
        Test.stopTest();

        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Task WHERE WhatId = :req.Id AND Status = 'Completed'],
            'Every open matching Task should be closed, not just the first'
        );
    }

    @isTest
    static void closeOpenTasksIsANoOpWhenThereIsNoMatch() {
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        // Should not throw even though nothing matches.
        GtmLifecycleNotificationService.closeOpenTasks(req.Id, 'Nothing fired this Subject');
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :req.Id]);
    }

    @isTest
    static void fireBellDoesNotThrowForAValidRecipient() {
        GTM_Assessment_Request__c req = seedRequest();

        Test.startTest();
        // Messaging.sendCustomNotification cannot actually deliver in test
        // context; this only proves the call is wrapped so a lifecycle
        // transition never fails because of it.
        GtmLifecycleNotificationService.fireBell(
            UserInfo.getUserId(), req.Id, 'Title', 'Body');
        Test.stopTest();

        Assert.isTrue(true, 'fireBell must complete without throwing');
    }

    @isTest
    static void fireBellIsANoOpWithNoRecipient() {
        Test.startTest();
        GtmLifecycleNotificationService.fireBell(null, null, 'Title', 'Body');
        Test.stopTest();

        Assert.isTrue(true, 'A null recipient must be a silent no-op');
    }

    @isTest
    static void fireTasksBulkCreatesOneTaskPerRequestWithOneDmlStatement() {
        GTM_Assessment_Request__c reqA = seedRequest();
        GTM_Assessment_Request__c reqB = seedRequest();
        GTM_Assessment_Request__c reqC = seedRequest();
        List<GtmLifecycleNotificationService.TaskRequest> requests =
            new List<GtmLifecycleNotificationService.TaskRequest> {
                new GtmLifecycleNotificationService.TaskRequest(
                    reqA.Id, UserInfo.getUserId(), GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, 'A'),
                new GtmLifecycleNotificationService.TaskRequest(
                    reqB.Id, UserInfo.getUserId(), GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, 'B'),
                new GtmLifecycleNotificationService.TaskRequest(
                    reqC.Id, UserInfo.getUserId(), GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, 'C')
            };

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        GtmLifecycleNotificationService.fireTasksBulk(requests);
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.areEqual(1, dmlUsed, 'fireTasksBulk must batch every requested Task into one DML statement');
        Assert.areEqual(
            3,
            [SELECT COUNT() FROM Task WHERE WhatId IN :new Set<Id> { reqA.Id, reqB.Id, reqC.Id }
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST]
        );
    }

    @isTest
    static void fireTasksBulkSkipsInvalidRequestsButStillInsertsTheRest() {
        GTM_Assessment_Request__c req = seedRequest();
        List<GtmLifecycleNotificationService.TaskRequest> requests =
            new List<GtmLifecycleNotificationService.TaskRequest> {
                new GtmLifecycleNotificationService.TaskRequest(
                    null, UserInfo.getUserId(), GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, 'Bad whatId'),
                new GtmLifecycleNotificationService.TaskRequest(
                    req.Id, null, GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, 'Bad ownerId'),
                new GtmLifecycleNotificationService.TaskRequest(
                    req.Id, UserInfo.getUserId(), GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, 'Good')
            };

        Test.startTest();
        GtmLifecycleNotificationService.fireTasksBulk(requests);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :req.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST],
            'Only the one well-formed request should have produced a Task'
        );
    }

    @isTest
    static void closeOpenTasksBulkClosesMatchingTasksAcrossMultipleWhatIdsWithOneDmlStatement() {
        GTM_Assessment_Request__c reqA = seedRequest();
        GTM_Assessment_Request__c reqB = seedRequest();
        GTM_Assessment_Request__c reqC = seedRequest();
        insert new List<Task> {
            new Task(WhatId = reqA.Id, OwnerId = UserInfo.getUserId(),
                Subject = GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, Status = 'Not Started'),
            new Task(WhatId = reqB.Id, OwnerId = UserInfo.getUserId(),
                Subject = GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST, Status = 'Not Started'),
            // Different subject on the same WhatId -- must be left alone.
            new Task(WhatId = reqC.Id, OwnerId = UserInfo.getUserId(),
                Subject = 'A different subject', Status = 'Not Started')
        };

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        Integer queriesBefore = Limits.getQueries();
        GtmLifecycleNotificationService.closeOpenTasksBulk(
            new Set<Id> { reqA.Id, reqB.Id, reqC.Id }, GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST);
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        Assert.areEqual(1, queriesUsed, 'closeOpenTasksBulk must issue one aggregate query across the whole set');
        Assert.areEqual(1, dmlUsed, 'closeOpenTasksBulk must issue one aggregate update across the whole set');

        Map<Id, Task> byId = new Map<Id, Task>([SELECT WhatId, Subject, Status FROM Task]);
        for (Task t : byId.values()) {
            if (t.Subject == GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST) {
                Assert.areEqual('Completed', t.Status, 'Every matching Task across the whole set should close');
            } else {
                Assert.areNotEqual('Completed', t.Status, 'A Task with a different Subject must be left alone');
            }
        }
    }

    @isTest
    static void closeOpenTasksBulkIsANoOpWithAnEmptySet() {
        Test.startTest();
        // Should not throw even with an empty/null set.
        GtmLifecycleNotificationService.closeOpenTasksBulk(new Set<Id>(), GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST);
        GtmLifecycleNotificationService.closeOpenTasksBulk(null, GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST);
        Test.stopTest();

        Assert.isTrue(true, 'An empty or null whatIds set must be a silent no-op');
    }

    // ------------------------------------------- syncEngagementStateTask
    // (issue #31 -- the fire/close orchestration behind the five wired
    // engagement-state call sites in GtmLinkEventController/
    // GtmAssessmentRequestController/GtmReadoutController.)

    private static Contact seedContact() {
        Contact c = new Contact(LastName = 'Prospect');
        insert c;
        return c;
    }

    @isTest
    static void syncFiresTheCorrectSubjectForEachFireableState() {
        Map<String, String> expected = new Map<String, String>{
            GtmEngagementStateClassifier.STATE_OPENED          => GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_OPENED,
            GtmEngagementStateClassifier.STATE_STARTED         => GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_STARTED,
            GtmEngagementStateClassifier.STATE_SUBMITTED_DRAFT => GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_SUBMITTED,
            GtmEngagementStateClassifier.STATE_PUBLISHED_UNSENT => GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_PUBLISHED_UNSENT
        };
        for (String state : expected.keySet()) {
            Contact c = seedContact();
            Test.startTest();
            GtmLifecycleNotificationService.syncEngagementStateTask(c.Id, UserInfo.getUserId(), state);
            Test.stopTest();

            List<Task> tasks = [SELECT Subject, OwnerId, Status FROM Task WHERE WhatId = :c.Id];
            Assert.areEqual(1, tasks.size(), 'Exactly one Task should fire for ' + state);
            Assert.areEqual(expected.get(state), tasks[0].Subject, 'Wrong subject for ' + state);
            Assert.areEqual('Not Started', tasks[0].Status);
            Assert.areEqual(UserInfo.getUserId(), tasks[0].OwnerId);
        }
    }

    @isTest
    static void syncFiresNothingForSentCompleteOrNeverOpened() {
        Contact c1 = seedContact();
        Contact c2 = seedContact();

        Test.startTest();
        GtmLifecycleNotificationService.syncEngagementStateTask(
            c1.Id, UserInfo.getUserId(), GtmEngagementStateClassifier.STATE_SENT_COMPLETE);
        GtmLifecycleNotificationService.syncEngagementStateTask(
            c2.Id, UserInfo.getUserId(), GtmEngagementStateClassifier.STATE_NEVER_OPENED);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :c1.Id]);
        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :c2.Id]);
    }

    @isTest
    static void syncIsIdempotentAcrossRepeatCallsAtTheSameState() {
        Contact c = seedContact();

        Test.startTest();
        GtmLifecycleNotificationService.syncEngagementStateTask(
            c.Id, UserInfo.getUserId(), GtmEngagementStateClassifier.STATE_OPENED);
        // A second prospect visit re-firing the same state (e.g. a repeat
        // Page View while still opened_not_started) must not spawn a
        // duplicate open Task.
        GtmLifecycleNotificationService.syncEngagementStateTask(
            c.Id, UserInfo.getUserId(), GtmEngagementStateClassifier.STATE_OPENED);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :c.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_OPENED],
            'Repeat calls at the same state must not create a duplicate open Task'
        );
    }

    @isTest
    static void syncAdvancingToAHigherStateClosesTheLowerOpenTask() {
        Contact c = seedContact();
        GtmLifecycleNotificationService.syncEngagementStateTask(
            c.Id, UserInfo.getUserId(), GtmEngagementStateClassifier.STATE_OPENED);

        Test.startTest();
        GtmLifecycleNotificationService.syncEngagementStateTask(
            c.Id, UserInfo.getUserId(), GtmEngagementStateClassifier.STATE_STARTED);
        Test.stopTest();

        Assert.areEqual(
            'Completed',
            [SELECT Status FROM Task WHERE WhatId = :c.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_OPENED LIMIT 1].Status,
            'opened_not_started\'s Task must close once started_not_submitted fires'
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :c.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_STARTED
                AND Status != 'Completed'],
            'started_not_submitted\'s own Task should be open'
        );
    }

    @isTest
    static void syncSkippingRanksClosesEveryLowerOpenTaskNotJustTheImmediatelyPriorOne() {
        // never_opened -> submitted_draft directly (a prospect who fills
        // the form fast), skipping opened_not_started/started_not_submitted
        // entirely -- both of their Tasks (fired earlier in this test to
        // simulate a link that WAS opened/started first) must still close.
        Contact c = seedContact();
        GtmLifecycleNotificationService.syncEngagementStateTask(
            c.Id, UserInfo.getUserId(), GtmEngagementStateClassifier.STATE_OPENED);
        GtmLifecycleNotificationService.syncEngagementStateTask(
            c.Id, UserInfo.getUserId(), GtmEngagementStateClassifier.STATE_STARTED);

        Test.startTest();
        GtmLifecycleNotificationService.syncEngagementStateTask(
            c.Id, UserInfo.getUserId(), GtmEngagementStateClassifier.STATE_SUBMITTED_DRAFT);
        Test.stopTest();

        Map<String, String> statusBySubject = new Map<String, String>();
        for (Task t : [SELECT Subject, Status FROM Task WHERE WhatId = :c.Id]) {
            statusBySubject.put(t.Subject, t.Status);
        }
        Assert.areEqual('Completed', statusBySubject.get(GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_OPENED));
        Assert.areEqual('Completed', statusBySubject.get(GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_STARTED));
        Assert.areNotEqual('Completed', statusBySubject.get(GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_SUBMITTED));
    }

    @isTest
    static void syncSentCompleteClosesThePublishedUnsentTaskWithoutFiringAnythingNew() {
        Contact c = seedContact();
        GtmLifecycleNotificationService.syncEngagementStateTask(
            c.Id, UserInfo.getUserId(), GtmEngagementStateClassifier.STATE_PUBLISHED_UNSENT);

        Test.startTest();
        // ownerId is deliberately null here -- sendPublishNotification's own
        // call site has no owner to pass for a close-only transition.
        GtmLifecycleNotificationService.syncEngagementStateTask(
            c.Id, null, GtmEngagementStateClassifier.STATE_SENT_COMPLETE);
        Test.stopTest();

        Assert.areEqual(
            'Completed',
            [SELECT Status FROM Task WHERE WhatId = :c.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_PUBLISHED_UNSENT LIMIT 1].Status
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :c.Id],
            'sent_complete must close the prior Task and fire nothing new -- exactly one Task total'
        );
    }

    @isTest
    static void syncIsANoOpWithNoWhatIdOrBlankState() {
        Contact c = seedContact();

        Test.startTest();
        GtmLifecycleNotificationService.syncEngagementStateTask(
            null, UserInfo.getUserId(), GtmEngagementStateClassifier.STATE_OPENED);
        GtmLifecycleNotificationService.syncEngagementStateTask(c.Id, UserInfo.getUserId(), null);
        GtmLifecycleNotificationService.syncEngagementStateTask(c.Id, UserInfo.getUserId(), '');
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :c.Id]);
    }

    @isTest
    static void syncFireStepIsANoOpWithNoOwnerIdButCloseStepStillRuns() {
        Contact c = seedContact();
        GtmLifecycleNotificationService.syncEngagementStateTask(
            c.Id, UserInfo.getUserId(), GtmEngagementStateClassifier.STATE_OPENED);

        Test.startTest();
        // No ownerId -- the fire half must no-op, but the close-every-other-
        // subject half must still run (a null ownerId is only ever passed
        // by a close-only call site, but this proves the method degrades
        // safely even for a would-be-fireable state).
        GtmLifecycleNotificationService.syncEngagementStateTask(
            c.Id, null, GtmEngagementStateClassifier.STATE_STARTED);
        Test.stopTest();

        Assert.areEqual(
            'Completed',
            [SELECT Status FROM Task WHERE WhatId = :c.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_OPENED LIMIT 1].Status,
            'The close-every-other-subject sweep must still run even when ownerId is null'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Task WHERE WhatId = :c.Id
                AND Subject = :GtmLifecycleNotificationService.SUBJECT_ENGAGEMENT_STARTED],
            'No ownerId means the fire step must no-op'
        );
    }
}
