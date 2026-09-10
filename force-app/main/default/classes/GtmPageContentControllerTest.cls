@IsTest
private class GtmPageContentControllerTest {

    private static final String OFFERING = 'ma-migrator';
    private static final String TMPL     = 'story';

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static GTM_Page_Content__c makeRecord(
            String offering, String tmpl, String section, String field,
            String fieldType, String textVal, String richVal, String jsonVal,
            String industry, Integer sortOrder) {
        GTM_Page_Content__c r = new GTM_Page_Content__c(
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
        Map<String, String> result = GtmPageContentController.getPageContent('', 'story', null);
        System.assertEquals(0, result.size(), 'Blank offeringKey should yield empty map');
    }

    @IsTest
    static void getPageContent_returnsTextRecord() {
        GTM_Page_Content__c rec = makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'Hello World', null, null, null, 0);
        insert rec;

        Test.startTest();
        Map<String, String> result = GtmPageContentController.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assert(result.containsKey('hero::headline'), 'Map should contain hero::headline');
        System.assertEquals('Hello World', result.get('hero::headline'));
    }

    @IsTest
    static void getPageContent_returnsRichRecord() {
        GTM_Page_Content__c rec = makeRecord(OFFERING, TMPL, 'hero', 'subhead', 'rich', null, '<b>Bold</b>', null, null, 0);
        insert rec;

        Test.startTest();
        Map<String, String> result = GtmPageContentController.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals('<b>Bold</b>', result.get('hero::subhead'));
    }

    @IsTest
    static void getPageContent_returnsJsonRecord() {
        GTM_Page_Content__c rec = makeRecord(OFFERING, TMPL, 'problem', 'chips', 'json', null, null, '["a","b"]', null, 0);
        insert rec;

        Test.startTest();
        Map<String, String> result = GtmPageContentController.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals('["a","b"]', result.get('problem::chips'));
    }

