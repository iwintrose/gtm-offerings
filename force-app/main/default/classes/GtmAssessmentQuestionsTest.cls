@isTest
private class GtmAssessmentQuestionsTest {

    private static GTM_Assessment_Question__mdt row(
        String instrument, String key, String name, Integer maxValue, Decimal sortOrder
    ) {
        return new GTM_Assessment_Question__mdt(
            Instrument__c      = instrument,
            Dimension_Key__c   = key,
            Dimension_Name__c  = name,
            Measures__c        = 'what ' + key + ' measures',
            Question_Text__c   = 'A question about ' + key + '?',
            Option_1_Label__c  = 'worst',
            Option_2_Label__c  = 'poor',
            Option_3_Label__c  = 'good',
            Option_4_Label__c  = maxValue == 4 ? 'best' : null,
            Max_Answer_Value__c = maxValue,
            Sort_Order__c      = sortOrder,
            Active__c          = true
        );
    }

    /** One row per real dimension of both instruments, in order. */
    private static void seedFullSet() {
        GtmAssessmentQuestions.resetCache();
        List<GTM_Assessment_Question__mdt> rows = new List<GTM_Assessment_Question__mdt>();
        Integer order = 0;
        for (String key : GtmAssessmentScoring.DIMENSIONS) {
            order += 10;
            rows.add(row('Readiness', key, 'Readiness ' + key, 4, order));
        }
        order = 0;
        for (String key : GtmEstateComplexity.DIMENSIONS) {
            order += 10;
            rows.add(row('Complexity', key, 'Complexity ' + key, 3, order));
        }
        GtmAssessmentQuestions.rowOverride = rows;
    }

    @isTest
    static void theQuestionnaireCarriesBothInstrumentsAndTheirMaxima() {
        seedFullSet();
        GtmAssessmentQuestions.Questionnaire q = GtmAssessmentQuestions.getQuestionnaire();

        Assert.areEqual(8, q.readiness.size());
        Assert.areEqual(6, q.complexity.size());
        Assert.areEqual(32, q.readinessMaxScore);
        Assert.areEqual(18, q.complexityMaxScore);
    }

    @isTest
    static void wordingComesFromMetadataAndTheOrderIsWhatWasConfigured() {
        seedFullSet();
        List<GtmAssessmentQuestions.Question> readiness =
            GtmAssessmentQuestions.questionsFor('Readiness');

        // The first configured question is the first dimension -- the whole
        // point being that a consultant reorders questions in Setup.
        Assert.areEqual(GtmAssessmentScoring.DIMENSIONS[0], readiness[0].dimensionKey);
        Assert.areEqual('Readiness ' + GtmAssessmentScoring.DIMENSIONS[0], readiness[0].dimensionName);
        Assert.isTrue(readiness[0].questionText.contains(GtmAssessmentScoring.DIMENSIONS[0]));
        Assert.isNotNull(readiness[0].measures);
    }

    @isTest
    static void readinessOffersFourAscendingOptionsAndComplexityThree() {
        seedFullSet();
        GtmAssessmentQuestions.Question readiness =
            GtmAssessmentQuestions.questionsFor('Readiness')[0];
        Assert.areEqual(4, readiness.options.size());
        Assert.areEqual(1, readiness.options[0].value);
        Assert.areEqual('worst', readiness.options[0].label);
        Assert.areEqual(4, readiness.options[3].value);
        Assert.areEqual('best', readiness.options[3].label, 'Option 4 is the LOWEST migration risk');

        GtmAssessmentQuestions.Question complexity =
            GtmAssessmentQuestions.questionsFor('Complexity')[0];
        Assert.areEqual(3, complexity.options.size(),
            'A complexity question is a 1-3 scale and must not offer a fourth option');
    }

    @isTest
    static void everyConfiguredKeyIsOneTheScorerActuallyCounts() {
        seedFullSet();
        for (GtmAssessmentQuestions.Question q : GtmAssessmentQuestions.questionsFor('Readiness')) {
            Assert.isTrue(q.scored, q.dimensionKey + ' should be scoreable');
        }
        Assert.areEqual(0, GtmAssessmentQuestions.unscoredKeys('Readiness').size());
        Assert.areEqual(0, GtmAssessmentQuestions.missingKeys('Readiness').size());
        Assert.areEqual(0, GtmAssessmentQuestions.unscoredKeys('Complexity').size());
        Assert.areEqual(0, GtmAssessmentQuestions.missingKeys('Complexity').size());
    }

