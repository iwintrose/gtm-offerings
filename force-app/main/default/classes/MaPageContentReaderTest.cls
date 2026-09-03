@IsTest
private class MaPageContentReaderTest {

    private static final String OFFERING = 'ma-migrator';
    private static final String TMPL = 'story';

    private static MA_Page_Content__c row(
        String section, String field, String type,
        String text, String rich, String json, String industry, Integer sortOrder
    ) {
        return new MA_Page_Content__c(
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
        insert new List<MA_Page_Content__c>{
            row('hero', 'eyebrow',  'text', 'Eyebrow copy', null, null, null, 1),
            row('hero', 'headline', 'rich', null, '<strong>Rich</strong>', null, null, 2),
            row('problem', 'chips', 'json', null, null, '["a","b"]', null, 3)
        };

        Test.startTest();
        Map<String, String> result = MaPageContentReader.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assertEquals('Eyebrow copy', result.get('hero::eyebrow'), 'text reads Text_Value__c');
        System.assertEquals('<strong>Rich</strong>', result.get('hero::headline'), 'rich reads Rich_Value__c');
        System.assertEquals('["a","b"]', result.get('problem::chips'), 'json reads JSON_Value__c');
    }

    @IsTest
    static void industryRowWinsOverOfferingDefault() {
        insert new List<MA_Page_Content__c>{
            row('hero', 'headline', 'text', 'Generic', null, null, null, 1),
            row('hero', 'headline', 'text', 'Retail', null, null, 'retail', 2)
        };

        Test.startTest();
        Map<String, String> result = MaPageContentReader.getPageContent(OFFERING, TMPL, 'retail');
        Test.stopTest();

        System.assertEquals('Retail', result.get('hero::headline'), 'Industry-scoped row should win');
    }

    @IsTest
    static void otherIndustryRowsAreExcluded() {
        insert new List<MA_Page_Content__c>{
            row('hero', 'headline', 'text', 'Generic', null, null, null, 1),
            row('hero', 'subhead',  'text', 'Finance only', null, null, 'finance', 2)
        };

        Test.startTest();
        Map<String, String> result = MaPageContentReader.getPageContent(OFFERING, TMPL, 'retail');
        Test.stopTest();

        System.assertEquals('Generic', result.get('hero::headline'), 'Offering default still resolves');
        System.assert(!result.containsKey('hero::subhead'), 'A different industry\'s row must not leak in');
    }

    @IsTest
    static void inactiveRowsExcluded() {
        MA_Page_Content__c rec = row('hero', 'headline', 'text', 'Hidden', null, null, null, 1);
        rec.Active__c = false;
        insert rec;

        Test.startTest();
        Map<String, String> result = MaPageContentReader.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assert(!result.containsKey('hero::headline'), 'Inactive rows must not resolve');
    }

    @IsTest
    static void wrongTemplateExcluded() {
        MA_Page_Content__c other = row('hero', 'headline', 'text', 'Configurator copy', null, null, null, 1);
        other.Template_Type__c = 'configurator';
        insert other;

        Test.startTest();
        Map<String, String> result = MaPageContentReader.getPageContent(OFFERING, TMPL, null);
        Test.stopTest();

        System.assert(!result.containsKey('hero::headline'), 'Rows from another template must not resolve');
    }

    @IsTest
    static void blankArgumentsReturnEmptyMap() {
        Test.startTest();
        Map<String, String> noOffering = MaPageContentReader.getPageContent('', TMPL, null);
        Map<String, String> noTemplate = MaPageContentReader.getPageContent(OFFERING, null, null);
        Test.stopTest();

        System.assert(noOffering.isEmpty(), 'Blank offering key returns an empty map');
        System.assert(noTemplate.isEmpty(), 'Blank template type returns an empty map');
    }
}
