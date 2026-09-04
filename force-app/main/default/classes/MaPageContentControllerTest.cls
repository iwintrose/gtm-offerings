@IsTest
private class MaPageContentControllerTest {

    private static final String OFFERING = 'ma-migrator';
    private static final String TMPL     = 'story';

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static MA_Page_Content__c makeRecord(
            String offering, String tmpl, String section, String field,
            String fieldType, String textVal, String richVal, String jsonVal,
            String industry, Integer sortOrder) {
        MA_Page_Content__c r = new MA_Page_Content__c(
            Offering_Key__c  = offering,
            Template_Type__c = tmpl,
            Section_Key__c   = section,
            Field_Key__c     = field,
            Field_Type__c    = fieldType,
            Text_Value__c    = textVal,
            Rich_Value__c    = richVal,
            JSON_Value__c    = jsonVal,
            Industry_Key__c  = industry,
            Sort_Order__c    = sortOrder,
            Active__c        = true
        );
        return r;
    }

    // ─── getPageContent ───────────────────────────────────────────────────────

    @IsTest
    static void getPageContent_returnsEmptyForBlankArgs() {
        Map<String, String> result = MaPageContentController.getPageContent('', 'story', null);
        System.assertEquals(0, result.size(), 'Blank offeringKey should yield empty map');
    }

    @IsTest
    static void getPageContent_returnsTextRecord() {
        MA_Page_Content__c rec = makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'Hello World', null, null, null, 0);
        insert rec;

