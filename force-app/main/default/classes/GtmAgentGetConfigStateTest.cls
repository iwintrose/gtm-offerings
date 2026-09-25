@IsTest
private class GtmAgentGetConfigStateTest {

    // The framework's industry-chooser taxonomy: one 'industry-<key>' section
    // per industry under Offering_Key__c = FRAMEWORK_KEY ('gtm') /
    // Template_Type__c = 'industry-chooser', each with its own content rows --
    // the same shape GtmPageContentReaderTest seeds for getIndustryProfiles.
    private static final String FW   = GtmPageContentController.FRAMEWORK_KEY;
    private static final String TMPL = 'industry-chooser';

    /** One content row (the industryLabel field) for an industry. */
    private static GTM_Page_Content__c industryLabelRow(String key, String label) {
        return new GTM_Page_Content__c(
            Offering_Key__c  = FW,
            Template_Type__c = TMPL,
            Section_Key__c   = 'industry-' + key,
            Field_Key__c     = 'industryLabel',
            Field_Type__c    = 'text',
            Text_Value__c    = label,
            Active__c        = true
        );
    }

    /** The industry's section, with explicit Active/Status so a test states which gate it exercises. */
    private static GTM_Page_Section__c industrySection(String key, Boolean active, String status) {
        String sectionKey = 'industry-' + key;
        return new GTM_Page_Section__c(
            Offering_Key__c    = FW,
            Template_Type__c   = TMPL,
            Section_Key__c     = sectionKey,
            Section_Address__c = FW + '::' + TMPL + '::' + sectionKey,
            Label__c           = key,
            Layout_Type__c     = 'industry-tile',
            Sort_Order__c      = 10,
            Active__c          = active,
            Status__c          = status
        );
    }

    /** A live (Published, Active) industry section: what GUS must report. */
    private static GTM_Page_Section__c liveIndustry(String key) {
        return industrySection(key, true, 'Published');
    }

    private static GtmAgentGetConfigState.Output run(String configId) {
        GtmAgentGetConfigState.Input inp = new GtmAgentGetConfigState.Input();
        inp.configId = configId;
        return GtmAgentGetConfigState.execute(new List<GtmAgentGetConfigState.Input>{ inp })[0];
    }

    @IsTest
    static void execute_blankConfigId_returnsDefaultsAndFrameworkIndustries() {
        insert new List<GTM_Page_Section__c>{ liveIndustry('fintech'), liveIndustry('medtech') };
        insert new List<GTM_Page_Content__c>{
            industryLabelRow('fintech', 'Financial Services'),
            industryLabelRow('medtech', 'MedTech')
        };

        Test.startTest();
        GtmAgentGetConfigState.Output out = run('');
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
        insert liveIndustry('fintech');
        insert industryLabelRow('fintech', 'Financial Services');

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

        Test.startTest();
        GtmAgentGetConfigState.Output out = run(cfg.Id);
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
        Test.startTest();
        GtmAgentGetConfigState.Output out = run('');
        Test.stopTest();

        Assert.areEqual(0, out.availableIndustries.size(),
            'With no framework industry-chooser content seeded, the list is empty rather than erroring.');
    }

    // ─── Section status gate (issue #19) ─────────────────────────────────────
    // A created-but-unpublished industry already has content rows; GUS must
    // report only industries whose section is Published and Active, exactly
    // as GtmPageContentReader.getIndustryProfiles does for the public chooser.

    @IsTest
    static void execute_draftIndustrySection_isExcluded() {
        insert new List<GTM_Page_Section__c>{
            liveIndustry('fintech'),
            industrySection('retail', true, 'Draft')
        };
        insert new List<GTM_Page_Content__c>{
            industryLabelRow('fintech', 'Financial Services'),
            industryLabelRow('retail',  'Retail')
        };

        Test.startTest();
        GtmAgentGetConfigState.Output out = run('');
        Test.stopTest();

        Assert.isFalse(out.availableIndustries.contains('retail'),
            'An industry whose section is still Draft must not be offered to a rep by GUS.');
        Assert.isTrue(out.availableIndustries.contains('fintech'),
            'A Published, Active industry must still be reported (no over-filtering).');
        Assert.areEqual(1, out.availableIndustries.size());
    }

