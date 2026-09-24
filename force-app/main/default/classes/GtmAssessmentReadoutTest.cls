/**
 * UNVERIFIED — no Salesforce CLI and no org in this environment, so nothing
 * here was compiled or run. Written to the same contract as the rest of the
 * suite; run before merge.
 *
 * The properties under test are the ones that make a gate a gate: it qualifies
 * the tier without touching the number, it stays silent on data nobody
 * supplied, and a supplement index can never leak into the readiness total.
 */
@IsTest
private class GtmAssessmentReadoutTest {

    private static GTM_Assessment_Question__mdt question(String key, Integer sortOrder) {
        return new GTM_Assessment_Question__mdt(
            Instrument__c       = 'Readiness',
            Dimension_Key__c    = key,
            Dimension_Name__c   = key + ' name',
            Question_Text__c    = key + '?',
            Option_1_Label__c   = 'one',
            Option_2_Label__c   = 'two',
            Option_3_Label__c   = 'three',
            Option_4_Label__c   = 'four',
            Max_Answer_Value__c = 4,
            Sort_Order__c       = sortOrder,
            Active__c           = true
        );
    }

    private static void seed(String targetKey, List<GTM_Assessment_Gate__mdt> gates,
                             List<GTM_Assessment_Supplement__mdt> supplements) {
        List<GTM_Assessment_Question__mdt> rows = new List<GTM_Assessment_Question__mdt>();
        Integer i = 10;
        for (String key : GtmAssessmentScoring.DIMENSIONS) {
            rows.add(question(key, i));
            i += 10;
        }
        GtmAssessmentQuestions.rowOverride = rows;
        GtmAssessmentQuestions.resetCache();

        GtmMigrationPairs.platformOverride = new List<GTM_Migration_Platform__mdt>{
            new GTM_Migration_Platform__mdt(Platform_Key__c = 'hubspot',
                Display_Label__c = 'HubSpot', Family_Key__c = 'inbound_suite', Active__c = true),
            new GTM_Migration_Platform__mdt(Platform_Key__c = 'sfmc_next',
                Display_Label__c = 'MCN', Family_Key__c = 'core_native', Active__c = true)
        };
        GtmMigrationPairs.resetCache();

        GtmAssessmentInstrument.pairOverride = new List<GTM_Assessment_Pair__mdt>{
            new GTM_Assessment_Pair__mdt(
                DeveloperName = 'base', Source_Key__c = '*', Target_Key__c = '*',
                Specificity__c = 4, Capability_Posture__c = 'interview_only',
                Source_Posture__c = 'interview_only', Target_Posture__c = 'interview_only',
                Posture_Statement__c = 'base statement', Version__c = '1.0', Active__c = true),
            new GTM_Assessment_Pair__mdt(
                DeveloperName = 'hubspot__mcn', Source_Key__c = 'hubspot',
                Target_Key__c = targetKey, Specificity__c = 1,
                Capability_Posture__c = 'interview_only', Source_Posture__c = 'interview_only',
                Target_Posture__c = 'interview_only',
                Posture_Statement__c = 'nothing is instrumented on either end',
                Supplement_Set__c = 'mcn_readiness', Version__c = '2026.09.1', Active__c = true)
        };
        GtmAssessmentInstrument.overrideOverride = new List<GTM_Assessment_Dimension_Override__mdt>();
        GtmAssessmentInstrument.supplementOverride = supplements;
        GtmAssessmentInstrument.gateOverride = gates;
        GtmAssessmentInstrument.resetCache();
    }

    private static GTM_Assessment_Gate__mdt foundationGate() {
        return new GTM_Assessment_Gate__mdt(
            Key__c = 'foundation_gated',
            Predicate_JSON__c =
                '{"all":[{"field":"target","op":"in","value":["sfmc_next"]},' +
                '{"field":"data_cloud_state","op":"eq","value":1}]}',
            Tier_Qualifier__c = 'foundation-gated',
            Readout_Block__c  = 'MCN runs on Data Cloud.',
            Severity__c       = 'blocker',
            Active__c         = true
        );
    }

    private static GTM_Assessment_Gate__mdt consentGate() {
        return new GTM_Assessment_Gate__mdt(
            Key__c = 'consent_parity_risk',
            Predicate_JSON__c =
                '{"all":[{"field":"target","op":"in","value":["sfmc_next"]},' +
                '{"field":"consent_portability","op":"lte","value":2}]}',
            Tier_Qualifier__c = 'consent workstream off critical path',
            Readout_Block__c  = 'Spring 26 parity is unverified.',
            Severity__c       = 'major',
            Active__c         = true
        );
    }

