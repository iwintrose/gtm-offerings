@IsTest
private class MaPageSectionControllerTest {

    private static final String OFFERING = 'ma-migrator';
    private static final String TMPL     = 'story';



    private static List<MaPageSectionController.FieldSeed> seeds() {
        List<MaPageSectionController.FieldSeed> out = new List<MaPageSectionController.FieldSeed>();
        MaPageSectionController.FieldSeed a = new MaPageSectionController.FieldSeed();
        a.fieldKey = 'eyebrow'; a.fieldType = 'text'; a.label = 'Eyebrow';
        MaPageSectionController.FieldSeed b = new MaPageSectionController.FieldSeed();
        b.fieldKey = 'cards'; b.fieldType = 'json'; b.label = 'Cards';
        out.add(a); out.add(b);
        return out;
    }

    @IsTest
    static void createSection_createsSectionAndItsFields() {
        Test.startTest();
        String id = MaPageSectionController.createSection(
            OFFERING, TMPL, 'new-beat', 'New Beat', 'card-grid', 'standard', seeds());
        Test.stopTest();

        MA_Page_Section__c sec = [
            SELECT Section_Key__c, Section_Address__c, Layout_Type__c, Width__c, Active__c
            FROM MA_Page_Section__c WHERE Id = :id];
        System.assertEquals('new-beat', sec.Section_Key__c, 'Section key should be stored as given');
        System.assertEquals(OFFERING + '::' + TMPL + '::new-beat', sec.Section_Address__c,
            'Section address should be offering::template::key');
        System.assertEquals(true, sec.Active__c, 'A new section should be visible');

        List<MA_Page_Content__c> rows = [
            SELECT Field_Key__c, Field_Type__c, JSON_Value__c FROM MA_Page_Content__c
            WHERE Offering_Key__c = :OFFERING AND Section_Key__c = 'new-beat' ORDER BY Field_Key__c];
        System.assertEquals(2, rows.size(), 'Both declared fields should get a record');
        // A json field with no value is an empty list, not an empty string: the
        // editor parses this column to build its repeater.
        for (MA_Page_Content__c r : rows) {
            if (r.Field_Type__c == 'json') {
                System.assertEquals('[]', r.JSON_Value__c, 'A new json field should seed an empty list');
            }
        }
    }

    @IsTest
    static void createSection_normalisesKeyForUseInAnAddress() {
        Test.startTest();
        String id = MaPageSectionController.createSection(
            OFFERING, TMPL, '  The Mechanism!! ', 'The Mechanism', 'hero', 'standard', seeds());
        Test.stopTest();

        MA_Page_Section__c sec = [SELECT Section_Key__c FROM MA_Page_Section__c WHERE Id = :id];
        System.assertEquals('the-mechanism', sec.Section_Key__c,
            'Punctuation and case should be stripped so the key survives an address');
    }

    @IsTest
    static void createSection_refusesADuplicateKey() {
        MaPageSectionController.createSection(
            OFFERING, TMPL, 'beat', 'Beat', 'hero', 'standard', seeds());
        Boolean blocked = false;
        Test.startTest();
        try {
            MaPageSectionController.createSection(
                OFFERING, TMPL, 'beat', 'Beat again', 'hero', 'standard', seeds());
        } catch (AuraHandledException e) {
            blocked = true;
        }
        Test.stopTest();
        // The key addresses every field under it, so a collision would merge
        // two sections' content rather than fail loudly.
        System.assert(blocked, 'A duplicate section key should be refused');
        System.assertEquals(1, [SELECT COUNT() FROM MA_Page_Section__c
            WHERE Offering_Key__c = :OFFERING AND Section_Key__c = 'beat'],
            'The duplicate should not have been inserted');
    }

    @IsTest
    static void createSection_refusesAKeyThatNormalisesToNothing() {
        Boolean blocked = false;
        Test.startTest();
        try {
            MaPageSectionController.createSection(
                OFFERING, TMPL, '!!!', '!!!', 'hero', 'standard', seeds());
        } catch (AuraHandledException e) {
            blocked = true;
        }
        Test.stopTest();
        System.assert(blocked, 'A key with no usable characters should be refused');
    }

    @IsTest
    static void deleteSection_removesTheSectionAndItsContent() {
        String id = MaPageSectionController.createSection(
            OFFERING, TMPL, 'doomed', 'Doomed', 'card-grid', 'standard', seeds());

        Test.startTest();
        Integer removed = MaPageSectionController.deleteSection(id);
        Test.stopTest();

        System.assertEquals(2, removed, 'Both content rows should be reported deleted');
        System.assertEquals(0, [SELECT COUNT() FROM MA_Page_Section__c WHERE Id = :id],
            'The section should be gone');
        System.assertEquals(0, [SELECT COUNT() FROM MA_Page_Content__c
            WHERE Offering_Key__c = :OFFERING AND Section_Key__c = 'doomed'],
            'Deleting a section must not leave its content rows orphaned');
    }

