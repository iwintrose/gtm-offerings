@IsTest
private class GtmOfferingArchiveCascadeTest {

    private static final String OFFERING = 'ma-migrator';
    private static final String OTHER_OFFERING = 'gtm-other-offering';
    private static final String TILE_TEMPLATE = 'offerings-listing';
    private static final String TILE_SECTION = 'tile';

    // ─── Helpers ────────────────────────────────────────────────────────────

    private static GTM_Page_Section__c makeSection(String offering, String tmpl, String sectionKey) {
        return new GTM_Page_Section__c(
            Offering_Key__c   = offering,
            Template_Type__c  = tmpl,
            Section_Key__c    = sectionKey,
            Layout_Type__c    = 'stat',
            Section_Address__c = offering + '::' + tmpl + '::' + sectionKey,
            Sort_Order__c     = 0
        );
    }

    private static GTM_Page_Content__c makeContent(String offering, String tmpl, String sectionKey, String fieldKey) {
        return new GTM_Page_Content__c(
            Offering_Key__c  = offering,
            Template_Type__c = tmpl,
            Section_Key__c   = sectionKey,
            Field_Key__c     = fieldKey,
            Field_Type__c    = 'text',
            Text_Value__c    = 'value',
            Active__c        = true
        );
    }

    // ─── Archive cascade ────────────────────────────────────────────────────

    @IsTest
    static void archivingTile_cascadesToSiblingSectionsAndContent() {
        GTM_Page_Section__c tile = makeSection(OFFERING, TILE_TEMPLATE, TILE_SECTION);
        GTM_Page_Section__c hero = makeSection(OFFERING, 'story', 'hero');
        GTM_Page_Section__c otherOfferingSection = makeSection(OTHER_OFFERING, 'story', 'hero');
        insert new List<GTM_Page_Section__c>{ tile, hero, otherOfferingSection };

        GTM_Page_Content__c content = makeContent(OFFERING, 'story', 'hero', 'headline');
        GTM_Page_Content__c otherOfferingContent = makeContent(OTHER_OFFERING, 'story', 'hero', 'headline');
        insert new List<GTM_Page_Content__c>{ content, otherOfferingContent };

        Test.startTest();
        tile.Archived__c = true;
        update tile;
        Test.stopTest();

        GTM_Page_Section__c tileAfter = [SELECT Archived__c, Archived_Date__c FROM GTM_Page_Section__c WHERE Id = :tile.Id];
        GTM_Page_Section__c heroAfter = [SELECT Archived__c, Archived_Date__c FROM GTM_Page_Section__c WHERE Id = :hero.Id];
        GTM_Page_Section__c otherSectionAfter = [SELECT Archived__c FROM GTM_Page_Section__c WHERE Id = :otherOfferingSection.Id];
        GTM_Page_Content__c contentAfter = [SELECT Archived__c, Archived_Date__c FROM GTM_Page_Content__c WHERE Id = :content.Id];
        GTM_Page_Content__c otherContentAfter = [SELECT Archived__c FROM GTM_Page_Content__c WHERE Id = :otherOfferingContent.Id];

        System.assertEquals(true, tileAfter.Archived__c, 'Tile itself should be archived');
        System.assertNotEquals(null, tileAfter.Archived_Date__c, 'Tile should be stamped with an archive date');

        System.assertEquals(true, heroAfter.Archived__c, 'Sibling section should cascade-archive');
        System.assertNotEquals(null, heroAfter.Archived_Date__c, 'Sibling section should be stamped with an archive date');

        System.assertEquals(true, contentAfter.Archived__c, 'Page content should cascade-archive');
        System.assertNotEquals(null, contentAfter.Archived_Date__c, 'Page content should be stamped with an archive date');

        System.assertEquals(false, otherSectionAfter.Archived__c, 'A different offering must not be touched');
        System.assertEquals(false, otherContentAfter.Archived__c, 'A different offering\'s content must not be touched');
    }

    // ─── Restore cascade ────────────────────────────────────────────────────