    private static List<GTM_Assessment_Supplement__mdt> mcnSupplements() {
        return new List<GTM_Assessment_Supplement__mdt>{
            new GTM_Assessment_Supplement__mdt(
                Set_Key__c = 'mcn_readiness', Key__c = 'data_cloud_state', Sort_Order__c = 10,
                Question__c = 'Where is Data Cloud?', Scored__c = true,
                Index_Key__c = 'mcn_readiness_index', Horizon_Driver__c = true,
                Options_JSON__c = '[{"value":1,"label":"not started","horizon":"8-16 weeks"},' +
                                  '{"value":2,"label":"in build","horizon":"8-12 weeks"},' +
                                  '{"value":3,"label":"live","horizon":"4-8 weeks"}]',
                Active__c = true),
            new GTM_Assessment_Supplement__mdt(
                Set_Key__c = 'mcn_readiness', Key__c = 'core_footprint', Sort_Order__c = 20,
                Question__c = 'What Core presence?', Scored__c = true,
                Index_Key__c = 'mcn_readiness_index',
                Options_JSON__c = '[{"value":1,"label":"none"},{"value":2,"label":"other team"},' +
                                  '{"value":3,"label":"marketing works there"}]',
                Active__c = true),
            new GTM_Assessment_Supplement__mdt(
                Set_Key__c = 'mcn_readiness', Key__c = 'shared_audience_definitions',
                Sort_Order__c = 50, Scored__c = false,
                Question__c = 'How many enrol from the same audience definition?',
                Active__c = true)
        };
    }

    private static Map<String, Integer> fullAnswers(Integer value) {
        Map<String, Integer> out = new Map<String, Integer>();
        for (String key : GtmAssessmentScoring.DIMENSIONS) {
            out.put(key, value);
        }
        return out;
    }

    // ------------------------------------------------------------- the gate

    @IsTest
    static void aFastTrackScoreCanCarryAGateQualifierWithoutLosingTheTier() {
        seed('sfmc_next', new List<GTM_Assessment_Gate__mdt>{ foundationGate() }, mcnSupplements());
        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('migration-accelerator', 'hubspot', 'sfmc_next');

        // 8 x 4 = 32 -- the top of the range.
        GtmAssessmentScoring.Score score = GtmAssessmentScoring.score('migration-accelerator', fullAnswers(4), pack);
        System.assertEquals(GtmAssessmentScoring.TIER_FAST_TRACK, score.tier);

        GtmAssessmentReadout.Readout out = GtmAssessmentReadout.compose(
            score, pack, new Map<String, Integer>{ 'data_cloud_state' => 1 }
        );

        System.assertEquals(32, out.total, 'A gate never touches the number');
        System.assertEquals(GtmAssessmentScoring.TIER_FAST_TRACK, out.tier,
            'A gate never moves the band either');
        System.assertEquals(1, out.gates.size(), 'The foundation gate fires');
        System.assertEquals('foundation-gated', out.qualifier);
        System.assertEquals('Fast-Track, foundation-gated', out.tierPhrase,
            'Both halves at once -- a readout that prints only one of them is wrong ' +
            'whichever one it picks');
    }

    @IsTest
    static void aGateStaysSilentWhenNobodyAnsweredTheQuestionItKeysOn() {
        seed('sfmc_next', new List<GTM_Assessment_Gate__mdt>{ foundationGate() }, mcnSupplements());
        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('migration-accelerator', 'hubspot', 'sfmc_next');
        GtmAssessmentScoring.Score score = GtmAssessmentScoring.score('migration-accelerator', fullAnswers(4), pack);

        GtmAssessmentReadout.Readout out =
            GtmAssessmentReadout.compose(score, pack, new Map<String, Integer>());

        System.assertEquals(0, out.gates.size(),
            'A gate firing on data nobody supplied reads as the tool guessing');
        System.assertEquals(null, out.qualifier);
        System.assertEquals(GtmAssessmentScoring.TIER_FAST_TRACK, out.tierPhrase);
    }

    @IsTest
    static void aGateDoesNotFireForADifferentTarget() {
        seed('other_target', new List<GTM_Assessment_Gate__mdt>{ foundationGate() },
             new List<GTM_Assessment_Supplement__mdt>());
        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('migration-accelerator', 'hubspot', 'other_target');
        GtmAssessmentReadout.Readout out = GtmAssessmentReadout.compose(
            GtmAssessmentScoring.score('migration-accelerator', fullAnswers(3), pack), pack,
            new Map<String, Integer>{ 'data_cloud_state' => 1 }
        );
        System.assertEquals(0, out.gates.size(),
            'The target clause is what keeps a target-specific gate off every other pair');
    }

    @IsTest
    static void twoGatesFiringProduceTwoQualifiers() {
        seed('sfmc_next',
             new List<GTM_Assessment_Gate__mdt>{ foundationGate(), consentGate() },
             mcnSupplements());
        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('migration-accelerator', 'hubspot', 'sfmc_next');
        Map<String, Integer> answers = fullAnswers(3);
        answers.put('consent_portability', 2);

        GtmAssessmentReadout.Readout out = GtmAssessmentReadout.compose(
            GtmAssessmentScoring.score('migration-accelerator', answers, pack), pack,
            new Map<String, Integer>{ 'data_cloud_state' => 1 }
        );
        System.assertEquals(2, out.gates.size());
        System.assert(out.qualifier.contains('foundation-gated'));
        System.assert(out.qualifier.contains('consent workstream off critical path'));
    }