    @IsTest
    static void deleteSection_rejectsAnUnknownId() {
        Boolean blocked = false;
        Test.startTest();
        try {
            MaPageSectionController.deleteSection('a0000000000000AAAA');
        } catch (Exception e) {
            blocked = true;
        }
        Test.stopTest();
        System.assert(blocked, 'Deleting a section that does not exist should fail loudly');
    }

    @IsTest
    static void createField_addsOneMissingRow() {
        MaPageSectionController.createSection(
            OFFERING, TMPL, 'partial', 'Partial', 'card-grid', 'standard', seeds());

        Test.startTest();
        String id = MaPageSectionController.createField(
            OFFERING, TMPL, 'partial', 'head', 'text', 'Head', null);
        Test.stopTest();

        MA_Page_Content__c row = [SELECT Content_Address__c, Field_Type__c, Label__c
            FROM MA_Page_Content__c WHERE Id = :id];
        System.assertEquals(OFFERING + '::' + TMPL + '::partial::head', row.Content_Address__c,
            'The address should be offering::template::section::field');
        System.assertEquals('Head', row.Label__c, 'The supplied label should be stored');
    }

    @IsTest
    static void createField_refusesAFieldThatAlreadyExists() {
        MaPageSectionController.createSection(
            OFFERING, TMPL, 'dupefield', 'Dupe Field', 'card-grid', 'standard', seeds());
        Boolean blocked = false;
        Test.startTest();
        try {
            MaPageSectionController.createField(
                OFFERING, TMPL, 'dupefield', 'eyebrow', 'text', 'Eyebrow', null);
        } catch (AuraHandledException e) {
            blocked = true;
        }
        Test.stopTest();
        System.assert(blocked, 'Adding a field that already has a record should be refused');
    }


    // ─── editor section methods ───────────────────────────────────────────────

    private static MA_Page_Section__c pageSection(String key, Integer sortOrder, Boolean active) {
        return new MA_Page_Section__c(
            Section_Address__c = OFFERING + '::' + TMPL + '::' + key,
            Offering_Key__c    = OFFERING,
            Template_Type__c   = TMPL,
            Section_Key__c     = key,
            Label__c           = key,
            Layout_Type__c     = 'hero',
            Width__c           = 'standard',
            Sort_Order__c      = sortOrder,
            Active__c          = active
        );
    }

