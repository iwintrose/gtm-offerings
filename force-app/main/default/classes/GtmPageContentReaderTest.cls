@IsTest
private class GtmPageContentReaderTest {

    private static final String OFFERING = 'ma-migrator';
    private static final String TMPL     = 'story';

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static GTM_Page_Content__c contentRow(
        String offering, String tmpl, String section, String field,
        String fieldType, String textVal, String richVal, String jsonVal,
        String industry, Integer sortOrder
    ) {
        return new GTM_Page_Content__c(
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
    }

    private static GTM_Page_Section__c sectionRow(
        String offering, String tmpl, String sectionKey, String label,
        String layoutType, Integer sortOrder, Boolean active, String status
    ) {
        return new GTM_Page_Section__c(
            Offering_Key__c   = offering,
            Template_Type__c  = tmpl,
            Section_Key__c    = sectionKey,
            Section_Address__c = offering + '::' + tmpl + '::' + sectionKey,
            Label__c          = label,
            Layout_Type__c    = layoutType,
            Sort_Order__c     = sortOrder,
            Active__c         = active,
            Status__c         = status
        );
    }

    /** A live (Published, Active) industry section, so its rows are visible to getIndustryProfiles. */
    private static GTM_Page_Section__c liveIndustry(String offering, String tmpl, String sectionKey) {
        return sectionRow(offering, tmpl, sectionKey, sectionKey, 'industry-tile', 10, true, 'Published');
    }

    // ─── getPageContent ───────────────────────────────────────────────────────

    @IsTest
    static void getPageContent_blankOfferingKey_returnsEmptyMap() {
        Map<String, String> result = GtmPageContentReader.getPageContent('', TMPL, null);
        Assert.areEqual(0, result.size(), 'A blank offeringKey should short-circuit to an empty map');
    }

    @IsTest
    static void getPageContent_blankTemplateType_returnsEmptyMap() {
        Map<String, String> result = GtmPageContentReader.getPageContent(OFFERING, '', null);
        Assert.areEqual(0, result.size(), 'A blank templateType should short-circuit to an empty map');
    }

    @IsTest
    static void getPageContent_resolvesEachFieldTypeFromItsOwnColumn() {
        insert new List<GTM_Page_Content__c>{
            contentRow(OFFERING, TMPL, 'hero', 'headline', 'text', 'Hello World', null, null, null, 0),
            contentRow(OFFERING, TMPL, 'hero', 'subhead', 'rich', null, '<b>Bold</b>', null, null, 1),
            contentRow(OFFERING, TMPL, 'problem', 'chips', 'json', null, null, '["a","b"]', null, 2),
            contentRow(OFFERING, TMPL, 'hero', 'icon', 'icontext', null, null, '{"icon":"star"}', null, 3)
        };

        Test.startTest();
        Map<String, String> result = GtmPageContentReader.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        Assert.areEqual('Hello World', result.get('hero::headline'));
        Assert.areEqual('<b>Bold</b>', result.get('hero::subhead'));
        Assert.areEqual('["a","b"]', result.get('problem::chips'));
        Assert.areEqual('{"icon":"star"}', result.get('hero::icon'), 'icontext resolves through the JSON column');
    }

    @IsTest
    static void getPageContent_industryScopedRecordWinsOverDefault() {
        insert new List<GTM_Page_Content__c>{
            contentRow(OFFERING, TMPL, 'hero', 'headline', 'text', 'Default headline', null, null, null, 0),
            contentRow(OFFERING, TMPL, 'hero', 'headline', 'text', 'FS headline', null, null, 'financial-services', 0)
        };

        Test.startTest();
        Map<String, String> result = GtmPageContentReader.getPageContent(OFFERING, TMPL, 'financial-services');
        Test.stopTest();

        Assert.areEqual('FS headline', result.get('hero::headline'), 'The industry-scoped row should win');
    }

    @IsTest
    static void getPageContent_otherIndustrysScopedRowIsExcludedEntirely() {
        // Distinct from the "industry wins over default" case: a row scoped to
        // an industry the caller did NOT ask for must not appear at all, not
        // even as a fallback -- the SOQL filter, not just the precedence rule,
        // is what is under test here.
        insert new List<GTM_Page_Content__c>{
            contentRow(OFFERING, TMPL, 'hero', 'headline', 'text', 'Generic', null, null, null, 0),
            contentRow(OFFERING, TMPL, 'hero', 'subhead', 'text', 'Finance only', null, null, 'finance', 1)
        };

        Test.startTest();
        Map<String, String> result = GtmPageContentReader.getPageContent(OFFERING, TMPL, 'retail');
        Test.stopTest();

        Assert.areEqual('Generic', result.get('hero::headline'), 'The offering default still resolves');
        Assert.isFalse(result.containsKey('hero::subhead'), 'A different industry\'s row must not leak in');
    }

    @IsTest
    static void getPageContent_excludesInactiveAndOtherTemplateRows() {
        GTM_Page_Content__c inactive = contentRow(OFFERING, TMPL, 'hero', 'headline', 'text', 'Should not appear', null, null, null, 0);
        inactive.Active__c = false;
        GTM_Page_Content__c otherTemplate = contentRow(OFFERING, 'configurator', 'hero', 'headline', 'text', 'Wrong template', null, null, null, 0);
        insert new List<GTM_Page_Content__c>{ inactive, otherTemplate };

        Test.startTest();
        Map<String, String> result = GtmPageContentReader.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        Assert.isFalse(result.containsKey('hero::headline'), 'Inactive rows and other-template rows must not appear');
    }

    // ─── getPageLayout ────────────────────────────────────────────────────────

    @IsTest
    static void getPageLayout_blankArgs_returnsEmptyLayout() {
        Test.startTest();
        GtmPageContentReader.PageLayout layout = GtmPageContentReader.getPageLayout('', '', null);
        Test.stopTest();

        Assert.areEqual(0, layout.sections.size());
        Assert.areEqual(0, layout.content.size());
        Assert.areEqual(0, layout.fieldMeta.size());
    }

    @IsTest
    static void getPageLayout_returnsPublishedActiveSectionsInOrder() {
        insert new List<GTM_Page_Section__c>{
            sectionRow(OFFERING, TMPL, 'proof', 'Proof', 'route-proof', 1, true, 'Published'),
            sectionRow(OFFERING, TMPL, 'hero', 'Hero', 'hero', 0, true, 'Published'),
            sectionRow(OFFERING, TMPL, 'draft-beat', 'Draft Beat', 'card-grid', 2, true, 'Draft'),
            sectionRow(OFFERING, TMPL, 'hidden-beat', 'Hidden Beat', 'card-grid', 3, false, 'Published')
        };
        insert contentRow(OFFERING, TMPL, 'hero', 'headline', 'text', 'Hello', null, null, null, 0);

        Test.startTest();
        GtmPageContentReader.PageLayout layout = GtmPageContentReader.getPageLayout(OFFERING, TMPL, null);
        Test.stopTest();

        Assert.areEqual(2, layout.sections.size(), 'Only the published, active sections should be returned');
        Assert.areEqual('hero', layout.sections[0].sectionKey, 'Sections are ordered by Sort_Order__c');
        Assert.areEqual('proof', layout.sections[1].sectionKey);
        Assert.areEqual('Hello', layout.content.get('hero::headline'), 'Content is fetched alongside the sections');
    }

    @IsTest
    static void getPageLayout_carriesSectionPresentationFields() {
        GTM_Page_Section__c sec = sectionRow(OFFERING, TMPL, 'hero', 'Hero', 'hero', 0, true, 'Published');
        sec.Help_Text__c = 'Explains the hero';
        sec.Width__c = 'wide';
        insert sec;

        Test.startTest();
        GtmPageContentReader.PageLayout layout = GtmPageContentReader.getPageLayout(OFFERING, TMPL, null);
        Test.stopTest();

        Assert.areEqual(1, layout.sections.size());
        GtmPageContentReader.SectionDto dto = layout.sections[0];
        Assert.areEqual('Hero', dto.label);
        Assert.areEqual('Explains the hero', dto.helpText);
        Assert.areEqual('hero', dto.layoutType);
        Assert.areEqual('wide', dto.width);
        Assert.areEqual(0, dto.sortOrder);
    }

    @IsTest
    static void getPageLayout_rewritingSortOrderReordersTheReturnedSections() {
        // The behavior the Rearrange control depends on: rewriting Sort_Order__c
        // on existing rows must change the order the renderer receives, with no
        // code change and no re-creating the sections.
        List<GTM_Page_Section__c> secs = new List<GTM_Page_Section__c>{
            sectionRow(OFFERING, TMPL, 'hero', 'Hero', 'hero', 10, true, 'Published'),
            sectionRow(OFFERING, TMPL, 'faq', 'FAQ', 'faq', 20, true, 'Published')
        };
        insert secs;

        secs[0].Sort_Order__c = 20;
        secs[1].Sort_Order__c = 10;
        update secs;

        Test.startTest();
        GtmPageContentReader.PageLayout layout = GtmPageContentReader.getPageLayout(OFFERING, TMPL, null);
        Test.stopTest();

        Assert.areEqual('faq', layout.sections[0].sectionKey, 'FAQ moved above the hero');
        Assert.areEqual('hero', layout.sections[1].sectionKey, 'Hero moved below the FAQ');
    }

    @IsTest
    static void getPageLayout_anotherOfferingsSectionsAreExcluded() {
        GTM_Page_Section__c mine = sectionRow(OFFERING, TMPL, 'hero', 'Hero', 'hero', 0, true, 'Published');
        GTM_Page_Section__c other = sectionRow('some-other-offering', TMPL, 'hero', 'Hero', 'hero', 0, true, 'Published');
        insert new List<GTM_Page_Section__c>{ mine, other };

        Test.startTest();
        GtmPageContentReader.PageLayout layout = GtmPageContentReader.getPageLayout(OFFERING, TMPL, null);
        Test.stopTest();

        Assert.areEqual(1, layout.sections.size(), 'Another offering\'s sections must not leak in');
        Assert.areEqual('hero', layout.sections[0].sectionKey);
    }

    @IsTest
    static void getPageLayout_fieldMetaDedupesIndustryAndDefaultForSameField() {
        insert new List<GTM_Page_Content__c>{
            contentRow(OFFERING, TMPL, 'hero', 'headline', 'text', 'Default', null, null, null, 0),
            contentRow(OFFERING, TMPL, 'hero', 'headline', 'text', 'FS', null, null, 'financial-services', 0)
        };

        Test.startTest();
        GtmPageContentReader.PageLayout layout = GtmPageContentReader.getPageLayout(OFFERING, TMPL, 'financial-services');
        Test.stopTest();

        Integer matches = 0;
        for (GtmPageContentReader.FieldMeta m : layout.fieldMeta) {
            if (m.sectionKey == 'hero' && m.fieldKey == 'headline') matches++;
        }
        Assert.areEqual(1, matches, 'Field metadata should list hero::headline exactly once');
    }

    @IsTest
    static void getPageLayout_fieldMetaCarriesPresentationAttributes() {
        GTM_Page_Content__c rec = contentRow(OFFERING, TMPL, 'hero', 'headline', 'text', 'Hello', null, null, null, 0);
        rec.Label__c = 'Headline';
        rec.Css_Class__c = 'text-xl';
        rec.Html_Id__c = 'hero-headline';
        rec.Inline_Style__c = 'color:red';
        insert rec;

        Test.startTest();
        GtmPageContentReader.PageLayout layout = GtmPageContentReader.getPageLayout(OFFERING, TMPL, null);
        Test.stopTest();

        Assert.areEqual(1, layout.fieldMeta.size());
        GtmPageContentReader.FieldMeta m = layout.fieldMeta[0];
        Assert.areEqual('text', m.fieldType);
        Assert.areEqual('Headline', m.label);
        Assert.areEqual('text-xl', m.cssClass);
        Assert.areEqual('hero-headline', m.htmlId);
        Assert.areEqual('color:red', m.inlineStyle);
    }

    // ─── getOfferingTiles ─────────────────────────────────────────────────────

    @IsTest
    static void getOfferingTiles_returnsPlaceholderWhenNoTileContentExists() {
        // Relies on the deployed GTM_Offering__mdt "Migration Accelerator"
        // record -- custom metadata rows are visible in every Apex test
        // context without needing to be inserted.
        Test.startTest();
        List<GtmPageContentReader.OfferingTile> tiles = GtmPageContentReader.getOfferingTiles();
        Test.stopTest();

        Assert.isFalse(tiles.isEmpty(), 'The deployed offering metadata should always yield a tile');
        GtmPageContentReader.OfferingTile tile = tiles[0];
        Assert.areEqual('migration-accelerator', tile.offeringKey);
        Assert.isFalse(tile.isLive, 'With no tile content rows, the offering is not yet live');
        Assert.isNull(tile.description);
    }

    @IsTest
    static void getOfferingTiles_marksLiveOnceDescriptionIsSet() {
        insert new List<GTM_Page_Content__c>{
            contentRow('migration-accelerator', 'offerings-listing', 'tile', 'mark', 'text', 'M', null, null, null, 0),
            contentRow('migration-accelerator', 'offerings-listing', 'tile', 'name', 'text', 'Migration Accelerator', null, null, null, 1),
            contentRow('migration-accelerator', 'offerings-listing', 'tile', 'description', 'text', 'Move faster between platforms.', null, null, null, 2)
        };

        Test.startTest();
        List<GtmPageContentReader.OfferingTile> tiles = GtmPageContentReader.getOfferingTiles();
        Test.stopTest();

        GtmPageContentReader.OfferingTile tile;
        for (GtmPageContentReader.OfferingTile t : tiles) {
            if (t.offeringKey == 'migration-accelerator') tile = t;
        }
        Assert.isNotNull(tile);
        Assert.areEqual('M', tile.mark);
        Assert.areEqual('Migration Accelerator', tile.name);
        Assert.areEqual('Move faster between platforms.', tile.description);
        Assert.isTrue(tile.isLive, 'A tile with a description should be marked live');
    }

    @IsTest
    static void getOfferingTiles_ignoresRowsForUnknownOfferingKeys() {
        // A stray content row for an offering key with no matching CMDT record
        // must not blow up the map lookup or fabricate a tile.
        insert contentRow('not-a-real-offering', 'offerings-listing', 'tile', 'description', 'text', 'Ghost', null, null, null, 0);

        Test.startTest();
        List<GtmPageContentReader.OfferingTile> tiles = GtmPageContentReader.getOfferingTiles();
        Test.stopTest();

        for (GtmPageContentReader.OfferingTile t : tiles) {
            Assert.areNotEqual('not-a-real-offering', t.offeringKey, 'No tile should be fabricated for an unknown offering key');
        }
    }

    @IsTest
    static void getOfferingTiles_excludesAnOfferingWhoseTileSectionIsDraft() {
        insert new List<GTM_Page_Content__c>{
            contentRow('migration-accelerator', 'offerings-listing', 'tile', 'name', 'text', 'Migration Accelerator', null, null, null, 0),
            contentRow('migration-accelerator', 'offerings-listing', 'tile', 'description', 'text', 'Move faster.', null, null, null, 1)
        };
        insert new GTM_Page_Section__c(
            Section_Address__c = 'migration-accelerator::offerings-listing::tile',
            Offering_Key__c    = 'migration-accelerator',
            Template_Type__c   = 'offerings-listing',
            Section_Key__c     = 'tile',
            Label__c            = 'Offerings page entry',
            Layout_Type__c      = 'offering-tile',
            Sort_Order__c       = 10,
            Active__c           = true,
            Status__c           = 'Published',
            Offering_Status__c  = 'Draft'
        );

        Test.startTest();
        List<GtmPageContentReader.OfferingTile> tiles = GtmPageContentReader.getOfferingTiles();
        Test.stopTest();

        for (GtmPageContentReader.OfferingTile t : tiles) {
            Assert.areNotEqual('migration-accelerator', t.offeringKey,
                'A tile whose section is set to Draft must be excluded from the dashboard listing');
        }
    }

    @IsTest
    static void getOfferingTiles_excludesAnOfferingWhoseTileSectionStatusIsNull() {
        insert new List<GTM_Page_Content__c>{
            contentRow('migration-accelerator', 'offerings-listing', 'tile', 'name', 'text', 'Migration Accelerator', null, null, null, 0),
            contentRow('migration-accelerator', 'offerings-listing', 'tile', 'description', 'text', 'Move faster.', null, null, null, 1)
        };
        GTM_Page_Section__c sec = new GTM_Page_Section__c(
            Section_Address__c = 'migration-accelerator::offerings-listing::tile',
            Offering_Key__c    = 'migration-accelerator',
            Template_Type__c   = 'offerings-listing',
            Section_Key__c     = 'tile',
            Label__c            = 'Offerings page entry',
            Layout_Type__c      = 'offering-tile',
            Sort_Order__c       = 10,
            Active__c           = true,
            Status__c           = 'Published'
            // Offering_Status__c intentionally omitted — null should be treated as Draft
        );
        insert sec;

        Test.startTest();
        List<GtmPageContentReader.OfferingTile> tiles = GtmPageContentReader.getOfferingTiles();
        Test.stopTest();

        for (GtmPageContentReader.OfferingTile t : tiles) {
            Assert.areNotEqual('migration-accelerator', t.offeringKey,
                'A tile whose section has a null Offering_Status__c must be excluded from the dashboard listing (null is treated as Draft)');
        }
    }

    @IsTest
    static void getOfferingTiles_excludesAnArchivedOffering() {
        insert new List<GTM_Page_Content__c>{
            contentRow('migration-accelerator', 'offerings-listing', 'tile', 'name', 'text', 'Migration Accelerator', null, null, null, 0),
            contentRow('migration-accelerator', 'offerings-listing', 'tile', 'description', 'text', 'Move faster.', null, null, null, 1)
        };
        insert new GTM_Page_Section__c(
            Section_Address__c = 'migration-accelerator::offerings-listing::tile',
            Offering_Key__c    = 'migration-accelerator',
            Template_Type__c   = 'offerings-listing',
            Section_Key__c     = 'tile',
            Label__c            = 'Offerings page entry',
            Layout_Type__c      = 'offering-tile',
            Sort_Order__c       = 10,
            Active__c           = true,
            Status__c           = 'Published',
            Archived__c         = true
        );

        Test.startTest();
        List<GtmPageContentReader.OfferingTile> tiles = GtmPageContentReader.getOfferingTiles();
        Test.stopTest();

        for (GtmPageContentReader.OfferingTile t : tiles) {
            Assert.areNotEqual('migration-accelerator', t.offeringKey,
                'An archived offering must be excluded from the dashboard listing');
        }
    }

    @IsTest
    static void getOfferingTiles_stillIncludesAPublishedNonArchivedOfferingWithATileSection() {
        // The additive-gate regression this guards: a normal, live tile
        // section (Published, not archived) must still resolve -- the new
        // gates must not accidentally exclude the common case.
        insert new List<GTM_Page_Content__c>{
            contentRow('migration-accelerator', 'offerings-listing', 'tile', 'name', 'text', 'Migration Accelerator', null, null, null, 0),
            contentRow('migration-accelerator', 'offerings-listing', 'tile', 'description', 'text', 'Move faster.', null, null, null, 1)
        };
        insert new GTM_Page_Section__c(
            Section_Address__c = 'migration-accelerator::offerings-listing::tile',
            Offering_Key__c    = 'migration-accelerator',
            Template_Type__c   = 'offerings-listing',
            Section_Key__c     = 'tile',
            Label__c            = 'Offerings page entry',
            Layout_Type__c      = 'offering-tile',
            Sort_Order__c       = 10,
            Active__c           = true,
            Status__c           = 'Published',
            Offering_Status__c  = 'Published',
            Archived__c         = false
        );

        Test.startTest();
        List<GtmPageContentReader.OfferingTile> tiles = GtmPageContentReader.getOfferingTiles();
        Test.stopTest();

        GtmPageContentReader.OfferingTile tile;
        for (GtmPageContentReader.OfferingTile t : tiles) {
            if (t.offeringKey == 'migration-accelerator') tile = t;
        }
        Assert.isNotNull(tile, 'A published, non-archived offering must still be listed');
        Assert.isTrue(tile.isLive, 'isLive derivation is unaffected by the new gates');
    }

    @IsTest
    static void getOfferingTiles_withNoTileSectionAtAllStillResolvesAsBeforeIsLiveOnly() {
        // No GTM_Page_Section__c row at all for this offering -- the new
        // gates must fail open (never exclude) rather than require a tile
        // section to exist just to be listed. Mirrors
        // getOfferingTiles_marksLiveOnceDescriptionIsSet above, which this
        // duplicates the setup of on purpose to isolate the new gate.
        insert contentRow('migration-accelerator', 'offerings-listing', 'tile', 'description', 'text', 'Move faster.', null, null, null, 0);

        Test.startTest();
        List<GtmPageContentReader.OfferingTile> tiles = GtmPageContentReader.getOfferingTiles();
        Test.stopTest();

        GtmPageContentReader.OfferingTile tile;
        for (GtmPageContentReader.OfferingTile t : tiles) {
            if (t.offeringKey == 'migration-accelerator') tile = t;
        }
        Assert.isNotNull(tile, 'An offering with content but no tile section row must still be listed');
    }

    // ─── getIndustryProfiles ──────────────────────────────────────────────────

    @IsTest
    static void getIndustryProfiles_blankArgs_returnsEmptyList() {
        Test.startTest();
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles('', '');
        Test.stopTest();

        Assert.areEqual(0, profiles.size());
    }

    @IsTest
    static void getIndustryProfiles_buildsProfileFromScalarFieldsAndStripsSectionPrefix() {
        // Reads the passed-in offering/template now (not a hardcoded owner),
        // so the rows are seeded under OFFERING/TMPL -- the same pair the
        // call below passes.
        insert liveIndustry(OFFERING, TMPL, 'industry-financial-services');
        insert new List<GTM_Page_Content__c>{
            contentRow(OFFERING, TMPL, 'industry-financial-services', 'industryLabel', 'text', 'Financial Services', null, null, null, 0),
            contentRow(OFFERING, TMPL, 'industry-financial-services', 'problem', 'text', 'Legacy platforms slow deals', null, null, null, 1),
            contentRow(OFFERING, TMPL, 'industry-financial-services', 'solution', 'text', 'Migrate faster', null, null, null, 2),
            contentRow(OFFERING, TMPL, 'industry-financial-services', 'demoRoot', 'text', 'root-object', null, null, null, 3)
        };

        Test.startTest();
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles(OFFERING, TMPL);
        Test.stopTest();

        Assert.areEqual(1, profiles.size());
        GtmPageContentReader.IndustryProfile p = profiles[0];
        Assert.areEqual('financial-services', p.industryKey, 'The "industry-" prefix should be stripped');
        Assert.areEqual('Financial Services', p.industryLabel);
        Assert.areEqual('Legacy platforms slow deals', p.problem);
        Assert.areEqual('Migrate faster', p.solution);
        Assert.areEqual('root-object', p.demoRoot);
    }

    @IsTest
    static void getIndustryProfiles_parsesJsonListFields() {
        insert liveIndustry(OFFERING, TMPL, 'industry-retail');
        insert new List<GTM_Page_Content__c>{
            contentRow(OFFERING, TMPL, 'industry-retail', 'uniquePoints', 'json', null, null, '["Fast setup","Low cost"]', null, 0),
            contentRow(OFFERING, TMPL, 'industry-retail', 'demoDeps', 'json', null, null, '["dep-a","dep-b"]', null, 1)
        };

        Test.startTest();
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles(OFFERING, TMPL);
        Test.stopTest();

        Assert.areEqual(1, profiles.size());
        GtmPageContentReader.IndustryProfile p = profiles[0];
        Assert.areEqual(2, p.uniquePoints.size());
        Assert.areEqual('Fast setup', p.uniquePoints[0]);
        Assert.areEqual(2, p.demoDeps.size());
        Assert.areEqual('dep-b', p.demoDeps[1]);
    }

    @IsTest
    static void getIndustryProfiles_malformedJsonListField_leavesListEmptyInsteadOfFailing() {
        insert liveIndustry(OFFERING, TMPL, 'industry-retail');
        insert contentRow(OFFERING, TMPL, 'industry-retail', 'uniquePoints', 'json', null, null, 'NOT VALID JSON [', null, 0);

        Test.startTest();
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles(OFFERING, TMPL);
        Test.stopTest();

        Assert.areEqual(1, profiles.size());
        Assert.areEqual(0, profiles[0].uniquePoints.size(), 'A malformed list field should not fail the whole page');
    }

    @IsTest
    static void getIndustryProfiles_ignoresSectionsOutsideTheIndustryNamespace() {
        insert liveIndustry(OFFERING, TMPL, 'hero');
        insert contentRow(OFFERING, TMPL, 'hero', 'headline', 'text', 'Not an industry section', null, null, null, 0);

        Test.startTest();
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles(OFFERING, TMPL);
        Test.stopTest();

        Assert.areEqual(0, profiles.size(), 'Only section keys prefixed industry- should be picked up');
    }

    @IsTest
    static void getIndustryProfiles_readsThePassedOwnerAndTemplateNotAHardcodedOne() {
        // The regression this guards: the method used to ignore its own
        // arguments and always read gtm/industry-chooser. Seed rows under a
        // DIFFERENT offering/template pair (mirroring what c/gtmConfigurator
        // now expects for its own per-offering industry-profile sections) and
        // confirm they resolve, while the framework's own industry-chooser
        // rows for the same industry key do NOT leak into this offering's
        // result.
        insert new List<GTM_Page_Section__c>{
            liveIndustry('ma-migrator', 'configurator', 'industry-fintech'),
            liveIndustry('gtm', 'industry-chooser', 'industry-fintech')
        };
        insert new List<GTM_Page_Content__c>{
            contentRow('ma-migrator', 'configurator', 'industry-fintech', 'problem', 'text', 'Offering-specific problem', null, null, null, 0),
            contentRow('gtm', 'industry-chooser', 'industry-fintech', 'problem', 'text', 'Framework problem', null, null, null, 0)
        };

        Test.startTest();
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles('ma-migrator', 'configurator');
        Test.stopTest();

        Assert.areEqual(1, profiles.size());
        Assert.areEqual('Offering-specific problem', profiles[0].problem,
            'getIndustryProfiles must read the offering/template it was called with, not a hardcoded framework owner');
    }

    @IsTest
    static void getIndustryProfiles_chooseIndustryCallStillReadsTheFrameworkTaxonomy() {
        // c/chooseIndustry always calls with offeringKey='gtm',
        // templateType='industry-chooser' explicitly -- confirms that exact
        // call still resolves the shared industry-tile rows exactly as
        // before, including the industryLabel/pickerBlurb fields that only
        // industry-tile (not industry-profile) models.
        insert liveIndustry('gtm', 'industry-chooser', 'industry-fintech');
        insert new List<GTM_Page_Content__c>{
            contentRow('gtm', 'industry-chooser', 'industry-fintech', 'industryLabel', 'text', 'Financial Services', null, null, null, 0),
            contentRow('gtm', 'industry-chooser', 'industry-fintech', 'pickerBlurb', 'rich', null, '<p>Blurb</p>', null, null, 1)
        };

        Test.startTest();
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles('gtm', 'industry-chooser');
        Test.stopTest();

        Assert.areEqual(1, profiles.size());
        Assert.areEqual('Financial Services', profiles[0].industryLabel);
        Assert.areEqual('<p>Blurb</p>', profiles[0].pickerBlurb);
    }

    // ─── getIndustryProfiles: Published and Active section join ───────────────

    private static void seedIndustryRow(String offering, String tmpl, String sectionKey, String label) {
        insert contentRow(offering, tmpl, sectionKey, 'industryLabel', 'text', label, null, null, null, 0);
    }

    @IsTest
    static void getIndustryProfiles_draftSection_isNotReturned() {
        insert sectionRow('gtm', 'industry-chooser', 'industry-new-one', 'New One', 'industry-tile', 10, true, 'Draft');
        seedIndustryRow('gtm', 'industry-chooser', 'industry-new-one', 'New One');

        Test.startTest();
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles('gtm', 'industry-chooser');
        Test.stopTest();

        Assert.areEqual(0, profiles.size(), 'A Draft industry must not reach the public chooser');
    }

    @IsTest
    static void getIndustryProfiles_hiddenSection_isNotReturned() {
        insert sectionRow('gtm', 'industry-chooser', 'industry-hidden', 'Hidden', 'industry-tile', 10, false, 'Published');
        seedIndustryRow('gtm', 'industry-chooser', 'industry-hidden', 'Hidden');

        Test.startTest();
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles('gtm', 'industry-chooser');
        Test.stopTest();

        Assert.areEqual(0, profiles.size(), 'A hidden (Active false) industry must not reach the public chooser');
    }

    @IsTest
    static void getIndustryProfiles_publishedActiveSection_isReturnedWithItsLabel() {
        insert liveIndustry('gtm', 'industry-chooser', 'industry-retail');
        seedIndustryRow('gtm', 'industry-chooser', 'industry-retail', 'Retail');

        Test.startTest();
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles('gtm', 'industry-chooser');
        Test.stopTest();

        Assert.areEqual(1, profiles.size());
        Assert.areEqual('retail', profiles[0].industryKey);
        Assert.areEqual('Retail', profiles[0].industryLabel);
    }

    @IsTest
    static void getIndustryProfiles_pendingDraftedHide_isStillReturnedUntilPublish() {
        GTM_Page_Section__c sec = liveIndustry('gtm', 'industry-chooser', 'industry-retail');
        sec.Draft_State__c = '{"active":false}';
        insert sec;
        seedIndustryRow('gtm', 'industry-chooser', 'industry-retail', 'Retail');

        Test.startTest();
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles('gtm', 'industry-chooser');
        Test.stopTest();

        Assert.areEqual(1, profiles.size(),
            'A hide that is only drafted must not change the public page before Publish');
    }

    @IsTest
    static void getIndustryProfiles_contentRowsWithNoSection_areNotReturned() {
        seedIndustryRow('gtm', 'industry-chooser', 'industry-orphan', 'Orphan');

        Test.startTest();
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles('gtm', 'industry-chooser');
        Test.stopTest();

        Assert.areEqual(0, profiles.size(), 'Content rows with no live section must not produce a profile');
    }

    @IsTest
    static void getIndustryProfiles_mixOfLiveDraftAndHidden_returnsOnlyTheLiveOne() {
        insert new List<GTM_Page_Section__c>{
            sectionRow('gtm', 'industry-chooser', 'industry-live', 'Live', 'industry-tile', 10, true, 'Published'),
            sectionRow('gtm', 'industry-chooser', 'industry-draft', 'Draft', 'industry-tile', 20, true, 'Draft'),
            sectionRow('gtm', 'industry-chooser', 'industry-off', 'Off', 'industry-tile', 30, false, 'Published')
        };
        seedIndustryRow('gtm', 'industry-chooser', 'industry-live', 'Live');
        seedIndustryRow('gtm', 'industry-chooser', 'industry-draft', 'Draft');
        seedIndustryRow('gtm', 'industry-chooser', 'industry-off', 'Off');

        Test.startTest();
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles('gtm', 'industry-chooser');
        Test.stopTest();

        Assert.areEqual(1, profiles.size());
        Assert.areEqual('live', profiles[0].industryKey);
    }

    // ─── getSiteInfo ──────────────────────────────────────────────────────────

    @IsTest
    static void getSiteInfo_returnsOrgAndLightningDomainUrls() {
        Test.startTest();
        GtmPageContentReader.SiteInfo info = GtmPageContentReader.getSiteInfo();
        Test.stopTest();

        Assert.isNotNull(info.orgUrl, 'The org domain URL should always resolve');
        Assert.isNotNull(info.lightningUrl);
        Assert.isFalse(
            info.lightningUrl.contains('.my.salesforce.com'),
            'The lightning URL should have the my.salesforce.com suffix swapped out'
        );
        Assert.isNotNull(info.sites, 'Sites list should never be null, even if empty');
    }

    // ─── industry variants (issue #industry-variants-core) ────────────────────

    private static GTM_Page_Section__c variantSectionRow(
        String offering, String tmpl, String variantKey, String baseKey,
        String industry, String label, String layoutType, Boolean active, String status
    ) {
        GTM_Page_Section__c sec = sectionRow(offering, tmpl, variantKey, label, layoutType, 10, active, status);
        sec.Base_Section_Key__c = baseKey;
        sec.Industry_Key__c = industry;
        return sec;
    }

    @IsTest
    static void getPageContent_remapsALiveVariantsRowsUnderTheBaseKey() {
        insert new List<GTM_Page_Section__c>{
            sectionRow(OFFERING, TMPL, 'problem', 'Problem', 'hero', 10, true, 'Published'),
            variantSectionRow(OFFERING, TMPL, 'problem--healthcare', 'problem', 'healthcare',
                'Problem (Healthcare)', 'hero', true, 'Published')
        };
        insert new List<GTM_Page_Content__c>{
            contentRow(OFFERING, TMPL, 'problem', 'headline', 'text', 'Generic problem', null, null, null, 10),
            contentRow(OFFERING, TMPL, 'problem--healthcare', 'headline', 'text',
                'Healthcare-specific problem', null, null, 'healthcare', 10)
        };

        Test.startTest();
        Map<String, String> forHealthcare = GtmPageContentReader.getPageContent(OFFERING, TMPL, 'healthcare');
        Map<String, String> forGeneric = GtmPageContentReader.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        Assert.areEqual('Healthcare-specific problem', forHealthcare.get('problem::headline'),
            'The variant content should be remapped under the BASE key, not the variant key');
        Assert.isFalse(forHealthcare.containsKey('problem--healthcare::headline'),
            'The variant key itself should never be exposed to the renderer');
        Assert.areEqual('Generic problem', forGeneric.get('problem::headline'),
            'With no industry selected, the base content is unaffected by the variant');
    }

    @IsTest
    static void getPageContent_ignoresAVariantThatIsNotPublished() {
        insert new List<GTM_Page_Section__c>{
            sectionRow(OFFERING, TMPL, 'problem', 'Problem', 'hero', 10, true, 'Published'),
            variantSectionRow(OFFERING, TMPL, 'problem--healthcare', 'problem', 'healthcare',
                'Problem (Healthcare)', 'hero', true, 'Draft')
        };
        insert new List<GTM_Page_Content__c>{
            contentRow(OFFERING, TMPL, 'problem', 'headline', 'text', 'Generic problem', null, null, null, 10),
            contentRow(OFFERING, TMPL, 'problem--healthcare', 'headline', 'text',
                'Draft healthcare problem', null, null, 'healthcare', 10)
        };

        Test.startTest();
        Map<String, String> result = GtmPageContentReader.getPageContent(OFFERING, TMPL, 'healthcare');
        Test.stopTest();

        Assert.areEqual('Generic problem', result.get('problem::headline'),
            'An unpublished variant must not substitute into the live page');
    }

    @IsTest
    static void getPageLayout_substitutesVariantLabelLayoutWidthButKeepsBaseKeyAndSortOrder() {
        GTM_Page_Section__c base = sectionRow(OFFERING, TMPL, 'problem', 'Problem', 'hero', 10, true, 'Published');
        base.Width__c = 'standard';
        GTM_Page_Section__c variant = variantSectionRow(OFFERING, TMPL, 'problem--healthcare', 'problem',
            'healthcare', 'The Healthcare Problem', 'card-grid', true, 'Published');
        variant.Width__c = 'wide';
        insert new List<GTM_Page_Section__c>{ base, variant };
        insert contentRow(OFFERING, TMPL, 'problem', 'headline', 'text', 'Generic', null, null, null, 10);

        Test.startTest();
        GtmPageContentReader.PageLayout layout = GtmPageContentReader.getPageLayout(OFFERING, TMPL, 'healthcare');
        Test.stopTest();

        Assert.areEqual(1, layout.sections.size(),
            'The variant must not appear as its own entry in the sequence');
        GtmPageContentReader.SectionDto dto = layout.sections[0];
        Assert.areEqual('problem', dto.sectionKey, 'sectionKey stays the BASE key -- ordering is untouched');
        Assert.areEqual(base.Sort_Order__c, dto.sortOrder, 'Sort_Order__c stays the base section\'s');
        Assert.areEqual('The Healthcare Problem', dto.label, 'Label is substituted from the variant');
        Assert.areEqual('card-grid', dto.layoutType, 'Layout type is substituted from the variant');
        Assert.areEqual('wide', dto.width, 'Width is substituted from the variant');
    }

    @IsTest
    static void getPageLayout_fieldMetaAgreesWithContentOnRemappedVariantKeys() {
        insert new List<GTM_Page_Section__c>{
            sectionRow(OFFERING, TMPL, 'problem', 'Problem', 'hero', 10, true, 'Published'),
            variantSectionRow(OFFERING, TMPL, 'problem--healthcare', 'problem', 'healthcare',
                'Problem (Healthcare)', 'hero', true, 'Published')
        };
        insert contentRow(OFFERING, TMPL, 'problem--healthcare', 'onlyOnVariant', 'text',
            'Only in healthcare', null, null, 'healthcare', 10);

        Test.startTest();
        GtmPageContentReader.PageLayout layout = GtmPageContentReader.getPageLayout(OFFERING, TMPL, 'healthcare');
        Test.stopTest();

        // The field must resolve under the base key in BOTH content and
        // fieldMeta, or the renderer -- which matches fieldMeta entries
        // against content's section::field keys to draw fields the layout
        // never declared -- would silently drop it.
        Assert.areEqual('Only in healthcare', layout.content.get('problem::onlyOnVariant'),
            'content is remapped to the base key');
        GtmPageContentReader.FieldMeta meta;
        for (GtmPageContentReader.FieldMeta m : layout.fieldMeta) {
            if (m.fieldKey == 'onlyOnVariant') meta = m;
        }
        Assert.isNotNull(meta, 'The variant-only field should be described in fieldMeta');
        Assert.areEqual('problem', meta.sectionKey, 'fieldMeta is remapped to the base key too');
    }
}
