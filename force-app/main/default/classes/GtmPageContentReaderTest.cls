@IsTest
private class GtmPageContentReaderTest {

    private static final String OFFERING = 'ma-migrator';
    private static final String TMPL = 'story';

    private static GTM_Page_Content__c row(
        String section, String field, String type,
        String text, String rich, String json, String industry, Integer sortOrder
    ) {
        return new GTM_Page_Content__c(
            Offering_Key__c  = OFFERING,
            Template_Type__c = TMPL,
            Section_Key__c   = section,
            Field_Key__c     = field,
            Field_Type__c    = type,
            Text_Value__c    = text,
            Rich_Value__c    = rich,
            JSON_Value__c    = json,
            Industry_Key__c  = industry,
            Active__c        = true,
            Sort_Order__c    = sortOrder
        );
    }

    @IsTest
    static void resolvesEachFieldTypeFromItsOwnColumn() {
        insert new List<GTM_Page_Content__c>{
            row('hero', 'eyebrow',  'text', 'Eyebrow copy', null, null, null, 1),
            row('hero', 'headline', 'rich', null, '<strong>Rich</strong>', null, null, 2),
            row('problem', 'chips', 'json', null, null, '["a","b"]', null, 3)
        };

        Test.startTest();
        Map<String, String> result = GtmPageContentReader.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals('Eyebrow copy', result.get('hero::eyebrow'), 'text reads Text_Value__c');
        System.assertEquals('<strong>Rich</strong>', result.get('hero::headline'), 'rich reads Rich_Value__c');
        System.assertEquals('["a","b"]', result.get('problem::chips'), 'json reads JSON_Value__c');
    }

    @IsTest
    static void industryRowWinsOverOfferingDefault() {
        insert new List<GTM_Page_Content__c>{
            row('hero', 'headline', 'text', 'Generic', null, null, null, 1),
            row('hero', 'headline', 'text', 'Retail', null, null, 'retail', 2)
        };

        Test.startTest();
        Map<String, String> result = GtmPageContentReader.getPageContent(OFFERING, TMPL, 'retail');
        Test.stopTest();

        System.assertEquals('Retail', result.get('hero::headline'), 'Industry-scoped row should win');
    }

    @IsTest
    static void otherIndustryRowsAreExcluded() {
        insert new List<GTM_Page_Content__c>{
            row('hero', 'headline', 'text', 'Generic', null, null, null, 1),
            row('hero', 'subhead',  'text', 'Finance only', null, null, 'finance', 2)
        };

        Test.startTest();
        Map<String, String> result = GtmPageContentReader.getPageContent(OFFERING, TMPL, 'retail');
        Test.stopTest();

        System.assertEquals('Generic', result.get('hero::headline'), 'Offering default still resolves');
        System.assert(!result.containsKey('hero::subhead'), 'A different industry\'s row must not leak in');
    }

    @IsTest
    static void inactiveRowsExcluded() {
        GTM_Page_Content__c rec = row('hero', 'headline', 'text', 'Hidden', null, null, null, 1);
        rec.Active__c = false;
        insert rec;

        Test.startTest();
        Map<String, String> result = GtmPageContentReader.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assert(!result.containsKey('hero::headline'), 'Inactive rows must not resolve');
    }

    @IsTest
    static void wrongTemplateExcluded() {
        GTM_Page_Content__c other = row('hero', 'headline', 'text', 'Configurator copy', null, null, null, 1);
        other.Template_Type__c = 'configurator';
        insert other;

        Test.startTest();
        Map<String, String> result = GtmPageContentReader.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assert(!result.containsKey('hero::headline'), 'Rows from another template must not resolve');
    }

    @IsTest
    static void blankArgumentsReturnEmptyMap() {
        Test.startTest();
        Map<String, String> noOffering = GtmPageContentReader.getPageContent('', TMPL, null);
        Map<String, String> noTemplate = GtmPageContentReader.getPageContent(OFFERING, null, null);
        Test.stopTest();

        System.assert(noOffering.isEmpty(), 'Blank offering key returns an empty map');
        System.assert(noTemplate.isEmpty(), 'Blank template type returns an empty map');
    }