    @isTest
    static void driftBetweenMetadataAndTheAllowlistIsVisibleNotSilent() {
        // A key that only exists in metadata still renders -- and is marked
        // unscoreable, rather than quietly contributing nothing to a total
        // somebody is reading as complete.
        GtmAssessmentQuestions.resetCache();
        GtmAssessmentQuestions.rowOverride = new List<GTM_Assessment_Question__mdt>{
            row('Readiness', 'estate_scale', 'Estate Scale', 4, 10),
            row('Readiness', 'invented_dimension', 'Something New', 4, 20)
        };

        List<GtmAssessmentQuestions.Question> questions =
            GtmAssessmentQuestions.questionsFor('Readiness');
        Assert.areEqual(2, questions.size(), 'The unknown question is still shown');
        Assert.isTrue(questions[0].scored);
        Assert.isFalse(questions[1].scored);

        Assert.areEqual(new Set<String>{ 'invented_dimension' },
            GtmAssessmentQuestions.unscoredKeys('Readiness'));
        Assert.areEqual(7, GtmAssessmentQuestions.missingKeys('Readiness').size(),
            'The seven dimensions with no wording configured are named too');
    }

    @isTest
    static void anInactiveQuestionDropsOutOfTheFormButKeepsItsName() {
        // A retired question still has to render when an old readout, whose
        // stored breakdown mentions it, is reopened.
        GtmAssessmentQuestions.resetCache();
        GTM_Assessment_Question__mdt retired = row('Readiness', 'estate_scale', 'Estate Scale', 4, 10);
        retired.Active__c = false;
        GtmAssessmentQuestions.rowOverride = new List<GTM_Assessment_Question__mdt>{ retired };

        Assert.areEqual(0, GtmAssessmentQuestions.questionsFor('Readiness').size());
        Assert.areEqual('Estate Scale', GtmAssessmentQuestions.dimensionNames().get('estate_scale'));
    }

    @isTest
    static void dimensionNamesCoverBothInstruments() {
        seedFullSet();
        Map<String, String> names = GtmAssessmentQuestions.dimensionNames();
        Assert.areEqual(14, names.size(), 'Eight readiness dimensions plus six complexity ones');
        Assert.areEqual('Readiness source_access', names.get('source_access'));
        Assert.areEqual('Complexity scripting_depth', names.get('scripting_depth'));
    }

    @isTest
    static void noMetadataAtAllYieldsAnEmptyQuestionnaireRatherThanAnError() {
        GtmAssessmentQuestions.resetCache();
        GtmAssessmentQuestions.rowOverride = new List<GTM_Assessment_Question__mdt>();

        GtmAssessmentQuestions.Questionnaire q = GtmAssessmentQuestions.getQuestionnaire();
        Assert.areEqual(0, q.readiness.size());
        Assert.areEqual(0, q.complexity.size());
        // ...but every scoreable key is reported missing, which is the signal.
        Assert.areEqual(8, GtmAssessmentQuestions.missingKeys('Readiness').size());
    }

    // -------------------------------------------------- the deployed metadata

    @isTest
    static void theMetadataShippedInThisRepoMatchesTheApexAllowlist() {
        // Runs against whatever GTM_Assessment_Question__mdt the org actually
        // has. Skipped when none is deployed, so this never fails on a scratch
        // org that has not had the records pushed yet -- but on an org that
        // does have them, a key typo is caught here rather than as a
        // questionnaire that quietly scores 24 out of a claimed 32.
        GtmAssessmentQuestions.resetCache();
        GtmAssessmentQuestions.rowOverride = null;
        if (GtmAssessmentQuestions.dimensionNames().isEmpty()) {
            return;
        }
        Assert.areEqual(new Set<String>(), GtmAssessmentQuestions.unscoredKeys('Readiness'),
            'A configured readiness key that the scorer ignores');
        Assert.areEqual(new Set<String>(), GtmAssessmentQuestions.missingKeys('Readiness'),
            'A scoreable readiness dimension with no question configured');
        Assert.areEqual(new Set<String>(), GtmAssessmentQuestions.unscoredKeys('Complexity'));
        Assert.areEqual(new Set<String>(), GtmAssessmentQuestions.missingKeys('Complexity'));
    }
}
