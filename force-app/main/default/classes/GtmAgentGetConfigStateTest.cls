@IsTest
private class GtmAgentGetConfigStateTest {

    private static GTM_Page_Content__c industrySection(String key, String label) {
        return new GTM_Page_Content__c(
            Offering_Key__c  = 'gtm',
            Template_Type__c = 'industry-chooser',
            Section_Key__c   = 'industry-' + key,
            Field_Key__c     = 'industryLabel',
            Field_Type__c    = 'text',
            Text_Value__c    = label,
            Active__c        = true
        );
    }

    @IsTest
    static void execute_blankConfigId_returnsDefaultsAndFrameworkIndustries() {
        insert new List<GTM_Page_Content__c>{
            industrySection('fintech', 'Financial Services'),
            industrySection('medtech', 'MedTech')
        };

        GtmAgentGetConfigState.Input inp = new GtmAgentGetConfigState.Input();
        inp.configId = '';

        Test.startTest();
        GtmAgentGetConfigState.Output out =
            GtmAgentGetConfigState.execute(new List<GtmAgentGetConfigState.Input>{ inp })[0];
        Test.stopTest();

        Assert.areEqual('', out.company, 'No saved config -- company defaults to blank.');
        Assert.areEqual(2, out.availableIndustries.size(),
            'availableIndustries must come from the framework industry-chooser taxonomy, ' +
            'not any one offering\'s story content.');
        Assert.isTrue(out.availableIndustries.contains('fintech'));
        Assert.isTrue(out.availableIndustries.contains('medtech'));
    }

    @IsTest
    static void execute_savedConfig_readsCompanyFromPayload() {
        insert industrySection('fintech', 'Financial Services');

        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c       = 'migration-accelerator',
            Company__c        = 'Acme Co',
            Industry__c       = 'fintech',
            Config_Payload__c = JSON.serialize(new Map<String, Object>{
                'company'      => 'Acme Co',
                'industry'     => 'fintech',
                'accent'       => '#112233',
                'objectsCount' => 4128,
                'depsCount'    => 9640,
                'healthScore'  => 62,
                'note'         => 'Test note'
            })
        );
        insert cfg;

        GtmAgentGetConfigState.Input inp = new GtmAgentGetConfigState.Input();
        inp.configId = cfg.Id;

        Test.startTest();
        GtmAgentGetConfigState.Output out =
            GtmAgentGetConfigState.execute(new List<GtmAgentGetConfigState.Input>{ inp })[0];
        Test.stopTest();

        Assert.areEqual('Acme Co', out.company);
        Assert.areEqual('fintech', out.industry);
        Assert.areEqual(4128, out.objectsCount);
        Assert.isTrue(out.availableIndustries.contains('fintech'),
            'The industry taxonomy must still resolve from the framework, ' +
            'independent of which offering the saved configuration belongs to.');
    }

    @IsTest
    static void execute_noIndustryChooserContent_returnsEmptyIndustryList() {
        GtmAgentGetConfigState.Input inp = new GtmAgentGetConfigState.Input();
        inp.configId = '';

        Test.startTest();
        GtmAgentGetConfigState.Output out =
            GtmAgentGetConfigState.execute(new List<GtmAgentGetConfigState.Input>{ inp })[0];
        Test.stopTest();

        Assert.areEqual(0, out.availableIndustries.size(),
            'With no framework industry-chooser content seeded, the list is empty rather than erroring.');
    }
}
