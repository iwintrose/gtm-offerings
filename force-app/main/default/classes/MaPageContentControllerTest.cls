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
}
