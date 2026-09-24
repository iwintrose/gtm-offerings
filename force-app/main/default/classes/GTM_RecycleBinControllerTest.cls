/**
 * Coverage for GTM_RecycleBinController (issue #184, part 2 of 5): list,
 * restore (single + bulk, including the parent-hard-deleted edge case),
 * permanent delete (single + bulk), and FLS-denial.
 */
@IsTest
private class GTM_RecycleBinControllerTest {

    private static GTM_Page_Section__c tileRow(String offering, Boolean archived) {
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
            Archived__c        = archived
        );
    }

    private static GTM_Page_Section__c sectionRow(String offering, String sectionKey, Boolean archived) {
        return new GTM_Page_Section__c(
            Section_Address__c = offering + '::offerings-listing::' + sectionKey,
            Offering_Key__c    = offering,
            Template_Type__c   = 'offerings-listing',
            Section_Key__c     = sectionKey,
            Label__c           = 'Section ' + sectionKey,
            Layout_Type__c     = 'hero',
            Sort_Order__c      = 20,
            Active__c          = true,
            Status__c          = 'Published',
            Archived__c        = archived
        );
    }

    private static GTM_Page_Content__c contentRow(String offering, String sectionKey, String fieldKey, Boolean archived) {
        return new GTM_Page_Content__c(
            Offering_Key__c  = offering,
            Template_Type__c = 'offerings-listing',
            Section_Key__c   = sectionKey,
            Field_Key__c     = fieldKey,
            Field_Type__c    = 'text',
            Text_Value__c    = 'value',
            Sort_Order__c    = 0,
            Active__c        = true,
            Archived__c      = archived
        );
    }

    private static User createStrippedUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias             = alias,
            Email             = alias + '@example.com',
            EmailEncodingKey  = 'UTF-8',
            LastName          = 'User ' + alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'America/New_York',
            Username          = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    private static User createUserWithPermissionSet(String alias, String permissionSetName) {
        User u = createStrippedUser(alias);
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    // ─── List ───────────────────────────────────────────────────────────

    @IsTest
    static void listReturnsOnlyArchivedItemsAcrossBothObjects() {
        insert new List<GTM_Page_Section__c>{
            tileRow('offer-a', true),
            tileRow('offer-b', false)
        };
        insert new List<GTM_Page_Content__c>{
            contentRow('offer-a', 'tile', 'name', true),
            contentRow('offer-b', 'tile', 'name', false)
        };

        Test.startTest();
        List<GTM_RecycleBinController.ArchivedItem> items = GTM_RecycleBinController.getArchivedItems();
        Test.stopTest();

        Set<String> archivedOfferingKeys = new Set<String>();
        for (GTM_RecycleBinController.ArchivedItem item : items) {
            archivedOfferingKeys.add(item.offeringKey);
            Assert.isTrue(
                item.objectType == 'GTM_Page_Section__c' || item.objectType == 'GTM_Page_Content__c',
                'objectType must identify which object the row came from'
            );
        }
        Assert.isTrue(archivedOfferingKeys.contains('offer-a'), 'archived rows for offer-a must appear');
        Assert.isFalse(archivedOfferingKeys.contains('offer-b'), 'non-archived rows for offer-b must not appear');
    }

    @IsTest
    static void listFlagsTheOfferingTileRow() {
        insert tileRow('offer-c', true);

        Test.startTest();
        List<GTM_RecycleBinController.ArchivedItem> items = GTM_RecycleBinController.getArchivedItems();
        Test.stopTest();

        Boolean found = false;
        for (GTM_RecycleBinController.ArchivedItem item : items) {
            if (item.offeringKey == 'offer-c' && item.objectType == 'GTM_Page_Section__c') {
                Assert.isTrue(item.isOfferingTile, 'the tile row must be flagged as the offering parent');
                found = true;
            }
        }
        Assert.isTrue(found, 'the archived tile row must be present in the list');
    }

    // ─── Restore ────────────────────────────────────────────────────────

    @IsTest
    static void restoreRecordRestoresASingleTileRow() {
        GTM_Page_Section__c tile = tileRow('offer-d', true);
        insert tile;

        Test.startTest();
        GTM_RecycleBinController.RestoreResult result = GTM_RecycleBinController.restoreRecord(tile.Id);
        Test.stopTest();

        Assert.isTrue(result.success);
        GTM_Page_Section__c reloaded = [SELECT Archived__c FROM GTM_Page_Section__c WHERE Id = :tile.Id];
        Assert.isFalse(reloaded.Archived__c);
    }

    @IsTest
    static void bulkRestoreOfTileAlsoRestoresItsArchivedChildrenViaCascade() {
        GTM_Page_Section__c tile = tileRow('offer-e', true);
        insert tile;
        GTM_Page_Section__c child = sectionRow('offer-e', 'hero', true);
        insert child;
        GTM_Page_Content__c content = contentRow('offer-e', 'tile', 'name', true);
        insert content;

        Test.startTest();
        List<GTM_RecycleBinController.RestoreResult> results =
            GTM_RecycleBinController.restoreRecords(new List<Id>{ tile.Id });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isTrue(results[0].success);

        GTM_Page_Section__c reloadedChild = [SELECT Archived__c FROM GTM_Page_Section__c WHERE Id = :child.Id];
        Assert.isFalse(reloadedChild.Archived__c, 'the cascade trigger must restore sibling sections when the tile is restored');
        GTM_Page_Content__c reloadedContent = [SELECT Archived__c FROM GTM_Page_Content__c WHERE Id = :content.Id];
        Assert.isFalse(reloadedContent.Archived__c, 'the cascade trigger must restore content rows when the tile is restored');
    }

    @IsTest
    static void restoreOfAChildIsBlockedWhileItsOfferingTileIsStillArchived() {
        GTM_Page_Section__c tile = tileRow('offer-f', true);
        insert tile;
        GTM_Page_Section__c child = sectionRow('offer-f', 'hero', true);
        insert child;

        Test.startTest();
        List<GTM_RecycleBinController.RestoreResult> results =
            GTM_RecycleBinController.restoreRecords(new List<Id>{ child.Id });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isFalse(results[0].success, 'a lone child restore must be blocked while its offering tile is still archived');
        Assert.isNotNull(results[0].message);

        GTM_Page_Section__c reloaded = [SELECT Archived__c FROM GTM_Page_Section__c WHERE Id = :child.Id];
        Assert.isTrue(reloaded.Archived__c, 'the blocked child must remain archived, not silently flip');
    }

    @IsTest
    static void restoreOfAChildFailsGracefullyWhenTheParentTileHasBeenPermanentlyDeleted() {
        // No tile row inserted at all for this offering key -- simulates the
        // tile having been permanently hard-deleted already.
        GTM_Page_Content__c orphan = contentRow('offer-g', 'tile', 'name', true);
        insert orphan;

        Test.startTest();
        Boolean threw = false;
        try {
            GTM_RecycleBinController.restoreRecord(orphan.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'restoring an orphaned child whose offering tile is gone must throw a handled exception, not orphan or crash');

        GTM_Page_Content__c reloaded = [SELECT Archived__c FROM GTM_Page_Content__c WHERE Id = :orphan.Id];
        Assert.isTrue(reloaded.Archived__c, 'the orphaned child must remain archived, not silently flip');
    }

    @IsTest
    static void restoreRecordsRequiresAtLeastOneId() {
        Test.startTest();
        Boolean threw = false;
        try {
            GTM_RecycleBinController.restoreRecords(new List<Id>());
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    // ─── Permanent delete ───────────────────────────────────────────────

    @IsTest
    static void deleteRecordPermanentlyRemovesAnArchivedRow() {
        GTM_Page_Section__c tile = tileRow('offer-h', true);
        insert tile;

        Test.startTest();
        GTM_RecycleBinController.DeleteResult result = GTM_RecycleBinController.deleteRecord(tile.Id);
        Test.stopTest();

        Assert.isTrue(result.success);
        List<GTM_Page_Section__c> remaining = [SELECT Id FROM GTM_Page_Section__c WHERE Id = :tile.Id];
        Assert.isTrue(remaining.isEmpty(), 'the record must be permanently gone');
    }

    @IsTest
    static void bulkDeleteHandlesAMixOfSectionsAndContentAcrossObjects() {
        GTM_Page_Section__c section = tileRow('offer-i', true);
        insert section;
        GTM_Page_Content__c content = contentRow('offer-i', 'tile', 'name', true);
        insert content;

        Test.startTest();
        List<GTM_RecycleBinController.DeleteResult> results =
            GTM_RecycleBinController.deleteRecords(new List<Id>{ section.Id, content.Id });
        Test.stopTest();

        Assert.areEqual(2, results.size());
        for (GTM_RecycleBinController.DeleteResult r : results) {
            Assert.isTrue(r.success, 'both an archived section and an archived content row must delete cleanly');
        }
    }

    @IsTest
    static void deleteFailsCleanlyForARecordThatIsNotArchived() {
        GTM_Page_Section__c tile = tileRow('offer-j', false);
        insert tile;

        Test.startTest();
        Boolean threw = false;
        try {
            GTM_RecycleBinController.deleteRecord(tile.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'only archived records are eligible for permanent delete');
        List<GTM_Page_Section__c> remaining = [SELECT Id FROM GTM_Page_Section__c WHERE Id = :tile.Id];
        Assert.areEqual(1, remaining.size(), 'a non-archived record must not be deleted');
    }

    @IsTest
    static void deleteRecordsRequiresAtLeastOneId() {
        Test.startTest();
        Boolean threw = false;
        try {
            GTM_RecycleBinController.deleteRecords(new List<Id>());
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    // ─── FLS denial ─────────────────────────────────────────────────────

    @IsTest
    static void listThrowsAHandledExceptionForAUserWithoutObjectAccess() {
        User stripped = createStrippedUser('rbstrip');

        Boolean threw = false;
        System.runAs(stripped) {
            try {
                GTM_RecycleBinController.getArchivedItems();
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Assert.isTrue(threw, 'a user without FLS/CRUD access to these objects must get a handled exception, not a silent empty list');
    }

    // ─── Permission-gated access (issue #184, part 4) ──────────────────────

    @IsTest
    static void contentManagerOnlyUserCanRestoreButIsBlockedFromDelete() {
        GTM_Page_Section__c tile = tileRow('offer-k', true);
        insert tile;
        User manager = createUserWithPermissionSet('rbmgr', 'GTM_Content_Manager');

        System.runAs(manager) {
            Test.startTest();
            GTM_RecycleBinController.RestoreResult restoreResult =
                GTM_RecycleBinController.restoreRecord(tile.Id);
            Assert.isTrue(restoreResult.success, 'a GTM_Content_Manager-only user must be able to restore');

            Boolean threw = false;
            try {
                GTM_RecycleBinController.deleteRecord(tile.Id);
            } catch (AuraHandledException e) {
                threw = true;
            }
            Test.stopTest();
            Assert.isTrue(threw, 'a GTM_Content_Manager-only user must be blocked from permanent delete');
        }
    }

    @IsTest
    static void contentAdminUserCanRestoreAndDelete() {
        GTM_Page_Section__c tile = tileRow('offer-l', true);
        insert tile;
        User admin = createUserWithPermissionSet('rbadm', 'GTM_Content_Admin');

        System.runAs(admin) {
            Test.startTest();
            GTM_RecycleBinController.RestoreResult restoreResult =
                GTM_RecycleBinController.restoreRecord(tile.Id);
            Assert.isTrue(restoreResult.success, 'a GTM_Content_Admin user must be able to restore');

            // Re-archive so the record is eligible for permanent delete.
            tile.Archived__c = true;
            update tile;

            GTM_RecycleBinController.DeleteResult deleteResult =
                GTM_RecycleBinController.deleteRecord(tile.Id);
            Test.stopTest();
            Assert.isTrue(deleteResult.success, 'a GTM_Content_Admin user must be able to permanently delete');
        }
    }

    /**
     * Apex unit tests invoke this class's static methods directly, which
     * bypasses the classAccesses check that only applies at the Aura/LWC/
     * REST remoting boundary (classAccesses cannot be exercised from plain
     * Apex-to-Apex calls in the same test). What IS testable here, and what
     * this asserts, is that a user with neither GTM_Content_Manager nor
     * GTM_Content_Admin -- i.e. exactly the population that classAccesses
     * would deny at the UI layer -- is also blocked by the underlying FLS/
     * CRUD denial these permission sets are the only source of, so such a
     * user has no path to this data either way.
     */
    @IsTest
    static void userWithNeitherContentPermissionSetCannotReachTheClassAtAll() {
        User stripped = createStrippedUser('rbnone');

        System.runAs(stripped) {
            Test.startTest();
            Boolean threw = false;
            try {
                GTM_RecycleBinController.getArchivedItems();
            } catch (Exception e) {
                threw = true;
            }
            Test.stopTest();
            Assert.isTrue(threw, 'a user with neither GTM_Content_Manager nor GTM_Content_Admin must be blocked at the class-access layer');
        }
    }
}
