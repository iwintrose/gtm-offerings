@IsTest
private class GtmAgentDraftSectionVariantTest {

    private static final String OFFERING = 'migration-accelerator';
    private static final String TMPL     = 'story';

    private static GTM_Page_Content__c headlineRecord;

    private static void makeVariantSection() {
        insert new GTM_Page_Section__c(
            Section_Address__c = OFFERING + '::' + TMPL + '::problem--healthcare',
            Offering_Key__c    = OFFERING,
            Template_Type__c   = TMPL,
            Section_Key__c     = 'problem--healthcare',
            Base_Section_Key__c = 'problem',
            Industry_Key__c     = 'healthcare',
            Label__c             = 'Problem (Healthcare)',
            Layout_Type__c       = 'hero',
            Width__c              = 'standard',
            Sort_Order__c         = 100,
            Active__c             = true,
            Status__c             = 'Published'
        );
        headlineRecord = new GTM_Page_Content__c(
            Content_Address__c = OFFERING + '::' + TMPL + '::problem--healthcare::headline',
            Offering_Key__c  = OFFERING, Template_Type__c = TMPL,
            Section_Key__c   = 'problem--healthcare', Field_Key__c = 'headline',
            Field_Type__c    = 'text', Text_Value__c = 'Original headline',
            Industry_Key__c  = 'healthcare', Active__c = true
        );
        insert headlineRecord;
    }

    private static GtmAgentDraftSectionVariant.Output run(String offeringKey, String templateType,
                                                           String sectionKey, String fieldValuesJson) {
        GtmAgentDraftSectionVariant.Input inp = new GtmAgentDraftSectionVariant.Input();
        inp.offeringKey     = offeringKey;
        inp.templateType    = templateType;
        inp.sectionKey      = sectionKey;
        inp.fieldValuesJson = fieldValuesJson;
        return GtmAgentDraftSectionVariant.execute(new List<GtmAgentDraftSectionVariant.Input>{ inp })[0];
    }

    @IsTest
    static void execute_validProposal_returnsSuccessAndDoesNotWriteContentRow() {
        makeVariantSection();

        Test.startTest();
        GtmAgentDraftSectionVariant.Output out = run(OFFERING, TMPL, 'problem--healthcare',
            JSON.serialize(new Map<String, Object>{ 'headline' => 'AI-proposed headline' }));
        Test.stopTest();

        Assert.areEqual(true, out.success);
        Assert.isTrue(out.appliedJson.containsIgnoreCase('AI-proposed headline'));

        // ── Regression guard: the action never writes GTM_Page_Content__c. ──
        GTM_Page_Content__c reloaded = [
            SELECT Text_Value__c FROM GTM_Page_Content__c WHERE Id = :headlineRecord.Id
        ];
        Assert.areEqual('Original headline', reloaded.Text_Value__c,
            'GtmAgentDraftSectionVariant must never write the record directly -- ' +
            'proposals are returned for the caller to apply through the Draft -> Publish path.');
    }

    @IsTest
    static void execute_unknownFieldKey_isDroppedSilently() {
        makeVariantSection();

        Test.startTest();
        GtmAgentDraftSectionVariant.Output out = run(OFFERING, TMPL, 'problem--healthcare',
            JSON.serialize(new Map<String, Object>{
                'headline'   => 'Kept',
                'notAField'  => 'Dropped'
            }));
        Test.stopTest();

        Assert.areEqual(true, out.success);
        Assert.isTrue(out.appliedJson.containsIgnoreCase('headline'));
        Assert.isFalse(out.appliedJson.containsIgnoreCase('notAField'),
            'An unrecognised fieldKey must be dropped, not passed through.');
    }

    @IsTest
    static void execute_allUnknownKeys_returnsFailure() {
        makeVariantSection();

        Test.startTest();
        GtmAgentDraftSectionVariant.Output out = run(OFFERING, TMPL, 'problem--healthcare',
            JSON.serialize(new Map<String, Object>{ 'bogus' => 'x' }));
        Test.stopTest();

        Assert.areEqual(false, out.success);
        Assert.isTrue(out.errorMessage.containsIgnoreCase('No recognised'));
    }

    @IsTest
    static void execute_notAVariantSection_returnsFailure() {
        insert new GTM_Page_Section__c(
            Section_Address__c = OFFERING + '::' + TMPL + '::problem',
            Offering_Key__c = OFFERING, Template_Type__c = TMPL,
            Section_Key__c = 'problem', Label__c = 'Problem', Layout_Type__c = 'hero',
            Width__c = 'standard', Sort_Order__c = 100, Active__c = true, Status__c = 'Published');

        Test.startTest();
        GtmAgentDraftSectionVariant.Output out = run(OFFERING, TMPL, 'problem',
            JSON.serialize(new Map<String, Object>{ 'headline' => 'x' }));
        Test.stopTest();

        Assert.areEqual(false, out.success);
        Assert.isTrue(out.errorMessage.containsIgnoreCase('not a draftable industry variant'));
    }

    @IsTest
    static void execute_malformedJson_returnsFailure() {
        makeVariantSection();

        Test.startTest();
        GtmAgentDraftSectionVariant.Output out = run(OFFERING, TMPL, 'problem--healthcare', 'not json');
        Test.stopTest();

        Assert.areEqual(false, out.success);
        Assert.isTrue(out.errorMessage.containsIgnoreCase('not valid JSON'));
    }

    @IsTest
    static void execute_fieldTooLong_returnsFailure() {
        makeVariantSection();
        String tooLong = ''.rightPad(8001, 'x');

        Test.startTest();
        GtmAgentDraftSectionVariant.Output out = run(OFFERING, TMPL, 'problem--healthcare',
            JSON.serialize(new Map<String, Object>{ 'headline' => tooLong }));
        Test.stopTest();

        Assert.areEqual(false, out.success);
        Assert.isTrue(out.errorMessage.containsIgnoreCase('exceeds'));
    }

    @IsTest
    static void execute_blankRequiredInputs_returnsFailure() {
        Test.startTest();
        GtmAgentDraftSectionVariant.Output out = run('', '', '', '');
        Test.stopTest();

        Assert.areEqual(false, out.success);
        Assert.isTrue(out.errorMessage.containsIgnoreCase('required'));
    }
}