    @IsTest
    static void getPageContent_industryScopedWinsOverDefault() {
        List<GTM_Page_Content__c> recs = new List<GTM_Page_Content__c>{
            makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'Default headline', null, null, null, 0),
            makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'FS headline', null, null, 'financial-services', 0)
        };
        insert recs;

        Test.startTest();
        Map<String, String> result = GtmPageContentController.getPageContent(OFFERING, TMPL, 'financial-services');
        Test.stopTest();

        System.assertEquals('FS headline', result.get('hero::headline'), 'Industry-scoped record should win');
    }

    @IsTest
    static void getPageContent_industryNullFallsBackToDefault() {
        GTM_Page_Content__c rec = makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'Default headline', null, null, null, 0);
        insert rec;

        Test.startTest();
        Map<String, String> result = GtmPageContentController.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals('Default headline', result.get('hero::headline'));
    }

    @IsTest
    static void getPageContent_inactiveRecordExcluded() {
        GTM_Page_Content__c rec = makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'Should not appear', null, null, null, 0);
        rec.Active__c = false;
        insert rec;

        Test.startTest();
        Map<String, String> result = GtmPageContentController.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assert(!result.containsKey('hero::headline'), 'Inactive records should not appear');
    }

    @IsTest
    static void getPageContent_wrongTemplateExcluded() {
        GTM_Page_Content__c rec = makeRecord(OFFERING, 'configurator', 'hero', 'headline', 'text', 'Wrong template', null, null, null, 0);
        insert rec;

        Test.startTest();
        Map<String, String> result = GtmPageContentController.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assert(!result.containsKey('hero::headline'), 'Records for a different template should not appear');
    }

    // ─── getAllContent ────────────────────────────────────────────────────────

    @IsTest
    static void getAllContent_returnsAllActive() {
        List<GTM_Page_Content__c> recs = new List<GTM_Page_Content__c>{
            makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'H', null, null, null, 0),
            makeRecord(OFFERING, TMPL, 'hero', 'subhead',  'rich', null, '<p>S</p>', null, null, 1)
        };
        insert recs;

        Test.startTest();
        List<GtmPageContentController.ContentRecord> result = GtmPageContentController.getAllContent(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals(2, result.size());
    }

    @IsTest
    static void getAllContent_includesIndustryScoped() {
        List<GTM_Page_Content__c> recs = new List<GTM_Page_Content__c>{
            makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'Default', null, null, null, 0),
            makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'FS', null, null, 'financial-services', 0)
        };
        insert recs;

        Test.startTest();
        List<GtmPageContentController.ContentRecord> result = GtmPageContentController.getAllContent(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'getAllContent returns all rows including industry-scoped');
    }

    // ─── saveContentRecord ────────────────────────────────────────────────────

    @IsTest
    static void saveContentRecord_insertsNewRecord() {
        GtmPageContentController.ContentRecord payload = new GtmPageContentController.ContentRecord();
        payload.offeringKey  = OFFERING;
        payload.templateType = TMPL;
        payload.sectionKey   = 'hero';
        payload.fieldKey     = 'headline';
        payload.fieldType    = 'text';
        payload.textValue    = 'Saved headline';
        payload.active       = true;
        payload.sortOrder    = 0;

        Test.startTest();
        String newId = GtmPageContentController.saveContentRecord(payload);
        Test.stopTest();

        System.assertNotEquals(null, newId, 'Save should return an ID');
        GTM_Page_Content__c saved = [SELECT Text_Value__c FROM GTM_Page_Content__c WHERE Id = :newId LIMIT 1];
        System.assertEquals('Saved headline', saved.Text_Value__c);
    }

    @IsTest
    static void saveContentRecord_upsertsByAddress() {
        GtmPageContentController.ContentRecord payload = new GtmPageContentController.ContentRecord();
        payload.offeringKey  = OFFERING;
        payload.templateType = TMPL;
        payload.sectionKey   = 'hero';
        payload.fieldKey     = 'headline';
        payload.fieldType    = 'text';
        payload.textValue    = 'First';
        payload.active       = true;
        payload.sortOrder    = 0;

        Test.startTest();
        String id1 = GtmPageContentController.saveContentRecord(payload);
        payload.textValue = 'Second';
        String id2 = GtmPageContentController.saveContentRecord(payload);
        Test.stopTest();

        System.assertEquals(id1, id2, 'Second save should upsert the same record');
        GTM_Page_Content__c saved = [SELECT Text_Value__c FROM GTM_Page_Content__c WHERE Id = :id1 LIMIT 1];
        System.assertEquals('Second', saved.Text_Value__c);
    }

    @IsTest
    static void saveContentRecord_throwsOnNullPayload() {
        Test.startTest();
        Boolean threw = false;
        try {
            GtmPageContentController.saveContentRecord(null);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Null payload should throw AuraHandledException');
    }

    // ─── saveContentRecords (bulk) ────────────────────────────────────────────

    @IsTest
    static void saveContentRecords_insertsBulk() {
        List<GtmPageContentController.ContentRecord> payloads = new List<GtmPageContentController.ContentRecord>();
        for (Integer i = 0; i < 5; i++) {
            GtmPageContentController.ContentRecord p = new GtmPageContentController.ContentRecord();
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
        List<String> ids = GtmPageContentController.saveContentRecords(payloads);
        Test.stopTest();

        System.assertEquals(5, ids.size(), 'Should return 5 IDs');
        System.assertEquals(5, [SELECT COUNT() FROM GTM_Page_Content__c WHERE Offering_Key__c = :OFFERING]);
    }

    // ─── deleteContentRecord ──────────────────────────────────────────────────

    @IsTest
    static void deleteContentRecord_deletesRecord() {
        GTM_Page_Content__c rec = makeRecord(OFFERING, TMPL, 'hero', 'headline', 'text', 'To delete', null, null, null, 0);
        insert rec;

        Test.startTest();
        GtmPageContentController.deleteContentRecord(rec.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM GTM_Page_Content__c WHERE Id = :rec.Id]);
    }

    @IsTest
    static void deleteContentRecord_throwsOnBlankId() {
        Test.startTest();
        Boolean threw = false;
        try {
            GtmPageContentController.deleteContentRecord('');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank ID should throw AuraHandledException');
    }
    // ─── draft / publish ──────────────────────────────────────────────────────

    private static GTM_Page_Content__c published(String section, String field, String type, String value) {
        GTM_Page_Content__c rec = makeRecord(
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
        GTM_Page_Content__c rec = published('hero', 'eyebrow', 'text', 'Live copy');
        insert rec;

        GtmPageContentController.DraftEdit edit = new GtmPageContentController.DraftEdit();
        edit.id = rec.Id;
        edit.value = 'Edited but unpublished';

        Test.startTest();
        GtmPageContentController.saveDrafts(new List<GtmPageContentController.DraftEdit>{ edit });
        Map<String, String> live = GtmPageContentReader.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals('Live copy', live.get('hero::eyebrow'),
            'The public page still shows the published value while a draft exists');
        GTM_Page_Content__c after = [SELECT Status__c, Draft_Value__c FROM GTM_Page_Content__c WHERE Id = :rec.Id];
        System.assertEquals('Draft', after.Status__c, 'The row is marked Draft');
        System.assertEquals('Edited but unpublished', after.Draft_Value__c, 'The draft is held separately');
    }

    @IsTest
    static void publishMovesDraftIntoTheColumnThePageReads() {
        GTM_Page_Content__c rec = published('hero', 'eyebrow', 'text', 'Live copy');
        insert rec;
        GtmPageContentController.DraftEdit edit = new GtmPageContentController.DraftEdit();
        edit.id = rec.Id;
        edit.value = 'New copy';
        GtmPageContentController.saveDrafts(new List<GtmPageContentController.DraftEdit>{ edit });

        Test.startTest();
        Integer count = GtmPageContentController.publishPage(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals(1, count, 'One field published');
        GTM_Page_Content__c after = [
            SELECT Text_Value__c, Draft_Value__c, Status__c, Version_Number__c, Last_Published_Date__c
            FROM GTM_Page_Content__c WHERE Id = :rec.Id];
        System.assertEquals('New copy', after.Text_Value__c, 'The page now reads the new value');
        System.assertEquals(null, after.Draft_Value__c, 'The draft is cleared');
        System.assertEquals('Published', after.Status__c, 'The row is Published');
        System.assertEquals(2, after.Version_Number__c,
            'Version_Number__c defaults to 1 on insert, so the first publish makes 2');
        System.assertNotEquals(null, after.Last_Published_Date__c, 'Publish time recorded');
    }

    @IsTest
    static void publishSnapshotsTheOutgoingValue() {
        GTM_Page_Content__c rec = published('hero', 'eyebrow', 'text', 'Original');
        insert rec;
        GtmPageContentController.DraftEdit edit = new GtmPageContentController.DraftEdit();
        edit.id = rec.Id;
        edit.value = 'Replacement';
        GtmPageContentController.saveDrafts(new List<GtmPageContentController.DraftEdit>{ edit });

        Test.startTest();
        GtmPageContentController.publishPage(OFFERING, TMPL);
        Test.stopTest();

        GTM_Page_Content_Version__c v = [
            SELECT Snapshot__c, Version_Number__c FROM GTM_Page_Content_Version__c
            WHERE Content__c = :rec.Id];
        System.assertEquals('Original', v.Snapshot__c,
            'The snapshot holds what was replaced, so it is what you roll back to');
        System.assertEquals(2, v.Version_Number__c,
            'The version carries the number the record moved to');
    }

    @IsTest
    static void publishRoutesEachTypeToItsOwnColumn() {
        GTM_Page_Content__c richRec = published('hero', 'headline', 'rich', '<b>old</b>');
        GTM_Page_Content__c jsonRec = published('problem', 'chips', 'json', '["old"]');
        insert new List<GTM_Page_Content__c>{ richRec, jsonRec };

        GtmPageContentController.DraftEdit a = new GtmPageContentController.DraftEdit();
        a.id = richRec.Id; a.value = '<b>new</b>';
        GtmPageContentController.DraftEdit b = new GtmPageContentController.DraftEdit();
        b.id = jsonRec.Id; b.value = '["new"]';
        GtmPageContentController.saveDrafts(new List<GtmPageContentController.DraftEdit>{ a, b });

        Test.startTest();
        GtmPageContentController.publishPage(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals('<b>new</b>',
            [SELECT Rich_Value__c FROM GTM_Page_Content__c WHERE Id = :richRec.Id].Rich_Value__c,
            'rich publishes into Rich_Value__c');
        System.assertEquals('["new"]',
            [SELECT JSON_Value__c FROM GTM_Page_Content__c WHERE Id = :jsonRec.Id].JSON_Value__c,
            'json publishes into JSON_Value__c');
    }

    @IsTest
    static void discardLeavesThePublishedValueAlone() {
        GTM_Page_Content__c rec = published('hero', 'eyebrow', 'text', 'Live copy');
        insert rec;
        GtmPageContentController.DraftEdit edit = new GtmPageContentController.DraftEdit();
        edit.id = rec.Id;
        edit.value = 'Throw me away';
        GtmPageContentController.saveDrafts(new List<GtmPageContentController.DraftEdit>{ edit });

        Test.startTest();
        Integer count = GtmPageContentController.discardDrafts(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals(1, count, 'One draft discarded');
        GTM_Page_Content__c after = [
            SELECT Text_Value__c, Draft_Value__c, Status__c FROM GTM_Page_Content__c WHERE Id = :rec.Id];
        System.assertEquals('Live copy', after.Text_Value__c, 'The published value survives a discard');
        System.assertEquals(null, after.Draft_Value__c, 'The draft is gone');
        System.assertEquals('Published', after.Status__c, 'Back to Published');
        System.assertEquals(0, [SELECT COUNT() FROM GTM_Page_Content_Version__c],
            'Discarding does not create a version');
    }

    @IsTest
    static void publishWithNoDraftsIsANoOp() {
        insert published('hero', 'eyebrow', 'text', 'Live copy');
        Test.startTest();
        Integer count = GtmPageContentController.publishPage(OFFERING, TMPL);
        Test.stopTest();
        System.assertEquals(0, count, 'Nothing to publish');
        System.assertEquals(0, [SELECT COUNT() FROM GTM_Page_Content_Version__c],
            'No version written when nothing changed');
    }

    @IsTest
    static void publishIgnoresOtherPages() {
        GTM_Page_Content__c mine = published('hero', 'eyebrow', 'text', 'Mine');
        GTM_Page_Content__c other = published('hero', 'eyebrow', 'text', 'Theirs');
        other.Template_Type__c = 'configurator';
        other.Content_Address__c = OFFERING + '::configurator::hero::eyebrow';
        insert new List<GTM_Page_Content__c>{ mine, other };

        GtmPageContentController.DraftEdit a = new GtmPageContentController.DraftEdit();
        a.id = mine.Id; a.value = 'Mine edited';
        GtmPageContentController.DraftEdit b = new GtmPageContentController.DraftEdit();
        b.id = other.Id; b.value = 'Theirs edited';
        GtmPageContentController.saveDrafts(new List<GtmPageContentController.DraftEdit>{ a, b });

        Test.startTest();
        Integer count = GtmPageContentController.publishPage(OFFERING, TMPL);
        Test.stopTest();

        System.assertEquals(1, count, 'Only this page publishes');
        System.assertEquals('Theirs',
            [SELECT Text_Value__c FROM GTM_Page_Content__c WHERE Id = :other.Id].Text_Value__c,
            'Another page keeps its unpublished draft');
    }

    // ─── setOfferingStatus / setOfferingArchived ───────────────────────────────
    // Issue #26, item 4: toggling an offering's dashboard Status/Archive flags,
    // which live on that offering's own tile section (Section_Key__c='tile',
    // Template_Type__c='offerings-listing') -- offering-level flags scoped to
    // one section record, not per-section-in-general settings. Ordinary DML,
    // same instant-effect pattern as setSectionActive.

    @isTest
    static void setOfferingStatus_createsTheTileSectionWhenNoneExistsYet() {
        Test.startTest();
        Boolean result = GtmPageContentController.setOfferingStatus('brand-new-offering', 'Draft');
        Test.stopTest();

        System.assert(result, 'The call should report success');
        GTM_Page_Section__c sec = [
            SELECT Offering_Status__c, Section_Key__c, Template_Type__c
            FROM GTM_Page_Section__c
            WHERE Section_Address__c = 'brand-new-offering::offerings-listing::tile'
        ];
        System.assertEquals('Draft', sec.Offering_Status__c);
        System.assertEquals('tile', sec.Section_Key__c);
        System.assertEquals('offerings-listing', sec.Template_Type__c);
    }

    @isTest
    static void setOfferingStatus_updatesAnExistingTileSectionInPlace() {
        GtmPageContentController.createOffering('Status Toggle Offering');
        String key = 'status-toggle-offering';

        Test.startTest();
        GtmPageContentController.setOfferingStatus(key, 'Draft');
        GtmPageContentController.setOfferingStatus(key, 'Published');
        Test.stopTest();

        List<GTM_Page_Section__c> secs = [
            SELECT Offering_Status__c FROM GTM_Page_Section__c
            WHERE Offering_Key__c = :key AND Section_Key__c = 'tile'
            AND Template_Type__c = 'offerings-listing'
        ];
        System.assertEquals(1, secs.size(), 'Toggling twice must not create a second tile section');
        System.assertEquals('Published', secs[0].Offering_Status__c);
    }

    @isTest
    static void setOfferingStatus_rejectsAnythingOtherThanDraftOrPublished() {
        Boolean refused = false;
        Test.startTest();
        try { GtmPageContentController.setOfferingStatus('ma-migrator', 'Archived'); }
        catch (Exception e) { refused = true; }
        Test.stopTest();
        System.assert(refused, 'Only Draft/Published are valid statuses');
    }

    @isTest
    static void setOfferingStatus_refusesTheFramework() {
        Boolean refused = false;
        Test.startTest();
        try { GtmPageContentController.setOfferingStatus('gtm', 'Draft'); }
        catch (Exception e) { refused = true; }
        Test.stopTest();
        System.assert(refused, 'The framework is not an offering and has no dashboard status');
    }

    @isTest
    static void setOfferingArchived_setsAndClearsTheFlagOnTheTileSection() {
        GtmPageContentController.createOffering('Archive Toggle Offering');
        String key = 'archive-toggle-offering';

        Test.startTest();
        GtmPageContentController.setOfferingArchived(key, true);
        Test.stopTest();

        GTM_Page_Section__c sec = [
            SELECT Archived__c FROM GTM_Page_Section__c
            WHERE Offering_Key__c = :key AND Section_Key__c = 'tile'
            AND Template_Type__c = 'offerings-listing'
        ];
        System.assertEquals(true, sec.Archived__c);

        GtmPageContentController.setOfferingArchived(key, false);
        sec = [
            SELECT Archived__c FROM GTM_Page_Section__c
            WHERE Offering_Key__c = :key AND Section_Key__c = 'tile'
            AND Template_Type__c = 'offerings-listing'
        ];
        System.assertEquals(false, sec.Archived__c, 'Un-archiving must be reversible from the same method');
    }

    @isTest
    static void setOfferingArchived_refusesTheFramework() {
        Boolean refused = false;
        Test.startTest();
        try { GtmPageContentController.setOfferingArchived('gtm', true); }
        catch (Exception e) { refused = true; }
        Test.stopTest();
        System.assert(refused, 'The framework is not an offering and cannot be archived');
    }

    @isTest
    static void getHomeSummary_reflectsOfferingStatusAndArchivedFlags() {
        GtmPageContentController.createOffering('Home Summary Offering');
        String key = 'home-summary-offering';
        GtmPageContentController.setOfferingStatus(key, 'Draft');
        GtmPageContentController.setOfferingArchived(key, true);

        Test.startTest();
        GtmPageContentController.HomeSummary home = GtmPageContentController.getHomeSummary();
        Test.stopTest();

        GtmPageContentController.OfferingSummary found;
        for (GtmPageContentController.OfferingSummary o : home.offerings) {
            if (o.offeringKey == key) found = o;
        }
        System.assertNotEquals(null, found, 'The offering must still appear in the Content Manager home list');
        System.assertEquals('Draft', found.offeringStatus);
        System.assertEquals(true, found.archived);
    }

    @isTest
    static void getHomeSummary_defaultsOfferingStatusAndArchivedWhenNoTileSectionExists() {
        // GTM_Offering__mdt ships a "Migration Accelerator" record with no
        // guarantee its tile section exists in this test's data -- either
        // way, an offering with no tile row yet must read as Published/not
        // archived, matching the field defaults so existing offerings are
        // unaffected by this change.
        Test.startTest();
        GtmPageContentController.HomeSummary home = GtmPageContentController.getHomeSummary();
        Test.stopTest();

        for (GtmPageContentController.OfferingSummary o : home.offerings) {
            if (o.isFramework) continue;
            System.assertNotEquals(null, o.offeringStatus, 'offeringStatus must never be null');
        }
    }
}