        Test.startTest();
        Map<String, String> result = MaPageContentController.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assert(result.containsKey('hero::headline'), 'Map should contain hero::headline');
        System.assertEquals('Hello World', result.get('hero::headline'));
    }

    @IsTest
    static void getPageContent_returnsRichRecord() {
        MA_Page_Content__c rec = makeRecord(OFFERING, TMPL, 'hero', 'subhead', 'rich', null, '<b>Bold</b>', null, null, 0);
        insert rec;

        Test.startTest();
        Map<String, String> result = MaPageContentController.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals('<b>Bold</b>', result.get('hero::subhead'));
    }

    @IsTest
    static void getPageContent_returnsJsonRecord() {
        MA_Page_Content__c rec = makeRecord(OFFERING, TMPL, 'problem', 'chips', 'json', null, null, '["a","b"]', null, 0);
        insert rec;

        Test.startTest();
        Map<String, String> result = MaPageContentController.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals('["a","b"]', result.get('problem::chips'));
    }

    @IsTest
    static void getPageContent_industryScopedWinsOverDefault() {
        List<MA_Page_Content__c> recs = new List<MA_Page_Content__c>{
            makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'Default headline', null, null, null, 0),
            makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'FS headline', null, null, 'financial-services', 0)
        };
        insert recs;

        Test.startTest();
        Map<String, String> result = MaPageContentController.getPageContent(OFFERING, TMPL, 'financial-services');
        Test.stopTest();

        System.assertEquals('FS headline', result.get('hero::headline'), 'Industry-scoped record should win');
    }

    @IsTest
    static void getPageContent_industryNullFallsBackToDefault() {
        MA_Page_Content__c rec = makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'Default headline', null, null, null, 0);
        insert rec;

        Test.startTest();
        Map<String, String> result = MaPageContentController.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals('Default headline', result.get('hero::headline'));
    }

    @IsTest
    static void getPageContent_inactiveRecordExcluded() {
        MA_Page_Content__c rec = makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'Should not appear', null, null, null, 0);
        rec.Active__c = false;
        insert rec;

        Test.startTest();
        Map<String, String> result = MaPageContentController.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assert(!result.containsKey('hero::headline'), 'Inactive records should not appear');
    }

    @IsTest
    static void getPageContent_wrongTemplateExcluded() {
        MA_Page_Content__c rec = makeRecord(OFFERING, 'configurator', 'hero', 'headline', 'text', 'Wrong template', null, null, null, 0);
        insert rec;

        Test.startTest();
        Map<String, String> result = MaPageContentController.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assert(!result.containsKey('hero::headline'), 'Records for a different template should not appear');
    }

    // ─── getAllContent ────────────────────────────────────────────────────────

    @IsTest
    static void getAllContent_returnsAllActive() {
        List<MA_Page_Content__c> recs = new List<MA_Page_Content__c>{
            makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'H', null, null, null, 0),
            makeRecord(OFFERING, TMPL, 'hero', 'subhead',  'rich', null, '<p>S</p>', null, null, 1)
        };
        insert recs;

        Test.startTest();
        List<MaPageContentController.ContentRecord> result = MaPageContentController.getAllContent(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals(2, result.size());
    }

    @IsTest
    static void getAllContent_includesIndustryScoped() {
        List<MA_Page_Content__c> recs = new List<MA_Page_Content__c>{
            makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'Default', null, null, null, 0),
            makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'FS', null, null, 'financial-services', 0)
        };
        insert recs;

        Test.startTest();
        List<MaPageContentController.ContentRecord> result = MaPageContentController.getAllContent(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'getAllContent returns all rows including industry-scoped');
    }

    // ─── saveContentRecord ────────────────────────────────────────────────────

    @IsTest
    static void saveContentRecord_insertsNewRecord() {
        MaPageContentController.ContentRecord payload = new MaPageContentController.ContentRecord();
        payload.offeringKey  = OFFERING;
        payload.templateType = TMPL;
        payload.sectionKey   = 'hero';
        payload.fieldKey     = 'headline';
        payload.fieldType    = 'text';
        payload.textValue    = 'Saved headline';
        payload.active       = true;
        payload.sortOrder    = 0;

        Test.startTest();
        String newId = MaPageContentController.saveContentRecord(payload);
        Test.stopTest();

        System.assertNotEquals(null, newId, 'Save should return an ID');
        MA_Page_Content__c saved = [SELECT Text_Value__c FROM MA_Page_Content__c WHERE Id = :newId LIMIT 1];
        System.assertEquals('Saved headline', saved.Text_Value__c);
    }

    @IsTest
    static void saveContentRecord_upsertsByAddress() {
        MaPageContentController.ContentRecord payload = new MaPageContentController.ContentRecord();
        payload.offeringKey  = OFFERING;
        payload.templateType = TMPL;
        payload.sectionKey   = 'hero';
        payload.fieldKey     = 'headline';
        payload.fieldType    = 'text';
        payload.textValue    = 'First';
        payload.active       = true;
        payload.sortOrder    = 0;

        Test.startTest();
        String id1 = MaPageContentController.saveContentRecord(payload);
        payload.textValue = 'Second';
        String id2 = MaPageContentController.saveContentRecord(payload);
        Test.stopTest();

        System.assertEquals(id1, id2, 'Second save should upsert the same record');
        MA_Page_Content__c saved = [SELECT Text_Value__c FROM MA_Page_Content__c WHERE Id = :id1 LIMIT 1];
        System.assertEquals('Second', saved.Text_Value__c);
    }

    @IsTest
    static void saveContentRecord_throwsOnNullPayload() {
        Test.startTest();
        Boolean threw = false;
        try {
            MaPageContentController.saveContentRecord(null);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Null payload should throw AuraHandledException');
    }

    // ─── saveContentRecords (bulk) ────────────────────────────────────────────

    @IsTest
    static void saveContentRecords_insertsBulk() {
        List<MaPageContentController.ContentRecord> payloads = new List<MaPageContentController.ContentRecord>();
        for (Integer i = 0; i < 5; i++) {
            MaPageContentController.ContentRecord p = new MaPageContentController.ContentRecord();
            p.offeringKey  = OFFERING;
            p.templateType = TMPL;
            p.sectionKey   = 'section' + i;
            p.fieldKey     = 'field' + i;
            p.fieldType    = 'text';
            p.textValue    = 'Value ' + i;
            p.active       = true;
            p.sortOrder    = i;
            payloads.add(p);
        }

        Test.startTest();
        List<String> ids = MaPageContentController.saveContentRecords(payloads);
        Test.stopTest();

        System.assertEquals(5, ids.size(), 'Should return 5 IDs');
        System.assertEquals(5, [SELECT COUNT() FROM MA_Page_Content__c WHERE Offering_Key__c = :OFFERING]);
    }

    // ─── deleteContentRecord ──────────────────────────────────────────────────

    @IsTest
    static void deleteContentRecord_deletesRecord() {
        MA_Page_Content__c rec = makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'To delete', null, null, null, 0);
        insert rec;

        Test.startTest();
        MaPageContentController.deleteContentRecord(rec.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM MA_Page_Content__c WHERE Id = :rec.Id]);
    }

    @IsTest
    static void deleteContentRecord_throwsOnBlankId() {
        Test.startTest();
        Boolean threw = false;
        try {
            MaPageContentController.deleteContentRecord('');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank ID should throw AuraHandledException');
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
        List<MaPageContentController.EditorSection> secs =
            MaPageContentController.getEditorSections(OFFERING, TMPL);
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
        MaPageContentController.saveSectionOrder(
            new List<String>{ secs[1].Id, secs[0].Id });
        Test.stopTest();

        Map<Id, MA_Page_Section__c> after = new Map<Id, MA_Page_Section__c>(
            [SELECT Id, Sort_Order__c FROM MA_Page_Section__c]);
        System.assert(after.get(secs[1].Id).Sort_Order__c < after.get(secs[0].Id).Sort_Order__c,
            'The section moved to the top of the rail sorts first');
    }

    @IsTest
    static void saveSectionOrderIgnoresEmptyInput() {
        Test.startTest();
        MaPageContentController.saveSectionOrder(null);
        MaPageContentController.saveSectionOrder(new List<String>());
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM MA_Page_Section__c],
            'No rows created or touched by an empty reorder');
    }

    @IsTest
    static void setSectionActiveTogglesVisibility() {
        MA_Page_Section__c sec = pageSection('faq', 10, true);
        insert sec;

        Test.startTest();
        MaPageContentController.setSectionActive(sec.Id, false);
        Test.stopTest();

        System.assertEquals(false,
            [SELECT Active__c FROM MA_Page_Section__c WHERE Id = :sec.Id].Active__c,
            'Section is switched off without being deleted');
    }

    @IsTest
    static void setSectionActiveRejectsBlankId() {
        Boolean threw = false;
        Test.startTest();
        try {
            MaPageContentController.setSectionActive('', true);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'A blank section id is rejected');
    }

    // ─── draft / publish ──────────────────────────────────────────────────────

    private static MA_Page_Content__c published(String section, String field, String type, String value) {
        MA_Page_Content__c rec = makeRecord(
            OFFERING, TMPL, section, field, type,
            type == 'text' ? value : null,
            type == 'rich' ? value : null,
            type == 'json' ? value : null,
            null, 1);
        rec.Status__c = 'Published';
        return rec;
    }

    @IsTest
    static void draftDoesNotChangeWhatThePageReads() {
        MA_Page_Content__c rec = published('hero', 'eyebrow', 'text', 'Live copy');
        insert rec;

        MaPageContentController.DraftEdit edit = new MaPageContentController.DraftEdit();
        edit.id = rec.Id;
        edit.value = 'Edited but unpublished';

        Test.startTest();
        MaPageContentController.saveDrafts(new List<MaPageContentController.DraftEdit>{ edit });
        Map<String, String> live = MaPageContentReader.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals('Live copy', live.get('hero::eyebrow'),
            'The public page still shows the published value while a draft exists');
        MA_Page_Content__c after = [SELECT Status__c, Draft_Value__c FROM MA_Page_Content__c WHERE Id = :rec.Id];
        System.assertEquals('Draft', after.Status__c, 'The row is marked Draft');
        System.assertEquals('Edited but unpublished', after.Draft_Value__c, 'The draft is held separately');
    }

    @IsTest
    static void publishMovesDraftIntoTheColumnThePageReads() {
        MA_Page_Content__c rec = published('hero', 'eyebrow', 'text', 'Live copy');
        insert rec;
        MaPageContentController.DraftEdit edit = new MaPageContentController.DraftEdit();
        edit.id = rec.Id;
        edit.value = 'New copy';
        MaPageContentController.saveDrafts(new List<MaPageContentController.DraftEdit>{ edit });

        Test.startTest();
        Integer count = MaPageContentController.publishPage(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals(1, count, 'One field published');
        MA_Page_Content__c after = [
            SELECT Text_Value__c, Draft_Value__c, Status__c, Version_Number__c, Last_Published_Date__c
            FROM MA_Page_Content__c WHERE Id = :rec.Id];
        System.assertEquals('New copy', after.Text_Value__c, 'The page now reads the new value');
        System.assertEquals(null, after.Draft_Value__c, 'The draft is cleared');
        System.assertEquals('Published', after.Status__c, 'The row is Published');
        System.assertEquals(2, after.Version_Number__c,
            'Version_Number__c defaults to 1 on insert, so the first publish makes 2');
        System.assertNotEquals(null, after.Last_Published_Date__c, 'Publish time recorded');
    }

    @IsTest
    static void publishSnapshotsTheOutgoingValue() {
        MA_Page_Content__c rec = published('hero', 'eyebrow', 'text', 'Original');
        insert rec;
        MaPageContentController.DraftEdit edit = new MaPageContentController.DraftEdit();
        edit.id = rec.Id;
        edit.value = 'Replacement';
        MaPageContentController.saveDrafts(new List<MaPageContentController.DraftEdit>{ edit });

        Test.startTest();
        MaPageContentController.publishPage(OFFERING, TMPL);
        Test.stopTest();

        MA_Page_Content_Version__c v = [
            SELECT Snapshot__c, Version_Number__c FROM MA_Page_Content_Version__c
            WHERE Content__c = :rec.Id];
        System.assertEquals('Original', v.Snapshot__c,
            'The snapshot holds what was replaced, so it is what you roll back to');
        System.assertEquals(2, v.Version_Number__c,
            'The version carries the number the record moved to');
    }

    @IsTest
    static void publishRoutesEachTypeToItsOwnColumn() {
        MA_Page_Content__c richRec = published('hero', 'headline', 'rich', '<b>old</b>');
        MA_Page_Content__c jsonRec = published('problem', 'chips', 'json', '["old"]');
        insert new List<MA_Page_Content__c>{ richRec, jsonRec };

        MaPageContentController.DraftEdit a = new MaPageContentController.DraftEdit();
        a.id = richRec.Id; a.value = '<b>new</b>';
        MaPageContentController.DraftEdit b = new MaPageContentController.DraftEdit();
        b.id = jsonRec.Id; b.value = '["new"]';
        MaPageContentController.saveDrafts(new List<MaPageContentController.DraftEdit>{ a, b });

        Test.startTest();
        MaPageContentController.publishPage(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals('<b>new</b>',
            [SELECT Rich_Value__c FROM MA_Page_Content__c WHERE Id = :richRec.Id].Rich_Value__c,
            'rich publishes into Rich_Value__c');
        System.assertEquals('["new"]',
            [SELECT JSON_Value__c FROM MA_Page_Content__c WHERE Id = :jsonRec.Id].JSON_Value__c,
            'json publishes into JSON_Value__c');
    }

    @IsTest
    static void discardLeavesThePublishedValueAlone() {
        MA_Page_Content__c rec = published('hero', 'eyebrow', 'text', 'Live copy');
        insert rec;
        MaPageContentController.DraftEdit edit = new MaPageContentController.DraftEdit();
        edit.id = rec.Id;
        edit.value = 'Throw me away';
        MaPageContentController.saveDrafts(new List<MaPageContentController.DraftEdit>{ edit });

        Test.startTest();
        Integer count = MaPageContentController.discardDrafts(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals(1, count, 'One draft discarded');
        MA_Page_Content__c after = [
            SELECT Text_Value__c, Draft_Value__c, Status__c FROM MA_Page_Content__c WHERE Id = :rec.Id];
        System.assertEquals('Live copy', after.Text_Value__c, 'The published value survives a discard');
        System.assertEquals(null, after.Draft_Value__c, 'The draft is gone');
        System.assertEquals('Published', after.Status__c, 'Back to Published');
        System.assertEquals(0, [SELECT COUNT() FROM MA_Page_Content_Version__c],
            'Discarding does not create a version');
    }

    @IsTest
    static void publishWithNoDraftsIsANoOp() {
        insert published('hero', 'eyebrow', 'text', 'Live copy');
        Test.startTest();
        Integer count = MaPageContentController.publishPage(OFFERING, TMPL);
        Test.stopTest();
        System.assertEquals(0, count, 'Nothing to publish');
        System.assertEquals(0, [SELECT COUNT() FROM MA_Page_Content_Version__c],
            'No version written when nothing changed');
    }

    @IsTest
    static void publishIgnoresOtherPages() {
        MA_Page_Content__c mine = published('hero', 'eyebrow', 'text', 'Mine');
        MA_Page_Content__c other = published('hero', 'eyebrow', 'text', 'Theirs');
        other.Template_Type__c = 'configurator';
        other.Content_Address__c = OFFERING + '::configurator::hero::eyebrow';
        insert new List<MA_Page_Content__c>{ mine, other };

        MaPageContentController.DraftEdit a = new MaPageContentController.DraftEdit();
        a.id = mine.Id; a.value = 'Mine edited';
        MaPageContentController.DraftEdit b = new MaPageContentController.DraftEdit();
        b.id = other.Id; b.value = 'Theirs edited';
        MaPageContentController.saveDrafts(new List<MaPageContentController.DraftEdit>{ a, b });

        Test.startTest();
        Integer count = MaPageContentController.publishPage(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals(1, count, 'Only this page publishes');
        System.assertEquals('Theirs',
            [SELECT Text_Value__c FROM MA_Page_Content__c WHERE Id = :other.Id].Text_Value__c,
            'Another page keeps its unpublished draft');
    }
}
