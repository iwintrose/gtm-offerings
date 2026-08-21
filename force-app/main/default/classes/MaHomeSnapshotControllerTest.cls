@IsTest
private class MaHomeSnapshotControllerTest {
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
        MaHomeSnapshotController.Snapshot snap = MaHomeSnapshotController.getSnapshot();
        Test.stopTest();

        Assert.areEqual(2, snap.activeEngagementCount);
        Assert.areEqual(50000, snap.activeEngagementValue);
        Assert.areEqual(1, snap.newAssessmentCount);
        Assert.areEqual(75000, snap.openPipelineAmount);
    }

    @IsTest
    static void returnsZeroesWhenNothingExists() {
        Test.startTest();
        MaHomeSnapshotController.Snapshot snap = MaHomeSnapshotController.getSnapshot();
        Test.stopTest();

        Assert.areEqual(0, snap.activeEngagementCount);
        Assert.areEqual(0, snap.activeEngagementValue);
        Assert.areEqual(0, snap.newAssessmentCount);
        Assert.areEqual(0, snap.openPipelineAmount);
    }
}