    @IsTest
    static void editorSectionsIncludeInactiveOnes() {
        insert new List<MA_Page_Section__c>{
            pageSection('hero', 10, true),
            pageSection('faq', 20, false)
        };

        Test.startTest();
        List<MaPageSectionController.EditorSection> secs =
            MaPageSectionController.getEditorSections(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals(2, secs.size(),
            'The editor shows switched-off sections so they can be restored');
        System.assertEquals('hero', secs[0].sectionKey, 'Ordered by Sort_Order__c');
        System.assertEquals(false, secs[1].active, 'Inactive flag round-trips');
    }

    @IsTest
    static void saveSectionOrderRewritesSortOrder() {
        List<MA_Page_Section__c> secs = new List<MA_Page_Section__c>{
            pageSection('hero', 10, true),
            pageSection('faq', 20, true)
        };
        insert secs;

        Test.startTest();
        // Rail order reversed: faq first.
        MaPageSectionController.saveSectionOrder(
            new List<String>{ secs[1].Id, secs[0].Id });
        Test.stopTest();

        // The published columns must not move: reordering is a draft, exactly
        // like editing a field, and the live page keeps the last published
        // order until someone publishes.
        Map<Id, MA_Page_Section__c> after = new Map<Id, MA_Page_Section__c>(
            [SELECT Id, Sort_Order__c, Draft_State__c FROM MA_Page_Section__c]);
        System.assert(after.get(secs[0].Id).Sort_Order__c < after.get(secs[1].Id).Sort_Order__c,
            'Published sort order is unchanged until publish');
        System.assert(String.isNotBlank(after.get(secs[1].Id).Draft_State__c),
            'The new position is held as a pending change');

        // The editor, by contrast, shows the order you just made.
        List<MaPageSectionController.EditorSection> rail =
            MaPageSectionController.getEditorSections(OFFERING, TMPL);
        System.assertEquals('faq', rail[0].sectionKey, 'The editor shows the pending order');
        System.assertEquals(true, rail[0].isMoved, 'and marks it as moved');
    }

    @IsTest
    static void saveSectionOrderClearsADraftThatMatchesWhatIsPublished() {
        List<MA_Page_Section__c> secs = new List<MA_Page_Section__c>{
            pageSection('hero', 10, true),
            pageSection('faq', 20, true)
        };
        insert secs;

        Test.startTest();
        MaPageSectionController.saveSectionOrder(new List<String>{ secs[1].Id, secs[0].Id });
        MaPageSectionController.saveSectionOrder(new List<String>{ secs[0].Id, secs[1].Id });
        Test.stopTest();

        // Moving a section and moving it back is not a pending change, and
        // should not leave the page looking like it has something to publish.
        for (MA_Page_Section__c sec : [SELECT Draft_State__c FROM MA_Page_Section__c]) {
            System.assert(String.isBlank(sec.Draft_State__c),
                'A draft equal to the published value is cleared, not stored');
        }
    }

    @IsTest
    static void saveSectionOrderIgnoresEmptyInput() {
        Test.startTest();
        MaPageSectionController.saveSectionOrder(null);
        MaPageSectionController.saveSectionOrder(new List<String>());
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM MA_Page_Section__c],
            'No rows created or touched by an empty reorder');
    }

    @IsTest
    static void setSectionActiveTogglesVisibility() {
        MA_Page_Section__c sec = pageSection('faq', 10, true);
        insert sec;

        Test.startTest();
        MaPageSectionController.setSectionActive(sec.Id, false);
        Test.stopTest();

        MA_Page_Section__c after =
            [SELECT Active__c, Draft_State__c FROM MA_Page_Section__c WHERE Id = :sec.Id];
        System.assertEquals(true, after.Active__c,
            'The live page keeps showing the section until the change is published');
        System.assert(String.isNotBlank(after.Draft_State__c),
            'Hiding a section is a pending change');
        System.assertEquals(false,
            MaPageSectionController.getEditorSections(OFFERING, TMPL)[0].active,
            'The editor shows it as hidden');
    }

    @IsTest
    static void deleteSection_marksAPublishedSectionRatherThanRemovingIt() {
        MA_Page_Section__c sec = pageSection('faq', 10, true);
        sec.Status__c = 'Published';
        insert sec;

        Test.startTest();
        MaPageSectionController.deleteSection(sec.Id);
        Test.stopTest();

        // A published section is still on the live page until publish runs, so
        // deleting it now would change the public page without asking.
        System.assertEquals(1, [SELECT COUNT() FROM MA_Page_Section__c WHERE Id = :sec.Id],
            'A published section survives until the delete is published');
        System.assertEquals(true,
            MaPageSectionController.getEditorSections(OFFERING, TMPL)[0].isDeleted,
            'The editor shows it as pending deletion');
    }

    @IsTest
    static void restoreSection_takesBackAPendingDelete() {
        MA_Page_Section__c sec = pageSection('faq', 10, true);
        sec.Status__c = 'Published';
        insert sec;
        MaPageSectionController.deleteSection(sec.Id);

        Test.startTest();
        MaPageSectionController.restoreSection(sec.Id);
        Test.stopTest();

        System.assertEquals(false,
            MaPageSectionController.getEditorSections(OFFERING, TMPL)[0].isDeleted,
            'Nothing was removed, so taking the mark back restores the section');
    }

    @IsTest
    static void publish_appliesPendingOrderAndRemovesMarkedSections() {
        List<MA_Page_Section__c> secs = new List<MA_Page_Section__c>{
            pageSection('hero', 10, true),
            pageSection('faq', 20, true)
        };
        for (MA_Page_Section__c s : secs) { s.Status__c = 'Published'; }
        insert secs;
        MaPageSectionController.saveSectionOrder(new List<String>{ secs[1].Id, secs[0].Id });
        MaPageSectionController.deleteSection(secs[0].Id);

        Test.startTest();
        MaPageContentController.publishPage(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM MA_Page_Section__c WHERE Id = :secs[0].Id],
            'The section marked for deletion is removed on publish');
        MA_Page_Section__c kept =
            [SELECT Sort_Order__c, Draft_State__c, Status__c FROM MA_Page_Section__c WHERE Id = :secs[1].Id];
        System.assertEquals(10, kept.Sort_Order__c, 'The pending order is written to the real column');
        System.assert(String.isBlank(kept.Draft_State__c), 'and the pending change is cleared');
    }

    @IsTest
    static void discard_removesASectionThatWasNeverPublished() {
        String id = MaPageSectionController.createSection(
            OFFERING, TMPL, 'brand-new', 'Brand New', 'card-grid', 'standard', seeds());

        Test.startTest();
        MaPageContentController.discardDrafts(OFFERING, TMPL);
        Test.stopTest();

        // It was never part of the published page, so there is nothing to
        // revert it to — discarding means it never happened.
        System.assertEquals(0, [SELECT COUNT() FROM MA_Page_Section__c WHERE Id = :id],
            'An unpublished section is removed by discard');
        System.assertEquals(0, [SELECT COUNT() FROM MA_Page_Content__c
            WHERE Offering_Key__c = :OFFERING AND Section_Key__c = 'brand-new'],
            'and takes its content rows with it');
    }

    @IsTest
    static void createSection_startsUnpublished() {
        Test.startTest();
        String id = MaPageSectionController.createSection(
            OFFERING, TMPL, 'fresh', 'Fresh', 'hero', 'standard', seeds());
        Test.stopTest();

        System.assertEquals('Draft',
            [SELECT Status__c FROM MA_Page_Section__c WHERE Id = :id].Status__c,
            'A new section does not appear on the public page until it is published');
    }

    @IsTest
    static void setSectionActiveRejectsBlankId() {
        Boolean threw = false;
        Test.startTest();
        try {
            MaPageSectionController.setSectionActive('', true);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'A blank section id is rejected');
    }
}
