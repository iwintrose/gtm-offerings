@IsTest
private class GtmAgentGetSectionContentTest {

    private static final String OFFERING = 'migration-accelerator';
    private static final String TMPL     = 'story';

    private static void makeVariantSection() {
        insert new GTM_Page_Section__c(
            Section_Address__c = OFFERING + '::' + TMPL + '::problem--healthcare',
            Offering_Key__c    = OFFERING,
            Template_Type__c   = TMPL,
            Section_Key__c     = 'problem--healthcare',
            Base_Section_Key__c = 'problem',
            Industry_Key__c     = 'healthcare',
            Label__c            = 'Problem (Healthcare)',
            Layout_Type__c      = 'hero',
            Width__c            = 'standard',
            Sort_Order__c       = 100,
            Active__c           = true,
            Status__c           = 'Published'
        );
        insert new List<GTM_Page_Content__c>{
            new GTM_Page_Content__c(
                Content_Address__c = OFFERING + '::' + TMPL + '::problem--healthcare::headline',
                Offering_Key__c  = OFFERING, Template_Type__c = TMPL,
                Section_Key__c   = 'problem--healthcare', Field_Key__c = 'headline',
                Field_Type__c    = 'text', Text_Value__c = 'Base headline',
                Industry_Key__c  = 'healthcare', Active__c = true
            ),
            new GTM_Page_Content__c(
                Content_Address__c = OFFERING + '::' + TMPL + '::problem--healthcare::body',
                Offering_Key__c  = OFFERING, Template_Type__c = TMPL,
                Section_Key__c   = 'problem--healthcare', Field_Key__c = 'body',
                Field_Type__c    = 'rich', Rich_Value__c = '<p>Base body</p>',
                Industry_Key__c  = 'healthcare', Active__c = true
            ),
            // A json field is present but must NOT come back (out of scope, §5/§8).
            new GTM_Page_Content__c(
                Content_Address__c = OFFERING + '::' + TMPL + '::problem--healthcare::points',
                Offering_Key__c  = OFFERING, Template_Type__c = TMPL,
                Section_Key__c   = 'problem--healthcare', Field_Key__c = 'points',
                Field_Type__c    = 'json', JSON_Value__c = '["a","b"]',
                Industry_Key__c  = 'healthcare', Active__c = true
            )
        };
    }

    private static void makeIndustryBrief() {
        insert new GTM_Page_Content__c(
            Content_Address__c = 'gtm::industry-chooser::industry-healthcare::industryLabel',
            Offering_Key__c  = 'gtm', Template_Type__c = 'industry-chooser',
            Section_Key__c   = 'industry-healthcare', Field_Key__c = 'industryLabel',
            Field_Type__c    = 'text', Text_Value__c = 'Healthcare',
            Active__c        = true
        );
        insert new GTM_Page_Section__c(
            Section_Address__c = 'gtm::industry-chooser::industry-healthcare',
            Offering_Key__c = 'gtm', Template_Type__c = 'industry-chooser',
            Section_Key__c = 'industry-healthcare', Label__c = 'Healthcare',
            Layout_Type__c = 'industry-tile', Width__c = 'standard',
            Sort_Order__c = 10, Active__c = true, Status__c = 'Published');
    }

    private static GtmAgentGetSectionContent.Output run(String offeringKey, String templateType, String sectionKey) {
        GtmAgentGetSectionContent.Input inp = new GtmAgentGetSectionContent.Input();
        inp.offeringKey  = offeringKey;
        inp.templateType = templateType;
        inp.sectionKey   = sectionKey;
        return GtmAgentGetSectionContent.execute(new List<GtmAgentGetSectionContent.Input>{ inp })[0];
    }

    @IsTest
    static void execute_variantSection_returnsTextAndRichFieldsOnly() {
        makeVariantSection();
        makeIndustryBrief();

        Test.startTest();
        GtmAgentGetSectionContent.Output out = run(OFFERING, TMPL, 'problem--healthcare');
        Test.stopTest();

        Assert.areEqual('Problem (Healthcare)', out.sectionLabel);
        Assert.areEqual('healthcare', out.industryKey);
        Assert.areEqual('problem', out.baseSectionKey);
        Assert.areEqual(2, out.fields.size(),
            'Only the text/rich fields should come back -- the json field must be excluded.');
        Set<String> keys = new Set<String>();
        for (GtmAgentGetSectionContent.FieldSnapshot fs : out.fields) keys.add(fs.fieldKey);
        Assert.isTrue(keys.contains('headline'));
        Assert.isTrue(keys.contains('body'));
        Assert.isFalse(keys.contains('points'), 'json-typed fields are out of scope for Track A.');
        Assert.isTrue(out.industryBriefJson.containsIgnoreCase('Healthcare'),
            'The industry brief should be resolved from the already-loaded industry-chooser taxonomy.');
    }

    @IsTest
    static void execute_ordinarySection_returnsBlankFields() {
        // A non-variant section (no Industry_Key__c) must never be draftable
        // through this pathway, even if a model supplies its key.
        insert new GTM_Page_Section__c(
            Section_Address__c = OFFERING + '::' + TMPL + '::problem',
            Offering_Key__c = OFFERING, Template_Type__c = TMPL,
            Section_Key__c = 'problem', Label__c = 'Problem', Layout_Type__c = 'hero',
            Width__c = 'standard', Sort_Order__c = 100, Active__c = true, Status__c = 'Published');

        Test.startTest();
        GtmAgentGetSectionContent.Output out = run(OFFERING, TMPL, 'problem');
        Test.stopTest();

        Assert.areEqual(0, out.fields.size(),
            'An ordinary (non-variant) section must return no fields through this action.');
        Assert.areEqual('', out.industryKey);
    }

    @IsTest
    static void execute_missingSection_returnsBlankOutputNotException() {
        Test.startTest();
        GtmAgentGetSectionContent.Output out = run(OFFERING, TMPL, 'does-not-exist');
        Test.stopTest();

        Assert.areEqual('', out.sectionLabel);
        Assert.areEqual(0, out.fields.size());
    }

    @IsTest
    static void execute_blankInputs_returnsBlankOutput() {
        Test.startTest();
        GtmAgentGetSectionContent.Output out = run('', '', '');
        Test.stopTest();

        Assert.areEqual('', out.sectionLabel);
        Assert.areEqual(0, out.fields.size());
    }
}