    @IsTest
    static void execute_publishedIndustrySection_isIncluded() {
        insert liveIndustry('fintech');
        insert industryLabelRow('fintech', 'Financial Services');

        Test.startTest();
        GtmAgentGetConfigState.Output out = run('');
        Test.stopTest();

        Assert.areEqual(new List<String>{ 'fintech' }, out.availableIndustries,
            'A Published, Active industry with content is reported by its key.');
    }

    @IsTest
    static void execute_hiddenIndustrySection_isExcluded() {
        insert new List<GTM_Page_Section__c>{
            liveIndustry('fintech'),
            industrySection('retail', false, 'Published')
        };
        insert new List<GTM_Page_Content__c>{
            industryLabelRow('fintech', 'Financial Services'),
            industryLabelRow('retail',  'Retail')
        };

        Test.startTest();
        GtmAgentGetConfigState.Output out = run('');
        Test.stopTest();

        Assert.areEqual(new List<String>{ 'fintech' }, out.availableIndustries,
            'A Published section that is hidden (Active__c = false) is not live and must be excluded.');
    }

    @IsTest
    static void execute_contentRowsWithNoSection_areExcluded() {
        // The pre-fix leak shape: content rows exist but no section at all.
        insert liveIndustry('fintech');
        insert new List<GTM_Page_Content__c>{
            industryLabelRow('fintech', 'Financial Services'),
            industryLabelRow('orphan',  'No section row')
        };

        Test.startTest();
        GtmAgentGetConfigState.Output out = run('');
        Test.stopTest();

        Assert.areEqual(new List<String>{ 'fintech' }, out.availableIndustries,
            'Content rows without a live section are not an industry; only the section decides.');
    }

    @IsTest
    static void execute_onlyDraftIndustries_returnsEmptyList() {
        insert industrySection('retail', true, 'Draft');
        insert industryLabelRow('retail', 'Retail');

        Test.startTest();
        GtmAgentGetConfigState.Output out = run('');
        Test.stopTest();

        Assert.areEqual(0, out.availableIndustries.size(),
            'With no live section at all, the list is empty rather than falling back to content rows.');
    }

    @IsTest
    static void execute_availableIndustries_matchGetIndustryProfiles() {
        // The acceptance rule: GUS reports exactly the industries the public
        // reader reports as live for the same taxonomy.
        insert new List<GTM_Page_Section__c>{
            liveIndustry('fintech'),
            liveIndustry('medtech'),
            industrySection('retail', true,  'Draft'),
            industrySection('energy', false, 'Published')
        };
        insert new List<GTM_Page_Content__c>{
            industryLabelRow('fintech', 'Financial Services'),
            industryLabelRow('medtech', 'MedTech'),
            industryLabelRow('retail',  'Retail'),
            industryLabelRow('energy',  'Energy'),
            industryLabelRow('orphan',  'No section row')
        };

        Test.startTest();
        GtmAgentGetConfigState.Output out = run('');
        List<GtmPageContentReader.IndustryProfile> profiles =
            GtmPageContentReader.getIndustryProfiles(FW, TMPL);
        Test.stopTest();

        List<String> readerKeys = new List<String>();
        for (GtmPageContentReader.IndustryProfile p : profiles) readerKeys.add(p.industryKey);
        readerKeys.sort();

        Assert.areEqual(new List<String>{ 'fintech', 'medtech' }, readerKeys,
            'Fixture sanity: the public reader sees exactly the two live industries.');
        Assert.areEqual(readerKeys, out.availableIndustries,
            'GUS must report the same live industry set as GtmPageContentReader.getIndustryProfiles.');
    }
}
