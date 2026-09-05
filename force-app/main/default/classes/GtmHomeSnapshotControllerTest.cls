@IsTest
private class GtmHomeSnapshotControllerTest {
    @IsTest
    static void summarizesActiveLinksAndOpenAssessments() {
        MA_Saved_Configuration__c activeWithValue = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/a',
            Active__c = true,
            Estimated_Value__c = 50000
        );
        MA_Saved_Configuration__c activeNoValue = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Beta Co',
            Generated_URL__c = 'https://example.com/b',
            Active__c = true
        );
        MA_Saved_Configuration__c inactive = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Gamma Inc',
            Generated_URL__c = 'https://example.com/c',
            Active__c = false,
            Estimated_Value__c = 999999
        );
        insert new List<MA_Saved_Configuration__c>{ activeWithValue, activeNoValue, inactive };

        insert new MA_Assessment_Request__c(
            Requester_Name__c = 'Alex Rivera',
            Requester_Email__c = 'alex@example.com',
            Status__c = 'New'
        );
        insert new MA_Assessment_Request__c(
            Requester_Name__c = 'Jordan Lee',
            Requester_Email__c = 'jordan@example.com',
            Status__c = 'Contacted'
        );

        Opportunity openOpp = new Opportunity(
            Name = 'Acme Bank Migration',
            StageName = 'Qualification',
            CloseDate = Date.today().addMonths(2),
            Amount = 75000
        );
        insert openOpp;
        activeWithValue.Opportunity__c = openOpp.Id;
        update activeWithValue;

        Test.startTest();
        GtmHomeSnapshotController.Snapshot snap = GtmHomeSnapshotController.getSnapshot();
        Test.stopTest();

        Assert.areEqual(2, snap.activeEngagementCount);
        Assert.areEqual(1, snap.newAssessmentCount);
    }

    @IsTest
    static void returnsRecentNewRequestsOnlyNewestFirst() {
        insert new MA_Assessment_Request__c(
            Requester_Name__c = 'Alex Rivera',
            Requester_Email__c = 'alex@example.com',
            Company__c = 'Acme Bank',
            Status__c = 'New'
        );
        insert new MA_Assessment_Request__c(
            Requester_Name__c = 'Already Handled',
            Requester_Email__c = 'handled@example.com',
            Status__c = 'Contacted'
        );

        Test.startTest();
        List<GtmHomeSnapshotController.RequestSummary> results =
            GtmHomeSnapshotController.getRecentNewAssessmentRequests();
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Only Status = New should be returned');
        Assert.areEqual('Alex Rivera', results[0].requesterName);
        Assert.areEqual('Acme Bank', results[0].company);
    }

    @IsTest
    static void returnsZeroesWhenNothingExists() {
        Test.startTest();
        GtmHomeSnapshotController.Snapshot snap = GtmHomeSnapshotController.getSnapshot();
        Test.stopTest();

        Assert.areEqual(0, snap.activeEngagementCount);
        Assert.areEqual(0, snap.newAssessmentCount);
    }

    /**
     * The funnel that made the deals card necessary: one deal that converted,
     * one that opened the form and left. They must not read the same.
     */
    @IsTest
    static void aDealCarriesTheFunnelAndTheRequestBehindIt() {
        Account acct = new Account(Name = 'Acme Bank');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Acme Bank — Migration Accelerator', AccountId = acct.Id,
            StageName = 'Qualification', CloseDate = Date.today().addMonths(2), Amount = 75000
        );
        Opportunity stalledOpp = new Opportunity(
            Name = 'Beta Co — Migration Accelerator', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addMonths(3)
        );
        insert new List<Opportunity>{ opp, stalledOpp };

        MA_Saved_Configuration__c converted = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/a', Active__c = true,
            Account__c = acct.Id, Opportunity__c = opp.Id
        );
        MA_Saved_Configuration__c stalled = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Beta Co',
            Generated_URL__c = 'https://example.com/b', Active__c = true,
            Account__c = acct.Id, Opportunity__c = stalledOpp.Id
        );
        // No opportunity, so it is not a deal and must not appear.
        MA_Saved_Configuration__c orphan = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Nobody Ltd',
            Generated_URL__c = 'https://example.com/c', Active__c = true
        );
        insert new List<MA_Saved_Configuration__c>{ converted, stalled, orphan };

        MA_Assessment_Request__c req = new MA_Assessment_Request__c(
            Requester_Name__c = 'Alex Rivera', Requester_Email__c = 'alex@example.com',
            Company__c = 'Acme Bank', Status__c = 'New',
            Saved_Configuration__c = converted.Id
        );
        insert req;

        insert new List<MA_Link_Event__c>{
            new MA_Link_Event__c(Saved_Configuration__c = converted.Id, Event_Type__c = 'Page View'),
            new MA_Link_Event__c(Saved_Configuration__c = converted.Id, Event_Type__c = 'Page View'),
            new MA_Link_Event__c(Saved_Configuration__c = converted.Id, Event_Type__c = 'Form Opened'),
            new MA_Link_Event__c(Saved_Configuration__c = converted.Id, Event_Type__c = 'Form Submitted',
                                 Assessment_Request__c = req.Id),
            new MA_Link_Event__c(Saved_Configuration__c = stalled.Id, Event_Type__c = 'Page View'),
            new MA_Link_Event__c(Saved_Configuration__c = stalled.Id, Event_Type__c = 'Form Opened'),
            new MA_Link_Event__c(Saved_Configuration__c = stalled.Id, Event_Type__c = 'Drop-off')
        };

        Test.startTest();
        List<GtmHomeSnapshotController.DealSummary> deals = GtmHomeSnapshotController.getDeals();
        GtmHomeSnapshotController.Snapshot snap = GtmHomeSnapshotController.getSnapshot();
        Test.stopTest();

        Assert.areEqual(2, deals.size(), 'A configuration with no opportunity is not a deal');

        Map<Id, GtmHomeSnapshotController.DealSummary> byConfig =
            new Map<Id, GtmHomeSnapshotController.DealSummary>();
        for (GtmHomeSnapshotController.DealSummary d : deals) byConfig.put(d.configId, d);

        GtmHomeSnapshotController.DealSummary won = byConfig.get(converted.Id);
        Assert.areEqual('Acme Bank — Migration Accelerator', won.opportunityName);
        Assert.areEqual('Acme Bank', won.accountName);
        Assert.areEqual('Qualification', won.stageName);
        Assert.areEqual(2, won.views, 'Views are counted, not flagged');
        Assert.isTrue(won.formOpened);
        Assert.isTrue(won.formSubmitted);
        Assert.isFalse(won.droppedOff);
        Assert.areEqual(req.Id, won.requestId);
        Assert.areEqual('New', won.requestStatus);
        Assert.isNotNull(won.lastActivity);

        GtmHomeSnapshotController.DealSummary lost = byConfig.get(stalled.Id);
        Assert.areEqual(1, lost.views);
        Assert.isTrue(lost.formOpened);
        Assert.isFalse(lost.formSubmitted, 'This is the deal worth chasing');
        Assert.isTrue(lost.droppedOff);
        Assert.isNull(lost.requestId, 'No request came back from this one');

        Assert.areEqual(1, snap.stalledCount,
            'Exactly one link was opened and never submitted');
    }

    @IsTest
    static void aLinkNobodyOpenedIsNotStalled() {
        MA_Saved_Configuration__c untouched = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Quiet Co',
            Generated_URL__c = 'https://example.com/q', Active__c = true
        );
        insert untouched;
        insert new MA_Link_Event__c(Saved_Configuration__c = untouched.Id, Event_Type__c = 'Page View');

        Test.startTest();
        GtmHomeSnapshotController.Snapshot snap = GtmHomeSnapshotController.getSnapshot();
        List<GtmHomeSnapshotController.DealSummary> deals = GtmHomeSnapshotController.getDeals();
        Test.stopTest();

        Assert.areEqual(0, snap.stalledCount, 'Reading the page is not starting the form');
        Assert.areEqual(0, deals.size());
    }
}
