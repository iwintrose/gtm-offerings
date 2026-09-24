/**
 * Coverage for GTM_PurgeRecordsBatch (issue #184, part 5): rows past the
 * retention window are purged, rows within the window are untouched,
 * non-archived rows are never touched, both target objects are covered,
 * and Schedulable.execute correctly kicks off the batch.
 */
@IsTest
private class GTM_PurgeRecordsBatchTest {

    private static GTM_Page_Section__c sectionRow(String offering, Boolean archived, Datetime archivedDate) {
        return new GTM_Page_Section__c(
            Section_Address__c = offering + '::offerings-listing::tile',
            Offering_Key__c    = offering,
            Template_Type__c   = 'offerings-listing',
            Section_Key__c     = 'tile',
            Label__c           = 'Offerings page entry',
            Layout_Type__c     = 'offering-tile',
            Sort_Order__c      = 10,
            Active__c          = true,
            Status__c          = 'Published',
            Offering_Status__c = 'Published',
            Archived__c        = archived,
            Archived_Date__c   = archivedDate
        );
    }

    private static GTM_Page_Content__c contentRow(String offering, Boolean archived, Datetime archivedDate) {
        return new GTM_Page_Content__c(
            Offering_Key__c  = offering,
            Template_Type__c = 'offerings-listing',
            Section_Key__c   = 'tile',
            Field_Key__c     = 'name',
            Field_Type__c    = 'text',
            Text_Value__c    = 'value',
            Sort_Order__c    = 0,
            Active__c        = true,
            Archived__c      = archived,
            Archived_Date__c = archivedDate
        );
    }

    @IsTest
    static void purgesSectionAndContentRowsPastTheRetentionWindow() {
        Datetime pastCutoff = System.now().addDays(-(GTM_PurgeRecordsBatch.PURGE_AFTER_DAYS + 1));

        GTM_Page_Section__c oldSection = sectionRow('offer-a', true, pastCutoff);
        insert oldSection;
        GTM_Page_Content__c oldContent = contentRow('offer-b', true, pastCutoff);
        insert oldContent;

        Test.startTest();
        Database.executeBatch(new GTM_PurgeRecordsBatch());
        Test.stopTest();

        Assert.isTrue(
            [SELECT Id FROM GTM_Page_Section__c WHERE Id = :oldSection.Id].isEmpty(),
            'a section archived past the retention window must be permanently deleted'
        );
        Assert.isTrue(
            [SELECT Id FROM GTM_Page_Content__c WHERE Id = :oldContent.Id].isEmpty(),
            'a content row archived past the retention window must be permanently deleted'
        );
    }

    @IsTest
    static void leavesArchivedRowsWithinTheRetentionWindowUntouched() {
        Datetime withinWindow = System.now().addDays(-(GTM_PurgeRecordsBatch.PURGE_AFTER_DAYS - 1));

        GTM_Page_Section__c recentSection = sectionRow('offer-c', true, withinWindow);
        insert recentSection;
        GTM_Page_Content__c recentContent = contentRow('offer-d', true, withinWindow);
        insert recentContent;

        Test.startTest();
        Database.executeBatch(new GTM_PurgeRecordsBatch());
        Test.stopTest();

        Assert.areEqual(
            1, [SELECT Id FROM GTM_Page_Section__c WHERE Id = :recentSection.Id].size(),
            'a section archived within the retention window must be preserved'
        );
        Assert.areEqual(
            1, [SELECT Id FROM GTM_Page_Content__c WHERE Id = :recentContent.Id].size(),
            'a content row archived within the retention window must be preserved'
        );
    }

    @IsTest
    static void neverTouchesANonArchivedRowEvenIfOld() {
        Datetime pastCutoff = System.now().addDays(-(GTM_PurgeRecordsBatch.PURGE_AFTER_DAYS + 1));

        GTM_Page_Section__c neverArchived = sectionRow('offer-e', false, pastCutoff);
        insert neverArchived;

        Test.startTest();
        Database.executeBatch(new GTM_PurgeRecordsBatch());
        Test.stopTest();

        Assert.areEqual(
            1, [SELECT Id FROM GTM_Page_Section__c WHERE Id = :neverArchived.Id].size(),
            'a non-archived row must never be purged regardless of Archived_Date__c'
        );
    }

    @IsTest
    static void mixedBatchPartialFailureDoesNotStrandTheRestOfTheBatch() {
        Datetime pastCutoff = System.now().addDays(-(GTM_PurgeRecordsBatch.PURGE_AFTER_DAYS + 1));

        GTM_Page_Section__c deletable = sectionRow('offer-f', true, pastCutoff);
        insert deletable;
        GTM_Page_Content__c staleRow = contentRow('offer-g', true, pastCutoff);
        insert staleRow;
        // Delete it ahead of time so the copy passed into execute() below is
        // stale -- Database.delete on an already-deleted Id fails with
        // "entity is deleted", exercising the allOrNone=false path: this
        // failure must not strand the sibling section row's delete.
        delete staleRow;

        List<SObject> scope = new List<SObject>{ deletable, staleRow };

        Test.startTest();
        new GTM_PurgeRecordsBatch().execute(null, scope);
        Test.stopTest();

        Assert.isTrue(
            [SELECT Id FROM GTM_Page_Section__c WHERE Id = :deletable.Id].isEmpty(),
            'the deletable section row must still be purged even though a sibling row in the same batch failed'
        );
    }

    @IsTest
    static void schedulableExecuteKicksOffTheBatch() {
        Datetime pastCutoff = System.now().addDays(-(GTM_PurgeRecordsBatch.PURGE_AFTER_DAYS + 1));
        GTM_Page_Section__c oldSection = sectionRow('offer-h', true, pastCutoff);
        insert oldSection;

        Test.startTest();
        new GTM_PurgeRecordsBatch().execute((SchedulableContext) null);
        Test.stopTest();

        Assert.isTrue(
            [SELECT Id FROM GTM_Page_Section__c WHERE Id = :oldSection.Id].isEmpty(),
            'Schedulable.execute must kick off the batch and purge eligible rows'
        );
    }
}