    @IsTest
    static void restoringTile_cascadesToSiblingSectionsAndContent() {
        GTM_Page_Section__c tile = makeSection(OFFERING, TILE_TEMPLATE, TILE_SECTION);
        tile.Archived__c = true;
        GTM_Page_Section__c hero = makeSection(OFFERING, 'story', 'hero');
        hero.Archived__c = true;
        insert new List<GTM_Page_Section__c>{ tile, hero };

        GTM_Page_Content__c content = makeContent(OFFERING, 'story', 'hero', 'headline');
        content.Archived__c = true;
        insert content;

        Test.startTest();
        tile.Archived__c = false;
        update tile;
        Test.stopTest();

        GTM_Page_Section__c heroAfter = [SELECT Archived__c, Archived_Date__c FROM GTM_Page_Section__c WHERE Id = :hero.Id];
        GTM_Page_Content__c contentAfter = [SELECT Archived__c, Archived_Date__c FROM GTM_Page_Content__c WHERE Id = :content.Id];

        System.assertEquals(false, heroAfter.Archived__c, 'Sibling section should cascade-restore');
        System.assertNotEquals(null, heroAfter.Archived_Date__c, 'Restore should also stamp a new date on the sibling');

        System.assertEquals(false, contentAfter.Archived__c, 'Page content should cascade-restore');
        System.assertNotEquals(null, contentAfter.Archived_Date__c, 'Restore should also stamp a new date on the content row');
    }

    // ─── No-op re-stamp ─────────────────────────────────────────────────────

    @IsTest
    static void reWritingSameArchiveValue_doesNotRestampDate() {
        GTM_Page_Section__c tile = makeSection(OFFERING, TILE_TEMPLATE, TILE_SECTION);
        GTM_Page_Section__c hero = makeSection(OFFERING, 'story', 'hero');
        insert new List<GTM_Page_Section__c>{ tile, hero };

        GTM_Page_Content__c content = makeContent(OFFERING, 'story', 'hero', 'headline');
        insert content;

        // First archive: establishes a baseline Archived_Date__c on every row.
        tile.Archived__c = true;
        update tile;

        GTM_Page_Section__c tileBaseline = [SELECT Archived_Date__c FROM GTM_Page_Section__c WHERE Id = :tile.Id];
        GTM_Page_Section__c heroBaseline = [SELECT Archived_Date__c FROM GTM_Page_Section__c WHERE Id = :hero.Id];
        GTM_Page_Content__c contentBaseline = [SELECT Archived_Date__c FROM GTM_Page_Content__c WHERE Id = :content.Id];

        System.assertNotEquals(null, tileBaseline.Archived_Date__c);
        System.assertNotEquals(null, heroBaseline.Archived_Date__c);
        System.assertNotEquals(null, contentBaseline.Archived_Date__c);

        Test.startTest();
        // Re-write the tile with the exact same Archived__c value it already
        // has -- this must not re-stamp the tile's own date, and must not
        // touch (or re-cascade a new date onto) any sibling either, since
        // the cascade's target-value filter finds nothing left to update.
        tile.Archived__c = true;
        update tile;
        Test.stopTest();

        GTM_Page_Section__c tileAfter = [SELECT Archived_Date__c FROM GTM_Page_Section__c WHERE Id = :tile.Id];
        GTM_Page_Section__c heroAfter = [SELECT Archived_Date__c FROM GTM_Page_Section__c WHERE Id = :hero.Id];
        GTM_Page_Content__c contentAfter = [SELECT Archived_Date__c FROM GTM_Page_Content__c WHERE Id = :content.Id];

        System.assertEquals(tileBaseline.Archived_Date__c, tileAfter.Archived_Date__c, 'Re-writing the same value must not re-stamp the tile');
        System.assertEquals(heroBaseline.Archived_Date__c, heroAfter.Archived_Date__c, 'A no-op tile write must not touch a sibling section date');
        System.assertEquals(contentBaseline.Archived_Date__c, contentAfter.Archived_Date__c, 'A no-op tile write must not touch a sibling content date');
    }
}
