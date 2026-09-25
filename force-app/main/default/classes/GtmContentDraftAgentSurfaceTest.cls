/**
 * The content-drafting surface's tools, exercised directly through
 * executeTool -- no HTTP callout involved, same approach as
 * GtmReadoutAgentSurfaceTest. Confirms: (1) get_section_content reads what
 * GtmAgentGetSectionContent reads, (2) draft_section_variant proposes into
 * accumulatedChanges['proposedFields'] and does no DML, (3) an unknown
 * section (or one lacking Industry_Key__c) never lets a proposal through.
 */
@IsTest
private class GtmContentDraftAgentSurfaceTest {

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

    private static Map<String, Object> call(GtmContentDraftAgentSurface s, String tool,
                                            Map<String, Object> input, Map<String, Object> changes) {
        return (Map<String, Object>) JSON.deserializeUntyped(s.executeTool(tool, input, changes));
    }

    @IsTest
    static void getSectionContent_returnsFieldsAndBrief() {
        makeVariantSection();
        GtmContentDraftAgentSurface surface =
            new GtmContentDraftAgentSurface(OFFERING, TMPL, 'problem--healthcare');

        Test.startTest();
        Map<String, Object> out = call(surface, 'get_section_content',
            new Map<String, Object>(), new Map<String, Object>());
        Test.stopTest();

        Assert.areEqual('healthcare', out.get('industryKey'));
        List<Object> fields = (List<Object>) out.get('fields');
        Assert.areEqual(1, fields.size());
    }

    @IsTest
    static void draftSectionVariant_validProposal_mergesIntoAccumulatedChangesNoDml() {
        makeVariantSection();
        GtmContentDraftAgentSurface surface =
            new GtmContentDraftAgentSurface(OFFERING, TMPL, 'problem--healthcare');
        Map<String, Object> changes = new Map<String, Object>();

        Test.startTest();
        Map<String, Object> out = call(surface, 'draft_section_variant',
            new Map<String, Object>{
                'field_values_json' => JSON.serialize(new Map<String, Object>{ 'headline' => 'AI copy' })
            }, changes);
        Test.stopTest();

        Assert.areEqual(true, out.get('success'));
        Assert.isTrue(changes.containsKey('proposedFields'),
            'A successful proposal must land in accumulatedChanges[\'proposedFields\'] for the LWC ' +
            'to apply through the existing Draft -> Publish path -- this tool never writes directly.');
        Map<String, Object> proposed = (Map<String, Object>) changes.get('proposedFields');
        Assert.areEqual('AI copy', proposed.get('headline'));

        GTM_Page_Content__c reloaded = [
            SELECT Text_Value__c FROM GTM_Page_Content__c WHERE Id = :headlineRecord.Id
        ];
        Assert.areEqual('Original headline', reloaded.Text_Value__c,
            'REGRESSION GUARD: "Draft with AI" must never auto-publish/auto-write. The proposal ' +
            'stays in accumulatedChanges only; the stored field value is untouched by this call.');
    }

    @IsTest
    static void draftSectionVariant_multipleCalls_accumulateAcrossRounds() {
        makeVariantSection();
        insert new GTM_Page_Content__c(
            Content_Address__c = OFFERING + '::' + TMPL + '::problem--healthcare::body',
            Offering_Key__c  = OFFERING, Template_Type__c = TMPL,
            Section_Key__c   = 'problem--healthcare', Field_Key__c = 'body',
            Field_Type__c    = 'rich', Rich_Value__c = '<p>Original</p>',
            Industry_Key__c  = 'healthcare', Active__c = true
        );
        GtmContentDraftAgentSurface surface =
            new GtmContentDraftAgentSurface(OFFERING, TMPL, 'problem--healthcare');
        Map<String, Object> changes = new Map<String, Object>();

        Test.startTest();
        call(surface, 'draft_section_variant', new Map<String, Object>{
            'field_values_json' => JSON.serialize(new Map<String, Object>{ 'headline' => 'First' })
        }, changes);
        call(surface, 'draft_section_variant', new Map<String, Object>{
            'field_values_json' => JSON.serialize(new Map<String, Object>{ 'body' => '<p>Second</p>' })
        }, changes);
        Test.stopTest();

        Map<String, Object> proposed = (Map<String, Object>) changes.get('proposedFields');
        Assert.areEqual(2, proposed.size(),
            'A second tool call in the same turn must merge into the existing proposal, not replace it.');
        Assert.areEqual('First', proposed.get('headline'));
        Assert.areEqual('<p>Second</p>', proposed.get('body'));
    }

    @IsTest
    static void draftSectionVariant_notAVariantSection_refusesAndAddsNothing() {
        insert new GTM_Page_Section__c(
            Section_Address__c = OFFERING + '::' + TMPL + '::problem',
            Offering_Key__c = OFFERING, Template_Type__c = TMPL,
            Section_Key__c = 'problem', Label__c = 'Problem', Layout_Type__c = 'hero',
            Width__c = 'standard', Sort_Order__c = 100, Active__c = true, Status__c = 'Published');
        GtmContentDraftAgentSurface surface =
            new GtmContentDraftAgentSurface(OFFERING, TMPL, 'problem');
        Map<String, Object> changes = new Map<String, Object>();

        Test.startTest();
        Map<String, Object> out = call(surface, 'draft_section_variant', new Map<String, Object>{
            'field_values_json' => JSON.serialize(new Map<String, Object>{ 'headline' => 'x' })
        }, changes);
        Test.stopTest();

        Assert.areEqual(false, out.get('success'));
        Assert.isFalse(changes.containsKey('proposedFields'));
    }

    @IsTest
    static void unknownTool_returnsError() {
        makeVariantSection();
        GtmContentDraftAgentSurface surface =
            new GtmContentDraftAgentSurface(OFFERING, TMPL, 'problem--healthcare');

        Test.startTest();
        Map<String, Object> out = call(surface, 'not_a_real_tool',
            new Map<String, Object>(), new Map<String, Object>());
        Test.stopTest();

        Assert.isTrue(String.valueOf(out.get('error')).containsIgnoreCase('Unknown tool'));
    }

    @IsTest
    static void toolDefinitions_declaresBothTools() {
        GtmContentDraftAgentSurface surface =
            new GtmContentDraftAgentSurface(OFFERING, TMPL, 'problem--healthcare');
        List<Object> defs = surface.toolDefinitions();
        Assert.areEqual(2, defs.size());
    }

    @IsTest
    static void systemPrompt_neverInstructsAutoSave() {
        GtmContentDraftAgentSurface surface =
            new GtmContentDraftAgentSurface(OFFERING, TMPL, 'problem--healthcare');
        String prompt = surface.systemPrompt('Be concise.');
        Assert.isTrue(prompt.containsIgnoreCase('nothing is saved'),
            'The prompt must tell GUS to state that nothing is saved yet -- the human-in-the-loop guard.');
    }
}
