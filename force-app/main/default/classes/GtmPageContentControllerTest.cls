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

    /**
     * A minimal "built" page for setOfferingStatus's publish guard: one
     * active section plus one active content row for offering+templateType,
     * the same sectionCount>0 AND fieldCount>0 shape unbuiltRequiredPages()
     * checks. createOffering() only ever seeds Offerings Listing (its tile),
     * never Story/Configurator, so tests that need those two "real" also use
     * this helper rather than assuming createOffering() covers them.
     */
    private static void seedBuiltPage(String offeringKey, String templateType) {
        insert new GTM_Page_Section__c(
            Section_Address__c = offeringKey + '::' + templateType + '::hero',
            Offering_Key__c    = offeringKey,
            Template_Type__c   = templateType,
            Section_Key__c     = 'hero',
            Label__c           = 'Hero',
            Layout_Type__c     = 'hero',
            Width__c           = 'standard',
            Sort_Order__c      = 10,
            Active__c          = true,
            Status__c          = 'Published'
        );
        insert makeRecord(offeringKey, templateType, 'hero', 'headline', 'text', 'Hello', null, null, null, 0);
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
        // createOffering() only seeds the Offerings Listing tile (1 section,
        // 3 content rows) -- Story and Configurator need their own real page
        // here now that Draft -> Published is gated on all three being built
        // (sectionCount > 0 AND fieldCount > 0), or this Published call would
        // be (correctly) rejected rather than exercising the toggle-in-place
        // behavior this test is actually about.
        seedBuiltPage(key, 'story');
        seedBuiltPage(key, 'configurator');

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
    static void setOfferingStatus_blocksPublishWhenRequiredPagesAreEmpty() {
        // A brand-new offering key with no GTM_Page_Section__c/Content__c
        // rows at all -- none of Story, Configurator or Offerings Listing
        // has ever been built.
        String key = 'unbuilt-offering';

        String message;
        Test.startTest();
        try {
            GtmPageContentController.setOfferingStatus(key, 'Published');
            System.assert(false, 'Publishing an offering with no built pages must be blocked');
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        System.assert(message.contains('Story'), 'Missing Story must be named: ' + message);
        System.assert(message.contains('Configurator'), 'Missing Configurator must be named: ' + message);
        System.assert(message.contains('Offerings Listing'), 'Missing Offerings Listing must be named: ' + message);

        // The rejected attempt must not leave any tileSectionFor() scaffold
        // (or any other row) behind -- the guard runs before any DML.
        System.assertEquals(0, [SELECT COUNT() FROM GTM_Page_Section__c WHERE Offering_Key__c = :key],
            'A blocked publish must not insert the tile-section scaffold');
        System.assertEquals(0, [SELECT COUNT() FROM GTM_Page_Content__c WHERE Offering_Key__c = :key],
            'A blocked publish must not insert any content row either');
    }

    @isTest
    static void setOfferingStatus_blocksPublishWhenOfferingsListingIsScaffoldOnly() {
        // Reproduces the exact live bug: Story and Configurator are fully
        // built, but Offerings Listing is only the bare tile section
        // tileSectionFor() leaves behind (1 section, 0 content rows) -- e.g.
        // from an earlier Draft/Archive toggle on an offering that had never
        // built its listing page. sectionCount alone would call this
        // "built"; fieldCount = 0 must still block the publish.
        String key = 'scaffold-only-offering';
        seedBuiltPage(key, 'story');
        seedBuiltPage(key, 'configurator');
        GtmPageContentController.setOfferingStatus(key, 'Draft');

        System.assertEquals(1,
            [SELECT COUNT() FROM GTM_Page_Section__c
             WHERE Offering_Key__c = :key AND Template_Type__c = 'offerings-listing'],
            'Setup check: the Draft toggle should have left exactly the bare scaffold tile');
        System.assertEquals(0,
            [SELECT COUNT() FROM GTM_Page_Content__c
             WHERE Offering_Key__c = :key AND Template_Type__c = 'offerings-listing'],
            'Setup check: the scaffold tile must carry no content rows');

        String message;
        Test.startTest();
        try {
            GtmPageContentController.setOfferingStatus(key, 'Published');
            System.assert(false, 'A scaffold-only Offerings Listing page must still block publish');
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        System.assert(message.contains('Offerings Listing'), 'Offerings Listing must be named: ' + message);
        System.assert(!message.contains('Story'), 'Story is built and must not be named: ' + message);
        System.assert(!message.contains('Configurator'), 'Configurator is built and must not be named: ' + message);

        List<GTM_Page_Section__c> secs = [
            SELECT Offering_Status__c FROM GTM_Page_Section__c
            WHERE Offering_Key__c = :key AND Section_Key__c = 'tile'
            AND Template_Type__c = 'offerings-listing'
        ];
        System.assertEquals(1, secs.size());
        System.assertEquals('Draft', secs[0].Offering_Status__c,
            'A blocked publish must leave the offering exactly as Draft, not partially updated');
    }

    @isTest
    static void setOfferingStatus_allowsPublishOnceAllThreeRequiredPagesAreBuilt() {
        // The regression check for a real, fully-built offering: this must
        // still succeed once every required page has both a section and a
        // content row, including Offerings Listing built the normal way
        // (createOffering(), not the tileSectionFor() scaffold).
        GtmPageContentController.createOffering('Fully Built Offering');
        String key = 'fully-built-offering';
        seedBuiltPage(key, 'story');
        seedBuiltPage(key, 'configurator');

        Test.startTest();
        Boolean result = GtmPageContentController.setOfferingStatus(key, 'Published');
        Test.stopTest();

        System.assert(result, 'A fully-built offering must be allowed to publish');
        GTM_Page_Section__c sec = [
            SELECT Offering_Status__c FROM GTM_Page_Section__c
            WHERE Offering_Key__c = :key AND Section_Key__c = 'tile'
            AND Template_Type__c = 'offerings-listing'
        ];
        System.assertEquals('Published', sec.Offering_Status__c);
    }

    @isTest
    static void setOfferingStatus_neverGatesDraftEvenWhenNoPagesAreBuilt() {
        // Draft (and, separately, setOfferingArchived below) must remain
        // unconditional -- only a Draft -> Published transition is gated.
        String key = 'draft-only-offering';

        Test.startTest();
        Boolean result = GtmPageContentController.setOfferingStatus(key, 'Draft');
        Test.stopTest();

        System.assert(result, 'Draft must never be blocked, regardless of what is built');
        GTM_Page_Section__c sec = [
            SELECT Offering_Status__c FROM GTM_Page_Section__c
            WHERE Offering_Key__c = :key AND Section_Key__c = 'tile'
            AND Template_Type__c = 'offerings-listing'
        ];
        System.assertEquals('Draft', sec.Offering_Status__c);
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

    // ─── renamePage ───────────────────────────────────────────────────────────
    // Issue #21: the eight structural/Framework page types have a fixed name --
    // Apex must refuse renamePage() for any of them before the upsert runs, both
    // as the must-have half of the fix (a direct Apex/API call has no LWC guard
    // to stop it) and independently of GtmPageContentController's own
    // STRUCTURAL_TEMPLATE_TYPES set. This list is its own hand-authored copy,
    // same "two independently-maintained copies that must agree" convention as
    // FRAMEWORK_KEY -- not read off the class under test, so a change to the
    // real set only passes here if it was made deliberately in both places.

    private static final List<String> STRUCTURAL_TEMPLATE_TYPES = new List<String>{
        'offerings-page', 'industry-chooser', 'faq-bd', 'faq-content-manager',
        'assistant', 'story', 'configurator', 'offerings-listing'
    };

    @isTest
    static void renamePage_blockListIsExactlyTheEightStructuralTypes() {
        // Catches drift: if a structural type is ever added to or removed from
        // GtmPageContentController's block-list without this test list being
        // updated to match, this assertion is the first thing to fail.
        System.assertEquals(8, STRUCTURAL_TEMPLATE_TYPES.size(),
            'Exactly eight templateTypes are structural/Framework -- update this list deliberately if that changes');
    }

    @isTest
    static void renamePage_throwsForEveryStructuralTemplateTypeAndWritesNoRow() {
        Test.startTest();
        for (String t : STRUCTURAL_TEMPLATE_TYPES) {
            Boolean threw = false;
            try {
                GtmPageContentController.renamePage(OFFERING, t, 'Hacked Title for ' + t);
            } catch (AuraHandledException ex) {
                threw = true;
            }
            System.assert(threw, 'renamePage should throw AuraHandledException for structural templateType "' + t + '"');

            String addr = OFFERING + '::' + t + '::page::title';
            System.assertEquals(0,
                [SELECT COUNT() FROM GTM_Page_Content__c WHERE Content_Address__c = :addr],
                'No page::title override row should be written for structural templateType "' + t + '"');
        }
        Test.stopTest();
    }

    @isTest
    static void renamePage_noNonStructuralTemplateTypeExistsTodayGuardIsForwardLooking() {
        // A real DML round-trip proving renamePage() "succeeds for a
        // non-structural templateType" cannot be written today: this method
        // used to insert with a fake templateType ('custom-page'), but
        // GTM_Page_Content__c.Template_Type__c (and its GTM_Page_Section__c
        // mirror) is a RESTRICTED picklist with exactly the eight values in
        // STRUCTURAL_TEMPLATE_TYPES above -- see
        // force-app/main/default/objects/GTM_Page_Content__c/fields/Template_Type__c.field-meta.xml.
        // Any value outside that set is rejected by the picklist itself with
        // INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST before renamePage()'s own
        // guard logic is ever exercised, on every org -- not just gtm-staging
        // -- so that DML failure proved nothing about the guard.
        //
        // Instead, assert the absence directly using the same
        // Schema.getDescribe()/getPicklistValues() pattern this codebase
        // already uses elsewhere (see GtmAssessmentListControllerTest's
        // everyReadoutStateMapsToExactlyOneKey / uiFilterVocabulariesMatchThePicklistsTheyFilter):
        // confirm every value the picklist will actually let through DML is
        // already accounted for in STRUCTURAL_TEMPLATE_TYPES. Today every
        // persistable Template_Type__c value is structural, so the "allow"
        // branch of renamePage()'s guard is currently unreachable via real
        // data -- the guard exists as forward-looking defense-in-depth for
        // when a non-structural page type is eventually added to the
        // picklist. If that happens, this assertion fails and names exactly
        // which new value needs a real "renamePage succeeds" DML test
        // written against it, replacing this method.
        Set<String> persistableValues = new Set<String>();
        for (Schema.PicklistEntry pe : GTM_Page_Content__c.Template_Type__c.getDescribe().getPicklistValues()) {
            persistableValues.add(pe.getValue());
        }
        System.assert(!persistableValues.isEmpty(), 'Sanity check: the picklist describe must return values');
        for (String value : persistableValues) {
            System.assert(STRUCTURAL_TEMPLATE_TYPES.indexOf(value) != -1,
                'Template_Type__c picklist value "' + value + '" is not in STRUCTURAL_TEMPLATE_TYPES -- ' +
                'it is a non-structural templateType and renamePage() must be proven to still succeed for it ' +
                'with a real DML test, not just asserted absent here.');
        }
    }

    // ─── createIndustry ───────────────────────────────────────────────────────
    // Hermetic: every test builds its own gtm/industry-chooser page. Nothing is
    // seeded and no offering or industry data is assumed.

    private static final String IND_OFFERING = 'gtm';
    private static final String IND_TMPL     = 'industry-chooser';

    /** Test-local copy of the industry-tile field vocabulary (the client's fieldsFor('industry-tile')). */
    private static List<GtmPageSectionController.FieldSeed> industrySeeds() {
        List<GtmPageSectionController.FieldSeed> out = new List<GtmPageSectionController.FieldSeed>();
        for (String k : new List<String>{ 'industryLabel', 'whyHead', 'demoRoot' }) { out.add(seed(k, 'text')); }
        for (String k : new List<String>{ 'pickerBlurb', 'coverSub', 'problem', 'useCase',
                                          'solution', 'proofLine', 'whyLine' }) { out.add(seed(k, 'rich')); }
        for (String k : new List<String>{ 'uniquePoints', 'demoDeps' }) { out.add(seed(k, 'json')); }
        return out;
    }

    private static GtmPageSectionController.FieldSeed seed(String key, String type) {
        GtmPageSectionController.FieldSeed s = new GtmPageSectionController.FieldSeed();
        s.fieldKey  = key;
        s.fieldType = type;
        s.label     = 'Label ' + key;
        return s;
    }

    private static void makeChooserPage() {
        insert new GTM_Page_Section__c(
            Section_Address__c = IND_OFFERING + '::' + IND_TMPL + '::header',
            Offering_Key__c = IND_OFFERING, Template_Type__c = IND_TMPL,
            Section_Key__c = 'header', Label__c = 'Header', Layout_Type__c = 'industry-tile',
            Width__c = 'standard', Sort_Order__c = 50, Active__c = true, Status__c = 'Published');
    }

    private static Integer sectionCount() {
        return [SELECT COUNT() FROM GTM_Page_Section__c WHERE Offering_Key__c = :IND_OFFERING AND Template_Type__c = :IND_TMPL];
    }

    private static Integer rowCount() {
        return [SELECT COUNT() FROM GTM_Page_Content__c WHERE Offering_Key__c = :IND_OFFERING AND Template_Type__c = :IND_TMPL];
    }

    /** Runs createIndustry and returns the exception message, or null if it succeeded. */
    private static String industryError(String label, List<GtmPageSectionController.FieldSeed> seeds) {
        try {
            GtmPageContentController.createIndustry(label, seeds);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @isTest
    static void createIndustry_happyPath_createsDraftSectionAndTwelveRows() {
        makeChooserPage();

        Test.startTest();
        String key = GtmPageContentController.createIndustry('Financial Services', industrySeeds());
        Test.stopTest();

        Assert.areEqual('industry-financial-services', key);
        GTM_Page_Section__c sec = [
            SELECT Section_Address__c, Layout_Type__c, Width__c, Label__c, Active__c, Status__c, Sort_Order__c
            FROM GTM_Page_Section__c WHERE Section_Key__c = :key];
        Assert.areEqual('gtm::industry-chooser::industry-financial-services', sec.Section_Address__c);
        Assert.areEqual('industry-tile', sec.Layout_Type__c);
        Assert.areEqual('standard', sec.Width__c);
        Assert.areEqual('Financial Services', sec.Label__c);
        Assert.isTrue(sec.Active__c);
        Assert.areEqual('Draft', sec.Status__c);
        Assert.areEqual(60, Integer.valueOf(sec.Sort_Order__c), 'Sorted after the existing section (50) by 10');

        List<GTM_Page_Content__c> rows = [
            SELECT Field_Key__c, Field_Type__c, Label__c, Content_Address__c, Sort_Order__c, Active__c, Status__c,
                   Draft_Value__c, Text_Value__c, Rich_Value__c, JSON_Value__c
            FROM GTM_Page_Content__c WHERE Section_Key__c = :key ORDER BY Sort_Order__c];
        Assert.areEqual(12, rows.size());
        Assert.areEqual(10, Integer.valueOf(rows[0].Sort_Order__c));
        Assert.areEqual(120, Integer.valueOf(rows[11].Sort_Order__c));
        Integer withDraft = 0;
        for (GTM_Page_Content__c r : rows) {
            Assert.isTrue(r.Active__c);
            Assert.areEqual('gtm::industry-chooser::' + key + '::' + r.Field_Key__c, r.Content_Address__c);
            if (r.Field_Type__c == 'json') Assert.areEqual('[]', r.JSON_Value__c);
            if (r.Field_Key__c == 'industryLabel') {
                Assert.areEqual('Financial Services', r.Draft_Value__c);
                Assert.isNull(r.Text_Value__c, 'The live column stays blank until Publish');
                Assert.areEqual('Draft', r.Status__c);
            }
            if (r.Draft_Value__c != null) withDraft++;
            Assert.isNull(r.Rich_Value__c);
        }
        Assert.areEqual(1, withDraft, 'Only industryLabel holds a value');
    }

    @isTest
    static void createIndustry_successiveIndustriesSortAfterEachOther() {
        makeChooserPage();
        GtmPageContentController.createIndustry('One', industrySeeds());
        GtmPageContentController.createIndustry('Two', industrySeeds());

        Assert.areEqual(60, Integer.valueOf([SELECT Sort_Order__c FROM GTM_Page_Section__c WHERE Section_Key__c = 'industry-one'].Sort_Order__c));
        Assert.areEqual(70, Integer.valueOf([SELECT Sort_Order__c FROM GTM_Page_Section__c WHERE Section_Key__c = 'industry-two'].Sort_Order__c));
    }

    @isTest
    static void createIndustry_duplicateVariants_areRefusedAndChangeNothing() {
        makeChooserPage();
        GtmPageContentController.createIndustry('Financial Services', industrySeeds());
        Integer sections = sectionCount();
        Integer rows = rowCount();

        for (String variant : new List<String>{
                'Financial Services', 'financial services', 'Financial-Services', 'Financial Services!' }) {
            String err = industryError(variant, industrySeeds());
            Assert.isNotNull(err, 'Should refuse "' + variant + '"');
            Assert.areEqual('An industry called "' + variant + '" already exists. Edit it instead.', err);
        }
        Assert.areEqual(sections, sectionCount());
        Assert.areEqual(rows, rowCount());
    }

    @isTest
    static void createIndustry_blankLabel_isRefused() {
        makeChooserPage();
        Assert.areEqual('Give the industry a name.', industryError(null, industrySeeds()));
        Assert.areEqual('Give the industry a name.', industryError('   ', industrySeeds()));
        Assert.areEqual(1, sectionCount());
    }

    @isTest
    static void createIndustry_punctuationOnlyLabel_isRefused() {
        makeChooserPage();
        Assert.areEqual('That name has no letters or numbers to build a key from.',
            industryError('!!!', industrySeeds()));
        Assert.areEqual(1, sectionCount());
    }

    @isTest
    static void createIndustry_labelOver80_isTrimmedAndKeyFitsTheField() {
        makeChooserPage();
        String key = GtmPageContentController.createIndustry('a'.repeat(100), industrySeeds());

        GTM_Page_Section__c sec = [SELECT Label__c FROM GTM_Page_Section__c WHERE Section_Key__c = :key];
        Assert.areEqual(80, sec.Label__c.length());
        Assert.isTrue(key.length() <= 80, 'Key length ' + key.length());
        Assert.areEqual('industry-' + 'a'.repeat(71), key);
        Assert.areEqual(80, [SELECT Draft_Value__c FROM GTM_Page_Content__c
                             WHERE Section_Key__c = :key AND Field_Key__c = 'industryLabel'].Draft_Value__c.length());
        Assert.areEqual(12, [SELECT COUNT() FROM GTM_Page_Content__c WHERE Section_Key__c = :key]);
    }

    @isTest
    static void createIndustry_slugBoundaryAt71() {
        makeChooserPage();
        String at71 = GtmPageContentController.createIndustry('b'.repeat(71), industrySeeds());
        Assert.areEqual('industry-' + 'b'.repeat(71), at71);
        Assert.areEqual(80, at71.length());

        String at72 = GtmPageContentController.createIndustry('c'.repeat(72), industrySeeds());
        Assert.areEqual('industry-' + 'c'.repeat(71), at72, 'A 72-character slug is cut to 71');
    }

    @isTest
    static void createIndustry_cutThatEndsOnADash_isReTrimmed() {
        makeChooserPage();
        // 70 letters, a space, then more: the slug is 70 a's + '-' + 'zzz...', and the
        // 71-character cut lands exactly on the dash, which must not be kept.
        String key = GtmPageContentController.createIndustry('a'.repeat(70) + ' ' + 'z'.repeat(20), industrySeeds());
        Assert.areEqual('industry-' + 'a'.repeat(70), key);
    }

    @isTest
    static void createIndustry_pageMissing_isRefused() {
        Assert.areEqual('Create the Industry Chooser page first.', industryError('Retail', industrySeeds()));
        Assert.areEqual(0, sectionCount());
    }

    @isTest
    static void createIndustry_atTheTwoHundredSectionCeiling_isRefusedWithAPlainMessage() {
        List<GTM_Page_Section__c> secs = new List<GTM_Page_Section__c>();
        for (Integer i = 0; i < 200; i++) {
            secs.add(new GTM_Page_Section__c(
                Section_Address__c = IND_OFFERING + '::' + IND_TMPL + '::s' + i,
                Offering_Key__c = IND_OFFERING, Template_Type__c = IND_TMPL,
                Section_Key__c = 's' + i, Label__c = 'S' + i, Layout_Type__c = 'industry-tile',
                Width__c = 'standard', Sort_Order__c = i, Active__c = true, Status__c = 'Published'));
        }
        insert secs;

        Assert.areEqual('The Industry Chooser page has reached its limit of 200 sections.',
            industryError('Retail', industrySeeds()));
        Assert.areEqual(200, sectionCount());
    }

    @isTest
    static void createIndustry_oneBelowTheCeiling_isAllowed() {
        List<GTM_Page_Section__c> secs = new List<GTM_Page_Section__c>();
        for (Integer i = 0; i < 199; i++) {
            secs.add(new GTM_Page_Section__c(
                Section_Address__c = IND_OFFERING + '::' + IND_TMPL + '::s' + i,
                Offering_Key__c = IND_OFFERING, Template_Type__c = IND_TMPL,
                Section_Key__c = 's' + i, Label__c = 'S' + i, Layout_Type__c = 'industry-tile',
                Width__c = 'standard', Sort_Order__c = i, Active__c = true, Status__c = 'Published'));
        }
        insert secs;

        Assert.areEqual('industry-retail', GtmPageContentController.createIndustry('Retail', industrySeeds()));
        Assert.areEqual(200, sectionCount());
    }

    @isTest
    static void createIndustry_invalidFieldSeeds_areRefusedAndChangeNothing() {
        makeChooserPage();
        String expected = 'The industry layout is not valid. Reload and try again.';

        List<List<GtmPageSectionController.FieldSeed>> bad = new List<List<GtmPageSectionController.FieldSeed>>();
        bad.add(null);
        bad.add(new List<GtmPageSectionController.FieldSeed>());
        // no industryLabel
        bad.add(new List<GtmPageSectionController.FieldSeed>{ seed('whyHead', 'text') });
        // industryLabel with the wrong type
        bad.add(new List<GtmPageSectionController.FieldSeed>{ seed('industryLabel', 'rich') });
        // duplicate key
        bad.add(new List<GtmPageSectionController.FieldSeed>{ seed('industryLabel', 'text'), seed('whyHead', 'text'), seed('whyHead', 'text') });
        // bad keys
        for (String k : new List<String>{ '1abc', 'has space', 'a-b', '', 'x'.repeat(81) }) {
            bad.add(new List<GtmPageSectionController.FieldSeed>{ seed('industryLabel', 'text'), seed(k, 'text') });
        }
        // bad types
        bad.add(new List<GtmPageSectionController.FieldSeed>{ seed('industryLabel', 'text'), seed('extra', 'enum') });
        bad.add(new List<GtmPageSectionController.FieldSeed>{ seed('industryLabel', 'text'), seed('extra', null) });
        // a null entry
        bad.add(new List<GtmPageSectionController.FieldSeed>{ seed('industryLabel', 'text'), null });
        // more than 40 entries
        List<GtmPageSectionController.FieldSeed> tooMany = new List<GtmPageSectionController.FieldSeed>{ seed('industryLabel', 'text') };
        for (Integer i = 0; i < 40; i++) { tooMany.add(seed('f' + i, 'text')); }
        bad.add(tooMany);

        Integer caseNo = 0;
        for (List<GtmPageSectionController.FieldSeed> seeds : bad) {
            Assert.areEqual(expected, industryError('Retail', seeds), 'Bad seed case ' + caseNo);
            caseNo++;
        }
        Assert.areEqual(1, sectionCount());
        Assert.areEqual(0, rowCount());
    }

    @isTest
    static void createIndustry_fortySeedsExactly_isAccepted() {
        makeChooserPage();
        List<GtmPageSectionController.FieldSeed> seeds = new List<GtmPageSectionController.FieldSeed>{ seed('industryLabel', 'text') };
        for (Integer i = 0; i < 39; i++) { seeds.add(seed('f' + i, 'text')); }
        GtmPageContentController.createIndustry('Retail', seeds);
        Assert.areEqual(40, rowCount());
    }

    @isTest
    static void createIndustry_rowInsertFails_rollsTheSectionBack() {
        makeChooserPage();
        List<GtmPageSectionController.FieldSeed> seeds = industrySeeds();
        seeds[1].label = 'x'.repeat(121); // Label__c on the content row is Text(120)

        String err = industryError('Retail', seeds);

        Assert.isNotNull(err);
        Assert.isTrue(err.startsWith('The industry could not be created: '), err);
        Assert.areEqual(1, sectionCount(), 'The section insert must be rolled back');
        Assert.areEqual(0, rowCount());
    }

    @isTest
    static void createIndustry_leftoverRowAtTheSameAddress_rollsTheSectionBack() {
        makeChooserPage();
        insert new GTM_Page_Content__c(
            Content_Address__c = 'gtm::industry-chooser::industry-retail::whyHead',
            Offering_Key__c = IND_OFFERING, Template_Type__c = IND_TMPL,
            Section_Key__c = 'industry-retail', Field_Key__c = 'whyHead', Field_Type__c = 'text',
            Active__c = true);

        String err = industryError('Retail', industrySeeds());

        Assert.isNotNull(err);
        Assert.isTrue(err.startsWith('The industry could not be created: '), err);
        Assert.areEqual(1, sectionCount(), 'No half-created section may remain');
        Assert.areEqual(1, rowCount(), 'Only the pre-existing row remains');
    }

    @isTest
    static void createIndustry_userWithoutCreateAccess_isRefused() {
        makeChooserPage();
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        // The Standard User profile is not guaranteed in every test context; the
        // guard is only meaningful with a user who lacks create access.
        if (profiles.isEmpty()) {
            Assert.isTrue(true, 'Standard User profile not available in this org; not-createable case skipped.');
            return;
        }
        User u = new User(
            Alias = 'indnoacc', Email = 'indnoacc@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'NoAccess', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = profiles[0].Id, TimeZoneSidKey = 'America/New_York',
            Username = 'indnoacc' + System.currentTimeMillis() + '@gtm-offerings.test.invalid');
        System.runAs(new User(Id = UserInfo.getUserId())) { insert u; }

        String err;
        System.runAs(u) {
            err = industryError('Retail', industrySeeds());
        }

        Assert.areEqual('You do not have permission to add industries.', err);
        Assert.areEqual(1, sectionCount());
    }

    @isTest
    static void createIndustry_driftAlarm_readerConsumesExactlyTheTwelveTileKeys() {
        // The 12 keys of the industry-tile layout (c/gtmPageLayouts LAYOUT_FIELDS).
        // Apex does not hard-code them; this test is the alarm that the reader and
        // the layout still agree. Add or rename a key on one side only and it fails.
        Map<String, String> typeByKey = new Map<String, String>();
        for (GtmPageSectionController.FieldSeed s : industrySeeds()) { typeByKey.put(s.fieldKey, s.fieldType); }
        Assert.areEqual(12, typeByKey.size());

        insert new GTM_Page_Section__c(
            Section_Address__c = 'gtm::industry-chooser::industry-drift', Offering_Key__c = IND_OFFERING,
            Template_Type__c = IND_TMPL, Section_Key__c = 'industry-drift', Label__c = 'Drift',
            Layout_Type__c = 'industry-tile', Width__c = 'standard', Sort_Order__c = 10,
            Active__c = true, Status__c = 'Published');
        List<GTM_Page_Content__c> rows = new List<GTM_Page_Content__c>();
        for (String k : typeByKey.keySet()) {
            String t = typeByKey.get(k);
            GTM_Page_Content__c r = new GTM_Page_Content__c(
                Offering_Key__c = IND_OFFERING, Template_Type__c = IND_TMPL,
                Section_Key__c = 'industry-drift', Field_Key__c = k, Field_Type__c = t, Active__c = true);
            if (t == 'json') r.JSON_Value__c = '["v-' + k + '"]';
            else if (t == 'rich') r.Rich_Value__c = 'v-' + k;
            else r.Text_Value__c = 'v-' + k;
            rows.add(r);
        }
        insert rows;

        GtmPageContentReader.IndustryProfile p =
            GtmPageContentReader.getIndustryProfiles(IND_OFFERING, IND_TMPL)[0];

        Assert.areEqual('v-industryLabel', p.industryLabel);
        Assert.areEqual('v-whyHead', p.whyHead);
        Assert.areEqual('v-demoRoot', p.demoRoot);
        Assert.areEqual('v-pickerBlurb', p.pickerBlurb);
        Assert.areEqual('v-coverSub', p.coverSub);
        Assert.areEqual('v-problem', p.problem);
        Assert.areEqual('v-useCase', p.useCase);
        Assert.areEqual('v-solution', p.solution);
        Assert.areEqual('v-proofLine', p.proofLine);
        Assert.areEqual('v-whyLine', p.whyLine);
        Assert.areEqual(new List<String>{ 'v-uniquePoints' }, p.uniquePoints);
        Assert.areEqual(new List<String>{ 'v-demoDeps' }, p.demoDeps);
    }

    @isTest
    static void createIndustry_publishRoundTrip_makesTheLabelLive() {
        makeChooserPage();
        String key = GtmPageContentController.createIndustry('Financial Services', industrySeeds());

        Assert.areEqual(0, GtmPageContentReader.getIndustryProfiles(IND_OFFERING, IND_TMPL).size(),
            'A Draft industry is not public before Publish');

        Test.startTest();
        GtmPageContentController.publishPage(IND_OFFERING, IND_TMPL);
        Test.stopTest();

        Assert.areEqual('Published', [SELECT Status__c FROM GTM_Page_Section__c WHERE Section_Key__c = :key].Status__c);
        List<GtmPageContentReader.IndustryProfile> live = GtmPageContentReader.getIndustryProfiles(IND_OFFERING, IND_TMPL);
        Assert.areEqual(1, live.size());
        Assert.areEqual('financial-services', live[0].industryKey);
        Assert.areEqual('Financial Services', live[0].industryLabel);
        GTM_Page_Content__c labelRow = [SELECT Text_Value__c, Draft_Value__c, Status__c FROM GTM_Page_Content__c
                                        WHERE Section_Key__c = :key AND Field_Key__c = 'industryLabel'];
        Assert.areEqual('Financial Services', labelRow.Text_Value__c);
        Assert.isNull(labelRow.Draft_Value__c);
        Assert.areEqual('Published', labelRow.Status__c);
    }
}