    @IsTest
    static void anUnparseablePredicateLeavesItsGateInert() {
        GTM_Assessment_Gate__mdt broken = foundationGate();
        broken.Predicate_JSON__c = '{ this is not json';
        seed('sfmc_next', new List<GTM_Assessment_Gate__mdt>{ broken }, mcnSupplements());
        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('migration-accelerator', 'hubspot', 'sfmc_next');

        GtmAssessmentReadout.Readout out = GtmAssessmentReadout.compose(
            GtmAssessmentScoring.score('migration-accelerator', fullAnswers(4), pack), pack,
            new Map<String, Integer>{ 'data_cloud_state' => 1 }
        );
        System.assertEquals(0, out.gates.size(),
            'A malformed predicate must not fire on everything, nor take the readout down');
    }

    // ----------------------------------------------------------- supplements

    @IsTest
    static void supplementScoresIntoItsOwnIndexAndNeverTheReadinessTotal() {
        seed('sfmc_next', new List<GTM_Assessment_Gate__mdt>(), mcnSupplements());
        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('migration-accelerator', 'hubspot', 'sfmc_next');
        GtmAssessmentScoring.Score score = GtmAssessmentScoring.score('migration-accelerator', fullAnswers(2), pack);
        System.assertEquals(16, score.total, '8 x 2');

        GtmAssessmentReadout.Readout out = GtmAssessmentReadout.compose(
            score, pack,
            new Map<String, Integer>{ 'data_cloud_state' => 3, 'core_footprint' => 2 },
            new Map<String, String>{ 'shared_audience_definitions' => 'six of forty' }
        );

        System.assertEquals(16, out.total,
            'Supplements sit OUTSIDE the 32 -- structurally, not by intention');
        System.assertEquals(1, out.supplementIndexes.size());
        GtmAssessmentReadout.IndexResult idx = out.supplementIndexes[0];
        System.assertEquals('mcn_readiness_index', idx.indexKey);
        System.assertEquals(5, idx.total, '3 + 2');
        System.assertEquals(6, idx.maximum, 'Two scored questions at 3 each');
        System.assertEquals('4-8 weeks', out.horizon,
            'The horizon comes from the answered option of the horizon-driver question, ' +
            'so no Apex has to know that question by name');
        System.assertEquals('six of forty', out.notes.get('shared_audience_definitions'),
            'An unscored probe is recorded as said and computed on never');
    }

    @IsTest
    static void anOutOfRangeSupplementAnswerIsDroppedNotClamped() {
        seed('sfmc_next', new List<GTM_Assessment_Gate__mdt>(), mcnSupplements());
        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('migration-accelerator', 'hubspot', 'sfmc_next');

        GtmAssessmentReadout.SupplementResult supp = GtmAssessmentReadout.scoreSupplements(
            pack,
            new Map<String, Integer>{ 'data_cloud_state' => 9, 'core_footprint' => 2 },
            null
        );
        System.assertEquals(false, supp.answers.containsKey('data_cloud_state'),
            'Dropped, not clamped -- clamping a 9 down to 3 invents an answer nobody gave');
        System.assertEquals(2, supp.indexes.get('mcn_readiness_index').total);
    }

    @IsTest
    static void postureAndVerificationFlagsSurviveIntoTheReadout() {
        seed('sfmc_next', new List<GTM_Assessment_Gate__mdt>(), mcnSupplements());
        for (GTM_Assessment_Pair__mdt row : GtmAssessmentInstrument.pairOverride) {
            if (row.DeveloperName == 'hubspot__mcn') {
                row.Callouts_JSON__c = JSON.serialize(new List<Object>{
                    new Map<String, Object>{ 'pattern' => 'engagement_split_partial',
                                             'severity' => 'major',
                                             'verification_required' => true }
                });
            }
        }
        GtmAssessmentInstrument.resetCache();
        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('migration-accelerator', 'hubspot', 'sfmc_next');

        GtmAssessmentReadout.Readout out = GtmAssessmentReadout.compose(
            GtmAssessmentScoring.score('migration-accelerator', fullAnswers(3), pack), pack, null
        );
        System.assertEquals('nothing is instrumented on either end', out.postureStatement);
        System.assertEquals(true, out.estateFiguresIllustrative);
        System.assertEquals(true, out.anyVerificationRequired,
            'The hedge is carried by the flag, not by whoever writes the deck that week');
        System.assertEquals('2026.09.1', out.version);
        System.assertEquals('hubspot__mcn', out.pairKey);
    }

    @IsTest
    static void composeWithANullPackFallsBackToBaseRatherThanThrowing() {
        seed('sfmc_next', new List<GTM_Assessment_Gate__mdt>(), mcnSupplements());
        GtmAssessmentReadout.Readout out = GtmAssessmentReadout.compose(
            GtmAssessmentScoring.score('migration-accelerator', fullAnswers(4)), null, null
        );
        System.assertEquals(8, out.perDimension.size());
        System.assertEquals(GtmAssessmentScoring.TIER_FAST_TRACK, out.tier);
    }
}