    // ─── getPageLayout ────────────────────────────────────────────────────────

    private static GTM_Page_Section__c section(String key, String layout, Integer sortOrder) {
        return new GTM_Page_Section__c(
            Section_Address__c = OFFERING + '::' + TMPL + '::' + key,
            Offering_Key__c    = OFFERING,
            Template_Type__c   = TMPL,
            Section_Key__c     = key,
            Label__c           = key,
            Layout_Type__c     = layout,
            Width__c           = 'standard',
            Sort_Order__c      = sortOrder,
            Active__c          = true
        );
    }

    @IsTest
    static void layoutReturnsSectionsInSortOrder() {
        insert new List<GTM_Page_Section__c>{
            section('closing', 'closing', 30),
            section('hero', 'hero', 10),
            section('faq', 'faq', 20)
        };

        Test.startTest();
        GtmPageContentReader.PageLayout layout =
            GtmPageContentReader.getPageLayout(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals(3, layout.sections.size(), 'All active sections return');
        System.assertEquals('hero', layout.sections[0].sectionKey, 'Lowest Sort_Order__c first');
        System.assertEquals('faq', layout.sections[1].sectionKey, 'Then the next');
        System.assertEquals('closing', layout.sections[2].sectionKey, 'Highest last');
    }

    @IsTest
    static void reorderingSortOrderReordersThePage() {
        // The behaviour the Rearrange control depends on: rewriting Sort_Order__c
        // must change the order the renderer receives, with no code change.
        List<GTM_Page_Section__c> secs = new List<GTM_Page_Section__c>{
            section('hero', 'hero', 10),
            section('faq', 'faq', 20)
        };
        insert secs;

        secs[0].Sort_Order__c = 20;
        secs[1].Sort_Order__c = 10;
        update secs;

        Test.startTest();
        GtmPageContentReader.PageLayout layout =
            GtmPageContentReader.getPageLayout(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals('faq', layout.sections[0].sectionKey, 'FAQ moved above the hero');
        System.assertEquals('hero', layout.sections[1].sectionKey, 'Hero moved below the FAQ');
    }

    @IsTest
    static void inactiveSectionIsRemovedFromThePage() {
        GTM_Page_Section__c hidden = section('faq', 'faq', 20);
        hidden.Active__c = false;
        insert new List<GTM_Page_Section__c>{ section('hero', 'hero', 10), hidden };

        Test.startTest();
        GtmPageContentReader.PageLayout layout =
            GtmPageContentReader.getPageLayout(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals(1, layout.sections.size(), 'Inactive sections do not render');
        System.assertEquals('hero', layout.sections[0].sectionKey, 'Only the active one remains');
    }

    @IsTest
    static void layoutCarriesContentAlongsideStructure() {
        insert section('hero', 'hero', 10);
        insert row('hero', 'eyebrow', 'text', 'Eyebrow copy', null, null, null, 1);

        Test.startTest();
        GtmPageContentReader.PageLayout layout =
            GtmPageContentReader.getPageLayout(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals(1, layout.sections.size(), 'Structure returns');
        System.assertEquals('Eyebrow copy', layout.content.get('hero::eyebrow'),
            'Content returns in the same call, so the page never paints a section before its content');
    }

    @IsTest
    static void layoutForAnotherOfferingIsExcluded() {
        GTM_Page_Section__c other = section('hero', 'hero', 10);
        other.Offering_Key__c = 'some-other-offering';
        other.Section_Address__c = 'some-other-offering::' + TMPL + '::hero';
        insert other;

        Test.startTest();
        GtmPageContentReader.PageLayout layout =
            GtmPageContentReader.getPageLayout(OFFERING, TMPL, null);
        Test.stopTest();

        System.assert(layout.sections.isEmpty(), 'Another offering\'s sections must not leak in');
    }
}
